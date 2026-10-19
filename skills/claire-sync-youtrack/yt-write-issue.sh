#!/usr/bin/env bash
#
# yt-write-issue.sh -- create or update the ticket's YouTrack issue: summary and
# description.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariants relied on from outside this boundary, each OBSERVED live against
# v2026.1 build 13162 (spec sidecar 2 §D) rather than assumed:
#   - a create is `POST /api/issues` and answers **HTTP 200**, not 201;
#   - an update is `POST /api/issues/<id>` -- not PUT, not PATCH;
#   - the description field renders **Markdown** (rendering class
#     `common-markdown`), so the rendered file is sent verbatim and is NOT
#     converted to Jira wiki markup. This is one of the adapter's documented
#     divergences from its sibling, not an omission;
#   - a `POST /api/issues/<id>` for an issue that does not exist answers 404.
#
# Upstream: the /claire-sync-youtrack orchestrator, after yt-connect.sh and
#   yt-resolve.sh; `--project` and `--issue` are yt-resolve.sh's own stdout.
# Downstream: ONE REST POST against the adopter's YouTrack instance. It reads
#   `metadata.yaml` and NEVER writes it -- the orchestrator applies the single
#   end-of-operation write.
# Spec: archive/BTG-176/spec.md (Proposed Design -- Endpoint map, Signatures) ;
#   youtrack-scripts.md.
#
# Contract (three channels):
#   args   : --ticket <id> --description-file <path>
#            (--project <0-NNN> on create | --issue <id> on update)
#   stdout : issue_id=<2-NNNN>  issue_readable=<KEY-N>  youtrack_url=<url>
#            write_result=created|updated  fields_verified=<n>
#   stderr : syncyt.write.* reported conditions
#   exit   : 0 ok / 1 rejected / 2 usage / 3 transport / 4 config HALT
#
# THE FIELD WRITES AND THEIR VERIFICATION SHIP TOGETHER, and that is not a
# stylistic choice. This instance accepts a custom field that cannot attach under
# the resolved Type with **HTTP 200 and then silently DROPS it** from the stored
# issue (OBSERVED, sidecar 2 D). So the mapped fields are never written without
# the read-back that proves they landed: a step that wrote them and trusted the
# 2xx would report a successful projection while losing the value.
#
# The state field is deliberately NOT written here -- it is the state step's one
# operation (spec.md, Script inventory), over the project's single project-wide
# state bundle.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""; DESC_FILE=""; PROJECT=""; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--description-file|--project|--issue)
      # Guard the pair BEFORE the `shift 2` that consumes it -- see the same
      # guard in yt-resolve.sh for why an unguarded `shift 2` spins forever.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.write.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket)           TICKET="$2" ;;
        --description-file) DESC_FILE="$2" ;;
        --project)          PROJECT="$2" ;;
        --issue)            ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.write.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.write.usage "--ticket <id> is required"
