#!/usr/bin/env bash
#
# jira-meta-list.sh -- js_metadata_list, the SEQUENCE-shape reader for the
# structured loader's JSON. Split out of the colocated jira-meta.sh (BTG-114
# DEC-004 headroom relocation).
#
# Bounded context: same as jira-meta.sh, which this file is SOURCED by,
# unconditionally, at the bottom of that file's Python-bearing half, so
# jira-lib.sh's existing `. jira-meta.sh` chain resolves `js_metadata_list`
# exactly as it did before the move -- no call site changed (jira-epic.sh
# calls it through jira-lib.sh, never sourcing this file directly).
#
# WHY THIS SEAM: `js_metadata_list` is a self-contained bash function outside
# the Python heredoc, with no coupling to the parser it reads the output of --
# a distinct, already well-documented concern from `js_metadata_load`'s parse
# logic, which stays in jira-meta.sh. Relocating it is the DX-ceiling remedy
# DEC-004 authorizes (accepted at the Spec Approval gate, OQ-3): `jira-meta.sh`
# measured 399/400 with the `> 390` contingency already spent, and the correct
# quote-escape grammar (G2/G3/G4) this ticket adds costs +11 lines, measured,
# not net-zero -- so the parser cannot land without this move first.
#
# Moved VERBATIM from jira-meta.sh (lines 371-399 as measured 2026-09-17,
# its own tail) -- no re-wrap, no compression, no logic change (regression
# R-9). `jira-server-scripts-libs.md`'s registry row documenting this
# function's home is updated in the same change.
#
# Spec: archive/BTG-114/spec.md DEC-004 (headroom), DEC-002 (the grammar this
# relocation makes affordable).

# --------------------------------------------------------------------------
# js_metadata_list <key> <condition-name> -- emit the loaded metadata's <key>
# as a SEQUENCE, one item per line.
# --------------------------------------------------------------------------
# Three shapes, three answers (DEC-044):
#   absent / null / empty  -> an empty list, exit 0. Nothing to iterate.
#   an array               -> its items, exit 0.
#   anything else          -> REPORT <condition-name> and return 1.
#
# The third case is the point. A shape this reader cannot interpret is NOT the
# same as an absent one, so it is never silently read as "empty": that is exactly
# what a scalar `decomposed_into` did on the live instance -- the umbrella branch
# re-typed the issue, renamed it, then iterated zero children and reported
# success. The caller decides what to do about it (here: halt its branch before
# any mutation); this helper only refuses to lie about the shape.
js_metadata_list() {
  local key="$1" condition="$2" shape
  shape="$(jq -r --arg k "$key" \
    '.[$k] | if . == null or . == "" then "empty" else type end' \
    <<<"${JS_METADATA_JSON:-}" 2>/dev/null)" || shape=""
  [[ -n "$shape" ]] || shape="unreadable"
  case "$shape" in
    empty) return 0 ;;
    array) jq -r --arg k "$key" '.[$k][] | tostring' <<<"$JS_METADATA_JSON" 2>/dev/null; return 0 ;;
    *)
      js_report "$condition" \
        "$key is a $shape ($(jq -r --arg k "$key" '.[$k] | tostring' <<<"${JS_METADATA_JSON:-}" 2>/dev/null)), not a sequence -- it is NOT read as an empty one, because a shape this reader cannot interpret is not an absent child set"
      return 1 ;;
  esac
}
