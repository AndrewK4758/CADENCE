# `/claire-sync-youtrack` -- orchestration mechanics: the ticket sequence

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-youtrack/youtrack-orchestration.md` -- every YouTrack operation is performed by a
co-located single-operation script (`yt-*.sh`), each of which READS `metadata.yaml` and never writes it.

**This file is a further part of one mechanics document, not another document.** BTG-247 split it off
because `youtrack-orchestration.md` stood at 395 lines against a re-derived headroom threshold, so the
remaining mechanics (the bulk loop, the per-ticket sequence) had nowhere to land in place. The record is
**split, never truncated** -- the same facet-conflict resolution the jira-server-conditions.md family
already applies.

**These fences are the implementation, not an illustration**, exactly as the primary file's own header
says. `ci-templates/scripts/tests/btg-176-lib/common.sh`'s `btg176_extract_block` globs every `.md` file
in this directory, so a fenced function defined here is found identically to one defined in the primary
-- no test-code change is needed to pick up this split.

---

## 5. The bulk loop -- `bulk_sync_tickets`

Each ticket is INDEPENDENT: its own sequence, its own accumulated payload, and its **own fresh
description temp file** -- `render_description_tempfile` is called INSIDE this loop, never hoisted above
it. A halted ticket is recorded and the loop MOVES ON: suppressing ticket 3's due projection because
ticket 2 hit a rejected credential would punish work that is correct and ready.

```bash
bulk_sync_tickets() {
  halted=""
  agent_leg_issues=""          # BTG-315: non-halted, split-mode tickets whose
                                # agent_legs_rejected is non-zero, named by id,
                                # never summed -- the sibling adapter's
                                # reference_issues shape (jira-server-
                                # orchestration.md), applied here since this
                                # loop resets YT_SYNC_PAYLOAD per ticket too.
  for id in "$@"; do
    # per-ticket state, reset so no ticket inherits another's payload or verdict
    YT_SYNC_TICKET="$id"; YT_SYNC_PAYLOAD=""; YT_SYNC_COMPLETED_STEPS=""
    YT_SYNC_REJECTED_STEPS=""; YT_SYNC_FAILED_STEP=""; YT_SYNC_FAILED_RC=""
    YT_SYNC_REPORT_EMITTED=""
    # FRESH per ticket, and a render that fails is this ticket's halt -- never a
    # reason to project the previous ticket's file onto this issue.
    if ! desc=$(render_description_tempfile "$id"); then
      YT_SYNC_FAILED_STEP="render"; YT_SYNC_FAILED_RC=1
      yt_emit_partial_report
      yt_assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:render"
      continue
    fi
    if yt_sync_one_ticket "$id" "$desc"; then
      # The rc is NOT discarded. A refused write-back means the YouTrack effects
      # landed but the repo never recorded them: the next run re-seeds work items
      # from a watermark that never advanced, and re-resolves an issue whose url
      # was never written. A ticket in that state is HALTED, not synced, and the
      # summary must name it -- otherwise the run reports a clean sync over a
      # write that refused.
      if ! yt_apply_metadata_writes "$id" "$YT_SYNC_PAYLOAD"; then   # end-of-operation, once
        YT_SYNC_FAILED_STEP="metadata-write-back"; YT_SYNC_FAILED_RC=1
        yt_emit_partial_report
        yt_assert_partial_report_emitted || :
        halted="${halted:+$halted }$id:metadata-write-back"
      else
        yt_emit_completion_report
        # BTG-315: agent_legs_rejected is ABSENT (never "0") for a ticket
        # whose prefix carries no agent-time user -- an unconfigured
        # ticket is never listed here.
        a=$(yt_payload_value agent_legs_rejected)
        if [ -n "$a" ] && [ "$a" != "0" ]; then
          agent_leg_issues="${agent_leg_issues:+$agent_leg_issues }$id:$a"
        fi
      fi
    else
      yt_emit_partial_report                          # never silent
      yt_assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:${YT_SYNC_FAILED_STEP:-unknown}"
    fi
  done
  # the summary LISTS each halted ticket and its failing step -- never a bare count
  if [ -n "$halted" ]; then
    echo "syncyt.orchestrator.bulk_halts: $halted" >&2
    for h in $halted; do echo "  halted: ${h%%:*} at step ${h#*:}" >&2; done
  fi
  # BTG-315: surfaced at end of sync, named per ticket -- never a bare count.
  if [ -n "$agent_leg_issues" ]; then
    echo "syncyt.orchestrator.bulk_agent_leg_rejections: $agent_leg_issues" >&2
    for ai in $agent_leg_issues; do
      echo "  agent legs rejected: ${ai%%:*} count=${ai#*:}" >&2
    done
  fi
}
```

---

## 6. The ticket sequence -- `yt_sync_one_ticket`

**The step argv lives HERE, in code, and nowhere else.** `$YT_SCRIPTS` is the directory the operation
scripts were installed into (the compiled skill's own directory); `$2` is the description file rendered
for **this** projection by the skill body's description step, which is consumed and unlinked by
`yt-write-issue.sh`.

The class of each step is its first argument, stated once, at the only place that runs it.

```bash
# $1 = ticket id, $2 = the rendered description file for THIS projection.
# Returns non-zero as soon as a step halts the ticket.
yt_sync_one_ticket() {
  id="$1"; desc="$2"
  YT_SYNC_STEPS="connect resolve preserve write-issue state worklog assignee links epic"

  yt_run_step blocking connect "$YT_SCRIPTS/yt-connect.sh" || return 1
  self=$(yt_payload_value self)

  yt_run_step blocking resolve "$YT_SCRIPTS/yt-resolve.sh" --ticket "$id" || return 1
  mode=$(yt_payload_value mode)

  # Create and update take DIFFERENT arguments -- `--project` on the create path
  # (there is no issue yet) and `--issue` on the update path -- so the branch is
  # here rather than inside the script.
  if [ "$mode" = update ]; then
    # PRESERVE FIRST, and only here. The write below overwrites the summary and
    # the description, so the as-filed original has to be captured before it --
    # afterwards there is nothing left to capture. It takes `--issue` and nothing
    # else, and the CREATE path skips it entirely because no issue exists yet.
    yt_run_step blocking preserve "$YT_SCRIPTS/yt-preserve.sh" \
      --issue "$(yt_payload_value issue)" || return 1
    yt_run_step blocking write-issue "$YT_SCRIPTS/yt-write-issue.sh" \
      --ticket "$id" --description-file "$desc" --issue "$(yt_payload_value issue)" || return 1
  else
    yt_run_step blocking write-issue "$YT_SCRIPTS/yt-write-issue.sh" \
      --ticket "$id" --description-file "$desc" --project "$(yt_payload_value project_id)" || return 1
  fi
  # From here on the issue is addressed by the INTERNAL id the write returned:
  # the link body's `id` key rejects a readable id with an HTTP 400 that quotes
  # back only its alphabetic prefix.
  issue=$(yt_payload_value issue_id)

  yt_run_step blocking   state    "$YT_SCRIPTS/yt-transition.sh" --ticket "$id" --issue "$issue" || return 1
  yt_run_step best-effort worklog "$YT_SCRIPTS/yt-worklog.sh"    --ticket "$id" --issue "$issue" || return 1
  yt_run_step best-effort assignee "$YT_SCRIPTS/yt-assign.sh"    --ticket "$id" --issue "$issue" --self "$self" || return 1
  yt_run_step best-effort links   "$YT_SCRIPTS/yt-link.sh"       --ticket "$id" --issue "$issue" || return 1
  # LAST, and best-effort: the parent relationship needs the issue the write step
  # created, and a parent that has not been projected yet is a skip rather than a
  # failure -- the next sync of the parent records its url and the run after that
  # creates the link.
  yt_run_step best-effort epic    "$YT_SCRIPTS/yt-epic.sh"       --ticket "$id" --issue "$issue" || return 1
  return 0
}
```

> **Every step's argv is now RECONCILED against a shipped script; nothing above is provisional.** The two
> that were are `yt-worklog.sh`, which takes exactly `--ticket <id> --issue <internal-id>`, and
> `yt-assign.sh`, which takes exactly `--ticket <id> --issue <internal-id> [--self <login>]` -- both the
> lines written above. `--self` is the identity `yt-connect.sh` emitted, read out of the accumulated
> payload rather than re-resolved.
>
> Both take the INTERNAL issue id the write step returned, not the readable one, for the same reason the
> link step does. A missing script would fail LOUD (exit 127 at a step, halting with a partial report)
> rather than being skipped -- which is the correct behaviour for a half-installed adapter in any case.
