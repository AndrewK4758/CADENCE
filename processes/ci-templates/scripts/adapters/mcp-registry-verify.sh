#!/usr/bin/env bash
#
# mcp-registry-verify.sh -- the MCP-config PRESERVATION postcondition + JSON
# well-formedness + reserved-key adopt guard for the BTG-057 registration engine
# (DEC-003 sibling split; the direct analog of claude-code-settings-verify.sh).
# Sourced by adapters/mcp-registry.sh; kept as its own module so the engine stays
# under the DX line ceiling. Ships to adopters via the ci-templates/scripts/
# adapters COPY_PATH (whole-dir copy).
#
# The pure-shell surgical engine (_mcp_registry_rewrite) assumes CLAIRE's exact
# canonical pretty-printed layout (2-space indent, one container-member key per
# line). mcp_json_wellformed only proves brace/quote balance -- NOT canonical
# layout -- so a well-formed-but-non-canonical file (compact single-line, alt
# indentation, inline objects) would be MISREAD, silently dropping adopter MCP
# servers. This module adds the contract-correct, LAYOUT-AGNOSTIC guard: before
# the atomic rename, verify "every non-CLAIRE item present in the input is
# present in the output" -- every non-container top-level key AND every
# non-`claire-`-prefixed container member key survives. On failure the caller
# refuses (no write, source untouched) and fails loud (AC-7 "refuse + instruct").

# The reserved ownership sentinel (DEC-002): a container member key is
# CLAIRE-owned iff it carries this prefix.
MCP_RESERVED_PREFIX="claire-"

# Reuse a shared emit_seam if the caller already defined one; else define it.
if ! declare -F emit_seam >/dev/null 2>&1; then
  emit_seam() {
    local seam_type="$1" event_name="$2" subject="${3:-}"
    echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
  }
fi

# JSON well-formedness (string-aware brace/bracket/quote balance check). Not a
# full validator: it proves balance + a leading '{', which catches the truncated /
# unbalanced config the fail-loud contract must refuse. 0 = well-formed-ish.
mcp_json_wellformed() {
  local file="$1"
  [[ -f "$file" ]] || return 0   # absent is handled by callers (create), not malformed
  awk '
    BEGIN { depth=0; instr=0; esc=0; firstnonspace="" }
    { n=length($0)
      for (i=1;i<=n;i++) { c=substr($0,i,1)
        if (firstnonspace=="" && c!=" " && c!="\t") firstnonspace=c
        if (instr) {
          if (esc) { esc=0 } else if (c=="\\") { esc=1 } else if (c=="\"") { instr=0 }
          continue }
        if (c=="\"") { instr=1; continue }
        if (c=="{" || c=="[") { depth++ }
        else if (c=="}" || c=="]") { depth--; if (depth<0) { exit 1 } } } }
    END { if (instr) exit 1; if (depth!=0) exit 1; if (firstnonspace!="{") exit 1; exit 0 }
  ' "$file"
}

# Echo the depth-1 (top-level) object keys of a JSON <file>, one per line.
# String-aware char scan: a string that CLOSES at depth 1 and is immediately
# followed (skipping whitespace) by ':' is a key. Layout-agnostic.
_mcp_toplevel_keys() {
  awk '
    { line=$0; n=length(line)
      for(i=1;i<=n;i++){ c=substr(line,i,1)
        if(instr){
          if(esc){esc=0; buf=buf c; continue}
          if(c=="\\"){esc=1; buf=buf c; continue}
          if(c=="\""){ instr=0
            if(depth==1){ j=i+1
              while(j<=n && (substr(line,j,1)==" "||substr(line,j,1)=="\t")) j++
              if(j<=n && substr(line,j,1)==":") print buf }
            buf=""; continue }
          buf=buf c; continue }
        if(c=="\""){instr=1; buf=""; continue}
        if(c=="{"||c=="[")depth++; else if(c=="}"||c=="]")depth-- } }
  ' "$1" 2>/dev/null
}

