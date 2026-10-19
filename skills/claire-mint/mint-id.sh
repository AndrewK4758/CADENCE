#!/usr/bin/env bash
#
# mint-id.sh -- CLAIRE's shared, collision-safe id allocator (PI-039).
#
# Bounded context: CLAIRE framework tooling / id-allocation seam.
# Invariant relied on from outside this boundary: CLAIRE_ORG.md §10
# id-allocation-binding governs whether the TICKET prefix is minted locally
# (`None — closed default`) or originates from a bound external tracker; this
# script is the local-mint half and is only ever called on the unbound path
# for tickets (ADR/II/PROD are always local, §10-independent).
#
# WHY THIS EXISTS: CLAIRE is run across parallel linked git worktrees. A
# per-worktree "scan specs/+archive/ for the highest id and increment" races:
# two worktrees pick the same number (the PI-031/032 collision, 2026-06-30).
# This allocator reserves every id against ONE append-only ledger shared by all
# linked worktrees of a clone (the git COMMON dir), serialized by flock, so two
# concurrent `--reserve` calls always get DIFFERENT ids.
#
# Usage:
#   mint-id.sh --peek    [PREFIX]           # print next id, reserve nothing
#   mint-id.sh --reserve [PREFIX] [note]    # atomically reserve + print next id
#   mint-id.sh --list    [PREFIX]           # show the ledger
#   mint-id.sh --seed    PREFIX N [note]    # one-time: baseline PREFIX high-water to N
#
# PREFIX defaults to PI. Numbers are zero-padded per prefix (width_for): ADR is
# 4 digits (docs/ADR/0001-*.md), everything else 3 (PI-034). "Next" id is the
# highest numeric suffix for PREFIX in the ledger + 1 -- monotonic, gaps are
# never reused (a reused gap is a latent collision).

set -euo pipefail

# --- observability seam: a build-time seam fires as a stderr line + non-zero exit
emit_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }

PREFIX_DEFAULT="PI"

# The lock binary. Overridable (CLAIRE_FLOCK_CMD) so a flock-absent host can be
# exercised in tests; on a real flock-absent host (macOS <12, native Windows)
# `command -v` below fails and the caller fails loud (AC-8 / OS-1.1).
FLOCK="${CLAIRE_FLOCK_CMD:-flock}"

# Guard: refuse to mint without an atomic lock. Fires idalloc.reserve.lock_unavailable
# (IMPOSSIBLE_STATE) and returns non-zero -- fail-loud is the SAFE failure, and the
# caller MUST halt rather than scan-fall-back (AC-8 / L-1).
require_flock() {
  if ! command -v "$FLOCK" >/dev/null 2>&1; then
    emit_seam IMPOSSIBLE_STATE idalloc.reserve.lock_unavailable "${1:-}"
    echo "Error: '$FLOCK' is unavailable on this host -- cannot mint an id atomically." >&2
    echo "       Install util-linux (flock) or run under WSL2; never fall back to scanning." >&2
    return 1
  fi
}

# Resolve the ledger path, decoupled from this script's own install location
# (H-4 / DEC-003 -- never $SELF_DIR-relative, or each linked worktree's installed
# copy would read a different ledger and reintroduce the per-worktree collision):
#   1. $CLAIRE_LEDGER            (test seam + escape hatch), if set
#   2. git-common-dir/claire/... in a git repo (shared by all linked worktrees
#      of one clone -- exactly the flock coordination set)
#   3. $PWD/.claire/...          committed working-tree fallback (non-git repo)
# The parent directory is created on demand. On an unresolvable/unwritable path,
# fires idalloc.ledger.path_unresolved and exits non-zero (AC-2 / OS-1.3).
resolve_index() {
  local idx common
  if [[ -n "${CLAIRE_LEDGER:-}" ]]; then
    idx="$CLAIRE_LEDGER"
  elif common="$(git rev-parse --git-common-dir 2>/dev/null)" && [[ -n "$common" ]]; then
    # git-common-dir may be relative to $PWD; resolve to an absolute path so the
    # ledger is stable regardless of which worktree invoked the script.
    common="$(cd "$common" && pwd)" || return 1
    idx="$common/claire/ticket-index.tsv"
  else
    idx="$(pwd)/.claire/ticket-index.tsv"
  fi
  mkdir -p "$(dirname "$idx")" 2>/dev/null || {
    emit_seam IMPOSSIBLE_STATE idalloc.ledger.path_unresolved "$idx"
    echo "Error: cannot resolve or create a writable ledger directory for '$idx'" >&2
    return 1
  }
  echo "$idx"
}

# Highest numeric suffix currently recorded for PREFIX (0 if none). Reads the
# ledger's first TSV column; ignores comments/blanks and other prefixes.
highest_for() {
  local prefix="$1" index="$2"
  [[ -f "$index" ]] || { echo 0; return; }
  awk -F'\t' -v p="$prefix" '
    $1 ~ ("^" p "-[0-9]+$") {
      n = $1; sub(p "-", "", n); n += 0
      if (n > max) max = n
    }
    END { print max + 0 }
  ' "$index"
}

