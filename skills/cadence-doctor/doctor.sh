#!/usr/bin/env bash
# Read-only governance, binding, and runtime health audit for CADENCE repos.
# Usage: doctor.sh [--root <dir>] [--ticket <id>] [--check-offload] [--full]
# Exit:  0 clean (all runnable checks passed; skips noted explicitly)
#        1 one or more checks failed or flagged missing prerequisites
#        2 usage failure or not a CADENCE repository
set -u

usage() {
  cat >&2 <<'EOF'
Usage: doctor.sh [--root <dir>] [--ticket <id>] [--check-offload] [--full]
  --root <dir>      Target repository root (default: git top-level or $PWD)
  --ticket <id>     Also audit specs/<id>/ (or archive/<id>/) artifacts & gates
  --check-offload   Probe local llama-swap health on 127.0.0.1:11434
  --full            In framework-dev mode, also execute tests/run-cadence-tests.sh
EOF
  exit 2
}

ROOT="" TICKET="" CHECK_OFFLOAD=0 FULL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)          [[ $# -ge 2 ]] || usage; ROOT="$2"; shift 2 ;;
    --ticket)        [[ $# -ge 2 ]] || usage; TICKET="$2"; shift 2 ;;
    --check-offload) CHECK_OFFLOAD=1; shift ;;
    --full)          FULL=1; shift ;;
    -h|--help)       usage ;;
    *) echo "cadence-doctor: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[[ -d "$ROOT" ]] || { echo "cadence-doctor: root is not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd -P)"

