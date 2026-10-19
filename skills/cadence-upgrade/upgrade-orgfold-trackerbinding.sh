#!/usr/bin/env bash
#
# upgrade-orgfold-trackerbinding.sh -- the BTG-315 Tracker Binding table-splice
# extension to the org-fold engine (BTG-048). A colocated sidecar module
# shipped by the same PI-023 directory-copy contract as its siblings and
# SOURCED by upgrade-orgfold.sh, so it runs in that file's dynamic scope: the
# global it reads (NEW_VERSION) resolves at CALL time from upgrade-cadence.sh's
# own scope, exactly like upgrade-orgfold.sh's other functions.
#
# Bounded context: Upgrade seam / template-to-live reconciliation (BTG-048),
# the BTG-315 extension of it (DEC-014). Invariant relied on from outside this
# boundary: `fold_one` (upgrade-orgfold.sh) routes the "Tracker Binding"
# section here BEFORE the generic 3-way line-merge, and reads TB_TABLE_CONFLICT
# after the call to decide whether this section contributed a conflict.
#
# WHY A SEPARATE FILE (Facet 3 DX): upgrade-orgfold.sh could not absorb the
# three functions below, with their contract comments, without breaching the
# DX ceiling this file must obey. Splitting out the ONE new concern this
# ticket adds mirrors the existing resolver-family precedent
# (org-binding-resolve.sh / -parse.sh / -modes.sh / -crossref.sh, BTG-179/
# BTG-247): one file, one new concern, rather than letting an unrelated file
# grow past its own ceiling for a change that is entirely additive.
#
# Spec: archive/BTG-315/spec.md (Proposed Design, Config layer);
#       archive/BTG-315/decisions.md DEC-013 (root-cause finding), DEC-014
#       (the operator's ruling to extend the fold engine, recorded by the
#       implementer).

# ---------------------------------------------------------------------------
# _orgfold_tb_split <infile> <bodyfile> <tablefile> (BTG-315): splits a "Tracker
# Binding" section into <bodyfile> (every line EXCEPT the `### Per-prefix tracker
# bindings` table's own header/separator/rows, with a single sentinel line
# `\x01BTG315_TRACKER_TABLE\x01` left in the table's place) and <tablefile> (just
# the table's own lines: header, separator, then zero or more data rows). The
# table starts at the FIRST `|`-prefixed line found after the H3 heading -- any
# prose between the heading and the table (this repo's own italic caveat
# paragraph, for instance) stays in the body -- and ends at the first line after
# that is NOT `|`-prefixed. <tablefile> is left EMPTY (and no sentinel is
# written) when the section carries no such H3 at all, which is how a
# Tracker-Binding-in-name-only fixture (S-3.3's prose-only section) is told
# apart from a real one -- the caller falls back to the plain 3-way line merge
# in that case, unchanged.
# ---------------------------------------------------------------------------
_orgfold_tb_split() {
  local infile="$1" bodyfile="$2" tablefile="$3"
  : > "$bodyfile"; : > "$tablefile"
  awk -v bodyf="$bodyfile" -v tablef="$tablefile" '
    BEGIN { insubsec=0; intable=0; placed=0 }
    /^### Per-prefix tracker bindings[ \t]*$/ {
      print > bodyf; insubsec=1; next
    }
    insubsec && !intable && /^\|/ {
      intable=1
      if(!placed){ print "\x01BTG315_TRACKER_TABLE\x01" > bodyf; placed=1 }
      print > tablef; next
    }
    insubsec && !intable {
      print > bodyf; next
    }
    intable && /^\|/ {
      print > tablef; next
    }
    intable {
      intable=0; insubsec=0; print > bodyf; next
    }
    { print > bodyf }
  ' "$infile"
}

