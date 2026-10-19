#!/usr/bin/env bash
#
# authored-doc-gate.sh -- BTG-191. The single home for every guard predicate that
# constrains the content of a document AUTOMATION writes, and the only
# implementation of each.
#
# Bounded context: Build tooling / compile-gate flow. Invariants relied on from
# outside this boundary: `artifacts/footprint.generated` is the source of record
# for which paths ship to an adopter; `artifacts/mcp/mcp.manifest` is the source
# of record for which MCP server rows exist AND states the `claire-` ownership
# sentinel its keys must carry; `docs/agentic-sdlc/CLAIRE_ORG.md` section 16's
# target clauses are the source of record for the org-token set.
#
# Usage:
#   authored-doc-gate.sh                  # repo-wide sweep (the run-gates.sh row)
#   authored-doc-gate.sh --path <file>    # check ONE authored document (write-time)
#   authored-doc-gate.sh --root <dir>     # operate on <dir> instead of this repo
#
# Exit: 0 clean | 1 violation | 2 setup failure -- three outcomes, read
# distinctly by every caller, identical to dead-citation-gate.sh's contract.
#
# IT DETECTS, CLASSIFIES AND BLOCKS; IT NEVER REWRITES -- THIS GATE's own remedy, not
# a claim that no ruling may edit such a document. A release note and an archived
# insight entry are IMMUTABLE RECORDS of what shipped (BTG-190 DEC-006), so a
# violation on one is dispositioned by an anchored ledger row, never an edit; nothing
# here writes into the scanned tree. The two insight registers are NOT symmetric
# though -- see insight-register-disposition.txt for the ruling that split them.
#
# ONE CLASSIFIER, N CALLERS, NEVER A SECOND IMPLEMENTATION -- the architecture
# `artifacts/commands/claire-archive.md` already describes in those words for
# dead-citation-gate.sh. Callers: /claire-release step 4b, the triage-agent's
# PROD-entry append, /claire-archive step 2d, the `authored-doc` run-gates.sh row, and
# the harnesses that SOURCE this file. Sourcing a shared library is not a harness
# invoking a harness, so the BTG-135 invariant is untouched and no exemption is
# requested.
#
# SOURCEABLE. `main` runs only when this file is EXECUTED, so sourcing it gives a
# harness the predicates with no side effect: no `set` change, no trap, no output.
#
# PORTABILITY: bash + grep/awk/sed/sort/cut only; busybox find is not GNU find.
# BTG-200 AC-4: MEASURED on `alpine/latest` + bash diffutils gawk grep sed coreutils,
# a deleted manifest's list. That measurement stands; the present-tense claim about
# what CI *is* is withdrawn -- see `CLAIRE_ORG.md` section 1's CI/CD row.
#
# References: archive/BTG-191/{problem,spec,test-plan,decisions}.md ;
#             ci-templates/scripts/dead-citation-gate.sh (the shape copied).

ADG_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ADG_OWN_FILES -- the basenames this gate is DELIVERED as: this file, every
# sibling it requires, and the ledger data file. They are the CLASSIFIER, not
# documents automation writes, so `sweep_paths` excludes them.
#
# WHY, and why no harness could see it. Here the footprint classes
# `ci-templates` as `framework_dev` and enumerates nothing beneath it, so the
# gate's own source is out of the swept set by construction. An ADOPTER's
# footprint is derived from COPY_PATHS at adopt time and enumerates each
# delivered file individually as `installed` -- so there the ledger became a
# swept document, its rows quote removed MCP keys as needles, and the gate
# reported four violations against its own shipped ledger before the adopter had
# authored anything (review cycle 2, B-5; DEC-021).
#
# DERIVED FROM `adg_require`, NOT LISTED, so a fifth sibling is excluded the
# moment it is required. It does not re-open B-1: the assertion policing these
# files for org tokens reads them DIRECTLY, not through the scan scope.
ADG_OWN_FILES="$(basename "${BASH_SOURCE[0]}")"

