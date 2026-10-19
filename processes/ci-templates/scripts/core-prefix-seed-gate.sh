#!/usr/bin/env bash
#
# core-prefix-seed-gate.sh -- BTG-197 structural gate (AC-3b, DEC-018).
#
# Bounded context: Build tooling / compile-gate flow, and the id-allocation
# surface (`/claire-mint` + the `ticket-index.tsv` reserve ledger, both registered in
# docs/policies/claire-surfaces.md).
#
# Invariant relied on from outside this boundary: the reserve ledger is
# PER-CLONE and UNCOMMITTED -- it lives under `git rev-parse --git-common-dir`,
# is never shipped, and `--seed` refuses a prefix that already has any row. A
# merge therefore CANNOT seed anything; seeding a core prefix is a one-time
# per-clone operator step. That is the gap this gate closes.
#
# WHAT IT CATCHES. A clone whose ledger carries no high-water row for one of
# CLAIRE core's own record prefixes will answer the next `--peek` with
# `<PREFIX>-0001` and mint straight onto an existing record. Nothing downstream
# can detect that: the row it would have to check against is precisely the one
# that is missing. So the seed value has to come from somewhere trustworthy, and
# THAT is what this gate guards.
#
# THE COMPARAND IS THE COMMITTED MANIFEST, NOT THIS CLONE'S LEDGER (DEC-049,
# resolving the DEC-038 halt). This gate used to compare the tree against the
# per-clone `claire-mint` reserve ledger. That ledger lives under
# `git rev-parse --git-common-dir`, is uncommitted and is never shipped -- so a
# fresh clone has none, and the CI manifest of the day CLONED FRESH ON EVERY PUSH.
# BTG-200 AC-4: past tense, because that manifest has been deleted; the DEC-049
# history and its conclusion (the comparand is the committed manifest) are
# untouched, and stand for any substrate. This sentence is maintained IDENTICALLY
# in `core-prefix-seed-manifest.txt`'s header -- one fact in two representations,
# ADR_CLAIRE-0094's subject -- and the two are corrected together or not at all.
# Once Phase 2 gave the core prefixes real records, the row therefore failed
# EVERY CI RUN, permanently, with no operator able to remediate: there is no
# operator, and the next build starts from a fresh clone again. Measured both
# ways and escalated rather than guessed.
#
# So the question moved one step back, from "is THIS CLONE seeded?" -- which is
# unanswerable in CI -- to "is the SEED SOURCE correct?", which is a fact about
# the committed tree and therefore answers identically in CI, in a fresh clone,
# and in a long-lived developer tree. Seeding remains the documented one-time
# per-clone `--seed` step (DEC-018, undisturbed); this gate guarantees the number
# that step is given is right. That is what restores full R-5 coverage rather
# than trading it away, which is why the alternative on the menu -- narrowing the
# gate to clones that already have a ledger -- was rejected: a fresh clone about
# to `--reserve ADR_CLAIRE` IS risk R-5.
#
# It still never scans the tree to INVENT a high-water and carry on -- that would
# contradict the `/claire-mint` contract's own never-scan-fall-back clause
# (CLAIRE_DIRECTIVES.md Behavior 5 -- the framework-owned sidecar, not
# CLAUDE.md, since BTG-198), which is why DEC-018 rejected exactly that as its
# option (c). It reads the tree only to CHECK a committed declaration against it,
# and it refuses rather than substituting when the two disagree.
#
# BEHAVIOR 6 APPLIES TO THE MANIFEST ITSELF. It and the tree are two
# representations of one fact, so a disagreement is a FAILURE in both directions,
# never a warning -- a stale comparand that silently passes is exactly the
# vacuity this gate already suffered once, from the day it shipped until Phase 2
# gave the prefixes records.
#
# SCOPE: CLAIRE CORE TREES ONLY -- and this is ENFORCED, not assumed.
#
# An earlier revision of this gate claimed it was "permanently silent on an
# adopter's tree by construction", reasoning that an adopting repository has no
# CLAIRE-development records so every prefix would measure a tree high-water
# of zero. THAT CLAIM WAS FALSE, and code review cycle 1 disproved it by running
# the shipped gate against a real adopted tree. The measurement:
#
#   - docs/agentic-sdlc/production-insights.md is a plain COPY_PATHS entry in
#     adopt-claire.sh and is copied VERBATIM -- unlike intent-insights.md,
#     which is entry-stripped, and authored-doc-exemptions.txt, which is
#     row-stripped. A freshly adopted tree therefore carries all 21 of core's
#     `### PROD-` entries, high-water PROD_CLAIRE-027.
#   - So once Phase 2 renames those records into the PROD_CLAIRE namespace, an
#     adopter's tree carries PROD_CLAIRE-027, their per-clone ledger has no
#     PROD_CLAIRE row and never will, and their FIRST run-gates.sh failed this
#     row -- instructing them to `--seed` a namespace they do not own.
#   - II_CLAIRE and ADR_CLAIRE were measured too and are NOT affected: the
#     intent-insights strip leaves zero residual citations, and only
#     docs/ADR/TEMPLATE.md is copied, which cites no ADR. PROD_CLAIRE alone
#     carried the hazard -- which is precisely why a by-construction argument
#     over all three prefixes was the wrong shape of reasoning.
#
# DEC-031 rules that the fix is to SCOPE the gate rather than to change the
# adopt path (Phase 1's AC-5 is that the adopter path does not move). Adopters
# never mint core prefixes, so scoping loses no protection that was ever real.
#
# The core marker is `kind=framework_dev` in artifacts/footprint.generated. It
# is not a marker invented here: it is the SAME predicate claire-eject.sh and
# eject-footprint.sh already use to tell a framework-dev tree from an adopter
# one. An adopting repo cannot satisfy it by accident -- adopt-claire.sh
# explicitly does NOT copy core's descriptor and instead GENERATES an adopter
# descriptor, whose emitter produces only kind=installed / kind=seed /
# kind=tree_root rows; the framework_dev emitter is reachable only in a tree
# that carries artifacts/commands/claire-adopt/adopt-claire.sh, the neutral
# compiler source that adoption never ships.
#
# On core's own tree the gate is still quiet throughout Phase 1, which renames
# no record: it starts biting when Phase 2 gives the prefixes real records --
# which is the point at which forgetting to seed becomes able to mint a
# collision.
#
# Exit codes: 0 clean ; 1 on a violation ; 2 on setup failure.
#
# READ-ONLY BY CONSTRUCTION -- it writes no file in the scanned tree and no row
# in the ledger. It reports; the operator runs the remediation.
#
# References: archive/BTG-197/{problem,spec,test-plan,decisions}.md (DEC-018
#             chose this shape; DEC-021 fixes that only the CITATION TOKEN
#             moves, so ADR filenames stay numeric and the token is read from
#             the file's CONTENT, never from its name).

