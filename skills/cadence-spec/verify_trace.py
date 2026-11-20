#!/usr/bin/env python3
"""Post-implementation spec/AC-to-code/test traceability verifier (Option 2A)."""
import os
import pathlib
import re
import subprocess
import sys

from trace_diff_hygiene import analyze_test_diff

SEAMS = ("UNSOUND_CONDITION", "DELTA_AUDIT_GAP", "RULE_DIVERGENCE", "BOUNDARY_FAULT")
SKIP_DIRS = {
    ".git", ".agents", ".claude", ".gemini", ".venv", "venv",
    "node_modules", "__pycache__", ".pytest_cache", "dist", "build", "target",
    "specs", "archive", "docs",
}
BIN_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf",
    ".pyc", ".so", ".o", ".a", ".gguf", ".db", ".sqlite", ".zip", ".tar", ".gz",
}
DOC_FILES = {
    "CADENCE_DIRECTIVES.md", "CHANGELOG.md", "README.md",
    "PROJECT_INTENT.md", "AGENTS.md", "GEMINI.md", "CLAUDE.md",
}


class Tracer:
    def __init__(self, root, base_arg, base_explicit, ticket, ticket_dir, ticket_rel, strict, code_roots=None):
        self.root = pathlib.Path(root).resolve()
        self.code_roots = [pathlib.Path(p).resolve() for p in code_roots] if code_roots else [self.root]
        self.multi_repo = len(self.code_roots) > 1 or self.code_roots[0] != self.root
        self.repo_map = {cr.name: cr for cr in self.code_roots}
        self.base_arg = base_arg
        self.base_explicit = int(base_explicit)
        self.ticket = ticket
        self.ticket_dir = pathlib.Path(ticket_dir).resolve()
        self.ticket_rel = ticket_rel
        self.strict = int(strict)
        self.pass_cnt = self.fail_cnt = self.warn_cnt = self.unv_cnt = 0
        self.sentinel = False
        self.changed_pairs = set()
        self.repo_bases = []
        self.affected_rows = []
        self.file_cache = {}
        self.tier = ""

    def emit(self, verdict, cat, target, reason=""):
        v = "WARN" if (verdict == "FAIL" and not self.sentinel) else verdict
        if v == "PASS":
            self.pass_cnt += 1
        elif v == "FAIL":
            self.fail_cnt += 1
        elif v == "WARN":
            self.warn_cnt += 1
        else:
            self.unv_cnt += 1
        print(f"{v} {cat} {target}" + (f" -- {reason}" if reason else ""))

    def git_ok(self, *args, repo_dir=None):
        return subprocess.run(["git", "-C", str(repo_dir or self.root), *args], capture_output=True, text=True)

    @staticmethod
    def read_scalar(meta_path, key):
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

    def resolve_tier(self):
        meta_path = self.ticket_dir / "metadata.yaml"
        if not meta_path.is_file():
            sys.exit(f"ERROR: cannot resolve tier -- missing {self.ticket_rel}/metadata.yaml")
        raw_tier = self.read_scalar(meta_path, "tier")
        if raw_tier is None or not raw_tier.strip():
            sys.exit(f"ERROR: cannot resolve tier in {self.ticket_rel}/metadata.yaml")
        self.tier = raw_tier.strip().lower()
        if self.tier not in {"trivial", "low", "medium", "high"}:
            sys.exit(f"ERROR: unrecognized tier {raw_tier!r} in {self.ticket_rel}/metadata.yaml")

    def _disp(self, cr, rel):
        return f"{cr.name}:{rel}" if self.multi_repo else rel

    def _inner_rel(self, disp):
        return disp.split(":", 1)[1] if (self.multi_repo and ":" in disp) else disp

    def _resolve_affected(self, fpath):
        if ":" in fpath:
            pref, rest = fpath.split(":", 1)
            if pref in self.repo_map:
                return self.repo_map[pref], rest.lstrip("./")
        rel = fpath.lstrip("./")
        if len(self.code_roots) == 1:
            return self.code_roots[0], rel
        for cr in self.code_roots:
            if (cr, rel) in self.changed_pairs or (cr / rel).exists():
                return cr, rel
        return self.code_roots[0], rel

    def resolve_base(self, repo_dir):
        if self.base_explicit:
            if self.git_ok("rev-parse", "--verify", "--quiet", f"{self.base_arg}^{{commit}}", repo_dir=repo_dir).returncode != 0:
                sys.exit(f"ERROR: base ref does not resolve in {repo_dir}: {self.base_arg}")
            return self.base_arg
        cands = []
        for sub in ("docs/agentic-sdlc/CADENCE_ORG.md", "CADENCE_ORG.md", "processes/docs/agentic-sdlc/CADENCE_ORG.md"):
            cand = repo_dir / sub
            if cand.is_file() and (m := re.search(r"integration-branch:\s*([^\s>`'\"]+)", cand.read_text(encoding="utf-8", errors="replace"))) and not m.group(1).startswith("<"):
                cands.extend([f"origin/{m.group(1)}", m.group(1)])
                break
        if repo_dir != self.root or not cands:
            r_sym = self.git_ok("symbolic-ref", "--short", "refs/remotes/origin/HEAD", repo_dir=repo_dir)
            if r_sym.returncode == 0 and r_sym.stdout.strip():
                cands.extend([r_sym.stdout.strip(), r_sym.stdout.strip().split("/", 1)[-1]])
            cands.extend(["origin/main", "origin/develop", "main", "develop"])
        return next((r for r in cands + ["HEAD"] if self.git_ok("rev-parse", "--verify", "--quiet", f"{r}^{{commit}}", repo_dir=repo_dir).returncode == 0), None)

    def collect_context(self, spec_path):
        if spec_path.is_file():
            self.affected_rows = self._parse_files_affected(spec_path)
        for cr in self.code_roots:
            base_ref = self.resolve_base(cr)
            self.repo_bases.append((cr, base_ref))
            cr_changed = set()
            if base_ref:
                r = self.git_ok("diff", "--name-only", f"{base_ref}...HEAD", repo_dir=cr)
                if r.returncode == 0:
                    cr_changed.update(p for p in r.stdout.splitlines() if p)
            st = self.git_ok("status", "--porcelain=v1", "-uall", repo_dir=cr)
            if st.returncode == 0:
                for line in st.stdout.splitlines():
                    if len(line) >= 4:
                        cr_changed.add(line[3:].strip().split(" -> ")[-1].strip().strip('"'))
            cr_changed = {p for p in cr_changed if not p.startswith(("specs/", "archive/"))}
            self.changed_pairs.update((cr, p) for p in cr_changed)
            aff_here = {self._resolve_affected(p)[1] for p, _ in self.affected_rows if "{" not in p and "*" not in p and self._resolve_affected(p)[0] == cr}
            rels = {p for p in (cr_changed | aff_here) if (cr / p).is_file() and pathlib.Path(p).suffix.lower() not in BIN_EXTS}
            ls = self.git_ok("ls-files", "-co", "--exclude-standard", repo_dir=cr)
            if ls.returncode == 0:
                rels.update(p for p in ls.stdout.splitlines() if p and not self._skip_default(p) and (cr / p).is_file())
            else:
                for dirpath, dirnames, filenames in os.walk(cr):
                    rel_dir = pathlib.Path(dirpath).resolve().relative_to(cr)
                    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
                    for fn in filenames:
                        p = (rel_dir / fn).as_posix() if rel_dir != pathlib.Path(".") else fn
                        if not self._skip_default(p):
                            rels.add(p)
            for rel in sorted(rels):
                try:
                    self.file_cache[self._disp(cr, rel)] = (cr / rel).read_text(encoding="utf-8", errors="replace").splitlines()
                except OSError:
                    pass

    @staticmethod
    def _skip_default(rel_pos):
        parts = pathlib.PurePosixPath(rel_pos).parts
        if any(part in SKIP_DIRS or part.startswith(".") for part in parts[:-1]):
            return True
        return parts[-1].startswith(".") or rel_pos in DOC_FILES or pathlib.PurePosixPath(rel_pos).suffix.lower() in BIN_EXTS

    def _parse_files_affected(self, spec_path):
        rows, in_fa, rownum, type_idx = [], False, 0, 2
        for raw in spec_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^###\s+Files Affected\b", raw):
                in_fa, rownum, type_idx = True, 0, 2
                continue
            if in_fa and re.match(r"^#", raw):
                in_fa = False
            elif in_fa and raw.lstrip().startswith("|"):
                rownum += 1
                cols = [c.strip() for c in raw.strip().strip("|").split("|")]
                if rownum == 1:
                    for i, h in enumerate(cols):
                        if h.lower() in {"change type", "action", "type"}:
                            type_idx = i
                    continue
                if rownum == 2 or not cols:
                    continue
                fpath = cols[0].strip("` ")
                ftype = cols[type_idx].strip("` ") if len(cols) > type_idx else ""
                if fpath and not fpath.startswith((f"specs/{self.ticket}/", f"archive/{self.ticket}/")):
                    rows.append((fpath, ftype))
        return rows

    def match_c5_tag(self, tag_id):
        t_esc, s_esc = re.escape(self.ticket), re.escape(tag_id)
        pat_l = re.compile(rf"(?<![A-Za-z0-9]){t_esc}(?![A-Za-z0-9]).*(?<![A-Za-z0-9_]){s_esc}(?![0-9A-Za-z_])")
        pat_r = re.compile(rf"(?<![A-Za-z0-9_]){s_esc}(?![0-9A-Za-z_]).*(?<![A-Za-z0-9]){t_esc}(?![A-Za-z0-9])")
        id_pat = None
        tp, ms = re.match(r"^([A-Za-z][A-Za-z0-9]*)-(\d+)$", self.ticket), re.match(r"^(S|OS|AC)-(\d+)(?:\.(\d+))?$", tag_id)
        if tp and ms:
            px, num = re.escape(tp.group(1)), re.escape(tp.group(2))
            kind, maj, minr = ms.group(1), ms.group(2), ms.group(3)
            sep_s = rf"{kind}[_-]?{maj}(?:[_.-]{minr})?" if minr else rf"{kind}[_-]?{maj}"
            id_pat = re.compile(rf"\b(?:def|async|func|fn|it|describe|test|public|void)\b.*{px}[_-]?{num}[A-Za-z0-9_]*{sep_s}(?![0-9])", re.I)
        for rel, lines in self.file_cache.items():
            if self._inner_rel(rel).startswith(("docs/", "specs/", "archive/")):
                continue
            for idx, line in enumerate(lines, 1):
                if pat_l.search(line) or pat_r.search(line) or (id_pat and id_pat.search(line)):
                    return f"{rel}:{idx}"
        return None

    def trace_low(self):
        problem_path = self.ticket_dir / "problem.md"
        if not problem_path.is_file():
            self.emit("FAIL", "problem", "problem.md", f"missing at {self.ticket_rel}/problem.md")
            return
        in_ac = in_fence = False
        ac_ids, real_bullets = [], 0
        placeholder_re = re.compile(r"(first specific, testable behavior|second specific, testable behavior|failure or edge-case behavior|\{[^}]+\}|<placeholder>)", re.I)
        for raw in problem_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^\s*```", raw):
                in_fence = not in_fence; continue
            if in_fence:
                continue
            if re.match(r"^##\s+Acceptance Criteria\b", raw, re.I):
                in_ac = True; continue
            if in_ac and re.match(r"^##\s+", raw):
                break
            if in_ac and re.match(r"^\s*[-*]\s+\[[ xX]\]\s+", raw) and not placeholder_re.search(raw):
                real_bullets += 1
                for m in re.finditer(r"\b(AC-\d+)\b", raw):
                    if m.group(1) not in ac_ids:
                        ac_ids.append(m.group(1))
        if ac_ids:
            for ac in ac_ids:
                hit = self.match_c5_tag(ac)
                self.emit("PASS" if hit else "FAIL", "scenario", ac, hit or f"no C5 test tag matching '{self.ticket} {ac}' outside specs/archive")
        elif real_bullets > 0:
            pat = re.compile(rf"(?<![A-Za-z0-9]){re.escape(self.ticket)}(?![A-Za-z0-9])")
            hit = next((f"{r}:{i}" for r, ls in self.file_cache.items() if not self._inner_rel(r).startswith(("docs/", "specs/", "archive/")) for i, ln in enumerate(ls, 1) if pat.search(ln)), None)
            self.emit("PASS" if hit else "FAIL", "scenario", f"{self.ticket}-ACs", hit or f"no test tag citing '{self.ticket}' for {real_bullets} Low-tier AC(s)")
        else:
            self.emit("FAIL", "problem-ac", "Acceptance Criteria", "no concrete acceptance criteria in problem.md")

    def trace_medium_high(self, spec_path):
        decisions_path = self.ticket_dir / "decisions.md"
        if not spec_path.is_file():
            dtxt = decisions_path.read_text(encoding="utf-8", errors="replace") if decisions_path.is_file() else ""
            if re.search(r"escalat", dtxt, re.I) and re.search(r"\bDEC-\d+\b", dtxt):
                self.emit("PASS", "contract", "escalation", "qualified mid-flight escalation in decisions.md")
                self.trace_low()
            else:
                self.emit("FAIL", "contract", "spec.md", f"missing spec.md at {self.ticket_rel}/spec.md")
            return

        for fpath, ftype in self.affected_rows:
            if "{" in fpath or "*" in fpath:
                self.emit("UNVERIFIABLE", "files-affected", f"{ftype} {fpath}")
                continue
            cr, rel = self._resolve_affected(fpath)
            exists = (cr / rel).exists()
            if ftype == "Add":
                self.emit("PASS" if exists else "FAIL", "files-affected", f"Add {fpath}", "" if exists else "target file missing on disk")
            elif ftype == "Delete":
                self.emit("PASS" if not exists else "FAIL", "files-affected", f"Delete {fpath}", "" if not exists else "deleted target still exists on disk")
            elif ftype == "Modify":
                if not exists:
                    self.emit("FAIL", "files-affected", f"Modify {fpath}", "target missing on disk")
                elif not self.changed_pairs or (cr, rel) in self.changed_pairs:
                    self.emit("PASS", "files-affected", f"Modify {fpath}")
                else:
                    self.emit("WARN", "files-affected", f"Modify {fpath}", "untouched relative to resolved base")

        test_plan_path = self.ticket_dir / "test-plan.md"
        if not test_plan_path.is_file():
            self.emit("FAIL", "test-plan", "test-plan.md", f"missing at {self.tier} tier")
            return

        scenarios, raw_headers, ac_map = self._parse_test_plan(test_plan_path)
        traced_ok = set()
        if scenarios:
            for sid in scenarios:
                hit = self.match_c5_tag(sid)
                self.emit("PASS" if hit else "FAIL", "scenario", sid, hit or f"no C5 test tag matching '{self.ticket} {sid}' outside specs/archive")
                if hit:
                    traced_ok.add(sid)
        elif raw_headers > 0:
            self.emit("WARN", "test-plan", "scenarios", f"{raw_headers} scenario(s) lack S-N.M / OS-N.M IDs")
        else:
            self.emit("FAIL", "test-plan", "scenarios", "no scenarios defined in test-plan.md")

        spec_lines = spec_path.read_text(encoding="utf-8", errors="replace").splitlines()
        self._trace_seams(spec_lines)
        self._trace_chord_coverage(spec_lines, scenarios, ac_map, traced_ok)

    @staticmethod
    def _parse_test_plan(test_plan_path):
        scenarios, raw_headers, in_cov, ac_map = [], 0, False, {}
        for raw in test_plan_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.match(r"^##\s+Acceptance Criteria Coverage\b", raw, re.I):
                in_cov = True; continue
            if in_cov and re.match(r"^##\s+", raw):
                in_cov = False
            if "{" in raw or "}" in raw:
                continue
            ms = re.match(r"^\s*Scenario(?:\s+Outline)?:\s*((?:S|OS)-\d+\.\d+)\b", raw)
            if ms and ms.group(1) not in scenarios:
                scenarios.append(ms.group(1))
            elif not ms and re.match(r"^\s*Scenario(?:\s+Outline)?:", raw):
                raw_headers += 1
            if in_cov and raw.lstrip().startswith("|"):
                m_ac = re.search(r"\b(AC-\d+)\b", raw)
                sids = re.findall(r"\b((?:S|OS)-\d+\.\d+)\b", raw)
                for s in sids:
                    if s not in scenarios:
                        scenarios.append(s)
                if m_ac and sids:
                    ac_map.setdefault(m_ac.group(1), []).extend(sids)
        return scenarios, raw_headers, ac_map

    def _trace_seams(self, spec_lines):
        in_seams = skip_sub = False
        active_seams = []
        dormant_re = re.compile(r"\b(not triggered|dormant|no observability seams|no seams)\b", re.I)
        for raw in spec_lines:
            if re.match(r"^##\s+Observability Seams\b", raw, re.I):
                in_seams, skip_sub = True, False; continue
            if in_seams and re.match(r"^##\s+", raw):
                in_seams = False
            if not in_seams:
                continue
            if re.match(r"^###\s+(Prior Production Findings|Baseline Definitions)\b", raw, re.I):
                skip_sub = True; continue
            if re.match(r"^###\s+", raw):
                skip_sub = False; continue
            if skip_sub or "{" in raw or re.match(r"^\s*\|[-\s|:]+\|\s*$", raw) or re.match(r"^\s*\|\s*AC\s*\|", raw, re.I):
                continue
            if dormant_re.search(raw) or re.fullmatch(r"[-*:\s`*]*(none|n/a)[.*\s]*", raw, re.I):
                continue
            for seam in SEAMS:
                if re.search(rf"\b{seam}\b", raw) and seam not in active_seams:
                    active_seams.append(seam)
        aff_set = {self._disp(*self._resolve_affected(p)) for p, _ in self.affected_rows if "{" not in p and "*" not in p}
        for seam in active_seams:
            pat_s = re.compile(rf"\b{seam}\b")
            hit = next((f"{r}:{i}" for r, ls in self.file_cache.items() if not (self._inner_rel(r).endswith(".md") and r not in aff_set) for i, ln in enumerate(ls, 1) if pat_s.search(ln)), None)
            self.emit("PASS" if hit else "FAIL", "seam", seam, hit or "declared in spec.md ## Observability Seams but not found in code/tests")

    def _trace_chord_coverage(self, spec_lines, scenarios, ac_map, traced_ok):
        in_chord, chord_acs = False, []
        for raw in spec_lines:
            if re.match(r"^##\s+CHORD\b", raw, re.I):
                in_chord = True; continue
            if in_chord and re.match(r"^##\s+", raw) and not re.match(r"^##\s+CHORD", raw, re.I):
                in_chord = False
            if in_chord and (m := re.match(r"^####\s+(AC-\d+)\b", raw)) and m.group(1) not in chord_acs:
                chord_acs.append(m.group(1))
        for ac in chord_acs:
            mapped = list(dict.fromkeys(ac_map.get(ac, []))) or [s for s in scenarios if re.match(rf"^(?:S|OS)-{re.escape(ac.split('-', 1)[1])}\.", s)]
            missing = [s for s in mapped if s not in traced_ok]
            if mapped and not missing:
                self.emit("PASS", "ac-coverage", ac, ", ".join(mapped))
            elif scenarios:
                self.emit("FAIL", "ac-coverage", ac, f"missing traced scenario(s): {', '.join(missing) or 'none mapped'}")

    def run(self):
        self.resolve_tier()
        if self.tier == "trivial":
            print(f"PASS trace exempt (tier=trivial) {self.ticket}")
            print("SUMMARY pass=1 fail=0 warn=0 unverifiable=0")
            return 0
        spec_path = self.ticket_dir / "spec.md"
        self.sentinel = bool(self.strict or self.tier == "low" or self.ticket_rel.startswith("specs/"))
        if not self.sentinel and spec_path.is_file():
            self.sentinel = "**Gate 1 rulings:** required" in spec_path.read_text(encoding="utf-8", errors="replace")
        self.collect_context(spec_path)
        if self.tier == "low":
            self.trace_low()
        else:
            self.trace_medium_high(spec_path)
        for cr, base_ref in self.repo_bases:
            chunks = [self.git_ok("diff", "-U2", *args, repo_dir=cr).stdout for args in (([f"{base_ref}...HEAD"],) if base_ref else ()) + (["--cached"], [])]
            for fl in analyze_test_diff("\n".join(c for c in chunks if c)):
                self.emit("WARN", "test-hygiene", cr.name if self.multi_repo else "diff", fl)
        print(f"SUMMARY pass={self.pass_cnt} fail={self.fail_cnt} warn={self.warn_cnt} unverifiable={self.unv_cnt}")
        return 1 if self.fail_cnt > 0 else 0


if __name__ == "__main__":
    if len(sys.argv) < 8:
        sys.exit("Usage: verify_trace.py ROOT BASE BASE_EXPLICIT TICKET TICKET_DIR TICKET_REL STRICT [CODE_ROOT ...]")
    sys.exit(Tracer(*sys.argv[1:8], code_roots=sys.argv[8:]).run())
