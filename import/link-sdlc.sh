#!/usr/bin/env bash
# link-sdlc.sh — Provisions CADENCE SDLC into a target repository using .agents/ as the
# universal primary directory and .gemini/ as the canonical Antigravity/Gemini reference
# implementation (plus optional secondary CLI adapters per docs/policies/cli-runtime-adoption-policy.md).
#
# Usage:
#   link-sdlc.sh <target-repo> [--replace] [--claude] [--opencode] [--blitz]
#   link-sdlc.sh --global [--offload-only] [--with-cadence-global] [--enable-service]
set -euo pipefail

SDLC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPLACE_COPIES=0

# Support --replace anywhere in non-global arguments without altering positional semantics.
FILTERED_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --replace) REPLACE_COPIES=1 ;;
    *) FILTERED_ARGS+=("$arg") ;;
  esac
done
set -- ${FILTERED_ARGS[@]+"${FILTERED_ARGS[@]}"}

link_dir_target() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    if [[ -d "$dst" ]]; then
      if (( REPLACE_COPIES )); then
        rm -rf "$dst"
      else
        echo "ERROR: $dst exists as a real directory (copied files). Re-run with --replace to link to $SDLC_ROOT." >&2
        exit 1
      fi
    fi
  fi
  ln -sfn "$src" "$dst"
}

