#!/usr/bin/env bash
#
# yt-worklog-lib.sh -- the crash-recovery marker scan and the post/verify loop of
# the /claire-sync-youtrack worklog step.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary (BTG-064): a posted work item is
# IMMUTABLE. Nothing here emits a work-item update or a work-item delete, and
# nothing here consults the tracker to decide what is already synced -- the
# repo-owned watermark is the sole oracle. This file exists so that
# `yt-worklog.sh` stays inside the DX line ceiling, which the spec's RISK-5
# anticipated and planned for; it is the same split `yt-link.sh` /
# `yt-link-targets.sh` already uses.
#
# SOURCED by yt-worklog.sh only, and only once the candidate list is non-empty.
# It reads the caller's CANDIDATES / CAPABILITY / ISSUE / TICKET and maintains
# the caller's POSTED / SUPPRESSED / ADVANCE / RESULT / POSTCHECK.
#
# Every REST shape here was OBSERVED (spec-2-live-rest-observations.md SS I).

# yt_worklog_spent_minutes -- the issue's current `Spent time`, in minutes.
# Returns non-zero printing nothing when the READ itself did not happen or could
# not be understood.
#
# THE TWO OUTCOMES ARE NEVER CONFLATED (Behavior 5). "The read failed" and "the
# issue has logged no time yet" are different facts: the first cannot verify
# absorption and must be loud, while the second is an ordinary zero and the
# comparison works perfectly on it. Deriving them both from an empty value made
# every unestimated ticket take a false Critical on the sibling adapter.
#
# `Spent time` reads back as a period value carrying `minutes` (OBSERVED: a
# 90-minute post moved it from null to `1h 30m` / 90). Minutes is used rather
# than the presentation string so the comparison is integer arithmetic and no
# duration is re-parsed on the way back in.
yt_worklog_spent_minutes() {
  local v
  yt_rest GET "/api/issues/$ISSUE?fields=id,customFields(name,value(minutes,presentation))" || return 1
  yt_http_ok || return 1
  v="$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg n "$YT_SPENT_FIELD" '
        ((.customFields // []) | map(select(.name == $n)) | .[0]) as $f
        | if $f == null then 0
          else (($f.value // {}) | if type == "object" then (.minutes // 0) else 0 end) end' 2>/dev/null)" \
    || return 1
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$v"
}

# --------------------------------------------------------------------------
# The SUPPRESS-ONLY marker scan (BTG-064 / crash recovery)
# --------------------------------------------------------------------------
# It runs ONLY over entries the watermark already selected, and it may only
# REMOVE them. It can never TRIGGER a post, so a MISSING marker can never cause
# anything at all. Its whole job is to close the window where a post succeeded
# but the watermark write did not persist -- the window in which a re-run would
# otherwise duplicate a work item that cannot afterwards be deleted.
#
# A scan that could not be performed REFUSES the batch rather than posting
# without it. That asymmetry is the point: the cost of skipping the scan is a
# permanent duplicate, and the cost of refusing is a deferred projection.
# yt_worklog_report_truncation <bound> -- announce a page that came back AT its
# explicit bound.
#
# TRUNCATION IS UNOBSERVABLE FROM THE BODY ALONE. A full page and a page holding
# exactly as many items as the bound are byte-identical answers; only the caller
# knows what it asked for, so only the caller can tell them apart -- and an
# adapter that treated a full page as the whole list would make every decision
# downstream of it on a partial view, silently. `>=`, not `==`, because an
# instance returning one more than asked is still a bounded answer.
#
# It is a WARNING and not a failure, and the direction of the degradation is what
# makes that safe: the scan is SUPPRESS-ONLY, so a marker that fell off the end
# cannot cause anything -- the entry simply is not suppressed, and the watermark
# posts it. That risks a duplicate only inside the crash-recovery window this
# scan exists to cover, whereas treating an unread marker as grounds to DROP the
# entry would lose a stage's effort on every truncated page. A duplicate is
# visible and fixable by hand; a drop is neither.
yt_worklog_report_truncation() {
  local bound="$1" count
  count="$(printf '%s' "$YT_HTTP_BODY" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null)" || return 0
  [[ "$count" =~ ^[0-9]+$ ]] || return 0
  [[ "$count" -ge "$bound" ]] || return 0
  yt_report syncyt.transport.page_truncated \
    "the work-item read for $ISSUE returned $count item(s) against an explicit \$top bound of $bound, so the page may be TRUNCATED and this run has seen only part of the issue's work items. The markers it did read still suppress their entries; an entry whose marker fell outside the page is not suppressed and will post, because an unread marker is never evidence that an entry was already logged. Raise page_top_bound in $(yt_config_path) if this recurs"
}

yt_worklog_scan_markers() {
  # The bound was resolved by the caller, before any request, and a run that
  # could not resolve it never reaches here.
  local bound="$YT_PAGE_BOUND"
  if ! yt_rest GET "/api/issues/$ISSUE/timeTracking/workItems?fields=id,text&\$top=$bound"; then
    yt_report syncyt.worklog.marker_scan_rejected \
      "the crash-recovery scan of $ISSUE's work items could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- posting NOTHING, because a duplicate work item cannot be undone by this adapter"
    return 1
  fi
  if ! yt_http_ok; then
    yt_report syncyt.worklog.marker_scan_rejected \
      "the crash-recovery scan of $ISSUE's work items returned HTTP $YT_HTTP_STATUS -- posting NOTHING without it, because a duplicate work item cannot be undone by this adapter"
    return 1
  fi
  if ! YT_WORKLOG_MARKERS="$(printf '%s' "$YT_HTTP_BODY" \
        | jq -r 'if type == "array" then (.[].text // empty) else error("not an array") end' 2>/dev/null)"; then
    yt_report syncyt.worklog.marker_scan_rejected \
      "the crash-recovery scan of $ISSUE's work items returned a body this adapter cannot read as a work-item list -- posting NOTHING without it"
    return 1
  fi
  # Announced AFTER the markers are parsed, not instead of parsing them: the part
  # of the page that arrived is still usable, and discarding it because the page
  # may be short would throw away the suppression the scan exists to provide.
  yt_worklog_report_truncation "$bound"
  return 0
}

# --------------------------------------------------------------------------
# The post/verify loop
# --------------------------------------------------------------------------
# EXACTLY ONE condition per entry outcome, and no post is ever silent. The
# outcome is on stderr; the post-add VERDICT is on stdout under `postcheck=`.
# They answer different questions -- what happened to this entry, and whether the
# instance absorbed it -- and an operator needs both.
yt_worklog_post_candidates() {
  local candidate stage rest effort at marker minutes before after body

  if ! yt_worklog_scan_markers; then
    RESULT=rejected
    return 0
  fi

  body="$(mktemp)" || {
    yt_report syncyt.worklog.scratch_unavailable \
      "no scratch file could be staged for $TICKET's work-item body -- posting NOTHING; a work item cannot be un-posted, so a body this run could not stage is never sent on a guess"
    RESULT=rejected
    return 0
  }
  trap 'rm -f "$body"' RETURN

  for candidate in "${CANDIDATES[@]}"; do
    stage="${candidate%%|*}"; rest="${candidate#*|}"
    effort="${rest%%|*}"; at="${rest#*|}"
    marker="stage=$stage at=$at"

    # BTG-315: split mode is a COMPLETE alternate path for this candidate,
    # handled entirely in yt-worklog-agent.sh (its own suppress-scan, its
    # own zero-leg skip, its own two-leg posting). Everything below this is
    # UNREACHABLE when AGENT_USER is set, and is otherwise byte-unchanged by
    # this ticket (AC-4).
    if [[ -n "$AGENT_USER" ]]; then
      yt_worklog_process_split_candidate "$stage" "$effort" "$at"
      continue
    fi

    # SUPPRESSION -- the only thing the scan is allowed to do.
    # BTG-315 (additive, AC-4 edge case): a STRAY split-mode marker (left
    # over from a crashed split run, or a since-emptied agent-time-user
    # cell) ALSO suppresses the whole entry here -- see the identical Jira
    # widening. Never changes the byte-identical common case: no split
    # marker can exist on a fork that never ran split mode.
    if printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "$marker" \
       || printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "stage=$stage op-at=$at" \
       || printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "stage=$stage agent-at=$at"; then
      yt_report syncyt.worklog.skipped_already_logged \
        "$TICKET $marker is already on $ISSUE as a work item -- not posted again, and the watermark advances to observed reality"
      SUPPRESSED=$((SUPPRESSED + 1))
      ADVANCE="$at"
      continue
    fi

    if ! minutes="$(yt_duration_minutes "$effort")"; then
      yt_report syncyt.worklog.entry_malformed \
        "$TICKET $marker carries an unparseable effort '$effort' -- halting the batch here; a duration is never guessed, because a wrong work item can never be corrected by this adapter"
      RESULT=halted-malformed
      return 0
    fi

    # AN ENTRY THAT RECORDS NO TIME IS NOT POSTED, and the watermark still moves
    # past it (BTG-112 AC-10 / DEC-007, re-homed here from the MCP-era prose).
    # The skip is REPORTED rather than a bare `continue`, because exactly one
    # worklog condition fires per outcome and a silent pass makes the batch
    # report not add up.
    #
    # The advance is the half that is easy to get wrong, and the ruling turns on
    # a property of the data: `stage_effort` is append-only and an entry's effort
    # is immutable, so no future state can make this skip wrong. Withholding the
    # advance would leave a TRAILING zero entry re-selected on every run, forever
    # re-reporting the same skip and never reaching up-to-date. That is
    # deliberately unlike the malformed branch above, which DOES withhold it: a
    # malformed entry may still owe a projection once it is repaired.
    #
    # The test is on the CONVERTED minutes, not on the literal `0m` the prose
    # named: `0h`, `0d` and `0m` are the same fact, and this way a zero duration
    # can never be offered to the instance whichever spelling produced it.
    if [[ "$minutes" -eq 0 ]]; then
      yt_report syncyt.worklog.skipped_zero \
        "$TICKET $marker records no time ('$effort') -- logging nothing and advancing the watermark past it; the entry is append-only and immutable, so it can never later owe a projection"
      ADVANCE="$at"
      continue
    fi

    # BASELINE, read BEFORE the post. One assignment site, and it is above the
    # post: a baseline captured afterwards is the post-state, and a check against
    # it passes unconditionally.
    if ! before="$(yt_worklog_spent_minutes)"; then before=""; fi

    if ! yt_worklog_post_one "$stage" "$at" "$marker" "$minutes" "$body"; then
      return 0
    fi
    POSTED=$((POSTED + 1))

    if ! yt_worklog_verify_one "$marker" "$minutes" "$before"; then
      return 0
    fi
    ADVANCE="$at"
  done
  return 0
}

# yt_worklog_post_one <stage> <at> <marker> <minutes> <body-file>
# Returns non-zero when the batch must stop. NEVER emits an update or a delete.
yt_worklog_post_one() {
  local stage="$1" at="$2" marker="$3" minutes="$4" body="$5" epoch type_id
  if ! epoch="$(yt_epoch_ms "$at")"; then
    yt_report syncyt.worklog.entry_malformed \
      "$TICKET $marker carries an 'at' this adapter cannot read as a date -- halting the batch here rather than posting a work item onto a date it invented"
    RESULT=halted-malformed
    return 1
  fi
  # The work-item type is OPTIONAL on this instance (omitting it returns
  # `"type": null` and the post still succeeds), so an adopter who declares none
  # gets a typeless work item rather than a guessed one.
  type_id="$(yt_config_get '.work_item_type')" || type_id=""
  # The `text` is the idempotency marker plus a fixed label, and NOTHING else --
  # no numeric multiplier and no arithmetic expression reaches it.
  if ! yt_build_body "$body" syncyt.worklog.body_unbuildable \
        "the work-item body for $TICKET ($marker)" \
        -n --argjson m "$minutes" --argjson d "$epoch" --arg t "[claire $marker] CLAIRE $stage stage effort" \
        --arg ty "$type_id" \
        '{duration:{minutes:$m},date:$d,text:$t} + (if $ty == "" then {} else {type:{id:$ty}} end)'; then
    RESULT=rejected
    return 1
  fi
  if ! yt_rest POST "/api/issues/$ISSUE/timeTracking/workItems?fields=id,duration(minutes),text" "$body"; then
    yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
      "POST /api/issues/$ISSUE/timeTracking/workItems could not reach the instance for $marker${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
  fi
  if ! yt_http_ok; then
    yt_report syncyt.worklog.post_rejected \
      "$TICKET $marker was rejected with HTTP $YT_HTTP_STATUS -- halting the batch here; the watermark stays put so a later run can retry this entry. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
    RESULT=rejected
    return 1
  fi
  YT_WORKLOG_ITEM_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)" || YT_WORKLOG_ITEM_ID=""
  return 0
}

# yt_worklog_verify_one <marker> <posted-minutes> <baseline-minutes>
# Returns non-zero when the batch must stop. The verdict comes from a FRESH
# re-read; the add response's own echo of what it believes it stored is never the
# evidence, because a self-report is exactly what fails when a write is dropped.
yt_worklog_verify_one() {
  local marker="$1" minutes="$2" before="$3" after
  if [[ "$CAPABILITY" == "none" ]]; then
    POSTCHECK=unsupported
    yt_report syncyt.worklog.postcheck_unsupported \
      "$TICKET $marker was posted to $ISSUE (work item ${YT_WORKLOG_ITEM_ID:-unknown}); the declared worklog_postcheck_capability is 'none', so absorption is NOT verified -- an explicit choice, recorded here so it is never mistaken for a check that passed"
    return 0
  fi
  if [[ -z "$before" ]]; then
    # The BASELINE READ failed. A baseline is never inferred after the fact: with
    # no before-value there is no comparison to make, so this is a failure and
    # the watermark does not advance.
    POSTCHECK=failed
    yt_report syncyt.worklog.postcheck_failed \
      "$TICKET $marker was posted to $ISSUE (work item ${YT_WORKLOG_ITEM_ID:-unknown}) but the pre-post '$YT_SPENT_FIELD' baseline READ had failed -- unreachable, rejected, or unreadable -- so absorption cannot be verified and a baseline is never reconstructed after the post. The watermark is NOT advanced; this is handed to the operator and nothing is self-corrected"
    RESULT=postcheck-failed
    return 1
  fi
  if ! after="$(yt_worklog_spent_minutes)"; then
    POSTCHECK=indeterminate
    yt_report syncyt.worklog.postcheck_indeterminate \
      "$TICKET $marker was posted to $ISSUE (work item ${YT_WORKLOG_ITEM_ID:-unknown}) but the post-add re-read of '$YT_SPENT_FIELD' was unreachable, rejected or unreadable -- never treated as a pass, and the watermark is NOT advanced"
    RESULT=postcheck-indeterminate
    return 1
  fi
  # PASS iff the increment is at least the posted duration. A LARGER increase --
  # someone logged time concurrently -- still passes: `>=`, not `==`. `Spent
  # time` only ever grows on this instance, so unlike the sibling's decrementing
  # counterpart there is no floor case to except.
  if [[ $((after - before)) -ge "$minutes" ]]; then
    POSTCHECK=passed
    yt_report syncyt.worklog.posted \
      "$TICKET $marker posted to $ISSUE as work item ${YT_WORKLOG_ITEM_ID:-unknown} ($minutes minutes); '$YT_SPENT_FIELD' went $before -> $after, which absorbs the post"
    return 0
  fi
  POSTCHECK=failed
  yt_report syncyt.worklog.postcheck_failed \
    "$TICKET $marker: issue $ISSUE, work item ${YT_WORKLOG_ITEM_ID:-unknown}, baseline $before minutes, observed $after minutes, expected an increase of at least $minutes minutes -- the instance did NOT absorb the post. The watermark is NOT advanced and the work item is left exactly as it is for the operator: this adapter never updates and never deletes a work item, so it cannot and must not tidy up after itself"
  RESULT=postcheck-failed
  return 1
}
