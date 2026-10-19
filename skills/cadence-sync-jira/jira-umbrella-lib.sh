#!/usr/bin/env bash
#
# jira-umbrella-lib.sh -- the umbrella REPLACEMENT creation/binding half,
# sourced by jira-epic.sh. Its ORIGINAL-RETIREMENT half (ordered-link
# retirement + the superseded original's close) lives in a sourced sibling,
# jira-umbrella-retire.sh (BTG-247, this file's own split).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-105).
# Invariant relied on from outside this boundary (BTG-036, live-verified): **an
# Epic may not carry an Epic Link on Jira Server/DC.** The umbrella carries one --
# that link is what MAKES it an umbrella -- so the replacement is created at the
# CONFIGURED umbrella type (`umbrella.issue_type`, shipped `Issue`) and NEVER at
# `Epic` (decisions.md DEC-011).
#
# Why this module exists at all: the predecessor path issued
# `PUT {fields:{issuetype:...}}` against the LIVE original. On Jira Server/DC a
# bare update PUT does not enforce `editmeta.allowedValues` (BTG-102 DEC-026): it
# returns 204, the type takes, the workflow pointer does NOT follow, the reachable
# transition set collapses, and no `Workflow` changelog item is written -- so
# neither of that path's safeguards could fire (DEC-031). **An issue born at the
# right type needs no re-type.** That single fact is the whole fix.
#
# Upstream: jira-epic.sh's umbrella branch (its only caller).
# Downstream: `POST /issue`, `PUT /issue/{key}` (custom field ONLY -- never an
#   issuetype), `GET /issue/{key}?fields=issuelinks`, `DELETE /issueLink/{id}`,
#   `GET`/`POST /issue/{key}/transitions`.
# Spec: archive/BTG-105/spec.md (Proposed Design) ; jira-server-scripts.md.
#
# Every function here REPORTS on stderr and RETURNS; none halts the ticket. The
# umbrella branch is best-effort, so a failure halts THE BRANCH, never the sync
# (DEC-033). This module installs NO `trap ... EXIT` (BTG-079 AC-3): each exit
# path unlinks its own scratch file, so it cannot displace its caller's trap.

