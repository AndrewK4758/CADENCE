#!/usr/bin/env bash
#
# jira-assign.sh -- reconcile the Jira assignee to the repo's spec `status`.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (BTG-014): assignment
# reconciliation is **opt-in** and **never a gate** on the surrounding sync. An
# instance that will not let the PAT owner be assigned -- or that keeps the
# assignee off the edit screen, or answers 403 -- must not cost the operator the
# status transition and the description projection that ran correctly. So EVERY
# rejection here exits 0 and reports itself as a named `assign_result=` payload:
# the refusal is loud, but it is not a halt.
#
# The actor identity is the credential's own, resolved from Jira by
# jira-connect.sh and passed in with `--self`. It is NEVER read from artifact
# content and never guessed or hardcoded -- an unresolved identity means the
# self-assignment is skipped and reported, not approximated.
#
# Upstream: invoked by the /cadence-sync-jira orchestrator, immediately AFTER the
#   status transition, so a workflow automation firing during the transition
#   cannot overwrite the repo-intended assignee -- this write is the last word.
# Downstream: `PUT $JIRA_BASE_URL/rest/api/2/issue/{key}/assignee`.
# Spec: archive/BTG-075/spec.md (AC-2 best-effort class) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> --issue-key <KEY> [--self <username>]
#   stdout : assign_result=self|unassigned|no-change|unknown-status|disabled|rejected
#   stderr : syncjs.assign.* reported conditions
#   exit   : 0 always, except a usage (2) or config (4) failure -- those are
#            breakage, not a sanctioned refusal, and are never swallowed
#
# This script READS metadata.yaml and NEVER writes it (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

TICKET=""
ISSUE_KEY=""
SELF_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)    js_argv_pair syncjs.assign.usage "$@"; TICKET="$2"; shift 2 ;;
    --issue-key) js_argv_pair syncjs.assign.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    --self)      js_argv_pair syncjs.assign.usage "$@"; SELF_NAME="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.assign.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET"    ]] || js_halt "$JS_EXIT_USAGE" syncjs.assign.usage "--ticket <id> is required"
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.assign.usage "--issue-key <KEY> is required"

js_config_require

# --- the OPT-IN gate (absent => DISABLED, BTG-014) --------------------------
# The inverse polarity of the worklog/AC opt-outs, and deliberately so: a fork
# that predates this feature must never be silently opted into overwriting a
# manually-set assignee on upgrade. Only an explicit `true` proceeds.
js_config_toggle assignment_reconciliation_enabled
TOGGLE_RC=$?
if [[ "$TOGGLE_RC" -eq "$JS_EXIT_CONFIG" ]]; then exit "$JS_EXIT_CONFIG"; fi
if [[ "$TOGGLE_RC" -ne 0 ]]; then
  js_report syncjs.assign.disabled "assignment reconciliation disabled by policy"
  js_emit assign_result disabled
  exit "$JS_EXIT_OK"
fi

js_metadata_load "$TICKET"

# An Epic's assignee is HUMAN-MANAGED (BTG-040), like its status and its Epic
# Status field: skip BEFORE any call, so a run cannot even accidentally overwrite
# whoever a human put there. jira-transition.sh skips an Epic for the same reason;
# until now this script did not, and every sync reassigned an Epic.
if [[ "$(js_metadata_get '.type')" == "epic" ]]; then
  js_report syncjs.assign.skipped_epic \
    "$TICKET is an Epic -- its assignee is managed manually by humans and is never reconciled by this sync"
  js_emit assign_result skipped-epic
  exit "$JS_EXIT_OK"
fi

STATUS="$(js_metadata_get '.status')"
[[ -n "$STATUS" ]] || {
  js_report syncjs.assign.unknown_status "the ticket carries no status -- no assignment action is guessed"
  js_emit assign_result unknown-status
  exit "$JS_EXIT_OK"
}

# The action comes from the config's assignment_map. A status OUTSIDE the map is
# REPORTED, never guessed: inventing an action would either strip a human's
# assignee or claim a ticket nobody asked this credential to own.
if ! ACTION="$(js_config_map assignment_map "$STATUS" 2>/dev/null)"; then
  js_report syncjs.assign.unknown_status \
    "status '$STATUS' is not in the config's assignment_map -- no assignment call is made and no action is guessed"
  js_emit assign_result unknown-status
  exit "$JS_EXIT_OK"
