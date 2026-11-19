#!/usr/bin/env bash
# certainty-gate.sh -- Deterministic hybrid empirical certainty & human-escalation gate.
# Bounded context: CADENCE verification tooling (/cadence-certainty sidecar).
# Read-only: evaluates codebase proofs, DAG inference depth, unknowns/probes,
# diff blast radius, dormant pillar contradictions, and HEAD-SHA test receipts.
#
# Usage:
#   certainty-gate.sh [--root <repo-root>] [--base <ref>] [--stage <auto|spec|implement|review>] [--require-evidence] <ticket-id>
#
# Exit codes:
#   0 = PROCEED (all active checks passed)
#   2 = ESCALATE_HUMAN (uncertainty, unmapped unknowns, unanswered probes, scope drift, or cycle oscillation)
#   1 = HALT (mechanical proof falsification, stale receipt, dormant security contradiction, or setup/tier failure)

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_GATE="$SELF_DIR/certainty_gate.py"

if [[ ! -f "$PY_GATE" ]]; then
  echo "ERROR: required module not found: $PY_GATE" >&2
  exit 1
fi

exec python3 -B "$PY_GATE" "$@"
