#!/usr/bin/env bash
#
# jira-desc-lib.sh -- the pre-write live-description DELTA GUARD (BTG-205).
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: the update path replaces
# `description` WHOLESALE. So a re-projection is not merely an update -- it is a
# destructive one, and when the fresh render is worse than what is already live
# it replaces better content with worse, successfully, with no error and a 2xx.
# That is the hazard problem.md §3 reports, observed on a re-sync whose source
# `problem.md` had not changed at all.
#
# Upstream: sourced by `jira-write-issue.sh` and called from exactly one site on
#   the update path. Downstream: at most ONE
#   `GET /rest/api/2/issue/{key}?fields=description`.
# Spec: archive/BTG-205/spec.md (AC-6) ; decisions.md DEC-005 ;
#   .agents/skills/cadence-sync-jira/jira-server-conditions-render.md.
#
# It is SOURCED -- not an entry point, and it runs nothing on load. It lives here
# rather than inline in `jira-write-issue.sh` for the reason `jira-type-lib.sh`
# and `jira-screen-lib.sh` already live in their own files: that script has a few
# lines of headroom under the agentic-DX file measure, and the guard body does
# not fit in them.
#
# WHY IT REPORTS RATHER THAN BLOCKS (DEC-005, and this is the one place the
# repo's Data-Integrity-over-Backwards-Compatibility precedence is genuinely
# tested). Blocking would halt every legitimate description update, and would
# turn the first post-upgrade sync of EVERY pre-existing issue into a halt -- a
# breaking change to a Stable surface. The integrity guarantee is obtained
# structurally instead: `jira-md2wiki.sh` is a total function of its input, so a
# re-render of an unchanged source is byte-identical and this guard stays silent.
# That removes the defect class rather than reporting on it; what the report adds
# is that an overwrite can no longer happen INVISIBLY.

# js_description_delta_check <ticket> <issue-key> <description-file> [<live-issue-json>]
#
# Compares the fresh render against the issue's live `description`. NEVER halts:
# every path returns 0 and the caller's PUT proceeds unchanged, byte for byte.
# Reuses <live-issue-json> when non-empty; issues at most ONE GET when it is
# empty. Reports exactly one of:
#   syncjs.description.reprojection_delta      (they differ; counts both ways)
#   syncjs.description.live_read_unavailable   (no comparison was possible)
#   (silence)                                  (byte-identical -- nothing to say)
#
# A failed read is NEVER conflated with "no delta". That distinction is
# PROD_CADENCE-006's lesson applied one field over: an unreadable value and an
# absent one are different facts, and collapsing them is how a projection gap
# becomes invisible.
#
# <live-issue-json> IS A PROVENANCE ARGUMENT, not merely a cache. There are TWO
# writers of the caller's live-issue variable, not one: the estimate prerequisite
# reads a field LIST that includes `description`, while the issue-type guard reads
# `?fields=issuetype` ALONE and stores its answer in the same variable. Handed the
# latter, this would read a field that was never REQUESTED as one that is ABSENT,
# and report a delta on every ordinary update -- a false alarm on exactly the path
# this guard has to stay credible on. So the caller passes the body only when the
# read that asked for `description` is the one that fetched it, and a body that
# arrives here is trusted whole: an absent or null `description` in it is then a
# real state (a create-then-update race leaves one), and it is a DELTA rather than
# an unreadable value. Testing the body's own shape instead would re-create the
# very conflation this note is about, one level down.
js_description_delta_check() {
  local ticket="$1" key="$2" file="$3" live_json="${4:-}"
  local live fresh added removed

  # PRECONDITIONS, owned here rather than at the call site. The guard runs only on
  # the UPDATE path, only for a non-epic, and only when a description will
  # actually be sent: an epic sends none (BTG-040) and a screen-suppressed
  # description leaves the live value untouched, so on either path there is no
  # overwrite to warn about and the read would be pure cost (PROD_CADENCE-021's
  # lesson -- a guard must not fire where the field is never sent).
  [[ "$MODE" == "update" && "$IS_EPIC" != "yes" ]] || return 0
  [[ "$SEND_DESC" == "yes" && -n "$file" ]]        || return 0

  if [[ -z "$live_json" ]]; then
    if ! js_rest GET "/rest/api/2/issue/$key?fields=description"; then
      js_report syncjs.description.live_read_unavailable \
        "could not reach the instance to read $key's live description -- NO comparison was made for $ticket; the projection proceeds and overwrites it unseen"
      return 0
    fi
    if ! js_http_ok; then
      js_report syncjs.description.live_read_unavailable \
        "GET /rest/api/2/issue/$key?fields=description returned HTTP $JS_HTTP_STATUS -- NO comparison was made for $ticket; the projection proceeds and overwrites it unseen"
      return 0
    fi
    live_json="$JS_HTTP_BODY"
  fi

  # `// ""` folds an ABSENT or null description to the empty string deliberately:
  # that is a real state (a create-then-update race leaves one), and it is a
  # DELTA, not an unreadable value. Only a failed exchange is unreadable.
  if ! live="$(printf '%s' "$live_json" | jq -r '.fields.description // ""' 2>/dev/null)"; then
    js_report syncjs.description.live_read_unavailable \
      "$key's live description could not be parsed out of the issue body -- NO comparison was made for $ticket; the projection proceeds and overwrites it unseen"
    return 0
  fi

  fresh="$(cat "$file" 2>/dev/null)" || return 0
  [[ "$live" == "$fresh" ]] && return 0

  # Counts in EACH direction, never one number. "They differ" tells an operator
  # nothing about whether the projection is adding detail or destroying it.
  added="$(diff <(printf '%s\n' "$live") <(printf '%s\n' "$fresh") 2>/dev/null | grep -c '^>' || true)"
  removed="$(diff <(printf '%s\n' "$live") <(printf '%s\n' "$fresh") 2>/dev/null | grep -c '^<' || true)"
  js_report syncjs.description.reprojection_delta \
    "$ticket: the fresh render differs from $key's live description -- ${added:-0} line(s) added, ${removed:-0} line(s) removed. The PUT proceeds and REPLACES the live value wholesale. If the source artifacts did not change, re-read the rendered output before accepting it; the description content itself is deliberately not logged"
  return 0
}
