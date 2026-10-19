#!/usr/bin/env bash
#
# upgrade-modes.sh -- the /claire-upgrade PI-032 mode helpers module, extracted
# from upgrade-bootstrap.sh (PI-036) so every co-located sidecar module stays under
# the DX <300-line target. BEHAVIOR-PRESERVING extraction: the functions move
# verbatim, no logic change.
#
# Bounded context: Upgrade seam / operator-UX flow (PI-032, G-1/G-3/G-6/G-7).
# Sourced by upgrade-claire.sh (after upgrade-bootstrap.sh) via
# `. "$SELF_DIR/upgrade-modes.sh"`, so it runs in the entry point's shell scope:
# the globals these functions read (CORE/TARGET/FOOTPRINT/DRY_RUN/AUTOGEN_CONFIRM)
# and the emit_seam helper resolve at CALL time from that scope (dynamic scoping).
# One of the colocated sidecar modules the PI-023 directory-copy contract ships
# into the compiled skill.
#
# Holds the two PI-032 engine-mode concerns:
#   - Step-0 footprint auto-generate (--autogen-footprint): derive_adopter_footprint,
#     run_autogen_mode (AC-2 / DEC-001/003/006/009).
#   - Dry-run preview (--dry-run): dry_run_report, assert_not_dry_run, dry_run_finish
#     (AC-3 / DEC-004/005).
#
# Spec: specs/PI-032/spec.md ; decisions.md DEC-001/003/004/005/006/009 ; PI-036 (extraction).

# Step-0 auto-generate (PI-032 / AC-2 / G-3): produce the absent adopter footprint
# by DELEGATING to the single eject deriver -- never a second boundary mechanism
# (DEC-001 / Simplicity). claire-eject.sh --derive-adopter-footprint reads only
# the CORE checkout and prints the descriptor to stdout (DEC-001); this helper
# captures that stdout to a temp file and atomically moves it into place (the temp-
# then-move below is the only write to the destination).
#
# Upstream: dispatched by run_autogen_mode() (below), which is the engine's
#   `upgrade-claire.sh --autogen-footprint` Step-0 entry point -- the single
#   documented production command (DEC-009). The skill body's "Step 0" runs that
#   command after the AC-1 pre-check surfaces the absent footprint and the OPERATOR
#   confirms (AUTOGEN_CONFIRM=1). Downstream: writes $TARGET/artifacts/footprint.generated
#   (the merge boundary consumed by upgrade-claire.sh's collect_in_scope).
# Spec: specs/PI-032/spec.md (AC-2 Side-effects); decisions.md DEC-001/003/006/009.
#
# Confirmation gate (DEC-003): does nothing without AUTOGEN_CONFIRM=1 -- never a
# silent overwrite of the boundary descriptor. Derive-to-temp-then-move (DEC-006):
# capture the deriver's stdout to a temp file, check its exit, and atomically mv
# into place ONLY on success -- a bare `> dest` would truncate the destination
# before the deriver runs, leaving a partial/empty footprint on a mid-derive
# failure. On failure: emit upgrade.footprint.derive_failed, remove the temp, and
# leave the destination untouched. Returns 0 on success, 1 on decline/failure.
derive_adopter_footprint() {
  local eject="$CORE/ci-templates/scripts/claire-eject.sh"
  if [[ "${AUTOGEN_CONFIRM:-0}" != "1" ]]; then
    echo "upgrade-claire: footprint auto-generate declined (no confirmation); nothing written." >&2
    echo "upgrade-claire: the footprint is still required -- see the Step-0 guidance above." >&2
    return 1
  fi
  if [[ ! -f "$eject" ]]; then
    emit_seam LINEAGE_GAP upgrade.footprint.derive_failed "$eject"
    echo "upgrade-claire: the footprint deriver is absent in the core checkout: $eject" >&2
    echo "upgrade-claire: cannot auto-generate -- check the core checkout path (UPGRADE_CORE)." >&2
    return 1
  fi
  # Co-locate the temp in $TARGET/artifacts (not $TMPDIR) so the mv below is a
  # guaranteed same-filesystem atomic rename -- a cross-device mv degrades to a
  # non-atomic copy+unlink, reopening a (narrow) partial-write window at the dest.
  mkdir -p "$TARGET/artifacts"
  local tmp; tmp="$(mktemp "$TARGET/artifacts/.footprint.XXXXXX")"
  if ! bash "$eject" --derive-adopter-footprint > "$tmp" 2>/dev/null; then
    emit_seam LINEAGE_GAP upgrade.footprint.derive_failed "$eject"
    echo "upgrade-claire: the footprint deriver ($eject --derive-adopter-footprint) exited non-zero." >&2
    echo "upgrade-claire: the destination footprint was NOT modified." >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$FOOTPRINT"
  echo "upgrade-claire: derived the adopter footprint at $FOOTPRINT; proceeding." >&2
  return 0
}

