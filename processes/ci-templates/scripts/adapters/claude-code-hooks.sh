#!/usr/bin/env bash
#
# Claude Code adapter -- hooks sub-module (BTG-008). The ONLY home for the
# Claude Code hook primitives (ADR_CADENCE-0008 R7 / DEC-002): the compiled hooks tree
# path (.claude/cadence-hooks/), the settings.json JSON shape, the concrete
# hook event names (Stop / PostToolUse) and matcher (Edit|Write), and the
# ${CLAUDE_PROJECT_DIR} command form. Sourced by the compiler (for the verbatim
# hook emit) and by adopt/upgrade/eject (for the settings.json render/upsert/
# remove/relocate). It defines:
#
#   cc_adapter_emit_hook   <src-file> <out-root>
#   cc_hook_settings_add   <settings-file> <hooks-manifest>
#   cc_hook_settings_sync  <settings-file> <hooks-manifest>
#   cc_hook_settings_remove <settings-file> [hooks-manifest]
#   cc_hook_relocate_files <target-root> <hooks-manifest>
#
# Ownership sentinel (DEC-002): a settings.json hook entry is CADENCE-owned iff
# its `command` references .claude/cadence-hooks/. The pre-BTG-008 legacy set is
# a `command` referencing .agents/hooks/<known-basename> (from hooks.manifest).
# All settings writes are ATOMIC (temp + mv) and FAIL-LOUD (UNSOUND_CONDITION
# hook.settings.unparseable) on a present-but-non-well-formed file -- never a
# partial/corrupt write. Pure POSIX shell; no `jq` (DEC-002 / Alternative 4).

# Reuse a shared emit_seam if the caller already defined one; else define it.
if ! declare -F emit_seam >/dev/null 2>&1; then
  emit_seam() {
    local seam_type="$1" event_name="$2" subject="${3:-}"
    echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
  }
fi

# BTG-008 (review fix B1): the settings.json preservation postcondition lives in a
# sourced sibling module so this file stays under the 300-line DX gate. It ships
# to adopters via the ci-templates/scripts/adapters COPY_PATH (whole-dir copy).
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claude-code-settings-verify.sh"

# --- compile: emit one hook verbatim into .claude/cadence-hooks/ -----------
# A hook compiles by a VERBATIM copy -- no frontmatter, no body placeholder
# expansion (DEC-001). The native tree literal lives here (the adapter), never
# in a core compile module.
cc_adapter_emit_hook() {
  local f="$1" out_root="$2"
  local name; name="$(basename "$f")"
  local dir="$out_root/.claude/cadence-hooks"
  mkdir -p "$dir"
  cp "$f" "$dir/$name"
  if [[ ! -f "$dir/$name" ]]; then
    emit_seam DELTA_AUDIT_GAP compile.output.missing_artifact "hook $name did not land in $dir"
    echo "FAIL: hook $name did not land in .claude/cadence-hooks/" >&2
    return 1
  fi
  echo "  emit hook -> .claude/cadence-hooks/$name"
}

# --- neutral hooks.manifest reader ------------------------------------------
# Echo "event script timeout" per hook row (in manifest file order). Fields are
# abstract (event = stop|post-edit); the abstract->concrete mapping is below.
cc_hook_manifest_rows() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 0
  local line ev sc to
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ev="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])event=([^[:space:]]+).*/\2/p')"
    sc="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])script=([^[:space:]]+).*/\2/p')"
    to="$(printf '%s\n' "$line" | sed -nE 's/.*(^|[[:space:]])timeout=([^[:space:]]+).*/\2/p')"
    [[ -n "$ev" && -n "$sc" ]] || continue
    [[ -n "$to" ]] || to=15
    echo "$ev $sc $to"
  done < "$manifest"
}

# Map an abstract event token to the concrete Claude Code event name.
cc_hook_map_event() {
  case "$1" in
    stop)      echo "Stop" ;;
    post-edit) echo "PostToolUse" ;;
    *)         echo "" ;;
  esac
}
# Map an abstract event token to its concrete matcher (empty = no matcher key).
cc_hook_map_matcher() {
  case "$1" in
    post-edit) echo "Edit|Write" ;;
    *)         echo "" ;;
  esac
}

# The known CADENCE hook basenames (from the manifest) -- the legacy-migration
# detection set and the relocation removal set. Echoes one basename per line.
cc_hook_known_basenames() {
  local manifest="$1" ev sc to
  cc_hook_manifest_rows "$manifest" | while read -r ev sc to; do echo "$sc"; done
}

