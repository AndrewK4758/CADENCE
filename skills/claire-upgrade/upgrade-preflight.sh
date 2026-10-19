#!/usr/bin/env bash
# upgrade-preflight.sh -- the "pre-flight" half of upgrade's preflight/compute seam.
#
# Bounded context: Upgrade seam / layered-source flow -- the /claire-upgrade
# merge engine (PI-022).
#
# THE SEAM. run_preflight establishes that this upgrade may proceed at all, and
# resolves the two commits the merge will run between. It WRITES NOTHING: every
# outcome is either a refusal (non-zero) or a pair of resolved commits. The
# compute phase that follows it in main() reads those commits; the apply
# transaction in upgrade-apply.sh is what finally writes.
#
# The five preconditions, in order (the order is behavior -- the no-stamp
# bootstrap must precede the boundary check, because a never-adopted repo has no
# descriptor by construction):
#   1. no-stamp bootstrap / never-adopted refusal (AC-8, DEC-009)
#   2. compiled-only detect-and-warn (PI-033/G-9 -- warns, never refuses)
#   3. the footprint descriptor precondition, i.e. the boundary (AC-9/ADR_CLAIRE-0009)
#   4. the two epoch bootstrapping-gap warnings and the forward-only check
#   5. ours = core@<new-version> and base = core@<stamped-commit> resolution
#
# Invariants relied on from outside this boundary:
#   - SOURCED, never executed. run_preflight takes no arguments and reads
#     STAMP / FOOTPRINT / CORE / TARGET / NEW_VERSION / CONFIRM_BASE /
#     BASE_EMPTY / emit_seam from scope at call time, the same dynamic-scope
#     contract every sibling upgrade-*.sh module relies on.
#   - IT ASSIGNS THREE OF main()'s LOCALS: base_ver, base_commit and
#     ours_commit. main() DECLARES them (`local base_ver base_commit
#     ours_commit`) before calling, so the assignments land in main()'s scope
#     and survive this function's return. Re-adding a `local` for any of them
#     here would silently empty the merge base -- the merge would then run
#     against no ancestor rather than fail.
#   - THE CALLER MUST PROPAGATE, AND MUST DISTINGUISH THREE OUTCOMES. Every
#     refusal returns non-zero. But one path -- "already at <version>, nothing
#     to do" -- was a `return 0` from main() BEFORE this extraction, meaning
#     "stop, successfully". A bare `run_preflight || return $?` would fall
#     THROUGH that zero into the compute phase and re-merge an already-current
#     repository. It therefore returns the sentinel PREFLIGHT_UP_TO_DATE (20),
#     which the call site maps back to `return 0`. This mirrors the file's own
#     existing idiom three lines into this function, where
#     bootstrap_if_no_stamp's 10 means "handled, stop" and is mapped by the
#     caller -- a DIFFERENT sentinel is used here precisely because the mapping
#     is different (10 -> refusal, 20 -> success).
#
# WHY THIS FILE EXISTS. It is the conditional second seam pre-authorised by
# archive/BTG-132/decisions.md DEC-005, fired by measurement: after the
# compute/apply extraction the entry point stood at 363 lines -- 37 of headroom
# against the PI-037 400-line ceiling, under the 40-line target DEC-005 sets.
# The trigger is a number, so the decision was arithmetic rather than taste.
#
# Spec: archive/BTG-132/spec.md (Scope 2b, "Conditional second seam"); decisions.md
# DEC-005 and DEC-016.

# "Handled, stop, successfully" -- see the caller contract above. Distinct from
# bootstrap_if_no_stamp's 10, which the caller maps to a refusal.
PREFLIGHT_UP_TO_DATE=20

