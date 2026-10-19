#!/usr/bin/env bash
#
# upgrade-collect.sh -- the /cadence-upgrade in-scope collection concern (BTG-020 DEC-002),
# extracted from upgrade-bootstrap.sh so each module holds a
# single coherent concern and both stay under the DX <300-line target. This is a
# BEHAVIOR-PRESERVING extraction + consolidation: collect_in_scope, resolve_root, _is_seed_path
# (now table-derived) and the IN_SCOPE array move here, and the three former bespoke per-path
# backfills are unified into ONE data-driven RECONCILE table (DEC-006) consumed with
# position-aware dispatch -- no observable-output change (scope, log lines, seams all preserved).
#
# Bounded context: Upgrade seam / layered-source flow (PI-022, Workstream A). Sourced by
# upgrade-bootstrap.sh via a self-locating guard, so it runs in the entry point's shell scope:
# the globals these functions read (SELF_DIR, CORE, TARGET, FOOTPRINT) and the emit_seam helper
# are resolved at CALL time from that scope (dynamic scoping). This file is one of the colocated
# sidecar modules the PI-023 directory-copy contract ships into the compiled skill.
#
# Holds: the unified RECONCILE table (BTG-008/015/018/019 corrections as data rows, subsuming
# the former SEED_FILES array), the table-derived _is_seed_path helper, the IN_SCOPE array,
# collect_in_scope (in-loop exclude dispatch + post-loop add dispatch + the pre-fold dedup guard
# + the dir-expansion branch + the seed regression guard), and resolve_root.
#
# Spec: specs/BTG-020/spec.md (DEC-002 extraction, DEC-006 table, DEC-007 anchors); specs/BTG-007/spec.md (R-4 dir-expand, PI-002).

