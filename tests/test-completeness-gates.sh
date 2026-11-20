#!/usr/bin/env bash
# Offline regression suite (T13) for generalized CADENCE completeness gates,
# repo-level strictness resolution, CLI override, unconfigured fail-loud prompt,
# pillar non-inversion, shared-invariant absence closure, satellite --code-root
# Layer 2 proofs, structured review anomaly dispositions, and Out-of-Scope overlap.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GATE="$ROOT/skills/cadence-certainty/certainty-gate.sh"
VSPEC="$ROOT/skills/cadence-spec/verify-spec.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_gate() {
  local exp="$1"; shift
  local rc=0 out=""
  out="$(bash "$GATE" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -ne "$exp" ]]; then
    echo "FAIL: expected exit $exp, got $rc for: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# --- 1. Strictness resolution: unconfigured -> CLI override -> AGENTS.md fallback -> team>1 HALT ---
FIX="$TMP/fix"
bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$FIX" >/dev/null
git -C "$FIX" checkout -q -b impl/feat/ACME-COMP
echo "Gate 1 ruling: unknowns -- agree -- reviewed" >> "$FIX/specs/ACME-201/decisions.md"

# 1A. Remove strictness markers from CADENCE_ORG.md -> ESCALATE completeness_strictness_unconfigured
sed -i '/Completeness Strictness Binding/,$d' "$FIX/docs/agentic-sdlc/CADENCE_ORG.md"
out1a="$(run_gate 2 --root "$FIX" --base trunk --stage spec ACME-201)"
grep -q 'ESCALATE completeness_strictness_unconfigured' <<<"$out1a"
grep -q 'strictness=unconfigured' <<<"$out1a"

# 1B. Explicit CLI override --strictness escalate clears unconfigured on clean ticket
out1b="$(run_gate 0 --root "$FIX" --base trunk --stage spec --strictness escalate ACME-201)"
grep -q 'strictness=escalate' <<<"$out1b"

# 1C. Root AGENTS.md fallback (solo repo -> escalate mode)
cat > "$FIX/AGENTS.md" <<'MD'
# Repo System Instructions
<!-- team-size: 1 -->
<!-- enforce-review: no -->
MD
out1c="$(run_gate 0 --root "$FIX" --base trunk --stage spec ACME-201)"
grep -q 'PASS completeness_strictness AGENTS.md' <<<"$out1c"
grep -q 'strictness=escalate' <<<"$out1c"
rm -f "$FIX/AGENTS.md"

# 1D. Team >1 + enforce-review: yes -> HALT on unruled HIGH KNOWN risk & pillar precedence inversion
cat >> "$FIX/docs/agentic-sdlc/CADENCE_ORG.md" <<'MD'

## Completeness Strictness Binding
<!-- team-size: >1 -->
<!-- enforce-review: yes -->
<!-- completeness-strictness: auto -->
MD
cp "$FIX/specs/ACME-201/design-options.md" "$FIX/specs/ACME-201/design-options.bak"
sed -i 's/\[Pillar: Operational Resilience | Severity: LOW | Scope: in-scope\]/[Pillar: Security Boundary Posture | Severity: HIGH | Scope: cross-boundary]/' "$FIX/specs/ACME-201/design-options.md"

out1d_halt="$(run_gate 1 --root "$FIX" --base trunk --stage spec ACME-201)"
grep -q 'HALT unruled_known_risk' <<<"$out1d_halt"
grep -q 'HALT pillar_precedence_inversion' <<<"$out1d_halt"
grep -q 'strictness=halt' <<<"$out1d_halt"

# CLI override --strictness escalate downgrades team-strict HALT -> ESCALATE (exit 2)
out1d_ov="$(run_gate 2 --root "$FIX" --base trunk --stage spec --strictness escalate ACME-201)"
grep -q 'ESCALATE unruled_known_risk' <<<"$out1d_ov"
grep -q 'strictness=escalate' <<<"$out1d_ov"

# verify-spec.sh independently catches pillar_precedence_inversion
rc_vs=0
out_vs="$(bash "$VSPEC" --root "$FIX" ACME-201 2>&1)" || rc_vs=$?
[[ "$rc_vs" -eq 1 ]]
grep -q 'pillar_precedence_inversion' <<<"$out_vs"

