#!/usr/bin/env bash
#
# jira-screen-lib.sh -- the SCREEN-AVAILABILITY concern for the projection write.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-168).
# Invariant relied on from outside this boundary, OBSERVED LIVE and not assumed
# (BTG-150's CADENCE_ORG.md §16 live-verification run against the reference
# Jira Server instance, 2026-08-19/20; PROD_CADENCE-024): a Jira
# Server/DC project's CREATE screen and EDIT screen are SEPARATE configurations,
# and a `fields` member the target screen does not carry is rejected outright --
# `POST /rest/api/2/issue` answers HTTP 400 and the WHOLE projection dies. A Bug
# create screen without Time Tracking made every bug-type ticket carrying an
# estimate unprojectable; `priority`, `labels` and `description` are sent by the
# same writer under the same assumption and carry the identical hazard (DEC-014).
#
# It is SOURCED, never invoked, and runs nothing on load. It never writes
# `metadata.yaml`, and it emits nothing on stdout: its caller publishes every
# result line.
#
# Why it is a library rather than a block in `jira-write-issue.sh`. Two independent
# reasons, both structural rather than stylistic:
#   * the 400-line DX ceiling (btg-046-ac-sync.test.sh S-42.1 fails at >=400, S-42.5
#     fails the write script above 395). Inline, the predicate and the follow-up
#     write land that file near 450. The relocation precedent is jira-ac-lib.sh
#     (BTG-079 AC-7), jira-type-lib.sh (BTG-173 DEC-002) and jira-link-targets.sh.
#   * `btg-102-retype-guard.test.sh` SS-1 locates the FIRST `js_build_body` and the
#     FIRST `js_rest PUT` in the write script POSITIONALLY. A second inline
#     `js_rest PUT` would put a new site inside an assertion that reasons about
#     ordering, which is how a guarded assertion goes quietly inert.
#
# Upstream: `jira-write-issue.sh`, its SOLE caller -- four guard calls before the
#   body is staged, and one follow-up call after a create has landed.
# Downstream: `GET /rest/api/2/issue/createmeta` (create screen),
#   `GET /rest/api/2/issue/{key}/editmeta` (edit screen), and ONE
#   `PUT /rest/api/2/issue/{key}` on the adopter's Jira Server/DC.
# Spec: archive/BTG-168/spec.md (Proposed Design) ; jira-server-scripts-screens.md ;
#   jira-server-conditions-screens.md.
# Guarded by: sync-jira-server-screen-availability-gate.sh -- it asserts the write
#   still asks before sending, that suppression stays fail-OPEN, and that the
#   follow-up stays a CREATE-COMPLETION write (which is what keeps PROD_CADENCE-006's
#   justification from decaying).
#
# Contract:
#   js_screen_available <field-id> -- 0 available | 1 affirmatively absent
#                                     | 2 unknown. THREE-VALUED, deliberately.
#   js_screen_guard <field-id> <condition> <var> <suppressed-value> <detail>
#                                  -- the per-field call site.
#   js_screen_recoverable <field-id> -- suppressed at create AND on the edit screen.
#   js_screen_followup <issue-key> -- the one create-completion PUT.
#
# It reads and writes its caller's variables by design ($MODE, $ISSUE_KEY,
# $ISSUE_TYPE, $PROJECT_KEY, $BASE_URL, $BODY_FILE, $DESCRIPTION_FILE,
# $ORIGINAL_ESTIMATE, $PRIORITY, $LABELS_JSON in; the four guarded fields' own
# variables out), exactly as jira-ac-lib.sh and jira-type-lib.sh do.

# --- process-global state, initialised at SOURCE time (the caller runs `set -u`)
JS_SCREEN_SCOPE=""             # create | edit -- which screen was asked
JS_SCREEN_KEY=""               # the issue key, on the edit scope
JS_SCREEN_STATE=unfetched      # unfetched | ok | unknown
JS_SCREEN_FIELDS=""            # the field map as JSON. NEVER printed, never
                               # written to a file: it describes the instance's
                               # whole screen configuration for an issue type and
                               # only per-field booleans are derived from it
                               # (Facet 7, Source Confidentiality). It lives in
                               # this variable and dies with the process.
