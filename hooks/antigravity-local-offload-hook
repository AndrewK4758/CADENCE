#!/bin/sh
# Global Lifecycle Hook (PreInvocation + PostToolUse) for Universal LiteRT / CADENCE Local Offload (:11434).
# Installed globally in ~/.gemini/config/hooks.json and ~/.agents/hooks.json so it runs on ALL repositories
# without per-repo configuration, and deduplicates across both global and repo-level hook invocations.

fail_safe() { exit 0; }
trap fail_safe EXIT

if [ "${AGY_DISABLE_LITERT:-0}" = "1" ]; then
  printf '{}'
  exit 0
fi

raw=$(cat 2>/dev/null)
[ -n "$(printf '%s' "$raw" | tr -d ' \t\r\n')" ] || exit 0

extract_str() {
  printf '%s' "$raw" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}
extract_int() {
  printf '%s' "$raw" | sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1
}

sid=$(extract_str conversationId)
[ -n "$sid" ] || sid=$(extract_str session_id)
safe_sid=$(printf '%s' "${sid:-default}" | tr -c 'A-Za-z0-9._-' '_')

# ---------------------------------------------------------------------------
# 1. PreInvocation Handler (Antigravity: payload has "invocationNum" & no "toolCall")
# ---------------------------------------------------------------------------
inv_num=$(extract_int invocationNum)
if [ -n "$inv_num" ] && ! printf '%s' "$raw" | grep -q '"toolCall"'; then
  dedup_file="/tmp/agy-offload-preinv.${safe_sid}"
  prev_inv=$(cat "$dedup_file" 2>/dev/null || echo "")
  if [ "$prev_inv" = "$inv_num" ]; then
    printf '{}'
    exit 0
  fi
  printf '%s' "$inv_num" > "$dedup_file" 2>/dev/null

  remind_file="/tmp/agy-offload-remind.${safe_sid}"
  if [ -f "$remind_file" ]; then
    msg=$(cat "$remind_file" 2>/dev/null)
    rm -f "$remind_file" 2>/dev/null
    if [ -n "$msg" ]; then
      printf '{"injectSteps":[{"ephemeralMessage":"%s"}]}' "$msg"
      exit 0
    fi
  fi

  first_file="/tmp/agy-offload-first.${safe_sid}"
  if [ ! -f "$first_file" ]; then
    printf '%s' "$inv_num" > "$first_file" 2>/dev/null
    msg="[COGNITIVE & LOCAL-OFFLOAD GATE (:11434) — READ-ONLY REASONING DEFAULT]: (A) THINK FIRST, DO NOT CREATE: Unless the user prompt explicitly authorizes implementation ('implement', 'write the code', 'apply patch', 'create file', 'build', or /cadence-implement), operate strictly in Read-Only Epistemic Architecture Mode (falsify premises, trace cross-boundary state, analyze trade-offs; NEVER call write_to_file/replace_file_content/multi_replace_file_content or dump unsolicited full files). (B) CONDITIONAL LOCAL-OFFLOAD SCHEMAS (DO NOT read_file .json schemas): ONLY IF this turn requires codebase discovery, test/log execution, or pre-PR review, call call_mcp_tool(ServerName='local-offload', ToolName=..., Arguments=...) directly without reading /home/ak/.gemini/antigravity-cli/mcp/local-offload/*.json: (1) local_semantic_embed: Arguments={'texts':['<file_or_dir>',...],'query':'<search_query>','top_k':6} — returns AST-aligned Pinned Context Slices + full File Symbol Maps (sym@L<line>); answer directly from pinned slices and only read_file specific missing StartLine..EndLine ranges; (2) offload_log_triage: Arguments={'log_text_or_command':'cmd:<shell_cmd>' or '<log_path_or_text>','model':'inference'} — runs/triages tests & builds on :11434 and writes raw log to /tmp/agy-triage/<repo_name>/<pid>.log (eliminates run_command for tests); (3) offload_deep_review: Arguments={'prompt':'<task>','context_files':['<path>',...],'model':'inference'} before commit/PR. NOTE: If [LiteRT Pre-Modified Execution Pack (:11434)] is ALREADY in the prompt or no repository lookup is required, reason directly without calling tools."
    printf '{"injectSteps":[{"ephemeralMessage":"%s"}]}' "$msg"
    exit 0
  fi

  printf '{}'
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. PostToolUse Handler (Antigravity "toolCall" or Claude Code "tool_input")
# ---------------------------------------------------------------------------
is_agy=0
printf '%s' "$raw" | grep -q '"toolCall"' && is_agy=1

