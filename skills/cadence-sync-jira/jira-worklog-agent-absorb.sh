#!/usr/bin/env bash
#
# jira-worklog-agent-absorb.sh -- BTG-315 cycle-2 review B3: the Remaining
# Estimate absorption check, shared by BOTH legs. Sourced by
# jira-worklog-agent.sh alone, never executed.
#
# Bounded context: Tracker projection / Jira Server-DC adapter, same as
# jira-worklog-agent.sh. Invariant relied on from outside this boundary:
# BTG-064 DEC-004 -- the absorption verdict comes from a FRESH re-read only,
# never the add response's own `*_updated` self-report (live-observed to
# report `false` on a decrement that demonstrably happened, PLAYSCRUM-3390).
#
# WHY A SEPARATE FILE: this pair was originally inline in
# jira-worklog-agent.sh (once for the operator leg, duplicated for the
# agent leg per review cycle-2 B3), and extracting it to ONE shared copy
# here is what keeps jira-worklog-agent.sh under the Facet 3 DX line
# ceiling -- the same resolver-family-split precedent this repository
# already uses (org-binding-resolve.sh / -parse.sh / -modes.sh /
# -crossref.sh) for exactly this reason. spec.md Facet 4 states ONE rule
# ("operator absorption check ... agent absorption check") applied per leg,
# not two different rules, so this is one function pair, not two.
#
# Spec: archive/BTG-315/spec.md (Proposed Design, Facet 4; behavioral decomposition AC-2 R3/R4).

# _js_worklog_absorb_baseline -- the pre-add Remaining Estimate READ. Sets
# BASELINE_OK / BASELINE_VALUE. Must be called BEFORE the leg's own POST.
BASELINE_OK=""
BASELINE_VALUE=""
_js_worklog_absorb_baseline() {
  local baseline_read=no baseline_value=""
  if [[ "$CAPABILITY" == "remaining-estimate-decrement" ]] \
     && js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=timetracking" && js_http_ok \
     && baseline_value="$(remaining_of "$JS_HTTP_BODY")"; then baseline_read=yes; fi
  BASELINE_VALUE="$(if [[ "$baseline_read" == "yes" ]]; then printf '%s' "$baseline_value"; fi)"
  BASELINE_OK="$baseline_read"
}

# _js_worklog_absorb_verify <leg-label> <stage> <at> <minutes> <remaining_before>
# <baseline_ok> -- the post-add verdict. May call the caller's `finish` on a
# postcheck failure/indeterminate outcome. POSTED is incremented by the
# CALLER immediately after its own successful POST, since this function only
# verifies absorption of an ALREADY-posted leg and must not double-count it.
_js_worklog_absorb_verify() {
  local leg="$1" stage="$2" at="$3" minutes="$4" remaining_before="$5" baseline_ok="$6"
  local effort="${minutes}m"
  if [[ "$CAPABILITY" == "none" ]]; then
    js_report syncjs.worklog.postcheck_unsupported \
      "the declared worklog_postcheck_capability is 'none' -- stage=$stage at=$at ($leg) posted, absorption not verified"
    return
  fi
  if [[ "$baseline_ok" != "yes" ]]; then
    js_report syncjs.worklog.postcheck_failed \
      "the pre-add baseline READ failed for stage=$stage at=$at ($leg) -- a baseline is never inferred post-hoc; the watermark is NOT advanced"
    RESULT=postcheck-failed
    finish
  fi
  if [[ -z "$remaining_before" ]]; then
    js_report syncjs.worklog.postcheck_skipped_no_estimate \
      "the issue carries no Remaining Estimate -- stage=$stage at=$at ($leg) posted"
    return
  fi
  local before_minutes
  if ! before_minutes="$(duration_minutes "$remaining_before")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the pre-add baseline '$remaining_before' is an unparseable payload ($leg) -- never treated as a pass; the watermark is NOT advanced"
    RESULT=postcheck-indeterminate
    finish
  fi
  local remaining_after=""
  if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=timetracking" || ! js_http_ok \
     || ! remaining_after="$(remaining_of "$JS_HTTP_BODY")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the post-add re-read for stage=$stage at=$at ($leg) was unreachable, rejected, or unparseable -- never treated as a pass; the watermark is NOT advanced"
    RESULT=postcheck-indeterminate
    finish
  fi
  if [[ "$before_minutes" -lt "$minutes" ]]; then
    js_report syncjs.worklog.postcheck_skipped_floor \
      "the baseline ($remaining_before) is less than the posted $effort ($leg), so Jira floors Remaining at zero -- a skip, never a failure"
    return
  fi
  local after_minutes=0
  if [[ -n "$remaining_after" ]] && ! after_minutes="$(duration_minutes "$remaining_after")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the post-add re-read returned '$remaining_after' ($leg), which is not a parseable duration -- never treated as a pass"
    RESULT=postcheck-indeterminate
    finish
  fi
  if [[ $((before_minutes - after_minutes)) -ge "$minutes" ]]; then
    js_report syncjs.worklog.posted \
      "posted stage=$stage ${effort} at=$at ($leg); Remaining $remaining_before -> ${remaining_after:-0m} absorbed the post"
    return
  fi
  js_report syncjs.worklog.postcheck_failed \
    "$ISSUE_KEY stage=$stage at=$at ($leg): baseline=$remaining_before observed=${remaining_after:-0m} expected a decrease of at least $effort -- the tracker did not absorb the post; the watermark is NOT advanced and this is handed to the operator, never self-corrected"
  RESULT=postcheck-failed
  finish
}
