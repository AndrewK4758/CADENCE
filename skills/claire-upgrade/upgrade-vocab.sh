#!/usr/bin/env bash
#
# upgrade-vocab.sh -- the BTG-332 tree-level vocab migration stage (spec.md D4).
# A colocated sidecar module shipped by the PI-023 directory-copy contract.
#
# Bounded context: Upgrade seam / active-spec vocabulary migration. Sourced by
# upgrade-claire.sh after upgrade-vocab-rules.sh, so vocab_classify_file and the
# TARGET / emit_seam / staging / conflicted / DRY_RUN globals resolve at call
# time (the same dynamic-scope contract every sibling upgrade-*.sh relies on).
#
# Upstream: vocab_classify_tree is called from main() after the framework merge
#   loop and BEFORE the dry-run return (so --dry-run previews the vocab plan);
#   vocab_apply is called from run_apply_transaction after the in-scope write
#   loop; run_rewrite_vocab_mode is a separate, stamp-independent entry point
#   dispatched by --rewrite-vocab, before the NEW_VERSION check.
# Downstream: writes only files vocab_classify_tree found rewritable, inside
#   $TARGET/specs/<id>/**. Never reads or writes .claire-version.
# Spec: archive/BTG-332/spec.md (D4, D5); decisions.md DEC-013.

declare -A VOCAB_LINES_BY_FILE=()
declare -A VOCAB_AMBIG_BY_FILE=()

# vocab_stage_cp <src> <dst> <subject> -- BTG-333 AC-3/AC-8: a checked cp,
# the one spelling every staging copy here and in upgrade-vocab-ref.sh uses.
# On failure: emit staging_failed naming <subject>, abort, return 1.
vocab_stage_cp() {
  local src="$1" dst="$2" subject="$3"
  if ! cp "$src" "$dst" 2>/dev/null; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.staging_failed "$subject"
    echo "upgrade-claire: could not stage $subject to $dst -- aborting before any write." >&2
    return 1
  fi
  return 0
}

