#!/usr/bin/env bash
#
# upgrade-orgfold-repair.sh -- the /cadence-upgrade --repair-orgfold on-demand
# org-fold sidecar (BTG-049). A colocated module shipped by the PI-023 directory-
# copy contract and sourced by upgrade-cadence.sh's --repair-orgfold dispatch, so
# it runs in the entry point's shell scope: the globals it sets (BASE_EMPTY,
# NEW_VERSION) and reads (TARGET, CORE, STAMP) and the helpers it reuses
# (emit_seam, stamp_field, core_commit_for_version, run_orgfold) resolve at CALL
# time from that scope (dynamic scoping), exactly like upgrade-repair.sh.
#
# Bounded context: Upgrade seam / on-demand bootstrapping-gap remediation (BTG-049).
# Upstream: run explicitly by a fleet operator whose FIRST post-4.0.1 upgrade was
#   run by the OLD (pre-fold) engine, so the engine-resident org-fold silently
#   skipped that upgrade (the PI-003 bootstrapping gap). Downstream: reconciles the
#   just-applied docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md inter-version changes
#   into the adopter's live docs/agentic-sdlc/CADENCE_ORG.md by calling BTG-048's
#   run_orgfold UNCHANGED -- same section-aware routing, conflict-staging (never in
#   place), best-effort loud skips, and seams.
# Spec: specs/BTG-049/spec.md (AC-1..AC-5); decisions.md DEC-001..DEC-006.
#
# Contract: a SEPARATE, stamp-independent operation (the --repair precedent) --
# dispatched before the merge arg parse, it NEVER reads-to-advance, writes, or
# rolls back .cadence-version. Idempotent (content-level, DEC-004): a re-run
# leaves the live file byte-stable. An unresolvable/unreachable pre-upgrade base
# fails LOUD (DELTA_AUDIT_GAP upgrade.orgfold.base_source_missing, exit non-zero) --
# never a guessed base (Behavior 5).

# ---------------------------------------------------------------------------
# orgfold_repair_base -- echo the PRE-upgrade core base commit, or nothing on
# ambiguity. Mirrors repair_seed_source_ref (upgrade-repair.sh:38-49): the anchor
# is the PARENT of the stamp-advancing commit (the commit that last touched
# .cadence-version); the pre-upgrade core commit is the commit= field of the
# .cadence-version blob at that parent. On ANY ambiguity -- no such commit, a root
# commit (no parent), or a merge commit (2+ parents: squashed/non-linear history),
# or an unreadable blob -- resolve NOTHING and let the caller fail loud. Honors an
# explicit --from override via $ORGFOLD_FROM (a dotted version -> resolved through
# core_commit_for_version; else treated as a raw core commit ref), which bypasses
# the anchor entirely.
# ---------------------------------------------------------------------------
orgfold_repair_base() {
  if [[ -n "${ORGFOLD_FROM:-}" ]]; then
    if [[ "$ORGFOLD_FROM" =~ ^[0-9]+\.[0-9]+ ]]; then
      core_commit_for_version "$ORGFOLD_FROM"
    else
      echo "$ORGFOLD_FROM"
    fi
    return 0
  fi
  local stampc parents n blob commit
  stampc="$(git -C "$TARGET" log -1 --format=%H -- .cadence-version 2>/dev/null)"
  [[ -n "$stampc" ]] || { echo ""; return 0; }
  # rev-list --parents -n1 prints "<commit> [<parent> ...]": 2 tokens = one parent
  # (linear, unambiguous); 1 token = root (no pre-upgrade blob); >=3 = merge.
  parents="$(git -C "$TARGET" rev-list --parents -n1 "$stampc" 2>/dev/null)"
  n="$(printf '%s\n' "$parents" | wc -w)"
  [[ "$n" -eq 2 ]] || { echo ""; return 0; }
  blob="$(mktemp)"
  git -C "$TARGET" show "$stampc^:.cadence-version" > "$blob" 2>/dev/null
  commit="$(stamp_field commit "$blob")"
  rm -f "$blob"
  echo "$commit"
}

# ---------------------------------------------------------------------------
# The on-demand org-fold entry point. Args: --repair-orgfold [--from <ref>].
# Resolves the pre-upgrade base commit, verifies it is reachable in CORE, sets the
# two globals run_orgfold reads (BASE_EMPTY, NEW_VERSION), and calls run_orgfold
# UNCHANGED. Best-effort / stamp-independent: run_orgfold's own loud skips
# (BASE_EMPTY / empty base / no live file / template unchanged) and conflict
# staging are reused verbatim; only base resolution can fail loud here.
# ---------------------------------------------------------------------------
upgrade_orgfold_repair() {
  local ORGFOLD_FROM=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repair-orgfold) shift ;;
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
        ORGFOLD_FROM="$2"; shift 2 ;;
      *) echo "upgrade-cadence --repair-orgfold: unknown option: $1" >&2; return 2 ;;
    esac
  done

  local base_commit; base_commit="$(orgfold_repair_base)"
  if [[ -z "$base_commit" ]]; then
    emit_seam DELTA_AUDIT_GAP upgrade.orgfold.base_source_missing ".cadence-version"
    echo "upgrade-cadence --repair-orgfold: cannot resolve the pre-upgrade base commit (ambiguous/non-linear history) -- pass --from <version-or-core-ref>." >&2
    return 1
  fi
  if ! git -C "$CORE" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    emit_seam DELTA_AUDIT_GAP upgrade.orgfold.base_source_missing "$base_commit (unreachable in core)"
    echo "upgrade-cadence --repair-orgfold: base commit $base_commit is unreachable in the core checkout -- point UPGRADE_CORE at a checkout containing it." >&2
    return 1
  fi

  BASE_EMPTY=0                                    # a real pre-upgrade base was resolved
  NEW_VERSION="$(stamp_field version "$STAMP")"   # for git merge-file conflict labels only
  run_orgfold "$base_commit"                      # reused UNCHANGED; best-effort, exit 0
}
