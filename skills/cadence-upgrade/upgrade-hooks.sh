#!/usr/bin/env bash
#
# upgrade-hooks.sh -- the BTG-008 hook relocation + settings-registration-sync
# concern of /cadence-upgrade (AC-5 / AC-8 / DEC-004). A colocated sidecar
# module shipped by the PI-023 directory-copy contract and sourced by
# upgrade-cadence.sh in this shell's scope (so CORE / TARGET / emit_seam /
# core_file resolve at call time; new module keeps the entry point under the DX
# <300-line target -- the PI-014/PI-023 split precedent).
#
# Bounded context: Upgrade seam / layered-source flow (BTG-008, Workstream A).
# Upstream: called by upgrade-cadence.sh main() AFTER the atomic clean apply +
#   stamp advance (never on a conflicted/partial apply -- R-5). Downstream:
#   removes ONLY the two known legacy CADENCE scripts from the adopter's
#   .agents/hooks/ and surgically repoints/reconciles the CADENCE entries in
#   .claude/settings.json (via the adapter's cc_hook_* helpers). Spec:
#   specs/BTG-008/spec.md (Upgrade / AC-5 / AC-8); decisions.md DEC-004.

# Extract core@<ours_commit>'s neutral hooks.manifest to <dest>. Returns 1 if
# core@new does not declare artifacts/hooks (defensive: no backfill/relocation).
hooks_core_manifest() {
  local ours_commit="$1" dest="$2"
  git -C "$CORE" cat-file -e "$ours_commit:artifacts/hooks/hooks.manifest" 2>/dev/null || return 1
  git -C "$CORE" show "$ours_commit:artifacts/hooks/hooks.manifest" > "$dest" 2>/dev/null || return 1
  [[ -s "$dest" ]]
}

# Resolve the adapter hooks sub-module (installed in the adopter under
# ci-templates/scripts/adapters, or reachable from core). Echoes its path or "".
hooks_adapter_path() {
  local a
  # >>> binding-resolution (clause-7 exempt) >>>
  for a in "$TARGET/ci-templates/scripts/adapters/claude-code-hooks.sh" \
           "$CORE/ci-templates/scripts/adapters/claude-code-hooks.sh"; do
  # <<< binding-resolution (clause-7 exempt) <<<
    [[ -f "$a" ]] && { echo "$a"; return 0; }
  done
  echo ""
}

# Echo the LEGACY .agents/hooks/<known> rel paths the adopter CUSTOMIZED relative
# to the stamped base (core@old:.agents/hooks/<known>). The no-data-loss guard
# (R-6): a customized legacy hook must NOT be silently relocated -- it is surfaced
# as a conflict by the caller. A legacy hook identical to the base (pristine), or
# one with no base to compare against safely, is handled by the caller. Args:
#   <base_commit> <base_empty> <manifest>
hooks_legacy_customized() {
  local base_commit="$1" base_empty="$2" manifest="$3" b legacy basef
  local hooks_adapter; hooks_adapter="$(hooks_adapter_path)"
  [[ -n "$hooks_adapter" ]] || return 0
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    # >>> binding-resolution (clause-7 exempt) >>>
    legacy="$TARGET/.agents/hooks/$b"
    [[ -f "$legacy" ]] || continue                 # no legacy copy -> nothing to relocate
    basef="$(mktemp)"
    if [[ "$base_empty" -eq 1 ]]; then : > "$basef"; else core_file "$base_commit" ".agents/hooks/$b" "$basef"; fi
    # Customized iff the legacy content differs from the stamped base. An absent
    # base (empty) is conservatively treated as customized (surface, never lose).
    if ! diff -q "$legacy" "$basef" >/dev/null 2>&1; then
      echo ".agents/hooks/$b"
    fi
    # <<< binding-resolution (clause-7 exempt) <<<
    rm -f "$basef"
  done < <( . "$hooks_adapter"; cc_hook_known_basenames "$manifest" )
}

# Reconcile the settings.json registration to core@new, THEN relocate pristine
# legacy hooks. NB-1 ORDERING (review fix): the settings sync runs/validates
# FIRST -- it repoints legacy .agents/hooks/<known> commands to
# .claude/cadence-hooks/ and add/update/retire the registration. ONLY after a
# successful sync are the legacy .agents/hooks/<known> FILES removed. So a sync
# refusal (a non-canonical settings.json, now caught by B1) leaves the legacy
# files intact and the caller leaves the stamp unadvanced -- all-or-nothing, no
# broken "registration points at a removed path" state. Emits the informational
# upgrade.hooks.relocated seam iff any legacy file was removed. Returns non-zero
# (fail-loud) iff the sync refuses. Idempotent. Args: <manifest>
hooks_relocate_and_sync() {
  local manifest="$1" hooks_adapter removed
  hooks_adapter="$(hooks_adapter_path)"
  [[ -n "$hooks_adapter" ]] || return 0
  # shellcheck source=/dev/null
  . "$hooks_adapter"
  # (1) sync/validate the registration FIRST (never remove files before this).
  if ! cc_hook_settings_sync "$TARGET/.claude/settings.json" "$manifest"; then
    echo "upgrade-cadence: hook registration sync refused (non-canonical settings.json) -- legacy files untouched." >&2
    return 1
  fi
  echo "upgrade-cadence: hook registration synced."
  # (2) only now remove the legacy files (the settings already repoint to cadence-hooks).
  removed="$(cc_hook_relocate_files "$TARGET" "$manifest")"
  if [[ -n "$removed" ]]; then
    emit_seam LOGIC_FAULT upgrade.hooks.relocated "$(printf '%s' "$removed" | tr '\n' ' ')"
    # >>> binding-resolution (clause-7 exempt) >>>
    echo "upgrade-cadence: relocated pre-BTG-008 CADENCE hooks out of .agents/hooks/ (repointed to .claude/cadence-hooks/)." >&2
    # <<< binding-resolution (clause-7 exempt) <<<
  fi
}
