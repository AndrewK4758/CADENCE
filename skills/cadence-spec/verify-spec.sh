#!/usr/bin/env bash
# verify-spec.sh — Layer-1 + Layer-1.5 structural and invariant linter for CADENCE specs.
#
# Usage: .agents/skills/cadence-spec/verify-spec.sh [--root <dir>] <ticket-id>
#
# Resolves repo root via `git rev-parse --show-toplevel` (or --root) so running
# through a symlinked ~/.agents/skills/ installation never targets the wrong repo.

set -euo pipefail

usage() {
  echo "Usage: $0 [--root <repo-root>] <ticket-id>" >&2
  exit 1
}

ROOT=""
TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || usage
      ROOT="$2"; shift 2 ;;
    -*) usage ;;
    *)
      [[ -z "$TICKET" ]] || usage
      TICKET="$1"; shift ;;
  esac
done
[[ -n "$TICKET" ]] || usage

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$ROOT" ]]; then
  ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if   [[ -d "$ROOT/specs/$TICKET"   ]]; then SPEC_REL="specs/$TICKET"
elif [[ -d "$ROOT/archive/$TICKET" ]]; then SPEC_REL="archive/$TICKET"
else
  echo "ERROR: no artifacts for $TICKET -- searched $ROOT/specs/$TICKET/ and $ROOT/archive/$TICKET/" >&2
  exit 1
