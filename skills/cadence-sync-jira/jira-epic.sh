#!/usr/bin/env bash
#
# jira-epic.sh -- project a ticket's Epic relationship.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (BTG-040): **the relationship
# lives on the CHILD.** An Epic creates zero links and carries no decomposition
# fields of its own; a child whose `decomposed_from` names an Epic sets its own
# Epic Link. Projecting the relationship from the Epic instead would make the
# Epic's own projection depend on the existence and ordering of every child.
#
# The second invariant (BTG-036) is a Jira Server/DC PROHIBITION -- **an Epic may
# not carry an Epic Link** -- so a `type: epic` ticket that already has one takes
# the UMBRELLA branch instead (see the fork below).
#
# The Epic Link field is a plugin-provided custom field whose id VARIES PER
# INSTANCE, so it is discovered by exact NAME at run time and never hardcoded --
# a hardcoded `customfield_10001` silently writes into whatever unrelated field
# happens to hold that id on another instance.
#
# Upstream: the orchestrator, near the end of the sequence (best-effort).
# Downstream: `GET .../field`, `GET`/`PUT .../issue/{key}`, and (umbrella only)
#   `GET .../issueLinkType` + `POST .../issueLink` via `jira-link-lib.sh`.
# Spec: archive/BTG-075/spec.md (Idempotency) ; jira-server-scripts.md.
# DX CEILING -- READ FIRST. The binding gate is NOT the 400 cap but
# btg-046-ac-sync.test.sh S-42.5 (BTG-079 AC-7), >=5 lines headroom (so <=395).
# BTG-105 DEC-017 SUPERSEDES the old note here: the umbrella writers now live in
# jira-umbrella-lib.sh, not jira-epic-lib.sh, and the next growth goes there too.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> --issue-key <KEY>
#   stdout : epic_result=associated|at-target|umbrella|umbrella-partial|umbrella-unclosed|none|rejected (+ epic_children_linked=<n> on the umbrella branch)
#   stderr : syncjs.epic.* / syncjs.umbrella.* reported conditions
#   exit   : 0 for every outcome including a rejection (best-effort); 2 usage;
#            4 config HALT. A failure inside the epic branch halts THE BRANCH,
#            never the ticket (DEC-033).
#
# This script READS metadata.yaml (its own and the parent's) and NEVER writes
# either (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
# The umbrella's child links REUSE the ordered-link machinery verbatim (type discovery, inversion calibration, read-back, self-heal), never re-deriving it.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-link-lib.sh"
# ...and the `type: epic` FORK is the same shared implementation jira-write-issue.sh
# used to choose this issue's type at step 4, so the two can never disagree.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-epic-lib.sh"
# ...and the umbrella REPLACEMENT writers (create U, move the ordered links, close
# the original) live in their own module -- the addition fits neither this file's
# ceiling nor either existing library's (BTG-105 DEC-017).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-umbrella-lib.sh"
# ...and this script's OWN per-run child-loop concerns (the whole-child-set
# pre-validation and UMBRELLA WRITE 3) live in a sibling too (BTG-247, this
# file's own split) -- distinct from the umbrella replacement's own
# create/retire machinery above.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-epic-umbrella-children.sh"

TICKET=""
ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)    js_argv_pair syncjs.epic.usage "$@"; TICKET="$2"; shift 2 ;;
    --issue-key) js_argv_pair syncjs.epic.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.epic.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET"    ]] || js_halt "$JS_EXIT_USAGE" syncjs.epic.usage "--ticket <id> is required"
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.epic.usage "--issue-key <KEY> is required"

js_config_require
js_metadata_load "$TICKET"

TICKET_TYPE="$(js_metadata_get '.type')"

