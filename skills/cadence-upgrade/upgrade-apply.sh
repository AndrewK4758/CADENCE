#!/usr/bin/env bash
# upgrade-apply.sh -- the "apply" half of upgrade's compute/apply seam.
#
# Bounded context: Upgrade seam / layered-source flow -- the /cadence-upgrade
# merge engine (PI-022).
#
# THE SEAM. upgrade-cadence.sh computes the ENTIRE 3-way merge and gates on
# conflicts, writing nothing to the adopter tree; this module performs the
# atomic write transaction, reached ONLY on the fully-clean path. That boundary
# is the engine's own stated contract -- "Compute the full 3-way merge FIRST
# (atomic: nothing applied until all clean)" -- promoted from a comment to a
# file boundary (BTG-132 DEC-005).
#
# Invariants relied on from outside this boundary:
#   - SOURCED, never executed. run_apply_transaction takes NO arguments and
#     reads staging / base_ver / base_commit / changed / IN_SCOPE / DIR_EXPANDED
#     / RELOC_MANIFEST / MCP_MANIFEST from main()'s scope at call time, and
#     TARGET / CORE / NEW_VERSION / emit_seam from the script's. This is the
#     same dynamic-scope contract every sibling upgrade-*.sh module already
#     relies on (upgrade-hooks.sh, upgrade-orgfold.sh, upgrade-baseline.sh).
#   - ORDERING INSIDE IS BEHAVIOR and is preserved exactly: the stamp advances
#     LAST, after the hook and MCP reconciliations; the org-fold runs after the
#     stale-staging cleanup. Re-ordering these would be a behavior change
#     disguised as a refactor.
#   - THE CALLER MUST PROPAGATE. Several steps return non-zero to REFUSE (e.g.
#     a non-canonical settings.json refusing the hook sync). The single call
#     site is `run_apply_transaction || return $?`; swallowing that status would
#     turn a refusal into a success AND advance the stamp -- the one thing the
#     atomic contract forbids.
#
# The ten ordered steps: write every in-scope file (loud abort on a partial
# write) -> BTG-008 hook registration sync + pristine legacy relocation ->
# BTG-057 MCP registration re-sync -> BTG-047 pristine removed-upstream deletion
# -> BTG-010 specs/drafts/ create-if-absent (non-fatal) -> BTG-100 dead-citation
# baseline create-once (non-fatal) -> advance .cadence-version (the LAST write)
# -> stale-staging cleanup -> BTG-048 org-fold (stamp-independent, post-apply)
# -> the summary line.
#
# Spec: archive/BTG-132/spec.md (Scope 2b); decisions.md DEC-005, following
# archive/BTG-078/decisions.md DEC-019.

