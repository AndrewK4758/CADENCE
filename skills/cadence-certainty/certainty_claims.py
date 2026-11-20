#!/usr/bin/env python3
"""Layer-2 empirical proof-graph, absence-regex, DAG-depth, and receipt verifier."""
import hashlib
import os
import pathlib
import re
import subprocess
import yaml

BIN_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf",
    ".pyc", ".so", ".o", ".a", ".gguf", ".db", ".sqlite", ".zip", ".tar", ".gz",
}
SKIP_PREFIXES = (".git/", "specs/", "archive/")


def _is_safe_rel(root: pathlib.Path, rel_str: str) -> pathlib.Path | None:
    if not rel_str or rel_str.startswith("/") or ".." in pathlib.PurePosixPath(rel_str).parts:
        return None
    resolved = (root / rel_str).resolve()
    try:
        resolved.relative_to(root.resolve())
        return resolved
    except ValueError:
        return None


def _read_repo_file_lines(root: pathlib.Path, rel_str: str) -> list[str] | None:
    target = _is_safe_rel(root, rel_str)
    if target is None:
        return None
    if target.is_file():
        return target.read_text(encoding="utf-8", errors="replace").splitlines()
    res = subprocess.run(["git", "-C", str(root), "cat-file", "-p", f"HEAD:{rel_str}"], capture_output=True, text=True)
    return res.stdout.splitlines() if res.returncode == 0 else None


def _resolve_target(root: pathlib.Path, code_roots: list[pathlib.Path], rel_str: str) -> tuple[pathlib.Path, str]:
    s = str(rel_str).strip()
    if ":" in s:
        prefix, rest = s.split(":", 1)
        for cr in code_roots:
            if cr.name == prefix and rest:
                return cr, rest.lstrip("./")
    clean = s.lstrip("./")
    if len(code_roots) == 1 and code_roots[0] != root:
        if _is_safe_rel(code_roots[0], clean) is not None and ((code_roots[0] / clean).exists() or not (root / clean).exists()):
            return code_roots[0], clean
    if _is_safe_rel(root, clean) is not None and (root / clean).exists():
        return root, clean
    for cr in code_roots:
        if cr != root and _is_safe_rel(cr, clean) is not None and (cr / clean).exists():
            return cr, clean
    return (code_roots[0] if len(code_roots) == 1 else root), clean


def _parse_ref(ref_str: str) -> tuple[str, int, int] | None:
    m = re.match(r"^(.+):(\d+)(?:-(\d+))?$", str(ref_str).strip())
    if not m:
        return None
    path = m.group(1).strip().lstrip("./")
    start = int(m.group(2))
    end = int(m.group(3) or start)
    return path, start, end


def _verify_observed_proof(
    root: pathlib.Path, code_roots: list[pathlib.Path], cid: str, claim: dict, halts: list, passes: list
) -> None:
    proof = claim.get("proof")
    if not isinstance(proof, dict) or not proof.get("ref"):
        halts.append(("missing_proof", cid, "observed non-absence claim lacks proof.ref"))
        return
    parsed = _parse_ref(proof["ref"])
    if not parsed:
        halts.append(("hallucinated_ref", cid, f"invalid proof.ref syntax: {proof['ref']!r}"))
        return
    raw_path, start, end = parsed
    tgt_root, rel_path = _resolve_target(root, code_roots, raw_path)
    lines = _read_repo_file_lines(tgt_root, rel_path)
    if lines is None:
        halts.append(("hallucinated_ref", cid, f"cited file missing or outside repo: {raw_path}"))
        return
    if start < 1 or end < start or end > len(lines):
        halts.append(("ref_out_of_bounds", cid, f"{raw_path}:{start}-{end} exceeds file length {len(lines)}"))
        return
    win = "\n".join(lines[max(0, start - 6) : min(len(lines), end + 5)])
    for sym in proof.get("symbols") or []:
        if str(sym) not in win:
            halts.append(("missing_symbol", cid, f"symbol {sym!r} not found near {raw_path}:{start}-{end}"))
            return
    anchor = proof.get("anchor_substring")
    if anchor and str(anchor) not in "\n".join(lines[start - 1 : end]):
        halts.append(("anchor_mismatch", cid, f"anchor_substring not found inside {raw_path}:{start}-{end}"))
        return
    passes.append(("observed_proof", cid, f"{raw_path}:{start}-{end}"))


