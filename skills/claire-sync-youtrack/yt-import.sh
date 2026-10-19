#!/usr/bin/env bash
#
# yt-import.sh -- seed-read an existing YouTrack issue (tracker-first intake).
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: this is an INBOUND read that
# writes NOTHING to the instance. It seeds `problem.md` for a ticket a business
# user filed directly in the tracker. Attachments are a one-time,
# non-authoritative-after ingestion (ADR_CLAIRE-0011 cl.2): the download happens at this
# single seed-read and is never re-synced.
#
# THE SIGNED URL IS A CREDENTIAL. An attachment's `url` carries a `sign=`
# parameter and was live-observed returning the file's bytes with NO
# Authorization header (spec sidecar 2 I). It therefore never reaches a log, an
# artifact or an error message: every diagnostic below names the attachment ID
# and the HTTP status, and the manifest records a disposition rather than a
# location (`syncyt.attachment.signed_url_disclosed`, Facet 7 / RISK-7). This is
# a real divergence from the sibling adapter (AC-6 divergence 7), whose manifest
# records the content
# URL because on Jira that URL is useless without a credential.
#
# The per-file size ceiling FAILS CLOSED (BTG-043): persisting an attachment is
# an irreversible git-history write, so an absent or malformed ceiling means
# reference EVERY attachment and download NONE -- never fail open to unbounded
# ingestion. That polarity is the INVERSE of the opt-out toggles and is resolved
# once, in yt-lib.sh.
#
# NO DEDICATED ACCEPTANCE-CRITERIA FIELD IS READ (AC-6 divergence 2). This
# instance has none -- writing an unknown custom-field name answers HTTP 500
# (OBSERVED, sidecar 2 D) -- so acceptance criteria are an outbound,
# description-only concern and are never seeded back from a tracker field.
#
# Upstream: /claire-triage, through the orchestrator's `import` target.
# Downstream: `GET /api/issues/<id>` (the seed fields), `GET
#   /api/issues/<id>/attachments` (the list) and, when the ceiling permits, one
#   download per attachment into `specs/<ticket>/attachments/`.
# Spec: archive/BTG-176/spec.md (Script inventory -- yt-import.sh) ;
#   youtrack-scripts.md.
#
# Contract (three channels):
#   args   : --issue <KEY-N> [--ticket <id>]   (--ticket sets the attachment dir;
#            without it NOTHING is downloaded, because there is nowhere the
#            caller has claimed to put it)
#   stdout : issue_readable=  issue_id=  seed_dir=  summary_file=
#            description_file=  manifest_file=  attachments_downloaded=
#            attachments_referenced=  type_hint=
#            (the seed files live INSIDE seed_dir; the caller removes that ONE
#             directory once it has written problem.md -- one owner, one unlink)
#   stderr : syncyt.import.* reported conditions
#   exit   : 0 ok / 1 rejected / 2 usage / 3 transport / 4 config HALT
#
# This script never writes `metadata.yaml`.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

ISSUE=""; TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue|--ticket)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.import.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --issue)  ISSUE="$2" ;;
        --ticket) TICKET="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.import.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$ISSUE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.import.usage "--issue <id> is required"

SEED_DIR=""; SEED_KEEP=0
yt_import_cleanup() {
  # A FAILED import unlinks its own seed directory: only a successful one leaves
  # anything behind, so the caller's ownership starts exactly where this script's
  # ends. Otherwise a halted run litters $TMPDIR with half-written seeds nobody
  # owns.
  [[ "$SEED_KEEP" -eq 1 ]] && return 0
  [[ -n "$SEED_DIR" ]] && rm -rf "$SEED_DIR"
  return 0
}
trap yt_import_cleanup EXIT

yt_config_require

# --- the seed fields, read once --------------------------------------------
READ="/api/issues/$ISSUE?fields=id,idReadable,summary,description,customFields(name,value(name))"
if ! yt_rest GET "$READ"; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "GET $READ could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- nothing seeded"
fi
if ! yt_http_ok; then
  yt_halt "$YT_EXIT_FAIL" syncyt.import.rest_read_rejected \
    "GET $READ returned HTTP $YT_HTTP_STATUS -- nothing seeded. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi
