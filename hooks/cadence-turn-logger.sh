#!/bin/sh
# Stop hook -- capture CADENCE session turns to external private storage for training data.
# Supports Antigravity (conversationId/terminationReason/transcriptPath) and Claude Code
# (session_id/transcript_path/cwd). Fails open and stays silent outside CADENCE repos.
# Opt-out: CADENCE_TURN_LOG=0. Storage: ${CADENCE_TURN_LOG_DIR:-~/.local/share/cadence-turn-logs}.

set -f
is_agy=0

allow_exit() {
  if [ "$is_agy" -eq 1 ]; then
    printf '{"decision":"allow"}'
  else
    printf '{}'
  fi
  exit 0
}

trap 'exit 0' EXIT

raw=$(cat 2>/dev/null || true)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || { printf '{}'; exit 0; }

case "$raw" in
  *\"terminationReason\"*|*\"continuationActive\"*|*\"executionNum\"*|*\"conversationId\"*)
    is_agy=1
    ;;
esac

if [ "${CADENCE_TURN_LOG:-1}" = "0" ]; then
  allow_exit
fi

if ! command -v python3 >/dev/null 2>&1; then
  allow_exit
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$SCRIPT_DIR/cadence_turn_logger.py" ]; then
  printf '%s' "$raw" | python3 -B "$SCRIPT_DIR/cadence_turn_logger.py" >/dev/null 2>&1 || true
fi

allow_exit
