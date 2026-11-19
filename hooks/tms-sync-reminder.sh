#!/bin/sh
# PostToolUse hook for CADENCE metadata.yaml tracker sync reminder.
# Supports both Antigravity (toolCall.args.TargetFile) and Claude Code (tool_input.file_path).
# Inert outside CADENCE repositories (requires docs/agentic-sdlc/CADENCE_ORG.md with a bound tracker).

fail_safe() { exit 0; }
trap fail_safe EXIT

raw=$(cat 2>/dev/null)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || exit 0

is_agy=0
printf '%s' "$raw" | grep -q '"toolCall"' && is_agy=1

# Fast exit when stdin does not touch any spec/archive metadata path
if ! printf '%s' "$raw" | grep -qE '(specs|archive)/[^/]+/metadata\.ya?ml'; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

eval_fields=$(
  printf '%s' "$raw" | python3 -c '
import json, sys, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tc = d.get("toolCall") or {}
ti = d.get("tool_input") or {}
args = tc.get("args") or {}
f = args.get("TargetFile") or args.get("path") or ti.get("file_path") or ti.get("path") or ""
wps = d.get("workspacePaths") or []
cwd = (wps[0] if isinstance(wps, list) and wps else "") or d.get("cwd") or ""
print("file=" + shlex.quote(str(f)))
print("cwd=" + shlex.quote(str(cwd)))
' 2>/dev/null
) || true

file=""
cwd=""
[ -n "$eval_fields" ] && eval "$eval_fields"

if [ -z "$file" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

norm=$(printf '%s' "$file" | sed 's#\\#/#g')
ticket=$(printf '%s' "$norm" | sed -n 's#.*\(^\|/\)\(specs\|archive\)/\([^/]*\)/metadata\.ya\{0,1\}ml$#\3#p')
if [ -z "$ticket" ] || [ "$ticket" = "TEMPLATE" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

[ -n "$cwd" ] || cwd=$(pwd)

org="$cwd/docs/agentic-sdlc/CADENCE_ORG.md"
[ -f "$org" ] || org="$cwd/processes/docs/agentic-sdlc/CADENCE_ORG.md"
if [ ! -f "$org" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

resolver="$cwd/ci-templates/scripts/org-binding-resolve.sh"
[ -f "$resolver" ] || resolver="$cwd/processes/ci-templates/scripts/org-binding-resolve.sh"
if [ ! -f "$resolver" ]; then
  # Resolver absent: do not fall back to removed scalar tracker markers (BTG-242).
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

prefix=${ticket%%-*}
tracker=$(sh "$resolver" --tracker "$prefix" --org "$org" 2>/dev/null | sed -n 's/^tracker=//p')
case "$tracker" in
  ""|inner-source)
    [ "$is_agy" -eq 1 ] && printf '{}'
    exit 0
    ;;
esac

if [ "$is_agy" -eq 1 ]; then
  # Antigravity PostToolUse contract expects {}; Stop hook handles turn-end continuation if unsynced
  printf '{}'
  exit 0
fi

agent_msg="The metadata.yaml for ${ticket} (${norm}) just changed. Per CADENCE_ORG.md#tracker-binding, project this metadata.yaml change to the bound tracker in the current session."
python3 -c 'import json,sys; m=sys.argv[1]; print(json.dumps({"systemMessage":m,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":m}}))' "$agent_msg"
exit 0
