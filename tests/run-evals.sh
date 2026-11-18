#!/usr/bin/env bash
# Offline deterministic eval runner across all 24 skills/*/evals/evals.json.
# Usage:
#   bash tests/run-evals.sh [--skill <name>] [--with-offload] [--verbose]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -B "$ROOT/tests/eval_runner.py" --root "$ROOT" "$@"
