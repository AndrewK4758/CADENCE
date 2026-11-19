#!/usr/bin/env python3
"""Historical multi-harness CADENCE session harvester (Antigravity, Claude Code, Blitz)."""
from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

_SK_DIR = pathlib.Path(__file__).resolve().parent
_HOOKS_CANDIDATES = (
    _SK_DIR.parents[1] / "hooks",
    _SK_DIR.parents[2] / "hooks",
)
for _hc in _HOOKS_CANDIDATES:
    if (_hc / "cadence_turn_logger.py").is_file() and str(_hc) not in sys.path:
        sys.path.insert(0, str(_hc))
        break

from cadence_turn_logger import (  # noqa: E402
    build_and_append_turn,
    default_max_tool_chars,
    find_repo_root,
    is_cadence_repo,
)
from cadence_turn_parsers import (  # noqa: E402
    cap_text,
    parse_antigravity_steps,
    parse_claude_rows,
)

UNIX_PATH_RE = re.compile(r"(/[^\s'\",;:)\]}\n\r`]+)")


def load_env_literals(path: pathlib.Path | None) -> tuple[str, ...]:
    """Load non-empty secret literals (>=8 chars) from an env file without echoing them."""
    if not path or not path.is_file():
        return ()
    lits: list[str] = []
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[7:].strip()
        _, val = line.split("=", 1)
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
            val = val[1:-1]
        if len(val) >= 8 and val not in lits:
            lits.append(val)
    return tuple(lits)


def _infer_repo_from_blobs(blobs: list[str], repo_filter: pathlib.Path | None) -> pathlib.Path | None:
    """Resolve most frequently referenced CADENCE git repo root from string blobs."""
    counts: dict[pathlib.Path, int] = {}
    for text in blobs:
        for cand in UNIX_PATH_RE.findall(text):
            if cand.count("/") < 2:
                continue
            p = pathlib.Path(cand)
            root = find_repo_root(str(p))
            if root and is_cadence_repo(root):
                if repo_filter and root != repo_filter.resolve():
                    continue
                counts[root] = counts.get(root, 0) + 1
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: kv[1])[0]


def _load_jsonl(path: pathlib.Path) -> list[dict[str, Any]]:
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip():
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows


def ingest_antigravity(
    brain_root: pathlib.Path,
    log_dir: pathlib.Path,
    repo_filter: pathlib.Path | None = None,
    extra_literals: tuple[str, ...] = (),
) -> dict[str, int]:
    """Backfill CADENCE turns from Antigravity transcript_full.jsonl / transcript.jsonl logs."""
    stats = {"ingested": 0, "skipped_duplicate": 0, "skipped_non_cadence": 0, "redactions": 0}
    if not brain_root.is_dir():
        return stats
    max_chars = default_max_tool_chars()
    for conv_dir in sorted(brain_root.iterdir()):
        if not conv_dir.is_dir():
            continue
        logs_dir = conv_dir / ".system_generated" / "logs"
        tp = logs_dir / "transcript_full.jsonl"
        if not tp.is_file():
            tp = logs_dir / "transcript.jsonl"
        if not tp.is_file():
            continue
        steps = _load_jsonl(tp)
        ui_indices = [i for i, s in enumerate(steps) if s.get("type") == "USER_INPUT" and s.get("source") == "USER_EXPLICIT"]
        if not ui_indices:
            continue
        sid = conv_dir.name
        blobs = [json.dumps(s, ensure_ascii=False) for s in steps[: min(40, len(steps))]]
        conv_repo = _infer_repo_from_blobs(blobs, repo_filter)
        for seq, start_idx in enumerate(ui_indices, start=1):
            end_idx = ui_indices[seq] if seq < len(ui_indices) else len(steps)
            chunk = steps[start_idx:end_idx]
            turn_repo = _infer_repo_from_blobs([json.dumps(s, ensure_ascii=False) for s in chunk], repo_filter) or conv_repo
            if not turn_repo:
                stats["skipped_non_cadence"] += 1
                continue
            msgs, models, usage = parse_antigravity_steps(chunk, max_chars)
            s0 = int(chunk[0].get("step_index", start_idx))
            s1 = int(chunk[-1].get("step_index", end_idx - 1))
            wrote, red, _ = build_and_append_turn(
                log_dir, turn_repo, "antigravity", sid, seq, [s0, s1], msgs, models, usage,
                str(chunk[0].get("created_at") or ""), extra_literals,
            )
            stats["redactions"] += red
            if wrote:
                stats["ingested"] += 1
            elif any(m.get("role") == "assistant" for m in msgs):
                stats["skipped_duplicate"] += 1
    return stats


