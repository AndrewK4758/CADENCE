#!/usr/bin/env bash
#
# jira-epic-umbrella-children.sh -- two self-contained pieces of the umbrella
# branch's child-processing concern (BTG-247 row: jira-epic.sh split): the
# whole-child-set pre-validation pass, and the per-child ordered-link write
# (UMBRELLA WRITE 3). MOVED VERBATIM from the parent (pre-split lines
# :123-:155 and :183-:229). Neither is the umbrella replacement's own
# create/retire machinery -- that already lives in jira-umbrella-lib.sh /
# jira-umbrella-retire.sh -- these two are specifically jira-epic.sh's own
# per-run child-loop concerns.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-105), same
# as jira-epic.sh. SOURCED by jira-epic.sh via a ${BASH_SOURCE[0]}-relative
# path, called at the two points in its own execution where this logic used
# to run inline.
#
# References: archive/BTG-247/spec.md ; archive/BTG-247/decisions.md (this
# split's own DEC entry).

# js_epic_umbrella_resolve_children -- pre-validates the WHOLE decomposed_into
# child set before the first write (no `local` for CHILD_PAIRS: the caller
# reads it after this returns). Uses $CHILDREN / $TICKET from the caller.
# Exits the WHOLE process directly on an unresolvable child set, identical to
# the pre-split inline behavior (a best-effort branch that must not leave a
# partial child set half-written).
js_epic_umbrella_resolve_children() {
    # ------------------------------------------------------------------------
    # PRE-VALIDATE THE WHOLE CHILD SET -- before the first write.
    # ------------------------------------------------------------------------
    # `js_metadata_load` HALTS on an unreadable file, which is right for owned data
    # and wrong MID-LOOP: with `[C1, GHOST, C2]` it wrote C1, exited 1 on the ghost,
    # never reached C2, and reported no partial application -- and a non-zero exit
    # from a best-effort script makes the orchestrator halt the whole ticket. The
    # resolution runs in a SUBSHELL so that halt kills only the validation pass,
    # and it runs FIRST so an unresolvable child costs nothing but a report.
    # A child with no `jira_url` is not an error: it is skipped and reported, and
    # its Epic Link is set on the run after it is first synced.
    if ! CHILD_PAIRS="$(
          for child in $CHILDREN; do
            if ! js_metadata_path "$child" >/dev/null 2>&1; then
              js_report syncjs.umbrella.child_unresolved \
                "$TICKET names decomposed_into child '$child', which has no metadata.yaml under specs/ or archive/"
              exit 1
            fi
            js_metadata_load "$child"
            child_url="$(js_metadata_get '.jira_url')"
            if [[ -z "$child_url" ]]; then
              js_report syncjs.umbrella.child_unprojected \
                "$child has no jira_url yet -- its Epic Link is set once it is synced"
              continue
            fi
            printf '%s %s\n' "$child" "${child_url##*/}"
          done
        )"; then
      js_report syncjs.umbrella.child_unresolved \
        "the decomposed_into child set could not be resolved in full -- HALTING the umbrella branch before ANY mutation, so no child is left written while its siblings are not; fix the named child and re-run"
      js_emit epic_result rejected
      exit "$JS_EXIT_OK"
    fi
}

# js_epic_umbrella_link_child_ordered -- UMBRELLA WRITE 3, one iteration: the
# child `is preceded by` link on the replacement. Uses $CHILD_KEY (set by the
# caller's loop) / $UMB_ORDERED / $UMB_PRED_SLOT / $UMB_ISSUE / $ISSUE_KEY /
# $JS_UMB_MODE, and increments the caller's $UMB_FAIL (no `local`).
js_epic_umbrella_link_child_ordered() {
      # ----------------------------------------------------------------------
      # UMBRELLA WRITE 3 -- the child `is preceded by` link, now on the REPLACEMENT.
      # ----------------------------------------------------------------------
      # The CHILD lands before the umbrella is complete, so the child is the
      # PREDECESSOR -- and on this inverted instance the predecessor occupies the
      # slot the calibration names. Native UI must read: on the child's page the
      # umbrella under "precedes"; on the umbrella's page the child under "is
      # preceded by". Only the FAR endpoint moves.
      if [[ -z "$UMB_ORDERED" ]]; then
        # A skipped ordered link is an UNAPPLIED child, so it counts as one: without
        # this the `syncjs.umbrella.partial` guard cannot fire, and a run that
        # linked ZERO children -- reachable on a transient 500 from
        # GET /issueLinkType, the case the type discovery exists to survive --
        # reported the projection complete (the outcome DEC-044 prevents, reached
        # through a different door).
        js_report syncjs.umbrella.ordered_skipped \
          "the $CHILD_KEY -> $UMB_ISSUE ordered link is skipped this run: the instance's link types were unreadable and the type is never guessed"
        UMB_FAIL=$((UMB_FAIL + 1))
      else
        if [[ "$UMB_PRED_SLOT" == "inwardIssue" ]]; then
          UMB_IN="$CHILD_KEY"; UMB_OUT="$UMB_ISSUE"
        else
          UMB_IN="$UMB_ISSUE"; UMB_OUT="$CHILD_KEY"
        fi
        js_link_upsert_ordered "$UMB_ISSUE" "$CHILD_KEY" "$UMB_ORDERED" "$UMB_IN" "$UMB_OUT"
        case "$JS_LINK_OUTCOME" in
          created)    js_report syncjs.umbrella.child_linked \
                        "$UMB_ISSUE is preceded by $CHILD_KEY ('$UMB_ORDERED', inward=$UMB_IN outward=$UMB_OUT)" ;;
          up-to-date) js_report syncjs.umbrella.child_link_present \
                        "$UMB_ISSUE is already preceded by $CHILD_KEY in the correct direction -- left untouched" ;;
          rejected)   js_report syncjs.umbrella.child_link_rejected \
                        "the $CHILD_KEY -> $UMB_ISSUE ordered link was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- reported; the remaining children continue"
                      UMB_FAIL=$((UMB_FAIL + 1)) ;;
          # `read-failed` is the library REFUSING to link blind (its own report is
          # already on stderr); like `unverified` it is an unapplied child, so it
          # counts toward the partial-projection guard.
          unverified|read-failed) UMB_FAIL=$((UMB_FAIL + 1)) ;;
        esac
        # CREATE BEFORE DELETE: only a VERIFIED link on the replacement earns the
        # retire, so no arm above can leave this pair with ZERO ordering links. It
        # runs -- and REPORTS -- after the create's own line, so the audit stream
        # reads in causal order (observed inverted at the §16 live run).
        if [[ "$JS_UMB_MODE" != settled && ( "$JS_LINK_OUTCOME" == created || "$JS_LINK_OUTCOME" == up-to-date ) ]]; then
          js_umbrella_ordered_retire "$ISSUE_KEY" "$CHILD_KEY" "$UMB_ORDERED"
          case "$JS_UMB_RETIRE" in failed|unreadable) UMB_FAIL=$((UMB_FAIL + 1)) ;; esac
        fi
      fi
}
