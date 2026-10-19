#!/usr/bin/env bash
#
# jira-type-lib.sh -- the ISSUE-TYPE decision for the projection write, as one unit.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075/BTG-173).
# Invariant relied on from outside this boundary, OBSERVED LIVE and not assumed
# (archive/BTG-102 DEC-026): Jira Server/DC's update `PUT` does NOT enforce the
# issue types its own `editmeta` offers. PLAYSCRUM-3395 -- a `Story` whose
# `editmeta.fields.issuetype.allowedValues` was exactly `["Story"]` -- accepted a
# bare `PUT` re-typing it to `Issue` with HTTP 204, leaving it on a status its new
# workflow does not contain and collapsing its offered transitions from 6 to 2,
# with NO `Workflow` changelog item (only Jira's UI Move writes one). So the
# INSTANCE is asked first, exactly as jira-transition.sh asks GET /transitions
# before a status hop.
#
# It is SOURCED, never invoked, and runs nothing on load. It never writes
# `metadata.yaml` (BTG-075 AC-6) and it emits nothing on stdout: it leaves its
# verdict in ISSUETYPE_PROJECTED and its CALLER publishes it.
#
# Why it is a library rather than a block in `jira-write-issue.sh`. It landed here
# by RELOCATION under the 400-line DX ceiling, on the `jira-ac-lib.sh` (BTG-079
# AC-7) and `jira-link-targets.sh` (BTG-106 DEC-003) precedents -- both TEXTUAL
# relocations that read and write their caller's variables exactly as the in-line
# block did, which is what made behaviour-preservation provable rather than argued.
# `jira-write-issue.sh` stood at 399 lines against an assertion that fails at
# `>= 400` (btg-046-ac-sync.test.sh S-42.1; btg-102-retype-guard.test.sh R-13), so
# BTG-173 could not add a single line to it. The unit chosen is the WHOLE issue-type
# concern -- resolution, the BTG-102 re-type guard, and the verdict -- so exactly
# one module answers "is the issue type written, and to what?". Ruled at BTG-173's
# spec-approval gate (archive/BTG-173/decisions.md DEC-004, OQ-2 -> option (a)),
# which supersedes BTG-102 DEC-023's "a helper for one caller is speculative
# generality": the helper is no longer speculative, it is the only way the caller
# fits under its own ceiling.
#
# `jira-write-issue.sh` stays its ONLY caller and its only `issuetype_projected`
# emitter. This file is deliberately NOT sourced by `jira-reserve.sh` or
# `jira-umbrella-lib.sh`: both are CREATES, an issue that does not yet exist and
# therefore has no workflow to strand, and they are unguarded BY DESIGN
# (btg-102-retype-guard.test.sh S-4.1's three-writers/one-guarded inventory).
#
# Upstream: `jira-write-issue.sh`, at the two sites the in-line blocks occupied.
# Downstream: `GET /rest/api/2/issue/{key}?fields=issuetype` and
#   `GET /rest/api/2/issue/{key}/editmeta` on the adopter's Jira Server/DC.
# Spec: archive/BTG-173/spec.md (D1, D3) ; archive/BTG-102/spec.md (AC-1..AC-4) ;
#   jira-server-scripts-type.md.
#
# Contract:
#   js_type_resolve -- reads TICKET_TYPE and MODE; sets ISSUE_TYPE and
#                      TYPE_UNASSERTED (yes|no). HALTs JS_EXIT_CONFIG when a
#                      type the repo DID assert cannot be resolved.
#   js_type_verdict -- the update-path re-type guard; reads MODE,
#                      TYPE_UNASSERTED, ISSUE_KEY, ISSUE_TYPE, LIVE_ISSUE_JSON
#                      and BASE_URL; sets ISSUETYPE_PROJECTED (yes|no) and may
#                      populate LIVE_ISSUE_JSON. HALTs JS_EXIT_TRANSPORT when the
#                      instance could not be asked.
#
# Both write their caller's variables directly and declare no `local` for them --
# the in-line blocks were straight-line code in the caller's scope, and keeping
# that scope is what makes the relocation a MOVE rather than a rewrite.