JS_SCREEN_UNKNOWN_REPORTED=no  # `availability_unknown` is ONE condition per RUN
JS_SCREEN_UNKNOWN_DETAIL=""
JS_SCREEN_SUPPRESSED=""        # space-delimited field ids suppressed at create
JS_SCREEN_RECOVERED=""         # space-delimited field ids the follow-up wrote

# --- js_screen_envelope_incomplete <body> -- INTERNAL. EVIDENCE-POSITIVE -------
# BTG-184 AC-2 / DEC-003: returns 0 ONLY when the create screen's step-2
# envelope AFFIRMS the page is incomplete -- never on an absent or malformed
# key. Two independent affirmative signals, either sufficient alone:
#   isLast present AND == false
#   total present AND numeric AND (values present AND an array) AND
#     total > (values | length)
# Never errors on a missing or malformed field; jq's `and`/`or` short-circuit,
# so an absent `values` or a non-numeric `total` simply falls through to "not
# evidence" rather than raising.
js_screen_envelope_incomplete() {
  jq -e '
    (has("isLast") and (.isLast == false))
    or
    (has("total") and ((.total | type) == "number")
      and (has("values") and ((.values | type) == "array"))
      and (.total > (.values | length)))
  ' <<<"$1" >/dev/null 2>&1
}

