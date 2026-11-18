#!/usr/bin/env python3
"""Offline deterministic eval runner for all 24 CADENCE skills (Option 2C)."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request


class EvalRunner:
    def __init__(self, root: pathlib.Path, skill_filter: str = "", with_offload: bool = False, verbose: bool = False):
        self.root = root.resolve()
        self.skill_filter = skill_filter
        self.with_offload = with_offload
        self.verbose = verbose
        self.tmp_root = pathlib.Path(tempfile.mkdtemp(prefix="cadence-evals-"))
        self.cached_fixtures = {}
        self.case_counter = 0
        self.passed = 0
        self.failed = 0
        self.script_ran = 0
        self.contract_ran = 0
        self.offload_ran = 0

    def cleanup(self):
        shutil.rmtree(self.tmp_root, ignore_errors=True)

    def _build_base_fixture(self, kind: str) -> pathlib.Path:
        if kind in self.cached_fixtures:
            return self.cached_fixtures[kind]
        dst = self.tmp_root / f"base-{kind}"
        dst.mkdir(parents=True, exist_ok=True)
        if kind == "cadence_fixture":
            subprocess.run(
                ["bash", str(self.root / "tests/fixtures/build_cadence_fixture.sh"), str(dst)],
                check=True, capture_output=True, text=True,
            )
        elif kind == "adopted_repo":
            subprocess.run(["git", "-C", str(dst), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(dst), "commit", "--allow-empty", "-q", "-m", "init"], check=True)
            (dst / "src").mkdir(exist_ok=True)
            (dst / "src/app.py").write_text("print('app')\n", encoding="utf-8")
            subprocess.run(
                ["bash", str(self.root / "skills/cadence-adopt/adopt-cadence.sh"), str(dst), "--gitignore-machinery"],
                check=True, capture_output=True, text=True,
            )
            org_tpl = dst / "docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md"
            org_dst = dst / "docs/agentic-sdlc/CADENCE_ORG.md"
            if org_tpl.is_file() and not org_dst.exists():
                shutil.copyfile(org_tpl, org_dst)
        else:
            raise ValueError(f"unknown cached fixture kind: {kind}")
        self.cached_fixtures[kind] = dst
        return dst

    def _prepare_workdir(self, chk: dict) -> pathlib.Path:
        kind = chk.get("fixture", "none")
        if kind == "none":
            return self.root
        self.case_counter += 1
        mutable = bool(chk.get("mutable", False) or chk.get("setup_sh"))
        if kind == "empty_git":
            work = self.tmp_root / f"case-{self.case_counter}"
            work.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "-C", str(work), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(work), "commit", "--allow-empty", "-q", "-m", "init"], check=True)
        else:
            base = self._build_base_fixture(kind)
            work = self.tmp_root / f"case-{self.case_counter}"
            shutil.copytree(base, work, symlinks=True)
        if setup_sh := chk.get("setup_sh"):
            env = dict(os.environ, ROOT=str(self.root), FIX=str(work))
            r = subprocess.run(["bash", "-euo", "pipefail", "-c", setup_sh], cwd=str(work), env=env, capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f"setup_sh failed ({r.returncode}): {r.stderr or r.stdout}")
        return work

    @staticmethod
    def _hash_paths(work: pathlib.Path, rels: list) -> dict:
        out = {}
        for rel in rels:
            p = work / rel
            out[rel] = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
        return out

    def _run_script(self, chk: dict) -> tuple[bool, str]:
        self.script_ran += 1
        work = self._prepare_workdir(chk)
        watch = chk.get("check_unchanged", [])
        before = self._hash_paths(work, watch)
        env = dict(os.environ, ROOT=str(self.root), FIX=str(work))
        r = subprocess.run(["bash", "-c", chk["cmd"]], cwd=str(work), env=env, capture_output=True, text=True, timeout=60)
        exp = chk.get("expect_exit", 0)
        ok_exit = (r.returncode != 0) if exp == "nonzero" else (r.returncode in exp if isinstance(exp, list) else r.returncode == exp)
        if not ok_exit:
            return False, f"exit {r.returncode}, expected {exp}; stderr={r.stderr.strip()[:200]!r}; stdout={r.stdout.strip()[:200]!r}"
        combined = (r.stdout or "") + "\n" + (r.stderr or "")
        for field, text in (("stdout_regex", r.stdout), ("stderr_regex", r.stderr), ("output_regex", combined)):
            for pat in chk.get(field, []):
                if not re.search(pat, text, re.M):
                    return False, f"{field} mismatch {pat!r} in {text.strip()[:220]!r}"
        for field, text in (("not_stdout_regex", r.stdout), ("not_output_regex", combined)):
            for pat in chk.get(field, []):
                if re.search(pat, text, re.M):
                    return False, f"forbidden {field} {pat!r} matched {text.strip()[:220]!r}"
        for rel in chk.get("check_files_exist", []):
            if not (work / rel).exists():
                return False, f"expected path missing: {rel}"
        for rel in chk.get("check_files_absent", []):
            if os.path.lexists(work / rel):
                return False, f"forbidden path exists: {rel}"
        after = self._hash_paths(work, watch)
        for rel in watch:
            if before[rel] != after[rel]:
                return False, f"path mutated unexpectedly: {rel}"
        return True, f"exit={r.returncode}"

    def _run_contract(self, skill_dir: pathlib.Path, chk: dict) -> tuple[bool, str]:
        self.contract_ran += 1
        for rel in chk.get("must_exist", []):
            p = self.root / rel
            if not p.exists() or (p.is_file() and p.stat().st_size == 0):
                return False, f"missing or empty required path: {rel}"
        for spec in chk.get("patterns", []):
            p = self.root / spec["file"]
            if not p.is_file():
                return False, f"contract file missing: {spec['file']}"
            flags = re.M | (re.I if "i" in spec.get("flags", "") else 0)
            if not re.search(spec["regex"], p.read_text(encoding="utf-8"), flags):
                return False, f"pattern {spec['regex']!r} not found in {spec['file']}"
        for spec in chk.get("forbidden_patterns", []):
            p = self.root / spec["file"]
            if p.is_file() and re.search(spec["regex"], p.read_text(encoding="utf-8"), re.M):
                return False, f"forbidden pattern {spec['regex']!r} found in {spec['file']}"
        if chk.get("read_only_tools"):
            txt = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
            fm = txt.split("---\n", 2)[1]
            m = re.search(r"^allowed-tools:\s*(.+)$", fm, re.M)
            if not m or re.search(r"\b(Write|Edit)\b", m.group(1)):
                return False, f"read-only skill exposes write tools: {m.group(1) if m else 'unset'}"
        return True, "contract ok"

    def _offload_grade(self, skill_dir: pathlib.Path, case: dict) -> str:
        self.offload_ran += 1
        skill_body = (skill_dir / "SKILL.md").read_text(encoding="utf-8")[:4000]
        payload = json.dumps({
            "model": "inference",
            "temperature": 0.0,
            "max_tokens": 768,
            "messages": [
                {"role": "system", "content": "Output ONLY one line: 'PASS: <reason>' or 'FAIL: <reason>'."},
                {"role": "user", "content": (
                    f"Skill instructions excerpt:\n{skill_body}\n\nEval prompt: {case['prompt']}\n"
                    f"Expected behavior: {case['expected_output']}\nAssertions: {case['assertions']}\n"
                    "Does the skill specification enforce all assertions? Reply PASS or FAIL cleanly."
                )},
            ],
        }).encode("utf-8")
        req = urllib.request.Request("http://127.0.0.1:11434/v1/chat/completions", data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        choices = data.get("choices") or []
        if not choices:
            return "WARN: empty choices from local offload"
        msg = choices[0].get("message") or {}
        content = (msg.get("content") or "").strip()
        if content:
            lines = [ln.strip() for ln in content.splitlines() if ln.strip()]
            return lines[0] if lines else "WARN: empty content from local offload"
        rtxt = (msg.get("reasoning_content") or "").strip()
        rlines = [ln.strip() for ln in rtxt.splitlines() if ln.strip()]
        return rlines[-1] if rlines else "WARN: empty response body from local offload"

    def _offload_alive(self) -> bool:
        try:
            with urllib.request.urlopen("http://127.0.0.1:11434/health", timeout=2) as r:
                return r.status == 200
        except (urllib.error.URLError, TimeoutError, OSError):
            return False

    def run(self) -> int:
        eval_files = sorted((self.root / "skills").glob("*/evals/evals.json"))
        offload_ok = self.with_offload and self._offload_alive()
        if self.with_offload and not offload_ok:
            print("WARN: --with-offload skipped (:11434/health unreachable)", file=sys.stderr)

        skills_seen = 0
        for ef in eval_files:
            data = json.loads(ef.read_text(encoding="utf-8"))
            sname = data["skill_name"]
            if self.skill_filter and sname != self.skill_filter:
                continue
            skills_seen += 1
            skill_checks = 0
            for case in data["evals"]:
                chk = case.get("check")
                if chk:
                    skill_checks += 1
                    ctype = chk.get("type")
                    try:
                        if ctype == "script":
                            ok, detail = self._run_script(chk)
                        elif ctype == "contract":
                            ok, detail = self._run_contract(ef.parent.parent, chk)
                        elif ctype == "composite":
                            ok, d1 = self._run_script(chk["script"])
                            ok2, d2 = self._run_contract(ef.parent.parent, chk["contract"])
                            ok, detail = (ok and ok2), f"{d1}; {d2}"
                        else:
                            ok, detail = False, f"unknown check type: {ctype!r}"
                    except Exception as exc:
                        ok, detail = False, str(exc)
                    if ok:
                        self.passed += 1
                        if self.verbose:
                            print(f"PASS {sname}[{case['id']}] {case['name']} ({detail})")
                    else:
                        self.failed += 1
                        print(f"FAIL {sname}[{case['id']}] {case['name']}: {detail}", file=sys.stderr)
                if offload_ok and (not chk or chk.get("type") == "contract"):
                    try:
                        verdict = self._offload_grade(ef.parent.parent, case)
                        if self.verbose or verdict.upper().startswith("FAIL"):
                            print(f"OFFLOAD {sname}[{case['id']}] {verdict}")
                    except Exception as exc:
                        print(f"OFFLOAD_WARN {sname}[{case['id']}]: {exc}", file=sys.stderr)
            if skill_checks == 0:
                self.failed += 1
                print(f"FAIL {sname}: 0 executable checks declared in evals.json", file=sys.stderr)

        if skills_seen == 0:
            print(f"ERROR: no skills matched (filter={self.skill_filter!r})", file=sys.stderr)
            return 1
        print(
            f"=== Eval Runner Summary: skills={skills_seen} passed={self.passed} failed={self.failed} "
            f"(script={self.script_ran}, contract={self.contract_ran}, offload={self.offload_ran}) ==="
        )
        return 1 if self.failed > 0 else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(pathlib.Path(__file__).resolve().parent.parent))
    ap.add_argument("--skill", default="")
    ap.add_argument("--with-offload", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    runner = EvalRunner(pathlib.Path(args.root), args.skill, args.with_offload, args.verbose)
    try:
        return runner.run()
    finally:
        runner.cleanup()


if __name__ == "__main__":
    sys.exit(main())
