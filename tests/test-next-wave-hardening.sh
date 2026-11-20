#!/usr/bin/env bash
# Offline regression suite (T14) for Next-Wave CADENCE Hardening:
#   1. Rework-delta SHA bookmarking (read_state.py + breaker-trigger.sh)
#   2. Cross-repo verify-facts.sh --code-root parity (facts, --rulings, --trace, certainty-gate)
#   3. Chaos matrix applicability enforcement (verify-spec.sh / verify-spec-invariants.sh)
#   4. /cadence-upgrade org-fold support for #completeness-strictness-binding
#   5. Test-diff anti-tautology heuristics (MOCK_ONLY_ASSERTION, SELF_MOCKED_SUT)
#   6. Physical cross-model gate attestation (read_state.py + retro_scan.py)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
READ_STATE="$ROOT/skills/cadence-define/scripts/read_state.py"
BREAKER="$ROOT/skills/cadence-review/breaker-trigger.sh"
VFACTS="$ROOT/skills/cadence-spec/verify-facts.sh"
VSPEC="$ROOT/skills/cadence-spec/verify-spec.sh"
CERTAINTY="$ROOT/skills/cadence-certainty/certainty-gate.sh"
RETRO="$ROOT/skills/cadence-retro/retro_scan.py"
ORGFOLD="$ROOT/skills/cadence-upgrade/upgrade-orgfold.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mk_git() {
  local d="$1" br="${2:-main}"
  mkdir -p "$d"
  git -C "$d" init -q -b "$br"
  git -C "$d" config user.email ci@example.test
  git -C "$d" config user.name CI
}

# ==============================================================================
# 1. Rework-delta SHA bookmarking & model attestation in read_state + breaker-trigger
# ==============================================================================
FIX="$TMP/rework-fix"
bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$FIX" >/dev/null
git -C "$FIX" checkout -q -b impl/fix/ACME-RWK
printf 'def run_step():\n    return 1\n' > "$FIX/src/step.py"
git -C "$FIX" add src/step.py && git -C "$FIX" commit -q -m "cycle 1 commit"
C1_SHA="$(git -C "$FIX" rev-parse --short HEAD)"
printf 'def run_step():\n    return 2\n' > "$FIX/src/step.py"
git -C "$FIX" commit -aq -m "cycle 2 rework fix"

mkdir -p "$FIX/specs/ACME-RWK"
printf 'id: ACME-RWK\ntier: Low\nstatus: in-review\n' > "$FIX/specs/ACME-RWK/metadata.yaml"
cat > "$FIX/specs/ACME-RWK/submission.md" <<MD
# Submission ACME-RWK
## Discussion
<!-- cadence-run:cycle n=1 phase=code-review blocking=1 nonblocking=0 at=2026-11-20T10:00:00Z sha=$C1_SHA implementer_model=model-alpha reviewer_model=model-beta breaker_model=model-gamma -->
MD

rs_out="$(python3 "$READ_STATE" ACME-RWK --repo-root "$FIX")"
grep -q "ledger_last=n=1,phase=code-review,blocking=1,nonblocking=0" <<<"$rs_out"
grep -q "ledger_last_sha=$C1_SHA" <<<"$rs_out"
grep -q "ledger_last_models=implementer:model-alpha,reviewer:model-beta,breaker:model-gamma" <<<"$rs_out"

bt_out="$(bash "$BREAKER" --root "$FIX" --base trunk ACME-RWK)"
grep -q "decision=TRIGGER tier=low mode=rework reason=rework-mandatory rework_base=$C1_SHA" <<<"$bt_out"
grep -q "files=.*src/step.py" <<<"$bt_out"

sed -i "s/sha=$C1_SHA/sha=deadbeef1234/" "$FIX/specs/ACME-RWK/submission.md"
bt_bad="$(bash "$BREAKER" --root "$FIX" --base trunk ACME-RWK)"
grep -q "rework_base=unreachable:deadbeef1234" <<<"$bt_bad"

# ==============================================================================
# 2. Cross-repo verify-facts.sh --code-root parity (facts, --rulings, --trace, certainty-gate)
# ==============================================================================
SAT="$TMP/sat-gov"
RA="$TMP/repoA"
RB="$TMP/repoB"
mk_git "$SAT" main
mk_git "$RA" main
mk_git "$RB" develop

