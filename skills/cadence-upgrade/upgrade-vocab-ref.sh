#!/usr/bin/env bash
#
# upgrade-vocab-ref.sh -- the BTG-332 DEC-033 reference-document swap (split out
# of upgrade-vocab.sh by code-review cycle 3 B3, which put upgrade-vocab.sh over
# the PI-037 400-line DX ceiling). A colocated sidecar module shipped by the
# PI-023 directory-copy contract.
#
# Bounded context: Upgrade seam / active-spec vocabulary migration. Sourced by
# upgrade-cadence.sh after upgrade-vocab.sh, so vocab_ref_validate_core /
# vocab_ref_classify / vocab_ref_apply / vocab_ref_report_plan are in scope for
# run_rewrite_vocab_mode (upgrade-vocab.sh), which is their only caller. Reads
# TARGET / CORE / emit_seam from that scope at call time, the same dynamic-scope
# contract every sibling upgrade-*.sh relies on.
#
# Upstream: called ONLY from run_rewrite_vocab_mode (--rewrite-vocab), never
#   from the normal versioned-upgrade path (the RECONCILE/REMOVAL_MANIFEST
#   mechanisms handle the reference document there instead -- see D5's own
#   rationale for why this mode exists at all).
# Downstream: writes only docs/agentic-sdlc/chord-reference.md (delivery) and
#   removes only docs/agentic-sdlc/prism-reference.md (retirement) under
#   $TARGET. Never touches .cadence-version.
# Spec: archive/BTG-332/spec.md (D5); decisions.md DEC-033, DEC-036, DEC-041.
#
# Maintainer ruling (DEC-033, cycle-2 Needs Discussion item): the migration
# guide's old Step 1c (a one-time hand cp/rm) is retired -- the same
# stamp-independent command that rewrites specs/ vocabulary now also delivers
# docs/agentic-sdlc/chord-reference.md and retires
# docs/agentic-sdlc/prism-reference.md, with the SAME per-file reporting and the
# SAME fail-loud/all-or-nothing posture as the rest of this stage.
#
# Stamp-independent (D5): there is no base_commit here to reconstruct "the
# stamp-base bytes" the way removals_classify (upgrade-removals.sh) does for a
# normal versioned upgrade -- and DEC-032's own bootstrap analysis is exactly
# why that mechanism can never retire this file anyway (the very first hop's
# stamp lands on a core commit that never shipped prism-reference.md at all, so
# every LATER removals_classify call sees an empty base and no-ops forever,
# unreported -- code-review N3, demonstrated).

PRISM_REF_PATH="docs/agentic-sdlc/prism-reference.md"
CHORD_REF_PATH="docs/agentic-sdlc/chord-reference.md"

# Reset at source time (BTG-333 AC-7): an inherited environment value can
# never enable the test-only seams below -- vocab_test_seams_gate is the
# only writer. Lives here (not upgrade-vocab.sh, which has no DX headroom
# left to spend) but is called from vocab_classify_tree there, the same
# dynamic-scope contract every sidecar in this directory relies on.
VOCAB_TEST_SEAMS_ENABLED=0

# vocab_test_seams_gate -- BTG-333 AC-7: sets VOCAB_TEST_SEAMS_ENABLED=1 iff
# "$CORE/.cadence-upgrade-test-seams" is a regular file AND $CORE and $TARGET
# resolve (pwd -P) to different directories; else 0. When 0, for each of
# UPGRADE_VOCAB_TEST_SHIPPED_SHA256 / UPGRADE_VOCAB_TEST_STALE that is
# non-empty: emit a BOUNDARY_FAULT naming the variable and print one
# non-fatal NOTICE -- the run continues (DEC-003/OQ-2). Called first in
# vocab_classify_tree, before the specs/ existence check, so the gate is
# evaluated once per run regardless of scope.
vocab_test_seams_gate() {
  VOCAB_TEST_SEAMS_ENABLED=0
  local core_abs target_abs
  core_abs="$(cd "$CORE" 2>/dev/null && pwd -P)"
  target_abs="$(cd "$TARGET" 2>/dev/null && pwd -P)"
  if [[ -f "$CORE/.cadence-upgrade-test-seams" && -n "$core_abs" && "$core_abs" != "$target_abs" ]]; then
    VOCAB_TEST_SEAMS_ENABLED=1
  fi
  local var
  for var in UPGRADE_VOCAB_TEST_SHIPPED_SHA256 UPGRADE_VOCAB_TEST_STALE; do
    if [[ "$VOCAB_TEST_SEAMS_ENABLED" -ne 1 && -n "${!var:-}" ]]; then
      emit_seam BOUNDARY_FAULT upgrade.vocab.test_seam_refused "$var"
      echo "upgrade-cadence: NOTICE: $var is a test-only variable and was ignored (the harness-only condition was not met)." >&2
    fi
  done
}

