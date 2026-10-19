#!/usr/bin/env bash
#
# yt-worklog.sh -- project each NEW `stage_effort` entry as its own YouTrack work
# item.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary (BTG-064, transport-independent
# and re-homed here VERBATIM in semantics): a posted work item is IMMUTABLE. It
# is never updated and never deleted by this skill, however far it diverges from
# `metadata.yaml`; there is no work-item update path and no work-item delete path
# here, and none may be added. Work items CADENCE did not author are outside its
# ownership boundary and are never enumerated for action, and tracker totals
# (`Spent time`) are never compared to `actual_effort` -- `metadata.yaml` is the
# sole system of record for realized effort (CADENCE_ORG.md 9 and 12).
#
# THAT INVARIANT IS A POLICY, NOT AN API LIMIT. The live probe UPDATED a work
# item (HTTP 200) and then DELETED it (HTTP 200) -- this API permits both, exactly
# as the sibling tracker's does. Nothing about the transport enforces the
# guarantee, so it is enforced structurally: by no shipped script emitting either
# verb, and by the watermark never being derived from tracker state.
#
# Upstream: the /cadence-sync-youtrack orchestrator's `worklog` step (best-effort), after
#   the state step; `--issue` is the write step's own internal id.
# Downstream: one `GET .../timeTracking/workItems` crash-recovery scan and one
#   `POST .../timeTracking/workItems` per new entry, plus the post-add absorption
#   re-read. It READS `metadata.yaml` and NEVER writes it -- the watermark advance
#   is RETURNED and applied once by the orchestrator at end-of-operation.
# Spec: archive/BTG-176/spec.md (AC-2 Rules, Script inventory) ;
#   archive/BTG-176/spec-2-live-rest-observations.md SS I (every shape OBSERVED).
#
# Contract (three channels):
#   args   : --ticket <id> --issue <internal-id>
#   stdout : worklog_posted=<n>  worklog_suppressed=<n>  worklog_result=<verdict>
#            worklog_watermark_advance=<iso8601>   (only when it advances)
#            postcheck=passed|failed|indeterminate|unsupported   (only when one ran)
#   stderr : syncyt.worklog.* reported conditions
#   exit   : 0 every verdict above, including a scoped batch halt (a rejection
#            HALTS via yt_worklog_finish, which always exits 0 -- BTG-320 OQ-2
#            resolved (a): corrected to match the code, not a behavior change) /
#            1 worklog_watermark_at is not ISO-8601 (syncyt.worklog.watermark_malformed) /
#            2 usage / 3 transport / 4 config HALT
#
# ---------------------------------------------------------------------------
# PRESERVED GUARANTEES (BTG-064, transport-neutral -- the sibling adapter states
# the identical semantics and each was paid for by a defect there).
#  * RE-RUN. A repeated invocation posts exactly once: the watermark SELECTS and
#    the suppress-only scan closes the crash-recovery window where a post
#    succeeded but the watermark write did not persist. Together they never
#    duplicate a work item. A MISSING marker can never cause a post, and the run
#    must NOT advance the watermark before a post and its verification have both
#    succeeded.
#  * SELECTION + ADVANCE. An entry is already-synced iff its `at` is at or below
#    the repo-owned `worklog_watermark_at`; after a verified post the run advances
#    the watermark to that entry's `at`. A suppressed (already-marked) entry does
#    not re-post, and the run must still advance the watermark past it.
#  * BOOTSTRAP. Keys on the KEY'S ABSENCE (or an explicit YAML null, which the
#    metadata reader returns as a real JSON null, not the string "null"): ABSENT
#    is NOT the same as EMPTY. A present-but-empty value has never projected, so
#    it posts normally. Any other value must be ISO-8601.
#  * MALFORMED ENTRY. An entry missing stage/effort/at is reported and HALTS the
#    batch at that entry: later entries are NOT posted in that run, the watermark
#    stays put, no duration is guessed, and the watermark never advances past it.
#    That halt is SCOPED to this step -- the description, state, assignee and
#    links for this ticket still run.
#  * TOGGLE. `worklog_creation_enabled` is an adopter OPT-OUT whose absence
#    resolves to ENABLED -- only an explicit `false` disables it.
#  * MARKER TEXT. The work item's text is exactly the idempotency marker plus a
#    fixed label -- no numeric multiplier value or arithmetic expression leaks
#    into it -- and posting alters no field beyond the ones the instance derives
#    from the work item itself.
#  * CAPABILITY. The post-check capability declaration is a framework constant,
#    not an opt-out: absent/malformed/non-allowlisted HALTs reporting the
#    offending value verbatim, and it never silently resolves to `none` -- only an
#    explicit `none` sanctions non-enforcement.
#  * VERIFICATION. The verdict comes from a FRESH re-read, never from the add
#    response's own echo of what it believes it stored.
#  * OWNERSHIP. Work items CADENCE did not author are not enumerated for action,
#    however far they diverge. A failed post-check hands off to the operator and
#    corrects nothing; nothing posted in a prior run is ever touched again; and
#    tracker totals are never compared to `actual_effort` -- no equality is
#    expected or enforced.
# ---------------------------------------------------------------------------

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--issue)
      # Guard the pair BEFORE the `shift 2` that consumes it -- see the same
      # guard in yt-resolve.sh for why an unguarded `shift 2` spins forever.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.worklog.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket) TICKET="$2" ;;
        --issue)  ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.worklog.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.worklog.usage "--ticket <id> is required"
