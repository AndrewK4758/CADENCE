#!/usr/bin/env bash
#
# jira-md2wiki-lib.sh -- the transform passes behind jira-md2wiki.sh (BTG-205).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# It is SOURCED by jira-md2wiki.sh -- it is not an entry point and runs nothing
# on load.
#
# Split axis (DEC-002): the entry point owns the CLI contract, BLOCK SEGMENTATION
# and the pass pipeline; this file owns the individual transforms and the
# Functional Validation predicate. The split exists because the passes plus this
# repository's comment density do not fit under the 400-line agentic-DX ceiling in
# one file -- measured, not assumed: with everything in here the library reached
# 426 -- and jira-link.sh/jira-link-lib.sh is the established precedent for
# exactly this shape.
#
# PURITY (the property every unit fixture rests on): nothing here reads a file,
# an environment variable, a credential or a socket. Every function is a total
# function of its arguments.
#
# Spec: archive/BTG-205/spec.md (AC-2..AC-5) ; decisions.md DEC-002/DEC-003/DEC-010.

# --------------------------------------------------------------------------
# The canonical no-change line -- the anchored constant (AC-5)
# --------------------------------------------------------------------------
# ticket_TEMPLATE.md's Functional Validation guard fires unless the section
# carries either a non-placeholder checklist item or THIS line. An adopter's
# renderer tested for a LOOSE SUBSTRING of it, so a correctly-filled section
# rendered as NOT SPECIFIED. The generalisable finding, worth stating once: a
# guard keyed on a loose substring of prose will eventually be wrong in BOTH
# directions.
#
# So the wording is anchored HERE, in the executable. It is not quoted into
# ticket_TEMPLATE.md's *If missing* cell, and that is not an oversight:
# btg-152-functional-validation.test.sh asserts, with fault-injection teeth and
# across BOTH adapters, that the cell must not reproduce it.
#
# This constant is a SECOND representation of a fact whose single authored source
# is the guidance comment in specs/TEMPLATE/problem.md, so it is mechanically
# PINNED to it by a harness scenario in the same change. Without that pin,
# II-149's rule says decline the second representation.
JS_MD2WIKI_NO_CHANGE_LINE='No behavioral changes expected -- regression testing only.'

# js_fv_dash_normalize <candidate> -- echo the candidate's comparison form.
#
# THREE operations, in this order, and nothing else (DEC-010, the operator's
# ruling at the Spec Review gate):
#   1. optional horizontal whitespace + U+2014 EM DASH + optional horizontal
#      whitespace  ->  space hyphen hyphen space. Folding the surrounding
#      whitespace INTO the replacement is what makes the UNSPACED em-dash
#      spelling match as well as the spaced one; folding the codepoint alone
#      would leave the unspaced form unmatched.
#   2. collapse every run of horizontal whitespace to one space
#   3. trim leading and trailing horizontal whitespace
#
# No case folding. No punctuation folding beyond the one codepoint named.
# U+2013 EN DASH is deliberately EXCLUDED: it is a semantically different
# character, not a typographic variant of the double hyphen, and admitting it on
# no evidence is the speculative widening Facet 1 forbids. A line spelled with
# one therefore renders the NOT SPECIFIED marker -- a VISIBLE third state, not a
# silent wrong answer.
#
# It has EXACTLY ONE call site (the predicate below), is applied to the CANDIDATE
# only and never to the pin, and no value it returns ever reaches stdout.
# Rewriting an em dash in ordinary description prose would be a new defect of
# precisely the class this ticket removes.
# PORTABILITY (archive/BTG-239/decisions.md DEC-002 is the source of record; nothing
# here re-derives it). The em-dash byte MUST be spelled as a LITERAL UTF-8
# character in the pattern below, never as a chained \xe2\x80\x94 hex escape:
# measured under a six-arm containerized ablation, GNU sed resolves the chained
# \x escape correctly but BusyBox sed does not -- the pattern passes the input
# through byte-for-byte unchanged, and the whole-line comparison in
# js_fv_is_no_change_line then never matches, so the caller falls through to the
# NOT SPECIFIED marker. The literal byte form is measured to match under BOTH
# interpreters, and the en dash (U+2013, a different byte sequence) is measured
# to keep NOT matching under either -- the BTG-236 DEC-010 exclusion is
# unaffected.
js_fv_dash_normalize() {
  printf '%s' "$1" | sed \
    -e 's/[[:blank:]]*—[[:blank:]]*/ -- /g' \
    -e 's/[[:blank:]][[:blank:]]*/ /g' \
    -e 's/^[[:blank:]]*//' \
    -e 's/[[:blank:]]*$//'
}