# BTG-332 DEC-036 (maintainer ruling, code-review cycle 3 Needs Discussion
# item): "pristine" for prism-reference.md is a COMMITTED SHIPPED-HASH LIST,
# not $CORE's own git history. The prior git-log-based definition (DEC-035)
# failed closed with a false "adopter-modified" reason against a tarball core
# (no .git at all), a --depth 1/shallow clone (the recording commit
# unreachable), or a CRLF checkout, and counted unreleased branches
# (`log --all`) as "shipped". This list needs NO $CORE git history at all, so
# a tarball, shallow, or CRLF core all resolve identically.
#
# Each entry is the sha256 of the LF-normalized bytes (CRLF -> LF, `sed
# 's/\r$//'`) of one released docs/agentic-sdlc/prism-reference.md version.
# Derived ONCE, at implementation time, against this repo's own tagged release
# history (23 tags, v3.8.1 .. v2026.40.0 -- every tag that ever shipped the
# file), by:
#
#   for t in $(git tag | sort -V); do
#     git cat-file -e "$t:docs/agentic-sdlc/prism-reference.md" 2>/dev/null &&
#       git show "$t:docs/agentic-sdlc/prism-reference.md" | sed 's/\r$//' | sha256sum | awk '{print $1}'
#   done | sort -u
#
# yielding the 7 unique hashes below (23 tags collapse to 7 distinct file
# revisions). The resulting sorted list's own sha256 is
# 82c6ee64ce4f6f18106b5be333588d2ebf4f4743e93ec745f5dbff12ce227299, recorded
# alongside this derivation in decisions.md DEC-038 so both can be
# re-verified independently of this comment. APPEND-ONLY: a future release
# that changes this file's content adds one more line here; existing lines
# are never removed or reordered (an already-shipped hash always stays
# pristine).
VOCAB_REF_SHIPPED_PRISM_SHA256=(
  c92792245f7a36612c9b0298b6edf31a51b235f179704de284372b57f3e4904d
  1508062cc74457c64f848339ad1f37e58499c6865aae03c87225d566b45e3b05
  ebf21c3900936391b5101a366afb5157ffda9665385128e83738d150ee07e1c5
  ed6470e39e0c07fb06ec0eeb02ba560d56932aca446444a8b2568ba3d824dde9
  a9af8e51509e0d3d03daee8dc5d61c9ea09dcb2d946936d96febbb3f94c25d6a
  74605ee0f489de8a8ee7515e66962a80ce884a6f6dec8b8eb3602f69d07cd821
  7c0af5b397ef50fef9a4149f48b79cc349bca836e9567484558018304de02ea3
)

