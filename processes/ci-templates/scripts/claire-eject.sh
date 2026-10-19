#!/usr/bin/env bash
#
# claire-eject -- produce a client-bound copy of a project with ALL CLAIRE
# material stripped, driven by the footprint descriptor (canonical identity),
# resolving native artifact roots through the runtime binding (ADR_CLAIRE-0008 cl.5).
#
# Bounded context: Source-export / IP-separation flow (PI-017, Workstream B).
# Invariant relied on from outside this boundary: the footprint descriptor
# (artifacts/footprint.generated) is the single authoritative enumeration of
# "what is CLAIRE" -- the same boundary Workstream A (update/override) reads
# (Structural Finding A). The native artifact tree roots are resolved through
# the runtime binding (CLAIRE_ORG.md#runtime-binding, RC-6) via the adapter's
# placeholder expansion -- this script body holds NO native-root literal in its
# strip logic (clause-7 sweep over this source is an acceptance criterion).
#
# Properties:
#   - One-directional: copies <src> -> <dest>; NEVER mutates <src>; no import-back.
#   - File-strip only: does NOT scrub .git history (BL-003, out of scope -- the
#     export is a copy, not a history rewrite; documented, not over-claimed).
#   - Fail-loud, never fail-open: a missing/unparseable descriptor or a bad
#     destination is a non-zero refusal, never a hardcoded-strip-list fallback.
#
# Usage:
#   claire-eject.sh <src-repo-root> <empty-dest-dir>
#   claire-eject.sh --derive-footprint            # print the derived descriptor
#   claire-eject.sh --check-footprint             # derive-and-diff gate
#
# Exit codes: 0 success / clean ; non-zero on a precondition failure or drift.
#
# References: specs/PI-017/{spec,test-plan,decisions}.md ; docs/ADR/0008-*.md
#             (clause 5 -- canonical identity, binding resolution).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"

# The committed footprint descriptor travels with the framework (installed by
# adopt-claire alongside this script). Override with EJECT_FOOTPRINT for tests.
FOOTPRINT="${EJECT_FOOTPRINT:-$REPO_ROOT/artifacts/footprint.generated}"

# ---------------------------------------------------------------------------
# The footprint-descriptor + strip-set concern lives in a sourced module so each
# file stays under the 300-line DX target (PI-017; mirrors the compile-*.sh
# split). It runs in this shell's scope, so SELF_DIR/REPO_ROOT/FOOTPRINT and the
# STRIP_* arrays resolve as before. (DEC-PI017-01.)
# shellcheck source=/dev/null
. "$SELF_DIR/eject-footprint.sh"
# BTG-008 (DEC-005): adopter-mode transform-on-ship for the co-owned
# .claude/settings.json lives in a sourced module so this entry point + the
# footprint module stay under the DX <300-line target.
# shellcheck source=/dev/null
. "$SELF_DIR/eject-transform.sh"

