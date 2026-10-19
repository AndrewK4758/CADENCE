#!/usr/bin/env bash
#
# Claude Code adapter (PI-012) -- the ONLY place concrete runtime primitives
# are introduced (ADR_CADENCE-0008 R7 / DEC-003). Compiles the parsed neutral-source
# model into the Claude Code native layout:
#
#   role    -> .agents/agents/<name>/AGENT.md
#   command -> .agents/skills/<name>/SKILL.md  (+ the whole colocated sidecar
#              directory copied verbatim; sidecar_script names the entry point
#              -- PI-023 / DEC-001)
#
# Resolves: tool capabilities -> concrete tool ids ; capability tier ->
# concrete model ; command-composition capability -> the composition-tool
# literal ; body placeholders ({{role:}}, {{role_kind}}, {{invoking_runtime}},
# {{artifact_root:roles|commands}}) -> Claude Code primitives (DEC-009, as
# corrected by DEC-010: the shipped path placeholder is {{artifact_root:<tree>}},
# resolving the tree root only -- there is no {{artifact_path:}}).
#
# This file is sourced by cadence-compile.sh; it relies on the parse helpers
# (fm_value, body_block) defined there. It defines:
#   cc_adapter_emit_role    <src-file> <out-root>
#   cc_adapter_emit_command <src-file> <out-root> <src-root>
#   cc_resolve_path_key     <path_key>   (echo native emitted path)
#
# SOURCES a sibling module (BTG-247): the placeholder-expansion and
# {{role:}}-validation functions (cc_expand_body, cc_expand_sidecar,
# cc_residual_sidecar, cc_residual_placeholders, cc_validate_role_refs) live
# in claude-code-placeholders.sh, pulled in below via a
# ${BASH_SOURCE[0]}-relative path -- the same self-locating sourcing shape
# org-binding-parse.sh and authored-doc-gate.sh already use for their own
# siblings. Any caller sourcing this file transitively gets that module too.

# Per-adapter function prefix (DEC-006): the compiler dispatch resolves each
# adapter's entry points by this prefix ("${ADAPTER_FN_PREFIX}_adapter_emit_*",
# "${ADAPTER_FN_PREFIX}_prune_orphans"), removing the old hardcoded cc_ calls.
# shellcheck disable=SC2034  # read by compile-manifest.sh after load_adapter.
ADAPTER_FN_PREFIX="cc"

# --- Capability -> concrete tool id map (RC-4) ----------------------------
cc_tool_id() {
  case "$1" in
    read)            echo "Read" ;;
    write)           echo "Write" ;;
    edit)            echo "Edit" ;;
    glob)            echo "Glob" ;;
    content-search)  echo "Grep" ;;
    shell)           echo "Bash" ;;
    web-fetch)       echo "WebFetch" ;;
    command-composition) echo "Skill" ;;
    *) echo "" ;;
  esac
}

# --- Capability tier -> concrete model map (RC-1/AC-4 R14) -----------------
# Sourced conceptually from CADENCE_ORG.md#model-tier-mapping. A tier absent
# here is a hard failure (AC-2 edge: never emit an empty model:).
cc_tier_model() {
  case "$1" in
    Deep-reasoning)  echo "claude-opus-5-5" ;;
    Fast-mechanical) echo "claude-sonnet-5" ;;
    *) echo "" ;;
  esac
}

# Parse a neutral bracketed list value, e.g. "[read, write, edit]" -> words.
cc_parse_list() {
  echo "$1" | sed -E 's/^\[//; s/\]$//; s/,/ /g'
}

# Render a JSON array of quoted tool ids from a neutral capability list value.
# Echoes e.g. ["Read", "Write", "Edit"]
cc_tools_json() {
  local listval="$1" cap id out=""
  for cap in $(cc_parse_list "$listval"); do
    id="$(cc_tool_id "$cap")"
    if [[ -z "$id" ]]; then
      echo "__UNKNOWN_CAPABILITY__:$cap" >&2
      return 1
    fi
    out="${out:+$out, }\"$id\""
  done
  echo "[$out]"
}

# Render a space-separated allowed-tools list (skill frontmatter form).
cc_tools_spaced() {
  local listval="$1" cap id out=""
  for cap in $(cc_parse_list "$listval"); do
    id="$(cc_tool_id "$cap")"
    if [[ -z "$id" ]]; then
      echo "__UNKNOWN_CAPABILITY__:$cap" >&2
      return 1
    fi
    out="${out:+$out }$id"
  done
  echo "$out"
}

