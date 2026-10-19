#!/usr/bin/env bash
#
# jira-link.sh -- project the repo's `related_tickets` as Jira issue links.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: linking is **additive-only**.
# This sync creates links; it never deletes or rewrites one, because a human may
# have added links this repo knows nothing about and their removal is not this
# tool's decision. Additive-only plus a READ-BEFORE-WRITE is also what makes the
# step idempotent: an existing correct link is left untouched, so an operator
# re-run after a halt (DEC-008/DEC-009) creates no duplicate.
#
# Ordered `precedes` links carry an INVERSION: on this instance the relation is
# declared with the predecessor in the `inwardIssue` slot, so writing it in the
# natural reading order would record the ordering backwards. The slot is config
# (`link_relations.precedes`), not a hardcoded assumption, because the direction
# is per-instance -- and the type NAME is not even config: it is discovered from
# the instance by phrasing (`jira-link-lib.sh`), because this org's live type is
# named `precedes ` with a trailing space.
#
# The relation comes from the DECLARING KEY where there is one (`precedes:`,
# `preceded_by:`, `duplicates:`, `clones:`, a keyed `related_tickets:` map) and
# from the entry's TRAILING COMMENT where there is not. The comment is not a
# convenience: the flat-list-plus-comment shape is the ONLY one this repo's 150
# metadata files actually use, so a projection that ignored it downgraded 100% of
# real relations to the symmetric default. Ordering means LANDING ORDER, never
# genealogy -- "introduced", "origin", "spawned" project symmetric.
#
# Two things this step will never do: it never CREATES the referenced issue (a
# reference to a ticket that does not exist yet is reported and skipped), and it
# never deletes a link it did not just create in the wrong direction. The one
# deletion it does make -- the reversed-ordering self-heal -- runs AFTER its
# replacement has landed, so no failure of any single step can leave the pair
# with no link at all.
#
# Upstream: invoked by the /claire-sync-jira orchestrator near the end of the
#   sequence (**best-effort** -- never a gate).
# Downstream: `GET $JIRA_BASE_URL/rest/api/2/issue/{key}?fields=issuelinks`,
#   `POST .../issueLink`.
# Spec: archive/BTG-075/spec.md (Idempotency) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> --issue-key <KEY>
#   stdout : links_created=<n>, references_unreadable=<n>, references_unresolved=<n>,
#            references_skipped=<n> ; link_result=created|up-to-date|none|rejected
#   stderr : syncjs.link.* reported conditions
#   exit   : 0 for every outcome including a rejection (best-effort); 2 usage;
#            4 config HALT
#
# THE ACCOUNT (BTG-107 AC-1): the three-counter partition's full rationale,
# each counter's operator action, and why REJECTED is a derived sum rather
# than an incremented total, are catalogued in jira-server-conditions-links.md
# beside the `ordered_skipped` entry it amends.
#
# This script READS metadata.yaml and NEVER writes it (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-link-lib.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-link-targets.sh"

TICKET=""
ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)    js_argv_pair syncjs.link.usage "$@"; TICKET="$2"; shift 2 ;;
    --issue-key) js_argv_pair syncjs.link.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.link.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET"    ]] || js_halt "$JS_EXIT_USAGE" syncjs.link.usage "--ticket <id> is required"
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.link.usage "--issue-key <KEY> is required"

js_config_require
js_metadata_load "$TICKET"

# THE ACCOUNT (BTG-107 AC-1). UNREADABLE is seeded from the extraction's own
# refusal count below; UNRESOLVED and SKIPPED start at zero and accumulate as
# the main loop disposes of each reference.
UNREADABLE=0
UNRESOLVED=0
SKIPPED=0

# js_link_emit_account <links_created> <result>
# The SOLE writer of this script's stdout payload, called from every outcome
# path so none can emit a partial account (S-1.6). Key names are LITERAL
# arguments, never assembled from a variable, so the contract gate keeps
# static visibility of them (OS-1.4).
js_link_emit_account() {
  js_emit links_created         "$1"
  js_emit references_unreadable "$UNREADABLE"
  js_emit references_unresolved "$UNRESOLVED"
  js_emit references_skipped    "$SKIPPED"
  js_emit link_result           "$2"
}