# ---------------------------------------------------------------------------
# eject <src> <dest> -- the strip-and-copy with a faithful audit record.
# ---------------------------------------------------------------------------
do_eject() {
  local src="$1" dest="$2"

  if [[ -z "$src" || -z "$dest" ]]; then
    echo "claire-eject: usage: claire-eject.sh <src-repo-root> <empty-dest-dir>" >&2
    return 2
  fi
  if [[ ! -d "$src" ]]; then
    echo "claire-eject: source is not a directory: $src" >&2
    return 1
  fi
  src="$(cd "$src" && pwd)"

  # Destination preconditions (clobber / recursive-copy guard).
  if [[ ! -d "$dest" ]]; then
    echo "claire-eject: destination directory does not exist: $dest" >&2
    return 1
  fi
  dest="$(cd "$dest" && pwd)"
  if [[ "$dest" == "$src" ]]; then
    emit_seam IMPOSSIBLE_STATE eject.precondition.dest_not_empty_or_nested "$dest"
    echo "claire-eject: destination must not equal the source." >&2
    return 1
  fi
  if [[ "$dest" == "$src/"* ]]; then
    emit_seam IMPOSSIBLE_STATE eject.precondition.dest_not_empty_or_nested "$dest"
    echo "claire-eject: destination must not be nested within the source tree." >&2
    return 1
  fi
  if [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    emit_seam IMPOSSIBLE_STATE eject.precondition.dest_not_empty_or_nested "$dest"
    echo "claire-eject: destination must be empty." >&2
    return 1
  fi

  # Load the boundary (fails loud on missing/malformed descriptor).
  load_descriptor || return 1

  # A recognizable CLAIRE install: the descriptor's identity is present in
  # <src>. Refuse to silently copy a non-CLAIRE tree as "clean".
  local roles_root commands_root
  roles_root="$(resolve_tree_root artifact_root:roles)" || return 1
  # BTG-198: the second arm is RE-KEYED from CLAUDE.md to the framework-owned
  # sidecar. Post-split CLAUDE.md is categorically ADOPTER-owned -- any repo may
  # have one, including a repo that never adopted CLAIRE -- so its presence no
  # longer evidences a CLAIRE install and keeping it here would make this
  # refusal fail OPEN on exactly the tree it exists to catch. The compiled-tree
  # arm is unchanged and remains the dominant signal.
  if [[ ! -e "$src/$roles_root" && ! -e "$src/CLAIRE_DIRECTIVES.md" ]]; then
    echo "claire-eject: no CLAIRE material detected in $src (no compiled artifact tree, no CLAIRE_DIRECTIVES.md)." >&2
    echo "claire-eject: refusing -- this does not look like a CLAIRE install; nothing to strip." >&2
    return 1
  fi

  # The audit record defaults OUTSIDE the delivered subtree so it does not
  # itself ship as CLAIRE residue (DEC-008 / OQ-4). Override with EJECT_AUDIT.
  local audit
  audit="${EJECT_AUDIT:-$dest.eject-audit.txt}"
  if ! ( : > "$audit" ) 2>/dev/null; then
    emit_seam LINEAGE_GAP eject.audit.record_missing_or_inconsistent "$audit"
    echo "claire-eject: audit-record location is not writable: $audit" >&2
    echo "claire-eject: refusing to complete an unaudited export." >&2
    return 1
  fi

  local now stripped=0 shipped=0
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  {
    echo "# claire-eject audit record"
    echo "# NOTE: file-strip export only -- .git history is NOT scrubbed (BL-003, out of scope)."
    echo "descriptor=$FOOTPRINT"
    echo "timestamp=$now"
    echo "source=$src"
    echo "destination=$dest"
    echo "# disposition  path  [descriptor-entry]"
  } > "$audit"

  # Walk the source tree (relative paths). For each file, strip or ship.
  local f rel reason
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    # .git is never copied (it is not project content; eject does not scrub it
    # either -- a handed-over .git is out of scope, BL-003).
    [[ "$rel" == ".git" || "$rel" == ".git/"* ]] && continue
    if reason="$(strip_reason_for "$rel")"; then
      echo "stripped  $rel  $reason" >> "$audit"
      stripped=$((stripped + 1))
    else
      mkdir -p "$dest/$(dirname "$rel")"
      cp -p "$f" "$dest/$rel"
      echo "shipped   $rel" >> "$audit"
      shipped=$((shipped + 1))
    fi
  done < <(find "$src" -type f -print0 | sort -z)

  # BTG-008 (DEC-005): in ADOPTER mode (no framework_dev rows in the descriptor)
  # the co-owned .claude/settings.json ships (parent-strip is framework-dev-only)
  # and is TRANSFORMED on the dest copy -- CLAIRE hook entries removed, adopter
  # config preserved. In framework-dev mode the whole .claude/ (incl. settings)
  # was already stripped, so there is nothing to transform. Fail loud (abort) if
  # the transform refuses a non-canonical shipped settings.json.
  # BTG-057 (DEC-006): the co-owned-config transforms are now dispatched through
  # the in-engine registry (settings.json + .mcp.json + opencode.json), iterated
  # rather than each hardcoded here (ADR_CLAIRE-0018 amendment / registry-driven dispatch).
  local fwdev_mode=0
  grep -qE '^kind=framework_dev ' "$FOOTPRINT" && fwdev_mode=1
  if [[ $fwdev_mode -eq 0 ]]; then
    if ! eject_transform_dispatch "$dest" "$audit"; then
      echo "claire-eject: adopter-mode co-owned-config transform-on-ship failed -- aborting." >&2
      return 1
    fi
  fi

  echo "claire-eject: $stripped stripped, $shipped shipped."
  # BTG-016a: make the in-memory hooks-tree_root backfill EXPLICIT when it supplied
  # a strip path (a STALE committed footprint that omitted the identity=hooks row).
  # Routine attribution, not a seam (BTG-015 DEC-007); the committed descriptor is
  # left byte-unchanged (ADR_CLAIRE-0009) -- the (backfill) suffix already rides each
  # per-file audit line via STRIP_SOURCE.
  local ssrc
  for ssrc in "${STRIP_SOURCE[@]}"; do
    if [[ "$ssrc" == *'(backfill)'* ]]; then
      echo "claire-eject: note -- stale committed footprint: $ssrc supplied in memory (committed descriptor unchanged; ADR_CLAIRE-0009)."
      break
    fi
  done
  echo "claire-eject: audit record -> $audit"
  return 0
}

# ---------------------------------------------------------------------------
# Adopter-repo footprint re-derivation (BTG-007 / DEC-004). An adopter repo has
# no COPY_PATHS source (adopt-claire.sh is framework-repo-only), so the
# committed descriptor is the adopter's boundary of record (manifest-as-boundary,
# Facet 4). derive_footprint delegates here when adopt-claire.sh is absent.
# Validate the committed descriptor (via the sourced load_descriptor: parseable +
# tree-root hooks resolve) and re-emit it. Fail LOUD on a missing/empty,
# malformed/unresolved-hook, or framework_dev-contaminated descriptor -- NEVER
# emit an empty or project-code-stripping one (PI-017 DEC-003 / DEC-011).
#
# Upstream: called by eject-footprint.sh derive_footprint on --derive-footprint /
#   --check-footprint when run in an adopter repo (no adopt-claire.sh).
# Downstream: prints the validated committed adopter descriptor to stdout; never
#   mutates the committed descriptor; emits a named seam + non-zero exit on fault.
# Spec: specs/BTG-007/spec.md (AC-4); decisions.md DEC-004.
derive_adopter_from_committed() {
  if [[ ! -s "$FOOTPRINT" ]]; then
    emit_seam IMPOSSIBLE_STATE footprint.derive.no_adopter_source "$FOOTPRINT"
    echo "claire-eject: adopter repo has no COPY_PATHS source and no committed descriptor to re-derive from: $FOOTPRINT" >&2
    echo "claire-eject: refusing -- there is NO empty/framework-dev fallback (would leak or over-strip)." >&2
    return 1
  fi
  load_descriptor || return 1   # parseable + tree-root hooks resolve, else fail loud
  if grep -qE '^kind=framework_dev ' "$FOOTPRINT"; then
    emit_seam SEAM_VIOLATION eject.descriptor.framework_dev_in_adopter "$FOOTPRINT"
    echo "claire-eject: adopter descriptor carries framework_dev rows (corruption / wrong mode): $FOOTPRINT" >&2
    return 1
  fi
  cat "$FOOTPRINT"              # re-emit the validated adopter boundary
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  --derive-footprint)
    derive_footprint framework-dev
    ;;
  --derive-adopter-footprint)
    # The PRECISE installed-surface descriptor an adopter repo uses (no
    # deny-by-default sweep). adopt-claire generates this at install time so an
    # adopter's eject strips only the installed CLAIRE surface, never project
    # code (DEC-011).
    derive_footprint adopter
    ;;
  --check-footprint)
    if [[ ! -f "$FOOTPRINT" ]]; then
      echo "claire-eject: no committed footprint descriptor at $FOOTPRINT." >&2
      exit 1
    fi
    if diff <(derive_footprint) "$FOOTPRINT" >/dev/null; then
      # BTG-017: the adopter-mode diff is a tautology (derive re-emits the committed
      # descriptor), so "in sync" alone cannot see a STALE footprint. Scan the
      # in-memory reconciliation for a (backfill) marker and warn. Silent in
      # framework-dev mode (the backfill is inert -> not stale). The diff ran
      # derive_footprint in a subshell, so load_descriptor is re-run in the parent.
      report_footprint_staleness; sr=$?
      if [[ $sr -eq 2 ]]; then exit 1; fi   # precondition failure (fail-loud already emitted)
      if [[ $sr -eq 0 ]]; then              # STALE -> warned (default: non-disruptive)
        # Opt-in escalation: EJECT_FAIL_ON_STALE turns staleness into a hard CI
        # fail (and ONLY staleness -- a healthy footprint never reaches here).
        [[ -n "${EJECT_FAIL_ON_STALE:-}" ]] && exit 1
        exit 0
      fi
      echo "OK: committed footprint descriptor is in sync with derive(sources)."
      exit 0
    fi
    emit_seam LINEAGE_GAP footprint.derive.drift "$FOOTPRINT"
    echo "FAILED: committed footprint descriptor diverges from derive(sources)." >&2
    echo "The descriptor is DERIVED, not authored -- regenerate with --derive-footprint." >&2
    # BTG-198: a drift that LOSES a context row is not just any drift -- the
    # committed descriptor is the eject strip boundary, so a descriptor without
    # CLAUDE.md or the directive sidecar stops stripping them from a client
    # deliverable. Name each missing row specifically before the generic diff, so
    # a confidentiality-relevant omission is legible rather than one line in a
    # wall of diff output a reader skims past (LINEAGE_GAP
    # eject.footprint.context_row_missing).
    for _ctx_row in "kind=seed path=CLAUDE.md" "kind=installed path=CLAIRE_DIRECTIVES.md"; do
      if ! grep -qFx "$_ctx_row" "$FOOTPRINT"; then
        emit_seam LINEAGE_GAP eject.footprint.context_row_missing "$_ctx_row"
        echo "FAILED: the committed descriptor is missing the context row: $_ctx_row" >&2
        echo "        Without it, eject stops stripping that file from a client deliverable." >&2
      fi
    done
    diff "$FOOTPRINT" <(derive_footprint) >&2
    exit 1
    ;;
  --*)
    echo "claire-eject: unknown option: $1" >&2
    exit 2
    ;;
  *)
    if do_eject "${1:-}" "${2:-}"; then
      exit 0
    fi
    exit 1
    ;;
esac
