#!/usr/bin/env bash
#
# jira-ac-lib.sh -- the BTG-046 acceptance-criteria PROJECTION, as one unit.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075/BTG-079).
# Invariant relied on from outside this boundary: the instance's acceptance-criteria
# custom field is a CHECKLIST field -- its value must be an ARRAY of checklist
# objects, and a text body is rejected 400 ("Must be an array of checklist items").
#
# It is SOURCED, never invoked, and runs nothing on load. It never writes
# `metadata.yaml` (AC-6).
#
# It owns THREE functions. One WRITES -- `PUT /rest/api/2/issue/{key}` against the
# discovered field -- and two READ: `js_ac_section` and `js_ac_items`, which arrived
# from `jira-meta.sh` under BTG-111's pre-authorized contingency relocation
# (BTG-111 DEC-006 / DEC-019) because the fold pushed that file past the ceiling.
# They land HERE and nowhere else because this file is their SOLE consumer, below.
# They are two halves of ONE predicate -- section PRESENCE and item EXTRACTION --
# and are deliberately co-located for the reason their own banner records: as two
# independent awk programs they could disagree about where the section starts.
#
# Why it is a library rather than a block in `jira-write-issue.sh`. It landed here
# by RELOCATION under the 400-line DX ceiling, on the DEC-057 / DEC-060 precedent --
# the third time this subsystem has had to buy lines that way, and the reason
# BTG-079 item 7 exists. The unit chosen is the whole `syncjs.ac.*` concern: one
# condition namespace, one result enumeration, one endpoint, and one caller,
# `jira-write-issue.sh`, which remains the sole `js_emit ac_result` site (this file
# emits nothing itself).
#
# Upstream: `jira-write-issue.sh`, AFTER its own create/update write has landed.
# Downstream: `GET /rest/api/2/field`, `GET .../issue/{key}/editmeta`, and the AC
#   `PUT .../issue/{key}` on the adopter's Jira Server/DC; reads the ticket's
#   `problem.md` under `specs/` then `archive/`.
# Spec: archive/BTG-079/decisions.md (DEC-003) ; archive/BTG-075/spec.md (AC-3/AC-9).
#
# Contract:
#   js_ac_project -- runs the projection and leaves the verdict in AC_RESULT
#                    (disabled|skipped|source-unreadable|section-absent|
#                     scratch-unavailable|body-unbuildable|items-unrecognized|
#                     projected|rejected), which its CALLER emits as `ac_result`.
#
# It reads and writes its caller's variables by design ($AC_TOGGLE_RC, $TICKET,
# $ISSUE_KEY, $ISSUE_TYPE, $IS_EPIC, $BASE_URL, $ESTIMATE_RESULT in; $AC_RESULT
# out) -- that is what makes the relocation TEXTUAL, and therefore provably
# behaviour-preserving, rather than a re-design wearing a refactor's clothes.

