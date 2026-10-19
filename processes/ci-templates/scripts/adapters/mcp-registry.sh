#!/usr/bin/env bash
#
# mcp-registry.sh -- the shared, runtime-neutral MCP-server registration engine
# (BTG-057 / DEC-003). Generalized from claude-code-hooks.sh's _cc_settings_rewrite
# into a depth-tracked, string-aware awk key-surgery core parameterized on the
# runtime's MCP CONTAINER KEY (`mcpServers` for Claude .mcp.json, `mcp` for
# OpenCode opencode.json) and an ENTRY-RENDERER function. Two thin shims
# (claude-code-mcp.sh; the MCP primitives in opencode.sh) supply the concretes.
# It defines:
#
#   mcp_registry_add    <config-file> <manifest> <container-key> <render-fn>
#   mcp_registry_sync   <config-file> <manifest> <container-key> <render-fn>
#   mcp_registry_remove <config-file> [container-key]
#   mcp_manifest_rows / mcp_manifest_keys / mcp_manifest_validate
#
# Ownership sentinel (DEC-002): a container member entry is CLAIRE-owned iff its
# key carries the reserved prefix `claire-` (MCP_RESERVED_PREFIX). add/sync/remove
# operate only on keys matching the sentinel -- never guessing. All writes are
# ATOMIC (temp + mv) and FAIL-LOUD (mcp.config.unparseable on a non-well-formed
# file; mcp.config.noncanonical on a well-formed-but-non-canonical file whose
# surgical edit would drop adopter content) -- never a partial/corrupt write. Pure
# POSIX shell; NO `jq` (DEC-003 -- matches the hooks constraint exactly).

# The preservation postcondition + wellformedness + adopt guard live in a sourced
# sibling module so this file stays under the DX line ceiling (BTG-008 split
# precedent). It ships to adopters via the same COPY_PATH (whole-dir copy).
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-registry-verify.sh"

# --- neutral mcp.manifest reader --------------------------------------------
# Echo "key|image|env|enabled_tools|transport|url|header" per manifest row (in
# file order). Fields are whitespace-separated key=value tokens; the abstract->
# concrete render is the shim.
#
# BTG-059 / DEC-008: an ADDITIVE remote-http transport form sits alongside the
# original docker form. A row is DOCKER when it carries image= (image/env/
# enabled_tools populated; transport/url/header empty) and REMOTE-HTTP when it
# carries transport=http (url/header populated; image/env/enabled_tools empty).
# header= is captured to END-OF-LINE (it MUST be the last token on the row) so a
# value with a space -- e.g. `header=Authorization:Bearer ${YOUTRACK_TOKEN}` --
# is preserved intact; every other field is a single whitespace-free token.
mcp_manifest_rows() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 0
  local line k img env et transport url header
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    k="$(printf '%s\n'   "$line" | sed -nE 's/.*(^|[[:space:]])key=([^[:space:]]+).*/\2/p')"
    img="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])image=([^[:space:]]+).*/\2/p')"
    env="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])env=([^[:space:]]+).*/\2/p')"
    et="$(printf '%s\n'  "$line" | sed -nE 's/.*(^|[[:space:]])enabled_tools=([^[:space:]]+).*/\2/p')"
    transport="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])transport=([^[:space:]]+).*/\2/p')"
    url="$(printf '%s\n'  "$line" | sed -nE 's/.*(^|[[:space:]])url=([^[:space:]]+).*/\2/p')"
    header="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])header=(.*)$/\2/p')"
    [[ -n "$k" ]] || continue
    echo "$k|$img|$env|$et|$transport|$url|$header"
  done < "$manifest"
}

# Echo one manifest server-key per line (the CLAIRE-owned reserved-prefix set).
mcp_manifest_keys() {
  local manifest="$1" row
  mcp_manifest_rows "$manifest" | while IFS='|' read -r row _; do echo "$row"; done
}

# _mcp_split_pair <token>  -- split one manifest env token into its server-config-key
# and adopter-env-var source, setting _MCP_PAIR_KEY / _MCP_PAIR_SRC. A colon-less
# token means key==source (`FOO` -> key FOO / source FOO). The split is `%%:*`
# (key = up to the first colon) and `##*:` (source = after the last colon), exactly
# as both renderers previously inlined it -- extracted here (the shared engine both
# shims source) so the two copies cannot drift (DEC-013). The `mcp-golden` byte-diff
# over both adapters is the behavioral safety net.
_mcp_split_pair() {
  _MCP_PAIR_KEY="${1%%:*}"
  _MCP_PAIR_SRC="${1##*:}"
}

