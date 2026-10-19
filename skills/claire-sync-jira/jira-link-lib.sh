#!/usr/bin/env bash
#
# jira-link-lib.sh -- the ORDERED-LINK machinery, shared by the two operations
# that create ordered links: `jira-link.sh` (related tickets) and `jira-epic.sh`
# (the umbrella's child `is preceded by` links).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary, live-verified on this org's
# instance (archive/BTG-036/submission.md): **the ordering link type is not named
# what a config would guess.** It is `precedes ` -- lowercase, TRAILING SPACE, id
# 10400 -- while its outward/inward LABELS are the clean `precedes` / `is preceded
# by`. Matching or posting `"Precedes"` matches no stored link and is rejected, so
# the type is DISCOVERED at run time and matched on its PHRASING, never its name.
#
# It exists so the umbrella branch reuses this machinery verbatim: a second
# implementation of the inversion calibration is a second chance to record every
# ordering backwards.
# Upstream: sourced by jira-link.sh and jira-epic.sh. Downstream:
# `GET .../issueLinkType`. Spec: archive/BTG-075/spec.md ; jira-server-scripts.md.
#
# It is SOURCED -- not an entry point, and it runs nothing on load.
#
# The RAW-comment reader that feeds `js_relation_from_signal` its input lives in
# jira-meta.sh with the other owned-data readers; this file owns the inference and
# the link machinery, not the file format.

# --------------------------------------------------------------------------
# The relation SIGNAL of a flat `related_tickets` entry (the sidecar's step 7a)
# --------------------------------------------------------------------------
# js_relation_from_signal <signal-text> -- the declaring KEY this signal implies,
# so the flat shape and the structured shape converge on one code path.
#
# The sidecar's rule, and the one most often applied backward: **ordering
# reflects the planned LANDING order, not genealogy.** That R spawned, originated
# or is the parent of C is a historical fact, not a sequencing constraint, and it
# projects SYMMETRIC. Only an explicit landing dependency orders a link.
#
# Prints the key; returns 2 when the direction cannot be determined -- the signal
# asserts BOTH directions, or names THIS ticket on both sides of one dependency
# clause -- so the caller reports the ambiguity rather than picking one and
# recording an ordering backwards. Deliberately NOT included as an ordering
# keyword: a bare `after`, which in prose ("named after", "cleanup after") points
# at nothing.
js_relation_from_signal() {
  local sig r_first=0 c_first=0 exchanged=0 confirmed=0 swap
  sig="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$sig" in                              # R lands first -> R is predecessor
    *"depends on"*|*"depends upon"*|*"blocked by"*|*"prerequisite:"*|\
    *"assumed merged before"*|*"merged before"*|*"must land first"*|\
    *"lands first"*|*"must merge first"*) r_first=1 ;;
  esac
  case "$sig" in                              # C lands first -> this is predecessor
    *"blocks"*|*"must land before"*|*"lands before"*|*"prerequisite for"*|\
    *"must merge before"*) c_first=1 ;;
  esac
  # SUBJECT-AWARENESS (DEC-053). Each keyword above carries an ASSUMED subject:
  # `depends on` reads "THIS depends on R"; the objectless `must land first` reads
  # "R must land first". A comment written from the other end names the OTHER
  # subject -- archive/BTG-016a's entry for BTG-016b reads "[BTG-016b] ... depends
  # on THIS ticket", which means BTG-016b lands AFTER, not before. Matching the
  # keyword alone recorded that real ordering BACKWARDS and reported `created`.
  #   EXCHANGED -- a self-reference in the OBJECT slot of a clause whose assumed
  #                object is the REFERENCED ticket, or in the SUBJECT slot of an
  #                objectless one.
  #   CONFIRMED -- a self-reference in the SUBJECT slot of an object-taking
  #                clause, or in the object slot of a clause whose assumed object
  #                ALREADY is this ticket (`R merged before this one`) -- the
  #                assumed reading, stated explicitly.
  # BOTH at once names THIS ticket on both sides: the subject genuinely cannot be
  # determined, so it takes the SAME degrade-and-report path a contradictory
  # signal does. Guessing a direction is the failure this whole calibration
  # exists to prevent -- it is never the fallback.
  local obj_self='(depends on|depends upon|blocked by|blocks|must land before|lands before|land before|must merge before|merge before|prerequisite for) this($|[^a-z])'
  local self_first='this( [a-z]+)? (must land first|lands first|must merge first)'
  local self_subj='(this( [a-z]+)? (depends|is blocked|blocks|is a prerequisite)|merged before this($|[^a-z]))'
  [[ "$sig" =~ $obj_self || "$sig" =~ $self_first ]] && exchanged=1
  [[ "$sig" =~ $self_subj ]] && confirmed=1
  if [[ "$exchanged" -eq 1 && "$confirmed" -eq 1 ]]; then
    printf 'related_tickets\n'
    return 2
  fi
  if [[ "$exchanged" -eq 1 ]]; then swap="$r_first"; r_first="$c_first"; c_first="$swap"; fi
  if [[ "$r_first" -eq 1 && "$c_first" -eq 1 ]]; then
    printf 'related_tickets\n'
    return 2
  fi
  [[ "$r_first" -eq 1 ]] && { printf 'preceded_by\n'; return 0; }
  [[ "$c_first" -eq 1 ]] && { printf 'precedes\n';    return 0; }
  case "$sig" in
    *duplicate*|*"dup of"*)            printf 'duplicates\n'; return 0 ;;
    *clone*|*"copy of"*)               printf 'clones\n';     return 0 ;;
  esac
  printf 'related_tickets\n'
}

