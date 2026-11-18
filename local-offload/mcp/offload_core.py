"""Core helpers for antigravity-local-offload-mcp (:11434)."""

from __future__ import annotations

import glob as glob_mod
import http.client
import json
import math
import os
import pathlib
import re
import socket
import subprocess
import threading
import time
from typing import Any
from urllib.parse import urlsplit

HOME_STR = str(pathlib.Path.home())
LLAMA_SWAP_URL = os.environ.get("LLAMA_SWAP_URL", "http://127.0.0.1:11434/v1")
LAN_EMBED_URL = os.environ.get("LIVING_ROOM_EMBED_URL", "http://192.168.50.254:11434/v1")
LAN_PROBE_TIMEOUT = float(os.environ.get("LIVING_ROOM_PROBE_TIMEOUT", "0.15"))
TIER1_CPU_URL = os.environ.get("LOCAL_AI_TIER1_URL", LLAMA_SWAP_URL)
TIER2_GPU_URL = os.environ.get("LOCAL_AI_TIER2_URL", LLAMA_SWAP_URL)
DEFAULT_OFFLOAD_MODEL = os.environ.get("OFFLOAD_GPU_MODEL", "inference")
MAX_INLINE_CHARS = 3850
RAW_TRIAGE_LOG_PATH = pathlib.Path("/tmp/agy-last-triage.log")
RAW_TRIAGE_DIR = pathlib.Path("/tmp/agy-triage")

_LAN_STATE_LOCK = threading.Lock()
_LAN_DOWN_UNTIL: float = 0.0
_THREAD_STATE = threading.local()

REPO_PATH_RE = re.compile(rf"(?:{re.escape(HOME_STR)}/projects/|~/projects/|-C\s+|cd\s+)([A-Za-z0-9_./~-]+)")
EMBED_MODELS = {
    "embedding", "embeddinggemma", "embeddinggemma-2", "embeddinggemma-2-bf16", "local-embed-cpu",
    "nomic-embed-text", "embedding-local-3050", "openai/embedding", "openai/embeddinggemma",
    "openai/embeddinggemma-2", "openai/local-embed-cpu",
}
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "bin", "obj", "dist", "build", "__pycache__", ".next", "target"}
ALLOW_HIDDEN_DIRS = {".agents", ".gemini", ".github", ".claude"}
TEXT_EXTS = {
    ".py", ".sh", ".zsh", ".bash", ".md", ".json", ".yaml", ".yml", ".toml", ".ini", ".service",
    ".ts", ".tsx", ".js", ".jsx", ".cs", ".kt", ".kts", ".java", ".rs", ".go", ".c", ".cpp", ".h", ".sql",
}
FAIL_SIGNAL_RE = re.compile(
    r"(?i)([A-Za-z_][A-Za-z0-9_]*(?:Error|Exception|Failure)\b"
    r"|\b(?:error|warning|warn|fail(?:ed|ure)?|exception|traceback|assert(?:ion)?|panic|fatal|expected|received)\b"
    r"|(?:^|\s|\|)(?:FAIL\t|●\s+|FAILED\b|={3,}\s*FAILURES)|[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:\d+(?::\d+)?)"
)
VERBATIM_SIGNAL_RE = re.compile(
    r"(?i)([A-Za-z_][A-Za-z0-9_]*(?:Error|Exception|Failure)\b"
    r"|\b(?:error|warning|warn|fail(?:ed|ure)?|exception|traceback|assert(?:ion)?|panic|fatal|expected|received|coverage|passed|skipped)\b"
    r"|[A-Za-z0-9_./-]+\.[A-Za-z0-9_]+:\d+(?::\d+)?)"
)
_CS_MODS = r"(?:(?:public|private|protected|internal|static|async|virtual|override|sealed|partial|abstract|readonly)\s+)*"
SYMBOL_RE = re.compile(
    rf"^\s*(?:"
    rf"async\s+def|def|class|function|"
    rf"export\s+(?:default\s+)?(?:async\s+)?(?:function|class|interface|type|const)|"
    rf"(?:suspend\s+)?fun|data\s+class|sealed\s+(?:class|interface)|object|"
    rf"{_CS_MODS}(?:class|record|struct|interface|enum|namespace)|"
    rf"pub\s+(?:async\s+)?fn|fn|impl|func\s+(?:\([^)]*\)\s*)?|type\s+|"
    rf"#{1,3}"
    rf")\s+([A-Za-z0-9_./:-]+)"
    rf"|^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:async\s+)?[A-Za-z0-9_<>,?.\[\]]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("
    rf"|^([A-Za-z0-9_-]+)\s*\(\)\s*\{{"
    rf"|^([A-Za-z0-9_.-]+):\s*$"
)
OBSERVABILITY_SEAMS = ("UNSOUND_CONDITION", "RULE_DIVERGENCE", "BOUNDARY_FAULT", "DELTA_AUDIT_GAP")
NORM_DUP_RE = re.compile(r"^\s*\d+\s*\|\s*(?:[A-Z][a-z]{2}\s+\d+\s+\d+:\d+:\d+\s+\S+\s+\S+?\[\d+\]:\s*)?")


