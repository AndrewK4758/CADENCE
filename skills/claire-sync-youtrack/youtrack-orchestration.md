# `/claire-sync-youtrack` -- orchestration mechanics

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
Invariant relied on from outside this boundary: every YouTrack operation is performed by a co-located
single-operation script (`yt-*.sh`), each of which READS `metadata.yaml` and never writes it. This file
carries the **orchestrator's own** mechanics -- the step runner, the ticket sequence, and the single
end-of-operation write of the owned file -- so the skill body stays an orchestration skeleton within the
DX line ceiling, the same split the sibling adapter's `jira-server-orchestration.md` applies.

Read this file **only** when changing how the orchestrator sequences, halts, reports or writes back.
Changing one YouTrack operation needs that one script instead.

**These fences are the implementation, not an illustration.** The sequence, the halt semantics and the
write-back exist here as executable bash because a sequence that lives only in a prose table drifts from
the scripts it invokes with nothing to notice: on the sibling adapter a step passed a flag its script
rejects -- at a **blocking** step, so no ticket was ever projected on any path -- and every harness
invoked the scripts with the *contract doc's* argv rather than the table's, so 93 green harnesses saw
nothing. `ci-templates/scripts/tests/btg-176-rest-foundation.test.sh` extracts and RUNS each fence below.

---

## 1. One step of the ticket sequence -- `yt_run_step`

Accumulates each script's stdout into `$YT_SYNC_PAYLOAD`, streams stderr straight through to the
operator, and returns non-zero when the ticket must halt.

**The halt decision reads the exit code ALONE.** The step *class* (`blocking` / `best-effort`) decides
only which refusals a script is allowed to report as a completed run: a best-effort step that cannot do
its job exits **0** carrying `<something>_result=rejected`, and the ticket continues; a non-zero exit
from any step halts the ticket whatever its class. One rule, in one place -- a class that also gated the
halt would give the same exit code two meanings depending on which script produced it.

```bash
#   $1 = blocking|best-effort   $2 = step name (for the report)   $3.. = argv
yt_run_step() {
  step_class="$1"; step_name="$2"; shift 2
  step_out=$("$@")            # stdout is DATA; stderr flows straight to the operator
  step_rc=$?
  # Accumulate the payload even from a step that then failed: the effects it
  # already applied are exactly what a partial-completion report must name.
  [ -n "$step_out" ] && YT_SYNC_PAYLOAD="${YT_SYNC_PAYLOAD:+$YT_SYNC_PAYLOAD
}$step_out"
  if [ "$step_rc" -ne 0 ]; then
    echo "syncyt.orchestrator.halted: step '$step_name' ($step_class) exited $step_rc -- the sequence stops here; its syncyt.* condition is above" >&2
    YT_SYNC_FAILED_STEP="$step_name"; YT_SYNC_FAILED_RC="$step_rc"
    return "$step_rc"
  fi
  YT_SYNC_COMPLETED_STEPS="${YT_SYNC_COMPLETED_STEPS:+$YT_SYNC_COMPLETED_STEPS }$step_name"
  # A step that COMPLETED and refused is neither a failure nor a success, and it
  # must not be readable as either. It is recorded by name at the moment it
  # happens and again in the completion report, because a rejected assignee or a
  # rejected link is the one outcome a run reports as `0` while a projection the
  # operator asked for did not land.
  if printf '%s\n' "$step_out" | grep -qE '^[a-z_]+_result=rejected$'; then
    YT_SYNC_REJECTED_STEPS="${YT_SYNC_REJECTED_STEPS:+$YT_SYNC_REJECTED_STEPS }$step_name"
    echo "syncyt.orchestrator.step_rejected: step '$step_name' ($step_class) completed but REFUSED its projection ($(printf '%s\n' "$step_out" | grep -E '^[a-z_]+_result=rejected$' | tr '\n' ' ')) -- the sequence continues; its own syncyt.* condition above says why" >&2
  fi
  return 0
}
```

One value out of the accumulated payload -- **last wins**, so a later step's correction supersedes an
earlier step's guess:

```bash
yt_payload_value() { printf '%s\n' "${YT_SYNC_PAYLOAD:-}" | sed -n "s/^$1=//p" | tail -1; }
```

