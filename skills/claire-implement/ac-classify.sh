#!/usr/bin/env bash
#
# ac-classify.sh -- deterministic verdict on a problem.md `## Acceptance
# Criteria` section: is it a usable behavioral contract, or is it still the
# template's placeholder scaffolding?
#
# Bounded context: CLAIRE framework governance / the ticket-lifecycle tooling.
# Sidecar of `/claire-implement` (`.claude/skills/claire-implement/ac-classify.sh`),
# invoked cross-command by the `claire-triage-agent` self-check and the
# `claire-implementer` role's Low-tier mirror. See archive/BTG-327/spec.md
# ("Proposed Design" -> Classifier) for the design rationale.
#
# Upstream inputs: a single problem.md path, supplied by the caller (the
# implement skill's Low-tier gate, the implementer role's direct-delegation
# mirror, or the triage self-check).
# Downstream effects: none. This script reads its argument and writes
# nothing -- callers act on its stdout/stderr/exit contract.
#
# Usage: ac-classify.sh <path-to-problem.md>
#
# stdout (exactly these three lines, in order, on exit 0 or 1; nothing on
# exit 2):
#   verdict=<real|mixed|placeholder-only|absent>
#   ac_items=<N>            # list items found in the Acceptance Criteria section
#   placeholder_items=<N>   # of those, template scaffolding
#
# stderr: on exit 1 or 2, exactly one line beginning `condition=<name>`,
# followed by a human-readable message naming the file.
#   exit 1 conditions: acclassify.verdict.placeholder_only | acclassify.verdict.absent
#   exit 2 conditions: acclassify.setup.usage | acclassify.setup.unreadable
#
# exit: 0 = real or mixed ; 1 = placeholder-only or absent ; 2 = usage or
#       setup failure (never a partial stdout on exit 2).
#
# THE RULE, stated once, here, and nowhere else (spec.md DEC-004; heading
# match widened at code-review cycle 1 / DEC-010, B-1/B-2; fence rule
# replaced and section summing changed to every match at code-review
# cycle 2 / DEC-017, B2-1/B2-2):
#   Fence:       a CommonMark-shaped fence, tracked across the WHOLE file (not
#                just inside the section), so a fenced quotation of the
#                heading (e.g. in a "## Description" section) never opens the
#                real section, and the real section's own fences are
#                correctly paired. A fence OPENS only on a line with up to 3
#                spaces of leading indent followed by either a run of 3+
#                backticks with NO further backtick later on the line (an
#                inline code span such as "``` `x` ```" is therefore never a
#                fence open), or a run of 3+ tildes (which may be followed by
#                anything). It CLOSES only on a bare run of the same
#                character, at least as long as the opening run, with up to 3
#                spaces of indent and only trailing whitespace after it.
#   Section:     the first UNFENCED line, matched case-insensitively, of the
#                form "## Acceptance Criteria" optionally followed by more
#                text after a word boundary (e.g. "## Acceptance criteria",
#                "## Acceptance Criteria (post-MVP)"; NOT "## Acceptance
#                Criteriaxyz"), up to the next unfenced ^## line or EOF. EVERY
#                unfenced line matching the heading reopens counting, and
#                items are SUMMED across every such section in the file, not
#                just the first (so a hand-authored heading inside a verbatim
#                Problem Description plus the template's own placeholder
#                section classifies `mixed`, never a first-match-only `real`).
#                Lines inside an HTML comment (<!-- ... -->) region are
#                skipped.
#   Item:        a line matching a list marker (-, *, +, or N./N)) at the
#                start after optional leading whitespace, with an optional
#                [ ]/[x]/[X] checkbox stripped. Blockquote lines and
#                continuation lines (no marker) are not items.
#   Placeholder: the trimmed item body begins with `{` and ends with `}`
#                (the js_fv_classify rule, restated rather than sourced, so
#                this gate never depends on the Jira adapter's sidecar being
#                installed).
#   Verdict:     no section or zero items -> absent; all items placeholder
#                -> placeholder-only; some placeholder, some not -> mixed;
#                none placeholder -> real.

set -u