mkdir -p "$SAT/docs/agentic-sdlc" "$SAT/specs/TKT-900" "$RA/src" "$RA/tests" "$RB/src"
cat > "$SAT/docs/agentic-sdlc/CADENCE_ORG.md" <<'MD'
## Branch-Strategy Binding
<!-- integration-branch: main -->
## Completeness Strictness Binding
<!-- team-size: >1 -->
<!-- enforce-review: yes -->
<!-- completeness-strictness: auto -->
MD

cat > "$RA/src/handler.py" <<'PY'
def execute_order(key):
    return key
PY
cat > "$RA/src/helper.py" <<'PY'
def verify_token(tok):
    return bool(tok)
PY
cat > "$RA/src/obsolete.py" <<'PY'
# legacy
PY
git -C "$RA" add . && git -C "$RA" commit -q -m "ra base"
RA_BASE="$(git -C "$RA" rev-parse --short HEAD)"

cat > "$RB/src/worker.py" <<'PY'
def sweep_pending():
    return 0
PY
git -C "$RB" add . && git -C "$RB" commit -q -m "rb base"
RB_BASE="$(git -C "$RB" rev-parse --short HEAD)"

cat > "$SAT/specs/TKT-900/metadata.yaml" <<'YAML'
id: TKT-900
tier: Medium
status: in-review
YAML
cat > "$SAT/specs/TKT-900/problem.md" <<'MD'
# TKT-900
## Acceptance Criteria
- [ ] **AC-1:** Order execution validates key across services
MD
cat > "$SAT/specs/TKT-900/spec.md" <<'MD'
# Spec TKT-900
## CHORD Analysis
#### AC-1: Order execution
## Observability Seams
### Seam Specification
| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-1 | Conditions | UNSOUND_CONDITION | order.key.missing | Key absent | High |
## Existing Code Analysis
Inspect `repoA:src/handler.py:1-2` (`execute_order`) and `repoB:src/worker.py:1-2` (`sweep_pending`).
### Files Affected
| File | Action |
|---|---|
| `repoA:src/handler.py` | Modify |
| `repoA:src/added.py` | Add |
| `repoA:src/obsolete.py` | Delete |
| `repoB:src/worker.py` | Modify |
## Risks and Open Questions
### Open Questions
**Gate 1 rulings:** required
- [x] **OQ-1:** Confirm token verification boundary?
MD
cat > "$SAT/specs/TKT-900/decisions.md" <<'MD'
# Decisions TKT-900
Gate 1 ruling: OQ-1 -- agree -- checked `repoA:src/helper.py:1` independently
MD
cat > "$SAT/specs/TKT-900/test-plan.md" <<'MD'
# Test Plan TKT-900
## Acceptance Criteria Coverage
| AC | Scenarios |
|---|---|
| AC-1 | S-1.1 |
## BDD Features
```gherkin
Feature: Order execution
  Scenario: S-1.1 -- Validates order key
    Given a request
```
MD
git -C "$SAT" add . && git -C "$SAT" commit -q -m "sat init"

# 2A. Facts & --rulings pass against base commits of repoA + repoB
vf_ok="$(bash "$VFACTS" --root "$SAT" --code-root "$RA" --code-root "$RB" TKT-900)"
grep -q "PASS files-affected Modify repoA:src/handler.py" <<<"$vf_ok"
grep -q "PASS files-affected Add repoA:src/added.py" <<<"$vf_ok"
grep -q "PASS files-affected Delete repoA:src/obsolete.py" <<<"$vf_ok"
grep -q "PASS files-affected Modify repoB:src/worker.py" <<<"$vf_ok"
grep -q "PASS citation repoA:src/handler.py:1-2" <<<"$vf_ok"
grep -q "PASS citation repoB:src/worker.py:1-2" <<<"$vf_ok"
grep -q "fail=0" <<<"$vf_ok"

vr_ok="$(bash "$VFACTS" --root "$SAT" --code-root "$RA" --code-root "$RB" --rulings TKT-900)"
grep -q "RULING gate=1 item=OQ-1 value=agree label=examined" <<<"$vr_ok"

# 2B. Broken satellite citation fails verify-facts AND halts certainty-gate via forwarded --code-root
cp "$SAT/specs/TKT-900/spec.md" "$SAT/specs/TKT-900/spec.bak"
sed -i 's/repoB:src\/worker.py:1-2/repoB:src\/worker.py:99/' "$SAT/specs/TKT-900/spec.md"
! bash "$VFACTS" --root "$SAT" --code-root "$RA" --code-root "$RB" TKT-900 >/dev/null 2>&1
rc_cg=0
cg_out="$(bash "$CERTAINTY" --root "$SAT" --code-root "$RA" --code-root "$RB" --stage spec TKT-900 2>&1)" || rc_cg=$?
[[ "$rc_cg" -eq 1 ]]
grep -q "HALT verify_facts_failed" <<<"$cg_out"
mv "$SAT/specs/TKT-900/spec.bak" "$SAT/specs/TKT-900/spec.md"