# UNIFIED reconciliation table (BTG-020, DEC-006). ONE data structure drives all
# three corrections a stale committed footprint may need -- the discrepancies
# between what core@new declares and what a pre-feature committed descriptor says.
# A fourth correction -- in EITHER direction -- is a one-row data addition, no new
# code block (AC-1/AC-5). Row schema:
#   <core_path>|<kind:tree_root|installed|seed>|<direction:add|exclude>|<resolver>|<origin>
#   add+tree_root : core@new-declared -> resolve <resolver> via resolve_root, dedup+append roots[]
#   add+installed : core@new-declared -> append <core_path> verbatim,        dedup+append installed[]
#   exclude+seed  : a descriptor row typing this path kind=installed IS a seed -> excluded
#                   IN-LOOP (skip line), never appended. Field 4, unused by the merge, is the
#                   --repair disposition: empty = restorable, `no-restore` = Concern 1 skips it.
# This is NOT a re-derivation of the boundary (ADR_CADENCE-0009): each add row is gated by
# core ownership (git cat-file -e) and each exclude row names a KNOWN adopter-owned
# seed the fleet already committed installed. The former SEED_FILES array is
# subsumed here (DEC-006); adding/retyping a seed is one exclude row (was: one
# SEED_FILES entry), and _is_seed_path derives from these rows (same result).
RECONCILE=(
  "artifacts/hooks|tree_root|add|artifact_root:hooks|BTG-008"
  "docs/agentic-sdlc/intent-insights.md|seed|exclude||BTG-015"
  "docs/agentic-sdlc/production-insights.md|seed|exclude||BTG-015"
  "docs/policies/surface-registry.md|seed|exclude||BTG-015"
  "docs/SYSTEM_OVERVIEW.md|seed|exclude||BTG-018"
  # BTG-100 (PROD_CADENCE-010): the three dead-citation COPY_PATHS entries BTG-083 added WITHOUT
  # a matching RECONCILE row. ci-templates/scripts is not a tree_root, so these reach an
  # adopter ONLY as named installed rows -- and a descriptor frozen before BTG-083 never
  # carries them, so /cadence-archive step 2b's blocking classifier never arrives (two field
  # reports: CTS-70, CTS-37). Data-only, exactly as the DEC-006 extensibility property
  # promises. SAFE ONLY IN COMBINATION with the backfill-base rule below
  # (upgrade-bootstrap.sh, BTG-100 backfill-base-anchor): rows alone are FAIL-OPEN for an
  # adopter stamped at or after v4.0.5, where core@base already owns these paths -- see
  # spec.md Alternative 1.
  "ci-templates/scripts/dead-citation-gate.sh|installed|add||BTG-100"
  "ci-templates/scripts/dead-citation-ledgers.sh|installed|add||BTG-100"
  "ci-templates/scripts/dead-citation-exemptions.txt|installed|add||BTG-100"
  # BTG-186 (PROD_CADENCE-010): the chaos-citation gate's COPY_PATHS entry, paired with its
  # RECONCILE row IN THE SAME CHANGE. ci-templates/scripts is not a tree_root, so a
  # descriptor frozen before this ticket never carries the new script and the adopter's
  # shipped run-gates.sh pre-flight aborts on a file they can never receive. That is
  # exactly the BTG-083 omission this row exists to not repeat -- two field reports.
  "ci-templates/scripts/chaos-citation-gate.sh|installed|add||BTG-186"
  "ci-templates/scripts/core-prefix-seed-gate.sh|installed|add||BTG-197"
  # BTG-191 (PROD_CADENCE-010, again): the authored-document gate's four files, each with its
  # RECONCILE row IN THE SAME CHANGE that adds its COPY_PATHS entry. FOUR rows, not
  # one: the classifier is an entry point plus three sourced files, and the runner's
  # pre-flight aborts on the ENTRY POINT alone -- so an adopter who received only that
  # one would get a runner that starts and a gate that cannot run, the same class one
  # level in. ci-templates/scripts is not a tree_root, so a descriptor frozen before
  # this ticket carries none of them and only these rows can reach that adopter.
  "ci-templates/scripts/authored-doc-gate.sh|installed|add||BTG-191"
  "ci-templates/scripts/authored-doc-predicates.sh|installed|add||BTG-191"
  "ci-templates/scripts/authored-doc-orgtoken.sh|installed|add||BTG-191"
  "ci-templates/scripts/authored-doc-ledgers.sh|installed|add||BTG-191"
  # BTG-247 DEC-007/spec.md Step 5: the fifth sourced sibling, same
  # PROD_CADENCE-010 reasoning as the four rows above; installed one row
  # later, same ticket.
  "ci-templates/scripts/authored-doc-report.sh|installed|add||BTG-247"
  # BTG-191: the exemption LEDGER is adopter-owned DATA, not framework code, so
  # it is seed/exclude -- an upgrade must never overwrite an adopter's accrued
  # rows with ours. Its rows quote THIS repo's history, including live project
  # keys; /cadence-adopt copies it with the rows stripped (review cycle 1, B-1).
  "ci-templates/scripts/authored-doc-exemptions.txt|seed|exclude||BTG-191"
  # BTG-109 (PROD_CADENCE-010, the DEC-014 residual): the COPY_PATHS entries added AFTER the
  # descriptor mechanism (PI-017, 2026-06-23) with no RECONCILE row. Ordered
  # branch-strategy-pair-first per CADENCE_ORG.md section 15, which binds trunk-based.md
  # BY NAME -- a pre-BTG-047 descriptor resolves that binding to an ABSENT FILE, and
  # upgrade-removals.sh has already deleted the flat predecessor, so the adopter ends
  # with NEITHER document (a net loss, not a missing new file).
  # SAFE ONLY IN COMBINATION with the backfill-base rule, exactly as stated in
  # full on the BTG-100 rows above.
  "docs/policies/branch-strategy/trunk-based.md|installed|add||BTG-109"
  "docs/policies/branch-strategy/long-lived-feature-release.md|installed|add||BTG-109"
  # BTG-109 (cont.): cadence-eject.sh SOURCES both modules below (directly for
  # the transform, via eject-footprint.sh for the headers), so an adopter missing
  # either cannot run the eject path -- and eject is this repo's Source
  # Confidentiality mechanism. Partial delivery of one is as broken as neither.
  "ci-templates/scripts/eject-footprint-headers.sh|installed|add||BTG-109"
  "ci-templates/scripts/eject-transform.sh|installed|add||BTG-109"
  # BTG-109 (cont.): the CORE-OWNED surface registry (PI-033's ownership split).
  # Its ADOPTER-OWNED counterpart, docs/policies/surface-registry.md, stays the
  # seed/exclude row above and is never created, merged or retyped -- the two have
  # OPPOSITE ownership and conflating them would destroy adopter-authored rows.
  "docs/policies/cadence-surfaces.md|installed|add||BTG-109"
  # BTG-112 (PROD_CADENCE-010): the single stage-effort computation site. A COPY_PATHS entry
  # alone reaches only a NEW adopter -- an ALREADY-adopted repo receives a new file
  # solely through a matching row here, and every one of the seven shipped
  # effort-recording instructions now invokes this script BY PATH. Without this row those
  # instructions reference a tool that never arrives, and every stage completion exits 127.
  # Data-only, per the DEC-006 extensibility property. SAFE ONLY IN COMBINATION with the
  # backfill-base rule, exactly as stated in full on the BTG-100 rows above.
  "ci-templates/scripts/stage-effort.sh|installed|add||BTG-112"
  # BTG-315 (PROD_CADENCE-010): the single worklog-split computation site, this
  # ticket's own structural sibling of the stage-effort.sh row directly above
  # and subject to the exact same reasoning -- a COPY_PATHS entry alone
  # reaches only a NEW adopter, and both tracker adapters' worklog steps
  # invoke this script BY PATH once an operator turns split mode on. Without
  # this row an already-adopted repo that fills a §9 agent-time-user cell
  # halts at every worklog projection for that prefix.
  "ci-templates/scripts/worklog-split.sh|installed|add||BTG-315"
  # BTG-179 (PROD_CADENCE-010): the COPY_PATHS entry above reaches a NEW adopter; without
  # this row it never reaches an ALREADY-ADOPTED one, because a pre-feature
  # committed footprint cannot name a file that did not exist when it was written.
  "ci-templates/scripts/org-binding-resolve.sh|installed|add||BTG-179"
  "ci-templates/scripts/org-binding-parse.sh|installed|add||BTG-179"
  "ci-templates/scripts/org-binding-modes.sh|installed|add||BTG-179"
  # BTG-247 DEC-012/OQ-B: the fourth, cross-section module -- same PROD_CADENCE-010
  # reasoning as the three rows above; installed one row later, same ticket.
  "ci-templates/scripts/org-binding-crossref.sh|installed|add||BTG-247"
  # RECONCILE-extensibility-proof (AC-5, DEC-004): a fourth ADD or a hypothetical EXCLUDE is
  # ONE data line here -- no code block. The standing tests S-5.1 (add) and S-5.2 (exclude)
  # insert a live row at this anchor in a throwaway copy and prove it flows through data-only.
  # BTG-198's rows below are the live proof: the context-wiring ownership flip as TWO data rows,
  # no code. CLAUDE.md becomes adopter-owned (a pre-split descriptor typing it kind=installed is
  # retyped in-loop, never merged); the sidecar is the new merged row and reaches an ALREADY-
  # adopted repo only through this add row (PROD_CADENCE-010, backfill-base rule as above). Its field-4
  # `no-restore` (review cycle 1 blocking #1) keeps --repair Concern 1 off an adopter-owned file
  # with no engine-pollution class to undo; the reasoning is at that concern, S-9.4/S-9.5 assert it.
  "CLAUDE.md|seed|exclude|no-restore|BTG-198"
  "CADENCE_DIRECTIVES.md|installed|add||BTG-198"
  "docs/policies/test-scope.md|installed|add||BTG-203"
  # BTG-303 (PROD_CADENCE-010): the COPY_PATHS entries above reach a NEW adopter; without
  # these rows they never reach an ALREADY-ADOPTED one. The version-scheme narrative pair,
  # mirroring the branch-strategy RECONCILE rows above.
  "docs/policies/version-scheme/semver.md|installed|add||BTG-303"
  "docs/policies/version-scheme/calver-yyyy-ww.md|installed|add||BTG-303"
  # BTG-303 (cycle-4 blocking finding #1): the migration guide's own COPY_PATHS entry
  # reaches only a NEW adopter; without this row it never reaches an ALREADY-ADOPTED
  # one, the same PROD_CADENCE-010 class as the two rows above. Required so DEC-023's
  # foregone-window ground's first limb (disclosure in the adopter's own installed
  # copy) is true of every adopter, not only a fresh /cadence-adopt.
  "docs/migrations/version-scheme-binding.md|installed|add||BTG-303"
  # BTG-332 (PROD_CADENCE-010): chord-reference.md's COPY_PATHS entry reaches only a
  # NEW adopter; without this row an ALREADY-ADOPTED repo whose committed footprint
  # still names prism-reference.md never receives the replacement (S-4.2). Paired
  # with upgrade-removals.sh's REMOVAL_MANIFEST entry for the old path in the same
  # change.
  "docs/agentic-sdlc/chord-reference.md|installed|add||BTG-332"
  # BTG-343 (PROD_CADENCE-010): finding-classes.md's COPY_PATHS entry reaches only a
  # NEW adopter; without this row an ALREADY-ADOPTED repo never receives the new
  # non-blocking finding class policy its upgraded roles/commands now point at.
  "docs/policies/finding-classes.md|installed|add||BTG-343"
  # BTG-341 (PROD_CADENCE-010): comment-discipline.md's COPY_PATHS entry reaches only a
  # NEW adopter; without this row an ALREADY-ADOPTED repo never receives the policy its
  # upgraded roles now point at.
  "docs/policies/comment-discipline.md|installed|add||BTG-341"
)

