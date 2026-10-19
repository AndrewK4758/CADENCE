#!/usr/bin/env bash
#
# jira-worklog-prepare.sh -- everything jira-worklog.sh does BEFORE the
# per-candidate posting loop (BTG-247 row: jira-worklog.sh split): argument
# parsing, the config-toggle opt-out, the Epic skip, capability/duration-unit
# resolution, and candidate selection. MOVED VERBATIM from the parent
# (pre-split lines :77-:132 and :128-:146), each wrapped in its own function so
# the parent's own early-exit paths (disabled toggle, Epic skip, malformed
# entry) behave identically -- `exit` inside a sourced function still
# terminates the whole process, and a `for` loop's `break`/`continue` stay
# correctly scoped because the loop itself moved whole, never split from its
# own boundary.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075), same
# as jira-worklog.sh. SOURCED by jira-worklog.sh via a
# ${BASH_SOURCE[0]}-relative path, called at the two points in its own
# execution where the inline code used to run.
#
# References: archive/BTG-247/spec.md ; archive/BTG-247/decisions.md (this
# split's own DEC entry).

# js_worklog_parse_and_prepare "$@" -- sets TICKET, ISSUE_KEY, BASE_URL,
# CAPABILITY, WORKDAY_HOURS, WORKWEEK_DAYS in the caller (no `local`, by
# design: the caller is the top-level script, not another function). May
# `exit` directly on a disabled toggle, an Epic ticket, a usage error, or a
# config HALT -- identical to the pre-split inline behavior.
js_worklog_parse_and_prepare() {
  TICKET=""
  ISSUE_KEY=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ticket)    js_argv_pair syncjs.worklog.usage "$@"; TICKET="$2"; shift 2 ;;
      --issue-key) js_argv_pair syncjs.worklog.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
      *) js_halt "$JS_EXIT_USAGE" syncjs.worklog.usage "unknown argument: $1" ;;
    esac
  done
  [[ -n "$TICKET"    ]] || js_halt "$JS_EXIT_USAGE" syncjs.worklog.usage "--ticket <id> is required"
  [[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.worklog.usage "--issue-key <KEY> is required"
  
  js_config_require
  
  # --- the opt-OUT gate (absent => ENABLED, BTG-064) --------------------------
  # Wraps ONLY the worklog calls: a disabled projection makes no worklog read and
  # no worklog post, and returns -- it never suppresses another step.
  js_config_toggle worklog_creation_enabled
  TOGGLE_RC=$?
  if [[ "$TOGGLE_RC" -eq "$JS_EXIT_CONFIG" ]]; then exit "$JS_EXIT_CONFIG"; fi
  if [[ "$TOGGLE_RC" -ne 0 ]]; then
    js_report syncjs.worklog.disabled "worklog creation disabled by policy"
    js_emit worklogs_posted 0
    js_emit worklog_result disabled
    exit "$JS_EXIT_OK"
  fi
  
  js_metadata_load "$TICKET"
  
  # An Epic tracks no realized effort of its own (BTG-040): skipped before any call.
  if [[ "$(js_metadata_get '.type')" == "epic" ]]; then
    js_report syncjs.worklog.skipped_epic \
      "$TICKET is an Epic -- an Epic tracks no realized effort of its own (its children do), so no worklog is read or posted"
    js_emit worklogs_posted 0
    js_emit worklog_result skipped-epic
    exit "$JS_EXIT_OK"
  fi
  
  BASE_URL="$(js_env_value base_url)"
  [[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.worklog.env_absent "the base-URL environment variable is unset"
  
  # The post-add verification capability. FAIL-LOUD: an absent or unrecognized
  # `worklog_postcheck_capability` HALTs rather than resolving to `none`, which
  # would make an unconfigured adapter a sanctioned non-enforcing one.
  # syncjs.worklog.capability_marker_absent names the worklog-level HALT; the
  # library reports the config-level one, so both vocabularies stay intact.
  CAPABILITY="$(js_config_capability)" || {
    js_report syncjs.worklog.capability_marker_absent \
      "the worklog-postcheck-capability declaration is absent, malformed, or outside the allowlist -- halting this ticket's worklog step"
    exit "$JS_EXIT_CONFIG"
  }
  
  # A workday's length is instance-varying Jira config: comparing a "1d" worklog
  # against a Remaining decrement needs "1d" as THIS instance means it.
  WORKDAY_HOURS="$(js_config_map duration_units workday_hours)" || exit "$JS_EXIT_CONFIG"
  WORKWEEK_DAYS="$(js_config_map duration_units workweek_days)" || exit "$JS_EXIT_CONFIG"

  # BTG-315: resolved ONCE, here, before the candidate loop. AGENT_USER empty
  # is UNSPLIT mode -- every line below this point in the whole worklog step
  # must then be byte-identical to before this ticket (AC-4); a non-empty
  # value turns on the two-leg split governed by CADENCE_ORG.md §19.
  AGENT_USER="$(js_agent_user "$TICKET")"
  WLS_PATH="${CADENCE_WORKLOG_SPLIT:-ci-templates/scripts/worklog-split.sh}"
}

# js_worklog_select_candidates -- walk the append-only stage_effort log,
# building the CANDIDATES array and setting MALFORMED (no `local`: read by the
# caller after this function returns). Uses $ENTRY_COUNT / $JS_METADATA_JSON /
# $WATERMARK, already resolved by the caller before this is invoked.
js_worklog_select_candidates() {
  # Walk the append-only stage_effort log in document order (which is chronological,
  # oldest first). A MALFORMED entry HALTS the batch at that entry and is never
  # skipped over: the watermark is a HIGH-WATER mark, so advancing it for a later
  # well-formed entry would move it PAST the malformed one, permanently marking an
  # entry that was never projected as projected. Halting DEFERS a projection;
  # skipping would DESTROY one.
  CANDIDATES=()
  MALFORMED=""
  for i in $(seq 0 $((ENTRY_COUNT - 1))); do
    [[ "$ENTRY_COUNT" -eq 0 ]] && break
    entry="$(jq -c ".stage_effort[$i]" <<<"$JS_METADATA_JSON")"
    e_stage="$(jq -r '.stage // ""'  <<<"$entry")"
    e_effort="$(jq -r '.effort // ""' <<<"$entry")"
    e_at="$(jq -r '.at // ""'         <<<"$entry")"
    if [[ -z "$e_stage" || -z "$e_effort" || -z "$e_at" ]]; then
      MALFORMED="entry $i (stage='$e_stage' effort='$e_effort' at='$e_at')"
      break
    fi
    [[ -n "$WATERMARK" && ! "$e_at" > "$WATERMARK" ]] && continue
    CANDIDATES+=("$e_stage|$e_effort|$e_at")
  done
}