# vocab_classify_tree <staging> -- scans $TARGET/specs/<id>/**/*.{md,yaml},
# excluding TEMPLATE/, drafts/, CLAIRE.md, and any ticket named in
# UPGRADE_VOCAB_EXCLUDE (space-separated). Sets VOCAB_REWRITE[], VOCAB_CONFLICT[],
# VOCAB_RETAINED_LINES, VOCAB_RETAINED_FILES, and the two associative arrays
# above. Writes staged copies under <staging>/vocab.{out,orig,residual}.<munged>
# and, for a conflicted file, <staging>/conflict.<munged> -- the SAME naming
# convention the framework-file conflict path already stages and restores from,
# so no change was needed to the generic staging loop in upgrade-claire.sh.
# BTG-334 AC-4: vocab_mark_residual (upgrade-vocab-rules.sh, see its header) is the marking authority for "was the rewrite finished".
vocab_classify_tree() {
  local staging="$1"
  VOCAB_REWRITE=(); VOCAB_CONFLICT=(); VOCAB_RETAINED_LINES=0; VOCAB_RETAINED_FILES=0
  VOCAB_LINES_BY_FILE=(); VOCAB_AMBIG_BY_FILE=()
  VOCAB_FATAL=0
  # BTG-333 AC-7: before the specs/ existence check, so a refused variable
  # is reported even with nothing to classify.
  vocab_test_seams_gate
  [[ -d "$TARGET/specs" ]] || return 0
  local exclude_list=" ${UPGRADE_VOCAB_EXCLUDE:-} "
  local abs rel ticketrel ticket specrel munged basef
  while IFS= read -r -d '' abs; do
    rel="${abs#"$TARGET"/}"
    case "$rel" in
      specs/TEMPLATE/*|specs/drafts/*|specs/CLAIRE.md) continue ;;
    esac
    [[ -L "$abs" ]] && continue
    ticketrel="${rel#specs/}"
    # BTG-333 AC-4: a file directly under specs/ has no "/" in ticketrel and
    # is skipped silently (A-8), never rewritten and never reported.
    [[ "$ticketrel" == */* ]] || continue
    ticket="${ticketrel%%/*}"
    [[ "$exclude_list" == *" $ticket "* ]] && continue
    specrel="${ticketrel#*/}"
    munged="$(echo "$rel" | tr '/' '_')"

    # BTG-333 AC-1: snapshot taken FIRST, never late (a late one lets a
    # concurrent write land inside it, so the later re-check silently
    # passes). Classification and the frozen-file check below both read
    # this snapshot, never $abs again.
    if ! vocab_stage_cp "$abs" "$staging/vocab.orig.$munged" "$rel"; then
      VOCAB_FATAL=1
      return 1
    fi

    # A classify_engine_failed return (code-review B3) is fatal exactly like
    # the frozen_line_changed check below: the seam is already emitted by
    # vocab_classify_file itself, so this aborts before any write and before
    # the stamp is touched, rather than silently treating the failure as "0
    # rewritten, 0 ambiguous" and proceeding as if the file were clean.
    if ! vocab_classify_file "$staging/vocab.orig.$munged" "$staging/vocab.out.$munged" "$specrel"; then
      echo "upgrade-claire: vocab classification failed on $rel -- aborting before any write." >&2
      VOCAB_FATAL=1
      return 1
    fi
    local rewritten="$VOCAB_REWRITTEN" retained="$VOCAB_RETAINED" ambiguous="$VOCAB_AMBIGUOUS"
    local detail=("${VOCAB_AMBIGUOUS_DETAIL[@]:-}")

    # OS-4.1: an INDEPENDENT re-check of the file-level V0 frozen classes,
    # reasoned here from the path alone rather than trusting the rules
    # module's own V0 logic -- defense in depth against a classifier defect
    # (or a future edit) silently rewriting a decision log or an elicited
    # quote. Region- and specific-line-shape V0 classes are the rules
    # module's sole responsibility (not independently re-derivable from the
    # path alone); this catches the file-level classes, which are.
    basef="$(basename "$specrel")"
    if { [[ "$basef" == "decisions.md" || "$basef" == "submission.md" || "$basef" == "summary.md" || "$basef" == "design-options.md" ]] \
         || [[ "$specrel" == attachments/* ]]; } \
       && ! cmp -s "$staging/vocab.orig.$munged" "$staging/vocab.out.$munged"; then
      emit_seam IMPOSSIBLE_STATE upgrade.vocab.frozen_line_changed "$rel"
      echo "upgrade-claire: vocab classification altered a frozen file ($rel) -- aborting before any write." >&2
      VOCAB_FATAL=1
      return 1
    fi

    VOCAB_RETAINED_LINES=$((VOCAB_RETAINED_LINES + retained))
    [[ "$retained" -gt 0 ]] && VOCAB_RETAINED_FILES=$((VOCAB_RETAINED_FILES + 1))

    if [[ "$ambiguous" -gt 0 || "$rewritten" -gt 0 ]]; then
      local d ambig_lines=""
      for d in "${detail[@]}"; do [[ -n "$d" ]] && ambig_lines+="${d%%$'\t'*},"; done
      ambig_lines="${ambig_lines%,}"

      # BTG-334 AC-4: vocab_mark_residual (header, upgrade-vocab-rules.sh), on the BTG-333 snapshot (DEC-012 rule 1); fatal here like the first call above (code-review B3).
      if ! vocab_mark_residual "$staging/vocab.orig.$munged" "$staging/vocab.out.$munged" "$specrel" "$ambig_lines" \
          "$staging/vocab.residual.$munged" "$staging/conflict.$munged" "$rel"; then
        echo "upgrade-claire: vocab residual check failed on $rel -- aborting before any write." >&2
        VOCAB_FATAL=1
        return 1
      fi

      if [[ -n "${VOCAB_RESIDUAL_LINES:-}" ]]; then
        emit_seam SEAM_VIOLATION upgrade.vocab.residual_after_rewrite "$rel"
        VOCAB_CONFLICT+=("$rel")
        # DEC-012: vocab_mark_residual already staged $conflict itself (DEC-017) -- no second cp here (would reintroduce c3-5).
        VOCAB_AMBIG_BY_FILE["$rel"]="$VOCAB_MARKED_LINES"
      elif [[ "$ambiguous" -gt 0 ]]; then
        # Unchanged (S-4.8): no leftover -- stage vocab.out itself, checked (DEC-012 rule 2).
        VOCAB_CONFLICT+=("$rel")
        if ! vocab_stage_cp "$staging/vocab.out.$munged" "$staging/conflict.$munged" "$rel"; then
          VOCAB_FATAL=1
          return 1
        fi
        VOCAB_AMBIG_BY_FILE["$rel"]="$ambig_lines"
      else
        VOCAB_REWRITE+=("$rel")
        # BTG-333 AC-1: the snapshot was already taken above, first -- no
        # late re-copy of $abs here (that was the check-then-write gap).
        VOCAB_LINES_BY_FILE["$rel"]="$rewritten"
      fi
    fi
  # Sorted (never bare readdir order, which is filesystem-dependent and not
  # alphabetical): a partial-failure report (code-review B5) must name exactly
  # which files were "already written" before file k failed, and that
  # sentence is only meaningful if the processing order is deterministic and
  # reproducible across runs and machines.
  done < <(find "$TARGET/specs" -type f \( -name '*.md' -o -name '*.yaml' \) -print0 2>/dev/null | sort -z)
}

# vocab_report <rel> <n> -- one spelling of the report-line grammar (C-1), used
# by both the real apply and the dry-run / --rewrite-vocab preview paths.
vocab_report() { echo "upgrade-claire: vocab rewrite: $1 ($2 line(s))"; }

# vocab_report_plan -- prints every VOCAB_REWRITE report line plus the retained
# summary, from already-computed state. Called for real only after a fully
# successful vocab_apply (never on a partial failure -- OS-4.3), and separately
# for the dry-run / --rewrite-vocab preview (which never writes).
vocab_report_plan() {
  local rel
  for rel in "${VOCAB_REWRITE[@]:-}"; do
    [[ -n "$rel" ]] || continue
    vocab_report "$rel" "${VOCAB_LINES_BY_FILE[$rel]:-0}"
  done
  if [[ "${VOCAB_RETAINED_FILES:-0}" -gt 0 ]]; then
    echo "upgrade-claire: vocab retained (historical): ${VOCAB_RETAINED_LINES} line(s) across ${VOCAB_RETAINED_FILES} file(s)."
  fi
}

# vocab_apply_report_written -- prints a "vocab rewrite:" report line (the
# same grammar vocab_report_plan uses) for every file in VOCAB_WRITTEN so far.
# Called on a partial-failure abort below (code-review B5 / JI-3): a spec
# file that was actually written to $TARGET is a real, observable edit, and
# the Elicited Intent audit answer ("every adopter spec rewrite is reported
# per file in the upgrade output ... an unreported edit ... would be a
# violation") makes an unreported one a violation regardless of whether the
# REST of the run went on to fail.
vocab_apply_report_written() {
  local rel
  for rel in "${VOCAB_WRITTEN[@]:-}"; do
    [[ -n "$rel" ]] || continue
    vocab_report "$rel" "${VOCAB_LINES_BY_FILE[$rel]:-0}"
  done
}

# vocab_apply_abort_note -- one spelling of the "how many were written" clause
# for both vocab_apply abort branches below. Never claims "nothing written"
# when EITHER write set is non-empty:
#   - VOCAB_WRITTEN: spec files this SAME vocab_apply loop already wrote
#     before the file that failed (code-review cycle 1 B5 / JI-3).
#   - VOCAB_FRAMEWORK_WRITTEN_COUNT: framework files upgrade-apply.sh's
#     IN_SCOPE loop already wrote to $TARGET earlier in this SAME run, BEFORE
#     vocab_apply was ever called (code-review cycle 2 N5, demonstrated:
#     a spec write failure reported "nothing written" while
#     docs/agentic-sdlc/scout-reference.md sat on disk, already applied).
#     Set by the caller: run_apply_transaction (upgrade-apply.sh) sets it to
#     the count of files its own loop just wrote; run_rewrite_vocab_mode
#     (stamp-independent -- no framework files are ever touched there) sets
#     it to 0.
vocab_apply_abort_note() {
  local fw="${VOCAB_FRAMEWORK_WRITTEN_COUNT:-0}" vw="${#VOCAB_WRITTEN[@]}"
  if [[ "$vw" -gt 0 && "$fw" -gt 0 ]]; then
    echo "aborting; $vw spec file(s) already written (reported above), plus $fw framework file(s) already written earlier in this same run."
  elif [[ "$vw" -gt 0 ]]; then
    echo "aborting; $vw file(s) already written (reported above)."
  elif [[ "$fw" -gt 0 ]]; then
    echo "aborting; $fw framework file(s) already written earlier in this same run (no spec file was written)."
  else
    echo "aborting; nothing written."
  fi
}

# vocab_apply -- writes every VOCAB_REWRITE file. Re-verifies each file's bytes
# against the classify-time snapshot first (a mismatch is upgrade.vocab.stale_input,
# CP-05); a write failure is upgrade.apply.partial_or_dirty (CP-04/CP-09), the
# same reused event the framework-file write loop emits. Never touches the stamp.
# On ANY abort, every file already in VOCAB_WRITTEN is reported first (above)
# and the abort message names how many were written via vocab_apply_abort_note
# -- never an unconditional "nothing written" when files 1..k-1 of THIS loop,
# or the framework-file loop that ran before this one, already landed on disk
# (code-review B5 / N5).
vocab_apply() {
  VOCAB_WRITTEN=()
  local rel munged
  for rel in "${VOCAB_REWRITE[@]:-}"; do
    [[ -n "$rel" ]] || continue
    munged="$(echo "$rel" | tr '/' '_')"
    # TEST SEAM ONLY (S-2.7 / CP-05), never documented for adopters, mirroring
    # the UPGRADE_VOCAB_EXCLUDE precedent: UPGRADE_VOCAB_TEST_STALE="<rel>:<text>"
    # simulates a hook writing to the file between classification and apply, by
    # performing that write immediately before the cmp check below would run.
    # BTG-333 AC-7: additionally requires the harness gate to be open.
    if [[ "${VOCAB_TEST_SEAMS_ENABLED:-0}" -eq 1 && -n "${UPGRADE_VOCAB_TEST_STALE:-}" && "${UPGRADE_VOCAB_TEST_STALE%%:*}" == "$rel" ]]; then
      printf '%s\n' "${UPGRADE_VOCAB_TEST_STALE#*:}" > "$TARGET/$rel"
      UPGRADE_VOCAB_TEST_STALE=""
    fi
    if ! cmp -s "$TARGET/$rel" "$staging/vocab.orig.$munged"; then
      emit_seam IMPOSSIBLE_STATE upgrade.vocab.stale_input "$rel"
      vocab_apply_report_written
      echo "upgrade-claire: $rel changed between vocab classification and apply -- $(vocab_apply_abort_note)" >&2
      return 1
    fi
    if ! cp "$staging/vocab.out.$munged" "$TARGET/$rel" 2>/dev/null; then
      emit_seam LINEAGE_GAP upgrade.apply.partial_or_dirty "$rel"
      vocab_apply_report_written
      echo "upgrade-claire: apply failed writing $rel -- $(vocab_apply_abort_note)" >&2
      return 1
    fi
    VOCAB_WRITTEN+=("$rel")
  done
  # OS-4.3: the written set must equal the reported set exactly -- vocab_report_plan
  # (called by the caller right after a successful return) reports precisely
  # VOCAB_REWRITE, so this can only diverge from VOCAB_WRITTEN if a future edit
  # breaks that invariant. Checked anyway (defense in depth, never trusted-by-
  # construction alone): a sorted-count comparison is sufficient since both
  # arrays are built from the same VOCAB_REWRITE traversal with no reordering.
  if [[ "${#VOCAB_WRITTEN[@]}" -ne "${#VOCAB_REWRITE[@]}" ]]; then
    emit_seam LINEAGE_GAP upgrade.vocab.unreported_write "${#VOCAB_WRITTEN[@]} of ${#VOCAB_REWRITE[@]}"
    return 1
  fi
  return 0
}

# --- BTG-332 DEC-033/DEC-036: the reference-document swap -------------------
# Split into upgrade-vocab-ref.sh (code-review cycle 3 B3: this file was over
# the PI-037 400-line ceiling). vocab_ref_validate_core / vocab_ref_classify /
# vocab_ref_apply / vocab_ref_report_plan are sourced from there by
# upgrade-claire.sh and are in scope here at call time, the same dynamic-scope
# contract every sidecar in this directory relies on.

# run_rewrite_vocab_mode -- the D5 stamp-independent entry point for
# `--rewrite-vocab`. All-or-nothing for SPEC vocabulary conflicts: any
# ambiguous line stages every conflicted file and writes nothing else. The
# DEC-033/DEC-036 reference-swap NEVER blocks the run (DEC-036's own
# consequence: "--rewrite-vocab therefore has no permanently blocking
# reference-file state") -- a customized prism-reference.md, or an
# unavailable scout-reference.md, is reported as a loud notice instead (see
# vocab_ref_report_plan, upgrade-vocab-ref.sh) and everything else still
# applies. Honors --dry-run.
run_rewrite_vocab_mode() {
  # DEC-053 pre-merge fix-up (held candidate c1-4): a staging tree already
  # present when THIS run starts means Step 1a (or an earlier --rewrite-vocab)
  # left an unresolved conflict there -- most notably an org-fold
  # CLAIRE_ORG.md conflict. Refuse to start, and never touch it, rather than
  # the spec-vocabulary-conflict path below unconditionally `rm -rf`-ing it
  # later in this same run regardless of whether it predates this run or was
  # just created by it. Checked first, before $CORE validation or any
  # classification, so this can never race a write.
  if [[ -e "$TARGET/.claire-upgrade-staging" ]]; then
    echo "upgrade-claire: $TARGET/.claire-upgrade-staging already exists -- resolve or remove it before running --rewrite-vocab (see docs/migrations/prism-to-scout.md Step 1b); nothing was written." >&2
    return 1
  fi

  # code-review cycle 3 B1: validate $CORE FIRST, before any spec is
  # classified and before any reference-swap decision is made -- CORE
  # resolving to TARGET itself (UPGRADE_CORE unset, running the installed
  # copy in place) is caught here and aborts the ENTIRE run, loud and named,
  # rather than silently classifying specs while the reference swap quietly
  # does nothing.
  vocab_ref_validate_core || return 1

  # BTG-333 AC-8: mktemp -d's result is verified BEFORE use, under its own
  # name ("mktemp"), not misattributed to the first file processed.
  local staging; staging="$(mktemp -d)"
  local mktemp_rc=$?
  if [[ "$mktemp_rc" -ne 0 || -z "$staging" || "$staging" != /* || ! -d "$staging" ]]; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.staging_failed "mktemp"
    echo "upgrade-claire: mktemp -d returned an unusable staging path: '${staging:-<empty>}' -- aborting before any write." >&2
    return 1
  fi
  # Stamp-independent: no framework file is ever touched here, so
  # vocab_apply_abort_note's "already written" clause is scoped to
  # VOCAB_WRITTEN alone in this mode (code-review cycle 2 N5).
  VOCAB_FRAMEWORK_WRITTEN_COUNT=0
  vocab_classify_tree "$staging"
  if [[ "${VOCAB_FATAL:-0}" -eq 1 ]]; then
    rm -rf "$staging"
    return 1
  fi
  # BTG-333 AC-3/A-3: same VOCAB_FATAL check as above -- a scout staging
  # failure aborts here (an engine I/O fault, not reference-file content;
  # DEC-036's "never blocks" does not cover this).
  VOCAB_FATAL=0
  vocab_ref_classify "$staging"
  if [[ "${VOCAB_FATAL:-0}" -eq 1 ]]; then
    rm -rf "$staging"
    return 1
  fi

  # code-review cycle 3 DEC-036: the reference-swap (scout/prism) NEVER
  # contributes to this conflict set -- an existing scout-reference.md is
  # always "available" (B2) and a customized prism-reference.md is a loud
  # notice, never a conflict (DEC-036's shipped-hash-list ruling; see
  # vocab_ref_report_plan). Only SPEC vocabulary conflicts (ambiguous lines)
  # remain all-or-nothing here.
  local all_conflicts=() _c
  for _c in "${VOCAB_CONFLICT[@]:-}"; do
    [[ -n "$_c" ]] && all_conflicts+=("$_c")
  done

  if [[ "${#all_conflicts[@]}" -gt 0 ]]; then
    assert_not_dry_run rewrite-vocab-stage || { rm -rf "$staging"; return 1; }
    local stage_root="$TARGET/.claire-upgrade-staging" rel munged ln linelist
    rm -rf "$stage_root"
    for rel in "${VOCAB_CONFLICT[@]:-}"; do
      [[ -n "$rel" ]] || continue
      munged="$(echo "$rel" | tr '/' '_')"
      # BTG-333 AC-8/A-5: mkdir and the conflict-form copy are both checked.
      # On failure $stage_root is left AS IS (never rm -rf'd) with a loud
      # "incomplete" message; only the internal $staging dir is cleaned.
      if ! mkdir -p "$stage_root/$(dirname "$rel")" 2>/dev/null; then
        emit_seam IMPOSSIBLE_STATE upgrade.vocab.staging_failed "$rel"
        echo "upgrade-claire: could not create $stage_root/$(dirname "$rel") -- aborting." >&2
        echo "upgrade-claire: $stage_root is incomplete -- remove it before re-running --rewrite-vocab." >&2
        rm -rf "$staging"
        return 1
      fi
      if ! vocab_stage_cp "$staging/conflict.$munged" "$stage_root/$rel" "$rel"; then
        echo "upgrade-claire: $stage_root is incomplete -- remove it before re-running --rewrite-vocab." >&2
        rm -rf "$staging"
        return 1
      fi
      linelist="${VOCAB_AMBIG_BY_FILE[$rel]:-}"
      IFS=',' read -ra _lns <<< "$linelist"
      for ln in "${_lns[@]:-}"; do [[ -n "$ln" ]] && echo "vocab-conflict: $rel:$ln" >&2; done
    done
    echo "upgrade-claire: ${#all_conflicts[@]} conflicting file(s) -- NOT applied (--rewrite-vocab is stamp-independent; nothing else was written):" >&2
    printf '  conflict: %s\n' "${all_conflicts[@]}" >&2
    rm -rf "$staging"
    return 1
  fi

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    vocab_report_plan
    vocab_ref_report_plan
    echo "upgrade-claire: [dry-run] nothing was written."
    rm -rf "$staging"
    return 0
  fi

  if ! vocab_apply; then rm -rf "$staging"; return 1; fi
  if ! vocab_ref_apply "$staging"; then
    # The specs loop above already fully succeeded (vocab_apply returned 0
    # without reporting) -- report those now so a reference-swap failure can
    # never hide an already-written spec rewrite (N5 posture, generalized).
    vocab_report_plan
    rm -rf "$staging"
    return 1
  fi
  vocab_report_plan
  vocab_ref_report_plan
  rm -rf "$staging"
  return 0
}
