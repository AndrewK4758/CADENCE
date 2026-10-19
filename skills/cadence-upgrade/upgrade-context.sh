#!/usr/bin/env bash
#
# upgrade-context.sh -- the /cadence-upgrade context-wiring concern (BTG-198).
# Colocated sidecar module shipped by the PI-023 directory-copy contract and
# sourced by upgrade-cadence.sh, so it runs in the entry point's shell scope:
# the globals it reads (TARGET, CORE, SELF_DIR) and emit_seam resolve at CALL
# time from that scope (dynamic scoping), exactly as the sibling modules do.
#
# Bounded context: Upgrade seam / adopter context wiring. Reads the adopter's
# CLAUDE.md and CADENCE_DIRECTIVES.md; the DETECT half writes nothing at all.
#
# Invariant relied on from outside this boundary: CLAUDE.md is adopter-owned and
# excluded from the merge set (upgrade-collect.sh's RECONCILE seed row), so this
# module is the ONLY place the upgrade engine may touch it -- and only from
# --repair, only inside the marker-fenced managed block, and only when the
# operator asked.
#
# Upstream: context_detect_and_report is called by upgrade-cadence.sh AFTER the
#   atomic apply and OUTSIDE its transaction, so a detection can never affect
#   whether the stamp advanced. context_repair is called ONLY by upgrade-repair.sh.
# Downstream: reads <target>/CLAUDE.md + <target>/CADENCE_DIRECTIVES.md; on
#   repair, read-modify-writes <target>/CLAUDE.md and re-emits the sidecar.
# Spec: archive/BTG-198/spec.md (Proposed Design, Build-tooling layer);
#       decisions.md DEC-009 (detect always, repair only on request),
#       DEC-010 (repair concern ordered after the seed restore).

