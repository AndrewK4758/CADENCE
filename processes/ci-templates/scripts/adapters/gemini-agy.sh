#!/usr/bin/env bash
# gemini-agy.sh — Canonical Reference CLI Runtime Adapter for Google Antigravity (agy) / Gemini CLI.
# Projects the universal .agents/ directory into .gemini/ per docs/policies/cli-runtime-adoption-policy.md.

set -euo pipefail

TARGET_ROOT="${1:-$(pwd)}"
AGENTS_DIR="$TARGET_ROOT/.agents"
GEMINI_DIR="$TARGET_ROOT/.gemini"

if [[ ! -d "$AGENTS_DIR" ]]; then
  echo "ERROR: Universal primary directory $AGENTS_DIR does not exist. Provision .agents/ first." >&2
  exit 1
fi

mkdir -p "$GEMINI_DIR"

ln -sfn "../.agents/agents" "$GEMINI_DIR/agents"
ln -sfn "../.agents/skills" "$GEMINI_DIR/skills"
if [[ -f "$AGENTS_DIR/hooks/hooks.json" ]]; then
  ln -sfn "../.agents/hooks/hooks.json" "$GEMINI_DIR/hooks.json"
elif [[ -f "$AGENTS_DIR/hooks.json" ]]; then
  ln -sfn "../.agents/hooks.json" "$GEMINI_DIR/hooks.json"
fi

if [[ ! -f "$GEMINI_DIR/GEMINI.md" ]]; then
  cat > "$GEMINI_DIR/GEMINI.md" <<'EOF'
# Gemini / Antigravity Runtime Projection (CADENCE SDLC)

> **Reference Implementation Projection:** This directory (`.gemini/`) is projected directly off the universal primary `.agents/` directory per `docs/policies/cli-runtime-adoption-policy.md`. Do not fork files here; edit `.agents/` or `AGENTS.md`.

@../AGENTS.md
@../CADENCE_DIRECTIVES.md
EOF
fi

echo "gemini-agy adapter: projected .agents/ -> .gemini/ in $TARGET_ROOT"