FAILS=0 WARNS=0 PASSES=0 SKIPS=0
pass() { PASSES=$((PASSES + 1)); printf 'PASS  %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1));   printf 'FAIL  %s\n' "$1"; }
warn() { WARNS=$((WARNS + 1));   printf 'WARN  %s\n' "$1"; }
skip() { SKIPS=$((SKIPS + 1));   printf 'SKIP  %s\n' "$1"; }

MODE=""
if [[ -f "$ROOT/tests/run-cadence-tests.sh" && -d "$ROOT/processes/ci-templates/scripts" ]]; then
  MODE="framework-dev"
  PROC_ROOT="$ROOT/processes"
  SCRIPTS_DIR="$PROC_ROOT/ci-templates/scripts"
  ORG_FILE="$PROC_ROOT/docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md"
  AGENTS_DIR="$ROOT/agents"
  SKILLS_DIR="$ROOT/skills"
  HOOKS_DIR="$ROOT/hooks"
  DIRECTIVES="$PROC_ROOT/CADENCE_DIRECTIVES.md"
  FOOTPRINT="$PROC_ROOT/artifacts/footprint.generated"
elif [[ -f "$ROOT/CADENCE_DIRECTIVES.md" || -d "$ROOT/ci-templates/scripts" || -f "$ROOT/docs/agentic-sdlc/CADENCE_ORG.md" ]]; then
  MODE="adopter"
  PROC_ROOT="$ROOT"
  SCRIPTS_DIR="$ROOT/ci-templates/scripts"
  ORG_FILE="$ROOT/docs/agentic-sdlc/CADENCE_ORG.md"
  AGENTS_DIR="$ROOT/.agents/agents"
  SKILLS_DIR="$ROOT/.agents/skills"
  HOOKS_DIR="$ROOT/.agents/hooks"
  DIRECTIVES="$ROOT/CADENCE_DIRECTIVES.md"
  FOOTPRINT="$ROOT/artifacts/footprint.generated"
else
  echo "seam_type=UNSOUND_CONDITION event_name=doctor.not_a_cadence_repo subject=$ROOT" >&2
  echo "cadence-doctor: $ROOT does not contain CADENCE framework or adopter files." >&2
  exit 2
fi

echo "=== CADENCE Doctor ($MODE) @ $ROOT ==="

# 1. Root entrypoint, directives, and runtime symlinks
if [[ -f "$ROOT/AGENTS.md" ]] && grep -q 'CADENCE_DIRECTIVES\.md' "$ROOT/AGENTS.md"; then
  pass "root AGENTS.md references CADENCE_DIRECTIVES.md"
else
  warn "root AGENTS.md missing or does not reference CADENCE_DIRECTIVES.md"
fi
[[ -s "$DIRECTIVES" ]] && pass "directives present ($DIRECTIVES)" || fail "directives missing or empty ($DIRECTIVES)"

broken_links=0
for rdir in "$ROOT/.agents" "$ROOT/.gemini" "$ROOT/.claude"; do
  [[ -e "$rdir" ]] || continue
  while IFS= read -r -d '' bl; do
    fail "broken runtime symlink: ${bl#"$ROOT/"}"
    broken_links=$((broken_links + 1))
  done < <(find "$rdir" -xtype l -print0 2>/dev/null)
done
[[ "$broken_links" -eq 0 ]] && pass "runtime symlinks valid (zero broken links)"

# 2. Organization config & bindings
if [[ -f "$ORG_FILE" ]]; then
  pass "org config present (${ORG_FILE#"$ROOT/"})"
  OBR="$SCRIPTS_DIR/org-binding-resolve.sh"
  if [[ -s "$OBR" ]]; then
    if out="$(cd "$ROOT" && bash "$OBR" --form --org "$ORG_FILE" 2>&1)"; then
      pass "org-binding-resolve --form (${out//$'\n'/; })"
    else
      fail "org-binding-resolve --form failed: $out"
    fi
  elif [[ -e "$OBR" ]]; then
    fail "org-binding-resolve.sh exists at ${OBR#"$ROOT/"} but is 0 bytes"
  else
    skip "org-binding-resolve.sh not installed"
  fi
  for marker in bound-strategy integration-branch bound-version-scheme; do
    val="$(sed -n "s/.*<!-- *${marker}: *\([^>]*\) *-->.*/\1/p" "$ORG_FILE" | head -n 1 | xargs 2>/dev/null || true)"
    if [[ -n "$val" && "$val" != \<* ]]; then
      pass "marker $marker=$val"
    else
      fail "marker $marker missing or placeholder in ${ORG_FILE#"$ROOT/"}"
    fi
  done
  if [[ "$MODE" == "adopter" ]]; then
    ph_count="$(awk '/^## .*Pre-Filled Contextual Grounding Constants/{f=1;next} /^## /{f=0} f && /<[^>]+>/{c++} END{print c+0}' "$ORG_FILE")"
    if [[ "$ph_count" -eq 0 ]]; then
      pass "Contextual Grounding Where/Who/Why placeholders filled (0 remaining)"
    else
      warn "$ph_count line(s) with <placeholder> tokens in CADENCE_ORG.md constants (run /cadence-interview)"
    fi
  fi
else
  fail "org config missing: ${ORG_FILE#"$ROOT/"}"
fi

# 3. Authoring line ceiling (<400 lines)
ceiling_hits=0
for f in "$AGENTS_DIR"/*/*.md "$SKILLS_DIR"/*/SKILL.md "$HOOKS_DIR"/*; do
  [[ -f "$f" && ! -L "$f" ]] || continue
  case "$f" in *.json|*.pyc) continue ;; esac
  lines="$(wc -l < "$f")"
  if [[ "$lines" -ge 400 ]]; then
    fail "line ceiling >=400L ($lines): ${f#"$ROOT/"}"
    ceiling_hits=$((ceiling_hits + 1))
  fi
done
[[ "$ceiling_hits" -eq 0 ]] && pass "all checked agent/skill/hook files <400 lines"

# 4. Eject footprint freshness (must never execute 0-byte gate silently)
EJECT="$SCRIPTS_DIR/cadence-eject.sh"
if [[ -s "$EJECT" && -f "$FOOTPRINT" ]]; then
  if out="$(cd "$ROOT" && bash "$EJECT" --check-footprint 2>&1)"; then
    pass "cadence-eject --check-footprint"
  else
    fail "cadence-eject --check-footprint: $out"
  fi
elif [[ -e "$EJECT" && ! -s "$EJECT" ]]; then
  fail "cadence-eject.sh is 0 bytes"
else
  skip "cadence-eject --check-footprint (script or footprint descriptor absent)"
fi

# 5. Allocator read-only health (--peek makes no writes)
MINT="$SKILLS_DIR/cadence-mint/mint-id.sh"
[[ -x "$MINT" || -s "$MINT" ]] || MINT="$ROOT/.agents/skills/cadence-mint/mint-id.sh"
if [[ -s "$MINT" ]]; then
  if peek="$(cd "$ROOT" && bash "$MINT" --peek ADR 2>&1)"; then
    pass "cadence-mint --peek ADR -> $peek"
  else
    warn "cadence-mint --peek ADR exited non-zero: $peek"
  fi
elif [[ -e "$MINT" ]]; then
  fail "mint-id.sh exists but is 0 bytes"
else
  skip "cadence-mint/mint-id.sh not installed"
fi

# 6. Governance gate scripts (0-byte gate is always a failure, never a silent pass)
run_gate_check() {
  local label="$1" script="$2"; shift 2
  if [[ -e "$script" && ! -s "$script" ]]; then
    fail "$label exists but is 0 bytes (${script#"$ROOT/"})"
    return
  fi
  [[ -s "$script" ]] || { skip "$label (not installed)"; return; }
  local out
  if out="$(cd "$ROOT" && bash "$script" "$@" 2>&1)"; then
    pass "$label"
  else
    local rc=$?
    fail "$label (exit $rc): $(printf '%s' "$out" | tail -n 5 | tr '\n' ' ')"
  fi
}

DEAD_GATE="$SCRIPTS_DIR/dead-citation-gate.sh"
if [[ "$MODE" == "framework-dev" || -d "$PROC_ROOT/archive" ]]; then
  run_gate_check "dead-citation-gate" "$DEAD_GATE" --root "$PROC_ROOT"
else
  skip "dead-citation-gate (no archive/ directory)"
fi

AUTH_GATE="$SCRIPTS_DIR/authored-doc-gate.sh"
if [[ "$MODE" == "adopter" && -f "$ORG_FILE" ]]; then
  run_gate_check "authored-doc-gate" "$AUTH_GATE" --root "$PROC_ROOT"
elif [[ -s "$AUTH_GATE" ]]; then
  run_gate_check "authored-doc-gate (--ledger-hygiene-only)" "$AUTH_GATE" --root "$PROC_ROOT" --ledger-hygiene-only
else
  skip "authored-doc-gate"
fi

CHAOS_GATE="$SCRIPTS_DIR/chaos-citation-gate.sh"
if find "$PROC_ROOT/specs" "$PROC_ROOT/archive" -maxdepth 2 -name 'test-plan.md' 2>/dev/null | grep -q .; then
  run_gate_check "chaos-citation-gate" "$CHAOS_GATE" --root "$PROC_ROOT"
else
  skip "chaos-citation-gate (no ticket test-plan.md files)"
fi

# 7. Optional ticket audit (--ticket <id>)
if [[ -n "$TICKET" ]]; then
  SELF_SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  T_VERIFY_SPEC="$SKILLS_DIR/cadence-spec/verify-spec.sh"
  [[ -e "$T_VERIFY_SPEC" ]] || T_VERIFY_SPEC="$SELF_SKILLS_DIR/cadence-spec/verify-spec.sh"
  T_VERIFY_FACTS="$SKILLS_DIR/cadence-spec/verify-facts.sh"
  [[ -e "$T_VERIFY_FACTS" ]] || T_VERIFY_FACTS="$SELF_SKILLS_DIR/cadence-spec/verify-facts.sh"
  T_AC_CLASSIFY="$SKILLS_DIR/cadence-implement/ac-classify.sh"
  [[ -e "$T_AC_CLASSIFY" ]] || T_AC_CLASSIFY="$SELF_SKILLS_DIR/cadence-implement/ac-classify.sh"

  TDIR=""
  [[ -d "$ROOT/specs/$TICKET" ]] && TDIR="$ROOT/specs/$TICKET"
  [[ -z "$TDIR" && -d "$ROOT/archive/$TICKET" ]] && TDIR="$ROOT/archive/$TICKET"
  if [[ -z "$TDIR" ]]; then
    fail "ticket $TICKET not found under specs/ or archive/"
  elif [[ ! -f "$TDIR/metadata.yaml" ]]; then
    fail "ticket $TICKET missing metadata.yaml"
  else
    tier="$(sed -n 's/^tier:[[:space:]]*["'\'']\{0,1\}\([A-Za-z]*\).*/\1/p' "$TDIR/metadata.yaml" | head -n 1 | tr '[:upper:]' '[:lower:]')"
    tstatus="$(sed -n 's/^status:[[:space:]]*["'\'']\{0,1\}\([A-Za-z-]*\).*/\1/p' "$TDIR/metadata.yaml" | head -n 1 | tr '[:upper:]' '[:lower:]')"
    if [[ "$tier" == "medium" || "$tier" == "high" ]]; then
      pass "ticket $TICKET tier=$tier (${TDIR#"$ROOT/"})"
      if [[ -f "$TDIR/spec.md" ]]; then
        run_gate_check "verify-spec ($TICKET)" "$T_VERIFY_SPEC" --root "$ROOT" "$TICKET"
        run_gate_check "verify-facts ($TICKET)" "$T_VERIFY_FACTS" --root "$ROOT" "$TICKET"
        run_gate_check "verify-facts --rulings ($TICKET)" "$T_VERIFY_FACTS" --root "$ROOT" --rulings "$TICKET"
        if [[ "$tstatus" == "in-progress" || "$tstatus" == "in-review" || "$tstatus" == "merged" || "$tstatus" == "archived" ]]; then
          run_gate_check "verify-facts --trace ($TICKET)" "$T_VERIFY_FACTS" --root "$ROOT" --trace "$TICKET"
        else
          skip "verify-facts --trace ($TICKET) (status=${tstatus:-unset}, pre-implementation)"
        fi
      else
        warn "ticket $TICKET spec.md not yet authored (${TDIR#"$ROOT/"})"
      fi
    elif [[ "$tier" == "low" ]]; then
      pass "ticket $TICKET tier=$tier (${TDIR#"$ROOT/"})"
      if [[ -f "$TDIR/problem.md" ]]; then
        run_gate_check "ac-classify ($TICKET)" "$T_AC_CLASSIFY" "$TDIR/problem.md"
        if [[ "$tstatus" == "in-progress" || "$tstatus" == "in-review" || "$tstatus" == "merged" || "$tstatus" == "archived" ]]; then
          run_gate_check "verify-facts --trace ($TICKET)" "$T_VERIFY_FACTS" --root "$ROOT" --trace "$TICKET"
        else
          skip "verify-facts --trace ($TICKET) (status=${tstatus:-unset}, pre-implementation)"
        fi
      else
        fail "ticket $TICKET problem.md missing"
      fi
    elif [[ "$tier" == "trivial" ]]; then
      pass "ticket $TICKET tier=trivial (spec/AC gates exempt)"
    else
      warn "ticket $TICKET tier unset or unrecognized ('${tier:-empty}')"
    fi
  fi
fi

# 8. Optional local offload endpoint check
if [[ "$CHECK_OFFLOAD" -eq 1 ]]; then
  if command -v curl >/dev/null 2>&1 && curl -sf --max-time 2 http://127.0.0.1:11434/health >/dev/null 2>&1; then
    pass "local offload endpoint reachable at 127.0.0.1:11434"
  else
    fail "local offload endpoint unreachable at 127.0.0.1:11434"
  fi
fi

# 9. Optional full framework regression suite
if [[ "$FULL" -eq 1 && "$MODE" == "framework-dev" ]]; then
  run_gate_check "run-cadence-tests.sh" "$ROOT/tests/run-cadence-tests.sh"
fi

echo "=== Doctor Summary: $PASSES passed, $WARNS warning(s), $FAILS failed, $SKIPS skipped ==="
[[ "$FAILS" -eq 0 ]] || exit 1
exit 0
