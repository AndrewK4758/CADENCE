#!/usr/bin/env bash
#
# upgrade-resolve.sh -- the /cadence-upgrade version-to-commit base-identity
# resolution concern (BTG-311), extracted from upgrade-bootstrap.sh so each
# module holds a single coherent concern and both stay under the DX <400-line
# target (upgrade-bootstrap.sh was at 387/400; this concern did not fit in the
# remaining 13 lines). A colocated sidecar module the PI-023 directory-copy
# contract ships into the compiled skill, mirroring the BTG-020 DEC-002
# extraction of upgrade-collect.sh out of this same file.
#
# Bounded context: Upgrade seam / layered-source flow (PI-022, Workstream A).
# Sourced by upgrade-bootstrap.sh via a self-locating guard, so it runs in the
# entry point's shell scope: the globals these functions read (CORE) and the
# emit_seam helper are resolved at CALL time from that scope (dynamic scoping).
#
# Invariant relied on from outside this boundary: `/cadence-release` (step 6)
# always creates an annotated `vX.Y.Z` tag on the released commit and bumps
# README.md's "**Version X.Y.Z**" line on that same commit (the version-of-
# record). Within a tag's own history those two identities coincide (measured
# 22/22 releases, archive/BTG-311/spec.md "Measured Evidence").
#
# FOURTH CALLER (BTG-314): /cadence-adopt's release phase
# (artifacts/commands/cadence-adopt/adopt-release-tree.sh) sources this file
# from the RUNNING checkout, in a private subshell that binds its own CORE and
# defines its own emit_seam before sourcing -- the same caller contract every
# other caller in THIS checkout already honors (CORE and emit_seam resolved
# from the caller's scope at call time). This is a comment-only change: no
# function below is edited for BTG-314.
#
# Spec: archive/BTG-311/spec.md (AC-1, AC-3, AC-4, AC-5); decisions.md DEC-001,
#       DEC-002, DEC-003, DEC-005, DEC-006. BTG-314 caller: archive/BTG-314/spec.md
#       (AC-2); decisions.md DEC-002, DEC-006.

# core_tag_for_version <ver>
#   Echo, one per line, each tag name that EXISTS in $CORE for <ver>, tried in
#   the order "v<ver>", "<ver>" (the adopt-provision.sh:41-47 `^v?(...)$`
#   precedent -- decisions.md DEC-005). Exact-name existence only, via
#   `git show-ref --tags --verify`, NEVER a pattern match: a version string can
#   legally contain a glob metacharacter, and a pattern match could resolve a
#   foreign tag (spec.md Non-Functional Considerations, "Input handling").
#   Scheme-agnostic by construction: the version string already carries the
#   bound scheme's shape (CADENCE_ORG.md#version-scheme-binding, BTG-303), so no
#   read of that binding is required here, and none is added (DEC-005 -- the
#   tag spelling stays an engine-local convention, not a declared binding
#   field). Echoes nothing when neither spelling exists.
core_tag_for_version() {
  local ver="$1" name
  for name in "v$ver" "$ver"; do
    if git -C "$CORE" show-ref --tags --verify -q "refs/tags/$name" 2>/dev/null; then
      echo "$name"
    fi
  done
}

# _core_commit_scan_all <ver>
#   The UNCHANGED pre-BTG-311 selector: walk every ref in $CORE
#   (reverse-chronological) and echo the first commit whose README.md declares
#   "**Version <ver>**", or nothing. Retained byte-for-byte as (a) the
#   announced fallback when no tag resolves (AC-4, R13) and (b) a diagnostic-
#   only computation on the H1 halt path (AC-5) -- never as the resolver's
#   answer when a tag exists.
_core_commit_scan_all() {
  local ver="$1" c
  while IFS= read -r c; do
    local readme_ver
    readme_ver="$(git -C "$CORE" show "$c:README.md" 2>/dev/null \
                    | sed -nE 's/^\*\*Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' \
                    | head -n1)"
    if [[ "$readme_ver" == "$ver" ]]; then
      echo "$c"; return 0
    fi
  done < <(git -C "$CORE" rev-list --all 2>/dev/null)
  return 0
}