# adg_require <file>... -- every dependency must be present AND NON-EMPTY.
#
# `[ -s ]`, NEVER `[ -r ]` OR `[ -f ]`: the gate applies to itself the rule it
# teaches its callers. A zero-byte file is readable, is valid shell and sources
# cleanly, so an existence test admits a TRUNCATED dependency -- after which the
# rule it carried is absent and every run reports clean. Measured by SEAM-1
# (DEC-015).
adg_require() {
  local f
  for f in "$@"; do
    if [ ! -s "$ADG_SELF_DIR/$f" ]; then
      echo "authored-doc: FATAL -- dependency absent or EMPTY: $ADG_SELF_DIR/$f (a zero-byte file sources cleanly and would silently remove the rule it carries)" >&2
      echo "seam_type=IMPOSSIBLE_STATE event_name=authoreddoc.gate.absent_or_empty subject=$f" >&2
      return 2
    fi
  done
  # Record the delivered set as it is required: the loader is the only place
  # that knows it, so nothing can drift out of sync with a second list.
  ADG_OWN_FILES="$ADG_OWN_FILES $*"
  return 0
}

adg_require authored-doc-ledgers.sh || { return 2 2>/dev/null || exit 2; }
# shellcheck source=./authored-doc-ledgers.sh
. "$ADG_SELF_DIR/authored-doc-ledgers.sh"

# adg_ledger_hygiene <tree-root>
#
# One `authoreddoc.disposition.unledgered_site: ...` line per ledger row that is
# not an anchored, per-sentence excuse. THE LEDGER IS ITSELF SUBJECT TO THE RULE
# IT ADMINISTERS: a bad row is a defect the day it is written, before it has
# excused anything, so this runs on every invocation and not only when a document
# trips a predicate.
#
# Two conditions, both measured shapes rather than invented ones:
#
#   (1) AN EMPTY ANCHOR. It excuses nothing legibly and everything in effect --
#       `adg_is_ledgered` would match any line of the named path.
#   (2) AN ANCHOR THAT MATCHES EVERY LINE of its own target file. A row can be
#       written as a sentence and still be a path-wide excuse: `docs/x.md|the|…`
#       is a per-sentence anchor in form and a file-wide one in effect. Checked
#       against the tree rather than against the row's shape, because only the
#       tree can answer it.
#
# This is PROD_CLAIRE-020's recorded shape -- "a blanket exemption blinds the sweep to
# what the archival's own promotion sub-step writes into the exempted file" --
# and it is why BTG176_MCP_KEY_LEDGER carries THREE rows for one release note.
# EVERY PATH-ANCHORED LEDGER THE GATE CONSULTS, not only the one this rule was
# first written for. A rule that governs one of two ledgers leaves the other able
# to take a blanket row unchallenged, and nothing would say so -- the shape
# PROD_CLAIRE-020 records. Caught by SEAM-5, which derives the governed set from this
# very loop and compares it against the ledgers the gate actually reads.
adg_ledger_hygiene() {
  local root="$1" ledger row path anchor total matched
  for ledger in ADG_MCP_KEY_LEDGER BTG095_EXEMPTIONS; do
    eval "set -- \"\${${ledger}[@]}\""
    [ -n "$ADG_EXTRA_LEDGER_ROW" ] && set -- "$@" "$ADG_EXTRA_LEDGER_ROW"
    for row in "$@"; do
      path="${row%%|*}"
      anchor="${row#*|}"; anchor="${anchor%%|*}"
      if [ -z "$anchor" ]; then
        echo "authoreddoc.disposition.unledgered_site: $path:0: a ledger row with an EMPTY anchor excuses every line of that path -- including every future line of a growing directory"
        continue
      fi
      [ -f "$root/$path" ] || continue
      # `grep -c` PRINTS 0 and EXITS 1 on no match, so `|| echo 0` appends a
      # SECOND zero and the comparison below is handed "0\n0". Caught here; the
      # fallback is applied to the captured value, not chained onto the command.
      total="$(grep -c '[^[:space:]]' "$root/$path" 2>/dev/null || true)"; total="${total:-0}"
      matched="$(grep -cF -- "$anchor" "$root/$path" 2>/dev/null || true)"; matched="${matched:-0}"
      if [ "$total" -gt 1 ] && [ "$matched" -eq "$total" ]; then
        echo "authoreddoc.disposition.unledgered_site: $path:0: the anchor matches ALL $total non-blank lines of that path -- a path-wide anchor in all but name, and it excuses every future line of a growing directory"
      fi
    done
  done
}