# Number of ledger rows currently recorded for PREFIX (0 if none). The --seed
# refuse-if-seeded guard keys on ROW EXISTENCE, not highest_for -- a prefix
# seeded to high-water 0 (adopt's fresh-install case) still has one row, so a
# second seed must refuse (else an immediate re-adopt double-seeds; the N=0 edge
# highest_for cannot see because max(0)==0==absent).
rows_for() {
  local prefix="$1" index="$2"
  [[ -f "$index" ]] || { echo 0; return; }
  awk -F'\t' -v p="$prefix" '$1 ~ ("^" p "-[0-9]+$") { c++ } END { print c + 0 }' "$index"
}

# Zero-pad width for PREFIX. ADR matches docs/ADR/0001-*.md (4 digits); every
# other prefix keeps the 3-digit convention (PI-034).
#
# BTG-197: ADR_CLAIRE is CLAIRE core's OWN ADR prefix, added beside `ADR`
# rather than in place of it. `ADR` stays exactly as it is -- it is the ADOPTER's
# prefix and this ticket exists precisely so an adopter never has to move.
#
# EXACT LITERALS ONLY, never a loose `ADR*` pattern: a glob would capture a
# legitimate adopter prefix such as ADRIAN and silently repad it to 4, which is a
# colliding id minted with no error (spec.md, Technology Model row 1).
width_for() {
  case "$1" in
    ADR|ADR_CLAIRE) echo 4 ;;
    *) echo 3 ;;
  esac
}

fmt_id() { printf '%s-%0*d' "$1" "$(width_for "$1")" "$2"; }   # PI + 34 -> PI-034

# resolver_required() and the four CLAIRE_ORG.md section 10 binding-delegation
# modes (--binding, --binding-for, --allocator-prefixes, --guard-ticket-seed)
# moved to the colocated mint-id-binding.sh (BTG-247 AC-1 headroom; see that
# file's header for the full rationale). Sourced unconditionally, right after
# `action` is parsed below, so every mode dispatches exactly as before.

usage() {
  echo "Usage: $0 --peek|--reserve|--list [PREFIX] [note]" >&2
  echo "       $0 --seed PREFIX N [note]" >&2
  echo "       $0 --binding [CLAIRE_ORG.md]   # echoes bound|unbound (§10 predicate)" >&2
  echo "       $0 --binding-for PREFIX [CLAIRE_ORG.md]  # echoes bound|unbound for ONE prefix" >&2
  echo "       $0 --allocator-prefixes [CLAIRE_ORG.md]  # every TICKET prefix §10 declares, one per line" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
action="$1"; shift

# shellcheck source=./mint-id-binding.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mint-id-binding.sh"

prefix="${1:-$PREFIX_DEFAULT}"; [[ $# -ge 1 ]] && shift || true
rest="${*:-}"

INDEX="$(resolve_index)"

case "$action" in
  --peek)
    fmt_id "$prefix" "$(( $(highest_for "$prefix" "$INDEX") + 1 ))"
    ;;
  --list)
    if [[ -f "$INDEX" ]]; then cat "$INDEX"; else echo "(empty: $INDEX)"; fi
    ;;
  --reserve)
    note="$rest"
    require_flock "$prefix" || exit 1
    exec 9>>"$INDEX" || { emit_seam IMPOSSIBLE_STATE idalloc.reserve.lock_unavailable "$INDEX"; echo "Error: cannot open ledger '$INDEX' for append." >&2; exit 1; }
    "$FLOCK" 9
    next="$(( $(highest_for "$prefix" "$INDEX") + 1 ))"
    id="$(fmt_id "$prefix" "$next")"
    wt="$(git rev-parse --show-toplevel 2>/dev/null || echo '?')"; wt="${wt##*/}"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\t%s\t%s\t%s\n' "$id" "$ts" "$wt" "$note" >&9
    "$FLOCK" -u 9
    echo "$id"
    ;;
  --seed)
    n="$rest"; n="${n%% *}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "Error: --seed requires PREFIX N [note], N must be numeric" >&2; exit 1; }
    note="${rest#"$n"}"; note="${note# }"
    require_flock "$prefix" || exit 1
    exec 9>>"$INDEX" || { emit_seam IMPOSSIBLE_STATE idalloc.reserve.lock_unavailable "$INDEX"; echo "Error: cannot open ledger '$INDEX' for append." >&2; exit 1; }
    "$FLOCK" 9
    if [[ "$(rows_for "$prefix" "$INDEX")" -ne 0 ]]; then
      existing="$(highest_for "$prefix" "$INDEX")"
      "$FLOCK" -u 9
      echo "Error: prefix '$prefix' is already seeded (high-water $(fmt_id "$prefix" "$existing")); use --reserve instead" >&2
      exit 1
    fi
    id="$(fmt_id "$prefix" "$n")"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\t%s\tseed\t%s\n' "$id" "$ts" "$note" >&9
    "$FLOCK" -u 9
    echo "$id"
    ;;
  *)
    usage
    ;;
esac