ISSUE_JSON="$YT_HTTP_BODY"
ISSUE_READABLE="$(printf '%s' "$ISSUE_JSON" | jq -r '.idReadable // empty' 2>/dev/null)" || ISSUE_READABLE=""
ISSUE_ID="$(printf '%s' "$ISSUE_JSON" | jq -r '.id // empty' 2>/dev/null)" || ISSUE_ID=""
[[ -n "$ISSUE_READABLE" ]] || yt_halt "$YT_EXIT_FAIL" syncyt.import.rest_read_rejected \
  "the issue read returned no readable id -- refusing to seed a ticket from a body this adapter cannot identify"

SEED_DIR="$(mktemp -d)" || yt_halt "$YT_EXIT_FAIL" syncyt.import.scratch_unavailable \
  "no seed directory could be staged -- nothing seeded"
SEED_FILE="$SEED_DIR/summary.txt"
DESC_FILE="$SEED_DIR/description.md"
MANIFEST_FILE="$SEED_DIR/attachment-manifest.tsv"
printf '%s\n' "$(printf '%s' "$ISSUE_JSON" | jq -r '.summary // ""' 2>/dev/null)" > "$SEED_FILE"
printf '%s' "$(printf '%s' "$ISSUE_JSON" | jq -r '.description // ""' 2>/dev/null)" > "$DESC_FILE"
: > "$MANIFEST_FILE"

# --- the reverse `type:` HINT (seed only -- NON-AUTHORITATIVE) --------------
# Import is a one-shot SEED, never an authority: /claire-triage classifies, and the repo
# `type:` wins on the next forward sync. So a hint is emitted ONLY where the
# forward mapping has a UNIQUE 1:1 inverse, COMPUTED from the config's own
# issue_type_map rather than restated as a second table that could drift. On the
# shipped map that leaves the two values with a two-element preimage unhinted --
# guessing between them would mislabel security work as an ordinary defect.
INSTANCE_TYPE="$(printf '%s' "$ISSUE_JSON" \
  | jq -r '((.customFields // []) | map(select(.name == "Type")) | .[0].value.name) // ""' 2>/dev/null)"
