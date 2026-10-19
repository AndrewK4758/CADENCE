#!/usr/bin/env bash
#
# yt-reserve.sh -- reserve an id from YouTrack (tracker-first origination).
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: when `CADENCE_ORG.md`
# #id-allocation-binding binds id allocation to the tracker, YOUTRACK is the
# numbering authority -- an id is reserved from the instance BEFORE any repo
# artifact is created, and is never minted from the local `specs/` sequence. The
# id the instance assigns is authoritative; a computed or guessed one is never
# used, so a failed reservation STOPS rather than inventing a number.
#
# Upstream: /cadence-triage, through the orchestrator's `reserve` target.
# Downstream: `GET /api/admin/projects` (the project key -> its internal id) and
#   ONE `POST /api/issues` -- the only write this script performs.
# Spec: archive/BTG-176/spec.md (Script inventory -- yt-reserve.sh) ;
#   youtrack-scripts.md ; test-plan.md R-7.
#
# Contract (three channels):
#   args   : --summary <text> [--type <repo-type>]
#   stdout : issue_id=<2-NNNN>  issue_readable=<KEY-N>  youtrack_url=<url>
#   stderr : syncyt.reserve.* reported conditions
#   exit   : 0 ok / 1 rejected / 2 usage / 3 transport / 4 config HALT
#
# It writes NOTHING to the repository: the pairing is the CALLER's duty, and the
# obligation is declared here so the caller can discharge it.
#
# NO PLACEHOLDER TYPE IS INVENTED, and that is a DIVERGENCE from the sibling
# (AC-6 divergence 6), rather than an omission. Jira REQUIRES an issuetype on create, so
# `jira-reserve.sh` has to supply a declared placeholder and announce it
# (BTG-173). This instance does not: a create carrying only `project.id` and
# `summary` answers 200 (OBSERVED, spec sidecar 2 A/D), and the issue takes the
# project's own default Type. So an untyped ticket is reserved untyped -- the
# repo asserts no type, and neither does this write. `--type`, when supplied,
# resolves through the config's issue_type_map like every other mapped value.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

SUMMARY=""; TICKET_TYPE=""; PREFIX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary|--type)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.reserve.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --summary) SUMMARY="$2" ;;
        --type)    TICKET_TYPE="$2" ;;
      esac
      shift 2 ;;
    # BTG-179: the prefix the operator SELECTED, which on a multi-binding repo
    # is what decides the project this id is reserved from. Optional: a
    # single-binding repo has nothing to select.
    --prefix)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.reserve.usage \
        "--prefix requires a value, but the argument list ends there"
      PREFIX="$2"; shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.reserve.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$SUMMARY" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.reserve.usage "--summary <text> is required"

yt_config_require
BASE_URL="$(yt_env_value base_url)" || exit "$YT_EXIT_CONFIG"
# BTG-179: a reservation is CREATING the ticket, so there is no ticket id to
# derive a prefix from -- the prefix the operator selected is passed in.
PROJECT_KEY="$(yt_project_key ${PREFIX:+--prefix} ${PREFIX:-})" || exit "$YT_EXIT_CONFIG"
if [[ -z "$BASE_URL" || -z "$PROJECT_KEY" ]]; then
  yt_halt "$YT_EXIT_USAGE" syncyt.reserve.env_absent \
    "the base-URL and project-key environment variables must both be set -- no request was issued and no id was reserved"
fi

# --- the project key -> the project id -------------------------------------
# The create body takes `project.id`, an INTERNAL id (OBSERVED), so the key has
# to be resolved first. `query=` is a SEARCH, so the shortName is matched
# EXACTLY: a substring hit on another project's name would reserve the id in the
# wrong project and report success.
if ! yt_rest GET "/api/admin/projects?fields=id,shortName,name,archived&query=$PROJECT_KEY"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "GET /api/admin/projects could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- no id reserved; never guess one"
fi
if [[ "$YT_HTTP_STATUS" == "401" || "$YT_HTTP_STATUS" == "403" ]]; then
  # A 401/403 HERE is not a bad project key, and reporting `project_unresolved`
  # would send the operator to correct the project-key variable, which is
  # correct (BTG-176 DEC-076). Project resolution is the ONE step this adapter
  # performs outside the issue operations a project-member token covers -- it
  # reads /api/admin/projects -- so a refusal at this call is most likely the
  # credential lacking that read. That is offered as a POSSIBILITY, not a
  # diagnosis: the instance does not say which of the two it means, and whether
  # the endpoint requires an administrative role has NOT been verified against a
  # second credential. Both candidates are named so the operator checks the
  # right two things instead of the wrong one.
  #
  # The token variable is named by RESOLVING it from the config's env block, the
  # same way the project-key variable is resolved above. Spelling either name
  # here would re-hardcode the thing this adapter de-hardcoded -- and would trip
  # btg-176-rest-foundation.test.sh S-11.1, which is how the first draft of this
  # arm was caught.
  YT_TOKEN_VAR="$(yt_config_map env token)" || YT_TOKEN_VAR=""
  yt_halt "$YT_EXIT_FAIL" syncyt.config.project_read_refused \
    "GET /api/admin/projects returned HTTP $YT_HTTP_STATUS while resolving '$PROJECT_KEY' -- no id reserved; an id is NEVER guessed. This is a REFUSAL, not a missing project: the instance was reached and rejected the credential for this read. Check that the token${YT_TOKEN_VAR:+ in \$$YT_TOKEN_VAR} is valid and unexpired, and that its owner may read /api/admin/projects -- the adapter has no other route to the project id. See the Permissions section of the skill body"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.config.project_unresolved \
    "GET /api/admin/projects returned HTTP $YT_HTTP_STATUS while resolving '$PROJECT_KEY' -- no id reserved"
