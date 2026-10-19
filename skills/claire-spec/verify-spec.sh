#!/usr/bin/env bash
# verify-spec.sh — Layer-1 structural completeness linter for a CLAIRE spec.
#
# Usage: .claude/skills/claire-spec/verify-spec.sh <ticket-id>
#
# Mechanical, deterministic, no LLM judgment. This is the spec-side analog of
# the unfilled-probe grep that anchors the /claire-elicit loop: it asserts that the
# artifacts spec-author produces are structurally complete before the human
# spec-approval gate sees them. Each check traces to a line in the spec-author
# Quality Criteria (.claude/agents/claire-spec-author/AGENT.md "Quality Criteria").
#
# Where it looks: the ticket's artifact root is specs/<id>/ while the ticket is
# live and archive/<id>/ once /claire-archive has relocated it, so this linter resolves
# specs/<id>/ first and falls back to archive/<id>/. specs/ wins if both exist.
# Neither present is a loud exit 1 naming both searched roots -- never a silent
# empty resolution. The "verify-spec:" header names the root that ACTUALLY
# resolved, so the reported location is always the one that was linted.
#
# What it CANNOT check (deferred to the human gate / Layer-2 judgment review):
#   - Whether a filled cell is correct, sound, or well-reasoned.
#   - Placeholders left inside fenced code blocks in spec.md (code legitimately
#     contains braces, so fenced regions are excluded from the spec.md scan).
#   - Layer-2 judgment-only Quality Criteria (e.g. the spec-author step-8h
#     policy-tooling-consistency bullet, and likewise the surface-registry,
#     compat-test, and journey-invariant bullets): gate/judgment conditions
#     this Layer-1 linter intentionally does not enforce.
# It only proves required sections exist and template placeholders were replaced.
#
# Exit codes: 0 = all checks pass (warnings allowed); 1 = one or more failures
# or a usage/precondition error.

set -euo pipefail

usage() {
  echo "Usage: $0 <ticket-id>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
TICKET="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Resolve the ticket's artifact root: the live spec first, else the archived
# copy (/claire-archive relocates specs/<id>/ -> archive/<id>/, so a consumer that
# hardcodes specs/<id>/ breaks silently the moment a ticket is archived).
# Same two-branch shape as pi-053-prod-criteria.test.sh's resolve_pi053, but
# with BTG-127 DEC-003's LOUD miss instead of that pattern's silent empty
# string -- an empty path lets a downstream check degrade into a vacuous pass,
# and this script is a gate. specs/ wins when both exist: a live spec is the
# working copy, an archived one is history.
if   [[ -d "$ROOT/specs/$TICKET"   ]]; then SPEC_REL="specs/$TICKET"
elif [[ -d "$ROOT/archive/$TICKET" ]]; then SPEC_REL="archive/$TICKET"
else
  echo "ERROR: no artifacts for $TICKET -- searched specs/$TICKET/ and archive/$TICKET/" >&2
  exit 1
fi
SPEC_DIR="$ROOT/$SPEC_REL"
SPEC="$SPEC_DIR/spec.md"
TEST_PLAN="$SPEC_DIR/test-plan.md"
PROBLEM="$SPEC_DIR/problem.md"

fails=0
warns=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }

echo "verify-spec: $SPEC_REL"

# --- Presence (Quality Criteria: artifacts produced) ---------------------------
[[ -f "$SPEC" ]]      && pass "spec.md present"      || fail "spec.md missing ($SPEC_REL/spec.md)"
[[ -f "$TEST_PLAN" ]] && pass "test-plan.md present" || fail "test-plan.md missing ($SPEC_REL/test-plan.md)"

# If either core artifact is absent, the remaining checks cannot run.
if [[ ! -f "$SPEC" || ! -f "$TEST_PLAN" ]]; then
  echo "verify-spec: $fails failure(s), $warns warning(s)"
  exit 1
fi

# has_heading <file> <regex> — true if an ATX heading line matches the regex.
has_heading() { grep -qE "^#{1,6} .*$2" "$1"; }

require_section() { # <file> <regex> <label>
  if has_heading "$1" "$2"; then pass "$3"; else fail "$3 — section missing"; fi
}

