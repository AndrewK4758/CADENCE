#!/usr/bin/env bash
#
# upgrade-bootstrap.sh -- the /cadence-upgrade bootstrap / base-inference module
# (PI-022 DEC-009), extracted from upgrade-cadence.sh (PI-023 DEC-008) so the
# entry point stays under the DX <300-line target. This is a BEHAVIOR-PRESERVING
# extraction: the functions move verbatim, no merge-logic change.
#
# Bounded context: Upgrade seam / layered-source flow (PI-022, Workstream A).
# Sourced by upgrade-cadence.sh via `source "$SELF_DIR/upgrade-bootstrap.sh"`,
# so it runs in the entry point's shell scope: the globals these functions read
# (SELF_DIR, CORE, TARGET, STAMP, FOOTPRINT, CONFIRM_BASE, TWO_WAY) and the
# emit_seam helper are resolved at CALL time from that scope (dynamic scoping),
# and the BOOT_BASE_COMMIT / BASE_EMPTY globals this module sets are read by the
# entry point's main(). This file is one of the colocated sidecar modules the
# PI-023 directory-copy contract ships into the compiled skill.
#
# Holds: stamp/version helpers (stamp_field, version_cmp), core-history
# resolution (core_commit_for_version, core_file), base inference
# (infer_base_version), and the no-stamp bootstrap branch (bootstrap_if_no_stamp).
# The in-scope collection concern (collect_in_scope, resolve_root, _is_seed_path,
# the IN_SCOPE array, the unified RECONCILE table) was extracted to the colocated
# sidecar upgrade-collect.sh (BTG-020 DEC-002) to keep each module single-concern
# and both under the DX <300-line target; it is sourced below via a self-locating
# guard so a single `source upgrade-bootstrap.sh` still exposes collect_in_scope /
# resolve_root / _is_seed_path (dynamic scope, entry point AND the test harness).
#
# Spec: specs/PI-022/spec.md (AC-8 / DEC-009); specs/PI-023/spec.md (DEC-008);
#       specs/BTG-007/spec.md (R-4 / DEC-006); specs/BTG-020/spec.md (DEC-002).
#
# UPDATE (BTG-311, DEC-006): core_commit_for_version has SINCE MOVED OUT of this
# file, to a second colocated sidecar, upgrade-resolve.sh -- the "Holds" list and
# the Spec line above are the BTG-020-era dated-provenance record (DEC-006 class,
# authored-doc-ledgers.sh) and are deliberately left unedited rather than rewritten
# to describe the current state; this paragraph is that reconciliation. See
# upgrade-resolve.sh's own header for the resolver's current home, and
# archive/BTG-311/spec.md (AC-1/AC-3/AC-4/AC-5, DEC-006) for why it moved.

# The in-scope collection concern lives in the colocated sidecar upgrade-collect.sh
# (BTG-020 DEC-002). Source it with a self-locating guard: SELF_DIR is set by the
# entry point (and by run_collect_in_scope), and falls back to this file's own
# directory when upgrade-bootstrap.sh is sourced directly with SELF_DIR unset
# (e.g. the BTG-018 _is_seed_path unit check) -- so the transitive source always
# resolves and collect_in_scope / resolve_root / _is_seed_path are available.
# shellcheck source=/dev/null
. "${SELF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/upgrade-collect.sh"

# The version-to-commit base-identity resolution concern (core_tag_for_version /
# core_commit_for_version) lives in the colocated sidecar upgrade-resolve.sh
# (BTG-311, DEC-006), extracted for the same DX <400-line reason and sourced
# with the SAME self-locating guard as upgrade-collect.sh above, so a single
# `source upgrade-bootstrap.sh` still exposes core_commit_for_version to the
# entry point, to all three call sites, and to the test harness (dynamic scope).
# shellcheck source=/dev/null
. "${SELF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/upgrade-resolve.sh"

# Read a single key=value from a stamp file. Echoes the value or nothing.
stamp_field() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 0
  sed -nE "s/^$key=(.*)\$/\1/p" "$file" | head -n1
}

# Compare two dotted versions (three dot-separated numeric fields -- scheme-
# agnostic; verified correct for a four-digit-year CalVer value too, BTG-303).
# Echoes -1 (a<b), 0 (a==b), 1 (a>b).
version_cmp() {
  local a="$1" b="$2"
  [[ "$a" == "$b" ]] && { echo 0; return; }
  local hi; hi="$(printf '%s\n%s\n' "$a" "$b" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)"
  if [[ "$hi" == "$a" ]]; then echo 1; else echo -1; fi
}