# --------------------------------------------------------------------------
# The `type: epic` FORK -- BTG-036 / BTG-040
# --------------------------------------------------------------------------
# Jira Server/DC FORBIDS an Epic from carrying an Epic Link: an Epic cannot be the
# child of another Epic. That prohibition is the entire reason the umbrella branch
# exists, so the fork is gated SOLELY on the ticket's OWN LIVE Epic Link -- never
# on whether it happens to declare children:
#   empty/absent -> the single-level Epic projection (zero links, zero writes;
#                   each child carries the relationship on its own Epic Link);
#   populated    -> the umbrella branch, with E = that live value.
# Gating on `decomposed_into` instead sends a REAL Epic-on-Epic down the child
# path, which writes the forbidden field, takes a 400, reports it, and silently
# never lands the decomposition lineage.
if [[ "$TICKET_TYPE" == "epic" ]]; then
  BASE_URL="$(js_env_value base_url)"
  [[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.epic.env_absent "the base-URL environment variable is unset"

  # THE GATE, resolved by the SHARED implementation step 4 already used to choose
  # this issue's type (jira-epic-lib.sh) -- re-deriving it here is what let the two
  # disagree and oscillate the umbrella every run. The branch mutates nothing it
  # could not read first, and every failure HALTS THE BRANCH before any mutation
  # (never the ticket: this step is best-effort, and a non-zero exit would halt
  # the whole sync).
  if ! js_epic_branch "$ISSUE_KEY"; then
    js_emit epic_result rejected
    exit "$JS_EXIT_OK"
  fi
  UMB_FIELD_ID="$JS_EPIC_LINK_FIELD"
  EPIC_E="$JS_EPIC_E"
  if [[ "$JS_EPIC_BRANCH" != "umbrella" ]]; then
    js_report syncjs.epic.single_level \
      "$TICKET carries no Epic Link of its own -- the single-level Epic projection: zero issue links and zero writes here; each child sets its own Epic Link when it syncs"
    js_emit epic_result none
    exit "$JS_EXIT_OK"
  fi

  # The child set, read SHAPE-AWARE: an uninterpretable one halts before write 1.
  CHILDREN="$(js_metadata_list decomposed_into syncjs.umbrella.children_unreadable)" || { js_emit epic_result rejected; exit "$JS_EXIT_OK"; }

  # Resolved by the library, which owns every key's polarity: headless iff the
  # bound signal is TRUTHY, and an absent binding HALTS rather than defaulting
  # here to a name the adopter is entitled to rebind. The ordered link type is a
  # READ that halts the SAME way, so it joins them here, ahead of every mutation:
  # standing after the create it minted a fresh orphan per run (B2 / DEC-026).
  HEADLESS_ENV="$(js_config_map run_mode headless_env)" || exit "$JS_EXIT_CONFIG"
  RUN_MODE="$(js_run_mode)" || exit "$JS_EXIT_CONFIG"
  js_umbrella_ordered_type "$CHILDREN" || exit "$JS_EXIT_CONFIG"

  UMB_SET=0; UMB_CONFLICT=0; UMB_FAIL=0
  UMB_BODY="$(mktemp 2>/dev/null)" || { js_report syncjs.umbrella.scratch_unavailable "no scratch file could be staged for $TICKET's child Epic Link bodies -- setting NO child links; an unstaged body degrades each PUT into a BODYLESS one a permissive server accepts, leaving every child unlinked while the run reports success"; js_emit epic_result rejected; exit "$JS_EXIT_OK"; }
  trap 'rm -f "$UMB_BODY" 2>/dev/null' EXIT

  js_epic_umbrella_resolve_children

  # THE REPLACEMENT -- create U, never re-type the original (BTG-105). Writing the
  # issue type onto the LIVE original returns 204, the type takes, the workflow
  # pointer does NOT follow, and neither safeguard can fire (BTG-102 DEC-026/031).
  # An issue BORN at the target type has no workflow to strand, so this file now
  # names that field NOWHERE at all -- a property asserted structurally, across
  # all three trees, by btg-105-umbrella-replacement.test.sh.
  js_umbrella_mode "$TICKET" "$ISSUE_KEY"
  if ! js_umbrella_issue_ensure "$TICKET" "$ISSUE_KEY" "$EPIC_E"; then
    # JS_UMB_ISSUE may STILL be set (the epic_link_unset arm): the issue EXISTS,
    # so its binding is emitted regardless, or a re-run creates a SECOND one.
    [[ -n "$JS_UMB_ISSUE" ]] && js_emit umbrella_epic_url "${BASE_URL%/}/browse/$JS_UMB_ISSUE"
    js_emit epic_result rejected
    exit "$JS_EXIT_OK"
  fi
  UMB_ISSUE="$JS_UMB_ISSUE"
  js_emit umbrella_epic_url "${BASE_URL%/}/browse/$UMB_ISSUE"

  # ONE snapshot of the original's links, taken before the loop so the stale ids
  # are discovered from a single consistent read and never computed.
  JS_UMB_T_READ=skipped
  [[ "$JS_UMB_MODE" != settled ]] && js_umbrella_stale_links "$ISSUE_KEY"

  # The child set is already resolved: the loop performs writes ONLY.
  while read -r child CHILD_KEY; do
    [[ -n "$CHILD_KEY" ]] || continue

    js_epic_umbrella_link_child_ordered

    # ----------------------------------------------------------------------
    # UMBRELLA WRITE 4 -- the child's Epic Link = E, the TOP-LEVEL epic.
    # ----------------------------------------------------------------------
    # E is where the child points, NOT the umbrella: the umbrella is now an
    # Issue, and a Jira Epic Link must target an Epic. Pointing PAST the umbrella
    # is also what makes the projection depth-uniform -- the single top-level E
    # flows unchanged down the whole subtree with no new mechanism.
    if ! js_rest GET "/rest/api/2/issue/$CHILD_KEY?fields=$UMB_FIELD_ID" || ! js_http_ok; then
      js_report syncjs.umbrella.child_epic_link_unreadable \
        "$CHILD_KEY's current Epic Link could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- its Epic Link is NOT written blind; the remaining children continue and a re-run converges it"
      UMB_FAIL=$((UMB_FAIL + 1))
      continue
    fi
    CHILD_LINK="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg f "$UMB_FIELD_ID" '.fields[$f] // ""' 2>/dev/null)"
    if [[ "$CHILD_LINK" == "$EPIC_E" ]]; then
      js_report syncjs.umbrella.at_target "$CHILD_KEY already points at the top-level Epic $EPIC_E -- left untouched"
      UMB_SET=$((UMB_SET + 1))
      continue
    fi
    if [[ -n "$CHILD_LINK" && "$CHILD_LINK" != "null" ]]; then
      UMB_CONFLICT=1
      UMB_FAIL=$((UMB_FAIL + 1))
      if [[ "$RUN_MODE" != "headless" ]]; then
        js_report syncjs.umbrella.child_epic_link_conflict \
          "$CHILD_KEY carries a different Epic Link ($CHILD_LINK, not the top-level $EPIC_E) -- leaving it alone; re-run with \$$HEADLESS_ENV set to overwrite deliberately (interactive is the fail-safe)"
        continue
      fi
      js_report syncjs.umbrella.child_epic_link_conflict \
        "$CHILD_KEY carries a different Epic Link ($CHILD_LINK, not the top-level $EPIC_E) -- overwriting it, because \$$HEADLESS_ENV declares this run headless"
    fi
    if ! js_build_body "$UMB_BODY" syncjs.umbrella.child_epic_link_body_unbuildable "$CHILD_KEY's Epic Link body" -n --arg f "$UMB_FIELD_ID" --arg v "$EPIC_E" '{fields: {($f): $v}}'; then
      UMB_FAIL=$((UMB_FAIL + 1)); continue   # its OWN arm; never *_rejected (BTG-084)
    elif ! js_rest PUT "/rest/api/2/issue/$CHILD_KEY" "$UMB_BODY" || ! js_http_ok; then
      js_report syncjs.umbrella.child_epic_link_rejected \
        "setting $CHILD_KEY's Epic Link to $EPIC_E was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the field may not be on this child's edit screen; the remaining children continue and a re-run converges them"
      UMB_FAIL=$((UMB_FAIL + 1))
      continue
    fi
    # MANDATORY read-back: a 2xx is not proof the field took the value.
    if ! js_rest GET "/rest/api/2/issue/$CHILD_KEY?fields=$UMB_FIELD_ID" || ! js_http_ok \
       || [[ "$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg f "$UMB_FIELD_ID" '.fields[$f] // ""' 2>/dev/null)" != "$EPIC_E" ]]; then
      js_report syncjs.umbrella.child_epic_link_unverified \
        "$CHILD_KEY's Epic Link could not be confirmed as $EPIC_E after the write -- reported rather than assumed"
      UMB_FAIL=$((UMB_FAIL + 1))
      continue
    fi
    UMB_SET=$((UMB_SET + 1))
  done <<<"$CHILD_PAIRS"
  # A child set that was only PARTLY applied is never reported as a plain result:
  # a re-run converges the remainder, but only if the operator is told there IS a
  # remainder.
  UMB_RESULT=umbrella
  if [[ "$UMB_FAIL" -gt 0 ]]; then
    # The MACHINE-READABLE channel carries the partiality too: the orchestrator
    # parses the payload, never stderr, so a flat `epic_result=umbrella` beside a
    # partial condition would read as a complete projection.
    UMB_RESULT=umbrella-partial
    js_report syncjs.umbrella.partial \
      "the umbrella projection was applied to only PART of the child set: $UMB_SET child(ren) at target, $UMB_FAIL not applied (each reported above) -- the landed writes are left in place and a re-run converges the rest"
  fi
  # RETIRE THE ORIGINAL -- last, and ONLY behind a complete child set, so an issue
  # is never retired while a child is stranded or dual-linked. `jira_url` moves to
  # the replacement ONLY on completion: that asymmetry is what keeps a partial run
  # convergent (it re-enters in mode B) rather than stranded.
  if [[ "$JS_UMB_MODE" == settled ]]; then
    js_report syncjs.umbrella.at_replacement \
      "$TICKET already projects onto its replacement $ISSUE_KEY -- the ordered links are converged and no create, retire or close applies"
  elif [[ "$UMB_FAIL" -eq 0 ]]; then
    js_umbrella_original_close "$ISSUE_KEY"
    case "$JS_UMB_CLOSE" in
      closed|at-target) js_emit jira_url "${BASE_URL%/}/browse/$UMB_ISSUE" ;;
      # The partial guard's own principle, applied to AC-2's close step: a refused close leaves jira_url on the superseded original, so a flat `umbrella` would report a SPLIT projection complete (B3 / DEC-027).
      *) UMB_RESULT=umbrella-unclosed; js_report syncjs.umbrella.binding_deferred \
           "$ISSUE_KEY could not be closed this run, so jira_url still names it and the branch will be re-entered to converge; the replacement $UMB_ISSUE is already recorded" ;;
    esac
  else
    js_report syncjs.umbrella.close_deferred \
      "the child set was only partly applied, so $ISSUE_KEY is NOT closed and jira_url is NOT re-pointed -- a re-run converges the remainder and then retires the original"
  fi
  js_report syncjs.umbrella.projected "umbrella $UMB_ISSUE (top-level Epic $EPIC_E, superseding $ISSUE_KEY): $UMB_SET child association(s) at target, $UMB_CONFLICT conflict(s) reported"
  js_emit epic_children_linked "$UMB_SET"
  js_emit epic_result "$UMB_RESULT"
  exit "$JS_EXIT_OK"
