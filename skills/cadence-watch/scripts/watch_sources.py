#!/usr/bin/env python3
"""Read-only forge PR/MR and bound tracker comment adapters for /cadence-watch."""

import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request

WATCH_REPLY_MARKER = "<!-- cadence-watch:reply"
PRESERVE_SENTINELS = (
    "Original intake (as filed)",
    "preserved on import; the repo now owns the description below",
)


class SourceHalt(Exception):
    """Fail-loud error raised when a forge or tracker source cannot be queried."""

    def __init__(self, cause: str, message: str):
        super().__init__(message)
        self.cause = cause
        self.message = message


def is_ignored_body(body: str) -> bool:
    """Return True for self-posted watch replies or tracker preservation notes."""
    text = body or ""
    return WATCH_REPLY_MARKER in text or all(tok in text for tok in PRESERVE_SENTINELS)


def _scrub(text: str, secret: str = "") -> str:
    cleaned = re.sub(r"([?&]sign=)[^&\s\"']+", r"\1[REDACTED]", text or "")
    if secret:
        cleaned = cleaned.replace(secret, "[REDACTED]")
    return cleaned.strip()[:240]


def _run_cmd(cmd: list[str], cwd: str, timeout: int = 30) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def detect_forge(pr_ref: str, submission_path: str, repo_root: str) -> str:
    """Resolve forge name from PR URL, submission.md metadata, or origin remote."""
    low = (pr_ref or "").lower()
    if "github.com" in low or re.search(r"/pull/\d+", low):
        return "github"
    if "/-/merge_requests/" in low or "gitlab" in low:
        return "gitlab"
    if "lists.sr.ht" in low:
        return "sourcehut"
    if submission_path and os.path.isfile(submission_path):
        with open(submission_path, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^\s*-\s*(?:\*\*)?Forge:(?:\*\*)?\s*(.+)$", line, re.I)
                if m:
                    val = m.group(1).strip().lower()
                    if val in ("github", "gitlab", "sourcehut") and "|" not in val:
                        return val
    rc, out, _ = _run_cmd(["git", "remote", "get-url", "origin"], cwd=repo_root)
    if rc == 0:
        remote = out.strip().lower()
        for name, needle in (("github", "github"), ("gitlab", "gitlab"), ("sourcehut", "sr.ht")):
            if needle in remote:
                return name
    raise SourceHalt("forge_unresolvable", f"cannot resolve forge for {pr_ref!r}")


def _normalize_gh_ci(rollup) -> str:
    if not rollup:
        return "UNKNOWN"
    bad = {"FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED"}
    wait = {"PENDING", "IN_PROGRESS", "QUEUED", "EXPECTED"}
    statuses = [(x.get("conclusion") or x.get("state") or x.get("status") or "").upper() for x in rollup if isinstance(x, dict)]
    if any(s in bad for s in statuses):
        return "FAIL"
    if any(s in wait for s in statuses):
        return "PENDING"
    return "PASS" if statuses else "UNKNOWN"


def fetch_github_pr(pr_ref: str, repo_root: str) -> dict:
    """Query GitHub PR state, reviews, comments, and inline diff threads via gh."""
    if not shutil.which("gh"):
        raise SourceHalt("gh_missing", "gh CLI is not installed -- cannot query GitHub PR")
    fields = ("number,url,state,isDraft,mergeStateStatus,reviewDecision,"
              "headRefName,headRefOid,baseRefName,mergedAt,closedAt,reviews,comments,statusCheckRollup")
    rc, out, err = _run_cmd(["gh", "pr", "view", pr_ref, "--json", fields], cwd=repo_root)
    if rc != 0:
        raise SourceHalt("forge_unreachable", f"gh pr view {pr_ref} failed: {err.strip()[:220]}")
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise SourceHalt("forge_unreachable", f"gh pr view returned invalid JSON: {exc}")

    reviews = []
    for r in data.get("reviews") or []:
        rstate, body = (r.get("state") or "").upper(), r.get("body") or ""
        if rstate == "COMMENTED" and is_ignored_body(body):
            continue
        author = (r.get("author") or {}).get("login") or "unknown"
        submitted = r.get("submittedAt") or ""
        reviews.append({"id": str(r.get("id") or f"{author}:{rstate}:{submitted}"), "author": author,
                        "state": rstate, "body": body, "created_at": submitted, "source": "github_review"})

    pr_comments = []
    for c in data.get("comments") or []:
        body = c.get("body") or ""
        if is_ignored_body(body):
            continue
        author = (c.get("author") or {}).get("login") or "unknown"
        created = c.get("createdAt") or ""
        pr_comments.append({"id": str(c.get("id") or f"{author}:{created}"), "author": author,
                            "body": body, "created_at": created, "source": "github_comment"})

    inline_comments, warnings = [], []
    pr_url = data.get("url") or ""
    m = re.match(r"https?://[^/]+/([^/]+/[^/]+)/pull/(\d+)", pr_url)
    if m:
        irc, iout, ierr = _run_cmd(["gh", "api", f"repos/{m.group(1)}/pulls/{m.group(2)}/comments"], cwd=repo_root)
        if irc != 0:
            warnings.append(f"inline_comments_unavailable:{ierr.strip()[:160]}")
        else:
            try:
                items = json.loads(iout)
                if isinstance(items, list):
                    for ic in items:
                        body = ic.get("body") or ""
                        if is_ignored_body(body):
                            continue
                        inline_comments.append({
                            "id": str(ic.get("id") or ""), "author": (ic.get("user") or {}).get("login") or "unknown",
                            "body": body, "path": ic.get("path") or "", "line": ic.get("line") or ic.get("original_line") or "",
                            "created_at": ic.get("created_at") or "", "url": ic.get("html_url") or "", "source": "github_inline",
                        })
            except json.JSONDecodeError as exc:
                warnings.append(f"inline_comments_unavailable:invalid JSON ({exc})")

    return {
        "forge": "github", "number": data.get("number") or "", "url": pr_url or pr_ref,
        "state": (data.get("state") or "OPEN").upper(), "is_draft": bool(data.get("isDraft")),
        "head_branch": data.get("headRefName") or "", "head_sha": data.get("headRefOid") or "",
        "base_branch": data.get("baseRefName") or "", "merged_at": data.get("mergedAt") or "",
        "review_decision": (data.get("reviewDecision") or "").upper(),
        "ci_status": _normalize_gh_ci(data.get("statusCheckRollup")),
        "reviews": reviews, "pr_comments": pr_comments, "inline_comments": inline_comments, "warnings": warnings,
    }


def _collect_gl_notes(notes: list, inline_out: list, comments_out: list) -> None:
    for note in notes:
        if not isinstance(note, dict) or note.get("system"):
            continue
        body = note.get("body") or ""
        if is_ignored_body(body):
            continue
        author_d = note.get("author") or {}
        author = author_d.get("username") or author_d.get("name") or "unknown"
        nid = str(note.get("id") or f"{author}:{note.get('created_at') or ''}")
        pos = note.get("position")
        if isinstance(pos, dict) and (pos.get("new_path") or pos.get("old_path")):
            inline_out.append({"id": nid, "author": author, "body": body, "path": pos.get("new_path") or pos.get("old_path") or "",
                               "line": pos.get("new_line") or pos.get("old_line") or "", "created_at": note.get("created_at") or "",
                               "source": "gitlab_inline"})
        else:
            comments_out.append({"id": nid, "author": author, "body": body,
                                 "created_at": note.get("created_at") or "", "source": "gitlab_comment"})


def fetch_gitlab_mr(pr_ref: str, repo_root: str) -> dict:
    """Query GitLab MR state, pipelines, and discussions via glab."""
    if not shutil.which("glab"):
        raise SourceHalt("glab_missing", "glab CLI is not installed -- cannot query GitLab MR")
    rc, out, err = _run_cmd(["glab", "mr", "view", pr_ref, "--output", "json"], cwd=repo_root)
    if rc != 0:
        raise SourceHalt("forge_unreachable", f"glab mr view {pr_ref} failed: {err.strip()[:220]}")
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise SourceHalt("forge_unreachable", f"glab mr view returned invalid JSON: {exc}")

    raw_state = (data.get("state") or "opened").lower()
    state = "MERGED" if raw_state == "merged" else ("CLOSED" if raw_state == "closed" else "OPEN")
    pipe = ((data.get("head_pipeline") or {}).get("status") or "").lower()
    ci_status = ("FAIL" if pipe in ("failed", "canceled")
                 else ("PENDING" if pipe in ("running", "pending", "created", "waiting_for_resource", "preparing")
                       else ("PASS" if pipe == "success" else "UNKNOWN")))
    dms = (data.get("detailed_merge_status") or "").lower()
    review_decision = ("CHANGES_REQUESTED" if dms == "discussions_not_resolved"
                       else ("APPROVED" if (data.get("approved") is True or bool(data.get("approved_by"))) else ""))

    inline_comments, pr_comments, warnings = [], [], []
    if isinstance(data.get("notes"), list):
        _collect_gl_notes(data["notes"], inline_comments, pr_comments)
    elif isinstance(data.get("discussions"), list):
        for d in data["discussions"]:
            _collect_gl_notes(d.get("notes") or [], inline_comments, pr_comments)
    elif data.get("project_id") and data.get("iid"):
        drc, dout, derr = _run_cmd(["glab", "api", f"projects/{data['project_id']}/merge_requests/{data['iid']}/discussions"], cwd=repo_root)
        if drc != 0:
            warnings.append(f"inline_comments_unavailable:{derr.strip()[:160]}")
        else:
            try:
                for d in json.loads(dout):
                    _collect_gl_notes(d.get("notes") or [], inline_comments, pr_comments)
            except (json.JSONDecodeError, TypeError) as exc:
                warnings.append(f"inline_comments_unavailable:invalid JSON ({exc})")

    diff_refs = data.get("diff_refs") or {}
    return {
        "forge": "gitlab", "number": data.get("iid") or "", "url": data.get("web_url") or pr_ref,
        "state": state, "is_draft": bool(data.get("draft") or data.get("work_in_progress")),
        "head_branch": data.get("source_branch") or "", "head_sha": data.get("sha") or diff_refs.get("head_sha") or "",
        "base_branch": data.get("target_branch") or "", "merged_at": data.get("merged_at") or "",
        "review_decision": review_decision, "ci_status": ci_status, "reviews": [],
        "pr_comments": pr_comments, "inline_comments": inline_comments, "warnings": warnings,
    }


def _load_env_names(repo_root: str, skill: str, cfg_name: str, defaults: dict) -> dict:
    for rel in (f".agents/skills/{skill}/{cfg_name}", f"skills/{skill}/{cfg_name}"):
        p = os.path.join(repo_root, rel)
        if os.path.isfile(p):
            try:
                env = json.loads(open(p, encoding="utf-8").read()).get("env") or {}
                return {k: env.get(k) or v for k, v in defaults.items()}
            except (OSError, json.JSONDecodeError):
                break
    return defaults


def _http_get_json(url: str, token: str, kind: str) -> object:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = _scrub(exc.read().decode("utf-8", errors="replace"), token)
        raise SourceHalt("tracker_http_error", f"{kind} GET {url} returned HTTP {exc.code}: {body}")
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        raise SourceHalt("tracker_unreachable", f"{kind} GET {url} failed: {_scrub(str(exc), token)}")
    except json.JSONDecodeError as exc:
        raise SourceHalt("tracker_http_error", f"{kind} GET {url} returned invalid JSON: {exc}")


def _extract_issue_key(tracker_url: str) -> str:
    parts = [p for p in urllib.parse.urlparse(tracker_url.strip()).path.split("/") if p]
    return parts[-1] if parts else ""


def fetch_tracker_comments(repo_root: str, ticket_id: str, jira_url: str, youtrack_url: str) -> dict:
    """Resolve CADENCE_ORG.md §9 tracker binding and fetch inbound ticket comments."""
    m = re.match(r"^([A-Za-z][A-Za-z0-9_]*)-", ticket_id)
    if not m:
        raise SourceHalt("invalid_ticket_id", f"ticket id {ticket_id!r} has no prefix")
    prefix = m.group(1)

    resolver = next(
        (os.path.join(repo_root, r) for r in ("ci-templates/scripts/org-binding-resolve.sh", "processes/ci-templates/scripts/org-binding-resolve.sh")
         if os.path.isfile(os.path.join(repo_root, r))),
        None,
    )
    if not resolver:
        raise SourceHalt("org_binding_resolver_missing", "org-binding-resolve.sh not found in repository")

    org_path = os.path.join(repo_root, "docs", "agentic-sdlc", "CADENCE_ORG.md")
    rc, out, err = _run_cmd(["bash", resolver, "--tracker", prefix, "--org", org_path], cwd=repo_root)
    if rc != 0:
        raise SourceHalt("tracker_binding_failed", err.strip() or out.strip() or f"resolver exited {rc}")

    tracker = dict(ln.split("=", 1) for ln in out.splitlines() if "=" in ln).get("tracker", "")
    if tracker == "inner-source":
        return {"status": "skipped_inner_source", "tracker": tracker, "comments": []}
    if tracker not in ("jira", "youtrack"):
        raise SourceHalt("tracker_unmapped", f"unsupported tracker {tracker!r} for prefix {prefix}")

    raw_url = jira_url if tracker == "jira" else youtrack_url
    if not raw_url:
        return {"status": "skipped_no_tracker_url", "tracker": tracker, "comments": []}

    cfg = (
        ("cadence-sync-jira", "jira-server-config.json", {"base_url": "JIRA_BASE_URL", "pat": "JIRA_PAT"}, "pat")
        if tracker == "jira"
        else ("cadence-sync-youtrack", "youtrack-server-config.json", {"base_url": "YOUTRACK_BASE_URL", "token": "YOUTRACK_TOKEN"}, "token")
    )
    env_map = _load_env_names(repo_root, cfg[0], cfg[1], cfg[2])
    base_url = os.environ.get(env_map["base_url"], "").strip()
    secret = os.environ.get(env_map[cfg[3]], "").strip()
    if not base_url or not secret:
        raise SourceHalt("tracker_env_unset", f"bound tracker {tracker} requires {env_map['base_url']} and {env_map[cfg[3]]} (or --no-tracker)")

    key = _extract_issue_key(raw_url)
    path = (f"/rest/api/2/issue/{key}/comment" if tracker == "jira"
            else f"/api/issues/{key}/comments?fields=id,text,created,updated,deleted,author(login,name)")
    payload = _http_get_json(f"{base_url.rstrip('/')}{path}", secret, tracker)
    items = (payload.get("comments", []) if isinstance(payload, dict) else []) if tracker == "jira" else (payload if isinstance(payload, list) else [])

    comments = []
    for c in items:
        if tracker == "youtrack" and c.get("deleted"):
            continue
        body = (c.get("body") if tracker == "jira" else c.get("text")) or ""
        if is_ignored_body(body):
            continue
        a = c.get("author") or {}
        comments.append({
            "id": str(c.get("id") or ""),
            "author": (a.get("displayName") or a.get("name") or "unknown") if tracker == "jira" else (a.get("login") or a.get("name") or "unknown"),
            "body": body, "created_at": str(c.get("created") or ""), "updated_at": str(c.get("updated") or ""), "source": tracker,
        })
    return {"status": "ok", "tracker": tracker, "comments": comments}


def fetch_github_issue_comments(issue_url: str, repo_root: str) -> dict:
    """Poll an upstream GitHub issue referenced by github_issue_url via gh."""
    url = (issue_url or "").strip()
    if not url:
        return {"status": "skipped_no_issue_url", "issue_url": "", "issue_state": "", "comments": []}
    if not shutil.which("gh"):
        raise SourceHalt("gh_missing", "gh CLI is not installed -- cannot query GitHub issue")
    rc, out, err = _run_cmd(["gh", "issue", "view", url, "--json", "number,url,state,closedAt,comments"], cwd=repo_root)
    if rc != 0:
        raise SourceHalt("forge_unreachable", f"gh issue view {url} failed: {err.strip()[:220]}")
    try:
        data = json.loads(out)
    except json.JSONDecodeError as exc:
        raise SourceHalt("forge_unreachable", f"gh issue view returned invalid JSON: {exc}")
    comments = []
    for c in data.get("comments") or []:
        body = c.get("body") or ""
        if is_ignored_body(body):
            continue
        author = (c.get("author") or {}).get("login") or "unknown"
        created = c.get("createdAt") or ""
        comments.append({
            "id": str(c.get("id") or f"{author}:{created}"), "author": author,
            "body": body, "created_at": created, "source": "github_issue",
        })
    return {
        "status": "polled_github_issue", "issue_url": data.get("url") or url,
        "issue_state": (data.get("state") or "OPEN").upper(), "comments": comments,
    }


def classify_github_issue(repo_root: str, issue_url: str, seen_ids: list | set, res: dict) -> dict:
    """Populate classify_ticket result for an upstream github_issue_url pre-PR."""
    gh_iss = fetch_github_issue_comments(issue_url, repo_root)
    seen = set(seen_ids or [])
    new_tr = [c for c in gh_iss["comments"] if c["id"] not in seen]
    res.update({
        "pr_kind": "github_issue", "pr_ref": issue_url, "pr_url": gh_iss["issue_url"],
        "forge": "github", "pr_state": gh_iss["issue_state"], "tracker_status": gh_iss["status"],
        "tracker": "github_issue", "new_tracker_comments": new_tr, "has_new_comments": bool(new_tr),
    })
    if gh_iss["issue_state"] == "CLOSED":
        res["event"], res["next_action"] = "closed_unmerged", "halt_human_rejected"
    elif new_tr:
        res["event"], res["next_action"] = "comments_new", "triage_comments"
    else:
        res["event"], res["next_action"] = "idle", "none"
    return res
