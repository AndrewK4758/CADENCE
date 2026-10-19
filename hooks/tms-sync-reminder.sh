#!/bin/sh
# PostToolUse hook for CLAIRE metadata.yaml tracker sync reminder.
# Supports both Antigravity (toolCall.args.TargetFile) and Claude Code (tool_input.file_path).
# Inert outside CLAIRE repositories (requires docs/agentic-sdlc/CLAIRE_ORG.md with a bound tracker).

fail_safe() { exit 0; }
trap fail_safe EXIT

raw=$(cat 2>/dev/null)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || exit 0

# Detect runtime: Antigravity passes "toolCall", Claude passes "tool_input"
is_agy=0
printf '%s' "$raw" | grep -q '"toolCall"' && is_agy=1

file=$(printf '%s' "$raw" | sed -n 's/.*"TargetFile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
if [ -z "$file" ]; then
  file=$(printf '%s' "$raw" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi
if [ -z "$file" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

norm=$(printf '%s' "$file" | sed 's#\\\\*#/#g')
ticket=$(printf '%s' "$norm" | sed -n 's#.*\(^\|/\)\(specs\|archive\)/\([^/]*\)/metadata\.ya\{0,1\}ml$#\3#p')
if [ -z "$ticket" ] || [ "$ticket" = "TEMPLATE" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

cwd=$(printf '%s' "$raw" | sed -n 's/.*"workspacePaths"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's#\\\\*#/#g')
if [ -z "$cwd" ]; then
  cwd=$(printf '%s' "$raw" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's#\\\\*#/#g')
fi
[ -n "$cwd" ] || cwd=$(pwd)

org="$cwd/docs/agentic-sdlc/CLAIRE_ORG.md"
if [ ! -f "$org" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

resolver="$cwd/ci-templates/scripts/org-binding-resolve.sh"
if [ -f "$resolver" ]; then
  prefix=${ticket%%-*}
  tracker=$(sh "$resolver" --tracker "$prefix" --org "$org" 2>/dev/null | sed -n 's/^tracker=//p')
  case "$tracker" in
    ""|inner-source)
      [ "$is_agy" -eq 1 ] && printf '{}'
      exit 0
      ;;
  esac
else
  bound=$(sed -n 's/.*\*\*Bound tracker(s):\*\*[[:space:]]*\([^.<]*\).*/\1/p' "$org" 2>/dev/null | head -n1)
  case "$(printf '%s' "$bound" | tr 'A-Z' 'a-z' | tr -d ' ')" in
    ""|none*|*inner-source*|*placeholder*|'<'*)
      [ "$is_agy" -eq 1 ] && printf '{}'
      exit 0
      ;;
  esac
fi

if [ "$is_agy" -eq 1 ]; then
  # Antigravity PostToolUse contract expects {}; Stop hook handles turn-end continuation if unsynced
  printf '{}'
  exit 0
fi

agent_msg="The metadata.yaml for ${ticket} (${norm}) just changed. Per CLAIRE_ORG.md §9 tracker binding, project this metadata.yaml change to the bound tracker in the current session."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
  "$agent_msg" "$agent_msg"
exit 0
