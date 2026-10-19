# upgrade-vocab-classify.awk -- line-by-line engine for upgrade-vocab-rules.sh's
# vocab_classify_file (spec.md D3). POSIX awk only (busybox-safe, II_CLAIRE-013):
# no \b, \<, \> or \y -- word boundaries are emulated with character-class
# lookarounds (ww_match / ww_gsub below), which mawk and busybox awk both run.
#
# Input: the file's raw bytes, one BEGIN-loaded flags (frozen_file, is_problem)
# plus the V4 exact-line data file. Output: the rewritten copy on stdout; the
# VOCAB_STATS / VOCAB_AMBIGUOUS report grammar on stderr (parsed by the caller),
# plus one additive "VOCAB_REWROTE <lineno>" record per rewritten line (BTG-334
# DEC-010 refinement 2), parsed by vocab_classify_file into VOCAB_REWROTE_LINES
# -- its only consumer is vocab_mark_residual's own recheck call
# (upgrade-vocab-rules.sh), which needs the recheck's rewritten line numbers to
# tell a leftover rewrite apart from an already-clean line. CRLF and a missing
# final newline are preserved per line (the caller trims the one trailing byte
# awk always adds when the source had no final newline).

BEGIN {
  split("Preconditions Rules Inputs Side-effects Mutations", PW, " ")
  split("State Constraints Triggers Outputs Updates", SW, " ")
  # D1's Singular column: the same five dimension words in singular form,
  # index-paired with their SCOUT singular counterpart. Checked everywhere PW
  # is checked (has_dim_word / V3) so a singular mention ("the PRISM Rule
  # dimension") is detected exactly like a plural one, never silently missed
  # (code-review B2).
  split("Precondition Rule Input Side-effect Mutation", PWS, " ")
  split("State Constraint Trigger Output Update", SWS, " ")
  n_pw = 5
  table_active = 0
  dim_field = 0
  in_elicited = 0
  n_rewritten = 0
  n_retained = 0
  n_ambiguous = 0
  n_v4 = 0
  if (v4file != "") {
    while ((getline oldl < v4file) > 0) {
      if ((getline newl < v4file) <= 0) break
      n_v4++
      v4old[n_v4] = oldl
      v4new[n_v4] = newl
    }
    close(v4file)
  }
}

# ww_match(str, word) -- whole-word, case-sensitive containment.
function ww_match(str, word) {
  return (str ~ ("(^|[^A-Za-z])" word "([^A-Za-z]|$)"))
}

# ww_gsub(str, old, new) -- whole-word, case-sensitive global replace. Advances
# past a non-word hit by one character so a later genuine word match is not lost.
function ww_gsub(str, old, new,    result, rest, idx, before, after, ok, oldlen) {
  result = ""; rest = str; oldlen = length(old)
  while (1) {
    idx = index(rest, old)
    if (idx == 0) { result = result rest; break }
    before = (idx == 1) ? "" : substr(rest, idx - 1, 1)
    after = substr(rest, idx + oldlen, 1)
    ok = 1
    if (before != "" && before ~ /[A-Za-z]/) ok = 0
    if (after != "" && after ~ /[A-Za-z]/) ok = 0
    if (ok) {
      result = result substr(rest, 1, idx - 1) new
      rest = substr(rest, idx + oldlen)
    } else {
      result = result substr(rest, 1, idx)
      rest = substr(rest, idx + 1)
    }
  }
  return result
}

function is_table_row(line) { return (line ~ /^[ \t]*\|.*\|[ \t]*$/) }

function is_separator_row(line,    t) {
  if (!is_table_row(line)) return 0
  t = line
  gsub(/[-:| \t]/, "", t)
  return (t == "" && line ~ /-/)
}

# dim_col_of(header) -- 1-based split() field index whose trimmed text is one of
# the three accepted spellings (spec.md D3 V3), or 0 if none matches.
function dim_col_of(header,    cells, nc, i, c) {
  nc = split(header, cells, "|")
  for (i = 1; i <= nc; i++) {
    c = cells[i]
    gsub(/^[ \t]+|[ \t]+$/, "", c)
    if (c == "Dimension" || c == "PRISM Dimension" || c == "PRISM Source") return i
  }
  return 0
}

