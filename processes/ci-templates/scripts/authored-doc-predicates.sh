#!/usr/bin/env bash
#
# authored-doc-predicates.sh -- the three guard predicates
# ci-templates/scripts/authored-doc-gate.sh classifies with, and the ONLY
# implementation of each (BTG-191).
#
# Bounded context: Build tooling / compile-gate flow. Invariants relied on from
# outside this boundary: `artifacts/footprint.generated` is the source of record
# for which paths ship to an adopter; `artifacts/mcp/mcp.manifest` is the source
# of record for which MCP server rows exist AND states the `cadence-` ownership
# sentinel its keys must carry; `docs/agentic-sdlc/CADENCE_ORG.md` section 16's
# target clauses are the source of record for the org-token set.
#
# SOURCED, never executed. It defines functions only -- no `set` change, no trap,
# no output -- and it relies on the three ledger arrays being defined by the
# caller BEFORE it is sourced, exactly as dead-citation-ledgers.sh relies on
# its caller. `adg_is_ledgered` (BTG-247 rows 13-21) moved IN here from
# authored-doc-gate.sh -- it is defined by THIS file now, not relied on from
# the caller.
#
# WHY IT IS A SEPARATE FILE, and why that is a real seam rather than a way around
# a number. The gate is the CLASSIFIER -- the CLI, the exit contract, the
# attribution rules, the scan scope and the ledger-hygiene rule that governs every
# ledger. This file is the PREDICATES -- three rules with three different
# subjects, each moved verbatim out of the harness library that used to own it.
# The two answer different questions and change for different reasons: a fourth
# predicate lands here and touches nothing in the gate, while a change to the
# report shape lands there and touches no predicate. Held in one file they came to
# 796 lines, twice the whole-file ceiling a named gate script is governed by --
# and the split is the same one dead-citation-gate.sh made from
# dead-citation-ledgers.sh, along the same kind of seam, for the same reason. It
# is ONE classifier delivered as three files, not three implementations.
#
# EVERY PREDICATE TAKES ITS TREE ROOT AS A PARAMETER, without exception. That is
# what lets an ablation run the real predicate over a mutated copy of a tree
# instead of over a re-implementation of it, and it is why the AC-5 arms in
# ci-templates/scripts/tests/btg-191-authored-doc-gate.test.sh can be executed
# rather than asserted in prose.
#
# PORTABILITY: bash + grep/awk/sed/sort/cut only. No `find -printf`, no python3.
#
# References: archive/BTG-191/{problem,spec,test-plan,decisions}.md ;
#             ci-templates/scripts/authored-doc-gate.sh (the classifier) ;
#             ci-templates/scripts/authored-doc-ledgers.sh (the ledgers).

# ======================================================================
# SCAN SCOPE -- the W-document set, derived
# ======================================================================


