#!/usr/bin/env python3
"""Monitor CADENCE PRs/MRs and bound-tracker comments with atomic watermarking."""

import argparse, json, os, re, subprocess, sys, tempfile, time
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import read_state, watch_sources  # noqa: E402

ITEM_TAG_RE = re.compile(r"<!--\s*cadence-watch:item\s+source=(?P<src>[a-z_]+)\s+id=(?P<id>[^\s>]+)\s*-->")
THREAD_URL_RE = re.compile(r"^\s*-\s*(?:\*\*)?Thread URL:(?:\*\*)?\s*(?P<url>https?://\S+)", re.I)
SOURCE_BUCKET = {
    "github_review": "seen_reviews", "gitlab_review": "seen_reviews",
    "github_comment": "seen_pr_comments", "gitlab_comment": "seen_pr_comments",
    "github_inline": "seen_inline_comments", "gitlab_inline": "seen_inline_comments",
    "jira": "seen_tracker_comments", "youtrack": "seen_tracker_comments",
    "github_issue": "seen_tracker_comments",
}
ITEM_GROUPS = ("new_reviews", "new_inline_comments", "new_pr_comments", "new_tracker_comments")
KV_SCALARS = (
    "repo_root", "integration_branch", "ticket_id", "status", "tier", "pr_kind", "pr_ref", "pr_url",
    "forge", "pr_state", "is_draft", "head_branch", "head_sha", "base_branch", "review_decision",
    "ci_status", "tracker_status", "tracker", "ledger_cycles_completed", "cycle_cap_reached", "has_new_comments",
)


def halt(cause: str, message: str) -> None:
    sys.stderr.write(f"cadence-watch.halt {cause}: {message}\n")
    raise SystemExit(2)


