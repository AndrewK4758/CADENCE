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
    if not rel_str or rel_str.startswith("/"):
        return None
    p = pathlib.PurePosixPath(rel_str)
    if ".." in p.parts:
        return None
    resolved = (root / rel_str).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def _read_repo_file_lines(root: pathlib.Path, rel_str: str) -> list[str] | None:
    target = _is_safe_rel(root, rel_str)
    if target is None:
        return None
    if target.is_file():
        return target.read_text(encoding="utf-8", errors="replace").splitlines()
    res = subprocess.run(
        ["git", "-C", str(root), "cat-file", "-p", f"HEAD:{rel_str}"],
        capture_output=True, text=True,
    )
    if res.returncode == 0:
        return res.stdout.splitlines()
    return None


def _parse_ref(ref_str: str) -> tuple[str, int, int] | None:
    m = re.match(r"^([^:\s]+):(\d+)(?:-(\d+))?$", str(ref_str).strip())
    if not m:
        return None
    path = m.group(1).lstrip("./")
    start = int(m.group(2))
    end = int(m.group(3) or start)
    return path, start, end


def _verify_observed_proof(root: pathlib.Path, cid: str, claim: dict, halts: list, passes: list) -> None:
    proof = claim.get("proof")
    if not isinstance(proof, dict) or not proof.get("ref"):
        halts.append(("missing_proof", cid, "observed non-absence claim lacks proof.ref"))
        return
    parsed = _parse_ref(proof["ref"])
    if not parsed:
        halts.append(("hallucinated_ref", cid, f"invalid proof.ref syntax: {proof['ref']!r}"))
        return
    rel_path, start, end = parsed
    lines = _read_repo_file_lines(root, rel_path)
    if lines is None:
        halts.append(("hallucinated_ref", cid, f"cited file missing or outside repo: {rel_path}"))
        return
    if start < 1 or end < start or end > len(lines):
        halts.append(("ref_out_of_bounds", cid, f"{rel_path}:{start}-{end} exceeds file length {len(lines)}"))
        return

    win = "\n".join(lines[max(0, start - 6) : min(len(lines), end + 5)])
    for sym in proof.get("symbols") or []:
        if str(sym) not in win:
            halts.append(("missing_symbol", cid, f"symbol {sym!r} not found near {rel_path}:{start}-{end}"))
            return

    anchor = proof.get("anchor_substring")
    if anchor:
        slice_txt = "\n".join(lines[start - 1 : end])
        if str(anchor) not in slice_txt:
            halts.append(("anchor_mismatch", cid, f"anchor_substring not found inside {rel_path}:{start}-{end}"))
            return
    passes.append(("observed_proof", cid, f"{rel_path}:{start}-{end}"))


def _list_scope_files(root: pathlib.Path, scope: str) -> list[str] | None:
    scope_clean = scope.strip().rstrip("/") or "."
    if scope_clean != "." and _is_safe_rel(root, scope_clean) is None:
        return None
    ls = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "--", scope_clean],
        capture_output=True, text=True,
    )
    rels: list[str] = []
    if ls.returncode == 0:
        candidates = [line.strip() for line in ls.stdout.splitlines() if line.strip()]
    else:
        base = root if scope_clean == "." else (root / scope_clean)
        if base.is_file():
            candidates = [scope_clean]
        elif base.is_dir():
            candidates = [
                p.relative_to(root).as_posix()
                for p in base.rglob("*") if p.is_file()
            ]
        else:
            candidates = []
    for rel in sorted(set(candidates)):
        if rel.startswith(SKIP_PREFIXES) or pathlib.PurePosixPath(rel).suffix.lower() in BIN_EXTS:
            continue
        if (root / rel).is_file():
            rels.append(rel)
    return rels