---

## 2. The end-of-run reports -- `yt_emit_partial_report` / `yt_emit_completion_report` / `yt_assert_partial_report_emitted`

A halt is loud, and it leaves partial work intact and VISIBLE. The orchestrator does **not** roll back,
does **not** issue a compensating call, and does **not** auto-retry or auto-resume -- the effects the
completed steps already applied stay in YouTrack. Two of them cannot be undone by a later run in any
case: a created issue is the ticket's only identity, and a posted work item is immutable by construction.

What the orchestrator owes the operator instead is a report: which steps completed and what effect each
applied, which step failed with its exit code, and which steps remain un-run. Recovery here is an
operator re-run, and the operator cannot judge whether to re-run without exactly that picture -- so a
halt that emitted no report is itself a defect (`syncyt.orchestrator.partial_report_absent`).

```bash
# $YT_SYNC_STEPS is the full sequence for the ticket; yt_run_step maintains
# $YT_SYNC_COMPLETED_STEPS / $YT_SYNC_FAILED_STEP / $YT_SYNC_FAILED_RC /
# $YT_SYNC_PAYLOAD. Emitted on the halt path, before returning to the caller.
yt_emit_partial_report() {
  echo "syncyt.orchestrator.partial_completion: ${YT_SYNC_TICKET:-this ticket} halted -- no rollback, no compensation, no auto-resume" >&2
  echo "  completed: ${YT_SYNC_COMPLETED_STEPS:-(none)}" >&2
  # the effects those steps applied -- this is what stays behind in YouTrack
  printf '%s\n' "${YT_SYNC_PAYLOAD:-}" | sed '/^$/d;s/^/    effect: /' >&2
  echo "  failed:    ${YT_SYNC_FAILED_STEP:-(unknown)} (exited ${YT_SYNC_FAILED_RC:-?}; its syncyt.* condition is above)" >&2
  # everything in the sequence that is neither completed nor the failed step
  remaining=""
  for s in ${YT_SYNC_STEPS:-}; do
    case " ${YT_SYNC_COMPLETED_STEPS:-} ${YT_SYNC_FAILED_STEP:-} " in
      *" $s "*) ;;
      *) remaining="${remaining:+$remaining }$s" ;;
    esac
  done
  echo "  remaining: ${remaining:-(none)} -- un-run; re-run /claire-sync-youtrack for this ticket once the cause is fixed" >&2
  YT_SYNC_REPORT_EMITTED=yes
}

# The COMPLETED counterpart. A run that finished still owes the operator the one
# fact its exit code cannot carry: which steps refused. `(none)` is printed
# explicitly, because a report that names rejected steps only when there are any
# is indistinguishable, on the clean run, from a report that forgot to look.
yt_emit_completion_report() {
  echo "syncyt.orchestrator.completed: ${YT_SYNC_TICKET:-this ticket} completed -- steps: ${YT_SYNC_COMPLETED_STEPS:-(none)}" >&2
  echo "  rejected: ${YT_SYNC_REJECTED_STEPS:-(none)}" >&2
}

# The guard behind the report: a halt that produced no report is a defect,
# because partial state the operator cannot see is indistinguishable from work
# that never happened -- and an operator re-run is the ONLY recovery path.
yt_assert_partial_report_emitted() {
  [ -n "${YT_SYNC_FAILED_STEP:-}" ] || return 0
  [ -n "${YT_SYNC_REPORT_EMITTED:-}" ] && return 0
  echo "syncyt.orchestrator.partial_report_absent: ${YT_SYNC_TICKET:-this ticket} halted at '${YT_SYNC_FAILED_STEP}' with no partial-completion report -- the operator cannot see what was applied, and cannot judge a re-run" >&2
  return 1
}
```

---

## 3. The single end-of-operation metadata write -- `yt_apply_metadata_writes`

The orchestrator is the **sole writer** of `metadata.yaml`. A script never writes it; it only reads it.
The update is applied **once, at end-of-operation**, after the sequence has completed -- so a
mid-sequence halt leaves the owned file byte-unchanged and the already-applied YouTrack effects are
re-derived from repo state on the operator's re-run.