def resolve_state_dir(repo_root: str, explicit_dir: str) -> str:
    if explicit_dir:
        return os.path.abspath(explicit_dir)
    if env_dir := os.environ.get("CADENCE_WATCH_STATE_DIR", "").strip():
        return os.path.abspath(env_dir)
    proc = subprocess.run(["git", "-C", repo_root, "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    if proc.returncode == 0 and proc.stdout.strip():
        common = proc.stdout.strip()
        if not os.path.isabs(common):
            common = os.path.abspath(os.path.join(repo_root, common))
        return os.path.join(common, "cadence", "watch")
    return os.path.join(repo_root, ".cadence", "watch")


def load_watermark(state_dir: str, ticket_id: str, submission_path: str) -> dict:
    wm = {
        "seen_reviews": [], "seen_pr_comments": [], "seen_inline_comments": [], "seen_tracker_comments": [],
        "last_head_sha": "", "last_state": "", "last_review_decision": "",
        "last_changes_requested_sha": "", "last_approved_sha": "", "last_failed_sha": "", "updated_at": "",
    }
    wm_path = os.path.join(state_dir, f"{ticket_id}.json")
    if os.path.isfile(wm_path):
        try:
            raw = json.loads(open(wm_path, encoding="utf-8").read())
            if not isinstance(raw, dict):
                raise ValueError("watermark JSON is not an object")
            for k in wm:
                if k in raw:
                    wm[k] = raw[k]
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            halt("watermark_corrupt", f"unreadable watermark {wm_path}: {exc}")
    if submission_path and os.path.isfile(submission_path):
        seen = {v: set() for v in set(SOURCE_BUCKET.values())}
        for m in ITEM_TAG_RE.finditer(open(submission_path, encoding="utf-8").read()):
            if bucket := SOURCE_BUCKET.get(m.group("src")):
                seen[bucket].add(m.group("id"))
        for bucket, ids in seen.items():
            wm[bucket] = sorted(set(wm.get(bucket) or []) | ids)
    return wm


def save_watermark_atomic(state_dir: str, ticket_id: str, wm: dict) -> str:
    os.makedirs(state_dir, exist_ok=True)
    dst = os.path.join(state_dir, f"{ticket_id}.json")
    fd, tmp_path = tempfile.mkstemp(prefix=f".{ticket_id}.", suffix=".tmp", dir=state_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(wm, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp_path, dst)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise
    return dst


def ack_snapshot(repo_root: str, state_dir: str, ticket_id: str, snap_path: str) -> str:
    snap = json.loads(sys.stdin.read() if snap_path == "-" else open(snap_path, encoding="utf-8").read())
    entry = snap if (isinstance(snap, dict) and snap.get("ticket_id") == ticket_id) else next(
        (x for x in (snap.get("tickets") or []) if isinstance(x, dict) and x.get("ticket_id") == ticket_id), None
    ) if isinstance(snap, dict) else None
    if entry is None:
        halt("ack_ticket_not_in_snapshot", f"{ticket_id} not found in snapshot {snap_path}")

    wm = load_watermark(state_dir, ticket_id, os.path.join(repo_root, "specs", ticket_id, "submission.md"))
    for snap_key, wm_key in (
        ("new_reviews", "seen_reviews"), ("new_pr_comments", "seen_pr_comments"),
        ("new_inline_comments", "seen_inline_comments"), ("new_tracker_comments", "seen_tracker_comments"),
    ):
        wm[wm_key] = sorted(set(wm.get(wm_key) or []) | {str(x["id"]) for x in (entry.get(snap_key) or []) if x.get("id")})

    head_sha = entry.get("head_sha") or ""
    eff_sha = head_sha or "(no-sha)"
    event, decision = entry.get("event") or "", entry.get("review_decision") or ""
    wm["last_head_sha"], wm["last_state"], wm["last_review_decision"] = head_sha, entry.get("pr_state") or "", decision
    if event == "changes_requested" or decision == "CHANGES_REQUESTED":
        wm["last_changes_requested_sha"] = eff_sha
    if event == "approved":
        wm["last_approved_sha"] = eff_sha
    if event == "ci_failed":
        wm["last_failed_sha"] = eff_sha
    wm["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return save_watermark_atomic(state_dir, ticket_id, wm)


def _read_thread_url(submission_path: str) -> str:
    if os.path.isfile(submission_path):
        for line in open(submission_path, encoding="utf-8"):
            m = THREAD_URL_RE.match(line)
            if m and "{" not in m.group("url"):
                return m.group("url").strip()
    return ""


def _resolve_ticket_record(repo_root: str, ticket_id: str) -> tuple[str, dict, str, list]:
    spec_dir, location = os.path.join(repo_root, "specs", ticket_id), "specs"
    if not os.path.isdir(spec_dir):
        arch_dir = os.path.join(repo_root, "archive", ticket_id)
        if os.path.isdir(arch_dir):
            spec_dir, location = arch_dir, "archive"
        else:
            for where in ("specs", "archive"):
                base = os.path.join(repo_root, where)
                if os.path.isdir(base):
                    for entry in sorted(os.listdir(base)):
                        if entry.lower() == ticket_id.lower() and os.path.isdir(os.path.join(base, entry)):
                            read_state.halt("ticket_id_case_mismatch",
                                            f"no {where}/{ticket_id}, but {where}/{entry} exists -- re-run with {entry}")
            halt("ticket_not_established", f"no specs/{ticket_id}/ or archive/{ticket_id}/ found")

    meta_path = os.path.join(spec_dir, "metadata.yaml")
    if not os.path.isfile(meta_path):
        halt("metadata_absent", f"{spec_dir} has no metadata.yaml")
    scalars = read_state.read_scalars(meta_path, set(read_state.FIELDS) | {"jira_url", "youtrack_url", "github_issue_url"})
    if not scalars.get("status"):
        halt("status_unreadable", f"could not resolve status: from {meta_path}")
    return location, scalars, os.path.join(spec_dir, "submission.md"), read_state.read_ledger(spec_dir)


def resolve_active_pr(location: str, scalars: dict, sub_path: str) -> tuple[str, str, str]:
    status, tier = (scalars.get("status") or "").strip().lower(), (scalars.get("tier") or "").strip().lower()
    spec_mr, merge_req = (scalars.get("spec_mr") or "").strip(), (scalars.get("merge_request") or "").strip()
    if location == "archive" or status == "archived":
        return "already_archived", "", ""
    if status == "cancelled":
        return "cancelled", "", ""
    if status == "merged":
        return "merged_local", "merge_request", merge_req
    if status in ("in-progress", "in-review") or merge_req:
        return ("active", "merge_request", merge_req) if merge_req else ("no_pr", "merge_request", "")
    if spec_mr:
        return "active", "spec_mr", spec_mr
    if status == "triaged" and tier in ("low", "trivial") and (turl := _read_thread_url(sub_path)):
        return "active", "triage_mr", turl
    return "no_pr", "", ""


def classify_ticket(repo_root: str, integration_branch: str, ticket_id: str, state_dir: str, use_tracker: bool) -> dict:
    location, scalars, sub_path, ledger = _resolve_ticket_record(repo_root, ticket_id)
    cycles = len({e["n"] for e in ledger})
    kind_state, pr_kind, pr_ref = resolve_active_pr(location, scalars, sub_path)
    res = {
        "repo_root": repo_root, "integration_branch": integration_branch, "ticket_id": ticket_id,
        "status": scalars.get("status", ""), "tier": scalars.get("tier", ""), "pr_kind": pr_kind,
        "pr_ref": pr_ref, "pr_url": pr_ref, "forge": "", "pr_state": "", "is_draft": False,
        "head_branch": scalars.get("branch", ""), "head_sha": "", "base_branch": integration_branch,
        "review_decision": "", "ci_status": "UNKNOWN", "tracker_status": "skipped_not_polled",
        "tracker": "", "ledger_cycles_completed": cycles, "cycle_cap_reached": cycles >= 4,
        "new_reviews": [], "new_pr_comments": [], "new_inline_comments": [], "new_tracker_comments": [],
        "has_new_comments": False, "warnings": [], "event": "idle", "next_action": "none",
    }
    if kind_state != "active":
        if kind_state == "no_pr" and (gh_issue_url := (scalars.get("github_issue_url") or "").strip()) and use_tracker:
            wm = load_watermark(state_dir, ticket_id, sub_path)
            return watch_sources.classify_github_issue(repo_root, gh_issue_url, wm["seen_tracker_comments"], res)
        if kind_state == "already_archived":
            res["event"] = "already_archived"
        elif kind_state == "cancelled":
            res["event"], res["next_action"] = "cancelled", "cadence-archive"
        elif kind_state == "merged_local":
            res["event"], res["pr_state"], res["next_action"] = "merged", "MERGED", "cadence-archive"
        else:
            res["event"], res["next_action"] = "no_pr", ("cadence-build" if pr_kind == "merge_request" else "cadence-define")
        return res

    forge = watch_sources.detect_forge(pr_ref, sub_path, repo_root)
    res["forge"] = forge
    if forge == "sourcehut":
        res["event"], res["next_action"] = "unsupported_forge", "manual_sourcehut_mirror"
        res["warnings"].append("sourcehut lists.sr.ht polling unsupported; mirror thread replies manually")
        return res

    pr = watch_sources.fetch_github_pr(pr_ref, repo_root) if forge == "github" else watch_sources.fetch_gitlab_mr(pr_ref, repo_root)
    res.update({
        "pr_url": pr["url"], "pr_state": pr["state"], "is_draft": pr["is_draft"],
        "head_branch": pr["head_branch"] or res["head_branch"], "head_sha": pr["head_sha"],
        "base_branch": pr["base_branch"] or integration_branch, "review_decision": pr["review_decision"],
        "ci_status": pr["ci_status"], "warnings": list(pr.get("warnings") or []),
    })
    if use_tracker:
        tr = watch_sources.fetch_tracker_comments(repo_root, ticket_id, scalars.get("jira_url", ""), scalars.get("youtrack_url", ""))
        res["tracker_status"], res["tracker"], tracker_comments = tr["status"], tr["tracker"], tr["comments"]
        if gh_issue_url := (scalars.get("github_issue_url") or "").strip():
            gh_iss = watch_sources.fetch_github_issue_comments(gh_issue_url, repo_root)
            tracker_comments.extend(gh_iss["comments"])
            if res["tracker_status"] == "skipped_inner_source":
                res["tracker_status"], res["tracker"] = gh_iss["status"], "github_issue"
    else:
        res["tracker_status"], tracker_comments = "disabled_flag", []

    wm = load_watermark(state_dir, ticket_id, sub_path)
    new_reviews = [r for r in pr["reviews"] if r["id"] not in wm["seen_reviews"]]
    new_pr = [c for c in pr["pr_comments"] if c["id"] not in wm["seen_pr_comments"]]
    new_in = [c for c in pr["inline_comments"] if c["id"] not in wm["seen_inline_comments"]]
    new_tr = [c for c in tracker_comments if c["id"] not in wm["seen_tracker_comments"]]
    new_cr = [r for r in new_reviews if r["state"] == "CHANGES_REQUESTED"]
    new_cm_rev = [r for r in new_reviews if r["state"] == "COMMENTED"]
    res.update({
        "new_reviews": new_reviews, "new_pr_comments": new_pr, "new_inline_comments": new_in,
        "new_tracker_comments": new_tr, "has_new_comments": bool(new_reviews or new_pr or new_in or new_tr),
    })

    eff_sha = pr["head_sha"] or "(no-sha)"
    if pr["state"] == "MERGED":
        res["event"], res["next_action"] = "merged", ("cadence-archive" if pr_kind == "merge_request" else "cadence-build")
    elif pr["state"] == "CLOSED":
        res["event"], res["next_action"] = "closed_unmerged", "halt_human_rejected"
    elif new_cr or (pr["review_decision"] == "CHANGES_REQUESTED" and eff_sha != wm["last_changes_requested_sha"] and wm["last_changes_requested_sha"] == ""):
        res["event"] = "changes_requested"
        res["next_action"] = {"spec_mr": "remediate_spec", "merge_request": "remediate_impl", "triage_mr": "remediate_triage"}[pr_kind]
    elif new_in or new_pr or new_tr or new_cm_rev:
        res["event"], res["next_action"] = "comments_new", "triage_comments"
    elif pr["ci_status"] == "FAIL" and eff_sha != wm["last_failed_sha"]:
        res["event"], res["next_action"] = "ci_failed", "remediate_ci"
    elif pr["review_decision"] == "APPROVED" and eff_sha != wm["last_approved_sha"]:
        res["event"], res["next_action"] = "approved", ("cadence-close" if pr_kind == "merge_request" else "await_human_merge")
    return res


def discover_active_tickets(repo_root: str) -> list[str]:
    specs_dir = os.path.join(repo_root, "specs")
    if not os.path.isdir(specs_dir):
        return []
    found = []
    for entry in sorted(os.listdir(specs_dir)):
        tdir = os.path.join(specs_dir, entry)
        meta = os.path.join(tdir, "metadata.yaml")
        if entry in ("TEMPLATE", "drafts") or not os.path.isdir(tdir) or not os.path.isfile(meta):
            continue
        sc = read_state.read_scalars(meta, {"status", "spec_mr", "merge_request", "github_issue_url"})
        if (sc.get("status") or "").strip().lower() in ("archived", "cancelled"):
            continue
        if sc.get("spec_mr") or sc.get("merge_request") or sc.get("github_issue_url") or _read_thread_url(os.path.join(tdir, "submission.md")):
            found.append(entry)
    return found


def _item_line(item: dict, prefix: str = "item=") -> str:
    loc = f"{item['path']}:{item.get('line', '')}" if item.get("path") else "-"
    snip = " ".join((item.get("body") or "").split())[:140]
    return f"{prefix}{item['source']}:{item['id']}:{item.get('author', 'unknown')}:{loc}:{snip}"


def render_kv(payload: dict) -> str:
    if "tickets" in payload:
        lines = [f"{k}={payload[k]}" for k in ("repo_root", "integration_branch", "active_tickets", "event", "next_action")]
        for t in payload["tickets"]:
            if t.get("event") == "error":
                lines.append(f"ticket={t['ticket_id']} event=error cause={t['error_cause']} message={t['error_message']}")
                continue
            cnt = sum(len(t[k]) for k in ITEM_GROUPS)
            lines.append(f"ticket={t['ticket_id']} status={t['status']} pr_kind={t['pr_kind']} forge={t['forge']} "
                         f"event={t['event']} next_action={t['next_action']} new_comments={cnt} pr_url={t['pr_url']}")
            for grp in ITEM_GROUPS:
                lines.extend(_item_line(it, prefix=f"ticket_item={t['ticket_id']}:") for it in t[grp])
            lines.extend(f"warning={t['ticket_id']}:{w}" for w in (t.get("warnings") or []))
        return "\n".join(lines)

    fmt = lambda v: ("true" if v else "false") if isinstance(v, bool) else v
    lines = [f"{k}={fmt(payload[k])}" for k in KV_SCALARS]
    lines.extend([
        f"new_review_count={len(payload['new_reviews'])}", f"new_pr_comment_count={len(payload['new_pr_comments'])}",
        f"new_inline_comment_count={len(payload['new_inline_comments'])}", f"new_tracker_comment_count={len(payload['new_tracker_comments'])}",
        f"event={payload['event']}", f"next_action={payload['next_action']}",
    ])
    for grp in ITEM_GROUPS:
        lines.extend(_item_line(it) for it in payload[grp])
    lines.extend(f"warning={w}" for w in payload["warnings"])
    return "\n".join(lines)


def poll_once(args, repo_root: str, integration_branch: str, state_dir: str) -> tuple[dict, bool]:
    use_tracker = not args.no_tracker
    if not args.all:
        return classify_ticket(repo_root, integration_branch, args.ticket_id, state_dir, use_tracker), False
    tids = discover_active_tickets(repo_root)
    if not tids:
        return {"repo_root": repo_root, "integration_branch": integration_branch, "active_tickets": 0,
                "event": "no_active_prs", "next_action": "none", "tickets": []}, False
    results, had_err = [], False
    for tid in tids:
        try:
            results.append(classify_ticket(repo_root, integration_branch, tid, state_dir, use_tracker))
        except watch_sources.SourceHalt as exc:
            had_err = True
            sys.stderr.write(f"cadence-watch.halt {exc.cause} [{tid}]: {exc.message}\n")
            results.append({"ticket_id": tid, "event": "error", "error_cause": exc.cause, "error_message": exc.message})
    actionable = [r for r in results if r.get("event") not in ("idle", "error")]
    return {
        "repo_root": repo_root, "integration_branch": integration_branch, "active_tickets": len(results),
        "event": actionable[0]["event"] if actionable else ("error" if had_err else "idle"),
        "next_action": actionable[0]["next_action"] if actionable else "none", "tickets": results,
    }, had_err


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket_id", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--watch", action="store_true")
    ap.add_argument("--interval", type=float, default=60.0)
    ap.add_argument("--timeout", type=float, default=1800.0)
    ap.add_argument("--no-tracker", action="store_true")
    ap.add_argument("--format", choices=("kv", "json"), default="kv")
    ap.add_argument("--state-dir", default="")
    ap.add_argument("--write-snapshot", default="")
    ap.add_argument("--ack", default="")
    ap.add_argument("--from-snapshot", default="")
    args = ap.parse_args()

    if args.once and args.watch:
        halt("invalid_args", "--once and --watch are mutually exclusive")
    if args.interval <= 0 or args.timeout < 0:
        halt("invalid_args", "--interval must be > 0 and --timeout must be >= 0")

    repo_root = read_state.find_repo_root(args.repo_root)
    integration_branch = read_state.resolve_binding(repo_root, "integration-branch")
    read_state.resolve_binding(repo_root, "branch-naming-convention")
    state_dir = resolve_state_dir(repo_root, args.state_dir)

    if args.ack:
        if not args.from_snapshot or args.ticket_id or args.all or args.watch:
            halt("invalid_args", "--ack requires --from-snapshot and takes no poll target")
        print(f"ack_ticket={args.ack}\nwatermark_file={ack_snapshot(repo_root, state_dir, args.ack, args.from_snapshot)}\nstatus=ok")
        return 0
    if args.from_snapshot:
        halt("invalid_args", "--from-snapshot requires --ack <TICKET-ID>")
    if bool(args.ticket_id) == bool(args.all):
        halt("invalid_args", "supply either <TICKET-ID> or --all")

    had_err = False
    try:
        if args.watch:
            deadline = time.monotonic() + args.timeout
            while True:
                payload, had_err = poll_once(args, repo_root, integration_branch, state_dir)
                if had_err or payload["event"] not in ("idle", "no_active_prs"):
                    break
                if time.monotonic() >= deadline:
                    payload["event"], payload["next_action"] = "timeout", "none"
                    break
                time.sleep(min(args.interval, max(0.01, deadline - time.monotonic())))
        else:
            payload, had_err = poll_once(args, repo_root, integration_branch, state_dir)
    except watch_sources.SourceHalt as exc:
        halt(exc.cause, exc.message)

    if args.write_snapshot:
        with open(args.write_snapshot, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")

    print(json.dumps(payload, indent=2) if args.format == "json" else render_kv(payload))
    return 2 if had_err else 0


if __name__ == "__main__":
    sys.exit(main())
