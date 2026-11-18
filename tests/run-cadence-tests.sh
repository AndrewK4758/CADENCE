#!/usr/bin/env bash
# Offline regression & verification suite for the hardened CADENCE repository.
# Usage: bash tests/run-cadence-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TMP_DIRS=()

cleanup() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [[ -n "$d" && -e "$d" ]] && rm -rf "$d" "${d}.eject-audit.txt" 2>/dev/null || true
  done
  rm -f /tmp/agy-offload-*.cadence_test_* 2>/dev/null || true
}
trap cleanup EXIT

run_subtest() {
  local name="$1"; shift
  local rc=0
  set +e
  ( set -euo pipefail; "$@" )
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "PASS: $name"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $name" >&2
  fi
}

echo "=== CADENCE Verification Suite ($ROOT) ==="

t1a_hygiene() {
  python3 - "$ROOT" <<'PY'
import json, pathlib, re, sys, yaml

root = pathlib.Path(sys.argv[1])
forbidden = re.compile(r"\b(?:" + chr(99) + r"laire|" + "spect" + r"[ru]{2}m)\b", re.I)
errs = []

for p in root.rglob("*"):
    if ".git" in p.parts or not p.is_file() or p.is_symlink() or p.suffix in {".png", ".jpg", ".pyc", ".gguf"}:
        continue
    try:
        text = p.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if m := forbidden.search(text):
        errs.append(f"forbidden token {m.group(0)!r} in {p.relative_to(root)}")
    rel = p.relative_to(root).as_posix()
    if (
        rel.startswith(("agents/", "hooks/", "local-offload/mcp/", "tests/"))
        or re.match(r"skills/.*/SKILL\.md$", rel)
        or rel.startswith(("skills/cadence-spec/", "skills/cadence-review/references/", "skills/cadence-cycle/references/", "skills/cadence-adopt/", "skills/cadence-doctor/", "skills/cadence-prep/scripts/", "skills/cadence-cycle/scripts/"))
    ):
        if len(text.splitlines()) >= 400:
            errs.append(f"line ceiling >=400 ({len(text.splitlines())}L) in {rel}")
    if p.suffix == ".json":
        json.loads(text)

allowed_fm = {"name", "description", "tools", "default_model", "permission_mode", "effort"}
expected_effort = {
    "cadence-architect": "xhigh",
    "cadence-explorer": "xhigh",
    "cadence-spec-author": "xhigh",
    "cadence-implementer": "xhigh",
    "cadence-migration-author": "xhigh",
    "cadence-reviewer": "xhigh",
    "cadence-maintainer": "xhigh",
    "cadence-triage-agent": "high",
    "cadence-archivist": "high",
    "log-triage": "medium",
    "repo-scout": "medium",
}
provider_leak = re.compile(r'Model="(?:pro|flash)"|Gemini 4 Argon|flash optional', re.I)
for am in sorted((root / "agents").glob("*/agent.md")):
    txt = am.read_text(encoding="utf-8")
    data = yaml.safe_load(txt.split("---\n", 2)[1])
    extra = set(data.keys()) - allowed_fm
    if extra:
        errs.append(f"disallowed frontmatter keys {sorted(extra)} in {am.relative_to(root)}")
    aname = am.parent.name
    if data.get("effort") != expected_effort.get(aname):
        errs.append(f"unexpected effort {data.get('effort')!r} in {am.relative_to(root)} (expected {expected_effort.get(aname)!r})")
    if m := provider_leak.search(txt):
        errs.append(f"provider-specific routing {m.group(0)!r} in {am.relative_to(root)}")

for sm in sorted((root / "skills").glob("*/SKILL.md")):
    txt = sm.read_text(encoding="utf-8")
    parts = txt.split("---\n", 2)
    if len(parts) >= 3 and re.search(r"^model:", parts[1], re.M):
        errs.append(f"hardcoded model: in {sm.relative_to(root)}")
    for bad in ("/cadence-run", "/cadence-finish"):
        if bad in txt:
            errs.append(f"dangling command {bad} in {sm.relative_to(root)}")
    if m := provider_leak.search(txt):
        errs.append(f"provider-specific routing {m.group(0)!r} in {sm.relative_to(root)}")
    eval_file = sm.parent / "evals" / "evals.json"
    if not eval_file.is_file():
        errs.append(f"missing evals file: {eval_file.relative_to(root)}")
    else:
        edata = json.loads(eval_file.read_text(encoding="utf-8"))
        if edata.get("skill_name") != sm.parent.name:
            errs.append(f"evals skill_name mismatch in {eval_file.relative_to(root)}: {edata.get('skill_name')!r}")
        cases = edata.get("evals")
        if not isinstance(cases, list) or len(cases) < 2:
            errs.append(f"evals must declare >=2 cases in {eval_file.relative_to(root)}")
        else:
            for c in cases:
                if not all(k in c for k in ("id", "name", "prompt", "expected_output", "assertions")) or not c["assertions"]:
                    errs.append(f"malformed eval case in {eval_file.relative_to(root)}: {c!r}")

for a, b in [
    ("hooks/antigravity-local-offload-hook", "hooks/local-offload-enforcer.sh"),
    ("skills/cadence-prep/scripts/read_state.py", "skills/cadence-cycle/scripts/read_state.py"),
    ("skills/cadence-prep/scripts/ready_mr.sh", "skills/cadence-cycle/scripts/ready_mr.sh"),
]:
    if (root / a).read_bytes() != (root / b).read_bytes():
        errs.append(f"twin drift: {a} != {b}")

if errs:
    print("\n".join(errs), file=sys.stderr)
    sys.exit(1)
PY
}

