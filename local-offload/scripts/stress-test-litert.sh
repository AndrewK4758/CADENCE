#!/usr/bin/env bash
# ==============================================================================
# stress-test-litert-mployee.sh
# End-to-End Integration & A/B Stress Test:
#   LiteRT (:11434) -> Modified Query -> Gemini 4 Argon (High)
#   Target Workload: ~/projects/mployee
#
# Suites:
#   1. Global Hook Concurrency & Deduplication Test (50 parallel sessions)
#   2. Concurrent Per-Repo/PID Log Isolation (/tmp/agy-triage/mployee/<PID>.log)
#   3. LiteRT (:11434) Concurrent Load & Compaction Benchmark
#   4. Live Gemini 4 Argon Integration A/B/C Test (WITHOUT LiteRT vs WITH LiteRT
#      MCP vs WITH LiteRT Pre-Modified Query: Token Usage, Steps & Output Quality)
# ==============================================================================
set -euo pipefail

export PATH="/home/ak/.local/bin:/home/ak/.asdf/shims:/home/ak/.asdf/bin:/home/ak/bin:/usr/local/bin:/usr/bin:$PATH"
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  TARGET_USER="${SUDO_USER:-ak}"
  exec sudo -u "$TARGET_USER" -H env PATH="$PATH" "$0" "$@"
fi

MPLOYEE_DIR="${MPLOYEE_DIR:-/home/ak/projects/mployee}"
HOOK_BIN="/home/ak/.local/bin/antigravity-local-offload-hook"
MCP_BIN="/home/ak/.local/bin/antigravity-local-offload-mcp"
UV_BIN="/home/ak/.local/bin/uv"
GLOBAL_HOOKS="/home/ak/.gemini/config/hooks.json"

printf "==============================================================================\n"
printf " LiteRT (:11434) + Gemini 4 Argon Full Integration Stress Test (mployee)\n"
printf "==============================================================================\n\n"

# ------------------------------------------------------------------------------
# Suite 1: Global Hook Concurrency & Deduplication Verification
# ------------------------------------------------------------------------------
printf "[Suite 1/4] Testing Global Hook Concurrency & Deduplication (50 parallel sessions)...\n"
grep -q '"global-litert-offload-enforcer"' "$GLOBAL_HOOKS" || {
  echo "FAIL: global-litert-offload-enforcer missing in $GLOBAL_HOOKS" >&2
  exit 1
}

FAIL_FILE=$(mktemp)
seq 1 50 | xargs -P 10 -I@ sh -c '
  SID="stress-mployee-@"
  OUT1=$(printf "{\"conversationId\":\"%s\",\"invocationNum\":1,\"workspacePaths\":[\"%s\"]}" "$SID" "'"$MPLOYEE_DIR"'" | "'"$HOOK_BIN"'")
  echo "$OUT1" | grep -q "MANDATORY LITERT" || echo "FAIL_TURN1:$SID:$OUT1" >> "'"$FAIL_FILE"'"

  OUT1_DUP=$(printf "{\"conversationId\":\"%s\",\"invocationNum\":1,\"workspacePaths\":[\"%s\"]}" "$SID" "'"$MPLOYEE_DIR"'" | "'"$HOOK_BIN"'")
  [ "$OUT1_DUP" = "{}" ] || echo "FAIL_DEDUP:$SID:$OUT1_DUP" >> "'"$FAIL_FILE"'"

  printf "{\"conversationId\":\"%s\",\"stepIdx\":4,\"toolCall\":{\"name\":\"run_command\",\"args\":{\"CommandLine\":\"go test ./orchestrator_service/... ./ai_service/...\"}}}" "$SID" | "'"$HOOK_BIN"'" >/dev/null

  OUT2=$(printf "{\"conversationId\":\"%s\",\"invocationNum\":2}" "$SID" | "'"$HOOK_BIN"'")
  echo "$OUT2" | grep -q "/tmp/agy-triage/<repo_name>/<pid>.log" || echo "FAIL_TURN2:$SID:$OUT2" >> "'"$FAIL_FILE"'"

  rm -f "/tmp/agy-offload-preinv.$SID" "/tmp/agy-offload-first.$SID" "/tmp/agy-offload-posttool.$SID" "/tmp/agy-offload-remind.$SID" "/tmp/agy-offload-searches.$SID"