# core_commit_for_version <ver>
#   CONTRACT (UNCHANGED, BTG-311): echo exactly one commit sha on stdout, or
#   echo nothing. Every diagnostic goes to stderr -- stdout is captured by all
#   three callers (upgrade-preflight.sh's ours_commit, upgrade-bootstrap.sh's
#   --confirm-base, upgrade-orgfold-repair.sh's --from) as the resolved commit,
#   so a diagnostic on stdout would silently corrupt the base identity (spec.md
#   Non-Functional Considerations, Security).
#
# AUTHORITY NOTE (BTG-311, narrowing PI-031 / DEC-002 -- see
# archive/BTG-311/decisions.md DEC-002 for the full reconciliation, never edited
# in the archived PI-031 text): the commit this function returns is STILL the
# README-of-record and STILL the commit a hand-resolver diffs against
# (DEC-002's ruling is narrowed, not reversed). What changed is the DOMAIN it
# is selected from: where a release tag `v<ver>` or `<ver>` exists in $CORE,
# the candidate set is bounded to that tag's own history (`git rev-list <tag>`)
# rather than every ref in the checkout -- so within released history the
# README-of-record and the tag commit COINCIDE (measured 22/22 releases in
# this repository, spec.md "Measured Evidence"). Where NO tag resolves for the
# version, the engine falls back to the pre-BTG-311 all-refs scan and
# ANNOUNCES that the resolution is unadjudicated (DRIFT_SIGNAL
# upgrade.base.resolved_without_tag) -- it never silently trusts an
# unconstrained scan again. A tag that cannot itself adjudicate the version
# (no commit in its history declares it), or two tag spellings that disagree,
# both halt loud (BOUNDARY_FAULT / UNSOUND_CONDITION below) rather than guess.
core_commit_for_version() {
  local ver="$1"
  local tags=() line
  while IFS= read -r line; do
    [[ -n "$line" ]] && tags+=("$line")
  done < <(core_tag_for_version "$ver")

  # H2: two tag spellings exist and peel to DIFFERENT commits -- an ambiguity
  # the engine refuses to resolve rather than guess which spelling wins (R15 /
  # DEC-005). Two spellings peeling to the SAME commit is not an ambiguity
  # (S-1.3) and falls through to the ordinary tag-bounded walk below.
  if [[ ${#tags[@]} -eq 2 ]]; then
    local c1 c2
    c1="$(git -C "$CORE" rev-list -n1 "${tags[0]}" 2>/dev/null)"
    c2="$(git -C "$CORE" rev-list -n1 "${tags[1]}" 2>/dev/null)"
    if [[ -n "$c1" && -n "$c2" && "$c1" != "$c2" ]]; then
      emit_seam UNSOUND_CONDITION upgrade.base.tag_spelling_ambiguous "$ver"
      echo "upgrade-cadence: version $ver resolves ambiguously -- tag ${tags[0]} -> $c1, tag ${tags[1]} -> $c2." >&2
      echo "upgrade-cadence: refusing -- remove or correct the duplicate tag spelling in the core checkout." >&2
      return 1
    fi
  fi

  # No tag spelling resolves: the announced fallback (AC-4). Never a silent
  # exit 0 -- the Elicited Intent names that as the violation this fix removes.
  if [[ ${#tags[@]} -eq 0 ]]; then
    emit_seam DRIFT_SIGNAL upgrade.base.resolved_without_tag "$ver"
    echo "upgrade-cadence: no tag v$ver or $ver exists in the core checkout for version $ver." >&2
    echo "upgrade-cadence: resolution falls back to an unadjudicated all-refs README scan (fetch tags and re-run to adjudicate)." >&2
    _core_commit_scan_all "$ver"
    return 0
  fi

  # One tag (or two peeling to the same commit): the candidate set is bounded
  # to the tag's own history. The README line remains the selector WITHIN that
  # set (DEC-002's README-of-record authority, narrowed rather than reversed).
  local tag="${tags[0]}" c
  while IFS= read -r c; do
    local readme_ver
    readme_ver="$(git -C "$CORE" show "$c:README.md" 2>/dev/null \
                    | sed -nE 's/^\*\*Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' \
                    | head -n1)"
    if [[ "$readme_ver" == "$ver" ]]; then
      echo "$c"; return 0
    fi
  done < <(git -C "$CORE" rev-list "$tag" 2>/dev/null)

  # H1: the tag resolved but no commit inside its history declares the
  # version -- a resolution gap, not a fallback (R14). Halt loud, naming every
  # candidate the diagnostic can find; write nothing, echo nothing (R17).
  local tag_commit allscan
  tag_commit="$(git -C "$CORE" rev-list -n1 "$tag" 2>/dev/null)"
  allscan="$(_core_commit_scan_all "$ver")"
  emit_seam BOUNDARY_FAULT upgrade.base.resolved_outside_release "$ver"
  echo "upgrade-cadence: tag $tag ($tag_commit) exists for version $ver, but no commit in its history declares \"**Version $ver**\"." >&2
  if [[ -n "$allscan" ]]; then
    echo "upgrade-cadence: an all-refs scan (diagnostic only, never used as the base) found $allscan declaring that version outside the tag's history." >&2
  else
    echo "upgrade-cadence: no README-of-record for $ver was found on any ref either." >&2
  fi
  echo "upgrade-cadence: this may indicate a shallow clone (run 'git fetch --unshallow' and retry) or an inconsistent release cut." >&2
  return 1
}
