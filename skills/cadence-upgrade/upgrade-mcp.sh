#!/usr/bin/env bash
#
# upgrade-mcp.sh -- the BTG-057 MCP-registration reconciliation concern of
# /cadence-upgrade (AC-4). The MCP analog of upgrade-hooks.sh: a colocated
# sidecar module shipped by the PI-023 directory-copy contract and sourced by
# upgrade-cadence.sh in this shell's scope (so CORE / TARGET / emit_seam resolve
# at call time; the split keeps the entry point under the DX line ceiling).
#
# Bounded context: Upgrade seam / layered-source flow (BTG-057, adopt/upgrade/eject).
# Upstream: called by upgrade-cadence.sh main() on the CLEAN-APPLY path only
#   (never a conflicted/partial apply -- R-5), after the hook reconciliation and
#   BEFORE the stamp advance. Downstream: idempotently re-syncs the CADENCE MCP
#   server entries in the adopter's .mcp.json (via the adapter's cc_mcp_registry_sync)
#   to the manifest's current shape; adopter-added MCP servers + non-mcpServers
#   content preserved. Spec: specs/BTG-057/spec.md (Upgrade / AC-4); decisions.md.
#
# Unlike hooks there is NO legacy file relocation (MCP had no prior on-disk
# namespace) -- the reserved server-key prefix IS the sentinel -- so this is a
# pure idempotent upsert. The name mirrors hooks_relocate_and_sync for symmetry.

# Extract core@<ours_commit>'s neutral mcp.manifest to <dest>. Returns 1 if
# core@new does not declare artifacts/mcp -- the PI-003 BOOTSTRAPPING GAP: the
# upgrade hop toward a release line that predates MCP registration cannot sync
# (the caller surfaces upgrade.mcp.bootstrapping_gap + self-heals next upgrade).
mcp_core_manifest() {
  local ours_commit="$1" dest="$2"
  git -C "$CORE" cat-file -e "$ours_commit:artifacts/mcp/mcp.manifest" 2>/dev/null || return 1
  git -C "$CORE" show "$ours_commit:artifacts/mcp/mcp.manifest" > "$dest" 2>/dev/null || return 1
  [[ -s "$dest" ]]
}

# Resolve the adapter MCP shim (installed in the adopter under ci-templates/
# scripts/adapters, or reachable from core). Echoes its path or "".
mcp_adapter_path() {
  local a
  # >>> binding-resolution (clause-7 exempt) >>>
  for a in "$TARGET/ci-templates/scripts/adapters/claude-code-mcp.sh" \
           "$CORE/ci-templates/scripts/adapters/claude-code-mcp.sh"; do
  # <<< binding-resolution (clause-7 exempt) <<<
    [[ -f "$a" ]] && { echo "$a"; return 0; }
  done
  echo ""
}

# Idempotently re-sync the CADENCE MCP registration in the adopter's .mcp.json to
# core@new's manifest shape. Preserves adopter-owned MCP servers + non-mcpServers
# content; re-running is a no-op. Emits the informational upgrade.mcp.synced seam
# on success. Returns non-zero (fail-loud) iff the sync refuses (a non-canonical
# .mcp.json), leaving the caller to keep the stamp UNADVANCED -- all-or-nothing.
# Args: <manifest>
mcp_relocate_and_sync() {
  local manifest="$1" mcp_adapter
  mcp_adapter="$(mcp_adapter_path)"
  [[ -n "$mcp_adapter" ]] || return 0
  # >>> binding-resolution (clause-7 exempt) >>>
  local cfg="$TARGET/.mcp.json"
  # <<< binding-resolution (clause-7 exempt) <<<
  # shellcheck source=/dev/null
  . "$mcp_adapter"
  if ! cc_mcp_registry_sync "$cfg" "$manifest"; then
    echo "upgrade-cadence: MCP registration sync refused (non-canonical .mcp.json) -- .mcp.json untouched." >&2
    return 1
  fi
  emit_seam LOGIC_FAULT upgrade.mcp.synced "$cfg"
  echo "upgrade-cadence: MCP registration synced."
}
