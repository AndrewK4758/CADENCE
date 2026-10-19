#!/usr/bin/env bash
#
# upgrade-vocab-rules.sh -- the BTG-332 PRISM-to-SCOUT classifier (spec.md D3).
# A colocated sidecar module shipped by the PI-023 directory-copy contract and
# sourced both by upgrade-claire.sh/upgrade-vocab.sh (the upgrade seam) and by
# ci-templates/scripts/scout-residue-gate.sh, so the two share one definition of
# "historical" (spec.md D9). Never sourced by an adopter's own tooling directly.
#
# Bounded context: Upgrade seam / active-spec vocabulary migration (BTG-332).
# Upstream: called per-file by vocab_classify_tree (upgrade-vocab.sh) and by the
#   residue gate, both of which supply the file's bytes and its path relative to
#   a ticket directory (e.g. "decisions.md", "attachments/draft.md", "spec.md").
# Downstream: writes a rewritten copy (never the input in place) and reports
#   per-line counts on stderr in a fixed VOCAB_STATS/VOCAB_AMBIGUOUS grammar that
#   both callers parse. Spec: archive/BTG-332/spec.md (Proposed Design D1, D3).
#
# Rule precedence (first match wins), per spec.md D3's table: V0 frozen classes
# are checked before any rewrite is considered; V1 headings; V5 legacy Zachman
# mislabel; V6 metadata template comments; V7 the reference path; V4 exact
# historical template lines; V3 dimension-table columns (tracked across lines);
# V8 acronym-only; V9 ambiguous. V2 (table header cells "PRISM Dimension" /
# "PRISM Source") needs no separate code: neither "Dimension" nor "Source" is one
# of the five mapped dimension words, so V8's generic acronym-only swap already
# produces the correct result for those header cells (documented judgment call,
# archive/BTG-332/decisions.md DEC-013).

# The one map (spec.md D1). Index-paired; never reordered.
VOCAB_PRISM_WORDS=(Preconditions Rules Inputs Side-effects Mutations)
VOCAB_SCOUT_WORDS=(State Constraints Triggers Outputs Updates)
VOCAB_SCOUT_VALUE_LIST="State | Constraints | Outputs | Updates | Triggers"
VOCAB_NEW_OBS_KEY="observability_scout_dimension"

# V4 -- exact historical specs/TEMPLATE/* lines, derived by hand from the
# pre-rename template content at the commit this ticket branched from (the
# git-log-p derivation spec.md D3 describes, done once rather than scripted).
# Stored as alternating old/new lines so no delimiter collides with markdown.
VOCAB_V4_DATA_FILE="$(dirname "${BASH_SOURCE[0]}")/upgrade-vocab-v4-data.txt"

