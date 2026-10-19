#!/usr/bin/env bash
#
# org-binding-crossref.sh -- the CROSS-SECTION concern of `CADENCE_ORG.md`'s
# per-prefix binding reader (BTG-179; fourth module authorized BTG-247 OQ-B,
# 2026-09-16, overturning `cadence-surfaces.md`'s earlier "three modules is
# TERMINAL" ruling). SOURCED by `org-binding-resolve.sh`; never executed.
#
# Bounded context: Governance config / per-repo binding resolution -- the same
# as `org-binding-parse.sh`, `org-binding-resolve.sh` and `org-binding-modes.sh`.
# Invariants relied on from outside this boundary:
#   - `CADENCE_ORG.md` is the single per-repo binding mechanism (ADR_CADENCE-0010 cl.2).
#   - §9 / §10 / §13 are registered Configuration Contracts whose absent-value
#     polarities DIFFER and are never unified: §9 fail-loud, §10
#     mint-by-convention, §13 disabled.
#
# THE SEAM: §10's and §13's own per-prefix answers each depend on §9's tracker
# vocabulary -- an external allocator resolves its adapter from the same
# prefix's §9 row (`resolve_allocator`, staying in org-binding-resolve.sh), and
# sprint enforcement's skill pointer and its own "does this prefix even have a
# tracker" guard are BOTH answered by following §9's row rather than declaring
# either independently (`resolve_sprint`, moved here). This file holds that
# CROSS-SECTION lookup machinery -- the §9 vocabulary mapping (`tracker_skill`,
# `validate_tracker_table`, `prefix_tracker`, `prefix_skill`) together with
# `resolve_sprint`, its one caller whose own logic is inseparable from it (it
# calls both `prefix_tracker` and `prefix_skill`) -- rather than the axis DEC-003
# used for the authored-doc family (a single concern with one owner). The
# alternative axis -- splitting `org-binding-resolve.sh`'s three per-prefix
# answer functions evenly, one per new file -- was rejected: `resolve_tracker`
# is §9's OWN answer and the file's own header already names `resolve.sh` as
# "the entry point [that] ANSWERS questions about a PREFIX", so moving it out
# would leave that description false, while `resolve_allocator`'s own §9
# dependency (`prefix_tracker`, once) is a single call rather than the two-call,
# full-answer dependency `resolve_sprint` has.
#
# `tracker_skill`, `validate_tracker_table`, `prefix_tracker` and `prefix_skill`
# moved verbatim from `org-binding-parse.sh` (pre-split lines :301-:399); they
# were audited there as the DOCUMENT LEXER's tracker-vocabulary concern, not its
# generic region/row/cell lexing, so moving them costs that file's own header
# nothing (it still lexes regions, rows, cells and forms; it no longer maps a
# tracker cell to a TS-1 skill). `resolve_sprint`, and its explanatory comment
# recording that `repo_sprint_marker()` is gone (BTG-242), moved verbatim from
# `org-binding-resolve.sh` (pre-split lines :269-:382). No re-wrap, no logic
# change (AC-9/AC-10 analogues for this non-`.md` family).
#
# Spec: archive/BTG-247/spec.md (Proposed Design Step 4, org-binding row); DEC-012
# (OQ-B authorization); DEC-007 (the 324-line threshold this split satisfies).

# tracker_skill <tracker-cell> -- the vendor token and its TS-1 skill, as
# "<tracker>|<skill>". The map is §9's curated reference-adapter table
# (ADR_CADENCE-0023); a tracker outside it is never guessed at and never falls back to
# jira. A bare `jira` is unmapped -- BTG-299 removed the Cloud adapter, so this is
# no longer because the token is AMBIGUOUS between two shipped Jira adapters
# (there is only one, Server/DC); the RULE is unchanged even though its reason
# changed: a bare `jira` still never resolves to a concrete adapter by guessing.
tracker_skill() {
  local raw lc
  raw="$1"
  lc="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    # An inner-source row binds no tracker at all. It is §9's DECLARED opt-out
    # in per-prefix form -- a deliberate SKIP, never the missing-binding state.
    *inner-source*|none)     echo "inner-source|n/a" ;;
    *jira*server*|*jira*dc*) echo "jira|/cadence-sync-jira" ;;
    # `*jira*cloud*)  echo "jira|/sync-jira" ;;` REMOVED (BTG-299). The Cloud
    # adapter no longer ships; a row binding it now falls through to the `*)`
    # arm below and halts `tracker.binding.tracker_unmapped`, never silently.
    *youtrack*)               echo "youtrack|/cadence-sync-youtrack" ;;
    *) return 1 ;;
  esac
}