# ---------------------------------------------------------------------------
# _orgfold_tb_hdr_is_append <base_hdr_row> <src_hdr_row> (BTG-316): exit 0 iff
# the trimmed cell list of <base_hdr_row> is a PREFIX of the trimmed cell list
# of <src_hdr_row> (equal length counts: a pure re-pad qualifies). Tokenizing:
# trim the line, strip ONE leading and ONE trailing `|`, split on every `|`
# with no escape handling, trim each cell -- the SAME naive split the §9
# readers use (org-binding-parse.sh `cell()`), so the header is judged the
# same way the data is later consumed. Comparison is exact (case-sensitive):
# a case-only rename is a rename, not an append (OQ-4). Exit 1 otherwise
# (reorder, removal, rename, or fewer cells than base).
# ---------------------------------------------------------------------------
_orgfold_tb_hdr_is_append() {
  local base_row="$1" src_row="$2"
  local base_cells src_cells i n
  base_cells="$(_orgfold_tb_hdr_cells "$base_row")"
  src_cells="$(_orgfold_tb_hdr_cells "$src_row")"
  local -a base_arr src_arr
  IFS=$'\x01' read -r -d '' -a base_arr < <(printf '%s\x00' "$base_cells")
  IFS=$'\x01' read -r -d '' -a src_arr < <(printf '%s\x00' "$src_cells")
  n="${#base_arr[@]}"
  [[ "${#src_arr[@]}" -ge "$n" ]] || return 1
  for ((i = 0; i < n; i++)); do
    [[ "${base_arr[$i]}" == "${src_arr[$i]}" ]] || return 1
  done
  return 0
}

# _orgfold_tb_hdr_cells <header_row>: trims the line, strips one leading and
# one trailing `|`, splits on every `|`, trims each cell, and prints the
# cells joined by \x01 (a byte that cannot appear in Markdown table text) so
# the caller can split back into an array without word-splitting on
# whitespace inside a cell.
_orgfold_tb_hdr_cells() {
  local row="$1"
  row="$(printf '%s' "$row" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  row="${row#|}"
  row="${row%|}"
  awk -F'|' -v RS='' '{
    for (i = 1; i <= NF; i++) {
      c = $i
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
      printf "%s%s", (i > 1 ? "\x01" : ""), c
    }
  }' <<<"$row"
}

