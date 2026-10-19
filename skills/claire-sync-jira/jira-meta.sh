#!/usr/bin/env bash
#
# jira-meta.sh -- the OWNED-DATA half of the /claire-sync-jira shared library.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: `metadata.yaml` is the SOURCE
# OF TRUTH and Jira is the projection. This half READS it and never writes it
# (AC-6) -- no operation script may reach past these helpers into the raw file.
#
# SOURCED by jira-lib.sh, never on its own: it depends on the exit-code
# vocabulary and the reporters defined there. It was split out when the combined
# library reached the 400-line DX ceiling -- the seam is clean (owned data vs
# config/channels) and NO call site changed, because every script still sources
# jira-lib.sh alone, exactly as the earlier jira-rest.sh split.
#
# Contracts: jira-server-scripts.md sections 1-4.

# --------------------------------------------------------------------------
# Owned data -- metadata.yaml is READ here and never written (AC-6)
# --------------------------------------------------------------------------

# js_metadata_path <id> -- specs/<id>/metadata.yaml, else the archived copy.
js_metadata_path() {
  local id="$1" root="${CLAIRE_REPO_ROOT:-.}"
  if [[ -f "$root/specs/$id/metadata.yaml" ]]; then
    printf '%s\n' "$root/specs/$id/metadata.yaml"
  elif [[ -f "$root/archive/$id/metadata.yaml" ]]; then
    printf '%s\n' "$root/archive/$id/metadata.yaml"
  else
    return 1
  fi
}

