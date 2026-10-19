#!/usr/bin/env bash
#
# jira-import.sh -- seed-read an existing Jira issue (ticket-first intake).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: this is an INBOUND read that
# writes NOTHING to Jira. It seeds `problem.md` for a ticket a business user filed
# directly in the tracker. Attachments are a one-time, non-authoritative-after
# ingestion (ADR_CADENCE-0011 cl.2): the download happens at this single seed-read and is
# never re-synced.
#
# The per-file size ceiling FAILS CLOSED (BTG-043): because persisting an
# attachment is an irreversible git-history write, an absent or malformed ceiling
# means reference EVERY attachment by URL and download NONE -- never fail open to
# unbounded ingestion. That polarity is the INVERSE of the opt-out toggles and is
# resolved once, in jira-lib.sh.
#
# Upstream: /cadence-triage, via the orchestrator.
# Downstream: `GET $JIRA_BASE_URL/rest/api/2/issue/{key}` plus, when the ceiling
#   permits, `GET` of each attachment's content URL into `specs/{id}/attachments/`.
# Spec: archive/BTG-075/spec.md (script inventory) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --issue-key <KEY> [--ticket <id>]   (--ticket sets the attachment dir)
#   stdout : issue_key=  seed_dir=  summary_file=  ac_items_file=  manifest_file=
#            attachments_downloaded=  attachments_referenced=  type_hint=
#            (the seed files live INSIDE seed_dir; the caller removes that ONE
#             directory when it has written problem.md -- AC-4's temp-file
#             discipline, one owner and one unlink)
#   stderr : syncjs.import.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# This script never writes `metadata.yaml` (AC-6); the caller seeds problem.md
# from the files whose paths it returns.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

ISSUE_KEY=""
TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-key) js_argv_pair syncjs.import.usage "$@"; ISSUE_KEY="$2"; shift 2 ;;
    --ticket)    js_argv_pair syncjs.import.usage "$@"; TICKET="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.import.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$ISSUE_KEY" ]] || js_halt "$JS_EXIT_USAGE" syncjs.import.usage "--issue-key <KEY> is required"

js_config_require
BASE_URL="$(js_env_value base_url)"
[[ -n "$BASE_URL" ]] || js_halt "$JS_EXIT_USAGE" syncjs.import.env_absent "the base-URL environment variable is unset"

# the core seed fields, read once
if ! js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=summary,description,issuetype,priority,attachment,labels"; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "GET /rest/api/2/issue/$ISSUE_KEY could not reach ${BASE_URL%/}"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.import.rejected \
    "GET /rest/api/2/issue/$ISSUE_KEY returned HTTP $JS_HTTP_STATUS -- nothing seeded"
fi
if ! printf '%s' "$JS_HTTP_BODY" | jq -e 'type == "object"' >/dev/null 2>&1; then
  js_halt "$JS_EXIT_FAIL" syncjs.import.rejected \
    "the issue read returned an unparseable body -- nothing seeded (never parsed around)"
fi
ISSUE_JSON="$JS_HTTP_BODY"