# is_elicited_heading(line) -- BTG-334 AC-1 (c1-1): the Elicited Intent freeze
# heading, tolerant of trailing whitespace, any letter case and one trailing
# parenthetical suffix (decisions.md DEC-006). Other variants (an extra "#", a
# non-parenthetical suffix, a changed internal spelling) are deliberately NOT
# frozen -- spec.md AC-1 edge cases, Gate 1 OQ-4.
function is_elicited_heading(line) {
  return (tolower(line) ~ /^## elicited intent[ \t]*(\([^)]*\)[ \t]*)?$/)
}

# legacy_obs_value(trimmed) -- BTG-334 AC-2 (c1-12, DEC-003/DEC-004): classify
# a trimmed line as "" (not the legacy observability_prism_dimension key line
# at all), "empty" (the value is "" or nothing, optionally followed by a
# trailing comment) or "recorded" (any other value -- quoted, unquoted, or
# the single-quoted '' shape, which DEC-004/A-4 counts as recorded, the
# fail-safe direction). Strips one leading "#[ \t]*" before testing; the key
# must start the (possibly de-commented) line.
function legacy_obs_value(trimmed,    t) {
  t = trimmed
  sub(/^#[ \t]*/, "", t)
  if (t !~ /^observability_prism_dimension:/) return ""
  sub(/^observability_prism_dimension:/, "", t)
  if (t ~ /^[ \t]*""[ \t]*(#.*)?$/) return "empty"
  if (t ~ /^[ \t]*(#.*)?$/) return "empty"
  return "recorded"
}

# v6_convert(line) -- BTG-334 AC-2 (c1-12, DEC-005): convert every dimension
# word on a V6 line. A COMPLETE list -- the five plural PRISM words, each
# exactly once, any order, "|"-separated with any surrounding whitespace --
# becomes the canonical scout_value_list string (VOCAB_SCOUT_VALUE_LIST,
# same order the template uses). Any other spelling (a partial list, a
# duplicate, a singular word) converts word by word in place, same as the
# per-cell V3 conversion below. The five-alternation regex below is built
# from PW[] rather than spelled out literally, so it stays in step with
# BEGIN's split() if the word list is ever extended.
function v6_convert(line,    re, alt, i, pos, len, seg, cells, nc, w, seen, complete, out2) {
  alt = "(" PW[1]
  for (i = 2; i <= n_pw; i++) alt = alt "|" PW[i]
  alt = alt ")"
  # BTG-333 reconciliation, code-review C3/N5: the separator uses the
  # bracket-class [|] form (spec.md's own V6_RUN_RE sketch), never a
  # backslash-escaped pipe -- POSIX ERE leaves a backslash before a special
  # character unspecified, so a literal pipe belongs inside a bracket
  # expression for mawk/busybox portability (II_CLAIRE-013), not behind \.
  re = alt "[ \t]*[|][ \t]*" alt "[ \t]*[|][ \t]*" alt "[ \t]*[|][ \t]*" alt "[ \t]*[|][ \t]*" alt
  if (match(line, re)) {
    pos = RSTART; len = RLENGTH
    seg = substr(line, pos, len)
    nc = split(seg, cells, "|")
    complete = (nc == 5)
    if (complete) {
      delete seen
      for (i = 1; i <= 5; i++) {
        w = cells[i]
        gsub(/^[ \t]+|[ \t]+$/, "", w)
        if (w in seen) { complete = 0; break }
        seen[w] = 1
      }
    }
    if (complete) return substr(line, 1, pos - 1) scout_value_list substr(line, pos + len)
  }
  out2 = line
  for (i = 1; i <= n_pw; i++) out2 = ww_gsub(out2, PW[i], SW[i])
  for (i = 1; i <= n_pw; i++) out2 = ww_gsub(out2, PWS[i], SWS[i])
  return out2
}

function acronym_only_suggestion(line) { return ww_gsub(line, "PRISM", "SCOUT") }

# v9_suggestion(line) -- BTG-334 AC-3 (c2-10): the V9 conflict suggestion is
# the acronym-only swap PLUS every retired prism-reference.md path renamed to
# scout-reference.md. acronym_only_suggestion itself stays byte-identical
# (spec.md DEC-010 refinement 1): the OS-4.2 fixture patches it by exact text
# (ci-templates/scripts/tests/btg-332-lib/fixtures.sh fx_mk_patched_engine
# "noacronym" mode).
function v9_suggestion(line,    s) {
  s = acronym_only_suggestion(line)
  gsub(/prism-reference\.md/, "scout-reference.md", s)
  return s
}

function has_dim_word(line,    i) {
  for (i = 1; i <= n_pw; i++) if (ww_match(line, PW[i])) return 1
  for (i = 1; i <= n_pw; i++) if (ww_match(line, PWS[i])) return 1
  return 0
}

{
  raw = $0
  cr = ""
  if (raw ~ /\r$/) { cr = "\r"; sub(/\r$/, "", raw) }
  lineno = NR
  line = raw
  frozen_line = 0
  specific_shape = 0
  rewritten_line = 0
  out = line

  # V0 -- file-level and region-level freezes.
  if (frozen_file) {
    frozen_line = 1
  } else if (is_problem && is_elicited_heading(line)) {
    in_elicited = 1; frozen_line = 1
  } else if (is_problem && in_elicited && line ~ /^## /) {
    in_elicited = 0
  } else if (is_problem && in_elicited) {
    frozen_line = 1
  }

  # V0 -- specific recorded-data line shapes, regardless of file/region. These
  # always count as retained even when the shape's own casing (the snake_case
  # key) never spells the acronym in uppercase.
  if (!frozen_line) {
    trimmed = line
    gsub(/^[ \t]+/, "", trimmed)
    if (legacy_obs_value(trimmed) == "recorded") {
      frozen_line = 1; specific_shape = 1
    } else if (line ~ /^[ \t]+effort:/ && trimmed !~ /^#/ && index(line, "PRISM") > 0) {
      frozen_line = 1; specific_shape = 1
    }
  }

  if (frozen_line) {
    if (specific_shape || index(line, "PRISM") > 0) n_retained++
    print raw cr
    next
  }

  matched = 0

  # V1 -- headings naming the tool. Skipped when the line ALSO carries a
  # dimension word (either form): that combination is not this exact heading
  # shape alone, and blindly replacing the acronym would silently produce
  # wrong content the residue gate cannot see (code-review B2). Left
  # unmatched, it falls through to the V8/V9 block below, which already
  # detects an acronym-plus-dimension-word line and marks it ambiguous.
  if (!matched && !has_dim_word(line) && (index(line, "PRISM Analysis") > 0 || index(line, "PRISM Decomposition") > 0 || index(line, "PRISM-to-BDD Mapping") > 0)) {
    out = ww_gsub(line, "PRISM", "SCOUT")
    matched = 1; rewritten_line = 1
  }

  # V5 -- legacy Zachman mislabel.
  if (!matched && index(line, "PRISM Who/People") > 0) {
    out = line; sub(/PRISM Who\/People/, "Zachman Who/People", out)
    matched = 1; rewritten_line = 1
  }
  if (!matched && index(line, "PRISM Why/Motivation") > 0) {
    out = line; sub(/PRISM Why\/Motivation/, "Zachman Why/Motivation", out)
    matched = 1; rewritten_line = 1
  }

  # V6 -- the legacy dimension key line, commented or not (V0 above already
  # took every RECORDED-value shape, quoted or unquoted -- BTG-334 AC-2,
  # DEC-003/DEC-004). Guard widened from "commented + exact current list" to
  # "any empty-value shape" via legacy_obs_value; the value-list conversion
  # (canonical order for a complete list, word-by-word otherwise) is
  # v6_convert (DEC-005).
  if (!matched && legacy_obs_value(trimmed) == "empty") {
    out = line
    sub(/observability_prism_dimension/, new_key, out)
    out = v6_convert(out)
    matched = 1; rewritten_line = 1
  }
  if (!matched && trimmed ~ /^#/ && index(line, "(e.g. \"PRISM + facets\")") > 0) {
    out = line
    sub(/\(e\.g\. "PRISM \+ facets"\)/, "(e.g. \"SCOUT + facets\")", out)
    matched = 1; rewritten_line = 1
  }

  # V3 -- dimension-table columns. Table-state bookkeeping runs unconditionally
  # so a header row still opens the window even when V1/V5-8 also fire on it.
  # Ordered BEFORE V7 (code-review cycle 2 N4): V7's path-rename now fires
  # unconditionally on a bare dimension word (see below), and a dimension-
  # table DATA row very often carries both the dimension word (in the
  # Dimension column) and the path (in another column, e.g. Details) on the
  # SAME line -- if V7 ran first it would claim the whole row for the path
  # rename alone and the dimension CELL would never reach its SCOUT relabel.
  # V3 claims such a row first, and (N4) now also renames the path if it
  # appears in a different cell of that same row; only a row V3 did NOT
  # rewrite (no dimension word in the dimension column) falls through to V7.
  if (is_separator_row(line)) {
    dim_field = dim_col_of(prev_line)
    table_active = (dim_field > 0)
  } else if (!is_table_row(line)) {
    table_active = 0
  } else if (!matched && table_active) {
    nc = split(line, cells, "|")
    if (dim_field >= 1 && dim_field <= nc && has_dim_word(cells[dim_field])) {
      newcell = cells[dim_field]
      for (i = 1; i <= n_pw; i++) newcell = ww_gsub(newcell, PW[i], SW[i])
      for (i = 1; i <= n_pw; i++) newcell = ww_gsub(newcell, PWS[i], SWS[i])
      if (newcell != cells[dim_field]) {
        cells[dim_field] = newcell
        rebuilt = cells[1]
        for (i = 2; i <= nc; i++) rebuilt = rebuilt "|" cells[i]
        # code-review cycle 2 N4: the reference path may live in a DIFFERENT
        # cell of the same row (e.g. a "Details" column) -- V3 only touched
        # the dimension cell above, so the path was left unrenamed. Same
        # acronym-co-occurrence guard as V7: only when no bare acronym is
        # present elsewhere in the rebuilt row.
        if (index(rebuilt, "prism-reference.md") > 0 && !ww_match(rebuilt, "PRISM")) {
          gsub(/prism-reference\.md/, "scout-reference.md", rebuilt)
        }
        out = rebuilt
        matched = 1; rewritten_line = 1
      }
    }
  }
  prev_line = line

  # V7 -- the reference path (lowercase, never caught by the acronym checks).
  # The path rename always applies when the path token is present (code-
  # review cycle 2 N4): a co-occurring dimension word alone no longer
  # suppresses it -- "Rules" and "prism-reference.md" are unrelated tokens on
  # the same line, and leaving the path unrenamed just because the line also
  # happens to mention a dimension word left prism-reference.md in place with
  # no rewrite, no conflict and no report (demonstrated: 18 archive lines of
  # this shape). Only a co-occurring BARE UPPERCASE ACRONYM routes the whole
  # line to the V8/V9 ambiguous path instead (left unmatched here, exactly as
  # before) -- a human resolves the acronym wording together with the path
  # rename in that case (code-review B2's original reasoning, now scoped to
  # the acronym alone rather than any dimension word). Ordered AFTER V3 (see
  # above) so an active dimension-table row is relabeled by V3 first.
  if (!matched && index(line, "prism-reference.md") > 0 && !(has_dim_word(line) && ww_match(line, "PRISM"))) {
    out = line
    gsub(/prism-reference\.md/, "scout-reference.md", out)
    if (ww_match(out, "PRISM")) out = ww_gsub(out, "PRISM", "SCOUT")
    matched = 1; rewritten_line = 1
  }
  # else (has_dim_word && bare acronym): fall through unmatched -- V8/V9
  # below marks the whole line ambiguous.

  # V4 -- exact historical specs/TEMPLATE/* lines.
  if (!matched) {
    for (i = 1; i <= n_v4; i++) {
      if (line == v4old[i]) { out = v4new[i]; matched = 1; rewritten_line = 1; break }
    }
  }

  # V8 / V9 -- the acronym, alone or beside a dimension word.
  if (!matched && ww_match(line, "PRISM")) {
    if (has_dim_word(line)) {
      n_ambiguous++
      suggestion = v9_suggestion(line)
      print "VOCAB_AMBIGUOUS " lineno "\t" suggestion > "/dev/stderr"
      print "<<<<<<< theirs"
      print raw cr
      print "======="
      print suggestion
      print ">>>>>>> scout-suggestion"
      prev_line = line
      next
    } else {
      out = acronym_only_suggestion(line)
      matched = 1; rewritten_line = 1
    }
  }

  if (rewritten_line) {
    n_rewritten++
    print "VOCAB_REWROTE " lineno > "/dev/stderr"
  }
  print out cr
}

END {
  print "VOCAB_STATS VOCAB_REWRITTEN=" n_rewritten " VOCAB_RETAINED=" n_retained " VOCAB_AMBIGUOUS=" n_ambiguous > "/dev/stderr"
}