def _list_scope_files(root: pathlib.Path, scope: str) -> list[str] | None:
    scope_clean = scope.strip().rstrip("/") or "."
    if scope_clean != "." and _is_safe_rel(root, scope_clean) is None:
        return None
    ls = subprocess.run(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "--", scope_clean], capture_output=True, text=True)
    if ls.returncode == 0:
        candidates = [line.strip() for line in ls.stdout.splitlines() if line.strip()]
    else:
        base = root if scope_clean == "." else (root / scope_clean)
        candidates = [scope_clean] if base.is_file() else ([p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file()] if base.is_dir() else [])
    return [
        rel for rel in sorted(set(candidates))
        if not rel.startswith(SKIP_PREFIXES) and pathlib.PurePosixPath(rel).suffix.lower() not in BIN_EXTS and (root / rel).is_file()
    ]


def _verify_absence_claim(
    root: pathlib.Path, code_roots: list[pathlib.Path], cid: str, claim: dict, halts: list, passes: list
) -> None:
    proof = claim.get("proof")
    if not isinstance(proof, dict) or not proof.get("search_pattern") or not proof.get("scope"):
        halts.append(("missing_absence_proof", cid, "absence claim requires proof.search_pattern and proof.scope"))
        return
    try:
        pat = re.compile(str(proof["search_pattern"]))
    except re.error as exc:
        halts.append(("invalid_absence_regex", cid, f"invalid search_pattern: {exc}"))
        return
    tgt_root, scope_rel = _resolve_target(root, code_roots, str(proof["scope"]))
    rels = _list_scope_files(tgt_root, scope_rel)
    if rels is None:
        halts.append(("hallucinated_ref", cid, f"invalid or unsafe scope: {proof['scope']!r}"))
        return
    expected = set()
    for ep in proof.get("expected_files") or []:
        if str(ep).strip():
            _, ep_rel = _resolve_target(root, code_roots, str(ep))
            expected.add(ep_rel)
            expected.add(str(ep).strip().lstrip("./"))
    unexpected: list[str] = []
    for rel in rels:
        try:
            txt = (tgt_root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if pat.search(txt) and rel not in expected and f"{tgt_root.name}:{rel}" not in expected:
            unexpected.append(f"{tgt_root.name}:{rel}" if tgt_root != root else rel)
    if unexpected:
        halts.append(("falsified_absence", cid, f"unexpected match(es) for {proof['search_pattern']!r}: {', '.join(unexpected[:5])}"))
    else:
        passes.append(("absence_proof", cid, f"scope={proof['scope']} matched expected={len(proof.get('expected_files') or [])} file(s)"))


def _evaluate_inferred_dag(
    by_id: dict[str, dict],
    ruled_items: set[str],
    sensitive_files: set[str],
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    memo: dict[str, tuple[int, bool]] = {}

    def _walk(node_id: str, stack: set[str]) -> tuple[int, bool] | None:
        if node_id in memo:
            return memo[node_id]
        if node_id in stack:
            halts.append(("cyclic_inference", node_id, "inference premise cycle detected"))
            return None
        c = by_id.get(node_id)
        if c is None:
            halts.append(("dangling_premise", node_id, f"missing premise claim {node_id}"))
            return None
        st = str(c.get("status", "")).strip().lower()
        if st == "observed":
            memo[node_id] = (0, False)
            return memo[node_id]
        if st == "unknown":
            oq = str(c.get("mapped_oq") or "").strip()
            is_ruled = (node_id in ruled_items) or (oq and oq in ruled_items)
            memo[node_id] = (0, not is_ruled)
            return memo[node_id]
        if st != "inferred":
            halts.append(("invalid_claim_status", node_id, f"unrecognized status {st!r}"))
            return None

        premises = c.get("premises")
        if not isinstance(premises, list) or not premises:
            halts.append(("missing_premises", node_id, "inferred claim requires non-empty premises list"))
            return None

        stack.add(node_id)
        max_d, has_unk = 0, False
        for pid in premises:
            res = _walk(str(pid), stack)
            if res is None:
                stack.remove(node_id)
                return None
            pd, pu = res
            max_d = max(max_d, pd)
            has_unk = has_unk or pu
        stack.remove(node_id)
        memo[node_id] = (1 + max_d, has_unk)
        return memo[node_id]

    for cid, c in by_id.items():
        if str(c.get("status", "")).strip().lower() != "inferred":
            continue
        res = _walk(cid, set())
        if res is None:
            continue
        depth, has_unk = res
        if cid in ruled_items:
            passes.append(("inferred_claim", cid, f"ruled in decisions.md (depth={depth})"))
            continue
        if has_unk:
            escalates.append(("inferred_on_unknown", cid, "inferred claim depends on unruled unknown premise"))
        elif depth > 2:
            escalates.append(("inference_depth_exceeded", cid, f"inference depth {depth} > 2 hops from observed claim"))
        else:
            crit = str(c.get("criticality", "supporting")).strip().lower()
            proof = c.get("proof") if isinstance(c.get("proof"), dict) else {}
            ref_info = _parse_ref(proof.get("ref", "")) if proof.get("ref") else None
            stmt = str(c.get("statement", ""))
            touches_sens = (
                crit == "load_bearing"
                and sensitive_files
                and ((ref_info and ref_info[0] in sensitive_files) or any(sf in stmt for sf in sensitive_files))
            )
            if touches_sens:
                escalates.append(("load_bearing_inferred_sensitive", cid, "load-bearing inferred claim touches security-sensitive file"))
            else:
                passes.append(("inferred_claim", cid, f"depth={depth} <= 2"))


def _sha_matches(rsha: str, head_shas: dict[str, str], repo_hint: str = "") -> bool:
    if not rsha or len(rsha) < 7:
        return False
    cands = [head_shas[repo_hint]] if (repo_hint and repo_hint in head_shas) else list(head_shas.values())
    return any(h and h.lower().startswith(rsha) for h in cands)


def _verify_receipts(
    receipts: object,
    head_shas: dict[str, str],
    test_scenarios: set[str],
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    if not isinstance(receipts, list) or not any(isinstance(r, dict) and r.get("kind") == "test_suite" for r in receipts):
        halts.append(("missing_test_receipt", "receipts", "implement/review stage requires >=1 test_suite receipt"))
        return
    covered: set[str] = set()
    valid_suite = 0
    for idx, rec in enumerate(receipts):
        if not isinstance(rec, dict) or rec.get("kind") != "test_suite":
            continue
        target = f"receipt[{idx}]"
        rsha = str(rec.get("head_sha") or "").strip().lower()
        repo_hint = str(rec.get("repo") or "").strip()
        if not _sha_matches(rsha, head_shas, repo_hint):
            expected_str = "/".join(v[:12] for v in head_shas.values() if v)
            halts.append(("stale_test_receipt", target, f"receipt head_sha={rsha!r} != HEAD {expected_str}"))
            continue
        if rec.get("exit_code") != 0:
            halts.append(("failing_test_receipt", target, f"test_suite exit_code={rec.get('exit_code')!r} != 0"))
            continue
        raw_log, exp_hash = str(rec.get("raw_log") or "").strip(), str(rec.get("raw_log_sha256") or "").strip().lower()
        if raw_log and exp_hash:
            lp = pathlib.Path(raw_log).expanduser()
            if lp.is_file():
                if hashlib.sha256(lp.read_bytes()).hexdigest().lower() != exp_hash:
                    halts.append(("receipt_log_hash_mismatch", target, f"raw_log sha256 mismatch for {raw_log}"))
                    continue
            else:
                escalates.append(("receipt_log_missing", target, f"raw_log missing on disk: {raw_log}"))
                continue
        valid_suite += 1
        covered.update(str(sid).strip() for sid in (rec.get("scenarios_observed_passing") or []))
        passes.append(("test_receipt", target, f"head={rsha[:12]} exit=0"))
    if valid_suite > 0 and test_scenarios and covered:
        missing = sorted(s for s in test_scenarios if s not in covered)
        if missing:
            halts.append(("unexecuted_scenarios", "receipts", f"test-plan scenarios missing from passing receipt: {', '.join(missing[:8])}"))


def evaluate_evidence(
    root: pathlib.Path,
    code_roots: list[pathlib.Path],
    evidence_path: pathlib.Path,
    stage: str,
    head_shas: dict[str, str],
    ruled_items: set[str],
    spec_oqs: set[str],
    test_scenarios: set[str],
    sensitive_files: set[str],
) -> tuple[list, list, list, dict | None]:
    halts, escalates, passes = [], [], []
    try:
        data = yaml.safe_load(evidence_path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:
        halts.append(("malformed_evidence_manifest", evidence_path.name, f"YAML parse error: {exc}"))
        return halts, escalates, passes, None
    if not isinstance(data, dict) or not isinstance(data.get("claims"), list):
        halts.append(("malformed_evidence_manifest", evidence_path.name, "manifest must be a mapping with claims list"))
        return halts, escalates, passes, None
    by_id: dict[str, dict] = {}
    for c in data["claims"]:
        if not isinstance(c, dict) or not c.get("id"):
            halts.append(("malformed_evidence_manifest", evidence_path.name, "claim entry missing id"))
            continue
        cid = str(c["id"]).strip()
        by_id[cid] = c
        st, kind = str(c.get("status", "")).strip().lower(), str(c.get("kind", "")).strip().lower()
        if kind == "absence" and st == "observed":
            _verify_absence_claim(root, code_roots, cid, c, halts, passes)
        elif st == "observed":
            _verify_observed_proof(root, code_roots, cid, c, halts, passes)
        elif st == "unknown":
            oq, crit = str(c.get("mapped_oq") or "").strip(), str(c.get("criticality", "supporting")).strip().lower()
            if (cid in ruled_items) or (oq and oq in ruled_items):
                passes.append(("unknown_claim", cid, f"ruled via {oq or cid}"))
            elif crit == "load_bearing" or stage in {"implement", "review"}:
                escalates.append(("unruled_unknown", cid, f"unruled unknown claim (criticality={crit}, stage={stage})"))
            elif not oq or (spec_oqs and oq not in spec_oqs):
                escalates.append(("unmapped_unknown_claim", cid, f"unknown claim lacks valid spec.md OQ-N mapping ({oq or 'none'})"))
            else:
                passes.append(("unknown_claim", cid, f"mapped to {oq} for Gate 1 review"))
    _evaluate_inferred_dag(by_id, ruled_items, sensitive_files, halts, escalates, passes)
    if stage in {"implement", "review"}:
        _verify_receipts(data.get("receipts"), head_shas, test_scenarios, halts, escalates, passes)
    return halts, escalates, passes, data


def resolve_repo_base(root: pathlib.Path, repo_dir: pathlib.Path, base_arg: str) -> str | None:
    def _g(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(repo_dir), *args], capture_output=True, text=True)

    if base_arg:
        if _g("rev-parse", "--verify", "--quiet", f"{base_arg}^{{commit}}").returncode != 0:
            raise ValueError(f"base ref does not resolve in {repo_dir}: {base_arg}")
        return base_arg
    cands: list[str] = []
    for sub in ("docs/agentic-sdlc/CADENCE_ORG.md", "CADENCE_ORG.md", "processes/docs/agentic-sdlc/CADENCE_ORG.md"):
        cand = repo_dir / sub
        if cand.is_file():
            m = re.search(r"integration-branch:\s*([^\s>`'\"]+)", cand.read_text(encoding="utf-8", errors="replace"))
            if m and not m.group(1).startswith("<"):
                cands.extend([f"origin/{m.group(1)}", m.group(1)])
                break
    if repo_dir != root or not cands:
        rs = _g("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        if rs.returncode == 0 and rs.stdout.strip():
            sym = rs.stdout.strip()
            cands.extend([sym, sym.split("/", 1)[-1]])
        cands.extend(["origin/main", "origin/develop", "main", "develop"])
    return next((r for r in cands + ["HEAD"] if _g("rev-parse", "--verify", "--quiet", f"{r}^{{commit}}").returncode == 0), None)


def collect_changed_files(
    root: pathlib.Path, code_roots: list[pathlib.Path], base_arg: str, root_base_ref: str | None
) -> list[tuple[str, str]]:
    multi = len(code_roots) > 1
    out: dict[str, str] = {}
    for cr in code_roots:
        cr_base = root_base_ref if cr == root else resolve_repo_base(root, cr, base_arg)
        changed: set[str] = set()
        if cr_base:
            r_diff = subprocess.run(["git", "-C", str(cr), "diff", "--name-only", f"{cr_base}...HEAD"], capture_output=True, text=True)
            if r_diff.returncode == 0:
                changed.update(p.strip() for p in r_diff.stdout.splitlines() if p.strip())
        r_st = subprocess.run(["git", "-C", str(cr), "status", "--porcelain=v1", "-uall"], capture_output=True, text=True)
        if r_st.returncode == 0:
            for line in r_st.stdout.splitlines():
                if len(line) >= 4:
                    changed.add(line[3:].strip().split(" -> ")[-1].strip().strip('"'))
        for rel in changed:
            disp = f"{cr.name}:{rel}" if multi else rel
            out[disp] = rel
    return [(rel, disp) for disp, rel in sorted(out.items())]
