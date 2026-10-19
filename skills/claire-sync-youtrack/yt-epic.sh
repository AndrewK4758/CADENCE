#!/usr/bin/env bash
#
# yt-epic.sh -- project the ticket's epic parent as ONE type-agnostic link.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary, OBSERVED live against v2026.1
# build 13162 (spec sidecar 2 E): the `Subtask` link type (id `140-3`,
# `parent for` / `subtask of`) carries NO per-Type restriction, so ANY issue may
# parent ANY issue -- including an Epic parenting an Epic (BTG-059 AC-4a, live
# 2026-07-16, carried forward and labelled as carried-forward rather than
# re-verified this session). `readOnly: true` on the link TYPE constrains editing
# the type definition, not creating links of it.
#
# THIS IS THE ADAPTER'S SHARPEST DIVERGENCE FROM ITS SIBLING, and it is a
# divergence by ABSENCE, which is the kind nobody notices. /claire-sync-jira
# carries a whole umbrella-replacement flow -- create a replacement issue at the
# configured plain type, move the children's ordered links onto it, close the
# superseded original -- because Jira forbids an Epic to hold an Epic Link. Here
# the equivalent is one link and nothing else: NO re-type, NO Move, NO flatten,
# NO replacement issue. Nothing below writes a field on either issue.
#
# Upstream: the /claire-sync-youtrack orchestrator's `epic` step (best-effort), after
#   the links step -- `--issue` is the write step's own internal id.
# Downstream: ONE `GET /api/issues/<parent>` (does the parent exist yet), ONE
#   `POST /api/issues/<child>/links/<type><dir>/issues`, and ONE read-back GET.
#   It READS `metadata.yaml` -- both this ticket's and its parent's -- and NEVER
#   writes either.
# Spec: archive/BTG-176/spec.md (Script inventory -- yt-epic.sh; AC-6 divergence 1)
#   ; youtrack-scripts.md ; test-plan.md R-10.
#
# Contract (three channels):
#   args   : --ticket <id> --issue <internal-id>
#   stdout : epic_result=applied|skipped|rejected|none
#   stderr : syncyt.epic.* reported conditions
#   exit   : 0, EXCEPT a usage (2) or config (4) failure, and EXCEPT owned data
#            that cannot be read at all (1, from the shared loader's own HALT).
#            The last is deliberate and is not a sanctioned refusal: a
#            `decomposed_from` naming a ticket whose metadata.yaml is unparseable
#            is broken owned data, and this adapter never proceeds past that.
#
# ADDITIVE-ONLY, EXISTING ISSUES ONLY. A parent that has never been projected --
# no recorded `youtrack_url`, or an issue the instance answers 404 for -- is
# SKIPPED with an audit line. It is never created here: the parent is a ticket in
# its own right and creating a stub for it would put an issue in the project that
# no ticket asked for.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

TICKET=""; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--issue)
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.epic.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket) TICKET="$2" ;;
        --issue)  ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.epic.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.epic.usage "--ticket <id> is required"