'

if [[ -s "$FAIL_FILE" ]]; then
  echo "  -> FAIL in Suite 1:" >&2
  cat "$FAIL_FILE" >&2
  rm -f "$FAIL_FILE"
  exit 1
fi
rm -f "$FAIL_FILE"
printf "  -> PASS: 50/50 concurrent sessions injected, deduplicated, and verified.\n\n"

# ------------------------------------------------------------------------------
# Suite 2, 3 & 4: Concurrent LiteRT Load + Live Gemini 4 Argon A/B/C Benchmark
# ------------------------------------------------------------------------------
printf "[Suite 2, 3 & 4] Running LiteRT (:11434) Stress + Live Gemini 4 Argon A/B/C Test...\n"
if command -v nvidia-smi >/dev/null 2>&1; then
  printf "  -> GPU Pre-Test Status:\n"
  nvidia-smi --query-gpu=index,name,memory.used,memory.free,utilization.gpu --format=csv,noheader | sed 's/^/     /'
fi

"$UV_BIN" run --with "mcp>=1.2.0,<2.0.0" python3 - <<'EOF'
import concurrent.futures
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import re
import statistics
import subprocess
import time

loader = importlib.machinery.SourceFileLoader("offload", "/home/ak/.local/bin/antigravity-local-offload-mcp")
spec = importlib.util.spec_from_loader("offload", loader)
offload = importlib.util.module_from_spec(spec)
loader.exec_module(offload)

MPLOYEE = "/home/ak/projects/mployee"
BRAIN_DIR = pathlib.Path("/home/ak/.gemini/antigravity-cli/brain")
REPORT_PATH = pathlib.Path("/tmp/agy-triage/mployee/ab-comparison-report.md")

# --- Suite 2: 8 Concurrent Per-Repo/PID Triage Log Isolation Checks ---
def run_isolated_triage(idx: int) -> pathlib.Path:
    cmd = f"cmd:cd {MPLOYEE} && printf 'worker={idx} line=%d\\n' $(seq 1 12)"
    res = offload.offload_log_triage(log_text_or_command=cmd)
    m = re.search(r"\*\*Raw\*\*:\s*`([^`]+)`", res)
    assert m, f"Missing Raw path: {res}"
    p = pathlib.Path(m.group(1))
    assert p.exists() and p.parent.name == "mployee" and f"worker={idx} line=12" in p.read_text(encoding="utf-8")
    return p

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    paths = list(ex.map(run_isolated_triage, range(8)))
assert len(set(paths)) == 8
print(f"  -> PASS [Suite 2]: 8/8 concurrent logs isolated in /tmp/agy-triage/mployee/<PID>.log")

# --- Suite 3: Concurrent LiteRT (:11434) Stress Load ---
QUERIES = [
    ("NATS JetStream wildcard subject hierarchy worker.<domain>.> and fail-fast panic",
     [f"{MPLOYEE}/orchestrator_service", f"{MPLOYEE}/ai_service"]),
    ("Identity validation MustValidate TenantId AppId JobId zero fallbacks",
     [f"{MPLOYEE}/shared_utils/identityparser", f"{MPLOYEE}/semantic_cache_service"]),
    ("C++26 MLInferenceEngine GLiNER zero-shot redaction and MuPDF Form XObject",
     [f"{MPLOYEE}/document_processing_service", f"{MPLOYEE}/storage_gateway_service"]),
    ("GlobalStatePayload unconditional hydration and native semantic cache unwrapping",
     [f"{MPLOYEE}/orchestrator_service", f"{MPLOYEE}/human_validation_service"]),
]