# validate_tracker_table <rows> -- the table-level rules, checked BEFORE any row
# is matched.
#
# WHY BEFORE, AND FOR EVERY PREFIX. These defects live in the TABLE, not in the
# row a given resolution happens to touch. If they only fired for the prefix that
# reached the bad row, an adopter would ship a broken table, watch their
# well-formed prefixes resolve, and discover the defect on the first ticket under
# an unlisted prefix -- which is precisely the ticket that would be mis-routed.
validate_tracker_table() {
  local rows="$1" row rp tcell key ts wilds=0 agent_cell
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    tcell="$(cell "$row" 2)"
    key="$(cell "$row" 3)"; unfilled "$key" && key=""
    ts="$(tracker_skill "$tcell")" || ts="unmapped|n/a"
    if [ "$rp" = "*" ]; then
      wilds=$((wilds + 1))
      # The catch-all may only ever be the no-tracker answer. This is the
      # security-adjacent rule of the set: a `*` row naming a real tracker sends
      # every prefix nobody configured -- typos included -- to a live board.
      if [ "${ts%%|*}" != "inner-source" ]; then
        halt tracker.binding.wildcard_binds_tracker \
          "the wildcard row binds tracker '$tcell'; a wildcard row may ONLY be inner-source, or every unconfigured prefix is routed to a live board"
      fi
      # BTG-315: an inner-source row has NO operator to attribute time away
      # from -- there is nothing for a fifth-cell agent-time user to mean on
      # the catch-all row, so a value there is refused before any prefix is
      # ever resolved through it, exactly as the tracker check above is.
      agent_cell="$(cell "$row" 5)"; unfilled "$agent_cell" && agent_cell=""
      if [ -n "$agent_cell" ]; then
        halt tracker.binding.wildcard_agent_user \
          "the wildcard row carries agent-time user '$agent_cell'; a wildcard row is inner-source only and has no operator to attribute time away from -- an agent-time user may only be set on a named-prefix row"
      fi
    elif [ -z "$key" ] && [ "${ts%%|*}" = "inner-source" ]; then
      # The near-miss: an adopter reaching for the catch-all and typing the
      # prefix they had in mind. Read literally it binds one prefix; read as
      # intended it binds all of them. Neither reading may be chosen silently, so
      # the failure teaches the grammar rather than merely naming the row.
      halt tracker.binding.wildcard_malformed \
        "the inner-source row for prefix '$rp' carries no project key; a WILDCARD row has prefix '*' and an empty key, and an inner-source row bound to a NAMED prefix must carry its key"
    fi
  done <<EOF
$rows
EOF
  if [ "$wilds" -gt 1 ]; then
    halt tracker.binding.wildcard_multiple \
      "$wilds wildcard rows are declared; at most one is allowed, or the catch-all has two answers and the resolver silently takes whichever it reaches first"
  fi
}


# prefix_tracker <prefix> -- the tracker token that prefix's §9 row resolves to,
# or the empty string when §9 gives no answer. Used by §10 to resolve an external
# allocator's adapter FROM §9, vendor-neutrally, so no allocator rule ever names
# a tracker itself.
prefix_tracker() {
  local sec9 rows row
  sec9="$(section_region 9 "$SEC_TRACKER")"
  rows="$(table_rows "$sec9" tracker)"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    [ "$(cell "$row" 1)" = "$1" ] || continue
    tracker_skill "$(cell "$row" 2)" 2>/dev/null | cut -d'|' -f1
    return 0
  done <<EOF
$rows
EOF
  printf ''
}

# prefix_skill <prefix> -- the TS-1 skill that prefix's §9 row resolves to, or
# `n/a`. The sibling of prefix_tracker(), and the mechanism §13's
# `sprint_check_skill` pointer is followed through.
prefix_skill() {
  local sec9 rows row
  sec9="$(section_region 9 "$SEC_TRACKER")"
  rows="$(table_rows "$sec9" tracker)"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    [ "$(cell "$row" 1)" = "$1" ] || continue
    tracker_skill "$(cell "$row" 2)" 2>/dev/null | cut -d'|' -f2
    return 0
  done <<EOF
$rows
EOF
  printf 'n/a'
}

# `repo_sprint_marker()` IS GONE (BTG-242). It read the value of one of §13's
# three repo-level HTML markers, and all three were REMOVED from the grammar --
# their presence is now `sprint.binding.form_removed`. Nothing reads a marker
# value any more, so a reader for one would be a second place for the removed
# form to come back.
#
# WHAT WENT WITH IT, stated so the retirement is visible rather than inferred:
#   the repo-level `yes` branch     -> gone; there is no repo level.
#   the INHERITED-yes degrade       -> gone, AND ITS STDERR DIAGNOSTIC WITH IT.
#                                      It reported a trackerless prefix inheriting
#                                      a repo-level enablement nobody wrote for it;
#                                      with no repo level there is nothing to
#                                      inherit. The EXPLICIT contradiction -- a
#                                      typed per-prefix `Yes` on a trackerless
#                                      prefix -- still halts
#                                      `sprint.binding.enabled_without_tracker`.
#   `source=repo-level`             -> leaves §13's vocabulary; `default` takes
#                                      its place on the unmatched-prefix path.