# ONE temp directory, so the caller has exactly ONE thing to remove (AC-4). Every
# failure path below unlinks it before exiting, so a failed import leaves nothing
# behind at all; only a SUCCESSFUL import hands the directory to the caller.
SEED_DIR="$(mktemp -d 2>/dev/null)" || js_halt "$JS_EXIT_FAIL" syncjs.import.scratch_unavailable "no scratch directory could be staged for the import seed -- nothing seeded; a partial seed is indistinguishable from a complete one to the caller"
js_seed_cleanup() { [[ -n "${SEED_KEEP:-}" ]] || rm -rf "$SEED_DIR"; }
trap js_seed_cleanup EXIT
SEED_FILE="$SEED_DIR/summary.txt"
printf '%s' "$ISSUE_JSON" | jq -r '
  "Summary: " + (.fields.summary // "") + "\n\n" +
  (.fields.description // "") + "\n\nJira issue type: " +
  ((.fields.issuetype.name) // "(none)")' > "$SEED_FILE"

# --- acceptance criteria (BTG-046, read side) -------------------------------
AC_FILE="$SEED_DIR/acceptance-criteria.txt"
: > "$AC_FILE"
# The exit code is captured, never collapsed (see jira-write-issue.sh): a
# non-boolean toggle is a config HALT, not a request to skip the AC seed.
js_config_toggle acceptance_criteria_sync_enabled
AC_TOGGLE_RC=$?
if [[ "$AC_TOGGLE_RC" -eq "$JS_EXIT_CONFIG" ]]; then exit "$JS_EXIT_CONFIG"; fi
if [[ "$AC_TOGGLE_RC" -eq 0 ]]; then
  # The dedicated "Acceptance Criteria" field is discovered by EXACT name; an
  # ambiguous match is skipped, never guessed. Its id is folded into the SAME
  # seed read (no second round-trip), and items render as unchecked `- [ ] `
  # checklist lines into the seed file the caller writes problem.md from.
  AC_FIELD_NAME="$(js_config_map acceptance_criteria field_name)" || AC_FIELD_NAME=""
  if [[ -z "$AC_FIELD_NAME" ]] || ! js_rest GET "/rest/api/2/field" || ! js_http_ok; then
    js_report syncjs.ac.field_discovery_failed \
      "the instance field-list read failed -- no acceptance criteria seeded; the import continues"
  else
    AC_IDS="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$AC_FIELD_NAME" \
      'if type=="array" then (.[] | select(.name == $n) | .id) else empty end' 2>/dev/null)"
    AC_COUNT="$(grep -c . <<<"$AC_IDS" || true)"
    [[ -z "$AC_IDS" ]] && AC_COUNT=0
    AC_FIELD_ID=""
    case "$AC_COUNT" in
      0) js_report syncjs.ac.field_absent "no field named exactly \"$AC_FIELD_NAME\" -- no AC seeded" ;;
      1) AC_FIELD_ID="$AC_IDS" ;;
      *) js_report syncjs.ac.field_ambiguous \
           "$AC_COUNT fields named exactly \"$AC_FIELD_NAME\" -- skipping, never guessing which" ;;
    esac
    if [[ -n "$AC_FIELD_ID" ]] \
       && js_rest GET "/rest/api/2/issue/$ISSUE_KEY?fields=$AC_FIELD_ID" && js_http_ok; then
      printf '%s' "$JS_HTTP_BODY" | jq -r --arg f "$AC_FIELD_ID" \
        '(.fields[$f] // []) | if type == "array" then (.[] | "- [ ] " + (.name // (. | tostring))) else empty end' \
        > "$AC_FILE" 2>/dev/null || : > "$AC_FILE"
      if [[ -s "$AC_FILE" ]]; then
        js_report syncjs.ac.imported "$(grep -c . "$AC_FILE" || true) acceptance-criteria item(s) seeded, all unchecked"
      else
        js_report syncjs.ac.field_empty "$AC_FIELD_ID is empty on this issue -- nothing to seed"
      fi
    fi
  fi
else
  js_report syncjs.ac.disabled "acceptance-criteria sync disabled by config -- no AC seeded"
fi

# --- attachments (BTG-043) ---------------------------------------------------
DOWNLOADED=0
REFERENCED=0
CEILING_MIB=""
if ! CEILING_MIB="$(js_config_ceiling_mib)"; then
  js_report syncjs.import.attachment_ceiling_unreadable \
    "the attachment ceiling is absent or unusable -- failing CLOSED: every attachment is referenced by URL and NONE is downloaded"
  CEILING_MIB=""
fi

ATTACH_DIR=""
if [[ -n "$TICKET" ]]; then
  ATTACH_DIR="${CADENCE_REPO_ROOT:-.}/specs/$TICKET/attachments"