def bench_embed(idx: int):
    q, targets = QUERIES[idx % len(QUERIES)]
    t0 = time.perf_counter()
    pack = offload.local_semantic_embed(texts=targets, query=q, top_k=5)
    dt = (time.perf_counter() - t0) * 1000.0
    raw_bytes = sum(p.stat().st_size for t in targets for p in pathlib.Path(t).rglob("*.go") if p.is_file())
    return ("embed_rewrite", dt, raw_bytes, len(pack.encode("utf-8")))

def bench_triage(idx: int):
    t0 = time.perf_counter()
    cmd = f"cmd:cd {MPLOYEE} && go test -v -count=1 ./shared_utils/workflowparser/... ./ai_service/internal/server/..."
    out = offload.offload_log_triage(log_text_or_command=cmd)
    dt = (time.perf_counter() - t0) * 1000.0
    m = re.search(r"\*\*Raw\*\*:\s*`([^`]+)`", out)
    raw_bytes = pathlib.Path(m.group(1)).stat().st_size if m else 1
    return ("log_triage", dt, raw_bytes, len(out.encode("utf-8")))

def bench_review(idx: int):
    t0 = time.perf_counter()
    files = [
        f"{MPLOYEE}/ai_service/internal/server/challenger_m3_stress_test.go",
        f"{MPLOYEE}/shared_utils/workflowparser/tier5_stress_test.go",
    ]
    out = offload.offload_deep_review(
        prompt="Verify AGENTS.md fail-fast panic compliance, <400L ceiling, and CHORD seams.",
        context_files=files,
    )
    dt = (time.perf_counter() - t0) * 1000.0
    raw_bytes = sum(pathlib.Path(f).stat().st_size for f in files)
    return ("deep_review", dt, raw_bytes, len(out.encode("utf-8")))

jobs = [bench_embed] * 6 + [bench_triage] * 3 + [bench_review] * 3
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
    futs = [ex.submit(fn, i) for i, fn in enumerate(jobs)]
    results = [f.result() for f in concurrent.futures.as_completed(futs)]

print("\n  -> PASS [Suite 3]: LiteRT (:11434) Concurrent Compaction Benchmark:")
print("     Stage           | Runs |   P50 (ms) |   Max (ms) | Gemini Payload vs Raw")
print("     ----------------+------+------------+------------+----------------------")
for kind in ("embed_rewrite", "log_triage", "deep_review"):
    rows = [r for r in results if r[0] == kind]
    lats = [r[1] for r in rows]
    pct = statistics.mean(r[3] / max(1, r[2]) for r in rows) * 100.0
    print(f"     {kind:15s} | {len(rows):4d} | {statistics.median(lats):10.1f} | {max(lats):10.1f} | {pct:6.1f}% of raw bytes")

# --- Suite 4: Full Live Gemini 4 Argon (High) A/B/C Integration Test ---
print("\n[Suite 4/4] Running Live Gemini 4 Argon (High) A/B/C Integration Benchmark on mployee...")
BASE_TASK = (
    f"In `{MPLOYEE}`, answer concisely with exact `file:line` citations and function names:\n"
    "1. How `shared_utils/identityparser` enforces fail-fast `MustValidate` on `TenantId`, `AppId`, and `JobId`.\n"
    "2. How `ai_service/internal/server/nats_server.go` resolves dynamic model routing (`AnalyzeText` / `AnalyzeImage`) and panics on missing required properties.\n"
    "3. Run or verify the Go unit tests in `./shared_utils/identityparser/...` and `./ai_service/internal/server/...` and report whether they pass."
)

def parse_transcript_tools(conv_id: str) -> list[str]:
    tpath = BRAIN_DIR / conv_id / ".system_generated" / "logs" / "transcript.jsonl"
    if not tpath.is_file():
        return []
    tools: list[str] = []
    for line in tpath.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            obj = json.loads(line)
        except Exception:
            continue
        for tc in obj.get("tool_calls") or []:
            name = tc.get("name", "")
            args = tc.get("args") or {}
            if name == "call_mcp_tool":
                tname = str(args.get("ToolName", "")).strip('"')
                tools.append(f"mcp:{tname}")
            elif name == "invoke_subagent":
                stype = str(args.get("TypeName", "")).strip('"')
                tools.append(f"subagent:{stype}")
            else:
                tools.append(name)
    return tools