# ---------------------------------------------------------------------------
# _orgfold_tb_merge_table <base_table> <src_table> <live_table> (BTG-315,
# narrowed BTG-316): the deterministic merge of the per-prefix table's
# header/separator against its rows. Rows are LIVE-AUTHORITATIVE -- carried
# verbatim, never re-added or removed (the template's own table always ships
# row-less, so there is nothing to row-add here, unlike the Contextual Grounding pass).
# The header+separator (lines 1-2) is a STANDARD three-way merge, not a
# two-way "does live match base" check (review cycle-2 B5 -- the original
# two-way form raised a conflict on ANY live/base divergence, even one this
# release's SOURCE never touched, e.g. an adopter's earlier cosmetic re-pad):
# (1) live unchanged from base AND the source's change is a STRICT COLUMN
# APPEND (BTG-316: base's trimmed header cells are a prefix of source's) ->
# take source (this release's widening, if any); (2) SOURCE unchanged from
# base (this release never touched the table) -> keep live exactly as it is,
# whatever it says, no conflict -- the fix; (3) both sides independently made
# the identical change -> no conflict either; (4) both changed AND differ, OR
# live is unchanged but the source's change is NOT a strict append (a
# reorder, removal, or rename -- BTG-316) -> a genuine, surfaced conflict,
# using the SAME `<<<<<<< theirs / ======= / >>>>>>> core@<version>` marker
# shape `fold_one`'s generic git-merge-file path already uses, so a reader
# sees one conflict grammar everywhere in this file, never two. Only line 1
# (the header) is judged by the append rule; the separator (line 2) travels
# with whichever header line wins, unjudged (OQ-2). Sets TB_TABLE_CONFLICT=0|1.
# Echoes the merged table text.
# ---------------------------------------------------------------------------
TB_TABLE_CONFLICT=0
_orgfold_tb_merge_table() {
  local basef="$1" srcf="$2" livef="$3"
  local base_hdr src_hdr live_hdr live_rows
  local base_hdr1 src_hdr1
  base_hdr="$(sed -n '1,2p' "$basef" 2>/dev/null)"
  src_hdr="$(sed -n '1,2p' "$srcf" 2>/dev/null)"
  live_hdr="$(sed -n '1,2p' "$livef" 2>/dev/null)"
  live_rows="$(tail -n +3 "$livef" 2>/dev/null)"
  base_hdr1="$(sed -n '1p' "$basef" 2>/dev/null)"
  src_hdr1="$(sed -n '1p' "$srcf" 2>/dev/null)"
  TB_TABLE_CONFLICT=0
  if [[ "$live_hdr" == "$base_hdr" ]] && ! _orgfold_tb_hdr_is_append "$base_hdr1" "$src_hdr1"; then
    # Live unchanged from base, but the source's header change is not a
    # strict column append (reorder, removal, rename, or fewer cells) --
    # BTG-316. Never silently take the source; surface a conflict exactly
    # like case (4) below, using the SAME marker shape.
    emit_seam BOUNDARY_FAULT upgrade.orgfold.header_change_not_append "Tracker Binding"
    echo "upgrade-cadence: org-fold Tracker Binding: the template's per-prefix header is not a strict column append of the base header (base: ${base_hdr1}; source: ${src_hdr1}) -- staged as a conflict; live rows are carried unchanged in the theirs side." >&2
    TB_TABLE_CONFLICT=1
    printf '<<<<<<< theirs\n'
    printf '%s\n' "$live_hdr"
    [[ -n "$live_rows" ]] && printf '%s\n' "$live_rows"
    printf '=======\n'
    printf '%s\n' "$src_hdr"
    printf '>>>>>>> core@%s\n' "${NEW_VERSION:-new}"
    return 0
  fi
  if [[ "$live_hdr" == "$base_hdr" || "$src_hdr" == "$base_hdr" || "$live_hdr" == "$src_hdr" ]]; then
    # (1) live unchanged (and the source's change IS a strict append,
    # guarded above) -> take source; (2) source unchanged -> take live
    # (the B5 fix: live wins verbatim, including a base-diverging re-pad
    # this release never asked to change); (3) both made the same change
    # -> either side, they agree. Preference order source-then-live is
    # deliberate: it means case (1) still returns source (the widening),
    # and case (2) falls through to live only because the FIRST condition
    # (live==base) is false there.
    if [[ "$live_hdr" == "$base_hdr" ]]; then
      printf '%s\n' "$src_hdr"
    else
      printf '%s\n' "$live_hdr"
    fi
    [[ -n "$live_rows" ]] && printf '%s\n' "$live_rows"
  else
    TB_TABLE_CONFLICT=1
    printf '<<<<<<< theirs\n'
    printf '%s\n' "$live_hdr"
    [[ -n "$live_rows" ]] && printf '%s\n' "$live_rows"
    printf '=======\n'
    printf '%s\n' "$src_hdr"
    printf '>>>>>>> core@%s\n' "${NEW_VERSION:-new}"
  fi
}