# The three predicates, plus the reporting/presentation module (BTG-247 rows
# 13-21). `adg_is_ledgered` moved to `authored-doc-predicates.sh` (BTG-247,
# this same pass) -- it is called from nowhere else, so it lives beside its
# sole consumer rather than in the entry point (DEC-003's subject-cohesion
# argument, applied a second time). Split along the classifier/predicate seam
# once one file passed the ceiling -- the same split dead-citation-gate.sh
# made from its own ledgers. One classifier, several files; never several
# implementations.
adg_require authored-doc-predicates.sh authored-doc-orgtoken.sh authored-doc-report.sh \
  || { return 2 2>/dev/null || exit 2; }
# shellcheck source=./authored-doc-predicates.sh
. "$ADG_SELF_DIR/authored-doc-predicates.sh"
# shellcheck source=./authored-doc-orgtoken.sh
. "$ADG_SELF_DIR/authored-doc-orgtoken.sh"
# shellcheck source=./authored-doc-report.sh
. "$ADG_SELF_DIR/authored-doc-report.sh"

# ======================================================================
# MAIN
# ======================================================================
adg_main() {
  local root="" mode=sweep target="" violations=0 examined=0

  root="$(cd "$ADG_SELF_DIR/../.." && pwd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) root="${2:-}"; shift 2 ;;
      --path) mode=path; target="${2:-}"; shift 2 ;;
      --ledger-hygiene-only) mode=hygiene; shift ;;
      -h|--help) sed -n '13,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
      *) echo "authored-doc: unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  [ -d "$root" ] || adg_setup_failure authoreddoc.root.unreadable "tree root not a directory: $root"

  local paths
  if [ "$mode" = hygiene ]; then
    paths=""
  elif [ "$mode" = path ]; then
    [ -n "$target" ] || adg_setup_failure authoreddoc.path.missing "--path given with no file"
    [ -f "$root/$target" ] \
      || adg_setup_failure authoreddoc.path.unreadable "document not readable: $target"
    paths="$target"
  else
    paths="$(sweep_paths "$root")"
  fi
  examined="$(printf '%s\n' "$paths" | grep -c . || true)"

  # SEAM-3, first condition: a sweep that resolved NOTHING certifies nothing.
  # An empty census measures only what its own detector is built to see (II-131),
  # and a clean verdict over zero paths is indistinguishable from a clean verdict
  # over a whole tree unless the run refuses. Mirrors `guard_examined_count`'s
  # existing refusal to believe an empty leak list.
  if [ "$mode" = sweep ] && [ "$examined" -eq 0 ]; then
    adg_setup_failure authoreddoc.sweep.examined_nothing \
      "the sweep resolved 0 paths from $root -- it examined nothing and certifies nothing"
  fi

  echo "=== authored-doc gate: guard predicates over documents automation writes ==="

  local hit path line text
  # LEDGER HYGIENE FIRST, on every invocation. A ledger row that is a blanket
  # excuse is a defect the day it is written, and checking it only when some
  # document happens to trip a predicate would make the check depend on the very
  # blindness it exists to remove.
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit="${hit#authoreddoc.disposition.unledgered_site: }"
    path="${hit%%:*}"; text="${hit#*:}"; line="${text%%:*}"; text="${text#*: }"
    adg_report_violation ledger-hygiene authoreddoc.disposition.unledgered_site \
      "$path" "$line" "$text"
    violations=$((violations + 1))
  done <<< "$(adg_ledger_hygiene "$root")"

  [ "$mode" = hygiene ] && {
    echo "authored-doc: ledger hygiene only -- $violations violation(s)"
    [ "$violations" -eq 0 ] || { adg_print_dispositions; return 1; }
    return 0
  }

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit="${hit#mcp.manifest.row_referenced_but_absent: }"
    path="${hit%%:*}"; line="${hit#*:}"
    text="$(sed -n "${line}p" "$root/$path" 2>/dev/null)"
    adg_report_violation mcp-key-ledger mcp.manifest.row_referenced_but_absent \
      "$path" "$line" "$text"
    violations=$((violations + 1))
    # shellcheck disable=SC2086 -- paths are newline-separated, word-split is intended
  done <<< "$(predicate_mcp_key "$root" $paths)"

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit="${hit#dxscope.representation.unenumerated_site -- }"
    path="${hit%%:*}"; text="${hit#*:}"; line="${text%%:*}"; text="${text#*: }"
    adg_report_violation dx-measure-scope dxscope.representation.unenumerated_site \
      "$path" "$line" "$text"
    violations=$((violations + 1))
    # shellcheck disable=SC2086 -- paths are newline-separated, word-split is intended
  done <<< "$(predicate_dx_measure "$root" $paths)"

  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    hit="${hit#intent.portability.org_token_in_portable_path: }"
    path="${hit%%:*}"; text="${hit#*:}"; line="${text%%:*}"; text="${text#*:}"
    # A derivation failure is a SETUP failure, not a finding: the sweep examined
    # nothing (or only part of what the org configuration declares) and certifies
    # nothing. Reporting it as a violation would tell an operator to fix a
    # document when the guard itself could not run.
    if [ "$path" = "<token-derivation>" ]; then
      # PASSED THROUGH WHOLE, never truncated. The derivation reports two
      # distinct conditions -- nothing derived, and a DECLARED adapter whose
      # token did not parse -- and the second names the offending subsection at
      # the END of its message. Cutting the message to a fixed width would drop
      # exactly the part that tells an operator which adapter to fix, in exactly
      # the case that condition was added for.
      adg_setup_failure authoreddoc.sweep.examined_nothing "$text"
    fi
    adg_report_violation org-token-portability intent.portability.org_token_in_portable_path \
      "$path" "$line" "$text"
    violations=$((violations + 1))
    # shellcheck disable=SC2086 -- paths are newline-separated, word-split is intended
  done <<< "$(predicate_org_token "$root" $paths)"

  # SEAM-3, second condition: the DX enumeration matched NOTHING over a scan set
  # that contains an operative representation of the rule.
  #
  # Anchored to REPS rather than to a raw hit count, and that is what makes it
  # usable rather than obstructive. Zero DX hits is the NORMAL state for one clean
  # drafted release note, so a bare zero-hits rule would block every clean cut.
  # What is never normal is a scan set containing a path whose whole definition is
  # that it STATES the measure, matching nothing: the only explanation is that the
  # enumeration commands have stopped matching, and every later clean verdict from
  # this predicate would be vacuous. btg-090's own S-3.2 carries the same refusal
  # in the same words.
  # shellcheck disable=SC2086 -- paths are newline-separated, word-split is intended
  if [ "$mode" = sweep ] && [ -z "$(adg_dx_hits "$root" $paths)" ]; then
    for path in $paths; do
      for line in "${REPS[@]}"; do
        [ "$path" = "$line" ] || continue
        adg_report_violation dx-measure-scope authoreddoc.sweep.examined_nothing \
          "$path" 0 "VACUOUS: the DX sweep found NO hits over a scan set holding this enumerated representation; the enumeration has stopped matching"
        violations=$((violations + 1))
        break 2
      done
    done
  fi

  # SEAM-4, sweep mode only: name the documents no write-time step covers, and
  # say plainly that this sweep is what compensates for them.
  # shellcheck disable=SC2086 -- paths are newline-separated, word-split is intended
  [ "$mode" = sweep ] && adg_report_uncovered "$root" $paths

  echo "authored-doc: $examined document(s) examined, $violations violation(s)"
  [ "$violations" -eq 0 ] || { adg_print_dispositions; return 1; }
  return 0
}

# THE LOAD IS VERIFIED, NOT ASSUMED, and it is verified HERE -- after every
# definition, including this file's own -- rather than beside the `source` lines.
# A file can be non-empty and still not define what it is named for: half-merged,
# half-written, or edited into a comment block. A predicate that failed to load
# reports nothing, and reporting nothing is precisely what a clean run looks like.
for adg_fn in predicate_mcp_key predicate_dx_measure predicate_org_token \
              adg_is_ledgered adg_portable_paths adg_org_tokens sweep_paths \
              adg_emit_seam adg_report_violation adg_setup_failure adg_uncovered_documents adg_report_uncovered; do
  declare -F "$adg_fn" >/dev/null 2>&1 && continue
  echo "authored-doc: FATAL -- $adg_fn is undefined after loading; the rule it carries would silently report nothing" >&2
  echo "seam_type=IMPOSSIBLE_STATE event_name=authoreddoc.gate.absent_or_empty subject=$adg_fn" >&2
  return 2 2>/dev/null || exit 2
done
unset adg_fn

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -u
  adg_main "$@"
  exit $?
fi