# --------------------------------------------------------------------------
# Ordered link-type discovery (the deleted sidecar's step 7c)
# --------------------------------------------------------------------------
# js_ordered_type_discover <configured-id> <default-type> -- resolve the ordered
# type ONCE per run. Sets:
#   JS_ORDERED_NAME   the type name to send and to match stored links against
#   JS_ORDERED_STATE  discovered | fallback | undiscoverable
#
# Three outcomes, deliberately distinct (the last is Behavior 5):
#   * the `precedes` / `is preceded by` phrasing exists -> `discovered`; the live
#     name is used verbatim.
#   * the instance genuinely has no such type -> `fallback`: the symmetric default
#     is used and the LOSS OF ORDERED SEMANTICS is reported.
#   * the list could not be READ -> `undiscoverable`: nothing is guessed. An
#     unreadable list is not an absent type, and downgrading on a transient 500
#     records a symmetric relation the next run cannot tell from a deliberate one.
# Returns 0 for the first two, non-zero for the third.
js_ordered_type_discover() {
  local cfg_id="$1" default_type="$2" prefix="${JS_LINK_REPORT_PREFIX:-syncjs.link}" name
  JS_ORDERED_NAME=""
  JS_ORDERED_STATE=undiscoverable
  if ! js_rest GET "/rest/api/2/issueLinkType" || ! js_http_ok; then
    js_report "$prefix.type_undiscoverable" \
      "the instance's issue link types could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- an unreadable list is not an absent type, so no ordered link type is guessed"
    return 1
  fi
  # Match on the outward/inward PHRASING, case- and whitespace-insensitively (the
  # live type's own name carries a trailing space; its labels do not). Among the
  # phrasing matches the CONFIGURED id wins, so an adopter can disambiguate two
  # look-alike types without the id ever being able to select a non-ordering one.
  name="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg id "$cfg_id" '
      def norm: (. // "") | ascii_downcase | gsub("^\\s+|\\s+$"; "");
      [ (.issueLinkTypes // [])[]
        | select((.outward | norm) == "precedes" and (.inward | norm) == "is preceded by") ] as $c
      | ((([ $c[] | select(.id == $id) ] + $c)[0].name) // empty)' 2>/dev/null)"
  if [[ -n "$name" ]]; then
    JS_ORDERED_NAME="$name"
    JS_ORDERED_STATE=discovered
    return 0
  fi
  JS_ORDERED_NAME="$default_type"
  JS_ORDERED_STATE=fallback
  js_report "$prefix.type_fallback" \
    "no link type on this instance carries the 'precedes' / 'is preceded by' phrasing -- falling back to '$default_type', which is SYMMETRIC: the ordering semantics are lost and only the relation is recorded"
  return 0
}

# js_link_type_by_name <config-key> <default-type>
# Resolve a STOCK link type (Duplicate, Cloners) against the live instance by NAME,
# CASE-INSENSITIVELY, falling back to <default-type> and REPORTING. Sets
# JS_LINK_TYPE_NAME / JS_LINK_TYPE_STATE=discovered|fallback|undiscoverable.
#
# Stock names are NOT safe to hardcode -- renameable, localized, per-instance; this
# org's ordered type is named `precedes ` with a trailing space. A hardcoded name
# has its POST rejected and the relation is never recorded. The ordered type got
# this treatment in DEC-031; AC-7 applies no less to the other two.
js_link_type_by_name() {
  local cfg_key="$1" default_type="$2" prefix="${JS_LINK_REPORT_PREFIX:-syncjs.link}" want name
  JS_LINK_TYPE_NAME=""
  JS_LINK_TYPE_STATE=undiscoverable
  want="$(js_config_map link_relations "$cfg_key")" || return "$JS_EXIT_CONFIG"
  if ! js_rest GET "/rest/api/2/issueLinkType" || ! js_http_ok; then
    js_report "$prefix.type_undiscoverable" \
      "the instance's issue link types could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- an unreadable list is not an absent type, so the '$want' type is not guessed"
    return 1
  fi
  name="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg w "$want" '
      def norm: (. // "") | ascii_downcase | gsub("^\\s+|\\s+$"; "");
      [ (.issueLinkTypes // [])[] | select((.name | norm) == ($w | norm)) ][0].name // empty' 2>/dev/null)"
  if [[ -n "$name" ]]; then
    JS_LINK_TYPE_NAME="$name"
    JS_LINK_TYPE_STATE=discovered
    return 0
  fi
  JS_LINK_TYPE_NAME="$default_type"
  JS_LINK_TYPE_STATE=fallback
  js_report "$prefix.type_fallback" \
    "this instance carries no link type named '$want' -- falling back to '$default_type', which records the relation but LOSES its specific meaning; rename the type or rebind link_relations.$cfg_key to what this instance calls it"
  return 0
}

# --------------------------------------------------------------------------
# Direction read-back + create (the deleted sidecar's steps 7e-7f)
# --------------------------------------------------------------------------
# js_link_verify_direction <self> <target> <type> <expected-inward> <expected-outward>
# Recover the link's ABSOLUTE record and classify its stored direction:
#   0 -- a link of this type connects the pair in the EXPECTED orientation
#   1 -- it connects them REVERSED (its id is left in JS_LINK_STORED_ID)
#   2 -- the read SUCCEEDED and no such link exists
#   3 -- the READ ITSELF FAILED, so nothing at all is known about the pair
#
# 2 and 3 are NOT the same answer and must never share a code. "No such link" is
# an instruction to create one; "I could not look" is not. Conflated, a transient
# 5xx POSTed links for pairs whose state was never read -- and Jira Server does
# not dedupe REST-created links, so each affected run appended a duplicate. Worse,
# a stored REVERSED link never had its id captured: the correct link was created
# beside it, post-verify answered "ok", and the reversed one was left permanently
# and unreported. Same refusal jira-link.sh makes on ITS snapshot read.
#
# The read is PERSPECTIVE-DEPENDENT (DEC-015, live-verified on PLAYSCRUM-3373/3374
# link 111507): a per-issue `issuelinks` entry names ONLY the FAR endpoint. The
# omitted near end is ALWAYS the issue being read, so it is folded back in with
# `// $self` before anything is classified -- comparing the raw slots leaves one
# side empty on every entry and cannot tell a correct link from a reversed one.
#
# `js_link_classify` holds the classification and takes an ALREADY-READ body, so
# jira-link.sh's whole-ticket snapshot and this per-issue read are two callers of
# ONE implementation. They used to be two implementations of one rule, and the
# `// $self` far-endpoint fold-in had to be fixed in each separately.
js_link_classify() {
  local links_json="$1" self="$2" target="$3" rel="$4" want_in="$5" want_out="$6" verdict
  JS_LINK_STORED_ID=""
  verdict="$(printf '%s' "$links_json" | jq -r \
      --arg self "$self" --arg t "$target" --arg rel "$rel" \
      --arg win "$want_in" --arg wout "$want_out" '
      [ (.fields.issuelinks // [])[]
        | select(.type.name == $rel)
        | {id: .id, in: (.inwardIssue.key // $self), out: (.outwardIssue.key // $self)}
        | select((.in == $t and .out == $self) or (.out == $t and .in == $self)) ] as $pair
      | if   ([ $pair[] | select(.in == $win and .out == $wout) ] | length) > 0 then "ok"
        elif ($pair | length) > 0 then "reversed \($pair[0].id)"
        else "none" end' 2>/dev/null)"
  case "$verdict" in
    ok)         return 0 ;;
    reversed*)  JS_LINK_STORED_ID="${verdict#reversed }"; return 1 ;;
    none)       return 2 ;;
    # an empty/unparseable verdict means jq could not classify the body -- that is
    # a failed read, not an absent link, and it takes the fail-closed code
    *)          return 3 ;;
  esac
}

js_link_verify_direction() {
  local self="$1" target="$2" rel="$3" want_in="$4" want_out="$5"
  JS_LINK_STORED_ID=""
  if ! js_rest GET "/rest/api/2/issue/$self?fields=issuelinks" || ! js_http_ok; then
    return 3
  fi
  js_link_classify "$JS_HTTP_BODY" "$self" "$target" "$rel" "$want_in" "$want_out"
}

# js_link_create_verified <self> <target> <type> <inward> <outward> <ordered 0|1>
# Create the link and, for an ORDERED type, prove its stored direction.
#   0 -- created (and, when ordered, verified)
#   1 -- the create was rejected; nothing was written
#   2 -- created, but the direction could NOT be confirmed even after a self-heal
#
# A 201 is not proof: `POST /rest/api/2/issueLink` answers with an EMPTY body, so
# the record is recovered by re-reading the issue. Ordered links are easy to
# create reversed, and an unverified one renders backwards on the board forever.
#
# The self-heal creates the exchanged link BEFORE removing the reversed one
# (DEC-029): worst case both are present -- visible and repairable -- rather than
# the pair silently unlinked.
js_link_create_verified() {
  local self="$1" target="$2" rel="$3" inward="$4" outward="$5" ordered="${6:-0}"
  local prefix="${JS_LINK_REPORT_PREFIX:-syncjs.link}" body rc reversed_id
  body="$(mktemp 2>/dev/null)" || { js_report "$prefix.scratch_unavailable" "no scratch file could be staged for the $rel link body for $self -> $target -- nothing was sent"; return 1; }
  # BOTH questions, one builder (BTG-084). The status was checked here but the
  # CONTENT was not, and there was no `2>/dev/null`, so a jq that exited 0 having
  # written nothing POSTed a BODYLESS issueLink -- an opaque 400 -- and jq's raw
  # diagnostic reached the channel DEC-001 reserves for syncjs.* alone.
  if ! js_build_body "$body" "$prefix.link_body_unbuildable" "the $rel link body for $self -> $target" \
       -n --arg rel "$rel" --arg in "$inward" --arg out "$outward" \
       '{type: {name: $rel}, inwardIssue: {key: $in}, outwardIssue: {key: $out}}'; then
    rm -f "$body"
    return 1
  fi
  if ! js_rest POST "/rest/api/2/issueLink" "$body" || ! js_http_ok; then
    rm -f "$body"
    return 1
  fi
  if [[ "$ordered" != "1" ]]; then
    rm -f "$body"
    return 0
  fi
  js_link_verify_direction "$self" "$target" "$rel" "$inward" "$outward"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    rm -f "$body"
    return 0
  fi
  if [[ "$rc" -eq 2 || "$rc" -eq 3 ]]; then
    js_report "$prefix.link_unverified" \
      "the $rel link $self -> $target was accepted (HTTP $JS_HTTP_STATUS) but the read-back $([[ "$rc" -eq 3 ]] && printf 'FAILED' || printf 'found no such link on the issue') -- its direction is NOT confirmed and is never assumed from the 201"
    rm -f "$body"
    return 2
  fi
  # stored REVERSED: recreate with the slots exchanged, then remove the original
  reversed_id="$JS_LINK_STORED_ID"
  js_report "$prefix.direction_reversed" \
    "the instance stored the $rel link $self -> $target with the slots reversed -- creating the exchanged link FIRST, then removing link $reversed_id, so no step can leave the pair unlinked"
  # The subject carries the OPERATOR-CRITICAL detail verbatim: an operator who
  # reads "could not be built" and assumes the pair was torn down would go looking
  # for a link that is still there.
  if ! js_build_body "$body" "$prefix.link_body_unbuildable" \
       "the exchanged $rel link body for $self -> $target -- the reversed link $reversed_id is LEFT IN PLACE and nothing was deleted --" \
       -n --arg rel "$rel" --arg in "$outward" --arg out "$inward" \
       '{type: {name: $rel}, inwardIssue: {key: $in}, outwardIssue: {key: $out}}'; then
    rm -f "$body"
    return 2
  fi
  if ! js_rest POST "/rest/api/2/issueLink" "$body" || ! js_http_ok; then
    js_report "$prefix.link_unverified" \
      "the exchanged $rel link $self -> $target was refused (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the reversed link $reversed_id is deliberately LEFT IN PLACE and nothing was deleted; the ordering still renders backwards and the next run retries"
    rm -f "$body"
    return 2
  fi
  rm -f "$body"
  if ! js_link_verify_direction "$self" "$target" "$rel" "$inward" "$outward"; then
    js_report "$prefix.link_unverified" \
      "the $rel link $self -> $target is still not stored in the intended direction after the self-heal -- reported rather than left silently backwards"
    return 2
  fi
  if js_rest DELETE "/rest/api/2/issueLink/$reversed_id" && js_http_ok; then
    js_report "$prefix.direction_healed" \
      "the reversed $rel link $reversed_id between $self and $target was removed after its correctly-ordered replacement landed and was verified"
  else
    js_report "$prefix.heal_incomplete" \
      "the correctly-ordered $rel link between $self and $target IS in place and verified, but removing the reversed link $reversed_id was refused (HTTP ${JS_HTTP_STATUS:-unreachable}) -- BOTH links are present; delete $reversed_id by hand or re-run"
  fi
  return 0
}

# js_link_upsert_ordered <self> <target> <type> <inward> <outward>
# The full ordered-link step for one pair: direction-aware SKIP, create, read-back
# and self-heal. Sets JS_LINK_OUTCOME to
# up-to-date|created|rejected|unverified|read-failed and returns 0 / 1 / 2
# respectively (up-to-date and created both return 0; read-failed returns 2,
# because nothing was written and nothing is known about the pair).
#
# This is the whole of steps 7c-7f behind one call, so the umbrella branch's child
# links are the SAME code as a related-ticket link -- including the read-back that
# makes `syncjs.umbrella.link_unverified` reachable at all.
js_link_upsert_ordered() {
  local self="$1" target="$2" rel="$3" inward="$4" outward="$5"
  local prefix="${JS_LINK_REPORT_PREFIX:-syncjs.link}" reversed_id="" rc
  js_link_verify_direction "$self" "$target" "$rel" "$inward" "$outward"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    JS_LINK_OUTCOME=up-to-date
    return 0
  fi
  if [[ "$rc" -eq 3 ]]; then
    # The pre-check READ failed, so nothing is known about the pair. Creating now
    # appends a duplicate Jira cannot dedupe, and a stored REVERSED link stays
    # permanently (its id was never captured, so the self-heal cannot fire).
    # Refuse and let the operator's re-run converge it.
    js_report "$prefix.link_read_failed" \
      "the existing-link state of $self <-> $target could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- REFUSING to link blind, because a duplicate link cannot be undone by this sync and a reversed one would be left unreported; nothing was written and a re-run converges it"
    JS_LINK_OUTCOME=read-failed
    return 2
  fi
  if [[ "$rc" -eq 1 ]]; then
    reversed_id="$JS_LINK_STORED_ID"
    js_report "$prefix.direction_reversed" \
      "the stored $rel link between $self and $target records the ordering backwards -- creating the correctly-ordered link FIRST, then removing link $reversed_id, so no step can leave the pair unlinked"
  fi
  js_link_create_verified "$self" "$target" "$rel" "$inward" "$outward" 1
  case $? in
    1) JS_LINK_OUTCOME=rejected;   return 1 ;;
    2) JS_LINK_OUTCOME=unverified; return 2 ;;
  esac
  JS_LINK_OUTCOME=created
  if [[ -n "$reversed_id" ]]; then
    if js_rest DELETE "/rest/api/2/issueLink/$reversed_id" && js_http_ok; then
      js_report "$prefix.direction_healed" \
        "the reversed $rel link $reversed_id between $self and $target was removed after its correctly-ordered replacement landed"
    else
      js_report "$prefix.heal_incomplete" \
        "the correctly-ordered $rel link between $self and $target IS in place, but removing the reversed link $reversed_id was refused (HTTP ${JS_HTTP_STATUS:-unreachable}) -- BOTH links are present; delete $reversed_id by hand or re-run"
    fi
  fi
  return 0
}