fi

PARENT="$(js_metadata_get '.decomposed_from')"
if [[ -z "$PARENT" ]]; then
  js_report syncjs.epic.none "$TICKET has no decomposed_from parent -- no Epic association to project"
  js_emit epic_result none
  exit "$JS_EXIT_OK"
fi

# The parent must be an Epic that already exists in Jira. Reading the PARENT's own
# metadata keeps the type judgement where the type is owned, rather than inferring
# it from a naming convention.
CHILD_JSON="$JS_METADATA_JSON"
# js_metadata_load HALTS on an unreadable file -- correct for the ticket's OWN
# metadata, wrong here: this step is best-effort ("0 for every outcome including a
# rejection"), so a child naming a parent this repo does not carry must report and
# continue rather than halting the whole ticket.
if ! js_metadata_path "$PARENT" >/dev/null 2>&1; then
  js_report syncjs.epic.parent_unresolved \
    "$TICKET names decomposed_from '$PARENT', which has no metadata.yaml under specs/ or archive/ -- no Epic Link is set; the sync continues"
  js_emit epic_result none
  exit "$JS_EXIT_OK"
fi
js_metadata_load "$PARENT"
PARENT_TYPE="$(js_metadata_get '.type')"
PARENT_URL="$(js_metadata_get '.jira_url')"
JS_METADATA_JSON="$CHILD_JSON"

