#!/usr/bin/env bash
#
# jira-write-issue.sh -- project the repo's ticket state onto a Jira issue.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (PROD_CADENCE-006 / BTG-037): in Jira
# Server/DC the `timetracking` fields are COUPLED -- writing `originalEstimate`
# WITHOUT `remainingEstimate` RESETS Remaining and destroys a sprint's burndown.
# So the update path reads the CURRENT Remaining as an explicit prerequisite and
# co-sends it; the projection is never dropped to dodge the reset.
#
# Upstream: the orchestrator, after jira-resolve.sh decided create-vs-update and
#   the skill rendered the description to a temp file.
# Downstream: `POST`/`GET`/`PUT .../issue[/{key}]` and, when the AC toggle is on,
#   the instance's dedicated AC field.
# Spec: archive/BTG-075/spec.md (AC-3, AC-8) ; jira-server-scripts.md.
# Guarded by: sync-jira-server-estimate-gate.sh -- it asserts this file still
#   co-sends remainingEstimate, still refuses the PUT when the current Remaining
#   is unreadable, and still re-projects the description.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id> [--mode create|update] [--issue-key <KEY>]
#            [--description-file <path>]
#   stdout : issuetype_projected= issue_key= jira_url= estimate_result= epic_branch= ac_result=
#   stderr : syncjs.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# The description arrives as a FRESH temp file rendered by the orchestrator (AC-4,
# wiki markup per the restored v4.0.1 template), CONSUMED and UNLINKED here on
# every exit path. This script READS metadata.yaml and NEVER writes it (AC-6).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"
# The `type: epic` fork decides this script's issuetype and summary, so it is
# resolved HERE, before the write -- one shared implementation with jira-epic.sh,
# never re-derived (BR-9: re-deriving it typed the umbrella `Epic` at step 4 and
# back to `Issue` at step 9, oscillating on every run).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-epic-lib.sh"
# The BTG-046 acceptance-criteria projection, relocated whole under the 400-line DX
# ceiling (BTG-079 AC-7). This script stays its only caller and its only emitter.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-ac-lib.sh"
# The ISSUE-TYPE decision -- resolution, the BTG-102 re-type guard and the
# verdict -- relocated whole under the 400-line DX ceiling (BTG-173 DEC-002/
# DEC-004, OQ-2 option (a)). This script stays its only caller and the only
# emitter of `issuetype_projected`.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-type-lib.sh"
# BTG-168: the SCREEN-AVAILABILITY concern -- one memoized probe, one shared
# three-valued predicate, four guarded fields, and the create-completion follow-up
# write (PROD_CADENCE-024). Relocated for the same 400-line ceiling, and independently
# because btg-102 SS-1 locates the FIRST body-staging call and the FIRST update
# write in THIS file POSITIONALLY: a second one inline would land a new site inside
# an assertion that reasons about ordering. The tokens are DESCRIBED, never
# reproduced, so this comment cannot satisfy that scenario's own greps.
# BTG-205's delta guard SHARES this line, on the precedent this file already sets below, so its arrival is net-2 against the headroom btg-173 S-7.4 reserved.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-screen-lib.sh"; . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-desc-lib.sh"

TICKET=""
ISSUE_KEY=""
MODE="update"
DESCRIPTION_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket)           js_argv_pair syncjs.write.usage "$@"; TICKET="$2"; shift 2 ;;
    --issue-key)        js_argv_pair syncjs.write.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    --mode)             js_argv_pair syncjs.write.usage "$@"; MODE="$2"; shift 2 ;;
    --description-file) js_argv_pair syncjs.write.usage "$@"; DESCRIPTION_FILE="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.write.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || js_halt "$JS_EXIT_USAGE" syncjs.write.usage "--ticket <id> is required"
