#!/usr/bin/env bash
#
# yt-worklog-agent.sh -- BTG-315 split-mode worklog projection: the operator/
# agent two-leg posting path, sourced by yt-worklog.sh only when a §9
# agent-time user is configured (AGENT_USER non-empty). The byte-parallel
# sibling of the Jira adapter's jira-worklog-agent.sh, adapted for native
# attribution: YouTrack's `author` field on the SAME work-item endpoint,
# rather than a second, third-party endpoint.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176),
# same as yt-worklog.sh / yt-worklog-lib.sh. Invariant relied on from
# outside this boundary: BTG-064's work-item immutability and re-run-safety
# guarantees apply per-leg, identically to the unsplit path.
#
# WHY A SEPARATE FILE: yt-worklog.sh and yt-worklog-lib.sh are both already
# split out against the 400-line DX ceiling (yt-worklog-lib.sh's own header);
# this ticket's two-leg posting logic is a further, independently-sized
# concern layered on top.
#
# THE UNSPLIT PATH IS NEVER TOUCHED BY THIS FILE (AC-4): every function here
# is called from exactly one place in yt-worklog-lib.sh's candidate loop,
# gated on AGENT_USER being non-empty.
#
# Upstream: yt-worklog-lib.sh's candidate loop, once per split-mode
# candidate.
# Downstream: `POST $YOUTRACK_BASE_URL/api/issues/{id}/timeTracking/workItems`
# with an `author` field for the agent leg (the SAME endpoint the operator
# leg already uses, unlike the Jira adapter's separate plugin path), plus a
# fresh re-read of the created item to confirm attribution.
# Spec: archive/BTG-315/spec.md (Proposed Design, Adapter layer; behavioral decomposition AC-2/AC-3/AC-5).

# yt_worklog_split <stage> <minutes> -- runs the single split-computation
# site (ci-templates/scripts/worklog-split.sh, resolved via $WLS_PATH) and
# sets YT_OP_MIN / YT_AG_MIN. Forwards any stderr the splitter emits (the
# worklogsplit.factor.org_value_unusable warning, and ONLY that warning --
# the factor itself never leaves the splitter, BTG-315 R6) onto this
# script's own stderr. Returns 1 when the splitter is missing or exits
# non-zero; the caller HALTs on that (OS-1.3).
yt_worklog_split() {
  local stage="$1" minutes="$2" org errf out rc
  # BTG-317: the SAME CADENCE_ORG_FILE yt_agent_user resolved the agent-time
  # user from (yt-projectkey-lib.sh: `org="${CADENCE_ORG_FILE:-$YT_ORG_FILE_DEFAULT}"`),
  # passed to worklog-split.sh as --org so the agent user and the §19 split
  # factor always come from ONE document -- never a suffix-match/fallback
  # derivation that could pick a different file (AC-2).
  org="${CADENCE_ORG_FILE:-$YT_ORG_FILE_DEFAULT}"
  if [[ ! -f "$WLS_PATH" ]]; then
    return 1
  fi
  errf="$(mktemp 2>/dev/null)" || errf=""
  out="$(bash "$WLS_PATH" --stage "$stage" --minutes "$minutes" --org "$org" 2>"${errf:-/dev/null}")"
  rc=$?
  if [[ -n "$errf" ]]; then
    [[ -s "$errf" ]] && cat "$errf" >&2
    rm -f "$errf"
  fi
  [[ "$rc" -eq 0 ]] || return 1
  YT_OP_MIN="$(printf '%s\n' "$out" | sed -n 's/^operator_minutes=//p')"
  YT_AG_MIN="$(printf '%s\n' "$out" | sed -n 's/^agent_minutes=//p')"
  [[ -n "$YT_OP_MIN" && -n "$YT_AG_MIN" ]] || return 1
  return 0
}

