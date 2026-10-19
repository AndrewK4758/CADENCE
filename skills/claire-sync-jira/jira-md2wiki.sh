#!/usr/bin/env bash
#
# jira-md2wiki.sh -- the deterministic Markdown-to-Jira-wiki FILTER (BTG-205).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: Jira Server/DC's REST v2
# `description` field renders **wiki markup** natively and converts NOTHING on the
# way in. Any Markdown construct that is not also valid wiki renders literally, or
# as something else entirely -- and the PUT still returns 2xx, so the defect is
# visible only to a human reading the issue.
#
# Upstream: invoked by the /claire-sync-jira orchestrator INSIDE the agent-performed
#   `render_ticket_template` (jira-server-orchestration.md section 4), once per
#   extracted Markdown fragment, BEFORE substitution into the wiki template body.
# Downstream: nothing. Its stdout becomes one `{{token}}` value; no REST call, no
#   file, no repository read.
# Spec: archive/BTG-205/spec.md (AC-2, AC-3) ; decisions.md DEC-001/DEC-002/DEC-003 ;
#   the contract table in .claude/skills/claire-sync-jira/jira-server-scripts-render.md.
#
# THE DIVISION OF LABOUR IT IMPLEMENTS (DEC-001). Content authorship -- which
# `problem.md` section fills which token, what is carried, what counts as absent --
# stays MODEL-PERFORMED and is not this script's business. Markup conversion --
# the mechanical transformation of an already-selected fragment -- is deterministic
# and lives here. BTG-150's "there is no executable renderer anywhere in this tree"
# is superseded for that step ALONE; nothing here licenses a general-purpose renderer.
#
# Contract (three channels, DEC-001 of BTG-075):
#   args   : [--functional-validation]
#   stdin  : one Markdown fragment
#   stdout : the converted wiki markup -- a DOCUMENT, not `key=value` lines. This
#            is the one script in the set whose stdout is prose, because it is a
#            filter; said explicitly so a reader is not surprised.
#   stderr : syncjs.render.* reported conditions
#   exit   : 0 converted / 1 a pass could not complete / 2 usage
#            (3 and 4 are unreachable by construction -- no transport, no config)
#
# PURITY is the property every fixture rests on. This script reads no credential,
# no configuration, no repository file and no environment variable; it opens no
# socket. Its output is a total function of stdin plus its one flag. That is also
# why it does NOT source jira-lib.sh: that library pulls in jira-rest.sh and
# jira-meta.sh transitively, which would put the transport and the owned-data
# reader in this process for the sake of two three-line channel helpers. The
# helpers are declared locally instead, using the same names and the same exit
# vocabulary (BTG-205 DEC-013).

set -u

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-md2wiki-lib.sh"

JS_EXIT_OK=0
JS_EXIT_FAIL=1
JS_EXIT_USAGE=2

# js_report <syncjs.condition> [detail...] -- one audit line on STDERR.
js_report() {
  local condition="$1"; shift
  printf '%s: %s\n' "$condition" "$*" >&2
}

