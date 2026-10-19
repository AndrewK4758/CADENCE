#!/usr/bin/env bash
#
# gitignore-block.sh -- the optional managed-.gitignore-block concern of
# adopt-cadence (PI-034). Co-located sidecar module, sourced by
# adopt-cadence.sh in its shell scope so SRC/DST and the note_copied helper
# resolve as in the entry point (kept separate to hold the entry point under the
# 300-line DX target -- R-1; the Claude adapter copies the WHOLE sidecar dir, so
# a co-located module travels and is placeholder-expanded, II-016).
#
# Bounded context: adopt-cadence install flow (co-located layout). Writes ONLY
# the adopter target repo's root .gitignore.
#
# Invariant relied on from outside this boundary: artifacts/footprint.generated
# (the adopter eject descriptor) is the single authoritative enumeration of "what
# is CADENCE" in the target -- generated earlier in the same adopt run. The
# ignore-path set is DERIVED from it via the eject module's load_descriptor (so
# it cannot drift from the eject strip-set), never a hand-maintained list.
#
# Upstream: called by adopt-cadence.sh when --gitignore-machinery is passed,
#   after the artifacts/footprint.generated create-once block, before the verify
#   loop. Downstream: read-modify-writes <target>/.gitignore.
# Spec: specs/PI-034/spec.md (Proposed Design); decisions DEC-002/012/013/014.
#       BTG-198 DEC-014 moved the generic read-modify-write half of this module
#       to managed-block.sh; this file keeps the .gitignore-specific derivation
#       and its two DEC-013 filters and delegates the write. Marker text,
#       GITIGNORE_ACTION values, filter behaviour and every refusal message are
#       byte-identical to before that extraction.

# The shared marker-fenced writer (BTG-198 DEC-014). Sourced from beside this
# module so this concern travels with its tool; the guard makes the double-source
# (context-block.sh sources it too) harmless.
# shellcheck source=/dev/null
[[ -n "${MANAGED_BLOCK_SOURCED:-}" ]] || . "$(dirname "${BASH_SOURCE[0]}")/managed-block.sh"

# Stable, unique managed-block markers (idempotency anchors, DEC-002). A re-run
# replaces the region between the FIRST marker pair in place; never appends a
# second block.
# LF-line-ending assumption (PI-034 review S-2): marker detection and replacement
# match these as exact WHOLE lines (grep -qFx / awk $0==), so a managed block
# whose lines were CRLF-converted by an editor would not be recognized and a
# re-run would append a second block instead of replacing it. Our own writes are
# always LF (printf '\n'), so this only affects an externally CRLF-mangled file.
# The matching now happens in managed-block.sh, which restates this caveat at its
# module head (BTG-198 OQ-2: accepted, not hardened).
GITIGNORE_BEGIN='# >>> CADENCE machinery (managed by adopt-cadence --gitignore-machinery) >>>'
GITIGNORE_END='# <<< CADENCE machinery <<<'

# Set by write_gitignore_block to "written" | "replaced" so the caller can
# announce which path it took (DEC-009).
GITIGNORE_ACTION=""

