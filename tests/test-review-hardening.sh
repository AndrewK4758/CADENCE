#!/usr/bin/env bash
# Offline regression checks for Pre-Gate-1 Spec Challenger, zero-spec Cold Breaker,
# breaker-trigger.sh, expanded security-trigger signals, and multi-repo --code-root.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BREAKER="$ROOT/skills/cadence-review/breaker-trigger.sh"
SECURITY="$ROOT/skills/cadence-review/security-trigger.sh"
CERTAINTY="$ROOT/skills/cadence-certainty/certainty-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SAT="$TMP/sat-cadence"
bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$SAT" >/dev/null
git -C "$SAT" checkout -q -b impl/fix/PLAT-TEST

# 1. breaker-trigger.sh: Trivial SKIP & High TRIGGER
out_triv="$(bash "$BREAKER" --root "$SAT" ACME-103)"
[[ "$out_triv" == "decision=SKIP tier=trivial mode=exempt reason=trivial-tier-exempt" ]]
out_high="$(bash "$BREAKER" --root "$SAT" ACME-201)"
[[ "$out_high" == decision=TRIGGER\ tier=high*reason=high-tier-mandatory* ]]

# 2. breaker-trigger.sh: Medium docs-only SKIP vs code diff TRIGGER
mkdir -p "$SAT/specs/ACME-MED" "$SAT/docs"
printf 'id: ACME-MED\ntier: Medium\nstatus: in-review\n' > "$SAT/specs/ACME-MED/metadata.yaml"
echo "prose only" > "$SAT/docs/med-notes.md"
out_med_docs="$(bash "$BREAKER" --root "$SAT" --base trunk ACME-MED)"
[[ "$out_med_docs" == "decision=SKIP tier=medium mode=initial reason=docs-only-exempt" ]]
echo "export function plainSum(a: number, b: number) { return a + b; }" > "$SAT/src/plain.ts"
out_med_code="$(bash "$BREAKER" --root "$SAT" --base trunk ACME-MED)"
[[ "$out_med_code" == decision=TRIGGER\ tier=medium\ mode=initial\ reason=medium-tier-code-diff\ files=*src/plain.ts* ]]
rm -f "$SAT/src/plain.ts" "$SAT/docs/med-notes.md"

# 3. breaker-trigger.sh: Low benign SKIP vs behavioral signal TRIGGER & rework TRIGGER
mkdir -p "$SAT/specs/ACME-LOW"
printf 'id: ACME-LOW\ntier: Low\nstatus: in-review\n' > "$SAT/specs/ACME-LOW/metadata.yaml"
echo "export function formatLabel(s: string) { return s.trim(); }" > "$SAT/src/benign.ts"
out_low_skip="$(bash "$BREAKER" --root "$SAT" --base trunk ACME-LOW)"
[[ "$out_low_skip" == "decision=SKIP tier=low mode=initial reason=no-breaker-signals" ]]
printf 'export async function fetchStream(sig: AbortController) { await Promise.resolve(sig); }\n' > "$SAT/src/stream.ts"
out_low_trig="$(bash "$BREAKER" --root "$SAT" --base trunk ACME-LOW)"
[[ "$out_low_trig" == decision=TRIGGER\ tier=low\ mode=initial\ reason=low-tier-signal-match\ files=*src/stream.ts* ]]
rm -f "$SAT/src/stream.ts"
printf '<!-- cadence-run:cycle n=1 phase=code-review blocking=1 nonblocking=0 -->\nREQUEST CHANGES\n' > "$SAT/specs/ACME-LOW/submission.md"
out_rework="$(bash "$BREAKER" --root "$SAT" --base trunk ACME-LOW)"
[[ "$out_rework" == decision=TRIGGER\ tier=low\ mode=rework\ reason=rework-mandatory* ]]
rm -f "$SAT/src/benign.ts" "$SAT/specs/ACME-LOW/submission.md"

# 4. Multi-repo --code-root setup (repoA on main, repoB on develop)
REPO_A="$TMP/repoA"
REPO_B="$TMP/repoB"
for d_br in "$REPO_A:main" "$REPO_B:develop"; do
  dir="${d_br%%:*}"; br="${d_br##*:}"
  mkdir -p "$dir/src"
  git -C "$dir" init -q -b "$br"
  git -C "$dir" config user.email "ci@example.test"
  git -C "$dir" config user.name "CI"
  echo "export const ok = 1;" > "$dir/src/base.ts"
  git -C "$dir" add .
  git -C "$dir" commit -q -m "init"
done

git -C "$REPO_A" checkout -q -b feat/test
cat > "$REPO_A/src/redact.ts" <<'TS'
import Redis from "ioredis";
export async function scrubPii(r: Redis, ac: AbortController) {
  return { r, ac };
}
TS
git -C "$REPO_B" checkout -q -b feat/test
cat > "$REPO_B/docker-stack.yml" <<'YAML'
services:
  app:
    deploy:
      rollback_config:
        order: start-first
YAML

