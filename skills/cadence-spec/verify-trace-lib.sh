#!/usr/bin/env bash
# verify-trace-lib.sh -- Post-implementation spec/AC-to-code/test traceability
# Sourced ONLY by verify-facts.sh (delegates parsing/scanning to verify_trace.py
# so every file remains cleanly under the <400-line Pillar 3 ceiling).

set -u

trace_mode() {
  local helper="$SELF_DIR/verify_trace.py"
  if [[ ! -f "$helper" ]]; then
    echo "ERROR: required module not found: $helper" >&2
    exit 1
  fi
  python3 "$helper" "$ROOT" "$BASE" "$BASE_EXPLICIT" "$TICKET" "$TICKET_DIR" "$TICKET_REL" "$TRACE_STRICT" "${CODE_ROOTS[@]+"${CODE_ROOTS[@]}"}"
}