# Recording explicit Gate 1 ruling for known_risks clears certainty-gate
echo "Gate 1 ruling: known_risks -- agree -- explicit risk acceptance for temporary window" >> "$FIX/specs/ACME-201/decisions.md"
out1d_ok="$(run_gate 0 --root "$FIX" --base trunk --stage spec ACME-201)"
grep -q 'PASS known_risks' <<<"$out1d_ok"
mv "$FIX/specs/ACME-201/design-options.bak" "$FIX/specs/ACME-201/design-options.md"

# --- 2. Satellite --code-root Layer 2 proofs + shared-invariant absence closure + Out-of-Scope overlap ---
SAT="$TMP/sat-gov"
APP="$TMP/app-repo"
mkdir -p "$SAT/specs/TKT-500" "$SAT/docs/agentic-sdlc" "$APP/src"
git -C "$SAT" init -q -b main && git -C "$SAT" config user.email ci@test && git -C "$SAT" config user.name CI
git -C "$APP" init -q -b main && git -C "$APP" config user.email ci@test && git -C "$APP" config user.name CI

cat > "$SAT/docs/agentic-sdlc/CADENCE_ORG.md" <<'MD'
## Branch-Strategy Binding
<!-- integration-branch: main -->
## Completeness Strictness Binding
<!-- team-size: >1 -->
<!-- enforce-review: yes -->
<!-- completeness-strictness: auto -->
MD
cat > "$APP/src/interactive.py" <<'PY'
def execute_action(key):
    return dispatch_external_mutation(key)
PY
cat > "$APP/src/background_worker.py" <<'PY'
def run_sweep():
    return dispatch_external_mutation(None)
PY
git -C "$APP" add . && git -C "$APP" commit -q -m "app init"
git -C "$APP" checkout -q -b impl/fix/TKT-500
printf '# updated\ndef execute_action(key):\n    return dispatch_external_mutation(key)\n' > "$APP/src/interactive.py"
git -C "$APP" commit -am "update interactive" -q
APP_SHA="$(git -C "$APP" rev-parse HEAD)"

printf 'id: TKT-500\ntier: Medium\nstatus: in-review\n' > "$SAT/specs/TKT-500/metadata.yaml"
cat > "$SAT/specs/TKT-500/problem.md" <<'MD'
# TKT-500
## Acceptance Criteria
- [ ] AC-1: At-most-once external mutation across retries
## Out of Scope
- `src/background_worker.py` background sweep excluded
MD
cat > "$SAT/specs/TKT-500/spec.md" <<'MD'
# Spec TKT-500
### Pillar 4: Data & Audit Fidelity
Active -- guards irreversible external mutation (CP-12).
### Pillar 6: Security Boundary Posture
Dormant -- not triggered.
### Files Affected
| File | Action |
|---|---|
| `app-repo:src/interactive.py` | Modify |
MD
cat > "$SAT/specs/TKT-500/evidence.yaml" <<YAML
ticket: TKT-500
stage: review
head_sha: $APP_SHA
claims:
  - id: CLM-001
    kind: boundary_contract
    criticality: load_bearing
    status: observed
    statement: interactive handler calls dispatch_external_mutation
    proof:
      ref: app-repo:src/interactive.py:2-3
      symbols: [execute_action, dispatch_external_mutation]
      anchor_substring: dispatch_external_mutation(key)
receipts:
  - kind: test_suite
    repo: app-repo
    command: pytest
    head_sha: $APP_SHA
    exit_code: 0
YAML
git -C "$SAT" add . && git -C "$SAT" commit -q -m "sat init"

# 2A. Missing absence proof on active Pillar 4 boundary -> HALT in team>1 mode, ESCALATE via --strictness escalate
out2a_h="$(run_gate 1 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'HALT missing_shared_invariant_absence_proof' <<<"$out2a_h"
out2a_e="$(run_gate 2 --root "$SAT" --code-root "$APP" --stage review --strictness escalate TKT-500)"
grep -q 'ESCALATE missing_shared_invariant_absence_proof' <<<"$out2a_e"

