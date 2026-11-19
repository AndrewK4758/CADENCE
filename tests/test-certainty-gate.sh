#!/usr/bin/env bash
# Offline regression suite (T10) for /cadence-certainty hybrid certainty-gate.sh.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
GATE="$ROOT/skills/cadence-certainty/certainty-gate.sh"
TMP="$(mktemp -d)"
LOG_TMP="$(mktemp)"
trap 'rm -rf "$TMP" "$LOG_TMP"' EXIT

# Provide co-located sibling sidecars in a temporary skills tree or pass via ROOT?
# certainty_gate.py discovers siblings from SELF_DIR.parent (ROOT/skills/), so running
# $GATE directly against --root $TMP exercises both Layer 1 and Layer 2 cleanly.
bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$TMP" >/dev/null
git -C "$TMP" checkout -q -b impl/feat/ACME-CERT
HEAD_SHA="$(git -C "$TMP" rev-parse HEAD)"

run_gate() {
  local expected_rc="$1"; shift
  local rc=0 out=""
  out="$(bash "$GATE" --root "$TMP" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "FAIL: expected exit $expected_rc, got $rc for args: $*" >&2
    echo "$out" >&2
    exit 1
  fi
  printf '%s\n' "$out"
}

# 1. Trivial tier exempt -> exit 0
out1="$(run_gate 0 ACME-103)"
grep -q '^decision=PROCEED tier=trivial stage=exempt grade=EXEMPT' <<<"$out1"

# 2. Clean Layer 1+2 spec manifest -> exit 0
cat > "$TMP/specs/ACME-201/evidence.yaml" <<YAML
ticket: ACME-201
stage: spec
head_sha: $HEAD_SHA
claims:
  - id: CLM-001
    kind: behavior
    criticality: load_bearing
    status: observed
    statement: compute_total returns len(items)
    proof:
      ref: src/alpha.py:1-2
      symbols: [compute_total]
      anchor_substring: return len(items)
  - id: CLM-002
    kind: absence
    criticality: supporting
    status: observed
    statement: No eval calls exist under src
    proof:
      search_pattern: 'eval\('
      scope: src/
      expected_files: []
  - id: CLM-003
    kind: invariant
    criticality: supporting
    status: inferred
    statement: compute_total is pure
    premises: [CLM-001]
YAML
echo "Gate 1 ruling: unknowns -- agree -- covered in spec" >> "$TMP/specs/ACME-201/decisions.md"
out2="$(run_gate 0 --base trunk --stage spec ACME-201)"
grep -q '^decision=PROCEED tier=high stage=spec grade=VERIFIED layer=1+2 halt=0 escalate=0' <<<"$out2"

# 3. Hallucinated anchor_substring -> exit 1 HALT
sed -i 's/return len(items)/return nonexistent_magic()/' "$TMP/specs/ACME-201/evidence.yaml"
out3="$(run_gate 1 --base trunk --stage spec ACME-201)"
grep -q 'HALT anchor_mismatch CLM-001' <<<"$out3"
sed -i 's/return nonexistent_magic()/return len(items)/' "$TMP/specs/ACME-201/evidence.yaml"

# 4. Falsified absence claim -> exit 1 HALT
sed -i "s/search_pattern: 'eval\\\\('/search_pattern: compute_total/" "$TMP/specs/ACME-201/evidence.yaml"
out4="$(run_gate 1 --base trunk --stage spec ACME-201)"
grep -q 'HALT falsified_absence CLM-002' <<<"$out4"
sed -i "s/search_pattern: compute_total/search_pattern: 'eval\\\\('/" "$TMP/specs/ACME-201/evidence.yaml"

# 5. Deep inferred chain (>2 hops) -> exit 2 ESCALATE_HUMAN; cyclic DAG -> exit 1 HALT
cat >> "$TMP/specs/ACME-201/evidence.yaml" <<'YAML'
  - id: CLM-004
    kind: invariant
    criticality: supporting
    status: inferred
    statement: Hop 2
    premises: [CLM-003]
  - id: CLM-005
    kind: invariant
    criticality: supporting
    status: inferred
    statement: Hop 3 exceeds max depth
    premises: [CLM-004]
YAML
out5a="$(run_gate 2 --base trunk --stage spec ACME-201)"
grep -q 'ESCALATE inference_depth_exceeded CLM-005' <<<"$out5a"
sed -i 's/premises: \[CLM-001\]/premises: [CLM-005]/' "$TMP/specs/ACME-201/evidence.yaml"
out5b="$(run_gate 1 --base trunk --stage spec ACME-201)"
grep -q 'HALT cyclic_inference' <<<"$out5b"
rm -f "$TMP/specs/ACME-201/evidence.yaml"

# 6. Unanswered probe (ACME-120) -> exit 2 ESCALATE_HUMAN
out6="$(run_gate 2 --stage spec ACME-120)"
grep -q 'ESCALATE unanswered_probes problem.md' <<<"$out6"

