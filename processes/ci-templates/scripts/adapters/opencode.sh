#!/usr/bin/env bash
#
# OpenCode adapter (PI-024) -- the sibling of claude-code.sh and the ONLY place
# OpenCode-concrete runtime primitives are introduced (ADR_CLAIRE-0008 R7 / DEC-003).
# Compiles the parsed neutral-source model into the OpenCode native layout:
#
#   role    -> .opencode/agents/<name>.md     (PLURAL dir; DEC-009)
#   command -> .opencode/commands/<name>.md   (+ the whole colocated sidecar
#              directory, EXPANDED per-runtime -- not raw cp -R; DEC-010)
#
# Confirmed OpenCode format (OQ-1 / DEC-009, official docs + sst/opencode source,
# pinned 2026-06-25; the golden gate catches future drift):
#   - PLURAL .opencode/agents|commands/<name>.md (singular is back-compat only).
#   - Tool/permission control is the `permission:` map (deny-by-default,
#     last-matching-rule-wins), NOT the deprecated boolean `tools:` map.
#   - Agent frontmatter: description (required), mode: primary|subagent|all,
#     model: <provider>/<model-id>, permission:.
#   - Command frontmatter: description, template (body), permission:.
#
# RC-3 command-composition is a KNOWN GAP on OpenCode (DEC-008): the `task`
# permission is GRANTED but no concrete command->command wiring is produced
# (no neutral delegation-target field), so a command declaring the capability
# emits but does not compose. RC-3 is fully satisfied on Claude Code.
#
# The set of affected commands is DERIVED, never enumerated here: this note used
# to name two of them, and BTG-208 granted the capability to three more, which
# would have left a stale list reading as an exhaustive one. Every command whose
# `allowed_tool_capabilities` carries `command-composition` is affected; read
# them out of artifacts/commands/ rather than from this comment.
#
# WHAT A COMMAND MUST DO ABOUT IT is a property of the command, not of this
# adapter, and BTG-208 fixed its shape: a composing step states a CAPABILITY
# PRECONDITION and, where the host runtime cannot compose, files nothing,
# allocates nothing, never simulates the callee, and emits a named notice
# recording the exact command a human can run instead. That contract is
# runtime-neutral by construction, so it holds here without this adapter
# changing behaviour.
#
# HOOKS -- sanctioned n/a (Claude-only), BTG-023 / DEC-001..DEC-003: hooks are a
# Claude-only capability (BTG-008 / BTG-022 OQ-2). OpenCode has NO hooks binding.
# The two hook-lifecycle placeholder families {{artifact_root:hooks}} and
# {{settings_file}} -- and, from BTG-198, the context-include placeholder (RC-7),
# for which this repository has no evidence of an OpenCode primitive and refuses
# to invent one -- therefore resolve to the ONLY value that exists -- the Claude
# concrete path (.claude/claire-hooks / .claude/settings.json), NOT a
# speculative .opencode/... value (OQ-2 rejected that). This is compile-time
# path-token resolution to keep shared sidecar text gate-clean; it asserts NO
# hooks capability -- emit_hooks skips for OpenCode (compile-hooks.sh capability
# guard) and no .opencode/claire-hooks tree is emitted. Coherent with the
# fenced literal .claude/claire-hooks/ at upgrade-repair.sh:153 that already
# ships verbatim to .opencode/ output.
#
# MCP -- unlike HOOKS, OpenCode genuinely HAS an MCP capability (opencode.json's
# `mcp` block). The OpenCode MCP-registration primitives (oc_mcp_render /
# oc_mcp_registry_add/sync/remove, BTG-057 / DEC-007) live in the sibling
# adapters/opencode-mcp.sh (extracted here for DX symmetry with claude-code-mcp.sh
# -- review N1 / DEC-007a). Consumers source that file directly; this compile
# adapter does not.
#
# Sourced by claire-compile.sh; relies on the parse helpers (load_fm,
# body_block) and emit_seam already in scope. It defines:
#   oc_adapter_emit_role    <src-file> <out-root>
#   oc_adapter_emit_command <src-file> <out-root> <src-root>
#   oc_resolve_path_key     <path_key>
#   oc_prune_orphans        <src> <out>

