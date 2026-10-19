#!/usr/bin/env bash
#
# org-binding-resolve.sh -- the SINGLE reader of `CADENCE_ORG.md`'s per-prefix
# binding grammar (BTG-179).
#
# Bounded context: Governance config / per-repo binding resolution.
# Invariants relied on from outside this boundary:
#   - `CADENCE_ORG.md` is the single per-repo binding mechanism (ADR_CADENCE-0010 cl.2).
#     This script changes the KEY of the selection (a ticket-id prefix), never
#     the number of mechanisms.
#   - §9 / §10 / §13 are registered Stable Configuration Contracts. Their
#     absent-value polarities DIFFER and are never unified: §9 fail-loud,
#     §10 mint-by-convention, §13 disabled.
#
# Three channels, mirroring the adapter contract (BTG-075 DEC-001):
#   stdout     `key=value` result lines, one per field of the mode's key set
#   stderr     `condition=<name>` plus a human-readable message
#   exit code  0 resolved / 1 a named halt / 2 usage or setup failure
#
# NEVER a partial answer alongside a halt: stdout is assembled in full and
# printed only once the resolution has succeeded.
#
# Usage:
#   org-binding-resolve.sh --tracker <PREFIX> [--org <file>]
#
# Default --org: docs/agentic-sdlc/CADENCE_ORG.md under $PWD -- the mint-id.sh
# `--binding` convention, so it works pre-adopt and outside a git tree.

set -u

ORG_DEFAULT="docs/agentic-sdlc/CADENCE_ORG.md"

usage() {
  echo "Usage: $0 --tracker   <PREFIX> [--org <file>]" >&2
  echo "       $0 --allocator <PREFIX> [--org <file>]" >&2
  echo "       $0 --sprint    <PREFIX> [--org <file>]" >&2
  echo "       $0 --prefixes           [--org <file>]" >&2
  echo "       $0 --allocator-prefixes [--org <file>]" >&2
  echo "       $0 --form               [--org <file>]" >&2
  exit 2
}

# --- the LEXER --------------------------------------------------------------
#
# `org-binding-parse.sh` holds the grammar lexer. The no-prefix MODES
# (`--prefixes`, `--form`, both scalar forms) live in `org-binding-modes.sh`,
# sourced below -- they were moved there by DEC-030 and this stanza still named
# them here for one review cycle (B4-1's site 3). DEC-004 pre-declared the split
# from Facet 3's 400-line ceiling, DEC-027 took it, DEC-030 made it three-way,
# BTG-247 DEC-012 (OQ-B) made it four; ALL FOUR modules carry the same three
# distribution rows -- the COPY_PATHS entry, the RECONCILE row and the
# `cadence-surfaces.md` mention.
#
# Located beside this script via `$0` rather than `${BASH_SOURCE[0]}`: the two
# `tms-*` backstop hooks invoke this file with `sh`, where BASH_SOURCE does not
# exist. A missing half is a SETUP failure (exit 2), never a degraded answer.
ORG_PARSE="$(dirname "$0")/org-binding-parse.sh"
if [ ! -f "$ORG_PARSE" ]; then
  echo "org-binding-resolve: the parser half is not at $ORG_PARSE" >&2
  echo "       Both halves ship together; refusing to answer from half a reader." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$ORG_PARSE"

# ...and the no-prefix ANSWERS, which need the lexer above (DEC-030). Load order
# is not incidental: `org-binding-modes.sh` calls `table_rows`, `bound_value` and
# `declares_table` at RUN time, so sourcing it second is what makes those
# definitions present when a mode actually runs.
ORG_MODES="$(dirname "$0")/org-binding-modes.sh"
if [ ! -f "$ORG_MODES" ]; then
  echo "org-binding-resolve: the modes half is not at $ORG_MODES" >&2
  echo "       All three halves ship together; refusing to answer from part of a reader." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$ORG_MODES"

