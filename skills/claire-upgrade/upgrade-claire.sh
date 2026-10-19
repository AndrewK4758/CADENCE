#!/usr/bin/env bash
#
# upgrade-claire.sh -- the /claire-upgrade 3-way merge engine (PI-022).
# Bounded context: Upgrade seam / layered-source flow (PI-022, Workstream A). Merges new
# core into the adopter's customized COMPILED tree (.claude/ + installed surface),
# never artifacts/ source (no decompiler -- DEC-002). The PI-021 .claire-version stamp
# (base ancestor) and the ADR_CLAIRE-0009 footprint.generated descriptor (boundary) are CONSUMED
# here, never re-derived (DEC-008). Run by the adopter via the skill wrapper against a
# reachable core checkout (UPGRADE_CORE); mutates ONLY in-scope files under UPGRADE_TARGET
# and advances the stamp ONLY on a fully-clean atomic apply (DEC-003/AC-4); conflicts are
# surfaced for human resolution, never silently merged (AC-3).
# Also (BTG-332, D4/D5): classifies and rewrites the adopter's active specs/<id>/
# vocabulary to SCOUT (D1's map) inside the same atomic apply, and offers --rewrite-vocab
# as a separate, stamp-independent entry point for branches merged after an upgrade.
# Spec: specs/PI-022/spec.md (AC-2..AC-5/8/9); archive/PI-032 (--dry-run, pre-check, Step-0; repointed BTG-126); decisions.md DEC-002/003/006/008/009; archive/BTG-332/spec.md (D4/D5).
# Usage: upgrade-claire.sh <new-version> [--confirm-base <ver>|--two-way] [--dry-run]
#        upgrade-claire.sh --rewrite-vocab [--dry-run]
# Exit: 0 clean/no-op/would-be-clean-dry-run; non-zero on conflict, precondition, or refusal.
set -u

# Observability seam emitter -- a seam "fires" as a stderr line + non-zero exit.
emit_seam() {
  local seam_type="$1" event_name="$2" subject="${3:-}"
  echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
}