# The shared marker-fenced writer (BTG-198 DEC-014) lives with the /cadence-adopt
# sidecars, because that is where the block is first written. The repair path
# needs the SAME writer -- a second implementation of a registered marker
# contract is exactly what DEC-014 forbids -- so it is resolved from the sibling
# command directory, then from the adopter tree, then from core, in that order.
# This mirrors how resolve_root locates the runtime adapter, and it is a plain
# sibling-relative path, not a runtime primitive. A caller that never repairs
# never needs it, so absence is reported at USE time (context_repair), not here.
_context_writer_path() {
  local c
  for c in "$SELF_DIR/../cadence-adopt/managed-block.sh" \
           "$TARGET/.agents/skills/cadence-adopt/managed-block.sh" \
           "$CORE/artifacts/commands/cadence-adopt/managed-block.sh"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# The adopter-owned context file and the framework-owned sidecar. Literals, not
# placeholders: BTG-198 OQ-1 was resolved at the spec-approval gate to keep the
# CLAUDE.md literal and neutralize only the include directive.
UPGRADE_CONTEXT_FILE='CLAUDE.md'
UPGRADE_CONTEXT_SIDECAR='CADENCE_DIRECTIVES.md'

# context_wiring_state <target>
# Echoes exactly ONE state token. This is the requester's settled predicate --
# "sidecar-present + import-line-present is sufficient" -- defined ONCE here and
# read by both callers, so detect and repair can never disagree about what
# "healthy" means.
#   healthy         both present and wired
#   sidecar_missing the framework-owned sidecar is absent
#   context_missing the adopter's context file is absent entirely
#   import_missing  both files exist but nothing imports the sidecar
context_wiring_state() {
  local target="$1"
  if [[ ! -f "$target/$UPGRADE_CONTEXT_SIDECAR" ]]; then
    echo "sidecar_missing"; return 0
  fi
  if [[ ! -f "$target/$UPGRADE_CONTEXT_FILE" ]]; then
    echo "context_missing"; return 0
  fi
  if ! grep -qFx "@CADENCE_DIRECTIVES.md" "$target/$UPGRADE_CONTEXT_FILE"; then
    echo "import_missing"; return 0
  fi
  echo "healthy"
}

# context_assert_sidecar_in_core <ours_commit>
# The RECONCILE add row is gated by `git cat-file -e "$ours_commit:<path>"`, and a
# gate that declines simply `continue`s -- so an adopter upgrading to a core
# version that does not own the sidecar would silently never receive it, and
# would never be told. That is the exact silent failure this whole ticket exists
# to kill, one layer down, so it is NAMED here rather than skipped (JI-6).
# Non-blocking: it reports, it does not fail an otherwise-clean upgrade.
context_assert_sidecar_in_core() {
  local ours_commit="$1"
  git -C "$CORE" cat-file -e "$ours_commit:$UPGRADE_CONTEXT_SIDECAR" 2>/dev/null && return 0
  emit_seam DELTA_AUDIT_GAP upgrade.context.sidecar_not_in_core "$UPGRADE_CONTEXT_SIDECAR"
  echo "upgrade-cadence: core at this version does not own $UPGRADE_CONTEXT_SIDECAR." >&2
  echo "upgrade-cadence: it CANNOT be delivered from this core version -- this is not a successful delivery." >&2
  echo "upgrade-cadence: upgrade to a core version that ships it, or the adopter has no CADENCE directives." >&2
  return 0
}

# context_detect_and_report <target>
# NON-MUTATING. Run after the atomic apply and outside its transaction. Emits
# DELTA_AUDIT_GAP upgrade.context.wiring_broken and a notice naming both files and
# the exact repair command. ALWAYS returns 0: a detection must never turn an
# otherwise-clean upgrade into a failure, and it re-fires on EVERY subsequent
# run until repaired -- an adopter who ignores it once still sees it (DEC-009).
context_detect_and_report() {
  local target="$1" state
  state="$(context_wiring_state "$target")"
  [[ "$state" == "healthy" ]] && return 0
  emit_seam DELTA_AUDIT_GAP upgrade.context.wiring_broken "$state"
  echo "upgrade-cadence: the CADENCE directives are NOT wired into this repository ($state)." >&2
  echo "upgrade-cadence:   $target/$UPGRADE_CONTEXT_FILE" >&2
  echo "upgrade-cadence:   $target/$UPGRADE_CONTEXT_SIDECAR" >&2
  echo "upgrade-cadence: every CADENCE agent here reads ZERO CADENCE directives until this is repaired." >&2
  echo "upgrade-cadence: nothing was written -- repair it explicitly with:" >&2
  echo "upgrade-cadence:   /cadence-upgrade --repair" >&2
  return 0
}

# The context managed-block marker contract, mirrored from the adopt side. These
# are a REGISTERED surface (docs/policies/cadence-surfaces.md): changing the
# text orphans every block in the field, so the two sites must agree exactly.
UPGRADE_CONTEXT_BEGIN='<!-- >>> CADENCE directives (managed by /adopt-cadence) >>> -->'
UPGRADE_CONTEXT_END='<!-- <<< CADENCE directives <<< -->'

# _context_block_file <path>
# Write the managed block body (markers included) to <path>. Kept byte-identical
# in shape to the adopt-side writer so a repaired block and a freshly adopted one
# are the same block.
_context_block_file() {
  {
    printf '%s\n' "$UPGRADE_CONTEXT_BEGIN"
    printf '%s\n' "@CADENCE_DIRECTIVES.md"
    printf '\n'
    printf '%s\n' "The line above imports the framework-owned CADENCE directives from"
    printf '%s\n' "CADENCE_DIRECTIVES.md; everything else in this file is yours, and CADENCE"
    printf '%s\n' "never edits it."
    printf '%s\n' "$UPGRADE_CONTEXT_END"
  } > "$1"
}

# context_repair <target>
# MUTATING. Called ONLY from --repair, never from a plain upgrade: the adopter's
# context file is theirs, and the framework does not write into it because a
# detection fired. Idempotent, per-concern atomic, fail-loud. Emits
# DELTA_AUDIT_GAP upgrade.repair.context_restored once per action taken, and is
# silent when nothing needed repair. Returns non-zero only on a named failure.
#
# The sidecar is restored from CORE'S WORKING TREE, not from a git ref: --repair
# is a stamp-independent operation that never resolves a target commit, and the
# sibling concerns (the eject-engine refresh, the hooks manifest) already source
# from $CORE the same way. An absent core copy is a NAMED refusal, never a
# fabricated file (the DEC-B2 never-guess rule).
# Set by context_repair to 1 when it actually WROTE something, so the caller can
# report "nothing to repair" honestly. A run that only warned did no work.
CONTEXT_REPAIR_DID=0

context_repair() {
  local target="$1" state
  CONTEXT_REPAIR_DID=0
  state="$(context_wiring_state "$target")"

  if [[ "$state" == "sidecar_missing" ]]; then
    if [[ ! -f "$CORE/$UPGRADE_CONTEXT_SIDECAR" ]]; then
      # An UNREACHABLE SOURCE is a loud warning, not a repair failure -- the same
      # posture this file already takes when the hooks manifest cannot be
      # resolved. Non-zero is reserved for a write that was attempted and failed.
      # A core version that predates the split simply has nothing to give, and
      # making --repair exit non-zero for every adopter in that position would
      # turn a fleet-wide expected state into a fleet-wide error.
      emit_seam DELTA_AUDIT_GAP upgrade.context.sidecar_not_in_core "$UPGRADE_CONTEXT_SIDECAR"
      echo "upgrade-cadence --repair: warning -- core does not own $UPGRADE_CONTEXT_SIDECAR; context concern skipped (nothing written)." >&2
      return 0
    fi
    if ! cp "$CORE/$UPGRADE_CONTEXT_SIDECAR" "$target/$UPGRADE_CONTEXT_SIDECAR"; then
      echo "upgrade-cadence --repair: could not write $target/$UPGRADE_CONTEXT_SIDECAR." >&2
      return 1
    fi
    emit_seam DELTA_AUDIT_GAP upgrade.repair.context_restored "sidecar re-emitted from core"
    echo "upgrade-cadence --repair: re-emitted $UPGRADE_CONTEXT_SIDECAR from core."
    CONTEXT_REPAIR_DID=1
    state="$(context_wiring_state "$target")"
  fi

  case "$state" in
    context_missing)
      # Re-create the adopter-owned stub: import line FIRST, then the one
      # explanatory sentence, then a short adopter-owned heading -- the same
      # shape /cadence-adopt generates, so a repaired repo is indistinguishable
      # from a freshly adopted one.
      {
        printf '%s\n' "@CADENCE_DIRECTIVES.md"
        printf '\n'
        printf '%s\n' "The line above imports the framework-owned CADENCE directives from"
        printf '%s\n' "CADENCE_DIRECTIVES.md; everything else in this file is yours, and CADENCE"
        printf '%s\n' "never edits it."
        printf '\n'
        printf '%s\n' "# Project Context"
        printf '\n'
        printf '%s\n' "Record this project's architecture, domain model, conventions and standing"
        printf '%s\n' "agent instructions below."
      } > "$target/$UPGRADE_CONTEXT_FILE" || {
        echo "upgrade-cadence --repair: could not write $target/$UPGRADE_CONTEXT_FILE." >&2
        return 1
      }
      emit_seam DELTA_AUDIT_GAP upgrade.repair.context_restored "context stub re-created"
      echo "upgrade-cadence --repair: re-created $UPGRADE_CONTEXT_FILE with the sidecar import."
      CONTEXT_REPAIR_DID=1
      ;;
    import_missing)
      local writer
      if ! writer="$(_context_writer_path)"; then
        emit_seam DELTA_AUDIT_GAP upgrade.repair.context_restored "writer unavailable"
        echo "upgrade-cadence --repair: the shared managed-block writer is not reachable; nothing written." >&2
        return 1
      fi
      # shellcheck source=/dev/null
      [[ -n "${MANAGED_BLOCK_SOURCED:-}" ]] || . "$writer"
      local blk; blk="$(mktemp)"
      _context_block_file "$blk"
      MANAGED_BLOCK_DELIVERABLE="CADENCE directives block"
      if ! write_managed_block "$target/$UPGRADE_CONTEXT_FILE" \
             "$UPGRADE_CONTEXT_BEGIN" "$UPGRADE_CONTEXT_END" "$blk"; then
        rm -f "$blk"
        echo "upgrade-cadence --repair: could not re-establish the managed block in $UPGRADE_CONTEXT_FILE." >&2
        return 1
      fi
      rm -f "$blk"
      emit_seam DELTA_AUDIT_GAP upgrade.repair.context_restored "managed block $MANAGED_BLOCK_ACTION"
      echo "upgrade-cadence --repair: managed block $MANAGED_BLOCK_ACTION in $UPGRADE_CONTEXT_FILE."
      CONTEXT_REPAIR_DID=1
      ;;
  esac

  if [[ "$CONTEXT_REPAIR_DID" -eq 1 && "$(context_wiring_state "$target")" != "healthy" ]]; then
    echo "upgrade-cadence --repair: the context wiring is STILL not healthy after repair." >&2
    return 1
  fi
  return 0
}
