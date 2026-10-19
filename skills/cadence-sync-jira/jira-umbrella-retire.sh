#!/usr/bin/env bash
#
# jira-umbrella-retire.sh -- the ORIGINAL-RETIREMENT half of jira-umbrella-lib.sh
# (BTG-247 row: jira-umbrella-lib.sh split). MOVED VERBATIM from the parent
# (pre-split lines :209-:397): the ordered-link discovery/retirement functions
# and the superseded-original close/transition function. All four run AFTER
# the replacement (jira-umbrella-lib.sh's own remaining half) has been created
# and bound -- this module's whole concern is what happens to the OLD issue
# and its stale ordered links once the new one exists, never issue creation.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-105), same
# as jira-umbrella-lib.sh. SOURCED by jira-umbrella-lib.sh via a
# ${BASH_SOURCE[0]}-relative path, so jira-epic.sh (which sources ONLY
# jira-umbrella-lib.sh) gets this module transitively with no call-site change.
#
# References: archive/BTG-247/spec.md ; archive/BTG-247/decisions.md (this
# split's own DEC entry) ; archive/BTG-105/spec.md (Proposed Design) ;
# jira-server-scripts.md.

# js_umbrella_ordered_type <child-set>
#
# The ordered type for the child links, DISCOVERED from the instance (this org's
# is named `precedes ` -- TRAILING SPACE), reusing the same machinery and the
# same inversion calibration as a related-ticket link. Read once, and only when
# there are children to link.
#
# RELOCATED WHOLE from jira-epic.sh, behaviour unchanged, under the DX ceiling
# that file is bound by (btg-046-ac-sync.test.sh S-42.5). See decisions.md
# DEC-020: the spec's RISK-1 mitigation named UMBRELLA WRITE 4 as the block to
# relocate; this block was chosen instead because it is smaller, cohesive with
# this module's concern, and -- unlike WRITE 4 -- contains no `continue` that a
# function boundary would change the meaning of.
#
# Sets UMB_ORDERED / UMB_PRED_SLOT in the caller. Returns non-zero for a config
# HALT, which the caller propagates: an absent binding is never defaulted here to
# a name the adopter is entitled to rebind (AC-7).
js_umbrella_ordered_type() {
  local children="$1" default_rel ordered_id
  UMB_ORDERED=""
  JS_ORDERED_STATE=""
  JS_LINK_REPORT_PREFIX=syncjs.umbrella
  [[ -n "$children" ]] || return 0
  default_rel="$(js_config_map link_relations default)" || return "$JS_EXIT_CONFIG"
  IFS='|' read -r _ UMB_PRED_SLOT ordered_id <<<"$(js_config_ordered_relation)" || return "$JS_EXIT_CONFIG"
  [[ -n "$UMB_PRED_SLOT" ]] || return "$JS_EXIT_CONFIG"
  js_ordered_type_discover "$ordered_id" "$default_rel" && UMB_ORDERED="$JS_ORDERED_NAME"
  return 0
}

# js_umbrella_stale_links <original-key>
#
# ONE read of the original's issue links, taken BEFORE the child loop, so the
# whole move works from a single consistent snapshot rather than re-reading per
# child. Sets JS_UMB_T_READ=ok|failed and JS_UMB_T_LINKS.
#
# An unreadable answer is NOT an empty one: it sets `failed`, and the caller then
# counts every child unapplied rather than deleting blind. The delete is the one
# IRREVERSIBLE write on this path, so it is never issued on a guess.
js_umbrella_stale_links() {
  local key="$1"
  JS_UMB_T_LINKS=""
  JS_UMB_T_READ=failed
  if ! js_rest GET "/rest/api/2/issue/$key?fields=issuelinks" || ! js_http_ok; then
    js_report syncjs.umbrella.ordered_stale_unreadable \
      "$key's issue links could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- NO stale ordered link is deleted on a guess, so every child counts as unapplied, $key is NOT closed and a re-run converges them"
    return 1
  fi
  JS_UMB_T_LINKS="$JS_HTTP_BODY"
  JS_UMB_T_READ=ok
  return 0
}

