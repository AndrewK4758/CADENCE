#!/usr/bin/env bash
# verify-facts-lib.sh -- Fact, citation-symbol proximity, and Gate-1 evidence helpers
# sourced ONLY by verify-facts.sh (keeps every module <400 lines).

set -u

# check_citation <path> <spec> [co_symbols...]
# Validates file existence at $BASE, line endpoint <= file line count, and
# (when co-located backticked symbol identifiers were mentioned alongside path:N)
# checks whether at least one mentioned identifier appears within +-5 lines of
# the cited coordinate at $BASE.
check_citation() {
  local path="$1" spec="$2" co_syms="${3:-}"
  if [[ "$path" != */* ]] && ! git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
    report_fact UNVERIFIABLE citation "$path:$spec"
    return 0
  fi
  if ! git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
    report_fact FAIL citation "$path:$spec" "path is absent at base ($BASE)"
    return 0
  fi
  local minn maxn
  minn="$(grep -oE '[0-9]+' <<<"$spec" | sort -n | head -1)"
  maxn="$(grep -oE '[0-9]+' <<<"$spec" | sort -n | tail -1)"
  if [[ -z "$maxn" ]]; then
    report_fact UNVERIFIABLE citation "$path:$spec" "no numeric endpoint in citation"
    return 0
  fi
  local content lines
  content="$(git -C "$ROOT" cat-file -p "$BASE:$path" 2>/dev/null || true)"
  lines="$(printf '%s\n' "$content" | awk 'END{print NR}')"
  lines="${lines:-0}"
  if [[ "$maxn" -gt "$lines" ]]; then
    report_fact FAIL citation "$path:$spec" "$path has $lines lines at base ($BASE)"
    return 0
  fi

  if [[ -n "$co_syms" ]]; then
    local lo=$(( minn > 5 ? minn - 5 : 1 ))
    local hi=$(( maxn + 5 ))
    local window
    window="$(printf '%s\n' "$content" | sed -n "${lo},${hi}p")"
    local matched=0 sym
    for sym in $co_syms; do
      if grep -qF -- "$sym" <<<"$window"; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -eq 0 ]]; then
      report_fact FAIL citation "$path:$spec" "symbol(s) [$co_syms] not found near L${lo}-L${hi} in $path"
      return 0
    fi
  fi

  report_fact PASS citation "$path:$spec"
}

# extract_citations_with_symbols <file> -- prints "<path>\t<linespec>\t<space-separated co_syms>"
extract_citations_with_symbols() {
  python3 - "$1" <<'PY'
import pathlib, re, sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
seen = {}
in_fence = False
pat_colon = re.compile(r"`([A-Za-z0-9_./-]+):([0-9]+(?:[,-][0-9]+)*)`")
pat_md = re.compile(r"\[[^\]]+\]\(([^)#\s]+)#L([0-9]+)(?:-L?([0-9]+))?\)")
pat_bt = re.compile(r"`([A-Za-z_][A-Za-z0-9_]{2,})(?:\(\))?`")

for raw in lines:
    if re.match(r"^\s*```", raw):
        in_fence = not in_fence
        continue
    if in_fence:
        continue
    cites = [(m.group(1), m.group(2)) for m in pat_colon.finditer(raw)]
    for m in pat_md.finditer(raw):
        p, l1, l2 = m.group(1), m.group(2), m.group(3)
        cites.append((p, f"{l1}-{l2}" if l2 else l1))
    if not cites:
        continue
    syms = []
    for bm in pat_bt.finditer(raw):
        tok = bm.group(1)
        if tok in {"true", "false", "null", "None", "Add", "Modify", "Delete", "Pass", "Flag"}:
            continue
        if any(tok in p for p, _ in cites):
            continue
        syms.append(tok)
    sym_str = " ".join(dict.fromkeys(syms))
    for p, spec in cites:
        key = (p, spec)
        if key not in seen:
            seen[key] = sym_str
        elif sym_str and not seen[key]:
            seen[key] = sym_str

for (p, spec), sym_str in sorted(seen.items()):
    print(f"{p}\t{spec}\t{sym_str}")
PY
}

# compute_label <value> <why> -- R7/B3 Gate 1 evidence labeler
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
