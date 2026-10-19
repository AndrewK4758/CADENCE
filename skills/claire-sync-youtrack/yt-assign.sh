#!/usr/bin/env bash
#
# yt-assign.sh -- reconcile the issue's Assignee to the repo's spec `status`.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariants relied on from outside this boundary, each OBSERVED live against
# v2026.1 build 13162 (spec sidecar 2 F) rather than carried over from the
# sibling adapter:
#   - `Assignee` is an ordinary custom field, written through the SAME
#     `POST /api/issues/<id>` the other fields use, with `$type`
#     `SingleUserIssueCustomField` and a value object carrying `login` (an `id`
#     is equally accepted);
#   - the write succeeds **iff** the target is in the PROJECT'S Assignee user
#     bundle. A user who exists in the directory but is not in that bundle is
#     rejected with HTTP 400 `{"error_description":"Value is not allowed",
#     "error_field":"value"}` -- a body naming NEITHER the field NOR the value;
#   - `value: null` CLEARS the field and answers 200.
#
# DEC-009, and it is the reason this script exists in this shape.
# `syncyt.assignee.unresolved` means "the target is not an ADMISSIBLE assignee on
# this project" -- NOT the MCP-era "an exact-match user lookup returned no user".
# The live probe found the target in the directory by login AND by id, and the
# write still failed, because the project's bundle did not contain them. An
# adapter that reported a lookup failure here would tell an operator to go and
# create a user who already exists.
#
# Upstream: the /claire-sync-youtrack orchestrator's `assignee` step (best-effort),
#   immediately after the state step, so a workflow reacting to the state change
#   cannot overwrite the repo-intended assignee -- this write is the last word.
#   `--issue` is the write step's own internal id; `--self` is the identity
#   yt-connect.sh resolved from the credential.
# Downstream: ONE `POST /api/issues/<id>` plus ONE confirmation GET against the
#   adopter's instance. It READS `metadata.yaml` and NEVER writes it.
# Spec: archive/BTG-176/spec.md (AC-13, Script inventory) ;
#   archive/BTG-176/spec-2-live-rest-observations.md SS F.
#
# Contract (three channels):
#   args   : --ticket <id> --issue <internal-id> [--self <login>]
#   stdout : assign_result=applied|no-change|unknown-status|disabled|rejected
#   stderr : syncyt.assign.* / syncyt.assignee.* reported conditions
#   exit   : 0 always, EXCEPT a usage (2) or config (4) failure -- those are
#            breakage rather than a sanctioned refusal and are never swallowed
#
# WHY EVERY REFUSAL EXITS 0. This step is best-effort, and the orchestrator halts
# the whole ticket on any non-zero exit whatever the step's class. An instance
# that will not accept this assignee must not cost the operator the description
# and the state transition that already landed -- so a refusal is LOUD on stderr,
# NAMED on stdout (`assign_result=rejected`, which the orchestrator records as a
# rejected step), and still exits 0.
#
# THE ACTOR IDENTITY IS THE CREDENTIAL'S OWN and arrives through `--self`. It is
# never read from artifact content, never guessed and never hardcoded: an
# unresolved identity skips the self-assignment and says so.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

ASSIGN_FIELD=Assignee
YT_USER_TYPE=SingleUserIssueCustomField
YT_ASSIGN_REPORTED=0

# yt_assign_report <condition> <detail...> -- report, and REMEMBER that something
# was said. The memory is what makes the seam below able to fire.
yt_assign_report() {
  YT_ASSIGN_REPORTED=1
  yt_report "$@"
}

# yt_assign_finish <result> -- the SINGLE exit for this step.
#
# THE SILENT-UNASSIGN SEAM (AC-13, IMPOSSIBLE_STATE) lives here. By construction
# every refusal path above reports first, so it can never fire -- which is
# exactly why it is here and why it is placed at the one exit rather than beside
# each decision. A guard that cannot fire is indistinguishable from a guard that
# is not there, and the state it guards against -- this step deciding not to
# assign, and saying nothing, leaving an issue with an assignee nobody chose -- is
# the one outcome that would look like a clean run in every channel at once.
yt_assign_finish() {
  local result="$1"
  if [[ "$result" != "applied" && "$result" != "no-change" && "$YT_ASSIGN_REPORTED" -eq 0 ]]; then
    yt_report syncyt.assignee.silent_unassign \
      "the assignee step for $TICKET ended as '$result' having reported NOTHING -- an operator reading the audit stream would see a clean run over an assignment that did not happen. This is an adapter defect, not a configuration one"
  fi
  yt_emit assign_result "$result"
  exit "$YT_EXIT_OK"
}

