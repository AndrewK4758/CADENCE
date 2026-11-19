#!/usr/bin/env python3
"""CADENCE Stop-hook turn logger and secret scrubber for external training logs."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

_HOOK_DIR = str(pathlib.Path(__file__).resolve().parent)
if _HOOK_DIR not in sys.path:
    sys.path.insert(0, _HOOK_DIR)

from cadence_turn_parsers import (  # noqa: E402
    cap_text,
    extract_cadence_context,
    extract_gate_signals,
    parse_antigravity_steps,
    parse_claude_rows,
    strip_user_wrapper,
)

SCHEMA_VERSION = "cadence-turn-log/v1"
CLIENT_SCOPE_RE = re.compile(
    r"(?:^|[-_/.])(cook[-_]?and[-_]?james|grec|csccg|whitaker(?:[-_]?company)?|"
    r"workfast|builders|ideus|askdilly|artera|square[-_]?1[-_]?art|"
    r"tsoa|treg|beach[-_]?house|btg[-_]?internal)(?:$|[-_/.])",
    re.I,
)
SECRET_RULES: tuple[tuple[re.Pattern[str], Any], ...] = (
    (re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"), "[REDACTED:PRIVATE_KEY]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"), "[REDACTED:GITHUB_TOKEN]"),
    (re.compile(r"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}\b"), "[REDACTED:API_KEY]"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{28,}\b"), "[REDACTED:GOOGLE_API_KEY]"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED:AWS_KEY]"),
    (re.compile(r"\bperm[:-][A-Za-z0-9.=_-]{12,}\b"), "[REDACTED:YOUTRACK_TOKEN]"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), "[REDACTED:SLACK_TOKEN]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"), "[REDACTED:JWT]"),
    (re.compile(r"(?i)(Authorization\s*:\s*(?:Bearer|Basic)\s+)(?!\[REDACTED:)[^\s'\",;\r\n]+"), r"\1[REDACTED:AUTH_TOKEN]"),
    (re.compile(r"(?i)(\bBearer\s+)(?!\[REDACTED:)[A-Za-z0-9._~+/=-]{12,}"), r"\1[REDACTED:AUTH_TOKEN]"),
    (re.compile(r"(https?://[^/\s:@]+:)(?!\[REDACTED:)[^/\s@]+(@)"), r"\1[REDACTED:URL_PASS]\2"),
    (re.compile(r"(?i)(\b[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|PAT|CREDENTIAL)\s*[:=]\s*['\"]?)(?!\[REDACTED:)[^\s'\"`\r\n]{8,}(['\"]?)"), r"\1[REDACTED:ENV_SECRET]\2"),
)


def default_log_dir() -> pathlib.Path:
    """Return the external directory where CADENCE turn logs are stored."""
    return pathlib.Path(os.environ.get("CADENCE_TURN_LOG_DIR") or "~/.local/share/cadence-turn-logs").expanduser()


def default_max_tool_chars() -> int:
    """Return max tool content length captured per message."""
    try:
        return max(512, int(os.environ.get("CADENCE_TURN_LOG_MAX_TOOL_CHARS", "65536")))
    except ValueError:
        return 65536


def _chmod_safe(path: pathlib.Path, mode: int) -> None:
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def ensure_private_dir(path: pathlib.Path) -> None:
    """Create directories and enforce 0700 owner-only permissions."""
    path.mkdir(parents=True, exist_ok=True)
    _chmod_safe(path, 0o700)


def write_private_file(path: pathlib.Path, content: str, append: bool = False) -> None:
    """Write or append UTF-8 text with 0600 permissions."""
    ensure_private_dir(path.parent)
    flags = os.O_WRONLY | os.O_CREAT | (os.O_APPEND if append else os.O_TRUNC)
    fd = os.open(str(path), flags, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
    finally:
        _chmod_safe(path, 0o600)


def redact_secrets(text: str, extra_literals: tuple[str, ...] = ()) -> tuple[str, int]:
    """Scrub secret tokens, private keys, credentials, and env literals from text."""
    hits = 0
    out = text
    for pat, repl in SECRET_RULES:
        out, n = pat.subn(repl, out)
        hits += n
    for lit in extra_literals:
        if lit and len(lit) >= 8 and lit in out:
            hits += out.count(lit)
            out = out.replace(lit, "[REDACTED:ENV_LITERAL]")
    return out, hits


def redact_obj(obj: Any, extra_literals: tuple[str, ...] = ()) -> tuple[Any, int]:
    """Recursively redact secrets across nested JSON-compatible structures."""
    if isinstance(obj, str):
        return redact_secrets(obj, extra_literals)
    if isinstance(obj, list):
        total, items = 0, []
        for item in obj:
            v, n = redact_obj(item, extra_literals)
            items.append(v)
            total += n
        return items, total
    if isinstance(obj, dict):
        total, res = 0, {}
        for k, v in obj.items():
            nv, n = redact_obj(v, extra_literals)
            res[k] = nv
            total += n
        return res, total
    return obj, 0


def is_cadence_repo(repo_root: pathlib.Path) -> bool:
    """Return True if repo_root contains canonical CADENCE governance markers."""
    markers = (
        "CADENCE_DIRECTIVES.md",
        "processes/CADENCE_DIRECTIVES.md",
        "docs/agentic-sdlc/CADENCE_ORG.md",
        "processes/docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md",
    )
    return any((repo_root / m).is_file() for m in markers)


def _git_out(repo_root: pathlib.Path, args: list[str]) -> str:
    try:
        r = subprocess.run(["git", "-C", str(repo_root), *args], capture_output=True, text=True, timeout=3)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def find_repo_root(path_hint: str) -> pathlib.Path | None:
    """Resolve git top-level root for path_hint (existing or pending leaf under an existing dir)."""
    if not path_hint:
        return None
    p = pathlib.Path(os.path.abspath(os.path.expanduser(path_hint)))
    while not p.exists() and p != p.parent:
        p = p.parent
    if p.is_file():
        p = p.parent
    if not p.is_dir():
        return None
    top = _git_out(p, ["rev-parse", "--show-toplevel"])
    return pathlib.Path(top).resolve() if top else None


def resolve_repo_meta(repo_root: pathlib.Path, log_dir: pathlib.Path | None = None) -> dict[str, Any]:
    """Derive normalized repo slug and confidentiality defaults; preserve explicit tags."""
    remote = _git_out(repo_root, ["remote", "get-url", "origin"])
    remote_host, remote_slug = "", ""
    if remote:
        m = re.match(r"^(?:git@([^:]+):|https?://(?:[^@]+@)?([^/]+)/)(.+?)(?:\.git)?$", remote)
        if m:
            remote_host = m.group(1) or m.group(2) or ""
            remote_slug = (m.group(3) or "").strip("/")
    raw_slug = remote_slug.replace("/", "__") if remote_slug else repo_root.name
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", raw_slug).strip("-") or "repo"
    cm = CLIENT_SCOPE_RE.search(str(repo_root)) or CLIENT_SCOPE_RE.search(remote_slug)
    env_scope = os.environ.get("CADENCE_TURN_LOG_SCOPE", "").strip()
    if env_scope in {"public-eligible", "private", "client-restricted"}:
        conf = env_scope
    else:
        conf = "client-restricted" if cm else "private"
    meta = {
        "schema_version": SCHEMA_VERSION,
        "repo_slug": slug,
        "repo_name": repo_root.name,
        "remote_host": remote_host,
        "remote_slug": remote_slug,
        "confidentiality": conf,
        "client_tag": cm.group(1).lower().replace("_", "-") if cm else "",
    }
    if log_dir and (meta_path := log_dir / "repos" / slug / "repo.meta.json").is_file():
        try:
            existing = json.loads(meta_path.read_text(encoding="utf-8"))
            for key in ("confidentiality", "client_tag"):
                if key in existing:
                    meta[key] = existing[key]
        except Exception:
            pass
    return meta


def build_and_append_turn(
    log_dir: pathlib.Path,
    repo_root: pathlib.Path,
    harness: str,
    session_id: str,
    turn_seq: int,
    step_range: list[int],
    messages: list[dict[str, Any]],
    models: list[str],
    usage: dict[str, int],
    timestamp: str = "",
    extra_literals: tuple[str, ...] = (),
) -> tuple[bool, int, str]:
    """Build normalized turn record, scrub secrets, dedup by record_id, and append JSONL."""
    if not messages or not any(m.get("role") == "assistant" for m in messages):
        return False, 0, ""
    meta = resolve_repo_meta(repo_root, log_dir)
    repo_slug = meta["repo_slug"]
    safe_sid = re.sub(r"[^A-Za-z0-9._-]+", "_", session_id or "default")
    branch = _git_out(repo_root, ["branch", "--show-current"])
    head_sha = _git_out(repo_root, ["rev-parse", "HEAD"])
    tickets, skills, subagents = extract_cadence_context(messages, repo_root, branch)
    gates, outcome, latest_cycle = extract_gate_signals(messages, repo_root, tickets)
    rid_seed = f"{harness}:{repo_slug}:{safe_sid}:{step_range[0]}-{step_range[1]}"
    record_id = hashlib.sha256(rid_seed.encode("utf-8")).hexdigest()[:24]
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ym = (timestamp or now_iso)[:7]
    if not re.match(r"^\d{4}-\d{2}$", ym):
        ym = now_iso[:7]
    repo_dir = log_dir / "repos" / repo_slug
    out_file = repo_dir / ym / f"{safe_sid}.turns.jsonl"
    state_file = log_dir / ".state" / f"{repo_slug}__{safe_sid}.cursor.json"
    state: dict[str, Any] = {}
    if state_file.is_file():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:
            state = {}
    seen_ids = set(state.get("seen_record_ids") or [])
    if record_id in seen_ids:
        return False, 0, repo_slug
    rec = {
        "schema_version": SCHEMA_VERSION,
        "record_id": record_id,
        "recorded_at": now_iso,
        "turn_timestamp": timestamp or now_iso,
        "harness": harness,
        "session_id": session_id,
        "turn_seq": turn_seq,
        "step_range": step_range,
        "models": models,
        "token_usage": usage,
        "repo": {"slug": repo_slug, "name": meta["repo_name"], "confidentiality": meta["confidentiality"], "client_tag": meta["client_tag"]},
        "git": {"branch": branch, "head_sha": head_sha},
        "cadence": {"tickets": tickets, "skills": skills, "subagents": subagents, "gates": gates, "latest_review_cycle": latest_cycle, "turn_outcome": outcome},
        "messages": messages,
    }
    clean_rec, redactions = redact_obj(rec, extra_literals)
    clean_rec["redactions"] = redactions
    if not (meta_path := repo_dir / "repo.meta.json").is_file():
        write_private_file(meta_path, json.dumps(meta, indent=2) + "\n")
    write_private_file(out_file, json.dumps(clean_rec, ensure_ascii=False) + "\n", append=True)
    seen_ids.add(record_id)
    state["seen_record_ids"] = sorted(seen_ids)[-500:]
    state["turn_seq"] = max(int(state.get("turn_seq") or 0), turn_seq)
    state["last_step"] = step_range[1]
    write_private_file(state_file, json.dumps(state, indent=2) + "\n")
    return True, redactions, repo_slug


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    is_agy = any(k in payload for k in ("terminationReason", "continuationActive", "executionNum", "conversationId"))
    if is_agy and payload.get("terminationReason") not in (None, "", "NO_TOOL_CALL"):
        return 0
    wps = payload.get("workspacePaths") or []
    cwd = (wps[0] if isinstance(wps, list) and wps else "") or payload.get("cwd") or ""
    repo_root = find_repo_root(str(cwd))
    if not repo_root or not is_cadence_repo(repo_root):
        return 0
    raw_tp = payload.get("transcriptPath") or payload.get("transcript_path") or ""
    if not raw_tp:
        return 0
    tp = pathlib.Path(raw_tp).expanduser()
    if (full_tp := tp.parent / "transcript_full.jsonl").is_file():
        tp = full_tp
    if not tp.is_file():
        return 0
    sid = str(payload.get("conversationId") or payload.get("session_id") or tp.stem)
    safe_sid = re.sub(r"[^A-Za-z0-9._-]+", "_", sid)
    log_dir = default_log_dir()
    repo_slug = resolve_repo_meta(repo_root, log_dir)["repo_slug"]
    state_file = log_dir / ".state" / f"{repo_slug}__{safe_sid}.cursor.json"
    last_step, prev_seq = -1, 0
    if state_file.is_file():
        try:
            st = json.loads(state_file.read_text(encoding="utf-8"))
            last_step, prev_seq = int(st.get("last_step", -1)), int(st.get("turn_seq", 0))
        except Exception:
            pass
    lines = [l for l in tp.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip()]
    max_chars = default_max_tool_chars()
    if is_agy:
        steps = [json.loads(l) for l in lines]
        last_ui = max((i for i, s in enumerate(steps) if s.get("type") == "USER_INPUT" and s.get("source") == "USER_EXPLICIT"), default=-1)
        if last_ui < 0:
            return 0
        slice_steps = [s for s in steps[last_ui:] if int(s.get("step_index", 0)) > last_step] if last_step >= steps[last_ui].get("step_index", 0) else steps[last_ui:]
        if not any(s.get("type") == "PLANNER_RESPONSE" for s in slice_steps):
            return 0
        if slice_steps[0].get("type") != "USER_INPUT":
            slice_steps = [steps[last_ui]] + slice_steps
        s0, s1 = int(slice_steps[0].get("step_index", 0)), int(slice_steps[-1].get("step_index", 0))
        msgs, models, usage = parse_antigravity_steps(slice_steps, max_chars)
        build_and_append_turn(log_dir, repo_root, "antigravity", sid, prev_seq + 1, [s0, s1], msgs, models, usage, str(slice_steps[0].get("created_at") or ""))
    else:
        rows = [json.loads(l) for l in lines]
        last_ui = max((i for i, r in enumerate(rows) if r.get("type") == "user" and isinstance((r.get("message") or {}).get("content"), str) and not r.get("isMeta")), default=-1)
        if last_ui < 0 or (len(rows) - 1) <= last_step:
            return 0
        slice_rows = rows[last_ui:] if last_ui > last_step else [rows[last_ui]] + rows[last_step + 1 :]
        if not any(r.get("type") == "assistant" for r in slice_rows):
            return 0
        msgs, models, usage = parse_claude_rows(slice_rows, max_chars)
        build_and_append_turn(log_dir, repo_root, "claude-code", sid, prev_seq + 1, [last_ui, len(rows) - 1], msgs, models, usage, str(slice_rows[0].get("timestamp") or ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
