#!/usr/bin/env bash
#
# jira-worklog-agent.sh -- BTG-315 split-mode worklog projection: the operator/
# agent two-leg posting path, sourced by jira-worklog.sh only when a §9
# agent-time user is configured (AGENT_USER non-empty).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075),
# same as jira-worklog.sh. Invariant relied on from outside this boundary:
# BTG-064's worklog immutability and re-run-safety guarantees (jira-worklog.sh's
# own header) apply IDENTICALLY to each leg -- a leg is posted at most once,
# ever, and a crash between legs never duplicates the leg that already landed.
#
# WHY A SEPARATE FILE: jira-worklog.sh sits close to the 400-line DX ceiling
# (BTG-247 already split argument-parsing/candidate-selection into
# jira-worklog-prepare.sh); this ticket's own two-leg posting logic is a
# second, independently-sized concern layered on top, so it gets its own
# module rather than pushing the entry point over the ceiling.
#
# THE UNSPLIT PATH IS NEVER TOUCHED BY THIS FILE (AC-4). Every function here is
# called from exactly one place in jira-worklog.sh's candidate loop, gated on
# `AGENT_USER` being non-empty; an unconfigured adopter's run never sources
# this file's functions into its call graph at all.
#
# Upstream: jira-worklog.sh's candidate loop, once per split-mode candidate.
# Downstream: `POST $JIRA_BASE_URL/rest/logwork-as-another-user/2.0/logwork`
# (the third-party attribution plugin; jira-log-as-user.md's live findings),
# plus the existing core worklog endpoint for the operator leg.
# Spec: archive/BTG-315/spec.md (Proposed Design, Adapter layer; behavioral decomposition AC-2/AC-3/AC-5).
#
# BTG-319: a failed agent-leg POST is classified by `js_worklog_agent_leg_disposition`
# before it is ever treated as a forfeit -- ONLY a 4xx other than 408/429, or an
# HTTP 500 whose JSON `.message` (trailing whitespace removed) equals the LITERAL
# string `Invalid user "<agent-user>".`, is a permanent rejection (forfeit, as
# before). Everything else halts the ticket's worklog step without advancing the
# watermark, so a re-run retries the agent leg instead of losing it permanently
# to a transient server/plugin failure (spec.md AC-1/AC-2; PROD_CADENCE-051).

# review cycle-2 B3 (decisions.md): the shared absorption-check pair,
# sourced here so both legs can call it -- split into its own sidecar file
# to keep THIS file under the Facet 3 DX line ceiling; see that file's own
# header for why.
JS_WORKLOG_ABSORB="$(dirname "${BASH_SOURCE[0]}")/jira-worklog-agent-absorb.sh"
if [[ ! -f "$JS_WORKLOG_ABSORB" ]]; then
  echo "jira-worklog-agent: the absorption-check half is not at $JS_WORKLOG_ABSORB" >&2
  echo "       Both halves ship together; refusing to run without it." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$JS_WORKLOG_ABSORB"

# js_worklog_split <stage> <minutes> -- runs the single split-computation site
# (ci-templates/scripts/worklog-split.sh, resolved via $WLS_PATH) and sets
# JS_OP_MIN / JS_AG_MIN. Any stderr the splitter emits (the
# worklogsplit.factor.org_value_unusable warning, and ONLY that warning --
# the factor itself never leaves the splitter, BTG-315 R6) is forwarded
# verbatim onto THIS script's own stderr, so it reaches the operator through
# the same channel as every other syncjs.* condition. Returns 1 when the
# splitter is missing or exits non-zero; the caller HALTs on that (OS-1.3).
js_worklog_split() {
  local stage="$1" minutes="$2" org errf out rc
  # BTG-317: the SAME CADENCE_ORG_FILE js_agent_user resolved the agent-time
  # user from (jira-projectkey-lib.sh: `org="${CADENCE_ORG_FILE:-$JS_ORG_FILE_DEFAULT}"`),
  # passed to worklog-split.sh as --org so the agent user and the §19 split
  # factor always come from ONE document -- never a suffix-match/fallback
  # derivation that could pick a different file (AC-2).
  org="${CADENCE_ORG_FILE:-$JS_ORG_FILE_DEFAULT}"
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
  JS_OP_MIN="$(printf '%s\n' "$out" | sed -n 's/^operator_minutes=//p')"
  JS_AG_MIN="$(printf '%s\n' "$out" | sed -n 's/^agent_minutes=//p')"
  [[ -n "$JS_OP_MIN" && -n "$JS_AG_MIN" ]] || return 1
  return 0
}