run_apply_transaction() {

  # All clean -> apply atomically (write every in-scope file), THEN advance the
  # stamp as the LAST write (DEC-003 / AC-4). Aborts LOUD on a partial write (II-014).
  assert_not_dry_run apply || { rm -rf "$staging"; return 1; }   # defensive (unreachable under dry-run)
  for rel in "${IN_SCOPE[@]}"; do
    if ! mkdir -p "$TARGET/$(dirname "$rel")" 2>/dev/null \
       || ! cp "$staging/apply.$(echo "$rel" | tr '/' '_')" "$TARGET/$rel" 2>/dev/null; then
      # BTG-333 AC-5: unified on DELTA_AUDIT_GAP at every partial_or_dirty site
      # (was UNSOUND_CONDITION here; requester decision DEC-004).
      emit_seam DELTA_AUDIT_GAP upgrade.apply.partial_or_dirty "$rel"
      # G-4 anomaly seam (DEC-004): a directory-row constituent that did NOT apply
      # cleanly also surfaces directory_as_file_path naming the source directory.
      [[ -n "${DIR_EXPANDED[$rel]:-}" ]] \
        && emit_seam LOGIC_FAULT upgrade.merge.directory_as_file_path "${DIR_EXPANDED[$rel]}"
      echo "upgrade-cadence: apply failed writing $rel -- aborting; the stamp stays at $base_ver." >&2
      echo "upgrade-cadence: the tree may be partially written; re-run after fixing the write error." >&2
      rm -rf "$staging"; rm -f "$RELOC_MANIFEST" "$MCP_MANIFEST"
      return 1
    fi
  done

  # BTG-332 (D4): write every vocab-classified spec rewrite AFTER the in-scope
  # write loop and BEFORE the hook sync. A stale-input or write failure aborts
  # here exactly like the loop above (stamp stays at $base_ver; nothing further
  # applies). The per-file report line is written from the SAME array that
  # drove the writes (Data Integrity: audit coverage), never a second pass.
  # code-review cycle 2 N5: the IN_SCOPE loop just above already wrote every
  # framework file to $TARGET -- vocab_apply's own abort message must never
  # claim "nothing written" on top of that; it reads this count via
  # vocab_apply_abort_note (upgrade-vocab.sh).
  VOCAB_FRAMEWORK_WRITTEN_COUNT="${#IN_SCOPE[@]}"
  if ! vocab_apply; then
    rm -f "$RELOC_MANIFEST" "$MCP_MANIFEST"; rm -rf "$staging"
    echo "upgrade-cadence: vocab apply failed -- aborting; the stamp stays at $base_ver." >&2
    return 1
  fi
  vocab_report_plan

  # BTG-008 AC-8/AC-5 (NB-1 ordering): reconcile the hook registration + relocate
  # pristine legacy hooks BEFORE advancing the stamp (gated strictly to the
  # clean-apply path -- R-5; never on a conflicted/partial apply, which returned
  # above). The sync validates FIRST and the legacy files are removed only after
  # it succeeds, so a refusal (non-canonical settings.json) leaves the stamp
  # UNADVANCED and the legacy files intact -- all-or-nothing. Idempotent.
  if [[ $HAVE_HOOKS -eq 1 ]]; then
    if ! hooks_relocate_and_sync "$RELOC_MANIFEST"; then
      rm -f "$RELOC_MANIFEST" "$MCP_MANIFEST"; rm -rf "$staging"
      echo "upgrade-cadence: hook reconciliation failed -- stamp stays at $base_ver; legacy hooks untouched. Fix settings.json and re-run." >&2
      return 1
    fi
  fi
  rm -f "$RELOC_MANIFEST"

  # BTG-057 AC-4 (R-5-gated, same clean-apply path as the hook sync): idempotently
  # re-sync the CADENCE MCP registration in .mcp.json to core@new's manifest shape,
  # BEFORE advancing the stamp. A sync refusal (non-canonical .mcp.json) leaves the
  # stamp UNADVANCED -- all-or-nothing. When core@new predates MCP registration
  # (HAVE_MCP=0) the sync is SILENTLY skipped (mirrors the hooks HAVE_HOOKS=0 path):
  # the PI-003 bootstrapping gap is a documented self-healing limitation, NOT a
  # runtime seam -- the *predating* engine physically cannot emit one, and firing a
  # seam here would false-positive on every legitimately pre-MCP upgrade (OS-8).
  # See decisions.md DEC-012 (spec OS-4.4 deviation, test-driven).
  if [[ $HAVE_MCP -eq 1 ]]; then
    if ! mcp_relocate_and_sync "$MCP_MANIFEST"; then
      rm -f "$MCP_MANIFEST"; rm -rf "$staging"
      echo "upgrade-cadence: MCP reconciliation failed -- stamp stays at $base_ver; .mcp.json untouched. Fix .mcp.json and re-run." >&2
      return 1
    fi
  fi
  rm -f "$MCP_MANIFEST"

  # BTG-047 (AC-13 / DEC-006): clean-apply path reached -> every conflict resolved,
  # so any MODIFIED removed-upstream file was surfaced above and never reaches here.
  # Delete the pristine (byte-identical-to-base) removed-upstream files now. Gated
  # strictly to the clean-apply path (mirrors the hook-relocation ordering); clobber-
  # safe by construction. A failed unlink is non-fatal (self-heals next run).
  for rmrel in "${REMOVALS_DELETE[@]:-}"; do
    [[ -n "$rmrel" ]] || continue
    if rm -f "$TARGET/$rmrel" 2>/dev/null; then
      emit_seam LOGIC_FAULT upgrade.removal.removed "$rmrel"
      echo "upgrade-cadence: removed obsolete removed-upstream file: $rmrel (byte-identical to the stamp-base version)." >&2
    fi
  done

  # BTG-010: ensure the gitignored local drafting area exists (create-if-absent,
  # clean-apply path only; separate from the merge loop -- it is NOT in the
  # footprint). An existing .gitignore may hold user patterns and is NEVER
  # overwritten; idempotent -- a no-op when already present. A create failure is
  # NON-fatal (convenience workspace, not a footprint file, so it does not
  # invalidate the applied upgrade) but is warned LOUD -- never a silent success
  # (this main() runs under `set -u` only) -- and self-heals on the next run.
  if [[ ! -e "$TARGET/specs/drafts/.gitignore" ]]; then
    if ! { mkdir -p "$TARGET/specs/drafts" \
           && printf '*\n!.gitignore\n' > "$TARGET/specs/drafts/.gitignore"; }; then
      echo "upgrade-cadence: warning -- could not create specs/drafts/.gitignore (non-fatal; recreated on next adopt/upgrade)." >&2
    fi
  fi

  # BTG-100 (AC-3 / DEC-004): create-once generation of the adopter's OWN
  # dead-citation debt ledger (upgrade-baseline.sh), gated to this clean-apply path
  # like the reconciliations above. Non-fatal by design -- never returns non-zero.
  ensure_dead_citation_baseline

  # All in-scope files applied AND hooks reconciled -> advance the stamp as the
  # LAST write (DEC-003 / AC-4: stamp iff fully clean, now incl. hook registration).
  assert_not_dry_run stamp || { rm -rf "$staging"; return 1; }   # defensive guard symmetry (unreachable under dry-run)
  printf 'schema=1\nversion=%s\ncommit=%s\n' "$NEW_VERSION" "$ours_commit" > "$STAMP"  # overwrites any transient bootstrap base stamp (G-2)

  # A prior conflicted run may have left a staging tree; a fully-clean apply
  # resolved everything, so remove the now-stale staging artefact (Defect 2 /
  # AC-2 / DEC-003). Gated strictly AFTER the stamp write.
  rm -rf "$TARGET/.cadence-upgrade-staging"

  # BTG-048: the template-to-live org-fold. A dependent, best-effort, stamp-
  # INDEPENDENT post-apply stage (DEC-002): it reconciles the just-applied
  # CADENCE_ORG_TEMPLATE.md inter-version changes into the adopter's live
  # CADENCE_ORG.md. Runs AFTER the stamp advance + the stale-staging cleanup
  # above (so a fold conflict repopulates a clean staging tree) and never rolls
  # the stamp back on a fold conflict (DEC-002). Dispatched only here, on the
  # fully-clean apply path -- a template-merge conflict returned long before.
  run_orgfold "$base_commit"

  echo "upgrade-cadence: applied ${#changed[@]} file(s); stamp advanced to $NEW_VERSION."
  rm -rf "$staging"
  return 0
}