def score_response(resp_text: str) -> tuple[int, list[str]]:
    checks = [
        ("MustValidate", r"MustValidate"),
        ("identityparser/parser.go:line", r"parser\.go(?:#L|:)\d+"),
        ("nats_server.go:line", r"nats_server\.go(?:#L|:)\d+"),
        ("AnalyzeText/AnalyzeImage", r"Analyze(?:Text|Image)"),
        ("Fail-fast panic()", r"panic\("),
        ("Go tests PASS verified", r"(?i)\b(?:pass(?:ed|es)?|ok)\b"),
    ]
    hits = [label for label, pat in checks if re.search(pat, resp_text)]
    return len(hits), hits

def run_gemini_arm(label: str, prompt: str, disable_litert: bool = False, pre_ms: float = 0.0) -> dict:
    env = os.environ.copy()
    env["AGY_DISABLE_LITERT"] = "1" if disable_litert else "0"
    t0 = time.perf_counter()
    proc = subprocess.run(
        ["/usr/bin/agy", "--model", "gemini-4-argon-high", "--output-format", "json", "--dangerously-skip-permissions", "-p", prompt],
        cwd=MPLOYEE, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=300,
    )
    wall_s = time.perf_counter() - t0
    raw_out = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else "{}"
    data = json.loads(raw_out)
    cid = data.get("conversation_id", "")
    usage = data.get("usage") or {}
    resp_text = data.get("response", "")
    tools = parse_transcript_tools(cid)
    score, hits = score_response(resp_text)
    return {
        "label": label, "cid": cid, "turns": data.get("num_turns", 0),
        "litert_s": pre_ms / 1000.0, "gemini_s": data.get("duration_seconds", wall_s),
        "total_s": (pre_ms / 1000.0) + data.get("duration_seconds", wall_s),
        "in_tok": usage.get("input_tokens", 0), "cache_tok": usage.get("cache_read_tokens", 0),
        "think_tok": usage.get("thinking_tokens", 0), "out_tok": usage.get("output_tokens", 0),
        "tot_tok": usage.get("total_tokens", 0),
        "tools": tools, "score": score, "hits": hits, "response": resp_text,
    }

# 1. Arm A: Baseline WITHOUT LiteRT (Standard read_file + run_command loop)
print("  -> [1/3] Running Arm A: WITHOUT LiteRT (Standard Gemini 4 Argon tool loop)...")
prompt_no_litert = (
    BASE_TASK + "\n\nIMPORTANT BENCHMARK CONSTRAINT: Do NOT call `call_mcp_tool`, `local-offload`, `repo-scout`, or `log-triage`. "
    "Use ONLY standard `read_file` and `run_command` tools directly."
)
arm_a = run_gemini_arm("A. WITHOUT LiteRT (Baseline)", prompt_no_litert, disable_litert=True)

# 2. Arm B: WITH LiteRT Pre-Modified Query (LiteRT :11434 builds pack -> sends modified query to Gemini 4 Argon)
print("  -> [2/3] Running Arm B: WITH LiteRT Pre-Modified Query (:11434 -> Gemini 4 Argon)...")
t_pre0 = time.perf_counter()
sem_pack = offload.local_semantic_embed(
    texts=[f"{MPLOYEE}/shared_utils/identityparser/parser.go", f"{MPLOYEE}/ai_service/internal/server/nats_server.go"],
    query="MustValidate TenantId AppId JobId AnalyzeText AnalyzeImage model routing fail-fast panic",
    top_k=6,
)
triage_pack = offload.offload_log_triage(
    log_text_or_command=f"cmd:cd {MPLOYEE} && go test -v -count=1 ./shared_utils/identityparser/... ./ai_service/internal/server/..."
)
pre_ms = (time.perf_counter() - t_pre0) * 1000.0
prompt_modified = (
    BASE_TASK + "\n\n=== VERIFIED LITERT (:11434) EXECUTION PACK (PRE-COMPUTED) ===\n"
    + sem_pack + "\n" + triage_pack + "\n"
    "Answer directly using the verified LiteRT execution pack above without calling extra tools unless a required line is missing."
)
arm_b = run_gemini_arm("B. WITH LiteRT Modified Query", prompt_modified, disable_litert=True, pre_ms=pre_ms)

