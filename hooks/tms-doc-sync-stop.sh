#!/bin/sh
# Stop hook -- end-of-operation reminder for CADENCE spec documents and metadata.yaml.
# Supports both Antigravity (workspacePaths, conversationId, terminationReason -> decision:"continue")
# and Claude Code (cwd, session_id -> decision:"block").
# Inert outside CADENCE repositories.

trap 'exit 0' EXIT
set -f

raw=$(cat 2>/dev/null)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || exit 0

is_agy=0
printf '%s' "$raw" | grep -q '"terminationReason"' && is_agy=1

extract() { printf '%s' "$raw" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1; }

cwd=$(printf '%s' "$raw" | sed -n 's/.*"workspacePaths"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 | sed 's#\\\\*#/#g')
[ -n "$cwd" ] || cwd=$(extract cwd | sed 's#\\\\*#/#g')
[ -n "$cwd" ] || cwd=$(pwd)

sid=$(extract conversationId)
[ -n "$sid" ] || sid=$(extract session_id)
active=$(printf '%s' "$raw" | sed -n 's/.*"stop_hook_active"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -n1)
term_reason=$(extract terminationReason)

# In Antigravity, only evaluate on normal turn completion (NO_TOOL_CALL)
if [ "$is_agy" -eq 1 ] && [ -n "$term_reason" ] && [ "$term_reason" != "NO_TOOL_CALL" ]; then
  printf '{"decision":"allow"}'
  exit 0
fi

git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

org="$cwd/docs/agentic-sdlc/CADENCE_ORG.md"
[ -f "$org" ] || exit 0

resolver="$cwd/ci-templates/scripts/org-binding-resolve.sh"
perprefix=0
if [ -f "$resolver" ]; then
  perprefix=1
else
  bound=$(sed -n 's/.*\*\*Bound tracker(s):\*\*[[:space:]]*\([^.<]*\).*/\1/p' "$org" 2>/dev/null | head -n1)
  case "$(printf '%s' "$bound" | tr 'A-Z' 'a-z' | tr -d ' ')" in
    ""|none*|*inner-source*|*placeholder*|'<'*) exit 0 ;;
  esac
fi

PATHS="specs/*/metadata.yaml specs/*/problem.md specs/*/spec.md specs/*/test-plan.md archive/*/metadata.yaml archive/*/problem.md archive/*/spec.md archive/*/test-plan.md"

changed=$(git -C "$cwd" diff --name-only HEAD -- $PATHS 2>/dev/null)
untracked=$(git -C "$cwd" ls-files --others --exclude-standard -- $PATHS 2>/dev/null)
all=$(printf '%s\n%s\n' "$changed" "$untracked" | sed '/^$/d' \
  | grep -Ev '(^|/)(specs|archive)/TEMPLATE/' | sort -u)
[ -n "$all" ] || exit 0

if [ "$perprefix" -eq 1 ]; then
  kept=""
  for f in $all; do
    id=$(printf '%s' "$f" | sed -n 's#.*\(specs\|archive\)/\([^/]*\)/.*#\2#p')
    [ -n "$id" ] || continue
    t=$(sh "$resolver" --tracker "${id%%-*}" --org "$org" 2>/dev/null | sed -n 's/^tracker=//p')
    case "$t" in ""|inner-source) continue ;; esac
    kept="$kept$f
"
  done
  all=$(printf '%s' "$kept" | sed '/^$/d')
  [ -n "$all" ] || exit 0
fi

sig=$( { git -C "$cwd" diff HEAD -- $PATHS 2>/dev/null
         printf '%s\n' "$untracked" | sed '/^$/d' | while IFS= read -r f; do
           printf 'U %s\n' "$f"; cat "$cwd/$f" 2>/dev/null
         done
       } | git -C "$cwd" hash-object --stdin 2>/dev/null )
[ -n "$sig" ] || exit 0

safe_sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9._-' '_')
state=$(git -C "$cwd" rev-parse --git-path "cadence-doc-sync.$safe_sid" 2>/dev/null)
case "$state" in
  "") state="$cwd/.git/cadence-doc-sync.$safe_sid" ;;
  /*) : ;;
  *)  state="$cwd/$state" ;;
esac
[ "$(cat "$state" 2>/dev/null)" = "$sig" ] && exit 0
printf '%s' "$sig" > "$state" 2>/dev/null

[ "$active" = "true" ] && exit 0

tickets=$(printf '%s\n' "$all" | sed -n 's#.*\(specs\|archive\)/\([^/]*\)/.*#\2#p' | sort -u | tr '\n' ' ' | sed 's/ *$//')
reason="CADENCE spec/metadata documents changed without a tracker sync for: ${tickets}. Per CADENCE_ORG.md §9 (Projection triggers & sync discipline), run the bound sync skill for each listed ticket before finishing, unless already synced in this session."

if [ "$is_agy" -eq 1 ]; then
  printf '{"decision":"continue","reason":"%s"}' "$reason"
else
  printf '{"decision":"block","reason":"%s"}' "$reason"
fi
exit 0