# Resolve the adopter repo (the merge TARGET) and the core checkout. Test seams
# UPGRADE_TARGET / UPGRADE_CORE mirror eject's EJECT_FOOTPRINT/EJECT_AUDIT.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Colocated sidecar modules (PI-023/PI-036), sourced after SELF_DIR so their functions are in
# scope for main() (globals resolve at call time): base/merge (upgrade-bootstrap.sh) + the PI-032 --dry-run/--autogen-footprint mode helpers (upgrade-modes.sh).
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-bootstrap.sh"
# BTG-008: the hook relocation + settings-registration-sync concern (AC-5/AC-8),
# a colocated sidecar module shipped by the directory-copy contract. Sourced here
# so its functions are in scope for main(); the globals they read (CORE/TARGET/
# emit_seam/core_file) resolve at call time.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-hooks.sh"
# BTG-057: the MCP-registration reconciliation concern (AC-4), a colocated sidecar
# module shipped by the same directory-copy contract. Sourced here so its functions
# (mcp_core_manifest / mcp_relocate_and_sync) are in scope for main().
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-mcp.sh"
# PI-032/DEC-009: the --dry-run / --autogen-footprint mode helpers (dry_run_finish,
# run_autogen_mode). Sourced here so they are in scope for main() and the option
# dispatch below.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-modes.sh"
# PI-039: the create-if-missing id-ledger scan-and-seed module (DEC-006). Sourced
# here so run_idseed_mode is in scope; dispatched by --seed-ledger below, OUTSIDE
# main()'s atomic merge transaction (it never touches the version stamp).
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-idseed.sh"
# BTG-047: the clobber-safe removed-upstream removal shim (AC-13 / DEC-006).
# Sourced here so removals_classify is in scope for main(); the globals it reads
# (CORE / TARGET / emit_seam / core_file) resolve at call time. Upgrade-only.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-removals.sh"
# BTG-048: the template-to-live org-fold sidecar (DEC-009). Sourced here so
# run_orgfold is in scope for main(); dispatched on the clean-apply path AFTER the
# stamp advance + stale-staging cleanup (a dependent, best-effort, stamp-independent
# post-apply stage -- the --repair precedent). Reads TARGET/CORE/BASE_EMPTY/
# NEW_VERSION/emit_seam/core_file from this scope at call time.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-orgfold.sh"
# BTG-100: the post-apply dead-citation baseline concern (AC-3 / DEC-004). Sourced
# here so ensure_dead_citation_baseline is in scope for main(); dispatched on the
# clean-apply path BEFORE the stamp advance. Reads TARGET/emit_seam at call time.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-baseline.sh"
# BTG-132 (DEC-005): the "apply" half of the compute/apply seam -- the atomic
# write transaction, reached only on the fully-clean path. Sourced here so
# run_apply_transaction is in scope for main(); it reads main()'s locals
# (staging/base_ver/base_commit/changed/IN_SCOPE/...) at call time, exactly as
# the modules above read CORE/TARGET/emit_seam. Splitting the entry point behind
# this named seam is what brings it back under the PI-037 400-line DX ceiling.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-apply.sh"
# BTG-198: the context-wiring concern -- context_wiring_state,
# context_assert_sidecar_in_core, context_detect_and_report (non-mutating) and
# context_repair (mutating, --repair only). Sourced here so all four are in scope
# for main() and for the --repair sidecar. The DETECTOR is dispatched AFTER the
# atomic apply and OUTSIDE its transaction, so a detection notice can never
# affect whether the stamp advanced.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-context.sh"
# BTG-132 (DEC-005, conditional second seam): the "pre-flight" half -- the
# precondition phase (no-stamp bootstrap, footprint boundary, epoch warnings,
# forward-only check, ours/base resolution). Writes nothing; refuses or resolves.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-preflight.sh"
# BTG-332 (D1-D5): the retired-vocabulary-to-SCOUT active-spec classifier and its
# tree-level migration stage. Sourced here so vocab_classify_file, vocab_apply,
# vocab_report_plan and run_rewrite_vocab_mode are in scope for main() and for
# the --rewrite-vocab dispatch below. Reads TARGET/emit_seam/staging/DRY_RUN
# from this scope at call time, exactly as the sidecars above.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-vocab-rules.sh"
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-vocab.sh"
# BTG-332 DEC-033/DEC-036 (code-review cycle 3 B3): the reference-document
# swap, split out of upgrade-vocab.sh to stay under the PI-037 400-line
# ceiling. Sourced here so vocab_ref_validate_core/vocab_ref_classify/
# vocab_ref_apply/vocab_ref_report_plan are in scope for run_rewrite_vocab_mode
# (upgrade-vocab.sh), its only caller. Reads TARGET/CORE/emit_seam from this
# scope at call time.
# shellcheck source=/dev/null
. "$SELF_DIR/upgrade-vocab-ref.sh"
TARGET="${UPGRADE_TARGET:-$PWD}"
CORE="${UPGRADE_CORE:-$(cd "$SELF_DIR/../../.." && pwd)}"
STAMP="$TARGET/.claire-version"
FOOTPRINT="$TARGET/artifacts/footprint.generated"