usage_fail() {
  echo "condition=acclassify.setup.usage" >&2
  echo "Usage: $0 <path-to-problem.md>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage_fail

FILE="$1"

if [[ ! -r "$FILE" ]]; then
  echo "condition=acclassify.setup.unreadable" >&2
  echo "ac-classify: cannot read $FILE" >&2
  exit 2
fi

# Single awk pass: extract the Acceptance Criteria section (fence/comment
# aware), classify each item line, and print the two counts. Verdict is
# decided in bash from those two counts so the exit-code / condition mapping
# (which needs bash's exit semantics) lives in one place.
counts="$(awk '
  function is_ac_heading(l,    low) {
    low = tolower(l)
    return (low ~ /^##[[:space:]]+acceptance criteria([[:space:]]|$)/)
  }
  BEGIN { in_section = 0; in_fence = 0; in_comment = 0; ac_items = 0; ph_items = 0; fence_char = ""; fence_len = 0 }
  {
    line = $0
    sub(/\r$/, "", line)

    # Fence toggle is tracked across the WHOLE file, before any section
    # logic runs, so a fenced quotation of the heading (e.g. inside a
    # "## Description" section, earlier in the file) never opens the real
    # section, and the real section'"'"'s own fences stay correctly paired.
    # A fence line is a CommonMark-shaped fence only: up to 3 spaces of
    # indent, then either a run of 3+ backticks with no further backtick
    # later on the line, or a run of 3+ tildes. An inline code span (e.g.
    # BTG-200'"'"'s "  ``` `x` (y) ```);") has a backtick later on the line and
    # is therefore never an open. Closing requires a bare run of the same
    # character, at least as long as the opening run, up to 3 spaces of
    # indent, and only trailing whitespace after it.
    if (in_fence) {
      close_re = "^ {0,3}" (fence_char == "`" ? "`" : "~") "{" fence_len ",}[[:space:]]*$"
      if (line ~ close_re) { in_fence = 0; fence_char = ""; fence_len = 0 }
      next
    }

    if (match(line, /^ {0,3}`{3,}/)) {
      run = substr(line, RSTART, RLENGTH)
      rest = substr(line, RSTART + RLENGTH)
      gsub(/^ +/, "", run)
      if (index(rest, "`") == 0) {
        in_fence = 1; fence_char = "`"; fence_len = length(run)
        next
      }
      # A backtick later on the line: an inline span, not a fence open.
      # Fall through and treat this line as ordinary content.
    } else if (match(line, /^ {0,3}~{3,}/)) {
      run = substr(line, RSTART, RLENGTH)
      gsub(/^ +/, "", run)
      in_fence = 1; fence_char = "~"; fence_len = length(run)
      next
    }

    if (in_section && line ~ /^##[[:space:]]/ && !is_ac_heading(line)) {
      in_section = 0
    }

    if (!in_section) {
      if (is_ac_heading(line)) { in_section = 1 }
      next
    }

    # HTML comment region -- may open and close on the same or different lines.
    scan = line
    while (length(scan) > 0) {
      if (in_comment) {
        p = index(scan, "-->")
        if (p == 0) { scan = ""; break }
        scan = substr(scan, p + 3)
        in_comment = 0
      } else {
        p = index(scan, "<!--")
        if (p == 0) { break }
        pre = substr(scan, 1, p - 1)
        scan = substr(scan, p + 4)
        in_comment = 1
        # Only the pre-comment text on this line is live content.
        line = pre
      }
    }
    if (in_comment && index(line, "<!--") == 0) {
      # Entire physical line consumed by an open comment region.
      next
    }

    # List-marker item detection.
    if (match(line, /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+/)) {
      body = substr(line, RSTART + RLENGTH - 1 + 1)
      # Strip an optional checkbox marker.
      if (body ~ /^\[[ xX]\][[:space:]]+/) {
        sub(/^\[[ xX]\][[:space:]]+/, "", body)
      }
      # Trim leading/trailing whitespace.
      gsub(/^[[:space:]]+/, "", body)
      gsub(/[[:space:]]+$/, "", body)
      ac_items++
      if (body ~ /^\{.*\}$/) { ph_items++ }
    }
  }
  END { printf "%d %d\n", ac_items, ph_items }
' "$FILE")"

ac_items="${counts%% *}"
placeholder_items="${counts##* }"

if [[ "$ac_items" -eq 0 ]]; then
  verdict="absent"
elif [[ "$placeholder_items" -eq "$ac_items" ]]; then
  verdict="placeholder-only"
elif [[ "$placeholder_items" -eq 0 ]]; then
  verdict="real"
else
  verdict="mixed"
fi

echo "verdict=$verdict"
echo "ac_items=$ac_items"
echo "placeholder_items=$placeholder_items"

case "$verdict" in
  real|mixed)
    exit 0
    ;;
  placeholder-only)
    echo "condition=acclassify.verdict.placeholder_only" >&2
    echo "ac-classify: $FILE's Acceptance Criteria section is placeholder-only" >&2
    exit 1
    ;;
  absent)
    echo "condition=acclassify.verdict.absent" >&2
    echo "ac-classify: $FILE has no usable Acceptance Criteria section" >&2
    exit 1
    ;;
esac