# core_commit_for_version (version -> git commit base-identity resolution) and
# its AUTHORITY NOTE moved to the colocated sidecar upgrade-resolve.sh (BTG-311,
# DEC-006 -- narrowing PI-031/DEC-002, see archive/BTG-311/decisions.md DEC-002),
# sourced above alongside upgrade-collect.sh. Look there for the resolver, the
# tag-bounded walk, the announced no-tag fallback, and the two named halts.

# G-4 (PI-031 / DEC-001): a kind=installed row whose path resolves to a DIRECTORY
# in the adopter tree (-d) OR a tree object in core@<ours_commit> (git ls-tree -d)
# must be expanded to its CONSTITUENT files -- the SAME enumeration the tree_root
# rows use: find -type f over the adopter tree UNION git ls-tree -r --name-only
# over core@new. A regular-file installed row is NOT a directory and is handled by
# the caller's single-target branch (the engine invariant "every merge input is a
# regular file"). An EMPTY expansion adds nothing (no bare directory path enters
# scope -- G-4.AC-3). Extracted here (the entry point stays under the <300-line DX
# target; PI-023 colocated-sidecar contract) alongside core_file. Reads CORE/TARGET
# and the caller's SEENMAP / DIR_EXPANDED associative arrays from the shared scope
# (dynamic scoping); records each constituent's source directory in DIR_EXPANDED so
# the merge loop can fire the directory_as_file_path anomaly seam (DEC-004).
# Returns 0 if <ip> was a directory (and was expanded), 1 if it was NOT a directory.
expand_dir_row() {
  local ip="$1" ours_commit="$2" f rel
  if [[ ! -d "$TARGET/$ip" ]] \
     && ! git -C "$CORE" ls-tree -d "$ours_commit" -- "$ip" 2>/dev/null | grep -q .; then
    return 1   # not a directory -> caller treats it as a single file target
  fi
  if [[ -d "$TARGET/$ip" ]]; then
    while IFS= read -r f; do
      rel="${f#"$TARGET"/}"; SEENMAP["$rel"]=1; DIR_EXPANDED["$rel"]="$ip"
    done < <(find "$TARGET/$ip" -type f 2>/dev/null)
  fi
  # KNOWN LIMITATION (PI-031 review #3): git ls-tree C-QUOTES pathnames containing
  # a tab/newline/non-ASCII byte (spaces are fine). Such a constituent would
  # enumerate as a quoted string and mismatch the adopter `find` path. Out of
  # practical scope -- footprint-declared directory paths make it extremely
  # unlikely. See specs/PI-031/test-plan.md "Known Limitations".
  while IFS= read -r rel; do
    [[ -n "$rel" ]] && { SEENMAP["$rel"]=1; DIR_EXPANDED["$rel"]="$ip"; }
  done < <(git -C "$CORE" ls-tree -r --name-only "$ours_commit" -- "$ip" 2>/dev/null)
  return 0
}

# Fetch <path> from core@<commit> into <dest_file>; empty file if absent there.
core_file() {
  local commit="$1" path="$2" dest="$3"
  if git -C "$CORE" cat-file -e "$commit:$path" 2>/dev/null; then
    git -C "$CORE" show "$commit:$path" > "$dest" 2>/dev/null
  else
    : > "$dest"
  fi
}

