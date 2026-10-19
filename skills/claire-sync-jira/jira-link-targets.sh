#!/usr/bin/env bash
#
# jira-link-targets.sh -- the link TARGETS computation, as one unit.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075/BTG-106).
# Invariant relied on from outside this boundary: `metadata.yaml` is the source of
# truth and Jira is only the projection, so a declaration this step cannot READ is
# never guessed at. Under `related_tickets:` -- in EVERY arm -- a value that is
# not a ticket reference is REPORTED and skipped, never interpolated, because a
# structure sent as a REST path segment is a corrupted request rather than a
# lookup (PROD_CLAIRE-011: a `related_tickets:` sub-key valued as a LIST was stringified
# into one "issue key", truncated by the dedupe at the first space, and sent as a
# URL on every run, forever, silently).
#
# That guarantee is UNQUALIFIED, and it is stated that way only because it is now
# true of the FLAT list arm too (BTG-108). It reads unqualified because every arm
# converges on ONE validation chokepoint below -- the keyed extraction, the four
# ordering keys and the flat comment-signal loop all flow through it -- so there
# is exactly one answer to "what counts as a ticket reference", and a future arm
# inherits it. A reference is spelled from LETTERS, DIGITS, `_` and `-`; anything
# else is reported by name and dropped before the dedupe can truncate it or
# `jira-link.sh` can interpolate it. The previous wording over-claimed this
# sentence once (BTG-106 maintainer gate), which is why it is now backed by
# executing scenarios rather than by prose -- see
# ci-templates/scripts/tests/btg-108-flat-related-tickets.test.sh S-5.3.
#
# It is SOURCED, never invoked, and runs nothing on load. It owns exactly one
# function, and that function only READS: no REST call, no file write, nothing on
# stdout. It READS `metadata.yaml` and NEVER writes it (AC-6).
#
# Why it is a library rather than a block in `jira-link.sh`. It landed here by
# RELOCATION under the 400-line DX ceiling, on the DEC-057 / DEC-060 precedent
# (BTG-079 AC-7) that `jira-ac-lib.sh` and `jira-epic-lib.sh` already follow:
# `jira-link.sh` measured 395 against a gate that fails at 400, and
# `jira-link-lib.sh` (370) owns the ORDERED-LINK machinery that `jira-epic.sh`
# also sources and would have inherited extraction it cannot use. The unit chosen
# is the WHOLE computation -- structured extraction, the flat comment-signal loop
# and the dedupe are one concern with one caller, so "how is a target derived" is
# a one-file question.
#
# The relocation is TEXTUAL -- same code, same variable names, same reports -- so
# behaviour preservation is provable from the diff rather than argued. That
# matters here more than usual: every one of this repo's own `related_tickets`
# users is on the FLAT path that moves.
#
# Upstream: `jira-link.sh`, before it reads the existing-link snapshot.
# Downstream: none -- no network, no write.
# Spec: archive/BTG-106/spec.md ; jira-server-scripts.md.
#
# Contract:
#   js_link_targets -- sets, for its caller:
#     JS_LINK_TARGETS              the deduped `<declaring-key> <target>` rows,
#                                  newline-separated (may be empty)
#     JS_LINK_TARGETS_UNPARSEABLE  how many declarations could not be read
#
# It is called DIRECTLY, never through a command substitution: a $( ) subshell
# would discard the counter, and a caller that read only the rows would report a
# clean run over a declaration this step refused. Same reason
# `js_ordered_type_discover` sets JS_ORDERED_NAME instead of printing it.

# js_link_pass_refused <pass-label> <exit-status> -- BTG-107 AC-5.
#
# One report + one count, shared by all three jq passes below. The rule:
# a jq pass that did not complete is never read as "it found nothing." A jq
# built without Oniguruma cannot evaluate test()/1 at all -- the predicate
# EVERY pass's `defs` block defines -- but a missing binary, a truncated
# $JS_METADATA_JSON, or an OOM'd process fail the identical way, so the
# status is observed rather than the cause probed for (DEC-008).
#
# The count is deliberately 1 and deliberately declared a FLOOR: the
# extraction that would have produced the true total is the thing that
# failed, so inventing a larger number would be a different kind of lie.
js_link_pass_refused() {
  js_report syncjs.link.extraction_unavailable \
    "the $1 pass over related_tickets did not complete (jq exited $2) -- its EMPTY result is a FAILURE, not a finding of 'no relations'. A jq built without Oniguruma cannot evaluate test(), which this pass uses. references_unreadable is a FLOOR from here, not a total; link_result is rejected and the next run retries"
  JS_LINK_TARGETS_UNPARSEABLE=$((JS_LINK_TARGETS_UNPARSEABLE + 1))
}

