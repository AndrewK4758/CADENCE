#!/usr/bin/env bash
#
# jira-worklog.sh -- project each NEW `stage_effort` entry as its own Jira worklog.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (BTG-064, transport-independent):
# a posted worklog is IMMUTABLE. It is **never updated and never deleted** by this
# skill, no matter how far it diverges from `metadata.yaml`; there is no worklog
# update path and no worklog delete path here, and none may be added. Worklogs
# CLAIRE did not author are outside its ownership boundary and are never
# enumerated for action, and tracker totals (Jira *Time Spent*) are never compared
# to `actual_effort` -- `metadata.yaml` is the sole system of record for realized
# effort (CLAIRE_ORG.md sections 9 and 12).
#
# Upstream: the /claire-sync-jira orchestrator, after the status transition.
# Downstream: `GET`/`POST $JIRA_BASE_URL/rest/api/2/issue/{key}[/worklog]`.
# Spec: archive/BTG-075/spec.md (AC-8) ; jira-server-scripts.md ; BTG-064.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> --issue-key <KEY>
#   stdout : worklogs_posted=<n>  worklog_result=<verdict>
#            worklog_watermark_advance=<iso8601>   (only when it advances)
#   stderr : syncjs.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# READS metadata.yaml, NEVER writes it (AC-6); the watermark advance is RETURNED
# and applied once by the orchestrator at end-of-operation.
#
# SOURCES a sibling module (BTG-247): argument parsing, config-toggle,
# Epic-skip and candidate-selection logic live in jira-worklog-prepare.sh.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

# ---------------------------------------------------------------------------
# PRESERVED GUARANTEES (BTG-064, transport-neutral -- re-homed here verbatim by
# BTG-075 DEC-003; the /claire-sync-youtrack adapter states the identical semantics).
#  * RE-RUN. A repeated invocation posts exactly once: the watermark selects and
#    the suppress-only scan closes the crash-recovery window where a post
#    succeeded but the watermark write did not persist -- together they
#    never duplicate a worklog. A **missing** marker can never cause a post, and
#    the run must do **NOT** advance the watermark before a post and its
#    verification have both succeeded.
#  * SELECTION + ADVANCE. An entry is already-synced iff its `at` is at or below
#    the repo-owned `worklog_watermark_at`; after a verified post the run advances
#    the watermark to that entry's `at`. A suppressed (already-marked) entry does
#    not re-post, and the run must still advance the watermark past it.
#  * BOOTSTRAP. Keys on the KEY'S ABSENCE (or an explicit YAML null, which the
#    metadata reader returns as a real JSON null, not the string "null"):
#    ABSENT is NOT the same as EMPTY. A present-but-empty value has never
#    projected, so it posts normally. Any other value must be ISO-8601.
#  * MALFORMED ENTRY. An entry missing stage/effort/at is reported and
#    HALTS the batch at that entry: later entries are NOT posted in that run,
#    the watermark stays put, do not guess a duration, and
#    never advance the watermark past it. That halt is SCOPED to this step -- the
#    description, status, assignee and links for this ticket still run.
#  * TOGGLE. `worklog_creation_enabled` is an adopter opt-out whose
#    absent resolves to ENABLED -- only an explicit `false` disables it, and
#    Epic tickets skip this step entirely (an Epic carries no stage effort).
#  * COMMENT. The comment is exactly the idempotency marker plus a fixed label --
#    no numeric multiplier value or arithmetic expression leaks into it, and
#    posting does not alter the assignee, the status, or any field beyond the
#    ones Jira derives from the worklog itself.
#  * CAPABILITY. The worklog-postcheck-capability declaration is a framework
#    constant, not an opt-out: absent/malformed/non-allowlisted is a HALT
#    reporting the offending value verbatim, and it must
#    never silently resolve to `none` -- only an explicit `none` sanctions it.
#  * VERIFICATION. The verdict comes from a fresh re-read, never from the add
#    response's own flags: `remaining_estimate_updated` MUST NOT be consulted --
#    it was live-observed reporting false on a decrement that demonstrably
#    happened (PLAYSCRUM-3390).
#  * OWNERSHIP. Worklogs CLAIRE did not author are not enumerated for action, no
#    matter how far they diverge. A failed post-check hands off to the operator and
#    corrects nothing -- today it touches none of them, nothing posted in a
#    prior run is ever touched again, and tracker totals are
#    never compared to `actual_effort`; no equality is expected or enforced.
# ---------------------------------------------------------------------------

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-worklog-prepare.sh"
# BTG-315: the split-mode module, sourced unconditionally (its functions are
# only ever CALLED when AGENT_USER is non-empty -- an unconfigured run never
# reaches them, so this source alone changes nothing observable, AC-4).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-worklog-agent.sh"
js_worklog_parse_and_prepare "$@"