# Per-file 3-way merge of one in-scope rel-path (extracted from main()'s merge
# loop, PI-031 R-1, to keep upgrade-cadence.sh under the 300-line DX target).
# Writes the merged form to <staging>/merged and sets the global MERGE_RC
# (0 clean / 1 conflict). Reads NEW_VERSION / BASE_EMPTY / TARGET / CORE and the
# DIR_EXPANDED map from the shared scope. Behavior-preserving for PI-022; the G-5
# never-installed base rule and the G-4 directory_as_file_path anomaly seam slot
# into this function. Args: <rel> <base_commit> <ours_commit> <staging>.
MERGE_RC=0
merge_one_file() {
  local rel="$1" base_commit="$2" ours_commit="$3" staging="$4"
  local b="$staging/base" t="$staging/theirs" o="$staging/ours" merged="$staging/merged"
  # Per-file base. G-5 (PI-031): a file ABSENT in the adopter tree AND ABSENT from
  # core@base was NEVER installed -> empty base -> clean take-ours (NOT a deletion).
  # A file absent in the adopter but PRESENT in core@base IS a genuine adopter
  # deletion -> base = core@base content -> conflict (the deletion is respected).
  # The never-installed branch is an elif STRICTLY AFTER the global 2-way fallback
  # so it never double-fires under BASE_EMPTY (R-2).
  if [[ "$BASE_EMPTY" -eq 1 ]]; then
    : > "$b"                                   # global 2-way fallback (unchanged)
  elif [[ ! -f "$TARGET/$rel" ]] && ! git -C "$CORE" cat-file -e "$base_commit:$rel" 2>/dev/null; then
    emit_seam DRIFT_SIGNAL upgrade.bootstrap.never_installed_classified_as_deleted "$rel"
    : > "$b"                                   # never installed -> empty base
  # >>> BTG-100 backfill-base-anchor-start: BACKFILL-BASE-BRANCH (DEC-002) >>>
  # BTG-100 (PROD_CADENCE-010): a path delivered by a RECONCILE installed+add row whose
  # per-entry dedup did NOT fire was never in THIS tree's committed descriptor, so
  # it was never installed here -- even when core@base owns it (the reporting
  # adopter is stamped at v4.0.5, where BTG-083 shipped). G-5's `absent from
  # core@base` conjunct is therefore the WRONG proxy for such a path: it falls
  # through to `base = core@base content`, i.e. "the adopter deleted it", which
  # yields either a 0-BYTE file written into the adopter tree (ours == base) or a
  # SPURIOUS delete/modify conflict blocking the whole atomic apply (ours != base).
  # Both observed against this engine before this branch existed (S-1.2a/S-1.2b).
  #
  # Placed as an elif STRICTLY AFTER G-5 -- never before it and never merged into
  # it -- so every path that reaches G-5 today still reaches it and still emits
  # never_installed_classified_as_deleted: no adopter whose upgrade works today
  # sees a changed stream (Backwards Compat #2 over DX #7). This mirrors G-5's own
  # placement rule above ("an elif STRICTLY AFTER the global 2-way fallback").
  #
  # The `! -f "$TARGET/$rel"` conjunct is load-bearing: a file PRESENT in the
  # adopter tree (hand-copied, possibly customized) stays on the ordinary 3-way
  # path and is merged or conflicted, never clobbered (AC-2 / R6).
  #
  # Marker-anchored so a between-markers `sed` delete strips exactly this middle
  # elif clause and leaves `if / elif G-5 / else` -- syntactically valid bash,
  # byte-equivalent to the pre-BTG-100 engine. That is what makes the standing
  # patched-copy discriminator possible (II-024/II-025; the technique
  # mk_patched_engine and BTG-007 S-1.4 already use).
  elif [[ ! -f "$TARGET/$rel" && -n "${RECONCILE_BACKFILLED[$rel]:-}" ]]; then
    emit_seam DELTA_AUDIT_GAP upgrade.merge.backfill_never_in_descriptor "$rel"
    : > "$b"                                   # never in THIS tree's descriptor -> empty base
  # <<< BTG-100 backfill-base-anchor-end: BACKFILL-BASE-BRANCH <<<
  else
    core_file "$base_commit" "$rel" "$b"       # present in base (incl. deletion case)
  fi
  # Write via redirection (NOT cp) so a read-only adopter source file does not
  # propagate its mode to the reused staging path and block the next iteration.
  if [[ -f "$TARGET/$rel" ]]; then cat "$TARGET/$rel" > "$t"; else : > "$t"; fi
  core_file "$ours_commit" "$rel" "$o"

  # Config-shaped `model:` normalization (DEC-006 / AC-5 / F5): on a compiled
  # AGENT.md or SKILL.md the `model:` frontmatter line is config-derived (its
  # source of truth is the adopter's CADENCE_ORG.md#model-tier-mapping,
  # maintained by /cadence-bump-model), NOT hand-authored prose. Line-merging it
  # conflicts on EVERY such artifact when theirs and ours differ. So it is
  # normalized OUT of conflict detection: strip `model:` from all three inputs,
  # merge the rest, then re-insert the adopter's value (theirs' compiled model: =
  # the resolution of their CADENCE_ORG.md; the S-5.4 fallback when the mapping
  # section is absent). BTG-134 widened the scope from roles to roles AND
  # commands: a command may now declare a capability_tier, so a compiled command
  # carries a config-derived model: line for exactly the same reason a role does.
  local kept_model=""
  if [[ "$rel" == *.agents/agents/*/AGENT.md    || "$rel" == .agents/agents/*/AGENT.md || \
        "$rel" == *.agents/skills/*/SKILL.md || "$rel" == .agents/skills/*/SKILL.md ]]; then
    kept_model="$(sed -nE 's/^(model:[[:space:]].*)$/\1/p' "$t" | head -n1)"
    # Fall back to OURS when theirs has none. Theirs still wins when present, so
    # the DEC-006 "the adopter's pin survives" contract is untouched -- but on
    # the upgrade ACROSS the tier boundary (BTG-134) the adopter's compiled
    # command legitimately has NO model: line yet while core's brand-new one
    # does. Reading theirs only would leave kept_model empty, the strip below
    # would delete core's line from ours too, and the re-insertion would be
    # skipped: a CLEAN-SUCCESS report that silently withholds the feature.
    [[ -z "$kept_model" ]] && kept_model="$(sed -nE 's/^(model:[[:space:]].*)$/\1/p' "$o" | head -n1)"
    sed -i '/^model:[[:space:]]/d' "$b" "$t" "$o"
  fi
  # git merge-file -p: exit 0 clean / >0 = conflict-hunk count. The apply gate keys
  # off this EXIT STATUS, never the report text (AC-3 edge). --diff3 -L-labels make
  # the conflicted form reviewable (the human resolves; never auto-resolved).
  if git merge-file -p -L theirs -L base -L "core@$NEW_VERSION" \
       "$t" "$b" "$o" > "$merged" 2>/dev/null; then
    # Re-insert the normalized-out model: just before the closing frontmatter `---`
    # fence (the 2nd `---`). A no-op when kept_model is empty (non-agent files).
    if [[ -n "$kept_model" ]]; then
      awk -v ml="$kept_model" 'BEGIN{c=0}
        /^---$/ { c++; if (c==2) { print ml } }
        { print }' "$merged" > "$merged.m" && mv "$merged.m" "$merged"
    fi
    MERGE_RC=0
  else
    MERGE_RC=1
  fi
}