def _thread_pool() -> dict[str, http.client.HTTPConnection]:
    pool = getattr(_THREAD_STATE, "conn_pool", None)
    if pool is None:
        pool = {}
        _THREAD_STATE.conn_pool = pool
    return pool


def fit_inline(body: str, footer: str = "", limit: int = MAX_INLINE_CHARS) -> str:
    full = f"{body}\n{footer}".strip() + "\n" if footer else body.strip() + "\n"
    if len(full.encode("utf-8")) <= limit:
        return full
    sfx = f"\n...\n{footer.strip()}\n" if footer else "\n...(inline-bounded)\n"
    budget = max(400, limit - len(sfx.encode("utf-8")) - 32)
    clipped = body.encode("utf-8")[:budget].decode("utf-8", errors="ignore").rsplit("\n", 1)[0]
    if clipped.count("```") % 2 == 1:
        clipped += "\n```"
    return clipped + sfx


def _configure_conn(conn: http.client.HTTPConnection, timeout: float) -> None:
    """Apply timeout and TCP_NODELAY to both HTTPConnection and its active socket."""
    conn.timeout = timeout
    if conn.sock is not None:
        conn.sock.settimeout(timeout)
        try:
            conn.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass


def _open_lan_conn(netloc: str, read_timeout: float = 60.0) -> http.client.HTTPConnection:
    """Connect to LAN/VPN endpoint using fast probe timeout, then raise socket read timeout."""
    host, _, port_s = netloc.partition(":")
    conn = http.client.HTTPConnection(host, int(port_s or 11434), timeout=LAN_PROBE_TIMEOUT)
    conn.connect()
    _configure_conn(conn, read_timeout)
    return conn


def resolve_base_url(model: str) -> str:
    global _LAN_DOWN_UNTIL
    if model not in EMBED_MODELS:
        return TIER2_GPU_URL
    with _LAN_STATE_LOCK:
        down_until = _LAN_DOWN_UNTIL
    if time.monotonic() >= down_until:
        pool = _thread_pool()
        netloc = urlsplit(LAN_EMBED_URL).netloc
        existing = pool.get(netloc)
        if existing is not None and existing.sock is not None:
            return LAN_EMBED_URL
        try:
            pool[netloc] = _open_lan_conn(netloc, read_timeout=60.0)
            return LAN_EMBED_URL
        except OSError:
            with _LAN_STATE_LOCK:
                _LAN_DOWN_UNTIL = time.monotonic() + 30.0
    return TIER1_CPU_URL


