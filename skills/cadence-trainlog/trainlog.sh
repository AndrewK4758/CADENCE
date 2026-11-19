#!/usr/bin/env bash
# CLI wrapper for CADENCE turn-log status, historical backfill, tagging, export, and verification.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -B "$SELF_DIR/trainlog_cli.py" "$@"
