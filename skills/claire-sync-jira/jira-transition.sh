#!/usr/bin/env bash
#
# jira-transition.sh -- apply the repo `status` to the Jira issue as a workflow
# TRANSITION (Jira will not let a status be set directly).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (BTG-040): an **Epic's status is
# never touched** -- Epic status is managed manually by humans, externally -- so
# this step is skipped entirely for `type: epic` rather than being applied and
# reverted.
#
# Upstream: invoked by the /claire-sync-jira orchestrator after the projection
#   write and before the worklog + assignee steps.
# Downstream: `GET`/`POST $JIRA_BASE_URL/rest/api/2/issue/{key}[/transitions]`.
# Spec: archive/BTG-075/spec.md (AC-2) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> --issue-key <KEY>
#   stdout : transitions_applied=<n>
#            transition_result=applied|at-target|skipped-epic|skipped-unmapped
#   stderr : syncjs.transition.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# This is a BLOCKING step: a rejected or unreachable transition halts the ticket.
# Status is the field every other CLAIRE surface reads back, so projecting it
# wrong -- or not at all, quietly -- misreports the state of the work itself.
#
# This script READS metadata.yaml and NEVER writes it (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

TICKET=""
ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)    js_argv_pair syncjs.transition.usage "$@"; TICKET="$2"; shift 2 ;;
    --issue-key) js_argv_pair syncjs.transition.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.transition.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET"    ]] || js_halt "$JS_EXIT_USAGE" syncjs.transition.usage "--ticket <id> is required"
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.transition.usage "--issue-key <KEY> is required"

js_config_require
js_metadata_load "$TICKET"

# An Epic's status is human-managed: skip BEFORE any call, so the run cannot even
# accidentally read-modify one.
if [[ "$(js_metadata_get '.type')" == "epic" ]]; then
  js_report syncjs.transition.skipped_epic \
    "$TICKET is an Epic -- its workflow status is managed manually by humans and is never transitioned by this sync"
  js_emit transitions_applied 0
  js_emit transition_result skipped-epic
  exit "$JS_EXIT_OK"
fi

STATUS="$(js_metadata_get '.status')"
[[ -n "$STATUS" ]] || js_halt "$JS_EXIT_FAIL" syncjs.transition.status_absent \
  "$TICKET carries no status -- refusing to guess a workflow target"

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.transition.env_absent "the base-URL environment variable is unset"

# The issue's CURRENT status and its issue TYPE both come from the live issue: the
# workflow scheme follows the type Jira actually holds, not the type the repo
# would like it to have (a re-type may not have been accepted).
if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=status,issuetype"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "GET /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/}"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS"
fi
if ! CURRENT_STATUS="$(printf '%s' "$JS_HTTP_BODY" | jq -r 'if type=="object" then (.fields.status.name // "") else error("x") end' 2>/dev/null)"; then
  js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
    "the issue read returned an unparseable body -- refusing to transition blind"
fi
ISSUE_TYPE="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.fields.issuetype.name // ""')"
[[ -n "$ISSUE_TYPE" ]] || js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
  "the issue read returned no issue type -- the workflow scheme cannot be resolved"

# The target is a pure config lookup. An unmapped status or workflow is REPORTED,
# never guessed: forcing a status the workflow does not define is how a sync
# corrupts a board.
if ! TARGET="$(js_config_map2 status_workflow_map "$ISSUE_TYPE" "$STATUS")"; then
  js_report syncjs.transition.unmapped \
    "no status_workflow_map entry for issue type '$ISSUE_TYPE' status '$STATUS' -- no transition is applied and none is guessed"
  js_emit transitions_applied 0
  js_emit transition_result skipped-unmapped
  exit "$JS_EXIT_OK"
fi

if [[ "$CURRENT_STATUS" == "$TARGET" ]]; then
  js_report syncjs.transition.at_target \
    "$ISSUE_KEY is already at '$TARGET' -- no transition applied (a completed path is never re-walked)"
  js_emit transitions_applied 0
  js_emit transition_result at-target
  exit "$JS_EXIT_OK"