# Echo the container member keys (depth-2 keys that are DIRECT children of the
# named <container> top-level object) of a JSON <file>, one per line. String-aware,
# layout-agnostic: tracks depth + whether the currently-open depth-1 key is the
# container, and reports keys that close at depth 2 while inside it.
_mcp_container_keys() {
  local file="$1" container="$2"
  awk -v container="$container" '
    { line=$0; n=length(line)
      for(i=1;i<=n;i++){ c=substr(line,i,1)
        if(instr){
          if(esc){esc=0; buf=buf c; continue}
          if(c=="\\"){esc=1; buf=buf c; continue}
          if(c=="\""){ instr=0
            j=i+1
            while(j<=n && (substr(line,j,1)==" "||substr(line,j,1)=="\t")) j++
            iskey=(j<=n && substr(line,j,1)==":")
            if(iskey && depth==1 && buf==container){ pending_container=1 }
            else if(iskey && depth==2 && in_container){ print buf }
            buf=""; continue }
          buf=buf c; continue }
        if(c=="\""){instr=1; buf=""; continue}
        if(c=="{"||c=="["){ depth++; if(pending_container){in_container=1;container_depth=depth;pending_container=0} }
        else if(c=="}"||c=="]"){ if(in_container && depth==container_depth){in_container=0} depth-- } } }
  ' "$file" 2>/dev/null
}

# mcp_preservation_ok <infile> <outfile> <container>  -- returns 0 iff every
# non-CLAIRE item in <infile> survives in <outfile>, else 1. Non-CLAIRE =
# every top-level key EXCEPT the container (CLAIRE-managed; may be cleaned when
# it holds only CLAIRE entries) + every container member key NOT carrying the
# reserved prefix.
mcp_preservation_ok() {
  local infile="$1" outfile="$2" container="$3" k
  local out_top out_sub
  out_top="$(_mcp_toplevel_keys "$outfile")"
  out_sub="$(_mcp_container_keys "$outfile" "$container")"
  # (1) every non-container top-level key survives.
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    [[ "$k" == "$container" ]] && continue
    printf '%s\n' "$out_top" | grep -qxF "$k" || return 1
  done < <(_mcp_toplevel_keys "$infile")
  # (2) every non-CLAIRE container member key survives.
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    case "$k" in "$MCP_RESERVED_PREFIX"*) continue ;; esac
    printf '%s\n' "$out_sub" | grep -qxF "$k" || return 1
  done < <(_mcp_container_keys "$infile" "$container")
  return 0
}

# --- adopt-path reserved-key collision guard (AC-6 / DEC-002) ----------------
# Echo the container member keys in <file> that carry the reserved prefix but are
# NOT owned by CLAIRE's manifest (an adopter squatting the reserved namespace),
# one per line. A reserved-prefixed key that IS a manifest key is CLAIRE's own
# (idempotent re-add), never a collision.
_mcp_reserved_collisions() {
  local file="$1" manifest="$2" container="$3" k
  local mkeys; mkeys="$(mcp_manifest_keys "$manifest")"
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    case "$k" in "$MCP_RESERVED_PREFIX"*) ;; *) continue ;; esac
    printf '%s\n' "$mkeys" | grep -qxF "$k" && continue   # CLAIRE's own -> fine
    echo "$k"
  done < <(_mcp_container_keys "$file" "$container")
}

# mcp_adopt_reserved_key_guard <file> <manifest> <container>  -- ADOPT-PATH ONLY
# (mirrors cc_adopt_reserved_basename_guard). Returns 0 when <file> is absent/empty
# or owns no non-manifest reserved-prefix key. Returns 1 -- warning loud+actionable,
# emitting mcp.registry.reserved_key_collision -- when the adopter already registers
# an MCP server under a reserved `claire-` key CLAIRE does not own. Refuse +
# instruct rather than clobber the adopter's namespace-squatting entry; the caller
# (adopt) then aborts loudly. The sync path (upgrade) does NOT call this guard.
mcp_adopt_reserved_key_guard() {
  local file="$1" manifest="$2" container="$3" collide
  [[ -f "$file" && -s "$file" ]] || return 0
  collide="$(_mcp_reserved_collisions "$file" "$manifest" "$container")"
  [[ -n "$collide" ]] || return 0
  emit_seam IMPOSSIBLE_STATE mcp.registry.reserved_key_collision "$file"
  echo "mcp_registry_add: refusing -- $file registers an MCP server under a RESERVED" >&2
  echo "  CLAIRE key prefix ('${MCP_RESERVED_PREFIX}') that CLAIRE does not own:" >&2
  while IFS= read -r k; do printf '    %s\n' "$k"; done <<<"$collide" >&2
  echo "  The '${MCP_RESERVED_PREFIX}' server-key prefix is CLAIRE's reserved namespace (DEC-002)." >&2
  echo "  RENAME your MCP server to a non-'${MCP_RESERVED_PREFIX}' key and retry the adopt." >&2
  return 1
}