# js_umbrella_ordered_retire <original-key> <child-key> <ordered-type-name>
#      -> JS_UMB_RETIRE=retired|absent|failed|unreadable
#
# CALLED ONLY AFTER the replacement link for the same pair is VERIFIED
# (create-before-delete), so a child is never left with ZERO ordering links --
# worst case dual-linked, which is visible, counted and convergent (RULING 3 /
# DEC-015).
#
# The link id is DISCOVERED from the snapshot, never computed, and matched in
# EITHER direction: a link a prior run created reversed must still be retired. A
# per-issue read names only the FAR endpoint, so the near end defaults to the
# original's own key.
js_umbrella_ordered_retire() {
  local self="$1" child="$2" rel="$3" id
  JS_UMB_RETIRE=absent
  if [[ "${JS_UMB_T_READ:-failed}" != ok ]]; then JS_UMB_RETIRE=unreadable; return 0; fi
  id="$(printf '%s' "$JS_UMB_T_LINKS" | jq -r --arg r "$rel" --arg c "$child" --arg s "$self" '
      [ (.fields.issuelinks // [])[]
        | select((.type.name // "") == $r)
        | {id: .id, a: (.inwardIssue.key // $s), b: (.outwardIssue.key // $s)}
        | select((.a == $c and .b == $s) or (.b == $c and .a == $s))
        | .id ][0] // empty' 2>/dev/null)"
  # No matching link is the CONVERGED steady state -- no write, no condition. A
  # human who deleted it first has simply reached the same place.
  [[ -n "$id" ]] || return 0
  if js_rest DELETE "/rest/api/2/issueLink/$id" && js_http_ok; then
    js_report syncjs.umbrella.ordered_retired \
      "the stale ordered link $id between $child and the superseded $self was retired, AFTER its replacement was verified -- $child now carries exactly one ordering link"
    JS_UMB_RETIRE=retired
  else
    js_report syncjs.umbrella.ordered_dual_linked \
      "$child is linked to BOTH the superseded $self and its replacement: the new ordered link IS in place but removing the stale link $id was refused (HTTP ${JS_HTTP_STATUS:-unreachable}) -- never unlinked, only dual-linked; $self is NOT closed and a re-run retries the delete"
    JS_UMB_RETIRE=failed
  fi
  return 0
}

# js_umbrella_original_close <original-key>
#      -> JS_UMB_CLOSE=closed|at-target|unmapped|unreachable|rejected|unverified
#
# Retires the superseded original by TRANSITION, never by re-type and never by
# delete: it keeps its type, its Epic Link to E and its summary, and becomes the
# closed record that a supersession occurred (Alternative 5 rejected -- a delete
# destroys the evidence trail PROD_CADENCE-014 and BTG-103 both rest on).
#
# BTG-040 carve-out, ratified by the human gate (RULING 4 / DEC-014): "an Epic's
# status is never touched" is scoped to jira-transition.sh, which this change
# leaves untouched, and the original is not typed `Epic` in Jira.
#
# NEVER returns non-zero: best-effort halts the BRANCH, never the ticket
# (DEC-033).
js_umbrella_original_close() {
  local key="$1" live_type current target id offered f
  JS_UMB_CLOSE=rejected
  # The LIVE type, read from the instance -- never the repo's `type:`, which is
  # `epic` here and would resolve the wrong workflow's terminal status.
  if ! js_rest GET "/rest/api/2/issue/$key?fields=status,issuetype" || ! js_http_ok; then
    js_report syncjs.umbrella.close_rejected \
      "$key's live status and type could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- it is NOT transitioned on a guess; it stays open and a re-run retries"
    return 0
  fi
  live_type="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.fields.issuetype.name // ""' 2>/dev/null)"
  current="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.fields.status.name // ""' 2>/dev/null)"
  # The terminal status this config ALREADY declares for that type. No new key.
  if ! target="$(js_config_map2 status_workflow_map "$live_type" archived)"; then
    js_report syncjs.umbrella.close_unmapped \
      "no status_workflow_map entry declares an 'archived' status for issue type '$live_type', so the superseded $key has no close target on this instance -- it is left OPEN and reported rather than transitioned somewhere unmapped"
    JS_UMB_CLOSE=unmapped
    return 0
  fi
  if [[ "$current" == "$target" ]]; then
    js_report syncjs.umbrella.close_at_target \
      "$key is already at '$target' -- the superseded original needs no transition and none is issued"
    JS_UMB_CLOSE=at-target
    return 0
  fi
  # RESOLVED BY OBSERVATION, never assumed.
  if ! js_rest GET "/rest/api/2/issue/$key/transitions" || ! js_http_ok; then
    js_report syncjs.umbrella.close_rejected \
      "$key's offered transitions could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- refusing to transition blind; it stays open and a re-run retries"
    return 0
  fi
  offered="$(printf '%s' "$JS_HTTP_BODY" | jq -r '[(.transitions // [])[] | ((.to.name // .name // "?") + " (id " + (.id|tostring) + ")")] | join(", ")' 2>/dev/null)"
  id="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg t "$target" '[(.transitions // [])[] | select((.to.name // "") == $t) | .id][0] // empty' 2>/dev/null)"
  # The EXISTING global_transitions escape hatch -- exactly why it is declared:
  # the reachable terminus for a workflow whose transition set has collapsed.
  [[ -n "$id" ]] || id="$(js_config_map2 status_workflow_map global_transitions "$target")" || id=""
  if [[ -z "$id" ]]; then
    # NO WALK, NO GUESS. A collapsed transition set is exactly where a multi-hop
    # walk wanders onto an ungoverned state, which is why jira-transition.sh's
    # walk is deliberately not reused here.
    js_report syncjs.umbrella.close_unreachable \
      "no transition offered on $key lands on '$target' and no global_transitions id is declared for it -- the superseded original stays OPEN (benign: the children already point at its replacement). Offered: ${offered:-<none>}"
    JS_UMB_CLOSE=unreachable
    return 0
  fi
  # THE ADAPTER'S OWN FAILURE, NAMED AS ITS OWN (B-9). `close_rejected` asserts
  # the INSTANCE refused something; a scratch file this process could not stage
  # is not the instance's doing, and this is the one site whose name literally
  # says "rejected". `scratch_unavailable` is ALREADY the vocabulary's name for
  # exactly this failure (see the create path above) -- reused, so no name is
  # minted and none is removed (archive/BTG-113/decisions.md DEC-018).
  f="$(mktemp 2>/dev/null)" || {
    js_report syncjs.umbrella.scratch_unavailable \
      "no scratch file could be staged for $key's transition body -- issuing NO transition rather than a bodyless one; $key stays open"
    return 0
  }
  # The ADDITIVE name (DEC-018 / archive/BTG-157/decisions.md DEC-004), derived from
  # the shipped `<subject>_body_unbuildable` pattern -- `issue_body_unbuildable`
  # above, `child_epic_link_body_unbuildable` in jira-epic.sh. js_build_body
  # reports whatever token it is handed, so the misnaming was HERE, at the call
  # site, never in the callee.
  if ! js_build_body "$f" syncjs.umbrella.close_body_unbuildable "the close transition body for $key" \
       -n --arg id "$id" '{transition: {id: $id}}'; then
    rm -f "$f"; return 0
  fi
  if ! js_rest POST "/rest/api/2/issue/$key/transitions" "$f" || ! js_http_ok; then
    rm -f "$f"
    js_report syncjs.umbrella.close_rejected \
      "transitioning the superseded $key to '$target' with id $id was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- NO retry and no second POST; it stays open and a re-run resolves the id afresh"
    return 0
  fi
  rm -f "$f"
  # MANDATORY read-back -- the PROD_CADENCE-006 shape applied to status.
  if ! js_rest GET "/rest/api/2/issue/$key?fields=status" || ! js_http_ok \
     || [[ "$(printf '%s' "$JS_HTTP_BODY" | jq -r '.fields.status.name // ""' 2>/dev/null)" != "$target" ]]; then
    js_report syncjs.umbrella.close_unverified \
      "$key's status could not be confirmed as '$target' after the transition returned HTTP $JS_HTTP_STATUS -- reported rather than assumed, so the ticket is NOT re-pointed at its replacement while the original may still be open"
    JS_UMB_CLOSE=unverified
    return 0
  fi
  js_report syncjs.umbrella.closed \
    "$key was transitioned to '$target' (id $id) as a superseded umbrella -- its type, its Epic Link and its summary are UNCHANGED; it stays as the record of what was replaced"
  JS_UMB_CLOSE=closed
  return 0
}