def post_json(url: str, payload: dict[str, Any], timeout: float = 180.0) -> dict[str, Any]:
    global _LAN_DOWN_UNTIL
    body = json.dumps(payload).encode("utf-8")
    pool = _thread_pool()
    for attempt in range(3):
        sp = urlsplit(url)
        pooled = pool.get(sp.netloc)
        reused = pooled is not None and pooled.sock is not None
        conn = pooled if reused else None
        try:
            if conn is None:
                conn = _open_lan_conn(sp.netloc, read_timeout=timeout) if url.startswith(LAN_EMBED_URL) else http.client.HTTPConnection(sp.netloc, timeout=timeout)
                pool[sp.netloc] = conn
            _configure_conn(conn, timeout)
            conn.request("POST", sp.path or "/", body=body, headers={"Content-Type": "application/json", "Connection": "keep-alive"})
            _configure_conn(conn, timeout)
            resp = conn.getresponse()
            raw = resp.read()
            if resp.will_close:
                conn.close()
                pool.pop(sp.netloc, None)
            if resp.status >= 400:
                raise RuntimeError(f"HTTP {resp.status}: {raw[:200]!r}")
            return json.loads(raw.decode("utf-8"))
        except (OSError, http.client.HTTPException):
            if conn is not None:
                conn.close()
            pool.pop(sp.netloc, None)
            if reused and attempt == 0:
                continue
            if url.startswith(LAN_EMBED_URL) and TIER1_CPU_URL != LAN_EMBED_URL:
                with _LAN_STATE_LOCK:
                    _LAN_DOWN_UNTIL = time.monotonic() + 30.0
                url = TIER1_CPU_URL + url[len(LAN_EMBED_URL):]
                continue
            raise
    raise RuntimeError(f"POST failed: {url}")