js_link_targets() {
  local TARGETS VALIDATED DEDUPED rel_key ref signal sub pos shape val row defs sigrows refusals validated_rows
  VALIDATED=""
  JS_LINK_TARGETS=""
  JS_LINK_TARGETS_UNPARSEABLE=0

  # WHAT COUNTS AS A TICKET REFERENCE, stated ONCE because two jq passes must
  # agree on it: the first emits the rows, the second enumerates exactly what the
  # first declined. Two copies of one predicate is two chances to drift, and the
  # drift would be silent -- a row emitted and also reported, or a declaration
  # dropped and never reported (DEC-002).
  #
  # A candidate must LOOK like a ticket reference, not merely BE a non-empty
  # string (DEC-015). Two reachable inputs make the weaker test unsafe:
  #   * the reader has no flow-MAPPING parser, so an INLINE list-of-maps
  #     `[{ticket: "CTS-61", note: "n1"}, ...]` arrives as the comma-split
  #     fragments ["{ticket: CTS-61", "note: n1}", ...] -- every one a non-empty
  #     string, so accepting any string fans ONE unreadable declaration out into
  #     N corrupted lookups and N link POSTs;
  #   * `ticket: "CTS-61 and CTS-62"` reaches the awk dedupe, which keys on
  #     `$1 $2` and truncates it to `CTS-61` -- half the declaration discarded
  #     with no report, which is PROD_CLAIRE-011's failure mode exactly.
  #
  # Stated as an ALLOWLIST, not a denylist. A ticket reference is spelled from
  # LETTERS, DIGITS, `_` and `-`: `CTS-37`, `BTG-108`, `PLAYSCRUM-3391`. The
  # former denylist ("not a bracket, brace, quote or space") admitted `../../etc`
  # and `CTS-61/62`, which carry none of those characters and so reached the REST
  # path segment UNENCODED (BTG-106 review item N-3; BTG-108 DEC-001). It is a
  # character class rather than an anchored key regex on purpose: `jira.project
  # .key.pattern` is server-configurable, and refusing a WORKING projection
  # because a key is spelled unexpectedly would be a silent break for the adopter
  # (DEC-001, Alternative 4).
  #
  # `structural` is DERIVED from `refish` rather than being a second character
  # test of its own: two independent spellings of "what a reference looks like"
  # is two chances to drift, and the drift would be SILENT -- a row emitted and
  # also reported, or a declaration dropped and never reported (PROD_CLAIRE-012;
  # DEC-002). A non-string -- `null` above all -- is neither, so it takes the
  # `else` arm untouched and BTG-106 DEC-005's carve-out survives by
  # construction rather than by a special case.
  defs='
    def refish: type == "string" and test("^[A-Za-z0-9_-]+$");
    def structural: type == "string" and (refish | not);
    def tcand: if type == "object" then .ticket else . end;
    def readable: tcand | refish;
    def tref: tcand | select(refish);
  '

  # TARGETS, keyed by the field that declared them. Each row is "<key> <target>".
  # each element is parenthesized: `|` binds looser than `,` in jq, so an
  # unparenthesized list would pipe every later branch through the first one.
  TARGETS="$(jq -r "$defs"'
    # rows($k) -- the target rows ONE keyed `related_tickets` sub-key contributes.
    # ARRAY      -> one row per element (a maps .ticket, or a bare string
    #               element), each inheriting its sub-keys own declaring key, so
    #               the relation falls out of link_slots() with no
    #               coupling-specific rule (DEC-001)
    # OBJECT     -> none; the second pass reports it (a structure is never a key)
    # STRUCTURAL -> none; the second pass reports it. A string arm, not an object
    #               one, because a FLOW-style mapping `{ticket: "CTS-70"}` never
    #               reaches the object branch: the reader has no flow-mapping
    #               parser, so it arrives here as that whole string and would be
    #               interpolated verbatim into a REST path segment (DEC-016)
    # ELSE       -> exactly todays row, byte for byte -- `null` included (DEC-005)
    def rows($k):
      if   type == "array"  then (.[] | tref | "\($k) \(.)")
      elif type == "object" then empty
      elif structural       then empty
      else "\($k) \(.)" end;
    [ ((.precedes        // [])[] | "precedes "        + .),
      ((.preceded_by     // [])[] | "preceded_by "     + .),
      ((.duplicates      // [])[] | "duplicates "      + .),
      ((.clones          // [])[] | "clones "          + .),
      ((.related_tickets // [])
         | if type == "object" then (to_entries[] | .key as $k | .value | rows($k))
           else empty end) ] | .[]' \
    <<<"$JS_METADATA_JSON" 2>/dev/null)" \
    || js_link_pass_refused "structured extraction" "$?"

  # A SECOND, INDEPENDENT pass enumerates what the first one DECLINED, so the
  # refusal is described rather than inferred from a count mismatch -- the count
  # alone cannot name the sub-key, the position, or the value the operator has to
  # go and fix. One condition name covers both cases (DEC-006); the message text
  # carries the distinction.
  refusals="$(jq -r "$defs"'
    (.related_tickets // {})
    | if type == "object" then
        ( to_entries[] | .key as $k | .value
          | if type == "array" then
              ( to_entries[] | select((.value | readable) | not)
                | "\($k)\telement \(.key + 1)\t\(.value | type)\t\(.value | tojson)" )
            elif type == "object" then "\($k)\tits value\tobject\t\(tojson)"
            elif structural       then "\($k)\tits value\t\(type)\t\(tojson)"
            else empty end )
      else empty end' \
    <<<"$JS_METADATA_JSON" 2>/dev/null)" \
    || js_link_pass_refused "refusal enumeration" "$?"
  while IFS=$'\t' read -r sub pos shape val; do
    [[ -n "$sub" ]] || continue
    js_report syncjs.link.related_tickets_value_shape_unrecognized \
      "the related_tickets sub-key '$sub' $pos is not a ticket reference this step can read ($shape: $(printf '%s' "$val" | tr -s ' ' | cut -c1-120)) -- it is REPORTED and skipped, never interpolated into an issue key, because a structure sent as a REST path segment is a corrupted request, not a lookup; fix the declaration and the next run projects it"
    JS_LINK_TARGETS_UNPARSEABLE=$((JS_LINK_TARGETS_UNPARSEABLE + 1))
  done <<<"$refusals"

  # The FLAT `related_tickets` shape states its relation in the TRAILING COMMENT --
  # the only shape this repo actually holds. It is read from the raw file (the
  # structured reader drops comments, correctly, for every other key) and mapped to
  # the same declaring keys the structured shape uses, so one code path serves both.
  # CAPTURED, not process-substituted: a REFUSED read (DEC-023) exits non-zero
  # having emitted nothing, and is COUNTED -- never read as "declares no relations".
  sigrows="$(js_metadata_list_signals related_tickets)" || JS_LINK_TARGETS_UNPARSEABLE=$((JS_LINK_TARGETS_UNPARSEABLE + 1))
  while IFS=$'\t' read -r ref signal; do
    [[ -n "$ref" ]] || continue
    if ! rel_key="$(js_relation_from_signal "$signal")"; then
      js_report syncjs.link.signal_ambiguous \
        "the note on $ref does not determine a landing direction -- it asserts BOTH, or names THIS ticket on both sides of one dependency clause ('$(printf '%s' "$signal" | tr -s ' ' | cut -c1-120)') -- degrading to the symmetric default rather than picking one and recording the ordering backwards"
    fi
    TARGETS="${TARGETS:+$TARGETS
}$rel_key $ref"
  done <<<"$sigrows"

  # THE VALIDATION CHOKEPOINT. Every arm that can contribute a row converges
  # HERE -- the structured keyed extraction above, the four top-level ordering
  # keys, and the flat comment-signal loop just closed -- so "is this a ticket
  # reference" is asked in exactly ONE place, with exactly ONE predicate, and a
  # future arm inherits the guarantee for free. Putting the test inside the flat
  # loop instead would buy an item index and cost a SECOND application site,
  # which is the drift this module's header already forbids (DEC-008).
  #
  # A row must be exactly `<declaring-key> <target>` with a refish target.
  # Anything else is REPORTED by name, COUNTED, and DROPPED here -- BEFORE the
  # dedupe can truncate it at the first space and BEFORE `jira-link.sh` can
  # interpolate it into `GET /rest/api/2/issue/<target>`. That ordering is the
  # whole point: a refused item costs ZERO calls, where it previously cost one
  # malformed one.
  #
  # It reuses syncjs.link.related_tickets_value_shape_unrecognized rather than
  # adding a name: one condition, two message texts (DEC-006/DEC-007). A new
  # name would split an operator's grep for "the extractor refused something".
  validated_rows="$(jq -Rr "$defs"'
    select(length > 0)
    | . as $row
    | ($row | split(" ")) as $f
    | ($f[0] // "") as $k
    | ($row | ltrimstr($k) | ltrimstr(" ")) as $v
    | if ($f | length) == 2 and ($f[1] | refish)
      then "ok\t\($k)\t\($f[1])"
      else "bad\t\($k)\t\($v)" end' <<<"$TARGETS")" \
    || js_link_pass_refused "validation chokepoint" "$?"
  while IFS=$'\t' read -r shape rel_key val; do
    case "$shape" in
      ok)  VALIDATED="${VALIDATED:+$VALIDATED
}$rel_key $val" ;;
      bad)
        js_report syncjs.link.related_tickets_value_shape_unrecognized \
          "the related_tickets declaration under '$rel_key' is not a ticket reference this step can read ($(printf '%s' "${val:-<empty>}" | tr -s '[:space:]' ' ' | cut -c1-120)) -- it is REPORTED and skipped, never interpolated into an issue key, because a value sent as a REST path segment is a corrupted request, not a lookup; a reference is spelled from letters, digits, '_' and '-', and ONE list item declares exactly ONE reference, so name two tickets on two items rather than one line; fix the declaration and the next run projects it"
        JS_LINK_TARGETS_UNPARSEABLE=$((JS_LINK_TARGETS_UNPARSEABLE + 1)) ;;
    esac
  done <<<"$validated_rows"
  TARGETS="$VALIDATED"

  # DEDUPE BY REPO ID, keeping the STRONGEST signal. A ticket named under both an
  # ordering key and `related_tickets` is ONE relation, not two: the existing-link
  # snapshot is taken once before the loop, so a second mention cannot see the link
  # the first one just created and the pair ends up doubly linked. Precedence is
  # the sidecar's -- ordered > duplicate > clone > symmetric -- and first mention
  # wins a tie, so the output order is the declaration order.
  #
  # The arity guard below is an ASSERTION, and an assertion with no failing arm
  # is not one. `NF == 2` ALONE converted a malformed row into TOTAL SILENT LOSS
  # of that row -- no stderr, no counter, exit 0 -- which is the failure class
  # this module exists to close, not the opposite of it (BTG-108 review cycle 1,
  # B-2). So awk now CLASSIFIES every row and this loop REPORTS and COUNTS the
  # refusals, exactly as the chokepoint above does: two guards, one idiom, and
  # a row that reaches here malformed costs an operator a named condition rather
  # than a vanished declaration.
  DEDUPED=""
  while IFS=$'\t' read -r shape row; do
    case "$shape" in
      ok)  DEDUPED="${DEDUPED:+$DEDUPED
}$row" ;;
      bad)
        js_report syncjs.link.related_tickets_value_shape_unrecognized \
          "the link dedupe received a row that is not exactly '<declaring-key> <target>' ($(printf '%s' "${row:-<empty>}" | tr -s '[:space:]' ' ' | cut -c1-120)) -- it is REPORTED and skipped, never keyed on its first two fields with the rest discarded, because that truncation IS PROD_CLAIRE-011's mechanism; the validation chokepoint above already refuses every row it can see, so a row arriving here malformed means a NEW contributing arm was added that does not converge on it -- route it through the chokepoint"
        JS_LINK_TARGETS_UNPARSEABLE=$((JS_LINK_TARGETS_UNPARSEABLE + 1)) ;;
    esac
  done < <(awk '
    function rank(k) {
      if (k ~ /^(precedes|preceded_by|blocks|depends_on|blocked_by)$/) return 3
      if (k == "duplicates") return 2
      if (k == "clones")     return 1
      return 0
    }
    # EXACTLY two fields, not "at least two". The `NF >= 2` this replaces IS the
    # mechanism of PROD_CLAIRE-011s silent loss: it read $1 and $2 and discarded $3
    # onward without a word, so `related_tickets CTS-72 and CTS-73` became the
    # target CTS-72 and the rest of the operators declaration vanished. The
    # chokepoint above now makes a >2-field row unreachable, which is precisely
    # why this stays: it is the ASSERTION that a future upstream change
    # re-opening that path fails loudly here instead of truncating silently
    # (DEC-006). "Loudly" is the `bad` arm: awk owns the CLASSIFICATION because
    # it is the only thing that has split the row, and the caller owns the
    # message and the counter because both live in the shell.
    NF == 2 {
      key = $1; tgt = $2; r = rank(key)
      if (!(tgt in bestr)) { order[++n] = tgt; best[tgt] = key; bestr[tgt] = r }
      else if (r > bestr[tgt]) { best[tgt] = key; bestr[tgt] = r }
      next
    }
    NF > 0 { print "bad\t" $0 }
    END { for (i = 1; i <= n; i++) print "ok\t" best[order[i]] " " order[i] }' <<<"$TARGETS")
  TARGETS="$DEDUPED"

  JS_LINK_TARGETS="$TARGETS"
}


# js_metadata_list_signals moved to the colocated jira-link-signals.sh
# (BTG-247 AC-1 headroom; see that file's header for the full rationale).
# Sourced unconditionally, self-located, so js_link_targets's call to it above
# resolves exactly as before.
# shellcheck source=./jira-link-signals.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-link-signals.sh"