# `remaining_of` is jira-lib.sh's, sourced above; a byte-identical copy also lived
# here and merely shadowed it -- one predicate, one home (BTG-079 AC-7 headroom).

# --------------------------------------------------------------------------
# Candidate selection -- REPO-OWNED idempotency (BTG-064)
# --------------------------------------------------------------------------
# An entry is **already-synced iff** `entry.at <= worklog_watermark_at`. Tracker
# state is NEVER an input to that decision, so an operator who edits or deletes a
# worklog is never overridden by a backfill.
# Bootstrap: the key ABSENT ENTIRELY -- or present with an explicit YAML null,
# which the metadata reader returns as a real JSON null -- means a ticket carried
# over from a pre-BTG-064 fork. Seed forward to max(stage_effort[].at), post
# NOTHING that run, never backfill. PRESENT-BUT-EMPTY (`""`, as every new ticket
# ships) is NOT a bootstrap: it posts from its very first sync. The condition is
# kept on ONE line so it stays an EXTRACTABLE, executable jq construct -- the
# parity harness runs this exact program against all three states.
WATERMARK_STATE=bootstrap
if jq -e '(has("worklog_watermark_at") | not) or (.worklog_watermark_at == null) or ((.worklog_watermark_at | type) == "array")' <<<"$JS_METADATA_JSON" >/dev/null 2>&1; then WATERMARK_STATE=bootstrap; else WATERMARK_STATE=present; fi
WATERMARK="$(js_metadata_get '.worklog_watermark_at')"