# --- js_type_resolve --------------------------------------------------------
# BTG-173: an UNTYPED ticket is a SANCTIONED state, not an error. `/claire-triage
# --file-only` files without classifying (artifacts/commands/claire-triage.md F3 writes
# `tier: ""` and NO `type:`), and `jira-import.sh` already REPORTS an untyped
# intake rather than guessing one. This makes the projection half agree with the
# intake half.
#
# On UPDATE the issue already carries the type `jira-reserve.sh` gave it, so this
# write DECLINES to restate a type the repo does not assert; it does not invent
# one. Declining to assert is not guessing.
#
# Two narrowings keep that from being a silent fallback (CLAUDE.md Behavior 5),
# and both are load-bearing:
#   * EMPTINESS, never lookup failure. A NON-EMPTY type the map cannot resolve
#     still HALTs exit 4 -- otherwise a genuine config gap would be swallowed
#     under this branch, which is the precise thing the halt's own text forbids.
#   * UPDATE, never create. `--mode create` with an empty type still HALTs: a
#     create must carry a type and there is no live value to leave alone. The
#     asymmetry is deliberate (archive/BTG-173/spec.md RISK-3).
# Whitespace-only is EMPTY here, using the same `[^[:space:]]` normalization the
# title guard applies in the caller, "because the umbrella summary helper already
# treats it so, and two writers of one concept must not disagree".
js_type_resolve() {
  TYPE_UNASSERTED=no
  if [[ ! "$TICKET_TYPE" =~ [^[:space:]] && "$MODE" == "update" ]]; then
    TYPE_UNASSERTED=yes
    ISSUE_TYPE=""
    js_report syncjs.write.type_unasserted \
      "$TICKET carries no type: -- the repo asserts NO issue type, so this update projects every other field and leaves $ISSUE_KEY's CURRENT type untouched. Nothing is guessed and no Move is owed; run /claire-triage on the id to classify it, and the next sync projects the real type"
    return 0
  fi
  ISSUE_TYPE="$(js_config_map issue_type_map "$TICKET_TYPE")" \
    || js_halt "$JS_EXIT_CONFIG" syncjs.config.marker_unresolved \
         "no issue_type_map entry for type='$TICKET_TYPE' -- a guessed issue type is an ungoverned decision"
}

