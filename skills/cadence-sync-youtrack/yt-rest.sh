#!/usr/bin/env bash
#
# yt-rest.sh -- the transport half of the /cadence-sync-youtrack shared library.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: YouTrack Server speaks a REST
# API under `/api` with a Bearer PERMANENT TOKEN, and that token is an
# operator-environment credential -- it rides curl's `-K-` stdin config block and
# never reaches argv, a temp file, an artifact, or any output channel (Facet 7).
#
# SOURCED by yt-lib.sh, never on its own: it depends on the exit-code vocabulary,
# the reporters and the config resolvers defined there.
#
# Contracts: youtrack-scripts.md. Endpoint shapes: every path this module is
# called with was OBSERVED live against v2026.1 build 13162 --
# archive/BTG-176/spec-2-live-rest-observations.md.

# --------------------------------------------------------------------------
# Transport -- direct YouTrack REST with a Bearer permanent token (AC-1)
# --------------------------------------------------------------------------
# yt_transport_env -- resolve the base URL and token THROUGH the config's `env`
# block, so a rebound variable name is honoured rather than met with a bare 401.
# Cached per process. Sets YT_BASE_URL / YT_TOKEN.
yt_transport_env() {
  [[ -n "${YT_BASE_URL+set}" ]] && return 0
  YT_BASE_URL="$(yt_env_value base_url)" || return "$YT_EXIT_CONFIG"
  YT_TOKEN="$(yt_env_value token)" || return "$YT_EXIT_CONFIG"
  return 0
}

