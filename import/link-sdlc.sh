#!/usr/bin/env bash
# Links ~/projects/sdlc agents, skills, and hooks into a target repository (.agents/)
# or globally (--global -> ~/.gemini/config/) so updates in ~/projects/sdlc propagate everywhere.
set -euo pipefail

SDLC_ROOT="/home/ak/projects/sdlc"

if [[ "${1:-}" == "--global" ]]; then
  cp "$SDLC_ROOT/import/agents.json" /home/ak/.gemini/config/agents.json
  cp "$SDLC_ROOT/import/skills.json" /home/ak/.gemini/config/skills.json
  echo "Linked $SDLC_ROOT globally into ~/.gemini/config/{agents.json,skills.json}"
  exit 0
fi

TARGET_REPO="${1:-$(pwd)}"
mkdir -p "$TARGET_REPO/.agents"

ln -sfn "$SDLC_ROOT/agents" "$TARGET_REPO/.agents/agents"
ln -sfn "$SDLC_ROOT/skills" "$TARGET_REPO/.agents/skills"
cp "$SDLC_ROOT/import/agents.json" "$TARGET_REPO/.agents/agents.json"
cp "$SDLC_ROOT/import/skills.json" "$TARGET_REPO/.agents/skills.json"
cp "$SDLC_ROOT/hooks/hooks.json" "$TARGET_REPO/.agents/hooks.json"

echo "Linked $SDLC_ROOT into $TARGET_REPO/.agents/ (agents, skills, hooks.json)"