TYPE_HINT="$(jq -r --arg t "$INSTANCE_TYPE" '
    [ (.issue_type_map // {}) | to_entries[] | select(.value == $t) | .key ]
    | if length == 1 then .[0] else empty end' "$(yt_config_path)" 2>/dev/null)" || TYPE_HINT=""
[[ -n "$TYPE_HINT" ]] || yt_report syncyt.import.no_reverse_map \
  "the instance Type '${INSTANCE_TYPE:-(none)}' has no unique reverse mapping in issue_type_map -- /claire-triage must classify; the imported ticket is left UNTYPED and no type: is written from this import"

# --- attachments ------------------------------------------------------------
# The resolver PRINTS the polarity and always returns 0 -- the verdict is the
# word, not the exit status, and reading it as a status would make every run look
# like it had a usable ceiling. `enabled` is the only value that means one is
# configured; `fail-closed` is what an absent, malformed or non-positive ceiling
# resolves to, and it is announced by the resolver itself.
CEILING_MIB=""
if [[ "$(yt_config_toggle attachment_size_ceiling_mib)" == "enabled" ]]; then
  CEILING_MIB="$(yt_config_get '.attachment_size_ceiling_mib')" || CEILING_MIB=""
fi
ATTACH_DIR=""
[[ -n "$TICKET" ]] && ATTACH_DIR="${CLAIRE_REPO_ROOT:-.}/specs/$TICKET/attachments"

DOWNLOADED=0; REFERENCED=0
# `$top=-1` is UNBOUNDED ON PURPOSE (youtrack-scripts.md §4). Every attachment
# must be either downloaded or recorded with a disposition; one that fell off a
# truncated page would be neither, and its absence from the seed would look
# exactly like an issue that had no attachments.
if ! yt_rest GET "/api/issues/$ISSUE/attachments?fields=id,name,size,url,mimeType&\$top=-1"; then
  yt_report syncyt.import.attachments_unreadable \
    "the attachment list for $ISSUE_READABLE could not be reached${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the seed carries none, and their absence is reported rather than inferred"
elif ! yt_http_ok; then
  yt_report syncyt.import.attachments_unreadable \
    "the attachment list for $ISSUE_READABLE returned HTTP $YT_HTTP_STATUS -- the seed carries none, and their absence is reported rather than inferred"
else
  ATTACH_JSON="$YT_HTTP_BODY"
  # EVERY column before the last is NEVER empty: tab is an IFS *whitespace*
  # character, so bash collapses a run of them and one empty middle column
  # silently shifts every field after it to the left -- which is how a size ends
  # up in a mime column and a fail-closed guard becomes dead code.
  while IFS=$'\t' read -r a_id a_name a_size a_mime a_url; do
    [[ -n "${a_name:-}" ]] || continue
    [[ "$a_id" == "unknown" ]] && a_id=""
    a_base="$(basename -- "$a_name")"
    # An id-less record joins the fail-closed branch: without the id there is no
    # collision-free name to give it.
    if [[ -z "$CEILING_MIB" || -z "$ATTACH_DIR" || -z "$a_id" ]] \
       || [[ ! "$a_size" =~ ^[0-9]+$ ]] || (( a_size > CEILING_MIB * 1024 * 1024 )); then
      yt_report syncyt.import.attachment_referenced \
        "attachment $a_id ($a_base, ${a_size} bytes) is referenced, not downloaded -- outside the configured ceiling, or there is no ceiling and no directory to put it in. Its url is a signed credential and is deliberately not recorded anywhere"
      printf '%s\t%s\t%s\t%s\t%s\n' "$ISSUE_READABLE" "$a_id" "$a_base" "$a_size" "referenced" >> "$MANIFEST_FILE"
      REFERENCED=$((REFERENCED + 1))
      continue
    fi
    mkdir -p "$ATTACH_DIR"
    # COLLISION-FREE NAMING (BTG-043): {attachmentId}-{sanitizedFilename}. This
    # instance permits several attachments with the SAME filename on one issue
    # (OBSERVED: the same name uploaded twice returned two distinct ids), so a
    # bare basename makes the second download overwrite the first -- an
    # irreversible loss reported as two successful downloads.
    a_dest="$ATTACH_DIR/${a_id}-${a_base}"
    if ! yt_rest_download "$a_url" "$a_dest"; then
      rm -f "$a_dest"
      yt_report syncyt.import.attachment_download_failed \
        "attachment $a_id ($a_base) could not be downloaded (HTTP ${YT_HTTP_STATUS:-transport}) -- referenced instead. The url is a signed credential and is not reproduced here; use the id above"
      printf '%s\t%s\t%s\t%s\t%s\n' "$ISSUE_READABLE" "$a_id" "$a_base" "$a_size" "failed" >> "$MANIFEST_FILE"
      REFERENCED=$((REFERENCED + 1))
      continue
    fi
    # Verify what actually landed. Persisting an attachment is an IRREVERSIBLE
    # git-history write, so a short or truncated transfer is never reported as a
    # success: the partial file is removed and the attachment falls back to a
    # reference -- the same fail-closed direction the ceiling takes.
    a_written="$(wc -c < "$a_dest" | tr -d '[:space:]')"
    if [[ "$a_written" != "$a_size" ]]; then
      rm -f "$a_dest"
      yt_report syncyt.import.attachment_corrupt \
        "attachment $a_id ($a_base): the instance declared $a_size byte(s) and $a_written landed -- removing the partial file and referencing instead; never persisting a corrupt artifact"
      printf '%s\t%s\t%s\t%s\t%s\n' "$ISSUE_READABLE" "$a_id" "$a_base" "$a_size" "failed" >> "$MANIFEST_FILE"
      REFERENCED=$((REFERENCED + 1))
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$ISSUE_READABLE" "$a_id" "$a_base" "$a_size" "path:$a_dest" >> "$MANIFEST_FILE"
    DOWNLOADED=$((DOWNLOADED + 1))
  done < <(printf '%s' "$ATTACH_JSON" \
           | jq -r 'if type=="array" then .[] else empty end
                    | [((.id // "" | tostring) | if length == 0 then "unknown" else . end),
                       ((.name // "") | if length == 0 then "unknown" else . end),
                       (.size // 0),
                       ((.mimeType // "") | if length == 0 then "unknown" else . end),
                       (.url // "")]
                    | @tsv' 2>/dev/null)
fi

SEED_KEEP=1                       # the import succeeded: the caller owns the dir now
yt_emit issue_readable "$ISSUE_READABLE"
yt_emit issue_id "$ISSUE_ID"
yt_emit seed_dir "$SEED_DIR"
yt_emit summary_file "$SEED_FILE"
yt_emit description_file "$DESC_FILE"
yt_emit manifest_file "$MANIFEST_FILE"
yt_emit attachments_downloaded "$DOWNLOADED"
yt_emit attachments_referenced "$REFERENCED"
yt_emit type_hint "$TYPE_HINT"
exit "$YT_EXIT_OK"
