#!/usr/bin/env python3
"""Transcript parsers (Antigravity / Claude Code) and CADENCE gate extractors."""
from __future__ import annotations

import json
import pathlib
import re
from typing import Any

NON_TICKET_RE = re.compile(r"^(?:UTF|SHA|ISO|TLS|HTTP|CLM|OQ|DEC|II|PROD|ADR)-\d+$")
TICKET_RE = re.compile(r"\b([A-Z][A-Z0-9]{1,10}-\d+)\b")
SKILL_RE = re.compile(
    r"\bcadence-(?:adopt|archive|build|bump-model|certainty|close|define|doctor|"
    r"eject|elicit|housekeep|implement|interview|maintain|merge|migrate|mint|"
    r"onboard|parallel|propose|refactor|release|retro|review|spec|sync-jira|"
    r"sync-youtrack|trainlog|triage|upgrade|watch)\b"
)
SUBAGENT_RE = re.compile(
    r"\b(?:cadence-(?:architect|archivist|explorer|implementer|maintainer|"
    r"migration-author|reviewer|security-auditor|spec-author|triage-agent)|"
    r"repo-scout|log-triage)\b"
)


def cap_text(text: str, limit: int) -> str:
    """Truncate long outputs preserving head and tail context."""
    if len(text) <= limit:
        return text
    head = limit // 2
    tail = limit - head
    omitted = len(text) - head - tail
    return f"{text[:head]}\n[... truncated {omitted} chars ...]\n{text[-tail:]}"


def strip_user_wrapper(text: str) -> str:
    """Strip harness <USER_REQUEST> tags wrapping user prompts."""
    m = re.match(r"^\s*<USER_REQUEST>\s*(.*?)\s*</USER_REQUEST>\s*$", text, re.S)
    return m.group(1) if m else text


def parse_antigravity_steps(
    steps: list[dict[str, Any]], max_tool_chars: int
) -> tuple[list[dict[str, Any]], list[str], dict[str, int]]:
    """Convert Antigravity transcript_full/transcript steps into OpenAI chat messages."""
    msgs: list[dict[str, Any]] = []
    models: list[str] = []
    usage = {"input": 0, "cache_read": 0, "output": 0}
    pending_calls: list[tuple[str, str]] = []
    for st in steps:
        stype, sidx = st.get("type", ""), st.get("step_index", 0)
        if stype == "USER_INPUT" and st.get("source") == "USER_EXPLICIT":
            pending_calls.clear()
            msgs.append({"role": "user", "content": strip_user_wrapper(st.get("content") or "")})
        elif stype == "PLANNER_RESPONSE":
            pending_calls.clear()
            if (mdl := st.get("model")) and mdl not in models:
                models.append(mdl)
            for k, uk in (("input", "input_tokens"), ("cache_read", "cache_read_tokens"), ("output", "output_tokens")):
                if isinstance(st.get(uk), int):
                    usage[k] += st[uk]
            msg: dict[str, Any] = {"role": "assistant"}
            if st.get("thinking"):
                msg["reasoning_content"] = st["thinking"]
            msg["content"] = st.get("content") or None
            tcs = []
            for i, tc in enumerate(st.get("tool_calls") or []):
                cid = tc.get("id") or f"call_{sidx}_{i}"
                name = tc.get("name") or "tool"
                args = tc.get("args", {})
                arg_str = args if isinstance(args, str) else json.dumps(args, ensure_ascii=False)
                tcs.append({"id": cid, "type": "function", "function": {"name": name, "arguments": arg_str}})
                pending_calls.append((cid, name))
            if tcs:
                msg["tool_calls"] = tcs
            msgs.append(msg)
        elif stype == "GENERIC" and st.get("source") == "MODEL" and pending_calls:
            cid, name = pending_calls.pop(0)
            msgs.append({"role": "tool", "tool_call_id": cid, "name": name, "content": cap_text(str(st.get("content") or ""), max_tool_chars)})
    return msgs, models, usage