if [[ "$PARENT_TYPE" != "epic" ]]; then
  js_report syncjs.epic.none "$TICKET's parent $PARENT is type '$PARENT_TYPE', not an epic -- no Epic Link is set"
  js_emit epic_result none
  exit "$JS_EXIT_OK"
fi
if [[ -z "$PARENT_URL" ]]; then
  js_report syncjs.epic.parent_unprojected \
    "$TICKET's Epic parent $PARENT has no jira_url yet -- the association is skipped this run and applies once the parent is synced (best-effort)"
  js_emit epic_result none
  exit "$JS_EXIT_OK"
fi
PARENT_KEY="${PARENT_URL##*/}"

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.epic.env_absent "the base-URL environment variable is unset"
FIELD_NAME="$(js_config_map link_relations epic_link_field_name)" || exit "$JS_EXIT_CONFIG"

# Discover the field id BY NAME -- per-instance, never hardcoded.
if ! js_rest GET "/rest/api/2/field" || ! js_http_ok; then
  js_report syncjs.epic.rejected \
    "the field discovery read failed (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the Epic Link field id is never guessed; the sync continues"
  js_emit epic_result rejected
  exit "$JS_EXIT_OK"
fi
FIELD_ID="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$FIELD_NAME" 'if type=="array" then (map(select(.name == $n)) | if length == 1 then .[0].id else empty end) else empty end' 2>/dev/null)"
if [[ -z "$FIELD_ID" ]]; then
  js_report syncjs.epic.field_unresolved \
    "no unambiguous '$FIELD_NAME' field on this instance -- refusing to write into a guessed custom field; the sync continues"
  js_emit epic_result rejected
  exit "$JS_EXIT_OK"