fi

# --- the SUPPORTING-EVIDENCE MANIFEST (BTG-043) ------------------------------
# One line per attachment, carrying its provenance: source issue key, attachment
# id, sanitized filename, size, mimeType, and its DISPOSITION -- `path:` (stored),
# `url:` (over-ceiling or ceiling-unreadable, referenced) or `failed:` (the fetch
# did not land, referenced with a visible note). `/cadence-triage` renders EXACTLY ONE
# `## Supporting Evidence` bullet per line into problem.md, and still promises
# that in `artifacts/commands/cadence-triage.md`.
#
# It is a FILE, not stdout: stdout carries `key=value` result lines only
# (DEC-001), so the manifest travels the same way the other seed content does --
# inside SEED_DIR, with its path returned as `manifest_file=`. A failed download
# is never silently dropped; counts alone cannot tell a caller WHICH attachment
# is missing, and a referenced attachment's URL never left this script at all.
MANIFEST_FILE="$SEED_DIR/attachment-manifest.tsv"
: > "$MANIFEST_FILE"
manifest_line() {   # <id> <name> <size> <mimeType> <disposition>
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ISSUE_KEY" "$1" "$2" "${3:-unknown}" "${4:-unknown}" "$5" >> "$MANIFEST_FILE"
}

while IFS=$'\t' read -r a_id a_name a_size a_mime a_url; do
  [[ -n "$a_name" ]] || continue
  # `unknown` is the never-empty PLACEHOLDER the jq producer below substitutes so
  # that no column can collapse. For the id it is not a value but the ABSENCE of
  # one, so it is restored to empty here and the fail-closed guard sees exactly
  # what it was written to see. The FILENAME deliberately keeps its placeholder:
  # a record still earns a manifest line, which is what tells `/cadence-triage` the
  # attachment exists at all.
  [[ "$a_id" == "unknown" ]] && a_id=""
  # the filename is reduced to its BASENAME before it ever reaches a path
  a_base="$(basename -- "$a_name")"
  # An id-less record joins the fail-closed branch rather than being downloaded
  # under a name that could collide: without the id there IS no collision-free
  # name (every real Jira attachment record carries one).
  if [[ -z "$CEILING_MIB" || -z "$ATTACH_DIR" || -z "$a_id" ]] \
     || [[ ! "$a_size" =~ ^[0-9]+$ ]] || (( a_size > CEILING_MIB * 1024 * 1024 )); then
    js_report syncjs.import.attachment_referenced "$a_base referenced by URL (not downloaded)"
    manifest_line "$a_id" "$a_base" "$a_size" "$a_mime" "url:$a_url"
    REFERENCED=$((REFERENCED + 1))
    continue
  fi
  mkdir -p "$ATTACH_DIR"
  # COLLISION-FREE NAMING (BTG-043): {attachmentId}-{sanitizedFilename}. Jira
  # permits several attachments with the same filename on one issue, so a bare
  # basename makes the second download overwrite the first -- an irreversible
  # loss of the first one's bytes, reported as two successful downloads.
  a_dest="$ATTACH_DIR/${a_id}-${a_base}"
  # The content URL is used VERBATIM (it is absolute), and the body is streamed to
  # the file by curl -- never through a shell variable, which would drop NUL bytes.
  if ! js_rest_download "$a_url" "$a_dest"; then
    rm -f "$a_dest"
    js_report syncjs.import.attachment_download_failed \
      "$a_base could not be downloaded (HTTP ${JS_HTTP_STATUS:-transport}) -- referenced by URL instead"
    manifest_line "$a_id" "$a_base" "$a_size" "$a_mime" "failed:$a_url"
    REFERENCED=$((REFERENCED + 1))
    continue
  fi
  # Verify what actually landed. Persisting an attachment is an IRREVERSIBLE
  # git-history write, so a short or truncated transfer must never be reported as a
  # success: the partial file is removed and the attachment falls back to a URL
  # reference (the same fail-closed direction the ceiling takes).
  a_written="$(wc -c < "$a_dest" | tr -d '[:space:]')"
  if [[ "$a_written" != "$a_size" ]]; then
    rm -f "$a_dest"
    js_report syncjs.import.attachment_corrupt \
      "$a_base: Jira declared $a_size byte(s) but $a_written landed -- removing the partial file and referencing by URL instead; never persisting a corrupt artifact"
    manifest_line "$a_id" "$a_base" "$a_size" "$a_mime" "failed:$a_url"
    REFERENCED=$((REFERENCED + 1))
    continue
  fi
  manifest_line "$a_id" "$a_base" "$a_size" "$a_mime" "path:$a_dest"
  DOWNLOADED=$((DOWNLOADED + 1))
