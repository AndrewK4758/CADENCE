#!/usr/bin/env bash
#
# OpenCode adapter -- MCP sub-module (BTG-057 / DEC-003, DEC-007). The ONLY home
# for the OpenCode MCP-registration primitives, extracted from opencode.sh for
# symmetry with claude-code-mcp.sh and to keep opencode.sh under the DX line
# ceiling (review N1; the placement refines DEC-007 -- see decisions.md DEC-007a).
# Unlike HOOKS ("sanctioned n/a (Claude-only)" in opencode.sh), MCP is a capability
# OpenCode genuinely HAS: opencode.json's native `mcp` block. This binds the shared
# runtime-neutral engine (mcp-registry.sh) to OpenCode's concretes -- container key
# `mcp` and the OpenCode per-entry shape (`type: "local"`, `command` ARRAY,
# `enabled`, `environment`; pinned DEC-004 -> DEC-011). It is the SECOND adapter
# that proves the engine's container-key parameterization is real (Replaceability).
# The OpenCode *adopt call-site* is wired only where an OpenCode adopt seam exists
# in the fleet (OQ-4); the engine+shim are built and parity-tested now. It defines:
#
#   oc_mcp_render          <manifest>                     # ENTRY-block spec (stdout)
#   oc_mcp_registry_add    <config-file> <manifest>       # create-if-absent / insert
#   oc_mcp_registry_sync   <config-file> <manifest>       # idempotent upsert
#   oc_mcp_registry_remove <config-file>                  # surgical strip (sentinel)
#
# Env block: the JSON key is the SERVER config key (+ `-e <key>` docker arg); the
# value references the ADOPTER's env var (`"JIRA_URL": "${JIRA_BASE_URL}"`, B1 fix /
# DEC-011a, DEC-005) -- never literal secrets. The renderer is a swappable adapter
# fn, so a schema correction stays confined here -- no runtime literal in the
# shared engine.

# The OpenCode MCP container key.
OC_MCP_CONTAINER="mcp"

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-registry.sh"

# Render the CLAIRE entries as an ENTRY-block spec in the OpenCode `mcp` member
# shape at canonical 4-space container-member indent. `command` is a single array
# (no separate args); env-block JSON key = server config key, value references the
# adopter env var (${JIRA_BASE_URL} etc., B1 fix) + the literal ENABLED_TOOLS.
oc_mcp_render() {
  local manifest="$1" k img env et transport url header hname hval
  mcp_manifest_rows "$manifest" | while IFS='|' read -r k img env et transport url header; do
    [[ -n "$k" ]] || continue
    # BTG-059 / DEC-008: remote-http transport form. OpenCode's native remote-MCP
    # entry shape is {"type":"remote","url":...,"enabled":true,"headers":{...}}
    # (opencode.json `mcp` block; the remote sibling of the "local" command form).
    # header= is `<header-name>:<header-value>` split on the FIRST colon; url/header
    # values are ${...} references (never literal secrets, DEC-005).
    if [[ "$transport" == "http" ]]; then
      hname="${header%%:*}"; hval="${header#*:}"
      echo "ENTRY"
      printf '    "%s": {\n' "$k"
      echo '      "type": "remote",'
      printf '      "url": "%s",\n' "$url"
      echo '      "enabled": true,'
      echo '      "headers": {'
      printf '        "%s": "%s"\n' "$hname" "$hval"
      echo '      }'
      echo '    }'
      echo "ENDENTRY"
      continue
    fi
    # BTG-059 review follow-up: skip a malformed imageless (non-http) row cleanly
    # rather than render an empty-image docker entry (parity with claude-code-mcp.sh;
    # S-5.6d). mcp_manifest_validate rejects such rows upstream; this is defensive.
    [[ -n "$img" ]] || continue
    # Each env token is <server-config-key>:<adopter-env-var> (B1 fix, DEC-011a):
    # docker `-e` arg + JSON key are the SERVER KEY; value references the ADOPTER's
    # env var. A colon-less token means key==source. The split is the shared
    # _mcp_split_pair helper (DEC-013) so the Claude and OpenCode copies cannot drift.
    local pair
    IFS=',' read -ra _envs <<< "$env"
    echo "ENTRY"
    printf '    "%s": {\n' "$k"
    echo '      "type": "local",'
    echo '      "command": ['
    echo '        "docker",'
    echo '        "run",'
    echo '        "--rm",'
    echo '        "-i",'
    for pair in "${_envs[@]}"; do
      [[ -n "$pair" ]] || continue
      _mcp_split_pair "$pair"
      printf '        "-e",\n        "%s",\n' "$_MCP_PAIR_KEY"
    done
    [[ -n "$et" ]] && echo '        "-e",' && echo '        "ENABLED_TOOLS",'
    printf '        "%s",\n' "$img"
    echo '        "--transport",'
    echo '        "stdio"'
    echo '      ],'
    echo '      "enabled": true,'
    echo '      "environment": {'
    local first=1
    for pair in "${_envs[@]}"; do
      [[ -n "$pair" ]] || continue
      _mcp_split_pair "$pair"
      [[ $first -eq 1 ]] && first=0 || echo ','
      printf '        "%s": "${%s}"' "$_MCP_PAIR_KEY" "$_MCP_PAIR_SRC"
    done
    if [[ -n "$et" ]]; then
      [[ $first -eq 1 ]] && first=0 || echo ','
      printf '        "ENABLED_TOOLS": "%s"' "$et"
    fi
    echo ''
    echo '      }'
    echo '    }'
    echo "ENDENTRY"
  done
}

oc_mcp_registry_add()    { mcp_registry_add    "$1" "$2" "$OC_MCP_CONTAINER" oc_mcp_render; }
oc_mcp_registry_sync()   { mcp_registry_sync   "$1" "$2" "$OC_MCP_CONTAINER" oc_mcp_render; }
oc_mcp_registry_remove() { mcp_registry_remove "$1" "$OC_MCP_CONTAINER"; }