out_brk_multi="$(bash "$BREAKER" --root "$SAT" --code-root "$REPO_A" --code-root "$REPO_B" ACME-LOW)"
[[ "$out_brk_multi" == *"repoA:src/redact.ts"* ]]
[[ "$out_brk_multi" == *"repoB:docker-stack.yml"* ]]

out_sec_multi="$(bash "$SECURITY" --root "$SAT" --code-root "$REPO_A" --code-root "$REPO_B" ACME-LOW)"
[[ "$out_sec_multi" == decision=TRIGGER\ tier=low* ]]
[[ "$out_sec_multi" == *"concurrency"* ]]
[[ "$out_sec_multi" == *"secrets_crypto"* ]]
[[ "$out_sec_multi" == *"untrusted_exec"* ]]
[[ "$out_sec_multi" == *"repoA:src/redact.ts"* ]]
[[ "$out_sec_multi" == *"repoB:docker-stack.yml"* ]]

# 5. Fail-closed checks for bad tier, bad --code-root, bad --base
mkdir -p "$SAT/specs/ACME-BAD"
printf 'id: ACME-BAD\ntier: ""\n' > "$SAT/specs/ACME-BAD/metadata.yaml"
! bash "$BREAKER" --root "$SAT" ACME-BAD >/dev/null 2>&1
! bash "$BREAKER" --root "$SAT" --code-root "$TMP/does-not-exist" ACME-LOW >/dev/null 2>&1
! bash "$BREAKER" --root "$SAT" --code-root "$REPO_A" --base no-such-ref ACME-LOW >/dev/null 2>&1
! bash "$SECURITY" --root "$SAT" --code-root "$TMP/does-not-exist" ACME-LOW >/dev/null 2>&1

# 6. certainty-gate.sh --code-root: undeclared_blast_radius (exit 2) & dormant_security_contradicted (exit 1)
SAT_C="$TMP/sat-cert"
mkdir -p "$SAT_C/specs/PLAT-777"
git -C "$SAT_C" init -q -b main
git -C "$SAT_C" config user.email "ci@example.test"
git -C "$SAT_C" config user.name "CI"
cat > "$SAT_C/specs/PLAT-777/metadata.yaml" <<'YAML'
id: PLAT-777
tier: Medium
status: in-review
YAML
cat > "$SAT_C/specs/PLAT-777/spec.md" <<'MD'
# Spec
### Files Affected
| File | Action |
|---|---|
| `repoA:src/base.ts` | Modify |

### Pillar 6: Security Boundary Posture
Dormant -- not triggered.

**Gate 1 rulings:** not required
MD
git -C "$SAT_C" add .
git -C "$SAT_C" commit -q -m "sat init"

# Benign undeclared file triggers ESCALATE_HUMAN (rc=2) with undeclared_blast_radius
rm -f "$REPO_A/src/redact.ts"
echo "export const x = 2;" > "$REPO_A/src/extra.ts"
rc_esc=0
out_esc="$(bash "$CERTAINTY" --root "$SAT_C" --code-root "$REPO_A" --stage review PLAT-777 2>&1)" || rc_esc=$?
[[ "$rc_esc" -eq 2 ]]
[[ "$out_esc" == *"ESCALATE undeclared_blast_radius"* ]]
[[ "$out_esc" == *"src/extra.ts"* ]]

# Security-sensitive file under dormant Pillar 6 triggers HALT (rc=1)
echo "export function scrubSecretToken() { return ''; }" > "$REPO_A/src/extra.ts"
rc_halt=0
out_halt="$(bash "$CERTAINTY" --root "$SAT_C" --code-root "$REPO_A" --stage review PLAT-777 2>&1)" || rc_halt=$?
[[ "$rc_halt" -eq 1 ]]
[[ "$out_halt" == *"HALT dormant_security_contradicted"* ]]

# 7. Structural contracts across agents, completeness policy, and chaos catalog
test -s "$ROOT/agents/cadence-breaker/agent.md"
test -s "$ROOT/agents/cadence-spec-challenger/agent.md"
test -s "$ROOT/processes/docs/policies/completeness-invariants.md"
grep -q "DO NOT READ.*spec\.md" "$ROOT/agents/cadence-breaker/agent.md"
grep -q "CP-12.*CP-13.*CP-14" "$ROOT/agents/cadence-breaker/agent.md"
grep -q "invariant-required-state" "$ROOT/agents/cadence-explorer/agent.md"
grep -q "Pillar Precedence Non-Inversion" "$ROOT/agents/cadence-spec-challenger/agent.md"
grep -q "Anti-Downgrade" "$ROOT/processes/docs/policies/finding-classes.md"
grep -q "Eventual-reconciliation excuses" "$ROOT/processes/docs/policies/finding-classes.md"
grep -q "^### CP-12:" "$ROOT/processes/docs/policies/chaos-profiles.md"
grep -q "^### CP-13:" "$ROOT/processes/docs/policies/chaos-profiles.md"
grep -q "^### CP-14:" "$ROOT/processes/docs/policies/chaos-profiles.md"

echo "PASS: test-review-hardening (all checks)"
