#!/usr/bin/env bash
# Builds a self-contained throwaway CADENCE-shaped fixture git repo for offline
# skill/script testing (integration branch: trunk, ACME-101..121).
# Usage: build_cadence_fixture.sh <dest-dir>
set -euo pipefail

DEST="${1:?Usage: $0 <dest-dir>}"
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

git -C "$DEST" init -q -b trunk
git -C "$DEST" config user.name "Fixture Bot"
git -C "$DEST" config user.email "fixture@example.com"

mkdir -p "$DEST/docs/agentic-sdlc" "$DEST/docs/policies" "$DEST/ci-templates/scripts"
cp "$ROOT/processes/ci-templates/scripts/org-binding-"*.sh "$DEST/ci-templates/scripts/"
cp "$ROOT/processes/ci-templates/scripts/stage-effort.sh" "$DEST/ci-templates/scripts/"
cp "$ROOT/processes/docs/policies/change-tiers.md" "$DEST/docs/policies/"

cat > "$DEST/docs/agentic-sdlc/CADENCE_ORG.md" <<'EOF'
# ACME Organization Governance

## Stage Review Multipliers
| Stage | Description | Factor | Notes |
|---|---|---|---|
| `triage` | Intake | **1.0×** | Standard |
| `spec` | Specification | **1.0×** | Standard |
| `implementation` | TDD | **1.0×** | Standard |
| `code-review` | Gate | **1.0×** | Standard |
| `maintainer` | Gate | **1.0×** | Standard |
| `archive` | Closeout | **1.0×** | Standard |

## Tracker Binding

### Per-prefix tracker bindings
| Ticket prefix | Bound tracker | Project key(s) | TS-1 sync skill | Agent-time user |
|---|---|---|---|---|
| `*` | None -- inner-source | | | |

## Id Allocation Binding
- **id_scheme:** `ACME-NNN`

### Per-prefix allocator bindings
| Ticket prefix | Bound allocator | id_scheme |
|---|---|---|

## Sprint-Enforcement Binding

### Per-prefix sprint-enforcement bindings
| Ticket prefix | `sprint_enforcement_enabled` | `sprint_check_skill` | `sprint_check_fallback` |
|---|---|---|---|
| ACME | No | Confirm | Confirm |

## Integration-Branch Enforcement Binding
<!-- integration-branch-enforcement-enabled: yes -->

## Branch-Strategy Binding
<!-- bound-strategy: trunk-based -->
<!-- integration-branch: trunk -->
<!-- branch-naming-convention: {phase}/{type}/{id} -->
<!-- integration-branch-protected: yes -->

## Version-Scheme Binding
<!-- bound-version-scheme: calver-yyyy-ww -->
<!-- version-pattern: ^[0-9]{4}\.(0[1-9]|[1-4][0-9]|5[0-3])\.(0|[1-9][0-9]*)$ -->
<!-- cycle-qualifying-cut: non-patch -->

| Field | Value |
|---|---|
| `bound-version-scheme` | **calver-yyyy-ww** |
| `version-pattern` | **`^[0-9]{4}\.(0[1-9]|[1-4][0-9]|5[0-3])\.(0|[1-9][0-9]*)$`** |
| `cycle-qualifying-cut` | **non-patch** |
EOF

_mk_ticket() {
  local id="$1" tier="$2" status="$3" extra="${4:-}"
  mkdir -p "$DEST/specs/$id"
  cat > "$DEST/specs/$id/metadata.yaml" <<EOF
id: $id
title: Sample $id
tier: $tier
status: $status
branch: ""
spec_mr: ""
merge_request: ""
spec_approved_at: ""
maintainer_approved_at: ""
review_started_at: ""
actual_effort: 0m
stage_effort: []
$extra
EOF
  cat > "$DEST/specs/$id/problem.md" <<EOF
# $id: Sample problem

## Acceptance Criteria
- [ ] System preserves existing invariant for $id without fallback loss
EOF
}

