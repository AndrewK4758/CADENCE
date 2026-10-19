#!/usr/bin/env bash
#
# eject-footprint-headers.sh -- the two descriptor header prologues, extracted
# from eject-footprint.sh (BTG-008) so that file stays under the 300-line DX
# target after the hooks tree_root row + mode-gate additions. Behavior-preserving
# extraction: the heredocs move verbatim. Sourced by eject-footprint.sh in this
# shell's scope.

# The ADOPTER-mode descriptor prologue (categories 1+2 only).
eject_footprint_header_adopter() {
  cat <<'HDR'
# DERIVED -- do not hand-edit. The ADOPTER CADENCE-footprint descriptor: the
# boundary between the installed CADENCE surface and the adopter team's own
# project code, consumed by cadence-eject.sh. Generated at adoption time.
#
# Categories 1+2 ONLY -- precise enumeration of the INSTALLED framework surface.
# There is NO deny-by-default sweep here: an adopter's arbitrary project code is
# NEVER stripped (the framework_dev category is for ejecting a framework-dev repo
# only). PI-017 / DEC-003 / DEC-011.
#
#   (1) tree_root  -- the compiled .claude/ tree roots, resolved via the runtime
#                     binding (RC-6); NEVER a hardcoded .claude/... literal here.
#   (2) installed  -- the installed framework surface = adopt-cadence.sh COPY_PATHS.
#   (seed) -- adopter-owned documents seeded at adopt time, stripped at eject, and
#            EXCLUDED from the upgrade merge (never merged or created -- BTG-015).
#
# Row grammar: kind=<tree_root|installed|seed> (identity=<id> binding_hook=<hook> | path=<repo-relative-path>)
HDR
}

# BTG-016a (DEC-001/DEC-006): the stale-committed-footprint hooks-tree_root
# backfill, extracted from eject-footprint.sh load_descriptor so that file stays
# under the 300-line DX ceiling (Simplicity #4 > DX #7 -- extract into this
# EXISTING sibling, never a new file). Runs in load_descriptor's shell scope
# (STRIP_PATHS / STRIP_SOURCE / REPO_ROOT and resolve_tree_root are all visible;
# arrays mutate in place). Mirrors the upgrade engine's collect_in_scope hooks
# backfill (upgrade-bootstrap.sh, BTG-008 AC-8).
#
# A pre-BTG-008 adopter descriptor LACKS the identity=hooks tree_root row; once
# the compiled .claude/cadence-hooks/ tree exists on disk it would LEAK at eject.
# When so, add that tree_root to the strip set IN MEMORY -- never mutating the
# committed file (ADR_CADENCE-0009). Adopter-mode only (framework-dev already strips
# .claude wholesale / carries the row); deduped (a descriptor already listing the
# row adds it once). An `(backfill)` audit line, NOT a seam -- routine, expected
# reconciliation on the normal path (BTG-015 DEC-007); its disk-probe guard also
# rejects an unresolved {{...}} residue, an empty root, or a "."/"/" root (no junk
# strip) -- mirroring the parent-dir guard in eject-footprint.sh load_descriptor.
#
# Arg: <fwdev_mode> (1 = framework-dev descriptor -> inert; 0 = adopter mode).
eject_footprint_backfill_hooks_root() {
  local fwdev_mode="$1"
  [[ "$fwdev_mode" -eq 0 ]] || return 0
  local hooks_root; hooks_root="$(resolve_tree_root artifact_root:hooks)" || return 1
  [[ -n "$hooks_root" && "$hooks_root" != "." && "$hooks_root" != "/" && -d "$REPO_ROOT/$hooks_root" ]] || return 0
  local sp
  for sp in "${STRIP_PATHS[@]}"; do [[ "$sp" == "$hooks_root" ]] && return 0; done
  STRIP_PATHS+=("$hooks_root")
  STRIP_SOURCE+=("tree_root:artifact_root:hooks(backfill)")
}