fi

# READ BEFORE WRITE: an issue already pointing at its Epic is left alone, so a
# re-run re-asserts nothing (DEC-009).
if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=$FIELD_ID" || ! js_http_ok; then
  js_report syncjs.epic.rejected \
    "could not read $ISSUE_KEY's current Epic Link (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the sync continues"
  js_emit epic_result rejected
  exit "$JS_EXIT_OK"
fi
CURRENT="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg f "$FIELD_ID" '.fields[$f] // ""' 2>/dev/null)"
if [[ "$CURRENT" == "$PARENT_KEY" ]]; then
  js_report syncjs.epic.at_target "$ISSUE_KEY already carries Epic Link $PARENT_KEY -- left untouched"
  js_emit epic_result at-target
  exit "$JS_EXIT_OK"
fi

# The association write lives in jira-epic-lib.sh, beside step 4's early exits and
# for the same reason DEC-057 put them there -- the 400-line DX ceiling. It stages
# the body and REFUSES the write if the scratch file or the jq build fails, rather
# than issuing a BODYLESS PUT a permissive server accepts while the run reports
# `associated`; it emits this script's epic_result payload and exits 0 (DEC-033).
js_epic_child_associate "$ISSUE_KEY" "$FIELD_ID" "$FIELD_NAME" "$PARENT_KEY"
