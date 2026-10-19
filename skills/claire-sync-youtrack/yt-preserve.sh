#!/usr/bin/env bash
#
# yt-preserve.sh -- preserve an issue's as-filed original intake as a comment.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: the very next step of the sync
# OVERWRITES the issue's summary and description with the repo's projection. On
# an externally-filed ("imported") issue that content is a business user's
# intake, and once overwritten it is gone -- YouTrack keeps a description edit in
# its activity stream, but this adapter does not read history and must not start
# depending on one. So the original is captured HERE, before the overwrite, and
# ANY failure to capture it stops the sequence rather than letting the overwrite
# proceed. Fail-loud here is not a style choice: a swallowed failure is data loss.
#
# Upstream: the /claire-sync-youtrack orchestrator's `preserve` step, on the UPDATE path
#   only -- the create path has no issue and therefore no original. `--issue` is
#   the id yt-resolve.sh recorded.
# Downstream: ONE `GET /api/issues/<id>` (the as-filed fields) and, unless the
#   gate skips, ONE `POST /api/issues/<id>/comments` -- both OBSERVED 200
#   (spec sidecar 2 I). It reads `metadata.yaml` for nothing and NEVER writes it.
# Spec: archive/BTG-176/spec.md (Script inventory -- yt-preserve.sh) ;
#   youtrack-scripts.md ; test-plan.md R-12 (BTG-063's banner gate).
#
# Contract (three channels):
#   args   : --issue <internal-or-readable-id>
#   stdout : preserved=true|skipped
#   stderr : syncyt.comment.* reported conditions
#   exit   : 0 preserved or sanctioned skip / 1 the read, the render or the post
#            failed / 2 usage / 3 transport / 4 config HALT
#
# ZERO INFERENCE. The comment is built here, in script, by substituting the
# tokens of the co-located `originalcontent_TEMPLATE.txt` -- a PURE-CONTENT
# sidecar with no directive prose for an agent to interpret. The as-filed values
# are copied VERBATIM: this is the original, so it is never reformatted,
# re-wrapped, summarized or converted. YouTrack renders both the description and
# a comment as Markdown (OBSERVED, sidecar 2 B), so what was read is what is
# posted -- there is no format conversion anywhere on this path, and the sibling
# adapter's wiki restoration has no analog here.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

YT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$YT_SCRIPT_DIR/originalcontent_TEMPLATE.txt"

# The format-invariant phrase the projection step's banner carries. Matched as a
# plain substring rather than as the whole banner line: the line around it is
# free to be re-worded, and a gate that broke on a wording change would re-post
# the preservation comment on every sync from then on.
YT_BANNER_SENTINEL='Repo-managed'

ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.comment.usage \
        "--issue requires a value, but the argument list ends there"
      ISSUE="$2"; shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.comment.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$ISSUE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.comment.usage \
  "--issue <id> is required -- this step never creates an issue, it preserves an existing one"

FIELDS_FILE=""; COMMENT_FILE=""; BODY_FILE=""
yt_preserve_cleanup() { rm -f "${FIELDS_FILE:-}" "${COMMENT_FILE:-}" "${BODY_FILE:-}" 2>/dev/null; }
trap yt_preserve_cleanup EXIT

