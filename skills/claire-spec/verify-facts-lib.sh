#!/usr/bin/env bash
# verify-facts-lib.sh -- BTG-331 cycle 2 (code-review B1/B3). Helpers factored
# out of verify-facts.sh to hold it under the 400-line Facet 3 ceiling after
# the two fixes below widened them: the citation checker (facts mode,
# generalized to range/list citation forms per B1) and the Gate 1 evidence
# label computation (rulings mode, generalized to examine every backticked
# token in a ruling's reason per B3, not just the first).
#
# Bounded context: CLAIRE framework tooling / the registered /claire-spec
# surface (docs/policies/claire-surfaces.md). Sourced ONLY by verify-facts.sh,
# from the same directory (resolved via that script's own BASH_SOURCE, so this
# works unmodified from both the neutral source tree and the compiled
# .claude/skills/claire-spec/ tree -- sidecar-completeness-gate.sh mirrors the
# whole directory).
# Invariant relied on from outside this boundary: the caller defines
# report_fact, ROOT, BASE and TICKET_DIR before sourcing this file. See
# archive/BTG-331/decisions.md DEC-011 for why this split exists, and
# verify-facts.sh (Proposed Design -> Sidecar interface) for the design
# rationale of the two functions themselves.
#
# PORTABILITY: bash + awk/grep only (II_CLAIRE-013, busybox-safe CI).

set -u

# check_citation <path> <spec> -- B1. <spec> is a single line number, a range
# (N-M) or a comma-separated list of numbers/ranges (e.g. "81-91",
# "73,304-321"), exactly the tokens the caller's broadened citation regex
# extracts. Checks the MAX numeric endpoint across the whole spec against the
# file's line count at $BASE -- the preferred resolution B1 calls for. A spec
# with no numeric endpoint (should not occur given the caller's regex, but
# never silently skipped) reports UNVERIFIABLE by name instead.
check_citation() {
  local path="$1" spec="$2"
  if [[ "$path" != */* ]] && ! git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
    report_fact UNVERIFIABLE citation "$path:$spec"
    return 0
  fi
  if ! git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
    report_fact FAIL citation "$path:$spec" "path is absent at base ($BASE)"
    return 0
  fi
  local maxn
  maxn="$(grep -oE '[0-9]+' <<<"$spec" | sort -n | tail -1)"
  if [[ -z "$maxn" ]]; then
    report_fact UNVERIFIABLE citation "$path:$spec" "no numeric endpoint in citation"
    return 0
  fi
  local lines
  lines="$(git -C "$ROOT" cat-file -p "$BASE:$path" 2>/dev/null | awk 'END{print NR}')"
  lines="${lines:-0}"
  if [[ "$maxn" -le "$lines" ]]; then
    report_fact PASS citation "$path:$spec"
  else
    report_fact FAIL citation "$path:$spec" "$path has $lines lines at base ($BASE)"
  fi
}

# compute_label <value> <why> -- R7, generalized per B3. amend/override always
# diverge. For agree, iterate EVERY backticked token in <why> (not just the
# first, which was the B3 defect) -- label `examined` the moment any ONE
# token qualifies (resolves in the working tree AND its exact token appears
# in none of the ticket's own agent-authored artifacts); only when no token
# qualifies (or none is present at all) does the label fall through to
# `accepted-as-presented`.
compute_label() {
  local value="$1" why="$2"
  case "$value" in
    amend|override) echo diverged; return 0 ;;
  esac

  local -a tokens=()
  while IFS= read -r tok; do
    [[ -n "$tok" ]] && tokens+=("$tok")
  done < <(grep -oE '`[^`]+`' <<<"$why")
  [[ ${#tokens[@]} -gt 0 ]] || { echo accepted-as-presented; return 0; }

  local token tpath tn resolves lc f found_in_own
  for token in "${tokens[@]}"; do
    token="${token#\`}"; token="${token%\`}"
    tpath="$token"; tn=""
    if [[ "$token" =~ ^(.+):([0-9]+)$ ]]; then
      tpath="${BASH_REMATCH[1]}"; tn="${BASH_REMATCH[2]}"
    fi
    resolves=0
    [[ -f "$ROOT/$tpath" ]] && resolves=1
    if [[ "$resolves" -eq 1 && -n "$tn" ]]; then
      lc="$(awk 'END{print NR}' "$ROOT/$tpath" 2>/dev/null)"
      lc="${lc:-0}"
      [[ "$tn" -le "$lc" ]] || resolves=0
    fi
    [[ "$resolves" -eq 1 ]] || continue

    found_in_own=0
    for f in "$TICKET_DIR/spec.md" "$TICKET_DIR/test-plan.md" "$TICKET_DIR/design-options.md" "$TICKET_DIR/submission.md"; do
      [[ -f "$f" ]] || continue
      if grep -qF -- "$token" "$f"; then
        found_in_own=1
        break
      fi
    done
    [[ "$found_in_own" -eq 0 ]] && { echo examined; return 0; }
  done
  echo accepted-as-presented
}