# EXEMPTIONS. An Epic's relationships are the Epic Link field on its children, not
# issue links (BTG-040), and `decomposed_into` / `child_decomposition` name tickets
# this one was split into -- a decomposition is a lineage record, not a board link.
TICKET_TYPE="$(js_metadata_get '.type')"
if [[ "$TICKET_TYPE" == "epic" ]]; then
  js_report syncjs.link.epic_exempt "$TICKET is an Epic -- its children carry the Epic Link field; no issue link is created"
  js_link_emit_account 0 none
  exit "$JS_EXIT_OK"
fi

# TARGETS, keyed by the field that declared them. Each row is "<key> <target>".
# The whole computation -- the structured extraction and its type dispatch, the
# flat comment-signal loop, the dedupe -- was relocated WHOLE into
# `jira-link-targets.sh` under the 400-line DX ceiling (BTG-106 DEC-003), so it is
# one file's question rather than 45 lines scrolled past here.
# It is called DIRECTLY, never in a $( ): a subshell would discard the refusal
# counter and this run would report clean over a declaration it could not read.
js_link_targets
TARGETS="$JS_LINK_TARGETS"
UNREADABLE="$JS_LINK_TARGETS_UNPARSEABLE"

if [[ -z "$TARGETS" ]]; then
  if [[ "$UNREADABLE" -gt 0 ]]; then
    # A step that could not READ its own declarations has not "declared none".
    # `none` here would be the silent failure this ticket exists to end: the
    # operator reads a clean result over a ticket whose every coupling was
    # refused, and the shape never changes between runs, so it stays wrong.
    js_report syncjs.link.rejected \
      "$TICKET's related_tickets declarations could not be read (reported above) -- no link call made, and the run is NOT reported clean; linking is best-effort, the sync continues"
    js_link_emit_account 0 rejected
  else
    js_report syncjs.link.none "$TICKET declares no related tickets -- no link call made"
    js_link_emit_account 0 none
  fi
  exit "$JS_EXIT_OK"
fi

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.link.env_absent "the base-URL environment variable is unset"

# READ BEFORE WRITE. Without the existing-link read this step would append a
# duplicate on every re-run, and re-run is the sanctioned recovery path.
if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=issuelinks"; then
  js_report syncjs.link.rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/} -- linking is best-effort, the sync continues"
  js_link_emit_account 0 rejected
  exit "$JS_EXIT_OK"
fi
if ! js_http_ok; then
  js_report syncjs.link.rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS -- refusing to link blind (a duplicate link cannot be undone by this sync); the sync continues"
  js_link_emit_account 0 rejected
  exit "$JS_EXIT_OK"
fi
JS_LINKS_JSON="$JS_HTTP_BODY"
# The snapshot must at least PARSE before anything is decided from its absence:
# an unparseable body yields "no existing links" from every later query, which
# reads exactly like a clean issue and duplicates every link on the ticket.
if ! printf '%s' "$JS_HTTP_BODY" | jq -e 'type == "object" and (has("fields"))' >/dev/null 2>&1; then
  js_report syncjs.link.rejected "the issue read returned an unparseable body -- refusing to link blind; the sync continues"
  js_link_emit_account 0 rejected
  exit "$JS_EXIT_OK"
fi

DEFAULT_REL="$(js_config_map link_relations default)" || exit "$JS_EXIT_CONFIG"
# resolved by the library, which owns every config polarity: an absent, malformed
# or self-contradictory ordered-relation declaration HALTs rather than defaulting
# here. The config's name/id are ANCHORS; the live type is discovered below.
IFS='|' read -r CFG_ORDERED_NAME PRED_SLOT CFG_ORDERED_ID <<<"$(js_config_ordered_relation)" || exit "$JS_EXIT_CONFIG"
[[ -n "$CFG_ORDERED_NAME" && -n "$PRED_SLOT" ]] || exit "$JS_EXIT_CONFIG"

# DISCOVER the ordered type from the instance, not from the config: on this org's
# instance it is named `precedes ` (trailing space), so a config-named projection
# matches no stored link and has its POST rejected (archive/BTG-036 live record).
# The read is made only when an ordered relation is actually declared.
ORDERED_REL=""
JS_ORDERED_STATE=""
if grep -qE '^(precedes|preceded_by|blocks|depends_on|blocked_by) ' <<<"$TARGETS"; then
  if js_ordered_type_discover "$CFG_ORDERED_ID" "$DEFAULT_REL"; then
    ORDERED_REL="$JS_ORDERED_NAME"
  fi
fi