if [[ "${1:-}" == "--global" ]]; then
  shift || true
  WITH_CADENCE_GLOBAL=0
  INSTALL_OFFLOAD_ARGS=()
  for g_arg in "$@"; do
    case "$g_arg" in
      --with-cadence-global) WITH_CADENCE_GLOBAL=1 ;;
      --offload-only) WITH_CADENCE_GLOBAL=0 ;;
      *) INSTALL_OFFLOAD_ARGS+=("$g_arg") ;;
    esac
  done

  if (( WITH_CADENCE_GLOBAL )); then
    # 1. Universal Global Primary Directory (~/.agents/)
    mkdir -p "$HOME/.agents"
    ln -sfn "$SDLC_ROOT/agents" "$HOME/.agents/agents"
    ln -sfn "$SDLC_ROOT/skills" "$HOME/.agents/skills"
    ln -sfn "$SDLC_ROOT/hooks" "$HOME/.agents/hooks"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/import/agents.json" > "$HOME/.agents/agents.json"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/import/skills.json" > "$HOME/.agents/skills.json"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/hooks/hooks.global.json" > "$HOME/.agents/hooks.json"

    # 2. Global Antigravity / Gemini Configuration (~/.gemini/config/)
    mkdir -p "$HOME/.gemini/config/agents" "$HOME/.gemini/config/skills"
    for agent_dir in "$SDLC_ROOT"/agents/cadence-* "$SDLC_ROOT"/agents/log-triage "$SDLC_ROOT"/agents/repo-scout; do
      if [[ -d "$agent_dir" ]]; then
        rm -rf "$HOME/.gemini/config/agents/$(basename "$agent_dir")"
        ln -sfn "$agent_dir" "$HOME/.gemini/config/agents/$(basename "$agent_dir")"
      fi
    done
    for skill_dir in "$SDLC_ROOT"/skills/cadence-*; do
      [[ -d "$skill_dir" ]] && ln -sfn "$skill_dir" "$HOME/.gemini/config/skills/$(basename "$skill_dir")"
    done
    ln -sfn "$SDLC_ROOT/hooks" "$HOME/.gemini/config/hooks"
    sed "s|/home/ak|$HOME|g" "$SDLC_ROOT/import/GEMINI.global.md" > "$HOME/.gemini/config/GEMINI.md"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/import/agents.json" > "$HOME/.gemini/config/agents.json"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/import/skills.json" > "$HOME/.gemini/config/skills.json"
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/hooks/hooks.global.json" > "$HOME/.gemini/config/hooks.json"

    # 3. Global Blitz Configuration (~/.blitz/agents/*.md & ~/.blitz/skills/)
    mkdir -p "$HOME/.blitz/agents" "$HOME/.blitz/skills"
    for agent_dir in "$SDLC_ROOT"/agents/cadence-* "$SDLC_ROOT"/agents/log-triage "$SDLC_ROOT"/agents/repo-scout; do
      if [[ -d "$agent_dir" && -f "$agent_dir/agent.md" ]]; then
        ln -sfn "$agent_dir/agent.md" "$HOME/.blitz/agents/$(basename "$agent_dir").md"
      fi
    done
    for skill_dir in "$SDLC_ROOT"/skills/cadence-*; do
      [[ -d "$skill_dir" ]] || continue
      skill_name="$(basename "$skill_dir")"
      rm -rf "$HOME/.blitz/skills/$skill_name"
      mkdir -p "$HOME/.blitz/skills/$skill_name"
      for item in "$skill_dir"/*; do
        [[ -e "$item" ]] && ln -sfn "$item" "$HOME/.blitz/skills/$skill_name/$(basename "$item")"
      done
    done
  else
    # Default Option-B neutral globals: install local-offload coprocessors & neutral hooks only;
    # keep CADENCE 100% repository-scoped so multi-framework hosts stay isolated.
    mkdir -p "$HOME/.agents/agents" "$HOME/.agents/hooks" "$HOME/.gemini/config/agents" "$HOME/.blitz/agents"
    for neutral_agent in log-triage repo-scout; do
      if [[ -d "$SDLC_ROOT/agents/$neutral_agent" ]]; then
        rm -rf "$HOME/.agents/agents/$neutral_agent" "$HOME/.gemini/config/agents/$neutral_agent"
        cp -R "$SDLC_ROOT/agents/$neutral_agent" "$HOME/.agents/agents/$neutral_agent"
        ln -sfn "$HOME/.agents/agents/$neutral_agent/agent.md" "$HOME/.blitz/agents/$neutral_agent.md"
      fi
    done
    sed "s|/home/ak/projects/sdlc|$SDLC_ROOT|g; s|/home/ak|$HOME|g" "$SDLC_ROOT/hooks/hooks.global.json" > "$HOME/.agents/hooks.json"
  fi

  # 4. Install LiteRT / Local Offload MCP Server, Hooks, llamaswap-server, and Systemd Unit
  if [[ -x "$SDLC_ROOT/local-offload/install-local-offload.sh" ]]; then
    bash "$SDLC_ROOT/local-offload/install-local-offload.sh" ${INSTALL_OFFLOAD_ARGS[@]+"${INSTALL_OFFLOAD_ARGS[@]}"}
  fi

  if command -v sync-mcp-configs >/dev/null 2>&1; then
    sync-mcp-configs --quiet || true
  fi

  if (( WITH_CADENCE_GLOBAL )); then
    echo "Promoted CADENCE ($SDLC_ROOT) globally into ~/.agents/, ~/.gemini/config/, ~/.blitz/, and ~/.local/bin/"
  else
    echo "Installed neutral global offload/coprocessors ($SDLC_ROOT); CADENCE remains repo-scoped"
  fi
  exit 0
fi

TARGET_REPO="${1:-$(pwd)}"
shift || true

# 1. Universal Primary Directory (.agents/)
mkdir -p "$TARGET_REPO/.agents"
link_dir_target "$SDLC_ROOT/agents" "$TARGET_REPO/.agents/agents"
link_dir_target "$SDLC_ROOT/skills" "$TARGET_REPO/.agents/skills"
link_dir_target "$SDLC_ROOT/hooks" "$TARGET_REPO/.agents/hooks"
printf '{"entries": [{"path": ".agents/agents"}]}\n' > "$TARGET_REPO/.agents/agents.json"
printf '{"entries": [{"path": ".agents/skills"}]}\n' > "$TARGET_REPO/.agents/skills.json"
ln -sfn hooks/hooks.json "$TARGET_REPO/.agents/hooks.json"

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
    --blitz)
      bash "$SDLC_ROOT/processes/ci-templates/scripts/adapters/blitz.sh" "$TARGET_REPO"
      ;;
  esac
done

echo "Linked CADENCE SDLC ($SDLC_ROOT) into $TARGET_REPO/.agents/ (primary) and $TARGET_REPO/.gemini/ (reference)"