# yt_rest <method> <path> [json-body-file]
#
# Upstream: called by every operation script for its one YouTrack operation.
# Downstream: the `/api/...` surface of the adopter's YouTrack Server, under the
#   base url the config's `env` block binds.
# Spec: archive/BTG-176/spec.md (Proposed Design -- Endpoint map).
#
# The Authorization header is written into curl's `-K-` stdin config block, so
# the token is never a positional argument (invisible to `ps`) and never touches
# a file. On return: YT_HTTP_STATUS holds the status code and YT_HTTP_BODY the
# response body. Returns 0 on a completed exchange (whatever the status), or
# YT_EXIT_TRANSPORT when the exchange itself could not happen -- the caller
# decides the polarity, so no transport failure is ever swallowed here.
#
# NOTE ON STATUS EXPECTATIONS. This instance answers **200** to a create, not
# 201, and answers a missing issue with **404** while answering a missing
# PROJECT with 200 and an empty array (OBSERVED, sidecar 2 §A/§D/§I). Callers
# therefore never infer "found" from a 2xx alone; see yt-resolve.sh.
yt_rest() {
  local method="$1" path="$2" body_file="${3:-}"
  yt_transport_env || return "$YT_EXIT_CONFIG"
  local url="${YT_BASE_URL%/}$path"
  local raw=() args
  args=(-sS -K- -X "$method" -H 'Accept: application/json' -w '\n%{http_code}')
  if [[ -n "$body_file" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body_file")
  fi
  # curl's own -sS diagnostic is CAPTURED, not discarded: it is the only thing
  # that distinguishes a DNS failure from a TLS or proxy error, and "could not
  # reach the instance" is useless to an operator without it.
  #
  # That capture file is a DIAGNOSTIC AID, never the exchange. An unstageable
  # capture file therefore degrades the DETAIL (`/dev/null`, the detail named as
  # missing) and the exchange proceeds; the run then halts at the first site
  # where a scratch file is genuinely load-bearing -- the request body -- naming
  # a scratch condition. Staging it unguarded would make an unusable $TMPDIR
  # report `rest_unreachable` for an instance that was never contacted, which is
  # loud but a MISDIAGNOSIS. `mktemp`'s own stderr is suppressed either way:
  # stderr is reserved for `syncyt.*` conditions.
  local out err_file
  err_file="$(mktemp 2>/dev/null)" || err_file=""
  if ! out="$(printf 'header = "Authorization: Bearer %s"\n' "$YT_TOKEN" \
              | curl "${args[@]}" "$url" 2>"${err_file:-/dev/null}")"; then
    YT_HTTP_STATUS=""
    YT_HTTP_BODY=""
    YT_TRANSPORT_ERROR="curl's diagnostic could not be captured (no scratch file)"
    [[ -n "$err_file" ]] && YT_TRANSPORT_ERROR="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]*$//')"
    [[ -n "$err_file" ]] && rm -f "$err_file"
    return "$YT_EXIT_TRANSPORT"
  fi
  YT_TRANSPORT_ERROR=""
  rm -f "$err_file"
  mapfile -t raw <<<"$out"
  YT_HTTP_STATUS="${raw[-1]}"
  unset 'raw[-1]'
  YT_HTTP_BODY="$(printf '%s\n' "${raw[@]}")"
  return 0
}

# yt_rest_download <path> <dest-file>
#
# Upstream: yt-import.sh's seed-read, for an attachment within the configured
#   per-file ceiling.
# Downstream: writes <dest-file> and nothing else.
#
# The body is streamed STRAIGHT TO THE FILE by curl (`-o`), never through a shell
# variable: a command substitution drops NUL bytes and would silently corrupt
# every binary attachment. On return YT_HTTP_STATUS holds the status; returns 0
# only on a completed 2xx exchange.
#
# THE PATH IS A CREDENTIAL ON THIS INSTANCE and is never echoed, never reported
# and never returned. An attachment's `url` carries a `sign=` parameter and was
# live-observed serving the file's bytes with NO Authorization header (spec
# sidecar 2 I), so anyone holding it can read the file. Callers diagnose with the
# attachment id and the HTTP status; there is deliberately nothing here that
# writes the path anywhere (`syncyt.attachment.signed_url_disclosed`).
yt_rest_download() {
  local path="$1" dest="$2" status
  yt_transport_env || return "$YT_EXIT_CONFIG"
  YT_HTTP_BODY=""
  if ! status="$(printf 'header = "Authorization: Bearer %s"\n' "$YT_TOKEN" \
                 | curl -sS -K- -o "$dest" -w '%{http_code}' "${YT_BASE_URL%/}$path" 2>/dev/null)"; then
    YT_HTTP_STATUS=""
    return "$YT_EXIT_TRANSPORT"
  fi
  YT_HTTP_STATUS="$status"
  yt_http_ok || return "$YT_EXIT_FAIL"
  return 0
}

# yt_http_ok -- true when the last yt_rest exchange returned a 2xx.
yt_http_ok() {
  [[ "${YT_HTTP_STATUS:-}" =~ ^2[0-9][0-9]$ ]]
}

# --------------------------------------------------------------------------
# Body staging -- the ONE builder every request body goes through (AC-14)
# --------------------------------------------------------------------------
# yt_build_body <dest-file> <syncyt.condition> <subject> <jq-arg>...
#
# Upstream: every script that stages a body for a subsequent yt_rest POST.
# Downstream: writes ONLY <dest-file> and, on failure, one syncyt.* line on
# stderr. Spec: archive/BTG-176/spec.md AC-14 (the BTG-084 analog).
#
# Answers BOTH questions the wire needs answered before a body is sent:
#   (a) did jq EXIT 0, and (b) did it PRODUCE content.
# They are DIFFERENT questions. A jq that dies mid-write leaves a TRUNCATED,
# NON-EMPTY file that an emptiness probe reads as "built", and a jq that exits 0
# having written nothing defeats a status probe. Only the pair is a check.
#
# The stakes are higher on this adapter than on the sibling: a `customFields`
# write here is ATOMIC (one bad member rejects the whole body, OBSERVED sidecar 2
# §D), so a partially-built body does not degrade into a partial write -- it
# discards every field in the request.
#
# Returns 0 built / 1 not built. On 1 it emits exactly ONE syncyt.* line naming
# <condition> and composed from <subject>; the CALLER decides whether that is a
# skip or a halt and MUST NOT report again -- a caller that must halt uses a bare
# `exit "$YT_EXIT_FAIL"`, never yt_halt, which would double-report.
#
# jq's own stderr is suppressed: stderr is reserved for syncyt.* conditions, and
# a raw jq diagnostic is not a condition an operator or the orchestrator can
# route. The loudness is RESTORED -- and improved -- by the named condition.
# Reads STDIN when the caller pipes into it.
yt_build_body() {
  local dest="$1" condition="$2" subject="$3"; shift 3
  if ! jq "$@" > "$dest" 2>/dev/null || ! grep -q '[^[:space:]]' "$dest"; then
    yt_report "$condition" \
      "$subject could not be built (jq exited non-zero, or produced nothing) -- issuing NO write rather than the bodyless or MALFORMED request a partial build degrades into, which on this instance would discard every field in the same customFields array"
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------
# The read-back: HTTP 200 is not evidence a field landed (AC-12)
# --------------------------------------------------------------------------
# yt_readback <issue-id> <field-name> <intended-value> [<field-name> <value>]...
#
# Upstream: every script that has just written custom fields to an issue.
# Downstream: ONE extra REST GET against the adopter's instance, per projection.
# Spec: archive/BTG-176/spec.md AC-12 ; sidecar 2 D (the observation that drives it).
#
# WHY THIS EXISTS, in one live observation. A create carrying a custom field the
# resulting issue Type cannot carry returns **HTTP 200** and **silently discards
# the value** -- the field is simply absent from the stored issue. The same
# mismatch on the update path is a loud 400. So a 2xx proves the request was
# accepted, never that the value was applied, and the only defence on the create
# path is to read the issue back and compare.
#
# Reports exactly one line per intended field -- `syncyt.write.field_applied`
# when the read-back carries the intended value, `syncyt.write.field_not_applied`
# (Critical) naming the field and the INTENDED value when it does not. Sets
# YT_FIELDS_VERIFIED to the number confirmed, and YT_FIELDS_NOT_APPLIED to the
# newline-separated NAMES of the ones that were not. Returns 0 when every
# intended field was confirmed, 1 when any was not; the caller decides the
# verdict.
#
# The name list exists because "how many landed" and "WHICH did not" are
# different questions with different consumers: the count is the projection's
# verdict, while AC-15's drift check has to intersect the misses against the
# fields pre-flight had CLAIMED would attach. Re-deriving that by parsing this
# function's own stderr would make an audit line into a machine interface.
#
# A read-back that cannot be performed -- an unreachable instance, a non-2xx, an
# unparseable body -- is NEVER a confirmation. Each intended field is reported
# not-applied with the reason, because "we could not check" and "it landed" are
# the two states this function exists to keep apart, and collapsing them would
# reinstate exactly the silent success AC-12 removes.
#
# The selector is `customFields(name,value(name))` -- the one read-back form
# OBSERVED verbatim against the live instance (sidecar 2 G). The value
# comparison falls back through `presentation` and `login` for the period and
# user forms, whose READ shape under that selector was not observed; those forms
# are unreachable from the shipped configuration and are marked in decisions.md
# as an inference for the live run to close.
# yt_readback_miss <field-name> -- record ONE not-applied field. Both effects
# live here, in one place, because the return code and the name list are two
# views of the same fact: a site that recorded only one of them would leave the
# caller's verdict and the caller's drift check disagreeing about the same field,
# and the disagreement would be silent.
yt_readback_miss() {
  YT_READBACK_MISSED=1
  YT_FIELDS_NOT_APPLIED="${YT_FIELDS_NOT_APPLIED:+$YT_FIELDS_NOT_APPLIED
}$1"
}

yt_readback() {
  local issue="$1"; shift
  YT_FIELDS_VERIFIED=0
  YT_FIELDS_NOT_APPLIED=""
  YT_READBACK_MISSED=0
  local reason=""
  if ! yt_rest GET "/api/issues/$issue?fields=id,idReadable,customFields(name,value(name))"; then
    reason="the read-back GET could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
  elif ! yt_http_ok; then
    reason="the read-back GET returned HTTP $YT_HTTP_STATUS, so no intended field could be confirmed"
  fi

  local fname want got state value
  while [[ $# -ge 2 ]]; do
    fname="$1"; want="$2"; shift 2
    if [[ -n "$reason" ]]; then
      yt_report syncyt.write.field_not_applied \
        "'$fname' was written with the intended value '$want' but could NOT be verified: $reason"
      yt_readback_miss "$fname"
      continue
    fi
    got="$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg n "$fname" '
        ((.customFields // []) | map(select(.name == $n)) | .[0]) as $f
        | if $f == null then "absent\t"
          else (($f.value.name? // $f.value.presentation? // $f.value.login?
                 // (if ($f.value|type) == "number" or ($f.value|type) == "string"
                     then ($f.value|tostring) else null end)) as $v
                | if $v == null then "empty\t" else "present\t" + $v end)
          end' 2>/dev/null)" || got=""
    state="${got%%$'\t'*}"; value="${got#*$'\t'}"
    case "$state" in
      present)
        if [[ "$value" == "$want" ]]; then
          yt_report syncyt.write.field_applied \
            "'$fname' was read back as '$value', matching the intended value"
          YT_FIELDS_VERIFIED=$((YT_FIELDS_VERIFIED + 1))
        else
          yt_report syncyt.write.field_not_applied \
            "'$fname' was written with the intended value '$want' but the issue carries '$value'"
          yt_readback_miss "$fname"
        fi ;;
      absent)
        # The OBSERVED silent-discard shape: the instance answered 2xx and the
        # field is not on the issue at all. This is data loss, not a partial
        # success, and it is the reason this function exists.
        yt_report syncyt.write.field_not_applied \
          "'$fname' was written with the intended value '$want' but is ABSENT from the issue -- the instance accepted the write and discarded the value (this field does not attach under the resolved Type)"
        yt_readback_miss "$fname" ;;
      *)
        yt_report syncyt.write.field_not_applied \
          "'$fname' was written with the intended value '$want' but the read-back carries no usable value for it"
        yt_readback_miss "$fname" ;;
    esac
  done
  return "$YT_READBACK_MISSED"
}

# --------------------------------------------------------------------------
# Rejection attribution: the adapter names the field, never the instance (AC-13)
# --------------------------------------------------------------------------
# yt_classify_rejection <field> <intended-value> <config-key> [<field> <value> <key>]...
#
# Upstream: every script holding a non-2xx from a field write, passing the SAME
#   triples it intended to write.
# Downstream: exactly one syncyt.* audit line. Issues no request and changes
#   nothing. Spec: archive/BTG-176/spec.md AC-13 ; sidecar 2 C/D.
#
# Returns 0 having reported an ATTRIBUTED condition when the rejection matches a
# recognized class, and 1 having reported nothing when it does not -- the caller
# then falls back to its own generic condition, so an unrecognized rejection is
# still loud and is never swallowed here.
#
# WHY THE FIELD NAME CANNOT BE TAKEN FROM THE INSTANCE. The live message for an
# unmapped bundle value is
#   "An <value>-type entity with the specified name ({1}) was not found"
# -- the offending VALUE sits where the entity type belongs and the field name
# is an unfilled placeholder. So the instance's text is never parsed for the
# pair. Instead each INTENDED triple is tested against the message, and the one
# that matches names itself: the field, the value and the configuration key an
# operator has to correct all come from the caller's own intent.
#
# The two recognized classes, both OBSERVED:
#   400 "An <value>-type entity ..."          -> the project's bundle has no such
#                                                VALUE  (schema.value_absent)
#   500 "incompatible-issue-custom-field-name-<field>"
#                                             -> the project defines no such
#                                                FIELD  (rest.unknown_field_name)
# The second is a **5xx for a permanent configuration error**. It is reported as
# a configuration fault and is NEVER retried: a retry policy that treated it as
# the transient class 5xx usually means would hammer the instance forever over a
# typo.
yt_classify_rejection() {
  local fname want key
  # Cleared on every call: a stale name from a PREVIOUS rejection would attribute
  # this one's drift to a field that is not even in this body.
  YT_REJECTED_ATTACHMENT_FIELD=""
  while [[ $# -ge 3 ]]; do
    fname="$1"; want="$2"; key="$3"; shift 3
    case "${YT_HTTP_BODY:-}" in
      *"An $want-type entity with the specified name"*)
        yt_report syncyt.schema.value_absent \
          "'$fname' was set to '$want', a value this project's bundle does not carry -- the instance rejected the write with HTTP ${YT_HTTP_STATUS:-}. Correct '$key' in $(yt_config_path). The field and the value named here are this step's OWN intent: the instance's message puts the value where the entity type belongs and leaves the field name unfilled, so it cannot be relayed"
        return 0 ;;
      *'"invalid_properties"'*"You can only update the value for the $fname field"*)
        # The offending field is matched on the FULL observed opening clause,
        # not on "the value for the <field> field" alone: that fragment occurs
        # TWICE in the live message -- once for the field that was refused and
        # once for the field it depends on -- so the shorter pattern attributes
        # the rejection to whichever intended field is tested first. A message
        # this pattern does not recognize falls through to the caller's generic
        # condition, so a reworded message costs attribution, never loudness.
        #
        # The LOUD half of the conditional-attachment defect. The create path
        # loses the same value in silence (see yt_readback); this path is told
        # about it. Both are reported with the SAME condition on purpose -- one
        # misconfiguration must not wear two names depending on which path a run
        # happened to take.
        # Recorded by NAME as well as reported. This is the one rejection class
        # that means "the server says this field cannot attach under this Type",
        # which is exactly the claim `type_conditional_fields` also makes -- so
        # it is the only class whose field the caller's AC-15 drift check can
        # act on. The other two classes are a bundle-VALUE fault and a
        # field-NAME fault; neither is an attachment disagreement, and recording
        # them here would make the drift signal fire on unrelated typos.
        YT_REJECTED_ATTACHMENT_FIELD="$fname"
        yt_report syncyt.write.field_not_applied \
          "'$fname' was written with the intended value '$want' and REJECTED with HTTP ${YT_HTTP_STATUS:-}: this field does not attach under the issue's resolved Type. Nothing in the request was applied, not the other fields and not the summary, so there is nothing to undo. Correct '$key' in $(yt_config_path), or the type map that resolves the Type"
        return 0 ;;
      *"incompatible-issue-custom-field-name-$fname"*)
        yt_report syncyt.rest.unknown_field_name \
          "this project defines no custom field named '$fname' -- the instance rejected the write with HTTP ${YT_HTTP_STATUS:-}, which is a PERMANENT configuration fault wearing a 5xx's clothes and is NOT retried. Correct '$key' in $(yt_config_path)"
        return 0 ;;
    esac
  done
  return 1
}