# 2C. Post-implementation --trace across repoA + repoB (plus multi-repo breaker rework_base)
git -C "$RA" checkout -q -b impl/feat/TKT-900
printf 'def execute_order(key):\n    return str(key)\n' > "$RA/src/handler.py"
printf 'def added_fn():\n    return 1\n' > "$RA/src/added.py"
git -C "$RA" rm -q src/obsolete.py
cat > "$RA/tests/test_order.py" <<'PY'
# TKT-900 S-1.1
def test_order_valid():
    assert True
PY
git -C "$RA" add . && git -C "$RA" commit -q -m "ra impl"

git -C "$RB" checkout -q -b impl/feat/TKT-900
printf 'def sweep_pending():\n    return "UNSOUND_CONDITION"\n' > "$RB/src/worker.py"
git -C "$RB" commit -aq -m "rb impl"

vt_ok="$(bash "$VFACTS" --root "$SAT" --code-root "$RA" --code-root "$RB" --trace TKT-900)"
grep -q "PASS files-affected Add repoA:src/added.py" <<<"$vt_ok"
grep -q "PASS files-affected Delete repoA:src/obsolete.py" <<<"$vt_ok"
grep -q "PASS scenario S-1.1 -- repoA:tests/test_order.py:1" <<<"$vt_ok"
grep -q "PASS seam UNSOUND_CONDITION -- repoB:src/worker.py:2" <<<"$vt_ok"
grep -q "fail=0" <<<"$vt_ok"

# Multi-repo rework_base bookmark resolution
printf '# Sub\n## Discussion\n<!-- cadence-run:cycle n=1 phase=code-review blocking=1 nonblocking=0 sha=repoA:%s,repoB:%s -->\n' "$RA_BASE" "$RB_BASE" > "$SAT/specs/TKT-900/submission.md"
bt_multi="$(bash "$BREAKER" --root "$SAT" --code-root "$RA" --code-root "$RB" TKT-900)"
grep -q "rework_base=repoA:${RA_BASE},repoB:${RB_BASE}" <<<"$bt_multi"

# Fail-closed on bad --code-root
! bash "$VFACTS" --root "$SAT" --code-root "$TMP/no-such-dir" TKT-900 >/dev/null 2>&1

# ==============================================================================
# 3. Chaos Matrix Applicability Enforcement (verify-spec.sh)
# ==============================================================================
CH="$TMP/chaos-fix"
bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$CH" >/dev/null
cat >> "$CH/specs/ACME-201/spec.md" <<'MD'

## Integration Changes
Dispatches an irreversible external mutation with retry on timeout, relies on an external deduplication TTL window, acquires a `SELECT ... FOR UPDATE` row lock before writeback, and preserves attempt identity across page reload during an in-flight mutation.
MD

rc_ch=0
ch_fail="$(bash "$VSPEC" --root "$CH" ACME-201 2>&1)" || rc_ch=$?
[[ "$rc_ch" -eq 1 ]]
grep -q "chaos_matrix_omission: CP-12" <<<"$ch_fail"
grep -q "chaos_matrix_omission: CP-13" <<<"$ch_fail"
grep -q "chaos_matrix_omission: CP-05" <<<"$ch_fail"
grep -q "chaos_matrix_omission: CP-14" <<<"$ch_fail"

cat >> "$CH/specs/ACME-201/test-plan.md" <<'MD'
  Scenario: S-1.2 -- Chaos coverage (CP-05, CP-12, CP-13)
    Given concurrent contention, post-commit ambiguous timeout, and expired external TTL
    Then local durable state preserves at-most-once execution
MD
printf '\n### Open Questions\n- [ ] **OQ-2:** Confirm CP-14 reload persistence mechanism\n' >> "$CH/specs/ACME-201/spec.md"
ch_pass="$(bash "$VSPEC" --root "$CH" ACME-201)"
grep -q "PASS  Chaos matrix applicability satisfied (CP-12, CP-13, CP-05, CP-14)" <<<"$ch_pass"

