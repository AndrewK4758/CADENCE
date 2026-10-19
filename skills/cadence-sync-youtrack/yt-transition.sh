#!/usr/bin/env bash
#
# yt-transition.sh -- project the ticket's repo status onto the issue's state
# field.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariants relied on from outside this boundary, OBSERVED live against
# v2026.1 build 13162 (spec sidecar 2 C/D) rather than carried over from the
# sibling adapter:
#   - the state field is a PLAIN custom field over ONE project-wide bundle of 16
#     values, not a per-issue-type workflow graph (AC-6 divergence 4). There is
#     no transition graph and no intermediate hop to walk, so BTG-102's
#     `global_transitions` -- the transition ids a hop is authorised by -- has
#     no analog here. THE GRAPH IS THE WHOLE OF THAT DIVERGENCE: the per-Type
#     `status_state_map` this script resolves is NOT part of it, and the shared
#     bundle is a shared VALUE SET, not a shared policy (see the (Type, status)
#     note below, §7 row 4, and DEC-077). The script is still named for the
#     operation it performs in the sequence, not for a graph walk;
#   - it is written like any other single-value field: `POST /api/issues/<id>`
#     with a `customFields` member whose value is an object carrying `name`;
#   - a value the project's bundle does not carry is rejected with HTTP 400.
#
# Upstream: the /cadence-sync-youtrack orchestrator, after yt-write-issue.sh has
#   established the issue; `--issue` is that step's own stdout.
# Downstream: ONE REST POST plus AC-12's read-back GET against the adopter's
#   YouTrack instance. It reads `metadata.yaml` and NEVER writes it.
# Spec: archive/BTG-176/spec.md (Proposed Design -- Script inventory, Endpoint
#   map) ; youtrack-scripts.md.
#
# Contract (three channels):
#   args   : --ticket <id> --issue <internal-or-readable-id>
#   stdout : state_result=applied  fields_verified=<n>
#   stderr : syncyt.write.* / syncyt.schema.* reported conditions
#   exit   : 0 ok / 1 rejected / 2 usage / 3 transport / 4 config HALT

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--issue)
      # Guard the pair BEFORE the `shift 2` that consumes it -- see the same
      # guard in yt-resolve.sh for why an unguarded `shift 2` spins forever.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.transition.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket) TICKET="$2" ;;
        --issue)  ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.transition.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.transition.usage "--ticket <id> is required"
[[ -n "$ISSUE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.transition.usage \
  "--issue <id> is required -- this step never creates an issue"

yt_config_require
yt_metadata_load "$TICKET"

# The bundle value is resolved from the config, never from a literal: an
# unmapped value is a guaranteed HTTP 400 on this instance, and guessing one
# would project an ungoverned decision.
#
# RESOLVED BY (Type, status), NOT BY status ALONE -- a correction, and the parity
# this adapter owed its sibling (BTG-176 DEC-077). `jira-transition.sh` resolves
# `js_config_map2 status_workflow_map "$ISSUE_TYPE" "$STATUS"`; this resolved
# `status_state_map "$STATUS"` and Type never entered the lookup, so a Task and a
# Bug at the same lifecycle stage projected onto the SAME board state while the
# sibling gave them different ones -- the same event, divergent boards, with
# nothing saying so. The justification for the flat shape ("no per-type variation
# to map") was disproved live: this instance imposes no Type->State coupling, so
# the per-type map encodes POLICY and YouTrack can express it exactly.
#
# THE TYPE COMES FROM metadata.yaml, RESOLVED THROUGH `issue_type_map` -- the same
# resolution `yt-write-issue.sh` performs to WRITE the Type. It is not re-read
# from the instance: metadata.yaml is the source of truth and YouTrack is the
# projection, so reading the Type back would let a hand-edit on the board change
# which policy the repo's own lifecycle projects through. The sibling reads it
# from the issue because Jira's workflow SCHEME is bound to the issue's actual
# type; there is no scheme here, so there is nothing on the instance to agree with.
STATE_FIELD=State
REPO_TYPE="$(yt_metadata_get '.type')"
ISSUE_TYPE="$(yt_config_map issue_type_map "$REPO_TYPE")" || exit "$YT_EXIT_CONFIG"
# FAIL LOUD on a pair the map does not carry: no flat fallback, no default Type,
# no guessed State. yt_config_map2 reports BOTH keys.
STATE_VALUE="$(yt_config_map2 status_state_map "$ISSUE_TYPE" "$(yt_metadata_get '.status')")" \
  || exit "$YT_EXIT_CONFIG"

BODY="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.transition.scratch_unavailable \
  "could not stage a request body (no scratch file) -- issuing no write"
trap 'rm -f "$BODY"' EXIT

yt_build_body "$BODY" syncyt.transition.body_unbuildable "the state body for $TICKET" \
  -n --arg n "$STATE_FIELD" --arg v "$STATE_VALUE" --arg t StateIssueCustomField \
  '{customFields:[{name:$n,value:{name:$v},"$type":$t}]}' \
  || exit "$YT_EXIT_FAIL"

TARGET="/api/issues/$ISSUE?fields=id,idReadable"
if ! yt_rest POST "$TARGET" "$BODY"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "POST $TARGET could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
fi
if ! yt_http_ok; then
  # An ATTRIBUTED condition when the rejection is a recognized class, the
  # generic one otherwise -- exactly one of the two, never both, so an operator
  # reconciles one audit line per failure. Nothing is re-read and nothing is
  # repaired: a rejected write on this instance applies nothing at all
  # (OBSERVED, sidecar 2 G), so there is no partial state to compensate for.
  yt_classify_rejection "$STATE_FIELD" "$STATE_VALUE" \
      "status_state_map.$ISSUE_TYPE.$(yt_metadata_get '.status')" \
    || yt_report syncyt.transition.rest_rejected \
         "POST $TARGET returned HTTP $YT_HTTP_STATUS -- the state was not set. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
  exit "$YT_EXIT_FAIL"
fi

# The 2xx above says the request was accepted, not that the value was applied
# (AC-12). The intended value is re-stated from this step's OWN intent.
yt_readback "$ISSUE" "$STATE_FIELD" "$STATE_VALUE"; VERIFIED=$?

yt_emit state_result applied
yt_emit fields_verified "$YT_FIELDS_VERIFIED"
[[ "$VERIFIED" -eq 0 ]] || exit "$YT_EXIT_FAIL"
exit "$YT_EXIT_OK"