[[ -n "$ISSUE" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.epic.usage \
  "--issue <internal-id> is required -- this step never creates an issue"

yt_config_require

# --- is there a parent at all? ---------------------------------------------
yt_metadata_load "$TICKET"
PARENT="$(yt_metadata_get '.decomposed_from')"
if [[ -z "$PARENT" ]]; then
  yt_report syncyt.epic.no_parent \
    "$TICKET declares no decomposed_from -- there is no parent relationship to project, and no request is issued"
  yt_emit epic_result none
  exit "$YT_EXIT_OK"
fi

# --- where does the parent live in YouTrack? -------------------------------
# The parent's OWN recorded `youtrack_url` is the only ticket-to-issue mapping
# this adapter has (yt-resolve.sh performs no recovery search: a non-existent
# readable key answers 400 invalid_query and an unknown field name answers 200
# with an empty array, so a search fallback would be a guess). A parent that has
# never been synced therefore cannot be linked yet -- and that is a skip, not a
# failure: the next sync of the parent records its url, and the run after that
# creates the link.
if ! yt_metadata_path "$PARENT" >/dev/null; then
  yt_report syncyt.epic.parent_unresolved \
    "$TICKET's decomposed_from names '$PARENT', for which there is no specs/ or archive/ metadata.yaml -- SKIPPED, never fabricated"
  yt_emit epic_result skipped
  exit "$YT_EXIT_OK"
fi
yt_metadata_load "$PARENT"
PARENT_URL="$(yt_metadata_get '.youtrack_url')"
if [[ -z "$PARENT_URL" ]]; then
  yt_report syncyt.epic.parent_unresolved \
    "$TICKET's parent '$PARENT' has no recorded youtrack_url, so it has never been projected to this instance -- SKIPPED with no request; sync '$PARENT' first and this link lands on the next run"
  yt_emit epic_result skipped
  exit "$YT_EXIT_OK"
fi
PARENT_KEY="${PARENT_URL##*/}"
if [[ -z "$PARENT_KEY" || "$PARENT_KEY" == "$PARENT_URL" && "$PARENT_URL" != */* ]]; then
  yt_report syncyt.epic.parent_unresolved \
    "$TICKET's parent '$PARENT' records youtrack_url='$PARENT_URL', which does not end in an issue id -- refusing to guess which issue it names; SKIPPED"
  yt_emit epic_result skipped
  exit "$YT_EXIT_OK"
fi

# --- does that issue still exist? ------------------------------------------
# Asked before the link is attempted, because the link body's `id` key needs the
# parent's INTERNAL id anyway: a readable id there is rejected 400 with a message
# quoting back only its alphabetic prefix, which names nothing an operator could
# act on (OBSERVED, sidecar 2 E).
if ! yt_rest GET "/api/issues/$PARENT_KEY?fields=id,idReadable"; then
  yt_report syncyt.transport.rest_unreachable \
    "GET /api/issues/$PARENT_KEY could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the parent link for $TICKET is unmade; this step is best-effort, the sequence continues"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
if ! yt_http_ok; then
  yt_report syncyt.epic.parent_unresolved \
    "$TICKET's parent '$PARENT' ($PARENT_KEY) answered HTTP $YT_HTTP_STATUS -- SKIPPED with an audit line rather than fabricated; this step is additive-only over issues that already exist"
  yt_emit epic_result skipped
  exit "$YT_EXIT_OK"
fi
PARENT_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)"
if [[ -z "$PARENT_ID" ]]; then
  yt_report syncyt.epic.parent_unresolved \
    "$TICKET's parent '$PARENT' ($PARENT_KEY) answered HTTP $YT_HTTP_STATUS with no internal id -- SKIPPED; the link body's 'id' key requires the internal id"
  yt_emit epic_result skipped
  exit "$YT_EXIT_OK"
fi

# --- the link type, direction and labels -- all from the config ------------
REL_ROW="$(yt_config_get '(.link_relations["decomposed_from"] // empty) | [(.type // ""), (.link_id // ""), ((.directed // false) | tostring), (.direction // ""), (.outward // ""), (.inward // "")] | @tsv')" \
  || yt_halt "$YT_EXIT_CONFIG" syncyt.config.marker_unresolved \
    "no 'link_relations.decomposed_from' entry in $(yt_config_path) -- refusing to guess a link type for a parent relationship, because guessing here projects the hierarchy as an undirected 'relates to' and reports success"
IFS=$'\t' read -r L_TYPE L_ID L_DIRECTED L_DIR L_OUT L_IN <<<"$REL_ROW"
[[ -n "$L_ID" && -n "$L_DIR" ]] \
  || yt_halt "$YT_EXIT_CONFIG" syncyt.config.marker_unresolved \
    "the 'link_relations.decomposed_from' entry in $(yt_config_path) declares no link id and/or no direction -- half a mapping is not a mapping"

# --- create it --------------------------------------------------------------
BODY="$(mktemp)" || { yt_report syncyt.epic.scratch_unavailable \
  "no scratch file for the parent-link body -- issuing no request; this step is best-effort, the sequence continues"
  yt_emit epic_result rejected; exit "$YT_EXIT_OK"; }
trap 'rm -f "$BODY"' EXIT
if ! yt_build_body "$BODY" syncyt.epic.body_unbuilt \
      "the parent-link body for $TICKET -> $PARENT" -n --arg id "$PARENT_ID" '{id: $id}'; then
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
LINK_PATH="/api/issues/$ISSUE/links/${L_ID}${L_DIR}/issues"
if ! yt_rest POST "$LINK_PATH" "$BODY"; then
  yt_report syncyt.transport.rest_unreachable \
    "POST $LINK_PATH could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR} -- the parent link for $TICKET is unmade; the sequence continues"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
if ! yt_http_ok; then
  yt_report syncyt.epic.link_rejected \
    "the instance rejected the $L_TYPE parent link $PARENT ($PARENT_ID) -> $TICKET ($ISSUE) with HTTP $YT_HTTP_STATUS: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi

# --- the direction is CONFIRMED, never inferred from the create's 200 -------
# On this instance the SLOT ID IS THE DIRECTION: a directed type reads back under
# `<id>s` as OUTWARD and `<id>t` as INWARD, and every slot the project defines
# comes back including the empty ones -- so the assertion is the parent's
# presence in the slot the mapping INTENDS, and a link that landed the other way
# round (this ticket parenting its own epic) appears under the other slot and is
# caught here.
#
# `$top=-1` is UNBOUNDED ON PURPOSE, for the same reason as yt-link.sh's own
# read-back and on the same ruling (youtrack-scripts.md §4): this read causes no
# write, so truncating it could only produce a false `direction_unverified` for a
# parent link that landed correctly.
SLOT="${L_ID}${L_DIR}"
[[ "$L_DIRECTED" == "true" ]] || SLOT="$L_ID"
if ! yt_rest GET "/api/issues/$ISSUE/links?fields=id,direction,linkType(id,name,sourceToTarget,targetToSource),issues(id,idReadable)&\$top=-1"; then
  yt_report syncyt.epic.direction_unverified \
    "the post-create read-back of $ISSUE's links could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}, so the direction of the parent link is UNVERIFIED"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
if ! yt_http_ok; then
  yt_report syncyt.epic.direction_unverified \
    "the post-create read-back of $ISSUE's links returned HTTP $YT_HTTP_STATUS, so the direction of the parent link is UNVERIFIED -- never inferred from the create's own 200"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
OBSERVED="$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg s "$SLOT" --arg t "$PARENT_ID" '
    if type == "array" then
      (map(select(.id == $s and ((.issues // []) | map(.id) | index($t)) != null))
       | .[0] // empty
       | [.direction, (.linkType.sourceToTarget // ""), (.linkType.targetToSource // "")] | @tsv)
    else empty end' 2>/dev/null)"
if [[ -z "$OBSERVED" ]]; then
  yt_report syncyt.epic.direction_unverified \
    "the read-back of $ISSUE shows no '$SLOT' slot carrying the parent $PARENT_ID, so the parent relationship is NOT confirmed -- the slots that DO carry it are [$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg t "$PARENT_ID" 'if type=="array" then (map(select(((.issues // []) | map(.id) | index($t)) != null)) | map("\(.id)=\(.direction)") | join(" ")) else "" end' 2>/dev/null)] -- and on this instance the slot id IS the direction, so a link under the other slot means this ticket was made the PARENT of its own epic"
  yt_emit epic_result rejected
  exit "$YT_EXIT_OK"
fi
IFS=$'\t' read -r O_DIR O_OUT O_IN <<<"$OBSERVED"
if [[ "$L_OUT|$L_IN" != "|" && "$L_OUT|$L_IN" != "$O_OUT|$O_IN" ]]; then
  yt_report syncyt.epic.type_labels_drifted \
    "the 'decomposed_from' mapping records the labels '$L_OUT'/'$L_IN' but the instance reports '$O_OUT'/'$O_IN' for the link type it landed on -- the link exists and its direction is confirmed, but the config's description of what the relation MEANS no longer matches the instance"
fi

# The branch-recording line BTG-059 asked for: an epic parenting an epic without
# a flatten is the behaviour that is easy to lose and impossible to see in a
# green suite, so the run says out loud that it took it.
yt_report syncyt.epic.parent_link \
  "$PARENT ($PARENT_ID) is now '$O_OUT' $TICKET ($ISSUE) through a type-agnostic $L_TYPE link, direction confirmed by read-back -- no re-type, no Move, no flatten; on this instance an epic may parent another epic directly"
yt_emit epic_result applied
exit "$YT_EXIT_OK"