set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "core-prefix-seed-gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  echo "core-prefix-seed-gate: FATAL -- --root is not a directory: $ROOT" >&2
  exit 2
fi

# Scope check, BEFORE anything else is read: if this is not a core tree, the
# gate has no subject at all. It reports that it looked and why it has nothing
# to say -- it does not fall silent unannounced (Behavior 5: report, never
# pretend). See the SCOPE block in this file's header for the measurement that
# made this necessary and for why an adopter cannot trip the marker by accident.
FOOTPRINT="$ROOT/artifacts/footprint.generated"
if [[ ! -f "$FOOTPRINT" ]] || ! grep -qE '^kind=framework_dev ' "$FOOTPRINT"; then
  # BEFORE concluding "not core", ASK A SECOND, INDEPENDENT QUESTION (BTG-197
  # Phase 2, discharging DEC-033's third obligation). The condition above
  # conflates two states that are not alike:
  #   * an ADOPTER's tree, which correctly has no framework_dev row and never
  #     will, and a PRE-PI-021 adopter, who legitimately has no descriptor at
  #     all -- both must pass silently, and both still do;
  #   * a CORE tree whose descriptor is MISSING or was never regenerated -- the
  #     failure case, which this branch used to wave through with an OK.
  #
  # DEC-033 recorded that second case as mitigated only INCIDENTALLY (a core tree
  # with a missing descriptor also fails the sibling `footprint` row in the same
  # run) and warned it becomes a real hazard once the core prefixes have records.
  # Phase 2 gave them records, so it is closed here rather than left as a
  # property that happens to hold.
  #
  # The discriminator is the NEUTRAL SOURCE of the adoption script itself. An
  # adopting repository cannot have it: `artifacts/` is not in COPY_PATHS, and
  # adoption GENERATES an adopter descriptor rather than copying core's. So its
  # presence means "this is a core tree" -- read from a file whose absence in an
  # adopter tree is structural rather than incidental, which is what leaves the
  # pre-PI-021 adopter case untouched.
  CORE_MARKER="$ROOT/artifacts/commands/claire-adopt/adopt-claire.sh"
  if [[ -f "$CORE_MARKER" ]]; then
    emit_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }
    emit_seam IMPOSSIBLE_STATE idalloc.seed.core_scope_undeterminable "$ROOT"
    echo "core-prefix-seed-gate: FATAL -- this IS a CLAIRE core tree, but its footprint" >&2
    echo "       descriptor does not say so, so the gate cannot scope itself." >&2
    echo "       Core marker present: artifacts/commands/claire-adopt/adopt-claire.sh" >&2
    echo "       Descriptor:          artifacts/footprint.generated ($([[ -f "$FOOTPRINT" ]] && echo "no kind=framework_dev row" || echo "absent"))" >&2
    echo "" >&2
    echo "       Refusing to report OK. Concluding 'not core' here would silently disable the" >&2
    echo "       unseeded-prefix check on the one kind of tree it exists for. Regenerate the" >&2
    echo "       descriptor:  bash ci-templates/scripts/claire-eject.sh --derive-footprint" >&2
    exit 2
  fi
  echo "OK: not a CLAIRE core tree (artifacts/footprint.generated carries no kind=framework_dev row,"
  echo "    and this tree carries no CLAIRE core marker); core record prefixes are minted only in"
  echo "    core, so this clone has nothing to seed."
  exit 0
