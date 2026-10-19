#!/usr/bin/env bash
# adopt-release-tree.sh -- the /claire-adopt release phase (BTG-314).
#
# Bounded context: CLAIRE adoption / the /claire-adopt installer surface.
#
# THE SEAM. Every other module in this directory installs into $DST from the
# RUNNING checkout's working tree. This module decides WHICH commit that
# installation names -- core's release identity, resolved by the same
# tag-bounded resolver /claire-upgrade uses (BTG-311's core_commit_for_version,
# sourced from its one home in the running checkout, Option A / DEC-002) -- then
# materializes that commit's own tree with `git archive` and hands the actual
# copy/provision work to THAT tree's own adopt engine. The stamp
# `.claire-version` and the bytes COPY_PATHS installs therefore always name the
# same commit (DEC-011/DEC-012): an ordinary post-tag checkout's own unreleased
# work is never installed, and the stamp is never HEAD unless HEAD IS that
# commit.
#
# Invariants relied on from outside this boundary:
#   - SOURCED, never executed, into adopt-claire.sh's own shell, BEFORE the
#     COPY_PATHS work begins. Reads SRC / DST / GITIGNORE_MACHINERY /
#     note_copied / resolve_core_version from the CALLER's scope at call time
#     (the same dynamic-scope contract every other sidecar module in this
#     directory relies on). This module's OWN BASH_SOURCE[0] resolves the
#     running engine's directory at CALL time (never at source time), since it
#     is co-located with adopt-claire.sh in every shipped tree.
#   - $SRC/artifacts/commands/claire-upgrade/upgrade-resolve.sh is the RUNNING
#     checkout's own copy. It is sourced in a PRIVATE subshell that binds its
#     own CORE and defines its own emit_seam, so nothing it defines leaks into
#     this shell (R6/R7). A release before BTG-311 does not carry this file, so
#     it can be read only from the checkout adopt runs from, never from a
#     materialized tree (E10).
#   - CLAIRE_ADOPT_RELEASE_TREE is a private, undeclared cross-version
#     handshake (DEC-014), never an adopter-facing flag: the caller (this
#     file's own entry point) has already established that it is either unset
#     (this IS the outer engine -> adopt_from_release_tree runs) or set with
#     $SRC carrying no ".git" (this IS the tree's own engine -> the release
#     phase never runs again).
#
# Spec: archive/BTG-314/spec.md (AC-1..AC-5); decisions.md DEC-002, DEC-003,
#       DEC-011..DEC-015, DEC-019 (OQ-6/OQ-7), DEC-020 (module ceiling).

# release_commit -- echo the commit /claire-adopt installs from and stamps on a
# FRESH resolution, or nothing (R1/R2/R8/R9/R10). Never writes $DST. Resolution
# runs in a private subshell: CORE is bound to $SRC and emit_seam is defined in
# the house shape (seam_type=... event_name=... subject=...), so
# upgrade-resolve.sh's dynamic-scope reads land on values scoped to this call,
# and its own function definitions never enter adopt's shell (R6/R7). Assumes
# the caller has already verified the resolver file exists.
release_commit() {
  local resolver="$SRC/artifacts/commands/claire-upgrade/upgrade-resolve.sh"
  local ver; ver="$(resolve_core_version "$SRC")"
  [[ -n "$ver" ]] || return 1
  ( CORE="$SRC"
    emit_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }
    # shellcheck source=/dev/null
    . "$resolver"
    core_commit_for_version "$ver"
  )
}

# release_tree_cleanup -- remove exactly $RELEASE_TREE (the recorded mktemp -d
# path), never a parent (the BTG-306 lesson). A path that still exists after an
# attempted removal is a LINEAGE_GAP (R19): an 85 MB leak per adoption is not a
# silent success.
release_tree_cleanup() {
  [[ -n "${RELEASE_TREE:-}" ]] || return 0
  rm -rf "$RELEASE_TREE" 2>/dev/null
  if [[ -e "$RELEASE_TREE" ]]; then
    echo "seam_type=LINEAGE_GAP event_name=adopt.release_tree.cleanup_failed subject=$RELEASE_TREE" >&2
    echo "ERROR: could not remove the temporary release tree: $RELEASE_TREE" >&2
    return 1
  fi
  return 0
}