TICKET=""; ISSUE=""; SELF_LOGIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--issue|--self)
      # Guard the pair BEFORE the `shift 2` that consumes it -- see the same
      # guard in yt-resolve.sh for why an unguarded `shift 2` spins forever.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.assign.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket) TICKET="$2" ;;
        --issue)  ISSUE="$2" ;;
        --self)   SELF_LOGIN="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.assign.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.assign.usage "--ticket <id> is required"
[[ -n "$ISSUE"  ]] || yt_halt "$YT_EXIT_USAGE" syncyt.assign.usage \
  "--issue <internal-id> is required -- this step never creates an issue"

yt_config_require

# --- the OPT-IN gate (absent => DISABLED) -----------------------------------
# The INVERSE polarity of the worklog and link opt-outs, and deliberately so:
# this step REASSIGNS issues that may belong to other people, so an adopter who
# never mentioned it must not be silently opted in on upgrade. Read before the
# owned data and before any request, so a disabled step costs nothing and cannot
# fail on a file it never needed.
if [[ "$(yt_config_toggle assignment_reconciliation_enabled)" != "enabled" ]]; then
  yt_report syncyt.assign.disabled \
    "assignment_reconciliation_enabled is disabled in $(yt_config_path) -- no assignee was written and no request was issued for $TICKET"
  yt_emit assign_result disabled
  exit "$YT_EXIT_OK"
fi

yt_metadata_load "$TICKET"

# --- the Epic skip (BTG-040 parity, AC-6) -----------------------------------
# An Epic's assignee is HUMAN-MANAGED, as its status is: whoever a human put
# there stays there, and this sync never reconciles it. Skipped BEFORE any call
# so a run cannot even accidentally overwrite that person -- an assignee write
# here is a single POST with no undo, and "we only meant to read" is not a
# property an operator can verify after the fact.
#
# Ordered AFTER the opt-in gate above, matching the sibling: a disabled step
# reports `disabled` and never reads the ticket at all, so the more specific
# reason is only reachable once the step is actually switched on.
if [[ "$(yt_metadata_get '.type')" == "epic" ]]; then
  yt_report syncyt.assign.skipped_epic \
    "$TICKET carries type: epic -- its assignee is managed manually by humans and is never reconciled by this sync, so no request was issued"
  yt_emit assign_result skipped-epic
  exit "$YT_EXIT_OK"
fi

STATUS="$(yt_metadata_get '.status')"
if [[ -z "$STATUS" ]]; then
  yt_assign_report syncyt.assign.unknown_status \
    "$TICKET carries no 'status', so no assignment action is available -- nothing is guessed, because the two guesses on offer are stripping a human's assignee and claiming a ticket for this credential"
  yt_assign_finish unknown-status
fi

# The action comes from the config's assignment_map. A status OUTSIDE the map is
# an ordinary state, not a configuration fault -- so the resolver's own
# config-level report is suppressed and replaced by this step's vocabulary. What
# is never done is inventing an action.
if ! ACTION="$(yt_config_map assignment_map "$STATUS" 2>/dev/null)"; then
  yt_assign_report syncyt.assign.unknown_status \
    "status '$STATUS' has no entry under 'assignment_map' in $(yt_config_path) -- no assignment request is issued and no action is guessed"
  yt_assign_finish unknown-status
fi

# WANT_LOGIN is the intended assignee, and EMPTY means "deliberately nobody".
# The two are kept apart from here on: an empty login is a clearing write that
# must still be confirmed, never a reason to skip the confirmation.
case "$ACTION" in
  no-change)
    yt_report syncyt.assign.skipped_no_change \
      "status '$STATUS' maps to no-change -- the issue keeps whatever assignee it has and no request is issued"
    yt_emit assign_result no-change
    exit "$YT_EXIT_OK" ;;
  self)
    if [[ -z "$SELF_LOGIN" ]]; then
      yt_assign_report syncyt.assign.rejected \
        "status '$STATUS' maps to 'self' but no identity was resolved for this credential (--self is empty) -- issuing no request, because a login is never guessed or hardcoded"
      yt_assign_finish rejected
    fi
    WANT_LOGIN="$SELF_LOGIN" ;;
  unassigned)
    WANT_LOGIN="" ;;
  *)
    yt_assign_report syncyt.assign.unknown_status \
      "assignment_map['$STATUS'] in $(yt_config_path) resolves to '$ACTION', which is not an action this adapter implements (self | unassigned | no-change) -- issuing no request rather than writing a field in a shape no branch produces"
    yt_assign_finish unknown-status ;;
esac

BODY="$(mktemp)" || { yt_assign_report syncyt.assign.scratch_unavailable \
  "could not stage a request body for $TICKET (no scratch file) -- issuing no assignment write; assignment is best-effort, the sequence continues"
  yt_assign_finish rejected; }
trap 'rm -f "$BODY"' EXIT

