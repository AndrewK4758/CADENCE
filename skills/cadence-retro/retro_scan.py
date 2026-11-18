#!/usr/bin/env python3
"""Read-only cross-ticket archive & retrospective scanner for /cadence-retro."""
import argparse
import datetime
import json
import pathlib
import re
import sys

DUR_RE = re.compile(r"(?:(\d+)\s*d)?\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?", re.I)


def parse_minutes(val: str):
    if not val:
        return None
    s = val.strip().strip('"').strip("'").lower()
    if not s or s in {"null", "none", "tbd", "n/a", "-"}:
        return None
    if re.fullmatch(r"\d+", s):
        return int(s)
    m = DUR_RE.fullmatch(s)
    if not m or not any(m.groups()):
        return None
    d, h, mn = (int(x or 0) for x in m.groups())
    return d * 480 + h * 60 + mn


def fmt_minutes(mins: int) -> str:
    if mins <= 0:
        return "0m"
    h, m = divmod(mins, 60)
    if h and m:
        return f"{h}h {m}m"
    return f"{h}h" if h else f"{m}m"


def read_metadata(meta_path: pathlib.Path) -> dict:
    data = {"tier": "", "tier_valid": False, "status": "", "archived_at": "", "merged_at": "",
            "estimated_effort": "", "actual_effort": "", "stages": {}, "domain_entities": ""}
    if not meta_path.is_file():
        return data
    lines = meta_path.read_text(encoding="utf-8", errors="replace").splitlines()
    in_stages = False
    cur_stage = ""
    for raw in lines:
        if re.match(r"^\s*stage_effort\s*:", raw):
            in_stages = True
            cur_stage = ""
            continue
        if in_stages and re.match(r"^[A-Za-z_][A-Za-z0-9_]*\s*:", raw):
            in_stages = False
        if in_stages:
            ms = re.match(r"^\s*-\s*stage\s*:\s*['\"]?([A-Za-z0-9_-]+)", raw)
            if ms:
                cur_stage = ms.group(1).strip()
            me = re.match(r"^\s*effort\s*:\s*['\"]?([^'\"#]+)", raw)
            if me and cur_stage:
                mins = parse_minutes(me.group(1))
                if mins is not None:
                    data["stages"][cur_stage] = data["stages"].get(cur_stage, 0) + mins
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", raw)
        if not m:
            continue
        k, val = m.group(1), m.group(2).strip()
        for q in ('"', "'"):
            if val.startswith(q) and val.find(q, 1) != -1:
                val = val[1:val.find(q, 1)].strip()
                break
        else:
            val = re.sub(r"\s+#.*$", "", val).strip()
        if k in {"status", "archived_at", "merged_at", "estimated_effort", "actual_effort", "domain_entities"}:
            data[k] = val
        elif k == "tier":
            norm = val.strip().lower()
            data["tier"] = norm if norm in {"trivial", "low", "medium", "high"} else (val or "missing")
            data["tier_valid"] = norm in {"trivial", "low", "medium", "high"}
    return data


def scan_ticket(tdir: pathlib.Path, source: str) -> dict:
    meta = read_metadata(tdir / "metadata.yaml")
    sub = tdir / "submission.md"
    summ = tdir / "summary.md"
    cycles = []
    followups_line = ""
    nb_counts = {c: 0 for c in ("out-of-scope-defect", "adr-owed", "nit", "hygiene", "observation")}
    if sub.is_file():
        stxt = sub.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r"<!--\s*cadence-run:cycle\b([^>]*)-->", stxt):
            kv = dict(re.findall(r"(\w+)=(\S+)", m.group(1)))
            cycles.append({"n": int(kv.get("n", 0)), "blocking": int(kv.get("blocking", 0)), "nonblocking": int(kv.get("nonblocking", 0))})
        mf = re.search(r"Follow-ups created\s*:?\s*(.+)", stxt, re.I)
        if mf:
            followups_line = mf.group(1).strip()
        for cls in nb_counts:
            nb_counts[cls] = len(re.findall(rf"\[`?{re.escape(cls)}`?\]", stxt))
    unguarded_sweep = False
    has_summary = summ.is_file()
    if has_summary:
        smtxt = summ.read_text(encoding="utf-8", errors="replace")
        unguarded_sweep = bool(re.search(r"DEAD-CITATION-SWEEP:\s*(SKIPPED|MANUAL)", smtxt))
    est_m = parse_minutes(meta["estimated_effort"])
    act_m = parse_minutes(meta["actual_effort"])
    if act_m is None and meta["stages"]:
        act_m = sum(meta["stages"].values())
    return {
        "id": tdir.name, "source": source, "tier": meta["tier"] or "missing", "tier_valid": meta["tier_valid"],
        "status": meta["status"], "sort_date": meta["archived_at"] or meta["merged_at"] or "",
        "est_min": est_m, "act_min": act_m, "stages": meta["stages"], "has_summary": has_summary,
        "cycles_count": len(cycles), "max_blocking": max((c["blocking"] for c in cycles), default=0),
        "followups_deferred": bool(re.search(r"\bDeferred\b", followups_line)),
        "unguarded_sweep": unguarded_sweep, "nb_counts": nb_counts,
    }


