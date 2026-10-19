#!/usr/bin/env bash
#
# jira-reserve.sh -- reserve a ticket key from Jira (tracker-first origination).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: when `CADENCE_ORG.md` §10 binds
# id allocation to the tracker, JIRA is the numbering authority -- a key is
# reserved from Jira BEFORE any repo artifact is created, and never minted from
# the local `specs/` sequence. The key Jira assigns is authoritative; a computed
# or guessed key is never used, so a failed reservation stops rather than
# inventing a number.
#
# Upstream: invoked by /cadence-triage (through the orchestrator) for description-sourced
#   intake.
# Downstream: `POST $JIRA_BASE_URL/rest/api/2/issue` -- the ONE write this script
#   performs.
# Spec: archive/BTG-075/spec.md (script inventory) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --summary <text> [--type <repo-type>] [--prefix <PREFIX>]
#   stdout : issue_key=<KEY>  jira_url=<url>
#   stderr : syncjs.reserve.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# Writes nothing to the repository (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

SUMMARY=""; PREFIX=""
TICKET_TYPE="tech-debt"; TYPE_DEFAULTED=yes   # BTG-173: declared below, never applied silently
while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) js_argv_pair syncjs.reserve.usage "$@"; SUMMARY="$2"; shift 2 ;;
    --type)    js_argv_pair syncjs.reserve.usage "$@"; TICKET_TYPE="$2"; TYPE_DEFAULTED=no; shift 2 ;;
    --prefix)  js_argv_pair syncjs.reserve.usage "$@"; PREFIX="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.reserve.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$SUMMARY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.reserve.usage "--summary <text> is required"

js_config_require
BASE_URL="$(js_env_value base_url)"
PROJECT_KEY="$(js_project_key ${PREFIX:+--prefix} ${PREFIX:-})" || exit "$JS_EXIT_CONFIG"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.reserve.env_absent "the base-URL environment variable must be set"

ISSUE_TYPE="$(js_config_map issue_type_map "$TICKET_TYPE")" \
  || js_halt "$JS_EXIT_CONFIG" syncjs.config.marker_unresolved \
       "no issue_type_map entry for type='$TICKET_TYPE'"

BODY_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.reserve.scratch_unavailable "no scratch file could be staged for the reservation body -- reserving NO key; a key is never guessed"
trap 'rm -f "$BODY_FILE"' EXIT
# A bodyless POST here reserves nothing, or a key with no fields, and the run then
# blames the instance for a body this adapter built wrong (BTG-084).
js_build_body "$BODY_FILE" syncjs.reserve.body_unbuildable "the reservation body for \"$SUMMARY\"" \
  -n --arg project "$PROJECT_KEY" --arg summary "$SUMMARY" --arg itype "$ISSUE_TYPE" \
  '{fields: {project: {key: $project}, summary: $summary, issuetype: {name: $itype}}}' || exit "$JS_EXIT_FAIL"

# DECLARE the allocation pairing BEFORE the tracker is contacted (record-before-
# contact, extending the §10 AUDIT rule). This script writes nothing to the repo
# by contract, so the pairing is an obligation on the CALLER; declaring it first
# is what lets a caller abort before an orphan exists rather than learn of the
# duty once one does. The canonical statement of the rule lives in
# `CADENCE_ORG.md` #id-allocation-binding (Reservation pairing) -- this line
# CITES it and never restates it. Deliberately sited BELOW the body build: four
# live citers name `jira-reserve.sh:56-58` by line number, so nothing is
# inserted above it (BTG-151 spec.md, Binding placement constraint).
js_report syncjs.reserve.pairing_obligation \
  "this reservation MUST be paired with specs/<id>/problem.md + metadata.yaml in this same governed operation (CADENCE_ORG.md #id-allocation-binding, Reservation pairing); an unpaired reservation is idalloc.reserve.unpaired_artifact_creation"

# BTG-173: DECLARE the placeholder rather than applying it silently. `--file-only`
# files without classifying (cadence-triage.md F3 writes no `type:`), so this create is the
# ONE issue-type write a filed ticket gets -- and before this line it happened with
# no record at all, leaving every filed ticket rendered `Task` in Jira while the
# repo asserted nothing. Jira REQUIRES an issuetype on create, so some placeholder
# is unavoidable; the reconciliation AC-4 asks for is to make it DECLARED, not to
# move it into config (DEC-003) or remove it (which would move the failure from
# projection to allocation). This is the CREATE half of the doctrine
# jira-type-lib.sh states on the UPDATE half: an untyped ticket receives a declared
# placeholder at create, and is never re-typed by an update until classification
# assigns a real one. Reported only when the default was actually taken -- an
# explicit `--type` defaulted nothing, so it declares nothing.
[[ "$TYPE_DEFAULTED" == "yes" ]] && js_report syncjs.reserve.type_placeholder \
  "no --type was supplied, so this reservation is created at the DECLARED PLACEHOLDER type '$TICKET_TYPE' -- the repo asserts no type for this ticket. The placeholder is a create-time necessity (Jira requires an issuetype on create), NEVER a classification; run /cadence-triage on the id to assign the real type and the next sync projects it. This write is the ONLY one that will set a type until then"

if ! js_rest POST "/rest/api/2/issue" "$BODY_FILE"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "POST /rest/api/2/issue could not reach ${BASE_URL%/} -- no key reserved; never guess one"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.reserve.rejected \
    "POST /rest/api/2/issue returned HTTP $JS_HTTP_STATUS -- no key reserved; never guess one"
fi

# Direct REST v2 returns the reserved key at the TOP level (`.key`).
ISSUE_KEY="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.key // empty' 2>/dev/null)"
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_FAIL" syncjs.reserve.rejected \
  "the reservation response carried no issue key -- never assume the key you computed"

js_report syncjs.reserve.reserved "$ISSUE_KEY reserved from $PROJECT_KEY (authoritative -- assigned by Jira); UNPAIRED until specs/$ISSUE_KEY/problem.md + specs/$ISSUE_KEY/metadata.yaml exist"
js_emit issue_key "$ISSUE_KEY"
js_emit jira_url "${BASE_URL%/}/browse/$ISSUE_KEY"
exit "$JS_EXIT_OK"