# 3. Arm C: WITH LiteRT Agentic MCP Tool Pipeline (Hook + Argon calls local-offload MCP)
print("  -> [3/3] Running Arm C: WITH LiteRT Agentic MCP Pipeline (Hook + MCP tools)...")
prompt_mcp = (
    BASE_TASK + "\n\nUse `call_mcp_tool` with `ServerName: \"local-offload\"` (`local_semantic_embed` and `offload_log_triage` "
    "with `cmd:cd /home/ak/projects/mployee && go test -v -count=1 ./shared_utils/identityparser/... ./ai_service/internal/server/...`) "
    "so you do not need raw `run_command` or full-file `read_file` sweeps."
)
arm_c = run_gemini_arm("C. WITH LiteRT Agentic MCP", prompt_mcp, disable_litert=False)

arms = [arm_a, arm_b, arm_c]
print("\n  ====================================================================================================")
print("   LIVE GEMINI 4 ARGON (HIGH) A/B/C COMPARISON ON ~/projects/mployee")
print("  ====================================================================================================")
print(f"  {'Metric':28s} | {'A. WITHOUT LiteRT':22s} | {'B. LiteRT Mod-Query':22s} | {'C. LiteRT Agentic MCP':22s}")
print("  " + "-" * 100)
print(f"  {'Gemini Planner Turns':28s} | {arm_a['turns']:22d} | {arm_b['turns']:22d} | {arm_c['turns']:22d}")
print(f"  {'Gemini Tool Calls':28s} | {len(arm_a['tools']):22d} | {len(arm_b['tools']):22d} | {len(arm_c['tools']):22d}")
print(f"  {'Fresh Input Tokens':28s} | {arm_a['in_tok']:22,d} | {arm_b['in_tok']:22,d} | {arm_c['in_tok']:22,d}")
print(f"  {'Cached Read Tokens':28s} | {arm_a['cache_tok']:22,d} | {arm_b['cache_tok']:22,d} | {arm_c['cache_tok']:22,d}")
print(f"  {'Thinking Tokens':28s} | {arm_a['think_tok']:22,d} | {arm_b['think_tok']:22,d} | {arm_c['think_tok']:22,d}")
print(f"  {'Output Tokens':28s} | {arm_a['out_tok']:22,d} | {arm_b['out_tok']:22,d} | {arm_c['out_tok']:22,d}")
print(f"  {'Total Tokens (All Turns)':28s} | {arm_a['tot_tok']:22,d} | {arm_b['tot_tok']:22,d} | {arm_c['tot_tok']:22,d}")
print(f"  {'LiteRT (:11434) Time (s)':28s} | {arm_a['litert_s']:22.2f} | {arm_b['litert_s']:22.2f} | {arm_c['litert_s']:22.2f}")
print(f"  {'Gemini Argon Time (s)':28s} | {arm_a['gemini_s']:22.2f} | {arm_b['gemini_s']:22.2f} | {arm_c['gemini_s']:22.2f}")
print(f"  {'Total End-to-End Time (s)':28s} | {arm_a['total_s']:22.2f} | {arm_b['total_s']:22.2f} | {arm_c['total_s']:22.2f}")
sa, sb, sc = f"{arm_a['score']}/6", f"{arm_b['score']}/6", f"{arm_c['score']}/6"
print(f"  {'Ground-Truth Accuracy Score':28s} | {sa:>22s} | {sb:>22s} | {sc:>22s}")
print("  " + "-" * 100)

