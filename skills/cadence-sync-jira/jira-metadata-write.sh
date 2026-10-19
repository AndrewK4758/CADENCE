#!/usr/bin/env bash
#
# jira-metadata-write.sh -- the SOLE writer of metadata.yaml for /cadence-sync-jira.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075,
# ADR_CADENCE-0025). Extracted from the orchestrator's own fenced reference
# implementation (BTG-125 DEC-014, Option C): the durability guarantee for the
# one effect this adapter cannot undo -- a duplicate Jira issue -- must be an
# executable a harness can run and a seam can enumerate, not prose an agent is
# trusted to execute faithfully.
#
# Invariant relied on from outside this boundary: every OTHER script in this
# adapter READS metadata.yaml and NEVER writes it (AC-6). This is not one of
# them: it is the one dedicated writer script, invoked by the orchestrator,
# and the sole writer of `metadata.yaml`.
#
# Upstream: invoked by sync_one_ticket / bulk_sync_tickets
#   (jira-server-orchestration.md section 6), up to THREE times per ticket --
#   early after step 4 (`jira_url`, `mode = create` only), early after step 9
#   (`umbrella_epic_url`, guarded on a non-empty emitted value), and once at
#   end-of-operation carrying every key the run accumulated.
# Downstream: NOTHING but the owned `metadata.yaml` file itself. No REST call.
# Spec: archive/BTG-125/spec.md (Proposed Design, Change 1).
#
# Contract (three channels, DEC-001 of BTG-075):
#   args   : --ticket <id> --set <key>=<value> [--set <key>=<value> ...]
#   stdout : nothing
#   stderr : syncjs.metadata.* reported conditions
#   exit   : 0 written (or a declared no-delta) / 1 fail-loud / 2 usage /
#            4 config HALT (unreachable here: no REST call, no config read)
#
# The owned file is reached through the $meta variable, exactly as the fence
# this replaces did -- not to evade the single-writer seam (BTG-125 DEC-014
# measured that OS-1.1 matches only a literal metadata.yaml token on the
# write-construct line, and this script needs no exemption), but because it
# is the moved code, unchanged. `--set` takes explicit key/value pairs so a
# caller cannot accidentally write a key it did not intend (AC-5).

set -u

TICKET=""
SETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ticket)
      [ $# -ge 2 ] || { echo "syncjs.metadata.usage: --ticket requires a value, but the argument list ends there" >&2; exit 2; }
      TICKET="$2"; shift 2 ;;
    --set)
      [ $# -ge 2 ] || { echo "syncjs.metadata.usage: --set requires a value, but the argument list ends there" >&2; exit 2; }
      SETS+=("$2")
      shift 2 ;;
    *) echo "syncjs.metadata.usage: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TICKET" ] || { echo "syncjs.metadata.usage: --ticket <id> is required" >&2; exit 2; }
[ "${#SETS[@]}" -gt 0 ] || { echo "syncjs.metadata.usage: at least one --set <key>=<value> is required" >&2; exit 2; }

