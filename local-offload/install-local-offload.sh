#!/usr/bin/env bash
# ==============================================================================
# install-local-offload.sh
#
# Installs the CADENCE LiteRT / Local Hardware Coprocessor Offload stack:
#   1. FastMCP server (`~/.local/bin/antigravity-local-offload-mcp`) & tool schemas
#      (`~/.gemini/antigravity-cli/mcp/local-offload/*.json`)
#   2. Global PreInvocation + PostToolUse lifecycle hook
#      (`~/.local/bin/antigravity-local-offload-hook`)
#   3. llama-swap wrapper (`~/.local/bin/llamaswap-server`,
#      `~/.local/bin/local-ai-offload-serve`, and `~/.config/llama-swap/*.yaml`)
#   4. LiteRT-LM runtime config (`~/.litert-lm/config.json`)
#   5. Systemd user service (`~/.config/systemd/user/local-ai-offload.service`)
#
# Usage:
#   ./local-offload/install-local-offload.sh [--enable-service]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENABLE_SERVICE=0

for arg in "$@"; do
  case "$arg" in
    --enable-service) ENABLE_SERVICE=1 ;;
  esac
done

mkdir -p \
  "$HOME/.local/bin" \
  "$HOME/.config/llama-swap" \
  "$HOME/.config/systemd/user" \
  "$HOME/.litert-lm" \
  "$HOME/.gemini/config" \
  "$HOME/.gemini/antigravity-cli/mcp/local-offload"

# 1. Install FastMCP server, lifecycle hook, and agy wrapper to ~/.local/bin (normalizing /home/ak -> $HOME)
sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/mcp/antigravity-local-offload-mcp" > "$HOME/.local/bin/antigravity-local-offload-mcp"
chmod +x "$HOME/.local/bin/antigravity-local-offload-mcp"

sed "s|/home/ak|$HOME|g" "$REPO_ROOT/hooks/antigravity-local-offload-hook" > "$HOME/.local/bin/antigravity-local-offload-hook"
chmod +x "$HOME/.local/bin/antigravity-local-offload-hook"

if [[ -f "$SCRIPT_DIR/mcp/agy" && -x /usr/bin/agy ]]; then
  sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/mcp/agy" > "$HOME/.local/bin/agy"
  chmod +x "$HOME/.local/bin/agy"
fi

# 2. Install llamaswap-server, local-ai-offload-serve, and llama-swap configs
sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/llama-swap/llamaswap-server" > "$HOME/.local/bin/llamaswap-server"
chmod +x "$HOME/.local/bin/llamaswap-server"

sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/llama-swap/local-ai-offload-serve" > "$HOME/.local/bin/local-ai-offload-serve"
chmod +x "$HOME/.local/bin/local-ai-offload-serve"

cp "$SCRIPT_DIR/llama-swap/llamaswap-server.plugin.zsh" "$HOME/.config/llama-swap/llamaswap-server.plugin.zsh"
cp "$SCRIPT_DIR/llama-swap/llama-swap.egpu.yaml" "$HOME/.config/llama-swap/llama-swap.egpu.yaml"
cp "$SCRIPT_DIR/llama-swap/llama-swap.single.yaml" "$HOME/.config/llama-swap/llama-swap.single.yaml"

# 3. Install LiteRT-LM config if not already present
if [[ ! -f "$HOME/.litert-lm/config.json" ]]; then
  cp "$SCRIPT_DIR/litert-lm/config.json" "$HOME/.litert-lm/config.json"
fi

# 4. Install lazy-loaded MCP tool schemas for Antigravity CLI
cp "$SCRIPT_DIR/mcp/schemas/"*.json "$HOME/.gemini/antigravity-cli/mcp/local-offload/"

# 5. Ensure local-offload MCP server is registered in ~/.gemini/config/mcp_config.json
if [[ ! -f "$HOME/.gemini/config/mcp_config.json" ]]; then
  sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/mcp/mcp_config.example.json" > "$HOME/.gemini/config/mcp_config.json"
  chmod 600 "$HOME/.gemini/config/mcp_config.json"
else
  python3 - "$HOME/.gemini/config/mcp_config.json" "$HOME" <<'PY'
import json, pathlib, sys
cfg_path = pathlib.Path(sys.argv[1])
home = sys.argv[2]
try:
    data = json.loads(cfg_path.read_text(encoding="utf-8"))
except Exception:
    data = {}
servers = data.setdefault("mcpServers", {})
if "local-offload" not in servers:
    servers["local-offload"] = {
        "command": f"{home}/.local/bin/uv",
        "args": ["run", "--script", f"{home}/.local/bin/antigravity-local-offload-mcp"],
        "env": {
            "LLAMA_SWAP_URL": "http://127.0.0.1:11434/v1",
            "LOCAL_AI_TIER1_URL": "http://127.0.0.1:11434/v1",
            "LOCAL_AI_TIER2_URL": "http://127.0.0.1:11434/v1",
        },
    }
    cfg_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
fi

# 6. Install systemd user service
sed "s|/home/ak|$HOME|g" "$SCRIPT_DIR/systemd/local-ai-offload.service" > "$HOME/.config/systemd/user/local-ai-offload.service"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
  if (( ENABLE_SERVICE )); then
    systemctl --user enable --now local-ai-offload.service
  fi
fi

echo "Installed CADENCE LiteRT / Local Offload stack:"
echo "  - MCP Server:      $HOME/.local/bin/antigravity-local-offload-mcp"
echo "  - MCP Schemas:     $HOME/.gemini/antigravity-cli/mcp/local-offload/*.json"
echo "  - Lifecycle Hook:  $HOME/.local/bin/antigravity-local-offload-hook"
echo "  - llama-swap CLI:  $HOME/.local/bin/llamaswap-server & $HOME/.local/bin/local-ai-offload-serve"
echo "  - llama-swap YAML: $HOME/.config/llama-swap/{llama-swap.egpu.yaml,llama-swap.single.yaml}"
echo "  - LiteRT Config:   $HOME/.litert-lm/config.json"
echo "  - Systemd Unit:    $HOME/.config/systemd/user/local-ai-offload.service"