case "$MODE" in
  create) ;;
  update) [[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.write.usage \
            "--issue-key <KEY> is required on the update path" ;;
  *) js_halt "$JS_EXIT_USAGE" syncjs.write.usage "--mode must be create or update, got '$MODE'" ;;
esac

# The temp file is the projection's ONLY copy of the rendered description and is
# never reused (AC-4). The trap is armed BEFORE anything that can fail, so the
# unlink is not a happy-path-only guarantee. The PAT never reaches it.
BODY_FILE=""
js_cleanup() { rm -f "${DESCRIPTION_FILE:-}" "${BODY_FILE:-}" 2>/dev/null; }
trap js_cleanup EXIT
if [[ -n "$DESCRIPTION_FILE" ]]; then
  [[ -r "$DESCRIPTION_FILE" ]] || js_halt "$JS_EXIT_USAGE" syncjs.write.usage \
    "--description-file is not readable: $DESCRIPTION_FILE"
fi

js_config_require
js_metadata_load "$TICKET"

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.write.env_absent "the base-URL environment variable is unset"

# `estimated_effort` is prose, so it is PROJECTED onto a Jira duration (range ->
# upper bound; anything else -> omitted + reported), never forwarded: a
# non-duration 400s at this BLOCKING step and strands the ticket, and 13 of this
# repo's 149 metadata files carry one (DEC-047).
RAW_ESTIMATE="$(js_metadata_get '.estimated_effort')"
ESTIMATE_UNPROJECTABLE=no
ORIGINAL_ESTIMATE=""
if [[ -n "$RAW_ESTIMATE" ]] && ! ORIGINAL_ESTIMATE="$(js_estimate_project "$RAW_ESTIMATE")"; then
  ORIGINAL_ESTIMATE=""
  ESTIMATE_UNPROJECTABLE=yes
fi
[[ -n "$ORIGINAL_ESTIMATE" && "$ORIGINAL_ESTIMATE" != "$RAW_ESTIMATE" ]] && \
  js_report syncjs.estimate.range_projected \
    "estimated_effort='$RAW_ESTIMATE' is a range -- projecting its UPPER bound '$ORIGINAL_ESTIMATE'"
TICKET_TYPE="$(js_metadata_get '.type')"
TITLE="$(js_metadata_get '.title')"
PRIORITY_KEY="$(js_metadata_get '.priority')"
CAPITALIZATION="$(js_metadata_get '.capitalization')"

# --- field mapping: instance-varying values all come from the config ---------
# The issue type is resolved by jira-type-lib.sh: it sets ISSUE_TYPE, and sets
# TYPE_UNASSERTED=yes for the one state that is not an error -- an UNTYPED ticket
# on the UPDATE path (BTG-173). Every other unresolvable type still HALTs there.
js_type_resolve
PRIORITY=""
if [[ -n "$PRIORITY_KEY" ]]; then
  PRIORITY="$(js_config_map priority_map "$PRIORITY_KEY")" \
    || js_halt "$JS_EXIT_CONFIG" syncjs.config.marker_unresolved \
         "no priority_map entry for priority='$PRIORITY_KEY'"
fi
SUMMARY="$TITLE"; [[ "$SUMMARY" =~ [^[:space:]] ]] || js_halt "$JS_EXIT_FAIL" syncjs.write.title_absent "$TICKET has an empty title -- refusing to send an empty fields.summary. Until BTG-124 an absent title still produced the degenerate-but-non-empty '<id>: ' and Jira took it; now it would reach the wire as \"\" and come back a 400 at this BLOCKING step, reported as this adapter's rest_rejected. Whitespace-only is empty here because the umbrella summary helper already treats it so, and two writers of one concept must not disagree. The guard shares this line to stay net-zero against the 400-line ceiling this file sits one line under"

# --- every config value this run needs is resolved BEFORE the first write ----
# The AC toggle is consumed far below but RESOLVED here. A non-boolean value is a
# config HALT (exit 4); resolving it after the create POST meant a `--mode create`
# run exited 4 having ALREADY created the issue and emitted no `issue_key=` -- the
# orchestrator never learned the key and the next sync created a SECOND issue. A
# halt must cost nothing. The exit code is captured, never collapsed: a bare `if`
# reads exit 4 as "disabled", silently switching the projection off.
js_config_toggle acceptance_criteria_sync_enabled
AC_TOGGLE_RC=$?
if [[ "$AC_TOGGLE_RC" -eq "$JS_EXIT_CONFIG" ]]; then exit "$JS_EXIT_CONFIG"; fi
# BTG-040: an Epic is deliberately MINIMAL -- no description, no labels, no
# priority, no estimate; the children carry the relationship. What it DOES need is
# the Epic Name field: on an instance with the Agile plugin that field is required
# on the Epic create screen, so a create without it is rejected 400. The field is
# discovered BY NAME (per-instance id), never hardcoded.
# BTG-036 forbids an Epic from carrying an Epic Link, so a `type: epic` ticket's
# TYPE depends on a fork resolved BEFORE the write and shared with jira-epic.sh so
# the two cannot disagree (DEC-045). On the UMBRELLA branch the call below emits
# step 4's payload and EXITS -- this step writes nothing for an umbrella.
IS_EPIC=no
EPIC_NAME_FIELD=""
if [[ "$TICKET_TYPE" == "epic" ]]; then
  IS_EPIC=yes
  js_epic_write_plan "$TICKET" "$MODE" "$ISSUE_KEY" "${BASE_URL%/}"
fi

# labels = the repo tags plus the capitalization classification. jq builds the
# array, so a label carrying markup-significant text is encoded, never interpolated.
# `.tags` is TYPE-GUARDED: a scalar `tags:` makes the `+` fail, emptying
# LABELS_JSON, which fails the whole body build and sends an EMPTY request.
TAGS_TYPE="$(jq -r '.tags | type' <<<"$JS_METADATA_JSON" 2>/dev/null)" || TAGS_TYPE=""
case "$TAGS_TYPE" in
  array|null|"") ;;
  *) js_report syncjs.write.labels_unusable \
       "$TICKET's tags: is a $TAGS_TYPE, not a list -- projecting NO labels rather than sending a malformed body" ;;