[[ -n "$ISSUE"  ]] || yt_halt "$YT_EXIT_USAGE" syncyt.worklog.usage \
  "--issue <internal-id> is required -- this step never creates an issue"

yt_config_require

# The time-tracking field whose growth the post-add check reads. It is a
# YouTrack MODEL field name, handled the same way `State` is in yt-transition.sh
# and `Assignee` is in yt-assign.sh: the adapter's `$type` constants and standard
# field names are model vocabulary, while every BUNDLE VALUE and every mapping is
# resolved from the config. Naming it once, here, is what keeps the three audit
# lines below and the read that feeds them talking about the same field.
YT_SPENT_FIELD='Spent time'

POSTED=0
SUPPRESSED=0
ADVANCE=""
RESULT=none
POSTCHECK=""
# BTG-315: counts agent-leg rejections across the whole run; emitted on
# stdout only in split mode (AGENT_USER non-empty), so an unconfigured
# run's stdout key set is byte-unchanged (AC-4).
AGENT_LEGS_REJECTED=0

# yt_worklog_finish -- the SINGLE exit. Publishes the three channels in one
# place, so the stdout verdict and the stderr stream can never disagree about
# what happened.
#
# A malformed-entry halt OUTRANKS a partial success: entries were dropped, so a
# bare `posted` would describe the run as complete when it is not. RESULT is
# derived here ONLY when a call site left it unset -- re-deriving it
# unconditionally is how `posted` came to overwrite every `postcheck-failed` on
# the sibling, so stderr said the post was not absorbed while stdout, the only
# channel the orchestrator parses, said it was.
yt_worklog_finish() {
  if [[ -n "$MALFORMED" ]]; then
    if [[ "$POSTED" -gt 0 ]]; then RESULT=posted-then-halted-malformed
    else RESULT=halted-malformed; fi
  elif [[ "$RESULT" == "none" && "$POSTED" -gt 0 ]]; then
    RESULT=posted
  fi
  yt_emit worklog_posted "$POSTED"
  yt_emit worklog_suppressed "$SUPPRESSED"
  yt_emit worklog_result "$RESULT"
  [[ -n "$POSTCHECK" ]] && yt_emit postcheck "$POSTCHECK"
  [[ -n "$ADVANCE" ]] && yt_emit worklog_watermark_advance "$ADVANCE"
  [[ -n "${AGENT_USER:-}" ]] && yt_emit agent_legs_rejected "$AGENT_LEGS_REJECTED"
  exit "$YT_EXIT_OK"
}