# yt_worklog_post_agent_one <stage> <at> <marker> <minutes> <agent-user>
# <body-file> -- the agent leg's post, mirroring yt_worklog_post_one
# (yt-worklog-lib.sh) exactly except for the added `author: {login:}` field
# and the agent-specific marker/label. Kept as its own function rather than
# a parameter added to the original: yt_worklog_post_one is UNTOUCHED by
# this ticket (AC-4), so this is a parallel implementation, not a refactor
# of it.
#
# THREE-WAY return (review cycle-2 B2), so the caller can never conflate a
# LOCAL failure with an actual tracker REJECTION:
#   0 -- posted (2xx).
#   1 -- a genuine tracker REJECTION (non-2xx) -- reported here
#        (agent_leg_rejected) WITHOUT halting and WITHOUT setting RESULT;
#        rejection handling (forfeit the share, advance the watermark,
#        never retry) is the caller's job (OQ-3/OQ-4), unlike the operator
#        leg's own post_rejected, which is fatal to the batch.
#   2 -- a LOCAL failure (an unparseable date, or an unbuildable body) --
#        already reported (entry_malformed / body_unbuildable) inside this
#        function; the caller HALTS via yt_worklog_finish and must NEVER
#        count this as a rejected leg.
yt_worklog_post_agent_one() {
  local stage="$1" at="$2" marker="$3" minutes="$4" agent_user="$5" body="$6" epoch type_id
  if ! epoch="$(yt_epoch_ms "$at")"; then
    yt_report syncyt.worklog.entry_malformed \
      "$TICKET $marker carries an 'at' this adapter cannot read as a date -- halting the batch here rather than posting a work item onto a date it invented"
    RESULT=halted-malformed
    return 2
  fi
  type_id="$(yt_config_get '.work_item_type')" || type_id=""
  if ! yt_build_body "$body" syncyt.worklog.body_unbuildable \
        "the agent-leg work-item body for $TICKET ($marker)" \
        -n --argjson m "$minutes" --argjson d "$epoch" --arg t "[cadence $marker] CADENCE $stage stage agent effort" \
        --arg ty "$type_id" --arg au "$agent_user" \
        '{duration:{minutes:$m},date:$d,text:$t,author:{login:$au}} + (if $ty == "" then {} else {type:{id:$ty}} end)'; then
    # review cycle-3 BLOCKING-1: RESULT must be set on this path, mirroring
    # the entry_malformed branch above and the unsplit twin's own
    # RESULT=rejected (yt_worklog_post_one, yt-worklog-lib.sh:237). Without
    # it, yt_worklog_finish derives worklog_result=posted from the OPERATOR
    # leg's own POSTED=1, so the orchestrator-parsed stdout channel reports
    # success while the batch halted and stderr says otherwise -- a genuine
    # contradiction between the two channels DEC-001 exists to prevent.
    #
    # BTG-320 (PROD_CADENCE-054): this NOW REUSES that same rejected literal
    # instead of the split-only halted-body-unbuildable string it used to
    # set. The two are the identical local failure -- a work-item body that
    # cannot be built -- so the orchestrator's `^[a-z_]+_result=rejected$`
    # rule (yt_run_step, youtrack-orchestration.md) now classifies this leg's
    # refusal too, which it silently could not before.
    RESULT=rejected
    return 2
  fi
  if ! yt_rest POST "/api/issues/$ISSUE/timeTracking/workItems?fields=id,duration(minutes),text,author(login)" "$body"; then
    yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
      "POST /api/issues/$ISSUE/timeTracking/workItems (agent leg) could not reach the instance for $marker${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- watermark NOT advanced; a re-run posts only the missing leg"
  fi
  if ! yt_http_ok; then
    yt_report syncyt.worklog.agent_leg_rejected \
      "ticket=$TICKET stage=$stage at=$at agent_minutes=$minutes agent_user=$agent_user status=$YT_HTTP_STATUS body=$(printf '%s' "$YT_HTTP_BODY" | head -c 200)"
    return 1
  fi
  YT_WORKLOG_ITEM_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)" || YT_WORKLOG_ITEM_ID=""
  return 0
}

# yt_worklog_confirm_agent_author <agent-user> -- the CONFIRMING RE-READ.
# Re-reads the just-created work item (by $YT_WORKLOG_ITEM_ID) and compares
# its `author.login` to the configured identity case-insensitively; `creator`
# is never consulted here -- it always stays the operator, by design, and
# is not part of this check. Echoes exactly one of `posted` / `misattributed`
# / `unconfirmed` and always returns 0.
yt_worklog_confirm_agent_author() {
  local agent_user="$1" author
  if [[ -z "${YT_WORKLOG_ITEM_ID:-}" ]]; then
    printf 'unconfirmed\n'; return 0
  fi
  if ! yt_rest GET "/api/issues/$ISSUE/timeTracking/workItems/$YT_WORKLOG_ITEM_ID?fields=author(login)" || ! yt_http_ok; then
    printf 'unconfirmed\n'; return 0
  fi
  author="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.author.login // ""' 2>/dev/null)"
  if [[ -z "$author" ]]; then
    printf 'unconfirmed\n'; return 0
  fi
  if [[ "$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')" \
     == "$(printf '%s' "$agent_user" | tr '[:upper:]' '[:lower:]')" ]]; then
    printf 'posted\n'
  else
    printf 'misattributed\n'
  fi
  return 0
}

