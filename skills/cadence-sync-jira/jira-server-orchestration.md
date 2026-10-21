# `/cadence-sync-jira` — orchestration mechanics

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, ADR_CADENCE-0025).
External invariant relied upon: every Jira REST v2 operation is executed by a co-located single-operation shell script whose contract is specified in `.agents/skills/cadence-sync-jira/jira-server-scripts.md`. This document defines the **orchestrator's own** mechanics — the helper functions referenced by `SKILL.md`, the `jira-metadata-write.sh` invocation sites, and the per-projection description temp file — keeping `SKILL.md` comfortably beneath the `<400`-line Developer Experience ceiling (BTG-075 blocking 11; matching the modular split applied by BTG-070/071/073).

Consult this document **only** when modifying how the orchestrator sequences steps, handles halts, emits reports, or invokes `jira-metadata-write.sh`. When modifying an individual Jira operation, consult `jira-server-scripts.md` and that operation's script instead.

---

## 1. One step of the ticket sequence — `run_step`

Executes one operation script, appends its stdout `key=value` lines into `$SYNC_PAYLOAD`, streams stderr audit conditions directly to the operator, and returns non-zero whenever the ticket sequence must halt. When a step exits non-zero and emits verbose REST/diagnostic output exceeding 30 lines, the orchestrator also routes the error log through `offload_log_triage` (`local-fast-cpu` on `:11434`) to extract verbatim `syncjs.*` error lines while preserving full raw output in `/tmp/agy-last-triage.log`. The halt decision inspects the **exit code alone**; the step class (`blocking` vs. `best-effort`) governs only whether the script itself may report a tracker refusal as a clean exit `0` (see the class table in `SKILL.md`).

```bash
#   $1 = blocking|best-effort   $2 = step name (for the report)   $3.. = argv
run_step() {
  step_class="$1"; step_name="$2"; shift 2
  step_out=$("$@")            # stdout carries key=value DATA; stderr streams to the operator
  step_rc=$?
  # Capture stdout lines even when the step subsequently exits non-zero: any
  # side effects applied prior to failure must appear in the partial report.
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

Every halt is loud and leaves already-applied tracker state intact and visible (DEC-008). The orchestrator **never** rolls back completed steps, **never** issues compensating requests, and **never** auto-retries or auto-resumes — changes already written to Jira stay in place. Instead, on any halt the orchestrator emits a structured partial-completion report naming: which steps finished and the `key=value` effects they produced, which step halted with its `syncjs.*` condition and exit code, and which remaining steps were not executed. Because operator re-run is the recovery path, a halt that fails to emit this report is flagged as `syncjs.orchestrator.partial_report_absent`.

```bash
# $SYNC_STEPS lists the full step sequence for the ticket; run_step updates
# $SYNC_COMPLETED_STEPS / $SYNC_FAILED_STEP / $SYNC_FAILED_RC / $SYNC_PAYLOAD.
# Invoked on the halt branch prior to returning to the bulk loop.
emit_partial_report() {
  echo "syncjs.orchestrator.partial_completion: ${SYNC_TICKET:-this ticket} halted -- no rollback, no compensation, no auto-resume" >&2
  echo "  completed: ${SYNC_COMPLETED_STEPS:-(none)}" >&2
  # emit the accumulated key=value effects that already landed in Jira
  printf '%s\n' "${SYNC_PAYLOAD:-}" | sed '/^$/d;s/^/    effect: /' >&2
  echo "  failed:    ${SYNC_FAILED_STEP:-(unknown)} (exit ${SYNC_FAILED_RC:-?}; its syncjs.* condition is above)" >&2
  # compute all remaining steps in the sequence after the failed step
  remaining=""
  for s in ${SYNC_STEPS:-}; do
    case " ${SYNC_COMPLETED_STEPS:-} ${SYNC_FAILED_STEP:-} " in
      *" $s "*) ;;
      *) remaining="${remaining:+$remaining }$s" ;;
    esac
  done
  echo "  remaining: ${remaining:-(none)} -- un-run; re-run /cadence-sync-jira for this ticket once the cause is fixed" >&2
  SYNC_REPORT_EMITTED=yes
}

