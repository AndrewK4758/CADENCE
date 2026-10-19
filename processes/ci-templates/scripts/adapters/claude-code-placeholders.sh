#!/usr/bin/env bash
#
# claude-code-placeholders.sh -- the Claude Code adapter's PLACEHOLDER
# EXPANSION AND VALIDATION half (BTG-247 row: adapters/claude-code.sh split).
# MOVED VERBATIM from claude-code.sh (pre-split lines :109-:221): body
# placeholder expansion, sidecar placeholder expansion, the two residual-token
# guards, and the {{role:}} reference validator. All five functions take an
# already-loaded source document (or its expanded text) and turn declared
# neutral placeholders into concrete Claude Code strings, or refuse a
# dangling one -- none of them derives a manifest row or resolves a tool
# capability, which is claude-code.sh's own remaining concern.
#
# Bounded context: Build tooling / cadence-compile flow, same as
# claude-code.sh. SOURCED by claude-code.sh via a relative
# ${BASH_SOURCE[0]}-derived path, exactly the pattern org-binding-parse.sh and
# authored-doc-gate.sh already use for their own siblings (BTG-247 DEC-031/032).
# Never sourced directly by anything else -- callers load claude-code.sh, which
# pulls this file in transitively.
#
# References: archive/BTG-247/spec.md ; archive/BTG-247/decisions.md (this
# entry's own DEC row).

# Expand body placeholders (DEC-009) into Claude Code primitives.
# Reads body on stdin, writes expanded body on stdout.
cc_expand_body() {
  sed -E \
    -e 's/\{\{role:([a-z0-9-]+)\}\}/`\1` subagent/g' \
    -e 's/\{\{role_kind\}\}/subagent/g' \
    -e 's/\{\{invoking_runtime\}\}/Claude/g' \
    -e 's#\{\{artifact_path:roles:([a-z0-9-]+)\}\}#.agents/agents/\1/AGENT.md#g' \
    -e 's#\{\{artifact_path:commands:([a-z0-9-]+)\}\}#.agents/skills/\1/SKILL.md#g' \
    -e 's#\{\{sidecar:([a-z0-9-]+):([^}]+)\}\}#.agents/skills/\1/\2#g' \
    -e 's#\{\{artifact_glob:roles\}\}#.agents/agents/*/AGENT.md#g' \
    -e 's#\{\{artifact_glob:commands\}\}#.agents/skills/*/SKILL.md#g' \
    -e 's#\{\{runtime_root\}\}#.claude#g' \
    -e 's#\{\{artifact_root:roles\}\}#.agents/agents#g' \
    -e 's#\{\{artifact_root:commands\}\}#.agents/skills#g' \
    -e 's#\{\{artifact_root:hooks\}\}#.claude/cadence-hooks#g' \
    -e 's#\{\{settings_file\}\}#.claude/settings.json#g' \
    -e 's#\{\{context_import:([^}]+)\}\}#@\1#g'
}

# Expand a sidecar .sh text file's PATH placeholders (DEC-010): the path set only
# (artifact_root/path, sidecar, artifact_glob, runtime_root) -- NOT the {{role:}}
# delegation phrasing (sidecars carry no role refs). For Claude every placeholder
# resolves back to the identical .claude/ string, so the committed sidecar golden stays
# byte-identical. Reads stdin, writes stdout.
cc_expand_sidecar() {
  sed -E \
    -e 's#\{\{artifact_path:roles:([a-z0-9-]+)\}\}#.agents/agents/\1/AGENT.md#g' \
    -e 's#\{\{artifact_path:commands:([a-z0-9-]+)\}\}#.agents/skills/\1/SKILL.md#g' \
    -e 's#\{\{sidecar:([a-z0-9-]+):([^}]+)\}\}#.agents/skills/\1/\2#g' \
    -e 's#\{\{artifact_glob:roles\}\}#.agents/agents/*/AGENT.md#g' \
    -e 's#\{\{artifact_glob:commands\}\}#.agents/skills/*/SKILL.md#g' \
    -e 's#\{\{runtime_root\}\}#.claude#g' \
    -e 's#\{\{artifact_root:roles\}\}#.agents/agents#g' \
    -e 's#\{\{artifact_root:commands\}\}#.agents/skills#g' \
    -e 's#\{\{artifact_root:hooks\}\}#.claude/cadence-hooks#g' \
    -e 's#\{\{settings_file\}\}#.claude/settings.json#g' \
    -e 's#\{\{context_import:([^}]+)\}\}#@\1#g'
}

# A residual sanctioned-FAMILY placeholder after sidecar expansion (a typo'd
# tree/name) is a hard error. Scoped to the families so legitimate shell brace-
# tokens (e.g. printf '{{%s}}') are not flagged. Reads expanded text on stdin;
# echoes offending lines, returns 1 if any.
cc_residual_sidecar() {
  local out
  out="$(grep -nE '\{\{(role:|role_kind|invoking_runtime|artifact_root:|artifact_path:|sidecar:|artifact_glob:|runtime_root|settings_file|context_import:)')"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out" | sed 's/^/  /'
    return 1
  fi
  return 0
}

# Guard against silent pass-through of an unknown/typo'd placeholder (review fix,
# BLOCKING #1a). cc_expand_body has no else-branch, so any {{...}} it does not
# recognize would be emitted verbatim into the native artifact. After expansion, any
# residual {{...}} token in a NORMATIVE position is a hard error: a dangling
# delegation/path reference must never ship.
#
# Worked-example / labelled-example / binding regions are excluded, mirroring the
# scanner discipline (scan_primitives / neutral_normative_lines): an illustrative token
# there (e.g. a `{{LIGHTRAG_QUERY: ...}}` adopter-wiring example) is content, reproduced
# verbatim, not a delegation to resolve. Reads the ALREADY-EXPANDED body on stdin;
# echoes "<lineno>: <content>" per offending line, returning 1 if any token remains.
cc_residual_placeholders() {
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
        # fall through: this heading line is itself a new normative sibling
        if ($0 ~ /^## Worked Example/ || $0 ~ /^## Example/ || $0 ~ /^## Runtime Binding/) { drop=2; next }
        if ($0 ~ /^### Example/) { drop=3; next }
      }
      if ($0 ~ /\{\{[^}]*\}\}/) { print NR": "$0; found=1 }
    }
    END { exit (found ? 1 : 0) }
  '
}

# Validate every {{role:<name>}} reference in a body against the known-role set
# (review fix, BLOCKING #1b). cc_expand_body would render ANY [a-z0-9-]+ name,
# so a typo'd role (e.g. {{role:archvist}}) silently shipped a dangling
# delegation. A reference whose <name> has no `roles/<name>.md` source artifact
# is a hard error. <1> is the body source file; the known-role set is the
# basenames of its sibling roles/*.md tree (the same canonical identity the
# manifest enumerates). Echoes each unknown name; returns 1 if any unknown.
cc_validate_role_refs() {
  local f="$1"
  local roles_dir; roles_dir="$(dirname "$f")"
  # If the body file is a command (commands/<name>.md), hop to the sibling
  # roles/ tree under the same artifacts root.
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