# Landed tickets on trunk: ACME-101, 103, 105, 106, 107, 110, 111, 112, 120, 121
_mk_ticket "ACME-101" "High" "triaged"
_mk_ticket "ACME-102" "High" "in-review"
_mk_ticket "ACME-103" "Trivial" "triaged"
_mk_ticket "ACME-105" "High" "spec-approved"
echo "# Spec for ACME-105" > "$DEST/specs/ACME-105/spec.md"
_mk_ticket "ACME-106" "High" "spec-approved"
sed -i 's|^spec_mr:.*|spec_mr: "https://github.com/acme/repo/pull/77"|' "$DEST/specs/ACME-106/metadata.yaml"
echo "# Spec for ACME-106" > "$DEST/specs/ACME-106/spec.md"
_mk_ticket "ACME-107" "High" "spec-in-review"
echo -e "# Spec for ACME-107\n\n## Open Questions\n1. Q1" > "$DEST/specs/ACME-107/spec.md"

_mk_ticket "ACME-110" "High" "in-review"
cat > "$DEST/specs/ACME-110/submission.md" <<'EOF'
# Submission ACME-110
## Discussion
<!-- cadence-run:cycle n=1 phase=code-review blocking=3 nonblocking=1 at=2026-08-01T10:00:00Z -->
<!-- cadence-run:cycle n=2 phase=code-review blocking=2 nonblocking=0 at=2026-08-02T10:00:00Z -->
<!-- cadence-run:cycle n=3 phase=code-review blocking=1 nonblocking=1 at=2026-08-03T10:00:00Z -->
EOF

_mk_ticket "ACME-111" "Medium" "in-review"
cat > "$DEST/specs/ACME-111/submission.md" <<'EOF'
# Submission ACME-111
## Discussion
<!-- cadence-run:cycle n=1 phase=code-review blocking=2 nonblocking=0 at=2026-08-01T10:00:00Z -->
<!-- cadence-run:cycle n=2 phase=code-review blocking=2 nonblocking=0 at=2026-08-02T10:00:00Z -->
<!-- cadence-run:cycle n=3 phase=code-review blocking=2 nonblocking=0 at=2026-08-03T10:00:00Z -->
<!-- cadence-run:cycle n=4 phase=code-review blocking=2 nonblocking=0 at=2026-08-04T10:00:00Z -->
EOF

_mk_ticket "ACME-112" "Medium" "in-review"
sed -i 's|^merge_request:.*|merge_request: "https://github.com/acme/repo/pull/88"|' "$DEST/specs/ACME-112/metadata.yaml"
echo -e "# Sub\n## Discussion\n<!-- cadence-run:cycle n=1 phase=code-review blocking=0 nonblocking=0 at=2026-08-05T10:00:00Z -->" > "$DEST/specs/ACME-112/submission.md"

_mk_ticket "ACME-120" "High" "triaged"
echo -e "\n### Probe 1\n_Answer:_ _(not yet answered)_" >> "$DEST/specs/ACME-120/problem.md"
_mk_ticket "ACME-121" "Medium" "triaged"
echo -e "\n## Elicited Intent\n**Answer:** Explicit single timeout." >> "$DEST/specs/ACME-121/problem.md"

git -C "$DEST" add -A
git -C "$DEST" commit -q -m "fixture baseline (#77)"

# Deliberately untracked fixtures on trunk (ACME-109, ACME-113):
_mk_ticket "ACME-109" "Low" "triaged"
_mk_ticket "ACME-113" "High" "spec-approved"
echo "# Spec for ACME-113 (untracked)" > "$DEST/specs/ACME-113/spec.md"

# Complete canonical High-tier spec ticket ACME-201 (anchored to trunk src/alpha.py):
mkdir -p "$DEST/src" "$DEST/specs/ACME-201"
printf 'def compute_total(items):\n    return len(items)\n' > "$DEST/src/alpha.py"
git -C "$DEST" add src/alpha.py && git -C "$DEST" commit -q -m "add src/alpha.py"
_mk_ticket "ACME-201" "High" "spec-in-review"
sed -i 's|^branch:.*|branch: "spec/feat/ACME-201"|' "$DEST/specs/ACME-201/metadata.yaml"
printf '# Decisions\nGate 1 ruling: design -- agree -- accepted Option A directly\n' > "$DEST/specs/ACME-201/decisions.md"
cat > "$DEST/specs/ACME-201/design-options.md" <<'MD'
# Design Options: ACME-201

