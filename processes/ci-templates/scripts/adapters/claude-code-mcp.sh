#!/usr/bin/env bash
#
# Claude Code adapter -- MCP sub-module (BTG-057 / DEC-003). The ONLY home for the
# Claude Code MCP-registration primitives (ADR_CLAIRE-0008 R7): the native config file
# (.mcp.json at the repo root), the `mcpServers` container key, and the Claude
# per-entry JSON shape (`command` string + `args` array + `env` object). Binds the
# shared runtime-neutral engine (mcp-registry.sh) to those concretes. Sourced by
# adopt/upgrade/eject. It defines:
#
#   cc_mcp_render          <manifest>                     # ENTRY-block spec (stdout)
#   cc_mcp_registry_add    <config-file> <manifest>       # create-if-absent / insert
#   cc_mcp_registry_sync   <config-file> <manifest>       # idempotent upsert
#   cc_mcp_registry_remove <config-file>                  # surgical strip (sentinel)
#
# Pinned per-entry schema (DEC-004 -> DEC-011): `command:"docker"`, `args:[...]`
# docker-stdio, `env:{...}` whose JSON key is the SERVER config key and whose value
# references the ADOPTER's env var (`"JIRA_URL": "${JIRA_BASE_URL}"`, B1 fix /
# DEC-011a, DEC-005), never literal secrets. The renderer is a swappable adapter
# fn, so a schema correction stays confined here (ADR_CLAIRE-0008 clause 4) -- no runtime
# literal in the shared engine.

# The Claude MCP container key.
CC_MCP_CONTAINER="mcpServers"

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-registry.sh"

# Render the CLAIRE entries as an ENTRY-block spec (one block per manifest row),
# in the Claude `mcpServers` member shape at canonical 4-space container-member
# indent. Env values are ${NAME} references + the literal ENABLED_TOOLS allow-list.
cc_mcp_render() {
  local manifest="$1" k img env et transport url header hname hval
  mcp_manifest_rows "$manifest" | while IFS='|' read -r k img env et transport url header; do
    [[ -n "$k" ]] || continue
    # BTG-059 / DEC-008: remote-http transport form. The Claude `.mcp.json` shape
    # for `claude mcp add --transport http --header ...` is
    # {"type":"http","url":...,"headers":{<name>:<value>}}. header= is
    # `<header-name>:<header-value>` split on the FIRST colon; url/header values
    # are ${...} references (never literal secrets, DEC-005).
    if [[ "$transport" == "http" ]]; then
      hname="${header%%:*}"; hval="${header#*:}"
      echo "ENTRY"
      printf '    "%s": {\n' "$k"
      echo '      "type": "http",'
      printf '      "url": "%s",\n' "$url"
      echo '      "headers": {'
      printf '        "%s": "%s"\n' "$hname" "$hval"
      echo '      }'
      echo '    }'
      echo "ENDENTRY"
      continue
    fi
    # BTG-059 review follow-up: the docker branch assumes an image. A row that is
    # neither remote-http nor carries image= is malformed (mcp_manifest_validate
    # rejects it upstream); skip it cleanly here rather than emit an empty-image
    # docker entry. Makes "the renderer skips an imageless row cleanly" a real,
    # tested property (S-5.6d) instead of a claim about un-changeable old engines.
    [[ -n "$img" ]] || continue
    echo "ENTRY"
    printf '    "%s": {\n' "$k"
    echo '      "command": "docker",'
    echo '      "args": ['
    echo '        "run",'
    echo '        "--rm",'
    echo '        "-i",'
    # Each env token is <server-config-key>:<adopter-env-var> (B1 fix, DEC-011a):
    # the docker `-e` arg + env-block JSON key are the SERVER KEY; the value
    # references the ADOPTER's env var. A colon-less token means key==source.
    # The split is the shared _mcp_split_pair helper (DEC-013) so the Claude and
    # OpenCode copies cannot drift.
    local pair
    IFS=',' read -ra _envs <<< "$env"
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
    echo '      "env": {'
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

cc_mcp_registry_add()    { mcp_registry_add    "$1" "$2" "$CC_MCP_CONTAINER" cc_mcp_render; }
cc_mcp_registry_sync()   { mcp_registry_sync   "$1" "$2" "$CC_MCP_CONTAINER" cc_mcp_render; }
cc_mcp_registry_remove() { mcp_registry_remove "$1" "$CC_MCP_CONTAINER"; }