# The NOT SPECIFIED marker, exactly as ticket_TEMPLATE.md's *If missing* cell
# mandates it. Leaving the section unfilled is NOT the no-change state, and the
# marker says so in the projected issue rather than letting silence be read as an
# assurance -- the visible third state ADR_CLAIRE-0065 requires.
JS_MD2WIKI_NOT_SPECIFIED='_Functional validation NOT SPECIFIED -- this ticket has not stated whether it changes end-user-observable behaviour; do not read this as "no change"._'

# js_fv_is_no_change_line <candidate> -- 0 iff the candidate IS the canonical
# no-change line. ANCHORED: a whole-line comparison against the pin, never a
# substring test.
#
# This is `js_fv_dash_normalize`'s ONE call site, and the normalization is applied
# to the CANDIDATE only, never to the pin -- which is safe precisely because the
# pinned text is already in normal form, and that is asserted rather than assumed.
js_fv_is_no_change_line() {
  [[ "$(js_fv_dash_normalize "$1")" == "$JS_MD2WIKI_NO_CHANGE_LINE" ]]
}

# js_fv_classify <text> -- echo `real`, `nochange` or `absent` for a Functional
# Validation section body whose HTML comments have already been stripped.
#
# A real item is detected STRUCTURALLY and PLACEHOLDER-AWARE: a list item whose
# text is brace-delimited scaffolding is the template's own guidance, not QA
# guidance, and projecting it was one of the two observed polarities of this
# defect. Any list item counts, not only a checkbox one -- a section filled with
# plain bullets is filled, and rendering it NOT SPECIFIED would be the OTHER
# polarity of the same defect.
js_fv_classify() {
  local text="$1" line body
  while IFS= read -r line; do
    [[ "$line" =~ $JS_MD2WIKI_LIST_RE ]] || continue
    body="${BASH_REMATCH[3]}"
    body="${body#'[ ] '}"; body="${body#'[x] '}"; body="${body#'[X] '}"
    body="${body#"${body%%[![:space:]]*}"}"; body="${body%"${body##*[![:space:]]}"}"
    [[ -z "$body" ]] && continue
    [[ "$body" == '{'*'}' ]] && continue
    printf 'real\n'; return 0
  done <<<"$text"
  while IFS= read -r line; do
    js_fv_is_no_change_line "$line" && { printf 'nochange\n'; return 0; }
  done <<<"$text"
  printf 'absent\n'
}

# --------------------------------------------------------------------------
# HTML comments -- pass 2, authoring scaffolding that is never ticket content
# --------------------------------------------------------------------------
# js_md2wiki_strip_comments <text> -- echo the text with `<!-- ... -->` regions
# removed. Multi-line regions are handled, because the one that matters -- the
# Functional Validation guidance block -- spans eight lines. Fenced code is
# exempt: inside a code block a comment is content.
js_md2wiki_strip_comments() {
  printf '%s' "$1" | awk '
    {
      if ($0 ~ /^```/) { fence = !fence; print; next }
      if (fence) { print; next }
      line = $0; outl = ""; had = 0
      if (incomment && length(line) == 0) next
      while (length(line) > 0) {
        if (incomment) {
          q = index(line, "-->")
          if (q == 0) { line = ""; had = 1; break }
          line = substr(line, q + 3); incomment = 0; had = 1
        } else {
          p = index(line, "<!--")
          if (p == 0) { outl = outl line; line = ""; break }
          outl = outl substr(line, 1, p - 1)
          line = substr(line, p + 4); incomment = 1; had = 1
        }
      }
      if (had && outl ~ /^[[:space:]]*$/) next
      print outl
    }
  '
}

# --------------------------------------------------------------------------
# Inline conversions -- applied to ONE already-assembled line of text
# --------------------------------------------------------------------------
# js_md2wiki_inline <text> -- echo the text with its inline Markdown converted.
#
# CODE SPANS ARE CARVED OUT FIRST and converted LAST. A span's contents are meant
# to be read literally, so no other inline rule may run inside one -- and carving
# them out is also what lets the span's own conversion do something the rest of
# the pass must not (defect 2.3, escaping).
#
# The carve leaves a MARKER behind rather than a severed fragment (BTG-236):
# each span is lifted behind a line-derived delimiter, emphasis is then
# converted over the whole line, and every span is restored in place. The
# earlier design severed the line at each span and handed the pieces to
# outside() one at a time, which tore any emphasis pair that wrapped or
# straddled a span across a boundary the source never had.
#
# This pass runs over an ALREADY-ASSEMBLED line. That is the whole reason a code
# span which opened on one source line and closed on the next is convertible at
# all (defect 2.2, second half): by the time it is reached, the wrap is gone.
js_md2wiki_inline() {
  printf '%s' "$1" | awk '
    BEGIN { BS = sprintf("%c", 92); SENT = sprintf("%c", 1) }
    # Inside a code span. Jira monospace is a DOUBLED-BRACE span and it ends at
    # the FIRST inner brace, so a span carrying a placeholder path template
    # renders with its markers visible -- which is not an error state Jira
    # reports, it is simply the wrong output (defect 2.3).
    #
    # The escape is built by CONCATENATION rather than by gsub. A backslash in a
    # gsub replacement is itself an escape introducer, so the number of
    # backslashes that survives depends on the awk implementation -- and the
    # first attempt here emitted two where one was meant.
    function inside(s,   res, c, i) {
      res = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        res = res ((c == "{" || c == "}") ? BS c : c)
      }
      return res
    }
    # Everything that is NOT inside a code span.
    # `**bold**` -> `*bold*`, because wiki bold is a SINGLE asterisk.
    function outside(s,   res, inner, st, len) {
      res = ""
      while (match(s, /\*\*[^*]+\*\*/)) {
        st = RSTART; len = RLENGTH
        inner = substr(s, st + 2, len - 4)
        res = res substr(s, 1, st - 1) "*" inner "*"
        s = substr(s, st + len)
      }
      s = res s; res = ""
      # `~~struck~~` -> `-struck-` (wiki strikethrough is a single hyphen pair).
      while (match(s, /~~[^~]+~~/)) {
        st = RSTART; len = RLENGTH
        inner = substr(s, st + 2, len - 4)
        res = res substr(s, 1, st - 1) "-" inner "-"
        s = substr(s, st + len)
      }
      return res s
    }
    # Longest run of ch in s -- 0 when ch does not occur at all. Pure.
    function maxrun(s, ch,   best, cur, i, c) {
      best = 0; cur = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == ch) { cur++; if (cur > best) best = cur } else cur = 0
      }
      return best
    }
    # ch repeated n times. Pure.
    function rep(ch, n,   res, i) {
      res = ""
      for (i = 1; i <= n; i++) res = res ch
      return res
    }
    {
      line = $0
      # Pass 0 -- DERIVE the delimiter from THIS line: a run of SENT one longer
      # than the longest run the line already carries. The tag namespace is then
      # exclusive BY CONSTRUCTION with nothing removed from the input, which is
      # the difference between this and a plain scrub of the sentinel -- measured,
      # a scrub renders a SENT b as ab, which is silent data loss (BTG-236 AC-8).
      D = rep(SENT, maxrun(line, SENT) + 1)
      # Pass 1 -- lift every code span out, leaving D <index> D in its slot and
      # holding the escaped body. Delimiting BOTH sides is what stops the tag for
      # span 1 false-matching inside the tag for span 11.
      #
      # RSTART/RLENGTH are GLOBAL, and outside() calls match() itself, so an index
      # is captured into a local BEFORE any call that can match() again. Reading
      # them afterwards consumed the inner match instead of this one and the loop
      # never advanced. Nothing in THIS loop calls outside() -- inside() never
      # matches -- but pass 2 below clobbers both globals, so the capture
      # discipline is kept here rather than left to depend on that.
      n = 0
      while (match(line, /`[^`]*`/)) {
        st = RSTART; len = RLENGTH
        n++
        spans[n] = inside(substr(line, st + 1, len - 2))
        line = substr(line, 1, st - 1) D n D substr(line, st + len)
      }
      # Pass 2 -- convert emphasis over the WHOLE line. outside() never learns
      # that code spans exist, so an emphasis pair that wraps or straddles one is
      # no longer torn across a fragment boundary and its markers are no longer
      # re-paired across a boundary the source never had (BTG-236).
      line = outside(line)
      # Pass 3 -- restore each held span, as wiki monospace, into its own slot.
      # index() plus substr(), NEVER gsub: a backslash or an ampersand in a gsub
      # replacement argument is treated specially, and a code span carries
      # arbitrary text.
      for (i = 1; i <= n; i++) {
        tag = D i D
        p = index(line, tag)
        if (p > 0)
          line = substr(line, 1, p - 1) "{{" spans[i] "}}" substr(line, p + length(tag))
      }
      printf "%s\n", line
    }
  '
}

# --------------------------------------------------------------------------
# Block classification -- what may NOT be swallowed by a paragraph
# --------------------------------------------------------------------------
# js_md2wiki_is_list <line>       -- 0 iff the line opens a list item.
# js_md2wiki_block_start <line>   -- 0 iff the line opens a NON-paragraph block.
#
# Paragraph unwrapping (defect 2.7) is only correct because it stops here. A
# joiner that did not know these kinds would fold a list, a table or a fence into
# the paragraph above it, which is a worse defect than the one being fixed.
# NOTE on the bracket expression below: the terminator set is spelled `[).]` and
# not `[.)]`. In a POSIX bracket expression `[.` OPENS a collating symbol, so the
# obvious spelling is a syntax error rather than "a dot or a close paren".
JS_MD2WIKI_LIST_RE='^([[:space:]]*)([-*+]|[0-9]+[).])[[:space:]]+(.*)$'

js_md2wiki_is_list() {
  [[ "$1" =~ $JS_MD2WIKI_LIST_RE ]]
}

js_md2wiki_block_start() {
  local line="$1"
  [[ -z "${line//[[:space:]]/}" ]] && return 0                 # blank
  [[ "$line" == '```'* ]] && return 0                          # fenced code
  [[ "$line" =~ ^\> ]] && return 0                             # blockquote
  [[ "$line" =~ ^\| ]] && return 0                             # table row
  [[ "$line" =~ ^#{1,6}[[:space:]] ]] && return 0              # heading
  js_md2wiki_is_list "$line" && return 0
  return 1
}

# --------------------------------------------------------------------------
# List items -- pass 3 (defect 2.2, first half)
# --------------------------------------------------------------------------
# js_md2wiki_list_item <marker-line> -- echo the wiki bullet for one ALREADY
# UNWRAPPED item. Jira wiki ends a list item at the newline, so an item that
# still spans two lines renders its continuation as body text OUTSIDE the bullet.
# Unwrapping is therefore done by the caller before this is reached.
#
# Nesting depth is taken from the source indent (two spaces per level), and the
# wiki marker is that depth repeated -- `*`/`**` for bullets, `#`/`##` for ordered
# items. A checklist marker is DROPPED rather than translated: wiki descriptions
# have no checkbox syntax, so `- [ ]` and `- [x]` both render as a plain bullet.
js_md2wiki_list_item() {
  local line="$1" indent body marker depth glyph
  [[ "$line" =~ $JS_MD2WIKI_LIST_RE ]] || { printf '%s' "$line"; return; }
  indent="${BASH_REMATCH[1]}"; marker="${BASH_REMATCH[2]}"; body="${BASH_REMATCH[3]}"
  depth=$(( ${#indent} / 2 + 1 ))
  (( depth > 6 )) && depth=6
  case "$marker" in
    [-*+]) glyph='*' ;;
    *)     glyph='#' ;;
  esac
  body="${body#'[ ] '}"; body="${body#'[x] '}"; body="${body#'[X] '}"
  printf '%s %s' "$(printf "%${depth}s" '' | tr ' ' "$glyph")" "$(js_md2wiki_inline "$body")"
}