done < <(printf '%s' "$ISSUE_JSON" \
         | jq -r '(.fields.attachment // [])[]
                  # EVERY column before the last is NEVER empty: tab is an IFS
                  # *whitespace* character, so bash COLLAPSES a run of them and an
                  # empty middle column silently shifts every field after it left
                  # -- here that handed the content URL to $a_mime and left the
                  # download with no URL at all, so the manifest recorded
                  # disposition `url:` with NO URL while the run reported success.
                  # `.mimeType` had this protection; `.id` and `.filename` did
                  # not, which is why `-z "$a_id"` could never be true and the
                  # fail-closed guard above was DEAD CODE.
                  | [((.id // "" | tostring) | if length == 0 then "unknown" else . end),
                     ((.filename // "") | if length == 0 then "unknown" else . end),
                     (.size // 0),
                     ((.mimeType // "") | if length == 0 then "unknown" else . end),
                     (.content // "")]
                  | @tsv' 2>/dev/null)

# --- reverse `type:` HINT (import seed only -- NON-AUTHORITATIVE) ------------
# Import is a one-shot SEED, never an authority: triage classifies, and the repo
# `type:` wins on the next forward sync. So a hint is emitted ONLY where the
# forward issue-type mapping has a UNIQUE 1:1 inverse. The inverse is COMPUTED
# from the config's own `issue_type_map` rather than restated as a second table --
# a hand-maintained copy is a second place to drift, and it is the config that an
# adopter is entitled to change.
#
# On the shipped mapping that yields Issue->documentation, Story->feature,
# Task->tech-debt, Epic->epic, and NO hint for `Bug`, whose preimage is
# {bug, security}: seeding `bug` there would risk mislabeling security work.
# Never best-guess an ambiguous type -- report and leave the ticket untyped.
JIRA_TYPE="$(printf '%s' "$ISSUE_JSON" | jq -r '.fields.issuetype.name // ""' 2>/dev/null)"
TYPE_HINT="$(jq -r --arg t "$JIRA_TYPE" '
    [ (.issue_type_map // {}) | to_entries[] | select(.value == $t) | .key ]
    | if length == 1 then .[0] else empty end' "$(js_config_path)" 2>/dev/null)"
if [[ -z "$TYPE_HINT" ]]; then
  js_report syncjs.import.no_reverse_map \
    "the Jira issue type '${JIRA_TYPE:-(none)}' has no unique reverse mapping in issue_type_map -- no reverse mapping, triage must classify; the imported ticket is left UNTYPED and no type: is written from the import"
fi

SEED_KEEP=1                       # the import succeeded: the caller owns the dir now
js_emit issue_key "$ISSUE_KEY"
js_emit seed_dir "$SEED_DIR"
js_emit summary_file "$SEED_FILE"
js_emit ac_items_file "$AC_FILE"
js_emit manifest_file "$MANIFEST_FILE"
js_emit attachments_downloaded "$DOWNLOADED"
js_emit attachments_referenced "$REFERENCED"
js_emit type_hint "$TYPE_HINT"
exit "$JS_EXIT_OK"