# ---------------------------------------------------------------------------
# _orgfold_trackerbinding <base_sec> <src_sec> <live_sec> (BTG-315 / AC-7):
# folds the "Tracker Binding" H2 section. EVERYTHING except the `### Per-prefix
# tracker bindings` table's own header/separator/rows flows through the SAME
# 3-way `git merge-file` line-merge `fold_one`'s generic path uses (S-3.3's
# prose-only-conflict pin, unaffected -- proven by splicing the table OUT
# rather than replacing the whole-section routing the way Contextual Grounding/Runtime
# Binding do). The table itself never reaches `git merge-file`: a header
# widened over populated live rows would otherwise conflict, because diff3
# has no unchanged context line separating "the header changed" from "rows
# were added right after it" (BTG-315 DEC-013's root-cause finding) --
# `_orgfold_tb_merge_table` resolves that deterministically instead. Falls
# back to the plain whole-section 3-way merge when the section carries no
# such table in EITHER live or source (S-3.3's fixture, and any other
# Tracker-Binding-shaped section that predates this table). Sets FOLD section
# conflict via the caller reading TB_TABLE_CONFLICT / the git-merge-file exit
# status on the fallback path -- echoed to stdout either way.
# ---------------------------------------------------------------------------
_orgfold_trackerbinding() {
  local basesec="$1" srcsec="$2" livesec="$3"
  local wd; wd="$(mktemp -d)"
  _orgfold_tb_split "$basesec" "$wd/base.body" "$wd/base.table"
  _orgfold_tb_split "$srcsec"  "$wd/src.body"  "$wd/src.table"
  _orgfold_tb_split "$livesec" "$wd/live.body" "$wd/live.table"

  if [[ ! -s "$wd/live.table" || ! -s "$wd/src.table" ]]; then
    # No table to splice on one of the two sides that matter (live has none, or
    # source no longer ships one): fall back to the untouched generic 3-way
    # line-merge over the WHOLE section, exactly as before this ticket.
    local merged; merged="$wd/merged"
    if git merge-file -p -L theirs -L base -L "core@${NEW_VERSION:-new}" \
         "$livesec" "$basesec" "$srcsec" > "$merged" 2>/dev/null; then
      TB_TABLE_CONFLICT=0
    else
      TB_TABLE_CONFLICT=1
    fi
    cat "$merged"
    rm -rf "$wd"
    return 0
  fi

  # Merge the body (everything but the table) exactly as the generic path
  # would -- the sentinel line is BYTE-IDENTICAL across all three body files
  # (it replaces a region that differs in exactly the way the table differs,
  # collapsed to one constant string), so git merge-file can never raise a
  # conflict ON the sentinel itself.
  local bodymerged="$wd/body.merged" body_conflict=0
  if ! git merge-file -p -L theirs -L base -L "core@${NEW_VERSION:-new}" \
         "$wd/live.body" "$wd/base.body" "$wd/src.body" > "$bodymerged" 2>/dev/null; then
    body_conflict=1
  fi

  # BUG-BEARING IF WRAPPED IN `$(...)`: a command substitution forks a
  # subshell, and a subshell's assignment to TB_TABLE_CONFLICT never escapes
  # back to this function's scope -- the flag would silently read as whatever
  # it was before this call (stale, usually 0), and a real header conflict
  # would be written straight into the live file instead of staged (caught by
  # S-7.4). Redirecting to a FILE instead is a plain redirection, not a
  # subshell, so the assignment inside `_orgfold_tb_merge_table` propagates.
  local tablemergedfile="$wd/table.merged"
  _orgfold_tb_merge_table "$wd/base.table" "$wd/src.table" "$wd/live.table" > "$tablemergedfile"
  local table_conflict="$TB_TABLE_CONFLICT"
  local tablemerged; tablemerged="$(cat "$tablemergedfile")"

  # Splice: emit the body, substituting the ONE sentinel occurrence with the
  # table merge result. awk (not sed) because the table text may itself
  # contain sed-special characters (`|`, `&`, backreferences in cell text).
  #
  # review cycle-2 B6: the replacement text is passed through ENVIRON, NEVER
  # `awk -v repl=...`. POSIX mandates that a `-v` (and command-line var=val)
  # assignment processes backslash escapes IN THE VALUE -- a live row
  # carrying a literal `\|` silently became a real `|` (widening one cell
  # into two) and `\t` silently became a real TAB, with no git-merge-file
  # conflict to catch it (TB_TABLE_CONFLICT stayed 0), so the corruption
  # shipped silently. An exported environment variable read via ENVIRON[]
  # carries no such escape processing.
  BTG315_TB_REPL="$tablemerged" awk '
    { if ($0 == "\x01BTG315_TRACKER_TABLE\x01") { print ENVIRON["BTG315_TB_REPL"] } else { print } }
  ' "$bodymerged"

  if [[ "$body_conflict" -eq 1 || "$table_conflict" -eq 1 ]]; then
    TB_TABLE_CONFLICT=1
  else
    TB_TABLE_CONFLICT=0
  fi
  rm -rf "$wd"
}