# vocab_ref_pristine <file> -- BTG-333 AC-2: <file> is now an absolute path
# (the classify-time SNAPSHOT, staged below), never a TARGET-relative rel --
# true iff its LF-normalized sha256 is on VOCAB_REF_SHIPPED_PRISM_SHA256
# above (DEC-036), or -- TEST SEAM ONLY, never documented for adopters,
# mirroring the UPGRADE_VOCAB_TEST_STALE precedent (upgrade-vocab.sh) -- one
# of the whitespace-separated hashes in UPGRADE_VOCAB_TEST_SHIPPED_SHA256
# (lets the harness's synthetic fixture content register as "shipped"
# without a real release). False (never a silent true) when the file is
# absent or its hash matches neither.
vocab_ref_pristine() {
  local file="$1" needle h
  [[ -f "$file" ]] || return 1
  needle="$(sed 's/\r$//' "$file" | sha256sum | awk '{print $1}')"
  # BTG-333 AC-7: the test-only hash list joins the loop only when the
  # harness gate is open (vocab_test_seams_gate, called once per run).
  local test_hashes=""
  [[ "${VOCAB_TEST_SEAMS_ENABLED:-0}" -eq 1 ]] && test_hashes="${UPGRADE_VOCAB_TEST_SHIPPED_SHA256:-}"
  for h in "${VOCAB_REF_SHIPPED_PRISM_SHA256[@]}" $test_hashes; do
    [[ "$h" == "$needle" ]] && return 0
  done
  return 1
}

# vocab_ref_validate_core -- code-review cycle 3 B1. Validates $CORE BEFORE any
# reference-swap decision is made, and before vocab_classify_tree runs at all
# (run_rewrite_vocab_mode calls this first): with UPGRADE_CORE unset, running
# the ALREADY-INSTALLED copy in place resolves $CORE to $TARGET itself
# (upgrade-cadence.sh's own fallback: `$SELF_DIR/../../..`, which is the
# adopter's own root when SELF_DIR sits inside the adopter's installed tree).
# Demonstrated failure modes of running this way: (a) chord-reference.md is
# never delivered and prism-reference.md never retired, silently, rc=0; (b)
# under the PRE-DEC-036 git-history "pristine" definition, an adopter's own
# committed prism-reference.md could byte-match ITS OWN history and be
# deleted -- DEC-036 already forecloses (b) unconditionally (the hash list
# never reads $CORE), but (a) is still live and is what this function fixes.
# Fails loud, naming UPGRADE_CORE, and returns 1 (never exits) so the caller
# reports and aborts before any write -- never a partial or silent run.
vocab_ref_validate_core() {
  local core_abs target_abs
  core_abs="$(cd "$CORE" 2>/dev/null && pwd -P)"
  target_abs="$(cd "$TARGET" 2>/dev/null && pwd -P)"
  if [[ -z "$core_abs" ]]; then
    echo "upgrade-cadence: --rewrite-vocab: UPGRADE_CORE (\"$CORE\") does not resolve to a real directory -- set UPGRADE_CORE to a separate, up-to-date CADENCE core checkout before running --rewrite-vocab." >&2
    return 1
  fi
  if [[ -n "$target_abs" && "$core_abs" == "$target_abs" ]]; then
    echo "upgrade-cadence: --rewrite-vocab: CORE resolves to the same directory as TARGET (UPGRADE_CORE is unset, so it defaulted to the installed copy's own tree) -- set UPGRADE_CORE to a separate, up-to-date CADENCE core checkout before running --rewrite-vocab." >&2
    return 1
  fi
  return 0
}