# Step-0 PRODUCTION entry point (PI-032 / DEC-009): the single documented command
# `upgrade-claire.sh --autogen-footprint` dispatches the Step-0 auto-generate
# THROUGH the tested derive_adopter_footprint helper -- so the operator/agent runs
# one safe command and the documented production path IS the temp-then-move helper,
# never a bare `... > "$FOOTPRINT"` redirect (which would truncate the destination
# before the deriver runs -- the anti-pattern DEC-006 forbids). The entry point
# resolves $CORE/$TARGET/$FOOTPRINT via the existing seams before calling this; the
# AUTOGEN_CONFIRM=1 confirmation gate (DEC-003) is enforced inside the helper.
# Lives here (not in the entry point) so upgrade-claire.sh stays under the DX
# <300-line cap (DEC-005). Returns the helper's status (0 success, 1 decline/fail).
run_autogen_mode() {
  derive_adopter_footprint
}

# AC-3 dry-run reporter (PI-032 / DEC-005): print the would-be merge outcome to
# stdout -- total files in scope, the count that would apply cleanly, the count
# that would conflict, and the conflicting paths (one per line). WRITES NOTHING
# (stdout only -- DEC-004). Lives here (not in the entry point) to keep
# upgrade-claire.sh under the DX <300-line cap (DEC-005). Args:
#   <total_in_scope> <clean_count> <conflicted_path...>
dry_run_report() {
  local total="$1" clean="$2"; shift 2
  local conflicts=$#
  echo "upgrade-claire: [dry-run] $total file(s) in scope; $clean would apply cleanly; $conflicts would conflict."
  if [[ $conflicts -gt 0 ]]; then
    local p
    for p in "$@"; do echo "  would-conflict: $p"; done
  fi
  echo "upgrade-claire: [dry-run] nothing was written (no stamp, no staging, no apply)."
}

# AC-3 defensive write guard (PI-032 / IMPOSSIBLE_STATE seam): every write site
# (stamp / staging / apply) calls this BEFORE writing. Under DRY_RUN=1 the dry-run
# branch returns long before any write site, so reaching one here is an impossible
# state -- emit upgrade.dryrun.write_attempted and refuse the write (return 1). A
# silent pass (return 0) under DRY_RUN=0 keeps the live path byte-unchanged.
# Arg: <write_site_label>. Spec: specs/PI-032/spec.md (AC-3 Mutations seam).
assert_not_dry_run() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    emit_seam IMPOSSIBLE_STATE upgrade.dryrun.write_attempted "$1"
    return 1
  fi
  return 0
}

# AC-3 dry-run finisher (DEC-005): keeps the entry point under the DX <300-line
# cap. Prints the report, removes the mktemp scratch (the ONLY thing a dry-run is
# allowed to touch -- it is not a tree/stamp/footprint artifact), and returns the
# CI-keyable exit code: 0 iff zero conflicts, non-zero iff >=1 (DEC-004). Args:
#   <staging_dir> <conflict_count> <total_in_scope> <clean_count> <conflicted_path...>
dry_run_finish() {
  local staging="$1" conflicts="$2" total="$3" clean="$4"; shift 4
  dry_run_report "$total" "$clean" "$@"
  rm -rf "$staging"
  [[ "$conflicts" -eq 0 ]] && return 0 || return 1
}