# Bootstrap branch (AC-8 / DEC-009): a repo with NO stamp keys off the PI-021
# absent-stamp semantics. No CADENCE surface (no CLAUDE.md) => never-adopted =>
# refuse (run /cadence-adopt first). CADENCE surface present => pre-PI-021
# adopter => infer + human-confirm a base, write a bootstrap stamp recording the
# BASE (not the target), then proceed; if no base is inferable, fall to a 2-way
# merge. Returns 0 to signal "handled, proceed normally", 10 "refused/handled,
# stop", non-zero on error. Sets BOOT_BASE_COMMIT when a base was bootstrapped.
# Infer the adopter's base version by matching their installed compiled tree
# against each core release: for each README-versioned core commit, count
# in-scope files byte-identical between the adopter and core@that-commit; the
# best match is the inferred base (best-effort -- DEC-009). Echoes "<ver> <commit>"
# or nothing if no candidate matches confidently (no identical files anywhere).
infer_base_version() {
  local best_ver="" best_commit="" best_score=0 c
  while IFS= read -r c; do
    local ver
    ver="$(git -C "$CORE" show "$c:README.md" 2>/dev/null \
             | sed -nE 's/^\*\*Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' | head -n1)"
    [[ -z "$ver" ]] && continue
    # Count identical files between the adopter and core@c across the compiled
    # tree AND the installed doc paths the footprint enumerates (the installed
    # docs are the discriminating surface when agents are customized).
    local score=0 f rel
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      rel="${f#"$TARGET"/}"
      if git -C "$CORE" cat-file -e "$c:$rel" 2>/dev/null; then
        if diff -q "$f" <(git -C "$CORE" show "$c:$rel" 2>/dev/null) >/dev/null 2>&1; then
          score=$((score + 1))
        fi
      fi
    done < <( {
                # >>> binding-resolution (clause-7 exempt) >>>
                # Claude-coupled runtime-root scan (PI-022, AC-10/DEC-018); the
                # binding-aware base-version scan is deferred to PI-028. Logic
                # UNCHANGED. The ONLY place this script names the bound tree root.
                find "$TARGET/.claude" -type f 2>/dev/null
                # <<< binding-resolution (clause-7 exempt) <<<
                sed -nE 's/^kind=installed[[:space:]]+path=(.*)$/\1/p' "$FOOTPRINT" 2>/dev/null \
                  | while IFS= read -r ip; do [[ -f "$TARGET/$ip" ]] && echo "$TARGET/$ip"; done; } )
    if [[ $score -gt $best_score ]]; then
      best_score=$score; best_ver="$ver"; best_commit="$c"
    fi
  done < <(git -C "$CORE" rev-list --all 2>/dev/null)
  [[ $best_score -gt 0 ]] && echo "$best_ver $best_commit"
}