# Set one top-level scalar key in a YAML file: substitute the existing line
# (commented or not) in place, else APPEND it. Portable awk, one pass -- moved
# VERBATIM from jira-server-orchestration.md (BTG-125 Change 1); no re-wrap,
# no compression, no logic change. The previous `sed -i -E "0,/re/s||repl|"`
# relied on two GNU extensions busybox sed does not implement, and busybox
# sed is what this repo's Alpine CI runs.
set_yaml_scalar() {
  f="$1"; k="$2"; v="$3"
  awk -v k="$k" -v v="$v" '
    BEGIN { done = 0 }
    !done && match($0, "^[[:space:]]*#?[[:space:]]*" k ":") {
      indent = ""
      if (match($0, /^[[:space:]]*/) && RLENGTH > 0) indent = substr($0, 1, RLENGTH)
      rest = substr($0, index($0, k ":") + length(k) + 1)
      trail = ""                       # keep any trailing `# ...` explanation
      if (match(rest, /[[:space:]]*#.*$/)) trail = substr(rest, RSTART)
      print indent k ": \"" v "\"" trail
      done = 1
      next
    }
    { print }
    END { if (!done) print k ": \"" v "\"" }   # column 0 ends any open block
  ' "$f"
}

id="$TICKET"; root="${CADENCE_REPO_ROOT:-.}"
meta="$root/specs/$id/metadata.yaml"
[ -f "$meta" ] || meta="$root/archive/$id/metadata.yaml"
[ -f "$meta" ] || { echo "syncjs.metadata.absent: no metadata.yaml for $id" >&2; exit 1; }

# At least one --set pair must carry a non-empty value, or there is nothing to
# write back (a best-effort step's guard evaluated empty, for instance).
# QUOTED array expansion throughout -- a --set value carrying whitespace or a
# glob metacharacter must never be split or globbed. The fence this replaces
# iterated a quoted list ("jira_url=$url" "worklog_watermark_at=$advance" ...);
# an earlier revision of this loop iterated an unquoted newline-joined string,
# which word-split a value like "PLAY 1" into two tokens and let the second
# ("1") glob-expand into an injected top-level key -- silently, with exit 0,
# because the verify loop below split the same way and verified the truncated
# tokens it had just written. Found at code review.
has_delta=0
for pair in "${SETS[@]}"; do
  want=${pair#*=}
  [ -n "$want" ] && has_delta=1
done
[ "$has_delta" = 1 ] || { echo "syncjs.metadata.no_delta: nothing to write back for $id" >&2; exit 0; }

# Build the whole new image in a temp file, then replace the owned file with a
# SINGLE atomic rename -- one write per invocation, never one per field. A
# FAILED mktemp REFUSES here, not later: an empty $tmp turns every later
# `awk ... "$tmp"` into an awk with NO FILE OPERAND, which reads STDIN and
# HANGS the run -- unbounded and silent, in the sole writer of owned data.
tmp=$(mktemp 2>/dev/null) || tmp=""
if [ -z "$tmp" ] || ! cp "$meta" "$tmp"; then
  [ -n "$tmp" ] && rm -f "$tmp"
  echo "syncjs.metadata.write_unverified: $id metadata.yaml could not be staged for the write-back (no temp file) -- refusing the write rather than reporting a no-op as success" >&2
  exit 1
fi
# a file that does not end in a newline would otherwise gain `key: "v"` glued
# onto its last line
[ -s "$tmp" ] && [ -n "$(tail -c 1 "$tmp")" ] && printf '\n' >> "$tmp"

for pair in "${SETS[@]}"; do
  key=${pair%%=*}; want=${pair#*=}
  [ -n "$want" ] || continue
  # rewritten IN PLACE via a scratch file, never renamed: the OWNED file is
  # replaced by exactly ONE `mv` (below), which is what makes the update
  # atomic -- a reader never observes a partial image.
  scratch=$(mktemp 2>/dev/null) || scratch=""
  if [ -z "$scratch" ]; then
    rm -f "$tmp"
    echo "syncjs.metadata.write_unverified: $id metadata.yaml could not be staged for the $key write (no temp file) -- refusing the write" >&2
    exit 1
  fi
  if set_yaml_scalar "$tmp" "$key" "$want" > "$scratch"; then cat "$scratch" > "$tmp"; fi
  rm -f "$scratch"
done

# VERIFY BEFORE REPLACING. A no-op write must never be reported as success.
for pair in "${SETS[@]}"; do
  key=${pair%%=*}; want=${pair#*=}
  [ -n "$want" ] || continue
  # anchored on the KEY, literal on the VALUE (awk index, so a value carrying
  # `/` or `.` cannot accidentally match as a regex)
  if [ -z "$tmp" ] || ! awk -v k="$key" -v v="$want" \
       '$0 ~ "^[[:space:]]*"k":" && index($0, v) > 0 { found = 1 } END { exit !found }' "$tmp"; then
    rm -f "$tmp"
    echo "syncjs.metadata.write_unverified: $id metadata.yaml still carries no $key line with the projected value after a set-or-append -- refusing the write rather than reporting a no-op as success" >&2
    exit 1
  fi
done

chmod --reference="$meta" "$tmp" 2>/dev/null || true
mv -f "$tmp" "$meta"