# Resolve a manifest path_key (e.g. commands/cadence-adopt) to the emitted
# native path Claude Code uses. roles/* -> .agents/agents/<name> ;
# commands/* -> .agents/skills/<name>. NOTE: this is NOT wired to a body
# placeholder -- the shipped body path placeholder is {{artifact_root:<tree>}}
# (tree root only; DEC-010). A whole-path-by-identity placeholder is a candidate
# for the OpenCode adapter ticket (DEC-010 follow-up); this helper is retained
# as the resolution primitive that ticket would build on.
cc_resolve_path_key() {
  local key="$1"
  case "$key" in
    roles/*)    echo ".agents/agents/${key#roles/}" ;;
    commands/*) echo ".agents/skills/${key#commands/}" ;;
    *) echo "$key" ;;
  esac
}

# The placeholder-expansion and role-ref-validation half (cc_expand_body,
# cc_expand_sidecar, cc_residual_sidecar, cc_residual_placeholders,
# cc_validate_role_refs) lives in a sibling module -- BTG-247, this file's own
# split, mirroring org-binding-parse.sh / authored-doc-gate.sh's sourcing
# pattern for their own siblings.
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/claude-code-placeholders.sh"

# --- prune orphaned native outputs (DEC-011) ------------------------------
# Remove emitted Claude outputs that no longer have a source artifact, so a
# role/command deleted from source does not leave a stale tree. The .claude/
# directory-glob knowledge lives HERE (the adapter), not in core compile-manifest
# (ADR_CADENCE-0008 R7). Identical behavior + summary lines to the pre-generalization
# prune_orphans (byte-identical Claude golden / round-trip is the proof).
cc_prune_orphans() {
  local src="$1" out="$2" d name
  for d in "$out"/.agents/agents/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ ! -f "$src/roles/$name.md" ]]; then
      rm -rf "$d"
      echo "  prune orphan role -> .agents/agents/$name (no source artifact)"
    fi
  done
  for d in "$out"/.agents/skills/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ ! -f "$src/commands/$name.md" ]]; then
      rm -rf "$d"
      echo "  prune orphan command -> .agents/skills/$name (no source artifact)"
    fi
  done
}

# --- emit a role -> AGENT.md ----------------------------------------------
cc_adapter_emit_role() {
  local f="$1" out_root="$2"
  local name desc tier toolcaps rationale model tools_json
  load_fm "$f"
  name="${FM[name]}"
  desc="${FM[description]}"
  tier="${FM[capability_tier]}"
  toolcaps="${FM[tool_capabilities]}"
  rationale="${FM[tier_rationale]:-}"

  model="$(cc_tier_model "$tier")"
  if [[ -z "$model" ]]; then
    emit_seam UNSOUND_CONDITION compile.output.missing_artifact "$f tier '$tier' has no model mapping"
    echo "FAIL: role $name tier '$tier' has no concrete-model mapping in the adapter" >&2
    return 1
  fi
  if ! tools_json="$(cc_tools_json "$toolcaps")"; then
    echo "FAIL: role $name has an unknown tool capability: $tools_json" >&2
    return 1
  fi

  local unknown_roles
  if unknown_roles="$(cc_validate_role_refs "$f")"; then :; else
    emit_seam BOUNDARY_FAULT compile.body.unknown_role_ref "$f"
    echo "FAIL: role $f references unknown role(s):$unknown_roles -- no roles/<name>.md source artifact" >&2
    return 1
  fi

  local expanded residual
  expanded="$(body_block "$f" | cc_expand_body)"
  if residual="$(printf '%s\n' "$expanded" | cc_residual_placeholders)"; then :; else
    emit_seam BOUNDARY_FAULT compile.body.residual_placeholder "$f"
    echo "FAIL: role $f has an unresolved placeholder in a normative body position:" >&2
    echo "$residual" | sed 's/^/  /' >&2
    return 1
  fi

  local dir="$out_root/.agents/agents/$name"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $name"
    echo "description: $desc"
    echo "tools: $tools_json"
    [[ -n "$rationale" ]] && echo "# $rationale"
    echo "model: $model"
    echo "---"
    echo ""
    printf '%s\n' "$expanded"
  } > "$dir/AGENT.md"
  echo "  emit role -> .agents/agents/$name/AGENT.md"
}

# --- emit a command -> SKILL.md (+ sidecar) -------------------------------
cc_adapter_emit_command() {
  local f="$1" out_root="$2" src_root="$3"
  local name desc hint args toolcaps sidecar tools_spaced model=""
  load_fm "$f"
  name="${FM[name]}"
  desc="${FM[description]}"
  hint="${FM[argument_hint]:-}"
  args="${FM[arguments]}"
  toolcaps="${FM[allowed_tool_capabilities]}"
  sidecar="${FM[sidecar_script]:-}"

  if ! tools_spaced="$(cc_tools_spaced "$toolcaps")"; then
    echo "FAIL: command $name has an unknown tool capability: $tools_spaced" >&2
    return 1
  fi
  # BTG-134: OPTIONAL for a command, so this keys on KEY PRESENCE, never value
  # truthiness: `${FM[k]+x}` keeps "undeclared" (benign: no model line, AC-2)
  # apart from "declared empty" (an error). cc_tier_model: same map as roles.
  if [[ -n "${FM[capability_tier]+x}" ]]; then
    model="$(cc_tier_model "${FM[capability_tier]}")"
    if [[ -z "$model" ]]; then
      emit_seam UNSOUND_CONDITION compile.output.missing_artifact "$f tier '${FM[capability_tier]}' has no model mapping"
      echo "FAIL: command $name tier '${FM[capability_tier]}' has no concrete-model mapping in the adapter" >&2
      return 1
    fi
  fi

  local unknown_roles
  if unknown_roles="$(cc_validate_role_refs "$f")"; then :; else
    emit_seam BOUNDARY_FAULT compile.body.unknown_role_ref "$f"
    echo "FAIL: command $f references unknown role(s):$unknown_roles -- no roles/<name>.md source artifact" >&2
    return 1
  fi

  local expanded residual
  expanded="$(body_block "$f" | cc_expand_body)"
  if residual="$(printf '%s\n' "$expanded" | cc_residual_placeholders)"; then :; else
    emit_seam BOUNDARY_FAULT compile.body.residual_placeholder "$f"
    echo "FAIL: command $f has an unresolved placeholder in a normative body position:" >&2
    echo "$residual" | sed 's/^/  /' >&2
    return 1
  fi

  local dir="$out_root/.agents/skills/$name"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $name"
    echo "description: $desc"
    echo "argument-hint: $hint"
    echo "arguments: $args"
    echo "allowed-tools: $tools_spaced"
    [[ -n "$model" ]] && echo "model: $model"
    echo "---"
    echo ""
    printf '%s\n' "$expanded"
  } > "$dir/SKILL.md"
  echo "  emit command -> .agents/skills/$name/SKILL.md"

  if [[ -n "$sidecar" ]]; then
    local sc_dir="$src_root/commands/$name"   # the colocated sidecar directory
    local sc_src="$sc_dir/$sidecar"           # the declared entry-point script
    if [[ ! -f "$sc_src" ]]; then
      emit_seam DELTA_AUDIT_GAP compile.output.missing_artifact "command $name sidecar entry-point not found: $sc_src"
      echo "FAIL: command $name sidecar entry-point not found at $sc_src" >&2
      return 1
    fi
    # PI-023 (DEC-001) + PI-024 (DEC-010): emit the ENTIRE colocated sidecar
    # directory, but EXPANDED per-runtime (not a raw cp -R) so sidecar .sh paths
    # are portable. A sorted walk emits each text file through cc_expand_sidecar
    # (placeholders resolve back to identical .claude/ strings -> byte-identical
    # golden); mode bits are preserved via chmod --reference (an executable
    # sidecar stays executable). Binary files are copied verbatim. The <name>.md
    # command file is a SIBLING of "$sc_dir", so SKILL.md is never clobbered;
    # whole-directory completeness (II-016) is preserved; deterministic
    # (--reproduce proves it).
    local file rel res
    while IFS= read -r -d '' file; do
      rel="${file#"$sc_dir/"}"
      mkdir -p "$dir/$(dirname "$rel")"
      if LC_ALL=C grep -Iq '' "$file"; then
        cc_expand_sidecar < "$file" > "$dir/$rel"
        if res="$(cc_residual_sidecar < "$dir/$rel")"; then :; else
          emit_seam BOUNDARY_FAULT compile.body.residual_placeholder "$sc_dir/$rel"
          echo "FAIL: sidecar $sc_dir/$rel has an unresolved placeholder after expansion:" >&2
          echo "$res" >&2
          return 1
        fi
      else
        cp "$file" "$dir/$rel"
      fi
      chmod --reference="$file" "$dir/$rel"
    done < <(find "$sc_dir" -type f -print0 | LC_ALL=C sort -z)
    echo "  copy sidecar dir -> .agents/skills/$name/ (entry point: $sidecar)"
  fi
}
