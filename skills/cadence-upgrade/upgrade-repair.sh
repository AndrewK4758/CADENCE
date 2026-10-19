#!/usr/bin/env bash
#
# upgrade-repair.sh -- the /cadence-upgrade --repair sidecar (BTG-016b / AC-4 /
# DEC-004 / DEC-B2). A colocated module shipped by the PI-023 directory-copy
# contract and sourced by upgrade-cadence.sh's --repair dispatch, so it runs in
# the entry point's shell scope (TARGET/CORE/SELF_DIR/emit_seam/version_cmp/
# stamp_field/core_file/SEED_FILES and the sourced upgrade-hooks.sh helpers all
# resolve at call time).
#
# Bounded context: Upgrade seam / bootstrapping-gap remediation (BTG-016b).
# Upstream: run explicitly by an adopter (already on the fixed version) whose
#   earlier pre-protection upgrade (F0 clause 1) mutated the seeds, stranded the
#   hooks, and/or skipped the specs/drafts create -- NONE of which the old engine
#   could self-apply in-run. Downstream: restores the five seed docs from the
#   adopter's OWN git history (the RESTORABLE projection -- CLAUDE.md is a seed
#   for the merge but carries the `no-restore` disposition and is never touched
#   here, BTG-198), relocates pristine legacy .agents/hooks/<known> to
#   .claude/cadence-hooks/ + repoints .claude/settings.json, creates-if-absent
#   specs/drafts/.gitignore, refreshes the frozen eject engine so BTG-016a's
#   in-memory backfill covers the stale committed footprint, and re-establishes
#   broken CLAUDE.md <-> CADENCE_DIRECTIVES.md context wiring inside its managed
#   block only. The committed artifacts/footprint.generated is NEVER mutated
#   (ADR_CADENCE-0009).
# Spec: specs/BTG-016b/spec.md (AC-1/AC-2/AC-4/AC-6); decisions.md DEC-004/DEC-B2.
#
# Contract: idempotent; per-concern atomic (a failure in one concern is named and
# does NOT roll back an already-correct concern); fail-loud (never fabricates or
# guesses seed content -- DEC-B2). Separate from the merge, so it does NOT touch
# the stamp-advance atomicity invariant. Returns non-zero only on a named,
# unrecoverable concern failure (an unsourceable seed blob, a hook conflict, a
# sync refusal); 0 otherwise (including a full no-op "nothing to repair").

