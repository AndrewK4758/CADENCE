# `/cadence-sync-youtrack` -- orchestration mechanics

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
External invariant relied upon: every YouTrack interaction is executed by a co-located single-operation shell script (`yt-*.sh`), each of which **reads** `metadata.yaml` and never writes to it. This document defines the **orchestrator's own** mechanics -- the step runner, the partial/completion report emitters, the description temp-file renderer, and the single end-of-operation write-back to `metadata.yaml` -- keeping `SKILL.md` well within the `<400`-line Developer Experience ceiling, matching the split used by `jira-server-orchestration.md`.

Consult this document **only** when modifying how the orchestrator sequences steps, handles halts, emits reports, or writes back to `metadata.yaml`. When modifying a single YouTrack REST operation, read that operation's script and `youtrack-scripts.md` instead.

**The bash code fences below are the executable reference implementation, not mere pseudocode.** Keeping the step runner, halt logic, and metadata writer as executable bash prevents drift between prose tables and script CLI flags: `ci-templates/scripts/tests/btg-176-rest-foundation.test.sh` extracts and executes these fenced functions directly.

---

## 1. One step of the ticket sequence -- `yt_run_step`

Executes one operation script, appends its stdout `key=value` lines into `$YT_SYNC_PAYLOAD`, streams stderr audit conditions directly to the operator, and returns non-zero whenever the ticket sequence must halt. When a step exits non-zero and emits verbose REST/diagnostic output exceeding 30 lines, the orchestrator also routes the error log through `offload_log_triage` (`local-fast-cpu` on `:11434`) to extract verbatim `syncyt.*` error lines while preserving full raw output in `/tmp/agy-last-triage.log`.

**The halt check inspects the script's exit code ALONE.** A step's *class* (`blocking` vs. `best-effort`) governs only whether the script itself may report a tracker refusal as a clean exit `0`: when a best-effort step encounters a tracker refusal it cannot overcome, it exits **0** with `<step>_result=rejected` on stdout so the ticket sequence can proceed; any non-zero exit code from any step halts the ticket regardless of class. Keeping exit-code semantics uniform across all scripts ensures a crash or usage error in a best-effort script is never mistaken for a benign refusal.

```bash
#   $1 = blocking|best-effort   $2 = step name (for the report)   $3.. = argv
yt_run_step() {
  step_class="$1"; step_name="$2"; shift 2
  step_out=$("$@")            # stdout carries key=value DATA; stderr streams to the operator
  step_rc=$?
  # Capture stdout lines even when the step subsequently exits non-zero: any
  # side effects applied prior to failure must appear in the partial report.
  [ -n "$step_out" ] && YT_SYNC_PAYLOAD="${YT_SYNC_PAYLOAD:+$YT_SYNC_PAYLOAD
}$step_out"
  if [ "$step_rc" -ne 0 ]; then
    echo "syncyt.orchestrator.halted: step '$step_name' ($step_class) exited $step_rc -- the sequence stops here; its syncyt.* condition is above" >&2
    YT_SYNC_FAILED_STEP="$step_name"; YT_SYNC_FAILED_RC="$step_rc"
    return "$step_rc"
  fi
  YT_SYNC_COMPLETED_STEPS="${YT_SYNC_COMPLETED_STEPS:+$YT_SYNC_COMPLETED_STEPS }$step_name"
  # A step that exited 0 while emitting `*_result=rejected` neither failed nor
  # applied its projection. Record the refusal explicitly both inline and in the
  # completion summary so a rejected assignee or link is never hidden behind exit 0.
  if printf '%s\n' "$step_out" | grep -qE '^[a-z_]+_result=rejected$'; then
    YT_SYNC_REJECTED_STEPS="${YT_SYNC_REJECTED_STEPS:+$YT_SYNC_REJECTED_STEPS }$step_name"
    echo "syncyt.orchestrator.step_rejected: step '$step_name' ($step_class) completed but REFUSED its projection ($(printf '%s\n' "$step_out" | grep -E '^[a-z_]+_result=rejected$' | tr '\n' ' ')) -- the sequence continues; its own syncyt.* condition above says why" >&2
  fi
  return 0
}
```

Extract a single key's value from `$YT_SYNC_PAYLOAD` -- **last write wins**, allowing a later step's updated value to supersede an earlier one:

```bash
yt_payload_value() { printf '%s\n' "${YT_SYNC_PAYLOAD:-}" | sed -n "s/^$1=//p" | tail -1; }
```

---

## 2. The end-of-run reports -- `yt_emit_partial_report` / `yt_emit_completion_report` / `yt_assert_partial_report_emitted`