# js_issue_key_valid <value> -- the ONE shape predicate for a value bound for a
# REST path. Extracted so a THIRD interpolation site cannot diverge from the two
# guarded here: PROD_CADENCE-014's recorded shape is "two writers share one systemic fact
# and only one of them was audited" (archive/BTG-113/decisions.md DEC-015).
js_issue_key_valid() { [[ "$1" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; }

# js_umbrella_mode <ticket> <issue-key>
#
# Resolves the branch's mode from REPO-OWNED state ALONE (CADENCE_ORG.md §9:
# "already synced" is decided from repo-owned state, never by reading mutable
# tracker state). Deriving it from Jira -- searching for an existing `[UMBRELLA] `
# summary -- is what would let a human rename mint a second replacement, or a
# similarly-named issue from another ticket hijack this one.
#
#   replace  no binding recorded          -> create U (JS_UMB_ISSUE decided by the create)
#   converge a binding, not this issue    -> U exists; no create, converge and retry
#   settled  a binding naming THIS issue  -> the ticket already projects onto U
js_umbrella_mode() {
  local issue_key="$2" bound
  JS_UMB_MODE=replace
  JS_UMB_ISSUE=""
  bound="$(js_metadata_get '.umbrella_epic_url')"
  [[ -n "$bound" && "$bound" != "null" ]] || return 0
  JS_UMB_ISSUE="${bound##*/}"
  if [[ "$JS_UMB_ISSUE" == "$issue_key" ]]; then JS_UMB_MODE=settled; else JS_UMB_MODE=converge; fi
  return 0
}

# js_umbrella_issue_ensure <ticket> <issue-key> <epic-E>
#
# Sets JS_UMB_ISSUE to the replacement's key. Returns 0 on a usable replacement,
# non-zero on any refusal -- and on the epic_link_unset arm it returns non-zero
# with JS_UMB_ISSUE STILL SET, because the issue EXISTS and must never be created
# twice.
js_umbrella_issue_ensure() {
  local ticket="$1" epic_e="$3"
  local summary itype project f live_link link_outcome="was already correct and is CONFIRMED -- NO live write was issued"
  if [[ "$JS_UMB_MODE" != replace ]]; then
    # SHAPE BEFORE THE WIRE. The key was derived from the repo-owned
    # `umbrella_epic_url` scalar by js_umbrella_mode, which interpolates nothing;
    # THIS is the first place it can reach a REST path, and it is guarded here
    # rather than at the assignment because jira-epic.sh calls js_umbrella_mode
    # BARE and discards its return code -- a refusal there would leave mode
    # `replace` and MINT A SECOND umbrella (archive/BTG-157/decisions.md DEC-003).
    if ! js_issue_key_valid "$JS_UMB_ISSUE"; then
      js_report syncjs.umbrella.binding_contradicted \
        "$ticket records an umbrella_epic_url whose issue key '$JS_UMB_ISSUE' is not a Jira issue key -- NO request is issued for it and NOTHING is created; fix the scalar by hand"
      JS_UMB_ISSUE=""
      return 1
    fi
    # PROVE the binding is real before acting on it. A repo that records a
    # replacement the tracker DENIES is a contradiction, not a state to
    # reconcile: a 404 from a transient fault is indistinguishable from a genuine
    # deletion, so re-creating would mint duplicates this adapter has no lock
    # with which to detect. FAIL LOUD, CREATE NOTHING (DEC-016).
    if ! js_rest GET "/rest/api/2/issue/$JS_UMB_ISSUE?fields=$JS_EPIC_LINK_FIELD" || ! js_http_ok; then
      if [[ "${JS_HTTP_STATUS:-}" == "404" ]]; then
        js_report syncjs.umbrella.binding_contradicted \
          "$ticket records $JS_UMB_ISSUE as its replacement umbrella issue and the instance answers 404 for it -- the repo and the tracker CONTRADICT each other, so NOTHING is created and nothing is moved; resolve it by hand (clear umbrella_epic_url to authorise a new replacement, or restore the issue)"
      else
        js_report syncjs.umbrella.binding_contradicted \
          "$ticket's recorded replacement $JS_UMB_ISSUE could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- an unreadable binding is not an absent one, so NOTHING is created; a re-run converges it"
      fi
      JS_UMB_ISSUE=""
      return 1
    fi
    # EXISTENCE IS NOT LINEAGE. The proof above says the bound issue is there, not
    # that it carries its Epic Link to E -- and `epic_link_unset` leaves exactly
    # that state behind for this arm to inherit. So the SAME read that proved
    # existence is used to converge the lineage: re-assert when it is not E, and
    # on a refusal return non-zero so the caller closes NOTHING and re-points
    # NOTHING. Without this the run moved the links, closed the original and
    # reported a clean `umbrella` over an umbrella with no parent, after which
    # every later run took the single-level branch -- silently, forever
    # (code-review B1 / DEC-025). Read before write: an already-correct value is
    # left alone (DEC-009), an UNSET one is re-asserted (DEC-025), and one naming
    # a DIFFERENT Epic is a human's deliberate re-parent -- a CONFLICT, refused
    # unless headless, matching the sibling child path (jira-epic.sh:250-260, DEC-014).
    live_link="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg fld "$JS_EPIC_LINK_FIELD" '.fields[$fld] // ""' 2>/dev/null)"
    if [[ "$live_link" != "$epic_e" ]] && [[ -n "$live_link" && "$live_link" != "null" ]]; then
      if [[ "$RUN_MODE" != "headless" ]]; then js_report syncjs.umbrella.epic_link_conflict "$JS_UMB_ISSUE carries a different Epic Link ($live_link, not the top-level $epic_e) -- leaving it alone; re-run with \$$HEADLESS_ENV set to overwrite deliberately (interactive is the fail-safe)"; return 1; fi
      js_report syncjs.umbrella.epic_link_conflict "$JS_UMB_ISSUE carries a different Epic Link ($live_link, not the top-level $epic_e) -- overwriting it, because \$$HEADLESS_ENV declares this run headless"
    fi
    [[ "$live_link" == "$epic_e" ]] || { js_umbrella_epic_link "$JS_UMB_ISSUE" "$epic_e" || return 1; link_outcome="was RE-ASSERTED by a live write, CONFIRMED by a read-back"; }
    # Mode `settled` reports its own terminal condition (`at_replacement`) at the
    # END of the branch, so nothing is reported here for it -- exactly one named
    # condition per outcome (journey invariant JI-10).
    [[ "$JS_UMB_MODE" == converge ]] && js_report syncjs.umbrella.issue_at_target \
      "$ticket already has the replacement umbrella issue $JS_UMB_ISSUE -- NO second one is created, its Epic Link to $epic_e $link_outcome; this run converges the ordered links and retries the close"
    return 0
  fi
  summary="$(js_umbrella_summary "$(js_metadata_get '.title')")" || {
    js_report syncjs.umbrella.title_absent \
      "$ticket has an empty title -- the replacement umbrella issue is NOT created rather than born with a bare '$JS_UMBRELLA_PREFIX' or a guessed summary"
    return 1
  }
  # The SAME config key the deleted re-type used, re-pointed from an update to a
  # CREATE (DEC-013): the key keeps its meaning ("the type an umbrella is") and
  # merely stops being applied destructively.
  itype="$(js_config_map umbrella issue_type)" || return "$JS_EXIT_CONFIG"
  project="$(js_project_key "$ticket")" || project=""
  [[ -n "$project" ]] || { js_report syncjs.umbrella.issue_create_rejected \
      "no project key resolved for $ticket -- no replacement umbrella issue is created"; return 1; }
  # SHAPE BEFORE THE WIRE, on the CREATE path too. The converge path already
  # renders its verdict before any request (:72); this is the one path where the
  # wire ran first, so a key this adapter cannot use cost a REAL created issue
  # and left it unbound. The probe is the SAME predicate (DEC-015), asked of the
  # shape a key minted in THIS project must take. It is never assigned, never
  # interpolated, never recorded -- the real key is still READ at the response
  # and still guarded below. An ADDITION, not a relocation: the post-POST guard
  # stays (btg-157-hardenings mutant 2).
  if ! js_issue_key_valid "${project}-1"; then
    js_report syncjs.umbrella.issue_create_rejected \
      "$ticket resolves to project key '$project', in which no issue key this adapter can use could be minted -- NOTHING is created and NO request is issued; an accepted key is an uppercase-alphanumeric project part, a hyphen, then digits, and the project key is declared in CADENCE_ORG.md section 9"
    return 1
  fi
  f="$(mktemp 2>/dev/null)" || { js_report syncjs.umbrella.scratch_unavailable \
      "no scratch file could be staged for $ticket's replacement umbrella body -- creating NOTHING; an unstaged body degrades the POST into a BODYLESS one a permissive server accepts"; return 1; }
  # The same three-field shape jira-reserve.sh:56-58 uses. The Epic Link is
  # deliberately NOT in the create body: nothing establishes that the field is on
  # this instance's create screen, and a create that 400s costs a whole run.
  if ! js_build_body "$f" syncjs.umbrella.issue_body_unbuildable "the replacement umbrella body for $ticket" \
       -n --arg p "$project" --arg s "$summary" --arg t "$itype" \
       '{fields: {project: {key: $p}, summary: $s, issuetype: {name: $t}}}'; then
    rm -f "$f"; return 1
  fi
  if ! js_rest POST "/rest/api/2/issue" "$f" || ! js_http_ok; then
    rm -f "$f"
    js_report syncjs.umbrella.issue_create_rejected \
      "creating the replacement umbrella issue for $ticket at '$itype' was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- NOTHING was mutated: the create is the first write, so a failure here costs nothing and a re-run retries it"
    return 1
  fi
  rm -f "$f"
  # Direct REST v2 returns the created key at the TOP level. It is READ, never
  # computed: PROD_CADENCE-011 is the entry where a computed key reached the wire and the
  # run still reported success.
  # The SAME shape predicate the recorded-binding site uses (DEC-015): this value
  # is INSTANCE-supplied, and it is interpolated into `PUT /rest/api/2/issue/$key`
  # by js_umbrella_epic_link. The existing non-empty test is STRENGTHENED to
  # well-shaped rather than given an arm of its own -- a malformed key is the same
  # failure through the same door, so no condition name is minted.
  JS_UMB_ISSUE="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.key // empty' 2>/dev/null)"
  if ! js_issue_key_valid "$JS_UMB_ISSUE"; then
    # A 2xx response carrying NO key at all and a 2xx response carrying a
    # MALFORMED one both reach here (both fail the same shape check), but the
    # two read differently: an empty key has nothing to name, so "CREATED
    # issue ''" / "resolve '' by hand" would be unactionable. Both branches
    # agree on the FACT (an issue exists, no binding, a re-run creates
    # ANOTHER one, not a retry) -- only the wording of WHICH key differs.
    if [[ -n "$JS_UMB_ISSUE" ]]; then
      js_report syncjs.umbrella.issue_create_rejected \
        "the replacement umbrella creation for $ticket returned HTTP $JS_HTTP_STATUS and CREATED issue '$JS_UMB_ISSUE', but that key is not one this adapter can use -- never assume the key you computed; NO binding is recorded for it, and a re-run does NOT retry the create -- it creates ANOTHER issue; resolve '$JS_UMB_ISSUE' by hand"
    else
      js_report syncjs.umbrella.issue_create_rejected \
        "the replacement umbrella creation for $ticket returned HTTP $JS_HTTP_STATUS and CREATED an issue whose key the response did not carry -- never assume the key you computed; NO binding is recorded for it, and a re-run does NOT retry the create -- it creates ANOTHER issue; resolve the created issue by hand"
    fi
    JS_UMB_ISSUE=""
    return 1
  fi
  # The Epic Link to E, in its OWN write -- the custom field only, never an
  # issuetype, so AC-3 holds by construction. From here on JS_UMB_ISSUE stays SET
  # even on a refusal: the issue EXISTS, and a caller that dropped the binding
  # would mint a SECOND replacement on the next run.
  js_umbrella_epic_link "$JS_UMB_ISSUE" "$epic_e" || return 1
  js_report syncjs.umbrella.issue_created \
    "$JS_UMB_ISSUE created at '$itype' as the replacement umbrella for $ticket (top-level Epic $epic_e) -- BORN at that type, so no existing issue's workflow is stranded"
  return 0
}

# js_umbrella_epic_link <replacement-key> <epic-E>
#
# One write, one MANDATORY read-back. PROD_CADENCE-006 is the entry where a write's
# read-back verified THE FIELD IT SET rather than the thing that had to be true
# afterwards; here they are the same field, and the read-back is what makes
# `epic_link_unset` reachable at all rather than decorative.
#
# Every failure of this step -- an unstageable scratch file, a jq build that
# produced nothing, a non-2xx, or a 2xx whose value did not land -- is the SAME
# outcome: a replacement with no lineage. So all four report the one condition
# the spec names for this step, and the caller must NOT report again.
js_umbrella_epic_link() {
  local key="$1" epic_e="$2" f rc=1
  f="$(mktemp 2>/dev/null)" || {
    js_report syncjs.umbrella.epic_link_unset \
      "$key exists but no scratch file could be staged for its Epic Link body, so its lineage to $epic_e is NOT set -- the binding is still recorded and the next run converges it"
    return 1
  }
  if js_build_body "$f" syncjs.umbrella.epic_link_unset "the Epic Link body for $key" \
       -n --arg fld "$JS_EPIC_LINK_FIELD" --arg v "$epic_e" '{fields: {($fld): $v}}'; then
    if ! js_rest PUT "/rest/api/2/issue/$key" "$f" || ! js_http_ok \
       || ! js_rest GET "/rest/api/2/issue/$key?fields=$JS_EPIC_LINK_FIELD" || ! js_http_ok \
       || [[ "$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg fld "$JS_EPIC_LINK_FIELD" '.fields[$fld] // ""' 2>/dev/null)" != "$epic_e" ]]; then
      js_report syncjs.umbrella.epic_link_unset \
        "$key's Epic Link could not be confirmed as $epic_e (HTTP ${JS_HTTP_STATUS:-unreachable}) -- reported rather than assumed; the replacement EXISTS and its binding is recorded, the original is NOT closed, and the next run converges it"
    else
      rc=0
    fi
  fi
  rm -f "$f"
  return "$rc"
}

# The ORIGINAL-RETIREMENT half (ordered-link discovery/retirement, and the
# superseded original's close/transition) lives in a sibling module --
# BTG-247, this file's own split. Sourced here so jira-epic.sh (which sources
# ONLY this file) gets it transitively.
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-umbrella-retire.sh"