# --- js_screen_fetch -- INTERNAL. ONE metadata read per invocation, memoized ----
# Four field questions are answered from ONE response (DEC-017): a naive predicate
# would issue four identical reads per write. The memo is an IN-PROCESS variable,
# not a cache layer and not a filesystem cache -- DEC-005's "no cache without
# profiling" stands, and there is still nothing cached ACROSS invocations.
#
# The scope is chosen by MODE, never by issue type: a create has no issue yet, so
# the question is "what does this project's create screen for this type carry?";
# an update asks the issue's own edit screen -- the endpoint jira-ac-lib.sh:89
# already uses for exactly this question about the acceptance-criteria field.
js_screen_fetch() {
  [[ "$JS_SCREEN_STATE" == "unfetched" ]] || return 0
  local path filter map tid
  # UNKNOWN is the default and every failure LEAVES it there. Written this way on
  # purpose: a future edit that adds a failure mode inherits fail-OPEN rather than
  # having to remember to ask for it. Set FIRST, before the create path's own
  # two-step resolution, so each of its exits inherits it too.
  JS_SCREEN_STATE=unknown
  if [[ "$JS_SCREEN_SCOPE" == "create" ]]; then
    # THE CREATE SCREEN IS A TWO-STEP READ, and this was OBSERVED, not assumed
    # (BTG-168's CADENCE_ORG.md §16 live run; DEC-026). Jira 9 REMOVED the classic
    # `GET /rest/api/2/issue/createmeta?projectKeys=…&expand=projects.issuetypes.fields`:
    # on Jira Server 9.3.1 that path answers **HTTP 404 "Issue Does Not Exist"**,
    # because `createmeta` is parsed as an issue KEY. The replacement is keyed on
    # the issue type's ID, not its name, so the id must be resolved first.
    # Step 2 is issued ONLY when step 1 resolved an id -- so an instance that
    # cannot answer step 1 (a pre-8.4 Jira, or a restricted endpoint) costs ONE
    # read and resolves UNKNOWN, which sends every field exactly as today. That
    # is the fail-open guarantee doing its job, and it is why the classic form is
    # not retained as a fallback: a second doomed shape would buy nothing here and
    # would make the call sequence depend on the instance's version.
    if ! js_rest GET "/rest/api/2/issue/createmeta/${PROJECT_KEY// /%20}/issuetypes?maxResults=200"; then
      JS_SCREEN_UNKNOWN_DETAIL="the create screen could not be read from ${BASE_URL%/} (${JS_TRANSPORT_ERROR:-no diagnostic})"
      return 0
    fi
    if ! js_http_ok; then
      JS_SCREEN_UNKNOWN_DETAIL="the create screen's issue-type read returned HTTP $JS_HTTP_STATUS"
      return 0
    fi
    tid="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$ISSUE_TYPE" \
      'if type=="object" and (.values|type)=="array"
       then (.values[] | select((.name? // "") == $n) | .id) else empty end' 2>/dev/null | head -1)"
    if [[ -z "$tid" ]]; then
      JS_SCREEN_UNKNOWN_DETAIL="the create screen's issue-type read (HTTP $JS_HTTP_STATUS) offered no id for the issue type"
      return 0
    fi
    path="/rest/api/2/issue/createmeta/${PROJECT_KEY// /%20}/issuetypes/${tid}?maxResults=200"
    # the field list arrives as an ARRAY of descriptors keyed by `fieldId`, where
    # the edit screen returns an object map -- normalized HERE so the predicate
    # below stays one `has()` over one shape and cannot drift per endpoint.
    # BTG-184 AC-4 / C-4d, widened at code review (N1): `select(type=="object")`
    # drops a non-object entry in `values` (e.g. a bare string) before `.fieldId`
    # is ever asked of it; `.fieldId` on an object missing the key, or holding
    # an explicit `null`, or a non-string value, all evaluate to something
    # `strings` then filters out -- so EVERY malformed shape is skipped rather
    # than turned into a `null`/non-string map key, which a bare `map` would
    # carry into `{(.): {}}` and jq refuses ("Cannot use null as object key"
    # or "Cannot use N (number) as object key"). Discovered building the
    # contract test's own fixture, not one of the ticket's named findings, but
    # squarely inside AC-4's own "never a crash" requirement. Any number of
    # malformed descriptors must not poison the whole map into `unknown`;
    # every well-formed sibling still resolves.
    filter='(([.values[]? | select(type=="object") | .fieldId | strings] | map({(.): {}}) | add) // {})'
  else
    path="/rest/api/2/issue/$JS_SCREEN_KEY/editmeta"
    filter='.fields'
  fi
  if ! js_rest GET "$path"; then
    JS_SCREEN_UNKNOWN_DETAIL="the ${JS_SCREEN_SCOPE} screen could not be read from ${BASE_URL%/} (${JS_TRANSPORT_ERROR:-no diagnostic})"
    return 0
  fi
  if ! js_http_ok; then
    JS_SCREEN_UNKNOWN_DETAIL="the ${JS_SCREEN_SCOPE} screen read returned HTTP $JS_HTTP_STATUS"
    return 0
  fi
  # BTG-184 AC-2 / F-3: the CREATE screen's step-2 body is a PAGINATED
  # envelope. EVIDENCE-POSITIVE (DEC-003): truncation is concluded ONLY from a
  # field that is PRESENT and says incomplete -- an ABSENT isLast/total is NOT
  # evidence. The inverse polarity would resolve every create read to unknown
  # on an instance that omits the envelope, silently disabling the probe:
  # fail-open AND quiet, exactly the defect class this ticket removes.
  # Examined on the RAW body, before the normalize filter below discards it.
  if [[ "$JS_SCREEN_SCOPE" == "create" ]] && js_screen_envelope_incomplete "$JS_HTTP_BODY"; then
    JS_SCREEN_UNKNOWN_DETAIL="the create screen's field-list read (HTTP $JS_HTTP_STATUS) returned a TRUNCATED page -- the envelope reports the map is incomplete, so it cannot be trusted"
    return 0
  fi
  # BTG-184 code review cycle 2: the create-branch normalize filter's `[]?`
  # (added for AC-4/DEC-015's malformed-descriptor tolerance) makes an ABSENT
  # or non-array `values` normalize to a VALID EMPTY OBJECT instead of
  # ERRORING, which would otherwise collapse this case into the EMPTY-map
  # branch below -- a distinct cause ("no recognizable field map" vs "an
  # empty map") that the conditions catalog documents separately. Guarded
  # here, on the CREATE scope only and BEFORE the normalize filter runs, so
  # the two causes stay separately reachable exactly as documented.
  if [[ "$JS_SCREEN_SCOPE" == "create" ]] && ! jq -e '(.values? | type) == "array"' <<<"$JS_HTTP_BODY" >/dev/null 2>&1; then
    JS_SCREEN_UNKNOWN_DETAIL="the ${JS_SCREEN_SCOPE} screen read returned HTTP $JS_HTTP_STATUS carrying no recognizable field map"
    return 0
  fi
  map="$(printf '%s' "$JS_HTTP_BODY" | jq -c "$filter // empty" 2>/dev/null)" || map=""
  if [[ -z "$map" ]] || ! jq -e 'type == "object"' <<<"$map" >/dev/null 2>&1; then
    JS_SCREEN_UNKNOWN_DETAIL="the ${JS_SCREEN_SCOPE} screen read returned HTTP $JS_HTTP_STATUS carrying no recognizable field map"
    return 0
  fi
  # BTG-184 AC-1 / F-3: a zero-key map is not an observation that these fields
  # are absent -- it is an unanswered question. `add` of an empty array is
  # null, which the create-branch normalize filter's `// {}` arm turns into a
  # VALID EMPTY OBJECT; on the edit scope a 200 `{"fields":{}}` arrives the
  # same way. Returning here inherits the `unknown` default set at the top of
  # this function, which is the whole reason it is set first.
  if [[ "$(jq -r 'length' <<<"$map" 2>/dev/null)" == "0" ]]; then
    JS_SCREEN_UNKNOWN_DETAIL="the ${JS_SCREEN_SCOPE} screen read returned HTTP $JS_HTTP_STATUS carrying an EMPTY field map -- an empty map answers nothing about these fields"
    return 0
  fi
  JS_SCREEN_FIELDS="$map"
  JS_SCREEN_STATE=ok
  return 0
}

# --- js_screen_available <field-id> -----------------------------------------
# 0 available | 1 affirmatively absent | 2 unknown.
#
# THREE-VALUED, deliberately. A boolean would force every caller to collapse "the
# instance says this field is absent" and "nobody could ask" into one branch, and
# collapsing them in the suppressing direction is the fail-CLOSED mistake DEC-007
# forbids by name: a transient metadata-endpoint failure would silently stop
# projecting four fields for every adopter at once, trading a loud failure for a
# quiet one -- exactly what problem.md's Constraints rule out.
#
# The polarity is precedent-backed, not invented: jira-ac-lib.sh:89 suppresses the
# AC write only when the editmeta GET SUCCEEDED, returned 2xx, AND the field was
# absent. An unreachable editmeta does not suppress. This inherits that shape.
#
# The field id is a PARAMETER and appears in no branch condition here (AC-3): one
# predicate governs every issue type and every guarded field identically, so the
# four cannot drift, and a fifth guarded field is one call line at the caller.
js_screen_available() {
  js_screen_fetch
  [[ "$JS_SCREEN_STATE" == "ok" ]] || return 2
  jq -e --arg f "$1" 'has($f)' <<<"$JS_SCREEN_FIELDS" >/dev/null 2>&1 && return 0
  return 1
}

# --- js_screen_report_unknown -- INTERNAL. ONE condition per RUN --------------
# One unanswered question is ONE condition, not one per field: four lines would
# report four facts where one probe produced one outcome (JI-3, S-2.6). The name
# is DISTINCT from `field_unsupported_type` because reporting the latter for an
# unresolved probe would assert a fact about the instance's screen that nobody
# observed (DEC-007).
js_screen_report_unknown() {
  [[ "$JS_SCREEN_UNKNOWN_REPORTED" == "no" ]] || return 0
  JS_SCREEN_UNKNOWN_REPORTED=yes
  js_report syncjs.screen.availability_unknown \
    "${JS_SCREEN_UNKNOWN_DETAIL:-the screen availability question could not be resolved} -- every guarded field is sent EXACTLY as it is today; a field is suppressed only on an affirmative absence, never on an unanswered question"
}

# --- js_screen_guard <field-id> <condition> <var> <suppressed-value> <detail> --
# The per-field call site. On an affirmative absence it clears the field's own
# omission sentinel (setting <var> to <suppressed-value>), records the id, and
# emits <condition>. On UNKNOWN it ensures the single shared availability_unknown
# has been emitted. On AVAILABLE it does NOTHING AT ALL -- deliberately, because a
# line on the available branch would appear in every adopter's transcript on every
# sync for no decision anyone can act on (AC-4 R4).
#
# The pre-suppression value is SAVED so the create-completion follow-up can write
# what the create could not (DEC-013). The field ids are shell identifiers, which
# is what makes the saved-value slot addressable without a per-field branch.
js_screen_guard() {
  local id="$1" condition="$2" var="$3" suppressed="$4" detail="$5"
  js_screen_available "$id"
  case $? in
    1) JS_SCREEN_SUPPRESSED="$JS_SCREEN_SUPPRESSED $id"
       eval "JS_SCREEN_SAVED_${id}=\${$var}"
       printf -v "$var" '%s' "$suppressed"
       js_report "$condition" \
         "$id is not on the ${ISSUE_TYPE:-(unasserted -- this ticket carries no type:)} ${JS_SCREEN_SCOPE} screen -- OMITTING $detail from the request body; the projection continues and every other field is still written" ;;
    2) js_screen_report_unknown ;;
  esac
  return 0
}

# --- js_screen_suppressed / js_screen_recovered <field-id> -------------------
# Membership of the two outcome lists, so the caller can resolve its own result
# enumeration with the field id as a PARAMETER rather than a branch condition.
js_screen_suppressed() { case " $JS_SCREEN_SUPPRESSED " in *" $1 "*) return 0 ;; esac; return 1; }
js_screen_recovered()  { case " $JS_SCREEN_RECOVERED "  in *" $1 "*) return 0 ;; esac; return 1; }

