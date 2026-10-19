#!/usr/bin/env bash
# link-sdlc.sh — Provisions CADENCE SDLC into a target repository using .agents/ as the
# universal primary directory and .gemini/ as the canonical Antigravity/Gemini reference
# implementation (plus optional secondary CLI adapters per docs/policies/cli-runtime-adoption-policy.md).
#
# Usage:
#   link-sdlc.sh <target-repo> [--claude] [--opencode]
#   link-sdlc.sh --global     (promotes ~/projects/sdlc into global ~/.agents/ and ~/.gemini/config/)
set -euo pipefail

SDLC_ROOT="/home/ak/projects/sdlc"

if [[ "${1:-}" == "--global" ]]; then
  # 1. Universal Global Primary Directory (~/.agents/)
  mkdir -p /home/ak/.agents
  ln -sfn "$SDLC_ROOT/agents" /home/ak/.agents/agents
  ln -sfn "$SDLC_ROOT/skills" /home/ak/.agents/skills
  ln -sfn "$SDLC_ROOT/hooks" /home/ak/.agents/hooks
  cp "$SDLC_ROOT/import/agents.json" /home/ak/.agents/agents.json
  cp "$SDLC_ROOT/import/skills.json" /home/ak/.agents/skills.json
  cp "$SDLC_ROOT/hooks/hooks.json" /home/ak/.agents/hooks.json

  # 2. Global Antigravity / Gemini Configuration (~/.gemini/config/)
  mkdir -p /home/ak/.gemini/config/agents /home/ak/.gemini/config/skills
  rm -rf /home/ak/.gemini/config/agents/claire-* /home/ak/.gemini/config/skills/claire-*
  for agent_dir in "$SDLC_ROOT"/agents/cadence-*; do
    [[ -d "$agent_dir" ]] && ln -sfn "$agent_dir" "/home/ak/.gemini/config/agents/$(basename "$agent_dir")"
  done
  for skill_dir in "$SDLC_ROOT"/skills/cadence-*; do
    [[ -d "$skill_dir" ]] && ln -sfn "$skill_dir" "/home/ak/.gemini/config/skills/$(basename "$skill_dir")"
  done
  ln -sfn "$SDLC_ROOT/hooks" /home/ak/.gemini/config/hooks
  cp "$SDLC_ROOT/import/GEMINI.global.md" /home/ak/.gemini/config/GEMINI.md
  cp "$SDLC_ROOT/import/agents.json" /home/ak/.gemini/config/agents.json
  cp "$SDLC_ROOT/import/skills.json" /home/ak/.gemini/config/skills.json
  cp "$SDLC_ROOT/hooks/hooks.json" /home/ak/.gemini/config/hooks.json

  echo "Promoted CADENCE ($SDLC_ROOT) globally into ~/.agents/ (primary) and ~/.gemini/config/ (Antigravity reference)"
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