# --- --sprint ------------------------------------------------------------
#
# §13's polarity is the THIRD distinct one in this design:
# fail-safe-toward-DISABLED. An absent or malformed enablement resolves to the
# Confirm path -- a prompt, no external call -- never to Block and never to a
# tracker query. It is never unified with §9's fail-loud or §10's mint.
resolve_sprint() {
  local sec13 rows row rp enabled fallback
  sec13="$(section_region 13 "$SEC_SPRINT")"
  # NB-2 (DEC-030 cl.5): §13's fail-safe-toward-DISABLED polarity governs an
  # ABSENT declaration, never a PRESENT-and-unreadable one -- DEC-028's rule, one
  # section over, where it had not been applied.
  require_locatable_13 "$sec13"
  # THE REMOVED FORM IS REFUSED BEFORE ANY ROW IS READ (BTG-242), after the
  # locatable check because an unlocatable §13 has no region for a marker to be
  # found in -- and `require_locatable_13` is the rule that covers that shape.
  require_sprint_form_removed "$sec13"
  rows="$(table_rows "$sec13" sprint-enforcement)"

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    rp="$(cell "$row" 1)"
    [ "$rp" = "$PREFIX" ] || continue
    enabled="$(cell "$row" 2)"
    fallback="$(cell "$row" 4)"
    case "$(printf '%s' "$enabled" | tr '[:upper:]' '[:lower:]')" in
      yes)
        # DEC-008: an EXPLICIT per-prefix Yes on a prefix that binds no tracker
        # is a typed statement of intent that cannot be honoured -- sprint
        # enforcement is a tracker QUERY and there is nothing to query -- so it is
        # REFUSED rather than quietly downgraded. The INHERITED form of the same
        # contradiction (below) degrades instead, because nobody wrote it.
        if [ "$(prefix_tracker "$PREFIX")" = "inner-source" ]; then
          halt sprint.binding.enabled_without_tracker \
            "prefix '$PREFIX' explicitly enables sprint enforcement but its §9 row binds no tracker; sprint enforcement is a tracker query and there is nothing to query"
        fi
        # THE SKILL IS A POINTER, NOT A VALUE. §13's own cell reads "resolved
        # from §9's <PREFIX> row", and it is followed rather than read: the
        # sprint-check skill and the sync skill MUST be the same adapter for a
        # given prefix, and letting §13 name one independently is exactly how
        # the two come to disagree.
        printf 'enabled=yes\n'
        printf 'skill=%s\n' "$(prefix_skill "$PREFIX")"
        printf 'fallback=%s\n' "$fallback"
        printf 'source=per-prefix\n'
        return 0 ;;
      no)
        printf 'enabled=no\n'
        printf 'skill=n/a\n'
        printf 'fallback=n/a\n'
        printf 'source=per-prefix\n'
        return 0 ;;
      *)
        # An unrecognized per-prefix CELL is not the same subject as an
        # unreadable repo-wide MARKER. `disabled` is the safe reading of "we
        # cannot tell"; it is NOT the safe reading of "you said something we do
        # not understand", where it would turn a typo into a guard that is off
        # and looks on.
        halt sprint.binding.marker_unrecognized \
          "prefix '$PREFIX' declares sprint enablement '$enabled', which is neither Yes nor No" ;;
    esac
  done <<EOF
$rows
EOF

  # UNMATCHED PREFIX => DISABLED, FROM A RULE (BTG-242 / G-5). There are no
  # repo-level markers left to fall through to, so this is not a fall-through: it
  # is §13's polarity stated directly, and the rule is now the ONLY thing holding
  # it. Adopting the per-prefix form for ONE project must not silently switch
  # sprint enforcement on -- or off-with-a-Block -- for every other prefix.
  #
  # NOT A MANDATORY WILDCARD ROW. That alternative was explicitly rejected: it
  # would make an unmatched prefix in a §13 with no `*` row FAIL LOUD, which is
  # §9's polarity imported into §13 and unifies two of the three -- forbidden by
  # ADR_CADENCE-0071 clause 3, which this change reaffirms rather than amends.
  #
  # `fallback` is reported even when DISABLED because disabled is not the absence
  # of a verdict: the guard still runs and still takes the Confirm path. Leaving
  # the caller to invent the path is where a Block would appear from nowhere.
  #
  # `source=default` REUSES §10'S EXISTING WORD rather than inventing one, and
  # says the same thing it says there: no row matched, so the section's own rule
  # answered. `source=repo-level` leaves the vocabulary with the repo level.
  #
  # SILENT. This is THE answer, not a degraded one. The INHERITED-YES degrade and
  # its stderr diagnostic retire here: they existed because a repo-level `yes`
  # could be inherited by a trackerless prefix nobody wrote a row for, and there
  # is no repo-level `yes` left to inherit. The EXPLICIT contradiction -- a typed
  # per-prefix `Yes` on a trackerless prefix -- still halts, above.
  printf 'enabled=no\n'
  printf 'skill=n/a\n'
  printf 'fallback=Confirm\n'
  printf 'source=default\n'
}