esac
LABELS_JSON="$(jq -c --arg cap "$CAPITALIZATION" \
  '((if (.tags | type) == "array" then .tags else [] end) + (if $cap == "" then [] else [$cap] end))' <<<"$JS_METADATA_JSON" 2>/dev/null)"
[[ -n "$LABELS_JSON" ]] || LABELS_JSON='[]'
# an Epic sets neither labels nor priority (BTG-040)
if [[ "$IS_EPIC" == "yes" ]]; then LABELS_JSON='[]'; PRIORITY=""; fi

# --- BTG-062: the UPDATE path RE-PROJECTS the description --------------------
# Not a create-only field: a repo-side edit that never reaches Jira is a silent
# projection gap. An update with no rendered description is a LOUD failure, not a
# quiet field-drop, and the PUT is never sent. The ONE sanctioned exception is
# `type: epic`, whose Description is deliberately left empty (BTG-040).
if [[ -z "$DESCRIPTION_FILE" && "$TICKET_TYPE" != "epic" ]]; then
  js_halt "$JS_EXIT_USAGE" syncjs.description.update_reproject_absent \
    "no --description-file was supplied for $TICKET (type='$TICKET_TYPE') -- the update fields object would drop description and silently strand a repo-side edit (BTG-062); NOT issuing the PUT"
fi
# A blank render must NEVER be sent: on the update path the description field
# OVERWRITES the live Jira description, so a silently-empty render would CLOBBER
# human-or-prior content while the sync still reported success.
if [[ -n "$DESCRIPTION_FILE" ]] && ! grep -q '[^[:space:]]' "$DESCRIPTION_FILE"; then
  js_halt "$JS_EXIT_FAIL" syncjs.description.empty_render \
    "the rendered description is empty/whitespace-only -- refusing to send (an update would CLOBBER the live description; a create would file a blank issue)"
fi