# _mcp_env_pair_ok <token>  -- returns 0 iff <token> is a well-formed env pair
# per the DEC-011a grammar hardened by DEC-013: a colon-less token (key==source)
# is VALID; a single-colon `key:source` token is VALID iff BOTH sides are non-empty;
# an empty token, an empty-sided token (`:BAR` / `FOO:`), or a multi-colon token
# (`A:B:C` -- ambiguous under the renderer's `%%:*`/`##*:` split, which would
# silently drop the middle) is INVALID. Kept beside the split helper both renderers
# use so the accept-set and the render-set cannot drift.
_mcp_env_pair_ok() {
  local pair="$1"
  [[ -n "$pair" ]] || return 1            # empty token
  case "$pair" in
    *:*:*) return 1 ;;                    # >1 colon -- ambiguous, reject
    *:*)  [[ -n "${pair%%:*}" && -n "${pair##*:}" ]] || return 1 ;;  # both sides non-empty
    *) : ;;                               # colon-less -- key==source, valid
  esac
  return 0
}

# mcp_manifest_validate <manifest>  -- fail loud if any row's server-key lacks the
# reserved prefix (mcp.manifest.reserved_key_missing, DEC-002 schema check, S-6.3)
# OR carries a malformed env=key:source pair (mcp.manifest.malformed_env_pair,
# DEC-013 grammar hardening, S-6.4). Returns 0 when every row passes both checks
# (or the manifest is absent/empty).
mcp_manifest_validate() {
  local manifest="$1" k env et transport url header rc=0 pair
  local -a _toks
  while IFS='|' read -r k _ env et transport url header; do
    [[ -n "$k" ]] || continue
    case "$k" in
      "$MCP_RESERVED_PREFIX"*) ;;
      *) emit_seam IMPOSSIBLE_STATE mcp.manifest.reserved_key_missing "$k"
         echo "mcp_manifest_validate: refusing -- manifest server-key '$k' lacks the reserved" >&2
         echo "  '${MCP_RESERVED_PREFIX}' prefix (the ownership sentinel, DEC-002)." >&2
         rc=1 ;;
    esac
    # Remote-http transport form (BTG-059 / DEC-008): a row carrying transport=http
    # MUST carry both url= and header= (else a broken remote entry would render
    # silently, Behavior 5). Docker rows (image=, no transport=http) are unchanged.
    if [[ "$transport" == "http" ]]; then
      if [[ -z "$url" || -z "$header" ]]; then
        emit_seam IMPOSSIBLE_STATE mcp.manifest.remote_http_incomplete "$k transport=http"
        echo "mcp_manifest_validate: refusing -- manifest row '$k' is transport=http but is" >&2
        echo "  missing url= or header= (a remote-http row needs both, BTG-059/DEC-008)." >&2
        rc=1
      fi
    fi
    # Env-pair grammar (DEC-013): validate every comma-separated env token so a
    # broken `"": "${}"` reference can never render silently (Behavior 5).
    if [[ -n "$env" ]]; then
      IFS=',' read -ra _toks <<< "$env"
      for pair in "${_toks[@]}"; do
        _mcp_env_pair_ok "$pair" && continue
        emit_seam IMPOSSIBLE_STATE mcp.manifest.malformed_env_pair "$k env='$pair'"
        echo "mcp_manifest_validate: refusing -- manifest row '$k' env token '$pair' is malformed;" >&2
        echo "  each token must be '<server-key>:<adopter-var>' (both sides non-empty) or a colon-less" >&2
        echo "  '<name>' (key==source) -- never empty, empty-sided, or multi-colon (DEC-013)." >&2
        rc=1
      done
    fi
  done < <(mcp_manifest_rows "$manifest")
  return $rc
}