# VALIDATE before trusting: the selection test is a LEXICAL comparison, so an
# unusable scalar sorts above every 20xx timestamp and suppresses the whole batch
# while reporting "up to date" -- false, not merely silent. Absent and empty are
# legitimate (bootstrap / never-projected); anything else must be ISO-8601.
if [[ "$WATERMARK_STATE" == "present" && -n "$WATERMARK" ]] \
   && [[ ! "$WATERMARK" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  js_halt "$JS_EXIT_FAIL" syncjs.worklog.watermark_malformed \
    "worklog_watermark_at is '$WATERMARK', which is not an ISO-8601 instant (YYYY-MM-DDTHH:MM:SSZ) -- refusing to use it as the selection base; an unusable watermark would suppress every entry while reporting 'up to date'"
fi

ENTRY_COUNT="$(jq -r '(.stage_effort // []) | length' <<<"$JS_METADATA_JSON")"

if [[ "$WATERMARK_STATE" == "bootstrap" ]]; then
  if [[ "$ENTRY_COUNT" -eq 0 ]]; then
    js_report syncjs.worklog.watermark_seeded "no stage_effort entries to seed from; nothing posted"
    js_emit worklogs_posted 0
    js_emit worklog_result seeded
    exit "$JS_EXIT_OK"
  fi
  SEED="$(jq -r '[.stage_effort[].at] | max' <<<"$JS_METADATA_JSON")"
  js_report syncjs.worklog.watermark_seeded \
    "seeded to $SEED; $ENTRY_COUNT entries skipped (a pre-BTG-064 carry-over never backfills history)"
  js_emit worklogs_posted 0
  js_emit worklog_result seeded
  js_emit worklog_watermark_advance "$SEED"
  exit "$JS_EXIT_OK"
fi

js_worklog_select_candidates

POSTED=0
ADVANCE=""
RESULT=none
# BTG-315: counts agent-leg rejections across the whole run; emitted on
# stdout only in split mode (AGENT_USER non-empty), so an unconfigured run's
# stdout key set is byte-unchanged (AC-4).
AGENT_LEGS_REJECTED=0

finish() {
  # A halt OUTRANKS a partial success: entries were dropped, so a bare "posted"
  # would describe the run as complete when it is not. Everything else keeps its
  # prior verdict semantics.
  #
  # `RESULT` is DERIVED here only when the call site left it unset. Re-derived
  # unconditionally -- with `POSTED` incrementing after the add but BEFORE the
  # verification -- `posted` always won, overwriting every `postcheck-failed`:
  # stderr said the post was not absorbed while stdout, the only channel the
  # orchestrator parses, said `posted`, disabling the check BTG-064 enforces.
  if [[ -n "${MALFORMED:-}" ]]; then
    if [[ "$POSTED" -gt 0 ]]; then RESULT=posted-then-halted-malformed
    else RESULT=halted-malformed; fi
  elif [[ "$RESULT" == "none" && "$POSTED" -gt 0 ]]; then
    RESULT=posted
  fi
  js_emit worklogs_posted "$POSTED"
  js_emit worklog_result "$RESULT"
  [[ -n "$ADVANCE" ]] && js_emit worklog_watermark_advance "$ADVANCE"
  [[ -n "$AGENT_USER" ]] && js_emit agent_legs_rejected "$AGENT_LEGS_REJECTED"
  exit "${1:-$JS_EXIT_OK}"
}

# The malformed report is UNCONDITIONAL, not a branch of the empty-candidate case:
# with postable entries AHEAD of it the candidate list is non-empty, so reporting
# it only when the list was empty swallowed it entirely (the run posted what
# preceded it, dropped the rest, and still reported a clean result).
if [[ -n "$MALFORMED" ]]; then
  js_report syncjs.worklog.entry_malformed \
    "$MALFORMED is missing stage/effort/at -- halting the batch here; later entries are NOT posted this run and the watermark stays put"
  RESULT=halted-malformed
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  [[ -n "$MALFORMED" ]] || \
    js_report syncjs.worklog.up_to_date "every stage_effort entry is at or below the watermark ($WATERMARK)"
  finish
fi

# --------------------------------------------------------------------------
# The SUPPRESS-ONLY marker scan (BTG-064 / crash recovery)
# --------------------------------------------------------------------------
# It runs ONLY over entries the watermark already selected and may only REMOVE
# them -- it can never TRIGGER a post, so a missing marker can never cause
# anything. It closes the window where a post succeeded but the watermark write
# did not persist. The read-back match is BRACKET-AGNOSTIC: Jira returns the
# comment with the brackets STRIPPED, so it keys on the `stage=<stage> at=<at>`
# core; matching literal brackets would fail to find the worklog and DUPLICATE it.
if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY/worklog"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "GET /rest/api/2/issue/$ISSUE_KEY/worklog could not reach ${BASE_URL%/}"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.worklog.marker_scan_rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY/worklog returned HTTP $JS_HTTP_STATUS -- refusing to post without the crash-recovery scan (a duplicate worklog cannot be undone: worklogs are immutable)"
fi
if ! EXISTING_MARKERS="$(printf '%s' "$JS_HTTP_BODY" \
      | jq -r 'if type == "object" then (.worklogs // [])[].comment // empty else error("not an object") end' 2>/dev/null)"; then
  js_halt "$JS_EXIT_FAIL" syncjs.worklog.marker_scan_rejected \
    "the worklog read returned an unparseable body -- refusing to post without the crash-recovery scan"
fi

BODY_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.worklog.scratch_unavailable "no scratch file could be staged for the worklog body -- posting NOTHING; a worklog cannot be un-posted, so a body this run could not stage is never sent on a guess"
trap 'rm -f "$BODY_FILE" 2>/dev/null' EXIT

for candidate in "${CANDIDATES[@]}"; do
  STAGE="${candidate%%|*}"
  REST="${candidate#*|}"
  EFFORT="${REST%%|*}"
  AT="${REST#*|}"
  MARKER="stage=$STAGE at=$AT"

  # BTG-315: split mode is a COMPLETE alternate path for this candidate,
  # handled entirely in jira-worklog-agent.sh (its own suppress-scan, its own
  # zero-leg skip, its own two-leg posting). The unsplit branch below this
  # is UNREACHABLE when AGENT_USER is set, and is otherwise byte-unchanged
  # by this ticket (AC-4).
  if [[ -n "$AGENT_USER" ]]; then
    js_worklog_process_split_candidate "$STAGE" "$EFFORT" "$AT"
    continue
  fi

  # BTG-315 (additive, AC-4 edge case): a STRAY split-mode marker -- left over
  # from a crashed split run, or from a since-emptied agent-time-user cell --
  # ALSO suppresses the whole entry here, exactly as the unsplit marker does.
  # This never changes the byte-identical common case (no split marker can
  # exist on a fork that never ran split mode); it only closes the one edge
  # case AC-4 names: a stray leg marker must never be topped up with a full
  # duplicate post once an adopter reverts to unsplit.
  if grep -qF "$MARKER" <<<"$EXISTING_MARKERS" \
     || grep -qF "stage=$STAGE op-at=$AT" <<<"$EXISTING_MARKERS" \
     || grep -qF "stage=$STAGE agent-at=$AT" <<<"$EXISTING_MARKERS"; then
    js_report syncjs.worklog.skipped_already_logged "skipped-already-logged (marker present) for stage=$STAGE at=$AT -- advancing the watermark to observed reality"
    ADVANCE="$AT"; continue
  fi
  # Post-nothing-but-ADVANCE; AFTER the scan, BEFORE duration_minutes. See jira-lib.sh.
  js_worklog_skip_zero syncjs.worklog.skipped_zero "$EFFORT" "$STAGE" "$AT" && { ADVANCE="$AT"; continue; }

  if ! POSTED_MINUTES="$(duration_minutes "$EFFORT")"; then
    js_report syncjs.worklog.entry_malformed \
      "stage=$STAGE at=$AT carries an unparseable effort '$EFFORT' -- halting the batch here, never guessing a duration"
    RESULT=halted-malformed
    finish
  fi

  # BASELINE -- read BEFORE the post (one captured after is the post-state).
  # ONE assignment site, on ONE line: the parity gate anchors its ordering check on
  # this line's number, so a second assignment would let a relocated baseline still
  # test as correctly ordered (a vacuous pass).
  #
  # TWO OUTCOMES, never conflated (Behavior 5): whether the READ succeeded is a
  # different question from whether the issue HAS a Remaining Estimate. A failed
  # read cannot verify absorption -- fail loud, do NOT advance; a SUCCESSFUL read
  # of a never-estimated issue is BTG-064's Info skip, which DOES advance
  # (archive/BTG-064/spec.md:183). Derived from the value's emptiness they were ONE
  # test, so every unestimated ticket took a false Critical that retried forever.
  BASELINE_OK=no
  BASELINE_READ=no
  BASELINE_VALUE=""
  if [[ "$CAPABILITY" == "remaining-estimate-decrement" ]] \
     && js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=timetracking" && js_http_ok \
     && BASELINE_VALUE="$(remaining_of "$JS_HTTP_BODY")"; then BASELINE_READ=yes; fi
  # ONE assignment site, ONE line, still ABOVE the post (parity-gate anchor).
  REMAINING_BEFORE="$(if [[ "$BASELINE_READ" == "yes" ]]; then printf '%s' "$BASELINE_VALUE"; fi)"
  BASELINE_OK="$BASELINE_READ"

  # The ADD. adjustEstimate=auto is passed EXPLICITLY and no Remaining override is
  # ever sent -- never `new`/`manual` (which set a value), never `leave` (which
  # freezes Remaining), and never a newEstimate/reduceBy field. Jira reduces
  # Remaining by the posted timeSpent, calculating it on its own.
  js_build_body "$BODY_FILE" syncjs.worklog.body_unbuildable "the worklog body for $ISSUE_KEY (stage=$STAGE at=$AT)" \
    -n --arg spent "$EFFORT" --arg comment "[claire $MARKER] CLAIRE $STAGE stage effort" '{timeSpent: $spent, comment: $comment}' || exit "$JS_EXIT_FAIL"
  if ! js_rest POST "/rest/api/2/issue/$ISSUE_KEY/worklog?adjustEstimate=auto" "$BODY_FILE"; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "POST /rest/api/2/issue/$ISSUE_KEY/worklog could not reach ${BASE_URL%/}"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.worklog.post_rejected \
      "POST /rest/api/2/issue/$ISSUE_KEY/worklog returned HTTP $JS_HTTP_STATUS for stage=$STAGE at=$AT"
  fi
  POSTED=$((POSTED + 1))

  # POST-ADD VERIFICATION -- did the tracker ABSORB the worklog? The verdict comes
  # from this FRESH re-read alone. The add response's own
  # `*_updated` self-report is NEVER consulted: it was live-observed to report
  # `false` while the decrement had demonstrably happened, so a verdict derived
  # from it would fail on every CORRECT post (BTG-064 DEC-004).
  if [[ "$CAPABILITY" == "none" ]]; then
    js_report syncjs.worklog.postcheck_unsupported \
      "the declared worklog_postcheck_capability is 'none' -- stage=$STAGE at=$AT posted, absorption not verified"
    ADVANCE="$AT"
    continue
  fi
  if [[ "$BASELINE_OK" != "yes" ]]; then
    js_report syncjs.worklog.postcheck_failed \
      "the pre-add baseline READ failed for stage=$STAGE at=$AT (unreachable, rejected, or an unparseable body) -- a baseline is never inferred post-hoc; the watermark is NOT advanced"
    RESULT=postcheck-failed
    finish
  fi
  if [[ -z "$REMAINING_BEFORE" ]]; then
    js_report syncjs.worklog.postcheck_skipped_no_estimate \
      "the issue carries no Remaining Estimate, so there is no baseline to compare -- stage=$STAGE at=$AT posted"
    ADVANCE="$AT"
    continue
  fi
  if ! BEFORE_MINUTES="$(duration_minutes "$REMAINING_BEFORE")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the pre-add baseline '$REMAINING_BEFORE' is an unparseable payload -- Never treated as a pass; the watermark is NOT advanced"
    RESULT=postcheck-indeterminate
    finish
  fi

  REMAINING_AFTER=""
  if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=timetracking" || ! js_http_ok \
     || ! REMAINING_AFTER="$(remaining_of "$JS_HTTP_BODY")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the post-add re-read for stage=$STAGE at=$AT was unreachable, rejected, or unparseable -- never treated as a pass; the watermark is NOT advanced"
    RESULT=postcheck-indeterminate
    finish
  fi
  if [[ "$BEFORE_MINUTES" -lt "$POSTED_MINUTES" ]]; then
    js_report syncjs.worklog.postcheck_skipped_floor \
      "the baseline ($REMAINING_BEFORE) is less than the posted $EFFORT, so Jira floors Remaining at zero and the identity cannot hold -- a skip, never a failure"
    ADVANCE="$AT"
    continue
  fi
  AFTER_MINUTES=0
  if [[ -n "$REMAINING_AFTER" ]] && ! AFTER_MINUTES="$(duration_minutes "$REMAINING_AFTER")"; then
    js_report syncjs.worklog.postcheck_indeterminate \
      "the post-add re-read returned '$REMAINING_AFTER', which is not a parseable duration -- never treated as a pass"
    RESULT=postcheck-indeterminate
    finish
  fi
  # pass iff remaining_before - remaining_after >= the posted duration. A LARGER
  # decrease (an operator logged time concurrently) still passes: `>=`, not `==`.
  if [[ $((BEFORE_MINUTES - AFTER_MINUTES)) -ge "$POSTED_MINUTES" ]]; then
    js_report syncjs.worklog.posted \
      "posted stage=$STAGE $EFFORT at=$AT; Remaining $REMAINING_BEFORE -> ${REMAINING_AFTER:-0m} absorbed the post"
    ADVANCE="$AT"
    continue
  fi
  js_report syncjs.worklog.postcheck_failed \
    "$ISSUE_KEY stage=$STAGE at=$AT: baseline=$REMAINING_BEFORE observed=${REMAINING_AFTER:-0m} expected a decrease of at least $EFFORT -- the tracker did not absorb the post; the watermark is NOT advanced and this is handed to the operator, never self-corrected"
  RESULT=postcheck-failed
  finish
done

finish