# js_metadata_load <id> -- read the ticket's metadata into JS_METADATA_JSON (path
# into JS_METADATA_PATH). BTG-068, re-homed: a DEGENERATE parse (absent, empty,
# comment-only, malformed, non-object) implies an UPSTREAM failure, not an empty
# ticket, and HALTS with `syncjs.metadata.degenerate` rather than letting a caller
# no-op a projection. The halt happens HERE, not as a returned status, so a caller
# cannot proceed by forgetting to check. The YAML subset is the one
# `specs/*/metadata.yaml` uses; anything else is a parse failure. STDLIB only.
js_metadata_load() {
  local id="$1" path json
  if ! path="$(js_metadata_path "$id")"; then
    js_halt "$JS_EXIT_FAIL" syncjs.metadata.degenerate \
      "$id metadata.yaml not found under \${CLAIRE_REPO_ROOT:-.}/specs or /claire-archive -- refusing to proceed on absent owned data"
  fi
  if ! json="$(python3 - "$path" 2>&1 <<'PY'
import json, re, sys

SCALAR = re.compile(r'^(?P<key>[A-Za-z_][A-Za-z0-9_]*):(?P<rest>.*)$')
ITEM   = re.compile(r'^-\s+(?P<rest>.*)$')

def flow_seq(raw):
    """Parse a FLOW-STYLE (inline) sequence -- `[]`, `["A", "B"]`, `['A','B']`.

    This is the form `/claire-elicit` writes when it decomposes a ticket
    (artifacts/commands/claire-elicit.md: "append `decomposed_into: [{ids}]`"), and the
    form real archived data carries (archive/PI-008/metadata.yaml:63,
    archive/BTG-016/metadata.yaml:76). Read as a SCALAR STRING it made the
    umbrella branch iterate zero children AFTER it had already re-typed and
    renamed the issue -- a partially-applied mutation reported as success.

    Scanned rather than split so a quoted item may contain `,`, `#`, `[` or `]`,
    and so the text after the closing bracket (a trailing comment) is dropped
    without a `#` split that would corrupt those items.
    """
    items, buf, quoted, quote, closed, i = [], '', False, None, False, 1
    while i < len(raw):
        ch = raw[i]
        if quote is not None:
            if ch == quote:
                quote = None
            else:
                buf += ch
        elif ch in ('"', "'"):
            quote, quoted = ch, True
        elif ch == ']':
            closed = True
            break
        elif ch == ',':
            items.append((buf.strip(), quoted))
            buf, quoted = '', False
        else:
            buf += ch
        i += 1
    if not closed:
        raise ValueError("unterminated flow sequence: %r" % raw)
    items.append((buf.strip(), quoted))
    # An unquoted empty item is separator noise (`[]`, a trailing comma); a
    # QUOTED empty item is a real empty string.
    return [text for text, was_quoted in items if was_quoted or text != '']


# G3's table (BTG-114): a backslash in a DOUBLE-quoted scalar consumes the
# next char; a control-char escape translates, else it falls through as-is.
ESC = {'n': '\n', 't': '\t', 'r': '\r', '0': '\x00', 'a': '\x07',
       'b': '\x08', 'f': '\x0c', 'v': '\x0b', 'e': '\x1b'}


def quoted(raw):
    """(VALUE, TAIL) of a quoted scalar, or None when the delimiter never closes.

    YAML escapes a quote inside a quoted scalar by DOUBLING it, so the first
    repeat of the delimiter does not necessarily end the string: `'it''s'` is
    `it's`, and taking the first match yielded `it` -- silently truncating a
    value mid-word with no error anywhere.

    Lifted out of scalar() so the FOLD below and the parse share ONE answer to
    "where does this quote end" -- two copies is how a check drifts from the
    grammar it approximates (PROD_CLAIRE-012's class).

    G2/G3/G4 (BTG-114): single-quoted backslash is literal (falls through);
    double-quoted consumes the next char via ESC; \\x/\\u/\\U refuse by name."""
    quote, buf, i = raw[0], '', 1
    while i < len(raw):
        ch = raw[i]
        if ch == quote:
            if i + 1 < len(raw) and raw[i + 1] == quote:
                buf += quote
                i += 2
                continue
            return buf, raw[i + 1:]
        if quote == '"' and ch == '\\' and i + 1 < len(raw):
            nxt = raw[i + 1]
            if nxt in ('x', 'u', 'U'):
                raise ValueError(
                    "a numeric escape (\\%s) is refused by name, not guessed: %r" % (nxt, raw))
            buf += ESC.get(nxt, nxt)
            i += 2
            continue
        buf += ch
        i += 1
    return None


def value_part(line):
    """The VALUE REGION of one physical line, decided exactly as the main loop
    decides it: `k: v` -> v, `- k: v` -> v, `- item` -> item; None for a blank
    line, a comment line, or a line the loop does not recognize. Deciding it any
    other way is what would let an apostrophe in prose or in a comment open a
    scalar (`don't`, `the reader's own`)."""
    if not line.strip() or line.lstrip().startswith('#'):
        return None
    body = line.strip()
    if len(line) == len(line.lstrip()):
        m = SCALAR.match(body)
        return m.group('rest').strip() if m else None
    m = ITEM.match(body)
    if m:
        rest = m.group('rest')
        inner = SCALAR.match(rest)
        return (inner.group('rest') if inner else rest).strip()
    inner = SCALAR.match(body)
    return inner.group('rest').strip() if inner else None


def opens_quote(text):
    """True iff text's value region STARTS with a quote that does not close in
    it. First character only, and only in a value position (DEC-008: quoted
    scalars fold; flow sequences, block scalars and plain scalars do not).
    BTG-114: quoted() can RAISE (a refused G4 escape); caught here so it
    surfaces at scalar()'s later call instead, WITH lineno/key context."""
    val = value_part(text)
    if not val or val[0] not in ('"', "'"):
        return False
    try:
        return quoted(val) is None
    except ValueError:
        return False


def fold(lines):
    """[(opening_lineno, logical_line, was_folded), ...]. While the accumulated
    text still opens a quote and lines remain, absorb the next physical line. One
    space per break, the preceding line's trailing and the continuation's leading
    whitespace dropped -- YAML flow-scalar folding, so this reader and
    yaml.safe_load agree on the value. The lineno is where the quote OPENED:
    after a fold, the line the scan gave up on is not an actionable location."""
    out, i, n = [], 0, len(lines)
    while i < n:
        text, opened = lines[i], i + 1
        while opens_quote(text) and i + 1 < n:
            i += 1
            text = text.rstrip() + ' ' + lines[i].strip()
        out.append((opened, text, i + 1 != opened))
        i += 1
    return out


def scalar(raw, item=False):
    raw = raw.strip()
    if not raw:
        return ""
    if raw[0] == '[':
        return flow_seq(raw)
    if not item and re.match(r'^[|>][0-9+-]*\s*(#.*)?$', raw):
        # A block-scalar HEADER, declined here rather than downstream (DEC-008):
        # left alone the indicator parses as the one-character value `|`, so the
        # key carries an INVENTED value and the halt arrives from a body line at
        # the wrong location -- or, if a body line carries a colon, never at all.
        #
        # `item=True` (a `- >` list item) is deliberately EXEMPT. A bare
        # indicator with no body is not a block scalar, and that spelling is
        # already owned and refused, by name and with its siblings preserved, at
        # the link module's boundary (BTG-108 S-2.11/S-2.12). Halting the whole
        # load would replace a per-item refusal with a per-file one.
        raise ValueError(
            "a block scalar (| or >) is not supported by this reader, and its "
            "indicator is not a value: %r" % raw)
    if raw[0] in ('"', "'"):
        closed = quoted(raw)
        if closed is None:
            raise ValueError("unterminated quote: %r" % raw)
        val, tail = closed
        # Once scalars FOLD, an unclosed quote runs on until it meets some LATER
        # key's quote and closes there: `title: "opens here` above
        # `tier: "Medium"` bound title to `opens here tier: `, dropped tier
        # entirely, and exited 0. So nothing but whitespace or a comment may
        # follow a closed quoted scalar, on EVERY line (G5; JI-3; Behavior 5) --
        # BTG-114 drops the former FOLDED gate now that G3 parses the escape it
        # existed to avoid rejecting (PI-060); this also closes member 7 (F-11).
        tail = tail.strip()
        if tail and not tail.startswith('#'):
            raise ValueError(
                "text after a closed quoted scalar -- everything after it on "
                "the line is wrong: %r" % raw)
        return val
    raw = raw.split('#', 1)[0].strip()
    # A bare YAML null is a NULL, not the four-character string "null". Returning
    # the string made `worklog_watermark_at: null` read as a populated scalar --
    # and because the watermark comparison is lexical, that one value suppressed
    # every 20xx entry forever while the run reported "up to date".
    if raw in ('null', '~', 'Null', 'NULL'):
        return None
    return raw

FOLDED = False                              # did the logical line being parsed absorb continuations?
out, key, cur_list, cur_map = {}, None, None, None
cur_map_indent = None                       # indent at which the open `- k: v` map's keys sit
nested_indent = None                        # indent of the open one-level nested map's keys


def bind_nested(container, name, rest):
    """Bind one indented `name: rest` under an open block-map.

    An EMPTY value opens a nested LIST and makes it the live append target --
    a nested key whose value is a list is the shape the linking lineage reads
    (`related_tickets:` with per-relation buckets beneath it), and appending to
    an unset target is what crashed the parser on a well-formed file.
    """
    global cur_list, cur_map, cur_map_indent, nested_indent
    cur_map = None
    cur_map_indent = None
    nested_indent = None
    if rest.strip() and not rest.strip().startswith('#'):
        container[name] = scalar(rest)
        cur_list = None
    else:
        cur_list = []
        container[name] = cur_list


def elide(text, cap=120):
    """One line, whitespace collapsed, capped. An unterminated quote absorbs
    everything after it, so an unelided diagnostic prints the rest of the FILE
    back -- no more actionable than the traceback it replaces (DEC-002)."""
    text = ' '.join(str(text).split())
    return text if len(text) <= cap else text[:cap] + ' ...[truncated]'


lineno, line = 0, ''
try:
    for lineno, line, FOLDED in fold(open(sys.argv[1], encoding='utf-8').read().splitlines()):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip())
        body = line.strip()
        if indent == 0:
            m = SCALAR.match(body)
            if not m:
                raise ValueError("unparsable top-level line: %r" % line)
            key = m.group('key')
            cur_map = None
            cur_map_indent = None
            rest = m.group('rest')
            if rest.strip() and not rest.strip().startswith('#'):
                out[key] = scalar(rest)
                cur_list = None
            else:
                # An empty value opens a BLOCK whose shape the next line decides: a
                # `- ` line makes it a list, an indented `k: v` line makes it a MAP.
                # The keyed shape is real repo data (`related_tickets:` with
                # `originating: ORD-39` beneath it), and rejecting it diagnosed a
                # well-formed file as degenerate.
                cur_list = []
                cur_map = None
                out[key] = cur_list
            continue
        if key is None:
            raise ValueError("indented line before any key: %r" % line)
        m = ITEM.match(body)
        if m:                                   # a list item
            if cur_list is None:
                raise ValueError("list item with no open list: %r" % line)
            rest = m.group('rest')
            inner = SCALAR.match(rest)
            if inner:                           # `- k: v` -> open a new map item
                cur_map = {inner.group('key'): scalar(inner.group('rest'))}
                # its continuation keys sit at the indent of `k` inside `- k:`
                cur_map_indent = indent + (len(body) - len(rest))
                cur_list.append(cur_map)
            else:
                cur_list.append(scalar(rest, item=True))
                cur_map = None
                cur_map_indent = None
            continue
        inner = SCALAR.match(body)
        # A key at or beyond the open map item's key indent continues that item; one
        # OUTDENTED past it closes the item and belongs to the enclosing block-map.
        # Without that test a sibling declared after a nested list silently landed
        # inside the list's last item.
        if inner and cur_map is not None and (cur_map_indent is None or indent >= cur_map_indent):
            cur_map[inner.group('key')] = scalar(inner.group('rest'))
            continue
        if inner and isinstance(out.get(key), list) and not out[key]:
            # first indented key under an empty block -> it is a NESTED MAP, not a list
            out[key] = {}
            bind_nested(out[key], inner.group('key'), inner.group('rest'))
            nested_indent = indent
            continue
        if inner and isinstance(out.get(key), dict):
            # This parser handles ONE level of map nesting, which is every shape the
            # repo's 149 metadata files actually use. A key indented PAST that level
            # is a second level, and binding it here would make it a SIBLING of the
            # map it is nested inside -- silently, with the wrong structure reaching
            # every consumer. Everything else in this parser fails loud; so does this.
            if nested_indent is not None and indent > nested_indent:
                raise ValueError(
                    "map nesting deeper than one level is not supported by this "
                    "parser, and hoisting the key would silently change the "
                    "structure: %r" % line)
            bind_nested(out[key], inner.group('key'), inner.group('rest'))
            nested_indent = indent
            continue
        raise ValueError("unparsable line: %r" % line)
