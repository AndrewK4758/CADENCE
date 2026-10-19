#!/usr/bin/env bash
#
# yt-link-targets.sh -- the link TARGETS computation, as one unit.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: `metadata.yaml` is the source
# of truth and YouTrack is only the projection, so a declaration this step cannot
# READ is never guessed at. A value that is not a ticket reference is REPORTED
# and skipped, never interpolated -- a structure sent as a REST path segment is a
# corrupted request rather than a lookup (PROD_CLAIRE-011, on the sibling adapter: a
# `related_tickets` sub-key valued as a LIST was stringified into one "issue
# key", truncated at the first space, and sent as a URL on every run, forever,
# silently).
#
# SOURCED by yt-link.sh, never invoked, and it runs nothing on load. It only
# READS: no REST call, no file write, nothing on stdout.
#
# Upstream: yt-link.sh, before it resolves any target.
# Downstream: none -- no network, no write.
# Spec: archive/BTG-176/spec.md (Proposed Design -- script inventory).
#
# Contract:
#   yt_link_targets -- sets, for its caller:
#     YT_LINK_TARGETS             the `<declaring-key> <target>` rows,
#                                 newline-separated (may be empty)
#     YT_LINK_TARGETS_UNREADABLE  how many declarations could not be read
#
# It is called DIRECTLY, never through a command substitution: a $( ) subshell
# would discard the counter, and a caller that read only the rows would report a
# clean run over a declaration this step refused.
#
# THE SHAPES IT MUST SURVIVE, each one real repo data:
#   * a FLAT list -- every `related_tickets` declaration in this repo today
#   * a MAPPING of sub-keys, each holding either a list of ids or one id
#     (BTG-106's `originating: ORD-39`)
#   * anything else -- reported, never read as an empty list, because "no
#     relations declared" and "the declaration could not be read" are opposite
#     facts and only one of them is safe to project silently.
#
# The TOP-LEVEL ordering keys `precedes:` and `preceded_by:` are read too: they
# are the repo's documented grammar for a directed relation
# (specs/TEMPLATE/metadata.yaml), and they are what makes DEC-016's Depend
# mapping reachable at all.
#
# RECORDED GAP, not an oversight: the other two ordering keys the template names,
# `duplicates:` and `clones:`, are NOT read here. `clones` has no counterpart on
# this instance at all (the type set is Relates, Depend, Duplicate, Subtask,
# Blocked By -- OBSERVED), and `duplicates` has a counterpart but no scenario in
# this ticket's plan, so reading it would be behaviour no test covers. Both
# belong to the sanctioned-divergence audit (test-plan S-6.4/S-6.5), and neither
# appears in any metadata.yaml in this repo today.