# sweep_paths <tree-root> -- the documents the repo-wide sweep examines.
#
# DERIVED, in two halves, neither of them a hand-maintained list:
#   * every shipping path the footprint declares (the insights registers, the
#     governance docs, the neutral source), and
#   * the release-notes directory by GLOB -- it is outside the footprint
#     (release notes do not ship to an adopter) but is the single largest source
#     of /cadence-release-authored content, so a glob covers every future cut with no
#     edit here.
# Only paths that exist in the tree are emitted.
sweep_paths() {
  local root="$1" p own
  {
    adg_portable_paths "$root"
    ( cd "$root" 2>/dev/null && ls docs/releases/*.md 2>/dev/null )
  } | while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$root/$p" ] || continue
    # The gate's OWN delivered files are the classifier, never a swept document.
    # In this repository they are invisible to the footprint anyway; in an
    # adopter tree they are enumerated individually as installed, and without
    # this the gate reports its own ledger as a violation (B-5).
    for own in $ADG_OWN_FILES; do
      case "$p" in "$own"|*/"$own") continue 2 ;; esac
    done
    echo "$p"
  done
}

# Moved verbatim from authored-doc-orgtoken.sh (BTG-247, pre-split :70-:101,
# :347-:357) -- adg_portable_paths was already called from THIS file (subject).

# adg_portable_paths <tree-root> -- every repo-relative path that SHIPS, derived
# from the footprint descriptor. Echoes one path per line; a path may be a file
# or a directory.
#
# EXTRACTED VERBATIM from btg-095-lib/guard.sh's `portable_paths`. Derived, never
# hardcoded: a hand-maintained portable-path list agrees with itself forever
# while a newly-installed path silently escapes the guard.
adg_portable_paths() {
  local fp="$1/artifacts/footprint.generated"
  [ -f "$fp" ] || return 0
  awk -F'[ =]' '
    /^kind=(installed|seed) / {
      path = ""
      for (i = 1; i <= NF; i++) if ($i == "path") path = $(i+1)
      if (path != "") print path
    }' "$fp"
  grep -q '^kind=tree_root identity=roles' "$fp" && echo 'artifacts/roles'
  grep -q '^kind=tree_root identity=commands' "$fp" && echo 'artifacts/commands'
  return 0
}

# is_exempt <repo-relative-path> <line-text>
adg_is_exempt() {
  local path="$1" line="$2" row epath anchor
  for row in "${BTG095_EXEMPTIONS[@]}"; do
    epath="${row%%|*}"
    anchor="${row#*|}"; anchor="${anchor%%|*}"
    [[ "$path" == "$epath" ]] || continue
    case "$line" in *"$anchor"*) return 0 ;; esac
  done
  return 1
}

# guard_examined_count <tree-root> -- how many shipping paths the guard resolved.
# A guard that reports "clean" having examined nothing certifies nothing, so every
# caller checks this before believing an empty leak list.
adg_guard_examined_count() {
  local n=0 p
  while read -r p; do
    [[ -z "$p" ]] && continue
    [[ -e "$1/$p" ]] && n=$((n + 1))
  done <<< "$(adg_portable_paths "$1")"
  echo "$n"
}

# ======================================================================
# PREDICATE 1 -- MCP server keys named but absent from the manifest
# ======================================================================

# adg_is_ledgered <ledger-array-name> <path> <line-text>
#
# A row matches only when the offending line CONTAINS its anchor. Substring, not
# equality, and keyed to file AND text: an unanchored row would excuse the very
# pattern the guard polices, and a NEW occurrence in an already-excused file must
# still be reported.
#
# MOVED VERBATIM from authored-doc-gate.sh (BTG-247 rows 13-21, DEC-007's
# 324-line threshold): called from nowhere but `predicate_mcp_key` below, so it
# lives beside its sole consumer (DEC-003's subject-cohesion argument, applied
# a second time).
adg_is_ledgered() {
  local ledger="$1" path="$2" text="$3" row epath anchor
  eval "set -- \"\${${ledger}[@]}\""
  for row in "$@"; do
    epath="${row%%|*}"
    anchor="${row#*|}"; anchor="${anchor%%|*}"
    [ "$path" = "$epath" ] || continue
    [ -n "$anchor" ] || continue
    case "$text" in *"$anchor"*) return 0 ;; esac
  done
  return 1
}

# The manifest's OWN documented ownership grammar, and the entire coupling
# between this predicate and that declaration: `key=<server-key>` is a
# "RESERVED-prefixed ownership sentinel (MUST start "cadence-")"
# (artifacts/mcp/mcp.manifest). Reading the grammar rather than enumerating the
# keys is what makes a FUTURE removal covered on the day it lands, with no edit
# here -- the "read the manifest; do not hardcode it" decision rule.
ADG_MCP_KEY_RE='cadence-mcp-[a-z0-9][a-z0-9-]*'