# --- BTG-168: ask the INSTANCE which of these fields its screen carries -------
# PROJECT_KEY is resolved HERE rather than beside the body build: the create-screen
# question is keyed on it, and a config HALT must still cost nothing -- so it lands
# BEFORE the probe, never after (S-4.4). No REST call; net-zero lines.
PROJECT_KEY="$(js_project_key "$TICKET")" || exit "$JS_EXIT_CONFIG"
# Sending a field the target screen does not carry is rejected OUTRIGHT and kills
# the WHOLE projection -- observed live for `timetracking` on the Bug create
# screen of the reference Jira Server instance (PROD_CADENCE-024). Three siblings are sent by this same writer under the
# same assumption, so all four are guarded by ONE predicate (DEC-014); a fifth is
# one more call line. Only an AFFIRMATIVE ABSENCE suppresses: an unreachable or
# unparseable probe sends everything exactly as it does today (DEC-007).
#
# ORDER is load-bearing. AFTER the BTG-062 absent/blank-render halts above -- an
# absent render is an upstream defect and must stay a loud failure, never masked by
# "the screen would not have taken it anyway". AFTER js_type_resolve, because the
# create screen is keyed on the resolved type. BEFORE the current-Remaining read
# below, so a suppressed estimate skips that read with no edit to it. BEFORE
# the body is staged, preserving btg-102 SS-1's verdict-before-body property.
#
# An Epic sends no labels, no priority, no description and no estimate (BTG-040),
# so nothing is guarded and NO probe is issued -- the guard costs nothing on the
# path it cannot help.
SEND_LABELS=yes
SEND_DESC=yes
if [[ "$IS_EPIC" != "yes" ]]; then
  JS_SCREEN_SCOPE=create; [[ "$MODE" == "create" ]] || { JS_SCREEN_SCOPE=edit; JS_SCREEN_KEY="$ISSUE_KEY"; }
  [[ -n "$ORIGINAL_ESTIMATE" ]] && js_screen_guard timetracking syncjs.estimate.field_unsupported_type \
    ORIGINAL_ESTIMATE "" "originalEstimate='$ORIGINAL_ESTIMATE'"
  [[ -n "$PRIORITY" ]] && js_screen_guard priority syncjs.priority.field_unsupported_type \
    PRIORITY "" "priority='$PRIORITY'"
  js_screen_guard labels syncjs.labels.field_unsupported_type \
    SEND_LABELS no "labels=$LABELS_JSON (OMITTED, never sent as an empty array: {labels: []} instructs Jira to CLEAR the labels)"
  [[ -n "$DESCRIPTION_FILE" ]] && js_screen_guard description syncjs.description.field_unsupported_type \
    SEND_DESC no "the rendered description (the live value is left untouched)"
fi

# --- PREREQUISITE of the update PUT: read the issue's CURRENT Remaining -----
# EXPLICIT and standalone, not a by-product of another read. A read FAILURE and a
# genuinely-absent estimate are never conflated (Behavior 5): a failed read is
# FAIL LOUD with no PUT (falling back to Original-alone silently resets Remaining
# -- the PROD_CADENCE-006 defect itself), while a successful read of a never-estimated
# issue legitimately sends Original alone. An EPIC skips `timetracking` entirely
# (BTG-040); CREATE has no prior Remaining -- Jira initializes it from Original.
CURRENT_REMAINING=""
LIVE_ISSUE_JSON=""
if [[ -n "$ORIGINAL_ESTIMATE" && "$TICKET_TYPE" != "epic" && "$MODE" == "update" ]]; then
  if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=summary,description,issuetype,priority,timetracking,labels"; then
    js_report syncjs.transport.rest_unreachable "GET /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/}"
    js_halt "$JS_EXIT_TRANSPORT" syncjs.estimate.current_remaining_unreadable \
      "could not read the issue's current Remaining Estimate -- NOT issuing the update PUT (writing Original alone would reset Remaining)"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.estimate.current_remaining_unreadable \
      "GET /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS -- NOT issuing the update PUT (writing Original alone would reset Remaining)"
  fi
  # ONE reader for the RAW nested REST v2 shape, shared with the worklog post-check
  # (jira-lib.sh's `remaining_of`): reading the retired transport's flattened
  # snake_case shape yields "" and silently drops the co-send -- PROD_CADENCE-006 itself.
  if ! CURRENT_REMAINING="$(remaining_of "$JS_HTTP_BODY")"; then
    js_halt "$JS_EXIT_FAIL" syncjs.estimate.current_remaining_unreadable \
      "the issue read returned an unparseable body -- NOT issuing the update PUT (writing Original alone would reset Remaining)"
  fi
  LIVE_ISSUE_JSON="$JS_HTTP_BODY"    # the guard below reuses it: no extra round trip
fi

# --- BTG-102: the pre-flight issue-type RE-TYPE guard (update path only) -----
# The guard itself lives in jira-type-lib.sh, relocated there whole under the
# 400-line DX ceiling on the DEC-057 / DEC-060 / BTG-079 AC-7 precedent (BTG-173
# DEC-002). It is CALLED HERE, before the body is staged and before the PUT --
# that ORDER is the whole property (btg-102-retype-guard.test.sh SS-1): a verdict
# resolved after the body is built cannot withhold a field. It leaves its answer
# in ISSUETYPE_PROJECTED, which the jq builder's $itype_ok gates and which is
# emitted below.
js_type_verdict