# ...and the CROSS-SECTION module (BTG-247 DEC-012 / OQ-B, the fourth): §9's
# tracker vocabulary (tracker_skill, validate_tracker_table, prefix_tracker,
# prefix_skill) and resolve_sprint, which is built entirely from it. Sourced
# last: resolve_sprint calls table_rows/cell/halt from the lexer above, and its
# own prefix_tracker/prefix_skill calls resolve within this same file, so load
# order only needs every definition present before the dispatch below runs.
ORG_CROSSREF="$(dirname "$0")/org-binding-crossref.sh"
if [ ! -f "$ORG_CROSSREF" ]; then
  echo "org-binding-resolve: the cross-section half is not at $ORG_CROSSREF" >&2
  echo "       All four halves ship together; refusing to answer from part of a reader." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$ORG_CROSSREF"

# --- argument parsing ----------------------------------------------------
[ $# -ge 1 ] || usage
MODE=""
PREFIX=""
ORG="$ORG_DEFAULT"
while [ $# -gt 0 ]; do
  case "$1" in
    --tracker)   MODE=tracker;   shift; [ $# -ge 1 ] || usage; PREFIX="$1"; shift ;;
    --allocator) MODE=allocator; shift; [ $# -ge 1 ] || usage; PREFIX="$1"; shift ;;
    --sprint)    MODE=sprint;    shift; [ $# -ge 1 ] || usage; PREFIX="$1"; shift ;;
    --prefixes)  MODE=prefixes;  shift ;;
    --allocator-prefixes) MODE=allocator-prefixes; shift ;;
    --form)      MODE=form;      shift ;;
    --org)     shift; [ $# -ge 1 ] || usage; ORG="$1"; shift ;;
    *) usage ;;
  esac
done
[ -n "$MODE" ] || usage
[ -f "$ORG" ] || { echo "org-binding-resolve: no org config at $ORG" >&2; exit 2; }



