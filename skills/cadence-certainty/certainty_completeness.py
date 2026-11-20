#!/usr/bin/env python3
"""Domain-neutral completeness & anti-exclusion checks for certainty-gate.sh."""
import pathlib
import re

LOWER_PILLARS = ("structural simplicity", "simplicity", "agentic ergonomics", "developer experience", "dx")
HIGHER_PILLAR_RE = re.compile(r"data\s*(?:&|and)\s*audit|data\s+integrity|security(?:\s+boundary)?\s+posture", re.I)
RATIONALIZATION_RE = re.compile(
    r"(?i)(?:"
    r"(?:next|future|subsequent|periodic|nightly|eventual)\s+(?:poll|cron|sweep|sync|job|tick|cycle|reconcil\w*)"
    r"[^\n]{0,40}(?:clear|fix|heal|reconcil|restor|resolv|correct|recover)"
    r"|practically\s+unreachable"
    r"|low\s+likelihood\s+in\s+normal"
    r"|only\s+happens\s+(?:if|when)\s+(?:stopped|cancelled|canceled|refreshed|reloaded|restarted|retried)"
    r")"
)
RISK_OQ_RE = re.compile(
    r"(?i)\b(?:known|risk|trade-?off|pillar|precedence|option\s+[a-z]|sibling|out\s+of\s+scope|"
    r"durab\w*|idempoten\w*|ttl|expir\w*|stale|race|ambigu\w*|reset|reload|fallback)\b"
)
SHARED_BOUNDARY_RE = re.compile(
    r"(?i)\b(?:CP-04|CP-05|CP-12|CP-13|CP-14|Journey\s+Invariants|irreversible\s+external|"
    r"post-lock|shared\s+(?:sink|invariant|writer)|idempoten\w*)\b"
)


def _strip_fences(text: str) -> list[str]:
    out, in_fence = [], False
    for raw in text.splitlines():
        if re.match(r"^\s*```", raw):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append(raw)
    return out


def _read_marker(text: str, name: str) -> str | None:
    pat = re.compile(rf"<!--\s*{re.escape(name)}\s*:\s*(.*?)\s*-->", re.I)
    for raw in _strip_fences(text):
        m = pat.search(raw)
        if m:
            val = m.group(1).strip()
            if val and not (val.startswith("<") and val.endswith(">")) and "{{" not in val:
                return val
    return None


def _parse_team_multi(val: str) -> bool | None:
    low = val.strip().lower()
    if low in {"1", "solo", "single"}:
        return False
    if low in {">1", ">=2", "2+", "team", "multi", "multiple"}:
        return True
    m = re.fullmatch(r"(\d+)(?:\+)?", low)
    if m:
        n = int(m.group(1))
        if n >= 2:
            return True
        if n == 1:
            return False
    return None


def _parse_bool(val: str) -> bool | None:
    low = val.strip().lower()
    if low in {"yes", "true", "on", "enforced", "1"}:
        return True
    if low in {"no", "false", "off", "disabled", "0"}:
        return False
    return None


