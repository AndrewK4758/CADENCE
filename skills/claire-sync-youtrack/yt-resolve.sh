#!/usr/bin/env bash
#
# yt-resolve.sh -- resolve the project key to a project id, and decide CREATE vs
# UPDATE for the ticket.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: this script is where the whole
# sync's idempotency is decided. A duplicate issue is the one effect that cannot
# be undone -- work items are immutable, links are additive, fields are
# set-to-desired, but a second issue splits the ticket's history in two and the
# repo can only ever point at one of them.
#
# THE EMPTY-ARRAY RULE, which is why this script exists rather than being folded
# into the write. This instance answers a project query for a key that matches
# NOTHING with **HTTP 200 and `[]`** -- not a 404 (OBSERVED, spec sidecar 2 §I).
# So a 2xx is not evidence of resolution here, and a caller that trusted the
# status would proceed with an unset project id and POST an issue with no
# project. The array is therefore inspected, and an empty one is a NOT-FOUND that
# halts.
#
# Upstream: the first ticket-scoped step of the /claire-sync-youtrack sequence, after
#   yt-connect.sh.
# Downstream: ONE REST GET against `/api/admin/projects`. It reads
#   `metadata.yaml` and NEVER writes it.
# Spec: archive/BTG-176/spec.md (Proposed Design -- Endpoint map) ;
#   youtrack-scripts.md.
#
# Contract (three channels):
#   args   : --ticket <id>
#   stdout : project_id=<0-NNN>  project_key=<KEY>
#            mode=update|create  ; issue=<internal-or-readable-id> when resolved
#   stderr : syncyt.resolve.* / syncyt.config.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport / 4 config HALT

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)
      # Guard the pair BEFORE the `shift 2` that consumes it: with exactly one
      # argument left, `shift 2` fails and shifts NOTHING, so this loop never
      # advances and the script spins at 100% CPU with no output and no exit --
      # the one failure mode that is neither loud nor recoverable.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.resolve.usage \
        "--ticket requires a value, but the argument list ends there"
      TICKET="$2"; shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.resolve.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.resolve.usage "--ticket <id> is required"

yt_config_require
yt_metadata_load "$TICKET"

# BTG-179: the project key resolves through the BINDING first (this ticket's
# prefix's §9 row, then §9's scalar line) and the environment only as the
# deprecated last resort. The resolver REPORTS and RETURNS rather than exiting,
# because an exit inside `$(...)` would leave only the subshell and hand this
# script an empty key.
PROJECT_KEY="$(yt_project_key "$TICKET")" || exit "$YT_EXIT_CONFIG"
if [[ -z "$PROJECT_KEY" ]]; then
  yt_halt "$YT_EXIT_USAGE" syncyt.connect.env_absent \
    "no project key resolved for $TICKET -- no request was issued"
fi

# --- (1) the project key -> the project id ---------------------------------
if ! yt_rest GET "/api/admin/projects?fields=id,shortName,name,archived&query=$PROJECT_KEY"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "GET /api/admin/projects could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
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
    "GET /api/admin/projects returned HTTP $YT_HTTP_STATUS while resolving '$PROJECT_KEY'. This is a REFUSAL, not a missing project: the instance was reached and rejected the credential for this read. Check that the token${YT_TOKEN_VAR:+ in \$$YT_TOKEN_VAR} is valid and unexpired, and that its owner may read /api/admin/projects -- the adapter has no other route to the project id. See the Permissions section of the skill body"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.config.project_unresolved \
    "GET /api/admin/projects returned HTTP $YT_HTTP_STATUS while resolving '$PROJECT_KEY'"
fi

# `query=` is a SEARCH, so a match on some other project's name would be a
# different project silently. The shortName is matched EXACTLY, and the id is
# taken only from that member. An empty result -- the observed shape for a key
# that matches nothing -- yields nothing here and halts below.
PROJECT_ID="$(printf '%s' "$YT_HTTP_BODY" \
  | jq -r --arg k "$PROJECT_KEY" \
      'if type=="array" then (map(select(.shortName == $k)) | .[0].id // empty) else empty end' \
      2>/dev/null)" || PROJECT_ID=""

if [[ -z "$PROJECT_ID" ]]; then
  # HTTP 200 with `[]` is the OBSERVED answer for a key that matches no project.
  # It is a NOT-FOUND, not an empty success: proceeding would POST an issue with
  # no project, or with whatever a later step guessed.
  yt_halt "$YT_EXIT_FAIL" syncyt.config.project_unresolved \
    "the project key '$PROJECT_KEY' matched no project on this instance -- the query returned HTTP $YT_HTTP_STATUS with $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-120). An empty result is a NOT-FOUND, never an empty success; refusing to proceed with an unresolved project"
fi

ARCHIVED="$(printf '%s' "$YT_HTTP_BODY" \
  | jq -r --arg k "$PROJECT_KEY" 'map(select(.shortName == $k)) | .[0].archived // false' 2>/dev/null)"
if [[ "$ARCHIVED" == "true" ]]; then
  yt_halt "$YT_EXIT_FAIL" syncyt.config.project_unresolved \
    "the project key '$PROJECT_KEY' resolves to $PROJECT_ID, which is ARCHIVED -- refusing to project into an archived project"
fi

yt_emit project_key "$PROJECT_KEY"
yt_emit project_id "$PROJECT_ID"

# --- (2) repo state decides create vs update -------------------------------
# A populated `youtrack_url` is the authoritative answer and costs no call. A
# COMMENTED-OUT key is absent, not populated, and a PRESENT-BUT-EMPTY one means
# "never projected" -- the shipped metadata template ships it empty, and reading
# that as populated would resolve every brand-new ticket to an empty issue id.
# Named RECORDED_URL, not YOUTRACK_URL: in this adapter a YOUTRACK_-prefixed
# identifier is an ENVIRONMENT VARIABLE NAME, and this is a repo-owned value
# read out of metadata.yaml.
RECORDED_URL="$(yt_metadata_get '.youtrack_url')"
if [[ -n "$RECORDED_URL" ]]; then
  ISSUE="${RECORDED_URL##*/}"
  if [[ -z "$ISSUE" || "$ISSUE" == "$RECORDED_URL" ]]; then
    yt_halt "$YT_EXIT_FAIL" syncyt.resolve.url_unparseable \
      "youtrack_url='$RECORDED_URL' does not end in an issue id -- refusing to guess which issue this ticket projects to"
  fi
  yt_report syncyt.resolve.from_metadata "$TICKET resolves to $ISSUE from its recorded youtrack_url"
  yt_emit mode update
  yt_emit issue "$ISSUE"
  exit "$YT_EXIT_OK"
fi

# No recorded URL -- and that is the END of the enquiry. No recovery search is
# performed: the recorded `youtrack_url` is the ONLY identity mapping this
# adapter has. The residual is REPORTED rather than left for an operator to
# infer, because on the one path where a prior run created the issue and then
# halted before the end-of-operation metadata write, this branch mints a SECOND
# issue -- the one effect nothing downstream can undo.
yt_report syncyt.resolve.create \
  "$TICKET has no recorded youtrack_url -- taking the CREATE path. If a prior run created this ticket's issue and halted before the metadata write, this run creates a DUPLICATE; check the project by hand before re-running a sync that halted mid-sequence"
yt_emit mode create
exit "$YT_EXIT_OK"
