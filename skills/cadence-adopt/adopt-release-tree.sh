#!/usr/bin/env bash
# adopt-release-tree.sh -- the /cadence-adopt release phase (BTG-314).
# Sourced by adopt-cadence.sh before COPY_PATHS work begins.

_adopt_resolver_path() {
  local c
  for c in "$SRC/skills/cadence-upgrade/upgrade-resolve.sh" \
           "$SRC/.agents/skills/cadence-upgrade/upgrade-resolve.sh" \
           "$SRC/artifacts/commands/cadence-upgrade/upgrade-resolve.sh"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

release_commit() {
  local resolver; resolver="$(_adopt_resolver_path)" || return 1
  local ver; ver="$(resolve_core_version "$SRC")"
  [[ -n "$ver" ]] || return 1
  ( CORE="$SRC"
    emit_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }
    # shellcheck source=/dev/null
    . "$resolver"
    core_commit_for_version "$ver" 2>/dev/null
  )
}

release_tree_cleanup() {
  [[ -n "${RELEASE_TREE:-}" ]] || return 0
  rm -rf "$RELEASE_TREE" 2>/dev/null
  if [[ -e "$RELEASE_TREE" ]]; then
    echo "seam_type=DELTA_AUDIT_GAP event_name=adopt.release_tree.cleanup_failed subject=$RELEASE_TREE" >&2
    echo "ERROR: could not remove the temporary release tree: $RELEASE_TREE" >&2
    return 1
  fi
  return 0
}

adopt_from_release_tree() {
  local stamp_rel="$DST/.cadence-version"
  local commit="" need_resolve=1 use_checkout_fallback=0
  local ver; ver="$(resolve_core_version "$SRC")"
  if [[ -z "$ver" ]]; then
    echo "ERROR: could not resolve CADENCE core version from $SRC (README.md / .cadence-version / tags)." >&2
    exit 1
  fi

  if [[ -e "$stamp_rel" ]]; then
    note_skipped ".cadence-version"
    commit="$(sed -nE 's/^commit=(.*)$/\1/p' "$stamp_rel" | head -n1)"
    local rel_resolved=""
    rel_resolved="$(release_commit || true)"
    if [[ -n "$rel_resolved" && -n "$commit" ]] && git -C "$SRC" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      need_resolve=0
    elif [[ -z "$rel_resolved" ]]; then
      # Running from an untagged development checkout: keep re-adopt running against the checkout
      # rather than materializing an older untagged commit.
      use_checkout_fallback=1
      need_resolve=0
    else
      echo "seam_type=DRIFT_SIGNAL event_name=adopt.release_tree.stamp_commit_unavailable subject=${commit:-<empty>}" >&2
      echo "adopt-cadence: existing stamp commit is unavailable in core checkout; falling back." >&2
      commit=""
    fi
  fi

  if [[ "$need_resolve" -eq 1 ]]; then
    commit="$(release_commit || true)"
    if [[ -z "$commit" ]] || ! git -C "$SRC" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      # Active framework development checkout without matching release tag / README-of-record commit:
      # record HEAD commit and install cleanly from the running checkout rather than hard-failing.
      commit="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo "working-tree")"
      use_checkout_fallback=1
      echo "seam_type=DRIFT_SIGNAL event_name=adopt.release_tree.untagged_checkout subject=$ver" >&2
    fi
  fi

  if [[ ! -e "$stamp_rel" ]]; then
    if { printf 'schema=1\nversion=%s\ncommit=%s\n' "$ver" "$commit" > "$stamp_rel"; } && [[ -s "$stamp_rel" ]]; then
      note_copied ".cadence-version (version stamp)"
    else
      rm -f "$stamp_rel"
      echo "ERROR: could not write version stamp ($stamp_rel)." >&2
      exit 1
    fi
  fi

  local extra=()
  [[ "${GITIGNORE_MACHINERY:-0}" -eq 1 ]] && extra+=(--gitignore-machinery)
  local self_dir canon_src engine_rel engine rc
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  canon_src="$(cd "$SRC" && pwd -P)"

  if [[ "$use_checkout_fallback" -eq 1 ]]; then
    echo "Installing CADENCE $ver from untagged checkout $canon_src ($commit)"
    CADENCE_ADOPT_RELEASE_TREE="checkout" bash "$self_dir/adopt-cadence.sh" "$DST" "${extra[@]}"
    exit $?
  fi

  RELEASE_TREE="$(mktemp -d)"
  trap 'release_tree_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! git -C "$SRC" archive "$commit" 2>/dev/null | tar -x -C "$RELEASE_TREE" 2>/dev/null; then
    echo "seam_type=UNSOUND_CONDITION event_name=adopt.release_tree.unavailable subject=$commit" >&2
    echo "ERROR: could not materialize release tree for commit $commit." >&2
    exit 1
  fi

  engine_rel="${self_dir#"$canon_src"/}"
  engine="$RELEASE_TREE/$engine_rel/adopt-cadence.sh"
  if [[ ! -f "$engine" ]]; then
    for engine in \
      "$RELEASE_TREE/skills/cadence-adopt/adopt-cadence.sh" \
      "$RELEASE_TREE/.agents/skills/cadence-adopt/adopt-cadence.sh"; do
      [[ -f "$engine" ]] && break
    done
  fi
  if [[ ! -f "$engine" ]]; then
    echo "seam_type=UNSOUND_CONDITION event_name=adopt.release_tree.unavailable subject=$engine_rel/adopt-cadence.sh" >&2
    echo "ERROR: materialized release tree for $commit has no adopt-cadence.sh." >&2
    exit 1
  fi

  echo "Installing CADENCE $ver from commit $commit (release tree)"
  CADENCE_ADOPT_RELEASE_TREE="$commit" bash "$engine" "$DST" "${extra[@]}"
  rc=$?
  release_tree_cleanup || rc=1
  trap - EXIT
  exit "$rc"
}