js_description_delta_check "$TICKET" "$ISSUE_KEY" "$DESCRIPTION_FILE" "${ORIGINAL_ESTIMATE:+$LIVE_ISSUE_JSON}"  # BTG-205 (AC-6): name the overwrite before it happens. Non-blocking, owns its own preconditions (jira-desc-lib.sh); the `:+` passes the cached issue body ONLY when the estimate prerequisite -- the one read that ASKS for `description` -- is what fetched it.

# --- build the fields object ------------------------------------------------
# The timetracking fragment is STRUCTURAL: `remainingEstimate` is present only
# when the issue HAS one -- never "" and never null.
BODY_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.write.scratch_unavailable "no scratch file could be staged for $TICKET's request body -- NOT sending it; an unstaged body degrades the write into a BODYLESS one, and mktemp's own diagnostic is not a channel DEC-001 sanctions"

ESTIMATE_RESULT=none
if [[ "$TICKET_TYPE" == "epic" ]]; then
  ORIGINAL_ESTIMATE=""                       # an Epic gets no Original Estimate
elif [[ "$ESTIMATE_UNPROJECTABLE" == "yes" ]]; then
  ESTIMATE_RESULT=unprojectable
elif js_screen_suppressed timetracking; then
  # BEFORE the empty-estimate arm, because suppression CLEARED that variable and
  # would otherwise read as "there was no estimate to project" -- collapsing the
  # two re-creates PROD_CADENCE-023's shape verbatim (DEC-008). Upgraded to
  # `followup-written` below if the create-completion write landed it.
  ESTIMATE_RESULT=field-unsupported
elif [[ -z "$ORIGINAL_ESTIMATE" ]]; then
  :
elif [[ -n "$CURRENT_REMAINING" ]]; then
  ESTIMATE_RESULT=cosent
else
  ESTIMATE_RESULT=original-only
fi

# The description is folded in as raw BYTES (`--rawfile`) so jq does the JSON
# encoding and the wiki reaches Jira exactly as rendered -- no shell interpolation
# of ticket prose, and no re-rendering here (this script only transports it).
DESC_ARGS=(--arg desc "" --arg send_desc no)
if [[ -n "$DESCRIPTION_FILE" && "$SEND_DESC" == "yes" ]]; then
  DESC_ARGS=(--rawfile desc "$DESCRIPTION_FILE" --arg send_desc yes)
fi

# BOTH questions, ONE builder (BTG-084). The status used to be discarded with a
# trailing `|| :`, under a comment claiming `CHECKED:` -- true only for emptiness.
# A jq that died mid-write left a TRUNCATED, NON-EMPTY body that the emptiness
# probe read as "built", so the malformed body went out and the instance's 400 was
# reported as `syncjs.write.rest_rejected` -- this adapter's defect, blamed on the
# instance. A bare exit follows the helper's own report: js_halt would double-report.
js_build_body "$BODY_FILE" syncjs.write.body_unbuildable "the request body for $TICKET" \
      -n --arg orig "$ORIGINAL_ESTIMATE" --arg rem "$CURRENT_REMAINING" \
      --arg summary "$SUMMARY" --arg itype "$ISSUE_TYPE" --arg prio "$PRIORITY" \
      --argjson labels "$LABELS_JSON" --arg mode "$MODE" --arg project "$PROJECT_KEY" \
      --arg epicfield "$EPIC_NAME_FIELD" --arg isepic "$IS_EPIC" --arg send_labels "$SEND_LABELS" \
      --arg itype_ok "$ISSUETYPE_PROJECTED" \
      "${DESC_ARGS[@]}" '
  {fields: (
    {summary: $summary}
    + (if $itype_ok == "yes" then {issuetype: {name: $itype}} else {} end)
    + (if $isepic == "yes" or $send_labels != "yes" then {} else {labels: $labels} end)
    + (if $epicfield == "" or $itype_ok != "yes" then {} else {($epicfield): $summary} end)
    + (if $prio == "" then {} else {priority: {name: $prio}} end)
    + (if $mode == "create" then {project: {key: $project}} else {} end)
    + (if $orig == "" then {}
       elif $rem == "" then {timetracking: {originalEstimate: $orig}}
       else {timetracking: {originalEstimate: $orig, remainingEstimate: $rem}}
       end)
    + (if $send_desc == "yes" then {description: $desc} else {} end)
  )}' || exit "$JS_EXIT_FAIL"