fi

# The allocator, whose --list resolves the ledger. Located rather than assumed,
# and a failure to locate it is a LOUD SETUP FAILURE, never a silent pass: a gate
# that cannot read the ledger has not checked anything, and reporting that as
# clean is the blind spot this whole family of gates exists to remove.
MINT="${CLAIRE_MINT_ID:-}"
if [[ -z "$MINT" ]]; then
  for candidate in \
    "$ROOT/.claude/skills/claire-mint/mint-id.sh" \
    "$ROOT/.opencode/commands/claire-mint/mint-id.sh" \
    "$SELF_DIR/../../.claude/skills/claire-mint/mint-id.sh"
  do
    if [[ -f "$candidate" ]]; then MINT="$candidate"; break; fi
  done
fi
if [[ -z "$MINT" || ! -f "$MINT" ]]; then
  echo "core-prefix-seed-gate: FATAL -- cannot locate mint-id.sh (set CLAIRE_MINT_ID)." >&2
  echo "core-prefix-seed-gate: refusing to report a verdict without reading the ledger." >&2
  exit 2
fi

emit_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }

# THE COMPARAND IS THE COMMITTED MANIFEST (BTG-197 DEC-049, resolving DEC-038).
# The prefix set and each prefix's record location are read from it rather than
# hardcoded here, so there is ONE enumerated source: a second copy in this script
# would be a place for the two to disagree about which prefixes exist, silently.
SEED_MANIFEST="$ROOT/ci-templates/scripts/core-prefix-seed-manifest.txt"

# Highest number the TREE carries for $1, under $2 (0 if the prefix appears
# nowhere, or the path does not exist). Reads the CITATION TOKEN out of file
# CONTENT: DEC-021 keeps ADR filenames numeric, so a filename scan would measure
# the adopter's namespace instead of core's.
#
# Deliberately POSIX/busybox-safe -- the portability floor is Alpine busybox,
# which has neither GNU
# find's -printf nor python3. `grep -oh` + `sort -n` + `tail -1` is the whole
# mechanism.
tree_high_water() {
  local prefix="$1" path="$2" target="$ROOT/$2" hits
  if [[ -d "$target" ]]; then
    hits="$(grep -oh "$prefix-[0-9][0-9]*" "$target"/*.md 2>/dev/null)"
  elif [[ -f "$target" ]]; then
    hits="$(grep -oh "$prefix-[0-9][0-9]*" "$target" 2>/dev/null)"
  else
    echo 0; return 0
  fi
  if [[ -z "$hits" ]]; then echo 0; return 0; fi
  # Strip the prefix, drop leading zeros so `sort -n` compares numbers rather
  # than strings, and take the largest.
  printf '%s\n' "$hits" \
    | sed "s/^$prefix-//" \
    | sed 's/^0*\([0-9]\)/\1/' \
    | sort -n | tail -1
}

# A missing manifest on a CORE tree is a LOUD SETUP FAILURE, never a silent pass.
# The manifest is the comparand; without it the gate has compared nothing, and
# reporting that as clean is the blind spot this whole family of gates removes --
# a blind spot this very gate occupied from the day it shipped until Phase 2 gave
# the core prefixes records.
if [[ ! -f "$SEED_MANIFEST" ]]; then
  emit_seam IMPOSSIBLE_STATE idalloc.seed.manifest_absent "$SEED_MANIFEST"
  echo "core-prefix-seed-gate: FATAL -- the core-prefix seed manifest is absent:" >&2
  echo "       ${SEED_MANIFEST#$ROOT/}" >&2
  echo "       This is a CLAIRE core tree, so it must declare its record high-water marks." >&2
  echo "       Refusing to report a verdict with nothing to compare against." >&2
  exit 2
fi

violations=0
checked=0
declared=""