# Through the ONE checked builder (AC-14), like every other body. The value is a
# jq NULL for the clearing case and an object carrying `login` otherwise -- both
# OBSERVED write forms. A body assembled as text here is exactly the defect the
# sibling adapter shipped: a failed build left an EMPTY variable, a zero-length
# body went out, and the run reported an assignment that never happened.
if ! yt_build_body "$BODY" syncyt.assign.body_unbuildable \
      "the assignee body for $TICKET" \
      -n --arg n "$ASSIGN_FIELD" --arg t "$YT_USER_TYPE" --arg l "$WANT_LOGIN" \
      '{customFields:[{name:$n,"$type":$t,value:(if $l == "" then null else {login:$l} end)}]}'; then
  yt_assign_finish rejected
fi

TARGET="/api/issues/$ISSUE?fields=id,idReadable"
if ! yt_rest POST "$TARGET" "$BODY"; then
  yt_assign_report syncyt.transport.rest_unreachable \
    "POST $TARGET could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the assignee for $TICKET is unchanged; assignment is best-effort, the sequence continues"
  yt_assign_finish rejected
fi
if ! yt_http_ok; then
  # 400 IS THE MEMBERSHIP CLASS on this endpoint, and the verdict is taken from
  # the STATUS rather than from the message text: the observed body is
  # `"Value is not allowed"` with `error_field: value`, which names neither the
  # field nor the login, and prose is the one part of an API answer that is free
  # to change. Every other status means something else entirely -- a 404 is a
  # missing issue and a 403 is a permission -- and collapsing them into
  # `unresolved` would reinstate the mis-diagnosis DEC-009 removed.
  #
  # The field and the login come from THIS STEP'S OWN INTENT. There is nothing
  # in the instance's reply to relay.
  if [[ "${YT_HTTP_STATUS:-}" == "400" ]]; then
    yt_assign_report syncyt.assignee.unresolved \
      "'$ASSIGN_FIELD' was set to '${WANT_LOGIN:-(cleared)}' and the instance refused it with HTTP 400 -- that target is not an ADMISSIBLE assignee on this project. The user may well exist in the directory; this project's Assignee user bundle does not contain them, so add them to the project's team or correct assignment_map.$STATUS in $(yt_config_path). The field and the login named here are this step's own intent: the instance's reply names neither. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
  else
    yt_assign_report syncyt.assign.rejected \
      "POST $TARGET returned HTTP $YT_HTTP_STATUS -- '$ASSIGN_FIELD' was NOT set to '${WANT_LOGIN:-(cleared)}' for $TICKET. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
  fi
  # Nothing is re-issued and nothing is compensated. A rejected write applies
  # NOTHING on this instance (OBSERVED, sidecar 2 G), so the issue keeps the
  # assignee it had -- and a clearing write here would take a refused assignment
  # and turn it into an unassignment nobody asked for.
  yt_assign_finish rejected
fi

# --- the confirmation: the 200 above is not evidence (AC-12) -----------------
# The selector asks for the USER shape (`login`, `fullName`) rather than the
# `value(name)` shape the enum fields read back through. The live record shows an
# accepted assignee reading back as a login and a full name; the exact selector
# STRING it used is not recorded, so this one is an INFERENCE and is flagged in
# decisions.md for the live run to close. It is safe in the direction that
# matters: a selector that returned nothing usable is reported as NOT CONFIRMED,
# never as confirmed, so a wrong inference costs a false alarm and never a false
# success.
if ! yt_rest GET "/api/issues/$ISSUE?fields=id,customFields(name,value(login,fullName))" || ! yt_http_ok; then
  yt_assign_report syncyt.write.field_not_applied \
    "'$ASSIGN_FIELD' was written as '${WANT_LOGIN:-(cleared)}' for $TICKET but could NOT be verified: the confirmation read was unreachable or returned HTTP ${YT_HTTP_STATUS:-}. 'we could not check' is not 'it landed'"
  yt_assign_finish rejected
fi
GOT_LOGIN="$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg n "$ASSIGN_FIELD" '
    ((.customFields // []) | map(select(.name == $n)) | .[0].value.login) // "" ' 2>/dev/null)" \
  || GOT_LOGIN=""
if [[ "$GOT_LOGIN" != "$WANT_LOGIN" ]]; then
  yt_assign_report syncyt.write.field_not_applied \
    "'$ASSIGN_FIELD' was written as '${WANT_LOGIN:-(cleared)}' for $TICKET and the instance answered 2xx, but the issue reads back as '${GOT_LOGIN:-(nobody)}' -- the write was accepted and the value did not land"
  yt_assign_finish rejected
fi

yt_report syncyt.assign.applied \
  "$TICKET: '$ASSIGN_FIELD' is '${WANT_LOGIN:-(cleared)}' on the issue, confirmed by reading it back rather than inferred from the write's own 200 (status '$STATUS' maps to '$ACTION')"
yt_emit assign_result applied
exit "$YT_EXIT_OK"
