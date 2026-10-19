#!/usr/bin/env bash
#
# org-binding-parse.sh -- the DOCUMENT half of `CLAIRE_ORG.md`'s per-prefix
# binding reader (BTG-179). SOURCED by `org-binding-resolve.sh`; never executed.
#
# Bounded context: Governance config / per-repo binding resolution.
# Invariants relied on from outside this boundary:
#   - `CLAIRE_ORG.md` is the single per-repo binding mechanism (ADR_CLAIRE-0010 cl.2).
#   - §9 / §10 / §13 are registered Configuration Contracts whose absent-value
#     polarities DIFFER and are never unified: §9 fail-loud, §10
#     mint-by-convention, §13 disabled.
#
# THE SEAM, four-way since BTG-247 DEC-012 (OQ-B) and stated once in
# `org-binding-modes.sh`:
#   THIS file  LEXES the document -- regions, rows, cells, forms, and the
#              present-and-unreadable guards. It no longer maps a tracker cell
#              to a TS-1 skill (BTG-247): that vocabulary, and the one
#              per-prefix answer built entirely from it, moved to the fourth
#              module -- see `org-binding-crossref.sh`'s own header.
#   modes      ANSWERS questions that name no prefix: both scalar forms,
#              `--prefixes`, `--form`. Those two modes USED to live here and were
#              moved by DEC-030; this header said otherwise for one review cycle,
#              which is B4-1's site 2.
#   crossref   ANSWERS the cross-section question: how §10 and §13 borrow §9's
#              tracker vocabulary to build their own per-prefix answers
#              (BTG-247 DEC-012 / OQ-B, authorizing the fourth module and
#              overturning `claire-surfaces.md`'s earlier "three is terminal").
#   resolve    ANSWERS questions about a PREFIX, and is the entry point.
#
# WHY IT EXISTS AT ALL, and what ALL FOUR modules owe (distribution rows -- the
# COPY_PATHS entry, the RECONCILE row and the surface-registry mention -- plus the
# `DX_SCRIPT_LINE_CAP` listing): DEC-004 pre-declared this split, DEC-027 records
# taking it and enumerates the obligations, DEC-030 made it three-way, BTG-247
# DEC-012 made it four (archive/BTG-247/spec.md Proposed Design Step 4; DEC-007's
# re-derived 324-line threshold is why). Pointed at rather than restated -- a
# second copy of that list is a second place for it to drift, and B4-1 is what a
# drifted copy costs.
#
# It reads `$ORG`, set by its caller. It defines functions and the three section
# names; it runs nothing at source time and it never exits, except through
# `halt()`, the shared failure exit all four modules use.

# halt <condition> <message> -- the sole failure exit. Prints NO stdout, so a
# caller can never read a partial answer beside a failure.
halt() {
  echo "condition=$1" >&2
  echo "org-binding-resolve: $2" >&2
  exit 1
}

# --- section extraction --------------------------------------------------
#
# The three binding sections, by ORDINAL and by NAME. Both are needed because the
# ordinal is not guaranteed to be there: `CLAIRE_ORG_TEMPLATE.md` ships these
# headings UNNUMBERED (`## Tracker Binding`) and tells the adopter to rename the
# file and "adjust the content, not the structure" -- and neither
# `adopt-claire.sh` nor `adopt-provision.sh` renumbers. A matcher anchored on
# `^## <n>\.` alone finds nothing in a freshly adopted repo, and three of the four
# modes have an absent-section answer indistinguishable from a legitimate one
# (`allocator=unbound`, `enabled=no`, `N=0`) -- a silent wrong answer with exit 0,
# which this file's header forbids.
SEC_TRACKER='Tracker Binding'
SEC_ALLOCATOR='Id Allocation Binding'
SEC_SPRINT='Sprint-Enforcement Binding'

# Extract one top-level section's region, from its `## [N. ]<Name>` heading to the
# next top-level `## ` heading. Anchoring every read to its own section is what
# keeps §9's prose from answering a §10 question (the II-003/II-005 lesson the
# structural gate already encodes). The ordinal is OPTIONAL and the name is not:
# the name is the part an adopter is told not to change.
#
# The four backslashes are load-bearing: `awk -v` runs its own escape pass over
# the value, so `\\.` in shell (two chars, `\.`) reaches the regex as a plain `.`
# -- a wildcard that would match `## 9X Tracker Binding` -- AND emits
# `awk: warning: escape sequence` onto stderr, which is this script's CONDITION
# channel. `\\\\.` survives both passes as a literal dot and prints nothing.
section_region() {
  awk -v pat="^## ($1\\\\. )?$2[[:space:]]*\$" '
    $0 ~ pat       { grab=1; print; next }
    grab && /^## / { exit }
    grab           { print }
  ' "$ORG"
}

