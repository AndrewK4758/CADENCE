#!/usr/bin/env bash
# security-trigger.sh -- Deterministic hybrid trigger for cadence-security-auditor
# Always triggers on tier=High; exempts tier=Trivial; inspects diff/working-tree
# paths & added/modified hunks on Low/Medium for security/concurrency signals.
# Fails closed (exit 1) when metadata.yaml or tier is missing/empty/unrecognized.
#
# Usage:
#   security-trigger.sh [--root <repo-root>] [--code-root <dir>]... [--base <ref>] [--scan-signals] <ticket-id>
# Output:
#   decision=TRIGGER|SKIP tier=<t> signals=<csv|none> reason=<why> [files=<csv>]

set -euo pipefail

usage() {
  echo "Usage: $0 [--root <repo-root>] [--code-root <dir>]... [--base <ref>] [--scan-signals] <ticket-id>" >&2
  exit 1
}

ROOT=""
BASE=""
BASE_EXPLICIT=0
SCAN_SIGNALS=0
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
    --scan-signals)
      SCAN_SIGNALS=1; shift ;;
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

python3 - "$ROOT" "$BASE" "$BASE_EXPLICIT" "$TICKET" "$SCAN_SIGNALS" "${CODE_ROOTS[@]+"${CODE_ROOTS[@]}"}" <<'PY'
import pathlib, re, subprocess, sys

root = pathlib.Path(sys.argv[1]).resolve()
base_arg, base_explicit = sys.argv[2], int(sys.argv[3])
ticket = sys.argv[4]
scan_signals = int(sys.argv[5])
raw_code_roots = sys.argv[6:]
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

raw_tier = None
for raw in meta_path.read_text(encoding="utf-8", errors="replace").splitlines():
    m = re.match(r"^\s*tier:\s*(.*)$", raw)
    if not m:
        continue
    val = m.group(1).strip()
    if not val:
        raw_tier = ""
        break
    for q in ('"', "'"):
        if val.startswith(q):
            end = val.find(q, 1)
            val = val[1:end].strip() if end != -1 else val.strip()
            break
    else:
        val = re.sub(r"\s+#.*$", "", val).strip()
    raw_tier = val
    break

if raw_tier is None or not raw_tier.strip():
    sys.exit(f"ERROR: cannot resolve tier in {meta_path.relative_to(root)}")

tier = raw_tier.strip().lower()
if tier not in {"trivial", "low", "medium", "high"}:
    sys.exit(f"ERROR: unrecognized tier {raw_tier!r} in {meta_path.relative_to(root)}")

if tier == "trivial":
    print("decision=SKIP tier=trivial signals=none reason=trivial-tier-exempt")
    sys.exit(0)

if tier == "high" and not scan_signals:
    print("decision=TRIGGER tier=high signals=high-tier reason=high-tier-mandatory")
    sys.exit(0)

def git_ok(repo_dir, *args):
    return subprocess.run(["git", "-C", str(repo_dir), *args], capture_output=True, text=True)

def org_branch(repo_dir):
    for sub in ("docs/agentic-sdlc/CADENCE_ORG.md", "CADENCE_ORG.md", "processes/docs/agentic-sdlc/CADENCE_ORG.md"):
        cand = repo_dir / sub
        if cand.is_file():
            m = re.search(r"integration-branch:\s*([^\s>`'\"]+)", cand.read_text(encoding="utf-8", errors="replace"))
            if m and not m.group(1).startswith("<"):
                return m.group(1)
    return None

