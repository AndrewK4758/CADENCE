# `/cadence-sync-youtrack` -- orchestration mechanics: the ticket sequence

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
External invariant relied upon: identical to `.agents/skills/cadence-sync-youtrack/youtrack-orchestration.md` -- every YouTrack REST operation is executed by a co-located single-operation shell script (`yt-*.sh`), each of which **reads** `metadata.yaml` and never writes to it.

**This file is the second half of the orchestration mechanics specification, split rather than truncated.** BTG-247 separated `bulk_sync_tickets` and `yt_sync_one_ticket` into this companion file so both documents remain comfortably beneath the `<400`-line Developer Experience ceiling, following the same modular split pattern used across `jira-server-conditions-*.md`.

**The bash code fences below are the live implementation, not pseudocode.** `ci-templates/scripts/tests/btg-176-lib/common.sh`'s `btg176_extract_block` scans all `.md` files inside this directory, so fenced functions defined here are extracted and tested identically to functions in `youtrack-orchestration.md`.

---

## 5. The bulk loop -- `bulk_sync_tickets`

Every ticket in a bulk run executes **independently**: with its own 9-step sequence, its own accumulated `$YT_SYNC_PAYLOAD`, and its **own freshly allocated description temp file** (`render_description_tempfile` is invoked *inside* the per-ticket loop, never outside it). When a ticket halts, the loop emits its partial-completion report, records the halted ticket, and **continues to the next ticket** -- ensuring one ticket's error never blocks ready sibling tickets from projecting.

