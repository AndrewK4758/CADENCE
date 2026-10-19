#!/usr/bin/env bash
#
# jira-sprint-check.sh -- is this ticket in an OPEN sprint? (read-only gate input)
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: `/claire-implement`'s sprint-enforcement
# guard (`CLAIRE_ORG.md` §13) turns this verdict into Proceed / Block / fallback.
# So the three verdicts are NOT interchangeable: exists-but-in-no-open-sprint
# (`not-in-sprint`) is a BLOCK, while no-such-ticket or any unresolved key is
# `inconclusive` and sends the guard to its fallback. A 400 is NEVER
# `not-in-sprint` (BTG-004 DEC-002/DEC-008), and there is no summary-search
# fallback -- a fuzzy match is unsafe for a gate decision, so an unresolved key is
# reported, never guessed.
#
# Upstream: /claire-implement's sprint guard, via the orchestrator.
# Downstream: one `GET $JIRA_BASE_URL/rest/api/2/search` -- READ-ONLY. This script
#   writes nothing to Jira and nothing to the repository.
# Spec: archive/BTG-075/spec.md (script inventory) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id>            (the Jira key is resolved verbatim, or from
#                                      metadata.yaml jira_url when present)
#   stdout : sprint_verdict=in-sprint|not-in-sprint|inconclusive  issue_key=<KEY>
#   stderr : syncjs.sprintcheck.* reported conditions (each verdict carries a reason)
#   exit   : 0 -- a verdict is a RESULT, not a failure; the guard decides what to do
#            with it. 2 usage / 3 transport unreachable / 4 config HALT.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) js_argv_pair syncjs.sprintcheck.usage "$@"; TICKET="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.sprintcheck.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || js_halt "$JS_EXIT_USAGE" syncjs.sprintcheck.usage "--ticket <id> is required"

js_config_require
BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.sprintcheck.env_absent "the base-URL environment variable is unset"

# Resolve the key VERBATIM: the recorded jira_url when the ticket has one, else the
# ticket id itself. No summary search -- an unresolved key is inconclusive.
ISSUE_KEY="$TICKET"
if js_metadata_path "$TICKET" >/dev/null 2>&1; then
  js_metadata_load "$TICKET"
  RECORDED="$(js_metadata_get '.jira_url')"
  [[ -n "$RECORDED" ]] && ISSUE_KEY="${RECORDED##*/}"
fi

JQL="key=$ISSUE_KEY AND sprint in openSprints()"
QUERY="$(jq -rn --arg jql "$JQL" '$jql|@uri')"
if ! js_rest GET "/rest/api/2/search?jql=$QUERY&fields=key&maxResults=1"; then
  js_report syncjs.sprintcheck.transport_unreachable \
    "GET /rest/api/2/search could not reach ${BASE_URL%/} -- the sprint state is UNKNOWN, never assumed"
  js_emit sprint_verdict inconclusive
  js_emit issue_key "$ISSUE_KEY"
  exit "$JS_EXIT_OK"
fi

if js_http_ok; then
  TOTAL="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.total // empty' 2>/dev/null)"
  case "$TOTAL" in
    0) js_report syncjs.sprintcheck.not_in_sprint "$ISSUE_KEY exists but is in no open sprint"
       VERDICT=not-in-sprint ;;
    ''|*[!0-9]*)
       js_report syncjs.sprintcheck.shape_unrecognized \
         "the search returned no usable total -- the sprint state is UNKNOWN, never assumed"
       VERDICT=inconclusive ;;
    *) js_report syncjs.sprintcheck.in_sprint "$ISSUE_KEY is in an open sprint"
       VERDICT=in-sprint ;;
  esac
else
  # A 400 here means Jira does not know that key at all. That is NOT
  # `not-in-sprint` -- reporting it as one would BLOCK on a ticket that simply
  # does not exist in the tracker (BTG-004 DEC-002).
  if [[ "$JS_HTTP_STATUS" == "400" ]]; then
    js_report syncjs.sprintcheck.nonexistent_key \
      "$ISSUE_KEY does not exist in this Jira instance -- inconclusive, never not-in-sprint"
  else
    js_report syncjs.sprintcheck.rejected \
      "the sprint query returned HTTP $JS_HTTP_STATUS -- the sprint state is UNKNOWN, never assumed"
  fi
  VERDICT=inconclusive
fi

js_emit sprint_verdict "$VERDICT"
js_emit issue_key "$ISSUE_KEY"
exit "$JS_EXIT_OK"