def _verify_absence_claim(root: pathlib.Path, cid: str, claim: dict, halts: list, passes: list) -> None:
    proof = claim.get("proof")
    if not isinstance(proof, dict) or not proof.get("search_pattern") or not proof.get("scope"):
        halts.append(("missing_absence_proof", cid, "absence claim requires proof.search_pattern and proof.scope"))
        return
    try:
        pat = re.compile(str(proof["search_pattern"]))
    except re.error as exc:
        halts.append(("invalid_absence_regex", cid, f"invalid search_pattern: {exc}"))
        return

    rels = _list_scope_files(root, str(proof["scope"]))
    if rels is None:
        halts.append(("hallucinated_ref", cid, f"invalid or unsafe scope: {proof['scope']!r}"))
        return

    expected = {str(p).strip().lstrip("./") for p in (proof.get("expected_files") or []) if str(p).strip()}
    unexpected: list[str] = []
    for rel in rels:
        try:
            txt = (root / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if pat.search(txt) and rel not in expected:
            unexpected.append(rel)

    if unexpected:
        halts.append(("falsified_absence", cid, f"unexpected match(es) for {proof['search_pattern']!r}: {', '.join(unexpected[:5])}"))
    else:
        passes.append(("absence_proof", cid, f"scope={proof['scope']} matched expected={len(expected)} file(s)"))


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


def _verify_receipts(
    receipts: object,
    head_sha: str,
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
        if not rsha or not head_sha or not (head_sha.lower().startswith(rsha) or rsha.startswith(head_sha.lower())) or len(rsha) < 7:
            halts.append(("stale_test_receipt", target, f"receipt head_sha={rsha!r} != HEAD {head_sha[:12]}"))
            continue
        if rec.get("exit_code") != 0:
            halts.append(("failing_test_receipt", target, f"test_suite exit_code={rec.get('exit_code')!r} != 0"))
            continue
        raw_log = str(rec.get("raw_log") or "").strip()
        exp_hash = str(rec.get("raw_log_sha256") or "").strip().lower()
        if raw_log and exp_hash:
            lp = pathlib.Path(raw_log).expanduser()
            if lp.is_file():
                actual = hashlib.sha256(lp.read_bytes()).hexdigest().lower()
                if actual != exp_hash:
                    halts.append(("receipt_log_hash_mismatch", target, f"raw_log sha256 mismatch for {raw_log}"))
                    continue
            else:
                escalates.append(("receipt_log_missing", target, f"raw_log missing on disk: {raw_log}"))
                continue
        valid_suite += 1
        for sid in rec.get("scenarios_observed_passing") or []:
            covered.add(str(sid).strip())
        passes.append(("test_receipt", target, f"head={rsha[:12]} exit=0"))

    if valid_suite > 0 and test_scenarios and covered:
        missing = sorted(s for s in test_scenarios if s not in covered)
        if missing:
            halts.append(("unexecuted_scenarios", "receipts", f"test-plan scenarios missing from passing receipt: {', '.join(missing[:8])}"))


def evaluate_evidence(
    root: pathlib.Path,
    evidence_path: pathlib.Path,
    stage: str,
    head_sha: str,
    ruled_items: set[str],
    spec_oqs: set[str],
    test_scenarios: set[str],
    sensitive_files: set[str],
) -> tuple[list, list, list]:
    halts: list = []
    escalates: list = []
    passes: list = []
    try:
        data = yaml.safe_load(evidence_path.read_text(encoding="utf-8", errors="replace"))
    except Exception as exc:
        halts.append(("malformed_evidence_manifest", evidence_path.name, f"YAML parse error: {exc}"))
        return halts, escalates, passes

    if not isinstance(data, dict) or not isinstance(data.get("claims"), list):
        halts.append(("malformed_evidence_manifest", evidence_path.name, "manifest must be a mapping with claims list"))
        return halts, escalates, passes

    by_id: dict[str, dict] = {}
    for c in data["claims"]:
        if not isinstance(c, dict) or not c.get("id"):
            halts.append(("malformed_evidence_manifest", evidence_path.name, "claim entry missing id"))
            continue
        cid = str(c["id"]).strip()
        by_id[cid] = c
        st = str(c.get("status", "")).strip().lower()
        kind = str(c.get("kind", "")).strip().lower()
        if kind == "absence" and st == "observed":
            _verify_absence_claim(root, cid, c, halts, passes)
        elif st == "observed":
            _verify_observed_proof(root, cid, c, halts, passes)
        elif st == "unknown":
            oq = str(c.get("mapped_oq") or "").strip()
            crit = str(c.get("criticality", "supporting")).strip().lower()
            is_ruled = (cid in ruled_items) or (oq and oq in ruled_items)
            if is_ruled:
                passes.append(("unknown_claim", cid, f"ruled via {oq or cid}"))
            elif crit == "load_bearing" or stage in {"implement", "review"}:
                escalates.append(("unruled_unknown", cid, f"unruled unknown claim (criticality={crit}, stage={stage})"))
            elif not oq or (spec_oqs and oq not in spec_oqs):
                escalates.append(("unmapped_unknown_claim", cid, f"unknown claim lacks valid spec.md OQ-N mapping ({oq or 'none'})"))
            else:
                passes.append(("unknown_claim", cid, f"mapped to {oq} for Gate 1 review"))

    _evaluate_inferred_dag(by_id, ruled_items, sensitive_files, halts, escalates, passes)
    if stage in {"implement", "review"}:
        _verify_receipts(data.get("receipts"), head_sha, test_scenarios, halts, escalates, passes)
    return halts, escalates, passes
