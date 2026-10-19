#!/usr/bin/env bash
# Publish one draft MR for review, and prove it actually happened.
#
# SHARED FILE -- byte-identical copies live in the scripts/ dir of every
# cadence-* skill that ends by publishing an MR. Copies rather than one shared
# file because the skills are distributed separately and each has to stand alone;
# this file carries NO per-skill text, so "have they drifted?" is a checksum:
#
#   md5sum ~/.agents/skills/cadence-*/scripts/ready_mr.sh \
#     | awk '{print $1}' | sort -u | wc -l      # must print 1
#
# Fix one, propagate verbatim. Do not hand-edit a single copy.
#
# Why this is a script. Marking the MR ready is the calling skill's terminal act
# and its only externally visible effect -- the run ends immediately after,
# so nothing downstream ever notices if it silently didn't take. `gh pr ready`
# exiting 0 is not proof it took: the forge can accept the call and change
# nothing, and --undo is documented as plan-dependent, which tells you draft
# state is not uniformly writable. An MR reported ready while still sitting in
# draft is a review request nobody will ever see -- a skipped step whose skipping
# looks exactly like success. So: read, publish, then RE-READ and confirm.
#
# Idempotent on purpose. An MR that is already ready exits 0 with was_draft=no,
# because "make sure it is ready" is the caller's actual intent and a second run
# should not fail just because the first one worked.
#
# Usage:  ready_mr.sh <pr-url-or-number> [--repo R]
# Exit:   0 ready for review | 2 could not publish, or could not confirm
set -u

PR=""; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo needs a value}"; shift 2 ;;
    -*) echo "ready_mr: unknown option $1" >&2; exit 2 ;;
    *)  if [ -z "$PR" ]; then PR="$1"; shift; else
          echo "ready_mr: unexpected argument $1" >&2; exit 2; fi ;;
  esac
done

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
ERR="${TMPDIR:-/tmp}/ready_mr.err"

WAS_DRAFT="unknown"; URL=""

# One summary line on stdout, always, including every failure path -- a silent
# exit here is indistinguishable from the step never having run, and this line
# is what the caller pastes as its evidence.
finish() { # result cause
  printf 'ready_mr: pr=%s result=%s was_draft=%s url=%s cause=%s at=%s\n' \
    "${PR:-none}" "$1" "$WAS_DRAFT" "${URL:-none}" "${2:-none}" "$(stamp)"
}

[ -n "$PR" ] || { echo "ready_mr: no MR given" >&2; finish ERROR no-mr-argument; exit 2; }
command -v gh >/dev/null 2>&1 || {
  echo "ready_mr: gh not installed -- cannot ask the forge anything" >&2
  finish ERROR gh-missing; exit 2; }

VIEW_ARGS=(pr view "$PR" --json state,isDraft,url)
READY_ARGS=(pr ready "$PR")
[ -n "$REPO" ] && { VIEW_ARGS+=(--repo "$REPO"); READY_ARGS+=(--repo "$REPO"); }

read_pr() { # sets STATE, DRAFT, URL
  OUT=$(gh "${VIEW_ARGS[@]}" 2>"$ERR") || return 1
  STATE=$(printf '%s' "$OUT" | sed -n 's/.*"state":"\([A-Z]*\)".*/\1/p')
  DRAFT=$(printf '%s' "$OUT" | sed -n 's/.*"isDraft":\([a-z]*\).*/\1/p')
  URL=$(printf '%s' "$OUT" | sed -n 's|.*"url":"\([^"]*\)".*|\1|p')
  [ -n "$STATE" ] && [ -n "$DRAFT" ]
}

if ! read_pr; then
  echo "ready_mr: could not read $PR: $(tr -d '\n' < "$ERR" 2>/dev/null | cut -c1-200)" >&2
  finish ERROR unreachable; exit 2
fi

# Publishing a MERGED or CLOSED PR is not a no-op worth papering over -- it means
# the caller is holding the wrong MR, or a human closed this one while the run
# was working. Either way that is a decision to surface, not to push past.
if [ "$STATE" != "OPEN" ]; then
  WAS_DRAFT="$DRAFT"
  echo "ready_mr: $PR is $STATE, not OPEN -- nothing to publish, and this is not the MR a prep run should be finishing." >&2
  finish ERROR "not-open-$STATE"; exit 2
fi

if [ "$DRAFT" != "true" ]; then
  WAS_DRAFT=no
  finish READY already-ready; exit 0
fi

WAS_DRAFT=yes
if ! gh "${READY_ARGS[@]}" >/dev/null 2>"$ERR"; then
  echo "ready_mr: could not publish $PR for review: $(tr -d '\n' < "$ERR" 2>/dev/null | cut -c1-200)" >&2
  finish ERROR ready-failed; exit 2
fi

# The confirming re-read. This is the whole reason the script exists; deleting it
# reduces this to `gh pr ready` with extra steps.
if ! read_pr; then
  echo "ready_mr: published $PR but could not re-read it to confirm -- treat it as unproven." >&2
  finish ERROR confirm-unreachable; exit 2
fi
if [ "$DRAFT" = "true" ]; then
  echo "ready_mr: gh reported success but $PR is still a draft -- not claiming it is ready." >&2
  finish ERROR still-draft; exit 2
fi

finish READY published; exit 0
