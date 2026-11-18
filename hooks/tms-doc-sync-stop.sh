#!/bin/sh
# Stop hook -- end-of-operation reminder for CADENCE spec documents and metadata.yaml.
# Supports both Antigravity (workspacePaths, conversationId, terminationReason, continuationActive -> decision:"continue")
# and Claude Code (cwd, session_id, stop_hook_active -> decision:"block").
# Inert outside CADENCE repositories.

trap 'exit 0' EXIT
set -f

raw=$(cat 2>/dev/null)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || exit 0

eval_fields=$(
  printf '%s' "$raw" | python3 -c '
import json, sys, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
is_agy = 1 if ("terminationReason" in d or "continuationActive" in d or "executionNum" in d) else 0
wps = d.get("workspacePaths") or []
cwd = (wps[0] if isinstance(wps, list) and wps else "") or d.get("cwd") or ""
sid = d.get("conversationId") or d.get("session_id") or ""
active = 1 if (d.get("stop_hook_active") is True or d.get("continuationActive") is True) else 0
term = d.get("terminationReason") or ""
print(f"is_agy={is_agy}")
print("cwd=" + shlex.quote(str(cwd)))
print("sid=" + shlex.quote(str(sid)))
print(f"active={active}")
print("term_reason=" + shlex.quote(str(term)))
' 2>/dev/null
) || true

is_agy=0 cwd="" sid="" active=0 term_reason=""
[ -n "$eval_fields" ] && eval "$eval_fields"

# In Antigravity, only evaluate on normal turn completion (NO_TOOL_CALL)
if [ "$is_agy" -eq 1 ] && [ -n "$term_reason" ] && [ "$term_reason" != "NO_TOOL_CALL" ]; then
  printf '{"decision":"allow"}'
  exit 0
fi

[ -n "$cwd" ] || cwd=$(pwd)
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

org="$cwd/docs/agentic-sdlc/CADENCE_ORG.md"
[ -f "$org" ] || org="$cwd/processes/docs/agentic-sdlc/CADENCE_ORG.md"
[ -f "$org" ] || exit 0

resolver="$cwd/ci-templates/scripts/org-binding-resolve.sh"
[ -f "$resolver" ] || resolver="$cwd/processes/ci-templates/scripts/org-binding-resolve.sh"
# Resolver required; never fall back to removed scalar tracker markers.
[ -f "$resolver" ] || exit 0

PATHS="specs/*/metadata.yaml specs/*/problem.md specs/*/spec.md specs/*/test-plan.md archive/*/metadata.yaml archive/*/problem.md archive/*/spec.md archive/*/test-plan.md"

changed=$(git -C "$cwd" diff --name-only HEAD -- $PATHS 2>/dev/null)
untracked=$(git -C "$cwd" ls-files --others --exclude-standard -- $PATHS 2>/dev/null)
all=$(printf '%s\n%s\n' "$changed" "$untracked" | sed '/^$/d' \
  | grep -Ev '(^|/)(specs|archive)/TEMPLATE/' | sort -u)
[ -n "$all" ] || exit 0

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

[ "$active" -eq 1 ] && exit 0

tickets=$(printf '%s\n' "$all" | sed -n 's#.*\(specs\|archive\)/\([^/]*\)/.*#\2#p' | sort -u | tr '\n' ' ' | sed 's/ *$//')
reason="CADENCE spec/metadata documents changed without a tracker sync for: ${tickets}. Per CADENCE_ORG.md §9 (Projection triggers & sync discipline), run the bound sync skill for each listed ticket before finishing, unless already synced in this session."

if [ "$is_agy" -eq 1 ]; then
  python3 -c 'import json,sys; print(json.dumps({"decision":"continue","reason":sys.argv[1]}))' "$reason"
else
  python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]}))' "$reason"
fi
exit 0
