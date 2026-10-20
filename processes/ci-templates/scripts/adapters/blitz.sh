#!/usr/bin/env bash
# blitz.sh — Secondary CLI Runtime Adapter for Blitz.
# Projects the universal .agents/ directory into flat <name>.md symlinks for Blitz
# per docs/policies/cli-runtime-adoption-policy.md.

set -euo pipefail

TARGET_ROOT="${1:-$(pwd)}"
AGENTS_DIR="$TARGET_ROOT/.agents"

if [[ ! -d "$AGENTS_DIR" ]]; then
  echo "ERROR: Universal primary directory $AGENTS_DIR does not exist. Provision .agents/ first." >&2
  exit 1
fi

mkdir -p "$HOME/.blitz/agents" "$HOME/.blitz/skills"
for agent_dir in "$AGENTS_DIR"/agents/*/; do
  [[ -d "$agent_dir" && -f "$agent_dir/agent.md" ]] || continue
  role_name="$(basename "$agent_dir")"
  ln -sfn "$(readlink -f "$agent_dir/agent.md")" "$HOME/.blitz/agents/${role_name}.md"
done

for skill_dir in "$AGENTS_DIR"/skills/cadence-*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  rm -rf "$HOME/.blitz/skills/$skill_name"
  mkdir -p "$HOME/.blitz/skills/$skill_name"
  for item in "$(readlink -f "$skill_dir")"/*; do
    [[ -e "$item" ]] && ln -sfn "$item" "$HOME/.blitz/skills/$skill_name/$(basename "$item")"
  done
done

echo "blitz adapter: projected .agents/ -> ~/.blitz/agents/*.md and ~/.blitz/skills/ (from $TARGET_ROOT)"