yt_config_require
[[ -f "$TEMPLATE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.comment.template_absent \
  "the preservation template is missing: $TEMPLATE -- NOT preserving, so the sync must not proceed to overwrite the original"

# --- read the AS-FILED fields ----------------------------------------------
# The `value(name)` selector is the enum/state read form (OBSERVED, sidecar 2 D);
# a field whose value is null reads back as an empty name and renders the
# template's own missing value.
READ="/api/issues/$ISSUE?fields=id,idReadable,summary,description,customFields(name,value(name))"
if ! yt_rest GET "$READ"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "GET $READ could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- NOT preserving, so the sync must not overwrite the original"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.comment.rest_read_rejected \
    "GET $READ returned HTTP $YT_HTTP_STATUS -- the as-filed original could not be read, so the sync must not overwrite it. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi

FIELDS_FILE="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.comment.scratch_unavailable \
  "no scratch file could be staged for $ISSUE's field read -- the as-filed original could not be read, so the sync must not overwrite it"
printf '%s' "$YT_HTTP_BODY" > "$FIELDS_FILE"
if ! CURRENT_DESCRIPTION="$(jq -r 'if type == "object" then (.description // "") else error("not an object") end' \
      "$FIELDS_FILE" 2>/dev/null)"; then
  yt_halt "$YT_EXIT_FAIL" syncyt.comment.rest_read_rejected \
    "the issue read returned an unparseable body -- the as-filed original could not be read, so the sync must not overwrite it"
fi

# --- the skip gate ----------------------------------------------------------
# The banner's presence means the repo already owns this description: there is no
# original left to preserve, and posting again would add one comment per sync
# forever. The banner is written by the NEXT step, which is what makes the skip
# permanent after the first sync and an operator re-run idempotent.
if [[ "$CURRENT_DESCRIPTION" == *"$YT_BANNER_SENTINEL"* ]]; then
  yt_report syncyt.comment.skipped_repo_managed \
    "$ISSUE already carries the repo-managed banner -- there is no as-filed original to preserve, and a second comment would be added on every sync"
  yt_emit preserved skipped
  exit "$YT_EXIT_OK"
fi

# --- render the comment, entirely in script --------------------------------
COMMENT_FILE="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.comment.scratch_unavailable \
  "no scratch file could be staged for the preservation comment -- the as-filed original is still un-preserved, so the sync must not overwrite it"
if ! python3 - "$TEMPLATE" "$FIELDS_FILE" > "$COMMENT_FILE" <<'PY'
import json, sys

template_path, fields_path = sys.argv[1:3]
doc = json.load(open(fields_path, encoding='utf-8'))

def field(name):
    """The named custom field's value name, or "" when the issue does not carry
    the field at all, carries it with a null value, or carries it in a shape this
    selector cannot read. All three are the same thing to a reader of the
    preserved record -- nothing was filed there -- and each renders the
    template's own missing value rather than an empty line."""
    for f in (doc.get("customFields") or []):
        if isinstance(f, dict) and f.get("name") == name:
            value = f.get("value")
            if isinstance(value, dict):
                return value.get("name") or ""
            if isinstance(value, str):
                return value
            return ""
    return ""

tokens = {
    "issue_id":             doc.get("idReadable") or doc.get("id") or "",
    "original_summary":     doc.get("summary") or "_(no summary was filed)_",
    "original_type":        field("Type") or "_(none)_",
    "original_priority":    field("Priority") or "_(none)_",
    "original_state":       field("State") or "_(none)_",
    # VERBATIM: no strip(), no re-wrap, no normalisation. The one substitution is
    # the missing-value rule, and it fires only on genuinely empty content.
    "original_description": doc.get("description") or "_(no description was filed)_",
}

body = open(template_path, encoding='utf-8').read()
for key, value in tokens.items():
    body = body.replace("{{%s}}" % key, value)
sys.stdout.write(body)
PY
then
  yt_halt "$YT_EXIT_FAIL" syncyt.comment.render_failed \
    "the preservation comment could not be rendered from $TEMPLATE -- NOT overwriting the original"
fi

# --- post it ----------------------------------------------------------------
# jq does the JSON encoding of arbitrary as-filed text (`--rawfile`), so nothing
# in a business user's intake -- a quote, a brace, a newline -- can break out of
# the request body, and the builder answers both wire questions before it is sent.
BODY_FILE="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.comment.scratch_unavailable \
  "no scratch file could be staged for the comment POST body -- the as-filed original is still un-preserved, so the sync must not overwrite it"
yt_build_body "$BODY_FILE" syncyt.comment.body_unbuildable \
  "the preservation-comment body for $ISSUE -- the as-filed original is still un-preserved, so the sync must not overwrite it" \
  -n --rawfile t "$COMMENT_FILE" '{text: $t}' \
  || exit "$YT_EXIT_FAIL"

POST="/api/issues/$ISSUE/comments"
if ! yt_rest POST "$POST" "$BODY_FILE"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "POST $POST could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the original is still un-preserved, so the sync must not overwrite it"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.comment.rest_post_rejected \
    "POST $POST returned HTTP $YT_HTTP_STATUS -- the original is still un-preserved, so the sync must not overwrite it. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi

yt_report syncyt.comment.preserved \
  "the as-filed original of $ISSUE was posted as a Markdown comment, verbatim -- the projection step may now overwrite the description"
yt_emit preserved true
exit "$YT_EXIT_OK"