step_idx=$(extract_int stepIdx)
if [ -n "$step_idx" ]; then
  post_dedup="/tmp/agy-offload-posttool.${safe_sid}"
  prev_step=$(cat "$post_dedup" 2>/dev/null || echo "")
  if [ "$prev_step" = "$step_idx" ]; then
    [ "$is_agy" -eq 1 ] && printf '{}'
    exit 0
  fi
  printf '%s' "$step_idx" > "$post_dedup" 2>/dev/null
fi

cmd_str=$(printf '%s' "$raw" | sed -n 's/.*"CommandLine"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
if [ -z "$cmd_str" ]; then
  cmd_str=$(printf '%s' "$raw" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
fi

if [ -z "$cmd_str" ]; then
  [ "$is_agy" -eq 1 ] && printf '{}'
  exit 0
fi

remind_file="/tmp/agy-offload-remind.${safe_sid}"

case "$cmd_str" in
  # Test / build / compiler / lint gates (substring matches on the raw command line).
  # Groups, in order: .NET | Python | JS/TS | Rust/Go | JVM/C/Make | CADENCE gates.
  *"dotnet test"*|*"dotnet build"*|*"dotnet ef"*|\
  *"pytest"*|*"unittest"*|*"tox "*|*"nox "*|*"ruff check"*|*"mypy "*|*"pyright"*|\
  *"npm test"*|*"npm run build"*|*"npm run test"*|*"npm run lint"*|*"pnpm test"*|*"pnpm build"*|*"pnpm run "*|\
  *"yarn test"*|*"yarn build"*|*"bun test"*|*"bun run "*|*"deno test"*|*"vitest"*|*" jest"*|"jest"*|*"playwright test"*|\
  *"eslint"*|*" tsc"*|"tsc"*|*"vite build"*|*"next build"*|*"turbo run"*|*"nx run"*|*"nx test"*|*"nx build"*|\
  *"cargo test"*|*"cargo check"*|*"cargo build"*|*"cargo clippy"*|*"go test"*|*"go build"*|*"go vet"*|\
  *"mvn test"*|*"mvn verify"*|*"mvn package"*|*"gradle test"*|*"gradle build"*|*"gradlew test"*|*"gradlew build"*|\
  *"make test"*|*"make check"*|*"make build"*|*"make all"*|*"ctest"*|*"cmake --build"*|*" ninja"*|"ninja"*|\
  *"verify-spec.sh"*|*"verify-facts.sh"*|*"authored-doc-gate.sh"*|*"dead-citation-gate.sh"*)
    msg="CADENCE Automatic Local Offload (:11434): Route any test/build/compiler/gate output exceeding 30 lines or exiting non-zero through call_mcp_tool(ServerName='local-offload', ToolName='offload_log_triage', Arguments={'log_text_or_command': ...}) or invoke_subagent(TypeName='log-triage') (raw log saved at /tmp/agy-triage/<repo_name>/<pid>.log)."
    if [ "$is_agy" -eq 1 ]; then
      printf '%s' "$msg" > "$remind_file" 2>/dev/null
      printf '{}'
      exit 0
    fi
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$msg" "$msg"
    exit 0
    ;;
  *"find "*|*"grep "*|*"rg "*)
    search_cnt_file="/tmp/agy-offload-searches.${safe_sid}"
    cnt=$(cat "$search_cnt_file" 2>/dev/null || echo "0")
    cnt=$((cnt + 1))
    printf '%s' "$cnt" > "$search_cnt_file" 2>/dev/null
    if [ "$cnt" -eq 2 ]; then
      msg="CADENCE Automatic Local Offload (:11434): You have run multiple shell search commands. Use call_mcp_tool(ServerName='local-offload', ToolName='local_semantic_embed', ...) (GPU-pinned on :11434) or invoke_subagent(TypeName='repo-scout') to semantically rank candidate files and offload multi-file exploration."
      if [ "$is_agy" -eq 1 ]; then
        printf '%s' "$msg" > "$remind_file" 2>/dev/null
        printf '{}'
        exit 0
      fi
      printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' "$msg" "$msg"
      exit 0
    fi
    [ "$is_agy" -eq 1 ] && printf '{}'
    exit 0
    ;;
  *)
    [ "$is_agy" -eq 1 ] && printf '{}'
    exit 0
    ;;
esac