def scan_existing_insights(root: pathlib.Path) -> dict:
    res = {"intent_ids": [], "prod_ids": [], "promoted_tickets": set()}
    for kind, fname in (("intent_ids", "intent-insights.md"), ("prod_ids", "production-insights.md")):
        for rel in (f"docs/agentic-sdlc/{fname}", f"processes/docs/agentic-sdlc/{fname}"):
            p = root / rel
            if not p.is_file():
                continue
            txt = p.read_text(encoding="utf-8", errors="replace")
            pref = "II" if kind == "intent_ids" else "PROD"
            res[kind].extend(re.findall(rf"\b{pref}-\d{{3,4}}\b", txt))
            for m in re.finditer(r"Source Ticket\s*\|\s*`?([A-Za-z][A-Za-z0-9_]*-\d+)`?", txt, re.I):
                res["promoted_tickets"].add(m.group(1))
    return {"intent_count": len(set(res["intent_ids"])), "prod_count": len(set(res["prod_ids"])), "promoted_tickets": sorted(res["promoted_tickets"])}


def run_scan(root: pathlib.Path, since: str = "", include_active: bool = False) -> dict:
    if not root.is_dir():
        raise ValueError(f"root directory does not exist: {root}")
    since_n, since_date = None, None
    if since:
        if re.fullmatch(r"\d+", since) and int(since) >= 1:
            since_n = int(since)
        elif re.fullmatch(r"\d{4}-\d{2}-\d{2}", since):
            datetime.date.fromisoformat(since)
            since_date = since
        else:
            raise ValueError(f"invalid --since value {since!r} (expected positive integer or YYYY-MM-DD)")

    tickets = []
    arch_dir = root / "archive"
    if arch_dir.is_dir():
        for d in sorted(arch_dir.iterdir()):
            if d.is_dir() and not d.name.startswith(".") and ((d / "metadata.yaml").is_file() or (d / "summary.md").is_file()):
                tickets.append(scan_ticket(d, "archive"))
    if include_active and (root / "specs").is_dir():
        for d in sorted((root / "specs").iterdir()):
            if d.is_dir() and d.name not in {"TEMPLATE", "drafts"} and (d / "metadata.yaml").is_file():
                tickets.append(scan_ticket(d, "specs"))

    if since_date:
        tickets = [t for t in tickets if t["sort_date"] and t["sort_date"][:10] >= since_date]
    elif since_n:
        tickets = sorted(tickets, key=lambda t: (t["sort_date"], t["id"]))[-since_n:]

    archived_cnt = sum(1 for t in tickets if t["source"] == "archive")
    tier_dist = {}
    stage_totals = {}
    for t in tickets:
        key = t["tier"] if t["tier_valid"] else f"unresolved:{t['tier']}"
        tier_dist[key] = tier_dist.get(key, 0) + 1
        for st, mn in t["stages"].items():
            stage_totals[st] = stage_totals.get(st, 0) + mn

    rework = [t["id"] for t in tickets if t["cycles_count"] >= 2]
    deferred = [t["id"] for t in tickets if t["followups_deferred"]]
    unguarded = [t["id"] for t in tickets if t["unguarded_sweep"]]
    missing_sum = [t["id"] for t in tickets if t["source"] == "archive" and not t["has_summary"]]
    over_est = [t["id"] for t in tickets if t["est_min"] and t["act_min"] and t["act_min"] > t["est_min"]]
    insights = scan_existing_insights(root)
    return {
        "status": "empty_archive" if archived_cnt == 0 and not include_active else "ok",
        "archived_tickets": archived_cnt, "total_scanned": len(tickets),
        "tier_distribution": tier_dist,
        "stage_totals": {k: fmt_minutes(v) for k, v in sorted(stage_totals.items())},
        "rework_hotspots": rework, "deferred_followups": deferred,
        "unguarded_citation_sweeps": unguarded, "missing_summary": missing_sum,
        "over_estimate_tickets": over_est, "existing_insights": insights,
        "tickets": tickets,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--since", default="")
    ap.add_argument("--include-active", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        res = run_scan(pathlib.Path(args.root).resolve(), args.since, args.include_active)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(res, indent=2))
        return 0
    print(f"status={res['status']} archived_tickets={res['archived_tickets']} total_scanned={res['total_scanned']}")
    print("tiers=" + (", ".join(f"{k}:{v}" for k, v in sorted(res["tier_distribution"].items())) or "none"))
    print("stage_effort=" + (", ".join(f"{k}:{v}" for k, v in res["stage_totals"].items()) or "none"))
    print("rework_hotspots=" + (",".join(res["rework_hotspots"]) or "none"))
    print("deferred_followups=" + (",".join(res["deferred_followups"]) or "none"))
    print("unguarded_citation_sweeps=" + (",".join(res["unguarded_citation_sweeps"]) or "none"))
    print("missing_summary=" + (",".join(res["missing_summary"]) or "none"))
    print("over_estimate_tickets=" + (",".join(res["over_estimate_tickets"]) or "none"))
    ins = res["existing_insights"]
    print(f"existing_insights=II:{ins['intent_count']},PROD:{ins['prod_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