# require_section9 <region> -- §9's ABSENT-SECTION rule, and ONLY §9's.
#
# THE THREE SECTIONS ANSWER AN ABSENT SECTION DIFFERENTLY, exactly as they answer
# an absent VALUE differently, and the two rule sets are never unified:
#   §9  absent => FAIL LOUD. It is the mandatory home for tracker coupling, so
#       "not there" is a broken config, not a configuration.
#   §10 absent => UNBOUND / MINT BY CONVENTION -- the new grammar adds no
#       requirement to declare §10, and halting would break every adopter who
#       never did. There is deliberately NO branch for it below.
#   §13 absent => DISABLED (the Confirm path). Likewise no branch.
# Called from a plain statement, never from inside `$(...)`: a halt there would
# exit only the subshell and the caller would read an empty answer as success.
require_section9() {
  [ -n "$1" ] || halt tracker.binding.section_missing \
    "no '## 9. Tracker Binding' (or '## Tracker Binding') section in $ORG; §9 is the single mandatory home for tracker coupling and an absent one is a broken config, never the inner-source SKIP"
}

# --- per-prefix table extraction -----------------------------------------
# The data rows of the `### Per-prefix <what> bindings` table inside a section
# region. A row is a pipe-delimited line that is neither the header nor the
# `---` separator.
#
# THE TERMINATOR IS PER-SUBSECTION (`^#{2,3} `), NOT PER-SECTION. A binding
# section carries other pipe tables after this one -- *Connection config*, the
# `IA-*` capability table, §13's Field/Value/Meaning table -- and stopping only
# at the next H2 ingests every one of their rows as per-prefix DATA. Nothing
# downstream rejects them: a `Setting | Where it lives` row is not a wildcard and
# names no tracker the map knows, so `validate_tracker_table` passes it through.
# The damage is silent in four directions -- a wrong N, a wrong `configured prefixes:`
# list inside a halt, `section_form` counting phantom rows and calling a section
# per-prefix that declares nothing, and a phantom first cell able to shadow a real
# prefix.
#
# This is also the terminator all three consumer lexers already use
# (`jira-projectkey-lib.sh`, `yt-projectkey-lib.sh`, `mint-id.sh`'s
# `resolver_required`). DEC-004 exists so one grammar has one parser; the canonical
# parser being the odd one out is that same drift with the blast radius reversed.
#
# THE SUBSECTION WORD IS REQUIRED, and it is the whole of the DEC-030 fix. This lexer
# used to accept ANY `### Per-prefix .* bindings` and resolve its rows as authoritative,
# while the presence predicates that decide whether to CALL it matched only the literal
# `### Per-prefix allocator bindings`. A renamed-but-valid H3 -- `### Per-prefix
# id-allocation bindings` -- was therefore read as a table by the parser and as no table
# by the guards.
#
# NAMED, NOT WIDENED. Widening the guards to `.* bindings` would let §9's tracker
# table answer a §10 question -- the II-003/II-005 cross-section leak DEC-028
# Alternative 2 rejected. Naming the subsection at every site makes the grammar
# one thing that every reader spells identically.
table_rows() {
  printf '%s\n' "$1" | awk -v h="^### Per-prefix $2 bindings" '
    $0 ~ h                        { intable=1; next }
    intable && /^#{2,3} /         { exit }
    intable && /^\| *Ticket prefix/ { next }
    intable && /^\|[ -]*-[- |]*\|/  { next }
    intable && /^\|/              { print }
  '
}

# declares_table <subsection-word> -- does the FILE declare
# `### Per-prefix <word> bindings` with a DATA row, ANYWHERE?
#
# THE ONE REGION-FREE READ HERE, deliberately: it cannot be asked of a region the
# section matcher failed to find, which is the state it exists to detect. A
# PRESENCE test only -- it never says which prefix binds what, so no other
# section's data can leak through it -- and it NAMES its subsection, so §9's
# table can never answer a §10 question (DEC-030). `table_rows` does the row
# lexing, so this adds no second copy of that grammar.
declares_table() {
  [ -n "$(table_rows "$(awk -v h="^### Per-prefix $1 bindings" '$0 ~ h { g=1 } g { print }' "$ORG")" "$1" \
          | grep '[^[:space:]]' || true)" ]
}