## Axis of variation
Streaming iterator vs upfront materialized count.

## Option A: Streaming
- Structure: Single-pass iterator in `compute_total`
- Steelman: Zero extra allocation for large sequences
- Failure modes (KNOWN): Single-consume iterator exhaustion
- Failure modes (UNKNOWN): Non-sized generator inputs
- Pillar-relevant properties: Structural Simplicity high; Agentic Ergonomics concise
- Novelty class: Existing codebase idiom

## Option B: Batch Pre-Aggregate
- Structure: Materialize list before `len`
- Steelman: Idempotent re-iteration across callers
- Failure modes (KNOWN): Linear memory spike on huge streams
- Failure modes (UNKNOWN): Timeout on slow iterators
- Pillar-relevant properties: Higher memory footprint
- Novelty class: Textbook alternative
MD
cat > "$DEST/specs/ACME-201/test-plan.md" <<'MD'
# Test Plan: ACME-201

## Acceptance Criteria Coverage
| AC | Scenarios | Status |
|---|---|---|
| AC-1 | Scenario 1 | Pending |

## BDD Features
Feature: Item count computation
  Scenario: Valid sequence returns exact count (`RULE_DIVERGENCE`)
    Given a non-null sequence of items
    When compute_total runs
    Then it returns the exact integer length

## Implementation Order
| # | Scenario | Notes |
|---|---|---|
| 1 | Valid sequence returns exact count | Core function |
MD
cat > "$DEST/specs/ACME-201/spec.md" <<'MD'
# Spec: ACME-201

## Contextual Grounding Matrix (6W×4L)
| Layer | Who | What | Where | Why | When | How |
|---|---|---|---|---|---|---|
| Domain | Worker | Count items | [src/alpha.py#L1-L2](src/alpha.py#L1-L2) `compute_total` | Accurate total | On call | Direct |
| Application | Caller | Pass sequence | src/alpha.py | Reuse | On request | Import |
| Infrastructure | Store | Read rows | src/alpha.py | Sync check | On tick | Stream |
| Interface | API | Return total | src/alpha.py | Output | Response | JSON |

## CHORD Analysis
#### AC-1
| Dimension | Specification |
|---|---|
| **Conditions** | Valid non-null item sequence passed |
| **Handling** | `compute_total` invoked by caller |
| **Outcomes** | Exact integer length returned |
| **Rules** | Null sequence rejected fail-closed |
| **Deltas** | `last_count` state updated |

## CADENCE Engineering Pillar Evaluation
### Pillar 1: Structural Simplicity
Single concise helper with shallow control flow.
### Pillar 2: Operational Resilience
Fails closed on invalid input without fallback masking.
### Pillar 3: Agentic Ergonomics
Focused module well under 150 lines.
### Pillar 4: Data & Audit Fidelity
Active — emits `RULE_DIVERGENCE` on cache mismatch.
### Pillar 5: Surface Compatibility
Dormant — internal module only.
### Pillar 6: Security Boundary Posture
Dormant — internal pure helper.

## Observability Seams
- `RULE_DIVERGENCE`: emitted when cached count diverges from live count

### Baseline Definitions
| Seam | Condition | Expected Baseline |
|---|---|---|
| `RULE_DIVERGENCE` | Cache mismatch | Recomputed live len equals cached total |

## Proposed Design
Use [src/alpha.py#L1-L2](src/alpha.py#L1-L2) `compute_total` directly.

| File | Action | Purpose |
|---|---|---|
| src/alpha.py | Modify | Count elements cleanly |

## Alternatives Considered
### Alternative 1: Batch Pre-Aggregate
Rejected due to linear memory copy overhead for large streams.

## Compatibility Impact
Internal helper signature stays backwards-compatible.

## Design Exploration
Evaluated Options A and B in `design-options.md`.

## Risks and Open Questions
**Gate 1 rulings:** required

| # | Question | Status |
|---|---|---|
| 1 | Streaming vs Batch option selection | Resolved in decisions.md |
MD

echo "$DEST"
