#!/usr/bin/env bash
#
# jira-preserve.sh -- preserve a ticket's as-filed original intake as a comment.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: the very next step of the sync
# OVERWRITES the issue's summary and description with the repo's projection. On
# an externally-filed ("imported") ticket that content is a business user's
# intake -- once overwritten it is gone. So it is captured here, BEFORE the
# overwrite, and ANY failure to capture it stops the sequence (exit non-zero)
# rather than letting the overwrite proceed. "Fail loud" here is not a style
# choice: a swallowed failure is data loss.
#
# Upstream: invoked by the /cadence-sync-jira orchestrator immediately before the
#   projection write, on every sync (it decides for itself whether to act).
# Downstream: `GET /rest/api/2/field` (acceptance-criteria field discovery, when
#   enabled), `GET /rest/api/2/issue/{key}` (the as-filed fields, RAW wiki), and
#   `POST /rest/api/2/issue/{key}/comment`.
# Spec: archive/BTG-075/spec.md (AC-5) ; decisions.md DEC-005 ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --issue-key <KEY>
#   stdout : preserved=true|skipped
#   stderr : syncjs.* reported conditions
#   exit   : 0 ok or sanctioned skip / 1 fail-loud / 2 usage / 3 transport / 4 config HALT
#
# ZERO INFERENCE (AC-5): the comment is built here, by substituting the tokens of
# the co-located `originalcontent_TEMPLATE.txt` -- a pure-content sidecar with no
# directive prose for an agent to interpret (DEC-005). The as-filed values are
# copied VERBATIM: this is the original, so it is never reformatted, re-wrapped,
# summarized, or converted. The raw wiki read by REST v2 is posted back as wiki.
#
# This script READS metadata-adjacent Jira state and NEVER writes metadata.yaml.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/originalcontent_TEMPLATE.txt"

ISSUE_KEY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-key) js_argv_pair syncjs.comment.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.comment.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.comment.usage "--issue-key <KEY> is required"

FIELDS_FILE=""
COMMENT_FILE=""
BODY_FILE=""
js_cleanup() { rm -f "${FIELDS_FILE:-}" "${COMMENT_FILE:-}" "${BODY_FILE:-}" 2>/dev/null; }
trap js_cleanup EXIT

js_config_require
[[ -f "$TEMPLATE" ]] || js_halt "$JS_EXIT_USAGE" syncjs.comment.template_absent \
  "the preservation template is missing: $TEMPLATE"

BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.comment.env_absent \
  "the base-URL environment variable is unset -- cannot preserve the as-filed original, so the sync must NOT proceed to overwrite it"

# --- acceptance-criteria field discovery (toggle-gated, NON-blocking) -------
# BTG-046 re-homed. The field is plugin-provided and its id differs per instance,
# so it is discovered by EXACT name -- never hardcoded and never guessed: zero
# matches or more than one both resolve to "no AC line", reported, rather than a
# best guess at which custom field holds someone's acceptance criteria.
AC_ENABLED=no
AC_ON=0               # the resolved toggle -- the F2 preservation gate anchors here
AC_PRESERVE_FIELD=""  # folded into the preservation GET's field list when resolved
AC_FIELD_ID=""
js_config_toggle acceptance_criteria_sync_enabled
case "$?" in
  0) AC_ENABLED=yes ;;
  1) js_report syncjs.ac.disabled \
       "acceptance_criteria_sync_enabled is off -- no AC field call is made in either direction and the AC line is omitted" ;;
  *) exit "$JS_EXIT_CONFIG" ;;
esac

if [[ "$AC_ENABLED" == "yes" ]]; then
  AC_FIELD_NAME="$(js_config_map acceptance_criteria field_name)" || exit "$JS_EXIT_CONFIG"
  if ! js_rest GET /rest/api/2/field; then
    js_report syncjs.ac.field_discovery_failed "the field-discovery GET could not reach ${BASE_URL%/} -- the AC line renders as none"
  elif ! js_http_ok; then
    js_report syncjs.ac.field_discovery_failed "the field-discovery GET returned HTTP $JS_HTTP_STATUS -- the AC line renders as none"
  else
    AC_MATCHES="$(printf '%s' "$JS_HTTP_BODY" \
      | jq -r --arg n "$AC_FIELD_NAME" 'if type == "array" then [.[] | select(.name == $n) | .id] else [] end | .[]' 2>/dev/null)"
    case "$(printf '%s' "$AC_MATCHES" | grep -c .)" in
      0) js_report syncjs.ac.field_absent "no field named exactly '$AC_FIELD_NAME' on this instance -- the AC line renders as none" ;;
      1) AC_FIELD_ID="$AC_MATCHES"; AC_ON=1; AC_PRESERVE_FIELD=",$AC_FIELD_ID" ;;
      *) js_report syncjs.ac.field_ambiguous \
           "more than one field named exactly '$AC_FIELD_NAME' -- never guessing which one holds the acceptance criteria" ;;
    esac
  fi
fi

# --- read the AS-FILED fields (RAW wiki) ------------------------------------
READ_FIELDS="summary,description,issuetype,priority,timetracking,labels$AC_PRESERVE_FIELD"

if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=$READ_FIELDS"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "GET /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/} -- NOT preserving, so the sync must NOT overwrite the original"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.comment.rest_read_rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS -- the as-filed original could not be read, so the sync must NOT overwrite it"
fi