t1b_syntax() {
  while IFS= read -r -d '' shf; do
    bash -n "$shf"
  done < <(find "$ROOT/hooks" "$ROOT/import" "$ROOT/skills/cadence-adopt" "$ROOT/skills/cadence-doctor" "$ROOT/skills/cadence-spec" "$ROOT/skills/cadence-implement" "$ROOT/skills/cadence-upgrade" "$ROOT/processes/ci-templates/scripts" "$ROOT/tests" -maxdepth 2 -name '*.sh' -print0)
}

t2_hooks() {
  rm -f /tmp/agy-offload-*.cadence_test_* 2>/dev/null || true
  python3 - "$ROOT" <<'PY'
import json, os, pathlib, subprocess, sys

root = pathlib.Path(sys.argv[1])
hook = str(root / "hooks" / "antigravity-local-offload-hook")
stop = str(root / "hooks" / "tms-doc-sync-stop.sh")
sid = f"cadence_test_{os.getpid()}"

p1 = subprocess.run([hook, "PreInvocation"], input=json.dumps({"invocationNum": 1, "conversationId": sid}), text=True, capture_output=True, check=True)
j1 = json.loads(p1.stdout)
assert "ephemeralMessage" not in j1
assert "COGNITIVE & LOCAL-OFFLOAD GATE" in j1["injectSteps"][0]["systemMessage"]["systemMessage"]

p2 = subprocess.run([hook, "PostToolUse"], input=json.dumps({"conversationId": sid, "tool_name": "run_command", "tool_input": {"command": "git status"}}), text=True, capture_output=True, check=True)
assert p2.stdout.strip() == "", f"expected empty on git status, got {p2.stdout!r}"

p3 = subprocess.run([hook, "PostToolUse"], input=json.dumps({"conversationId": sid, "tool_name": "run_command", "tool_input": {"command": "pytest tests/"}}), text=True, capture_output=True, check=True)
assert "offload_log_triage" in json.loads(p3.stdout)["systemMessage"]

p4 = subprocess.run([stop], input=json.dumps({"continuationActive": True}), text=True, capture_output=True, check=True)
assert p4.stdout.strip() == ""
PY
}

t3_offload() {
  local py_runner=(python3)
  [[ -x "/home/ak/.local/bin/uv" ]] && py_runner=(/home/ak/.local/bin/uv run --with "mcp>=1.2.0,<2.0.0" python3)
  "${py_runner[@]}" - "$ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys

root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / "local-offload" / "mcp"))
import offload_core as oc

for sig in ("AssertionError: bad", "ValueError: x", "NullReferenceException", "FAIL\tpkg/a", "● suite fail", "FAILED test.py"):
    assert oc.FAIL_SIGNAL_RE.search(sig), sig

assert oc.SYMBOL_RE.match("public async Task<int> ComputeAsync(string id) {}")
assert oc.SYMBOL_RE.match("suspend fun fetchItems(limit: Int): List<String> {}")

rows, flags, diffs = oc.collect_git_diff_context("466c632~1..466c632", root)
assert rows and diffs and any("link-sdlc.sh" in r for r in rows), rows
assert len(diffs[0]) <= 10500

metas, chunks, stats = oc.expand_targets([str(root / ".agents")], max_files=2)
assert stats["truncated"] >= 0 and stats["indexed"] <= 2 and chunks, stats