# js_worklog_post_agent_leg <issue-key> <stage> <at> <minutes> <agent-user> --
# the plugin POST (jira-log-as-user.md's live-verified shape): `issueId` is the
# issue KEY (never the numeric id -- a wrong form and a genuine permission
# denial return the SAME HTTP 403, the research note's documented trap),
# `user` the configured identity verbatim, `timeSpent` in Jira duration form,
# `startDate` ISO-8601 WITHOUT milliseconds and WITH the literal `+0000`
# offset suffix (spec.md's Integration Changes: `YYYY-MM-DDTHH:MM:SS+0000`;
# review cycle-2 B4 -- a value with milliseconds returns HTTP 500, and an
# offset-less value risks a server-local time shift), and
# `adjustEstimate=auto` -- never a Remaining override.
#
# THREE-WAY return, distinguished (review cycle-2 B2) so the caller can never
# conflate a LOCAL staging failure with an actual transport problem:
#   0 -- the request was issued (2xx or not); caller reads js_http_ok /
#        $JS_HTTP_STATUS / $JS_HTTP_BODY to tell a rejection from a success.
#   1 -- a genuine TRANSPORT failure (the caller HALTs with
#        syncjs.transport.rest_unreachable, S-5.8).
#   2 -- a LOCAL failure (scratch file or body build) -- already reported
#        (syncjs.worklog.scratch_unavailable / body_unbuildable) inside this
#        function; the caller HALTS with a bare exit, per js_build_body's own
#        contract ("a caller that must halt uses a bare exit, never js_halt,
#        which would double-report"), and must NEVER count this as a rejected
#        leg or report it as rest_unreachable.
js_worklog_post_agent_leg() {
  local issue_key="$1" stage="$2" at="$3" minutes="$4" agent_user="$5"
  local marker="stage=$stage agent-at=$at" start_date body_file
  start_date="$(date -u +%Y-%m-%dT%H:%M:%S)+0000"
  body_file="$(mktemp 2>/dev/null)" || {
    js_report syncjs.worklog.scratch_unavailable \
      "no scratch file could be staged for the agent-leg body ($issue_key stage=$stage at=$at) -- posting NOTHING; a worklog cannot be un-posted"
    return 2
  }
  js_build_body "$body_file" syncjs.worklog.body_unbuildable \
    "the agent-leg body for $issue_key (stage=$stage at=$at)" \
    -n --arg issueid "$issue_key" --arg user "$agent_user" --arg spent "${minutes}m" \
    --arg start "$start_date" --arg comment "[cadence $marker] CADENCE $stage stage agent effort" \
    '{issueId: $issueid, user: $user, timeSpent: $spent, startDate: $start, adjustEstimate: "auto", comment: $comment}' \
    || { rm -f "$body_file"; return 2; }
  if ! js_rest POST "/rest/logwork-as-another-user/2.0/logwork" "$body_file"; then
    rm -f "$body_file"
    return 1
  fi
  rm -f "$body_file"
  return 0
}