# yt_worklog_process_split_candidate <stage> <effort> <at> -- the whole
# split-mode handling for ONE candidate entry. Reads and writes the
# CALLER'S (yt-worklog.sh's / yt-worklog-lib.sh's) own globals directly --
# POSTED, ADVANCE, RESULT, AGENT_LEGS_REJECTED, plus the already-resolved
# ISSUE / CAPABILITY / AGENT_USER / YT_WORKLOG_MARKERS -- the established
# no-`local` convention every sourced entry-point helper in this adapter
# family already uses. May call the caller's own `yt_worklog_finish` to
# exit early, safe because it is DEFINED in yt-worklog.sh before the loop
# that calls this function ever runs.
yt_worklog_process_split_candidate() {
  local stage="$1" effort="$2" at="$3"
  local unsplit_marker="stage=$stage at=$at"
  local op_marker="stage=$stage op-at=$at"
  local ag_marker="stage=$stage agent-at=$at"

  # OQ-5: an unsplit-mode marker suppresses the WHOLE entry.
  if printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "$unsplit_marker"; then
    yt_report syncyt.worklog.skipped_already_logged \
      "$TICKET $unsplit_marker is already on $ISSUE as a work item (unsplit) -- not posted again, and the watermark advances to observed reality"
    SUPPRESSED=$((SUPPRESSED + 1))
    ADVANCE="$at"; return 0
  fi

  local posted_minutes
  if ! posted_minutes="$(yt_duration_minutes "$effort")"; then
    yt_report syncyt.worklog.entry_malformed \
      "$TICKET $stage at=$at carries an unparseable effort '$effort' -- halting the batch here, never guessing a duration"
    RESULT=halted-malformed
    yt_worklog_finish
  fi
  if [[ "$posted_minutes" -eq 0 ]]; then
    yt_report syncyt.worklog.skipped_zero \
      "$TICKET stage=$stage at=$at records no time ('$effort') -- logging nothing and advancing the watermark past it"
    ADVANCE="$at"; return 0
  fi

  if ! yt_worklog_split "$stage" "$posted_minutes"; then
    yt_halt "$YT_EXIT_CONFIG" syncyt.worklog.split_unavailable \
      "an agent-time user is configured but the split computation site ($WLS_PATH) is missing or exited non-zero -- nothing posted for stage=$stage at=$at, the watermark stays put"
  fi

  # RECORD-BEFORE-CONTACT: the split audit line is emitted before either leg
  # is posted, and names ONLY durations and the identity -- never the
  # factor (BTG-315 R6, OS-1.4).
  yt_report syncyt.worklog.split_resolved \
    "stage=$stage at=$at operator=${YT_OP_MIN}m agent=${YT_AG_MIN}m agent_user=$AGENT_USER"

  local op_present="" ag_present=""
  printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "$op_marker" && op_present=yes
  printf '%s\n' "${YT_WORKLOG_MARKERS:-}" | grep -qF "$ag_marker" && ag_present=yes

  # HALTS exactly like the unsplit path's own equivalent
  # (yt_worklog_post_candidates' `body=$(mktemp) || { ...; RESULT=rejected;
  # return 0; }`, which returns straight into an unconditional
  # yt_worklog_finish at the top level): review cycle-2 B2, a local scratch
  # failure must stop this candidate's batch via yt_worklog_finish, never
  # merely `return 0` back into the per-candidate loop, which would let the
  # loop silently move on to the NEXT candidate as if this one succeeded.
  local body; body="$(mktemp 2>/dev/null)" || {
    yt_report syncyt.worklog.scratch_unavailable \
      "no scratch file could be staged for $TICKET's split-mode work-item body for stage=$stage at=$at -- posting NOTHING"
    # BTG-320 (OQ-1 resolved (b), DEC-009): converges on the SAME rejected
    # literal the unsplit path's own equivalent scratch failure already
    # reports (yt-worklog-lib.sh:128-133), making the comment above literally
    # true rather than aspirational.
    RESULT=rejected
    yt_worklog_finish
  }

  # --- operator leg: reuse the UNTOUCHED yt_worklog_post_one / verify_one ---
  if [[ "$op_present" == "yes" ]]; then
    yt_report syncyt.worklog.skipped_already_logged \
      "operator leg already logged for stage=$stage at=$at"
  elif [[ "$YT_OP_MIN" -eq 0 ]]; then
    yt_report syncyt.worklog.leg_zero_skipped \
      "operator leg for stage=$stage at=$at is 0m -- posting nothing"
  else
    local before
    if ! before="$(yt_worklog_spent_minutes)"; then before=""; fi
    if yt_worklog_post_one "$stage" "$at" "$op_marker" "$YT_OP_MIN" "$body"; then
      POSTED=$((POSTED + 1))
      if ! yt_worklog_verify_one "$op_marker" "$YT_OP_MIN" "$before"; then
        rm -f "$body"
        yt_worklog_finish
      fi
    else
      rm -f "$body"
      yt_worklog_finish
    fi
  fi

  # --- agent leg: the SAME endpoint, author field, confirmed by re-read ----
  if [[ "$ag_present" == "yes" ]]; then
    yt_report syncyt.worklog.skipped_already_logged \
      "agent leg already logged for stage=$stage at=$at"
    rm -f "$body"; ADVANCE="$at"; return 0
  fi
  if [[ "$YT_AG_MIN" -eq 0 ]]; then
    yt_report syncyt.worklog.leg_zero_skipped \
      "agent leg for stage=$stage at=$at is 0m -- posting nothing"
    rm -f "$body"; ADVANCE="$at"; return 0
  fi

  # review cycle-2 B3: the agent leg's own absorption BASELINE, read BEFORE
  # its POST -- spec.md Facet 4's stated order applies the SAME rule the
  # operator leg already has (via yt_worklog_verify_one, reused below), per
  # leg, not as an operator-only special case.
  local _yt_ag_before
  if ! _yt_ag_before="$(yt_worklog_spent_minutes)"; then _yt_ag_before=""; fi

  yt_worklog_post_agent_one "$stage" "$at" "$ag_marker" "$YT_AG_MIN" "$AGENT_USER" "$body"
  local _yt_agent_post_rc=$?
  if [[ "$_yt_agent_post_rc" -ne 0 ]]; then
    rm -f "$body"
    # review cycle-2 B2: rc 2 is a LOCAL failure (malformed date or an
    # unbuildable body) -- already reported inside yt_worklog_post_agent_one;
    # halt via yt_worklog_finish and NEVER count it as a rejected leg. rc 1
    # is a genuine tracker REJECTION (OQ-3/OQ-4): forfeited, never retried,
    # watermark still advances.
    if [[ "$_yt_agent_post_rc" -eq 2 ]]; then yt_worklog_finish; fi
    AGENT_LEGS_REJECTED=$((AGENT_LEGS_REJECTED + 1))
    ADVANCE="$at"; return 0
  fi
  rm -f "$body"
  POSTED=$((POSTED + 1))

  local confirm; confirm="$(yt_worklog_confirm_agent_author "$AGENT_USER")"
  case "$confirm" in
    posted)
      yt_report syncyt.worklog.agent_leg_posted \
        "posted stage=$stage agent=${YT_AG_MIN}m at=$at to $AGENT_USER" ;;
    misattributed)
      yt_report syncyt.worklog.agent_leg_misattributed \
        "stage=$stage at=$at: the agent leg posted but the re-read does not name $AGENT_USER as author -- work items are immutable, never re-posted" ;;
    unconfirmed)
      yt_report syncyt.worklog.agent_leg_unconfirmed \
        "stage=$stage at=$at: the agent leg posted but the attribution re-read was unreachable, rejected, or unparseable -- never treated as a pass; the watermark is NOT advanced"
      RESULT=postcheck-indeterminate
      yt_worklog_finish ;;
  esac
  # review cycle-2 B3: the agent leg's own absorption VERIFY, AFTER the
  # attribution re-read (spec.md Facet 4's stated order), reusing
  # yt_worklog_verify_one (yt-worklog-lib.sh) verbatim -- it is ALREADY
  # leg-agnostic (keys only on YT_WORKLOG_ITEM_ID, which
  # yt_worklog_post_agent_one also sets), so no parallel copy is needed
  # here, unlike the Jira adapter's own operator/agent split. `unconfirmed`
  # already halted above and never reaches this line. ADVANCE is set ONLY
  # AFTER this call returns success: on failure it returns 1 without
  # calling yt_worklog_finish itself (yt_worklog_lib.sh's own contract --
  # the CALLER decides), so this halts exactly the same way the operator
  # leg's own call site does.
  if ! yt_worklog_verify_one "$ag_marker" "$YT_AG_MIN" "$_yt_ag_before"; then
    yt_worklog_finish
  fi
  ADVANCE="$at"
  return 0
}