run_preflight() {
  # No-stamp bootstrap (AC-8): refuse a never-adopted repo BEFORE the boundary
  # check (it has no descriptor by construction); a pre-PI-021 adopter is
  # bootstrapped (DEC-009). A 10 return means "handled, stop" (refusal).
  bootstrap_if_no_stamp; local boot_rc=$?
  if [[ $boot_rc -eq 10 ]]; then return 1; fi
  if [[ $boot_rc -ne 0 ]]; then return "$boot_rc"; fi
  warn_if_compiled_only  # PI-033/G-9: read-only detect-and-warn; never refuses (DEC-007)
  # Precondition: a valid footprint descriptor (the boundary). Fail loud, never
  # fail-open scope-everything (DEC-008 / AC-9 / ADR_CLAIRE-0009).
  if [[ ! -f "$FOOTPRINT" ]]; then
    # G-2 (DEC-003): a pending bootstrap stamp must NOT have been written before
    # this gate. If one ever exists on a no-stamp path, that is the impossible
    # stamp-before-footprint state the fix prevents -- emit the defensive seam.
    [[ "$BOOT_PENDING_STAMP" -eq 1 && -f "$STAMP" ]] \
      && emit_seam LOGIC_FAULT upgrade.bootstrap.stamp_before_footprint "$STAMP"
    emit_seam LINEAGE_GAP upgrade.boundary.descriptor_missing "$FOOTPRINT"
    echo "upgrade-claire: footprint descriptor not found: $FOOTPRINT" >&2
    echo "upgrade-claire: refusing -- there is NO fail-open scope-everything fallback (ADR_CLAIRE-0009)." >&2
    return 1
  fi

  # G-2 (DEC-003): the footprint precondition holds -> safe to persist the bootstrap stamp,
  # which is INTENTIONALLY TRANSIENT (overwritten at the new version after apply; a crash
  # between leaves a VALID base stamp -- the intended bootstrap outcome, atomic model).
  if [[ "$BOOT_PENDING_STAMP" -eq 1 ]]; then
    # AC-3 (PI-032): under --dry-run, suppress this bootstrap stamp write -- a
    # dry-run writes NOTHING, including the transient base stamp (DEC-004 / S-3.4).
    # The in-memory BOOT_BASE_COMMIT (below) drives the preview instead.
    if [[ "$DRY_RUN" -eq 0 ]]; then
      printf 'schema=1\nversion=%s\ncommit=%s\n' "$BOOT_PENDING_VERSION" "$BOOT_BASE_COMMIT" > "$STAMP"
      echo "upgrade-claire: bootstrapped a base stamp at $BOOT_PENDING_VERSION; proceeding with the 3-way merge." >&2
    else
      echo "upgrade-claire: [dry-run] would bootstrap a base stamp at $BOOT_PENDING_VERSION (not written)." >&2
    fi
  fi

  # base_ver/base_commit are declared by main() (see upgrade-preflight.sh scoping note)
  base_ver="$(stamp_field version "$STAMP")"
  base_commit="$(stamp_field commit "$STAMP")"
  # Dry-run bootstrap (PI-032): no stamp file (write suppressed) -> use the in-memory bootstrapped base for the preview.
  [[ -z "$base_commit" && -n "$BOOT_BASE_COMMIT" ]] && { base_commit="$BOOT_BASE_COMMIT"; base_ver="$CONFIRM_BASE"; }

  # BTG-016b AC-4 / PI-003: run-start bootstrapping-gap warning. If the base engine
  # predates the 3.8.8 protection epoch the target crosses, its protections cannot
  # self-apply (F0) -- warn LOUD, never abort; --repair. BTG-018 AC-11/DEC-006: epoch 3.8.7->3.8.8.
  if [[ -n "$base_ver" && "$BASE_EMPTY" -eq 0 \
        && "$(version_cmp "$base_ver" 3.8.8)" == "-1" && "$(version_cmp "$NEW_VERSION" 3.8.8)" != "-1" ]]; then
    emit_seam LOGIC_FAULT upgrade.engine.bootstrapping_gap "$base_ver-to-$NEW_VERSION crosses 3.8.8"
    echo "upgrade-claire: WARNING -- this engine ($base_ver) predates the 3.8.8 protection epoch; seed exclusion (BTG-015), hook relocation (BTG-008), specs/drafts creation (BTG-010), and SYSTEM_OVERVIEW.md exclusion (BTG-018) will NOT apply this run." >&2
    echo "upgrade-claire: run '/claire-upgrade --repair' (after upgrading) to reconcile seeds/hooks/drafts." >&2
  fi
  # BTG-048 (PI-003): the template-to-live org-fold is engine-resident and ships at
  # the 4.0.1 epoch, so an engine predating it cannot self-apply the fold on the very
  # upgrade that CROSSES 4.0.1 -- the fold reaches the fleet only from the SECOND
  # post-release upgrade (the PI-003 bootstrapping-gap class). This is a SEPARATE
  # epoch from 3.8.8 (advancing that single epoch would wrongly suppress the older
  # protections' warning); it reuses the same bootstrapping_gap seam. Warn LOUD,
  # never abort -- the gap self-heals on the next upgrade (or an on-demand fold via
  # '/claire-upgrade --repair-orgfold', BTG-049).
  if [[ -n "$base_ver" && "$BASE_EMPTY" -eq 0 \
        && "$(version_cmp "$base_ver" 4.0.1)" == "-1" && "$(version_cmp "$NEW_VERSION" 4.0.1)" != "-1" ]]; then
    emit_seam LOGIC_FAULT upgrade.engine.bootstrapping_gap "$base_ver-to-$NEW_VERSION crosses 4.0.1 (org-fold)"
    echo "upgrade-claire: WARNING -- this engine ($base_ver) predates the 4.0.1 org-fold epoch; the CLAIRE_ORG_TEMPLATE.md -> live CLAIRE_ORG.md org-fold will NOT run this upgrade (it is engine-resident and not yet installed)." >&2
    echo "upgrade-claire: it self-heals on your NEXT '/claire-upgrade' (or run '/claire-upgrade --repair-orgfold' to fold on demand now)." >&2
  fi

  # Forward-only in v1 (DEC-001/DEC-003): an already-at target is a no-op; an
  # older target is refused (downgrade is out of scope) -- both NAMED, never
  # silently attempted. Skipped in the 2-way fallback (no base version, AC-8).
  if [[ -n "$base_ver" && "$BASE_EMPTY" -eq 0 ]]; then
    local cmp; cmp="$(version_cmp "$NEW_VERSION" "$base_ver")"
    if [[ "$cmp" == "0" ]]; then
      echo "upgrade-claire: already at $NEW_VERSION -- nothing to do."
      return "$PREFLIGHT_UP_TO_DATE"   # caller maps to 0; see the contract above
    fi
    if [[ "$cmp" == "-1" ]]; then
      echo "upgrade-claire: target $NEW_VERSION is OLDER than the stamped $base_ver." >&2
      echo "upgrade-claire: refusing -- v1 is forward-only (downgrade is out of scope)." >&2
      return 1
    fi
  fi

  # Resolve ours = core@<new-version>.
  # ours_commit is declared by main() (see upgrade-preflight.sh scoping note)
  ours_commit="$(core_commit_for_version "$NEW_VERSION")"
  if [[ -z "$ours_commit" ]]; then
    echo "upgrade-claire: cannot resolve core version $NEW_VERSION in the core checkout." >&2
    return 1
  fi

  # Reconstruct base = core@<stamped-commit>. The stamp's commit is the precise
  # base identity (DEC-002). An unreachable base aborts loud (no guessed base).
  # In the 2-way fallback there is NO base -- every file uses an empty ancestor.
  if [[ "$BASE_EMPTY" -eq 0 ]] && ! git -C "$CORE" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    # BTG-333 AC-5: unified on LINEAGE_GAP (was IMPOSSIBLE_STATE; DEC-004).
    emit_seam LINEAGE_GAP upgrade.apply.partial_or_dirty "$base_commit"
    echo "upgrade-claire: the stamped base commit is unreachable in the core checkout: $base_commit" >&2
    echo "upgrade-claire: refusing -- the merge base cannot be reconstructed (a wrong base corrupts the merge)." >&2
    return 1
  fi

  # AC-9 (BTG-311 / DEC-007, DEC-008 OQ-1 choice (a)): a base stamp WRITTEN BY
  # THE PRE-BTG-311 resolver may sit AHEAD of the newly-narrowed target -- that
  # resolver's `--all` scan could land on any ref (including one the tag's own
  # history never reaches), so the stamped base is not guaranteed to be an
  # ancestor of the newly tag-bounded `ours_commit`. WARN, never refuse:
  # refusing would strand exactly the population this fix exists to help.
  # Warn-only, so the shallow-clone fragility of --is-ancestor (the same
  # fragility that disqualified this predicate as a HARD gate -- see
  # upgrade-resolve.sh's H1) is acceptable here: a false positive is a
  # spurious notice, never a refusal.
  if [[ "$BASE_EMPTY" -eq 0 ]] \
     && ! git -C "$CORE" merge-base --is-ancestor "$base_commit" "$ours_commit" 2>/dev/null; then
    emit_seam DRIFT_SIGNAL upgrade.base.stamp_ahead_of_target "$base_commit"
    echo "upgrade-claire: WARNING -- the stamped base ($base_commit) is not an ancestor of the resolved target ($ours_commit)." >&2
    echo "upgrade-claire: conflicts in this run may be an artifact of a base stamp written before BTG-311's tag-bounded fix." >&2
  fi
}