**Set-or-append, never substitute-only.** A key this sync projects back is very often not present in the
file to substitute: the shipped `specs/TEMPLATE/metadata.yaml` carries `youtrack_url` empty and most
tickets never gain a `worklog_watermark_at` line at all. A writer that could only replace an existing
line would refuse on the overwhelming majority of the repo -- no watermark would ever advance, no issue
URL would ever be recorded, and every run would report a clean sync.

> **There is no compensating guard behind this write.** `youtrack_url` is the **only** ticket-to-issue
> mapping this adapter has: `yt-resolve.sh` performs no recovery search (a non-existent readable key is
> HTTP 400 `invalid_query` on this instance, and an unknown *field* name silently returns `[]`, so a
> fuzzy search is not available as a fallback). A first sync that creates the issue and then halts
> **before** this write lands leaves no record anywhere, and a re-run mints a **duplicate issue** that
> must be cleaned up by hand. Check the project before re-running a sync that halted mid-sequence.

```bash
# Set one top-level scalar key in a YAML file: substitute the existing line
# (commented or not) in place, else APPEND it. Portable awk, one pass -- a
# `sed -i -E "0,/re/s||repl|"` would rely on two GNU extensions busybox sed does
# not implement, and busybox sed is what this repo's Alpine CI runs.
yt_set_yaml_scalar() {
  f="$1"; k="$2"; v="$3"
  awk -v k="$k" -v v="$v" '
    BEGIN { done = 0 }
    !done && match($0, "^[[:space:]]*#?[[:space:]]*" k ":") {
      indent = ""
      if (match($0, /^[[:space:]]*/) && RLENGTH > 0) indent = substr($0, 1, RLENGTH)
      rest = substr($0, index($0, k ":") + length(k) + 1)
      trail = ""                       # keep any trailing `# ...` explanation
      if (match(rest, /[[:space:]]*#.*$/)) trail = substr(rest, RSTART)
      print indent k ": \"" v "\"" trail
      done = 1
      next
    }
    { print }
    END { if (!done) print k ": \"" v "\"" }   # column 0 ends any open block
  ' "$f"
}

