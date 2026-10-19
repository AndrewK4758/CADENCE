#!/usr/bin/env bash
#
# yt-link.sh -- project the repo's declared relationships as YouTrack issue
# links: additive-only, over issues that already exist, with a post-create
# direction read-back.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: the repository is the source of
# truth for the RELATIONSHIP; YouTrack holds a projection of it. This step
# therefore only ever ADDS. It issues no DELETE, and it never reconciles the
# instance's links back down to the repo's set -- a link a human added in
# YouTrack is a human's decision, and removing it because the repo does not
# mention it would be this adapter overwriting a person.
#
# Upstream: the orchestrator's `links` step (best-effort), after the issue exists
#   and its internal id is known.
# Downstream: one GET per declared target, one POST per target that resolves, and
#   ONE read-back GET over the issue's links. It READS `metadata.yaml` (through
#   yt-meta.sh) and never writes it.
# Spec: archive/BTG-176/spec.md (Proposed Design -- Endpoint map) ;
#   archive/BTG-176/spec-2-live-rest-observations.md SS E (every shape OBSERVED).
#
# Contract (three channels):
#   args   : --ticket <id> --issue <internal-id>
#   stdout : links_created=<n>  links_skipped=<n>
#            link_result=applied|skipped|rejected
#   stderr : syncyt.link.* reported conditions
#   exit   : 0 ok / 1 rejected / 2 usage / 3 transport / 4 config HALT
#
# WHY A TARGET THAT DOES NOT RESOLVE IS A SKIP AND NOT A FAILURE. The repo
# routinely names tickets that were never projected (a related ticket in another
# repo, one filed but not yet synced). Halting the sequence for one of those
# would make an ordinary declaration block a projection; fabricating the issue
# would invent an object nobody asked for. It is skipped, and the skip is
# AUDITED by name -- silence is the only outcome that would be wrong.

set -u

YT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$YT_DIR/yt-lib.sh"
# shellcheck source=/dev/null
. "$YT_DIR/yt-link-targets.sh"

TICKET=""
ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket|--issue)
      # Guard the pair BEFORE the `shift 2` that consumes it -- see the same
      # guard in yt-resolve.sh for why an unguarded `shift 2` spins forever.
      [[ $# -ge 2 ]] || yt_halt "$YT_EXIT_USAGE" syncyt.link.usage \
        "$1 requires a value, but the argument list ends there"
      case "$1" in
        --ticket) TICKET="$2" ;;
        --issue)  ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) yt_halt "$YT_EXIT_USAGE" syncyt.link.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || yt_halt "$YT_EXIT_USAGE" syncyt.link.usage "--ticket <id> is required"
[[ -n "$ISSUE"  ]] || yt_halt "$YT_EXIT_USAGE" syncyt.link.usage "--issue <internal-id> is required"

yt_config_require

# The toggle is read BEFORE the owned data and before any request: a disabled
# step must cost nothing, and reading the ticket to then do nothing with it is
# how a "disabled" capability still fails on a file it never needed.
if [[ "$(yt_config_toggle link_creation_enabled)" != "enabled" ]]; then
  yt_report syncyt.link.disabled \
    "link_creation_enabled is disabled in $(yt_config_path) -- no link was created and no request was issued for $TICKET"
  yt_emit links_created 0
  yt_emit links_skipped 0
  yt_emit link_result skipped
  exit "$YT_EXIT_OK"
fi

yt_metadata_load "$TICKET"

# --------------------------------------------------------------------------
# The link type a relation projects onto (AC-3: resolved, never hardcoded)
# --------------------------------------------------------------------------
# yt_link_relation <declaring-key> -- one TAB-separated
# `<type> <link_id> <directed> <direction> <outward> <inward>` row for the
# relation that key projects onto, or a config HALT.
#
# A `related_tickets` SUB-KEY is a human's GROUPING LABEL as often as it is a
# relation -- the shape this repo's lineage actually produced is
# `originating: ORD-39` -- so a key the map does not declare falls back to the
# default `related_tickets` relation and SAYS SO by name. Halting the sequence
# because someone grouped their related tickets under a heading would make an
# ordinary declaration block a projection.
#
# The fallback is AUDITED, never silent, and that is the whole difference: an
# adopter whose `blocked_by:` sub-key was projected as an undirected `Relates`
# is told which key was defaulted and what to declare, rather than discovering a
# directed relation quietly flattened. If even the DEFAULT is unmapped, that is a
# broken config and it HALTS -- there is nothing left to fall back to.
yt_link_relation() {
  local key="$1" row
  row="$(yt_link_relation_row "$key")" || row=""
  if [[ -z "$row" ]]; then
    if [[ "$key" != "related_tickets" ]]; then
      yt_report syncyt.link.relation_defaulted \
        "the related_tickets sub-key '$key' names no entry under 'link_relations' in $(yt_config_path), so it is projected as the DEFAULT related_tickets relation -- declare it in link_relations if it means something directed, because the default is undirected and cannot carry an ordering"
      row="$(yt_link_relation_row related_tickets)" || row=""
    fi
  fi
  if [[ -z "$row" ]]; then
    yt_report syncyt.config.marker_unresolved \
      "no '$key' entry under 'link_relations' in $(yt_config_path), and no 'related_tickets' default to fall back to -- refusing to guess a link type, because guessing here projects a directed relation as an undirected one and reports success"
    return "$YT_EXIT_CONFIG"
  fi
  printf '%s\n' "$row"
}