# BTG-017 (DEC-001): the adopter-side footprint-STALENESS signal, read-only.
# Reuses the BTG-016a in-memory reconciliation as the hand-list-free definition of
# "the installed CADENCE surface" (constraint (a) / PI-017 DEC-002 -- NO
# deny-by-default hand-list, NO re-derivation, which is impossible in an adopter
# repo). Staleness := load_descriptor had to backfill a tree_root the committed
# descriptor omitted (a STRIP_SOURCE entry tagged "(backfill)"). Lives in this
# sibling (not eject-footprint.sh, which sits at the 299-line DX ceiling) and runs
# in load_descriptor's shell scope (STRIP_SOURCE is visible). ADR_CADENCE-0009: never
# mutates the committed descriptor.

# Echo each STRIP_SOURCE entry that is a (backfill) staleness marker; return 0 if
# any were found, 1 if none. STRIP_SOURCE must be populated (call load_descriptor
# first) -- the caller does so in the parent shell, because the --check-footprint
# diff runs derive_footprint in a process-substitution subshell whose mutations do
# not persist.
eject_footprint_stale_roots() {
  local found=1 s
  for s in "${STRIP_SOURCE[@]}"; do
    case "$s" in
      *'(backfill)'*) printf '%s\n' "$s"; found=0 ;;
    esac
  done
  return "$found"
}

# Load the committed descriptor (populating STRIP_SOURCE via the in-memory
# backfill), scan for staleness, and WARN on stderr when stale. Returns:
#   2 -- precondition failure (load_descriptor already emitted a fail-loud seam)
#   1 -- not stale (no (backfill) marker: current descriptor, hooks tree absent,
#        or framework-dev mode where the backfill is inert)
#   0 -- STALE: a warning was emitted (default posture is warn/exit 0; the caller
#        honors EJECT_FAIL_ON_STALE)
report_footprint_staleness() {
  load_descriptor || return 2
  local stale
  stale="$(eject_footprint_stale_roots)" || return 1
  {
    echo "cadence-eject: WARNING -- stale committed footprint detected."
    echo "cadence-eject:   stale surface: $stale"
    echo "cadence-eject:   eject is UNAFFECTED -- the tree_root is backfilled in memory; the leak is closed (BTG-016a)."
    echo "cadence-eject:   Refresh: run /cadence-upgrade --repair (from a CADENCE core providing --repair; BTG-016b -- this pointer does not assert its presence in your installed core)."
    echo "cadence-eject:   If --repair is absent: upgrade to a core providing --repair, or see docs/guides/upgrade-repair-runbook.md."
    echo "cadence-eject:   The committed artifacts/footprint.generated is NOT modified (read-only; ADR_CADENCE-0009)."
  } >&2
  return 0
}

# The FRAMEWORK-DEV descriptor prologue (categories 1+2+3, deny-by-default).
eject_footprint_header_framework_dev() {
  cat <<'HDR'
# DERIVED -- do not hand-edit. The authoritative CADENCE-footprint descriptor:
# the single boundary between framework material and project-owned code, shared
# with Workstream A (update/override) and consumed by cadence-eject.sh.
#
# Composed (in order) from three canonical-identity sources -- regenerate with
#   bash ci-templates/scripts/cadence-eject.sh --derive-footprint
# and verify with
#   bash ci-templates/scripts/cadence-eject.sh --check-footprint
# (mirrors cadence-compile.sh --check-manifest). PI-017 / DEC-003 (Option B).
#
#   (1) tree_root  -- the compiled .claude/ tree roots, resolved via the runtime
#                     binding (RC-6); NEVER a hardcoded .claude/... literal here.
#   (2) installed  -- the installed framework surface = adopt-cadence.sh
#                     COPY_PATHS (the inverse of the strip boundary).
#   (3) framework_dev -- DENY-BY-DEFAULT (DEC-011): EVERY top-level repo entry,
#                     EXCEPT .git and the reviewed non-CADENCE exceptions
#                     (ci-templates/scripts/eject-exceptions.conf). Complete by
#                     construction -- a new top-level CADENCE entry is covered
#                     automatically; an independent completeness gate is the
#                     backstop. (Was a hand-maintained list that failed open.)
#   (seed) -- adopter-owned documents seeded at adopt time, stripped at eject, and
#            EXCLUDED from the upgrade merge (never merged or created -- BTG-015).
#
# Row grammar: kind=<tree_root|installed|seed|framework_dev> (identity=<id> binding_hook=<hook> | path=<repo-relative-path>)
HDR
}