fi

# The statuses THIS issue type's workflow declares -- the only states an
# intermediate hop may step through. Read from the same config block that chose
# the target, so the walk can never leave the governed workflow. Wrapped in
# newlines at both ends so an awk `index()` match is exact, not a substring.
JS_NL=$'\n'
DECLARED_STATUSES="$JS_NL$(js_config_workflow_statuses "$ISSUE_TYPE" || true)$JS_NL"

BODY_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.transition.scratch_unavailable "no scratch file could be staged for the transition body -- issuing NO transition; a bodyless POST /transitions is rejected 400, and this step is BLOCKING"
trap 'rm -f "$BODY_FILE" 2>/dev/null' EXIT
APPLIED=0

# Walk toward the target, re-reading the offered transitions after each hop so a
# multi-hop path is followed by OBSERVATION, never by assumption. The bound stops
# a workflow cycle from spinning; reaching it is a fail-loud outcome, not a
# silent give-up.
MAX_HOPS=4
# Every transition id already POSTed, and every status already stood in. A
# transition is never fired TWICE in one run: re-selecting the same id (the
# config-declared global one is offered from every status, so it was selectable on
# every pass) re-fires real post-functions and re-sends notifications, and a
# workflow that routes back to a visited status would do it MAX_HOPS times before
# anyone noticed.
TRIED_IDS=""
VISITED="$JS_NL$CURRENT_STATUS$JS_NL"
while [[ "$APPLIED" -lt "$MAX_HOPS" ]]; do
  if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY/transitions"; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "GET /rest/api/2/issue/$ISSUE_KEY/transitions could not reach ${BASE_URL%/}"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
      "GET /rest/api/2/issue/$ISSUE_KEY/transitions returned HTTP $JS_HTTP_STATUS"
  fi
  if ! OFFERED="$(printf '%s' "$JS_HTTP_BODY" | jq -r 'if type=="object" then ((.transitions // [])[] | "\(.id)\t\(.to.name // "")") else error("x") end' 2>/dev/null)"; then
    js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
      "the transitions read returned an unparseable body -- refusing to transition blind"
  fi

  # (1) the target is directly offered from here
  TRANSITION_ID="$(awk -F'\t' -v t="$TARGET" '$2 == t {print $1; exit}' <<<"$OFFERED")"
  # (2) else an instance-declared global transition id for this target -- but only
  # if it has not already been fired this run.
  if [[ -z "$TRANSITION_ID" ]]; then
    GLOBAL_ID="$(js_config_map2 status_workflow_map global_transitions "$TARGET" || true)"
    if [[ -n "$GLOBAL_ID" && " $TRIED_IDS " != *" $GLOBAL_ID "* ]]; then
      TRANSITION_ID="$GLOBAL_ID"
      js_report syncjs.transition.global_used \
        "'$TARGET' is not offered from '$CURRENT_STATUS'; using the config-declared global transition id $TRANSITION_ID"
    fi
  fi
  # (3) else walk ONE INTERMEDIATE HOP toward the target -- Jira only offers the
  # transitions available FROM the current status, so a mapped target is often not
  # reachable in one (the Bug workflow's `Code Review -> In Progress -> Done` is
  # the named case). The walk is GOVERNED, not a guess:
  #   - a candidate's landing status must be a status THIS issue type's workflow
  #     map declares, so the walk can never wander onto an ungoverned board state;
  #   - a status already visited this run is excluded, so a cycle cannot spin;
  #   - and the candidate must be UNIQUE. Two governed onward hops is a real
  #     choice between two paths, and picking one is exactly the ungoverned state
  #     change this script refuses to make.
  if [[ -z "$TRANSITION_ID" ]]; then
    HOP="$(awk -F'\t' -v declared="$DECLARED_STATUSES" -v visited="$VISITED" -v tried="$TRIED_IDS" '
        $2 != "" \
          && index(declared, "\n" $2 "\n") > 0 \
          && index(visited,  "\n" $2 "\n") == 0 \
          && index(" " tried " ", " " $1 " ") == 0 { print $1 "\t" $2 }' <<<"$OFFERED")"
    HOP_COUNT="$(grep -c . <<<"$HOP" || true)"
    [[ -z "$HOP" ]] && HOP_COUNT=0
    if [[ "$HOP_COUNT" -eq 1 ]]; then
      TRANSITION_ID="${HOP%%$'\t'*}"
      js_report syncjs.transition.hop \
        "'$TARGET' is not offered from '$CURRENT_STATUS'; stepping through '${HOP#*$'\t'}', the one governed onward status this workflow declares, and re-listing from there"
    elif [[ "$HOP_COUNT" -gt 1 ]]; then
      js_halt "$JS_EXIT_FAIL" syncjs.transition.unreachable \
        "'$TARGET' is not offered from '$CURRENT_STATUS' and $HOP_COUNT governed onward hops are available ($(tr '\n' ' ' <<<"$HOP")) -- refusing to choose a path through the workflow; declare a global transition id for '$TARGET' instead"
    fi
  fi
  # (4) otherwise STOP: no path exists at all from here.
  if [[ -z "$TRANSITION_ID" ]]; then
    js_halt "$JS_EXIT_FAIL" syncjs.transition.unreachable \
      "'$TARGET' is not reachable from '$CURRENT_STATUS' for issue type '$ISSUE_TYPE' (offered: $(tr '\n' ' ' <<<"$OFFERED")) -- no direct transition, no unfired global transition id, and no governed intermediate hop"
  fi
  TRIED_IDS="${TRIED_IDS:+$TRIED_IDS }$TRANSITION_ID"

  # A build failure is the ADAPTER's, never the instance's: a bare exit after the
  # helper's own report, because js_halt would emit a SECOND condition (BTG-084).
  js_build_body "$BODY_FILE" syncjs.transition.body_unbuildable \
    "the transition body for $ISSUE_KEY (id=$TRANSITION_ID)" \
    -n --arg id "$TRANSITION_ID" '{transition: {id: $id}}' || exit "$JS_EXIT_FAIL"
  if ! js_rest POST "/rest/api/2/issue/$ISSUE_KEY/transitions" "$BODY_FILE"; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "POST /rest/api/2/issue/$ISSUE_KEY/transitions could not reach ${BASE_URL%/}"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
      "POST /rest/api/2/issue/$ISSUE_KEY/transitions (id=$TRANSITION_ID, target '$TARGET') returned HTTP $JS_HTTP_STATUS: $JS_HTTP_BODY"
  fi
  APPLIED=$((APPLIED + 1))

  # Verify by RE-READ where we actually landed -- a transition can route somewhere
  # other than its declared `to` when a post-function intervenes.
  if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=status" || ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.transition.rest_rejected \
      "could not re-read $ISSUE_KEY after applying transition $TRANSITION_ID -- the landed status is unverified"
  fi
  CURRENT_STATUS="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.fields.status.name // ""')"
  VISITED="$VISITED$CURRENT_STATUS$JS_NL"
  [[ "$CURRENT_STATUS" == "$TARGET" ]] && break
done

if [[ "$CURRENT_STATUS" != "$TARGET" ]]; then
  js_halt "$JS_EXIT_FAIL" syncjs.transition.unreachable \
    "after $APPLIED hop(s) $ISSUE_KEY is at '$CURRENT_STATUS', not the target '$TARGET' -- stopping rather than walking the workflow further"
fi

js_report syncjs.transition.applied "$ISSUE_KEY transitioned to '$TARGET' in $APPLIED hop(s) for status '$STATUS'"
js_emit transitions_applied "$APPLIED"
js_emit transition_result applied
exit "$JS_EXIT_OK"