# vocab_ref_classify <staging> -- decides what (if anything) the reference
# swap does this run. Sets VOCAB_REF_DELIVER / VOCAB_REF_RETIRE (0/1),
# VOCAB_REF_RETIRE_BLOCKED (0/1, code-review B1: prism is present and
# eligible for retirement, but nothing retires it this run because no
# chord-reference.md is available anywhere), VOCAB_REF_RETIRE_TRUNCATED (0/1,
# DEC-041: the retirement is of a zero-byte truncation artifact, not a
# byte-for-byte shipped match), VOCAB_REF_CUSTOMIZED (0/1, DEC-036: prism is
# present, non-empty, and NOT on the shipped-hash list) and
# VOCAB_REF_CHORD_UNAVAILABLE (0/1, code-review cycle 5 Blocking 2: chord is
# unavailable anywhere -- neither the adopter nor $CORE has it -- set purely
# from that fact, INDEPENDENTLY of whether prism-reference.md exists at all,
# so an adopter with neither file still gets a NOTICE instead of a silent
# rc=0). Stages the delivered bytes at <staging>/refdeliver.out so
# vocab_ref_apply writes EXACTLY what was classified (mirrors
# vocab_classify_tree's own stage-then-apply contract).
#
# NEITHER reference file's state EVER blocks this run (DEC-036's own
# consequence, "no permanently blocking reference-file state") -- there is
# no VOCAB_REF_CONFLICT array. Every non-delivering/non-retiring outcome is
# reported as a loud, non-fatal NOTICE (vocab_ref_report_plan) instead.
#
#   chord-reference.md: an EXISTING adopter copy, ANY bytes, counts as
#   available and is left untouched -- never a conflict (code-review B2: the
#   old byte-comparison-to-$CORE conflict path made a customized copy block
#   every future --rewrite-vocab forever, so Step 3 (a late-merged branch)
#   could never converge). Only when the adopter has NONE does $CORE's own
#   copy get delivered, if $CORE ships one.
#
#   prism-reference.md: present and PRISTINE (vocab_ref_pristine, DEC-036) ->
#   eligible for retirement. Present, NOT pristine, and ZERO BYTES ->
#   ALSO eligible for retirement (DEC-041, maintainer ruling on DEC-039): the
#   pinned pre-BTG-332 engine's own generic merge truncates this file to
#   empty, rather than deleting it, when an adopter's FIRST hop lands on a
#   core commit that no longer ships it (that old engine has no
#   REMOVAL_MANIFEST row for the path yet -- the row is itself new BTG-332
#   code). An empty file is never a real shipped release (confirmed: none of
#   the 7 hashes in VOCAB_REF_SHIPPED_PRISM_SHA256 is the empty-file hash),
#   so this is judged as the KNOWN truncation artifact, not a customization.
#   EITHER eligible case retires ONLY when chord-reference.md is already
#   present or is being delivered this same run -- never leave an adopter
#   with NEITHER file; if chord is unavailable, VOCAB_REF_RETIRE_BLOCKED is
#   set instead (a loud notice, never silently skipped -- code-review B1,
#   extended by DEC-041 to the truncated case too). Present, NOT pristine,
#   and NON-EMPTY (a genuine adopter customization) -> VOCAB_REF_CUSTOMIZED:
#   left in place, a loud notice naming the file, NEVER deleted and NEVER a
#   reason to block the rest of the run (DEC-036, superseding DEC-035's
#   blocking "conflict" treatment of this same case). Absent -> nothing to
#   retire -- but if chord is ALSO unavailable in this case,
#   VOCAB_REF_CHORD_UNAVAILABLE (set above, unconditionally) still reports it;
#   this branch adds nothing further of its own.
vocab_ref_classify() {
  local staging="$1" chord_available=0
  VOCAB_REF_DELIVER=0
  VOCAB_REF_RETIRE=0
  VOCAB_REF_RETIRE_BLOCKED=0
  VOCAB_REF_RETIRE_TRUNCATED=0
  VOCAB_REF_CUSTOMIZED=0
  VOCAB_REF_CHORD_UNAVAILABLE=0

  if [[ -f "$TARGET/$CHORD_REF_PATH" ]]; then
    chord_available=1
  elif [[ -f "$CORE/$CHORD_REF_PATH" ]]; then
    # BTG-333 AC-3: the classify-time staging copy is checked. On failure,
    # VOCAB_REF_DELIVER is never set (so "delivered" can never be reported
    # for bytes that were never actually staged) and the caller aborts
    # before any write (VOCAB_FATAL, set here -- the same abort path
    # vocab_classify_tree uses).
    if ! vocab_stage_cp "$CORE/$CHORD_REF_PATH" "$staging/refdeliver.out" "$CHORD_REF_PATH"; then
      VOCAB_FATAL=1
      return 1
    fi
    VOCAB_REF_DELIVER=1
    chord_available=1
  fi

  # code-review cycle 5 Blocking 2: computed from chord_available ALONE,
  # before the prism-reference.md presence check below -- the prior code only
  # ever reported chord's unavailability as a SIDE EFFECT of
  # prism-reference.md ALSO being present and eligible for retirement
  # (VOCAB_REF_RETIRE_BLOCKED, below). An adopter with NEITHER file, against a
  # CORE that ships neither either, hit no branch at all: rc=0, no NOTICE,
  # left with neither file (demonstrated). vocab_ref_report_plan reports this
  # independently of whatever the prism-reference.md branch decides.
  if [[ "$chord_available" -eq 0 ]]; then
    VOCAB_REF_CHORD_UNAVAILABLE=1
  fi

  if [[ -f "$TARGET/$PRISM_REF_PATH" ]]; then
    # BTG-333 AC-2: snapshot the retired reference file BEFORE judging it
    # (the same snapshot-first pattern AC-1 applies to specs) -- both the
    # pristine test and the zero-byte (DEC-041 truncation) test below run
    # on the SNAPSHOT, never the live file, so a write landing after this
    # point is what vocab_ref_apply's re-check catches, not silently
    # re-judged here.
    if ! vocab_stage_cp "$TARGET/$PRISM_REF_PATH" "$staging/refretire.orig" "$PRISM_REF_PATH"; then
      VOCAB_FATAL=1
      return 1
    fi
    if vocab_ref_pristine "$staging/refretire.orig"; then
      if [[ "$chord_available" -eq 1 ]]; then
        VOCAB_REF_RETIRE=1
      else
        VOCAB_REF_RETIRE_BLOCKED=1
      fi
    elif [[ ! -s "$staging/refretire.orig" ]]; then
      if [[ "$chord_available" -eq 1 ]]; then
        VOCAB_REF_RETIRE=1
        VOCAB_REF_RETIRE_TRUNCATED=1
      else
        VOCAB_REF_RETIRE_BLOCKED=1
      fi
    else
      VOCAB_REF_CUSTOMIZED=1
    fi
  fi
}

