#!/usr/bin/env bash
#
# yt-sprint-check.sh -- is this ticket in a sprint? (read-only gate input)
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: `/cadence-implement`'s sprint-enforcement
# guard (`CADENCE_ORG.md` section 13) turns this verdict into Proceed / Block /
# fallback. The three verdicts are therefore NOT interchangeable:
# exists-but-in-no-sprint (`not-in-sprint`) is a BLOCK, while no-such-id or any
# unresolved query is `inconclusive` and sends the guard to its fallback.
#
# A 400 IS NEVER `not-in-sprint`. On this instance a query naming an id that does
# not exist answers 400 `invalid_query`, while a nonsense FIELD name answers 200
# with an empty array (OBSERVED, spec sidecar 2 H) -- so an empty result and an
# unresolvable query are different facts arriving through different channels, and
# only one of them means "the ticket exists and is not in a sprint". There is no
# summary-search fallback: a fuzzy match is unsafe for a gate decision.
#
# THE QUERY IS CONFIGURATION, and that is a documented divergence
# (AC-6 divergence 5). The sibling
# adapter can write `sprint in openSprints()`; this instance has no such function
# -- sprint membership is a board concept, the reference project has no agile
# board, and a naive sprint query in a board-less project matches EVERY issue
# because `Unscheduled` is the empty-field text for the sprint field (OBSERVED).
# So the query lives in `youtrack-server-config.json` under `sprint_query` with
# `{key}` substituted, and an adopter WITH a board narrows it to their current
# sprint. An absent or blank template yields `inconclusive` -- never a guess.
#
# Upstream: /cadence-implement's sprint guard, via the orchestrator's `sprint-check` target.
# Downstream: ONE `GET /api/issues?query=...` -- READ-ONLY. This script writes
#   nothing to the instance and nothing to the repository.
# Spec: archive/BTG-176/spec.md (Script inventory -- yt-sprint-check.sh) ;
#   youtrack-scripts.md.
#
# Contract (three channels):
#   args   : --ticket <id>   (resolved VERBATIM: the recorded youtrack_url when
#                             the ticket has one, else the ticket id itself)
#   stdout : sprint_verdict=in-sprint|not-in-sprint|inconclusive
#            issue_readable=<KEY-N>
#   stderr : syncyt.sprintcheck.* -- every verdict carries its reason
#   exit   : 0 -- A VERDICT IS A RESULT, not a failure, and the guard decides
#            what to do with it. 2 usage / 4 config HALT. Deliberately NOT 3: an
#            unreachable instance is a KNOWN-UNKNOWN sprint state, which is
#            exactly `inconclusive`, and halting there would deny the guard the
#            fallback it has for this case.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.sprintcheck.usage \
        "--ticket requires a value, but the argument list ends there"
      TICKET="$2"; shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.sprintcheck.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.sprintcheck.usage "--ticket <id> is required"

yt_config_require

# Resolve the id VERBATIM: the recorded youtrack_url when the ticket has one,
# else the ticket id itself. Never a search.
ISSUE_READABLE="$TICKET"
if yt_metadata_path "$TICKET" >/dev/null 2>&1; then
  yt_metadata_load "$TICKET"
  RECORDED="$(yt_metadata_get '.youtrack_url')"
  [[ -n "$RECORDED" ]] && ISSUE_READABLE="${RECORDED##*/}"
fi

# yt_sprint_verdict <verdict> -- emit EXACTLY ONE verdict and stop. Every arm
# below routes through it, so no path can emit two verdict lines and leave a
# reader to pick the one they wanted.
yt_sprint_verdict() {
  yt_emit sprint_verdict "$1"
  yt_emit issue_readable "$ISSUE_READABLE"
  exit "$YT_EXIT_OK"
}

TEMPLATE="$(yt_config_get '.sprint_query')" || TEMPLATE=""
if [[ -z "$TEMPLATE" ]]; then
  yt_report syncyt.sprintcheck.query_unconfigured \
    "no 'sprint_query' in $(yt_config_path), so there is no query to run -- this instance has no openSprints() analog and the membership predicate is adopter-specific, so it is never guessed. The sprint state is UNKNOWN, which is inconclusive rather than a block"
  yt_sprint_verdict inconclusive
fi
QUERY="${TEMPLATE//\{key\}/$ISSUE_READABLE}"
ENCODED="$(jq -rn --arg q "$QUERY" '$q|@uri' 2>/dev/null)" || ENCODED=""
if [[ -z "$ENCODED" ]]; then
  yt_report syncyt.sprintcheck.query_unconfigured \
    "the sprint query for $ISSUE_READABLE could not be encoded -- the sprint state is UNKNOWN, never assumed"
  yt_sprint_verdict inconclusive
fi

if ! yt_rest GET "/api/issues?query=$ENCODED&fields=id,idReadable&\$top=1"; then
  yt_report syncyt.sprintcheck.transport_unreachable \
    "GET /api/issues could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the sprint state is UNKNOWN, never assumed"
  yt_sprint_verdict inconclusive
fi

if yt_http_ok; then
  # The answer is an ARRAY. A non-array body is a shape this script does not
  # understand, which is a known-unknown and not an emptiness.
  MATCHES="$(printf '%s' "$YT_HTTP_BODY" | jq -r 'if type=="array" then length else "?" end' 2>/dev/null)" \
    || MATCHES="?"
  case "$MATCHES" in
    0) yt_report syncyt.sprintcheck.not_in_sprint \
         "$ISSUE_READABLE exists and the sprint query matched nothing -- it is in no sprint the query names"
       yt_sprint_verdict not-in-sprint ;;
    ''|*[!0-9]*)
       yt_report syncyt.sprintcheck.shape_unrecognized \
         "the sprint query returned HTTP $YT_HTTP_STATUS with a body this adapter cannot read as a result array -- the sprint state is UNKNOWN, never assumed" \
       ; yt_sprint_verdict inconclusive ;;
    *) yt_report syncyt.sprintcheck.in_sprint \
         "$ISSUE_READABLE matched the sprint query ($MATCHES result(s))"
       yt_sprint_verdict in-sprint ;;
  esac
fi

# A 400 here means the instance does not know that id at all -- reporting it as
# `not-in-sprint` would BLOCK /cadence-implement on a ticket that simply is not in the
# tracker, which is precisely the case the guard's fallback exists for.
if [[ "${YT_HTTP_STATUS:-}" == "400" ]]; then
  yt_report syncyt.sprintcheck.nonexistent_key \
    "the sprint query for $ISSUE_READABLE returned HTTP 400 -- on this instance that means the id is not one it knows, NOT that the ticket is out of sprint. Inconclusive, never not-in-sprint. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
else
  yt_report syncyt.sprintcheck.rejected \
    "the sprint query returned HTTP ${YT_HTTP_STATUS:-} -- the sprint state is UNKNOWN, never assumed. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
fi
yt_sprint_verdict inconclusive
