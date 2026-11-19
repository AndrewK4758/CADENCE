#!/usr/bin/env bash
# Offline regression suite (T11) for cadence-turn-logger.sh Stop hook and /cadence-trainlog.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$ROOT/hooks/cadence-turn-logger.sh"
CLI="$ROOT/skills/cadence-trainlog/trainlog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/cadence-app"
CL_REPO="$TMP/cook-and-james-portal"
NON_REPO="$TMP/plain-git"
LOGDIR="$TMP/turn-logs"
export CADENCE_TURN_LOG_DIR="$LOGDIR"
export HOME="$TMP/fakehome"
mkdir -p "$HOME"

bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$REPO" >/dev/null
git -C "$REPO" checkout -q -b impl/feat/ACME-201

cp -R "$REPO" "$CL_REPO"
mkdir -p "$NON_REPO"
git -C "$NON_REPO" init -q
git -C "$NON_REPO" -c user.name=Test -c user.email=test@example.com commit --allow-empty -q -m "init"

mkdir -p "$TMP/agy/conv1" "$TMP/claude" "$TMP/ingest_agy/c2/.system_generated/logs" "$TMP/ingest_claude/proj" "$TMP/ingest_blitz"

# Build synthetic Antigravity transcript_full (Turn 1 -> fail, later append Turn 2 -> pass)
python3 -B - "$TMP/agy/conv1/transcript_full.jsonl" <<'PY'
import json, sys
rows = [
    {"step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "created_at": "2026-11-19T10:00:00Z", "content": "<USER_REQUEST>\nVerify ACME-201 in repo\n</USER_REQUEST>"},
    {"step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-11-19T10:00:01Z", "model": "test-model-a", "input_tokens": 100, "cache_read_tokens": 20, "output_tokens": 30, "thinking": "check gate", "tool_calls": [{"name": "run_command", "args": {"CommandLine": "certainty-gate.sh ACME-201"}}]},
    {"step_index": 2, "source": "MODEL", "type": "GENERIC", "created_at": "2026-11-19T10:00:02Z", "content": "Command exited with code 1\ndecision=HALT"},
    {"step_index": 3, "source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-11-19T10:00:03Z", "model": "test-model-a", "output_tokens": 12, "content": "Gate halted"},
]
with open(sys.argv[1], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY

AGY_PL="$(python3 -B -c 'import json,sys; print(json.dumps({"conversationId":"conv1","workspacePaths":[sys.argv[1]],"transcriptPath":sys.argv[2],"terminationReason":"NO_TOOL_CALL"}))' "$REPO" "$TMP/agy/conv1/transcript.jsonl")"

# 1. Antigravity Stop hook captures Turn 1 & emits allow
out1="$(printf '%s' "$AGY_PL" | bash "$HOOK")"
[[ "$out1" == '{"decision":"allow"}' ]]

# 2. Cursor idempotency (repeat fires 0 writes; Turn 2 writes turn_seq=2)
before_cnt="$(cat "$LOGDIR"/repos/*/*/*.turns.jsonl | wc -l)"
[[ "$before_cnt" -eq 1 ]]
printf '%s' "$AGY_PL" | bash "$HOOK" >/dev/null
[[ "$(cat "$LOGDIR"/repos/*/*/*.turns.jsonl | wc -l)" -eq 1 ]]

python3 -B - "$TMP/agy/conv1/transcript_full.jsonl" <<'PY'
import json, sys
rows = [
    {"step_index": 4, "source": "USER_EXPLICIT", "type": "USER_INPUT", "created_at": "2026-11-19T10:05:00Z", "content": "Verify ACME-201 in repo"},
    {"step_index": 5, "source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-11-19T10:05:01Z", "model": "test-model-a", "input_tokens": 120, "output_tokens": 25, "thinking": "recheck", "tool_calls": [{"name": "run_command", "args": {"CommandLine": "certainty-gate.sh ACME-201"}}]},
    {"step_index": 6, "source": "MODEL", "type": "GENERIC", "created_at": "2026-11-19T10:05:02Z", "content": "Command exited with code 0\ndecision=PROCEED"},
    {"step_index": 7, "source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-11-19T10:05:03Z", "model": "test-model-a", "output_tokens": 15, "content": "All green"},
]
with open(sys.argv[1], "a") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
printf '%s' "$AGY_PL" | bash "$HOOK" >/dev/null
[[ "$(cat "$LOGDIR"/repos/*/*/*.turns.jsonl | wc -l)" -eq 2 ]]

# 3. Claude Code Stop hook + 4. Secret redaction + 0600/0700 perms
python3 -B - "$TMP/claude/cc1.jsonl" "$REPO" <<'PY'
import json, sys
sec_lines = "\n".join([
    "gh" + "p_" + "A" * 28,
    "sk-" + "B" * 24,
    "AIza" + "C" * 32,
    "perm-" + "D" * 24,
    "Bearer " + "E" * 20,
    "https://user:" + "MyPass999" + "@git.example.com/r.git",
    "MY_API_KEY=" + "SecretValue12345",
    "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJ\n-----END RSA PRIVATE KEY-----",
])
rows = [
    {"type": "user", "cwd": sys.argv[2], "sessionId": "cc-1", "timestamp": "2026-11-19T11:00:00Z", "message": {"role": "user", "content": "Review ACME-201 secrets:\n" + sec_lines}},
    {"type": "assistant", "cwd": sys.argv[2], "sessionId": "cc-1", "timestamp": "2026-11-19T11:00:02Z", "message": {"model": "claude-test", "usage": {"input_tokens": 10, "output_tokens": 8}, "content": [{"type": "thinking", "thinking": "run escalate"}, {"type": "tool_use", "id": "tu1", "name": "Bash", "input": {"command": "certainty-gate.sh ACME-201"}}]}},
    {"type": "user", "cwd": sys.argv[2], "sessionId": "cc-1", "timestamp": "2026-11-19T11:00:03Z", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "tu1", "content": "Command exited with code 2\ndecision=ESCALATE_HUMAN"}]}},
    {"type": "assistant", "cwd": sys.argv[2], "sessionId": "cc-1", "timestamp": "2026-11-19T11:00:04Z", "message": {"model": "claude-test", "usage": {"input_tokens": 5, "output_tokens": 4}, "content": [{"type": "text", "text": "Escalated to human"}]}},
]
with open(sys.argv[1], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
CC_PL="$(python3 -B -c 'import json,sys; print(json.dumps({"session_id":"cc-1","cwd":sys.argv[1],"transcript_path":sys.argv[2],"stop_hook_active":False}))' "$REPO" "$TMP/claude/cc1.jsonl")"
out_cc="$(printf '%s' "$CC_PL" | bash "$HOOK")"
[[ "$out_cc" == '{}' ]]

python3 -B - "$LOGDIR" <<'PY'
import glob, json, os, stat, sys
logdir = sys.argv[1]
files = glob.glob(f"{logdir}/repos/*/*/*.turns.jsonl")
assert len(files) == 2, files
for f in files:
    mode = stat.S_IMODE(os.stat(f).st_mode)
    assert mode == 0o600, oct(mode)
    txt = open(f).read()
    for bad in ("gh" + "p_AAAA", "sk-BBBB", "AIzaCCCC", "perm-DDDD", "Bearer EEEE", "MyPass999", "SecretValue12345", "MIIBOgIBAAJ"):
        assert bad not in txt, f"secret leaked: {bad}"
dmode = stat.S_IMODE(os.stat(logdir + "/repos/cadence-app").st_mode)
assert dmode == 0o700, oct(dmode)
PY

# 5. Opt-out & non-CADENCE git repo are silent no-ops
AGY_OPT="$(python3 -B -c 'import json,sys; print(json.dumps({"conversationId":"conv-non","workspacePaths":[sys.argv[1]],"transcriptPath":sys.argv[2],"terminationReason":"NO_TOOL_CALL"}))' "$NON_REPO" "$TMP/agy/conv1/transcript.jsonl")"
out_non="$(printf '%s' "$AGY_OPT" | bash "$HOOK")"
[[ "$out_non" == '{"decision":"allow"}' ]]
AGY_OFF="$(python3 -B -c 'import json,sys; print(json.dumps({"conversationId":"conv-off","workspacePaths":[sys.argv[1]],"transcriptPath":sys.argv[2],"terminationReason":"NO_TOOL_CALL"}))' "$REPO" "$TMP/agy/conv1/transcript.jsonl")"
out_off="$(printf '%s' "$AGY_OFF" | CADENCE_TURN_LOG=0 bash "$HOOK")"
[[ "$out_off" == '{"decision":"allow"}' ]]
[[ "$(cat "$LOGDIR"/repos/cadence-app/*/*.turns.jsonl | wc -l)" -eq 3 ]]
[[ ! -e "$LOGDIR"/repos/cadence-app/2026-11/conv-off.turns.jsonl ]]
[[ ! -d "$LOGDIR/repos/plain-git" ]]

# 6. Verify deterministic gate outcomes (gate_failed + verified_pass + escalated_human)
python3 -B - "$LOGDIR/repos/cadence-app" <<'PY'
import glob, json, sys
recs = []
for f in sorted(glob.glob(f"{sys.argv[1]}/*/*.turns.jsonl")):
    recs.extend(json.loads(l) for l in open(f))
outcomes = sorted(r["cadence"]["turn_outcome"] for r in recs)
assert outcomes == ["escalated_human", "gate_failed", "verified_pass"], outcomes
PY

# 7. Multi-harness historical ingest (agy + claude + blitz) against client-named repo & non-cadence skip
python3 -B - "$TMP" "$CL_REPO" "$NON_REPO" <<'PY'
import json, pathlib, sys
tmp, cl, non = map(pathlib.Path, sys.argv[1:])
with open(tmp / "ingest_agy/c2/.system_generated/logs/transcript_full.jsonl", "w") as f:
    for r in [
        {"step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "created_at": "2026-11-19T12:00:00Z", "content": f"Check {cl}/README.md"},
        {"step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "created_at": "2026-11-19T12:00:01Z", "model": "m", "content": "Done"},
    ]:
        f.write(json.dumps(r) + "\n")
with open(tmp / "ingest_claude/proj/s2.jsonl", "w") as f:
    for r in [
        {"type": "user", "cwd": str(cl), "sessionId": "cl-s2", "timestamp": "2026-11-19T12:01:00Z", "message": {"role": "user", "content": "Hi"}},
        {"type": "assistant", "cwd": str(cl), "sessionId": "cl-s2", "timestamp": "2026-11-19T12:01:01Z", "message": {"model": "m", "usage": {}, "content": [{"type": "text", "text": "Ok"}]}},
    ]:
        f.write(json.dumps(r) + "\n")
(tmp / "ingest_blitz/session-1.meta.json").write_text(json.dumps({"id": "b1", "workspace": str(cl), "model": "qwen", "usage": {"input": 5, "output": 5}}))
(tmp / "ingest_blitz/session-1.jsonl").write_text(json.dumps({"role": "user", "content": "Hi", "timestamp": "2026-11-19T12:02:00Z"}) + "\n" + json.dumps({"role": "model", "content": "Hi there", "timestamp": "2026-11-19T12:02:01Z"}) + "\n")
(tmp / "ingest_blitz/session-2.meta.json").write_text(json.dumps({"id": "b2", "workspace": str(non), "model": "qwen"}))
(tmp / "ingest_blitz/session-2.jsonl").write_text(json.dumps({"role": "user", "content": "Skip"}) + "\n" + json.dumps({"role": "model", "content": "No"}) + "\n")
PY
ing_out="$(bash "$CLI" ingest --source all --log-dir "$LOGDIR" --agy-dir "$TMP/ingest_agy" --claude-dir "$TMP/ingest_claude" --blitz-dir "$TMP/ingest_blitz")"
grep -q 'TOTAL ingested=3 skipped_duplicate=0 skipped_non_cadence=1' <<<"$ing_out"

# 8. Export SFT / DPO / RLVR + verify + status + tag
bash "$CLI" status --log-dir "$LOGDIR" | grep -q 'cook-and-james-portal \[client-restricted client=cook-and-james\]'
bash "$CLI" export --log-dir "$LOGDIR" --format sft --repo cadence-app --only-verified --no-thinking --out "$TMP/sft.jsonl" | grep -q 'exported=1'
! grep -q 'reasoning_content' "$TMP/sft.jsonl"
bash "$CLI" export --log-dir "$LOGDIR" --format dpo --repo cadence-app --out "$TMP/dpo.jsonl" | grep -q 'exported=1'
bash "$CLI" export --log-dir "$LOGDIR" --format rlvr --repo cadence-app --out "$TMP/rlvr.jsonl" | grep -q 'exported=3'
for ds in "$TMP/sft.jsonl" "$TMP/dpo.jsonl" "$TMP/rlvr.jsonl"; do
  bash "$CLI" verify --input "$ds" | grep -q 'secrets=0'
done
bash "$CLI" tag --log-dir "$LOGDIR" --repo cadence-app --confidentiality public-eligible | grep -q 'confidentiality=public-eligible'

# 9. Chinese-wall blocks mixing different client-restricted repos (exit 2, no file created)
mkdir -p "$LOGDIR/repos/grec"
printf '{"repo_slug":"grec","confidentiality":"client-restricted","client_tag":"grec"}\n' > "$LOGDIR/repos/grec/repo.meta.json"
rc=0
bash "$CLI" export --log-dir "$LOGDIR" --format sft --allow-multi-repo --repos cook-and-james-portal,grec --out "$TMP/mixed.jsonl" 2>"$TMP/wall.err" || rc=$?
[[ "$rc" -eq 2 && ! -e "$TMP/mixed.jsonl" ]]
grep -q 'CHINESE_WALL_VIOLATION' "$TMP/wall.err"

echo "PASS: test-turn-logger (all 9 scenarios)"