# vocab_classify_file <in> <out> <rel-path>
# Writes the classified rewrite of <in> to <out>. Sets VOCAB_REWRITTEN,
# VOCAB_RETAINED, VOCAB_AMBIGUOUS, the array VOCAB_AMBIGUOUS_DETAIL (each
# entry "lineno<TAB>suggestion") and the array VOCAB_REWROTE_LINES (each entry
# one rewritten line number, BTG-334 -- consumed by vocab_mark_residual's own
# recheck call, below). <rel-path> is relative to the ticket
# directory and drives the file-level and region-level V0 checks.
# Returns 0 on success. Returns 1, having emitted a named
# IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed seam, if the stats-file
# mktemp or the classifier awk itself fails -- never a silent 0-rewritten skip
# (code-review B3): a caller that ignored this would advance the stamp over a
# file the engine never actually classified.
vocab_classify_file() {
  local in="$1" out="$2" relpath="$3" statsfile
  statsfile="$(mktemp)"
  if [[ $? -ne 0 || -z "$statsfile" || ! -f "$statsfile" ]]; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_classify_file: mktemp failed building a stats file for $relpath -- refusing to silently skip; the run must abort." >&2
    return 1
  fi
  local frozen_file=0 base
  base="$(basename "$relpath")"
  case "$base" in
    decisions.md|submission.md|summary.md|design-options.md) frozen_file=1 ;;
  esac
  case "$relpath" in
    attachments/*|*/attachments/*) frozen_file=1 ;;
  esac
  local is_problem=0
  [[ "$base" == "problem.md" ]] && is_problem=1

  if ! awk -v frozen_file="$frozen_file" -v is_problem="$is_problem" \
      -v scout_value_list="$VOCAB_SCOUT_VALUE_LIST" -v new_key="$VOCAB_NEW_OBS_KEY" \
      -v v4file="$VOCAB_V4_DATA_FILE" \
      -f "$(dirname "${BASH_SOURCE[0]}")/upgrade-vocab-classify.awk" \
      "$in" > "$out" 2> "$statsfile"; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_classify_file: the classifier engine failed on $relpath -- refusing to silently skip; the run must abort. awk stderr:" >&2
    cat "$statsfile" >&2
    rm -f "$statsfile"
    return 1
  fi

  VOCAB_REWRITTEN=0 VOCAB_RETAINED=0 VOCAB_AMBIGUOUS=0
  VOCAB_AMBIGUOUS_DETAIL=()
  VOCAB_REWROTE_LINES=()
  local line
  while IFS= read -r line; do
    case "$line" in
      "VOCAB_STATS "*)
        eval "${line#VOCAB_STATS }" ;;
      "VOCAB_AMBIGUOUS "*)
        VOCAB_AMBIGUOUS_DETAIL+=("${line#VOCAB_AMBIGUOUS }") ;;
      "VOCAB_REWROTE "*)
        VOCAB_REWROTE_LINES+=("${line#VOCAB_REWROTE }") ;;
    esac
  done < "$statsfile"
  rm -f "$statsfile"

  # Preserve "no final newline" exactly as the input had it: awk's print always
  # terminates the last record, so undo that one byte when the source lacked it.
  if [[ -s "$in" ]] && [[ "$(tail -c1 "$in" | wc -l)" -eq 0 ]]; then
    truncate -s -1 "$out"
  fi
  return 0
}

# _vocab_collapse <classified-file> <ambig-lines> <dest> <relpath> -- BTG-334
# AC-4 helper: collapses each marker block in <classified-file> (positioned at
# the ORIGINAL line numbers in <ambig-lines>) to just its suggestion line,
# producing <dest> line-aligned with whatever <classified-file> was itself
# classified FROM. Never parses block CONTENT -- a marked line is found by
# POSITION alone, so adopter text that itself contains "<<<<<<< theirs" at an
# unmarked position is passed through untouched (S-4.7). Returns 1, having
# emitted IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed, if a marker
# block is not where <ambig-lines> says one is.
_vocab_collapse() {
  local classified="$1" ambig="$2" dest="$3" relpath="$4" errfile
  errfile="$(mktemp)"
  if ! awk -v ambig="$ambig" '
    BEGIN {
      n = split(ambig, tmp, ",")
      for (i = 1; i <= n; i++) if (tmp[i] != "") isambig[tmp[i] + 0] = 1
      origline = 0
    }
    {
      origline++
      if (isambig[origline]) {
        if ($0 != "<<<<<<< theirs") { print "misaligned open marker at line " origline > "/dev/stderr"; exit 1 }
        if ((getline) <= 0) { print "truncated theirs line at line " origline > "/dev/stderr"; exit 1 }
        if ((getline sep) <= 0 || sep != "=======") { print "misaligned separator at line " origline > "/dev/stderr"; exit 1 }
        if ((getline sug) <= 0) { print "truncated suggestion at line " origline > "/dev/stderr"; exit 1 }
        if ((getline endm) <= 0 || endm != ">>>>>>> scout-suggestion") { print "misaligned close marker at line " origline > "/dev/stderr"; exit 1 }
        print sug
      } else {
        print $0
      }
    }
  ' "$classified" > "$dest" 2>"$errfile"; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_mark_residual: the classified output has no marker block where the first pass said one was, for $relpath -- refusing to silently skip; the run must abort. detail:" >&2
    cat "$errfile" >&2
    rm -f "$errfile"
    return 1
  fi
  rm -f "$errfile"
  return 0
}

# vocab_mark_residual <in> <out> <relpath> <ambig-lines> <scratch-prefix> <conflict> [<stage-subject>]
# BTG-334 AC-4 (c3-5, DEC-007): rechecks a file the first pass changed to find
# every line the rewrite left unfinished (a "leftover"), then stages EVERY
# marked line -- first-pass ambiguous and leftover alike -- inside the
# engine's own marker convention, with nothing silently half-migrated
# (problem.md: "every ambiguous line is surfaced as a marked conflict with a
# correct suggestion").
#   <in>            the bytes the first pass classified -- the BTG-333
#                   snapshot ($staging/vocab.orig.<munged>, DEC-012 rule 1)
#   <out>           the first pass's own classified output
#   <relpath>       ticket-relative path (e.g. "spec.md"), the same value
#                   vocab_classify_file's own callers use for ITS
#                   classify_engine_failed seams -- also the default
#                   <stage-subject> when the 7th argument is omitted
#   <ambig-lines>   comma list of first-pass VOCAB_AMBIGUOUS line numbers
#                   (may be empty)
#   <scratch-prefix> writes <prefix>.aligned, <prefix>.recheck,
#                   <prefix>.recheck-aligned, <prefix>.marked, <prefix>.render
#                   (all removed after)
#   <conflict>      written ONLY when a leftover exists, via vocab_stage_cp
#                   (DEC-017 -- never a bare cp, so a write fault here fails
#                   loud under its own name, upgrade.vocab.staging_failed,
#                   like every other staging copy in this engine)
#   <stage-subject> OPTIONAL: the vocab_stage_cp <subject> for the <conflict>
#                   write -- every OTHER vocab_stage_cp call site in this
#                   engine uses the target-relative path ($rel, e.g.
#                   "specs/ORD-1/spec.md", hardening.sh S-8.1), not the
#                   ticket-relative <relpath>; defaults to <relpath> if
#                   omitted (a caller with no $rel to hand, e.g. a unit test)
#
# Algorithm: (1) collapse <out> by position (_vocab_collapse) to <aligned>,
# line-count-matched to <in>; (2) recheck <aligned> via vocab_classify_file;
# (3) if the recheck found nothing, done -- VOCAB_RESIDUAL_LINES="",
# VOCAB_MARKED_LINES=<ambig-lines>, <conflict> is NOT written; (4) otherwise
# collapse the RECHECK's own output the same way, giving <recheck-aligned> --
# also line-count-matched to <in> -- which is then the single source of
# "what this line's final content is" for every marked line, whether it was
# a first-pass suggestion the recheck left alone, a plain rewrite the recheck
# found, or a fresh ambiguous mark the recheck raised; (5) render one awk
# pass over <in> (for "theirs") and <recheck-aligned> (for the suggestion,
# CR stripped -- S-4.6's byte convention) to a scratch file; (6) check the
# rendered block count against the marked-line count; (7) vocab_stage_cp the
# scratch render into <conflict>.
#
# Sets VOCAB_RESIDUAL_LINES (ascending comma list, empty if no leftover) and
# VOCAB_MARKED_LINES (ascending comma list: first-pass ambiguous lines union
# leftovers). Returns 0 on success; returns 1, having emitted
# IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed <relpath>, if
# _vocab_collapse fails, the recheck's own vocab_classify_file call fails,
# the rendered block count differs from the marked-line count, or the
# vocab_stage_cp into <conflict> fails (its own upgrade.vocab.staging_failed).
vocab_mark_residual() {
  local in="$1" out="$2" relpath="$3" ambig_lines="$4" prefix="$5" conflict="$6"
  local stage_subject="${7:-$relpath}"
  local aligned="$prefix.aligned" recheck="$prefix.recheck" recheck_aligned="$prefix.recheck-aligned"

  _vocab_collapse "$out" "$ambig_lines" "$aligned" "$relpath" || return 1

  if ! vocab_classify_file "$aligned" "$recheck" "$relpath"; then
    return 1
  fi

  # N2 (code-review, folded into DEC-018 C1): VOCAB_REWROTE_LINES must carry
  # exactly one entry per line the recheck counted as rewritten -- trusting a
  # non-zero VOCAB_REWRITTEN the array does not actually back is the "fail
  # open" gap Behavior 5 forbids. Checked before either is used below.
  if [[ "$VOCAB_REWRITTEN" -gt 0 && "${#VOCAB_REWROTE_LINES[@]}" -ne "$VOCAB_REWRITTEN" ]]; then
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_mark_residual: the recheck reported VOCAB_REWRITTEN=$VOCAB_REWRITTEN but VOCAB_REWROTE_LINES has ${#VOCAB_REWROTE_LINES[@]} entries for $relpath -- refusing to silently trust a mismatched count; the run must abort." >&2
    return 1
  fi

  VOCAB_RESIDUAL_LINES=""
  if [[ "$VOCAB_REWRITTEN" -eq 0 && "$VOCAB_AMBIGUOUS" -eq 0 ]]; then
    VOCAB_MARKED_LINES="$ambig_lines"
    return 0
  fi

  local recheck_ambig_lines="" d
  for d in "${VOCAB_AMBIGUOUS_DETAIL[@]:-}"; do
    [[ -n "$d" ]] || continue
    recheck_ambig_lines+="${d%%$'\t'*},"
  done
  recheck_ambig_lines="${recheck_ambig_lines%,}"

  _vocab_collapse "$recheck" "$recheck_ambig_lines" "$recheck_aligned" "$relpath" || return 1

  local -A residual_seen=()
  local ln
  for ln in "${VOCAB_REWROTE_LINES[@]:-}"; do
    [[ -n "$ln" ]] && residual_seen["$ln"]=1
  done
  for d in "${VOCAB_AMBIGUOUS_DETAIL[@]:-}"; do
    [[ -n "$d" ]] && residual_seen["${d%%$'\t'*}"]=1
  done

  VOCAB_RESIDUAL_LINES="$(printf '%s\n' "${!residual_seen[@]}" | sort -n | paste -sd,)"
  local marked_sorted
  marked_sorted="$(
    { [[ -n "$ambig_lines" ]] && tr ',' '\n' <<<"$ambig_lines"; printf '%s\n' "${!residual_seen[@]}"; } \
      | sort -n -u | paste -sd,
  )"
  VOCAB_MARKED_LINES="$marked_sorted"

  local markedfile="$prefix.marked" rendercount="$prefix.render-count" rendered_scratch="$prefix.render"
  tr ',' '\n' <<<"$marked_sorted" > "$markedfile"

  if ! awk -v markedfile="$markedfile" -v sugfile="$recheck_aligned" -v infile="$in" '
    BEGIN {
      n_in = 0
      while ((getline iline < infile) > 0) { n_in++; inarr[n_in] = iline }
      close(infile)
      n_sug = 0
      while ((getline sline < sugfile) > 0) { n_sug++; sugarr[n_sug] = sline }
      close(sugfile)
      while ((getline ml < markedfile) > 0) { if (ml != "") ismark[ml + 0] = 1 }
      close(markedfile)
      nblocks = 0
    }
    {
      if (ismark[NR]) {
        nblocks++
        theirs = inarr[NR]
        cr = ""
        if (theirs ~ /\r$/) { cr = "\r"; sub(/\r$/, "", theirs) }
        sug = sugarr[NR]
        sub(/\r$/, "", sug)
        print "<<<<<<< theirs"
        print theirs cr
        print "======="
        print sug
        print ">>>>>>> scout-suggestion"
      } else {
        print $0
      }
    }
    END { print nblocks > "/dev/stderr" }
  ' "$aligned" > "$rendered_scratch" 2>"$rendercount"; then
    rm -f "$markedfile" "$rendercount" "$rendered_scratch"
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_mark_residual: the render pass failed for $relpath -- refusing to silently skip; the run must abort." >&2
    return 1
  fi
  local rendered; rendered="$(cat "$rendercount" 2>/dev/null)"
  local marked_count; marked_count="$(tr ',' '\n' <<<"$marked_sorted" | grep -c .)"
  rm -f "$markedfile" "$rendercount"

  # Preserve "no final newline" exactly as <in> had it, same convention as
  # vocab_classify_file.
  if [[ -s "$in" ]] && [[ "$(tail -c1 "$in" | wc -l)" -eq 0 ]]; then
    truncate -s -1 "$rendered_scratch"
  fi

  if [[ "${rendered:-0}" -ne "$marked_count" ]]; then
    rm -f "$rendered_scratch"
    emit_seam IMPOSSIBLE_STATE upgrade.vocab.classify_engine_failed "$relpath"
    echo "upgrade-claire: vocab_mark_residual: rendered block count (${rendered:-0}) differs from the marked-line count ($marked_count) for $relpath -- refusing to silently skip; the run must abort." >&2
    return 1
  fi

  # DEC-017: stage the rendered form through BTG-333's checked copy (never a
  # bare cp) -- the SAME staging-copy discipline every other write in this
  # engine uses, so a write fault here fails loud under its own name
  # (upgrade.vocab.staging_failed) exactly like any other staging copy.
  if ! vocab_stage_cp "$rendered_scratch" "$conflict" "$stage_subject"; then
    rm -f "$rendered_scratch"
    return 1
  fi
  rm -f "$rendered_scratch"

  return 0
}