js_ac_project() {
  # --- BTG-046: project the repo Acceptance Criteria to the dedicated field ----
  # Toggle-gated and BEST-EFFORT: a refusal is reported and the sync continues, never
  # halting the ticket. The field is discovered by EXACT name; ambiguity is skipped.
  AC_RESULT=disabled
  # An Epic skips the field ENTIRELY and exits here. The payload lives in
  # jira-epic-lib.sh beside the umbrella early exit, which emits the same five keys.
  [[ "$IS_EPIC" == "yes" ]] \
    && js_epic_ac_skip_exit "$TICKET" "$ISSUE_KEY" "$BASE_URL" "$ESTIMATE_RESULT"
  # $AC_TOGGLE_RC was resolved before the write (see above); this only CONSUMES it.
  if [[ "$AC_TOGGLE_RC" -eq 0 ]]; then
    AC_RESULT=skipped
    AC_FIELD_NAME="$(js_config_map acceptance_criteria field_name)" || AC_FIELD_NAME=""
    if [[ -n "$AC_FIELD_NAME" ]] && js_rest GET "/rest/api/2/field" && js_http_ok; then
      AC_IDS="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$AC_FIELD_NAME" \
        'if type=="array" then (.[] | select(.name == $n) | .id) else empty end' 2>/dev/null)"
      AC_COUNT="$(grep -c . <<<"$AC_IDS" || true)"
      [[ -z "$AC_IDS" ]] && AC_COUNT=0
      if [[ "$AC_COUNT" -eq 0 ]]; then
        js_report syncjs.ac.field_absent \
          "no field named exactly \"$AC_FIELD_NAME\" -- skipping the AC projection; the sync continues"
      elif [[ "$AC_COUNT" -gt 1 ]]; then
        js_report syncjs.ac.field_ambiguous \
          "$AC_COUNT fields named exactly \"$AC_FIELD_NAME\" -- skipping, never guessing which one this instance means"
      else
        # Items come from problem.md's "Acceptance Criteria" checklist.
        # Every element is written always unchecked: the repo's [x]/[ ] state is
        # discarded and only the item TEXT projects. jq encodes each item; the body is an ARRAY of checklist objects
        # -- a text body is rejected 400 ("Must be an array of checklist items").
        # FOUR source states, of which only the first reaches the PUT (Behavior 5):
        #   1. section PRESENT -> project its items; a section present and
        #      genuinely EMPTY sends `[]`, a SANCTIONED deliberate clear.
        #   2. file UNREADABLE -> a read failure. NO write.
        #   3. file readable but NO `## Acceptance Criteria` heading -> also a read
        #      failure: awk yielded nothing, jq emitted `[]`, and the PUT wiped the
        #      QA hand-off record while reporting `projected`. NO write.
        #   4. section present WITH CONTENT but no checklist item recognized -> a
        #      PARSE failure (archive/PI-009 writes its criteria as ordinary
        #      bullets); "nothing parsed" is not "the author cleared it". NO write.
        AC_FIELD_ID="$AC_IDS"
        # Per-type availability pre-check: a field not on THIS issue's edit screen
        # rejects the write 400, so read the edit metadata and skip cleanly.
        if js_rest GET "/rest/api/2/issue/$ISSUE_KEY/editmeta" && js_http_ok \
           && ! printf '%s' "$JS_HTTP_BODY" | jq -e --arg f "$AC_FIELD_ID" '(.fields // {}) | has($f)' >/dev/null 2>&1; then
          js_report syncjs.ac.field_unsupported_type \
            "$AC_FIELD_ID is not on the ${ISSUE_TYPE:-(unasserted -- this ticket carries no type:)} edit screen -- skipping the AC write; the sync continues"
          AC_FIELD_ID=""
        fi
        PROBLEM="${CADENCE_REPO_ROOT:-.}/specs/$TICKET/problem.md"
        [[ -r "$PROBLEM" ]] || PROBLEM="${CADENCE_REPO_ROOT:-.}/archive/$TICKET/problem.md"
        if [[ -n "$AC_FIELD_ID" && ! -r "$PROBLEM" ]]; then
          AC_RESULT=source-unreadable
          js_report syncjs.ac.source_unreadable \
            "$TICKET has no readable problem.md under specs/ or archive/ -- issuing NO acceptance-criteria write; an unreadable source is a read failure, never a request to clear the field"
          AC_FIELD_ID=""
        fi
        # SECTION PRESENCE is separate from file readability, and both it and the
        # extraction now come from jira-meta.sh, so the two CANNOT disagree.
        AC_SECTION=""
        if [[ -n "$AC_FIELD_ID" ]] && ! AC_SECTION="$(js_ac_section "$PROBLEM")"; then
          AC_RESULT=section-absent
          js_report syncjs.ac.section_absent \
            "$PROBLEM has no \"## Acceptance Criteria\" heading -- issuing NO acceptance-criteria write; a section that is not there is a read failure, never a request to clear the field (an empty section, which IS a sanctioned clear, still clears)"
          AC_FIELD_ID=""
        fi
        # STAGING and BUILD are probed SEPARATELY, and each REFUSES the write rather
        # than degrading into one, because the state-4 guard below cannot substitute
        # for either: it reads `jq '.fields[$f] | length' "$AC_JSON"`, which on an
        # unstaged or zero-length file errors to "" and never to the "0" it compares.
        # An unstaged path then goes out as a BODYLESS PUT (js_rest omits
        # `--data-binary` when the path is empty) and an EMPTY FILE as an empty-bodied
        # one -- both accepted by a permissive server, CLEARING the field while the run
        # reports `projected`. Same lost write, two doors (BTG-079 AC-2 closed the
        # second; `mktemp`'s own stderr is suppressed because DEC-001 gives stderr to
        # `syncjs.*` conditions alone).
        AC_JSON=""
        if [[ -n "$AC_FIELD_ID" ]] && ! AC_JSON="$(mktemp 2>/dev/null)"; then
          AC_RESULT=scratch-unavailable; AC_FIELD_ID=""
          js_report syncjs.ac.scratch_unavailable "no scratch file could be created for $TICKET's acceptance-criteria body -- issuing NO acceptance-criteria write; an unstaged body degrades the PUT into a BODYLESS PUT that a permissive server accepts, clearing the field while the run reports success"
        fi
        if [[ -n "$AC_JSON" ]] && ! js_ac_items "$AC_SECTION" \
             | js_build_body "$AC_JSON" syncjs.ac.body_unbuildable "the acceptance-criteria body for $TICKET" \
                 -R -s --arg f "$AC_FIELD_ID" \
                 '{fields: {($f): [splits("\n") | select(length > 0) | {name: ., checked: false}]}}'; then
          AC_RESULT=body-unbuildable; AC_FIELD_ID=""
        fi
        # State 4: content the recognizer found NO item in is a PARSE failure, not a
        # clear. archive/PI-009 carries 3 real criteria as ordinary `- **AC1 ...`
        # bullets and rendered to `[]` -- the PUT wiped the field and the run still
        # reported `projected`. Only a section with NO content at all may clear.
        if [[ -n "$AC_FIELD_ID" ]] && grep -q '[^[:space:]]' <<<"$AC_SECTION" \
           && [[ "$(jq -r --arg f "$AC_FIELD_ID" '.fields[$f] | length' "$AC_JSON" 2>/dev/null)" == "0" ]]; then
          AC_RESULT=items-unrecognized
          js_report syncjs.ac.items_unrecognized \
            "$PROBLEM's \"## Acceptance Criteria\" section carries content but NO \`- [ ]\` / \`- [x]\` checklist item was recognized -- issuing NO acceptance-criteria write; a section the parser read nothing out of is a read failure, never a request to clear the field (a section with no content at all, which IS the sanctioned clear, still clears)"
          AC_FIELD_ID=""
        fi
        if [[ -z "$AC_FIELD_ID" ]]; then
          :                                   # skipped above; already reported
        elif js_rest PUT "/rest/api/2/issue/$ISSUE_KEY" "$AC_JSON" && js_http_ok; then
          AC_RESULT=projected
          js_report syncjs.ac.projected "acceptance criteria written to $AC_FIELD_ID"
        else
          AC_RESULT=rejected
          js_report syncjs.ac.write_rejected \
            "HTTP ${JS_HTTP_STATUS:-transport} -- NON-BLOCKING (mirrors syncjs.assign.rejected); the sync continues"
        fi
        rm -f "$AC_JSON"
      fi
    else
      js_report syncjs.ac.field_discovery_failed \
        "could not read the instance field list -- skipping the AC projection; the sync continues"
    fi
  else
    js_report syncjs.ac.disabled "acceptance-criteria sync disabled by config"
  fi
}