# The two STOCK types get the same treatment as the ordered one (AC-7): the config
# name is an anchor, the live type is discovered by name case-insensitively, and
# an instance that has renamed or localized it falls back to the symmetric default
# and says so -- rather than firing a POST that is rejected and recording nothing.
# Each read is made only when that relation is actually declared.
DUPLICATE_REL="$DEFAULT_REL"
CLONE_REL="$DEFAULT_REL"
if grep -qE '^duplicates ' <<<"$TARGETS"; then
  js_link_type_by_name duplicate "$DEFAULT_REL" && DUPLICATE_REL="$JS_LINK_TYPE_NAME"
fi
if grep -qE '^clones ' <<<"$TARGETS"; then
  js_link_type_by_name clone "$DEFAULT_REL" && CLONE_REL="$JS_LINK_TYPE_NAME"
fi

BODY_FILE="$(mktemp 2>/dev/null)" || { js_report syncjs.link.scratch_unavailable "no scratch file could be staged for $TICKET's link bodies -- creating NO links; an unstaged body degrades every POST into a bodyless one Jira answers with an opaque 400"; js_link_emit_account 0 rejected; exit "$JS_EXIT_OK"; }
trap 'rm -f "$BODY_FILE" 2>/dev/null' EXIT
CREATED=0
# UNREADABLE/UNRESOLVED/SKIPPED are already initialised above; REJECTED is
# derived once, at the very end, as their sum (BTG-107 AC-1; see the final
# `REJECTED=$(( UNREADABLE + UNRESOLVED + SKIPPED ))`).

# link_slots <key> <this> <other> -- echo "<type>|<inward>|<outward>".
# The ordered type is INVERTED on this instance: the predecessor goes in the
# configured slot, so `precedes` (this issue lands first) puts THIS issue there
# and `preceded_by` puts the referenced ticket there. The symmetric and stock
# types are unaffected by the calibration.
link_slots() {
  local key="$1" this="$2" other="$3" pred succ
  # the KEYED related_tickets shape carries its signal in the key name
  case "$key" in
    precedes|blocks)              pred="$this";  succ="$other" ;;
    preceded_by|depends_on|blocked_by) pred="$other"; succ="$this" ;;
    duplicates)  printf '%s|%s|%s' "$DUPLICATE_REL" "$other" "$this"; return ;;
    clones)      printf '%s|%s|%s' "$CLONE_REL"     "$other" "$this"; return ;;
    *)           printf '%s|%s|%s' "$DEFAULT_REL" "$this" "$other"; return ;;
  esac
  if [[ "$PRED_SLOT" == "inwardIssue" ]]; then
    printf '%s|%s|%s' "$ORDERED_REL" "$pred" "$succ"
  else
    printf '%s|%s|%s' "$ORDERED_REL" "$succ" "$pred"
  fi
}