# adg_mcp_occurrences <tree-root> <ledger-array-name> <needle-ere> <scan-root>...
#
# One `<path>:<line>` per occurrence of <needle-ere> under <scan-root>... that no
# row of <ledger-array-name> anchors. Comment lines are excluded (a key named in
# a comment is prose about the removal, not a live expectation).
#
# EXTRACTED VERBATIM from btg-176-lib/mcp-manifest.sh's `btg176_mcp_dangling`,
# with the needle, the LEDGER and the scan roots lifted to parameters so the one
# body serves both that harness's single-key sweep against its own ledger and
# this gate's grammar-derived sweep against the wider one. That file now calls
# this function; there is exactly one implementation.
#
# `-H` IS THE ONE ADDITION, and it is load-bearing rather than cosmetic: the
# pre-extraction form only ever received DIRECTORIES, where `grep -rn` prints the
# path anyway. The write-time caller passes ONE FILE, and `grep -rn` on a file
# prints `line:text` with NO path -- so every hit would parse with the line
# number as the path and be silently dropped. MEASURED, not reasoned about:
# BTG-200 AC-4: `docker run alpine:latest` with the package list the then-current
# CI manifest installed (that manifest is now deleted; the measurement is not)
# shows busybox grep and GNU grep 3.12 both omit the path without
# `-H` and both print it with `-H`, byte-identically, for a file target AND for a
# directory target. So adding it changes nothing for the harness's call.
#
# THE LEDGER IS A PARAMETER RATHER THAN A CONSTANT ON PURPOSE. The gate's ledger
# is a strict superset of the harness's, and passing the superset to the harness
# would have widened what that harness excuses as a side effect of an extraction
# it never asked for. Each caller names the ledger it means.
adg_mcp_occurrences() {
  local root="$1" ledger="$2" needle="$3"; shift 3
  local hit path line
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path="${hit%%:*}"; hit="${hit#*:}"
    line="${hit%%:*}"
    adg_is_ledgered "$ledger" "$path" "${hit#*:}" || echo "$path:$line"
  done <<< "$(cd "$root" && grep -rnHE "$needle" "$@" 2>/dev/null \
                 | grep -vE '^[^:]*:[0-9]*:[[:space:]]*#' || true)"
}

# predicate_mcp_key <tree-root> <path>...
#
# One `mcp.manifest.row_referenced_but_absent: <path>:<line>` per occurrence of a
# `cadence-mcp-*` key that the tree's manifest does NOT carry and no ledger row
# anchors. A key the manifest DOES carry is a live registration, so naming it is
# correct and is not reported -- that filter is what makes this a statement about
# the manifest rather than about one historical key.
predicate_mcp_key() {
  local root="$1"; shift
  local manifest="$root/artifacts/mcp/mcp.manifest"
  local hit path line key
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path="${hit%%:*}"; line="${hit#*:}"; line="${line%%:*}"
    key="$(sed -n "${line}p" "$root/$path" 2>/dev/null | grep -oE "$ADG_MCP_KEY_RE" | head -1)"
    [ -n "$key" ] || continue
    grep -qE "(^|[[:space:]])key=${key}([[:space:]]|$)" "$manifest" 2>/dev/null && continue
    echo "mcp.manifest.row_referenced_but_absent: $path:$line"
  done <<< "$(adg_mcp_occurrences "$root" ADG_MCP_KEY_LEDGER "$ADG_MCP_KEY_RE" "$@")"
}

# ======================================================================
# PREDICATE 2 -- restatements of the DX file-length measure
# ======================================================================