# js_worklog_agent_leg_disposition <agent-user> -- BTG-319: classifies the
# CURRENT $JS_HTTP_STATUS / $JS_HTTP_BODY of a non-2xx agent-leg response.
# Echoes exactly one of `rejected` / `ambiguous` and ALWAYS returns 0 (the
# verdict is the output, as in js_worklog_confirm_agent_author above) --
# only the caller decides what to do with it.
#   rejected  -- a permanent identity/authorization rejection (spec.md AC-1
#                R1/R2): every 4xx EXCEPT 408/429, OR HTTP 500 whose JSON
#                `.message` (trailing whitespace removed) equals the LITERAL
#                string `Invalid user "<agent-user>".` -- string equality via
#                a quoted `[[ ]]` comparison, never a regex/glob/substring/
#                case-folded match, so a username carrying pattern
#                metacharacters (`.`, `+`) matches only itself (S-1.2/S-1.3).
#   ambiguous -- everything else (spec.md AC-2 R4): every other 5xx, 408,
#                429, any 1xx/3xx, an unparseable/non-object/empty body, or a
#                500 whose `.message` names a different user or differs in
#                case. Fail-safe direction: an unrecognized failure is NEVER
#                assumed permanent (Data Integrity over Simplicity, spec.md
#                Facet Conflict Resolution).
js_worklog_agent_leg_disposition() {
  local agent_user="$1" msg expected
  if [[ "$JS_HTTP_STATUS" =~ ^4[0-9][0-9]$ && "$JS_HTTP_STATUS" != "408" && "$JS_HTTP_STATUS" != "429" ]]; then
    printf 'rejected\n'
    return 0
  fi
  if [[ "$JS_HTTP_STATUS" == "500" ]]; then
    msg="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.message // empty' 2>/dev/null)"
    if [[ -n "$msg" ]]; then
      # trailing-whitespace strip (R1: "trailing whitespace removed")
      msg="${msg%"${msg##*[![:space:]]}"}"
      expected="$(printf 'Invalid user "%s".' "$agent_user")"
      if [[ "$msg" == "$expected" ]]; then
        printf 'rejected\n'
        return 0
      fi
    fi
  fi
  printf 'ambiguous\n'
  return 0
}

# js_worklog_confirm_agent_author <issue-key> <marker> <agent-user> -- the
# CONFIRMING RE-READ (PROD_CADENCE-045 / jira-log-as-user.md Finding 1: the
# core Jira REST API returns HTTP 201 while silently keeping the caller as
# `author`, so a create response is NEVER evidence of attribution). Re-reads
# the core worklog list, finds the entry whose comment carries the agent
# marker, and compares its `author.name` to the configured identity
# case-insensitively. Echoes exactly one of `posted` / `misattributed` /
# `unconfirmed` (re-read unreachable, rejected, unparseable, or the marker is
# not found) and always returns 0 -- the verdict is the return value, not the
# exit status, because "the query itself worked" and "what it found" are
# different questions and the caller needs both classified together.
js_worklog_confirm_agent_author() {
  local issue_key="$1" marker="$2" agent_user="$3" author
  if ! js_rest GET "/rest/api/2/issue/$issue_key/worklog" || ! js_http_ok; then
    printf 'unconfirmed\n'; return 0
  fi
  author="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg m "$marker" \
    '(.worklogs // [])[] | select((.comment // "") | contains($m)) | (.author.name // "")' 2>/dev/null | head -1)"
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

# js_worklog_process_split_candidate <stage> <effort> <at> -- the whole
# split-mode handling for ONE candidate entry: resolves the split, posts the
# operator leg through the EXISTING core endpoint (baseline + postcheck,
# mirroring the unsplit path's own logic so the same seams fire -- S-5.9),
# then the agent leg through the plugin, confirmed by re-read. Reads and
# writes the CALLER'S (jira-worklog.sh's) own globals directly -- POSTED,
# ADVANCE, RESULT, AGENT_LEGS_REJECTED, plus the already-resolved ISSUE_KEY /
# CAPABILITY / AGENT_USER / EXISTING_MARKERS -- exactly as
# js_worklog_select_candidates already does for CANDIDATES/MALFORMED; this is
# the established no-`local` convention for a sourced entry-point helper, not
# a new one. May call the caller's own `finish` function to exit early
# (postcheck-failed / postcheck-indeterminate / unconfirmed attribution),
# which is safe because `finish` is DEFINED in jira-worklog.sh before the
# loop that calls this function ever runs, even though it is sourced earlier.
js_worklog_process_split_candidate() {
  local stage="$1" effort="$2" at="$3"
  local unsplit_marker="stage=$stage at=$at"
  local op_marker="stage=$stage op-at=$at"
  local ag_marker="stage=$stage agent-at=$at"

  # OQ-5: an unsplit-mode marker suppresses the WHOLE entry -- a pre-upgrade
  # full worklog is never topped up with an agent leg.
  if grep -qF "$unsplit_marker" <<<"$EXISTING_MARKERS"; then
    js_report syncjs.worklog.skipped_already_logged \
      "skipped-already-logged (unsplit marker present) for stage=$stage at=$at -- advancing the watermark to observed reality"
    ADVANCE="$at"; return 0
  fi

  js_worklog_skip_zero syncjs.worklog.skipped_zero "$effort" "$stage" "$at" && { ADVANCE="$at"; return 0; }

  local posted_minutes
  if ! posted_minutes="$(duration_minutes "$effort")"; then
    js_report syncjs.worklog.entry_malformed \
      "stage=$stage at=$at carries an unparseable effort '$effort' -- halting the batch here, never guessing a duration"
    RESULT=halted-malformed
    finish
  fi

  if ! js_worklog_split "$stage" "$posted_minutes"; then
    js_halt "$JS_EXIT_CONFIG" syncjs.worklog.split_unavailable \
      "an agent-time user is configured but the split computation site ($WLS_PATH) is missing or exited non-zero -- nothing posted for stage=$stage at=$at, the watermark stays put"
  fi

  # RECORD-BEFORE-CONTACT (section 9 audit precedent): the split audit line
  # is emitted before either leg is posted, and names ONLY durations and the
  # identity -- never the factor (BTG-315 R6, OS-1.4).
  js_report syncjs.worklog.split_resolved \
    "stage=$stage at=$at operator=${JS_OP_MIN}m agent=${JS_AG_MIN}m agent_user=$AGENT_USER"

  local op_present="" ag_present=""
  grep -qF "$op_marker" <<<"$EXISTING_MARKERS" && op_present=yes
  grep -qF "$ag_marker" <<<"$EXISTING_MARKERS" && ag_present=yes

  # --- operator leg: the EXISTING core endpoint, baseline + postcheck ------
  if [[ "$op_present" == "yes" ]]; then
    js_report syncjs.worklog.skipped_already_logged \
      "operator leg already logged for stage=$stage at=$at"
  elif [[ "$JS_OP_MIN" -eq 0 ]]; then
    js_report syncjs.worklog.leg_zero_skipped \
      "operator leg for stage=$stage at=$at is 0m -- posting nothing"
  else
    _js_post_operator_leg "$stage" "$at" "$JS_OP_MIN" "$op_marker"
  fi

  # --- agent leg: the plugin, confirmed by re-read --------------------------
  if [[ "$ag_present" == "yes" ]]; then
    js_report syncjs.worklog.skipped_already_logged \
      "agent leg already logged for stage=$stage at=$at"
    ADVANCE="$at"; return 0
  fi
  if [[ "$JS_AG_MIN" -eq 0 ]]; then
    js_report syncjs.worklog.leg_zero_skipped \
      "agent leg for stage=$stage at=$at is 0m -- posting nothing"
    ADVANCE="$at"; return 0
  fi

  # review cycle-2 B3: the agent leg's own absorption BASELINE, read BEFORE
  # its POST -- spec.md Facet 4's stated order ("... agent leg, attribution
  # re-read, agent absorption check ...") applies the SAME rule the operator
  # leg already has, per leg, not as an operator-only special case.
  local _js_ag_remaining_before _js_ag_baseline_ok
  _js_worklog_absorb_baseline
  _js_ag_remaining_before="$BASELINE_VALUE"
  _js_ag_baseline_ok="$BASELINE_OK"

  js_worklog_post_agent_leg "$ISSUE_KEY" "$stage" "$at" "$JS_AG_MIN" "$AGENT_USER"
  local _js_agent_post_rc=$?
  # review cycle-2 B2: a LOCAL failure (rc 2) already reported its own named
  # condition inside js_worklog_post_agent_leg -- halt with a bare exit, per
  # js_build_body's own contract, and never relabel it rest_unreachable or
  # count it as a rejected leg (that would be a genuine tracker rejection's
  # classification, which this is not).
  if [[ "$_js_agent_post_rc" -eq 2 ]]; then
    exit "$JS_EXIT_FAIL"
  elif [[ "$_js_agent_post_rc" -ne 0 ]]; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "POST /rest/logwork-as-another-user/2.0/logwork could not reach ${BASE_URL%/} -- watermark NOT advanced; a re-run posts only the missing leg"
  fi
  if ! js_http_ok; then
    # BTG-319: distinguish a PERMANENT identity rejection (forfeit, as
    # before) from anything NOT positively identified as one (halt, never
    # forfeit) -- the catch-all arm is `*)`, not `ambiguous)`, so even an
    # unexpected verdict word halts (fail loud, spec.md Proposed Design).
    case "$(js_worklog_agent_leg_disposition "$AGENT_USER")" in
      rejected)
        js_report syncjs.worklog.agent_leg_rejected \
          "ticket=$TICKET stage=$stage at=$at agent_minutes=$JS_AG_MIN agent_user=$AGENT_USER status=$JS_HTTP_STATUS body=$(printf '%s' "$JS_HTTP_BODY" | head -c 200)"
        AGENT_LEGS_REJECTED=$((AGENT_LEGS_REJECTED + 1))
        # OQ-3/OQ-4: the rejected share is FORFEITED, never retried, and the
        # watermark still advances -- a rejection writes no state that would
        # change any LATER split (not sticky, S-5.3).
        ADVANCE="$at"; return 0
        ;;
      *)
        # AC-2 R5/R6: HALT before ADVANCE or AGENT_LEGS_REJECTED are ever
        # touched for this candidate -- nothing is forfeited, the watermark
        # is not advanced, and a re-run retries only the missing agent leg
        # (AC-3). The body excerpt flattens CR/LF to spaces (R12) so the
        # condition stays one line even for a multi-line HTML body (S-4.2).
        js_halt "$JS_EXIT_FAIL" syncjs.worklog.agent_leg_status_ambiguous \
          "ticket=$TICKET stage=$stage at=$at agent_minutes=$JS_AG_MIN agent_user=$AGENT_USER status=$JS_HTTP_STATUS body=$(printf '%s' "$JS_HTTP_BODY" | tr '\r\n' '  ' | head -c 200) -- not a recognized identity rejection; nothing forfeited, watermark NOT advanced; a re-run retries only the agent leg"
        ;;
    esac
  fi
  POSTED=$((POSTED + 1))

  local confirm; confirm="$(js_worklog_confirm_agent_author "$ISSUE_KEY" "$ag_marker" "$AGENT_USER")"
  case "$confirm" in
    posted)
      js_report syncjs.worklog.agent_leg_posted \
        "posted stage=$stage agent=${JS_AG_MIN}m at=$at to $AGENT_USER" ;;
    misattributed)
      js_report syncjs.worklog.agent_leg_misattributed \
        "stage=$stage at=$at: the agent leg posted but the re-read does not name $AGENT_USER as author -- worklogs are immutable, never re-posted" ;;
    unconfirmed)
      js_report syncjs.worklog.agent_leg_unconfirmed \
        "stage=$stage at=$at: the agent leg posted but the attribution re-read was unreachable, rejected, or unparseable -- never treated as a pass; the watermark is NOT advanced"
      RESULT=postcheck-indeterminate
      finish ;;
  esac
  # review cycle-2 B3: the agent leg's own absorption VERIFY, AFTER the
  # attribution re-read (spec.md Facet 4's stated order), for BOTH `posted`
  # and `misattributed` -- the estimate decrement is a property of the POST
  # itself, independent of who it ended up attributed to. `unconfirmed`
  # already halted above and never reaches this line. ADVANCE is set ONLY
  # AFTER this call returns normally: `_js_worklog_absorb_verify` may call
  # `finish` on a postcheck failure/indeterminate outcome, and `finish`
  # reads whatever ADVANCE already holds -- setting it any earlier would
  # report a watermark advance for an entry whose absorption was never
  # confirmed (exactly the bug S-5.9's own operator-leg equivalent avoids
  # by never touching ADVANCE before its own absorb_verify call either).
  _js_worklog_absorb_verify "agent leg" "$stage" "$at" "$JS_AG_MIN" "$_js_ag_remaining_before" "$_js_ag_baseline_ok"
  ADVANCE="$at"
  return 0
}