# Read-only pre-flight (PI-033 / G-9; predicate corrected by PI-038, reversing
# PI-033 DEC-007): classify a COMPILED-ONLY adopter and WARN. Mutates nothing;
# does NOT alter merge control flow; proceeds.
# Compiled-only <=> neutral SOURCE absent: artifacts/roles/ AND artifacts/commands/
# AND CADENCE_ORG.md all missing (AND across the three source anchors -- PI-038
# DEC-002). artifacts/footprint.generated is legitimately present on EVERY adopter
# (adopt-cadence writes it; the engine reads its boundary from it) and is NOT part
# of the discriminator -- keying on the bare artifacts/ dir was the PI-033 defect
# (it is always present post-adoption, so the seam never fired -- PROD_CADENCE-002). Inert
# for full-source AND partial-source adopters: any one source anchor present makes
# the AND false (AC-2/AC-5). Returns 0 always (warn-and-proceed; never refuses).
# The merged CADENCE_DIRECTIVES.md + agents + skills reference neutral-source
# infrastructure a compiled-only adopter lacks (BTG-198: the directives are the
# merged file now -- CLAUDE.md is adopter-owned and excluded from the merge); the warning names the four architectural anchors
# (DEC-008, static list) so the operator can complete the adoption by hand (the
# completion path is deferred -- DEC-001). Spec: specs/PI-038/spec.md (AC-1/AC-5).
warn_if_compiled_only() {
  [[ ! -d "$TARGET/artifacts/roles" && ! -d "$TARGET/artifacts/commands" \
     && ! -f "$TARGET/CADENCE_ORG.md" ]] || return 0
  emit_seam DELTA_AUDIT_GAP upgrade.adopter.compiled_only_infra_absent "$TARGET"
  echo "upgrade-cadence: this target is a COMPILED-ONLY adopter (no artifacts/, no CADENCE_ORG.md)." >&2
  echo "upgrade-cadence: the merged CADENCE_DIRECTIVES.md + agents + skills reference neutral-source infrastructure that is ABSENT here:" >&2
  echo "upgrade-cadence:   - artifacts/roles/" >&2
  echo "upgrade-cadence:   - artifacts/commands/" >&2
  echo "upgrade-cadence:   - ci-templates/scripts/cadence-compile.sh" >&2
  echo "upgrade-cadence:   - CADENCE_ORG.md" >&2
  echo "upgrade-cadence: agents invoked here may be told to edit files that do not exist." >&2
  echo "upgrade-cadence: completing the adoption (installing neutral source + CADENCE_ORG.md) is a separate, deferred step." >&2
  return 0
}

