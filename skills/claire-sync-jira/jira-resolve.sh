#!/usr/bin/env bash
#
# jira-resolve.sh -- decide CREATE vs UPDATE and resolve the issue key.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (DEC-009): this script is where
# the whole sync's idempotency is decided. A duplicate issue is the one effect
# that cannot be undone -- worklogs are immutable, links are additive, fields are
# set-to-desired, but a second issue splits the ticket's history in two and the
# repo can only ever point at one of them.
#
# Since BTG-125, a prior run that HALTED after creating the issue records
# `jira_url` as soon as jira-write-issue.sh (step 4) RETURNS -- immediately, not
# at end-of-operation. So the residual this script must still report is narrow:
# only a halt INSIDE step 4 itself, between the create POST and the script's own
# return (a span that includes the non-fatal screen-completion PUT), still loses
# the mapping. Repo state alone says "create" on that path, and since BTG-124
# that is the answer this script gives -- see below.
#
# BTG-124 DEC-007 (OQ-1 Option C, ratified at the Spec Review gate): the id search
# that used to cover the OLD, wider window is GONE and is NOT replaced. It worked
# by matching the repo id inside the projected Summary, and BTG-124 removed the id
# from the Summary. So `jira_url` is now the SOLE identity mapping, this script
# makes NO REST call on any path, and the residual duplicate it can no longer
# prevent is an ACCEPTED, ratified trade that the create branch REPORTS rather
# than takes silently. The measure that closes most of the window at its source --
# recording `jira_url` immediately after the create POST returns, rather than only
# at end-of-operation -- SHIPPED as BTG-125 (Option C: one dedicated writer
# script, invoked by the orchestrator, is the sole writer of `metadata.yaml`).
# The "READS metadata.yaml and NEVER writes it" invariant nine operation-script
# headers and seven library headers state is REFRAMED by that design, not
# lifted, and not six headers -- sixteen.
#
# Upstream: the first ticket-scoped step of the /claire-sync-jira sequence.
# Downstream: NOTHING. This script reads `metadata.yaml` and the config and issues
#   no request at all; it mutates nothing anywhere.
# Spec: archive/BTG-075/spec.md (Idempotency) ; archive/BTG-124/decisions.md DEC-007
#   ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   args   : --ticket <id>
#   stdout : mode=update|create ; issue_key=<KEY> when resolved
#   stderr : syncjs.resolve.* reported conditions
#   exit   : 0 ok / 1 fail-loud / 2 usage / 4 config HALT
#
# This script READS metadata.yaml and NEVER writes it (AC-6). Since BTG-124
# (DEC-007) it resolves ENTIRELY from repo state and issues no request, so it
# emits no `jira_url=` and cannot report a transport failure -- exit 3 is
# unreachable here. It no longer recovers a halted run's effect: the fuzzy
# `summary ~ "<id>"` search that did so was deleted, not replaced, when the
# ticket-id prefix left the Summary. A ticket with no recorded `jira_url`
# therefore resolves `create`, and if an issue already exists the re-run mints a
# duplicate -- the ratified residual risk, reported loudly at the create branch
# below rather than silently compensated. BTG-125 closes MOST of the window at
# source; the residual it leaves is a halt inside step 4 itself.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) js_argv_pair syncjs.resolve.usage "$@"; TICKET="$2"; shift 2 ;;
    *) js_halt "$JS_EXIT_USAGE" syncjs.resolve.usage "unknown argument: $1" ;;
  esac
done
[[ -n "$TICKET" ]] || js_halt "$JS_EXIT_USAGE" syncjs.resolve.usage "--ticket <id> is required"

js_config_require
js_metadata_load "$TICKET"

# No environment is read here any more. Until BTG-124 this script resolved the
# base URL to build a `jira_url=` for the recovery path and to name the host in a
# transport halt; both are gone with that path (DEC-007), so requiring the
# variable would refuse -- with a usage halt -- a resolution this script can now
# complete entirely from repo state. The orchestrated sequence still demands it
# at step 1 (`jira-connect`), which is the right place for it.

# (1) Repo state first. A populated `jira_url` is the authoritative answer and
# costs no call. A COMMENTED-OUT key is absent, not populated -- the shipped
# metadata template ships it commented, and reading it as populated would resolve
# every brand-new ticket to an empty key. (The metadata parser drops comment
# lines, so this is structural rather than a special case here.)
JIRA_URL="$(js_metadata_get '.jira_url')"
if [[ -n "$JIRA_URL" ]]; then
  ISSUE_KEY="${JIRA_URL##*/}"
  if [[ -z "$ISSUE_KEY" || "$ISSUE_KEY" == "$JIRA_URL" ]]; then
    js_halt "$JS_EXIT_FAIL" syncjs.resolve.url_unparseable \
      "jira_url='$JIRA_URL' does not end in an issue key -- refusing to guess which issue this ticket projects to"
  fi
  js_report syncjs.resolve.from_metadata "$TICKET resolves to $ISSUE_KEY from its recorded jira_url"
  js_emit mode update
  js_emit issue_key "$ISSUE_KEY"
  exit "$JS_EXIT_OK"
fi

# (2) No recorded URL -- and that is the END of the enquiry. BTG-124 DEC-007
# (OQ-1 Option C, ratified by the human maintainer at the Spec Review gate)
# DELETED the halted-run recovery search that used to stand here. It found the
# issue by the repo id embedded in the projected Summary, and BTG-124 removed
# that id from the Summary. It was NOT replaced: `jira_url` is now the SOLE
# identity mapping between a repo ticket and its Jira issue.
#
# The residual is REPORTED, never left for an operator to infer, because the
# guard that used to cover it was real. Since BTG-125, `jira_url` is recorded as
# soon as jira-write-issue.sh (step 4) RETURNS -- immediately, not at
# end-of-operation -- so the only halt that still loses it, and still mints a
# SECOND issue -- the one effect nothing downstream can undo -- is one INSIDE
# step 4 itself, between the create POST and the script's own return (a span
# that includes the non-fatal screen-completion PUT). The write model is now a
# dedicated writer script invoked by the orchestrator (BTG-125 Option C): the
# "READS metadata.yaml and NEVER writes it" invariant nine operation-script
# headers and seven library headers state is REFRAMED, not lifted, by that
# design -- every one of those sixteen headers stays literally true because the
# writer is not an operation script.
js_report syncjs.resolve.create \
  "$TICKET has no recorded jira_url -- taking the CREATE path. No recovery lookup is performed: the recorded jira_url is the ONLY identity mapping this adapter has (BTG-124 DEC-007 deleted the id search from here, because the projected Summary no longer carries the ticket id, and deliberately did not replace it). Since BTG-125 jira_url is recorded as soon as jira-write-issue.sh returns, so the remaining exposure is a halt INSIDE that step itself -- between the create POST and its return, a span that includes the non-fatal screen-completion PUT -- which would still mint a DUPLICATE on re-run. Transcript check: if the previous run's transcript shows syncjs.write.created with no metadata write reported after it, check the project by hand before re-running"
js_emit mode create
exit "$JS_EXIT_OK"