# Per-adapter function prefix (DEC-006): the compiler dispatch resolves entry
# points by this prefix. shellcheck disable=SC2034 (read after load_adapter).
# shellcheck disable=SC2034
ADAPTER_FN_PREFIX="oc"

# --- Capability -> concrete OpenCode tool id map (RC-4) --------------------
# command-composition -> `task` permission GRANT only (RC-3 KNOWN GAP, DEC-008).
# NOTE: the hot emit loops (oc_allowed_ids / oc_assert_capability) inline this
# same case to stay fork-free under the <1s compile NFR; keep them in sync.
oc_tool_id() {
  case "$1" in
    read)            echo "read" ;;
    write)           echo "write" ;;
    edit)            echo "edit" ;;
    glob)            echo "glob" ;;
    content-search)  echo "grep" ;;
    shell)           echo "bash" ;;
    web-fetch)       echo "webfetch" ;;
    command-composition) echo "task" ;;
    *) echo "" ;;
  esac
}

# Inline tool-id resolution (NO fork): sets the global __OC_TOOL_ID for a cap,
# "" if unmappable. Mirrors oc_tool_id (kept in sync) -- used by the hot loops.
oc_tool_id_inline() {
  case "$1" in
    read) __OC_TOOL_ID=read ;; write) __OC_TOOL_ID=write ;;
    edit) __OC_TOOL_ID=edit ;; glob) __OC_TOOL_ID=glob ;;
    content-search) __OC_TOOL_ID=grep ;; shell) __OC_TOOL_ID=bash ;;
    web-fetch) __OC_TOOL_ID=webfetch ;; command-composition) __OC_TOOL_ID=task ;;
    *) __OC_TOOL_ID="" ;;
  esac
}

# --- Capability tier -> concrete model map (RC-1) --------------------------
# OpenCode model strings are <provider>/<model-id> (DEC-009). A tier absent here
# is a hard failure (never emit an empty model:). Concrete ids are the
# illustrative reference instance (CLAIRE_ORG.md#runtime-binding); the golden
# gate pins them.
oc_tier_model() {
  case "$1" in
    Deep-reasoning)  echo "anthropic/claude-opus-5-5" ;;
    Fast-mechanical) echo "anthropic/claude-sonnet-5" ;;
    *) echo "" ;;
  esac
}

# Parse a neutral bracketed list value, e.g. "[read, write, edit]" -> words.
# Pure bash parameter expansion (NO fork) -- the <1s compile NFR is fork-bound.
oc_parse_list() {
  local v="${1#\[}"; v="${v%\]}"; echo "${v//,/ }"
}

# Echo the space-separated OpenCode tool ids for a neutral capability list.
# Fails (non-zero, names the cap on stderr) on an unmappable capability.
oc_allowed_ids() {
  local v="${1#\[}" cap out=""; v="${v%\]}"; v="${v//,/ }"
  for cap in $v; do
    oc_tool_id_inline "$cap"
    if [[ -z "$__OC_TOOL_ID" ]]; then
      echo "__UNKNOWN_CAPABILITY__:$cap" >&2
      return 1
    fi
    out="${out:+$out }$__OC_TOOL_ID"
  done
  echo "$out"
}

# Render the OpenCode `permission:` map for a neutral capability list as a
# DENY-BY-DEFAULT allowlist (RC-1, R27): "*": deny first, then the sensitive
# write/side-effecting keys explicitly denied when NOT allowed (RC-5 read-only
# enforcement, R28 -- OpenCode ships exactly this as its review.md example),
# then allow for each of the artifact's tool keys (last-matching-rule-wins).
# Reads the list value as $1; writes indented YAML map lines on stdout.
oc_permission_map() {
  local listval="$1" allowed id k present
  allowed="$(oc_allowed_ids "$listval")" || return 1
  echo '  "*": deny'
  # Sensitive keys denied explicitly when absent from the allowlist (RC-5).
  for k in bash edit webfetch; do
    present=0
    for id in $allowed; do [[ "$id" == "$k" ]] && present=1; done
    [[ $present -eq 0 ]] && echo "  $k: deny"
  done
  # Allow each granted key, in declaration order (deterministic).
  for id in $allowed; do
    echo "  $id: allow"
  done
}