def resolve_completeness_strictness(
    root: pathlib.Path, code_roots: list[pathlib.Path], cli_strictness: str
) -> tuple[str, str, str]:
    """Resolve completeness enforcement strictness: CLI override -> repo MD -> unconfigured."""
    cli = (cli_strictness or "auto").strip().lower()
    if cli in {"halt", "strict"}:
        return "halt", "command-override", "explicit --strictness halt"
    if cli in {"escalate", "advisory"}:
        return "escalate", "command-override", "explicit --strictness escalate"

    candidates: list[tuple[pathlib.Path, str]] = []
    seen: set[pathlib.Path] = set()
    for base in [root, *[cr for cr in code_roots if cr != root]]:
        for rel in (
            "docs/agentic-sdlc/CADENCE_ORG.md",
            "CADENCE_ORG.md",
            "AGENTS.md",
            "GEMINI.md",
            "CLAUDE.md",
        ):
            p = (base / rel).resolve()
            if p not in seen and p.is_file():
                seen.add(p)
                label = rel if base == root else f"{base.name}:{rel}"
                candidates.append((p, label))

    for path, label in candidates:
        txt = path.read_text(encoding="utf-8", errors="replace")
        pinned = _read_marker(txt, "completeness-strictness")
        ts_raw = _read_marker(txt, "team-size")
        er_raw = _read_marker(txt, "enforce-review")
        if pinned:
            plow = pinned.lower()
            if plow in {"halt", "strict"}:
                return "halt", label, f"completeness-strictness={pinned}"
            if plow in {"escalate", "advisory"}:
                return "escalate", label, f"completeness-strictness={pinned}"
            if plow != "auto":
                return "unconfigured", label, f"unrecognized completeness-strictness={pinned!r}"
        if ts_raw is not None and er_raw is not None:
            multi = _parse_team_multi(ts_raw)
            enforced = _parse_bool(er_raw)
            if multi is not None and enforced is not None:
                mode = "halt" if (multi and enforced) else "escalate"
                return mode, label, f"team-size={ts_raw} enforce-review={er_raw}"
            return "unconfigured", label, f"invalid team-size={ts_raw!r} or enforce-review={er_raw!r}"
        if ts_raw is not None or er_raw is not None:
            return "unconfigured", label, f"partial binding (team-size={ts_raw!r}, enforce-review={er_raw!r})"

    return (
        "unconfigured",
        "absent",
        "no team-size/enforce-review or completeness-strictness markers in CADENCE_ORG.md or repo-level AGENTS.md/GEMINI.md/CLAUDE.md",
    )


def _emit(mode: str, halts: list, escalates: list, code: str, target: str, msg: str) -> None:
    if mode == "halt":
        halts.append((code, target, msg))
    else:
        escalates.append((code, target, msg))


def _slice_option(opts_txt: str, opt_label: str) -> str:
    m = re.search(rf"(?ms)^##\s+{re.escape(opt_label)}\b.*?(?=^##\s+|\Z)", opts_txt)
    return m.group(0) if m else ""


def _extract_oq_text(spec_txt: str) -> str:
    m = re.search(r"(?ms)^#{2,3}\s+Open Questions\b.*?(?=^#{1,2}\s+|\Z)", spec_txt)
    return m.group(0) if m else ""


def _parse_winner(spec_txt: str) -> tuple[str | None, str]:
    sec_m = re.search(r"(?ms)^##\s+Design Exploration\b.*?(?=^##\s+|\Z)", spec_txt)
    if not sec_m:
        return None, ""
    blk = sec_m.group(0)
    m_win = re.search(
        r"(?im)^[-*\s]*(?:\*\*)?(?:Winner|Selected\s+(?:winner|option))(?::\*\*|\*\*:|:)\s*(Option\s+[A-Z])\b",
        blk,
    )
    return (m_win.group(1) if m_win else None), blk