# adg_dx_hits <tree-root> <path>...
#
# Every line under <path>... that states a file-size measure, as
# `<path>:<line>:<text>`.
#
# EXTRACTED VERBATIM from btg-090-dx-measure-scope.test.sh's `sweep_hits`, with
# the scan roots lifted to parameters. Both of that function's passes are kept
# and are kept SEPARATE, because they are not the same question: pass 1 asks
# prose documents for a measure stated as a rule, pass 2 asks the neutral source
# for a measure stated anywhere at all.
#
# THE PARTITION IS PART OF THE RULE, not an implementation detail, and getting it
# wrong was MEASURED here rather than reasoned about. `sweep_hits` hard-codes two
# DIFFERENT root sets: pass 1 over prose (`--include='*.md'`, a tight keyword
# filter that demands the measure be stated as a rule) and pass 2 over the
# NEUTRAL SOURCE AND ITS MIRRORS ONLY, with a looser filter that any 3-4 digit
# number can reach. Running pass 2 over prose as well -- which is what "give both
# passes the same paths" does -- produced TWENTY findings on the committed tree,
# every one of them a release note, a registry row or an insight entry RECORDING
# a past line count. Not one was an operative restatement of the rule. Widening a
# guard until it reports records is how a gate earns a blanket exemption, which
# is the outcome this whole design exists to avoid, so the partition is
# reproduced exactly.
#
# THE VALUE PATTERN IS DELIBERATELY NOT (300|400), and that is load-bearing
# rather than incidental. A sweep that searches only for the two values already
# known cannot detect a site stating a THIRD -- and a site nobody anticipated is
# exactly what this predicate exists to catch. Matching any 3-4 digit line count
# is what makes a planted 250-line ceiling turn it red.
#
# `--include` IS A GNU-GREP DEPENDENCY, inherited unchanged from the
# pre-extraction form. BTG-200 AC-4: the then-current CI manifest installed the
# `grep` package, which put GNU grep 3.12 rather than busybox at /bin/grep on the
# measured image -- verified by running that base image, not by reasoning about
# flag support. The manifest is deleted; the measurement stands, and this
# dependency is stated as a requirement on any substrate rather than as a claim
# about one that runs.
adg_dx_hits() {
  local root="$1"; shift
  local p prose=() source=()
  for p in "$@"; do
    case "$p" in
      artifacts/roles|artifacts/roles/*|artifacts/commands|artifacts/commands/*| \
      .agents/agents|.agents/agents/*|.agents/skills|.agents/skills/*| \
      *opencode-golden*) source+=("$p") ;;
      *) prose+=("$p") ;;
    esac
  done
  ( cd "$root" 2>/dev/null || return 0
    {
      [ "${#prose[@]}" -gt 0 ] && \
        grep -rnH -E '(<|less than |under |target[: ]|exceed )[[:space:]]*[<]?[[:space:]]*[0-9]{3,4}([ -]?line| lines)?' \
          --include='*.md' "${prose[@]}" 2>/dev/null \
          | grep -iE 'file size|files? <|lines per file|line ceiling|line cap|exceed [0-9]{3}|<[0-9]{3} lines|target: <'
      [ "${#source[@]}" -gt 0 ] && \
        grep -rnH -E '[0-9]{3,4}' "${source[@]}" 2>/dev/null \
          | grep -iE 'file size|files? <|lines per file|line ceiling|line cap|exceed [0-9]{3}|<[0-9]{3}'
    } 2>/dev/null )
    # NO `sort -u`. An earlier draft added one and it was caught by the
    # byte-identity arm rather than by any verdict: the pre-extraction form emits
    # hits in pass order, and its consumer breaks on the FIRST offender, so
    # reordering changes WHICH site a failure names while leaving every pass/fail
    # unchanged. That is precisely the reported-text drift RISK-6 names and that a
    # green suite cannot see. The two passes address disjoint path sets, so there
    # is nothing to deduplicate anyway.
}

# predicate_dx_measure <tree-root> <path>...
#
# One `dxscope.representation.unenumerated_site -- <path>:<line>: <text>` per hit
# that is neither an enumerated operative representation (a REPS path), nor an
# attributed dated-provenance exemption, nor a recorded non-measure false
# positive. The three-way classification is btg-090's, unchanged.
predicate_dx_measure() {
  local root="$1"; shift
  local hit path rest line text rep anchor
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path="${hit%%:*}"; rest="${hit#*:}"
    line="${rest%%:*}"; text="${rest#*:}"
    for rep in "${REPS[@]}"; do [ "$path" = "$rep" ] && continue 2; done
    for anchor in "${PROVENANCE_ANCHORS[@]}"; do
      case "$text" in *"$anchor"*) continue 2 ;; esac
    done
    for anchor in "${NON_MEASURE_ANCHORS[@]}"; do
      case "$text" in *"$anchor"*) continue 2 ;; esac
    done
    echo "dxscope.representation.unenumerated_site -- $path:$line: $text"
  done <<< "$(adg_dx_hits "$root" "$@")"
}