BOOT_BASE_COMMIT=""
BASE_EMPTY=0            # set by the 2-way fallback: merge against an empty base.
# G-2 (DEC-003): the confirmed-base branch resolves + STASHES the base here and
# signals a pending stamp, but does NOT write .cadence-version. main() writes the
# bootstrap stamp ONLY AFTER the footprint precondition check passes -- the stamp
# is a consequence of a proceedable merge, never written on the abort path.
BOOT_PENDING_STAMP=0
BOOT_PENDING_VERSION=""
bootstrap_if_no_stamp() {
  [[ -f "$STAMP" ]] && return 0   # has a stamp -- normal path
  # BTG-198 (AC-7): an EITHER-PATH surface check. A CADENCE surface is present
  # iff the adopter's context file OR the framework-owned directive sidecar is
  # present. The CLAUDE.md arm is RETAINED for backwards compatibility -- the
  # entire pre-PI-021 population is identified by it and has no sidecar -- and
  # the sidecar arm is what makes the documented semantic TRUE rather than merely
  # correct-by-population, now that CLAUDE.md is adopter-owned and an adopter may
  # legitimately have deleted it. Known residual, retained and documented: a
  # never-adopted repo carrying its own CLAUDE.md still passes here and is then
  # halted by the footprint-absent precheck below, which remains the only
  # complete classifier.
  if [[ ! -f "$TARGET/CLAUDE.md" && ! -f "$TARGET/CADENCE_DIRECTIVES.md" ]]; then
    echo "upgrade-cadence: no .cadence-version and no CADENCE surface (CLAUDE.md and CADENCE_DIRECTIVES.md both absent)." >&2
    echo "upgrade-cadence: this is not a CADENCE adopter -- run /cadence-adopt first." >&2
    return 10
  fi
  # AC-1 pre-check (PI-032 / G-1): the footprint descriptor is a HARD precondition
  # for the merge (consumed, never re-derived -- DEC-008/ADR_CADENCE-0009). Surface its
  # absence to the operator BEFORE the confirm-base interaction and BEFORE any
  # stamp write, so a pre-PI-021 adopter never wastes a confirm-base cycle nor
  # ends up with a stamp-without-merge partial state. Placed at the function head
  # so it stands INDEPENDENTLY of PI-031's G-2 stamp-ordering fix (DEC-002).
  if [[ ! -f "$FOOTPRINT" ]]; then
    emit_seam DELTA_AUDIT_GAP upgrade.boundary.descriptor_missing "$FOOTPRINT"
    echo "upgrade-cadence: required footprint descriptor is absent: $FOOTPRINT" >&2
    echo "upgrade-cadence: it is the merge boundary (consumed, never re-derived)." >&2
    echo "upgrade-cadence: generate it first (Step 0), with explicit confirmation -- this derives it atomically (temp-then-move, never a truncating redirect):" >&2
    echo "upgrade-cadence:   AUTOGEN_CONFIRM=1 UPGRADE_TARGET=\"$TARGET\" UPGRADE_CORE=<core> bash <core>/artifacts/commands/cadence-upgrade/upgrade-cadence.sh --autogen-footprint" >&2
    return 10   # handled, stop -- NO stamp written
  fi
  # Pre-PI-021 adopter (surface present, no stamp): infer + human-confirm a base
  # (DEC-009) -- NEVER invent a base silently. The wrapper presents the inferred
  # base to the human and re-invokes with --confirm-base <ver> on confirmation,
  # or --two-way to fall back to a base-less merge (every difference surfaced).
  if [[ "$TWO_WAY" -eq 1 ]]; then
    BASE_EMPTY=1
    echo "upgrade-cadence: no base -- 2-way fallback; every difference is surfaced as a conflict." >&2
    return 0
  fi
  if [[ -z "$CONFIRM_BASE" ]]; then
    local inferred
    inferred="$(infer_base_version)"
    if [[ -n "$inferred" ]]; then
      local iv ic; read -r iv ic <<<"$inferred"
      echo "upgrade-cadence: no .cadence-version stamp; this looks like a pre-PI-021 adopter." >&2
      echo "upgrade-cadence: inferred base version: $iv (from the installed surface)." >&2
      echo "upgrade-cadence: re-run with --confirm-base $iv to confirm and proceed (never applied unconfirmed)." >&2
      return 10
    fi
    # No base inferable -> the 2-way fallback (cycle 21 / S-8.4 / OS-4).
    emit_seam UNSOUND_CONDITION upgrade.bootstrap.base_uninferable "$TARGET"
    echo "upgrade-cadence: no base version could be inferred from the installed surface." >&2
    echo "upgrade-cadence: re-run with --confirm-base <ver> (a 2-way merge surfaces every difference)." >&2
    return 10
  fi
  # Confirmed base -> resolve + STASH the base; signal a pending bootstrap stamp.
  # G-2 (DEC-003): the stamp is NOT written here -- main() writes it ONLY after the
  # footprint precondition check passes, so a footprint-absent abort leaves no
  # stale stamp and a re-run still reaches bootstrap (not skipped as already-stamped).
  local bc
  bc="$(core_commit_for_version "$CONFIRM_BASE")"
  if [[ -z "$bc" ]]; then
    echo "upgrade-cadence: confirmed base $CONFIRM_BASE not found in the core checkout." >&2
    return 1
  fi
  BOOT_BASE_COMMIT="$bc"
  BOOT_PENDING_STAMP=1
  BOOT_PENDING_VERSION="$CONFIRM_BASE"
  return 0
}