# $1 = ticket id, $2 = the accumulated stdout payload of EVERY script run for
# this ticket. Called ONCE, only after the sequence completed; a halt never
# reaches this point.
yt_apply_metadata_writes() {
  id="$1"; payload="$2"; root="${CLAIRE_REPO_ROOT:-.}"
  meta="$root/specs/$id/metadata.yaml"
  [ -f "$meta" ] || meta="$root/archive/$id/metadata.yaml"
  [ -f "$meta" ] || { echo "syncyt.metadata.absent: no metadata.yaml for $id" >&2; return 1; }

  # the two repo-owned fields this sync projects back, taken from the payload
  url=$(printf '%s\n' "$payload" | sed -n 's/^youtrack_url=//p' | tail -1)
  advance=$(printf '%s\n' "$payload" | sed -n 's/^worklog_watermark_advance=//p' | tail -1)
  [ -n "$url$advance" ] || { echo "syncyt.metadata.no_delta: nothing to write back for $id" >&2; return 0; }

  # Build the whole new image in a temp file, then replace the owned file with a
  # SINGLE atomic rename -- one write per operation, never one per field, so a
  # reader never observes a partial file.
  # A FAILED mktemp REFUSES here, not later: an empty $tmp turns every later
  # `awk ... "$tmp"` into an awk with NO FILE OPERAND, which reads STDIN and
  # HANGS the run -- unbounded and silent, in the sole writer of owned data.
  tmp=$(mktemp) || tmp=""
  if [ -z "$tmp" ] || ! cp "$meta" "$tmp"; then
    [ -n "$tmp" ] && rm -f "$tmp"
    echo "syncyt.metadata.write_unverified: $id metadata.yaml could not be staged for the write-back (no temp file) -- refusing the write rather than reporting a no-op as success" >&2
    return 1
  fi
  # a file that does not end in a newline would otherwise gain `key: "v"` glued
  # onto its last line
  [ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ] && printf '\n' >> "$tmp"
  for pair in "youtrack_url=$url" "worklog_watermark_at=$advance"; do
    key=${pair%%=*}; want=${pair#*=}
    [ -n "$want" ] || continue
    scratch=$(mktemp) || scratch=""
    if [ -z "$scratch" ]; then
      rm -f "$tmp"
      echo "syncyt.metadata.write_unverified: $id metadata.yaml could not be staged for the $key write (no temp file) -- refusing the write" >&2
      return 1
    fi
    # rewritten IN PLACE via a scratch file, never renamed: the OWNED file is
    # replaced by exactly ONE `mv` (below), which is what makes the update atomic
    if yt_set_yaml_scalar "$tmp" "$key" "$want" > "$scratch"; then cat "$scratch" > "$tmp"; fi
    rm -f "$scratch"
  done
  # VERIFY BEFORE REPLACING. A no-op write must never be reported as success: if
  # the watermark did not actually advance, the whole idempotency load falls
  # silently onto the next run's re-read.
  for pair in "youtrack_url=$url" "worklog_watermark_at=$advance"; do
    key=${pair%%=*}; want=${pair#*=}
    [ -n "$want" ] || continue
    # anchored on the KEY, literal on the VALUE (awk index, so a value carrying
    # `/` or `.` cannot accidentally match as a regex)
    if ! awk -v k="$key" -v v="$want" \
         '$0 ~ "^[[:space:]]*"k":" && index($0, v) > 0 { found = 1 } END { exit !found }' "$tmp"; then
      rm -f "$tmp"
      echo "syncyt.metadata.write_unverified: $id metadata.yaml still carries no $key line with the projected value after a set-or-append -- refusing the write rather than reporting a no-op as success" >&2
      return 1
    fi
  done
  chmod --reference="$meta" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$meta"
}
```

Re-applying the same payload converges byte-identically (each field is *set* to the desired value, not
appended), so an operator re-run after a halt is safe.

---

## 4. The per-projection description temp file -- `render_description_tempfile`

**This is the one thing the orchestrator renders rather than delegating**, because the description is
content the skill *supplies* to `yt-write-issue.sh`. `yt_render_ticket_template` is that rendering step:
it fills `ticket_TEMPLATE.md`'s body from the repo artifacts per its *Token sources* table. YouTrack
renders a description as Markdown and the template is already Markdown, so nothing converts markup on the
way in.

`mktemp` is what makes the freshness **structural**. A fixed name, or a path derived from the ticket id,
is the same defect wearing a disguise: it collides with itself the moment the same ticket is projected
twice -- an operator re-run after a halt is the normal case here, and this adapter has one window that is
not convergent (§3), so re-runs are expected rather than exceptional. In a bulk run a short-written render
would leave the PREVIOUS ticket's prose in place to be projected onto THIS issue, and the write itself
would report that as success.

```bash
# Called ONCE PER PROJECTION -- $1 = ticket id -- and echoes the path of a FRESH
# file every time.
render_description_tempfile() {
  id="$1"
  f=$(mktemp "${TMPDIR:-/tmp}/claire-youtrack-desc-XXXXXXXX") || return 1
  yt_render_ticket_template "$id" > "$f" || { rm -f "$f"; return 1; }
  # An EMPTY render is refused rather than sent. The projection OVERWRITES the
  # issue description, so an empty body is not a smaller update -- it is the
  # deletion of whatever was there, applied with a 200 and no complaint. This is
  # the same reasoning as the AC-12 read-back, one step earlier in the pipe.
  [ -s "$f" ] || { rm -f "$f"; echo "syncyt.write.body_unbuildable: $id rendered an EMPTY description -- refusing to overwrite the issue body with nothing" >&2; return 1; }
  printf '%s\n' "$f"
}
```

`yt-write-issue.sh` unlinks the path on **every** exit path, so the orchestrator never deletes it itself
and never re-uses a path it has already handed over. The token is **never** written into the temp file --
it belongs to the environment alone.

---
## 5. The bulk loop and the ticket sequence (relocated)

`bulk_sync_tickets` and `yt_sync_one_ticket` moved to
`.claude/skills/claire-sync-youtrack/youtrack-orchestration-sequence.md` (BTG-247) when this file reached the
DX line ceiling. Relocated, not removed.