# Archive without coverage downgrades to WARN (exit 0)
mkdir -p "$CH/archive/ACME-OLD"
cp "$CH/specs/ACME-201/spec.md" "$CH/archive/ACME-OLD/spec.md"
sed -i '/OQ-2/d' "$CH/archive/ACME-OLD/spec.md"
cp "$CH/specs/ACME-201/test-plan.md" "$CH/archive/ACME-OLD/test-plan.md"
sed -i '/CP-05/d' "$CH/archive/ACME-OLD/test-plan.md"
ch_arch="$(bash "$VSPEC" --root "$CH" ACME-OLD)"
grep -q "WARN  chaos_matrix_omission: CP-12" <<<"$ch_arch"

# ==============================================================================
# 4. /cadence-upgrade org-fold support for #completeness-strictness-binding
# ==============================================================================
OF="$TMP/orgfold"
mkdir -p "$OF"
cat > "$OF/base.md" <<'MD'
# Org
## Branch-Strategy Binding
<!-- integration-branch: develop -->
<!-- bound-strategy: long-lived-feature-release -->

MD
cat > "$OF/live.md" <<'MD'
# Org
## Branch-Strategy Binding
<!-- integration-branch: main -->
<!-- bound-strategy: long-lived-feature-release -->

MD
cat > "$OF/src.md" <<'MD'
# Org
## Branch-Strategy Binding
<!-- integration-branch: develop -->
<!-- bound-strategy: long-lived-feature-release -->

## Completeness Strictness Binding
<!-- team-size: >1 -->
<!-- enforce-review: yes -->
<!-- completeness-strictness: auto -->
Default posture text v1.
MD

# 4A: Appending brand-new section onto pre-binding live CADENCE_ORG.md + stderr reminder
of_err4a="$(bash -c "set -euo pipefail; . '$ORGFOLD'; fold_one '$OF/base.md' '$OF/src.md' '$OF/live.md' '$OF/out4a.md'; echo RC=\$FOLD_RC" 2>&1)"
grep -q "RC=0" <<<"$of_err4a"
grep -q "org-fold appended new template section \[Completeness Strictness Binding\]" <<<"$of_err4a"
grep -q "org-fold NOTE -- verify \[Completeness Strictness Binding\] markers" <<<"$of_err4a"
grep -q "<!-- team-size: >1 -->" "$OF/out4a.md"
grep -q "<!-- integration-branch: main -->" "$OF/out4a.md"

# 4B: Prose update adjacent to customized solo markers preserves markers cleanly (RC=0)
cp "$OF/src.md" "$OF/base4b.md"
cat > "$OF/live4b.md" <<'MD'
# Org
## Branch-Strategy Binding
<!-- integration-branch: main -->
<!-- bound-strategy: long-lived-feature-release -->

## Completeness Strictness Binding
<!-- team-size: 1 -->
<!-- enforce-review: no -->
<!-- completeness-strictness: auto -->
Default posture text v1.
MD
cat > "$OF/src4b.md" <<'MD'
# Org
## Branch-Strategy Binding
<!-- integration-branch: develop -->
<!-- bound-strategy: long-lived-feature-release -->

## Completeness Strictness Binding
<!-- team-size: >1 -->
<!-- enforce-review: yes -->
<!-- completeness-strictness: auto -->
Updated posture text v2 with expanded guidance.
MD
of_rc4b="$(bash -c "set -euo pipefail; . '$ORGFOLD'; fold_one '$OF/base4b.md' '$OF/src4b.md' '$OF/live4b.md' '$OF/out4b.md'; echo RC=\$FOLD_RC" 2>&1)"
grep -q "RC=0" <<<"$of_rc4b"
grep -q "<!-- team-size: 1 -->" "$OF/out4b.md"
grep -q "<!-- enforce-review: no -->" "$OF/out4b.md"
grep -q "Updated posture text v2" "$OF/out4b.md"

# 4C: Genuine prose conflict still stages conflict (RC=1)
sed -i 's/Default posture text v1./Custom local prose text./' "$OF/live4b.md"
of_rc4c="$(bash -c "set -euo pipefail; . '$ORGFOLD'; fold_one '$OF/base4b.md' '$OF/src4b.md' '$OF/live4b.md' '$OF/out4c.md'; echo RC=\$FOLD_RC" 2>&1)"
grep -q "RC=1" <<<"$of_rc4c"