def ingest_claude(
    claude_projects_root: pathlib.Path,
    log_dir: pathlib.Path,
    repo_filter: pathlib.Path | None = None,
    extra_literals: tuple[str, ...] = (),
) -> dict[str, int]:
    """Backfill CADENCE turns from Claude Code project JSONL transcripts."""
    stats = {"ingested": 0, "skipped_duplicate": 0, "skipped_non_cadence": 0, "redactions": 0}
    if not claude_projects_root.is_dir():
        return stats
    max_chars = default_max_tool_chars()
    for jf in sorted(claude_projects_root.glob("*/*.jsonl")):
        rows = _load_jsonl(jf)
        if not rows:
            continue
        cwd_hint = next((str(r.get("cwd") or "") for r in rows if r.get("cwd")), "")
        repo_root = find_repo_root(cwd_hint)
        if repo_root and not is_cadence_repo(repo_root):
            repo_root = None
        if repo_root and repo_filter and repo_root != repo_filter.resolve():
            repo_root = None
        if not repo_root:
            repo_root = _infer_repo_from_blobs([json.dumps(r, ensure_ascii=False) for r in rows[:20]], repo_filter)
        if not repo_root:
            stats["skipped_non_cadence"] += 1
            continue
        ui_indices = [
            i for i, r in enumerate(rows)
            if r.get("type") == "user" and isinstance((r.get("message") or {}).get("content"), str) and not r.get("isMeta")
        ]
        sid = next((str(r.get("sessionId") or r.get("session_id")) for r in rows if r.get("sessionId") or r.get("session_id")), jf.stem)
        for seq, start_idx in enumerate(ui_indices, start=1):
            end_idx = ui_indices[seq] if seq < len(ui_indices) else len(rows)
            chunk = rows[start_idx:end_idx]
            msgs, models, usage = parse_claude_rows(chunk, max_chars)
            wrote, red, _ = build_and_append_turn(
                log_dir, repo_root, "claude-code", sid, seq, [start_idx, end_idx - 1], msgs, models, usage,
                str(chunk[0].get("timestamp") or ""), extra_literals,
            )
            stats["redactions"] += red
            if wrote:
                stats["ingested"] += 1
            elif any(m.get("role") == "assistant" for m in msgs):
                stats["skipped_duplicate"] += 1
    return stats


def ingest_blitz(
    blitz_sessions_root: pathlib.Path,
    log_dir: pathlib.Path,
    repo_filter: pathlib.Path | None = None,
    extra_literals: tuple[str, ...] = (),
) -> dict[str, int]:
    """Backfill CADENCE turns from Blitz session *.meta.json + *.jsonl transcripts."""
    stats = {"ingested": 0, "skipped_duplicate": 0, "skipped_non_cadence": 0, "redactions": 0}
    if not blitz_sessions_root.is_dir():
        return stats
    max_chars = default_max_tool_chars()
    for mf in sorted(blitz_sessions_root.glob("session-*.meta.json")):
        try:
            meta = json.loads(mf.read_text(encoding="utf-8"))
        except Exception:
            continue
        ws = str(meta.get("workspace") or "")
        repo_root = find_repo_root(ws)
        if not repo_root or not is_cadence_repo(repo_root):
            stats["skipped_non_cadence"] += 1
            continue
        if repo_filter and repo_root != repo_filter.resolve():
            stats["skipped_non_cadence"] += 1
            continue
        jl = pathlib.Path(str(mf)[:-len(".meta.json")] + ".jsonl")
        if not jl.is_file():
            continue
        rows = _load_jsonl(jl)
        ui_indices = [i for i, r in enumerate(rows) if r.get("role") == "user"]
        if not ui_indices:
            continue
        sid = str(meta.get("id") or jf_stem(mf))
        mdl = str(meta.get("model") or "")
        u_raw = meta.get("usage") if isinstance(meta.get("usage"), dict) else {}
        base_usage = {"input": int(u_raw.get("input") or 0), "cache_read": int(u_raw.get("cached") or 0), "output": int(u_raw.get("output") or 0)}
        for seq, start_idx in enumerate(ui_indices, start=1):
            end_idx = ui_indices[seq] if seq < len(ui_indices) else len(rows)
            chunk = rows[start_idx:end_idx]
            msgs = []
            for r in chunk:
                role = "assistant" if r.get("role") in ("model", "assistant") else "user"
                msgs.append({"role": role, "content": cap_text(str(r.get("content") or ""), max_chars)})
            wrote, red, _ = build_and_append_turn(
                log_dir, repo_root, "blitz", sid, seq, [start_idx, end_idx - 1], msgs,
                [mdl] if mdl else [], base_usage if seq == len(ui_indices) else {"input": 0, "cache_read": 0, "output": 0},
                str(chunk[0].get("timestamp") or meta.get("created_at") or ""), extra_literals,
            )
            stats["redactions"] += red
            if wrote:
                stats["ingested"] += 1
            elif any(m.get("role") == "assistant" for m in msgs):
                stats["skipped_duplicate"] += 1
    return stats


def jf_stem(meta_file: pathlib.Path) -> str:
    return meta_file.name[:-len(".meta.json")]