# --- the opt-OUT gate (absent => ENABLED) -----------------------------------
# Wraps ONLY the work-item calls: a disabled projection makes no work-item read
# and no work-item post, and returns -- it never suppresses another step.
if [[ "$(yt_config_toggle worklog_creation_enabled)" != "enabled" ]]; then
  yt_report syncyt.worklog.disabled \
    "worklog_creation_enabled is disabled in $(yt_config_path) -- no work item was read or posted for $TICKET, and no request was issued"
  yt_emit worklog_posted 0
  yt_emit worklog_suppressed 0
  yt_emit worklog_result disabled
  exit "$YT_EXIT_OK"
fi

yt_metadata_load "$TICKET"

# --- the Epic skip (BTG-040 parity, AC-6) -----------------------------------
# An Epic tracks no realized effort of its OWN -- its children do -- so there is
# nothing here to project, and this is a PARITY item rather than a divergence:
# the rule is a fact about this repository's decomposition model, not about any
# tracker, and `type: epic` is a value of the same metadata.yaml schema the
# sibling adapter reads.
#
# It sits BEFORE the capability resolve and before any call, so an Epic costs
# nothing and cannot fail on configuration it never needed. That ordering is the
# behaviour, not a tidiness choice: a posted work item is never updated and never
# deleted by this adapter, so an Epic's stage effort posted by mistake could not
# be taken back.
#
# The audit line quotes the REPO-side value (`type: epic`, lower case) rather
# than the English word "Epic". That is not style: `Epic` is a value of the
# config's issue_type_map, and a shipped script carrying a mapped value as a
# literal is exactly what S-3.1 forbids. Quoting what was actually read is both
# more accurate and the only wording that stays inside that rule.
#
# The watermark is deliberately NOT advanced. Advancing it would suppress exactly
# the entries a later decomposition needs, and the skip is not evidence that
# anything was projected.
if [[ "$(yt_metadata_get '.type')" == "epic" ]]; then
  yt_report syncyt.worklog.skipped_epic \
    "$TICKET carries type: epic -- an epic tracks no realized effort of its own (its children do), so no work item is read or posted and no request is issued"
  yt_emit worklog_posted 0
  yt_emit worklog_suppressed 0
  yt_emit worklog_result skipped-epic
  exit "$YT_EXIT_OK"
fi

# The post-add verification capability. FAIL-LOUD by design: an absent or
# unrecognized marker HALTs rather than resolving to `none`, which would turn an
# unconfigured adapter into a sanctioned non-enforcing one -- still posting work
# items, still reporting success, verifying nothing.
CAPABILITY="$(yt_config_capability)" || exit "$YT_EXIT_CONFIG"

# A workday's length is instance-varying configuration: comparing a `1d` entry
# against a `Spent time` increment needs `1d` as THIS adopter means it.
WORKDAY_HOURS="$(yt_config_map duration_units workday_hours)" || exit "$YT_EXIT_CONFIG"
WORKWEEK_DAYS="$(yt_config_map duration_units workweek_days)" || exit "$YT_EXIT_CONFIG"

# The explicit `$top` the crash-recovery scan carries, resolved HERE with the
# other load-bearing config rather than inside the scan.
#
# Both halves of that are deliberate. It is a CONFIG HALT (exit 4), the same
# polarity `duration_units` two lines above already has: two required keys in one
# script failing in two different ways, for no stated reason, is exactly the
# drift that becomes a defect. And it is resolved BEFORE any request, so a config
# fault is reported as a config fault instead of surfacing later as a work-item
# step that mysteriously declined to post.
YT_PAGE_BOUND="$(yt_config_page_bound)" || exit "$YT_EXIT_CONFIG"

# BTG-315: resolved ONCE, here, before candidate selection. AGENT_USER empty
# is UNSPLIT mode -- every line below this point stays byte-identical to
# before this ticket (AC-4); a non-empty value turns on the two-leg split
# governed by CADENCE_ORG.md §19.
AGENT_USER="$(yt_agent_user "$TICKET")"
WLS_PATH="${CADENCE_WORKLOG_SPLIT:-ci-templates/scripts/worklog-split.sh}"