Every halt is loud and leaves already-applied tracker state intact and visible. The orchestrator **never** rolls back completed steps, **never** issues compensating requests, and **never** auto-retries -- changes already written to YouTrack remain in place (a created issue is the ticket's permanent identity, and posted work items are immutable by policy).

Instead, on any halt the orchestrator must emit a structured partial-completion report naming: which steps finished and the `key=value` effects they produced, which step halted with its exit code, and which remaining steps were skipped. Because operator re-run is the recovery path, a halt that fails to emit this report is flagged as `syncyt.orchestrator.partial_report_absent`.

```bash
# $YT_SYNC_STEPS lists the full step sequence for the ticket; yt_run_step updates
# $YT_SYNC_COMPLETED_STEPS / $YT_SYNC_FAILED_STEP / $YT_SYNC_FAILED_RC /
# $YT_SYNC_PAYLOAD. Invoked on the halt branch prior to returning non-zero.
yt_emit_partial_report() {
  echo "syncyt.orchestrator.partial_completion: ${YT_SYNC_TICKET:-this ticket} halted -- no rollback, no compensation, no auto-resume" >&2
  echo "  completed: ${YT_SYNC_COMPLETED_STEPS:-(none)}" >&2
  # emit the accumulated key=value effects that already landed in YouTrack
  printf '%s\n' "${YT_SYNC_PAYLOAD:-}" | sed '/^$/d;s/^/    effect: /' >&2
  echo "  failed:    ${YT_SYNC_FAILED_STEP:-(unknown)} (exited ${YT_SYNC_FAILED_RC:-?}; its syncyt.* condition is above)" >&2
  # compute all remaining steps in the sequence after the failed step
  remaining=""
  for s in ${YT_SYNC_STEPS:-}; do
    case " ${YT_SYNC_COMPLETED_STEPS:-} ${YT_SYNC_FAILED_STEP:-} " in
      *" $s "*) ;;
      *) remaining="${remaining:+$remaining }$s" ;;
    esac
  done
  echo "  remaining: ${remaining:-(none)} -- un-run; re-run /cadence-sync-youtrack for this ticket once the cause is fixed" >&2
  YT_SYNC_REPORT_EMITTED=yes
}

# Completion report for a full sequence that exited 0. Explicitly prints
# `rejected: (none)` when zero best-effort refusals occurred so a clean run is
# distinguishable from a run that omitted the check.
yt_emit_completion_report() {
  echo "syncyt.orchestrator.completed: ${YT_SYNC_TICKET:-this ticket} completed -- steps: ${YT_SYNC_COMPLETED_STEPS:-(none)}" >&2
  echo "  rejected: ${YT_SYNC_REJECTED_STEPS:-(none)}" >&2
}

# Post-halt invariant check: halting without emitting a partial-completion report
# is a contract violation because the operator cannot inspect what landed in YouTrack.
yt_assert_partial_report_emitted() {
  [ -n "${YT_SYNC_FAILED_STEP:-}" ] || return 0
  [ -n "${YT_SYNC_REPORT_EMITTED:-}" ] && return 0
  echo "syncyt.orchestrator.partial_report_absent: ${YT_SYNC_TICKET:-this ticket} halted at '${YT_SYNC_FAILED_STEP}' with no partial-completion report -- the operator cannot see what was applied, and cannot judge a re-run" >&2
  return 1
}
```

---

## 3. The single end-of-operation metadata write -- `yt_apply_metadata_writes`

The orchestrator is the **exclusive writer** of `metadata.yaml`. Individual `yt-*.sh` scripts only read `metadata.yaml`. `yt_apply_metadata_writes` executes **once, at the end of the sequence**, after all steps succeed -- guaranteeing that any mid-sequence halt leaves `metadata.yaml` untouched on disk.

**Set-or-append semantics, never substitute-only.** Because `specs/TEMPLATE/metadata.yaml` ships with `youtrack_url` blank and most tickets initially lack a `worklog_watermark_at` key altogether, a writer that only substituted existing lines would silently drop updates on most tickets. `yt_set_yaml_scalar` replaces an existing key line (commented or active) in place, or appends the key at column 0 if absent.

> **Non-convergent first-create window.** Because `youtrack_url` in `metadata.yaml` is the **sole** link between a repo ticket and its YouTrack issue (`yt-resolve.sh` performs no fuzzy summary search because a non-existent readable key returns HTTP 400 `invalid_query` and an unknown field returns `[]`), if an initial sync creates the issue in Step 4 and then halts before `yt_apply_metadata_writes` runs, `youtrack_url` is not yet written to `metadata.yaml` (though it is printed in `yt_emit_partial_report`'s `effect: youtrack_url=...` output). Check the project or record that URL before re-running an interrupted first sync so a duplicate issue is not minted.

```bash
# Update or append one top-level scalar key in a YAML file using portable awk
# (avoiding GNU-only sed range extensions so Alpine/busybox CI runs identically).
yt_set_yaml_scalar() {
  f="$1"; k="$2"; v="$3"
  awk -v k="$k" -v v="$v" '
    BEGIN { done = 0 }
    !done && match($0, "^[[:space:]]*#?[[:space:]]*" k ":") {
      indent = ""
      if (match($0, /^[[:space:]]*/) && RLENGTH > 0) indent = substr($0, 1, RLENGTH)
      rest = substr($0, index($0, k ":") + length(k) + 1)
      trail = ""                       # preserve any inline trailing `# ...` comment
      if (match(rest, /[[:space:]]*#.*$/)) trail = substr(rest, RSTART)
      print indent k ": \"" v "\"" trail
      done = 1
      next
    }
    { print }
    END { if (!done) print k ": \"" v "\"" }   # column 0 terminates any open block
  ' "$f"
}

# $1 = ticket id, $2 = accumulated stdout payload across all scripts for this ticket.
# Invoked ONCE after the full sequence succeeds; never called on a halted run.
yt_apply_metadata_writes() {
  id="$1"; payload="$2"; root="${CADENCE_REPO_ROOT:-.}"
  meta="$root/specs/$id/metadata.yaml"
  [ -f "$meta" ] || meta="$root/archive/$id/metadata.yaml"
  [ -f "$meta" ] || { echo "syncyt.metadata.absent: no metadata.yaml for $id" >&2; return 1; }

  # extract the two repo-owned projection fields from the accumulated payload
  url=$(printf '%s\n' "$payload" | sed -n 's/^youtrack_url=//p' | tail -1)
  advance=$(printf '%s\n' "$payload" | sed -n 's/^worklog_watermark_advance=//p' | tail -1)
  [ -n "$url$advance" ] || { echo "syncyt.metadata.no_delta: nothing to write back for $id" >&2; return 0; }

  # Stage the updated file in a temporary copy and replace metadata.yaml with a
  # SINGLE atomic mv. Guard against a failed mktemp immediately: an empty $tmp
  # would cause awk to read from stdin and hang indefinitely.
  tmp=$(mktemp) || tmp=""
  if [ -z "$tmp" ] || ! cp "$meta" "$tmp"; then
    [ -n "$tmp" ] && rm -f "$tmp"
    echo "syncyt.metadata.write_unverified: $id metadata.yaml could not be staged for the write-back (no temp file) -- refusing the write rather than reporting a no-op as success" >&2
    return 1
  fi
  # ensure a trailing newline before appending any new scalar key
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
    # update $tmp via $scratch so metadata.yaml itself is replaced by a single mv below
    if yt_set_yaml_scalar "$tmp" "$key" "$want" > "$scratch"; then cat "$scratch" > "$tmp"; fi
    rm -f "$scratch"
  done
  # Verify both intended values landed in $tmp before moving it into place.
  for pair in "youtrack_url=$url" "worklog_watermark_at=$advance"; do
    key=${pair%%=*}; want=${pair#*=}
    [ -n "$want" ] || continue
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

Re-applying an identical payload is byte-idempotent (each key is set in place rather than duplicated), making operator re-runs after a halt completely safe.

---

## 4. The per-projection description temp file -- `render_description_tempfile`

**Description rendering is the sole data-preparation step performed by the orchestrator**, supplying the rendered Markdown file consumed by `yt-write-issue.sh`. `yt_render_ticket_template` populates `ticket_TEMPLATE.md` from the ticket's `problem.md` and `metadata.yaml` per its *Token sources* table. Because YouTrack Server natively renders Markdown and `ticket_TEMPLATE.md` is authored in Markdown, no markup translation is performed.

Using `mktemp` guarantees **structural freshness** on every single projection. A static filename or a path derived solely from the ticket ID would risk colliding on re-runs or leaking a prior ticket's rendered description into the next ticket during bulk syncs.

```bash
# Invoked ONCE PER PROJECTION -- $1 = ticket id -- printing the path of a brand-new
# temporary file on stdout.
render_description_tempfile() {
  id="$1"
  f=$(mktemp "${TMPDIR:-/tmp}/cadence-youtrack-desc-XXXXXXXX") || return 1
  yt_render_ticket_template "$id" > "$f" || { rm -f "$f"; return 1; }
  # Refuse an empty rendered file: because yt-write-issue.sh overwrites the issue
  # description, sending a zero-byte file would wipe the existing description with HTTP 200.
  [ -s "$f" ] || { rm -f "$f"; echo "syncyt.write.body_unbuildable: $id rendered an EMPTY description -- refusing to overwrite the issue body with nothing" >&2; return 1; }
  printf '%s\n' "$f"
}
```

`yt-write-issue.sh` unlinks the `--description-file` path on **every** exit path, so the orchestrator never reuses a path once handed to `yt-write-issue.sh`. Authentication tokens are **never** written into the description temp file.

---
## 5. The bulk loop and the ticket sequence (relocated)

`bulk_sync_tickets` and `yt_sync_one_ticket` reside in `.agents/skills/cadence-sync-youtrack/youtrack-orchestration-sequence.md` (split under BTG-247 to respect the `<400`-line Developer Experience ceiling).
