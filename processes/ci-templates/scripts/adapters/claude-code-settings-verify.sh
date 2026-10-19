#!/usr/bin/env bash
#
# claude-code-settings-verify.sh -- the settings.json PRESERVATION postcondition
# (BTG-008 review fix B1). Sourced by adapters/claude-code-hooks.sh; kept as its
# own module so claude-code-hooks.sh stays under the 300-line DX gate. Ships to
# adopters via the ci-templates/scripts/adapters COPY_PATH (whole-dir copy).
#
# The pure-shell settings engine (_cc_settings_rewrite) assumes CADENCE's exact
# canonical pretty-printed layout. cc_json_wellformed only proves brace/quote
# balance -- NOT canonical layout -- so a well-formed-but-non-canonical file
# (compact single-line, alt indentation, inline arrays) would be MISREAD, silently
# dropping adopter content, and still return 0 (the old postcondition only checked
# that CADENCE entries LANDED, never that non-CADENCE content SURVIVED).
#
# This module adds the contract-correct, LAYOUT-AGNOSTIC guard: before the atomic
# rename, verify the universal invariant "every non-CADENCE item present in the
# input is present in the output":
#   (1) every top-level key in the input (EXCEPT the CADENCE-managed `hooks` key,
#       which may legitimately disappear when it holds only CADENCE entries) is
#       present in the output;
#   (2) every non-CADENCE command path in the input (a ${CLAUDE_PROJECT_DIR}/...
#       command that does NOT reference .claude/cadence-hooks/) survives in the
#       output.
# If the invariant fails, the caller refuses (no write, source untouched) and
# fails loud -- the specified AC-3 "refuse + instruct" behavior for a
# non-canonical file (an adopter is told to canonicalize and retry; we do NOT
# teach the shell parser arbitrary JSON -- that needs jq / is out of scope).

# JSON well-formedness (string-aware brace/bracket/quote balance check). Not a
# full validator: it proves balance + leading '{', which catches the truncated /
# unbalanced settings.json the fail-loud contract must refuse. 0 = well-formed-ish.
cc_json_wellformed() {
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
# followed (skipping whitespace) by ':' is a key. Layout-agnostic (works on
# compact single-line and multi-line/indented input alike).
_cc_toplevel_keys() {
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

# Echo the NON-CADENCE ${CLAUDE_PROJECT_DIR}/... command paths in <file> (those
# referencing neither .claude/cadence-hooks/ nor -- when <legacy_re> is given --
# a legacy .agents/hooks/<known> CADENCE command), one per line, deduped. A
# legacy CADENCE command is intentionally removed on relocation, so it is NOT
# adopter content and must not be required to survive.
_cc_noncadence_cmdpaths() {
  local file="$1" legacy_re="${2:-}" paths
  paths="$(grep -oE '\$\{CLAUDE_PROJECT_DIR\}/[^"\\]+' "$file" 2>/dev/null \
             | grep -vF '${CLAUDE_PROJECT_DIR}/.claude/cadence-hooks/')"
  [[ -n "$legacy_re" ]] && paths="$(printf '%s\n' "$paths" | grep -vE "$legacy_re")"
  printf '%s\n' "$paths" | LC_ALL=C sort -u
}

# cc_settings_preservation_ok <infile> <outfile> [legacy_re]  -- returns 0 iff
# every non-CADENCE item in <infile> survives in <outfile>, else 1.
cc_settings_preservation_ok() {
  local infile="$1" outfile="$2" legacy_re="${3:-}" k p
  local out_keys; out_keys="$(_cc_toplevel_keys "$outfile")"
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    [[ "$k" == "hooks" ]] && continue          # CADENCE-managed; may be cleaned away
    printf '%s\n' "$out_keys" | grep -qxF "$k" || return 1
  done < <(_cc_toplevel_keys "$infile")
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    grep -qF "$p" "$outfile" || return 1
  done < <(_cc_noncadence_cmdpaths "$infile" "$legacy_re")
  return 0
}

# --- BTG-009: adopt-path reserved-basename collision guard -------------------
# Echo the ${CLAUDE_PROJECT_DIR}/... command paths in <file> that DO match the
# legacy reserved-basename regex (the inverse of _cc_noncadence_cmdpaths's
# exclusion), one per line, deduped. Empty <legacy_re> -> nothing. Anchored on the
# ${CLAUDE_PROJECT_DIR}/.agents/hooks/<known> command form (NB-3), so a deeper
# vendor-nested path that merely contains a reserved basename is not matched.
_cc_legacy_cmdpaths() {
  local file="$1" legacy_re="${2:-}"
  [[ -f "$file" && -n "$legacy_re" ]] || return 0
  grep -oE '\$\{CLAUDE_PROJECT_DIR\}/[^"\\]+' "$file" 2>/dev/null \
    | grep -E "$legacy_re" | LC_ALL=C sort -u
}

# cc_adopt_reserved_basename_guard <file> <legacy_re>  -- ADOPT-PATH ONLY guard
# (BTG-009 / AC-1). Returns 0 when <file> is absent/empty or registers no command
# under a reserved CADENCE legacy basename. Returns 1 -- warning loud+actionable --
# when a pre-existing entry references ${CLAUDE_PROJECT_DIR}/.agents/hooks/<known>.
# On the adopt path there is no stamped base to tell a real pre-BTG-008 CADENCE
# install from an adopter's name collision, so that entry would be dropped by the
# legacy-relocation classifier (DEC-004) with no R-6 guard (R-6 covers only the
# upgrade path). Refuse + instruct rather than silently drop the adopter's entry;
# the caller (adopt) then aborts loudly. The upgrade path (cc_hook_settings_sync)
# does NOT call this guard -- its relocation is R-6-vetted (AC-2/AC-3 untouched).
cc_adopt_reserved_basename_guard() {
  local file="$1" legacy_re="${2:-}" collide
  [[ -f "$file" && -s "$file" && -n "$legacy_re" ]] || return 0
  collide="$(_cc_legacy_cmdpaths "$file" "$legacy_re")"
  # Empty collide -> proceed. On the theoretical case of a present-but-unreadable
  # file this fails open here, but never yields a silent drop: _cc_settings_upsert's
  # downstream cc_json_wellformed + cc_settings_preservation_ok checks then refuse.
  [[ -n "$collide" ]] || return 0
  emit_seam UNSOUND_CONDITION hook.settings.reserved_basename_collision "$file"
  echo "cc_hook_settings_add: refusing -- $file registers a hook under a RESERVED" >&2
  echo "  CADENCE legacy basename in .agents/hooks/:" >&2
  while IFS= read -r p; do printf '    %s\n' "$p"; done <<<"$collide" >&2
  echo "  Adopting CADENCE would drop this entry (that path is CADENCE's reserved" >&2
  echo "  legacy-migration namespace, DEC-004). RENAME your hook to a non-reserved" >&2
  echo "  basename under .agents/hooks/ (avoid tms-sync-reminder.sh / tms-doc-sync-stop.sh)" >&2
  echo "  and retry the adopt." >&2
  return 1
}
