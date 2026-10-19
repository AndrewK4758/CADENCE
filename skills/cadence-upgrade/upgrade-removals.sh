#!/usr/bin/env bash
#
# upgrade-removals.sh -- the BTG-047 clobber-safe removed-upstream removal shim of
# /cadence-upgrade (AC-13 / DEC-006). A colocated sidecar module shipped by the
# PI-023 directory-copy contract and sourced by upgrade-cadence.sh in this
# shell's scope (so CORE / TARGET / emit_seam / core_file resolve at call time --
# the same wiring as upgrade-hooks.sh).
#
# Bounded context: Upgrade seam / layered-source flow (BTG-047, Workstream A).
# Upstream: called by upgrade-cadence.sh main() in the PRE-APPLY computation
#   phase (after collect_in_scope + the merge loop, before the conflicts>0 gate),
#   so it obeys the existing atomic contract. Downstream: removes ONLY the
#   removed-upstream flat files this manifest names from the adopter tree, and
#   ONLY when byte-identical to the version CADENCE shipped at the stamp base
#   (reconstructed via core_file at base_commit -- never an invented base). A
#   MODIFIED file is surfaced as an ordinary upgrade conflict (staged, stamp NOT
#   advanced), never clobbered -- preserving upgrade's no-clobber safety property.
#   Spec: specs/BTG-047/spec.md (Proposed Design -> Clobber-safe upgrade-removal
#   shim; AC-13); decisions.md DEC-006. Upgrade-only: /cadence-adopt
#   (adopt-cadence.sh) never delivered these files, so the shim is not wired there.

# The removal manifest: removed-upstream **regular-file** paths (never a tree).
# BTG-047 relocated the flat docs/policies/branch-strategy.md into the
# docs/policies/branch-strategy/ directory, so the flat file is removed-upstream:
# the generic 3-way merge loop never touches it (it is no longer in COPY_PATHS /
# footprint), so without this shim it would linger in already-adopted repos.
REMOVAL_MANIFEST=(
  docs/policies/branch-strategy.md
  # BTG-332: prism-reference.md is retired in favor of chord-reference.md (a
  # new COPY_PATHS/RECONCILE entry, upgrade-collect.sh). A pristine copy is
  # removed on the clean-apply path; an adopter-modified copy is surfaced as
  # an ordinary conflict and never clobbered (S-4.3/S-4.4).
  docs/agentic-sdlc/prism-reference.md
)

# removals_classify <base_commit> <base_empty>
# Classifies each manifest path PRESENT in the adopter tree against the
# stamp-base-shipped bytes. Populates two arrays consumed by main():
#   REMOVALS_DELETE   -- byte-identical to base -> safe to delete on clean apply.
#   REMOVALS_CONFLICT -- differs from base (adopter-modified) -> surface, never delete.
# No-ops (never a blind delete): adopter lacks the file, OR the base never shipped
# it (empty base bytes) -- the fail-safe skip.
removals_classify() { # base_commit base_empty
  local base_commit="$1" base_empty="$2" rel basef
  REMOVALS_DELETE=(); REMOVALS_CONFLICT=()
  for rel in "${REMOVAL_MANIFEST[@]}"; do
    [ -f "$TARGET/$rel" ] || continue                 # adopter lacks it -> no-op
    basef="$(mktemp)"
    if [[ "$base_empty" -eq 1 ]]; then
      : > "$basef"                                    # 2-way fallback: no base
    else
      core_file "$base_commit" "$rel" "$basef"        # reconstruct stamp-base bytes
    fi
    if [[ ! -s "$basef" ]]; then                      # never shipped at base -> no-op
      rm -f "$basef"; continue
    fi
    if diff -q "$TARGET/$rel" "$basef" >/dev/null 2>&1; then
      REMOVALS_DELETE+=("$rel")                        # pristine -> remove on clean apply
    else
      REMOVALS_CONFLICT+=("$rel")                      # modified -> surface as conflict
    fi
    rm -f "$basef"
  done
}
