#!/usr/bin/env bash
#
# jira-link-signals.sh -- js_metadata_list_signals, the relation SIGNAL reader
# for a flat `related_tickets:` entry (the sidecar's step 7a). Split out of the
# colocated jira-link-targets.sh (BTG-247 AC-1 headroom).
#
# Bounded context: same as jira-link-targets.sh, which this file is SOURCED by,
# unconditionally, before js_link_targets calls js_metadata_list_signals.
#
# WHY THIS SEAM: js_metadata_list_signals is a self-contained reader of raw
# metadata.yaml text (it reads only $JS_METADATA_PATH and calls only js_report,
# both already available once this file is sourced) -- a distinct, already
# well-documented concern from js_link_targets's own validation-chokepoint
# logic, which stays in jira-link-targets.sh.
#
# Moved VERBATIM from jira-link-targets.sh (lines 272-399 as measured
# 2026-09-16, its own tail) -- no re-wrap, no compression, no logic change.
# `artifacts/commands/cadence-sync-jira/jira-server-scripts.md`'s registry row
# documenting this function's home is updated in the same change (AC-3-style
# discipline, applied here even though this is not a registered surface).
#
# Spec: archive/BTG-247/spec.md AC-1 (headroom), DEC-008 (hybrid convergence).

# --------------------------------------------------------------------------
# The relation SIGNAL of a flat `related_tickets` entry (the sidecar's step 7a)
# --------------------------------------------------------------------------
# js_metadata_list_signals <top-level-key> -- emit one `<value>\t<signal>` line
# per list item under that key, where the signal is the item's TRAILING COMMENT
# plus any comment-only CONTINUATION lines beneath it.
#
# The structured reader drops comments, which every other consumer wants. But
# `related_tickets` is different: across this repo's 150 metadata files ZERO
# declare an ordering key or keyed map, and all ten users are FLAT lists whose
# relation is stated only in the trailing comment -- which the sidecar makes
# normative. Without reading the raw file for this one key, 100% of this repo's
# relations project as the symmetric default. Continuation lines matter as much:
# the one live landing dependency (archive/BTG-020/metadata.yaml:101-102) is on a
# comment-only line BENEATH its item.
#
# The joined signal has its WHITESPACE RUNS COLLAPSED. Each continuation segment
# already begins with a space once `#` is stripped, and the join added another, so
# a phrase straddling the break emitted DOUBLE spaces -- `THIS ticket DEPENDS  ON
# it` from archive/BTG-016b/metadata.yaml:88-89 -- while every pattern in
# js_relation_from_signal uses one. The repo's genuine landing dependency matched
# nothing and was silently downgraded to the symmetric default, which is exactly
# what the continuation join was added for (DEC-032).
js_metadata_list_signals() {
  local key="$1" detail
  [[ -n "${JS_METADATA_PATH:-}" ]] || return 1
  # BTG-114: swap stdout/stderr so a refusal's DETAIL (the offending item,
  # named -- AC-1/AC-11) is captured for the report while the emitted
  # <value>\t<signal> lines still reach the caller's own command substitution
  # undisturbed. No temp file: the library's most-called function stays free
  # of one to leak (jira-meta.sh DEC-009's precedent, applied here too).
  exec 3>&1
  detail="$(python3 - "$JS_METADATA_PATH" "$key" 2>&1 1>&3 <<'PY'
import re, sys

def refuse(msg):
    sys.stderr.write(msg)
    sys.exit(3)

path, key = sys.argv[1], sys.argv[2]
out, state = [], {"item": None, "sig": []}

# G3's table (BTG-114): a backslash in a DOUBLE-quoted scalar consumes the
# next char; a control-char escape translates, else it falls through as-is.
ESC = {'n': '\n', 't': '\t', 'r': '\r', '0': '\x00', 'a': '\x07',
       'b': '\x08', 'f': '\x0c', 'v': '\x0b', 'e': '\x1b'}


def quoted(raw):
    """(VALUE, TAIL) of a quoted scalar, or None when the delimiter never
    closes. The SAME escape-aware scan jira-meta.sh's quoted() uses (G1-G5),
    for a PLAIN item's own text: the DOUBLED quote escape in either quote
    style; a DOUBLE-quoted backslash that consumes the next character (G3;
    single-quoted stays literal, G2); the numeric sub-family \\x/\\u/\\U
    refused by name (G4), never guessed. This is the escape grammar that
    used to be spec'd for the loader only -- implementing it here too is
    what makes the three readers agree rather than silently disagree on
    exactly the shapes each already accepts or refuses on its own."""
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
                refuse("a numeric escape (\\%s) is refused by name, not "
                       "guessed: %r" % (nxt, raw))
            buf += ESC.get(nxt, nxt)
            i += 2
            continue
        buf += ch
        i += 1
    return None

ITEM = re.compile(r"^\s+-\s+(.*)$")
TOP  = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*:")


def opens_quote(rest):
    """True iff a list item's text opens a quote that does not close ON IT.
    Decided on the RAW item text, BEFORE the `#` split below: `- "CTS-72#CTS-73"`
    splits to the OPEN-looking `"CTS-72`, and folding on that would swallow the
    next line -- a known truncation (BTG-114 member 5) made larger."""
    rest = rest.strip()
    if rest[:1] not in ('"', "'"):
        return False
    return rest.find(rest[0], 1) < 0


def fold(lines):
    """Join a list item's CONTINUATION lines into it by the SAME rule
    js_metadata_load's fold uses -- one space per break, surrounding whitespace
    dropped -- so the two readers of one file cannot disagree about a value:
    this one agrees with the loader or REFUSES (the DEC-023 guard below, now
    scoped to map-shaped items; BTG-114's escape-aware quoted() resolves a
    plain item's doubled escape the same way the loader does). Before BTG-111
    a wrapped item's continuation, neither `- ` nor `#`, hit
    `if stripped: break` and ended the block at ONE item with every later
    declaration gone, no condition, no counter, exit 0 (BTG-108 DEC-016's R-9
    premise; Behavior 5). It follows the QUOTE only: a block scalar's
    continuation still ends the read, but the indicator itself is now refused
    by name before that can happen (BTG-114 G7 closes member 4 / btg-108
    S-2.13). Absorption stops at the next top-level key or EOF."""
    res, i, n = [], 0, len(lines)
    while i < n:
        line = lines[i]
        m = ITEM.match(line)
        while (m and opens_quote(m.group(1))
               and i + 1 < n and not TOP.match(lines[i + 1])):
            i += 1
            line = line.rstrip() + " " + lines[i].strip()
            m = ITEM.match(line)
        res.append(line)
        i += 1
    return res


def flush():
    # BTG-114 G8: emptiness is a value, not an absence -- `is not None` is the
    # test, never truthiness, so `- ""` still emits its (empty) line.
    if state["item"] is not None:
        # BTG-114 G6: a literal TAB in the value or in any signal segment
        # (including a continuation line, BEFORE the collapse below hides it)
        # collides with the <value>\t<signal> line contract's own delimiter;
        # refuse by name rather than emit a silently reinterpreted third field.
        if "\t" in state["item"] or any("\t" in s for s in state["sig"]):
            refuse("a tab character in %r is not representable in the "
                   "<value>\\t<signal> line contract" % state["item"])
        sig = re.sub(r"\s+", " ", " ".join(state["sig"])).strip()
        out.append("%s\t%s" % (state["item"], sig))
    state["item"], state["sig"] = None, []

inblock = False
for line in fold(open(path, encoding="utf-8").read().splitlines()):
    stripped = line.strip()
    if not inblock:
        if re.match(r"^%s:\s*(#.*)?$" % re.escape(key), line):
            inblock = True
        continue
    if TOP.match(line):                                  # the next top-level key
        break
    m = ITEM.match(line)
    if m:
        flush()
        rest = m.group(1)
        v = re.sub(r"^[^#'\"]*:\s*(?=['\"])", "", rest, count=1)
        # BTG-114 G7: a block-scalar indicator is outside this reader's
        # grammar. Refused by name HERE, before it can be read as the
        # one-character value ">" or "|" and before the indented body line
        # can hit the `if stripped: break` below and silently end the whole
        # read (spec.md member 4 / F-8).
        if re.match(r'^[|>][0-9+-]*\s*(#.*)?$', rest.strip()):
            refuse("%r is a block scalar, outside this reader's grammar" % rest)
        plain = v.strip()
        if v == rest and plain[:1] in ('"', "'"):
            # BTG-114 G1/G2/G3/G4/G5, PLAIN quoted items (`v == rest`: the
            # regex below stripped no "- key: " prefix, so this is not a map
            # item). `quoted()` is the SAME escape-aware scan jira-meta.sh's
            # own function uses -- it resolves the doubled-quote escape
            # correctly (SUPERSEDING the old "cannot resolve a doubled
            # escape" refusal for exactly this shape, a scanning limitation
            # the real scan no longer has) and the backslash-escape family,
            # refusing only the numeric sub-family by name. The signal is
            # split off the TAIL, so a "#" inside the value is not mistaken
            # for the comment boundary (G1). Only whitespace or a "#"
            # comment may follow the close; anything else is refused by
            # name (member 6) rather than silently discarded.
            closed = quoted(plain)
            if closed is None:
                refuse("%r opens a quote this step cannot resolve" % rest)
            value, tail = closed
            value, tail = value.strip(), tail.strip()
            if tail.startswith('#'):
                state["sig"] = [tail[1:]]
            elif tail:
                refuse("%r carries text after its closing quote (%r) that "
                       "is not a comment -- never discarded silently"
                       % (rest, tail))
            state["item"] = value
        else:
            # BTG-111 DEC-023, MAP ITEMS ONLY (`v != rest`, a "- key: ..."
            # value) and any UNQUOTED item (a bare reference, a flow-style
            # map "{...}"): REFUSE a quoted value this reader cannot
            # resolve structurally from here -- a closure that never
            # completes, or a doubled escape outside the region this scan
            # covers -- rather than truncate and drop every later
            # declaration SILENTLY. UNCHANGED by BTG-114 (DEC-013): the
            # escape grammar above is scoped to plain items; a map item's
            # value is still opaque to this reader and passes through (or
            # refuses) exactly as it did before this ticket.
            e = v.find(v[:1], 1) if v[:1] in ('"', "'") else -2
            if (e == -1 and v != rest) or (e >= 0 and v[e + 1:e + 2] == v[0]):
                refuse("%r opens a quote this step cannot resolve -- YAML's "
                       "DOUBLED-quote escape ('' or \"\"), or a map item "
                       "'- key: \"...\"' whose quoted value wraps; spell it "
                       "on ONE line, without the doubled escape" % rest)
            hash_at = rest.find("#")
            if hash_at >= 0:
                state["sig"] = [rest[hash_at + 1:]]
                rest = rest[:hash_at]
            rest = rest.strip()
            if rest[:1] in ('"', "'"):
                quote = rest[0]
                end = rest.find(quote, 1)
                rest = rest[1:end] if end > 0 else rest[1:]
            state["item"] = rest.strip()
        continue
    if stripped.startswith("#"):                          # a CONTINUATION comment
        if state["item"] is not None:
            state["sig"].append(stripped[1:])
        continue
    if stripped:
        break
flush()
# every line is TERMINATED, not separated: a final line without its newline is
# dropped by the `while read` that consumes this, which silently loses the last
# related ticket on every ticket in the repo.
for line in out:
    sys.stdout.write(line + "\n")
PY
  )"
  local rc=$?
  exec 3>&-
  if [[ $rc -ne 0 ]]; then
    js_report syncjs.link.related_tickets_value_shape_unrecognized \
      "a $key item in $JS_METADATA_PATH could not be resolved by this reader (${detail:-no detail captured}) -- the WHOLE flat relation read is REFUSED rather than emitting a truncated value and dropping every later declaration silently; fix the item and the next run projects it"
    return 1
  fi
}
