#!/usr/bin/env bash
#
# eject-transform.sh -- adopter-mode transform-on-ship for the co-owned
# .claude/settings.json (BTG-008 / DEC-005, OQ-2 Position B). Sourced by
# cadence-eject.sh in this shell's scope (SELF_DIR resolves the adapter).
#
# Bounded context: Source-export / IP-separation flow (PI-017, Workstream B) --
# the co-owned-config transform seam (BTG-008).
# Upstream: called by cadence-eject.sh do_eject after the copy walk, in ADOPTER
#   mode only (a descriptor with no kind=framework_dev rows).
# Downstream: edits ONLY the destination copy of .claude/settings.json (source
#   immutability preserved -- eject stays one-directional); appends a transform
#   line to the eject audit. Spec: specs/BTG-008/spec.md (Eject / DEC-005).
#
# The settings-file path is resolved through the runtime BINDING ({{settings_file}}
# -> .claude/settings.json), so this engine holds NO native .claude/ literal.

# Resolve the co-owned settings-file repo-relative path via the adapter binding
# (the single runtime-coupling home; no native literal in this file).
# >>> binding-resolution (clause-7 exempt) >>>
_eject_settings_rel() {
  local adapter="$SELF_DIR/adapters/claude-code.sh"
  [[ -f "$adapter" ]] || { echo ""; return 1; }
  # shellcheck source=/dev/null
  ( . "$adapter"; printf '{{settings_file}}' | cc_expand_body )
}
# <<< binding-resolution (clause-7 exempt) <<<

# eject_transform_settings <dest> <audit>
#   In adopter mode, if the shipped <dest>/<settings-rel> exists, run
#   cc_hook_settings_remove on that DEST COPY -- dropping CADENCE-owned entries
#   (command references .claude/cadence-hooks/), preserving the project env block
#   and any adopter hook entry, cleaning an emptied event array / empty hooks
#   object. Records the transform in the audit. Fails LOUD (non-zero) if the
#   dest copy is non-canonical (cc_hook_settings_remove refuses) rather than
#   shipping a corrupt config.
eject_transform_settings() {
  local dest="$1" audit="$2" rel target hooks_adapter
  rel="$(_eject_settings_rel)" || return 0   # no adapter -> nothing to transform
  [[ -n "$rel" ]] || return 0
  target="$dest/$rel"
  [[ -f "$target" ]] || return 0             # settings.json not shipped -> no-op
  hooks_adapter="$SELF_DIR/adapters/claude-code-hooks.sh"
  if [[ ! -f "$hooks_adapter" ]]; then
    emit_seam UNSOUND_CONDITION eject.binding.adapter_missing "$hooks_adapter"
    echo "cadence-eject: hooks adapter sub-module not found: $hooks_adapter" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$hooks_adapter"
  local before after
  before="$(grep -c '\.claude/cadence-hooks/' "$target" 2>/dev/null)"; before=${before:-0}
  if ! cc_hook_settings_remove "$target"; then
    echo "cadence-eject: refusing to ship a corrupt $rel (transform-on-ship failed)." >&2
    return 1
  fi
  after="$(grep -c '\.claude/cadence-hooks/' "$target" 2>/dev/null)"; after=${after:-0}
  echo "transformed  $rel  (removed $((before - after)) CADENCE hook entr(y/ies); adopter config preserved)" >> "$audit"
}

# ===========================================================================
# BTG-057 -- MCP-registration co-owned-config transform-on-ship (AC-5 / DEC-006).
# Generic dest-copy transform: source the runtime MCP shim from SELF_DIR and run
# its sentinel-only remove on the SHIPPED <rel> config -- dropping only
# CADENCE-owned (reserved `cadence-` key) entries, preserving every adopter MCP
# server + non-container top-level key, cleaning an emptied container. An empty
# resulting MCP container is an ACCEPTABLE outcome (not a failure). Records the
# transform in the audit. Fails LOUD (non-zero + eject.mcp.transform_failed) if the
# dest copy is non-canonical rather than shipping a corrupt config. Args:
#   <dest> <audit> <rel> <adapter-rel> <remove-fn>
_eject_transform_mcp() {
  local dest="$1" audit="$2" rel="$3" adapter_rel="$4" remove_fn="$5"
  local target="$dest/$rel"
  [[ -f "$target" ]] || return 0             # config not shipped -> no-op
  local adapter="$SELF_DIR/adapters/$adapter_rel"
  if [[ ! -f "$adapter" ]]; then
    emit_seam UNSOUND_CONDITION eject.binding.adapter_missing "$adapter"
    echo "cadence-eject: MCP adapter sub-module not found: $adapter" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  . "$adapter"
  # Count CADENCE container-member KEYS at key position (reserved-prefix key
  # immediately followed by `:`) -- NOT a bare "cadence- substring, which a
  # non-key adopter VALUE containing that text would inflate (review N3). The
  # canonical layout guarantees one member key per line (DEC-002 / verify module).
  local mcp_key_re='^[[:space:]]*"cadence-[^"]*"[[:space:]]*:'
  local before after
  before="$(grep -cE "$mcp_key_re" "$target" 2>/dev/null)"; before=${before:-0}
  if ! "$remove_fn" "$target"; then
    emit_seam UNSOUND_CONDITION eject.mcp.transform_failed "$target"
    echo "cadence-eject: refusing to ship a corrupt $rel (MCP transform-on-ship failed)." >&2
    return 1
  fi
  after="$(grep -cE "$mcp_key_re" "$target" 2>/dev/null)"; after=${after:-0}
  echo "transformed  $rel  (removed $((before - after)) CADENCE MCP entr(y/ies); adopter config preserved)" >> "$audit"
}

# The Claude co-owned MCP config (.mcp.json / mcpServers).
eject_transform_mcp_claude() {
  # >>> binding-resolution (clause-7 exempt) >>>
  _eject_transform_mcp "$1" "$2" ".mcp.json" "claude-code-mcp.sh" cc_mcp_registry_remove
  # <<< binding-resolution (clause-7 exempt) <<<
}
# The OpenCode co-owned MCP config (opencode.json / mcp).
eject_transform_mcp_opencode() {
  # >>> binding-resolution (clause-7 exempt) >>>
  _eject_transform_mcp "$1" "$2" "opencode.json" "opencode-mcp.sh" oc_mcp_registry_remove
  # <<< binding-resolution (clause-7 exempt) <<<
}

# --- DEC-006 (OQ-1) registry-driven transform-on-ship dispatch ---------------
# The ADR_CADENCE-0018 co-owned-file threshold (now 3-4 files) is crossed. Rather than add
# a third/fourth hardcoded special-case in do_eject (or formalize a kind=transform
# footprint-grammar row -- the deferred BC-costed alternative, ADR_CADENCE-0018 amendment),
# do_eject iterates this in-engine registry of co-owned-config transform fns. Each
# fn owns its (config-path, shim) pair; adding a co-owned config later is ONE row
# here, no do_eject change. Every fn is <dest> <audit> and fail-loud on a
# non-canonical shipped copy.
eject_transform_registry() {
  printf '%s\n' eject_transform_settings eject_transform_mcp_claude eject_transform_mcp_opencode
}

# eject_transform_dispatch <dest> <audit> -- run every registered co-owned-config
# transform; returns non-zero if ANY refuses (do_eject then aborts the export).
eject_transform_dispatch() {
  local dest="$1" audit="$2" fn rc=0
  while IFS= read -r fn; do
    [[ -n "$fn" ]] || continue
    "$fn" "$dest" "$audit" || rc=1
  done < <(eject_transform_registry)
  return $rc
}