# --- --tracker -----------------------------------------------------------
resolve_tracker() {
  local sec9 rows row rp tracker_cell key ts agent_user
  sec9="$(section_region 9 "$SEC_TRACKER")"
  require_section9 "$sec9"
  # THE REMOVED FORM IS REFUSED BEFORE ANY ROW IS READ (BTG-242), inheriting
  # section_form()'s own ordering rule: a file carrying both a removed
  # declaration and a valid table halts on the removal, never on whichever form
  # happens to match first.
  require_line_form_removed "$sec9" 'Bound tracker(s)' tracker.binding.form_removed tracker
  rows="$(table_rows "$sec9" tracker)"
  # TABLE PRESENCE IS THE DECLARATION, so a table with no data row is §9's ABSENT
  # state -- and §9's absent state has always been FAIL LOUD. This condition
  # supersedes `tracker.binding.scalar_unbound`, which answered the same question
  # about the bound line this ticket removed. The POLARITY is unchanged; only the
  # shape that counts as absent moved.
  if [ -z "$(printf '%s\n' "$rows" | grep '^|' || true)" ]; then
    halt tracker.binding.table_missing \
      "§9 declares no per-prefix tracker binding: its '### Per-prefix tracker bindings' table carries no data row, and a header and a separator are not a table; §9's polarity is FAIL LOUD, so there is no default tracker and no silent inner-source SKIP -- declare a row per ticket-id prefix, or a single '*' wildcard row for an inner-source repository"
  fi
  validate_tracker_table "$rows"

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    [ "$rp" = "$PREFIX" ] || continue
    tracker_cell="$(cell "$row" 2)"
    key="$(cell "$row" 3)"; unfilled "$key" && key=""
    ts="$(tracker_skill "$tracker_cell")" || halt tracker.binding.tracker_unmapped \
      "prefix '$PREFIX' names tracker '$tracker_cell', which has no TS-1 mapping in the curated reference set -- never a fallback to jira"
    # A row binding a REAL tracker must carry its project key. The two fallbacks
    # this refuses are different and both are plausible: the deprecated
    # environment variable, and the PREFIX itself -- which looks exactly like a
    # key and would be right for most rows while being silently wrong for the
    # very row this design exists to support (a prefix filing to a differently
    # named board).
    if [ -z "$key" ] && [ "${ts%%|*}" != "inner-source" ]; then
      halt tracker.binding.project_key_missing \
        "prefix '$PREFIX' binds tracker '$tracker_cell' but its row names no project key; a tracker-bound row must carry one -- never an environment-variable fallback, never a key derived from the prefix"
    fi
    printf 'tracker=%s\n' "${ts%%|*}"
    printf 'project_key=%s\n' "$key"
    printf 'skill=%s\n' "${ts##*|}"
    printf 'source=per-prefix\n'
    # BTG-315 (additive): the OPTIONAL fifth cell, an agent-time user for the
    # operator/agent worklog split. A placeholder resolves empty, the same
    # rule cell 3 (project key) already applies -- an un-substituted template
    # row is no configuration at all. Every existing consumer parses named
    # `key=value` lines, so this extra line is ignored by all of them.
    agent_user="$(cell "$row" 5)"; unfilled "$agent_user" && agent_user=""
    printf 'agent_user=%s\n' "$agent_user"
    return 0
  done <<EOF
$rows
EOF
  # No explicit row matched. A declared WILDCARD row (`*`, keyless, inner-source)
  # is how an adopter says "every other prefix is inner-source" -- §9's declared
  # SKIP in per-prefix form. It is a FALLTHROUGH, consulted only after every
  # explicit row has been tried, so it can never preempt a prefix that has its
  # own row. `source=wildcard` is reported distinctly from `per-prefix` because
  # "no row matched and the catch-all answered" is a different fact about an
  # operator's configuration than "this prefix has its own inner-source row",
  # and only the first hints that a row may be missing.
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    [ "$(cell "$row" 1)" = "*" ] || continue
    printf 'tracker=inner-source\n'
    printf 'project_key=\n'
    printf 'skill=n/a\n'
    printf 'source=wildcard\n'
    # BTG-315 (additive): a wildcard row is validated (validate_tracker_table)
    # to never carry a non-empty agent-time user before this loop runs, so
    # this is always empty -- an inner-source row has no operator to
    # attribute time away from.
    printf 'agent_user=\n'
    return 0
  done <<EOF
$rows
EOF

  # The configured set is named in the failure so an operator sees what WAS
  # available, not merely that their prefix was not. A halt that reports only the
  # unresolved value leaves the reader to go and read the table themselves.
  local configured=""
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    configured="$configured $(cell "$row" 1)"
  done <<EOF
$rows
EOF
  halt tracker.binding.prefix_unbound \
    "prefix '$PREFIX' has no §9 binding; configured prefixes:${configured:- (none)}"
}