fi

case "$ACTION" in
  no-change)
    js_report syncjs.assign.skipped_no_change "status '$STATUS' maps to no-change -- no assignment call made"
    js_emit assign_result no-change
    exit "$JS_EXIT_OK" ;;
  self)
    if [[ -z "$SELF_NAME" ]]; then
      js_report syncjs.assign.rejected \
        "status '$STATUS' maps to self but no self identity was resolved (--self empty) -- skipping; a name is never guessed or hardcoded"
      js_emit assign_result rejected
      exit "$JS_EXIT_OK"
    fi
    # BOTH questions, as everywhere else (BTG-084). This build is CAPTURED INTO A
    # VARIABLE rather than redirected to a file, so `js_build_body` does not fit
    # and the AC-2 gate cannot see it -- which is exactly how it survived four
    # inventories. `set -u` does NOT trip on a set-but-EMPTY variable, so a failed
    # jq left ASSIGNEE_JSON="", the later `printf` wrote a ZERO-LENGTH body, and
    # js_rest SENT it (it omits --data-binary only for an empty PATH, not an empty
    # FILE). Observed against a test stub: a 0-byte body on the wire under
    # `applied`. Whether a live Jira reads that as a field CLEAR or rejects it is
    # unverified; either way the run reported a write that did not happen.
    # Best-effort class: skip and report, never halt.
    # NON-WHITESPACE, not merely non-empty: R-1's rule, and what js_build_body
    # does with `grep -q '[^[:space:]]'` at every other site. Emptiness alone let
    # a jq exiting 0 with three spaces send a 3-byte body under `applied`.
    if ! ASSIGNEE_JSON="$(jq -n --arg n "$SELF_NAME" '{name: $n}' 2>/dev/null)" \
       || [[ -z "${ASSIGNEE_JSON//[[:space:]]/}" ]]; then
      js_report syncjs.assign.body_unbuildable \
        "the assignee body for $ISSUE_KEY could not be built (jq exited non-zero, or produced nothing) -- issuing NO assignment call rather than the EMPTY body that would otherwise go out under a success report; assignment is best-effort, the sync continues"
      js_emit assign_result rejected
      exit "$JS_EXIT_OK"
    fi ;;
  unassigned)
    ASSIGNEE_JSON='{"name":null}' ;;
  *)
    js_report syncjs.assign.unknown_status \
      "assignment_map['$STATUS'] resolved to the unrecognized action '$ACTION' -- no assignment call is made"
    js_emit assign_result unknown-status
    exit "$JS_EXIT_OK" ;;
esac

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.assign.env_absent "the base-URL environment variable is unset"

BODY_FILE="$(mktemp 2>/dev/null)" || { js_report syncjs.assign.rejected "no scratch file could be staged for $ISSUE_KEY's assignee body -- issuing NO assignment call; assignment is best-effort, the sync continues"; js_emit assign_result rejected; exit "$JS_EXIT_OK"; }
trap 'rm -f "$BODY_FILE" 2>/dev/null' EXIT
printf '%s' "$ASSIGNEE_JSON" > "$BODY_FILE"

if ! js_rest PUT "/rest/api/2/issue/$ISSUE_KEY/assignee" "$BODY_FILE"; then
  js_report syncjs.assign.rejected \
    "PUT /rest/api/2/issue/$ISSUE_KEY/assignee could not reach ${BASE_URL%/} -- assignment is best-effort, the sync continues"
  js_emit assign_result rejected
  exit "$JS_EXIT_OK"
fi
if ! js_http_ok; then
  js_report syncjs.assign.rejected \
    "PUT /rest/api/2/issue/$ISSUE_KEY/assignee returned HTTP $JS_HTTP_STATUS: $JS_HTTP_BODY -- assignment is best-effort, the sync continues"
  js_emit assign_result rejected
  exit "$JS_EXIT_OK"
fi

case "$ACTION" in
  self)       js_report syncjs.assign.applied "assigned $ISSUE_KEY to the credential's own identity for status '$STATUS'" ;;
  unassigned) js_report syncjs.assign.applied "unassigned $ISSUE_KEY for status '$STATUS'" ;;
esac
js_emit assign_result "$ACTION"
exit "$JS_EXIT_OK"
