#!/usr/bin/env python3
"""CLI for /cadence-trainlog: status, ingest, tag, SFT/DPO/RLVR export, and verify."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import tempfile
from typing import Any

_SK_DIR = pathlib.Path(__file__).resolve().parent
for _p in (_SK_DIR, _SK_DIR.parents[1] / "hooks", _SK_DIR.parents[2] / "hooks"):
    if (_p / "cadence_turn_logger.py").is_file() or _p == _SK_DIR:
        if str(_p) not in sys.path:
            sys.path.insert(0, str(_p))

from cadence_turn_logger import (  # noqa: E402
    default_log_dir,
    redact_obj,
    redact_secrets,
    write_private_file,
)
from cadence_turn_parsers import cap_text  # noqa: E402
from trainlog_ingest import (  # noqa: E402
    ingest_antigravity,
    ingest_blitz,
    ingest_claude,
    load_env_literals,
)


def _iter_repo_records(log_dir: pathlib.Path, repo_slug: str) -> list[dict[str, Any]]:
    rdir = log_dir / "repos" / repo_slug
    records: list[dict[str, Any]] = []
    if not rdir.is_dir():
        return records
    for jf in sorted(rdir.glob("*/*.turns.jsonl")):
        for line in jf.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.strip():
                try:
                    records.append(json.loads(line))
                except Exception:
                    continue
    records.sort(key=lambda r: (str(r.get("turn_timestamp") or ""), int(r.get("turn_seq") or 0)))
    return records


def _load_repo_meta(log_dir: pathlib.Path, repo_slug: str) -> dict[str, Any]:
    mp = log_dir / "repos" / repo_slug / "repo.meta.json"
    if mp.is_file():
        return json.loads(mp.read_text(encoding="utf-8"))
    return {"repo_slug": repo_slug, "confidentiality": "private", "client_tag": ""}


def _build_dpo_pairs(records: list[dict[str, Any]], include_thinking: bool, max_tool_chars: int) -> list[dict[str, Any]]:
    """Pair sequential failed/rejected turns with subsequent verified_pass turns."""
    grouped: dict[str, list[dict[str, Any]]] = {}
    for rec in records:
        tickets = (rec.get("cadence") or {}).get("tickets") or []
        key = f"ticket:{tickets[0]}" if tickets else f"session:{rec.get('session_id')}"
        grouped.setdefault(key, []).append(rec)
    pairs: list[dict[str, Any]] = []
    for key, group in grouped.items():
        group.sort(key=lambda r: (str(r.get("turn_timestamp") or ""), int(r.get("turn_seq") or 0)))
        pending_rej: dict[str, Any] | None = None
        for rec in group:
            cad = rec.get("cadence") or {}
            out = cad.get("turn_outcome")
            cyc = cad.get("latest_review_cycle") or {}
            is_fail = (out == "gate_failed") or (isinstance(cyc.get("blocking"), int) and cyc["blocking"] > 0 and out != "verified_pass")
            is_pass = out == "verified_pass"
            if is_fail:
                pending_rej = rec
            elif is_pass and pending_rej is not None:
                prompt_msgs = [m for m in (pending_rej.get("messages") or []) if m.get("role") == "user"][:1]
                if not prompt_msgs:
                    prompt_msgs = [m for m in (rec.get("messages") or []) if m.get("role") == "user"][:1]
                rej_traj = _clean_messages([m for m in (pending_rej.get("messages") or []) if m.get("role") != "user"], include_thinking, max_tool_chars)
                chs_traj = _clean_messages([m for m in (rec.get("messages") or []) if m.get("role") != "user"], include_thinking, max_tool_chars)
                if prompt_msgs and rej_traj and chs_traj:
                    pairs.append({
                        "prompt": prompt_msgs,
                        "chosen": chs_traj,
                        "rejected": rej_traj,
                        "metadata": {
                            "group_key": key,
                            "repo": rec.get("repo"),
                            "chosen_record_id": rec.get("record_id"),
                            "rejected_record_id": pending_rej.get("record_id"),
                            "chosen_gates": cad.get("gates"),
                            "rejected_gates": (pending_rej.get("cadence") or {}).get("gates"),
                        },
                    })
                pending_rej = None
    return pairs


def _clean_messages(msgs: list[dict[str, Any]], include_thinking: bool, max_tool_chars: int) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for m in msgs:
        nm = dict(m)
        if not include_thinking:
            nm.pop("reasoning_content", None)
        if nm.get("role") == "tool" and isinstance(nm.get("content"), str):
            nm["content"] = cap_text(nm["content"], max_tool_chars)
        cleaned.append(nm)
    return cleaned


def cmd_status(args: argparse.Namespace) -> int:
    log_dir = pathlib.Path(args.log_dir).expanduser()
    repos_dir = log_dir / "repos"
    rows = []
    if repos_dir.is_dir():
        for rdir in sorted(repos_dir.iterdir()):
            if not rdir.is_dir():
                continue
            slug = rdir.name
            meta = _load_repo_meta(log_dir, slug)
            recs = _iter_repo_records(log_dir, slug)
            outcomes = {"verified_pass": 0, "gate_failed": 0, "escalated_human": 0, "unverified": 0}
            sessions = set()
            for r in recs:
                sessions.add(str(r.get("session_id") or ""))
                o = str((r.get("cadence") or {}).get("turn_outcome") or "unverified")
                outcomes[o] = outcomes.get(o, 0) + 1
            size_bytes = sum(f.stat().st_size for f in rdir.rglob("*.turns.jsonl"))
            dpo_cnt = len(_build_dpo_pairs(recs, True, 65536))
            rows.append({
                "repo_slug": slug,
                "confidentiality": meta.get("confidentiality", "private"),
                "client_tag": meta.get("client_tag", ""),
                "sessions": len([s for s in sessions if s]),
                "turns": len(recs),
                **outcomes,
                "dpo_pairs": dpo_cnt,
                "size_bytes": size_bytes,
            })
    if args.json:
        print(json.dumps({"log_dir": str(log_dir), "repos": rows}, indent=2))
        return 0
    print(f"CADENCE Turn Logs @ {log_dir} ({len(rows)} repo(s))")
    if not rows:
        print("  (no captured turns yet)")
        return 0
    for r in rows:
        tag = f" client={r['client_tag']}" if r["client_tag"] else ""
        print(f"  {r['repo_slug']} [{r['confidentiality']}{tag}] sessions={r['sessions']} turns={r['turns']} pass={r['verified_pass']} fail={r['gate_failed']} escalate={r['escalated_human']} unverified={r['unverified']} dpo_pairs={r['dpo_pairs']} bytes={r['size_bytes']}")
    return 0


def cmd_tag(args: argparse.Namespace) -> int:
    log_dir = pathlib.Path(args.log_dir).expanduser()
    rdir = log_dir / "repos" / args.repo
    if not rdir.is_dir():
        print(f"ERROR: unknown repo slug '{args.repo}' under {log_dir / 'repos'}", file=sys.stderr)
        return 1
    meta = _load_repo_meta(log_dir, args.repo)
    meta["confidentiality"] = args.confidentiality
    if args.client_tag is not None:
        meta["client_tag"] = args.client_tag.strip().lower().replace("_", "-")
    write_private_file(rdir / "repo.meta.json", json.dumps(meta, indent=2) + "\n")
    print(f"TAGGED repo={args.repo} confidentiality={meta['confidentiality']} client_tag={meta.get('client_tag','')}")
    return 0


def cmd_ingest(args: argparse.Namespace) -> int:
    log_dir = pathlib.Path(args.log_dir).expanduser()
    repo_filter = pathlib.Path(args.repo).resolve() if args.repo else None
    lits = load_env_literals(pathlib.Path(args.redact_env_file).expanduser()) if args.redact_env_file else ()
    src = args.source
    totals = {"ingested": 0, "skipped_duplicate": 0, "skipped_non_cadence": 0, "redactions": 0}
    jobs = []
    if src in ("agy", "all"):
        jobs.append(("agy", ingest_antigravity, pathlib.Path(args.agy_dir).expanduser()))
    if src in ("claude", "all"):
        jobs.append(("claude", ingest_claude, pathlib.Path(args.claude_dir).expanduser()))
    if src in ("blitz", "all"):
        jobs.append(("blitz", ingest_blitz, pathlib.Path(args.blitz_dir).expanduser()))
    for name, fn, root in jobs:
        res = fn(root, log_dir, repo_filter, lits)
        for k in totals:
            totals[k] += res[k]
        print(f"ingest[{name}]: ingested={res['ingested']} dup={res['skipped_duplicate']} non_cadence={res['skipped_non_cadence']} redactions={res['redactions']}")
    print(f"TOTAL ingested={totals['ingested']} skipped_duplicate={totals['skipped_duplicate']} skipped_non_cadence={totals['skipped_non_cadence']} redactions={totals['redactions']}")
    return 0


def _check_chinese_wall(log_dir: pathlib.Path, repos: list[str]) -> tuple[bool, str]:
    if len(repos) <= 1:
        return True, ""
    metas = [_load_repo_meta(log_dir, r) for r in repos]
    restricted = [m for m in metas if m.get("confidentiality") == "client-restricted"]
    if not restricted:
        return True, ""
    sigs = {(m.get("confidentiality"), m.get("client_tag") or f"__untagged:{m.get('repo_slug')}") for m in metas}
    if len(sigs) > 1:
        return False, f"CHINESE_WALL_VIOLATION: cannot mix scopes {sorted(str(s) for s in sigs)} into one export"
    return True, ""


def cmd_export(args: argparse.Namespace) -> int:
    log_dir = pathlib.Path(args.log_dir).expanduser()
    if args.allow_multi_repo:
        if not args.repos:
            print("ERROR: --allow-multi-repo requires --repos a,b", file=sys.stderr)
            return 2
        repos = [r.strip() for r in args.repos.split(",") if r.strip()]
    else:
        if not args.repo:
            print("ERROR: export requires --repo <slug> (or --allow-multi-repo --repos a,b)", file=sys.stderr)
            return 2
        repos = [args.repo]
    for r in repos:
        if not (log_dir / "repos" / r).is_dir():
            print(f"ERROR: repo '{r}' not found under {log_dir / 'repos'}", file=sys.stderr)
            return 1
    ok_wall, wall_err = _check_chinese_wall(log_dir, repos)
    if not ok_wall:
        print(f"ERROR: {wall_err}", file=sys.stderr)
        return 2
    sys_prompt = pathlib.Path(args.system_prompt).read_text(encoding="utf-8") if args.system_prompt else ""
    lits = load_env_literals(pathlib.Path(args.redact_env_file).expanduser()) if args.redact_env_file else ()
    emitted: list[dict[str, Any]] = []
    for rslug in repos:
        recs = _iter_repo_records(log_dir, rslug)
        if args.format == "sft":
            for rec in recs:
                cad = rec.get("cadence") or {}
                if args.only_verified and cad.get("turn_outcome") != "verified_pass":
                    continue
                msgs = _clean_messages(rec.get("messages") or [], args.include_thinking, args.max_tool_chars)
                if sys_prompt:
                    msgs = [{"role": "system", "content": sys_prompt}] + msgs
                emitted.append({"messages": msgs, "metadata": {"record_id": rec.get("record_id"), "harness": rec.get("harness"), "models": rec.get("models"), "repo": rec.get("repo"), "cadence": cad}})
        elif args.format == "dpo":
            emitted.extend(_build_dpo_pairs(recs, args.include_thinking, args.max_tool_chars))
        elif args.format == "rlvr":
            for rec in recs:
                cad = rec.get("cadence") or {}
                out = cad.get("turn_outcome")
                reward = 1.0 if out == "verified_pass" else (0.0 if out == "gate_failed" else None)
                msgs = _clean_messages(rec.get("messages") or [], args.include_thinking, args.max_tool_chars)
                emitted.append({
                    "prompt": [m for m in msgs if m.get("role") == "user"][:1],
                    "trajectory": [m for m in msgs if m.get("role") != "user"],
                    "reward": reward,
                    "escalated_human": out == "escalated_human",
                    "verifiable_signals": {"gates": cad.get("gates"), "latest_review_cycle": cad.get("latest_review_cycle"), "git": rec.get("git")},
                    "metadata": {"record_id": rec.get("record_id"), "repo": rec.get("repo"), "tickets": cad.get("tickets")},
                })
    total_red = 0
    lines_out = []
    for row in emitted:
        clean_row, red = redact_obj(row, lits)
        total_red += red
        lines_out.append(json.dumps(clean_row, ensure_ascii=False))
    out_path = pathlib.Path(args.out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".trainlog-", dir=str(out_path.parent))
    try:
        os.chmod(tmp_name, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines_out) + ("\n" if lines_out else ""))
        os.replace(tmp_name, out_path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
    print(f"exported={len(lines_out)} format={args.format} repos={','.join(repos)} redactions={total_red} out={out_path}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    in_path = pathlib.Path(args.input).expanduser()
    if not in_path.is_file():
        print(f"FAIL: dataset not found: {in_path}", file=sys.stderr)
        return 1
    lines = [l for l in in_path.read_text(encoding="utf-8").splitlines() if l.strip()]
    fmt = args.format
    total_chars = 0
    scopes: set[tuple[str, str]] = set()
    for idx, line in enumerate(lines, start=1):
        total_chars += len(line)
        _, sec_hits = redact_secrets(line)
        if sec_hits > 0:
            print(f"FAIL: potential unredacted secret at line {idx} (hits={sec_hits})", file=sys.stderr)
            return 1
        row = json.loads(line)
        if fmt == "auto":
            fmt = "dpo" if ("chosen" in row and "rejected" in row) else ("rlvr" if "trajectory" in row else "sft")
        if fmt == "sft" and not isinstance(row.get("messages"), list):
            print(f"FAIL: invalid SFT record at line {idx}", file=sys.stderr)
            return 1
        if fmt == "dpo" and not all(k in row for k in ("prompt", "chosen", "rejected")):
            print(f"FAIL: invalid DPO record at line {idx}", file=sys.stderr)
            return 1
        if fmt == "rlvr" and not all(k in row for k in ("prompt", "trajectory", "verifiable_signals")):
            print(f"FAIL: invalid RLVR record at line {idx}", file=sys.stderr)
            return 1
        repo = (row.get("metadata") or {}).get("repo") or {}
        if repo:
            scopes.add((str(repo.get("confidentiality") or "private"), str(repo.get("client_tag") or "")))
    if any(c == "client-restricted" for c, _ in scopes) and len(scopes) > 1:
        print(f"FAIL: CHINESE_WALL_VIOLATION across scopes {sorted(scopes)}", file=sys.stderr)
        return 1
    avg = total_chars // len(lines) if lines else 0
    print(f"PASS: verify records={len(lines)} format={fmt} avg_chars={avg} secrets=0")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="trainlog.sh")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_st = sub.add_parser("status")
    p_st.add_argument("--log-dir", default=str(default_log_dir()))
    p_st.add_argument("--json", action="store_true")
    p_tg = sub.add_parser("tag")
    p_tg.add_argument("--repo", required=True)
    p_tg.add_argument("--confidentiality", required=True, choices=["public-eligible", "private", "client-restricted"])
    p_tg.add_argument("--client-tag", default=None)
    p_tg.add_argument("--log-dir", default=str(default_log_dir()))
    p_in = sub.add_parser("ingest")
    p_in.add_argument("--source", default="all", choices=["agy", "claude", "blitz", "all"])
    p_in.add_argument("--repo", default="")
    p_in.add_argument("--log-dir", default=str(default_log_dir()))
    p_in.add_argument("--agy-dir", default="~/.gemini/antigravity-cli/brain")
    p_in.add_argument("--claude-dir", default="~/.claude/projects")
    p_in.add_argument("--blitz-dir", default="~/.blitz/sessions")
    p_in.add_argument("--redact-env-file", default="")
    p_ex = sub.add_parser("export")
    p_ex.add_argument("--format", required=True, choices=["sft", "dpo", "rlvr"])
    p_ex.add_argument("--repo", default="")
    p_ex.add_argument("--allow-multi-repo", action="store_true")
    p_ex.add_argument("--repos", default="")
    p_ex.add_argument("--out", required=True)
    p_ex.add_argument("--log-dir", default=str(default_log_dir()))
    p_ex.add_argument("--include-thinking", action="store_true", default=True)
    p_ex.add_argument("--no-thinking", dest="include_thinking", action="store_false")
    p_ex.add_argument("--only-verified", action="store_true")
    p_ex.add_argument("--max-tool-chars", type=int, default=16000)
    p_ex.add_argument("--system-prompt", default="")
    p_ex.add_argument("--redact-env-file", default="")
    p_vr = sub.add_parser("verify")
    p_vr.add_argument("--input", required=True)
    p_vr.add_argument("--format", default="auto", choices=["auto", "sft", "dpo", "rlvr"])
    args = ap.parse_args()
    dispatch = {"status": cmd_status, "tag": cmd_tag, "ingest": cmd_ingest, "export": cmd_export, "verify": cmd_verify}
    return dispatch[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
