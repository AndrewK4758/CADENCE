#!/usr/bin/env bash
# Offline regression checks for verify-facts.sh --trace (Option 2A).
# Sourced or executed directly from tests/run-cadence-tests.sh.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERIFY_FACTS="$ROOT/skills/cadence-spec/verify-facts.sh"
DOCTOR="$ROOT/skills/cadence-doctor/doctor.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$TMP" >/dev/null
mkdir -p "$TMP/docs/policies"
cat > "$TMP/docs/policies/observability-patterns.md" <<'MD'
# Observability Patterns
UNSOUND_CONDITION DELTA_AUDIT_GAP RULE_DIVERGENCE BOUNDARY_FAULT
MD
: > "$TMP/src/legacy.py"
git -C "$TMP" add docs/policies/observability-patterns.md src/legacy.py
git -C "$TMP" commit -q -m "add observability docs and legacy helper"

# Cut an implementation branch off trunk with ACME-202 (High, in-progress)
git -C "$TMP" checkout -q -b impl/feature/ACME-202
git -C "$TMP" rm -q src/legacy.py
mkdir -p "$TMP/specs/ACME-202" "$TMP/tests"
cat > "$TMP/specs/ACME-202/metadata.yaml" <<'YAML'
id: ACME-202
tier: High
status: in-progress
actual_effort: 0m
YAML
cat > "$TMP/specs/ACME-202/problem.md" <<'MD'
# Problem: ACME-202
## Acceptance Criteria
- [ ] **AC-1:** Validate batch totals cleanly
- [ ] **AC-2:** Emit telemetry when validation fails
MD
cat > "$TMP/specs/ACME-202/decisions.md" <<'MD'
# Decisions: ACME-202
Gate 1 ruling: OQ-1 -- agree -- fail closed on None payload
MD
cat > "$TMP/specs/ACME-202/spec.md" <<'MD'
# Spec: ACME-202
## CHORD Analysis
#### AC-1: Validate batch totals
#### AC-2: Emit telemetry
## Observability Seams
### Prior Production Findings
| PROD-1 | DELTA_AUDIT_GAP | Outcomes | Template sample |
### Seam Specification
| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-2 | Conditions | UNSOUND_CONDITION | batch.validate.precondition_violated | Triggered when payload is None | Critical |
- BOUNDARY_FAULT: Dormant — not triggered
### Baseline Definitions
## Existing Code Analysis
### Files Affected
| File | Layer/Module | Change Type | Description |
|---|---|---|---|
| `src/beta.py` | Domain | Add | Add batch validator |
| `src/alpha.py` | Domain | Modify | Call batch validator |
| `src/legacy.py` | Domain | Delete | Remove obsolete helper |
## Risks and Open Questions
### Open Questions
**Gate 1 rulings:** required -- one ruling line per OQ in decisions.md.
- [x] **OQ-1:** Reject empty payload?
MD
cat > "$TMP/specs/ACME-202/test-plan.md" <<'MD'
# Test Plan: ACME-202
## Acceptance Criteria Coverage
| AC # | Acceptance Criterion | CHORD Source | Feature | Scenarios | Level |
|---|---|---|---|---|---|
| AC-1 | Validate batch totals | spec.md AC-1 | Feature 1 | S-1.1, S-1.10 | Unit |
| AC-2 | Emit telemetry | spec.md AC-2 | Feature 2 | OS-2.1 | Unit |
## BDD Features
```gherkin
Feature: Batch totals
  Scenario: S-1.1 -- Non-empty batch succeeds
    Given valid items
  Scenario: S-1.10 -- Empty batch fails closed
    Given no items
  Scenario: OS-2.1 -- Invalid payload emits UNSOUND_CONDITION
    When payload is None
```
MD

cat > "$TMP/src/beta.py" <<'PY'
def validate_batch(payload):
    if payload is None:
        raise RuntimeError("UNSOUND_CONDITION: null payload")
    return len(payload)
PY
printf '\n# modified for ACME-202\n' >> "$TMP/src/alpha.py"
cat > "$TMP/tests/test_beta.py" <<'PY'
# ACME-202 S-1.1, S-1.10
# ACME-202 OS-2.1
def test_validate():
    assert True
PY

# 1. Clean Medium/High --trace pass
out="$(bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-202)"
[[ "$out" == *"PASS scenario S-1.1"* ]]
[[ "$out" == *"PASS scenario S-1.10"* ]]
[[ "$out" == *"PASS scenario OS-2.1"* ]]
[[ "$out" == *"PASS seam UNSOUND_CONDITION"* ]]
[[ "$out" == *"PASS files-affected Add src/beta.py"* ]]
[[ "$out" == *"PASS files-affected Modify src/alpha.py"* ]]
[[ "$out" == *"PASS files-affected Delete src/legacy.py"* ]]
[[ "$out" == *"PASS ac-coverage AC-1"* ]]
[[ "$out" == *"PASS ac-coverage AC-2"* ]]
[[ "$out" == *"fail=0"* ]]