fi
PROJECT_ID="$(printf '%s' "$YT_HTTP_BODY" \
  | jq -r --arg k "$PROJECT_KEY" \
      'if type=="array" then (map(select(.shortName == $k)) | .[0].id // empty) else empty end' 2>/dev/null)" \
  || PROJECT_ID=""
[[ -n "$PROJECT_ID" ]] || yt_halt "$YT_EXIT_FAIL" syncyt.config.project_unresolved \
  "the project key '$PROJECT_KEY' matched no project on this instance (HTTP $YT_HTTP_STATUS) -- an empty result is a NOT-FOUND, never an empty success; no id reserved"

# --- stage the body ---------------------------------------------------------
BODY="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.reserve.scratch_unavailable \
  "no scratch file could be staged for the reservation body -- reserving NO id; an id is never guessed"
trap 'rm -f "$BODY"' EXIT

if [[ -n "$TICKET_TYPE" ]]; then
  TYPE_VALUE="$(yt_config_map issue_type_map "$TICKET_TYPE")" || exit "$YT_EXIT_CONFIG"
  yt_build_body "$BODY" syncyt.reserve.body_unbuildable "the reservation body for \"$SUMMARY\"" \
    -n --arg p "$PROJECT_ID" --arg s "$SUMMARY" --arg v "$TYPE_VALUE" \
    '{project:{id:$p},summary:$s,customFields:[{name:"Type","$type":"SingleEnumIssueCustomField",value:{name:$v}}]}' \
    || exit "$YT_EXIT_FAIL"
else
  # No type was asserted, so none is written. See the header: this instance does
  # not require one, so there is no placeholder to declare and nothing to
  # un-declare later when /cadence-triage classifies the ticket.
  yt_report syncyt.reserve.type_unasserted \
    "no --type was supplied, so this reservation carries NO Type and the issue takes the project's own default -- the repo asserts no type for this ticket. Run /cadence-triage on the id and the next sync projects the classified type"
  yt_build_body "$BODY" syncyt.reserve.body_unbuildable "the reservation body for \"$SUMMARY\"" \
    -n --arg p "$PROJECT_ID" --arg s "$SUMMARY" '{project:{id:$p},summary:$s}' \
    || exit "$YT_EXIT_FAIL"
fi

# DECLARE THE PAIRING BEFORE THE TRACKER IS CONTACTED (record-before-contact,
# extending the id-allocation binding's AUDIT rule -- BTG-151). This script
# writes nothing to the repo by contract, so the pairing is an obligation on the
# CALLER; declaring it before the write is what lets a caller abort before an
# orphan exists rather than learn of the duty once one does. The canonical
# statement of the rule lives in `CADENCE_ORG.md` #id-allocation-binding
# (Reservation pairing) -- this line CITES it and never restates it.
yt_report syncyt.reserve.pairing_obligation \
  "this reservation MUST be paired, in this same governed operation, with the problem.md and the metadata.yaml artifacts that the allocated id owns under specs/ (CADENCE_ORG.md #id-allocation-binding, Reservation pairing); an unpaired reservation is idalloc.reserve.unpaired_artifact_creation"

if ! yt_rest POST "/api/issues?fields=id,idReadable" "$BODY"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "POST /api/issues could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- no id reserved; never guess one"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.reserve.rejected \
    "POST /api/issues returned HTTP $YT_HTTP_STATUS -- no id reserved; never guess one. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi

# This instance answers a create with 200 (not 201) and returns BOTH ids. The
# readable one is the id a human uses; the internal one is what every link body
# needs. Neither is computed.
ISSUE_READABLE="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.idReadable // empty' 2>/dev/null)"
ISSUE_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)"
[[ -n "$ISSUE_READABLE" ]] || yt_halt "$YT_EXIT_FAIL" syncyt.reserve.rejected \
  "the reservation response carried no readable id -- never assume the id you computed"

yt_report syncyt.reserve.reserved \
  "$ISSUE_READABLE reserved from $PROJECT_KEY (authoritative -- assigned by the instance); UNPAIRED until the allocated id owns both of the artifacts named in the obligation above"
yt_emit issue_id "$ISSUE_ID"
yt_emit issue_readable "$ISSUE_READABLE"
yt_emit youtrack_url "${BASE_URL%/}/issue/$ISSUE_READABLE"
exit "$YT_EXIT_OK"