# 7. Unmapped UNKNOWN in design-options.md -> exit 2, cleared after human ruling in decisions.md
mkdir -p "$TMP/specs/ACME-202"
printf 'id: ACME-202\ntier: High\nstatus: spec-in-review\n' > "$TMP/specs/ACME-202/metadata.yaml"
printf '# ACME-202\n## Acceptance Criteria\n- [ ] AC-1 handled\n' > "$TMP/specs/ACME-202/problem.md"
cp "$TMP/specs/ACME-201/design-options.md" "$TMP/specs/ACME-202/design-options.md"
cp "$TMP/specs/ACME-201/spec.md" "$TMP/specs/ACME-202/spec.md"
sed -i 's/ACME-201/ACME-202/g' "$TMP/specs/ACME-202/spec.md"
out7a="$(run_gate 2 --base trunk --stage spec ACME-202)"
grep -q 'ESCALATE unmapped_unknowns spec.md' <<<"$out7a"
printf 'Gate 1 ruling: unknowns -- agree -- reviewed unknown modes\n' > "$TMP/specs/ACME-202/decisions.md"
out7b="$(run_gate 0 --base trunk --stage spec ACME-202)"
grep -q '^decision=PROCEED ' <<<"$out7b"

# 8. Undeclared production file modified outside Files Affected -> exit 2 ESCALATE_HUMAN
printf 'def extra(): return 1\n' > "$TMP/src/undeclared_beta.py"
out8="$(run_gate 2 --base trunk --stage implement ACME-202)"
grep -q 'ESCALATE undeclared_blast_radius git-diff' <<<"$out8"
rm -f "$TMP/src/undeclared_beta.py"

# 9. Dormant Security pillar contradicted by auth/concurrency diff -> exit 1 HALT
cat > "$TMP/src/alpha.py" <<'PY'
import fcntl
def verify_jwt_session(items):
    fcntl.flock(0, fcntl.LOCK_EX)
    return len(items)
PY
out9="$(run_gate 1 --base trunk --stage review ACME-202)"
grep -q 'HALT dormant_security_contradicted spec.md' <<<"$out9"
git -C "$TMP" checkout -- src/alpha.py

# 10. Stale receipt -> exit 1 HALT; fresh HEAD receipt + SHA-256 -> exit 0; cycle oscillation -> exit 2
cat > "$TMP/specs/ACME-202/evidence.yaml" <<'YAML'
ticket: ACME-202
stage: implement
head_sha: deadbeef1234
claims: []
receipts:
  - kind: test_suite
    command: pytest
    head_sha: deadbeef1234
    exit_code: 0
YAML
out10a="$(run_gate 1 --base trunk --stage implement ACME-202)"
grep -q 'HALT stale_test_receipt' <<<"$out10a"

LOG_FILE="$LOG_TMP"
printf '1 | PASS S-1.1\n' > "$LOG_FILE"
LOG_SHA="$(sha256sum "$LOG_FILE" | awk '{print $1}')"
cat > "$TMP/specs/ACME-202/evidence.yaml" <<YAML
ticket: ACME-202
stage: implement
head_sha: $HEAD_SHA
claims: []
receipts:
  - kind: test_suite
    command: pytest
    head_sha: $HEAD_SHA
    exit_code: 0
    raw_log: $LOG_FILE
    raw_log_sha256: $LOG_SHA
    scenarios_observed_passing: [S-1.1]
YAML
out10b="$(run_gate 0 --base trunk --stage implement ACME-202)"
grep -q '^decision=PROCEED tier=high stage=implement grade=VERIFIED layer=1+2' <<<"$out10b"

out10c="$(run_gate 2 --base trunk --stage review ACME-111)"
grep -q 'ESCALATE cycle_oscillation submission.md' <<<"$out10c"

# 11. Bold Failure modes (UNKNOWN) + Additional Pillars #### boundary + Pillar 6 Security Boundary Posture
mkdir -p "$TMP/specs/ACME-203"
printf 'id: ACME-203\ntier: High\nstatus: spec-in-review\n' > "$TMP/specs/ACME-203/metadata.yaml"
printf '# ACME-203\n## Acceptance Criteria\n- [ ] AC-1\n' > "$TMP/specs/ACME-203/problem.md"
printf '## Option A\n- **Failure modes (UNKNOWN):** Retry backoff race\n' > "$TMP/specs/ACME-203/design-options.md"
sed 's/ACME-202/ACME-203/g' "$TMP/specs/ACME-202/spec.md" | sed '/Security Boundary Posture/{n;s/.*/Active -- validated./}' > "$TMP/specs/ACME-203/spec.md"
out11a="$(run_gate 2 --base trunk --stage spec ACME-203)"
grep -q 'ESCALATE unmapped_unknowns spec.md' <<<"$out11a"
cat > "$TMP/src/alpha.py" <<'PY'
def verify_jwt_session(token):
    return bool(token)
PY
printf '\n### Additional Pillars\n\n#### Custom Non-Security Pillar\nDormant -- not applicable.\n\n#### Security Boundary Posture\nActive -- auth verified.\n' >> "$TMP/specs/ACME-203/spec.md"
out11b="$(run_gate 0 --base trunk --stage review ACME-203)"
grep -q '^decision=PROCEED ' <<<"$out11b"
sed -i '/^#### Security Boundary Posture/{n;s/.*/Not triggered/}' "$TMP/specs/ACME-203/spec.md"
out11c="$(run_gate 1 --base trunk --stage review ACME-203)"
grep -q 'HALT dormant_security_contradicted spec.md' <<<"$out11c"
git -C "$TMP" checkout -- src/alpha.py

echo "PASS: test-certainty-gate (all 11 scenarios)"