def parse_claude_rows(
    rows: list[dict[str, Any]], max_tool_chars: int
) -> tuple[list[dict[str, Any]], list[str], dict[str, int]]:
    """Convert Claude Code session JSONL rows into normalized OpenAI chat messages."""
    msgs: list[dict[str, Any]] = []
    models: list[str] = []
    usage = {"input": 0, "cache_read": 0, "output": 0}
    id_to_name: dict[str, str] = {}
    for row in rows:
        rtype, mobj = row.get("type"), row.get("message")
        if not isinstance(mobj, dict) or row.get("isMeta"):
            continue
        content = mobj.get("content")
        if rtype == "user":
            if isinstance(content, str):
                msgs.append({"role": "user", "content": content})
            elif isinstance(content, list):
                for blk in content:
                    if isinstance(blk, dict) and blk.get("type") == "tool_result":
                        tid, tc_raw = blk.get("tool_use_id") or "", blk.get("content")
                        if isinstance(tc_raw, list):
                            text = "\n".join(str(x.get("text", "")) for x in tc_raw if isinstance(x, dict))
                        else:
                            text = str(tc_raw or "")
                        msgs.append({"role": "tool", "tool_call_id": tid, "name": id_to_name.get(tid, "tool"), "content": cap_text(text, max_tool_chars)})
        elif rtype == "assistant":
            if (mdl := mobj.get("model")) and mdl not in models:
                models.append(mdl)
            if isinstance(u := mobj.get("usage"), dict):
                usage["input"] += int(u.get("input_tokens") or 0) + int(u.get("cache_creation_input_tokens") or 0)
                usage["cache_read"] += int(u.get("cache_read_input_tokens") or 0)
                usage["output"] += int(u.get("output_tokens") or 0)
            think_parts, text_parts, tcs = [], [], []
            for idx, blk in enumerate(content if isinstance(content, list) else []):
                if not isinstance(blk, dict):
                    continue
                bt = blk.get("type")
                if bt == "thinking":
                    think_parts.append(str(blk.get("thinking") or ""))
                elif bt == "text":
                    text_parts.append(str(blk.get("text") or ""))
                elif bt == "tool_use":
                    tid, name = blk.get("id") or f"call_{idx}", blk.get("name") or "tool"
                    id_to_name[tid] = name
                    tcs.append({"id": tid, "type": "function", "function": {"name": name, "arguments": json.dumps(blk.get("input", {}), ensure_ascii=False)}})
            msg: dict[str, Any] = {"role": "assistant", "content": "\n".join(text_parts) if text_parts else None}
            if think_parts:
                msg["reasoning_content"] = "\n".join(think_parts)
            if tcs:
                msg["tool_calls"] = tcs
            msgs.append(msg)
    return msgs, models, usage


def _extract_cmd(args_str: str) -> str:
    try:
        parsed = json.loads(args_str) if isinstance(args_str, str) else args_str
        if isinstance(parsed, dict):
            return str(parsed.get("CommandLine") or parsed.get("command") or parsed.get("cmd") or "")
    except Exception:
        pass
    return ""


def _parse_exit(output: str) -> int | None:
    m = re.search(r"Command exited with code (\d+)", output)
    return int(m.group(1)) if m else None


def extract_cadence_context(
    messages: list[dict[str, Any]], repo_root: pathlib.Path, branch: str
) -> tuple[list[str], list[str], list[str]]:
    """Extract referenced ticket IDs, CADENCE skills, and subagent names."""
    corpus = branch + "\n" + "\n".join(json.dumps(m, ensure_ascii=False) for m in messages)
    tickets: list[str] = []
    for t in TICKET_RE.findall(corpus):
        if NON_TICKET_RE.match(t) or t in tickets:
            continue
        if (repo_root / "specs" / t).is_dir() or (repo_root / "archive" / t).is_dir() or t in branch or len(tickets) < 4:
            tickets.append(t)
    return tickets[:12], list(dict.fromkeys(SKILL_RE.findall(corpus))), list(dict.fromkeys(SUBAGENT_RE.findall(corpus)))


