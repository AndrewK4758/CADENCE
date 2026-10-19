#!/usr/bin/env bash
# link-sdlc.sh — Provisions CADENCE SDLC into a target repository using .agents/ as the
# universal primary directory and .gemini/ as the canonical Antigravity/Gemini reference
# implementation (plus optional secondary CLI adapters per docs/policies/cli-runtime-adoption-policy.md).
#
# Usage:
#   link-sdlc.sh <target-repo> [--claude] [--opencode]
#   link-sdlc.sh --global     (promotes ~/projects/sdlc into global ~/.gemini/config/)
set -euo pipefail

SDLC_ROOT="/home/ak/projects/sdlc"

if [[ "${1:-}" == "--global" ]]; then
  cp "$SDLC_ROOT/import/agents.json" /home/ak/.gemini/config/agents.json
  cp "$SDLC_ROOT/import/skills.json" /home/ak/.gemini/config/skills.json
  cp "$SDLC_ROOT/hooks/hooks.json" /home/ak/.gemini/config/hooks.json
  echo "Promoted $SDLC_ROOT globally into ~/.gemini/config/{agents.json,skills.json,hooks.json}"
  exit 0
fi

TARGET_REPO="${1:-$(pwd)}"
shift || true

# 1. Universal Primary Directory (.agents/)
mkdir -p "$TARGET_REPO/.agents"
ln -sfn "$SDLC_ROOT/agents" "$TARGET_REPO/.agents/agents"
ln -sfn "$SDLC_ROOT/skills" "$TARGET_REPO/.agents/skills"
ln -sfn "$SDLC_ROOT/hooks" "$TARGET_REPO/.agents/hooks"
cp "$SDLC_ROOT/import/agents.json" "$TARGET_REPO/.agents/agents.json"
cp "$SDLC_ROOT/import/skills.json" "$TARGET_REPO/.agents/skills.json"
cp "$SDLC_ROOT/hooks/hooks.json" "$TARGET_REPO/.agents/hooks.json"

# 2. Canonical Reference Implementation (.gemini/ for Antigravity / Gemini CLI)
bash "$SDLC_ROOT/processes/ci-templates/scripts/adapters/gemini-agy.sh" "$TARGET_REPO"

# 3. Optional Secondary CLI Runtime Projections (Modeled after .gemini/ off .agents/)
for arg in "$@"; do
  case "$arg" in
    --claude)
      mkdir -p "$TARGET_REPO/.claude"
      ln -sfn "../.agents/agents" "$TARGET_REPO/.claude/agents"
      ln -sfn "../.agents/skills" "$TARGET_REPO/.claude/skills"
      ln -sfn "../.agents/hooks" "$TARGET_REPO/.claude/hooks"
      echo "Projected .agents/ -> .claude/ in $TARGET_REPO"
      ;;
    --opencode)
      mkdir -p "$TARGET_REPO/.opencode"
      ln -sfn "../.agents/agents" "$TARGET_REPO/.opencode/agent"
      ln -sfn "../.agents/skills" "$TARGET_REPO/.opencode/command"
      echo "Projected .agents/ -> .opencode/ in $TARGET_REPO"
      ;;
  esac
done

echo "Linked CADENCE SDLC ($SDLC_ROOT) into $TARGET_REPO/.agents/ (primary) and $TARGET_REPO/.gemini/ (reference)"