# Seed classification (_is_seed_path, SEED_FILES) and merge-scope state
# (IN_SCOPE, DIR_EXPANDED, RECONCILE_BACKFILLED) moved to the colocated
# upgrade-collect-state.sh (BTG-247 DEC-029, audited safe by DEC-017).
# Self-locating source: never $SELF_DIR, which is unset on the standalone-
# sourcing paths this file is also exercised on.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upgrade-collect-state.sh"
collect_in_scope() {
  local ours_commit="$1"
  IN_SCOPE=()
  DIR_EXPANDED=()
  RECONCILE_BACKFILLED=()
  local line kind p roots=() installed=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      "kind=tree_root "*)
        local hook root
        hook="$(printf '%s\n' "$line" | sed -nE 's/.*binding_hook=([^ ]+).*/\1/p')"
        root="$(resolve_root "$hook")" || return 1
        [[ -n "$root" ]] && roots+=("$root")
        ;;
      "kind=seed "*)
        # BTG-015 (AC-1/AC-3/AC-5): a data-driven seed row is EXCLUDED from the
        # merge set -- never added to installed[], so never merged nor created.
        # One plain skip log line per excluded seed (DEC-007, not a seam).
        p="$(printf '%s\n' "$line" | sed -nE 's/.*[[:space:]]path=([^ ]+).*/\1/p')"
        [[ -n "$p" ]] && echo "upgrade-cadence: skipping seed $p (adopter-owned, excluded from merge)" >&2
        ;;
      "kind=installed "*)
        p="$(printf '%s\n' "$line" | sed -nE 's/.*[[:space:]]path=([^ ]+).*/\1/p')"
        # >>> BTG-015 seed-exclude-anchor-start: IN-LOOP EXCLUDE DISPATCH (RECONCILE) >>>
        # The unification's EXCLUDE half (DEC-006). A pre-BTG-015 descriptor still
        # types a seed kind=installed; the RECONCILE exclude/seed rows (via the
        # table-derived _is_seed_path) exclude it here IN-LOOP -- at exactly the
        # position and bytes as before -- never mutating the committed footprint
        # (ADR_CADENCE-0009), reaching the existing fleet. One plain skip log line fires at
        # this point (before the append, before the post-loop add dispatch). The
        # OS-1.1 guard strips exactly this region from a throwaway copy to prove a
        # seed then leaks into IN_SCOPE and seed_in_merge_set catches it.
        if _is_seed_path "$p"; then
          echo "upgrade-cadence: skipping seed $p (adopter-owned, excluded from merge)" >&2
          continue
        fi
        # <<< BTG-015 seed-exclude-anchor-end: IN-LOOP EXCLUDE DISPATCH <<<
        # overlay + the stamp are eject-only strip rows, not merge inputs: the
        # overlay is the adopter's own source (DEC-008 edge) and the stamp is
        # managed by this engine. Skip them as merge files.
        [[ "$p" == "overlay" || "$p" == ".cadence-version" ]] && continue
        [[ -n "$p" ]] && installed+=("$p")
        ;;
    esac
  done < "$FOOTPRINT"

  # >>> BTG-020 reconcile-anchor-start: POST-LOOP ADD DISPATCH (RECONCILE) >>>
  # The unification's ADD half (DEC-006), consumed at the current BTG-008/BTG-019
  # position (post-descriptor-loop). Each add row is gated by core@new ownership
  # (git cat-file -e "$ours_commit:<path>") -- the engine never invents a path
  # core does not own -- then dispatched by kind: tree_root -> resolve_root ->
  # roots[]; installed -> verbatim -> installed[]. Deduped per entry (below), so a
  # post-fix footprint already listing the row adds it once. Never mutates the
  # committed footprint (ADR_CADENCE-0009). Stripping this whole region simulates a
  # pre-3.8.7 engine with neither the hooks nor the TMS backfill (DEC-007 guard).
  local _row _path _kind _dir _resolver _origin _tgt _val
  local _guard_targets=()
  for _row in "${RECONCILE[@]}"; do
    IFS='|' read -r _path _kind _dir _resolver _origin <<<"$_row"
    [[ "$_dir" == add ]] || continue                 # exclude rows are handled in-loop
    git -C "$CORE" cat-file -e "$ours_commit:$_path" 2>/dev/null || continue
    if [[ "$_kind" == tree_root ]]; then
      _tgt=roots
      _val="$(resolve_root "$_resolver")" || return 1
      [[ -z "$_val" ]] && continue
    else
      _tgt=installed
      _val="$_path"
    fi
    # >>> BTG-020 dedup-anchor-start: per-entry dedup for add rows (AC-6) >>>
    # Skip the append if this add target is already accumulated in its array. This
    # is the per-entry guard the pre-fold dedup scan below asserts is ACTIVE: strip
    # THIS region (marker-anchored) to bypass the dedup and the append runs
    # unconditionally, doubling the entry -- exactly the regression S-2.5 patches to
    # prove the duplicate_backfill_entry guard (not the downstream SEENMAP) is the
    # discriminating observable. SEENMAP would still fold IN_SCOPE to one path.
    local _acc _dup=0
    if [[ "$_tgt" == roots ]]; then
      for _acc in "${roots[@]}"; do [[ "$_acc" == "$_val" ]] && _dup=1; done
    else
      for _acc in "${installed[@]}"; do [[ "$_acc" == "$_val" ]] && _dup=1; done
    fi
    [[ $_dup -eq 1 ]] && continue
    # <<< BTG-020 dedup-anchor-end <<<
    # >>> BTG-100 backfill-mark-anchor-start: RECONCILE_BACKFILLED mark >>>
    # Reached ONLY when the per-entry dedup above did NOT fire -- i.e. the adopter's
    # own committed descriptor never carried this path. Record that one bit so
    # merge_one_file can choose an empty base instead of misreading the absent file
    # as an adopter deletion (DEC-002). Set for kind=installed rows ONLY: a
    # tree_root row's _val is a RESOLVED ROOT, not a file rel-path, and marking it
    # would force an empty base on every file beneath it (SM-2 guards that).
    # SM-2 REINTERPRETED (recorded, not silent -- archive/BTG-100/decisions.md
    # DEC-018 #6). spec.md specifies SM-2's condition as "a mark WOULD be set for a
    # row whose kind is not installed". Once the `installed` guard above exists
    # that condition is UNFIREABLE -- the guard is what makes it impossible, so a
    # seam on it could never emit and would be decorative. The implemented
    # condition is the nearest one that CAN fire and still means the same thing: a
    # non-installed row whose resolved value is ALREADY marked, i.e. a tree_root
    # resolving onto a path some installed row also marked. Still "must never
    # fire", still emit-only (mirroring duplicate_backfill_entry, DEC-006).
    if [[ "$_tgt" == installed ]]; then
      RECONCILE_BACKFILLED["$_val"]=1
    elif [[ -n "${RECONCILE_BACKFILLED[$_val]:-}" ]]; then
      emit_seam UNSOUND_CONDITION upgrade.scope.backfill_mark_for_non_installed_row "$_val"
    fi
    # <<< BTG-100 backfill-mark-anchor-end <<<
    if [[ "$_tgt" == roots ]]; then roots+=("$_val"); else installed+=("$_val"); fi
    _guard_targets+=("$_tgt|$_val")
  done

  # Pre-fold dedup guard (AC-6 discriminator): each RECONCILE add-row target must
  # appear at most once in its array BEFORE the SEENMAP fold. A duplicate is only
  # reachable if the per-entry dedup above was bypassed; SEENMAP folds final PATHS
  # and would hide it in IN_SCOPE, so this pre-fold scan is the sole discriminating
  # observable. Emit-only (non-aborting) UNSOUND_CONDITION, per DEC-006.
  local _gt _ga _gv _gc _gx
  for _gt in "${_guard_targets[@]:-}"; do
    [[ -z "$_gt" ]] && continue
    _ga="${_gt%%|*}"; _gv="${_gt#*|}"; _gc=0
    if [[ "$_ga" == roots ]]; then
      for _gx in "${roots[@]}"; do [[ "$_gx" == "$_gv" ]] && _gc=$((_gc + 1)); done
    else
      for _gx in "${installed[@]}"; do [[ "$_gx" == "$_gv" ]] && _gc=$((_gc + 1)); done
    fi
    [[ $_gc -gt 1 ]] && emit_seam UNSOUND_CONDITION upgrade.scope.duplicate_backfill_entry "$_gv"
  done
  # <<< BTG-020 reconcile-anchor-end <<<

  # Files under each tree root, from theirs (adopter) and ours (core@new).
  local r f rel seen
  declare -A SEENMAP=()
  for r in "${roots[@]}"; do
    if [[ -d "$TARGET/$r" ]]; then
      while IFS= read -r f; do
        rel="${f#"$TARGET"/}"; SEENMAP["$rel"]=1
      done < <(find "$TARGET/$r" -type f 2>/dev/null)
    fi
    while IFS= read -r rel; do
      [[ -n "$rel" ]] && SEENMAP["$rel"]=1
    done < <(git -C "$CORE" ls-tree -r --name-only "$ours_commit" -- "$r" 2>/dev/null)
  done
  local ip
  for ip in "${installed[@]}"; do
    # An installed path MAY be a directory: the footprint grammar allows it and
    # eject matches installed paths as prefixes (strip_reason_for). Merging a
    # directory as a single file mis-handles it -- `git show <c>:<dir>` yields a
    # tree-listing dump (not content) and `-f <dir>` is false, so theirs looks
    # empty and each version's tree-dump header differs -> a spurious conflict
    # that blocks the whole atomic apply. So expand a directory-valued installed
    # path into its member files -- the union of the adopter tree and core@new --
    # exactly as the tree roots are expanded above. A file-valued installed path
    # falls through to the direct 1:1 behavior below.
    #
    # >>> BTG-007 S-1.4-anchor-start: DIR-EXPAND-BRANCH (DEC-002 fix / DEC-008 guard) >>>
    # The region between these two anchor comments is the shipped Defect-1
    # directory-expansion branch (BTG-007), now delegated to upstream's
    # expand_dir_row (PI-031, defined in upgrade-bootstrap.sh): it detects a
    # directory-valued installed path (in the adopter tree OR core@new), expands it
    # into its member files -- the union of `find` under the adopter tree and
    # `git ls-tree -r` at core@new -- records DIR_EXPANDED provenance so the merge
    # loop can fire the directory_as_file_path anomaly seam, and returns 0 so we
    # `continue` past the file-valued 1:1 branch. It returns 1 for a regular file,
    # falling through. Equivalent scope to the former inline branch (same find +
    # ls-tree union), plus provenance + the seam. The S-1.4 standing guard strips
    # exactly this region from a throwaway engine COPY (a marker-anchored sed
    # delete, never line numbers) and proves the strip turns S-1.1 red -- i.e. that
    # this branch is the discriminating cause of S-1.1 passing. The delete leaves
    # valid bash that processes a directory as a single file (the pre-fix defect).
    expand_dir_row "$ip" "$ours_commit" && continue
    # <<< BTG-007 S-1.4-anchor-end: DIR-EXPAND-BRANCH <<<
    # File-valued installed path -- the direct 1:1 behavior.
    [[ -e "$TARGET/$ip" ]] && SEENMAP["$ip"]=1
    git -C "$CORE" cat-file -e "$ours_commit:$ip" 2>/dev/null && SEENMAP["$ip"]=1
  done
  # Deterministic order.
  while IFS= read -r rel; do
    IN_SCOPE+=("$rel")
  done < <(printf '%s\n' "${!SEENMAP[@]}" | LC_ALL=C sort)

  # BTG-015 regression guard (PI-002 pre-merge-loop lesson): a seed reaching the
  # merge set is an UNSOUND_CONDITION -- assert BEFORE the merge loop and abort
  # loud so a regression that lets a seed into IN_SCOPE can never mutate it.
  local sp
  for sp in "${IN_SCOPE[@]}"; do
    if _is_seed_path "$sp"; then
      emit_seam UNSOUND_CONDITION upgrade.scope.seed_in_merge_set "$sp"
      echo "upgrade-cadence: a seed reached the merge set: $sp -- aborting (no seed is ever merged)." >&2
      return 1
    fi
  done
}

# Resolve a tree_root binding hook to its native root through the adapter (the
# same RC-6 resolution eject uses) -- no native-root literal in this engine.
resolve_root() {
  # >>> binding-resolution (clause-7 exempt) >>>
  local hook="$1" adapter="$SELF_DIR/../../../ci-templates/scripts/adapters/claude-code.sh"
  # In an adopter repo the adapter is installed under ci-templates/scripts.
  [[ -f "$adapter" ]] || adapter="$TARGET/ci-templates/scripts/adapters/claude-code.sh"
  [[ -f "$adapter" ]] || adapter="$CORE/ci-templates/scripts/adapters/claude-code.sh"
  # <<< binding-resolution (clause-7 exempt) <<<
  if [[ ! -f "$adapter" ]]; then
    emit_seam UNSOUND_CONDITION upgrade.binding.adapter_missing "$adapter"
    echo "upgrade-cadence: cannot resolve tree roots -- runtime adapter not found." >&2
    return 1
  fi
  # shellcheck source=/dev/null
  ( . "$adapter"; printf '{{%s}}' "$hook" | cc_expand_body )
}
