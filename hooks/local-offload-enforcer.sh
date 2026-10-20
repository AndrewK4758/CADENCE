#!/bin/sh
# Lifecycle hook (PreInvocation + PostToolUse) for universal CADENCE / LiteRT Local Hardware Coprocessor Offload enforcement.
# Routes all prompts (both general/ad-hoc requests and /cadence-* skills) through the unified llama-swap gateway on 127.0.0.1:11434
# (`local-offload` MCP tools: `local_semantic_embed`, `offload_log_triage`, `offload_deep_review`, and subagents: `repo-scout`, `log-triage`).
# Supports both Antigravity (PreInvocation -> injectSteps ephemeralMessage; PostToolUse -> queues reminder) and Claude Code (PostToolUse -> systemMessage).

fail_safe() { exit 0; }
trap fail_safe EXIT

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

  # On the first invocation of a user prompt turn (invocationNum == 1), inject a transient reminder
  if [ "$inv_num" = "1" ]; then
    msg="[MANDATORY LITERT / LOCAL-OFFLOAD PIPELINE (:11434)]: On THIS prompt (whether ad-hoc or /cadence-*), you MUST use your local-offload MCP tools (call_mcp_tool ServerName='local-offload' — read /home/ak/.gemini/antigravity-cli/mcp/local-offload/<tool>.json first if lazy-loaded) and offload subagents (repo-scout, log-triage): (1) Step 0 Discovery: call local_semantic_embed or invoke_subagent(TypeName='repo-scout') to rank candidate files before broad read_file/grep/find sweeps; (2) Log Triage: route test/build/diagnostic commands or >30-line outputs through offload_log_triage (log_text_or_command='cmd:<command>' or text/path) or log-triage; (3) Pre-Commit Review: call offload_deep_review on modified files before committing or opening a PR."
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
  *"dotnet test"*|*"dotnet build"*|*"dotnet ef"*|*"pytest"*|*"npm test"*|*"pnpm test"*|*"cargo test"*|*"cargo check"*|*"go test"*|*"verify-spec.sh"*|*"verify-facts.sh"*|*"authored-doc-gate.sh"*|*"dead-citation-gate.sh"*)
    msg="CADENCE Automatic Local Offload (:11434): Route any test/build/compiler/gate output exceeding 30 lines or exiting non-zero through call_mcp_tool(ServerName='local-offload', ToolName='offload_log_triage', Arguments={'log_text_or_command': ...}) or invoke_subagent(TypeName='log-triage') (raw log saved at /tmp/agy-last-triage.log)."
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
      msg="CADENCE Automatic Local Offload (:11434): You have run multiple shell search commands. Use call_mcp_tool(ServerName='local-offload', ToolName='local_semantic_embed', ...) (0 MB VRAM on :11434) or invoke_subagent(TypeName='repo-scout') to semantically rank candidate files and offload multi-file exploration."
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