# --------------------------------------------------------------------------
# Block segmentation -- pass 1, on which every later pass is scoped
# --------------------------------------------------------------------------
# js_md2wiki_blocks <text> -- echo the converted body, or return 1 when a block
# cannot be segmented at all.
#
# FENCED CODE IS NEVER TRANSFORMED. Its content is carried through byte for byte
# and only its delimiters are converted, because a code block is the one place in
# a description where a Markdown-looking construct is meant to be read literally.
#
# An UNTERMINATED fence returns 1 rather than guessing where the block ends.
# Guessing would emit a plausible-looking partial render, and a partial render is
# exactly the output that gets projected as though it were correct -- the failure
# mode this whole ticket exists to remove.
js_md2wiki_blocks() {
  local text="$1"
  [[ -n "$text" ]] || return 0
  local -a lines=() out=() body=()
  local -a quoted=()
  local i=0 n line lang closed item para inner
  mapfile -t lines <<<"$text"
  n=${#lines[@]}
  while (( i < n )); do
    line="${lines[i]}"
    if [[ "$line" == '```'* ]]; then
      lang="${line#'```'}"
      i=$((i + 1)); body=(); closed=no
      while (( i < n )); do
        if [[ "${lines[i]}" == '```'* ]]; then closed=yes; i=$((i + 1)); break; fi
        body+=("${lines[i]}"); i=$((i + 1))
      done
      [[ "$closed" == yes ]] || return 1
      if [[ -n "$lang" ]]; then out+=("{code:$lang}"); else out+=("{code}"); fi
      (( ${#body[@]} )) && out+=("${body[@]}")
      out+=("{code}")
    elif [[ -z "${line//[[:space:]]/}" ]]; then
      out+=("")
      i=$((i + 1))
    elif [[ "$line" =~ ^(#{1,6})[[:space:]]+(.*)$ ]]; then
      # A heading is its own block. ticket_TEMPLATE.md's *Rendering rules*
      # mandate `#`/`##` -> `h1.`/`h2.`, and its *Elicited Intent sub-structure*
      # rule mandates `### <name>` -> `h3. <name>`; both are the same rule at a
      # different depth.
      out+=("h${#BASH_REMATCH[1]}. $(js_md2wiki_inline "${BASH_REMATCH[2]}")")
      i=$((i + 1))
    elif [[ "$line" =~ ^\| ]]; then
      # One table. Jira wiki marks header cells with DOUBLED pipes and has NO
      # separator row at all, so a Markdown table sent verbatim emits a literal
      # junk row of dashes and leaves its headers unbolded (defect 2.5).
      #
      # The header is recognised STRUCTURALLY -- by the separator row that
      # follows it, alignment colons and all -- never by position. A table with
      # no separator row has no header to promote, and every row stays a data
      # row rather than one being guessed at.
      body=()
      while (( i < n )) && [[ "${lines[i]}" =~ ^\| ]]; do
        body+=("${lines[i]}"); i=$((i + 1))
      done
      if (( ${#body[@]} > 1 )) && [[ "${body[1]}" =~ ^\|[[:space:]:|-]*-[[:space:]:|-]*\|[[:space:]]*$ ]]; then
        out+=("$(js_md2wiki_inline "${body[0]}" | sed -e 's/|/||/g')")
        body=("${body[@]:2}")
      fi
      if (( ${#body[@]} )); then
        for item in "${body[@]}"; do out+=("$(js_md2wiki_inline "$item")"); done
      fi
    elif [[ "$line" =~ ^\> ]]; then
      # One blockquote run: the OPENER plus every CONTIGUOUS continuation line.
      # Defect 2.1 is that a renderer stripping only the opener strands the
      # answer body in the description as loose prose, so the run is taken whole
      # and the decision -- scaffolding or content -- is made once, for the run.
      body=();
      while (( i < n )) && [[ "${lines[i]}" =~ ^\> ]]; do
        body+=("${lines[i]}"); i=$((i + 1))
      done
      if [[ "${body[0]}" =~ ^\>[[:space:]]*\*\*Probe:\*\* ]]; then
        continue                       # authoring scaffolding: the whole run goes
      fi
      # Content the author meant to keep quoted. Jira wiki has no Markdown
      # blockquote syntax and renders the marker LITERALLY, so the markers are
      # removed and the body is wrapped in the wiki quote macro (defect 2.6).
      #
      # Conversion then RECURSES on the inner text, which is what preserves bold,
      # monospace and table conversion inside a quote. It terminates because the
      # prefix is removed BEFORE the recursive call, so the inner text is
      # strictly shorter and can never re-enter this branch on the same lines.
      quoted=()
      for item in "${body[@]}"; do
        item="${item#>}"; quoted+=("${item# }")
      done
      out+=("{quote}")
      if (( ${#quoted[@]} )); then
        inner="$(js_md2wiki_blocks "$(printf '%s\n' "${quoted[@]}")")" || return 1
        [[ -n "$inner" ]] && out+=("$inner")
      fi
      out+=("{quote}")
    elif js_md2wiki_is_list "$line"; then
      # One list block: each item accumulates its own continuation lines, so the
      # item reaches the renderer already on one line.
      item="$line"; i=$((i + 1))
      while (( i < n )); do
        line="${lines[i]}"
        [[ -z "${line//[[:space:]]/}" ]] && break
        if js_md2wiki_is_list "$line"; then
          out+=("$(js_md2wiki_list_item "$item")"); item="$line"; i=$((i + 1)); continue
        fi
        js_md2wiki_block_start "$line" && break
        item="$item ${line#"${line%%[![:space:]]*}"}"; i=$((i + 1))
      done
      out+=("$(js_md2wiki_list_item "$item")")
    else
      # A paragraph: joined onto ONE line, because Jira wiki renders each source
      # newline inside a paragraph as a hard line break (defect 2.7).
      para="${line#"${line%%[![:space:]]*}"}"; i=$((i + 1))
      while (( i < n )); do
        js_md2wiki_block_start "${lines[i]}" && break
        para="$para ${lines[i]#"${lines[i]%%[![:space:]]*}"}"; i=$((i + 1))
      done
      out+=("$(js_md2wiki_inline "$para")")
    fi
  done
  (( ${#out[@]} )) && printf '%s\n' "${out[@]}"
  return 0
}

# --------------------------------------------------------------------------
# The pass pipeline
# --------------------------------------------------------------------------
# js_md2wiki_render <mode> <markdown> -- echo the converted wiki markup.
# Returns non-zero when a pass cannot complete; the caller emits nothing on
# stdout in that case.
js_md2wiki_render() {
  local mode="$1" text="$2" body
  text="$(js_md2wiki_strip_comments "$text")"
  # The Functional Validation guard (defect 2.4) classifies BEFORE the passes
  # run, because its answer may be that none of them apply. It is inside the
  # deterministic step by DEC-003's total-function test: ticket_TEMPLATE.md
  # already states the rule completely and in both polarities, so nothing is left
  # to judgement -- and a rule that is executed cannot be misread.
  if [[ "$mode" == functional-validation ]] && [[ "$(js_fv_classify "$text")" == absent ]]; then
    printf '%s' "$JS_MD2WIKI_NOT_SPECIFIED"
    return 0
  fi
  body="$(js_md2wiki_blocks "$text")" || return 1
  # Leading and trailing blank lines are TRIMMED. Stripping a probe block that
  # opened a section legitimately leaves one behind, and a token value that opens
  # with a blank line pushes the whole section down in the rendered issue.
  body="$(printf '%s' "$body" | sed -e '/./,$!d')"
  printf '%s' "$body" | sed -e ':a' -e '/^\n*$/{$d;N;};/\n$/ba'
}

MODE=prose
while [[ $# -gt 0 ]]; do
  case "$1" in
    --functional-validation) MODE=functional-validation; shift ;;
    *) js_report syncjs.render.usage "unknown argument: $1 -- jira-md2wiki.sh takes stdin and at most --functional-validation"
       exit "$JS_EXIT_USAGE" ;;
  esac
done

INPUT="$(cat)"

# The whole conversion is buffered and printed only on success. A pass that
# cannot complete must leave stdout EMPTY, because a partial render is the one
# output that would be projected as though it were correct (seam
# syncjs.render.md2wiki_failed).
if ! OUTPUT="$(js_md2wiki_render "$MODE" "$INPUT")"; then
  js_report syncjs.render.md2wiki_failed \
    "a conversion pass could not complete over its input -- emitting NOTHING on stdout, so no partial render can be projected"
  exit "$JS_EXIT_FAIL"
fi

# A fragment that converts to nothing -- a section holding only authoring
# scaffolding, say -- emits NOTHING, not a bare newline. The caller applies the
# template's *If missing* rule to an empty token value, and a lone newline would
# read as content to it.
[[ -n "$OUTPUT" ]] && printf '%s\n' "$OUTPUT"
exit "$JS_EXIT_OK"