# BTG-016b: --repair is a SEPARATE operation (sidecar) -- dispatch before parsing.
if [[ "${1:-}" == "--repair" ]]; then . "$SELF_DIR/upgrade-repair.sh"; upgrade_repair "$@"; exit $?; fi
# BTG-049: --repair-orgfold is a SEPARATE, stamp-independent operation (sidecar) --
# the on-demand org-fold (PI-003 bootstrapping remedy). Dispatch before parsing;
# upgrade-orgfold.sh is already sourced (line 57), so run_orgfold is in scope.
if [[ "${1:-}" == "--repair-orgfold" ]]; then . "$SELF_DIR/upgrade-orgfold-repair.sh"; upgrade_orgfold_repair "$@"; exit $?; fi
NEW_VERSION=""
CONFIRM_BASE=""          # set by the wrapper after the human confirms the base.
TWO_WAY=0               # the human-driven no-base fallback (every diff surfaced).
DRY_RUN=0              # AC-3: preview the merge, write NOTHING (CI-keyable exit).
AUTOGEN_FOOTPRINT=0    # PI-032/DEC-009: Step-0 mode -- derive the footprint via the tested helper.
SEED_LEDGER=0         # PI-039/DEC-006: create-if-missing id-ledger scan-and-seed mode.
REWRITE_VOCAB=0      # BTG-332/D5: stamp-independent retired-vocabulary-to-SCOUT active-spec rewrite.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-base)
      # BTG-050 value-presence guard -- parity with the --from sidecar guards. The
      # bare "$2" under `set -u` (line 15) makes a dangling --confirm-base exit on a
      # CRYPTIC `$2: unbound variable` (fast, not a hang) and silently swallow a
      # flag-lookalike (--confirm-base --two-way) as the base value. Fail loud BEFORE
      # the bare read with a named, --confirm-base-specific message and cover shift 2.
      # A version value never legitimately starts with --, so --* is "not a value".
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "upgrade-claire: --confirm-base requires a <ver> value (none given)." >&2
        exit 2
      fi
      CONFIRM_BASE="$2"; shift 2 ;;
    --two-way)      TWO_WAY=1; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --autogen-footprint) AUTOGEN_FOOTPRINT=1; shift ;;
    --seed-ledger)  SEED_LEDGER=1; shift ;;
    --rewrite-vocab) REWRITE_VOCAB=1; shift ;;
    --*) echo "upgrade-claire: unknown option: $1" >&2; exit 2 ;;
    *) if [[ -z "$NEW_VERSION" ]]; then NEW_VERSION="$1"; shift; else
         echo "upgrade-claire: unexpected argument: $1" >&2; exit 2; fi ;;
  esac
done
# Step-0 production entry point (DEC-009): `--autogen-footprint` derives the absent
# footprint THROUGH the tested temp-then-move helper (run_autogen_mode in the
# bootstrap module) -- the single safe command, no bare redirect; needs no version.
if [[ "$AUTOGEN_FOOTPRINT" -eq 1 ]]; then run_autogen_mode; exit $?; fi
# PI-039 (DEC-006): `--seed-ledger` bootstraps the id-allocation ledger from the
# adopter's real history. Dispatched HERE -- before the NEW_VERSION check and
# entirely outside main()'s atomic merge transaction -- so it never reads, writes,
# or advances the .claire-version stamp and needs no version argument. Honors
# --dry-run (writes nothing). Create-if-missing: an already-seeded prefix is skipped.
if [[ "$SEED_LEDGER" -eq 1 ]]; then run_idseed_mode; exit $?; fi
# BTG-332 (D5): `--rewrite-vocab` migrates specs/<id>/ vocabulary for branches
# merged after an upgrade (and core's own active specs, OQ-8). Dispatched HERE,
# on the --seed-ledger precedent -- before the NEW_VERSION check and entirely
# outside main()'s atomic merge transaction, so it never reads, writes, or
# advances the .claire-version stamp and needs no version argument.
# DEC-053 pre-merge fix-up (held candidate c1-4): a version argument combined
# with --rewrite-vocab was silently ignored (NEW_VERSION is captured by the
# generic positional-argument branch above, regardless of --rewrite-vocab).
# Reject the combination loud and named, rather than silently discarding the
# version, BEFORE dispatching to run_rewrite_vocab_mode.
if [[ "$REWRITE_VOCAB" -eq 1 ]]; then
  if [[ -n "$NEW_VERSION" ]]; then
    echo "upgrade-claire: --rewrite-vocab does not take a version argument (got '$NEW_VERSION') -- --rewrite-vocab is stamp-independent and never reads or writes .claire-version; run it alone." >&2
    exit 2
  fi
  run_rewrite_vocab_mode; exit $?
fi
if [[ -z "$NEW_VERSION" ]]; then
  echo "upgrade-claire: usage: upgrade-claire.sh <new-version> [--confirm-base <ver>]" >&2
  exit 2