# 2B. Incomplete absence proof omits sibling background_worker.py -> HALT falsified_absence across --code-root!
cat > "$SAT/specs/TKT-500/evidence.yaml" <<YAML
ticket: TKT-500
stage: review
head_sha: $APP_SHA
claims:
  - id: CLM-001
    kind: boundary_contract
    criticality: load_bearing
    status: observed
    statement: interactive handler calls dispatch_external_mutation
    proof:
      ref: app-repo:src/interactive.py:2-3
      symbols: [execute_action, dispatch_external_mutation]
      anchor_substring: dispatch_external_mutation(key)
  - id: CLM-002
    kind: absence
    criticality: load_bearing
    status: observed
    statement: Only interactive.py calls dispatch_external_mutation
    proof:
      search_pattern: dispatch_external_mutation
      scope: app-repo:src/
      expected_files: [app-repo:src/interactive.py]
receipts:
  - kind: test_suite
    repo: app-repo
    command: pytest
    head_sha: $APP_SHA
    exit_code: 0
YAML
out2b="$(run_gate 1 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'HALT falsified_absence CLM-002.*app-repo:src/background_worker.py' <<<"$out2b"

# 2C. Complete absence proof (both callers listed) + valid satellite observed ref & HEAD receipt -> PROCEED!
sed -i 's|expected_files: \[app-repo:src/interactive.py\]|expected_files: [app-repo:src/interactive.py, app-repo:src/background_worker.py]|' "$SAT/specs/TKT-500/evidence.yaml"
out2c="$(run_gate 0 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'PASS observed_proof CLM-001' <<<"$out2c"
grep -q 'PASS absence_proof CLM-002' <<<"$out2c"
grep -q 'PASS test_receipt' <<<"$out2c"
grep -q '^decision=PROCEED ' <<<"$out2c"

# 2D. Modifying a file declared Out of Scope triggers out_of_scope_shared_surface
echo "# touched background" >> "$APP/src/background_worker.py"
out2d="$(run_gate 1 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'HALT out_of_scope_shared_surface' <<<"$out2d"
git -C "$APP" checkout -- src/background_worker.py

# --- 3. Structured Review Anomaly Disposition & Banned Rationalizations ---
# 3A. Prose eventual-heal excuse in blocking=0 cycle -> HALT in team>1, ESCALATE in solo
cat > "$SAT/specs/TKT-500/submission.md" <<'MD'
# Submission TKT-500
## Discussion
### Adversarial Lens
Stale flag race exists, but the next periodic sweep reconciles both flags consistently.
<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-20T00:00:00Z -->
MD
out3a_h="$(run_gate 1 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'HALT reviewer_rationalized_defect' <<<"$out3a_h"
out3a_e="$(run_gate 2 --root "$SAT" --code-root "$APP" --stage review --strictness escalate TKT-500)"
grep -q 'ESCALATE reviewer_rationalized_defect' <<<"$out3a_e"

# 3B. Structured BLOCKING anomaly row inside blocking=0 cycle -> ALWAYS HALT (even with --strictness escalate)
cat > "$SAT/specs/TKT-500/submission.md" <<'MD'
# Submission TKT-500
## Discussion
### Adversarial Lens
| Anomaly | Location | Disposition | Basis |
|---|---|---|---|
| Post-lock stale flag write | `src/interactive.py:2` | BLOCKING | Reproducible race |
<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-20T00:00:00Z -->
MD
out3b="$(run_gate 1 --root "$SAT" --code-root "$APP" --stage review --strictness escalate TKT-500)"
grep -q 'HALT blocking_anomaly_in_approve' <<<"$out3b"

# 3C. Clean PROVEN_SAFE row with file:line invariant proof -> PROCEED
cat > "$SAT/specs/TKT-500/submission.md" <<'MD'
# Submission TKT-500
## Discussion
### Adversarial Lens
| Anomaly | Location | Disposition | Basis |
|---|---|---|---|
| Re-checked locked row | `src/interactive.py:2` | PROVEN_SAFE | Verified predicate re-evaluated under row lock at src/interactive.py:2 |
<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-20T00:00:00Z -->
MD
out3c="$(run_gate 0 --root "$SAT" --code-root "$APP" --stage review TKT-500)"
grep -q 'PASS review_anomalies' <<<"$out3c"
grep -q '^decision=PROCEED ' <<<"$out3c"

echo "PASS: test-completeness-gates (all scenarios)"