# 2. doctor.sh --ticket runs --trace for in-progress ACME-202, skips pre-impl ACME-201
doc_202="$(bash "$DOCTOR" --root "$TMP" --ticket ACME-202 2>&1 || true)"
[[ "$doc_202" == *"PASS  verify-facts --trace (ACME-202)"* ]]
doc_201="$(bash "$DOCTOR" --root "$TMP" --ticket ACME-201 2>&1 || true)"
[[ "$doc_201" == *"SKIP  verify-facts --trace (ACME-201) (status=spec-in-review, pre-implementation)"* ]]

# 3. Token boundary negative test: S-1.10 must NOT satisfy S-1.1
sed -i 's/S-1.1, S-1.10/S-1.10/' "$TMP/tests/test_beta.py"
set +e
bad_s1="$(bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-202 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ "$bad_s1" == *"FAIL scenario S-1.1 "* ]]
[[ "$bad_s1" == *"PASS scenario S-1.10"* ]]
[[ "$bad_s1" == *"FAIL ac-coverage AC-1"* ]]
sed -i 's/S-1.10/S-1.1, S-1.10/' "$TMP/tests/test_beta.py"

# 3b. Identifier-encoded C5 name also traces (e.g. def test_acme_202_s_1_1)
cat > "$TMP/tests/test_beta.py" <<'PY'
# ACME-202 S-1.10
# ACME-202 OS-2.1
def test_acme_202_s_1_1():
    assert True
PY
bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-202 | grep -q "PASS scenario S-1.1 -- tests/test_beta.py:3"
cat > "$TMP/tests/test_beta.py" <<'PY'
# ACME-202 S-1.1, S-1.10
# ACME-202 OS-2.1
def test_validate():
    assert True
PY

# 4. Negative test: docs/ observability-patterns.md must NOT satisfy missing code seam
sed -i 's/UNSOUND_CONDITION/NOOP_ERR/' "$TMP/src/beta.py"
set +e
bad_seam="$(bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-202 2>&1)"
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ "$bad_seam" == *"FAIL seam UNSOUND_CONDITION"* ]]
sed -i 's/NOOP_ERR/UNSOUND_CONDITION/' "$TMP/src/beta.py"

# 5. Negative test: Delete file still exists on disk -> FAIL
: > "$TMP/src/legacy.py"
! bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-202 >/dev/null 2>&1
rm -f "$TMP/src/legacy.py"

# 6. Low-tier test ACME-203 (in-review, no spec.md)
mkdir -p "$TMP/specs/ACME-203"
cat > "$TMP/specs/ACME-203/metadata.yaml" <<'YAML'
id: ACME-203
tier: "Low" # trimmed comment check
status: in-review
YAML
cat > "$TMP/specs/ACME-203/problem.md" <<'MD'
# Problem: ACME-203
## Acceptance Criteria
- [ ] **AC-1:** Reject negative quantity
- [ ] **AC-2:** Return HTTP 400
MD
cat > "$TMP/tests/test_low.py" <<'PY'
# ACME-203 AC-1, AC-2
def test_low(): pass
PY
bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-203 | grep -q "PASS scenario AC-2"
doc_203="$(bash "$DOCTOR" --root "$TMP" --ticket ACME-203 2>&1 || true)"
[[ "$doc_203" == *"PASS  verify-facts --trace (ACME-203)"* ]]
sed -i 's/AC-1, AC-2/AC-1/' "$TMP/tests/test_low.py"
! bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-203 >/dev/null 2>&1

# 7. Trivial exempt & fail-closed malformed/empty tier
bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-103 | grep -q "PASS trace exempt (tier=trivial)"
mkdir -p "$TMP/specs/ACME-204"
printf 'id: ACME-204\ntier: ""\nstatus: in-review\n' > "$TMP/specs/ACME-204/metadata.yaml"
! bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-204 >/dev/null 2>&1
printf 'id: ACME-204\ntier: bogus\nstatus: in-review\n' > "$TMP/specs/ACME-204/metadata.yaml"
! bash "$VERIFY_FACTS" --root "$TMP" --trace ACME-204 >/dev/null 2>&1

# 8. Legacy archive backward-compat without sentinel vs --strict
mkdir -p "$TMP/archive/OLD-10"
printf 'id: OLD-10\ntier: Medium\nstatus: archived\n' > "$TMP/archive/OLD-10/metadata.yaml"
printf '# Old Spec\n' > "$TMP/archive/OLD-10/spec.md"
cat > "$TMP/archive/OLD-10/test-plan.md" <<'MD'
```gherkin
  Scenario: S-1.1 -- Missing legacy tag
```
MD
bash "$VERIFY_FACTS" --root "$TMP" --trace OLD-10 | grep -q "WARN scenario S-1.1"
! bash "$VERIFY_FACTS" --root "$TMP" --strict --trace OLD-10 >/dev/null 2>&1