# Resolve a manifest path_key to the emitted native OpenCode path. roles/* ->
# .opencode/agents/<name> ; commands/* -> .opencode/commands/<name>. NOT wired
# to a body placeholder (the body placeholders are expanded by oc_expand_body).
oc_resolve_path_key() {
  local key="$1"
  case "$key" in
    roles/*)    echo ".opencode/agents/${key#roles/}" ;;
    commands/*) echo ".opencode/commands/${key#commands/}" ;;
    *) echo "$key" ;;
  esac
}

# Expand body placeholders into OpenCode primitives (DEC-009/DEC-010/DEC-012).
# Reads body on stdin, writes expanded body on stdout.
oc_expand_body() {
  sed -E \
    -e 's/\{\{role:([a-z0-9-]+)\}\}/`\1` subagent/g' \
    -e 's/\{\{role_kind\}\}/subagent/g' \
    -e 's/\{\{invoking_runtime\}\}/OpenCode/g' \
    -e 's#\{\{artifact_path:roles:([a-z0-9-]+)\}\}#.opencode/agents/\1.md#g' \
    -e 's#\{\{artifact_path:commands:([a-z0-9-]+)\}\}#.opencode/commands/\1.md#g' \
    -e 's#\{\{sidecar:([a-z0-9-]+):([^}]+)\}\}#.opencode/commands/\1/\2#g' \
    -e 's#\{\{artifact_glob:roles\}\}#.opencode/agents/*.md#g' \
    -e 's#\{\{artifact_glob:commands\}\}#.opencode/commands/*.md#g' \
    -e 's#\{\{runtime_root\}\}#.opencode#g' \
    -e 's#\{\{artifact_root:roles\}\}#.opencode/agents#g' \
    -e 's#\{\{artifact_root:commands\}\}#.opencode/commands#g' \
    -e 's#\{\{artifact_root:hooks\}\}#.claude/claire-hooks#g' \
    -e 's#\{\{settings_file\}\}#.claude/settings.json#g' \
    -e 's#\{\{context_import:([^}]+)\}\}#@\1#g'
}

# Expand a sidecar .sh text file's PATH placeholders per-runtime (DEC-010): the
# path set only (artifact_root/path, sidecar, artifact_glob, runtime_root) --
# NOT the {{role:}} delegation phrasing (sidecars carry no role refs). Reads
# stdin, writes stdout.
oc_expand_sidecar() {
  sed -E \
    -e 's#\{\{artifact_path:roles:([a-z0-9-]+)\}\}#.opencode/agents/\1.md#g' \
    -e 's#\{\{artifact_path:commands:([a-z0-9-]+)\}\}#.opencode/commands/\1.md#g' \
    -e 's#\{\{sidecar:([a-z0-9-]+):([^}]+)\}\}#.opencode/commands/\1/\2#g' \
    -e 's#\{\{artifact_glob:roles\}\}#.opencode/agents/*.md#g' \
    -e 's#\{\{artifact_glob:commands\}\}#.opencode/commands/*.md#g' \
    -e 's#\{\{runtime_root\}\}#.opencode#g' \
    -e 's#\{\{artifact_root:roles\}\}#.opencode/agents#g' \
    -e 's#\{\{artifact_root:commands\}\}#.opencode/commands#g' \
    -e 's#\{\{artifact_root:hooks\}\}#.claude/claire-hooks#g' \
    -e 's#\{\{settings_file\}\}#.claude/settings.json#g' \
    -e 's#\{\{context_import:([^}]+)\}\}#@\1#g'
}

# After expansion, any residual sanctioned-FAMILY placeholder (a typo'd tree/
# name that did not expand) is a hard error. Scoped to the placeholder families
# so legitimate shell brace-tokens (e.g. printf '{{%s}}') are NOT flagged.
# Reads the ALREADY-EXPANDED text on stdin; echoes "<lineno>: <content>" per
# offending line and returns 1 if any residual, else 0.
oc_residual_sidecar() {
  local out
  out="$(grep -nE '\{\{(role:|role_kind|invoking_runtime|artifact_root:|artifact_path:|sidecar:|artifact_glob:|runtime_root|settings_file|context_import:)')"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | sed 's/^/  /'
    return 1
  fi
  return 0
}

# Guard against silent pass-through of an unknown/typo'd placeholder in a body.
# Identical heading-bounded discipline to cc_residual_placeholders: worked-
# example / labelled-example / binding regions are excluded. Reads the
# ALREADY-EXPANDED body on stdin; echoes offending lines, returns 1 if any.
oc_residual_placeholders() {
  awk '
    BEGIN { drop=0 }
    {
      if (drop==0) {
        if ($0 ~ /^## Worked Example/) { drop=2; next }
        if ($0 ~ /^### Example/)       { drop=3; next }
        if ($0 ~ /^## Example/)        { drop=2; next }
        if ($0 ~ /^## Runtime Binding/){ drop=2; next }
      } else {
        if (drop==2 && $0 ~ /^## [^#]/)      { drop=0 }
        else if (drop==3 && $0 ~ /^### [^#]/) { drop=0 }
        else if (drop==3 && $0 ~ /^## [^#]/)  { drop=0 }
        else { next }
        if ($0 ~ /^## Worked Example/ || $0 ~ /^## Example/ || $0 ~ /^## Runtime Binding/) { drop=2; next }
        if ($0 ~ /^### Example/) { drop=3; next }
      }
      if ($0 ~ /\{\{[^}]*\}\}/) { print NR": "$0; found=1 }
    }
    END { exit (found ? 1 : 0) }
  '
}

# Validate every {{role:<name>}} reference in a body against the known-role set
# (the sibling roles/*.md basenames). A reference with no source is a hard
# error. Identical to cc_validate_role_refs.
oc_validate_role_refs() {
  local f="$1"
  local roles_dir; roles_dir="$(dirname "$f")"
  case "$roles_dir" in
    */commands) roles_dir="${roles_dir%/commands}/roles" ;;
  esac
  local refs ref unknown=""
  refs="$(grep -oE '\{\{role:[a-z0-9-]+\}\}' "$f" | sed -E 's/\{\{role:([a-z0-9-]+)\}\}/\1/' | LC_ALL=C sort -u)"
  for ref in $refs; do
    [[ -f "$roles_dir/$ref.md" ]] || unknown="$unknown $ref"
  done
  if [[ -n "$unknown" ]]; then
    echo "$unknown"
    return 1
  fi
  return 0
}