try:
    loader = importlib.machinery.SourceFileLoader("agy_mcp", str(root / "local-offload" / "mcp" / "antigravity-local-offload-mcp"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    assert "ERROR:" in mod.offload_log_triage("cmd:pwd", cwd="/nonexistent-cadence-test-dir-xyz")
    assert str(root) in mod.offload_log_triage("cmd:pwd", cwd=str(root))
    assert "ERROR:" in mod.offload_deep_review("check", cwd="/nonexistent-cadence-test-dir-xyz")
except ModuleNotFoundError:
    pass
PY
}

t4_fixture_and_gates() {
  local fix="$1"
  bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$fix" >/dev/null
  python3 "$ROOT/skills/cadence-cycle/scripts/read_state.py" ACME-110 --repo-root "$fix" | grep -q "ledger_cycles_completed=3"
  python3 "$ROOT/skills/cadence-prep/scripts/read_state.py" ACME-105 --repo-root "$fix" | grep -q "integration_branch=trunk"
  ! python3 "$ROOT/skills/cadence-prep/scripts/read_state.py" acme-105 --repo-root "$fix" >/dev/null 2>&1
  [[ "$(bash "$ROOT/processes/ci-templates/scripts/stage-effort.sh" --stage spec --observed 7 --root "$fix")" == "15m" ]]
  (cd "$fix" && bash ci-templates/scripts/org-binding-resolve.sh --sprint ACME | grep -q "enabled=no")

  cd "$fix"
  bash "$ROOT/skills/cadence-spec/verify-spec.sh" ACME-201 >/dev/null
  bash "$ROOT/skills/cadence-spec/verify-facts.sh" ACME-201 >/dev/null
  bash "$ROOT/skills/cadence-spec/verify-facts.sh" --rulings ACME-201 >/dev/null
  local fix_doc
  fix_doc="$(bash "$ROOT/skills/cadence-doctor/doctor.sh" --root "$fix" --ticket ACME-201 2>&1 || true)"
  [[ "$fix_doc" == *"PASS  verify-spec (ACME-201)"* ]]
  [[ "$fix_doc" == *"PASS  verify-facts (ACME-201)"* ]]
  [[ "$fix_doc" == *"PASS  verify-facts --rulings (ACME-201)"* ]]

  cp specs/ACME-201/spec.md specs/ACME-201/spec.md.bak
  echo "extra <placeholder>" >> specs/ACME-201/spec.md
  ! bash "$ROOT/skills/cadence-spec/verify-spec.sh" ACME-201 >/dev/null 2>&1
  cp specs/ACME-201/spec.md.bak specs/ACME-201/spec.md
  sed -i '/^### Pillar 4: Data/{n;s/.*/Dormant — none./}' specs/ACME-201/spec.md
  ! bash "$ROOT/skills/cadence-spec/verify-spec.sh" ACME-201 >/dev/null 2>&1
  cp specs/ACME-201/spec.md.bak specs/ACME-201/spec.md
  echo "Recommended option: Option A" >> specs/ACME-201/design-options.md
  ! bash "$ROOT/skills/cadence-spec/verify-spec.sh" ACME-201 >/dev/null 2>&1
  sed -i 's/`compute_total`/`nonexistent_fn`/' specs/ACME-201/spec.md
  ! bash "$ROOT/skills/cadence-spec/verify-facts.sh" ACME-201 >/dev/null 2>&1

  cp "$ROOT/processes/specs/TEMPLATE/problem.md" "$fix/tpl.md"
  ! bash "$ROOT/skills/cadence-implement/ac-classify.sh" "$fix/tpl.md" >/dev/null 2>&1
  sed -i 's/^## Acceptance Criteria.*/## Acceptance Criteria\n- [ ] Concrete behavior verified/' "$fix/tpl.md"
  bash "$ROOT/skills/cadence-implement/ac-classify.sh" "$fix/tpl.md" | grep -qE "verdict=(real|mixed)"

  mkdir -p "$fix/bin" && echo "true" > "$fix/state"
  cat > "$fix/bin/gh" <<SH
#!/usr/bin/env bash
if [[ "\$1 \$2" == "pr view" ]]; then
  printf '{"state":"OPEN","isDraft":%s,"url":"https://github.com/acme/repo/pull/99"}\n' "\$(cat "$fix/state")"
elif [[ "\$1 \$2" == "pr ready" ]]; then
  printf 'false' > "$fix/state"
fi
SH
  chmod +x "$fix/bin/gh"
  PATH="$fix/bin:$PATH" bash "$ROOT/skills/cadence-prep/scripts/ready_mr.sh" 99 | grep -q "result=READY was_draft=yes"
}

t5_adopt_and_eject() {
  local dst="$1" out="$2" reout
  git -C "$dst" init -q && git -C "$dst" commit --allow-empty -q -m "init"
  mkdir -p "$dst/src" && echo "print('app')" > "$dst/src/app.py"
  bash "$ROOT/skills/cadence-adopt/adopt-cadence.sh" "$dst" --gitignore-machinery >/dev/null
  grep -qFx "@CADENCE_DIRECTIVES.md" "$dst/AGENTS.md"
  test -f "$dst/.gemini/GEMINI.md"
  test -e "$dst/.gemini/agents/cadence-reviewer/agent.md"
  test -e "$dst/.gemini/skills/cadence-spec/SKILL.md"
  for ns in cadence-doctor cadence-eject cadence-merge cadence-propose cadence-refactor; do
    test -e "$dst/.gemini/skills/$ns/SKILL.md"
  done
  test -x "$dst/.agents/skills/cadence-doctor/doctor.sh"
  test -e "$dst/.gemini/hooks.json"
  grep -q '\.agents/hooks/' "$dst/.agents/hooks.json"
  (cd "$dst" && bash .agents/skills/cadence-mint/mint-id.sh --peek ADR | grep -q '^ADR-')

  reout="$(bash "$ROOT/skills/cadence-adopt/adopt-cadence.sh" "$dst" --gitignore-machinery)"
  [[ "$reout" == *"skip (exists): CADENCE_DIRECTIVES.md"* ]]
  [[ "$reout" == *"AGENTS.md (CADENCE directives block written)"* ]]

  bash "$ROOT/skills/cadence-doctor/doctor.sh" --root "$ROOT" >/dev/null
  local doc_pre
  doc_pre="$(bash "$dst/.agents/skills/cadence-doctor/doctor.sh" --root "$dst" 2>&1 || true)"
  [[ "$doc_pre" == *"FAIL  org config missing: docs/agentic-sdlc/CADENCE_ORG.md"* ]]
  cp "$dst/docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md" "$dst/docs/agentic-sdlc/CADENCE_ORG.md"
  local doc_org
  doc_org="$(bash "$dst/.agents/skills/cadence-doctor/doctor.sh" --root "$dst" 2>&1 || true)"
  [[ "$doc_org" == *"PASS  org-binding-resolve --form"* ]]
  [[ "$doc_org" == *"PASS  marker integration-branch=develop"* ]]
  [[ "$doc_org" == *"WARN "* ]]

  bash "$dst/ci-templates/scripts/cadence-eject.sh" "$dst" "$out" >/dev/null
  test -f "$out/src/app.py"
  test ! -e "$out/CADENCE_DIRECTIVES.md"
  test ! -e "$out/.agents"
  test ! -e "$out/.gemini"
  test ! -e "$out/AGENTS.md"
  test ! -e "$out/ci-templates"
  bash "$ROOT/processes/ci-templates/scripts/cadence-eject.sh" --check-footprint >/dev/null

  ! bash "$ROOT/skills/cadence-doctor/doctor.sh" --root "$out" >/dev/null 2>&1
  mkdir -p "$dst/archive"
  : > "$dst/ci-templates/scripts/dead-citation-gate.sh"
  local doc_zero
  doc_zero="$(bash "$dst/.agents/skills/cadence-doctor/doctor.sh" --root "$dst" 2>&1 || true)"
  [[ "$doc_zero" == *"FAIL  dead-citation-gate exists but is 0 bytes"* ]]
}

FIX_DIR="$(mktemp -d)"; ADOPT_DST="$(mktemp -d)"; EJECT_OUT="$(mktemp -d)"
TMP_DIRS+=("$FIX_DIR" "$ADOPT_DST" "$EJECT_OUT")

run_subtest "T1a static hygiene, <400L ceiling, JSON, Blitz frontmatter, parity" t1a_hygiene
run_subtest "T1b bash -n syntax validation" t1b_syntax
run_subtest "T2 hooks PreInvocation / PostToolUse / Stop continuationActive" t2_hooks
run_subtest "T3 local-offload core unit tests" t3_offload
run_subtest "T4 fixtures, read_state, verify-spec/facts, ac-classify, ready_mr" t4_fixture_and_gates "$FIX_DIR"
run_subtest "T5 adopt, .gemini projection, mint-id peek, idempotency, eject, check-footprint" t5_adopt_and_eject "$ADOPT_DST" "$EJECT_OUT"

echo "=== Summary: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