# ---------------------------------------------------------------------------
# Seed-source resolution (DEC-B2). The pre-upgrade seed blob lives at the PARENT
# of the stamp-advancing commit (the commit that last touched .cadence-version).
# On ANY ambiguity -- no such commit, a root commit (no parent), or a merge commit
# (2+ parents: squashed/non-linear history) -- resolve NOTHING and let the caller
# fail loud (upgrade.repair.seed_source_missing). We NEVER guess a base blob.
# Echoes the resolved source ref or nothing. Honors an explicit --from override
# via $REPAIR_FROM (set by the arg parse), which bypasses the anchor entirely.
# ---------------------------------------------------------------------------
repair_seed_source_ref() {
  [[ -n "${REPAIR_FROM:-}" ]] && { echo "$REPAIR_FROM"; return 0; }
  local stampc parents n
  stampc="$(git -C "$TARGET" log -1 --format=%H -- .cadence-version 2>/dev/null)"
  [[ -n "$stampc" ]] || { echo ""; return 0; }
  # rev-list --parents -n1 prints "<commit> [<parent> ...]": 2 tokens = one parent
  # (linear, unambiguous); 1 token = root (no pre-upgrade blob); >=3 = merge.
  parents="$(git -C "$TARGET" rev-list --parents -n1 "$stampc" 2>/dev/null)"
  n="$(printf '%s\n' "$parents" | wc -w)"
  [[ "$n" -eq 2 ]] || { echo ""; return 0; }
  git -C "$TARGET" rev-parse "$stampc^" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Resolve the CADENCE hooks.manifest for the repair (the known-basename set):
# prefer the adopter's installed artifacts/hooks/hooks.manifest (present once the
# adopter reached the fixed version), else core's. Copies it to <dest>; returns 1
# if none is found. Args: <dest>.
# ---------------------------------------------------------------------------
repair_hooks_manifest() {
  local dest="$1" m
  for m in "$TARGET/artifacts/hooks/hooks.manifest" "$CORE/artifacts/hooks/hooks.manifest"; do
    if [[ -f "$m" && -s "$m" ]]; then cp "$m" "$dest"; return 0; fi
  done
  return 1
}

# Resolve the PRISTINE framework content for hook basename <b> into <dest> (the
# BTG-008 relocation is a pure move, so the framework's canonical hook content is
# byte-identical to the pre-relocation legacy content). Prefer the adopter's
# installed artifacts/hooks/<b>, else core's. Returns 1 if none is found.
repair_pristine_hook() {
  local b="$1" dest="$2" p
  for p in "$TARGET/artifacts/hooks/$b" "$CORE/artifacts/hooks/$b"; do
    [[ -f "$p" ]] && { cp "$p" "$dest"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------------------
# The repair entry point. Args: --repair [--from <ref>].
# ---------------------------------------------------------------------------
upgrade_repair() {
  local REPAIR_FROM=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repair) shift ;;
      --from)
        # BTG-050 value-presence guard (kept byte-identical across both --from sidecars).
        # A dangling --from (no following token, or the next token is itself a flag)
        # would ask `shift 2` to drop 2 positionals with only 1 left: shift fails,
        # $# is unchanged, and (no set -e) the while loop spins on --from forever.
        # Fail loud BEFORE the shift instead of hanging. A git ref never legitimately
        # starts with --, so treating --* as "not a value" is safe.
        if [[ $# -lt 2 || "$2" == --* ]]; then
          echo "upgrade-cadence: --from requires a <ref> value (none given)." >&2
          return 2
        fi
        REPAIR_FROM="$2"; shift 2 ;;
      *) echo "upgrade-cadence --repair: unknown option: $1" >&2; return 2 ;;
    esac
  done

  local did_work=0 fail=0

  # --- Concern 1: seeds (AC-1 / Defect 2, highest severity) -----------------
  # Restore each polluted seed byte-for-byte from its pre-upgrade git blob; a
  # seed already matching its blob is left untouched (idempotent). An unsourceable
  # blob fails LOUD for that seed and restores nothing -- never fabricate (DEC-B2).
  #
  # WHAT THIS CONCERN IS FOR, and therefore what it must NOT touch (BTG-198,
  # review cycle 1 blocking #1). It exists to undo pre-3.8.8 engine POLLUTION of
  # a seed: the merge wrote framework rows into a file the adopter owns, and the
  # pre-upgrade blob is that file before the engine damaged it. The set it
  # iterates is therefore the RESTORABLE seed projection, ${SEED_FILES[@]} --
  # NOT every kind=seed row. upgrade-collect.sh's RECONCILE table carries the
  # distinction as field 4 (`no-restore`), so it stays one reviewed data
  # statement rather than a second list here (DEC-006).
  #
  # CLAUDE.md is the first `no-restore` row and shows why the distinction is
  # load-bearing. It is categorically excluded from the merge, so no engine ever
  # wrote it and there is no pollution class to undo -- while its pre-upgrade
  # blob is either core's OLD directives (a pre-split adopter, i.e. exactly the
  # content BTG-198 removes) or a stale copy of the adopter's own file (a
  # post-split adopter). Restoring it can only destroy adopter work, and `cmp -s`
  # skips the copy only when the file already matches the blob, so the loss would
  # fire EXACTLY when the adopter has edits. Scenarios S-9.4 and S-9.5 assert it.
  local src_ref seed tmp
  src_ref="$(repair_seed_source_ref)"
  for seed in "${SEED_FILES[@]}"; do
    [[ -e "$TARGET/$seed" ]] || continue          # absent seed: nothing to restore
    if [[ -z "$src_ref" ]] || ! git -C "$TARGET" cat-file -e "$src_ref:$seed" 2>/dev/null; then
      emit_seam DELTA_AUDIT_GAP upgrade.repair.seed_source_missing "$seed"
      echo "upgrade-cadence --repair: cannot source the pre-upgrade blob for $seed -- left unchanged; reconcile it manually or pass --from <ref>." >&2
      fail=1
      continue
    fi
    tmp="$(mktemp)"; git -C "$TARGET" show "$src_ref:$seed" > "$tmp" 2>/dev/null
    if cmp -s "$tmp" "$TARGET/$seed"; then rm -f "$tmp"; continue; fi
    cp "$tmp" "$TARGET/$seed"; rm -f "$tmp"
    did_work=1
    echo "upgrade-cadence --repair: restored $seed from its pre-upgrade blob."
  done

  # --- Concern 2: hooks (AC-2 / Defect 3) -----------------------------------
  # Reuse the BTG-008 no-data-loss guard: a legacy .agents/hooks/<known> that is
  # byte-identical to the pristine framework hook is relocated to
  # .claude/cadence-hooks/ + settings.json repointed (hooks_relocate_and_sync);
  # a CUSTOMIZED legacy hook is surfaced as a conflict and NOT touched (settings
  # left unchanged) -- the operator reconciles it, then re-runs. Mirrors the merge
  # path's all-or-nothing hook handling within this concern.
  local mani; mani="$(mktemp)"
  if repair_hooks_manifest "$mani"; then
    local hooks_adapter; hooks_adapter="$(hooks_adapter_path)"
    if [[ -n "$hooks_adapter" ]]; then
      # shellcheck source=/dev/null
      . "$hooks_adapter"
      local b legacy pf pristine=() customized=()
      while IFS= read -r b; do
        [[ -n "$b" ]] || continue
        # >>> binding-resolution (clause-7 exempt) >>>
        legacy="$TARGET/.agents/hooks/$b"
        # <<< binding-resolution (clause-7 exempt) <<<
        [[ -f "$legacy" ]] || continue
        pf="$(mktemp)"
        if repair_pristine_hook "$b" "$pf" && cmp -s "$legacy" "$pf"; then
          pristine+=("$b")
        else
          customized+=("$b")
        fi
        rm -f "$pf"
      done < <(cc_hook_known_basenames "$mani")
      if [[ "${#customized[@]}" -gt 0 ]]; then
        did_work=1; fail=1
        echo "upgrade-cadence --repair: customized legacy hook(s) surfaced as a CONFLICT (NOT relocated): ${customized[*]}" >&2
        echo "upgrade-cadence --repair: reconcile each against .claude/cadence-hooks/ then re-run --repair; settings.json left unchanged." >&2
      elif [[ "${#pristine[@]}" -gt 0 ]]; then
        # Place the pristine content under .claude/cadence-hooks/ (the merge path
        # gets this from the 3-way merge; the repair copies the pristine legacy
        # bytes), THEN reuse hooks_relocate_and_sync to repoint settings.json and
        # remove the legacy .agents/hooks/<known> copies (emits the relocated seam).
        mkdir -p "$TARGET/.claude/cadence-hooks"
        for b in "${pristine[@]}"; do
          # >>> binding-resolution (clause-7 exempt) >>>
          cp "$TARGET/.agents/hooks/$b" "$TARGET/.claude/cadence-hooks/$b"
          # <<< binding-resolution (clause-7 exempt) <<<
        done
        if hooks_relocate_and_sync "$mani"; then
          did_work=1
        else
          fail=1
        fi
      fi
    fi
  else
    # No hooks.manifest reachable in TARGET or CORE -- the known CADENCE basename
    # set cannot be resolved, so the hooks concern cannot run. Surface it LOUD
    # rather than skipping SILENTLY (parity with the seed concern's fail-loud
    # posture); non-fatal, so the other concerns still apply. This is unreachable
    # once the adopter is on the fixed version (the manifest ships in
    # artifacts/hooks/) -- it guards a genuinely anomalous repo.
    # >>> binding-resolution (clause-7 exempt) >>>
    echo "upgrade-cadence --repair: warning -- no artifacts/hooks/hooks.manifest reachable; hooks concern skipped (relocate any legacy .agents/hooks/<known> manually)." >&2
    # <<< binding-resolution (clause-7 exempt) <<<
  fi
  rm -f "$mani"

  # --- Concern 3: drafts (AC-6 / Defect 4, lowest severity) -----------------
  # Create-if-absent specs/drafts/.gitignore ('*' then '!.gitignore') reusing the
  # BTG-010 logic; NEVER overwrite an existing one (it may hold adopter patterns);
  # non-fatal on failure (a convenience workspace, not framework material).
  if [[ ! -e "$TARGET/specs/drafts/.gitignore" ]]; then
    if mkdir -p "$TARGET/specs/drafts" \
       && printf '*\n!.gitignore\n' > "$TARGET/specs/drafts/.gitignore"; then
      did_work=1
      echo "upgrade-cadence --repair: created specs/drafts/.gitignore."
    else
      echo "upgrade-cadence --repair: warning -- could not create specs/drafts/.gitignore (non-fatal)." >&2
    fi
  fi

  # --- Concern 4: eject refresh (Source-Confidentiality; BTG-016a dependency) --
  # Refresh the WHOLE frozen eject engine from core so BTG-016a's in-memory
  # backfill covers the adopter's stale committed footprint at the next eject.
  # The '*eject*.sh' glob deliberately spans EVERY eject-engine script -- the
  # cadence-eject.sh ENTRY POINT as well as its eject-*.sh helpers (footprint,
  # headers, transform) -- so load-bearing logic in the entry point is refreshed
  # too; a narrower 'eject-*.sh' glob would silently miss it. The adopter-tunable
  # eject-exceptions.conf CONFIG is intentionally NOT refreshed (it may hold
  # adopter exceptions -- no-data-loss). NEVER mutate the committed
  # artifacts/footprint.generated (ADR_CADENCE-0009). Counts as work only when a script
  # actually changed (so a clean repo still reports "nothing").
  local es dst
  for es in "$CORE"/ci-templates/scripts/*eject*.sh; do
    [[ -f "$es" ]] || continue
    dst="$TARGET/ci-templates/scripts/$(basename "$es")"
    if [[ ! -f "$dst" ]] || ! cmp -s "$es" "$dst"; then
      mkdir -p "$TARGET/ci-templates/scripts" && cp "$es" "$dst" && did_work=1 \
        && echo "upgrade-cadence --repair: refreshed $(basename "$es") from core (footprint untouched)."
    fi
  done

  # --- Concern 5: context wiring (BTG-198 / DEC-010) ------------------------
  # Ordered AFTER Concern 1 deliberately, and the ordering IS the behaviour:
  # CLAUDE.md is a SEED, so Concern 1 restores it from its pre-upgrade git blob
  # -- a blob that predates the managed block and therefore REMOVES it. Running
  # the context concern first would leave the repair worse than it found the
  # adopter. Running it here re-establishes the wiring in the SAME run (R-2,
  # asserted by scenario S-9.4). Idempotent and silent when nothing needs
  # repairing; a named failure is non-fatal to the other concerns, exactly as the
  # seed and hook concerns are.
  #
  # SCOPED, and the scope is named rather than assumed: the concern runs only for
  # a repo that IS context-wired -- one carrying CLAUDE.md or the sidecar -- which
  # is the SAME either-path predicate the absent-stamp surface check uses
  # (upgrade-bootstrap.sh, BTG-198 AC-7). A repo with NEITHER has no wiring to
  # repair and no surface to repair it against, and treating that as a repair
  # failure would make --repair non-zero on repos this concern has nothing to say
  # about. The signal is not lost: such a repo is reported by
  # context_detect_and_report on its next upgrade.
  if [[ -f "$TARGET/CLAUDE.md" || -f "$TARGET/CADENCE_DIRECTIVES.md" ]] \
     && [[ "$(context_wiring_state "$TARGET")" != "healthy" ]]; then
    if context_repair "$TARGET"; then
      [[ "$CONTEXT_REPAIR_DID" -eq 1 ]] && did_work=1
    else
      fail=1
    fi
  fi

  # --- Report --------------------------------------------------------------
  if [[ "$did_work" -eq 0 && "$fail" -eq 0 ]]; then
    echo "upgrade-cadence --repair: nothing to repair (repo already in the post-protection state)."
  fi
  [[ "$fail" -eq 0 ]]
}