# --------------------------------------------------------------------------
# Owned data -- the repo's problem.md acceptance criteria (BTG-046)
# --------------------------------------------------------------------------
# These live beside the metadata.yaml reader because they are the SAME kind of
# thing: a read of repo-owned data that the projection may never write back.
# They are two halves of ONE predicate, deliberately co-located -- the section
# PRESENCE check and the item EXTRACTION used to be two independent awk programs
# in jira-write-issue.sh and could disagree about where the section starts.

# js_ac_section <problem-path> -- print the "## Acceptance Criteria" section
# BODY. The section runs to the NEXT `## ` heading whatever its name -- the
# former `/^## [^A]/` ran straight through "## Assumptions" and projected its
# items as criteria. The heading matches case-INSENSITIVELY, so a case-differing
# heading projects rather than reading as absent.
#
# Returns 1 when the file carries no such heading AT ALL. That is a READ FAILURE
# and never a request to clear the field: awk yields nothing, jq emits `[]`, and
# the PUT wipes the QA hand-off record while reporting success.
js_ac_section() {
  awk 'tolower($0) ~ /^## acceptance criteria/ { inb = 1; found = 1; next }
       inb && /^## / { inb = 0 }
       inb
       END { exit !found }' "$1" 2>/dev/null
}

# js_ac_items <section-body> -- print one criterion per line. Items WRAP (house
# style breaks a criterion over several lines), so continuation lines are joined
# until the next item or a blank line. Only `- [ ]` / `- [x]` lines start an
# item; a section whose content this recognizes NOTHING in is a parse failure for
# the caller to report, never an empty list (DEC-052).
js_ac_items() {
  printf '%s\n' "$1" | awk '
      /^- \[[ xX]\][[:space:]]*/ {
        if (item != "") print item
        sub(/^- \[[ xX]\][[:space:]]*/, "")
        item = $0; next
      }
      /^[[:space:]]*$/ { if (item != "") { print item; item = "" } next }
      /^[[:space:]]+/  { if (item != "") { sub(/^[[:space:]]+/, ""); item = item " " $0 } next }
      { if (item != "") { print item; item = "" } }
      END { if (item != "") print item }'
}