fi
SPEC_DIR="$ROOT/$SPEC_REL"
SPEC="$SPEC_DIR/spec.md"
TEST_PLAN="$SPEC_DIR/test-plan.md"
PROBLEM="$SPEC_DIR/problem.md"
DESIGN_OPTIONS="$SPEC_DIR/design-options.md"
IS_ARCHIVE=0
[[ "$SPEC_REL" == archive/* ]] && IS_ARCHIVE=1

fails=0
warns=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }

echo "verify-spec: $SPEC_REL"

# --- Presence ---------------------------------------------------------------
[[ -f "$SPEC" ]]      && pass "spec.md present"      || fail "spec.md missing ($SPEC_REL/spec.md)"
[[ -f "$TEST_PLAN" ]] && pass "test-plan.md present" || fail "test-plan.md missing ($SPEC_REL/test-plan.md)"

if [[ ! -f "$SPEC" || ! -f "$TEST_PLAN" ]]; then
  echo "verify-spec: $fails failure(s), $warns warning(s)"
  exit 1
fi

has_heading() { grep -qE "^#{1,6} .*$2" "$1"; }
require_section() {
  if has_heading "$1" "$2"; then pass "$3"; else fail "$3 — section missing"; fi
}

# Catches brace placeholders ({multi words}, {TBD|TODO|FIXME|N/A|Fill in}) AND
# unfilled <angle-bracket placeholder> tokens outside inline code & fenced blocks.
count_placeholders() { # <file> <fence-aware:0|1>
  awk -v skipfence="$2" '
    /^[[:space:]]*```/ { infence = !infence; next }
    (skipfence && infence) { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      gsub(/<!--[^>]*-->/, "", line)
      if (line ~ /\{[^}]*[[:space:]][^}]*\}/ || line ~ /\{(Pass\/Flag|Yes\/No|TICKET-ID|Title|TBD|TODO|FIXME|N\/A)\}/) {
        printf "%s:%d: %s\n", FILENAME, FNR, $0
        next
      }
      # Catch <placeholder phrase> while sparing URLs <http...> and short HTML tags (<br>, <em>, etc.)
      tmp = line
      gsub(/<https?:\/\/[^>]+>/, "", tmp)
      gsub(/<\/?(br|hr|p|sub|sup|details|summary|code|pre|table|tr|td|th|a|img|em|strong|b|i|ul|ol|li)([[:space:]][^>]*)?>/, "", tmp)
      if (tmp ~ /<[a-z][a-z0-9_ -]{2,}>/)
        printf "%s:%d: %s\n", FILENAME, FNR, $0
    }
  ' "$1"
}

placeholder_check() { # <file> <fence-aware> <label>
  local offenders
  offenders="$(count_placeholders "$1" "$2")"
  if [[ -z "$offenders" ]]; then
    pass "$3"
  else
    local n
    n="$(printf '%s\n' "$offenders" | grep -c '')"
    fail "$3 — $n unfilled placeholder line(s):"
    printf '%s\n' "$offenders" | awk '
      NR <= 10 { printf "          %s\n", $0 }
      END { if (NR > 10) printf "          ... and %d more\n", NR - 10 }'
  fi
}

echo "spec.md:"
require_section "$SPEC" "Contextual Grounding"      "Contextual Grounding Matrix (6W×4L) section"
if has_heading "$SPEC" "CHORD (Analysis|Decomposition)"; then
  pass "CHORD Analysis section"
elif has_heading "$SPEC" "PRISM Analysis"; then
  if [[ "$IS_ARCHIVE" -eq 1 ]]; then
    warn "legacy Analysis heading -- archived record not migrated"
  else
    warn "legacy Analysis heading -- migrate with upgrade-cadence.sh --rewrite-vocab"
  fi
else
  fail "CHORD Analysis section — section missing"
fi
require_section "$SPEC" "(Pillar|Facet) Evaluation" "CADENCE Engineering Pillar Evaluation section"
require_section "$SPEC" "Observability Seams"       "Observability Seams section"
require_section "$SPEC" "Proposed Design"           "Proposed Design section"
require_section "$SPEC" "Alternatives Considered"   "Alternatives Considered section"
require_section "$SPEC" "Compatibility Impact"      "Compatibility Impact section"
require_section "$SPEC" "Risks"                     "Risks and Open Questions section"

if [[ -f "$DESIGN_OPTIONS" ]]; then
  if grep -qE '^## Design Exploration' "$SPEC"; then
    pass "Design Exploration section"
  else
    fail "Design Exploration section -- section missing (design-options.md exists for this ticket)"
  fi
else
  warn "Design Exploration section not checked -- no design-options.md present"
fi

ac_blocks="$(grep -cE '^#### AC-[0-9]+' "$SPEC" || true)"
if [[ "$ac_blocks" -ge 1 ]]; then pass "CHORD AC decomposition present ($ac_blocks block(s))"
else fail "CHORD AC decomposition missing — no '#### AC-N' blocks"; fi

for pillar in "(Structural Simplicity|Simplicity)" "(Operational Resilience|Operability)" "(Agentic Ergonomics|Developer Experience)"; do
  if grep -qE "^### (Pillar|Facet) [0-9]+: $pillar" "$SPEC"; then
    pass "Pillar evaluated: $pillar"
  else
    fail "Mandatory pillar not evaluated: $pillar"
  fi
done

if grep -qE '^### Alternative [0-9]+:' "$SPEC"; then pass "Alternative documented"
else fail "No alternative documented — expected '### Alternative N:'"; fi

placeholder_check "$SPEC" 1 "No unfilled template placeholders (outside code blocks)"

echo "test-plan.md:"
require_section "$TEST_PLAN" "Acceptance Criteria Coverage" "Acceptance Criteria Coverage section"
require_section "$TEST_PLAN" "BDD Features"                 "BDD Features section"
require_section "$TEST_PLAN" "Implementation Order"         "Implementation Order section"

feat="$(grep -cE '^\s*Feature:' "$TEST_PLAN" || true)"
scen="$(grep -cE '^\s*Scenario( Outline)?:' "$TEST_PLAN" || true)"
[[ "$feat" -ge 1 ]] && pass "Gherkin Feature present ($feat)" || fail "No Gherkin 'Feature:' found"
[[ "$scen" -ge 1 ]] && pass "Gherkin Scenario present ($scen)" || fail "No Gherkin 'Scenario:' found"

if awk '/^## Implementation Order/{f=1; next} /^## /{f=0} f && /^\| *[0-9]+ *\|/{found=1} END{exit !found}' "$TEST_PLAN"; then
  pass "Implementation Order has sequenced rows"
else
  fail "Implementation Order table has no numbered rows"
fi

placeholder_check "$TEST_PLAN" 0 "No unfilled template placeholders"

echo "invariants:"
if [[ -f "$SELF_DIR/verify-spec-invariants.sh" ]]; then
  # shellcheck source=/dev/null
  . "$SELF_DIR/verify-spec-invariants.sh"
  SPEC_AC_IDS=""
  check_chord_tables_and_data_integrity "$SPEC" "$IS_ARCHIVE"
  check_cross_artifact_traceability "$ROOT" "$SPEC" "$TEST_PLAN" "$IS_ARCHIVE" "$SPEC_AC_IDS"
  check_design_options_hygiene "$DESIGN_OPTIONS" "$IS_ARCHIVE"
  check_pillar_precedence_convergence "$SPEC" "$DESIGN_OPTIONS" "$IS_ARCHIVE"
else
  warn "verify-spec-invariants.sh absent; skipped Layer-1.5 checks"
fi

if [[ -f "$PROBLEM" ]]; then
  ac_bullets="$(awk '/^## Acceptance Criteria/{f=1; next} /^## /{f=0} f && /^- \[[ xX]\] /{c++} END{print c+0}' "$PROBLEM")"
  if [[ "$ac_bullets" -gt 0 && "$ac_bullets" -gt "$ac_blocks" ]]; then
    warn "problem.md lists $ac_bullets acceptance criteria but spec.md has $ac_blocks CHORD block(s) — confirm none were dropped"
  fi
fi

echo "verify-spec: $fails failure(s), $warns warning(s)"
[[ "$fails" -eq 0 ]] || exit 1