# Defensive hard-refuse guard (AC-6 / DEC-001): before emit, assert every tool
# capability the artifact declares is expressible in OpenCode. With OQ-1/OQ-2
# resolved (DEC-009/DEC-008) it never fires for the real set -- command-
# composition is GRANTED (task), not refused -- only for the synthetic negative-
# control fixture requiring an unmappable capability. Reads the frontmatter via
# the already-loaded FM array; <1> is the artifact path, <2> the capability
# field name (tool_capabilities | allowed_tool_capabilities).
oc_assert_capability() {
  local f="$1" field="$2" v cap id
  v="${FM[$field]:-}"; v="${v#\[}"; v="${v%\]}"; v="${v//,/ }"
  for cap in $v; do
    oc_tool_id_inline "$cap"; id="$__OC_TOOL_ID"
    if [[ -z "$id" ]]; then
      emit_seam SEAM_VIOLATION compile.capability.unsupported "$f RC-1 $cap"
      echo "FAIL: $f requires capability '$cap' which OpenCode cannot express (RC-1)" >&2
      return 1
    fi
  done
  return 0
}

# Optional neutral-source tail scan (AC-4 / OQ-3): flag a literal AGENT.md /
# SKILL.md filename tail in a NORMATIVE body position (outside a labelled region)
# -- a recommended backstop that the .md tail ban does not regress. NOT wired as
# a live gate (claire-review.md intentionally keeps "AGENT.md §10" per DEC-017);
# exercised by OS-4.1. <1> = body file. Emits a seam per hit; returns 1 if any.
oc_scan_unneutralized_tail() {
  local f="$1" hit=0 lineno=0 drop=0 line
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    case "$line" in
      '## Worked Example'*|'## Example'*|'## Runtime Binding'*|'### Example'*) drop=1; continue ;;
      '## '*|'### '*) drop=0 ;;
    esac
    [[ $drop -eq 1 ]] && continue
    if printf '%s' "$line" | grep -qE '(AGENT|SKILL)\.md'; then
      emit_seam SEAM_VIOLATION compile.body.unneutralized_tail "$f:$lineno"
      hit=$((hit + 1))
    fi
  done < "$f"
  [[ $hit -eq 0 ]]
}