# vocab_ref_report_plan -- the reference-swap analog of vocab_report_plan,
# same "upgrade-cadence:" prefix grammar the rest of this stage uses. Every
# NOTICE line (code-review B1, DEC-036, and cycle 5 Blocking 2) is the "never
# silent" fix for a non-delivering/non-retiring outcome: previously each
# produced no output at all -- the file just silently stayed in place (or,
# under DEC-035, was sometimes wrongly deleted), with nothing printed to
# explain why. Sent to stderr (a notice, not a report-of-what-was-written),
# and NEVER blocks the run by itself. The retirement report line names the
# truncation case explicitly (DEC-041) so an operator can tell, from the
# log alone, which of the two eligible reasons actually applied.
vocab_ref_report_plan() {
  [[ "${VOCAB_REF_DELIVER:-0}" -eq 1 ]] && echo "upgrade-cadence: vocab reference delivered: $CHORD_REF_PATH"
  if [[ "${VOCAB_REF_RETIRE:-0}" -eq 1 ]]; then
    if [[ "${VOCAB_REF_RETIRE_TRUNCATED:-0}" -eq 1 ]]; then
      echo "upgrade-cadence: vocab reference retired: $PRISM_REF_PATH (zero bytes -- recognized as a retirement-eligible truncation artifact, DEC-041)"
    else
      echo "upgrade-cadence: vocab reference retired: $PRISM_REF_PATH"
    fi
  fi
  if [[ "${VOCAB_REF_RETIRE_BLOCKED:-0}" -eq 1 ]]; then
    echo "upgrade-cadence: NOTICE: $PRISM_REF_PATH is present and eligible for retirement but was NOT retired -- $CHORD_REF_PATH is unavailable (neither the adopter nor \$CORE has it). Point UPGRADE_CORE at a core checkout that ships $CHORD_REF_PATH and re-run --rewrite-vocab." >&2
  elif [[ "${VOCAB_REF_CHORD_UNAVAILABLE:-0}" -eq 1 ]]; then
    # code-review cycle 5 Blocking 2: VOCAB_REF_RETIRE_BLOCKED's own notice
    # (above) already names $CHORD_REF_PATH and UPGRADE_CORE whenever
    # prism-reference.md was ALSO present and eligible, so this `elif` only
    # fires for every OTHER chord-unavailable outcome -- most notably, no
    # prism-reference.md at all -- which previously reported nothing.
    echo "upgrade-cadence: NOTICE: $CHORD_REF_PATH is unavailable (neither the adopter nor \$CORE has it) -- no reference file was delivered. Point UPGRADE_CORE at a core checkout that ships $CHORD_REF_PATH and re-run --rewrite-vocab." >&2
  fi
  if [[ "${VOCAB_REF_CUSTOMIZED:-0}" -eq 1 ]]; then
    echo "upgrade-cadence: NOTICE: $PRISM_REF_PATH is customized (its bytes are not on the shipped-hash list, DEC-036) -- left in place, never deleted." >&2
  fi
}

