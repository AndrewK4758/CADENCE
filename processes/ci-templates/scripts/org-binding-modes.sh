#!/usr/bin/env bash
#
# org-binding-modes.sh -- the answers that take NO PREFIX. SOURCED by
# `org-binding-resolve.sh` after `org-binding-parse.sh`; never executed.
#
# Bounded context: Governance config / per-repo binding resolution.
# Invariants relied on from outside this boundary:
#   - `CADENCE_ORG.md` is the single per-repo binding mechanism (ADR_CADENCE-0010 cl.2).
#   - §9 / §10 / §13's absent-value polarities DIFFER and are never unified.
#
# THE SEAM, now three-way and stated once here:
#   `org-binding-parse.sh`   LEXES the document -- regions, rows, cells, forms.
#   `org-binding-modes.sh`   ANSWERS questions that name no prefix: both scalar
#                            forms, `--prefixes`, `--form`.
#   `org-binding-resolve.sh` ANSWERS questions ABOUT A PREFIX, plus the entry
#                            point and dispatch.
#
# WHY THREE: DEC-028 recorded that both halves were within 10 lines of Facet 3's
# 400-line ceiling and that "the next change of any size will need the third
# module". DEC-030's sweep was that change. This file owes the same three
# distribution rows as its siblings -- see DEC-030.
#
# Functions only: nothing runs at source time, and `$ORG` plus every helper come
# from the caller and the parse half.

# §9'S SCALAR ANSWERER IS GONE (BTG-242). `resolve_tracker_scalar()` lexed the
# `**Bound tracker(s):**` line, and that line was REMOVED from the grammar rather
# than deprecated in place, so there is nothing left for it to lex. Its two
# conditions retire with it:
#   `tracker.binding.scalar_unbound`  -> superseded by `tracker.binding.table_missing`,
#                                        which asks the same question ("§9 declares
#                                        no binding") about the shape that replaces
#                                        the bound line: a table with no data row.
#   its `tracker.binding.tracker_unmapped` arm -> the condition SURVIVES; only this
#                                        second raising site is gone. The per-prefix
#                                        row path in `resolve_tracker()` still
#                                        raises it, so the curated-reference-set
#                                        rule is unchanged.
# Removed rather than left as dead code with a "deprecated" comment, per
# `deprecation-policy.md`'s Sunset Execution step 2.
#
# `bound_value()` SURVIVES in the parse half, because `**Project key(s):**` is
# deliberately RETAINED by BTG-242 and both sync adapters still read it at
# resolution level (2).

# §10'S SCALAR ANSWERER IS GONE TOO (BTG-242). `allocator_scalar_answer()` lexed
# the `**Bound allocator(s):**` line, which was REMOVED from the grammar, so it
# had nothing left to lex. Its three outcomes are dispositioned rather than
# dropped:
#   line present, names a real allocator -> now `idalloc.binding.form_removed`.
#   line present, says `None`/placeholder -> same halt. A removed form is refused
#                                        whatever it says; "it happened to say
#                                        None" is not a reason to read it.
#   line ABSENT                          -> `unbound` / `n/a` / `source=default`,
#                                        which is BYTE-IDENTICAL to the answer
#                                        `resolve_allocator()`'s unmatched-prefix
#                                        tail already gives. §10's MINT polarity
#                                        is therefore preserved by the fall-
#                                        through rather than by a branch, and
#                                        `source=scalar` leaves §10's vocabulary.
#
# `require_locatable_10 ""` used to be raised from inside this function. It is now
# raised on `resolve_allocator()`'s own path, so the PRESENT-and-unreadable rule
# survives the deletion instead of leaving with it.

