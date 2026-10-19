#!/usr/bin/env bash
#
# upgrade-collect-state.sh -- seed classification and merge-scope state for the
# /claire-upgrade in-scope collection concern, split out of the colocated
# upgrade-collect.sh (BTG-247 DEC-029: a partial shed to buy headroom under the
# CI-enforced LCG_CEILING gate, once DEC-018 exempted upgrade-collect.sh BY NAME
# from AC-1's general headroom threshold -- so the only live constraint left on
# that file is the gate itself, applied with -ge).
#
# Bounded context: same as upgrade-collect.sh -- the Upgrade seam / layered-source
# flow (PI-022, Workstream A). Sourced UNCONDITIONALLY by upgrade-collect.sh via a
# self-locating guard (${BASH_SOURCE[0]}, never a caller-supplied $SELF_DIR, which
# several harnesses leave unset when they source upgrade-collect.sh standalone --
# DEC-017's finding).
#
# WHY this boundary: DEC-017's full 24-harness audit classified upgrade-collect.sh's
# content into anchored/entangled regions (the RECONCILE table, the BTG-015/BTG-020/
# BTG-007 marker-anchored dispatch logic inside collect_in_scope(), the BTG-015
# regression guard's closing loop, and resolve_root()) that at least one harness
# sed-anchors or textually pins to THAT file, versus the two blocks moved here,
# which no harness anchors by marker or line range and which are not entangled with
# collect_in_scope()'s SEENMAP-populating control flow. This is the audited-safe set
# DEC-017 identified and DEC-029 sheds.
#
# Holds: the RECONCILE-table-derived seed classification (_is_seed_path,
# _derive_seed_files, SEED_FILES -- read by the colocated upgrade-repair.sh's
# --repair restore loop) and the collect_in_scope()-populated module-scope state
# arrays (IN_SCOPE, DIR_EXPANDED, RECONCILE_BACKFILLED), moved VERBATIM -- no
# re-wrap, no logic change. Pre-split lines :130-:189 of upgrade-collect.sh.
#
# Spec: archive/BTG-247/spec.md (Proposed Design Step 1); archive/BTG-247/decisions.md
# DEC-017 (the audit), DEC-018 (the exemption), DEC-029 (this shed).

# A path is a seed iff the unified RECONCILE table carries it as an exclude/seed row (DEC-006;
# SEED_FILES subsumed). Same result as the former SEED_FILES scan, one data structure. Not a
# denylist: a brand-new seed is a kind=seed derive row; an exclude row is added ONLY to retype
# a file the fleet already committed installed (BTG-015/018).
_is_seed_path() {
  local p="$1" _row _rpath _rkind _rdir
  for _row in "${RECONCILE[@]}"; do
    IFS='|' read -r _rpath _rkind _rdir _ <<<"$_row"
    [[ "$_rkind" == seed && "$_rdir" == exclude && "$p" == "$_rpath" ]] && return 0
  done
  return 1
}

# SEED_FILES is a DERIVED projection of the RECONCILE exclude/seed rows, computed once at
# source time. It is NOT a second hand-maintained list (DEC-006): RECONCILE stays the single
# source of truth, so adding a seed remains a one-row RECONCILE addition. It is retained only
# because the colocated --repair sidecar (upgrade-repair.sh) iterates ${SEED_FILES[@]} by name
# to restore each adopter-owned seed from its pre-upgrade git blob; keeping the projection
# preserves that cross-module contract byte-for-byte without touching that file (BTG-020
# DEC-009). _is_seed_path derives from RECONCILE directly, not from this. That restore loop is
# the SOLE consumer, so the projection is the RESTORABLE subset: a row whose field-4 disposition
# is `no-restore` stays a seed for the MERGE (_is_seed_path still returns true for it) and is
# not a seed for the RESTORE. Declared in the table, never a second list here.
SEED_FILES=()
_derive_seed_files() {
  local _row _rpath _rkind _rdir _rres
  for _row in "${RECONCILE[@]}"; do
    IFS='|' read -r _rpath _rkind _rdir _rres _ <<<"$_row"
    [[ "$_rkind" == seed && "$_rdir" == exclude && "$_rres" != no-restore ]] && SEED_FILES+=("$_rpath")
  done
}
_derive_seed_files

# Enumerate the in-scope merge set: every file under the footprint's resolved
# tree roots + every installed path, as repo-relative paths present in EITHER the
# adopter tree (theirs) or core@new (ours). The boundary is CONSUMED from the
# committed descriptor (DEC-008) -- this engine does NOT re-derive the boundary.
# Tree roots resolve through the adapter exactly as eject does. Populates the
# global IN_SCOPE array. Args: <ours_commit>.
IN_SCOPE=()
# DIR_EXPANDED (G-4 / DEC-004, PI-031 provenance): constituent rel-path -> its
# source directory-row path, populated by upstream's expand_dir_row (defined in
# upgrade-bootstrap.sh) when a directory-valued installed row is expanded. Declared
# associative at file scope so expand_dir_row's `DIR_EXPANDED["$rel"]="$ip"` writes
# resolve correctly under `set -u` (an undeclared array would be treated as indexed,
# corrupting string keys) and so main()'s merge loop can read it to fire the
# directory_as_file_path anomaly seam. collect_in_scope resets it each run.
declare -A DIR_EXPANDED=()
# RECONCILE_BACKFILLED (BTG-100 / DEC-002): rel-path -> 1 for every RECONCILE
# installed+add row whose PER-ENTRY DEDUP DID NOT FIRE. A row is appended only
# when the descriptor loop did not already accumulate that path, so this key set
# is EXACTLY "the adopter's own committed descriptor never carried this path" --
# the authoritative "never installed IN THIS TREE" signal. merge_one_file reads it
# (dynamic scoping, exactly as main() reads DIR_EXPANDED) to pick an EMPTY base
# instead of core@base content; core@base membership, which the pre-existing G-5
# branch uses, is the WRONG proxy for this question (PROD_CLAIRE-010: BTG-083 shipped in
# v4.0.5, so core@base already owns these paths for the reporting adopter).
# Declared associative at file scope for the same `set -u` reason DIR_EXPANDED is:
# an undeclared array is treated as indexed and corrupts string keys.
declare -A RECONCILE_BACKFILLED=()