def check_known_risks_and_precedence(
    spec_path: pathlib.Path,
    opts_path: pathlib.Path,
    tier: str,
    stage: str,
    ruled_items: set[str],
    spec_oqs: set[str],
    mode: str,
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    if tier not in {"medium", "high"} or not spec_path.is_file() or not opts_path.is_file():
        return
    spec_txt = spec_path.read_text(encoding="utf-8", errors="replace")
    opts_txt = opts_path.read_text(encoding="utf-8", errors="replace")
    win_opt, expl_blk = _parse_winner(spec_txt)
    if not win_opt:
        return
    opt_sec = _slice_option(opts_txt, win_opt)
    if not opt_sec:
        return

    high_known = []
    for line in _strip_fences(opt_sec):
        if re.search(r"\[[^\]]*Severity:\s*HIGH[^\]]*\]", line, re.I):
            high_known.append(line.strip())
        elif re.search(r"\[[^\]]*Pillar:\s*[^\]]*\]", line, re.I) and HIGHER_PILLAR_RE.search(line):
            if not re.search(r"Severity:\s*LOW", line, re.I):
                high_known.append(line.strip())

    oq_txt = _extract_oq_text(spec_txt)
    has_risk_oq = bool(spec_oqs) and bool(RISK_OQ_RE.search(oq_txt))
    oq_ruled = any(oq in ruled_items for oq in spec_oqs)
    ruled_known = ("known_risks" in ruled_items) or (stage == "spec" and has_risk_oq) or (stage != "spec" and has_risk_oq and oq_ruled)

    if high_known and not ruled_known:
        _emit(
            mode, halts, escalates, "unruled_known_risk", "design-options.md",
            f"{win_opt} retains {len(high_known)} unmitigated HIGH/Rank-1-2 KNOWN failure mode(s) without Gate 1 OQ-N or known_risks ruling",
        )
    elif high_known:
        passes.append(("known_risks", "design-options.md", f"{win_opt} high-impact KNOWN mode(s) mapped/ruled"))

    axis_m = re.search(r"(?im)^[-*\s]*(?:\*\*)?(?:Winning\s+axis|Decisive\s+pillar)[^:\n]*:(?:\*\*)?\s*(.+)$", expl_blk)
    if axis_m:
        axis_low = axis_m.group(1).lower()
        picked_lower = any(tok in axis_low for tok in LOWER_PILLARS) and not HIGHER_PILLAR_RE.search(axis_low)
        higher_flagged = bool(
            re.search(r"(?ms)^###\s+(?:Pillar|Facet)\s+[46]:.*?(?=^###\s+|\Z)", spec_txt)
            and any(
                re.search(r"\|\s*Flag\s*\|", m.group(0), re.I)
                for m in re.finditer(r"(?ms)^###\s+(?:Pillar|Facet)\s+[46]:.*?(?=^###\s+|\Z)", spec_txt)
            )
        )
        if picked_lower and (high_known or higher_flagged) and not ruled_known:
            _emit(
                mode, halts, escalates, "pillar_precedence_inversion", "spec.md",
                f"{win_opt} selected on lower-ranked pillar while active higher-ranked pillar has unmitigated Flag/KNOWN risk without Gate 1 ruling",
            )


def check_shared_invariant_absence(
    spec_path: pathlib.Path,
    test_plan_path: pathlib.Path,
    ev_data: dict | None,
    tier: str,
    require_evidence: bool,
    sensitive_files: set[str],
    ruled_items: set[str],
    is_pillar_dormant_fn,
    mode: str,
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    if tier not in {"medium", "high"} or not spec_path.is_file() or ev_data is None:
        return
    if "absence_waiver" in ruled_items:
        passes.append(("shared_invariant_absence", "evidence.yaml", "waived via decisions.md absence_waiver"))
        return
    di_active = not is_pillar_dormant_fn(spec_path, r"Data\s*(?:&|and)\s*Audit|Data Integrity")
    sec_active = not is_pillar_dormant_fn(spec_path, r"Security(?: Boundary)? Posture")
    if not (di_active or sec_active):
        return

    claims = ev_data.get("claims") if isinstance(ev_data, dict) else []
    claims = claims if isinstance(claims, list) else []
    spec_txt = spec_path.read_text(encoding="utf-8", errors="replace")
    tp_txt = test_plan_path.read_text(encoding="utf-8", errors="replace") if test_plan_path.is_file() else ""
    needs_closure = (
        require_evidence
        or bool(sensitive_files)
        or bool(ev_data.get("shared_sinks"))
        or any(isinstance(c, dict) and str(c.get("kind", "")).lower() in {"boundary_contract", "blast_radius"} for c in claims)
        or bool(SHARED_BOUNDARY_RE.search(spec_txt))
        or bool(SHARED_BOUNDARY_RE.search(tp_txt))
    )
    if not needs_closure:
        return

    has_absence = any(
        isinstance(c, dict)
        and str(c.get("kind", "")).strip().lower() == "absence"
        and str(c.get("status", "")).strip().lower() == "observed"
        for c in claims
    )
    if has_absence:
        passes.append(("shared_invariant_absence", "evidence.yaml", "observed absence closure claim present"))
    else:
        _emit(
            mode, halts, escalates, "missing_shared_invariant_absence_proof", "evidence.yaml",
            "active Pillar 4/6 boundary change requires >=1 observed kind: absence proof enumerating shared-sink/invariant callers (or absence_waiver ruling)",
        )


def check_review_anomalies(
    sub_path: pathlib.Path,
    stage: str,
    ruled_items: set[str],
    mode: str,
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    if stage != "review" or not sub_path.is_file():
        return
    sub_txt = sub_path.read_text(encoding="utf-8", errors="replace")
    cycles = list(re.finditer(r"<!--\s*cadence-run:cycle\s+n=(\d+)\s+phase=code-review\s+blocking=(\d+)\b[^>]*-->", sub_txt))
    if not cycles or int(cycles[-1].group(2)) != 0:
        return
    start_pos = cycles[-2].end() if len(cycles) >= 2 else 0
    latest_blk = sub_txt[start_pos : cycles[-1].start()]
    if not latest_blk.strip():
        latest_blk = sub_txt[cycles[-1].end() :]

    waived_ok = ("rationalization_waiver" in ruled_items) or ("anomaly_waiver" in ruled_items)
    lines = _strip_fences(latest_blk)
    table_issues = 0
    for ln in lines:
        if not ln.lstrip().startswith("|"):
            continue
        cols = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cols) < 4:
            continue
        disp = re.sub(r"[`*_\s]+", "", cols[2]).upper()
        basis = cols[3]
        if disp == "BLOCKING":
            table_issues += 1
            halts.append(("blocking_anomaly_in_approve", "submission.md", f"Adversarial Lens row marked BLOCKING inside blocking=0 cycle: {cols[0][:60]}"))
        elif disp == "WAIVED" and not waived_ok:
            table_issues += 1
            _emit(mode, halts, escalates, "unruled_review_waiver", "submission.md", f"WAIVED anomaly lacks Gate 2 ruling: {cols[0][:60]}")
        elif disp == "PROVEN_SAFE":
            if RATIONALIZATION_RE.search(basis) or not re.search(r"[A-Za-z0-9_./-]+:\d+", basis):
                table_issues += 1
                _emit(mode, halts, escalates, "unproven_safe_anomaly", "submission.md", f"PROVEN_SAFE anomaly lacks file:line proof or uses banned excuse: {cols[0][:60]}")

    prose_hits = [ln for ln in lines if not ln.lstrip().startswith("|") and RATIONALIZATION_RE.search(ln)]
    if prose_hits and "rationalization_waiver" not in ruled_items:
        _emit(
            mode, halts, escalates, "reviewer_rationalized_defect", "submission.md",
            f"blocking=0 review cycle contains banned rationalization phrasing ({len(prose_hits)} hit(s)); verify no live defect was downgraded",
        )
    elif table_issues == 0:
        passes.append(("review_anomalies", "submission.md", "blocking=0 review cycle free of unruled anomalies or rationalizations"))


def check_out_of_scope_overlap(
    prob_path: pathlib.Path,
    spec_path: pathlib.Path,
    changed_pairs: list[tuple[str, str]],
    stage: str,
    ruled_items: set[str],
    spec_oqs: set[str],
    mode: str,
    halts: list,
    escalates: list,
    passes: list,
) -> None:
    if stage not in {"implement", "review"} or not prob_path.is_file() or not changed_pairs:
        return
    if "scope_exclusion" in ruled_items or "scope" in ruled_items:
        return
    ptxt = prob_path.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"(?ms)^##\s+Out of Scope\b.*?(?=^##\s+|\Z)", ptxt)
    if not m:
        return
    oos_tokens = {
        tok.strip().lstrip("./")
        for tok in re.findall(r"`([^`\n]+)`", m.group(0))
        if len(tok.strip()) >= 4 and ("/" in tok or "." in tok)
    }
    if not oos_tokens:
        return
    overlaps = sorted({
        disp for rel, disp in changed_pairs
        for tok in oos_tokens
        if rel == tok or disp == tok or rel.endswith("/" + tok) or pathlib.PurePosixPath(rel).name == tok
    })
    if overlaps:
        _emit(
            mode, halts, escalates, "out_of_scope_shared_surface", "problem.md",
            f"diff modifies path(s) declared Out of Scope without scope_exclusion ruling: {', '.join(overlaps[:5])}",
        )
    else:
        passes.append(("out_of_scope_overlap", "problem.md", "no modified file overlaps Out of Scope declarations"))