[[ -n "$DESC_FILE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.write.usage "--description-file <path> is required"
[[ -f "$DESC_FILE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.write.usage \
  "--description-file names a path that does not exist: $DESC_FILE"
[[ -n "$PROJECT" || -n "$ISSUE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.write.usage \
  "exactly one of --project <id> (create) or --issue <id> (update) is required"

# THE RENDERED DESCRIPTION IS THIS PROJECTION'S ONLY COPY, and this script owns
# its end of life: the orchestrator hands the path over and never unlinks it.
# The trap is armed HERE -- as soon as the path is known and BEFORE anything
# that can fail -- so the unlink is not a happy-path-only guarantee. A rendered
# body left behind in $TMPDIR is ticket content at rest that a later run could
# re-send onto a different issue, which is the same cross-ticket leak `mktemp`
# freshness exists to prevent, one step further along.
# $BODY is added to the same cleanup below, once it is staged.
BODY=""
yt_write_cleanup() { rm -f "${DESC_FILE:-}" "${BODY:-}" 2>/dev/null || :; }
trap yt_write_cleanup EXIT

yt_config_require
yt_metadata_load "$TICKET"

SUMMARY="$(yt_metadata_get '.title')"
if [[ -z "$SUMMARY" ]]; then
  # An issue with no summary is not a projection, it is a blank. Refused here,
  # before the wire, rather than sent and left for the instance to accept.
  yt_halt "$YT_EXIT_FAIL" syncyt.write.summary_absent \
    "$TICKET metadata.yaml carries no non-empty 'title' -- refusing to create or update an issue with no summary"
fi

# --- the mapped custom fields ----------------------------------------------
# Resolved through the config's maps, never from a literal here: the bundle
# values are instance-varying and an unmapped one is a guaranteed HTTP 400 on
# this instance (OBSERVED). yt_config_map is fail-loud, so an absent entry HALTs
# with the offending key named rather than projecting a guess.
#
# FIELDS carries one (name, value, $type, config-key) QUAD per intended field.
# The config key rides along so that a rejection can name the entry an operator
# has to correct rather than only the field that failed. The $type values are
# YouTrack model constants, not adopter configuration: an enum-backed
# single-value field is written as an object carrying `name` (OBSERVED, sidecar 2
# D's write-form table).
FIELDS=()
PREFLIGHT_ATTACHES=""
YT_ENUM_TYPE=SingleEnumIssueCustomField
REPO_TYPE="$(yt_metadata_get '.type')"
REPO_PRIORITY="$(yt_metadata_get '.priority')"
FIELD_TYPE="$(yt_config_map issue_type_map "$REPO_TYPE")" || exit "$YT_EXIT_CONFIG"
FIELD_PRIORITY="$(yt_config_map priority_map "$REPO_PRIORITY")" || exit "$YT_EXIT_CONFIG"
FIELDS+=(Type "$FIELD_TYPE" "$YT_ENUM_TYPE" "issue_type_map.$REPO_TYPE")
FIELDS+=(Priority "$FIELD_PRIORITY" "$YT_ENUM_TYPE" "priority_map.$REPO_PRIORITY")

# ...plus whatever the adopter's custom_field_map projects. A repo key whose
# value is EMPTY contributes nothing: there is no value to project, and sending
# an empty one would overwrite a field a human may have set by hand.
CF_ROWS="$(yt_config_field_map)" || exit "$YT_EXIT_CONFIG"

# THE GUARD POSTURE, ANNOUNCED ONCE PER PROJECTION (AC-15). With no usable
# `type_conditional_fields` map the pre-flight refusal cannot be evaluated at
# all, so this projection runs on ONE guard -- the read-back -- instead of two.
# That is a degradation and it is said out loud; it is NOT a halt. Halting every
# projection over an optional map an adopter never wrote would turn a
# recoverable state (the read-back still catches the observed silent discard)
# into an outage, which is the wrong trade in the direction that loses the most.
#
# Emitted BEFORE the loop and outside it, so an adopter with ten mapped fields
# reads one line about the run rather than ten about the same missing key.
if ! yt_conditional_map_usable; then
  yt_report syncyt.config.conditional_map_absent \
    "$(yt_config_path) carries no usable 'type_conditional_fields' map, so the pre-flight refusal cannot be evaluated for $TICKET -- this projection is guarded ONLY by the post-write read-back. That still catches a field the instance accepts and silently discards, but it catches it AFTER the request; declare the map to refuse an impossible field before the wire"
fi

while IFS=$'\t' read -r CF_KEY CF_FIELD CF_TYPE; do
  [[ -n "$CF_KEY" ]] || continue
  CF_VALUE="$(yt_metadata_get ".$CF_KEY")"
  CF_VERDICT="$(yt_field_attachment "$FIELD_TYPE" "$CF_FIELD")"
  if [[ -z "$CF_VALUE" ]]; then
    # A field the config declares under some OTHER type, for a ticket that holds
    # no value for it, is a routine non-event -- the schema does not carry it
    # here and there is nothing to lose. It is recorded BY NAME rather than
    # passed over in silence, because the RATE of these skips is the baseline
    # that makes a real drop stand out; but it is not a failure, and an adapter
    # that failed every such projection would cry wolf until nobody read the
    # condition at all.
    if [[ "$CF_VERDICT" == "refused" ]]; then
      yt_report syncyt.write.conditional_field_skipped \
        "'$CF_FIELD' is not sent: the configuration declares it does not attach under this issue's resolved type, and $TICKET carries no value for it (custom_field_map.$CF_KEY)"
    fi
    continue
  fi
  # THE PRE-FLIGHT REFUSAL (AC-15). A real value mapped into a type that the
  # configuration itself says cannot carry it is a CONFIGURATION ERROR, not a
  # routine skip, and the whole projection is refused before any request is
  # issued. Dropping only the offending field would project a ticket that
  # silently disagrees with the repository -- the same silence the read-back
  # exists to remove, reintroduced one layer up.
  #
  # This is the first of the two guards, not a replacement for the second: it
  # cannot see a rule that changed on the instance after this map was written,
  # so the read-back still runs on every projection that gets past here
  # (DEC-015). Recorded before any call, so a refusal and a rejection can never
  # be confused -- one leaves an empty call log, the other does not.
  if [[ "$CF_VERDICT" == "refused" ]]; then
    YT_PREFLIGHT_REFUSED="$CF_FIELD"
    yt_report syncyt.write.preflight_refused \
      "REFUSING the whole projection of $TICKET before any request: '$CF_FIELD' is set to '$CF_VALUE', and the configuration declares that field does not attach to an issue whose type is '$FIELD_TYPE'. On the create path this instance would answer HTTP 200 and silently discard the value. Correct custom_field_map.$CF_KEY, type_conditional_fields.$FIELD_TYPE, or issue_type_map.$REPO_TYPE"
    exit "$YT_EXIT_FAIL"
  fi
  # THE CLAIM, RECORDED SO IT CAN BE CHECKED (AC-15 drift). `attaches` is the
  # only verdict that is a positive statement about the instance's schema --
  # `unguarded`, `type-undeclared` and `map-absent` all mean the config said
  # NOTHING. Only a field the map actively promised can be observed to disagree
  # with the server, so only those names are carried forward.
  [[ "$CF_VERDICT" == "attaches" ]] && PREFLIGHT_ATTACHES="${PREFLIGHT_ATTACHES:+$PREFLIGHT_ATTACHES
}$CF_FIELD"
  FIELDS+=("$CF_FIELD" "$CF_VALUE" "$CF_TYPE" "custom_field_map.$CF_KEY")
done <<<"$CF_ROWS"

# yt_report_preflight_disagreement <field-name>... -- for each named field the
# instance did not apply, report the drift IF pre-flight had claimed it attaches.
#
# WHY THE SECOND CONDITION IS NOT REDUNDANT WITH THE FIRST. `field_not_applied`
# reports the SYMPTOM -- a value did not land -- and sends an operator looking at
# the instance. This one reports the CAUSE and names the file to correct: the
# adopter's `type_conditional_fields` map describes a REMOTE schema and rots
# without anyone touching it, so a field it still promises can quietly stop
# attaching when an administrator moves it between Types. Its declared baseline
# is ZERO, which is what makes any occurrence actionable rather than a rate to
# watch.
#
# The INVERSE half of the catalogue's definition -- pre-flight REFUSING a field
# the server would have accepted -- is structurally unobservable here and is not
# faked: a refusal issues no request, so there is no server answer to compare
# against. Only the observable half is implemented.
yt_report_preflight_disagreement() {
  local f
  for f in "$@"; do
    [[ -n "$f" ]] || continue
    printf '%s\n' "${PREFLIGHT_ATTACHES:-}" | grep -qxF "$f" || continue
    yt_report syncyt.write.preflight_disagreed \
      "'$f' was not applied, but type_conditional_fields in $(yt_config_path) declares that it DOES attach under Type '$FIELD_TYPE' -- the configuration and the instance disagree about this project's schema. This is CONFIG DRIFT, not a transport fault: the exchange completed and the instance answered. Re-read the project's field-to-Type attachment and correct type_conditional_fields.$FIELD_TYPE"
  done
}

BODY="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.write.scratch_unavailable \
  "could not stage a request body (no scratch file) -- issuing no write"
# The EXIT trap set above already removes both paths; $BODY is simply now
# non-empty. Re-arming it here would REPLACE the handler and strand the rendered
# description -- which is exactly the defect this line used to be.

# The description is read from the rendered FILE with --rawfile, so its newlines,
# quotes and backslashes reach the instance exactly as rendered. Splicing it into
# a jq program instead would make any of those three a body-corrupting character.
#
# The customFields array is assembled INSIDE the one checked builder (AC-14),
# from the triples above -- never spliced together as text. A partially built
# body is not a partial write on this instance: one malformed member rejects the
# whole request and discards every field in it (OBSERVED, sidecar 2 D/G).
#
# The value SHAPE is decided by the field's `$type`, and each branch is an
# OBSERVED write form (sidecar 2 D): an enum- or state-backed single-value field
# takes an object carrying `name`, a simple field takes a BARE scalar. The
# `else` arm is unreachable -- yt_config_field_map allowlists the types before
# this program runs -- and it raises rather than falling through to a default
# shape, so an allowlist and a builder that ever drift apart fail loudly instead
# of writing a field in a form nothing implements.
YT_CF_PROGRAM='(if ($ARGS.positional|length) > 0 then
    {customFields: [ $ARGS.positional as $a
                     | range(0; ($a|length); 3)
                     | {name: $a[.], "$type": $a[.+2],
                        value: (if   $a[.+2] == "SimpleIssueCustomField"
                                then ($a[.+1] | tonumber? // .)
                                elif $a[.+2] == "SingleEnumIssueCustomField"
                                  or $a[.+2] == "StateIssueCustomField"
                                then {name: $a[.+1]}
                                else error("no write form for " + $a[.+2]) end)} ]}
  else {} end)'
CF_ARGS=()
for ((i = 0; i < ${#FIELDS[@]}; i += 4)); do
  CF_ARGS+=("${FIELDS[i]}" "${FIELDS[i+1]}" "${FIELDS[i+2]}")
done
if [[ -n "$ISSUE" ]]; then
  MODE=updated
  TARGET="/api/issues/$ISSUE?fields=id,idReadable"
  yt_build_body "$BODY" syncyt.write.body_unbuildable "the issue update body for $TICKET" \
    -n --arg s "$SUMMARY" --rawfile d "$DESC_FILE" \
    "{summary:\$s,description:\$d} + $YT_CF_PROGRAM" --args "${CF_ARGS[@]}" \
    || exit "$YT_EXIT_FAIL"
else
  MODE=created
  TARGET="/api/issues?fields=id,idReadable"
  yt_build_body "$BODY" syncyt.write.body_unbuildable "the issue create body for $TICKET" \
    -n --arg p "$PROJECT" --arg s "$SUMMARY" --rawfile d "$DESC_FILE" \
    "{project:{id:\$p},summary:\$s,description:\$d} + $YT_CF_PROGRAM" --args "${CF_ARGS[@]}" \
    || exit "$YT_EXIT_FAIL"
fi

# THE BYPASS SEAM (AC-15, IMPOSSIBLE_STATE). By construction the refusal above
# exits, so this can never fire -- which is exactly why it is here. A guard that
# cannot fire is indistinguishable from a guard that is not there, and the state
# it guards against ("pre-flight decided to refuse this projection, and a
# mutating request went out anyway") is the one failure that would make every
# AC-15 assertion in the suite vacuous at once. It is placed immediately before
# the request, not near the decision, so no future edit can slip a code path
# between the two.
if [[ -n "${YT_PREFLIGHT_REFUSED:-}" ]]; then
  yt_halt "$YT_EXIT_FAIL" syncyt.write.preflight_bypassed \
    "a mutating request was about to be issued for a projection pre-flight had REFUSED ('$YT_PREFLIGHT_REFUSED') -- issuing nothing. This is an adapter defect, not a configuration one: the refusal and the request must never both happen"
fi

if ! yt_rest POST "$TARGET" "$BODY"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "POST $TARGET could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
fi
if ! yt_http_ok; then
  # An ATTRIBUTED condition when the rejection names one of the fields this step
  # intended, the generic one otherwise -- exactly one of the two. Nothing is
  # re-read and nothing is compensated: a rejected write applies NOTHING on this
  # instance, not even the valid members of the same body (OBSERVED, sidecar 2
  # G), so there is no partial state to repair and no request to re-issue.
  CLASSIFY=()
  for ((i = 0; i < ${#FIELDS[@]}; i += 4)); do
    CLASSIFY+=("${FIELDS[i]}" "${FIELDS[i+1]}" "${FIELDS[i+3]}")
  done
  # The attributed path additionally checks the AC-15 claim: a REJECTED
  # conditional field is the loud half of the same schema disagreement the
  # read-back catches silently on the create path.
  yt_classify_rejection "${CLASSIFY[@]}" \
    && yt_report_preflight_disagreement "${YT_REJECTED_ATTACHMENT_FIELD:-}" \
    || yt_report syncyt.write.rest_rejected \
         "POST $TARGET returned HTTP $YT_HTTP_STATUS -- the issue was not $MODE. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
  exit "$YT_EXIT_FAIL"
fi

ISSUE_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)" || ISSUE_ID=""
ISSUE_READABLE="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.idReadable // empty' 2>/dev/null)" || ISSUE_READABLE=""
if [[ -z "$ISSUE_ID" || -z "$ISSUE_READABLE" ]]; then
  # A 200 whose body does not carry both ids is not a usable success: every later
  # step addresses the issue by one or the other, and the `youtrack_url` the
  # orchestrator records is the run's ONLY identity mapping. Reporting success
  # here would lose the issue that was just created.
  yt_halt "$YT_EXIT_FAIL" syncyt.write.shape_unrecognized \
    "POST $TARGET returned HTTP $YT_HTTP_STATUS but no usable id/idReadable pair -- refusing to report a write whose issue cannot be addressed. Body: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi

# --- the read-back: the 2xx above is not evidence the fields landed --------
# One extra GET per projection, and it is the only defence against the observed
# silent discard on the create path. The intended values are re-stated here from
# the SAME triples that were sent, so the comparison is against this step's own
# intent rather than against anything the instance chose to echo back.
READBACK=()
for ((i = 0; i < ${#FIELDS[@]}; i += 4)); do
  READBACK+=("${FIELDS[i]}" "${FIELDS[i+1]}")
done
yt_readback "$ISSUE_ID" "${READBACK[@]}"; VERIFIED=$?
# Read as a LIST, never re-parsed out of the audit stream: yt_readback hands back
# the names it missed, and only the ones pre-flight had PROMISED are drift.
mapfile -t NOT_APPLIED <<<"${YT_FIELDS_NOT_APPLIED:-}"
yt_report_preflight_disagreement "${NOT_APPLIED[@]+"${NOT_APPLIED[@]}"}"

BASE="$(yt_env_value base_url)"
yt_emit issue_id "$ISSUE_ID"
yt_emit issue_readable "$ISSUE_READABLE"
# The READABLE id is used in the recorded url, preserving the base-url-then-
# `/issue/` shape this adapter has always written and keeping the value
# clickable. Both id forms address the issue on read (OBSERVED), so the choice
# costs nothing on the update path.
#
# The base url is resolved THROUGH the config's `env` block, never by naming an
# environment variable here: the NAME is adopter-rebindable, and this comment
# deliberately describes the shape rather than reproducing the interpolation --
# a literal reproduced in prose becomes an occurrence that every census over the
# adapter's neutral source then has to account for.
yt_emit youtrack_url "${BASE%/}/issue/$ISSUE_READABLE"
yt_emit write_result "$MODE"
yt_emit fields_verified "$YT_FIELDS_VERIFIED"

# The identity is emitted even when a field did not land, and the exit code is
# still a failure. Both halves matter: the issue EXISTS, so the orchestrator must
# be able to record its url (losing it strands a duplicate on the next run --
# see yt-resolve.sh), and the projection is nonetheless INCOMPLETE, so it is
# never reported as success. A quietly partial projection is the one outcome
# AC-12 exists to remove.
[[ "$VERIFIED" -eq 0 ]] || exit "$YT_EXIT_FAIL"
exit "$YT_EXIT_OK"