# write_gitignore_block <src> <dst>
#   <src>  framework-source root (where ci-templates/scripts/eject-footprint.sh
#          lives -- the same $SRC the descriptor-generation block uses).
#   <dst>  adopter target repo root (its root .gitignore is the write target).
# Loads the in-$DST descriptor through the eject module, computes the ignore-path
# list (resolved tree roots + installed paths minus TWO filtered entries,
# DEC-013), and read-modify-writes a single managed block. Returns 0 on success
# (GITIGNORE_ACTION set), non-zero with a loud stderr refusal on any failure
# (II-014: never report success past a requested deliverable), leaving no partial
# block.
write_gitignore_block() {
  local src="$1" dst="$2"
  local footprint="$dst/artifacts/footprint.generated"
  local gitignore="$dst/.gitignore"

  # Precondition (DEC-006): the descriptor must exist & be non-empty. It was
  # generated earlier this run (create-once on re-adopt). Absent => fail loud.
  if [[ ! -s "$footprint" ]]; then
    echo >&2
    echo "ERROR: --gitignore-machinery requested but the footprint descriptor is absent or empty ($footprint)." >&2
    echo "Adoption aborted -- refusing to report success without the requested .gitignore machinery block (II-014)." >&2
    return 1
  fi

  # Reuse the eject module's descriptor parser. It populates the parallel arrays
  # STRIP_PATHS[] / STRIP_SOURCE[]: the resolved tree roots (binding-resolved via
  # the adapter -- NO native-root literal here, PI-024/DEC-010), the synthesized
  # bare parent-dir entry (tagged "...(root)"), and every installed path. SELF_DIR
  # and FOOTPRINT are the inputs load_descriptor / resolve_tree_root read; REPO_ROOT
  # is the adopter tree ($dst) whose on-disk hooks presence the BTG-016a hooks-root
  # backfill probes (load_descriptor calls it; unbound REPO_ROOT would abort under set -u).
  # shellcheck source=/dev/null
  SELF_DIR="$src/ci-templates/scripts" FOOTPRINT="$footprint" REPO_ROOT="$dst" . "$src/ci-templates/scripts/eject-footprint.sh"
  SELF_DIR="$src/ci-templates/scripts" FOOTPRINT="$footprint" REPO_ROOT="$dst" load_descriptor || {
    echo >&2
    echo "ERROR: could not load the footprint descriptor to derive .gitignore paths ($footprint)." >&2
    echo "Adoption aborted -- refusing to report success without the requested .gitignore machinery block (II-014)." >&2
    return 1
  }

  # Compute ignore lines by iterating the parallel arrays by index. TWO filters
  # (DEC-013, narrow carve-out): (1) drop the CONTEXT WIRING -- adopters customize
  # CLAUDE.md and share it via their remote, and BTG-198 DEC-011 extends the same
  # carve-out to CADENCE_DIRECTIVES.md for the identical reason, more strongly:
  # CLAUDE.md's import is INERT without the sidecar, so ignoring half the wiring
  # is worse than ignoring neither -- a teammate's fresh clone would get a context
  # file importing a path that is not in the remote, and every CADENCE agent on
  # that clone would read zero CADENCE directives. (2) drop the bare parent-dir
  # entry load_descriptor synthesizes (its STRIP_SOURCE ends in "(root)"), so
  # adopter-owned content directly under the runtime config dir (e.g.
  # settings.json) stays trackable. The result: the resolved tree roots + every
  # installed path except the two context files; CHANGELOG.md / archive/ never
  # appear (they are not descriptor rows). The carve-out stays a FILTER over a
  # descriptor-derived list, never a hand-maintained denylist -- it names the
  # context wiring and nothing else, and a third entry would be the signal to
  # reconsider the shape rather than to keep appending.
  local lines=() i p s
  for i in "${!STRIP_PATHS[@]}"; do
    p="${STRIP_PATHS[$i]}"; s="${STRIP_SOURCE[$i]}"
    [[ "$p" == "CLAUDE.md" || "$p" == "CADENCE_DIRECTIVES.md" ]] && continue  # filter 1: context-wiring carve-out
    [[ "$s" == *'(root)' ]] && continue        # filter 2: bare parent-dir entry
    lines+=("$p")
  done

  # Build the fresh managed block (markers + one path per line) in a temp file.
  local block; block="$(mktemp)" || return 1
  {
    printf '%s\n' "$GITIGNORE_BEGIN"
    printf '%s\n' "${lines[@]}"
    printf '%s\n' "$GITIGNORE_END"
  } > "$block"

  # Read-modify-write, DELEGATED to the shared writer (BTG-198 DEC-014). It
  # replaces the FIRST open->first close region in place when a terminated block
  # is present (PI-034 OQ-1/DEC-014: do not self-heal a double-block), otherwise
  # appends a fresh block, preserving all non-managed content + ordering
  # byte-for-byte and creating .gitignore if absent. Every refusal it prints
  # names this deliverable, so the messages are byte-identical to the pre-
  # extraction ones. The block temp file is OURS to clean up on both paths.
  MANAGED_BLOCK_DELIVERABLE=".gitignore machinery block"
  if ! write_managed_block "$gitignore" "$GITIGNORE_BEGIN" "$GITIGNORE_END" "$block"; then
    rm -f "$block"
    return 1
  fi
  GITIGNORE_ACTION="$MANAGED_BLOCK_ACTION"
  rm -f "$block"
  return 0
}
