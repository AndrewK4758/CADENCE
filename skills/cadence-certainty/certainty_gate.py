#!/usr/bin/env python3
"""Deterministic Hybrid Certainty & Human-Escalation Gate (Layer 1 + Layer 2)."""
import argparse
import fnmatch
import pathlib
import re
import subprocess
import sys

from certainty_claims import collect_changed_files, evaluate_evidence, resolve_repo_base
from certainty_completeness import (
    check_known_risks_and_precedence,
    check_out_of_scope_overlap,
    check_review_anomalies,
    check_shared_invariant_absence,
    resolve_completeness_strictness,
)

SELF_DIR = pathlib.Path(__file__).resolve().parent


def _git(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


def _read_scalar(meta_path: pathlib.Path, key: str) -> str | None:
    for raw in meta_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(rf"^\s*{re.escape(key)}:\s*(.*)$", raw)
        if not m:
            continue
        val = m.group(1).strip()
        if not val:
            return ""
        for q in ('"', "'"):
            if val.startswith(q):
                end = val.find(q, 1)
                return val[1:end].strip() if end != -1 else val.strip()
        return re.sub(r"\s+#.*$", "", val).strip()
    return None


def _parse_ruled_items(decisions_path: pathlib.Path) -> set[str]:
    ruled: set[str] = set()
    if not decisions_path.is_file():
        return ruled
    in_fence = False
    for raw in decisions_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.match(r"^\s*```", raw):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m_gate = re.match(r"^Gate\s+[1-3]\s+ruling:\s+([A-Za-z0-9._-]+)\s+--\s+(?:agree|amend|override)\s+--\s+.+$", raw)
        if m_gate:
            ruled.add(m_gate.group(1).strip())
            continue
        if re.match(r"^Gate\s+1\s+Design\s+Exploration\s+outcome:\s+(?:accepted as recommended|accepted with amendment|overridden to a different option)\s+--\s+.+$", raw):
            ruled.add("design")
            continue
        m_dec = re.match(r"^(?:##\s+DEC-\d+.*|-\s*\*\*Ruled:\*\*\s*)(.+)$", raw)
        if m_dec:
            tok_re = r"\b(?:CLM-\d+|OQ-\d+|unknowns|probes|scope|oscillation|draft|known_risks|absence_waiver|anomaly_waiver|rationalization_waiver|scope_exclusion|completeness_strictness)\b"
            for tok in re.findall(tok_re, m_dec.group(1)):
                ruled.add(tok)
    return ruled


def _extract_spec_oqs(spec_path: pathlib.Path) -> set[str]:
    if not spec_path.is_file():
        return set()
    in_oq, oqs = False, set()
    for raw in spec_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.match(r"^#{2,3}\s+Open Questions\b", raw, re.I):
            in_oq = True
            continue
        if in_oq and re.match(r"^#{1,3}\s+", raw):
            in_oq = False
        if in_oq:
            oqs.update(re.findall(r"\bOQ-\d+\b", raw))
    return oqs


def _extract_test_scenarios(test_plan_path: pathlib.Path) -> set[str]:
    if not test_plan_path.is_file():
        return set()
    out: set[str] = set()
    for raw in test_plan_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "{" in raw or "}" in raw:
            continue
        m = re.match(r"^\s*Scenario(?:\s+Outline)?:\s*((?:S|OS)-\d+\.\d+)\b", raw)
        if m:
            out.add(m.group(1))
    return out


def _is_test_or_doc_path(rel: str) -> bool:
    if rel.startswith(("specs/", "archive/", "docs/")) or rel in {"CHANGELOG.md", "README.md", "PROJECT_INTENT.md"}:
        return True
    p = pathlib.PurePosixPath(rel)
    if any(part in {"tests", "test", "__tests__"} for part in p.parts[:-1]):
        return True
    name = p.name.lower()
    return name.startswith("test_") or ".test." in name or "_test." in name or name.endswith(".spec.ts") or name.endswith(".spec.js")


def _parse_files_affected(spec_path: pathlib.Path, ticket: str) -> list[str]:
    lines = spec_path.read_text(encoding="utf-8", errors="replace").splitlines()

    def _scan_section(heading_re: str, stop_re: str, require_file_col: bool) -> list[str]:
        rows, in_sec, rownum, in_tbl = [], False, 0, False
        for raw in lines:
            if re.match(heading_re, raw, re.I):
                in_sec, rownum, in_tbl = True, 0, False
                continue
            if in_sec and re.match(stop_re, raw):
                break
            if in_sec and raw.lstrip().startswith("|"):
                cols = [c.strip() for c in raw.strip().strip("|").split("|")]
                if not in_tbl:
                    if require_file_col and (not cols or cols[0].lower() not in {"file", "path"}):
                        continue
                    in_tbl, rownum = True, 1
                    continue
                rownum += 1
                if rownum == 2:
                    continue
                fpath = cols[0].strip("` ").lstrip("./") if cols else ""
                if fpath and not fpath.startswith((f"specs/{ticket}/", f"archive/{ticket}/")):
                    rows.append(fpath)
            elif in_tbl:
                in_tbl, rownum = False, 0
        return rows

    return _scan_section(r"^###\s+Files Affected\b", r"^#", False) or _scan_section(r"^##\s+Proposed Design\b", r"^##\s+", True)


def _is_pillar_dormant(spec_path: pathlib.Path, heading_re: str) -> bool:
    in_sec = False
    for raw in spec_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.match(rf"^(?:[-*]\s*)?(?:\*\*)?{heading_re}(?:\*\*)?:\s*(?:dormant|not triggered)\b", raw, re.I):
            return True
        if re.match(rf"^#{{3,4}}\s+(?:(?:Pillar|Facet)\s+\d+:\s*)?{heading_re}", raw, re.I):
            in_sec = True
            continue
        if in_sec and re.match(r"^#{1,4}\s+", raw):
            in_sec = False
        elif in_sec and re.search(r"\b(?:dormant|not triggered)\b", raw, re.I):
            return True
    return False


def _locate_sibling(root: pathlib.Path, rel_subpath: str) -> pathlib.Path | None:
    for base in (SELF_DIR.parent, root / ".agents" / "skills", root / "skills"):
        cand = base / rel_subpath
        if cand.is_file():
            return cand
    return None


def _run_layer1(
    root: pathlib.Path,
    code_roots: list[pathlib.Path],
    base_arg: str,
    ticket: str,
    ticket_dir: pathlib.Path,
    tier: str,
    stage: str,
    base_ref: str | None,
    ruled_items: set[str],
    spec_oqs: set[str],
) -> tuple[list, list, list, set[str]]:
    halts, escalates, passes = [], [], []
    sensitive_files: set[str] = set()
    prob_path = ticket_dir / "problem.md"
    spec_path = ticket_dir / "spec.md"
    opts_path = ticket_dir / "design-options.md"
    sub_path = ticket_dir / "submission.md"

    # 1. Unanswered probes
    if tier in {"medium", "high"} and prob_path.is_file():
        in_fence, unans = False, 0
        for raw in prob_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^\s*```", raw):
                in_fence = not in_fence; continue
            if not in_fence and "_(not yet answered)_" in raw:
                unans += 1
        if unans > 0 and "probes" not in ruled_items:
            escalates.append(("unanswered_probes", "problem.md", f"{unans} probe(s) still marked _(not yet answered)_"))
        else:
            passes.append(("probes", "problem.md", "0 unanswered probes"))

    # 2. Unmapped UNKNOWNs & Draft/Open contracts
    unk_count = 0
    if opts_path.is_file():
        for raw in opts_path.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*-\s*(?:\*\*)?Failure modes \(UNKNOWN\)(?::\*\*|\*\*:\s*|:\s*)(.*)$", raw)
            if m and m.group(1).strip().strip("*` ").strip().lower() not in {"", "none", "n/a", "-"}:
                unk_count += 1
    draft_count = 0
    for md in ticket_dir.glob("*.md"):
        for raw in md.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^\s*#\s*STATUS:\s*(?:Draft|Open question)\b", raw, re.I):
                draft_count += 1
    if tier in {"medium", "high"} and spec_path.is_file():
        if stage == "spec" and (unk_count > 0 or draft_count > 0) and not spec_oqs and "unknowns" not in ruled_items:
            escalates.append(("unmapped_unknowns", "spec.md", f"found {unk_count} UNKNOWN failure mode(s) and {draft_count} Draft/Open contract(s) with no OQ-N in spec.md"))
        elif stage in {"implement", "review"} and draft_count > 0 and "draft" not in ruled_items and "unknowns" not in ruled_items:
            escalates.append(("unpromoted_draft_contract", "specs", f"{draft_count} '# STATUS: Draft/Open question' contract(s) remain unpromoted"))
        else:
            passes.append(("unknowns_mapped", "spec.md", f"unknowns={unk_count} drafts={draft_count} oqs={len(spec_oqs)}"))

    # 3. Reverse blast-radius drift & Out-of-Scope overlap
    changed_pairs: list[tuple[str, str]] = []
    if stage in {"implement", "review"} and (base_ref or len(code_roots) > 1 or code_roots[0] != root):
        try:
            changed_pairs = collect_changed_files(root, code_roots, base_arg, base_ref)
        except ValueError as exc:
            sys.exit(f"ERROR: {exc}")
        if tier in {"medium", "high"} and spec_path.is_file():
            affected = _parse_files_affected(spec_path, ticket)
            if affected:
                cr_prefixes = tuple(f"{cr.name}:" for cr in code_roots)
                norm_aff = affected + [p.split(":", 1)[1].lstrip("./") for p in affected if p.startswith(cr_prefixes)]
                undeclared = sorted(
                    disp for rel, disp in changed_pairs
                    if not _is_test_or_doc_path(rel)
                    and not any(fnmatch.fnmatch(disp, pat) or disp == pat or fnmatch.fnmatch(rel, pat) or rel == pat for pat in norm_aff)
                )
                if undeclared and "scope" not in ruled_items:
                    escalates.append(("undeclared_blast_radius", "git-diff", f"modified file(s) outside spec.md Files Affected: {', '.join(undeclared[:6])}"))
                else:
                    passes.append(("blast_radius", "git-diff", "all modified production files declared in Files Affected"))

    # 4. Dormant Security / Data pillar vs security-trigger.sh
    sec_script = _locate_sibling(root, "cadence-review/security-trigger.sh")
    if sec_script and tier in {"low", "medium", "high"}:
        cmd = ["bash", str(sec_script), "--root", str(root), "--scan-signals"]
        for cr in code_roots:
            if cr != root or len(code_roots) > 1:
                cmd += ["--code-root", str(cr)]
        if base_arg:
            cmd += ["--base", base_arg]
        elif len(code_roots) == 1 and code_roots[0] == root and base_ref:
            cmd += ["--base", base_ref]
        cmd.append(ticket)
        sr = subprocess.run(cmd, capture_output=True, text=True)
        if sr.returncode == 0:
            m_sig = re.search(r"\bsignals=([^\s]+)", sr.stdout)
            m_files = re.search(r"\bfiles=([^\s]+)", sr.stdout)
            sigs = set(m_sig.group(1).split(",")) if m_sig and m_sig.group(1) != "none" else set()
            if m_files and m_files.group(1) != "diff":
                sensitive_files.update(m_files.group(1).split(","))
            if stage in {"implement", "review"} and spec_path.is_file() and "decision=TRIGGER" in sr.stdout:
                if (sigs & {"auth", "secrets_crypto", "untrusted_exec"}) and _is_pillar_dormant(spec_path, r"Security(?: Boundary)? Posture"):
                    halts.append(("dormant_security_contradicted", "spec.md", f"Security Boundary Posture marked dormant while diff matched {sorted(sigs)}"))
                if ("data_sql" in sigs) and _is_pillar_dormant(spec_path, r"Data\s*(?:&|and)\s*Audit|Data Integrity"):
                    halts.append(("dormant_data_contradicted", "spec.md", "Data & Audit Fidelity marked dormant while diff matched data_sql"))

    # 5. verify-facts.sh UNVERIFIABLE ratio
    vf_script = _locate_sibling(root, "cadence-spec/verify-facts.sh")
    if vf_script and tier in {"medium", "high"} and spec_path.is_file():
        cmd = ["bash", str(vf_script), "--root", str(root)]
        if base_ref:
            cmd += ["--base", base_ref]
        cmd.append(ticket)
        vr = subprocess.run(cmd, capture_output=True, text=True)
        m_sum = re.search(r"SUMMARY\s+pass=(\d+)\s+fail=(\d+)\s+warn=(\d+)\s+unverifiable=(\d+)", vr.stdout)
        if vr.returncode != 0 or (m_sum and int(m_sum.group(2)) > 0):
            halts.append(("verify_facts_failed", "spec.md", "verify-facts.sh reported FAIL citation(s)"))
        elif m_sum:
            p_cnt, u_cnt = int(m_sum.group(1)), int(m_sum.group(4))
            if (p_cnt + u_cnt) > 0 and (u_cnt / (p_cnt + u_cnt)) > 0.25 and "citations" not in ruled_items:
                escalates.append(("high_unverifiable_ratio", "spec.md", f"verify-facts unverifiable ratio {u_cnt}/{p_cnt + u_cnt} > 25%"))

    # 6. Review cycle oscillation
    if stage in {"implement", "review"} and sub_path.is_file():
        cycles = [
            int(m.group(1))
            for m in re.finditer(r"<!--\s*cadence-run:cycle\s+n=\d+\s+phase=code-review\s+blocking=(\d+)\b", sub_path.read_text(encoding="utf-8", errors="replace"))
        ]
        if len(cycles) >= 2 and cycles[-1] > 0 and cycles[-1] >= cycles[-2] and "oscillation" not in ruled_items:
            escalates.append(("cycle_oscillation", "submission.md", f"non-decreasing blocking defects across cycles ({cycles[-2]} -> {cycles[-1]})"))

    return halts, escalates, passes, sensitive_files, changed_pairs


def main() -> int:
    ap = argparse.ArgumentParser(description="Empirical CADENCE certainty & human-escalation gate")
    ap.add_argument("--root", default="")
    ap.add_argument("--code-root", action="append", default=[], dest="code_roots")
    ap.add_argument("--base", default="")
    ap.add_argument("--stage", default="auto", choices=["auto", "spec", "implement", "review"])
    ap.add_argument("--strictness", default="auto", choices=["auto", "halt", "escalate", "strict", "advisory"])
    ap.add_argument("--require-evidence", action="store_true")
    ap.add_argument("ticket")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve() if args.root else pathlib.Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
    ).resolve()
    code_roots = [pathlib.Path(p).resolve() for p in args.code_roots] if args.code_roots else [root]
    for cr in code_roots:
        if not cr.is_dir():
            print(f"ERROR: --code-root is not a directory: {cr}", file=sys.stderr)
            return 1

    ticket_dir = root / "specs" / args.ticket
    if not ticket_dir.is_dir():
        ticket_dir = root / "archive" / args.ticket
    if not ticket_dir.is_dir():
        print(f"ERROR: no artifacts for {args.ticket} -- searched specs/{args.ticket}/ and archive/{args.ticket}/", file=sys.stderr)
        return 1

    meta_path = ticket_dir / "metadata.yaml"
    if not meta_path.is_file():
        print(f"ERROR: cannot resolve tier -- missing {meta_path}", file=sys.stderr)
        return 1

    raw_tier = _read_scalar(meta_path, "tier")
    tier = (raw_tier or "").strip().lower()
    if tier not in {"trivial", "low", "medium", "high"}:
        print(f"ERROR: unrecognized tier {raw_tier!r} in {meta_path}", file=sys.stderr)
        return 1
    if tier == "trivial":
        print("decision=PROCEED tier=trivial stage=exempt grade=EXEMPT layer=1 halt=0 escalate=0 triggers=none strictness=exempt")
        return 0

    status = (_read_scalar(meta_path, "status") or "").strip().lower()
    stage = args.stage
    if stage == "auto":
        stage = "implement" if status == "in-progress" else ("review" if status in {"in-review", "merged", "archived"} else "spec")

    try:
        base_ref = resolve_repo_base(root, root, args.base if root in code_roots else "")
        if args.base:
            for cr in code_roots:
                resolve_repo_base(root, cr, args.base)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    head_shas = {root.name: _git(root, "rev-parse", "HEAD").stdout.strip()}
    for cr in code_roots:
        head_shas[cr.name] = _git(cr, "rev-parse", "HEAD").stdout.strip()
    ruled_items = _parse_ruled_items(ticket_dir / "decisions.md")
    spec_path = ticket_dir / "spec.md"
    test_plan_path = ticket_dir / "test-plan.md"
    spec_oqs = _extract_spec_oqs(spec_path)
    test_scenarios = _extract_test_scenarios(test_plan_path)
    strict_mode, strict_src, strict_detail = resolve_completeness_strictness(root, code_roots, args.strictness)

    halts, escalates, passes, sensitive_files, changed_pairs = _run_layer1(
        root, code_roots, args.base, args.ticket, ticket_dir, tier, stage, base_ref, ruled_items, spec_oqs,
    )
    if strict_mode == "unconfigured" and "completeness_strictness" not in ruled_items:
        escalates.append(("completeness_strictness_unconfigured", strict_src, f"{strict_detail} -- prompt operator or pass --strictness halt|escalate"))
    else:
        passes.append(("completeness_strictness", strict_src, f"mode={strict_mode} ({strict_detail})"))

    check_known_risks_and_precedence(spec_path, ticket_dir / "design-options.md", tier, stage, ruled_items, spec_oqs, strict_mode, halts, escalates, passes)
    check_review_anomalies(ticket_dir / "submission.md", stage, ruled_items, strict_mode, halts, escalates, passes)
    check_out_of_scope_overlap(ticket_dir / "problem.md", spec_path, changed_pairs, stage, ruled_items, spec_oqs, strict_mode, halts, escalates, passes)

    ev_path, layer, ev_data = ticket_dir / "evidence.yaml", "1", None
    if ev_path.is_file():
        layer = "1+2"
        h2, e2, p2, ev_data = evaluate_evidence(root, code_roots, ev_path, stage, head_shas, ruled_items, spec_oqs, test_scenarios, sensitive_files)
        halts.extend(h2); escalates.extend(e2); passes.extend(p2)
    elif args.require_evidence or (spec_path.is_file() and "**Evidence manifest:** required" in spec_path.read_text(encoding="utf-8", errors="replace")):
        halts.append(("missing_evidence_manifest", "evidence.yaml", "evidence manifest required but absent"))

    check_shared_invariant_absence(spec_path, test_plan_path, ev_data, tier, args.require_evidence, sensitive_files, ruled_items, _is_pillar_dormant, strict_mode, halts, escalates, passes)

    for code, tgt, msg in passes:
        print(f"PASS {code} {tgt} -- {msg}")
    for code, tgt, msg in escalates:
        print(f"ESCALATE {code} {tgt} -- {msg}")
    for code, tgt, msg in halts:
        print(f"HALT {code} {tgt} -- {msg}")

    triggers = sorted({c for c, _, _ in halts + escalates})
    trig_str = ",".join(triggers) if triggers else "none"
    if halts:
        decision, grade, rc = "HALT", "INSUFFICIENT", 1
    elif escalates:
        decision, grade, rc = "ESCALATE_HUMAN", "CONDITIONAL", 2
    else:
        decision, grade, rc = "PROCEED", "VERIFIED", 0

    print(f"decision={decision} tier={tier} stage={stage} grade={grade} layer={layer} halt={len(halts)} escalate={len(escalates)} triggers={trig_str} strictness={strict_mode}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