# Post-halt invariant check: halting without emitting a partial-completion report
# is a contract violation because the operator cannot inspect what landed in Jira (DEC-009).
assert_partial_report_emitted() {
  [ -n "${SYNC_FAILED_STEP:-}" ] || return 0
  [ -n "${SYNC_REPORT_EMITTED:-}" ] && return 0
  echo "syncjs.orchestrator.partial_report_absent: ${SYNC_TICKET:-this ticket} halted at '${SYNC_FAILED_STEP}' with no partial-completion report -- the operator cannot see what was applied" >&2
  return 1
}
```

---

## 3. The dedicated metadata writer — `jira-metadata-write.sh`

The orchestrator is the **exclusive caller**, and the dedicated `jira-metadata-write.sh` script is the **sole writer** of `metadata.yaml`. All other operation scripts strictly read `metadata.yaml` and never modify it. `jira-metadata-write.sh` (`.agents/skills/cadence-sync-jira/jira-server-scripts.md`) is a standalone executable script verified by the single-writer structural seam test (BTG-125 DEC-014, Option C).

**Invoked up to THREE times per ticket**, with each invocation performing an atomic verify-then-`mv -f` replacement of `metadata.yaml` (so readers never observe a half-written file, DEC-009):

1. **Early write immediately after Step 4 returns, on `mode = create` ONLY** — persisting `jira_url` alone. Recording `jira_url` in `metadata.yaml` before Step 5 runs (BTG-125) guarantees that if any step from Step 5 onward halts, a subsequent re-run resolves `mode=update` rather than minting a duplicate Jira issue. On `mode=update` no early write is needed, and on the umbrella branch `jira_url` is intentionally re-pointed only upon full completion (`.agents/skills/cadence-sync-jira/jira-server-conditions-umbrella.md`).
2. **Early write immediately after Step 9 returns, whenever `umbrella_epic_url` is non-empty** — persisting `umbrella_epic_url` **alone**, without re-pointing `jira_url` yet (BTG-125 AC-5; see Step 9 in `sync_one_ticket` below).
3. **Final write at end-of-operation** — persisting all accumulated keys (`jira_url`, `worklog_watermark_at`, `umbrella_epic_url`) once the entire sequence finishes (Section 5 below).

> **Residual mid-Step-4 window (BTG-124, DEC-007).** Because BTG-124 removed the `<id>: ` prefix from Jira issue summaries and retired `jira-resolve.sh`'s fuzzy `summary ~ "<id>"` search (Option C), `jira_url` in `metadata.yaml` is the **sole** mapping from a repository ticket to its Jira issue. While BTG-125's early write persists `jira_url` as soon as Step 4 returns, one narrow window remains: if a halt occurs **inside** Step 4 itself *after* the create `POST` succeeds but *before* `jira-write-issue.sh` exits, `jira_url` has not yet been written to `metadata.yaml`, and `jira-resolve.sh`'s create-branch notice flags that boundary.

`jira-metadata-write.sh` adheres to the three-channel contract (BTG-075 DEC-001):

```
# args   : --ticket <id> --set <key>=<value> [--set <key>=<value> ...]
# stdout : nothing
# stderr : syncjs.metadata.* reported conditions
# exit   : 0 written (or a declared no-delta) / 1 fail-loud / 2 usage / 4 config HALT
```

Two properties are foundational: the target file is addressed through `$meta`, and `--set` requires explicit `key=value` arguments so only intended keys are touched. **If `jira-metadata-write.sh` is missing or non-executable, the orchestrator halts immediately** rather than risking an unrecorded issue creation.

Inside `jira-metadata-write.sh`, `set_yaml_scalar` implements **set-or-append semantics** (substituting an existing active or commented key line in place while preserving any inline comment, or appending the key at column 0 when absent). Re-applying an identical value converges byte-identically (DEC-009), so end-of-operation writes cleanly re-assert values written by the early call sites.

---

## 4. The per-projection description temp file — `render_description_tempfile` (step 4, AC-4)

Using `mktemp` enforces **structural freshness** on every projection. A static path or ticket-ID-derived filename would collide across retries (DEC-008/DEC-009) or risk leaking a previous ticket's prose into the current issue during a bulk sync.

```bash
# Invoked ONCE PER PROJECTION -- $1 = ticket id -- printing the path of a brand-new
# temporary file on stdout.
render_description_tempfile() {
  id="$1"
  f=$(mktemp "${TMPDIR:-/tmp}/cadence-jira-desc-XXXXXXXX") || return 1
  render_ticket_template "$id" > "$f" || { rm -f "$f"; return 1; }
  printf '%s\n' "$f"
}
```

`jira-write-issue.sh` unlinks `--description-file` on **every** exit path, so the orchestrator never deletes or reuses a path once handed over. `JIRA_PAT` is **never** written into the temp file.

**`render_ticket_template` combines agent section extraction with mandatory deterministic markup conversion.** You extract each `{{token}}`'s source content from `problem.md` and `metadata.yaml` per `ticket_TEMPLATE.md`'s *Token sources* table, and **MUST pipe every extracted Markdown fragment through `jira-md2wiki.sh`** prior to substitution (passing `--functional-validation` for the `{{functional_validation}}` fragment). **Never pass the outer `ticket_TEMPLATE.md` body itself through `jira-md2wiki.sh`**, as the template is already authored in Jira wiki markup. Full details on pass ordering and the seven markup conversions live in `.agents/skills/cadence-sync-jira/jira-server-scripts-render.md`.

Note that the `render_description_tempfile` bash function signature above is kept exact because test harnesses extract and `eval` this fenced block with `render_ticket_template` stubbed to verify temp-file lifecycle invariants.

---

## 5. The bulk loop — `bulk_sync_tickets`

Every ticket in a bulk run executes **independently**: with its own sequence, its own accumulated `$SYNC_PAYLOAD`, and its own fresh description temp file. When a ticket halts, the loop emits its partial-completion report, records the halted ticket, and **continues to the next ticket**.

```bash
bulk_sync_tickets() {
  halted=""
  reference_issues=""          # BTG-107 DEC-005: non-halted tickets whose link
                                # reference account is non-zero, named by id -- NEVER summed.
  agent_leg_issues=""          # BTG-315: non-halted, split-mode tickets whose
                                # agent_legs_rejected is non-zero, named by id --
                                # using the same per-ticket reporting shape.
  for id in "$@"; do
    # reset per-ticket orchestrator state so nothing leaks across tickets
    SYNC_TICKET="$id"; SYNC_PAYLOAD=""; SYNC_COMPLETED_STEPS=""
    SYNC_FAILED_STEP=""; SYNC_FAILED_RC=""; SYNC_REPORT_EMITTED=""
    if sync_one_ticket "$id"; then
      # End-of-operation write-back: re-asserts every key accumulated during the
      # ticket's run so early writes and this final write converge byte-identically
      # (DEC-009). If write-back fails, treat the ticket as HALTED.
      if ! "$SCRIPTS/jira-metadata-write.sh" --ticket "$id" \
           --set "jira_url=$(payload_value jira_url)" \
           --set "worklog_watermark_at=$(payload_value worklog_watermark_advance)" \
           --set "umbrella_epic_url=$(payload_value umbrella_epic_url)"; then
        SYNC_FAILED_STEP="metadata-write-back"; SYNC_FAILED_RC=1
        emit_partial_report
        assert_partial_report_emitted || :
        halted="${halted:+$halted }$id:metadata-write-back"
      else
        # Record non-zero reference accounts for non-halted tickets (S-2.4).
        # Never default empty ("") to "0" (cadence-sync-jira's S-2.5 rule).
        u=$(payload_value references_unreadable); r=$(payload_value references_unresolved)
        s=$(payload_value references_skipped)
        if [ "$u" != "0" ] || [ "$r" != "0" ] || [ "$s" != "0" ]; then
          reference_issues="${reference_issues:+$reference_issues }$id:${u:-<absent>}/${r:-<absent>}/${s:-<absent>}"
        fi
        # BTG-315: agent_legs_rejected is omitted (never "0") when the ticket's
        # prefix has no configured agent-time user.
        a=$(payload_value agent_legs_rejected)
        if [ -n "$a" ] && [ "$a" != "0" ]; then
          agent_leg_issues="${agent_leg_issues:+$agent_leg_issues }$id:$a"
        fi
      fi
    else
      emit_partial_report                             # never silent on halt
      assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:${SYNC_FAILED_STEP:-unknown}"
    fi
  done
  # explicitly list every halted ticket and its failing step -- never a bare count
  if [ -n "$halted" ]; then
    echo "syncjs.orchestrator.bulk_halts: $halted" >&2
    for h in $halted; do echo "  halted: ${h%%:*} at step ${h#*:}" >&2; done
  fi
  # explicitly list every ticket with a non-zero link reference account by id (DEC-005 / OQ-3)
  if [ -n "$reference_issues" ]; then
    echo "syncjs.orchestrator.bulk_reference_issues: $reference_issues" >&2
    for ri in $reference_issues; do
      echo "  reference account: ${ri%%:*} unreadable/unresolved/skipped=${ri#*:}" >&2
    done
  fi
  # BTG-315: explicitly list per-ticket agent-leg rejections at end of batch
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

**The authoritative step sequence and CLI argument vector live in the bash function below.** Keeping `sync_one_ticket` as an executable fenced function ensures test harnesses validate the exact flags passed at every step (preventing prose-table drift such as passing `--ticket` to `jira-preserve.sh` or omitting `--self` on `jira-assign.sh`).

```bash
# Extract one key's value from the accumulated payload -- LAST write wins.
payload_value() { printf '%s\n' "${SYNC_PAYLOAD:-}" | sed -n "s/^$1=//p" | tail -1; }

# $1 = ticket id. Returns non-zero immediately if any step halts the ticket.
sync_one_ticket() {
  id="$1"
  SYNC_STEPS="connect resolve preserve write-issue transition worklog assign link epic"

  run_step blocking connect "$SCRIPTS/jira-connect.sh" || return 1
  self=$(payload_value self)

  run_step blocking resolve "$SCRIPTS/jira-resolve.sh" --ticket "$id" || return 1
  mode=$(payload_value mode)
  key=$(payload_value issue_key)

  # Step 3 preserves the as-filed original on the UPDATE path only (on create, no
  # issue exists yet) and skips `type: epic` (because an Epic's description is left
  # empty per BTG-040 and never carries the Repo-managed sentinel).
  # `--issue-key` is jira-preserve.sh's ONLY flag and must be quoted.
  if [ "$mode" = update ] && [ "$(ticket_type "$id")" != epic ]; then
    run_step blocking preserve "$SCRIPTS/jira-preserve.sh" --issue-key "$key" || return 1
  else
    SYNC_COMPLETED_STEPS="${SYNC_COMPLETED_STEPS:+$SYNC_COMPLETED_STEPS }preserve(skipped)"
  fi

  # Step 4 renders a fresh description temp file per projection -- except for
  # `type: epic`, whose Description remains empty (BTG-040).
  set -- --ticket "$id" --mode "$mode"
  [ -n "$key" ] && set -- "$@" --issue-key "$key"
  if [ "$(ticket_type "$id")" != epic ]; then
    tmp=$(render_description_tempfile "$id") || return 1
    set -- "$@" --description-file "$tmp"
  fi
  run_step blocking write-issue "$SCRIPTS/jira-write-issue.sh" "$@" || return 1
  # on the create path, issue_key is emitted by Step 4
  key=$(payload_value issue_key)

  # AC-1 (BTG-125): Persist jira_url immediately after creation on `mode = create`
  # BEFORE Step 5 runs so a subsequent halt cannot cause a re-run to mint a duplicate.
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

  # Pass `--self "$self"` resolved by jira-connect.sh, always quoted.
  run_step best-effort assign "$SCRIPTS/jira-assign.sh" --ticket "$id" --issue-key "$key" --self "$self" || return 1
  run_step best-effort link   "$SCRIPTS/jira-link.sh"   --ticket "$id" --issue-key "$key" || return 1
  run_step best-effort epic   "$SCRIPTS/jira-epic.sh"   --ticket "$id" --issue-key "$key" || return 1

  # AC-5 (BTG-125): Persist `umbrella_epic_url` immediately when emitted by Step 9
  # so a partial umbrella replacement is recorded and never mints a second replacement
  # on re-run (jira_url itself is re-pointed only on full completion).
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

`$SCRIPTS` points to `.agents/skills/cadence-sync-jira/` and `ticket_type` extracts `.type` from the ticket's `metadata.yaml` (`specs/$id/` or `archive/$id/`).