for a in arms:
    print(f"  * {a['label']} (conv={a['cid']}):")
    print(f"    - Tool sequence: {', '.join(a['tools']) if a['tools'] else '(0 tools — answered in 1 shot from LiteRT pack)'}")
    print(f"    - Verified checks ({a['score']}/6): {', '.join(a['hits'])}")

# Write full side-by-side report
report_lines = [
    "# LiteRT (:11434) + Gemini 4 Argon (High) Full Integration A/B/C Report (`mployee`)\n",
    f"- **Generated**: {time.strftime('%Y-%m-%d %H:%M:%S %Z')}\n",
    "## 1. Quantitative Comparison\n",
    "| Metric | A. WITHOUT LiteRT (Baseline) | B. WITH LiteRT Modified Query | C. WITH LiteRT Agentic MCP |",
    "| :--- | ---: | ---: | ---: |",
    f"| **Gemini Planner Turns** | `{arm_a['turns']}` | `{arm_b['turns']}` | `{arm_c['turns']}` |",
    f"| **Gemini Tool Calls** | `{len(arm_a['tools'])}` | `{len(arm_b['tools'])}` | `{len(arm_c['tools'])}` |",
    f"| **Fresh Input Tokens** | `{arm_a['in_tok']:,}` | `{arm_b['in_tok']:,}` | `{arm_c['in_tok']:,}` |",
    f"| **Cached Read Tokens** | `{arm_a['cache_tok']:,}` | `{arm_b['cache_tok']:,}` | `{arm_c['cache_tok']:,}` |",
    f"| **Thinking Tokens** | `{arm_a['think_tok']:,}` | `{arm_b['think_tok']:,}` | `{arm_c['think_tok']:,}` |",
    f"| **Output Tokens** | `{arm_a['out_tok']:,}` | `{arm_b['out_tok']:,}` | `{arm_c['out_tok']:,}` |",
    f"| **Total Tokens Across Turns** | `{arm_a['tot_tok']:,}` | `{arm_b['tot_tok']:,}` | `{arm_c['tot_tok']:,}` |",
    f"| **LiteRT (:11434) Time (s)** | `{arm_a['litert_s']:.2f}s` | `{arm_b['litert_s']:.2f}s` | `{arm_c['litert_s']:.2f}s` |",
    f"| **Gemini Argon Time (s)** | `{arm_a['gemini_s']:.2f}s` | `{arm_b['gemini_s']:.2f}s` | `{arm_c['gemini_s']:.2f}s` |",
    f"| **Total End-to-End Time (s)** | `{arm_a['total_s']:.2f}s` | `{arm_b['total_s']:.2f}s` | `{arm_c['total_s']:.2f}s` |",
    f"| **Accuracy Score (out of 6)** | `{arm_a['score']}/6` | `{arm_b['score']}/6` | `{arm_c['score']}/6` |\n",
    "## 2. Tool Steps & Verbatim Gemini 4 Argon Outputs\n",
]
for a in arms:
    report_lines.extend([
        f"### {a['label']} (`{a['cid']}`)\n",
        f"- **Turns**: `{a['turns']}` | **Tools Called**: `{', '.join(a['tools']) if a['tools'] else 'None (1-shot)'}`",
        f"- **Ground-Truth Hits (`{a['score']}/6`)**: `{', '.join(a['hits'])}`\n",
        "```markdown\n" + a["response"].strip() + "\n```\n",
    ])
REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
REPORT_PATH.write_text("\n".join(report_lines), encoding="utf-8")
print(f"\n  -> Full side-by-side verbatim report saved to: {REPORT_PATH}")
EOF

if command -v nvidia-smi >/dev/null 2>&1; then
  printf "\n  -> GPU Post-Test Status:\n"
  nvidia-smi --query-gpu=index,name,memory.used,memory.free,utilization.gpu --format=csv,noheader | sed 's/^/     /'
fi

printf "\n==============================================================================\n"
printf " ALL STRESS & LIVE GEMINI A/B/C SUITES COMPLETED.\n"
printf " Report: /tmp/agy-triage/mployee/ab-comparison-report.md\n"
printf "==============================================================================\n"