def cosine_similarity(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na, nb = math.sqrt(sum(x * x for x in a)), math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


def detect_repo_name(hint: str, cwd: str | None = None) -> str:
    cands = ([cwd] if cwd else []) + [os.path.expanduser(m.group(1)) for m in REPO_PATH_RE.finditer(hint)] + [os.getcwd()]
    for raw in cands:
        p = pathlib.Path(raw).expanduser()
        cur = p if p.is_dir() else p.parent
        for d in (cur, *cur.parents):
            if (d / ".git").exists():
                return re.sub(r"[^A-Za-z0-9._-]", "_", d.name)
        m = re.search(r"/projects/([A-Za-z0-9._-]+)", str(p))
        if m:
            return m.group(1)
    return re.sub(r"[^A-Za-z0-9._-]", "_", pathlib.Path.cwd().name or "global")


def clip_line(nline: str, log_path: pathlib.Path = RAW_TRIAGE_LOG_PATH, limit: int = 260) -> str:
    if len(nline) <= limit:
        return nline
    m = VERBATIM_SIGNAL_RE.search(nline)
    if not m or m.start() < limit // 2:
        return f"{nline[:limit]} ...[+{len(nline) - limit}c in {log_path.name}]"
    start = max(10, m.start() - 60)
    end = min(len(nline), start + limit - 20)
    return f"{nline[:10]}...{nline[start:end]}...[+{len(nline) - end}c in {log_path.name}]"


def compact_signals(numbered_lines: list[str], log_path: pathlib.Path = RAW_TRIAGE_LOG_PATH) -> tuple[list[str], set[int], bool]:
    fail_groups: dict[str, dict[str, Any]] = {}
    info_groups: dict[str, dict[str, Any]] = {}
    matched: set[int] = set()
    total = len(numbered_lines)
    for idx, nline in enumerate(numbered_lines, start=1):
        is_fail = bool(FAIL_SIGNAL_RE.search(nline))
        if not is_fail and not VERBATIM_SIGNAL_RE.search(nline):
            continue
        matched.add(idx)
        target = fail_groups if is_fail else info_groups
        key = NORM_DUP_RE.sub("", nline)[:180]
        if key not in target:
            ctx = [clip_line(nline, log_path)]
            if is_fail:
                for cidx in range(idx + 1, min(total + 1, idx + 3)):
                    cline = numbered_lines[cidx - 1]
                    if not FAIL_SIGNAL_RE.search(cline) and cline.split("|", 1)[-1].strip():
                        ctx.append(clip_line(cline, log_path))
                        matched.add(cidx)
            target[key] = {"line": "\n".join(ctx), "count": 1, "first": idx, "last": idx}
        else:
            target[key]["count"] += 1
            target[key]["last"] = idx
    fmt = lambda g: f"{g['line']}  [x{g['count']}, L{g['first']}..L{g['last']}]" if g["count"] > 1 else g["line"]
    out = [fmt(g) for g in fail_groups.values()] + [fmt(g) for g in info_groups.values()]
    return out, matched, bool(fail_groups)


def write_numbered_raw_log(raw_text: str, source_header: str, repo_name: str, pid: str | int) -> tuple[int, list[str], pathlib.Path]:
    lines = raw_text.splitlines()
    numbered = [f"{idx:6d} | {line}" for idx, line in enumerate(lines, start=1)]
    repo_dir = RAW_TRIAGE_DIR / repo_name
    repo_dir.mkdir(parents=True, exist_ok=True)
    log_path = repo_dir / f"{pid}.log"
    header = f"# {log_path} — Full Unedited Output (CADENCE SDLC Ephemeral Session Escape Hatch)\n# Repo: {repo_name} | PID: {pid} | Source: {source_header} | Total Lines: {len(lines)}\n# ------------------------------------------------------------------------------\n"
    payload = header + "\n".join(numbered) + "\n"
    log_path.write_text(payload, encoding="utf-8")
    log_path.chmod(0o600)
    latest_link, tmp_link = repo_dir / "latest.log", repo_dir / f".latest.log.{pid}"
    tmp_last = RAW_TRIAGE_LOG_PATH.with_name(f".agy-last-triage.log.{pid}")
    try:
        tmp_link.unlink(missing_ok=True)
        tmp_link.symlink_to(log_path)
        tmp_link.replace(latest_link)
        tmp_last.write_text(payload, encoding="utf-8")
        tmp_last.chmod(0o600)
        tmp_last.replace(RAW_TRIAGE_LOG_PATH)
    except OSError:
        for f in (tmp_link, tmp_last):
            f.unlink(missing_ok=True)
    return len(lines), numbered, log_path


def extract_file_chunks(p: pathlib.Path, chunk_lines: int = 36, overlap: int = 4) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    text = p.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    total = len(lines)
    symbols: list[tuple[int, str]] = []
    for idx, raw in enumerate(lines, start=1):
        m = SYMBOL_RE.match(raw)
        if m:
            sym = next((g for g in m.groups() if g), "").strip()
            if sym and len(sym) <= 64:
                symbols.append((idx, sym))
    meta = {
        "path": str(p), "name": p.name, "lines": total, "seams": [s for s in OBSERVABILITY_SEAMS if s in text],
        "ergonomics": "OK (<400)" if total < 400 else f"EXCEEDS_400 ({total})", "symbols": [f"{s}@L{ln}" for ln, s in symbols[:24]],
    }
    if total == 0:
        return meta, []
    bounds = [ln for ln, _ in symbols if ln > 1]
    chunks: list[dict[str, Any]] = []
    start = 1
    while start <= total:
        end = min(total, start + chunk_lines - 1)
        for b in bounds:
            if start + 16 <= b <= end + 4:
                end = max(start, b - 1)
                break
        slice_lines = lines[start - 1 : end]
        c_syms = [f"{s}@L{ln}" for ln, s in symbols if start <= ln <= end]
        numbered = "\n".join(f"{i:4d} | {l[:140]}" for i, l in enumerate(slice_lines, start=start))
        embed_body = "\n".join(l[:240] for l in slice_lines)[:4000]
        chunks.append({
            "label": f"{p}#L{start}-L{end}", "path": str(p), "name": p.name, "start": start, "end": end,
            "symbols": c_syms, "numbered": numbered, "embed_text": f"title: {p.name} L{start}-L{end} symbols={','.join(c_syms)} | text: {embed_body}",
        })
        if end >= total:
            break
        start = max(start + 1, end + 1 - overlap)
    return meta, chunks


def expand_targets(texts: list[str], max_files: int = 80) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]], dict[str, int]]:
    file_metas: dict[str, dict[str, Any]] = {}
    chunks: list[dict[str, Any]] = []
    seen: set[str] = set()
    eligible_total = 0

    def _add(fp: pathlib.Path) -> None:
        nonlocal eligible_total
        if not fp.is_file():
            return
        res = str(fp.resolve())
        if res in seen or fp.stat().st_size > 512_000:
            return
        eligible_total += 1
        if len(seen) >= max_files:
            return
        seen.add(res)
        meta, fchunks = extract_file_chunks(fp)
        file_metas[str(fp)] = meta
        chunks.extend(fchunks)

    for idx, item in enumerate(texts):
        s = item.strip()
        if "\n" not in s and len(s) < 1024:
            exp = os.path.expanduser(s)
            p = pathlib.Path(exp)
            if p.is_file():
                _add(p)
                continue
            if p.is_dir():
                for root, dirs, files in os.walk(p):
                    dirs[:] = [d for d in sorted(dirs) if d not in SKIP_DIRS and (not d.startswith(".") or d in ALLOW_HIDDEN_DIRS)]
                    for fn in sorted(files):
                        fp = pathlib.Path(root) / fn
                        if fp.suffix.lower() in TEXT_EXTS or fn.endswith(("_ORG.md", "_DIRECTIVES.md")) or fn in {"SKILL.md", "GEMINI.md", "AGENTS.md", "CLAUDE.md", "PROJECT_INTENT.md", "CHANGELOG.md"}:
                            _add(fp)
                continue
            if any(ch in exp for ch in "*?[]"):
                for mp in sorted(glob_mod.glob(exp, recursive=True)):
                    _add(pathlib.Path(mp))
                continue
        lines = s.splitlines()
        chunks.append({
            "label": f"snippet[{idx}]", "path": f"snippet[{idx}]", "name": f"snippet[{idx}]", "start": 1, "end": max(1, len(lines)),
            "symbols": [], "numbered": "\n".join(f"{i:4d} | {l[:160]}" for i, l in enumerate(lines[:36], start=1)), "embed_text": f"title: snippet[{idx}] | text: {s[:4000]}",
        })
    stats = {"indexed": len(seen), "eligible": eligible_total, "truncated": max(0, eligible_total - len(seen))}
    return file_metas, chunks, stats