# ==============================================================================
# 5. Test-diff anti-tautology heuristics (offload_core + verify-facts --trace)
# ==============================================================================
TD="$TMP/test-diff-repo"
mk_git "$TD" main
mkdir -p "$TD/src" "$TD/tests" "$TD/specs/TKT-800"
printf 'def process_wallet_charge(amount):\n    return amount\n' > "$TD/src/billing.py"
printf 'id: TKT-800\ntier: Low\nstatus: in-review\n' > "$TD/specs/TKT-800/metadata.yaml"
printf '# TKT-800\n## Acceptance Criteria\n- [ ] AC-1: Settle charge once\n' > "$TD/specs/TKT-800/problem.md"
git -C "$TD" add . && git -C "$TD" commit -q -m "base"

git -C "$TD" checkout -q -b impl/fix/TKT-800
printf 'def process_wallet_charge(amount):\n    return {"status": "settled", "amount": amount}\n' > "$TD/src/billing.py"
cat > "$TD/tests/test_billing.py" <<'PY'
# TKT-800 AC-1
from unittest.mock import MagicMock, patch

def test_charge_mock_only():
    gw = MagicMock()
    with patch("src.billing.process_wallet_charge") as mocked:
        gw.send(10)
        gw.send.assert_called_once()

def test_charge_real_state():
    res = {"status": "settled"}
    assert res["status"] == "settled"
PY
git -C "$TD" add . && git -C "$TD" commit -q -m "tautology test"

python3 - "$ROOT" "$TD" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]) / "local-offload" / "mcp"))
import offload_core as oc

rows, flags, _ = oc.collect_git_diff_context("main...HEAD", pathlib.Path(sys.argv[2]))
assert any("MOCK_ONLY_ASSERTION: tests/test_billing.py (test_charge_mock_only)" in f for f in flags), flags
assert not any("test_charge_real_state" in f for f in flags), flags
assert any("SELF_MOCKED_SUT: tests/test_billing.py mocks/patches modified production symbol 'process_wallet_charge'" in f for f in flags), flags
PY

vt_hyg="$(bash "$VFACTS" --root "$TD" --base main --trace TKT-800)"
grep -q "WARN test-hygiene diff -- MOCK_ONLY_ASSERTION: tests/test_billing.py (test_charge_mock_only)" <<<"$vt_hyg"
grep -q "WARN test-hygiene diff -- SELF_MOCKED_SUT: tests/test_billing.py mocks/patches modified production symbol 'process_wallet_charge'" <<<"$vt_hyg"

# ==============================================================================
# 6. Physical cross-model gate attestation in retro_scan.py
# ==============================================================================
RT="$TMP/retro-att"
mkdir -p "$RT/archive/TKT-1" "$RT/archive/TKT-2" "$RT/archive/TKT-3"
printf 'id: TKT-1\ntier: High\nstatus: archived\narchived_at: 2026-11-01T00:00:00Z\n' > "$RT/archive/TKT-1/metadata.yaml"
printf '<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-01T00:00:00Z sha=aaa1111 implementer_model=model-a reviewer_model=model-b breaker_model=model-c -->\n' > "$RT/archive/TKT-1/submission.md"
printf '# Summary\n' > "$RT/archive/TKT-1/summary.md"

printf 'id: TKT-2\ntier: Medium\nstatus: archived\narchived_at: 2026-11-02T00:00:00Z\n' > "$RT/archive/TKT-2/metadata.yaml"
printf '<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-02T00:00:00Z sha=bbb2222 implementer_model=model-a reviewer_model=model-a -->\n' > "$RT/archive/TKT-2/submission.md"
printf '# Summary\n' > "$RT/archive/TKT-2/summary.md"

printf 'id: TKT-3\ntier: High\nstatus: archived\narchived_at: 2026-11-03T00:00:00Z\n' > "$RT/archive/TKT-3/metadata.yaml"
printf '<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-11-03T00:00:00Z -->\n' > "$RT/archive/TKT-3/submission.md"
printf '# Summary\n' > "$RT/archive/TKT-3/summary.md"

rt_out="$(python3 "$RETRO" --root "$RT")"
grep -q "model_attestation=independent:1,same_model:1,unattested_high:1" <<<"$rt_out"
python3 - "$RETRO" "$RT" <<'PY'
import json, subprocess, sys
data = json.loads(subprocess.check_output(["python3", sys.argv[1], "--root", sys.argv[2], "--json"], text=True))
assert data["independent_model_reviews"] == ["TKT-1"], data
assert data["same_model_reviews"] == ["TKT-2"], data
assert data["unattested_high_tier_reviews"] == ["TKT-3"], data
PY

echo "PASS: test-next-wave-hardening (all 6 wave-2 capabilities)"