while read -r key target; do
  [[ -n "$key" && -n "$target" ]] || continue
  HEAL_ID=""                        # set only on the self-heal path, per target

  # EXISTENCE PRE-CHECK. A referenced ticket with no issue yet is reported and
  # skipped: this step links existing issues and NEVER creates the referenced one.
  # ONLY a 404 is an absence. A 401/403/500 or an unreachable transport says
  # nothing about whether the issue exists, and reporting one as "the ticket does
  # not exist" turns a credential failure into a clean run that skipped every
  # link -- the operator sees `link_result=up-to-date` and no relation projected.
  if ! js_rest GET "/rest/api/2/issue/$target?fields=key"; then
    js_report syncjs.link.reference_unresolved \
      "whether $target exists could not be determined -- ${JS_TRANSPORT_ERROR:-the transport did not complete}; the link is neither created nor reported absent, and the next run retries"
    UNRESOLVED=$((UNRESOLVED + 1))
    continue
  fi
  TARGET_KEY="$target"
  if ! js_http_ok; then
    if [[ "$JS_HTTP_STATUS" == "404" ]]; then
      # A repo id is only USUALLY a Jira key. When it is not, this step used to
      # find the issue by its summary, which carried the repo id. BTG-124 removed
      # the id from the projected summary, and DEC-007 (OQ-1 Option C, ratified at
      # the Spec Review gate) DELETED that fallback rather than re-pointing it at
      # another signal. It is NOT replaced.
      #
      # So a repo-id target that is not itself a Jira key is now reported ABSENT.
      # The cost is real and was accepted: a cross-reference to a ticket that has
      # not yet been synced silently does not link. It degrades quietly BY DESIGN
      # -- this step is best-effort and exits 0 (R10) -- but "quietly" must not
      # mean "unreported", so the absence still gets its own named condition and
      # still counts, and the step still NEVER creates the referenced issue.
      js_report syncjs.link.referenced_absent \
        "$target has no issue on this instance -- it is not a Jira key, and since BTG-124 DEC-007 there is no fallback that finds one (the projected summary no longer carries the repo id, and the search that read it back was deleted, not replaced). Skipping the link; this step never creates the referenced issue"
      # COUNTED, not merely reported (BTG-124 OS-1.5). A declared relation that
      # did not project is not an up-to-date run: `up-to-date` means every
      # declared link is in place, and an operator reading it takes the board as
      # complete. Before this it was reported and then forgotten, so a run where
      # EVERY target was absent still emitted `link_result=up-to-date` -- a clean
      # run that linked nothing, which is the exact LINEAGE_GAP the deleted
      # fallback's own comment said it existed to prevent. DEC-007 makes that
      # state ordinary rather than rare (every not-yet-synced repo-id target now
      # lands here), so the count is what keeps the removal honest. It joins
      # references_unresolved (BTG-107 DEC-007), the same counter the
      # auth/server failure below lands in; the stderr condition names which.
      UNRESOLVED=$((UNRESOLVED + 1))
      continue
    else
      js_report syncjs.link.reference_unresolved \
        "whether $target exists could not be determined (HTTP $JS_HTTP_STATUS -- an auth or server failure, NOT an absence); the link is neither created nor reported absent, and the next run retries"
      UNRESOLVED=$((UNRESOLVED + 1))
      continue
    fi
  fi

  IFS='|' read -r rel inward outward <<<"$(link_slots "$key" "$ISSUE_KEY" "$TARGET_KEY")"
  if [[ -z "$rel" ]]; then
    # the ordered type could not be READ from the instance (not: is absent). A
    # guessed type is the one thing this step will not do.
    js_report syncjs.link.ordered_skipped \
      "the ordered link $ISSUE_KEY -> $target is skipped this run: the instance's link types were unreadable and the type is never guessed; the next run retries"
    # COUNTED as SKIPPED (BTG-107 DEC-004) -- see jira-server-conditions-links.md.
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # "Already linked" is a question about a link OF THIS TYPE. A type-blind test
  # lets any unrelated symmetric link suppress a required ordered one -- and then
  # reports it "in the correct direction", a direction it never looked at.
  # THE CLASSIFICATION IS THE LIBRARY'S, against THIS ticket's one snapshot.
  # "Already linked" is a question about a link OF THIS TYPE: a type-blind test
  # lets any unrelated symmetric link suppress a required ordered one -- and then
  # reports it "in the correct direction", a direction it never looked at.
  #
  # And the read is PERSPECTIVE-DEPENDENT (DEC-015, verified live on
  # PLAYSCRUM-3373/3374, link id 111507): a per-issue `issuelinks` entry names
  # ONLY THE FAR ENDPOINT, so the omitted near end must be folded back in as
  # $ISSUE_KEY before anything is classified. Comparing the raw slots leaves one
  # side "" on every entry, which makes the predicate ALWAYS true -- a correct
  # link and a reversed one produce byte-identical output, so every correct
  # ordered link is deleted and recreated on every run.
  #
  # Both rules live in `js_link_classify`, which the library's own read-back
  # calls too. They were two copies of one rule, and the `// $self` fold-in had
  # to be fixed in each separately -- a second chance to drift on the exact bug
  # that has now recurred three times.
  js_link_classify "$JS_LINKS_JSON" "$ISSUE_KEY" "$TARGET_KEY" "$rel" "$inward" "$outward"
  CLASSIFY_RC=$?
  if [[ "$CLASSIFY_RC" -eq 0 ]]; then
    js_report syncjs.link.up_to_date "$ISSUE_KEY is already linked to $target in the correct direction -- left untouched"
    continue
  fi
  if [[ "$CLASSIFY_RC" -eq 1 ]]; then
    # A link of this type connects the pair the OTHER way round. For an ORDERED
    # type the direction is part of the fact, so this is not "already correct" --
    # it renders the ordering backwards on the board. Under the `type_fallback`
    # the type is SYMMETRIC and carries no direction, so a slot difference is
    # meaningless there and the link is left alone; treating it as mis-ordered
    # would delete and recreate it on every run.
    if [[ "$JS_ORDERED_STATE" == "discovered" && "$rel" == "$ORDERED_REL" ]]; then
      # CREATE BEFORE DELETE. The heal is the one deletion this step ever makes,
      # and it must never be able to leave the pair with NO link: delete-first
      # loses a correct relation outright when the recreate is refused (DELETE
      # 204 then POST 403 destroyed it and still exited 0). Creating first can
      # at worst leave BOTH links -- visible, reported, and repairable -- which
      # is strictly recoverable where the loss is not. The delete is deferred
      # until after the POST is known to have landed, and its own result is
      # CHECKED (`|| true` swallowed a refusal).
      js_report syncjs.link.direction_reversed \
        "the stored $rel link between $ISSUE_KEY and $target records the ordering backwards -- creating the correctly-ordered link FIRST, then removing link $JS_LINK_STORED_ID, so no step can leave the pair unlinked"
      HEAL_ID="$JS_LINK_STORED_ID"
    else
      js_report syncjs.link.up_to_date "$ISSUE_KEY is already linked to $target -- left untouched (additive-only, no duplicate)"
      continue
    fi
  fi
  if [[ "$CLASSIFY_RC" -eq 3 ]]; then
    # The snapshot could not be classified. That is not "no such link": creating
    # now would append a duplicate Jira cannot dedupe, and a stored reversed link
    # would be left in place with its id never captured.
    js_report syncjs.link.rejected \
      "the existing-link state of $ISSUE_KEY <-> $target could not be classified -- refusing to link blind; the sync continues and a re-run converges it"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # The create, and -- for an ordered type -- the MANDATORY post-create direction
  # read-back and its self-heal, both live in the shared library, so the umbrella
  # branch's child links go through this same code rather than a second
  # implementation of the calibration (SEAM: umbrella.readback_reuse_intact).
  ORDERED_NOW=0
  [[ "$JS_ORDERED_STATE" == "discovered" && "$rel" == "$ORDERED_REL" ]] && ORDERED_NOW=1
  js_link_create_verified "$ISSUE_KEY" "$TARGET_KEY" "$rel" "$inward" "$outward" "$ORDERED_NOW"
  CREATE_RC=$?
  if [[ "$CREATE_RC" -eq 1 ]]; then
    if [[ -n "$HEAL_ID" ]]; then
      js_report syncjs.link.heal_abandoned \
        "the correctly-ordered $rel link between $ISSUE_KEY and $target was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the reversed link $HEAL_ID is deliberately LEFT IN PLACE and nothing was deleted; the ordering still renders backwards, but the relation is not lost and the next run retries"
    else
      js_report syncjs.link.rejected \
        "linking $ISSUE_KEY -> $target as '$rel' was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- linking is best-effort, the sync continues"
    fi
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  js_report syncjs.link.created "linked $ISSUE_KEY -> $target as '$rel' (inward=$inward outward=$outward)"
  CREATED=$((CREATED + 1))
  # A link whose direction could not be confirmed is NOT a clean outcome: it was
  # created, so it is counted, but the run does not report itself successful.
  [[ "$CREATE_RC" -eq 2 ]] && SKIPPED=$((SKIPPED + 1))
  # The replacement is in place, so removing the reversed original can no longer
  # unlink the pair. The delete's own result is checked: a refused delete leaves
  # a DUPLICATE, which is a reported outcome, never a clean one.
  if [[ -n "$HEAL_ID" ]]; then
    if js_rest DELETE "/rest/api/2/issueLink/$HEAL_ID" && js_http_ok; then
      js_report syncjs.link.direction_healed \
        "the reversed $rel link $HEAL_ID between $ISSUE_KEY and $target was removed after its correctly-ordered replacement landed"
    else
      js_report syncjs.link.heal_incomplete \
        "the correctly-ordered $rel link between $ISSUE_KEY and $target IS in place, but removing the reversed link $HEAL_ID was refused (HTTP ${JS_HTTP_STATUS:-unreachable}) -- BOTH links are present; delete $HEAL_ID by hand or re-run once the refusal is resolved"
      SKIPPED=$((SKIPPED + 1))
    fi
  fi
done <<<"$TARGETS"

# REJECTED is a DERIVED SUM, assigned exactly once (S-1.7) -- never
# incremented directly, so the partition sums by construction (S-1.5).
REJECTED=$(( UNREADABLE + UNRESOLVED + SKIPPED ))
if   [[ "$REJECTED" -gt 0 ]]; then js_link_emit_account "$CREATED" rejected
elif [[ "$CREATED"  -gt 0 ]]; then js_link_emit_account "$CREATED" created
else                               js_link_emit_account "$CREATED" up-to-date
fi
exit "$JS_EXIT_OK"