while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  prefix="$(printf '%s' "$line" | cut -d'|' -f1)"
  manifest_hw="$(printf '%s' "$line" | cut -d'|' -f2)"
  path="$(printf '%s' "$line" | cut -d'|' -f3)"
  if [[ -z "$prefix" || -z "$manifest_hw" || -z "$path" ]]; then
    echo "core-prefix-seed-gate: FATAL -- malformed manifest row: $line" >&2
    exit 2
  fi
  case "$manifest_hw" in
    ''|*[!0-9]*) echo "core-prefix-seed-gate: FATAL -- non-numeric high-water in row: $line" >&2; exit 2 ;;
  esac
  # LEADING ZEROS ARE REFUSED, not normalised away. Bash's arithmetic context
  # reads `074` as OCTAL 60, so a padded value would compare wrong -- quietly, and
  # in the direction that says the manifest is behind when it is not. Refusing is
  # right rather than stripping: a padded value means whoever wrote the row copied
  # a zero-padded ID instead of the number, and that is worth telling them.
  case "$manifest_hw" in
    0) ;;
    0*) echo "core-prefix-seed-gate: FATAL -- zero-padded high-water in row: $line" >&2
        echo "       Write the NUMBER, not the padded id: '${manifest_hw#"${manifest_hw%%[!0]*}"}' not '$manifest_hw'." >&2
        echo "       Bash arithmetic reads a leading zero as octal, so a padded value compares wrong." >&2
        exit 2 ;;
  esac
  declared="$declared $prefix"
  checked=$((checked + 1))

  tree_hw="$(tree_high_water "$prefix" "$path")"

  # BEHAVIOR 6, ENFORCED. The manifest and the tree are two representations of
  # one fact, so they must AGREE -- in both directions, and a disagreement FAILS
  # rather than warning.
  #
  #   manifest BEHIND the tree: a clone seeded from it would seed too low and the
  #     next --reserve collides with an existing record -- the original hazard.
  #   manifest AHEAD of the tree: it claims records that are not there. Left as a
  #     warning it would be the stale-comparand vacuity this ruling exists to
  #     remove, and it also hides a deleted or unmerged record.
  if [[ "$manifest_hw" -ne "$tree_hw" ]]; then
    emit_seam LINEAGE_GAP idalloc.seed.manifest_stale "$prefix"
    echo "core-prefix-seed-gate: ERROR -- the seed manifest disagrees with the tree for $prefix." >&2
    echo "       Manifest declares: $manifest_hw" >&2
    echo "       Tree actually has: $tree_hw   (measured under $path)" >&2
    if [[ "$manifest_hw" -lt "$tree_hw" ]]; then
      echo "       The manifest is BEHIND the tree. A clone seeded from it would seed too low," >&2
      echo "       and the next --reserve would collide with an existing record." >&2
    else
      echo "       The manifest is AHEAD of the tree. It declares records that are not present --" >&2
      echo "       a record was removed, or was never merged." >&2
    fi
    echo "" >&2
    echo "       Fix the manifest in the change that moved the records:" >&2
    echo "         ${SEED_MANIFEST#$ROOT/}   ->   $prefix|$tree_hw|$path" >&2
    echo "" >&2
    echo "       Then seed this clone's ledger, which stays a one-time per-clone step:" >&2
    echo "         bash $MINT --seed $prefix $tree_hw" >&2
    echo "" >&2
    violations=$((violations + 1))
  fi
done < "$SEED_MANIFEST"

# COMPLETENESS. A core prefix whose records exist but whose row was never added
# would otherwise be checked by nothing at all -- the manifest would be silently
# partial, which is the same shape of gap as a stale one. The prefix set is read
# from the manifest, so this is the one check that cannot be.
for probe in ADR_CLAIRE PROD_CLAIRE II_CLAIRE; do
  case " $declared " in *" $probe "*) continue ;; esac
  for loc in docs/ADR docs/agentic-sdlc/production-insights.md docs/agentic-sdlc/intent-insights.md; do
    hw="$(tree_high_water "$probe" "$loc")"
    if [[ "$hw" -gt 0 ]]; then
      emit_seam LINEAGE_GAP idalloc.seed.manifest_incomplete "$probe"
      echo "core-prefix-seed-gate: ERROR -- $probe carries records but the manifest declares no row." >&2
      echo "       Highest found: $probe-$hw, under $loc" >&2
      echo "       Add:  $probe|$hw|$loc" >&2
      echo "" >&2
      violations=$((violations + 1))
      break
    fi
  done
done

if [[ $violations -gt 0 ]]; then
  echo "core-prefix-seed-gate: FAILED -- $violations core prefix(es) whose seed manifest disagrees with the tree." >&2
  exit 1
fi

if [[ $checked -eq 0 ]]; then
  echo "core-prefix-seed-gate: FATAL -- the manifest declares no prefixes." >&2
  echo "       An empty manifest would report clean while checking nothing." >&2
  exit 2
fi
# The count is the anti-vacuity clause: a pass that came from declining to look
# is otherwise indistinguishable from a real one.
echo "OK: the core-prefix seed manifest agrees with the tree ($checked prefix(es) checked)."
exit 0