# _js_post_operator_leg <stage> <at> <minutes> <marker> -- the operator leg's
# post-and-postcheck, mirroring jira-worklog.sh's OWN unsplit-path logic
# (baseline read BEFORE the post) so the SAME seams fire in split mode
# (S-5.9). The absorption VERIFY half is the shared function above
# (review cycle-2 B3); only the baseline-read-then-POST shape stays here,
# deliberately NOT shared with the unsplit path's own inline copy: the
# unsplit path must stay byte-for-byte untouched by this ticket (AC-4), so
# nothing here is extracted FROM it -- this is a parallel implementation of
# the identical rule, not a refactor of the original. Increments the
# caller's POSTED and may call the caller's `finish` on a postcheck failure
# (unsplit's own behavior, mirrored).
_js_post_operator_leg() {
  local stage="$1" at="$2" minutes="$3" marker="$4"
  local effort="${minutes}m"
  local remaining_before baseline_ok body_file

  _js_worklog_absorb_baseline
  remaining_before="$BASELINE_VALUE"
  baseline_ok="$BASELINE_OK"

  # HALTS exactly like the unsplit path's own equivalent (jira-worklog.sh's
  # `BODY_FILE=$(mktemp) || js_halt ...` and `js_build_body ... || exit
  # "$JS_EXIT_FAIL"`), review cycle-2 B2: a local scratch/body-build failure
  # must never silently fall through to the agent leg while the watermark
  # advances past a leg that was never posted.
  body_file="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.worklog.scratch_unavailable \
    "no scratch file could be staged for the operator-leg body ($ISSUE_KEY stage=$stage at=$at) -- posting NOTHING; a worklog cannot be un-posted, so a body this run could not stage is never sent on a guess"
  js_build_body "$body_file" syncjs.worklog.body_unbuildable "the operator-leg body for $ISSUE_KEY (stage=$stage at=$at)" \
    -n --arg spent "$effort" --arg comment "[cadence $marker] CADENCE $stage stage effort" '{timeSpent: $spent, comment: $comment}' \
    || { rm -f "$body_file"; exit "$JS_EXIT_FAIL"; }
  if ! js_rest POST "/rest/api/2/issue/$ISSUE_KEY/worklog?adjustEstimate=auto" "$body_file"; then
    rm -f "$body_file"
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "POST /rest/api/2/issue/$ISSUE_KEY/worklog could not reach ${BASE_URL%/}"
  fi
  rm -f "$body_file"
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.worklog.post_rejected \
      "POST /rest/api/2/issue/$ISSUE_KEY/worklog returned HTTP $JS_HTTP_STATUS for stage=$stage at=$at (operator leg)"
  fi
  POSTED=$((POSTED + 1))
  _js_worklog_absorb_verify "operator leg" "$stage" "$at" "$minutes" "$remaining_before" "$baseline_ok"
}