# --- --allocator ---------------------------------------------------------
#
# §10's answer is `bound` or `unbound` -- the SAME vocabulary the existing
# allocator sidecar already speaks. The per-prefix mode is a finer KEY on the
# same question, not a new question, so every caller that already branches on
# bound-vs-unbound keeps its branch and only the thing it asks about changes.
resolve_allocator() {
  local sec10 rows row rp alloc scheme
  # ADR / II / PROD numbering is §10-INDEPENDENT: it is always local, even for a
  # tracker-bound adopter, and those ids have no `specs/<id>/` by design. A row
  # declaring one of them tracker-reserved is IGNORED rather than obeyed --
  # honouring it would make every ADR, II and PROD id an unpaired external
  # reservation. This is checked before the table is read at all, because the
  # rule is about the PREFIX, not about what the table happens to say.
  #
  # BTG-197: the same rule, for the same reason, for CADENCE core's own record
  # prefixes. ADDITIVE -- the bare three keep behaving exactly as they did, which
  # is the whole point of the ticket. EXACT LITERALS, never `ADR*`: a loose
  # pattern here would silently exempt an adopter's own ADRIAN prefix from a §10
  # binding it is genuinely subject to.
  case "$PREFIX" in
    ADR|II|PROD|ADR_CADENCE|II_CADENCE|PROD_CADENCE)
      printf 'allocator=unbound\n'
      printf 'id_scheme=n/a\n'
      printf 'source=convention-id\n'
      return 0 ;;
  esac
  sec10="$(section_region 10 "$SEC_ALLOCATOR")"
  # THE REMOVED FORM IS REFUSED BEFORE ANY ROW IS READ (BTG-242). Checked in the
  # §10 region AND then file-wide, which is the read shape `allocator_scalar_answer`
  # itself carried: the sidecar's `--binding` has always read this label file-wide,
  # and the two must not disagree on a non-canonical §10 heading -- the seed steps
  # call one then the other, so a disagreement aborts adopt.
  require_alloc_form_removed "$sec10"
  # §10's PRESENT-and-unreadable rule, raised HERE now that the scalar answerer
  # that used to raise it is gone. §10's MINT polarity governs an ABSENT
  # declaration, never a PRESENT-and-unreadable one: a table this file declares
  # under a heading no region can anchor is unreadable, and answering `unbound`
  # for it would call every prefix locally-minted on a file that plainly binds
  # several externally.
  require_locatable_10 "$sec10"
  rows="$(table_rows "$sec10" allocator)"

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    [ "$rp" = "$PREFIX" ] || continue
    alloc="$(cell "$row" 2)"
    scheme="$(cell "$row" 3)"; unfilled "$scheme" && scheme=""
    # A ROW IS NOT THE SAME THING AS A BOUND ROW. `None -- closed default` is a
    # row that declares the local mint explicitly; only a real external allocator
    # answers `bound`. This mirrors binding_status()'s existing scalar lexer.
    case "$(printf '%s' "$alloc" | tr '[:upper:]' '[:lower:]')" in
      none*|"") printf 'allocator=unbound\n' ;;
      *)
        # An EXTERNAL reservation resolves its concrete adapter from THE SAME
        # PREFIX'S §9 row, vendor-neutrally. If that row binds no tracker there
        # is literally nothing to call, and falling back to a mint would
        # silently ignore an explicit declaration -- the opposite of honouring a
        # default. This is the one §10 state that IS an error, and it does not
        # contradict the mint polarity: minting is what happens when NOTHING is
        # declared, not when something impossible is.
        if [ "$(prefix_tracker "$PREFIX")" = "inner-source" ]; then
          halt idalloc.binding.allocator_without_tracker \
            "prefix '$PREFIX' declares the allocator '$alloc' but its §9 row binds no tracker; an external reservation resolves its adapter from the same prefix's §9 row, so there is nothing to reserve from"
        fi
        printf 'allocator=bound\n' ;;
    esac
    printf 'id_scheme=%s\n' "${scheme:-n/a}"
    printf 'source=per-prefix\n'
    return 0
  done <<EOF
$rows
EOF

  # UNMATCHED PREFIX => MINT BY CONVENTION. The closed default, and the EXPLICIT
  # INVERSE of §9's unmatched-prefix FAIL LOUD. Do NOT copy §9's polarity here:
  # an unbound allocator is the byte-identical legacy behaviour of every repo
  # that never bound one, so making it an error would break every existing
  # adopter the moment they added their first per-prefix row for one project.
  # There is nothing to report -- this is not a degraded answer, it is THE answer.
  printf 'allocator=unbound\n'
  printf 'id_scheme=n/a\n'
  printf 'source=default\n'
}

# resolve_sprint (§13's --sprint answer) moved to the colocated
# org-binding-crossref.sh (BTG-247 DEC-012 / OQ-B): its own logic is entirely
# built from §9's tracker vocabulary (prefix_tracker, prefix_skill), which
# moved there with it. Sourced below, alongside the parse and modes halves.

case "$MODE" in
  tracker)   resolve_tracker ;;
  allocator) resolve_allocator ;;
  sprint)    resolve_sprint ;;
  prefixes)  resolve_prefixes ;;
  allocator-prefixes) resolve_allocator_prefixes ;;
  form)      resolve_form ;;
esac