# yt_link_relation_row <key> -- the raw config row for one key, or nothing.
yt_link_relation_row() {
  yt_config_get '(.link_relations[$r] // empty) | [(.type // ""), (.link_id // ""), ((.directed // false) | tostring), (.direction // ""), (.outward // ""), (.inward // "")] | @tsv' --arg r "$1"
}

# --------------------------------------------------------------------------
CREATED=0
SKIPPED=0
REJECTED=0
VERIFY=""          # `<slot-id> <expected-direction> <target-internal-id> <relation>` rows

yt_link_targets
# A refused declaration is part of the VERDICT, not just the audit stream. The
# traversal already reported each one by name; carrying the count here is what
# stops the step reporting `applied` over a relationship it dropped.
REJECTED=$((REJECTED + ${YT_LINK_TARGETS_UNREADABLE:-0}))

while IFS=' ' read -r REL TARGET; do
  [[ -n "${TARGET:-}" ]] || continue

  # (1) the target must ALREADY EXIST. Both id forms are accepted in a PATH
  # (OBSERVED), so the declared readable id goes here unchanged.
  if ! yt_rest GET "/api/issues/$TARGET?fields=id,idReadable"; then
    yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
      "GET /api/issues/$TARGET could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
  fi
  if ! yt_http_ok; then
    # 404 is the OBSERVED answer for an issue that does not exist. Any other
    # non-2xx is reported the same way and for the same reason: this step may
    # only link to an issue it has SEEN, and it will not create one.
    yt_report syncyt.link.target_unresolved \
      "the related ticket '$TARGET' (declared under '$REL') does not resolve to an issue on this instance (HTTP $YT_HTTP_STATUS) -- SKIPPED with this line rather than fabricated; no link was created for it"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  TARGET_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)"
  if [[ -z "$TARGET_ID" ]]; then
    yt_report syncyt.link.target_unresolved \
      "the related ticket '$TARGET' answered HTTP $YT_HTTP_STATUS with no internal id -- SKIPPED; the link body's 'id' key requires the internal id and a readable one there is rejected with an error naming nothing useful"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # (2) the link type, direction and expected labels -- all from the config
  if ! REL_ROW="$(yt_link_relation "$REL")"; then exit "$YT_EXIT_CONFIG"; fi
  IFS=$'\t' read -r L_TYPE L_ID L_DIRECTED L_DIR L_OUT L_IN <<<"$REL_ROW"
  if [[ -z "$L_ID" || -z "$L_DIR" ]]; then
    yt_halt "$YT_EXIT_CONFIG" syncyt.config.marker_unresolved \
      "the 'link_relations.$REL' entry in $(yt_config_path) declares no link id and/or no direction -- half a mapping is not a mapping"
  fi

  # (3) create. The body carries the INTERNAL id under the `id` key: a readable
  # id there is HTTP 400 (OBSERVED), and the message quotes back only the
  # alphabetic prefix of the readable id -- naming nothing an operator could act
  # on, which is why the internal id is resolved first rather than hoped for.
  BODY="$(mktemp)" || yt_halt "$YT_EXIT_FAIL" syncyt.link.scratch_unavailable \
    "no scratch file for the link body -- issuing no request"
  if ! yt_build_body "$BODY" syncyt.link.body_unbuilt \
        "the link body for $TARGET ($REL)" -n --arg id "$TARGET_ID" '{id: $id}'; then
    rm -f "$BODY"; REJECTED=$((REJECTED + 1)); continue
  fi
  if ! yt_rest POST "/api/issues/$ISSUE/links/${L_ID}${L_DIR}/issues" "$BODY"; then
    rm -f "$BODY"
    yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
      "POST /api/issues/$ISSUE/links/${L_ID}${L_DIR}/issues could not reach the instance${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
  fi
  rm -f "$BODY"
  if ! yt_http_ok; then
    yt_report syncyt.link.create_rejected \
      "the instance rejected the $L_TYPE link $ISSUE -> $TARGET ($TARGET_ID, declared '$REL') with HTTP $YT_HTTP_STATUS: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-160)"
    REJECTED=$((REJECTED + 1))
    continue
  fi
  CREATED=$((CREATED + 1))

  # The slot the read-back must show it in. A DIRECTED type keeps the s/t suffix
  # and reports OUTWARD/INWARD; an UNDIRECTED one is read back under the BARE
  # link id with direction BOTH, even though the create path carries a suffix
  # (OBSERVED: created at `140-0s`, read back as `140-0` / BOTH).
  if [[ "$L_DIRECTED" == "true" ]]; then
    SLOT="${L_ID}${L_DIR}"
    [[ "$L_DIR" == "s" ]] && WANT_DIR=OUTWARD || WANT_DIR=INWARD
  else
    SLOT="$L_ID"
    WANT_DIR=BOTH
  fi
  VERIFY="${VERIFY:+$VERIFY
}$SLOT $WANT_DIR $TARGET_ID $REL $L_OUT|$L_IN"
done <<<"${YT_LINK_TARGETS:-}"