FIELDS_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.comment.scratch_unavailable "no scratch file could be staged for $ISSUE_KEY's field read -- the as-filed original could not be read, so the sync must NOT overwrite it"
printf '%s' "$JS_HTTP_BODY" > "$FIELDS_FILE"
if ! CURRENT_DESCRIPTION="$(jq -r 'if type == "object" then (.fields.description // "") else error("not an object") end' \
      "$FIELDS_FILE" 2>/dev/null)"; then
  js_halt "$JS_EXIT_FAIL" syncjs.comment.rest_read_rejected \
    "the issue read returned an unparseable body -- the as-filed original could not be read, so the sync must NOT overwrite it"
fi

# --- the skip sentinel ------------------------------------------------------
# The plain-text phrase `Repo-managed` is format-invariant: it appears verbatim
# in the raw wiki whether the banner was authored as a {panel} title or as bold.
# Its presence means the repo already owns this description -- there is no
# original to preserve, and posting again would add a duplicate comment on every
# single sync. This is also what makes a re-run idempotent (DEC-009).
if [[ "$CURRENT_DESCRIPTION" == *"Repo-managed"* ]]; then
  js_report syncjs.comment.skipped_repo_managed \
    "$ISSUE_KEY already carries the repo-managed banner -- there is no as-filed original to preserve"
  js_emit preserved skipped
  exit "$JS_EXIT_OK"
fi

# --- build the comment, entirely in script (AC-5) ---------------------------
COMMENT_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.comment.scratch_unavailable "no scratch file could be staged for the preservation comment -- the as-filed original is still un-preserved, so the sync must NOT overwrite it"
if ! python3 - "$TEMPLATE" "$FIELDS_FILE" "$ISSUE_KEY" "$AC_FIELD_ID" "$AC_ENABLED" > "$COMMENT_FILE" <<'PY'
import json, sys

template_path, fields_path, issue_key, ac_field_id, ac_enabled = sys.argv[1:6]
doc = json.load(open(fields_path, encoding='utf-8'))
f = doc.get("fields") or {}

def named(value):
    return (value or {}).get("name") or ""

def ac_lines(value):
    """The as-filed AC record, STATE-PRESERVING -- `(x)` when the filed item was
    checked, `( )` when it was not. Deliberately unlike the outbound projection,
    which is always unchecked: this is the original, so it reflects what was
    actually filed."""
    if isinstance(value, list):
        out = []
        for item in value:
            if isinstance(item, dict):
                mark = "(x)" if item.get("checked") else "( )"
                out.append("%s %s" % (mark, item.get("name") or item.get("value") or ""))
            elif item is not None:
                out.append("( ) %s" % item)
        return "\n".join(out)
    if isinstance(value, str):
        return value
    return ""

labels = f.get("labels") or []
tokens = {
    "ticket_key":          issue_key,
    "original_summary":    f.get("summary") or "_(no summary was filed)_",
    "original_type":       named(f.get("issuetype")) or "_(none)_",
    "original_priority":   named(f.get("priority")) or "_(none)_",
    "original_estimate":   ((f.get("timetracking") or {}).get("originalEstimate")) or "_(none)_",
    "original_labels":     ", ".join(labels) if labels else "_(none)_",
    "original_acceptance_criteria":
        (ac_lines(f.get(ac_field_id)) if ac_field_id else "") or "_(none)_",
    "original_description": f.get("description") or "_(no description was filed)_",
}

AC_TOKEN = "{{original_acceptance_criteria}}"
out = []
for line in open(template_path, encoding='utf-8').read().splitlines():
    # The line is OMITTED for one reason only: the toggle is OFF, so no AC call
    # was made in either direction and the adapter has nothing to say about the
    # field. Every OTHER unresolved case -- field absent, name ambiguous,
    # discovery failed -- DID look and found nothing usable, and renders the
    # template's own "If missing" value `_(none)_`. Omitting the line there says
    # "acceptance criteria are not part of this record" when what happened is
    # "this instance would not tell us", and the reader cannot tell the two apart.
    if AC_TOKEN in line and ac_enabled != "yes":
        continue
    for key, value in tokens.items():
        line = line.replace("{{%s}}" % key, value)
    out.append(line)
sys.stdout.write("\n".join(out) + "\n")
PY
then
  js_halt "$JS_EXIT_FAIL" syncjs.comment.render_failed \
    "the preservation comment could not be rendered from $TEMPLATE -- NOT overwriting the original"
fi

# --- post it ----------------------------------------------------------------
# jq does the JSON encoding of arbitrary as-filed text (`--rawfile`), so nothing
# in a business user's intake can break out of the request body.
BODY_FILE="$(mktemp 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.comment.scratch_unavailable "no scratch file could be staged for the comment POST body -- the as-filed original is still un-preserved, so the sync must NOT overwrite it"
js_build_body "$BODY_FILE" syncjs.comment.body_unbuildable \
  "the preservation-comment body for $ISSUE_KEY -- the as-filed original is still un-preserved, so the sync must NOT overwrite it" \
  -n --rawfile b "$COMMENT_FILE" '{body: $b}' || exit "$JS_EXIT_FAIL"

if ! js_rest POST "/rest/api/2/issue/$ISSUE_KEY/comment" "$BODY_FILE"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "POST /rest/api/2/issue/$ISSUE_KEY/comment could not reach ${BASE_URL%/} -- the original is still un-preserved, so the sync must NOT overwrite it"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.comment.rest_post_rejected \
    "POST /rest/api/2/issue/$ISSUE_KEY/comment returned HTTP $JS_HTTP_STATUS -- the original is still un-preserved, so the sync must NOT overwrite it"
fi

js_report syncjs.comment.preserved \
  "the as-filed original of $ISSUE_KEY was posted wiki-native via direct REST v2 (renders exactly as authored)"
js_emit preserved true
exit "$JS_EXIT_OK"