# require_locatable_10 <sec10-region> -- §10's PRESENT-and-unreadable rule, in
# the one place both `--allocator` and `--form` can reach it (DEC-030 cl.5).
#
# ONE DETECTOR SINCE BTG-242, and the second one is RETIRED rather than lost. It
# read the RESERVED LITERAL `Per-prefix` off the bound line: seeing it while §10
# was unlocatable meant the table was out of reach. That literal only ever
# appeared on `**Bound allocator(s):**`, and BTG-242 removed that line -- so the
# detector's subject no longer exists, and the state it covered is reached earlier
# and named better by `idalloc.binding.form_removed`, which fires on the line's
# PRESENCE whether or not §10 can be located. `idalloc.binding.section_missing` is
# unchanged and is still raised by the surviving detector:
#   (b) a DECLARED table with a data row that no region could anchor.
require_locatable_10() {
  [ -z "$1" ] || return 0
  if declares_table allocator; then
    halt idalloc.binding.section_missing \
      "this file declares a '### Per-prefix allocator bindings' table with a data row, but no '## 10. Id Allocation Binding' (or '## Id Allocation Binding') heading could be located to anchor it; rename the heading -- refusing to read the bound line as a scalar allocator, which would call every prefix bound"
  fi
}

# require_locatable_13 <sec13-region> -- the SAME rule, one section over
# (DEC-030 cl.5). §13's polarity is fail-safe-toward-DISABLED and that is NOT
# weakened: it governs an ABSENT declaration. A §13 that DECLARES enforcement and
# cannot be located is present-and-unreadable, and resolving it DISABLED silently
# downgrades a declared `Block` fallback to `Confirm` -- a guard that is off and
# looks on, which is the state §13's own marker rule refuses everywhere else.
#
# §13 has no bound line, so the reserved-literal detector has no analogue here;
# the evidence is a declared table or a repo-level marker the region hid.
require_locatable_13() {
  [ -z "$1" ] || return 0
  if declares_table sprint-enforcement || grep -q 'sprint-enforcement-enabled:' "$ORG" 2>/dev/null; then
    halt sprint.binding.section_missing \
      "this file declares sprint enforcement (a per-prefix table, a 'sprint-enforcement-enabled' marker, or both) but no '## 13. Sprint-Enforcement Binding' (or '## Sprint-Enforcement Binding') heading could be located to anchor it; rename the heading -- resolving DISABLED here would downgrade a declared fallback to Confirm silently"
  fi
}

# cell <row> <n> -- the nth pipe-delimited cell, trimmed of whitespace and of the
# backticks the tables use for literals.
cell() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '{ print $(n+1) }' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^`//; s/`$//'
}

# unfilled <value> -- true when a cell holds an un-substituted template
# placeholder. §9 already rules that a placeholder on the BOUND line is no
# binding at all; this is that same rule one level down, at cell granularity.
# Nobody deletes a key cell -- they copy the template row and fill three of its
# four cells -- so this is the state an adopter actually ships.
unfilled() {
  case "$1" in "<"*">") return 0 ;; "{{"*) return 0 ;; *) return 1 ;; esac
}