# --- js_type_verdict --------------------------------------------------------
# BTG-102: the pre-flight issue-type RE-TYPE guard (update path only). Relocated
# from `jira-write-issue.sh` by BTG-173 without a behavioural change.
#
# The guard's ONLY preconditions are the UPDATE path and a type the repo actually
# ASSERTS: a create has no live type to diverge from, and an UNASSERTED type has
# no target to compare against. Reusing the estimate prerequisite read's body is an
# OPTIMISATION (it already asked for `issuetype`), but ITS condition -- a
# projectable estimate, and not an epic -- must never become the guard's: 73 of
# this repo's 162 tickets carry an empty or non-duration estimate, so inheriting it
# left the write UNGUARDED in the COMMON case while stdout still reported a verdict
# (BTG-102 review-1 B-1). An epic is guarded too: the fork resolves the type first
# and the guard only decides whether that type is WRITTEN (DEC-029). A live type
# that already equals the target asks nothing and costs nothing.
#
# BTG-173: the TYPE_UNASSERTED arm is a BYPASS, not a skip, and that is
# load-bearing behaviour rather than tidiness. Left running against an empty
# target the guard would compare the live type (`Task`) against "", find them
# different, ask `GET .../editmeta` whether the instance offers the type "",
# receive `refused`, and report `syncjs.write.issuetype_move_required` --
# instructing the operator to perform a Jira Move to a type that does not exist.
# That is a FALSE instruction on the happy path. `type_unasserted` keeps its own
# name for the same reason: `move_required` means the instance refused a type the
# repo DOES assert and a human must act, where `type_unasserted` means the repo
# asserts nothing and no human action is owed.
js_type_verdict() {
  ISSUETYPE_PROJECTED=yes
  [[ "$TYPE_UNASSERTED" == "yes" ]] && { ISSUETYPE_PROJECTED=no; return 0; }
  [[ "$MODE" == "update" ]] || return 0
  if [[ -z "$LIVE_ISSUE_JSON" ]]; then
    if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=issuetype"; then
      js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
        "GET /rest/api/2/issue/$ISSUE_KEY?fields=issuetype could not reach ${BASE_URL%/} (${JS_TRANSPORT_ERROR:-no diagnostic}) -- NOT issuing the update PUT; the live issue type was never read and a re-type on a guess is the corrupting direction"
    fi
    js_http_ok && LIVE_ISSUE_JSON="$JS_HTTP_BODY"
  fi
  LIVE_ISSUE_TYPE="$(printf '%s' "$LIVE_ISSUE_JSON" | jq -r '.fields.issuetype.name // empty' 2>/dev/null)"
  RETYPE_CLASS=""
  if [[ -z "$LIVE_ISSUE_TYPE" ]]; then
    # "I do not know what this issue IS" can never resolve to "write it anyway" --
    # the fail-open polarity rule (c) forbids for an absent allowedValues.
    RETYPE_CLASS=no-live-type
  elif [[ "$LIVE_ISSUE_TYPE" != "$ISSUE_TYPE" ]]; then
    # "The exchange could not happen" is NOT "the exchange happened and the answer
    # is unusable". The first halts with the existing transport condition and
    # sends NO write; only the second falls through to a verdict. Conflating them
    # would send an update after failing to ask the instance anything.
    if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY/editmeta"; then
      js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
        "GET /rest/api/2/issue/$ISSUE_KEY/editmeta could not reach ${BASE_URL%/} (${JS_TRANSPORT_ERROR:-no diagnostic}) -- NOT issuing the update PUT; whether the re-type is acceptable was never asked"
    fi
    # An ABSENT allowedValues is never read as "every type is allowed" and an EMPTY
    # one is never read as "no type is allowed" -- both are UNKNOWN, and unknown
    # fails CLOSED on the issue type alone. Each unusable shape keeps its OWN name
    # so the operator can tell a non-editable field from a malformed response.
    if ! js_http_ok; then
      RETYPE_CLASS=http
    else
      RETYPE_CLASS="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg t "$ISSUE_TYPE" '
        if type != "object" or (.fields | type) != "object" then "unparseable"
        elif (.fields | has("issuetype") | not) or (.fields.issuetype | type) != "object" then "no-issuetype"
        elif (.fields.issuetype | has("allowedValues") | not)
          or (.fields.issuetype.allowedValues | type) != "array" then "no-allowedvalues"
        elif (.fields.issuetype.allowedValues | length) == 0 then "empty-allowedvalues"
        elif any(.fields.issuetype.allowedValues[]; (.name? // "") == $t) then "allowed"
        else "refused" end' 2>/dev/null)" || RETYPE_CLASS=unparseable
      [[ -n "$RETYPE_CLASS" ]] || RETYPE_CLASS=unparseable
    fi
  fi
  case "$RETYPE_CLASS" in
      "") ;;                                   # no divergence: nothing was asked
      allowed)
        js_report syncjs.write.issuetype_retyped \
          "$ISSUE_KEY is issue type '$LIVE_ISSUE_TYPE' and this instance OFFERS '$ISSUE_TYPE' for it -- projecting the re-type (no Move is owed)" ;;
      refused)
        # The wording generalizes jira-epic.sh's existing umbrella rejection: the
        # answer is the INSTANCE's, the remedy is a human one, and a status is
        # NEVER transitioned to force the type through.
        ISSUETYPE_PROJECTED=no
        js_report syncjs.write.issuetype_move_required \
          "$ISSUE_KEY is currently issue type '$LIVE_ISSUE_TYPE', and this instance does not offer '$ISSUE_TYPE' for it -- the change crosses workflow schemes, which Jira only performs through its MOVE operation. The issue type is NOT projected and a status is NEVER transitioned to force it; every other field was projected. Perform the Move in the Jira UI (More -> Move) on ${BASE_URL%/}/browse/$ISSUE_KEY, then re-run the sync" ;;
      *)
        case "$RETYPE_CLASS" in
          no-live-type)        RETYPE_DETAIL="the issue read (HTTP ${JS_HTTP_STATUS:-unknown}) carried no .fields.issuetype, so the LIVE type is unknown -- field-level security, or an unexpected shape; the edit metadata was not even asked, because there is nothing to compare" ;;
          http)                RETYPE_DETAIL="the edit-metadata read returned HTTP $JS_HTTP_STATUS" ;;
          no-issuetype)        RETYPE_DETAIL="this instance's edit screen carries NO Issue Type field for the issue -- the field is not editable here (NOT a malformed response), so a Move is the only path" ;;
          no-allowedvalues)    RETYPE_DETAIL="the edit metadata's issuetype field carries no allowedValues list -- an ABSENT list is never read as 'every type is allowed'" ;;
          empty-allowedvalues) RETYPE_DETAIL="the edit metadata's allowedValues list is EMPTY -- an empty list is never read as 'no type is allowed'; it is UNKNOWN" ;;
          *)                   RETYPE_DETAIL="the edit-metadata response could not be parsed (HTTP $JS_HTTP_STATUS)" ;;
        esac
        ISSUETYPE_PROJECTED=no
        js_report syncjs.write.issuetype_undeterminable \
          "$ISSUE_KEY is issue type '${LIVE_ISSUE_TYPE:-(unreadable)}' and whether this instance accepts '$ISSUE_TYPE' could not be determined: $RETYPE_DETAIL. The issue type is NOT projected (unknown never becomes 'go ahead') and every other field was; perform the Move in the Jira UI (More -> Move) on ${BASE_URL%/}/browse/$ISSUE_KEY if the re-type is intended, then re-run the sync" ;;
  esac
}