if [[ "$MODE" == "create" ]]; then
  if ! js_rest POST "/rest/api/2/issue" "$BODY_FILE"; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "POST /rest/api/2/issue could not reach ${BASE_URL%/}"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.write.rest_rejected \
      "POST /rest/api/2/issue returned HTTP $JS_HTTP_STATUS"
  fi
  # Direct REST v2 returns the new key at the TOP level (`.key`) -- the previous
  # transport's `{"issue":{"key":...}}` envelope is gone with it.
  ISSUE_KEY="$(printf '%s' "$JS_HTTP_BODY" | jq -r '.key // empty' 2>/dev/null)"
  [[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_FAIL" syncjs.write.rest_rejected \
    "the create response carried no issue key -- refusing to continue without knowing what was created"
  js_report syncjs.write.created "$TICKET created as $ISSUE_KEY"
  # BTG-168 / DEC-013: complete the create the screen would not take whole. ONE
  # PUT carrying EVERY suppressed field the issue's EDIT screen carries. Invoked
  # AFTER the key is known and AFTER the created line, so the transcript records
  # the create before the completion of it, and NON-FATALLY -- a rejected
  # follow-up can never turn a successful create into a failed run.
  js_screen_followup "$ISSUE_KEY"
  js_screen_recovered timetracking && ESTIMATE_RESULT=followup-written
else
  if ! js_rest PUT "/rest/api/2/issue/$ISSUE_KEY" "$BODY_FILE"; then
    js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
      "PUT /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/}"
  fi
  if ! js_http_ok; then
    js_halt "$JS_EXIT_FAIL" syncjs.write.rest_rejected \
      "PUT /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS"
  fi
fi

case "$ESTIMATE_RESULT" in
  cosent)        js_report syncjs.estimate.remaining_cosent \
                   "originalEstimate=$ORIGINAL_ESTIMATE co-sent with the issue's current remainingEstimate=$CURRENT_REMAINING (Remaining preserved)" ;;
  original-only) js_report syncjs.estimate.original_only \
                   "the issue has no current Remaining Estimate (never estimated) -- originalEstimate=$ORIGINAL_ESTIMATE sent alone; Jira initializes Remaining from it" ;;
  field-unsupported|followup-written) : ;;   # already reported at the guard / the follow-up
  unprojectable) js_report syncjs.estimate.unprojectable \
                   "estimated_effort='$RAW_ESTIMATE' is not a Jira duration -- the Original Estimate was OMITTED (the live value is untouched) and the rest of the projection applied; sending it verbatim would 400 at this blocking step and strand the ticket" ;;
esac

# The issue-type projection decision is AUDITABLE from the transcript for the first
# time (BTG-102): a guarded write that completed without saying whether it projected
# the type is an unaudited mutation decision. Emitted HERE, BEFORE the AC projection,
# because that projection EXITS for an epic (js_epic_ac_skip_exit emits its own
# five-key payload and leaves) -- after it, this line would silently never appear on
# any `type: epic` write.
js_emit issuetype_projected "$ISSUETYPE_PROJECTED"

# --- BTG-046: project the repo Acceptance Criteria to the dedicated field ----
# The projection itself lives in jira-ac-lib.sh, relocated there under the 400-line
# DX ceiling on the DEC-057 / DEC-060 precedent (BTG-079 AC-7). It is toggle-gated
# and BEST-EFFORT -- every refusal is reported and the sync continues, never halting
# the ticket -- and it leaves its verdict in AC_RESULT, emitted below.
js_ac_project

js_emit issue_key "$ISSUE_KEY"
js_emit jira_url "${BASE_URL%/}/browse/$ISSUE_KEY"
js_emit estimate_result "$ESTIMATE_RESULT"
js_emit ac_result "$AC_RESULT"
exit "$JS_EXIT_OK"