# bound_value <region> <label> -- the value of the `**<label>:**` line inside a
# section region, trimmed of leading whitespace and of the template backticks.
# BOTH backticks are stripped: the template writes its placeholders as
# `` `<your tracker(s) ...>` ``, and a value still carrying the closing backtick
# does not match the `<...>` placeholder test one line below -- so an
# un-substituted binding would read as a real one.
bound_value() {
  local line val
  line="$(printf '%s\n' "$1" | grep -m1 "^\*\*$2:\*\*" || true)"
  [ -n "$line" ] || { printf ''; return 0; }
  val="${line#\*\*$2:\*\*}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  val="${val#\`}"
  val="${val%\`}"
  printf '%s' "$val"
}

# --- the REMOVED declaration forms ---------------------------------------
#
# BTG-242 removed the scalar declaration forms from §9, §10 and §13. They are not
# deprecated-but-read and they are not ignored: their PRESENCE is a named halt.
#
# WHY PRESENCE AND NOT VALUE. A removed form has no value -- reading one to decide
# whether to complain about it would be reading it. The check is a line-shape test,
# run BEFORE any row is read, so a file carrying BOTH a removed declaration and a
# valid table halts on the removal rather than answering from whichever form happens
# to match first: `section_form()`'s own former ordering rule, inherited rather than
# re-derived. WHY THE MESSAGE CARRIES THREE FACTS: there is no deprecation window
# here, so THE HALT IS THE NOTIFICATION. An operator meets it once, cold, and must
# act on it without finding this file -- it names the line to delete, the table that
# replaces it, and the guide that walks the conversion.
BINDING_REMOVAL_GUIDE="docs/migrations/scalar-binding-removal.md"

# require_line_form_removed <region> <label> <condition> <subsection-word> [<extra>]
require_line_form_removed() {
  local region="$1" label="$2" cond="$3" sub="$4" extra="${5:-}"
  printf '%s\n' "$region" | grep -q "^\*\*$label:\*\*" || return 0
  halt "$cond" \
    "'**$label:**' is a REMOVED declaration form (BTG-242) and is no longer read; delete the line and declare one row per ticket-id prefix in the '### Per-prefix $sub bindings' table instead. ${extra}Upgrade the framework FIRST and convert this file SECOND, and see $BINDING_REMOVAL_GUIDE for the conversion."
}

# require_alloc_form_removed <sec10-region> -- §10's removed-form refusal.
#
# SECTION-SCOPED FIRST, FILE-WIDE SECOND, and the second read is not belt-and-braces.
# `mint-id.sh`'s `--binding` has always read `**Bound allocator(s):**` FILE-WIDE, so a
# section-scoped read alone would make the resolver and the sidecar DISAGREE about a
# non-canonical §10 heading -- and both seed steps call one then the other, so a
# disagreement aborts adopt. It also reaches the one shape a region read cannot: an
# unlocatable §10 heading with the removed line still under it. THE `id_scheme:`
# SENTENCE IS PART OF THE CONTRACT: §10 carries two things an operator can mistake for
# one, and deleting both regresses local minting to the sidecar's `PI` prefix default.
require_alloc_form_removed() {
  local extra="§10's repo-wide 'id_scheme:' field is NOT removed and must stay -- it is not the binding line, and four consumers read it directly. "
  require_line_form_removed "$1" 'Bound allocator(s)' idalloc.binding.form_removed allocator "$extra"
  require_line_form_removed "$(cat "$ORG")" 'Bound allocator(s)' idalloc.binding.form_removed allocator "$extra"
}

# require_sprint_form_removed <sec13-region> -- §13's removed-form refusal.
#
# REGION-SCOPED, AND MATCHED AS AN HTML COMMENT rather than by bare name. §13's own
# prose -- and the migration guide, and the template -- all discuss these three markers
# by name, so a name-only match would refuse a file for explaining what it correctly
# does not declare.
#
# ITS PRESENCE, NEVER ITS VALUE. The marker in a retired grammar most often reads `no`,
# which is exactly what the rule that replaces it also answers -- and that is not a
# reason to read it. THIS DOES NOT INVERT §13'S POLARITY: fail-safe-toward-DISABLED
# governs an ABSENT or MALFORMED enablement value, and a present marker in a removed
# grammar is neither -- it is the PRESENT-and-unreadable state `require_locatable_13`
# already halts on, one level up.
require_sprint_form_removed() {
  printf '%s\n' "$1" | grep -q '^<!--[[:space:]]*sprint-\(enforcement-enabled\|check-skill\|check-fallback\):' \
    || return 0
  halt sprint.binding.form_removed \
    "§13's three repo-level markers -- 'sprint-enforcement-enabled', 'sprint-check-skill' and 'sprint-check-fallback' -- are a REMOVED declaration form (BTG-242) and are no longer read; delete all three and declare one row per ticket-id prefix in the '### Per-prefix sprint-enforcement bindings' table instead. Deleting them is SAFE: a prefix with no row now resolves DISABLED by rule, with fallback Confirm, which is what an absent or 'no' marker already meant. Upgrade the framework FIRST and convert this file SECOND, and see $BINDING_REMOVAL_GUIDE for the conversion."
}

# section_form <region> <subsection-word> -- `per-prefix` or `none`.
#
# TABLE PRESENCE IS THE DECLARATION (BTG-242). This used to be a SCALAR XOR TABLE
# decision, selected by the reserved literal `Per-prefix` on a bound line and by
# nothing else, with BOTH contradictory states halting `*.binding.form_conflict`
# because neither form was preferred. With the bound line removed there is no second
# form for a table to contradict, so the exclusivity rule has no subject and
# `form_conflict` RETIRES in both sections.
#
# WHAT REPLACES IT IS NOT A SECOND FORM BUT A NAMED ABSENCE. `none` means "this
# section declares no per-prefix binding", and each section answers that state in its
# OWN polarity, one level up, where the polarities live: §9 halts
# `tracker.binding.table_missing`, §10 mints, §13 resolves DISABLED. This function
# deliberately does not know which -- it reports the shape, never the verdict, so
# `--form` can describe a file that `--tracker` refuses.
section_form() {
  local region="$1" sub="$2" rows n
  rows="$(table_rows "$region" "$sub")"
  n="$(printf '%s\n' "$rows" | grep -c '^|' || true)"
  if [ "$n" -ge 1 ]; then echo per-prefix; else echo none; fi
}