def embed_batch(inputs: list[str], batch_size: int = 48) -> list[list[float]]:
    base_url = resolve_base_url("embedding")
    vecs: list[list[float]] = []
    for i in range(0, len(inputs), batch_size):
        resp = post_json(f"{base_url}/embeddings", {"model": "embedding", "input": inputs[i : i + batch_size]}, timeout=60.0)
        vecs.extend(r["embedding"] for r in sorted(resp["data"], key=lambda r: r["index"]))
    return vecs


def collect_git_diff_context(diff_range: str, work_dir: pathlib.Path) -> tuple[list[str], list[str], list[str]]:
    """Return (static_rows, deterministic_flags, diff_blocks) for git diff_range."""
    ns = subprocess.run(["git", "-C", str(work_dir), "diff", "--numstat", diff_range], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    if ns.returncode != 0:
        raise RuntimeError(f"git diff --numstat {diff_range} failed: {ns.stderr.strip()}")
    df = subprocess.run(["git", "-C", str(work_dir), "diff", "--unified=2", diff_range], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    if df.returncode != 0:
        raise RuntimeError(f"git diff {diff_range} failed: {df.stderr.strip()}")
    rows, flags, changed_paths = [], [], []
    for line in ns.stdout.splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        add_s, del_s, rel = parts
        changed_paths.append(rel)
        p = work_dir / rel
        if p.is_file():
            meta, _ = extract_file_chunks(p, chunk_lines=50, overlap=4)
            seams_s = ",".join(meta["seams"]) or "none"
            rows.append(f"- [{meta['name']}](file://{meta['path']}): `+{add_s}/-{del_s}` | `{meta['lines']}`L (`{meta['ergonomics']}`) | seams: `{seams_s}`")
            if meta["lines"] >= 400:
                flags.append(f"EXCEEDS_400: {rel} ({meta['lines']} lines)")
        else:
            rows.append(f"- `{rel}`: `+{add_s}/-{del_s}` (deleted/absent in HEAD)")
    diff_text = df.stdout
    for dline in diff_text.splitlines():
        if dline.startswith("+") and not dline.startswith("+++") and re.search(r"(#|//)\s*(?:TODO|FIXME|specs/)", dline):
            flags.append(f"DIFF_SMELL: `{dline[1:].strip()[:100]}`")
    sections = re.split(r"(?=^diff --git )", diff_text, flags=re.MULTILINE)
    sections = [s for s in sections if s.strip()]
    per_file = max(360, 9000 // max(1, len(sections)))
    budgeted = []
    for sec in sections:
        if len(sec) <= per_file:
            budgeted.append(sec.rstrip())
        else:
            budgeted.append(sec[:per_file].rstrip() + f"\n... (hunk clipped at {per_file}/{len(sec)} chars)")
    return rows, flags, ["\n".join(budgeted)] if budgeted else []
