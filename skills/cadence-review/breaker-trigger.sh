#!/usr/bin/env bash
# breaker-trigger.sh -- Deterministic hybrid trigger for cadence-breaker
# Triggers on High tier, any rework cycle, Medium tier with non-doc code diffs,
# and Low tier initial diffs touching async/stream/timeout/error/upgrade/config signals.
# Exempts Trivial tier and docs-only / benign Low-tier changes; fails closed on bad inputs.
#
# Usage:
#   breaker-trigger.sh [--root <cadence-root>] [--code-root <target-repo>]... [--base <ref>] <ticket-id>
# Output:
#   decision=TRIGGER|SKIP tier=<t> mode=<exempt|initial|rework> reason=<why> [rework_base=<sha>] [files=<csv>]

set -euo pipefail

usage() {
  echo "Usage: $0 [--root <cadence-root>] [--code-root <target-repo>]... [--base <ref>] <ticket-id>" >&2
  exit 1
}

ROOT=""
BASE=""
BASE_EXPLICIT=0
TICKET=""
CODE_ROOTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || usage
      ROOT="$2"; shift 2 ;;
    --code-root)
      [[ $# -ge 2 ]] || usage
      CODE_ROOTS+=("$2"); shift 2 ;;
    --base)
      [[ $# -ge 2 ]] || usage
      BASE="$2"; BASE_EXPLICIT=1; shift 2 ;;
    -*) usage ;;
    *)
      [[ -z "$TICKET" ]] || usage
      TICKET="$1"; shift ;;
  esac
done
[[ -n "$TICKET" ]] || usage

if [[ -z "$ROOT" ]]; then
  ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

python3 - "$ROOT" "$BASE" "$BASE_EXPLICIT" "$TICKET" "${CODE_ROOTS[@]+"${CODE_ROOTS[@]}"}" <<'PY'
import pathlib, re, subprocess, sys

root = pathlib.Path(sys.argv[1]).resolve()
base_arg, base_explicit = sys.argv[2], int(sys.argv[3])
ticket = sys.argv[4]
raw_code_roots = sys.argv[5:]
code_roots = [pathlib.Path(p).resolve() for p in raw_code_roots] if raw_code_roots else [root]
for cr in code_roots:
    if not cr.is_dir():
        sys.exit(f"ERROR: --code-root is not a directory: {cr}")

ticket_dir = root / "specs" / ticket
if not ticket_dir.is_dir():
    ticket_dir = root / "archive" / ticket
if not ticket_dir.is_dir():
    sys.exit(f"ERROR: no artifacts for {ticket} -- searched specs/{ticket}/ and archive/{ticket}/")

meta_path = ticket_dir / "metadata.yaml"
if not meta_path.is_file():
    sys.exit(f"ERROR: cannot resolve tier -- missing {meta_path.relative_to(root)}")

raw_tier, status_val = None, ""
for raw in meta_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if m := re.match(r"^\s*tier:\s*(.*)$", raw):
        if raw_tier is None:
            val = m.group(1).strip()
            for q in ('"', "'"):
                if val.startswith(q):
                    end = val.find(q, 1)
                    val = val[1:end].strip() if end != -1 else val.strip()
                    break
            else:
                val = re.sub(r"\s+#.*$", "", val).strip()
            raw_tier = val
    elif m := re.match(r"^\s*status:\s*(.*)$", raw):
        if not status_val:
            status_val = m.group(1).strip().strip("\"'").lower()

if not raw_tier or not raw_tier.strip():
    sys.exit(f"ERROR: cannot resolve tier in {meta_path.relative_to(root)}")
tier = raw_tier.strip().lower()
if tier not in {"trivial", "low", "medium", "high"}:
    sys.exit(f"ERROR: unrecognized tier {raw_tier!r} in {meta_path.relative_to(root)}")
if tier == "trivial":
    print("decision=SKIP tier=trivial mode=exempt reason=trivial-tier-exempt")
    sys.exit(0)

sub_path = ticket_dir / "submission.md"
sub_text = sub_path.read_text(encoding="utf-8", errors="replace") if sub_path.is_file() else ""
cycle_matches = list(re.finditer(r"<!--\s*cadence-run:cycle\b(.*?)-->", sub_text))
last_cycle_sha = ""
if cycle_matches:
    parsed_cycles = []
    for idx, cm in enumerate(cycle_matches):
        kv = dict(re.findall(r"([a-z_]+)=([^\s>]+)", cm.group(1)))
        parsed_cycles.append((int(kv.get("n", idx + 1)), idx, kv.get("sha", "")))
    parsed_cycles.sort(key=lambda x: (x[0], x[1]))
    last_cycle_sha = parsed_cycles[-1][2]
is_rework = (
    status_val in {"rework", "changes-requested", "blocked"}
    or bool(cycle_matches)
    or bool(re.search(r"\bREQUEST CHANGES\b|\bVerdict:\s*BROKEN\b", sub_text))
)
mode = "rework" if is_rework else "initial"

def git_ok(repo_dir, *args):
    return subprocess.run(["git", "-C", str(repo_dir), *args], capture_output=True, text=True)

def resolve_base(repo_dir):
    if base_explicit:
        if git_ok(repo_dir, "rev-parse", "--verify", "--quiet", f"{base_arg}^{{commit}}").returncode != 0:
            sys.exit(f"ERROR: base ref does not resolve: {base_arg}")
        return base_arg
    cands = []
    for sub in ("docs/agentic-sdlc/CADENCE_ORG.md", "CADENCE_ORG.md", "processes/docs/agentic-sdlc/CADENCE_ORG.md"):
        cand = repo_dir / sub
        if cand.is_file() and (m := re.search(r"integration-branch:\s*([^\s>`'\"]+)", cand.read_text(encoding="utf-8", errors="replace"))) and not m.group(1).startswith("<"):
            cands.extend([f"origin/{m.group(1)}", m.group(1)])
            break
    if repo_dir != root or not cands:
        r_sym = git_ok(repo_dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        if r_sym.returncode == 0 and r_sym.stdout.strip():
            sym = r_sym.stdout.strip()
            cands.extend([sym, sym.split("/", 1)[-1]])
        cands.extend(["origin/main", "origin/develop", "main", "develop"])
    return next((r for r in cands + ["HEAD"] if git_ok(repo_dir, "rev-parse", "--verify", "--quiet", f"{r}^{{commit}}").returncode == 0), None)

LOW_SIGNALS = re.compile(r"(?<![A-Za-z0-9])(?:await|async|abort[_ ]?(?:controller|signal)|promise|cancel|timeout|settimeout|retry|retries|backoff|idempoten[a-z]*|dedup[a-z]*|ttl|expir[a-z]*|session[_ ]?storage|local[_ ]?storage|queue|redis|headers[_ ]?sent|stream|sse|flock|mutex|lock|transaction|for\s+update|outbox|compensat[a-z]*|rollback|deploy|storage[_ ]?backend|filesystem|docker[_-]?stack|env|redact|scrub|sanitize|guardrail|parser|lexer|regex|quota|headroom)(?![A-Za-z0-9])", re.I)
code_files, all_changed, low_signal_files = set(), set(), set()
multi_repo, pathspecs = len(code_roots) > 1, ["--", ".", ":!specs/", ":!archive/"]

for cr in code_roots:
    base_ref = resolve_base(cr)
    changed_in_cr, diff_chunks = set(), []
    name_cmds = (["diff", "--name-only", "--cached", *pathspecs], ["diff", "--name-only", *pathspecs], ["ls-files", "-o", "--exclude-standard", *pathspecs])
    diff_cmds = (["diff", "-U0", "--cached", *pathspecs], ["diff", "-U0", *pathspecs])
    if base_ref:
        name_cmds = (["diff", "--name-only", f"{base_ref}...HEAD", *pathspecs],) + name_cmds
        diff_cmds = (["diff", "-U0", f"{base_ref}...HEAD", *pathspecs],) + diff_cmds
    for cmd in name_cmds:
        if (r := git_ok(cr, *cmd)).returncode == 0:
            changed_in_cr.update(p for p in r.stdout.splitlines() if p)
    for cmd in diff_cmds:
        if (r := git_ok(cr, *cmd)).returncode == 0 and r.stdout:
            diff_chunks.append(r.stdout)
    untracked_set = set(git_ok(cr, "ls-files", "-o", "--exclude-standard", *pathspecs).stdout.splitlines())
    for rel in changed_in_cr:
        disp = f"{cr.name}:{rel}" if multi_repo else rel
        all_changed.add(disp)
        if not rel.endswith(".md") and not rel.startswith("docs/"):
            code_files.add(disp)
            if LOW_SIGNALS.search(rel) or ((not base_ref or rel in untracked_set) and (cr / rel).is_file() and LOW_SIGNALS.search((cr / rel).read_text(encoding="utf-8", errors="replace"))):
                low_signal_files.add(disp)
    cur_rel, cur_buf = None, []
    for line in "\n".join(diff_chunks).splitlines():
        if line.startswith("diff --git a/"):
            if cur_rel and not cur_rel.endswith(".md") and not cur_rel.startswith("docs/") and (LOW_SIGNALS.search(cur_rel) or LOW_SIGNALS.search("\n".join(cur_buf))):
                low_signal_files.add(f"{cr.name}:{cur_rel}" if multi_repo else cur_rel)
            cur_rel, cur_buf = line.split(" b/", 1)[-1].strip(), []
        elif line.startswith("+++ b/"):
            cur_rel = line[6:].strip()
        elif (line.startswith("+") and not line.startswith("+++")) or (line.startswith("-") and not line.startswith("---")):
            cur_buf.append(line[1:])
    if cur_rel and not cur_rel.endswith(".md") and not cur_rel.startswith("docs/") and (LOW_SIGNALS.search(cur_rel) or LOW_SIGNALS.search("\n".join(cur_buf))):
        low_signal_files.add(f"{cr.name}:{cur_rel}" if multi_repo else cur_rel)

rework_base_tokens = []
if is_rework and last_cycle_sha:
    sha_map = {}
    for tok in last_cycle_sha.split(","):
        if ":" in tok:
            k, v = tok.split(":", 1)
            sha_map[k] = v
        elif tok:
            sha_map["*"] = tok
    for cr in code_roots:
        cand_sha = sha_map.get(cr.name) or sha_map.get("*")
        if not cand_sha:
            continue
        r_ver = git_ok(cr, "rev-parse", "--verify", "--quiet", f"{cand_sha}^{{commit}}")
        if r_ver.returncode == 0:
            short_sha = git_ok(cr, "rev-parse", "--short", cand_sha).stdout.strip() or cand_sha
            rework_base_tokens.append(f"{cr.name}:{short_sha}" if multi_repo else short_sha)
            r_delta = git_ok(cr, "diff", "--name-only", f"{cand_sha}..HEAD", *pathspecs)
            if r_delta.returncode == 0:
                for rel in (p for p in r_delta.stdout.splitlines() if p):
                    disp = f"{cr.name}:{rel}" if multi_repo else rel
                    all_changed.add(disp)
                    if not rel.endswith(".md") and not rel.startswith("docs/"):
                        code_files.add(disp)
        else:
            rework_base_tokens.append(f"unreachable:{cr.name}:{cand_sha}" if multi_repo else f"unreachable:{cand_sha}")

files_csv = ",".join(sorted(low_signal_files or code_files))
rework_part = f" rework_base={','.join(rework_base_tokens)}" if rework_base_tokens else ""
suffix = f" files={files_csv}" if files_csv else ""
if is_rework:
    print(f"decision=TRIGGER tier={tier} mode=rework reason=rework-mandatory{rework_part}{suffix}")
elif tier == "high":
    print(f"decision=TRIGGER tier=high mode={mode} reason=high-tier-mandatory{suffix}")
elif tier == "medium":
    if code_files:
        print(f"decision=TRIGGER tier=medium mode=initial reason=medium-tier-code-diff files={','.join(sorted(code_files))}")
    elif all_changed:
        print("decision=SKIP tier=medium mode=initial reason=docs-only-exempt")
    else:
        print("decision=SKIP tier=medium mode=initial reason=no-code-diff")
else:
    if low_signal_files:
        print(f"decision=TRIGGER tier=low mode=initial reason=low-tier-signal-match files={','.join(sorted(low_signal_files))}")
    elif all_changed and not code_files:
        print("decision=SKIP tier=low mode=initial reason=docs-only-exempt")
    else:
        print("decision=SKIP tier=low mode=initial reason=no-breaker-signals")
PY