except ValueError as exc:
    # The parser's own message says WHAT is wrong; this adds WHERE and WHAT TO
    # DO, then exits without a traceback. The line reported is where the logical
    # line OPENED -- after a fold, the line the scan gave up on is not a location
    # an author can act on (DEC-002).
    sys.stderr.write("%s:%d: %s\n" % (sys.argv[1], lineno, elide(exc)))
    sys.stderr.write("  last key read: %s\n" % (key or "(none -- failed before any key)"))
    sys.stderr.write("  offending text: %s\n" % elide(line))
    if 'unterminated quote' in str(exc):
        fix = "a quoted value opened here and never closes; close it, or remove the stray quote"
    elif 'text after a closed quoted scalar' in str(exc):
        fix = ("only whitespace or a '#' comment may follow a closed quoted "
               "scalar; remove the extra text, or move it into a comment")
    else:
        fix = ("this shape is outside the reader's grammar; see the authoring note "
               "in specs/TEMPLATE/metadata.yaml")
    sys.stderr.write("  remedy: %s\n" % fix)
    sys.exit(1)

json.dump(out, sys.stdout)
PY
  )"; then
    # `2>&1` above merges the subprocess's stderr into THIS capture, so the
    # traceback never reaches the operator and the diagnostic is carried INTO the
    # halt rather than discarded with it. No temp file, so no lifecycle to get
    # wrong in the library's most-called function (DEC-009); a stray warning on
    # an otherwise-successful parse makes the capture a non-object, which the
    # `jq -e` guard below already halts on -- fail-loud, never a silent misread.
    # Both halts name the file ONCE, and break before the captured text so the condition line cannot grow with the caller's path (BTG-132 DEC-006/DEC-008).
    js_halt "$JS_EXIT_FAIL" syncjs.metadata.degenerate \
      "$id metadata.yaml did not parse -- the upstream read failed; refusing to proceed:
$json"
  fi
  if ! jq -e 'type == "object" and (length > 0)' <<<"$json" >/dev/null 2>&1; then
    js_halt "$JS_EXIT_FAIL" syncjs.metadata.degenerate \
      "$id metadata.yaml did not parse into a non-empty JSON object (empty, malformed, or non-object) -- refusing to proceed:
$path: ${json:0:200}"
  fi
  JS_METADATA_PATH="$path"
  JS_METADATA_JSON="$json"
}

# js_metadata_get <jq-filter> -- read one value from the loaded metadata.
js_metadata_get() {
  jq -r "$1 // empty" <<<"${JS_METADATA_JSON:-}" 2>/dev/null
}

# js_metadata_list moved to the colocated jira-meta-list.sh (BTG-114 DEC-004
# headroom relocation; see that file's header for the full rationale).
# Sourced unconditionally, self-located, so jira-lib.sh's existing
# `. jira-meta.sh` chain resolves it exactly as before the move.
# shellcheck source=./jira-meta-list.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-meta-list.sh"