# vocab_ref_report_written -- BTG-333 AC-6: one "vocab reference delivered:
# <path>" line (grammar identical to vocab_ref_report_plan) per entry of
# VOCAB_REF_WRITTEN, so a write already on disk is always reported even when
# a LATER step in this same apply fails or refuses.
vocab_ref_report_written() {
  local p
  for p in "${VOCAB_REF_WRITTEN[@]:-}"; do
    [[ "$p" == "$CHORD_REF_PATH" ]] && echo "upgrade-cadence: vocab reference delivered: $CHORD_REF_PATH"
  done
}

# vocab_ref_apply <staging> -- writes the classified reference-swap plan.
# Reports each write as it happens (VOCAB_REF_WRITTEN) so a mid-way failure
# never claims less was applied than actually was -- the same fail-loud
# posture as vocab_apply (N5), scoped here to the two reference paths.
vocab_ref_apply() {
  local staging="$1"
  VOCAB_REF_WRITTEN=()
  if [[ "${VOCAB_REF_DELIVER:-0}" -eq 1 ]]; then
    if ! mkdir -p "$(dirname "$TARGET/$CHORD_REF_PATH")" 2>/dev/null \
       || ! cp "$staging/refdeliver.out" "$TARGET/$CHORD_REF_PATH" 2>/dev/null; then
      emit_seam DELTA_AUDIT_GAP upgrade.apply.partial_or_dirty "$CHORD_REF_PATH"
      echo "upgrade-cadence: apply failed writing $CHORD_REF_PATH -- aborting." >&2
      return 1
    fi
    VOCAB_REF_WRITTEN+=("$CHORD_REF_PATH")
  fi
  if [[ "${VOCAB_REF_RETIRE:-0}" -eq 1 ]]; then
    # BTG-333 AC-2: re-check the LIVE bytes against the classify-time
    # snapshot before removing -- the same re-check pattern CP-05 already
    # applies to spec files (AC-1). A mismatch, or the file having vanished
    # since classification, means it is kept: never delete on the strength
    # of a stale observation. Any write already landed (the chord delivery
    # above) is still reported.
    if ! cmp -s "$TARGET/$PRISM_REF_PATH" "$staging/refretire.orig" 2>/dev/null; then
      emit_seam UNSOUND_CONDITION upgrade.vocab.stale_input "$PRISM_REF_PATH"
      vocab_ref_report_written
      echo "upgrade-cadence: $PRISM_REF_PATH changed since classification -- kept, not retired." >&2
      return 1
    fi
    if ! rm -f "$TARGET/$PRISM_REF_PATH" 2>/dev/null; then
      emit_seam DELTA_AUDIT_GAP upgrade.apply.partial_or_dirty "$PRISM_REF_PATH"
      vocab_ref_report_written
      echo "upgrade-cadence: apply failed removing $PRISM_REF_PATH -- aborting." >&2
      return 1
    fi
  fi
  return 0
}