# --- --prefixes ----------------------------------------------------------
#
# One line per DECLARED prefix: `<prefix><TAB><project key><TAB><tracker><TAB><skill>`.
#
# A WILDCARD ROW IS EMITTED LAST AND CONTRIBUTES 0 TO N. It names no prefix -- it
# says "any prefix, inner-source" -- so a caller counting configured projects must
# not count it, while a caller RENDERING the choice still needs to know it is
# there (the `/cadence-triage --file-only` menu shows it as a final "any prefix" row).
# Emitting it, marked, serves both; omitting it would serve only the first.
#
# A repo with no table prints NOTHING and exits 0. That is the answer, not a
# failure: N = 0 is exactly the state every existing adopter is in, and a halt
# here would make the counting step itself the thing that breaks them.
#
# A repo with no §9 AT ALL is the different case, and it halts. N = 0 there is
# indistinguishable from the legitimate scalar repo above, and the caller that
# reads it is `/cadence-triage --file-only`'s menu step -- so a silent 0 suppresses the
# prefix menu on a multi-prefix repo, which is `triage.fileonly.menu_bypassed`
# produced by the resolver rather than detected by it.
resolve_prefixes() {
  local sec9 rows row rp key tcell ts wild=""
  sec9="$(section_region 9 "$SEC_TRACKER")"
  require_section9 "$sec9"
  rows="$(table_rows "$sec9" tracker)"
  [ -n "$(printf '%s\n' "$rows" | grep '[^[:space:]]' || true)" ] || return 0
  validate_tracker_table "$rows"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    tcell="$(cell "$row" 2)"
    key="$(cell "$row" 3)"; unfilled "$key" && key=""
    ts="$(tracker_skill "$tcell")" || ts="$tcell|n/a"
    if [ "$rp" = "*" ]; then
      wild="$(printf '*\t\t%s\tn/a' "${ts%%|*}")"
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$rp" "$key" "${ts%%|*}" "${ts##*|}"
  done <<EOF
$rows
EOF
  [ -n "$wild" ] && printf '%s\n' "$wild"
  return 0
}

# --- --form --------------------------------------------------------------
#
# WHICH FORM IS EACH SECTION IN. This is the question every consumer must answer
# BEFORE it can decide whether to call the resolver at all, and while no mode
# answered it each consumer hand-rolled its own table-presence lexer
# (`js_org_perprefix_table`, `yt_org_perprefix_table`, `mint-id.sh`'s
# `resolver_required`). That is the PROD_CADENCE-005 drift DEC-004 exists to prevent, and
# it has already produced one defect: the copies and the canonical parser
# disagreed about where a per-prefix table ends.
#
# SECTION 13 IS REPORTED FROM ITS TABLE ALONE. §9 and §10 are SELECTED by the
# reserved literal on a bound line, so a line/table contradiction is possible and
# HALTs. §13 has no bound line at all: its table is consulted first and an
# unmatched prefix FALLS THROUGH to the repo-level markers, deliberately, so
# there is no contradiction for it to have. Inventing a §13 selector to make the
# three look uniform would document a rule this resolver does not implement.
#
# ALL THREE ARE COMPUTED BEFORE ANYTHING IS PRINTED. An operator attaching this
# output to a support ticket (the migration guide's §7) must never be handed
# three plausible lines describing a file that does not resolve.
resolve_form() {
  local sec9 sec10 sec13 f9 f10 f13
  sec9="$(section_region 9 "$SEC_TRACKER")"
  require_section9 "$sec9"
  # `--form` SHARES every removed-form and present-and-unreadable halt rather than
  # describing a file the prefix-keyed modes refuse. The migration guide sends this
  # output to a support ticket, so an attachment stating that §9 is fine on a file
  # that halts would send the operator looking in the wrong place.
  require_line_form_removed "$sec9" 'Bound tracker(s)' tracker.binding.form_removed tracker
  f9="$(section_form "$sec9" tracker)"
  sec10="$(section_region 10 "$SEC_ALLOCATOR")"
  require_alloc_form_removed "$sec10"
  require_locatable_10 "$sec10"
  f10="$(section_form "$sec10" allocator)"
  sec13="$(section_region 13 "$SEC_SPRINT")"
  require_locatable_13 "$sec13"
  require_sprint_form_removed "$sec13"
  f13="$(section_form "$sec13" sprint-enforcement)"
  printf 'section9=%s\n'  "$f9"
  printf 'section10=%s\n' "$f10"
  printf 'section13=%s\n' "$f13"
}

# --- --allocator-prefixes ------------------------------------------------
#
# One line per prefix DECLARED IN §10's `### Per-prefix allocator bindings`
# table, in TABLE ORDER. No other column, and no other section.
#
# §10 AND ONLY §10. resolve_prefixes() above walks §9's TRACKER table; the two
# tables are declared INDEPENDENTLY and may name different prefix sets, so
# reusing it here would seed whatever the TRACKER binding happens to name --
# PROD_CADENCE-022's own named second-order trap. A prefix with a §9 row and no §10 row
# would be seeded, and a prefix with a §10 row and no §9 row -- the
# inner-source-allocator case this binding exists to support -- would be MISSED.
# So this function never calls section_region 9 and never calls
# require_section9: §10 has no §9 dependency, and §9's absent-section FAIL-LOUD
# is not §10's polarity (BTG-180 DEC-001).
#
# ADR / II / PROD ARE EXCLUDED even if a row names one. §10's own rule is that
# their numbering is §10-INDEPENDENT and consults no prefix row, mirroring
# resolve_allocator()'s short-circuit one file over. Emitting them would hand the
# seed steps prefixes they already seed unconditionally, scanned by the WRONG
# scanner: `idseed_scan_ticket` reads `specs/ADR-NNN`, while ADR numbering lives
# in `docs/ADR/NNNN-*.md`.
#
# A PLACEHOLDER PREFIX CELL IS EXCLUDED -- unfilled()'s rule at cell
# granularity. Nobody deletes a template row; they copy it and fill some of its
# cells, so a literal `<PREFIX>` is the state an adopter actually ships -- and
# `--seed` never removes a row, so a nonsense namespace would be permanent.
#
# A `*` ROW IS EXCLUDED AND REPORTED on stderr. It names no prefix, and a ledger
# high-water row is keyed by one. §9 defines a wildcard grammar; §10 does not,
# and inventing one here would decide §10's wildcard semantics by implication --
# a declaration-syntax change this ticket is scoped out of (BTG-180 OQ-2).
# Silence would hide a misconfiguration, so the skip is VISIBLE: a diagnostic,
# never a `condition=` halt.
#
# NO TABLE / SCALAR FORM => PRINT NOTHING, EXIT 0. That is THE answer, not a
# degraded one -- the same rule resolve_prefixes() states for §9 -- and it is
# what routes both seed steps to their untouched scalar path (BTG-180 DEC-002).
resolve_allocator_prefixes() {
  local sec10 rows row rp
  sec10="$(section_region 10 "$SEC_ALLOCATOR")"
  # DEC-028's PRESENT-and-unreadable rule: a DECLARED table under a heading no
  # region can anchor HALTs. §10's mint polarity governs an ABSENT declaration,
  # never a present-and-unreadable one -- and an empty enumeration here would
  # tell both seed steps "this repo declares no prefixes" about a file that
  # plainly declares several, which is the silent underrun PROD_CADENCE-022 records,
  # produced by the remediation itself.
  require_locatable_10 "$sec10"
  rows="$(table_rows "$sec10" allocator)"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    [ -n "$rp" ] || continue
    unfilled "$rp" && continue
    # §10-INDEPENDENT prefixes are never enumerated as TICKET prefixes: they are
    # always minted locally, so they never belong in a seed step's work queue.
    # BTG-197 adds core's own three beside the bare three -- additive, exact
    # literals, the bare three byte-unchanged (the sibling rule is stated at
    # resolve_allocator()'s short-circuit in org-binding-resolve.sh).
    case "$rp" in ADR|II|PROD) continue ;; esac
    case "$rp" in ADR_CADENCE|II_CADENCE|PROD_CADENCE) continue ;; esac
    if [ "$rp" = "*" ]; then
      echo "org-binding-resolve: §10 declares a wildcard '*' allocator row; it names no prefix, so it is SKIPPED -- §10 has no wildcard grammar (that is §9's) and a ledger high-water row is keyed by a prefix" >&2
      continue
    fi
    printf '%s\n' "$rp"
  done <<EOF
$rows
EOF
  return 0
}