# count_placeholders <file> <fence-aware:0|1>
# Emits "file:line: text" for every line carrying a residual *template*
# placeholder. A template placeholder is an instructional brace token — one
# that contains internal whitespace (e.g. "{What business entities ...}",
# "{Fill in}") or a known fill-status marker ({Pass/Flag}, {Yes/No},
# {TICKET-ID}, {Title}). Authored prose never wraps multi-word English in
# braces, but brace-templated identifiers legitimately appear in prose
# (`specs/{id}/problem.md`, `{path}`) — so single-token braces are NOT flagged,
# and inline-code spans are stripped before testing. When fence-aware is 1,
# lines inside ``` fenced code blocks are skipped too (spec.md code may contain
# braces); test-plan.md passes 0 so unfilled placeholders inside Gherkin fences
# are still caught (concrete Gherkin has no braces).
count_placeholders() { # <file> <fence-aware>
  awk -v skipfence="$2" '
    /^[[:space:]]*```/ { infence = !infence; next }
    (skipfence && infence) { next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)   # drop inline-code spans before testing
      if (line ~ /\{[^}]*[[:space:]][^}]*\}/ || line ~ /\{(Pass\/Flag|Yes\/No|TICKET-ID|Title)\}/)
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
    # Single awk pass: reads all input (no early pipe close → no SIGPIPE under
    # set -e + pipefail), indents the first 10, then summarizes the remainder.
    printf '%s\n' "$offenders" | awk '
      NR <= 10 { printf "          %s\n", $0 }
      END { if (NR > 10) printf "          ... and %d more\n", NR - 10 }'
  fi
}

echo "spec.md:"
require_section "$SPEC" "Zachman"                "Zachman grid section"
# BTG-332 D6 / Gate 1 OQ-2: require the SCOUT Analysis heading; a spec recorded
# before the rename that still carries the legacy PRISM Analysis heading passes
# with a WARN (never a FAIL), wherever it lives (specs/ or archive/) --
# durability for recorded tickets (Elicited Intent).
# BTG-337 AC-1: the migration-command advice inside that WARN is scoped by
# WHERE the spec lives -- --rewrite-vocab's vocab tree walk is specs/-rooted
# only and never touches archive/, so suggesting it for an archive/-resident
# spec would point the operator at a command that cannot help them. Only a
# specs/-resident spec's WARN names upgrade-claire.sh --rewrite-vocab; an
# archive/-resident spec's WARN does not.
if has_heading "$SPEC" "SCOUT Analysis"; then
  pass "SCOUT Analysis section"
elif has_heading "$SPEC" "PRISM Analysis"; then
  if [[ "$SPEC_REL" == archive/* ]]; then
    warn "legacy PRISM Analysis heading -- recorded before the SCOUT rename; archived records are read as-is and are not migrated"
  else
    warn "legacy PRISM Analysis heading -- recorded before the SCOUT rename; migrate with upgrade-claire.sh --rewrite-vocab"
  fi
else
  fail "SCOUT Analysis section — section missing"
fi
require_section "$SPEC" "Facet Evaluation"       "CLAIRE Facet Evaluation section"
require_section "$SPEC" "Observability Seams"    "Observability Seams section"
require_section "$SPEC" "Proposed Design"        "Proposed Design section"
require_section "$SPEC" "Alternatives Considered" "Alternatives Considered section"
require_section "$SPEC" "Compatibility Impact"   "Compatibility Impact section"
require_section "$SPEC" "Risks"                  "Risks and Open Questions section"

# Design Exploration -- the section BTG-201 added to specs/TEMPLATE/spec.md.
#
# CONDITIONAL BY DESIGN. The requirement is scoped to specs authored under the
# post-BTG-201 process, and the evidence that a ticket WAS is the explorer's own
# artifact sitting in the same resolved ticket root. A spec that predates the
# requirement carries no design-options.md, so it is never retroactively
# rejected -- a guarantee held by this code rather than by who happens to invoke
# the linter. Both branches print; neither is silent.
#
# ANCHORED ON PURPOSE. has_heading() builds "^#{1,6} .*<phrase>", which any
# "#### AC-N: ..." or "### Alternative N: ..." heading merely NAMING the phrase
# satisfies -- a check that could not fail. This uses the same inline-grep idiom
# as the "### Alternative N:" check below.
if [[ -f "$SPEC_DIR/design-options.md" ]]; then
  if grep -qE '^## Design Exploration' "$SPEC"; then
    pass "Design Exploration section"
  else
    fail "Design Exploration section -- section missing (design-options.md exists for this ticket)"
  fi
else
  warn "Design Exploration section not checked -- this ticket has no design-options.md; the Gate 1 checklist decides whether the omission is acceptable"
fi

# >=1 SCOUT AC decomposition block (Quality Criteria: "Every AC has a SCOUT decomposition").
ac_blocks="$(grep -cE '^#### AC-[0-9]+' "$SPEC" || true)"
if [[ "$ac_blocks" -ge 1 ]]; then pass "SCOUT AC decomposition present ($ac_blocks block(s))"
else fail "SCOUT AC decomposition missing — no '#### AC-N' blocks"; fi

# The 3 always-on mandatory facets evaluated (Quality Criteria: "All 3 always-on
# mandatory facets are evaluated"). Data Integrity, Security Posture and Backwards
# Compatibility are TRIGGERED mandatory (org default, PI-055; Security Posture added by
# org security posture policy). Security Posture activates when the change touches
# authentication, authorization, PII, user input handling, or new client-side code.
# NONE of the three
# is hard-required by this mechanical linter, and none may be added to the loop below:
# a grep cannot evaluate a trigger, so requiring a triggered facet here would fail every
# spec whose trigger is legitimately dormant. Their trigger-aware enforcement lives in
# the spec-author role (step 5 / step 10d / the Security Posture trigger check) + the
# code-reviewer, not in this Layer-1 grep.
for facet in "Simplicity" "Operability" "Developer Experience"; do
  if grep -qE "^### Facet [0-9]+: $facet" "$SPEC"; then pass "Facet evaluated: $facet"
  else fail "Mandatory facet not evaluated: $facet"; fi
done

# >=1 alternative documented (Quality Criteria: "At least one alternative is documented").
if grep -qE '^### Alternative [0-9]+:' "$SPEC"; then pass "Alternative documented"
else fail "No alternative documented — expected '### Alternative N:'"; fi

placeholder_check "$SPEC" 1 "No unfilled template placeholders (outside code blocks)"

echo "test-plan.md:"
require_section "$TEST_PLAN" "Acceptance Criteria Coverage" "Acceptance Criteria Coverage section"
require_section "$TEST_PLAN" "BDD Features"                 "BDD Features section"
require_section "$TEST_PLAN" "Implementation Order"         "Implementation Order section"

# >=1 Feature and >=1 Scenario (Quality Criteria: "at least one happy-path AND one edge-case scenario").
feat="$(grep -cE '^\s*Feature:' "$TEST_PLAN" || true)"
scen="$(grep -cE '^\s*Scenario( Outline)?:' "$TEST_PLAN" || true)"
[[ "$feat" -ge 1 ]] && pass "Gherkin Feature present ($feat)" || fail "No Gherkin 'Feature:' found"
[[ "$scen" -ge 1 ]] && pass "Gherkin Scenario present ($scen)" || fail "No Gherkin 'Scenario:' found"

# Implementation Order has >=1 numbered data row (Quality Criteria: "Implementation Order ... sequences all scenarios").
if awk '/^## Implementation Order/{f=1; next} /^## /{f=0} f && /^\| *[0-9]+ *\|/{found=1} END{exit !found}' "$TEST_PLAN"; then
  pass "Implementation Order has sequenced rows"
else
  fail "Implementation Order table has no numbered rows"
fi

placeholder_check "$TEST_PLAN" 0 "No unfilled template placeholders"

# --- Cross-reference (advisory) ------------------------------------------------
# Every acceptance criterion in problem.md should have a SCOUT block in spec.md.
# problem.md lists ACs as markdown checkboxes, so this is a soft signal, not a hard
# gate (criteria may legitimately be grouped into one decomposition).
if [[ -f "$PROBLEM" ]]; then
  ac_bullets="$(awk '/^## Acceptance Criteria/{f=1; next} /^## /{f=0} f && /^- \[[ xX]\] /{c++} END{print c+0}' "$PROBLEM")"
  if [[ "$ac_bullets" -gt 0 && "$ac_bullets" -gt "$ac_blocks" ]]; then
    warn "problem.md lists $ac_bullets acceptance criteria but spec.md has $ac_blocks SCOUT block(s) — confirm none were dropped"
  fi
fi

echo "verify-spec: $fails failure(s), $warns warning(s)"
[[ "$fails" -eq 0 ]] || exit 1