# cc_hook_relocate_files <target-root> <hooks-manifest> -- remove ONLY the known
# CADENCE basenames from <target-root>/.agents/hooks/ (pre-BTG-008 legacy loc).
# NEVER globs, NEVER removes an adopter's own hook, NEVER removes the .claude/
# hooks/ dir. Echoes each removed rel path (the caller emits the relocated seam).
# Idempotent. The .claude/ literal lives here in the adapter (ADR_CADENCE-0008 R7).
cc_hook_relocate_files() {
  local target="$1" manifest="$2" b
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    if [[ -f "$target/.agents/hooks/$b" ]]; then
      rm -f "$target/.agents/hooks/$b" && echo ".agents/hooks/$b"
    fi
  done < <(cc_hook_known_basenames "$manifest")
}

# cc_json_wellformed + the preservation postcondition: see claude-code-settings-verify.sh.
# --- render the canonical CADENCE entries as an EVENT/ENTRY intermediate ----
# One EVENT block per manifest row (the abstract event mapped to its concrete
# Claude Code event + matcher). The command points at .claude/cadence-hooks/
# (the ownership sentinel). Deterministic serialization CADENCE controls.
cc_hook_render_cadence() {
  local manifest="$1" ev sc to cev matcher
  cc_hook_manifest_rows "$manifest" | while read -r ev sc to; do
    cev="$(cc_hook_map_event "$ev")"; [[ -n "$cev" ]] || continue
    matcher="$(cc_hook_map_matcher "$ev")"
    echo "EVENT $cev"
    echo "ENTRY"
    echo "      {"
    [[ -n "$matcher" ]] && printf '        "matcher": "%s",\n' "$matcher"
    echo '        "hooks": ['
    echo '          {'
    echo '            "type": "command",'
    echo '            "shell": "bash",'
    printf '            "command": "bash \\"${CLAUDE_PROJECT_DIR}/.claude/cadence-hooks/%s\\"",\n' "$sc"
    printf '            "timeout": %s\n' "$to"
    echo '          }'
    echo '        ]'
    echo "      }"
    echo "ENDENTRY"
    echo "ENDEVENT"
  done
}

# Build an ERE matching a legacy pre-BTG-008 command path .agents/hooks/<known>
# for the manifest's known CADENCE basenames. Empty if no manifest/basenames.
cc_hook_legacy_regex() {
  local manifest="$1" b b_esc re=""
  [[ -f "$manifest" ]] || { echo ""; return 0; }
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    b_esc="$(printf '%s' "$b" | sed 's/\./[.]/g')"
    re="${re:+$re|}$b_esc"
  done < <(cc_hook_known_basenames "$manifest")
  # NB-3: anchored on the ${CLAUDE_PROJECT_DIR}/.agents/hooks/ command form
  # ([$][{]...[}] = literal braces in ERE) so a deeper vendor path is not matched.
  [[ -n "$re" ]] && echo "[$][{]CLAUDE_PROJECT_DIR[}]/[.]claude/hooks/($re)" || echo ""
}