# --------------------------------------------------------------------------
# The post-create read-back -- direction is CONFIRMED, never assumed (AC-6)
# --------------------------------------------------------------------------
# A 200 on the create says the request was accepted; it says nothing about which
# WAY the link landed. Direction is exactly the property a near-fit mapping
# inverts silently -- `Depend` is a mapping for the repo's `precedes`, not an
# identity (DEC-016) -- so it is read back and compared, once, for every link
# this run created.
#
# `$top=-1` returns every slot (OBSERVED), and it is UNBOUNDED ON PURPOSE --
# see youtrack-scripts.md §4, "Which reads carry page_top_bound". Nothing is
# written on the strength of this read, so a truncated page could not cause a
# duplicate; it could only report `direction_unverified` for a link that DID
# land, sending an operator to hunt a relation that is already correct.
#
# The read-back must filter on a NON-EMPTY `issues` array: the instance returns every slot the project defines,
# including the empty ones, so the presence of a slot means nothing at all.
if [[ "$CREATED" -gt 0 ]]; then
  if ! yt_rest GET "/api/issues/$ISSUE/links?fields=id,direction,linkType(id,name,sourceToTarget,targetToSource),issues(id,idReadable)&\$top=-1"; then
    yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
      "GET /api/issues/$ISSUE/links could not reach the instance for the direction read-back${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
  fi
  if ! yt_http_ok; then
    yt_report syncyt.link.direction_unverified \
      "the post-create read-back of $ISSUE's links returned HTTP $YT_HTTP_STATUS, so the direction of the $CREATED link(s) this run created is UNVERIFIED -- never inferred from the create's own 200"
    REJECTED=$((REJECTED + 1))
  else
    while IFS=' ' read -r V_SLOT V_DIR V_TARGET V_REL V_LABELS; do
      [[ -n "${V_SLOT:-}" ]] || continue
      OBSERVED="$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg s "$V_SLOT" --arg t "$V_TARGET" '
          if type == "array" then
            (map(select(.id == $s and ((.issues // []) | map(.id) | index($t)) != null))
             | .[0] // empty
             | [.direction, (.linkType.sourceToTarget // ""), (.linkType.targetToSource // "")] | @tsv)
          else empty end' 2>/dev/null)"
      if [[ -z "$OBSERVED" ]]; then
        # THE SLOT ID *IS* THE DIRECTION on this instance (OBSERVED): a directed
        # type reads back under `<id>s` as OUTWARD and `<id>t` as INWARD, and an
        # undirected one under the bare `<id>` as BOTH. So finding the target in
        # the slot the mapping INTENDS is the direction assertion, and a second
        # comparison against the `direction` string would be a branch no
        # consistent response can reach -- a link that landed the other way round
        # appears under the OTHER slot and is caught right here.
        #
        # A slot is returned even when empty, so its presence proves nothing;
        # only the target's presence in its `issues` array does.
        yt_report syncyt.link.direction_unverified \
          "the read-back of $ISSUE shows no '$V_SLOT' slot carrying $V_TARGET (declared '$V_REL'), so the direction of the link this run created is NOT confirmed -- the slots that DO carry it are [$(printf '%s' "$YT_HTTP_BODY" | jq -r --arg t "$V_TARGET" 'if type=="array" then (map(select(((.issues // []) | map(.id) | index($t)) != null)) | map("\(.id)=\(.direction)") | join(" ")) else "" end' 2>/dev/null)] -- and on this instance the slot id IS the direction"
        REJECTED=$((REJECTED + 1))
        continue
      fi
      IFS=$'\t' read -r O_DIR O_OUT O_IN <<<"$OBSERVED"
      # The instance's own labels for the type, compared against what the config
      # says the mapping means. A mismatch is CONFIG DRIFT -- the adopter's map
      # naming one relation while the instance's link type carries another -- and
      # it is reported rather than absorbed, because the projection is still
      # readable by a human who would then be reading the wrong relation.
      if [[ "$V_LABELS" != "|" && "$V_LABELS" != "$O_OUT|$O_IN" ]]; then
        yt_report syncyt.link.type_labels_drifted \
          "the '$V_REL' mapping records the labels '${V_LABELS%|*}'/'${V_LABELS#*|}' but the instance reports '$O_OUT'/'$O_IN' for the link type it landed on -- the link exists and its direction is confirmed, but the config's description of what the relation MEANS no longer matches the instance"
      fi
    done <<<"$VERIFY"
  fi
fi

yt_emit links_created "$CREATED"
yt_emit links_skipped "$SKIPPED"
if [[ "$REJECTED" -gt 0 ]]; then
  yt_emit link_result rejected
elif [[ "$CREATED" -gt 0 ]]; then
  yt_emit link_result applied
else
  yt_emit link_result skipped
fi
exit "$YT_EXIT_OK"