# --- prune orphaned native outputs (DEC-011) ------------------------------
# OpenCode emits FLAT files; prune the flat .opencode/agents/*.md +
# .opencode/commands/*.md (and any colocated .opencode/commands/<name>/ sidecar
# dir) with no source artifact. The .opencode/ glob knowledge lives HERE.
oc_prune_orphans() {
  local src="$1" out="$2" f name
  for f in "$out"/.opencode/agents/*.md; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f" .md)"
    if [[ ! -f "$src/roles/$name.md" ]]; then
      rm -f "$f"
      echo "  prune orphan role -> .opencode/agents/$name.md (no source artifact)"
    fi
  done
  for f in "$out"/.opencode/commands/*.md; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f" .md)"
    if [[ ! -f "$src/commands/$name.md" ]]; then
      rm -f "$f"
      rm -rf "$out/.opencode/commands/$name"
      echo "  prune orphan command -> .opencode/commands/$name.md (no source artifact)"
    fi
  done
}

# --- emit a role -> .opencode/agents/<name>.md ----------------------------
oc_adapter_emit_role() {
  local f="$1" out_root="$2"
  local name desc tier toolcaps model
  load_fm "$f"
  name="${FM[name]}"
  desc="${FM[description]}"
  tier="${FM[capability_tier]}"
  toolcaps="${FM[tool_capabilities]}"

  oc_assert_capability "$f" tool_capabilities || return 1

  model="$(oc_tier_model "$tier")"
  if [[ -z "$model" ]]; then
    emit_seam IMPOSSIBLE_STATE compile.output.missing_artifact "$f tier '$tier' has no model mapping"
    echo "FAIL: role $name tier '$tier' has no concrete-model mapping in the adapter" >&2
    return 1
  fi

  local unknown_roles
  if unknown_roles="$(oc_validate_role_refs "$f")"; then :; else
    emit_seam SEAM_VIOLATION compile.body.unknown_role_ref "$f"
    echo "FAIL: role $f references unknown role(s):$unknown_roles -- no roles/<name>.md source artifact" >&2
    return 1
  fi

  local permission expanded residual
  permission="$(oc_permission_map "$toolcaps")" || {
    echo "FAIL: role $name has an unknown tool capability" >&2; return 1; }
  expanded="$(body_block "$f" | oc_expand_body)"
  if residual="$(printf '%s\n' "$expanded" | oc_residual_placeholders)"; then :; else
    emit_seam SEAM_VIOLATION compile.body.residual_placeholder "$f"
    echo "FAIL: role $f has an unresolved placeholder in a normative body position:" >&2
    echo "$residual" | sed 's/^/  /' >&2
    return 1
  fi

  mkdir -p "$out_root/.opencode/agents"
  {
    echo "---"
    echo "description: $desc"
    echo "mode: subagent"
    echo "model: $model"
    echo "permission:"
    printf '%s\n' "$permission"
    echo "---"
    echo ""
    printf '%s\n' "$expanded"
  } > "$out_root/.opencode/agents/$name.md"
  echo "  emit role -> .opencode/agents/$name.md"
}

# --- emit a command -> .opencode/commands/<name>.md (+ EXPANDED sidecar) ---
oc_adapter_emit_command() {
  local f="$1" out_root="$2" src_root="$3"
  local name desc toolcaps sidecar model=""
  load_fm "$f"
  name="${FM[name]}"
  desc="${FM[description]}"
  toolcaps="${FM[allowed_tool_capabilities]}"
  sidecar="${FM[sidecar_script]:-}"

  oc_assert_capability "$f" allowed_tool_capabilities || return 1
  # BTG-134: OPTIONAL for a command, so this keys on KEY PRESENCE, never value
  # truthiness: `${FM[k]+x}` keeps "undeclared" (benign: no model line, AC-2)
  # apart from "declared empty" (an error). oc_tier_model: same map as roles --
  # its values are provider-prefixed, so the two mirrors differ by construction.
  if [[ -n "${FM[capability_tier]+x}" ]]; then
    model="$(oc_tier_model "${FM[capability_tier]}")"
    if [[ -z "$model" ]]; then
      emit_seam IMPOSSIBLE_STATE compile.output.missing_artifact "$f tier '${FM[capability_tier]}' has no model mapping"
      echo "FAIL: command $name tier '${FM[capability_tier]}' has no concrete-model mapping in the adapter" >&2
      return 1
    fi
  fi

  local unknown_roles
  if unknown_roles="$(oc_validate_role_refs "$f")"; then :; else
    emit_seam SEAM_VIOLATION compile.body.unknown_role_ref "$f"
    echo "FAIL: command $f references unknown role(s):$unknown_roles -- no roles/<name>.md source artifact" >&2
    return 1
  fi

  local permission expanded residual
  permission="$(oc_permission_map "$toolcaps")" || {
    echo "FAIL: command $name has an unknown tool capability" >&2; return 1; }
  expanded="$(body_block "$f" | oc_expand_body)"
  if residual="$(printf '%s\n' "$expanded" | oc_residual_placeholders)"; then :; else
    emit_seam SEAM_VIOLATION compile.body.residual_placeholder "$f"
    echo "FAIL: command $f has an unresolved placeholder in a normative body position:" >&2
    echo "$residual" | sed 's/^/  /' >&2
    return 1
  fi

  mkdir -p "$out_root/.opencode/commands"
  {
    echo "---"
    echo "description: $desc"
    [[ -n "$model" ]] && echo "model: $model"
    echo "permission:"
    printf '%s\n' "$permission"
    echo "---"
    echo ""
    printf '%s\n' "$expanded"
  } > "$out_root/.opencode/commands/$name.md"
  echo "  emit command -> .opencode/commands/$name.md"

  if [[ -n "$sidecar" ]]; then
    local sc_dir="$src_root/commands/$name"
    local sc_src="$sc_dir/$sidecar"
    if [[ ! -f "$sc_src" ]]; then
      emit_seam LINEAGE_GAP compile.output.missing_artifact "command $name sidecar entry-point not found: $sc_src"
      echo "FAIL: command $name sidecar entry-point not found at $sc_src" >&2
      return 1
    fi
    local dest="$out_root/.opencode/commands/$name"
    mkdir -p "$dest"
    # Per-runtime EXPANSION (DEC-010): a sorted walk emitting each text file
    # through oc_expand_sidecar (replacing raw cp -R), preserving mode bits via
    # chmod --reference, preserving the whole-directory completeness (II-016).
    local file rel res
    while IFS= read -r -d '' file; do
      rel="${file#"$sc_dir/"}"
      mkdir -p "$dest/$(dirname "$rel")"
      if LC_ALL=C grep -Iq '' "$file"; then   # text file -> expand once
        oc_expand_sidecar < "$file" > "$dest/$rel"
        if res="$(oc_residual_sidecar < "$dest/$rel")"; then :; else
          emit_seam SEAM_VIOLATION compile.body.residual_placeholder "$sc_dir/$rel"
          echo "FAIL: sidecar $sc_dir/$rel has an unresolved placeholder after expansion:" >&2
          echo "$res" >&2
          return 1
        fi
      else                                      # binary -> verbatim
        cp "$file" "$dest/$rel"
      fi
      chmod --reference="$file" "$dest/$rel"
    done < <(find "$sc_dir" -type f -print0 | LC_ALL=C sort -z)
    echo "  emit sidecar dir -> .opencode/commands/$name/ (entry point: $sidecar)"
  fi
}