# yt_link_targets -- traverse `related_tickets` in every shape above.
yt_link_targets() {
  local rows defs where shape val
  YT_LINK_TARGETS=""
  YT_LINK_TARGETS_UNREADABLE=0

  # WHAT COUNTS AS A TICKET REFERENCE, stated ONCE because two jq passes must
  # agree on it: the first emits the rows, the second enumerates exactly what the
  # first declined. Two copies of one predicate is two chances to drift, and the
  # drift would be silent -- a row emitted AND reported, or a declaration dropped
  # and never reported.
  #
  # LETTERS, DIGITS, `_` and `-` (`BTG-176`, `ABC-3391`). An allowlist, not
  # a denylist -- the denylist spelling ("not a bracket, brace, quote or space")
  # admits `../../etc` and `CTS-61/62`, which carry none of those characters and
  # so reach the REST path segment unencoded. It is a character class rather than
  # an anchored key pattern because a project's key spelling is
  # instance-configurable, and refusing a WORKING projection because a key looks
  # unfamiliar would be a silent break for the adopter.
  defs='
    def refish: type == "string" and test("^[A-Za-z0-9_-]+$");
    (.related_tickets) as $r |
  '

  # EVERY BRANCH IS TOTAL. An ordering key that is not an array is NOT iterated:
  # iterating a STRING is a jq ERROR, and an error here does not empty one key,
  # it empties the WHOLE program -- taking a perfectly well-formed
  # `related_tickets` list with it. Found by the §16 live run (DEC-072): a scalar
  # `precedes:` made the step report `links_created=0 links_skipped=0
  # link_result=skipped` with no audit line at all, over a declaration it had
  # simply failed to read.
  local rc
  rows="$(jq -r "$defs"'
      ((.precedes // []) | if type == "array" then (.[] | select(refish) | "precedes " + .) else empty end),
      ((.preceded_by // []) | if type == "array" then (.[] | select(refish) | "preceded_by " + .) else empty end),
      if   ($r | type) == "array" then ($r[] | select(refish) | "related_tickets " + .)
      elif ($r | type) == "object" then
        ( $r | to_entries[] | .key as $k | .value
          | if type == "array" then (.[] | select(refish) | "\($k) \(.)")
            elif refish       then "\($k) \(.)"
            else empty end )
      else empty end' <<<"${YT_METADATA_JSON:-}" 2>/dev/null)"; rc=$?
  # AND THE EXIT STATUS IS READ. `|| true` on this substitution is what turned a
  # failed traversal into an empty one, and an empty traversal reads to every
  # caller as "this ticket declares no relationships". A program that did not run
  # is reported and COUNTED, so the step reports `rejected` rather than a clean
  # run over relations it never looked at.
  if [ "$rc" -ne 0 ]; then
    yt_report syncyt.link.related_tickets_shape_unreadable \
      "the link-target traversal for ${YT_METADATA_TICKET:-this ticket} could not be computed (jq exited $rc) -- NO relation is projected on this run, and this is reported rather than read as 'no relationships declared', which is the opposite fact"
    YT_LINK_TARGETS=""
    YT_LINK_TARGETS_UNREADABLE=$((YT_LINK_TARGETS_UNREADABLE + 1))
    return 0
  fi
  YT_LINK_TARGETS="$rows"

  # A SECOND, INDEPENDENT pass enumerates what the first one DECLINED, so the
  # refusal is DESCRIBED rather than inferred from a count mismatch: the count
  # alone cannot name the sub-key, the position, or the value an operator has to
  # go and fix.
  #
  # An ABSENT (or null) declaration is not a refusal -- a ticket that declares no
  # relationships is an ordinary ticket, and reporting it would make the audit
  # stream noise on nearly every projection.
  while IFS=$'\t' read -r where shape val; do
    [[ -n "${where:-}" ]] || continue
    yt_report syncyt.link.related_tickets_shape_unreadable \
      "$where is not a ticket reference this step can read ($shape: $(printf '%s' "$val" | tr -s ' ' | cut -c1-120)) -- it is REPORTED and skipped, never interpolated into an issue id, because a structure sent as a REST path segment is a corrupted request rather than a lookup; fix the declaration and the next run projects it"
    YT_LINK_TARGETS_UNREADABLE=$((YT_LINK_TARGETS_UNREADABLE + 1))
  done < <(jq -r "$defs"'
      ( ["precedes", "preceded_by"][] as $k
        | select((. [$k] // null) != null)
        | select((. [$k] | type) != "array")
        | "the ordering key \($k)\t\(. [$k] | type)\t\(. [$k] | tojson)" ),
      if   ($r | type) == "array" then
        ( $r | to_entries[] | select((.value | refish) | not)
          | "related_tickets element \(.key + 1)\t\(.value | type)\t\(.value | tojson)" )
      elif ($r | type) == "object" then
        ( $r | to_entries[] | .key as $k | .value
          | if type == "array" then
              ( to_entries[] | select((.value | refish) | not)
                | "the related_tickets sub-key \($k), element \(.key + 1),\t\(.value | type)\t\(.value | tojson)" )
            elif refish then empty
            else "the related_tickets sub-key \($k),\t\(type)\t\(tojson)" end )
      elif $r == null then empty
      else "the related_tickets value\t\($r | type)\t\($r | tojson)" end' \
    <<<"${YT_METADATA_JSON:-}" 2>/dev/null || true)
  return 0
}