# --- the surgical parse-to-model + reserialize core --------------------------
# Reads <infile> (canonical config, or /dev/null for absent), DROPS every
# CLAIRE-owned container member (key ^claire-), then re-inserts the entries
# from <specfile> (empty for remove). Preserves every non-container top-level key
# and every adopter-owned container member byte-for-byte; cleans an emptied
# container object. Prints the rewritten JSON to stdout. Depth-tracked, string-
# aware (a value string carrying { } / " cannot fool the structure).
_mcp_registry_rewrite() {
  local infile="$1" specfile="$2" container="$3"
  awk -v specfile="$specfile" -v container="$container" -v prefix="$MCP_RESERVED_PREFIX" '
    function depthscan(s,   i,c,n){ n=length(s)
      for(i=1;i<=n;i++){ c=substr(s,i,1)
        if(instr){ if(esc)esc=0; else if(c=="\\")esc=1; else if(c=="\"")instr=0; continue }
        if(c=="\""){instr=1;continue}
        if(c=="{"||c=="[")depth++; else if(c=="}"||c=="]")depth-- } }
    function stripcomma(s){ sub(/,[[:space:]]*$/,"",s); return s }
    function keyname(s,   t){ if(match(s,/"[^"]+"/)){ t=substr(s,RSTART+1,RLENGTH-2); return t } return "" }
    function is_claire(k){ return (substr(k,1,length(prefix))==prefix) }
    function printblock(b,suf,  a,m,j){ m=split(b,a,"\n")
      for(j=1;j<=m;j++){ if(j==m)print a[j] suf; else print a[j] } }
    function finalize_entry(  t){ t=stripcomma(eb)
      if(!is_claire(curkey)){ adopt_ent[++n_ad]=t } }
    BEGIN{ depth=0;instr=0;esc=0;mode="OUT";n_tb=0;n_item=0;n_ad=0;n_spec=0;cont_seen=0
      if(specfile!=""){ blk=""; inblk=0
        while((getline line < specfile)>0){
          if(line=="ENTRY"){ inblk=1; blk=""; continue }
          if(line=="ENDENTRY"){ spec_ent[++n_spec]=blk; inblk=0; continue }
          if(inblk){ blk=blk (blk!=""?"\n":"") line } } } }
    { db=depth; depthscan($0); da=depth; line=$0
      if(mode=="OUT"){ if(line ~ /^[[:space:]]*{/)mode="IN"; next }
      if(mode=="IN"){
        if(da==0)next
        if(db==1 && line ~ ("^[[:space:]]*\"" container "\"[[:space:]]*:")){
          cont_seen=1; n_item++; item_kind[n_item]="cont"; mode="CONT"; next }
        if(db==1 && line ~ /^[[:space:]]*"[^"]+"[[:space:]]*:/){ tb=line
          if(da<=1){ topblocks[++n_tb]=stripcomma(tb); n_item++; item_kind[n_item]="tb"; item_tb[n_item]=n_tb } else mode="TOPBLOCK"; next }
        next }
      if(mode=="TOPBLOCK"){ tb=tb "\n" line
        if(da<=1){ topblocks[++n_tb]=stripcomma(tb); n_item++; item_kind[n_item]="tb"; item_tb[n_item]=n_tb; mode="IN" } next }
      if(mode=="CONT"){
        if(da<=1){ mode="IN"; next }
        if(line ~ /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*{/){ curkey=keyname(line); eb=line
          if(da<=2)finalize_entry(); else mode="ENTRY"; next }
        next }
      if(mode=="ENTRY"){ eb=eb "\n" line; if(da<=2){ finalize_entry(); mode="CONT" } next } }
    END{ has_cont=(n_ad>0 || n_spec>0)?1:0
      if(has_cont && !cont_seen){ n_item++; item_kind[n_item]="cont" }
      ec=0
      for(i=1;i<=n_item;i++){ if(item_kind[i]=="tb" || (item_kind[i]=="cont" && has_cont)) ec++ }
      print "{"; done=0
      for(i=1;i<=n_item;i++){
        if(item_kind[i]=="tb"){ done++; printblock(topblocks[item_tb[i]], (done<ec)?",":"") }
        else if(item_kind[i]=="cont" && has_cont){ done++
          print "  \"" container "\": {"
          nmem=0
          for(j=1;j<=n_ad;j++)mem[++nmem]=adopt_ent[j]
          for(j=1;j<=n_spec;j++)mem[++nmem]=spec_ent[j]
          for(k=1;k<=nmem;k++)printblock(mem[k], (k<nmem)?",":"")
          print (done<ec)?"  },":"  }" } }
      print "}" }
  ' "$infile"
}

# --- public: add / sync (idempotent upsert) ---------------------------------
# mcp_registry_add/sync <config-file> <manifest> <container-key> <render-fn>
_mcp_registry_upsert() {
  local file="$1" manifest="$2" container="$3" render="$4" infile spec tmp
  mcp_manifest_validate "$manifest" || return 1
  if [[ -f "$file" && -s "$file" ]]; then
    if ! mcp_json_wellformed "$file"; then
      emit_seam IMPOSSIBLE_STATE mcp.config.unparseable "$file"
      echo "mcp_registry: refusing -- $file is present but not well-formed JSON; edit it manually." >&2
      return 1
    fi
    infile="$file"
  else
    infile="/dev/null"
  fi
  spec="$(mktemp)"; "$render" "$manifest" > "$spec"
  # Create the atomic-replace temp IN THE TARGET DIRECTORY so the final `mv` is a
  # genuine same-filesystem rename (atomic), never a cross-fs copy+unlink that
  # could leave a partial config on a mid-mv interrupt (review N2). Requires the
  # target dir to exist first.
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "$(dirname "$file")/.mcp-registry.tmp.XXXXXX")"
  if ! _mcp_registry_rewrite "$infile" "$spec" "$container" > "$tmp"; then
    rm -f "$spec" "$tmp"; return 1
  fi
  # Post-condition: the CLAIRE entries must have landed (LINEAGE_GAP if not).
  if [[ -s "$spec" ]] && ! grep -q "\"${MCP_RESERVED_PREFIX}" "$tmp"; then
    emit_seam LINEAGE_GAP mcp.config.postcondition_missing "$file"
    echo "mcp_registry: the CLAIRE entries did not land in $file." >&2
    rm -f "$spec" "$tmp"; return 1
  fi
  # Preservation postcondition: a non-canonical input the pure-shell engine cannot
  # parse without dropping adopter content is REFUSED (no write, source untouched)
  # -- never a best-effort partial edit (AC-7 / DEC-003).
  if [[ "$infile" != "/dev/null" ]] && ! mcp_preservation_ok "$infile" "$tmp" "$container"; then
    emit_seam IMPOSSIBLE_STATE mcp.config.noncanonical "$file"
    echo "mcp_registry: refusing -- $file is well-formed but NON-CANONICAL; a surgical" >&2
    echo "  edit would drop adopter-owned content. Canonicalize it (CLAIRE pretty-printed" >&2
    echo "  layout, 2-space indent, one server key per line) and retry." >&2
    rm -f "$spec" "$tmp"; return 1
  fi
  mv "$tmp" "$file"       # atomic same-fs rename (temp created beside target)
  rm -f "$spec"
}

mcp_registry_add() {
  local file="$1" manifest="$2" container="$3" render="$4"
  mcp_adopt_reserved_key_guard "$file" "$manifest" "$container" || return 1
  _mcp_registry_upsert "$file" "$manifest" "$container" "$render"
}
mcp_registry_sync() { _mcp_registry_upsert "$1" "$2" "$3" "$4"; }

# --- public: remove (surgical deregistration; empty-container cleanup) -------
# mcp_registry_remove <config-file> <container-key>
mcp_registry_remove() {
  local file="$1" container="${2:-mcpServers}" tmp
  [[ -f "$file" && -s "$file" ]] || return 0   # absent/empty -> no-op
  if ! mcp_json_wellformed "$file"; then
    emit_seam IMPOSSIBLE_STATE mcp.config.unparseable "$file"
    echo "mcp_registry_remove: refusing -- $file is present but not well-formed JSON." >&2
    return 1
  fi
  # Temp beside the target (same-fs atomic rename; review N2). $file exists here.
  tmp="$(mktemp "$(dirname "$file")/.mcp-registry.tmp.XXXXXX")"
  if ! _mcp_registry_rewrite "$file" "" "$container" > "$tmp"; then rm -f "$tmp"; return 1; fi
  if ! mcp_preservation_ok "$file" "$tmp" "$container"; then
    emit_seam IMPOSSIBLE_STATE mcp.config.noncanonical "$file"
    echo "mcp_registry_remove: refusing -- $file is well-formed but NON-CANONICAL;" >&2
    echo "  a surgical edit would drop adopter-owned content. Canonicalize it and retry." >&2
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$file"       # atomic same-fs rename (temp created beside target)
}