fi

# The in-scope collection concern -- collect_in_scope, resolve_root, and the
# IN_SCOPE array -- moved to the sourced upgrade-bootstrap.sh module (BTG-007
# DEC-006 / R-4: a behavior-preserving extraction, so this entry point stays
# under the DX <300-line target). They run in this shell's scope via dynamic
# scoping, exactly as the bootstrap functions do; main() calls collect_in_scope
# after the sidecar is sourced.
# The no-stamp bootstrap / base-inference concern -- stamp_field, version_cmp,
# core_commit_for_version, core_file, infer_base_version, bootstrap_if_no_stamp,
# and the BOOT_BASE_COMMIT / BASE_EMPTY globals -- lives in the sourced
# upgrade-bootstrap.sh module (PI-023 DEC-008). They are in scope here.

main() {
  # Pre-flight: establish that this upgrade may proceed and resolve the two
  # commits to merge between. The three locals are declared HERE, not in the
  # module, so run_preflight's assignments survive its return (see the scoping
  # note in upgrade-preflight.sh). `|| return $?` preserves both the refusal
  # statuses and the "already up to date" 0-return.
  local base_ver base_commit ours_commit
  run_preflight; local pf_rc=$?
  # 20 == PREFLIGHT_UP_TO_DATE: "already at <version>", which was a `return 0`
  # from main() before the extraction and must STOP rather than fall through
  # into the compute phase. Any other non-zero is a refusal and propagates.
  if [[ $pf_rc -eq 20 ]]; then
    # BTG-198: an already-up-to-date run still REPORTS broken context wiring. The
    # detector is the only signal a mid-migration adopter gets, and R-1 accepts
    # that they may never run --repair -- so a run that merges nothing must not
    # also say nothing. Non-mutating and always returns 0, so the up-to-date
    # exit status is unchanged.
    context_detect_and_report "$TARGET"
    return 0
  fi
  if [[ $pf_rc -ne 0 ]]; then return "$pf_rc"; fi

  collect_in_scope "$ours_commit" || return 1

  # BTG-198: the sidecar's RECONCILE add row is gated by core ownership, and a
  # gate that declines simply skips -- so an adopter upgrading to a core version
  # that does not own CLAIRE_DIRECTIVES.md would never receive it and would
  # never be told. Name that, before anything is applied. Non-blocking.
  context_assert_sidecar_in_core "$ours_commit"

  # Compute the full 3-way merge FIRST (atomic: nothing applied until all clean).
  local staging; staging="$(mktemp -d)"
  local conflicts=0 changed=() conflicted=()
  local rel merged
  for rel in "${IN_SCOPE[@]}"; do
    merged="$staging/merged"
    # Per-file 3-way merge -> $merged, MERGE_RC (0 clean / 1 conflict). The base
    # rule (2-way fallback, G-5 never-installed vs deletion) and the DEC-006
    # config-shaped model: normalization live in merge_one_file (upgrade-bootstrap.sh).
    merge_one_file "$rel" "$base_commit" "$ours_commit" "$staging"
    if [[ "$MERGE_RC" -eq 0 ]]; then
      # >>> BTG-100 empty-result-anchor-start: SCOPED EMPTY-RESULT ASSERTION (DEC-003/DEC-012) >>>
      # A backfilled path can never legitimately merge to zero bytes: theirs is
      # absent and base is empty BY CONSTRUCTION (merge_one_file's backfill-base
      # branch), so merged must equal ours. Writing an empty form would install a
      # 0-byte script, which exits 0 -- a SILENT success (the PROD_CLAIRE-010 fail-open).
      # SCOPED to marked paths only: an empty merge is legitimate in general (an
      # adopter deliberately emptying a file core did not change), and a blanket
      # assertion would regress that -- S-1.7-control pins it. Defence-in-depth
      # against a future refactor breaking the base branch (S-1.7 strips it).
      if [[ -n "${RECONCILE_BACKFILLED[$rel]:-}" && ! -s "$merged" && -s "$staging/ours" ]]; then
        emit_seam IMPOSSIBLE_STATE upgrade.apply.backfill_empty_result "$rel"
        echo "upgrade-claire: $rel is delivered by a RECONCILE backfill but merged to ZERO bytes while core@$NEW_VERSION's copy is not empty." >&2
        echo "upgrade-claire: refusing to write it -- an empty script exits 0 and would be a silent success. Nothing applied; the stamp stays at $base_ver." >&2
        rm -rf "$staging"
        return 1
      fi
      # <<< BTG-100 empty-result-anchor-end <<<
      cp "$merged" "$staging/apply.$(echo "$rel" | tr '/' '_')"
      changed+=("$rel")
    else
      conflicts=$((conflicts + 1))
      conflicted+=("$rel")
      cp "$merged" "$staging/conflict.$(echo "$rel" | tr '/' '_')"
      # G-4 anomaly seam (DEC-004): a constituent from a DIRECTORY-row expansion
      # conflicted -> fire directory_as_file_path naming the SOURCE directory (not
      # the constituent). Silent on the all-clean path (the only fire site for a
      # conflict; the apply-failure site below covers non-clean apply).
      [[ -n "${DIR_EXPANDED[$rel]:-}" ]] \
        && emit_seam LOGIC_FAULT upgrade.merge.directory_as_file_path "${DIR_EXPANDED[$rel]}"
    fi
  done

  # BTG-332 (D4): classify the adopter's active specs/ vocabulary BEFORE the
  # dry-run return, so --dry-run previews the vocab plan too (S-2.4). An
  # ambiguous line folds into the SAME conflict machinery the framework-file
  # merge above uses -- vocab_classify_tree already staged
  # $staging/conflict.<munged> in the identical naming convention the generic
  # staging loop below reads from, so no change was needed there.
  vocab_classify_tree "$staging"
  if [[ "${VOCAB_FATAL:-0}" -eq 1 ]]; then
    rm -rf "$staging"
    return 1
  fi
  local vrel vln vlinelist
  for vrel in "${VOCAB_CONFLICT[@]:-}"; do
    [[ -n "$vrel" ]] || continue
    conflicts=$((conflicts + 1)); conflicted+=("$vrel")
    vlinelist="${VOCAB_AMBIG_BY_FILE[$vrel]:-}"
    IFS=',' read -ra _vlns <<< "$vlinelist"
    for vln in "${_vlns[@]:-}"; do [[ -n "$vln" ]] && echo "vocab-conflict: $vrel:$vln" >&2; done
  done

  # AC-3 dry-run: merge fully computed; the finisher reports/clears/returns the
  # CI-keyable code BEFORE any write (DEC-004/005). Returns HERE -- before the
  # BTG-008 hook-relocation guard -- so a dry-run never mktemps a relocation
  # manifest nor stages hook conflicts (a dry-run writes NOTHING).
  if [[ $DRY_RUN -eq 1 ]]; then
    vocab_report_plan
    dry_run_finish "$staging" "$conflicts" "${#IN_SCOPE[@]}" "${#changed[@]}" "${conflicted[@]}"; return $?
  fi

  # BTG-008 AC-8: relocation no-data-loss guard (R-6). Compute core@new's hooks
  # manifest once (reused post-apply). For each KNOWN legacy hook the adopter
  # CUSTOMIZED vs the stamped base, surface a conflict (staged; not removed; stamp
  # NOT advanced) -- reusing the upgrade conflict path so the human reconciles.
  RELOC_MANIFEST="$(mktemp)"; HAVE_HOOKS=0
  if hooks_core_manifest "$ours_commit" "$RELOC_MANIFEST"; then
    HAVE_HOOKS=1
    local cf
    while IFS= read -r cf; do
      [[ -n "$cf" ]] || continue
      conflicts=$((conflicts + 1)); conflicted+=("$cf")
      cp "$TARGET/$cf" "$staging/conflict.$(echo "$cf" | tr '/' '_')"
    done < <(hooks_legacy_customized "$base_commit" "$BASE_EMPTY" "$RELOC_MANIFEST")
  fi

  # BTG-057 AC-4: compute core@new's MCP manifest once (reused post-apply). HAVE_MCP=0
  # when core@new predates artifacts/mcp (the PI-003 bootstrapping gap, surfaced on
  # the clean-apply path). No pre-apply conflict computation is needed -- MCP
  # registration has no on-disk file to relocate (the reserved key prefix is the
  # sentinel), so the idempotent upsert runs on the clean-apply path only.
  MCP_MANIFEST="$(mktemp)"; HAVE_MCP=0
  mcp_core_manifest "$ours_commit" "$MCP_MANIFEST" && HAVE_MCP=1


  # BTG-047 (AC-13 / DEC-006): clobber-safe removal of removed-upstream files.
  # Classify each manifest path present in the adopter against the stamp-base bytes
  # (core_file at base_commit -- the same base merge_one_file uses). A byte-identical
  # (pristine) file is queued for deletion on the clean-apply path; a MODIFIED file is
  # surfaced as an ordinary conflict (staged, counted, stamp NOT advanced), never
  # clobbered -- preserving upgrade's no-clobber safety property. Runs in the pre-apply
  # computation phase (before the conflict gate), so it obeys the atomic contract.
  # Skipped implicitly under --dry-run (that path returned above; a dry-run writes
  # nothing, including no removal). Upgrade-only -- adopt never delivered these files.
  removals_classify "$base_commit" "$BASE_EMPTY"
  local rmrel
  for rmrel in "${REMOVALS_CONFLICT[@]:-}"; do
    [[ -n "$rmrel" ]] || continue
    emit_seam IMPOSSIBLE_STATE upgrade.removal.modified_file_clobber_avoided "$rmrel"
    conflicts=$((conflicts + 1)); conflicted+=("$rmrel")
    cp "$TARGET/$rmrel" "$staging/conflict.$(echo "$rmrel" | tr '/' '_')"
  done

  if [[ $conflicts -gt 0 ]]; then
    # Surface the conflicts in a reviewable staging tree -- NOT applied (atomic;
    # never a silent merge -- AC-3/SEAM_VIOLATION upgrade.merge.silent_resolution).
    # The working copy stays theirs; the stamp is unchanged; the human resolves.
    assert_not_dry_run staging || { rm -rf "$staging"; return 1; }   # defensive (unreachable under dry-run)
    local stage_root="$TARGET/.claire-upgrade-staging"
    rm -rf "$stage_root"
    for rel in "${conflicted[@]}"; do
      mkdir -p "$stage_root/$(dirname "$rel")"
      cp "$staging/conflict.$(echo "$rel" | tr '/' '_')" "$stage_root/$rel"
    done
    echo "upgrade-claire: $conflicts conflicting file(s) -- NOT applied (atomic; stamp unchanged):" >&2
    printf '  conflict: %s\n' "${conflicted[@]}" >&2
    echo "upgrade-claire: conflicted forms staged for review under .claire-upgrade-staging/ (with conflict markers)." >&2
    echo "upgrade-claire: resolve the conflicts and re-run; the stamp stays at $base_ver." >&2
    rm -rf "$staging"; rm -f "$RELOC_MANIFEST" "$MCP_MANIFEST"
    return 1
  fi
  # The compute phase is done and every file merged clean; hand off to the
  # atomic write transaction. `|| return $?` is LOAD-BEARING: steps inside
  # refuse by returning non-zero, and a swallowed refusal would report success
  # with the stamp wrongly advanced (BTG-132 Risk R-3).
  run_apply_transaction || return $?

  # BTG-198 (DEC-009): the post-apply context-wiring detector. Runs AFTER the
  # atomic apply and OUTSIDE its transaction, so a detection notice can never
  # affect whether the stamp advanced, and it writes NOTHING -- CLAUDE.md is the
  # adopter's file and the framework does not edit it because a check failed. It
  # re-fires on every run until repaired: an adopter who ignores it once still
  # sees it, which is the whole mitigation for R-1. Always returns 0.
  context_detect_and_report "$TARGET"
}

main "$@"