# --- js_screen_recoverable <field-id> ---------------------------------------
# True when the field was suppressed at create AND the issue's EDIT screen carries
# it. Both halves matter: the create and edit screens are different configurations,
# which is the entire premise of the follow-up write, and if the edit screen also
# omits the field then the suppression correctly stands (S-1.3).
js_screen_recoverable() {
  js_screen_suppressed "$1" || return 1
  js_screen_available "$1"
}

# --- js_screen_followup <issue-key> -- THE CREATE-COMPLETION WRITE ------------
# Reachable ONLY from the create path, in the SAME invocation, against the key
# that invocation just created. That constraint is not decoration: it is what
# makes `originalEstimate` ALONE correct here rather than the PROD_CADENCE-006 defect.
# The issue was created MOMENTS AGO with the estimate SUPPRESSED, so it has no
# Remaining Estimate at all -- this is today's correct create semantics
# (`estimate_result=original-only`), where Jira initializes Remaining from
# Original. Reading Remaining first would cost a round trip to produce the
# identical body. A future edit that generalised this into an update path would
# silently re-open PROD_CADENCE-006 (RK-11); check 3 of
# sync-jira-server-screen-availability-gate.sh exists to fail that edit.
#
# EXACTLY ONE write, carrying EVERY recovered field -- never one PUT per field
# (four writes, four failure modes, four transcript entries for one decision).
# It NEVER halts: a rejected follow-up reports and returns, because turning a
# successful create into a failed run would re-introduce the exact defect BTG-168
# removes. The caller has already reported the create by the time this runs.
js_screen_followup() {
  local key="$1" recovered="" send_tt=no send_prio=no send_lab=no send_desc=no
  [[ "$MODE" == "create" ]] || return 0
  [[ -n "$key" && -n "$JS_SCREEN_SUPPRESSED" ]] || return 0
  # ask the EDIT screen of the issue just created -- a DIFFERENT question from the
  # one the create screen answered, so the memo is deliberately re-primed.
  JS_SCREEN_SCOPE=edit; JS_SCREEN_KEY="$key"
  JS_SCREEN_STATE=unfetched; JS_SCREEN_FIELDS=""
  js_screen_recoverable timetracking && { send_tt=yes;   recovered="$recovered timetracking"; }
  js_screen_recoverable priority     && { send_prio=yes; recovered="$recovered priority"; }
  js_screen_recoverable labels       && { send_lab=yes;  recovered="$recovered labels"; }
  js_screen_recoverable description  && { send_desc=yes; recovered="$recovered description"; }
  [[ "$JS_SCREEN_STATE" == "unknown" ]] && js_screen_report_unknown
  local dargs=(--arg desc "")
  if [[ "$send_desc" == "yes" ]]; then
    if [[ -r "${DESCRIPTION_FILE:-}" ]]; then dargs=(--rawfile desc "$DESCRIPTION_FILE")
    else send_desc=no; recovered="${recovered% description}"; fi
  fi
  if [[ -z "$recovered" ]]; then
    # BTG-184 AC-3 / F-2: assert a SCREEN FACT only about a screen that was
    # actually observed. When the edit-screen read did not resolve (state
    # unknown), `availability_unknown` has already fired above at :251 and it
    # is the correct and sufficient line -- claiming the edit screen "carries
    # none of them" here would assert what nobody observed (DEC-025's
    # collapse, one level in), and its catalogued operator action ("add the
    # fields to that issue type's screens") would be wrong advice for a
    # screen nobody could read.
    [[ "$JS_SCREEN_STATE" == "ok" ]] || return 0
    js_report syncjs.screen.followup_unavailable \
      "the create screen omitted$JS_SCREEN_SUPPRESSED and $key's edit screen carries none of them -- issuing NO follow-up write; the omissions reported above STAND, and this line is what distinguishes 'the edit screen could not take them either' from 'the completion never ran'"
    return 0
  fi
  # ONE builder, every request body (BTG-084). The create body file is reused, so
  # this write inherits the caller's unlink trap on every exit path rather than
  # staging a second temp file with its own lifecycle.
  if ! js_build_body "$BODY_FILE" syncjs.screen.followup_rejected \
        "the create-completion follow-up body for $key" \
        -n --arg orig "${JS_SCREEN_SAVED_timetracking:-}" --arg prio "${JS_SCREEN_SAVED_priority:-}" \
        --argjson labels "${LABELS_JSON:-[]}" \
        --arg send_tt "$send_tt" --arg send_prio "$send_prio" \
        --arg send_lab "$send_lab" --arg send_desc "$send_desc" "${dargs[@]}" '
    {fields: (
      (if $send_tt   == "yes" then {timetracking: {originalEstimate: $orig}} else {} end)
    + (if $send_prio == "yes" then {priority: {name: $prio}} else {} end)
    + (if $send_lab  == "yes" then {labels: $labels} else {} end)
    + (if $send_desc == "yes" then {description: $desc} else {} end)
    )}'; then
    return 0
  fi
  if js_rest PUT "/rest/api/2/issue/$key" "$BODY_FILE" && js_http_ok; then
    JS_SCREEN_RECOVERED="$recovered"
    js_report syncjs.screen.followup_written \
      "$key was created without$JS_SCREEN_SUPPRESSED; its edit screen carries$recovered, so ONE follow-up PUT wrote them. Both facts are true and both are recorded: the field was unavailable at create AND was recovered"
    return 0
  fi
  js_report syncjs.screen.followup_rejected \
    "the create-completion follow-up PUT for$recovered on $key returned HTTP ${JS_HTTP_STATUS:-transport} -- NON-BLOCKING: $key exists and was already reported created, and turning a successful create into a failed run is the defect BTG-168 removes. Re-run the sync, or write the fields in Jira"
  return 0
}