# adopt_from_release_tree -- the release phase (R17/R20). NEVER RETURNS: exits
# with the hand-off's status, or a fatal status of its own before any byte
# reaches $DST.
adopt_from_release_tree() {
  local stamp_rel="$DST/.claire-version"
  local resolver="$SRC/artifacts/commands/claire-upgrade/upgrade-resolve.sh"
  local commit="" need_resolve=1

  # OQ-7 (a), DEC-019: a re-adopt installs the STAMP's commit, so the files it
  # fills in match the recorded base -- never a newer release the stamp does
  # not name (R11). No resolution runs when the stamp's commit is usable
  # (S-3.5): the resolver is not even consulted.
  if [[ -e "$stamp_rel" ]]; then
    note_skipped ".claire-version"   # create-once: never overwrite an existing base ancestor
    commit="$(sed -nE 's/^commit=(.*)$/\1/p' "$stamp_rel" | head -n1)"
    if [[ -n "$commit" ]] && git -C "$SRC" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      need_resolve=0
    else
      echo "seam_type=DRIFT_SIGNAL event_name=adopt.release_tree.stamp_commit_unavailable subject=${commit:-<empty>}" >&2
      echo "adopt-claire: the existing stamp's commit is unavailable in this core checkout; falling back to a freshly resolved commit. The stamp itself is left untouched." >&2
      commit=""
    fi
  fi

  if [[ "$need_resolve" -eq 1 ]]; then
    if [[ ! -f "$resolver" ]]; then
      echo >&2
      echo "ERROR: could not write the version stamp (.claire-version) -- resolver not found: $resolver" >&2
      echo "Adoption aborted — refusing to report success without the version stamp." >&2
      exit 1
    fi
    commit="$(release_commit)" || commit=""
    if [[ -z "$commit" ]]; then
      echo >&2
      echo "ERROR: could not write the version stamp (.claire-version)." >&2
      echo "Adoption aborted — refusing to report success without the version stamp." >&2
      exit 1
    fi
  fi

  RELEASE_TREE="$(mktemp -d)"
  trap 'release_tree_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! git -C "$SRC" archive "$commit" 2>/dev/null | tar -x -C "$RELEASE_TREE" 2>/dev/null; then
    echo "seam_type=IMPOSSIBLE_STATE event_name=adopt.release_tree.unavailable subject=$commit" >&2
    echo "ERROR: could not materialize the release tree for commit $commit (git archive/tar failed)." >&2
    echo "ERROR: could not write the version stamp (.claire-version)." >&2
    echo "Adoption aborted — refusing to report success without the version stamp." >&2
    exit 1
  fi

  local self_dir engine_rel engine
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  engine_rel="${self_dir#"$SRC"/}"
  engine="$RELEASE_TREE/$engine_rel/adopt-claire.sh"
  if [[ ! -f "$engine" ]]; then
    echo "seam_type=IMPOSSIBLE_STATE event_name=adopt.release_tree.unavailable subject=$engine_rel/adopt-claire.sh" >&2
    echo "ERROR: the release tree for commit $commit has no adopt engine at $engine_rel/adopt-claire.sh." >&2
    echo "ERROR: could not write the version stamp (.claire-version)." >&2
    echo "Adoption aborted — refusing to report success without the version stamp." >&2
    exit 1
  fi

  local ver; ver="$(resolve_core_version "$SRC")"
  if [[ ! -e "$stamp_rel" ]]; then
    if { printf 'schema=1\nversion=%s\ncommit=%s\n' "$ver" "$commit" > "$stamp_rel"; } \
         && [[ -s "$stamp_rel" ]]; then
      note_copied ".claire-version (version stamp)"
    else
      rm -f "$stamp_rel"
      echo >&2
      echo "ERROR: could not write the version stamp ($stamp_rel)." >&2
      echo "Adoption aborted — refusing to report success without the version stamp." >&2
      exit 1
    fi
  fi

  echo "Installing CLAIRE $ver from commit $commit (release tree; the checkout's working tree is not installed)"
  local extra=()
  [[ "${GITIGNORE_MACHINERY:-0}" -eq 1 ]] && extra+=(--gitignore-machinery)
  CLAIRE_ADOPT_RELEASE_TREE="$commit" bash "$engine" "$DST" "${extra[@]}"
  local rc=$?
  release_tree_cleanup || rc=1
  trap - EXIT
  exit "$rc"
}
