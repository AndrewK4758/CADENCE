# `/claire-sync-jira` — orchestration mechanics

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, ADR_CLAIRE-0025).
Invariant relied on from outside this boundary: every Jira operation is performed by a co-located
single-operation script whose contract is `.claude/skills/claire-sync-jira/jira-server-scripts.md`. This
file carries the **orchestrator's own** mechanics — the four helper functions the skill body names and
the per-projection description temp file — so the skill body stays an orchestration skeleton within the
DX line ceiling (BTG-075 blocking 11; the same split BTG-070/071/073 applied to this file's ancestors).

Read this file **only** when changing how the orchestrator sequences, halts, reports or writes back.
Changing one Jira operation needs the contract doc and that one script instead.

---

## 1. One step of the ticket sequence — `run_step`

Accumulates each script's stdout into `$SYNC_PAYLOAD`, streams stderr through for the operator, and
returns non-zero when the ticket must halt. The halt decision reads the **exit code alone**; the step
class only decides which script is *allowed* to report a sanctioned refusal at all (see the class table
in the skill body).

```bash
#   $1 = blocking|best-effort   $2 = step name (for the report)   $3.. = argv
run_step() {
  step_class="$1"; step_name="$2"; shift 2
  step_out=$("$@")            # stdout is DATA; stderr flows straight to the operator
  step_rc=$?
  # Accumulate the payload even from a step that then failed: the effects it
  # already applied are exactly what the partial-completion report must name.
  [ -n "$step_out" ] && SYNC_PAYLOAD="${SYNC_PAYLOAD:+$SYNC_PAYLOAD
}$step_out"
  if [ "$step_rc" -ne 0 ]; then
    echo "syncjs.orchestrator.halted: step '$step_name' ($step_class) exited $step_rc" >&2
    SYNC_FAILED_STEP="$step_name"; SYNC_FAILED_RC="$step_rc"
    return "$step_rc"
  fi
  SYNC_COMPLETED_STEPS="${SYNC_COMPLETED_STEPS:+$SYNC_COMPLETED_STEPS }$step_name"
  return 0
}
```

---

## 2. The partial-completion report — `emit_partial_report` / `assert_partial_report_emitted`

A halt is loud, and it leaves partial work intact and VISIBLE (DEC-008). The orchestrator does **not**
roll back, does **not** issue a compensating call, and does **not** auto-retry or auto-resume — the
effects the completed steps already applied stay in Jira. What it owes the operator instead is a
report: which steps completed and what effect each applied, which step failed with its `syncjs.*`
condition and exit code, and which steps remain un-run. Recovery is an operator re-run, which the
operator cannot judge without exactly that picture — so a halt that emitted no report is itself a
defect (`syncjs.orchestrator.partial_report_absent`).

```bash
# $SYNC_STEPS is the full sequence for the ticket; run_step maintains
# $SYNC_COMPLETED_STEPS / $SYNC_FAILED_STEP / $SYNC_FAILED_RC / $SYNC_PAYLOAD.
# Emitted on the halt path, before returning to the bulk loop.
emit_partial_report() {
  echo "syncjs.orchestrator.partial_completion: ${SYNC_TICKET:-this ticket} halted -- no rollback, no compensation, no auto-resume" >&2
  echo "  completed: ${SYNC_COMPLETED_STEPS:-(none)}" >&2
  # the effects those steps applied -- this is what stays behind in Jira
  printf '%s\n' "${SYNC_PAYLOAD:-}" | sed '/^$/d;s/^/    effect: /' >&2
  echo "  failed:    ${SYNC_FAILED_STEP:-(unknown)} (exit ${SYNC_FAILED_RC:-?}; its syncjs.* condition is above)" >&2
  # everything in the sequence that is neither completed nor the failed step
  remaining=""
  for s in ${SYNC_STEPS:-}; do
    case " ${SYNC_COMPLETED_STEPS:-} ${SYNC_FAILED_STEP:-} " in
      *" $s "*) ;;
      *) remaining="${remaining:+$remaining }$s" ;;
    esac
  done
  echo "  remaining: ${remaining:-(none)} -- un-run; re-run /claire-sync-jira for this ticket once the cause is fixed" >&2
  SYNC_REPORT_EMITTED=yes
}

# The guard behind the report: a halt that produced no report is a defect, because
# partial state the operator cannot see is indistinguishable from work that never
# happened -- and operator re-run is the ONLY recovery path (DEC-009).
assert_partial_report_emitted() {
  [ -n "${SYNC_FAILED_STEP:-}" ] || return 0
  [ -n "${SYNC_REPORT_EMITTED:-}" ] && return 0
  echo "syncjs.orchestrator.partial_report_absent: ${SYNC_TICKET:-this ticket} halted at '${SYNC_FAILED_STEP}' with no partial-completion report -- the operator cannot see what was applied" >&2
  return 1
}
```

---

## 3. The dedicated metadata writer — `jira-metadata-write.sh`

The orchestrator is the **sole caller**, and one dedicated writer script, invoked by the orchestrator,
is the **sole writer** of `metadata.yaml`. Every operation script still never writes it (or any other
owned artifact); it only reads it. This is not a preserve-by-prose claim: `jira-metadata-write.sh`
(`.claude/skills/claire-sync-jira/jira-server-scripts.md`) is a real executable a harness can run and the
single-writer seam enumerates, extracted verbatim from this file's own fenced reference implementation
(BTG-125 DEC-014, Option C) after this author measured that the seam guarding the single-writer model
reads only `.sh` files and so could never have seen a guarantee left inside this Markdown file.

**Called up to THREE times per ticket**, each an independent atomic replace of the owned file
(verify-then-single-`mv -f`, so a reader never observes a partial image, DEC-009):

1. **Early, after step 4 returns, `mode = create` ONLY** — `jira_url` alone. The create is durable in the
   repo before step 5 runs, which is BTG-125's whole point: a halt anywhere from step 5 onward can no
   longer cause a re-run to mint a duplicate. The update path performs no early write and stays
   byte-for-byte as it was, and the umbrella branch's "`jira_url` is re-pointed only on full completion"
   asymmetry (`.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md`) is left intact.
2. **Early, after step 9 returns, guarded on a non-empty emitted value** — `umbrella_epic_url` **alone**,
   never a re-pointed `jira_url` (BTG-125 AC-5; see the step-9 site below for why).
3. **Once, at end-of-operation** — every key the run accumulated, unchanged in position (section 5 below).

> **There is no compensating guard behind these writes — do not assume one (BTG-124, DEC-007).** Until
> BTG-124, `jira-resolve.sh` carried a fuzzy `summary ~ "<id>"` search that could recover a halted run's
> issue from the Summary's ticket-id prefix. That prefix is gone and the search was **deleted, not
> replaced**: the Spec Review gate ratified the reduction (Option C) on the explicit condition that the
> residual risk be *documented rather than silent*, which is what this note is. `metadata.yaml`'s
> `jira_url` is now the **sole** ticket→issue mapping. Since BTG-125 the early write above records it as
> soon as step 4 returns, so the residual that remains is narrow: a halt **inside** step 4 itself, between
> the create POST and the script's own return (a span that includes the non-fatal screen-completion PUT),
> still loses the mapping and a re-run mints a duplicate. `jira-resolve.sh`'s create-branch warning names
> that residual by its bounds.

`jira-metadata-write.sh`'s contract, in the adapter's three-channel form (DEC-001 of BTG-075):

```
# args   : --ticket <id> --set <key>=<value> [--set <key>=<value> ...]
# stdout : nothing
# stderr : syncjs.metadata.* reported conditions
# exit   : 0 written (or a declared no-delta) / 1 fail-loud / 2 usage / 4 config HALT
```

Two properties are load-bearing: the owned file is reached through a `$meta` variable (not to evade the
single-writer seam -- BTG-125 DEC-014 measured that extracting the moved body verbatim produces zero
findings -- but because it is the moved code, unchanged), and `--set` takes explicit key/value pairs, so
a caller cannot accidentally write a key it did not intend. **A non-executable or missing writer is a
halt, never a silent no-op**: the state a lost write would leave behind (an issue that exists in Jira and
is unknown to the repo) is exactly the state this whole section exists to prevent.

`set_yaml_scalar` inside it is **set-or-append, never substitute-only**: a key this sync projects back is
very often **not present** in the file to substitute (across this repo's 149 real `metadata.yaml` files
only **10** carry a `worklog_watermark_at:` line and only **46** carry a `jira_url:` line in any shape),
so it substitutes in place when a line exists (commented or not, its trailing comment preserved) and
otherwise **appends** it as a new top-level key. Re-applying the same value converges byte-identically
(DEC-009), so an operator re-run after a halt is safe, and the end-of-operation call re-asserting a key an
early write already recorded does not clobber it.

---

## 4. The per-projection description temp file — `render_description_tempfile` (step 4, AC-4)

`mktemp` is what makes the freshness structural. A fixed name, or a path DERIVED FROM THE TICKET ID, is
the same defect wearing a disguise: it collides with itself the moment the same ticket is projected
twice (an operator re-run after a halt is the normal case, DEC-008/DEC-009), and in a bulk run a
short-written render would leave the PREVIOUS ticket's prose in place to be projected onto THIS issue —
a silent cross-ticket content leak that the write itself would report as success.

```bash
# Called ONCE PER PROJECTION -- $1 = ticket id -- and echoes the path of a FRESH
# file every time.
render_description_tempfile() {
  id="$1"
  f=$(mktemp "${TMPDIR:-/tmp}/claire-jira-desc-XXXXXXXX") || return 1
  render_ticket_template "$id" > "$f" || { rm -f "$f"; return 1; }
  printf '%s\n' "$f"
}
```

The consuming script (`jira-write-issue.sh`) unlinks the path on **every** exit path, so the
orchestrator never deletes it itself and never reuses a path it has already handed over. The PAT is
**never** written into the temp file (it belongs to the environment alone).

**`render_ticket_template` is agent-performed, and it has one mandatory mechanical sub-step.** You
select each `{{token}}`'s source fragment from `problem.md` / `metadata.yaml` per the *Token sources*
table — that is authorship, and it is yours. You then **MUST pipe every extracted Markdown fragment
through `jira-md2wiki.sh`** before substituting it, and the `{{functional_validation}}` fragment with
`--functional-validation`. **The template body itself is never passed through the filter**: it is
already wiki markup and a second pass would corrupt it. The full division of labour, the pass order and
the seven conversion cases it exists to fix are in
`.claude/skills/claire-sync-jira/jira-server-scripts-render.md`.

The snippet above is **unchanged** by that: `render_ticket_template` keeps its shell-function shape, the
deterministic step lands *inside* what it does, and nothing here invokes a script directly. That is not
cosmetic — two harnesses extract this fenced block and `eval` it with `render_ticket_template` stubbed,
so rewriting the call to invoke the filter here would make both stubs inert and silently drop the
temp-file-lifecycle guarantee they pin.

---

## 5. The bulk loop — `bulk_sync_tickets`

Each ticket is INDEPENDENT: its own sequence, its own payload, its own fresh description temp file.
A halted ticket is recorded and the loop MOVES ON — suppressing ticket 3's due projection because
ticket 2 hit a permissions error would punish work that is correct and ready.

```bash
bulk_sync_tickets() {
  halted=""
  reference_issues=""          # BTG-107 DEC-005: non-halted tickets whose link
                                # account is non-zero, named by id -- NEVER summed.
  agent_leg_issues=""          # BTG-315: non-halted, split-mode tickets whose
                                # agent_legs_rejected is non-zero, named by id --
                                # the SAME never-summed shape as reference_issues,
                                # for the SAME reason (bulk_sync_tickets resets
                                # SYNC_PAYLOAD per ticket, so no cross-ticket total
                                # exists to fold rejections into).
  for id in "$@"; do
    # per-ticket state, reset so no ticket inherits another's payload or verdict
    SYNC_TICKET="$id"; SYNC_PAYLOAD=""; SYNC_COMPLETED_STEPS=""
    SYNC_FAILED_STEP=""; SYNC_FAILED_RC=""; SYNC_REPORT_EMITTED=""
    if sync_one_ticket "$id"; then
      # The rc is NOT discarded. A refused write-back means the Jira effects
      # landed but the repo never recorded them: the next run re-seeds worklogs
      # from a watermark that never advanced, and re-resolves an issue whose URL
      # was never written. A ticket in that state is HALTED, not synced, and the
      # summary must name it -- otherwise the run reports a clean sync over a
      # write that refused.
      #
      # End-of-operation, once: re-asserts EVERY key the run accumulated, so the
      # two early writes above and this call converge byte-identically (DEC-009)
      # -- narrow, explicit --set pairs, never $SYNC_PAYLOAD itself, built from
      # the SAME accumulated payload the early writes read from.
      if ! "$SCRIPTS/jira-metadata-write.sh" --ticket "$id" \
           --set "jira_url=$(payload_value jira_url)" \
           --set "worklog_watermark_at=$(payload_value worklog_watermark_advance)" \
           --set "umbrella_epic_url=$(payload_value umbrella_epic_url)"; then
        SYNC_FAILED_STEP="metadata-write-back"; SYNC_FAILED_RC=1
        emit_partial_report
        assert_partial_report_emitted || :
        halted="${halted:+$halted }$id:metadata-write-back"
      else
        # A HALTED ticket is listed by the halt clause above, never by the
        # account (S-2.4). NO ${x:-0} defaulting below: absent ("") vs "0"
        # are different facts (claire-sync-jira.md's S-2.5 rule).
        u=$(payload_value references_unreadable); r=$(payload_value references_unresolved)
        s=$(payload_value references_skipped)
        if [ "$u" != "0" ] || [ "$r" != "0" ] || [ "$s" != "0" ]; then
          reference_issues="${reference_issues:+$reference_issues }$id:${u:-<absent>}/${r:-<absent>}/${s:-<absent>}"
        fi
        # BTG-315: agent_legs_rejected is ABSENT (never "0") for a ticket whose
        # prefix carries no agent-time user -- an unconfigured ticket is never
        # listed here, the same absent-vs-zero distinction S-2.5 already draws
        # for the reference account above.
        a=$(payload_value agent_legs_rejected)
        if [ -n "$a" ] && [ "$a" != "0" ]; then
          agent_leg_issues="${agent_leg_issues:+$agent_leg_issues }$id:$a"
        fi
      fi
    else
      emit_partial_report                             # never silent
      assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:${SYNC_FAILED_STEP:-unknown}"
    fi
  done
  # the summary LISTS each halted ticket and its failing step -- never a bare count
  if [ -n "$halted" ]; then
    echo "syncjs.orchestrator.bulk_halts: $halted" >&2
    for h in $halted; do echo "  halted: ${h%%:*} at step ${h#*:}" >&2; done
  fi
  # the summary NAMES each non-clean ticket by id -- never folded into a total
  # (DEC-005 / OQ-3: bulk_sync_tickets resets SYNC_PAYLOAD per ticket, so a
  # cross-ticket total has no home and none is built)
  if [ -n "$reference_issues" ]; then
    echo "syncjs.orchestrator.bulk_reference_issues: $reference_issues" >&2
    for ri in $reference_issues; do
      echo "  reference account: ${ri%%:*} unreadable/unresolved/skipped=${ri#*:}" >&2
    done
  fi
  # BTG-315: surfaced at end of sync, named per ticket -- never a bare count,
  # and never folded into the reference-account line above (a different
  # account, a different family of conditions).
  if [ -n "$agent_leg_issues" ]; then
    echo "syncjs.orchestrator.bulk_agent_leg_rejections: $agent_leg_issues" >&2
    for ai in $agent_leg_issues; do
      echo "  agent legs rejected: ${ai%%:*} count=${ai#*:}" >&2
    done
  fi
}
```

---

## 6. The ticket sequence — `sync_one_ticket`

**The step argv lives HERE, in code, and nowhere else.** The sequence used to exist only as a prose
table, and prose drifted from the scripts it invokes without a single test noticing: step 3 passed
`jira-preserve.sh` a `--ticket` flag it rejects (exit 2 at a **blocking** step, so no ticket was ever
projected on any path), and step 7 never passed `--self`, so every status mapping to `self` was
refused while `jira-connect.sh` resolved an identity nothing consumed. Every harness invoked the
scripts with the *contract doc's* argv, never the table's, which is why 93 green harnesses never saw
it. A reference implementation is what makes the seam executable — and therefore testable.

```bash
# One value out of the accumulated payload -- LAST wins, so a later step's
# correction supersedes an earlier step's guess.
payload_value() { printf '%s\n' "${SYNC_PAYLOAD:-}" | sed -n "s/^$1=//p" | tail -1; }

# $1 = ticket id. Returns non-zero as soon as a step halts the ticket.
sync_one_ticket() {
  id="$1"
  SYNC_STEPS="connect resolve preserve write-issue transition worklog assign link epic"

  run_step blocking connect "$SCRIPTS/jira-connect.sh" || return 1
  self=$(payload_value self)

  run_step blocking resolve "$SCRIPTS/jira-resolve.sh" --ticket "$id" || return 1
  mode=$(payload_value mode)
  key=$(payload_value issue_key)

  # Step 3 preserves the AS-FILED original of an issue that already exists, so it
  # is UPDATE-only: on the create path there is no issue and no `$key` to pass.
  # `--issue-key` is the script's ONLY argument (jira-server-scripts.md); it is
  # passed QUOTED, because an unquoted empty `$key` leaves a dangling flag.
  #
  # It is also skipped for `type: epic`. The skip that makes preservation
  # idempotent is the `Repo-managed` sentinel in the live DESCRIPTION -- and an
  # Epic's description is deliberately never written (BTG-040), so that sentinel
  # can never appear and the step would post a duplicate preservation comment on
  # EVERY sync, growing without bound. An Epic has no as-filed original to
  # preserve in the first place: the repo holds its substance.
  if [ "$mode" = update ] && [ "$(ticket_type "$id")" != epic ]; then
    run_step blocking preserve "$SCRIPTS/jira-preserve.sh" --issue-key "$key" || return 1
  else
    SYNC_COMPLETED_STEPS="${SYNC_COMPLETED_STEPS:+$SYNC_COMPLETED_STEPS }preserve(skipped)"
  fi

  # Step 4 renders a FRESH description temp file per projection -- except for
  # `type: epic`, whose Description is deliberately left empty (BTG-040).
  set -- --ticket "$id" --mode "$mode"
  [ -n "$key" ] && set -- "$@" --issue-key "$key"
  if [ "$(ticket_type "$id")" != epic ]; then
    tmp=$(render_description_tempfile "$id") || return 1
    set -- "$@" --description-file "$tmp"
  fi
  run_step blocking write-issue "$SCRIPTS/jira-write-issue.sh" "$@" || return 1
  # on the create path the key is only known now
  key=$(payload_value issue_key)

  # AC-1 (BTG-125). The create is DURABLE IN THE REPO before step 5 runs.
  # `mode = create` ONLY: the update path stays byte-for-byte as it was, and the
  # umbrella branch's deliberate "jira_url is re-pointed only on full completion"
  # asymmetry is left intact.
  if [ "$mode" = create ]; then
    early_url=$(payload_value jira_url)
    if [ -z "$early_url" ] || ! "$SCRIPTS/jira-metadata-write.sh" \
         --ticket "$id" --set "jira_url=$early_url"; then
      echo "syncjs.orchestrator.halted: step 'metadata-write-early' (blocking) could not record the created issue's jira_url -- the issue EXISTS in Jira and the repo does not know it; do NOT re-run until you have recorded it by hand" >&2
      SYNC_FAILED_STEP="metadata-write-early"; SYNC_FAILED_RC=1
      return 1
    fi
  fi

  run_step blocking transition "$SCRIPTS/jira-transition.sh" --ticket "$id" --issue-key "$key" || return 1
  run_step blocking worklog    "$SCRIPTS/jira-worklog.sh"    --ticket "$id" --issue-key "$key" || return 1

  # `--self` is the identity jira-connect.sh resolved from the credential. Without
  # it every `self` assignment action is refused; it is never guessed or hardcoded,
  # and it is passed QUOTED so an unresolved identity is an empty value rather
  # than a dangling flag.
  run_step best-effort assign "$SCRIPTS/jira-assign.sh" --ticket "$id" --issue-key "$key" --self "$self" || return 1
  run_step best-effort link   "$SCRIPTS/jira-link.sh"   --ticket "$id" --issue-key "$key" || return 1
  run_step best-effort epic   "$SCRIPTS/jira-epic.sh"   --ticket "$id" --issue-key "$key" || return 1

  # AC-5 (BTG-125). The replacement umbrella issue exists from jira-epic.sh:145
  # -- emitted even when child linking was REJECTED (:140) -- and a lost write
  # here, not a lost issue, is the only way a second replacement can ever be
  # minted. `umbrella_epic_url` ALONE: jira-epic.sh:228 re-points jira_url only
  # on closed|at-target, and that asymmetry is what keeps a partial umbrella
  # run convergent rather than stranded (jira-server-conditions-umbrella.md).
  early_epic=$(payload_value umbrella_epic_url)
  if [ -n "$early_epic" ]; then
    if ! "$SCRIPTS/jira-metadata-write.sh" \
         --ticket "$id" --set "umbrella_epic_url=$early_epic"; then
      echo "syncjs.orchestrator.halted: step 'metadata-write-umbrella' (blocking) could not record the replacement umbrella issue -- it EXISTS in Jira and the repo does not know it; a re-run would mint a SECOND replacement" >&2
      SYNC_FAILED_STEP="metadata-write-umbrella"; SYNC_FAILED_RC=1
      return 1
    fi
  fi
  return 0
}
```

`$SCRIPTS` is the co-located script directory and `ticket_type` reads `.type` from the ticket's
`metadata.yaml` (`specs/$id/` or `archive/$id/`). Both are resolved once by the caller.