# yt_duration_minutes <human-duration> -- `45m`, `3h`, `1d 2h`, `1w` -> minutes.
# Returns non-zero printing nothing on anything it does not recognize, because a
# guessed duration is a wrong work item that can never be corrected.
yt_duration_minutes() {
  awk -v s="$1" -v wd="$WORKDAY_HOURS" -v ww="$WORKWEEK_DAYS" '
    BEGIN {
      n = split(s, part, " "); if (n == 0) exit 1
      total = 0
      for (i = 1; i <= n; i++) {
        if (part[i] !~ /^[0-9]+(\.[0-9]+)?[wdhm]$/) exit 1
        v = substr(part[i], 1, length(part[i]) - 1) + 0
        u = substr(part[i], length(part[i]), 1)
        if      (u == "w") total += v * ww * wd * 60
        else if (u == "d") total += v * wd * 60
        else if (u == "h") total += v * 60
        else               total += v
      }
      printf "%.0f\n", total
    }'
}

# yt_epoch_ms <iso8601-instant> -- the work item's `date`, in epoch
# MILLISECONDS (OBSERVED). Only the DATE part is used, and that is not a
# shortcut: the instance normalises a work item's date to midnight of the
# supplied day (`1787328000000` went in, `1787270400000` came back), so a work
# item's date is day-granular and any time-of-day precision would be discarded
# server-side anyway.
#
# Computed with the standard days-from-civil arithmetic rather than by shelling
# out to `date -d`: this repo's CI is Alpine, `-d` is a GNU extension, and a
# date helper that silently produces nothing would post a work item onto the
# epoch. Returns non-zero on anything that is not a YYYY-MM-DD prefix.
yt_epoch_ms() {
  awk -v s="$1" '
    BEGIN {
      if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) exit 1
      y = substr(s,1,4) + 0; m = substr(s,6,2) + 0; d = substr(s,9,2) + 0
      if (m < 1 || m > 12 || d < 1 || d > 31) exit 1
      yy = y - (m <= 2)
      era = int((yy >= 0 ? yy : yy - 399) / 400)
      yoe = yy - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe/4) - int(yoe/100) + doy
      days = era * 146097 + doe - 719468
      printf "%d000\n", days * 86400
    }'
}

# --------------------------------------------------------------------------
# Candidate selection -- REPO-OWNED idempotency (BTG-064)
# --------------------------------------------------------------------------
# An entry is **already-synced iff** `entry.at <= worklog_watermark_at`. Tracker
# state is NEVER an input to that decision, so an operator who edits or deletes a
# work item is never overridden by a backfill.
#
# Bootstrap: the key ABSENT ENTIRELY -- or present with an explicit YAML null,
# which the metadata reader returns as a real JSON null -- means a ticket carried
# over from before the watermark existed. Seed forward to max(stage_effort[].at),
# post NOTHING that run, never backfill. PRESENT-BUT-EMPTY (`""`, as every new
# ticket ships) is NOT a bootstrap: it posts from its very first sync. The
# condition is kept on ONE line so it stays an extractable, executable construct.
WATERMARK_STATE=present
if jq -e '(has("worklog_watermark_at") | not) or (.worklog_watermark_at == null) or ((.worklog_watermark_at | type) == "array")' <<<"$YT_METADATA_JSON" >/dev/null 2>&1; then WATERMARK_STATE=bootstrap; fi
WATERMARK="$(yt_metadata_get '.worklog_watermark_at')"