def resolve_base(repo_dir):
    if base_explicit:
        if git_ok(repo_dir, "rev-parse", "--verify", "--quiet", f"{base_arg}^{{commit}}").returncode != 0:
            sys.exit(f"ERROR: base ref does not resolve: {base_arg}")
        return base_arg
    branch = org_branch(repo_dir)
    cands = [f"origin/{branch}", branch] if branch else []
    if repo_dir != root or not cands:
        r_sym = git_ok(repo_dir, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        if r_sym.returncode == 0 and r_sym.stdout.strip():
            sym = r_sym.stdout.strip()
            cands.extend([sym, sym.split("/", 1)[-1]])
        cands.extend(["origin/main", "origin/develop", "main", "develop"])
    for ref in cands + ["HEAD"]:
        if git_ok(repo_dir, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}").returncode == 0:
            return ref
    return None

SIGNALS = {
    "auth": re.compile(r"(?<![A-Za-z0-9])(?:auth[nz]?|oauth|oidc|jwt|rbac|acl|session|cookie|permission|authorize|login|logout|sudo|csrf|cors)(?![A-Za-z0-9])", re.I),
    "secrets_crypto": re.compile(r"(?:\.env(?:\.|$)|(?<![A-Za-z0-9])(?:secret|api[_-]?key|apikey|password|passwd|credential|private[_-]?key|hmac|encrypt|decrypt|cipher|pkcs|pem|tls|ssl|bearer|signing[_-]?key|bcrypt|argon2|scrypt|pbkdf2|redact|scrub|sanitize[_a-z]*|guardrail)(?![A-Za-z0-9]))", re.I),
    "data_sql": re.compile(r"(?:migrat|schema|\.sql$|(?<![A-Za-z0-9])(?:SELECT\s+.+\s+FROM|INSERT\s+INTO|UPDATE\s+.+\s+SET|DELETE\s+FROM|ALTER\s+TABLE|CREATE\s+TABLE|DROP\s+TABLE|raw[_-]?query|execute[_-]?sql|cursor\.execute)(?![A-Za-z0-9]))", re.I),
    "concurrency": re.compile(r"(?<![A-Za-z0-9])(?:flock|mutex|rwlock|semaphore|lock|unlock|atomic|transaction|serializable|for\s+update|asyncio|threading|multiprocessing|goroutine|concurrent|race|idempoten[a-z]*|nonce|compare[_-]?and[_-]?swap|abort[_ ]?controller|abort[_ ]?signal|ioredis|bull|max[_ ]?retries[_ ]?per[_ ]?request)(?![A-Za-z0-9])", re.I),
    "untrusted_exec": re.compile(r"(?<![A-Za-z0-9])(?:subprocess|shell\s*=\s*True|os\.system|eval\(|exec\(|pickle\.loads?|yaml\.load|marshal\.loads?|deserialize|unserialize|redirect[_-]?url|webhook|presign|tarfile\.extract|zipfile|path[_-]?traversal|docker[_-]?stack|swarm)(?![A-Za-z0-9])", re.I),
}

matched_signals = set()
matched_files = set()
pathspecs = ["--", ".", ":!specs/", ":!archive/", ":!docs/"]
multi_repo = len(code_roots) > 1

def normalize_ident(s):
    return re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", s)

def check_text(rel, disp, txt):
    if rel.endswith(".md"):
        return
    norm_rel = normalize_ident(rel)
    norm_txt = normalize_ident(txt)
    for name, pat in SIGNALS.items():
        if pat.search(norm_rel) or pat.search(norm_txt):
            matched_signals.add(name)
            matched_files.add(disp)

for cr in code_roots:
    base_ref = resolve_base(cr)
    changed_files = set()
    diff_chunks = []
    if base_ref:
        r_names = git_ok(cr, "diff", "--name-only", f"{base_ref}...HEAD", *pathspecs)
        if r_names.returncode == 0:
            changed_files.update(p for p in r_names.stdout.splitlines() if p)
        r_diff = git_ok(cr, "diff", "-U0", f"{base_ref}...HEAD", *pathspecs)
        if r_diff.returncode == 0:
            diff_chunks.append(r_diff.stdout)
    for wt_args in (["diff", "-U0", "--cached", *pathspecs], ["diff", "-U0", *pathspecs]):
        r_wt = git_ok(cr, *wt_args)
        if r_wt.returncode == 0 and r_wt.stdout:
            diff_chunks.append(r_wt.stdout)
    for nm_args in (["diff", "--name-only", "--cached", *pathspecs], ["diff", "--name-only", *pathspecs], ["ls-files", "-o", "--exclude-standard", *pathspecs]):
        r_nm = git_ok(cr, *nm_args)
        if r_nm.returncode == 0:
            changed_files.update(p for p in r_nm.stdout.splitlines() if p)

    current_rel = None
    current_buf = []
    for chunk in diff_chunks:
        for line in chunk.splitlines():
            if line.startswith("diff --git a/"):
                if current_rel:
                    check_text(current_rel, f"{cr.name}:{current_rel}" if multi_repo else current_rel, "\n".join(current_buf))
                current_rel = line.split(" b/", 1)[-1].strip()
                current_buf = []
            elif line.startswith("+++ b/"):
                current_rel = line[6:].strip()
            elif line.startswith("--- a/") and not current_rel:
                current_rel = line[6:].strip()
            elif (line.startswith("+") and not line.startswith("+++")) or (line.startswith("-") and not line.startswith("---")):
                current_buf.append(line[1:])
    if current_rel:
        check_text(current_rel, f"{cr.name}:{current_rel}" if multi_repo else current_rel, "\n".join(current_buf))

    untracked_set = set(git_ok(cr, "ls-files", "-o", "--exclude-standard", *pathspecs).stdout.splitlines())
    for rel in sorted(changed_files):
        if rel.endswith(".md"):
            continue
        disp = f"{cr.name}:{rel}" if multi_repo else rel
        norm_rel = normalize_ident(rel)
        for name, pat in SIGNALS.items():
            if pat.search(norm_rel):
                matched_signals.add(name)
                matched_files.add(disp)
        p = cr / rel
        if p.is_file() and (not base_ref or rel in untracked_set):
            try:
                body = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                body = ""
            check_text(rel, disp, body)

if matched_signals:
    sigs = ",".join(sorted(matched_signals))
    files = ",".join(sorted(matched_files)) or "diff"
    reason = "high-tier-mandatory" if tier == "high" else "diff-signal-match"
    print(f"decision=TRIGGER tier={tier} signals={sigs} reason={reason} files={files}")
elif tier == "high":
    print("decision=TRIGGER tier=high signals=high-tier reason=high-tier-mandatory")
else:
    print(f"decision=SKIP tier={tier} signals=none reason=no-risk-signals")
PY