def extract_gate_signals(
    messages: list[dict[str, Any]], repo_root: pathlib.Path, ticket_ids: list[str]
) -> tuple[list[dict[str, Any]], str, dict[str, Any] | None]:
    """Derive objective verification labels from tool outputs and submission.md cycles."""
    call_cmds: dict[str, str] = {}
    review_touch = False
    for m in messages:
        if m.get("role") == "assistant":
            for tc in m.get("tool_calls") or []:
                fn = tc.get("function") or {}
                args = fn.get("arguments") or ""
                if fn.get("name") in ("run_command", "Bash", "bash", "execute_terminal_command"):
                    call_cmds[tc.get("id") or ""] = _extract_cmd(args)
                if "submission.md" in str(args) or "cadence-review" in str(args):
                    review_touch = True
            if "cadence-review" in str(m.get("content") or ""):
                review_touch = True
    gates: list[dict[str, Any]] = []
    for m in messages:
        if m.get("role") != "tool":
            continue
        cmd = call_cmds.get(m.get("tool_call_id") or "", "")
        out = str(m.get("content") or "")
        rc = _parse_exit(out)
        if "certainty-gate" in cmd or "certainty_gate.py" in cmd or re.search(r"decision=(PROCEED|HALT|ESCALATE_HUMAN)\b", out):
            dm = re.search(r"decision=(PROCEED|HALT|ESCALATE_HUMAN)\b", out)
            dec = dm.group(1) if dm else ("PROCEED" if rc == 0 else ("ESCALATE_HUMAN" if rc == 2 else "HALT"))
            st = "pass" if dec == "PROCEED" and rc in (None, 0) else ("escalate" if dec == "ESCALATE_HUMAN" or rc == 2 else "fail")
            gates.append({"gate": "certainty-gate", "status": st, "decision": dec, "exit_code": rc})
        elif "run-cadence-tests.sh" in cmd or re.search(r"=== Summary:\s*(\d+)\s*passed,\s*(\d+)\s*failed", out):
            sm = re.search(r"=== Summary:\s*(\d+)\s*passed,\s*(\d+)\s*failed", out)
            st = "pass" if (sm and int(sm.group(2)) == 0 and rc in (None, 0)) else "fail"
            gates.append({"gate": "run-cadence-tests", "status": st, "exit_code": rc})
        elif "doctor.sh" in cmd or "Doctor Summary:" in out:
            dm = re.search(r"Doctor Summary:\s*\d+\s*passed,\s*\d+\s*warning\(s\),\s*(\d+)\s*failed", out)
            st = "pass" if ((dm and int(dm.group(1)) == 0) or (not dm and rc == 0)) else "fail"
            gates.append({"gate": "cadence-doctor", "status": st, "exit_code": rc})
        elif "verify-spec" in cmd or "verify-facts" in cmd or "ac-classify" in cmd:
            gname = next(x for x in ("verify-spec", "verify-facts", "ac-classify") if x in cmd)
            failed = (rc not in (None, 0)) or bool(re.search(r"\b(?:FAIL|ERROR)\b", out))
            gates.append({"gate": gname, "status": "fail" if failed else "pass", "exit_code": rc})
        elif re.search(r"\b(?:pytest|dotnet test|npm test|cargo test|go test|jest|vitest|test-[a-z0-9-]+\.sh)\b", cmd):
            failed = (rc not in (None, 0)) or bool(re.search(r"(?:^FAIL:|^\s*FAILED\b)", out, re.M))
            passed = (rc == 0) or bool(re.search(r"^PASS:", out, re.M))
            if failed or passed:
                gates.append({"gate": "test-runner", "status": "fail" if failed else "pass", "exit_code": rc})
    latest_cycle = None
    for tid in ticket_ids:
        sub = repo_root / "specs" / tid / "submission.md"
        if sub.is_file():
            matches = re.findall(r"<!--\s*cadence-run:cycle\s+(\d+)\s+blocking=(\d+)[^>]*-->", sub.read_text(encoding="utf-8", errors="replace"))
            if matches:
                cnum, blk = matches[-1]
                latest_cycle = {"ticket": tid, "cycle": int(cnum), "blocking": int(blk)}
                break
    statuses = [g["status"] for g in gates]
    if "fail" in statuses or (review_touch and latest_cycle and latest_cycle["blocking"] > 0):
        outcome = "gate_failed"
    elif "escalate" in statuses:
        outcome = "escalated_human"
    elif "pass" in statuses or (review_touch and latest_cycle and latest_cycle["blocking"] == 0):
        outcome = "verified_pass"
    else:
        outcome = "unverified"
    return gates, outcome, latest_cycle