```bash
bulk_sync_tickets() {
  halted=""
  agent_leg_issues=""          # BTG-315: non-halted, split-mode tickets whose
                                # agent_legs_rejected count is non-zero, recorded as
                                # id:count pairs rather than a bare aggregate sum.
  for id in "$@"; do
    # reset per-ticket orchestrator state so nothing leaks across tickets
    YT_SYNC_TICKET="$id"; YT_SYNC_PAYLOAD=""; YT_SYNC_COMPLETED_STEPS=""
    YT_SYNC_REJECTED_STEPS=""; YT_SYNC_FAILED_STEP=""; YT_SYNC_FAILED_RC=""
    YT_SYNC_REPORT_EMITTED=""
    # allocate a FRESH description temp file per ticket; a render failure halts
    # this ticket immediately rather than reusing a prior ticket's temp file.
    if ! desc=$(render_description_tempfile "$id"); then
      YT_SYNC_FAILED_STEP="render"; YT_SYNC_FAILED_RC=1
      yt_emit_partial_report
      yt_assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:render"
      continue
    fi
    if yt_sync_one_ticket "$id" "$desc"; then
      # Verify metadata.yaml write-back succeeded. If the write-back fails, the
      # YouTrack changes landed but metadata.yaml did not record youtrack_url or
      # advance worklog_watermark_at -- which must be reported as a halt rather
      # than a clean sync.
      if ! yt_apply_metadata_writes "$id" "$YT_SYNC_PAYLOAD"; then   # end-of-operation, once
        YT_SYNC_FAILED_STEP="metadata-write-back"; YT_SYNC_FAILED_RC=1
        yt_emit_partial_report
        yt_assert_partial_report_emitted || :
        halted="${halted:+$halted }$id:metadata-write-back"
      else
        yt_emit_completion_report
        # BTG-315: agent_legs_rejected is omitted (never "0") when the ticket's
        # prefix has no configured agent-time user.
        a=$(yt_payload_value agent_legs_rejected)
        if [ -n "$a" ] && [ "$a" != "0" ]; then
          agent_leg_issues="${agent_leg_issues:+$agent_leg_issues }$id:$a"
        fi
      fi
    else
      yt_emit_partial_report                          # never silent on halt
      yt_assert_partial_report_emitted || :
      halted="${halted:+$halted }$id:${YT_SYNC_FAILED_STEP:-unknown}"
    fi
  done
  # explicitly list every halted ticket and its failing step -- never a bare count
  if [ -n "$halted" ]; then
    echo "syncyt.orchestrator.bulk_halts: $halted" >&2
    for h in $halted; do echo "  halted: ${h%%:*} at step ${h#*:}" >&2; done
  fi
  # BTG-315: report per-ticket agent-leg rejections at end of batch
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

**The authoritative step sequence and CLI argument vector live in the bash function below.** `$YT_SCRIPTS` points to the directory housing the operation scripts (the compiled `.agents/skills/cadence-sync-youtrack/` directory); `$2` is the fresh description file rendered specifically for **this** ticket projection and unlinked by `yt-write-issue.sh`.

Each step's class (`blocking` vs. `best-effort`) is declared as the first argument to `yt_run_step`.

```bash
# $1 = ticket id, $2 = path to the rendered description temp file for THIS projection.
# Returns non-zero immediately if any step halts the ticket.
yt_sync_one_ticket() {
  id="$1"; desc="$2"
  YT_SYNC_STEPS="connect resolve preserve write-issue state worklog assignee links epic"

  yt_run_step blocking connect "$YT_SCRIPTS/yt-connect.sh" || return 1
  self=$(yt_payload_value self)

  yt_run_step blocking resolve "$YT_SCRIPTS/yt-resolve.sh" --ticket "$id" || return 1
  mode=$(yt_payload_value mode)

  # Create and update pass different target flags -- `--project` when creating a
  # new issue and `--issue` when updating an existing one.
  if [ "$mode" = update ]; then
    # Preserve the as-filed original comment FIRST on the update path, before
    # yt-write-issue.sh overwrites the summary and description. Skipped on the
    # create path because no prior issue exists.
    yt_run_step blocking preserve "$YT_SCRIPTS/yt-preserve.sh" \
      --issue "$(yt_payload_value issue)" || return 1
    yt_run_step blocking write-issue "$YT_SCRIPTS/yt-write-issue.sh" \
      --ticket "$id" --description-file "$desc" --issue "$(yt_payload_value issue)" || return 1
  else
    yt_run_step blocking write-issue "$YT_SCRIPTS/yt-write-issue.sh" \
      --ticket "$id" --description-file "$desc" --project "$(yt_payload_value project_id)" || return 1
  fi
  # All subsequent steps address the issue by the INTERNAL id (`2-NNNN`) emitted
  # by yt-write-issue.sh, since YouTrack link endpoints reject readable keys in
  # request payloads with HTTP 400.
  issue=$(yt_payload_value issue_id)

  yt_run_step blocking   state    "$YT_SCRIPTS/yt-transition.sh" --ticket "$id" --issue "$issue" || return 1
  yt_run_step best-effort worklog "$YT_SCRIPTS/yt-worklog.sh"    --ticket "$id" --issue "$issue" || return 1
  yt_run_step best-effort assignee "$YT_SCRIPTS/yt-assign.sh"    --ticket "$id" --issue "$issue" --self "$self" || return 1
  yt_run_step best-effort links   "$YT_SCRIPTS/yt-link.sh"       --ticket "$id" --issue "$issue" || return 1
  # Run epic parent linking LAST as best-effort: if the parent ticket has not been
  # projected to YouTrack yet, yt-epic.sh records a clean skip and links on the
  # subsequent sync after the parent's youtrack_url is recorded.
  yt_run_step best-effort epic    "$YT_SCRIPTS/yt-epic.sh"       --ticket "$id" --issue "$issue" || return 1
  return 0
}
```

> **Every step's CLI invocation above is verified against its shipped script.** Specifically, `yt-worklog.sh` accepts `--ticket <id> --issue <internal-id>`, and `yt-assign.sh` accepts `--ticket <id> --issue <internal-id> [--self <login>]`, where `--self` is extracted from `yt-connect.sh`'s stdout payload in `$YT_SYNC_PAYLOAD`.
>
> Both scripts require the **internal** issue ID (`2-NNNN`) returned by `yt-write-issue.sh` rather than the readable `KEY-N` ID. If any script is missing from `$YT_SCRIPTS`, `yt_run_step` fails loud (exit 127) and emits a partial-completion report rather than silently skipping the step.