# VALIDATE before trusting. The selection test is a LEXICAL comparison, so an
# unusable scalar sorts above every 20xx timestamp and would suppress the whole
# batch while reporting "up to date" -- false, not merely silent. Absent and empty
# are legitimate (bootstrap / never-projected); anything else must be ISO-8601.
if [[ "$WATERMARK_STATE" == "present" && -n "$WATERMARK" ]] \
   && [[ ! "$WATERMARK" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  yt_halt "$YT_EXIT_FAIL" syncyt.worklog.watermark_malformed \
    "worklog_watermark_at is '$WATERMARK', which is not an ISO-8601 instant (YYYY-MM-DDTHH:MM:SSZ) -- refusing to use it as the selection base; an unusable watermark would suppress every entry while reporting 'up to date'"
fi

ENTRY_COUNT="$(jq -r '(.stage_effort // []) | length' <<<"$YT_METADATA_JSON")"
MALFORMED=""

if [[ "$WATERMARK_STATE" == "bootstrap" ]]; then
  if [[ "$ENTRY_COUNT" -eq 0 ]]; then
    yt_report syncyt.worklog.watermark_seeded \
      "$TICKET carries no stage_effort entries to seed a watermark from -- 0 entries skipped, nothing posted, and no request issued"
    RESULT=seeded
    yt_worklog_finish
  fi
  SEED="$(jq -r '[.stage_effort[].at] | max' <<<"$YT_METADATA_JSON")"
  yt_report syncyt.worklog.watermark_seeded \
    "$TICKET carries no worklog watermark, so it is SEEDED FORWARD to $SEED and $ENTRY_COUNT entries are skipped -- a ticket carried over from before the watermark existed never backfills its history, because a work item this adapter posts can never afterwards be removed by it"
  RESULT=seeded
  ADVANCE="$SEED"
  yt_worklog_finish
fi

# Walk the append-only stage_effort log in document order (chronological, oldest
# first). A MALFORMED entry HALTS the batch at that entry and is never skipped
# over: the watermark is a HIGH-WATER mark, so advancing it for a later
# well-formed entry would move it PAST the malformed one, permanently marking an
# entry that was never projected as projected. Halting DEFERS a projection;
# skipping would DESTROY one.
CANDIDATES=()
for ((i = 0; i < ENTRY_COUNT; i++)); do
  ENTRY="$(jq -c ".stage_effort[$i]" <<<"$YT_METADATA_JSON")"
  E_STAGE="$(jq -r '.stage  // ""' <<<"$ENTRY")"
  E_EFFORT="$(jq -r '.effort // ""' <<<"$ENTRY")"
  E_AT="$(jq -r '.at      // ""' <<<"$ENTRY")"
  if [[ -z "$E_STAGE" || -z "$E_EFFORT" || -z "$E_AT" ]]; then
    MALFORMED="entry $i (stage='$E_STAGE' effort='$E_EFFORT' at='$E_AT')"
    break
  fi
  [[ -n "$WATERMARK" && ! "$E_AT" > "$WATERMARK" ]] && continue
  CANDIDATES+=("$E_STAGE|$E_EFFORT|$E_AT")
done

# UNCONDITIONAL, not a branch of the empty-candidate case. With postable entries
# AHEAD of it the candidate list is non-empty, so reporting it only when the list
# was empty swallowed it entirely on the sibling: the run posted what preceded
# it, dropped the rest, and still reported a clean result.
if [[ -n "$MALFORMED" ]]; then
  yt_report syncyt.worklog.entry_malformed \
    "$TICKET $MALFORMED is missing stage/effort/at -- halting the batch here; later entries are NOT posted this run and the watermark stays put"
  RESULT=halted-malformed
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  [[ -n "$MALFORMED" ]] || yt_report syncyt.worklog.up_to_date \
    "every stage_effort entry on $TICKET is at or below the watermark ($WATERMARK) -- nothing to post"
  yt_worklog_finish
fi

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-worklog-lib.sh"
# BTG-315: sourced unconditionally, same as the Jira sibling's
# jira-worklog-agent.sh -- its functions are only ever CALLED when
# AGENT_USER is non-empty, so an unconfigured run never reaches them (AC-4).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-worklog-agent.sh"
yt_worklog_post_candidates
yt_worklog_finish