# --- the surgical parse-to-model + reserialize core --------------------------
# Reads <infile> (canonical settings.json, or /dev/null for absent), DROPS every
# CADENCE-owned hook entry (command references .claude/cadence-hooks/, or a
# legacy .agents/hooks/<known> path via <legacy_re>), then re-inserts the entries
# from <specfile> (empty for remove). Preserves every non-hooks top-level key and
# every project-owned hook entry byte-for-byte; cleans emptied event arrays + an
# emptied hooks object. Prints the rewritten JSON to stdout. Depth-tracked,
# string-aware (a command string carrying { } / \" cannot fool the structure).
_cc_settings_rewrite() {
  local infile="$1" specfile="$2" legacy_re="$3"
  awk -v specfile="$specfile" -v legacyre="$legacy_re" '
    function depthscan(s,   i,c,n){ n=length(s)
      for(i=1;i<=n;i++){ c=substr(s,i,1)
        if(instr){ if(esc)esc=0; else if(c=="\\")esc=1; else if(c=="\"")instr=0; continue }
        if(c=="\""){instr=1;continue}
        if(c=="{"||c=="[")depth++; else if(c=="}"||c=="]")depth-- } }
    function stripcomma(s){ sub(/,[[:space:]]*$/,"",s); return s }
    function is_cadence(t){ if(index(t,"${CLAUDE_PROJECT_DIR}/.claude/cadence-hooks/")>0)return 1
      if(legacyre!="" && t ~ legacyre)return 1; return 0 }
    function finalize_entry(  t){ t=stripcomma(eb)
      if(!is_cadence(t)){ proj_ent[curev]=proj_ent[curev] (proj_ent[curev]!=""?SUBSEP:"") t } }
    function printblock(b,suf,  a,m,j){ m=split(b,a,"\n")
      for(j=1;j<=m;j++){ if(j==m)print a[j] suf; else print a[j] } }
    BEGIN{ depth=0;instr=0;esc=0;mode="OUT";n_tb=0;n_ev=0;n_spec=0;n_item=0;hooks_seen=0
      if(specfile!=""){ cur=""
        while((getline line < specfile)>0){
          if(line ~ /^EVENT /){ cur=substr(line,7); if(!(cur in spec_has)){spec_has[cur]=1;spec_order[++n_spec]=cur} }
          else if(line=="ENTRY"){ eb2="" }
          else if(line=="ENDENTRY"){ spec_ent[cur]=spec_ent[cur] (spec_ent[cur]!=""?SUBSEP:"") eb2 }
          else if(line=="ENDEVENT"){}
          else { eb2=eb2 (eb2!=""?"\n":"") line } } } }
    { db=depth; depthscan($0); da=depth; line=$0
      if(mode=="OUT"){ if(line ~ /^[[:space:]]*{/)mode="IN"; next }
      if(mode=="IN"){
        if(da==0)next
        if(line ~ /^[[:space:]]*"hooks"[[:space:]]*:/){ mode="HOOKS"; curev=""
          if(!hooks_seen){hooks_seen=1; n_item++; item_kind[n_item]="hooks"} next }
        if(line ~ /^[[:space:]]*"[^"]+"[[:space:]]*:/){ tb=line
          if(da<=1){ topblocks[++n_tb]=stripcomma(tb); n_item++; item_kind[n_item]="tb"; item_tb[n_item]=n_tb } else mode="TOPBLOCK"; next }
        next }
      if(mode=="TOPBLOCK"){ tb=tb "\n" line
        if(da<=1){ topblocks[++n_tb]=stripcomma(tb); n_item++; item_kind[n_item]="tb"; item_tb[n_item]=n_tb; mode="IN" } next }
      if(mode=="HOOKS"){
        if(da<=1){ mode="IN"; next }
        if(line ~ /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*\[/){
          match(line,/"[^"]+"/); curev=substr(line,RSTART+1,RLENGTH-2)
          if(!(curev in ev_has)){ev_has[curev]=1;ev_order[++n_ev]=curev}; mode="EVENT"; next }
        next }
      if(mode=="EVENT"){
        if(da<=2){ mode="HOOKS"; next }
        if(line ~ /^[[:space:]]*{/){ eb=line; if(da<=3)finalize_entry(); else mode="ENTRY"; next }
        next }
      if(mode=="ENTRY"){ eb=eb "\n" line; if(da<=3){ finalize_entry(); mode="EVENT" } next } }
    END{ ne=0
      for(i=1;i<=n_ev;i++){ merged[++ne]=ev_order[i]; seen[ev_order[i]]=1 }
      for(i=1;i<=n_spec;i++){ if(!(spec_order[i] in seen)){ merged[++ne]=spec_order[i]; seen[spec_order[i]]=1 } }
      nec=0
      for(i=1;i<=ne;i++){ e=merged[i]; if(proj_ent[e]!="" || spec_ent[e]!="")evfinal[++nec]=e }
      has_hooks=(nec>0)?1:0
      # NB-2: a "hooks" item that becomes empty (all entries removed) is dropped;
      # if hooks were absent in the input but CADENCE entries exist (add on a file
      # with no hooks key), append the hooks item last.
      if(has_hooks && !hooks_seen){ n_item++; item_kind[n_item]="hooks" }
      # Effective item count (topblocks always count; the hooks item iff has_hooks).
      ec=0
      for(i=1;i<=n_item;i++){ if(item_kind[i]=="tb" || (item_kind[i]=="hooks" && has_hooks)) ec++ }
      print "{"; done=0
      for(i=1;i<=n_item;i++){
        if(item_kind[i]=="tb"){ done++; printblock(topblocks[item_tb[i]], (done<ec)?",":"") }
        else if(item_kind[i]=="hooks" && has_hooks){ done++
          print "  \"hooks\": {"
          for(e2=1;e2<=nec;e2++){ e=evfinal[e2]; print "    \"" e "\": ["
            n_all=0
            if(proj_ent[e]!=""){ np=split(proj_ent[e],pa,SUBSEP); for(j=1;j<=np;j++)all_ent[++n_all]=pa[j] }
            if(spec_ent[e]!=""){ nsp=split(spec_ent[e],sa,SUBSEP); for(j=1;j<=nsp;j++)all_ent[++n_all]=sa[j] }
            for(k=1;k<=n_all;k++){ printblock(all_ent[k], (k<n_all)?",":"") }
            print (e2<nec)?"    ],":"    ]" }
          print (done<ec)?"  },":"  }" } }
      print "}" }
  ' "$infile"
}

# --- public: add / sync (idempotent upsert) ---------------------------------
_cc_settings_upsert() {
  local file="$1" manifest="$2" infile spec legacy_re tmp
  if [[ -f "$file" && -s "$file" ]]; then
    if ! cc_json_wellformed "$file"; then
      emit_seam UNSOUND_CONDITION hook.settings.unparseable "$file"
      echo "cc_hook_settings: refusing -- $file is present but not well-formed JSON; edit it manually." >&2
      return 1
    fi
    infile="$file"
  else
    infile="/dev/null"
  fi
  spec="$(mktemp)"; cc_hook_render_cadence "$manifest" > "$spec"
  legacy_re="$(cc_hook_legacy_regex "$manifest")"
  tmp="$(mktemp)"
  if ! _cc_settings_rewrite "$infile" "$spec" "$legacy_re" > "$tmp"; then
    rm -f "$spec" "$tmp"; return 1
  fi
  if [[ -s "$spec" ]] && ! grep -q '/.claude/cadence-hooks/' "$tmp"; then
    emit_seam DELTA_AUDIT_GAP hook.settings.postcondition_missing "$file"
    echo "cc_hook_settings: the CADENCE entries did not land in $file." >&2
    rm -f "$spec" "$tmp"; return 1
  fi
  # B1 preservation postcondition: a non-canonical input that the pure-shell
  # engine cannot parse without dropping adopter content is REFUSED (no write,
  # source untouched) -- never a best-effort partial edit (AC-3 / DEC-002 / R-1).
  if [[ "$infile" != "/dev/null" ]] && ! cc_settings_preservation_ok "$infile" "$tmp" "$legacy_re"; then
    emit_seam UNSOUND_CONDITION hook.settings.unparseable "$file"
    echo "cc_hook_settings: refusing -- $file is well-formed but NON-CANONICAL; a surgical" >&2
    echo "  edit would drop project-owned content. Canonicalize .claude/settings.json (CADENCE" >&2
    echo "  pretty-printed layout, 2-space indent) and retry." >&2
    rm -f "$spec" "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$file")"
  mv "$tmp" "$file"       # atomic replace
  rm -f "$spec"
}
cc_hook_settings_add()  { cc_adopt_reserved_basename_guard "$1" "$(cc_hook_legacy_regex "$2")" && _cc_settings_upsert "$1" "$2"; }
cc_hook_settings_sync() { _cc_settings_upsert "$1" "$2"; }

# --- public: remove (surgical deregistration; empty-section cleanup) --------
cc_hook_settings_remove() {
  local file="$1" manifest="${2:-}" legacy_re tmp
  [[ -f "$file" && -s "$file" ]] || return 0   # absent/empty -> no-op
  if ! cc_json_wellformed "$file"; then
    emit_seam UNSOUND_CONDITION hook.settings.unparseable "$file"
    echo "cc_hook_settings_remove: refusing -- $file is present but not well-formed JSON." >&2
    return 1
  fi
  legacy_re="$(cc_hook_legacy_regex "$manifest")"
  tmp="$(mktemp)"
  if ! _cc_settings_rewrite "$file" "" "$legacy_re" > "$tmp"; then rm -f "$tmp"; return 1; fi
  # B1 preservation postcondition (see _cc_settings_upsert): refuse a non-canonical
  # file rather than ship a content-dropping deliverable.
  if ! cc_settings_preservation_ok "$file" "$tmp" "$legacy_re"; then
    emit_seam UNSOUND_CONDITION hook.settings.unparseable "$file"
    echo "cc_hook_settings_remove: refusing -- $file is well-formed but NON-CANONICAL;" >&2
    echo "  a surgical edit would drop project-owned content. Canonicalize it and retry." >&2
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$file"
}
