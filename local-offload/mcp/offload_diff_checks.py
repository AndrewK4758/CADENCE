"""Deterministic test-diff anti-tautology heuristics (MOCK_ONLY_ASSERTION & SELF_MOCKED_SUT).

SHARED TWIN MODULE -- kept byte-identical at:
  - local-offload/mcp/offload_diff_checks.py
  - skills/cadence-spec/trace_diff_hygiene.py
Pure Python stdlib only so both the local-offload MCP server and offline
adopter `verify-facts.sh --trace` checks share one zero-dependency analyzer.
"""

from __future__ import annotations

import pathlib
import re

TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs_tests"}
DOC_EXTS = {".md", ".txt", ".rst", ".json", ".yaml", ".yml", ".toml", ".lock"}
GENERIC_SYMS = {
    "main", "init", "__init__", "setup", "teardown", "handle", "render",
    "create", "update", "delete", "build", "parse", "format", "helper", "run",
}

PROD_SYM_RES = (
    re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]{3,})\s*\("),
    re.compile(r"^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]{3,})\s*\("),
    re.compile(r"^\s*(?:export\s+)?(?:abstract\s+|sealed\s+|data\s+)?class\s+([A-Za-z_][A-Za-z0-9_]{3,})\b"),
    re.compile(r"^\s*(?:export\s+)?const\s+([A-Za-z_][A-Za-z0-9_]{3,})\s*=\s*(?:async\s*)?\("),
    re.compile(r"^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:async\s+)?(?:class|record|struct|interface)\s+([A-Za-z_][A-Za-z0-9_]{3,})\b"),
    re.compile(r"^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:async\s+)?[A-Za-z0-9_<>,?.\[\]]+\s+([A-Za-z_][A-Za-z0-9_]{3,})\s*\("),
    re.compile(r"^\s*(?:pub\s+(?:async\s+)?)?(?:fn|fun|func)\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]{3,})\s*\("),
)
HUNK_SYM_RE = re.compile(r"@@[^@]+@@\s*(?:async\s+)?(?:def|class|function|func|fn|fun|public|private|internal)\s+(?:[A-Za-z0-9_<>,?.\[\]]+\s+)*([A-Za-z_][A-Za-z0-9_]{3,})\b")

TEST_HEADER_RES = (
    re.compile(r"^\s*(?:async\s+)?def\s+(test_[A-Za-z0-9_]+)\s*\("),
    re.compile(r"^\s*(?:it|test)\s*\(\s*[\"'`]([^\"'`]+)[\"'`]"),
    re.compile(r"^\s*func\s+(Test[A-Za-z0-9_]+)\s*\("),
    re.compile(r"^\s*(?:public|private|internal)?\s*(?:async\s+)?(?:Task|void)\s+([A-Za-z0-9_]+)\s*\("),
)
MOCK_PATCH_RE = re.compile(
    r"(?:\bpatch(?:\.object)?\s*\(|\bmonkeypatch\.setattr\s*\(|\b(?:vi|jest)\.(?:spyOn|mock)\s*\(|\bsinon\.stub\s*\("
    r"|\bnew\s+Mock\s*<|\bSubstitute\.For\s*<|\bMagicMock\s*\(\s*spec\s*=|\bcreate_autospec\s*\()"
)
MOCK_ASSERT_RE = re.compile(
    r"(?:\.assert_(?:called|called_once|called_with|called_once_with|any_call|not_called|awaited|awaited_once|awaited_with|awaited_once_with)\s*\("
    r"|\.toHaveBeenCalled(?:With|Times|LastCalledWith)?\s*\("
    r"|\.Verify\s*\(|\bTimes\.(?:Once|Exactly|AtLeast|AtMost|Never)\b"
    r"|\bverify\s*\([^)]*\)\.)"
)
STATE_ASSERT_RE = re.compile(
    r"(?:^\s*assert\b(?!.*\bassert_(?:called|awaited))|\bassert(?:Equal|NotEqual|True|False|In|NotIn|Is|IsNot|Raises|AlmostEqual|Greater|Less|DictEqual|ListEqual)\s*\("
    r"|\bpytest\.raises\s*\("
    r"|\bexpect\s*\(.*?\)\.(?:not\.)?(?:toBe|toEqual|toStrictEqual|toMatch|toContain|toThrow|toHaveLength|toHaveProperty|toBeTruthy|toBeFalsy|toBeNull|toBeUndefined|toBeDefined|toBeGreaterThan|toBeLessThan|rejects|resolves)\b"
    r"|\bAssert\.(?:Equal|NotEqual|True|False|Null|NotNull|Single|Empty|NotEmpty|Contains|Throws|ThrowsAsync|Same|IsType)\b"
    r"|\.Should\s*\(\s*\)\.(?:Be|NotBe|Contain|HaveCount|Throw|BeEquivalentTo)\b"
    r"|\b(?:assert|require)\.(?:Equal|NotEqual|NoError|Error|True|False|Len|Contains|Nil|NotNil)\s*\("
    r"|\bt\.(?:Error|Errorf|Fatal|Fatalf)\s*\()"
)


def is_test_path(rel: str) -> bool:
    p = pathlib.PurePosixPath(rel)
    if any(part.lower() in TEST_DIRS for part in p.parts[:-1]):
        return True
    name = p.name.lower()
    return (
        name.startswith("test_")
        or "_test." in name
        or ".test." in name
        or ".spec." in name
        or name.endswith(("tests.cs", "test.cs", "test.java", "tests.java", "test.kt"))
    )


def _extract_test_blocks(added_lines: list[str]) -> list[tuple[str, list[str]]]:
    blocks: list[tuple[str, list[str]]] = []
    cur_name, cur_body = "", []
    for line in added_lines:
        matched_name = ""
        for pat in TEST_HEADER_RES:
            m = pat.match(line)
            if m:
                matched_name = m.group(1).strip()
                break
        if matched_name:
            if cur_name and cur_body:
                blocks.append((cur_name, cur_body))
            cur_name, cur_body = matched_name, []
        elif cur_name:
            cur_body.append(line)
    if cur_name and cur_body:
        blocks.append((cur_name, cur_body))
    return blocks


def analyze_test_diff(diff_text: str, max_flags: int = 8) -> list[str]:
    """Return deterministic anti-tautology flags for unified git diff text."""
    if not diff_text:
        return []
    sections = [s for s in re.split(r"(?=^diff --git )", diff_text, flags=re.MULTILINE) if s.strip()]
    prod_syms: set[str] = set()
    test_added: list[tuple[str, list[str]]] = []

    for sec in sections:
        m_hdr = re.match(r"^diff --git a/(.+?) b/(.+)$", sec.splitlines()[0])
        if not m_hdr:
            continue
        rel = m_hdr.group(2).strip()
        ext = pathlib.PurePosixPath(rel).suffix.lower()
        if ext in DOC_EXTS:
            continue
        lines = sec.splitlines()
        if is_test_path(rel):
            added = [ln[1:] for ln in lines if ln.startswith("+") and not ln.startswith("+++")]
            if added:
                test_added.append((rel, added))
        else:
            for ln in lines:
                if ln.startswith("@@"):
                    mh = HUNK_SYM_RE.search(ln)
                    if mh and mh.group(1).lower() not in GENERIC_SYMS:
                        prod_syms.add(mh.group(1))
                elif ln and ln[0] in {" ", "+", "-"} and not ln.startswith(("+++", "---")):
                    body = ln[1:]
                    for pat in PROD_SYM_RES:
                        ms = pat.match(body)
                        if ms and ms.group(1).lower() not in GENERIC_SYMS:
                            prod_syms.add(ms.group(1))
                            break

    flags: list[str] = []
    seen: set[str] = set()

    def _add(msg: str) -> None:
        if msg not in seen and len(flags) < max_flags:
            seen.add(msg)
            flags.append(msg)

    sym_res = [(sym, re.compile(rf"(?<![A-Za-z0-9_]){re.escape(sym)}(?![A-Za-z0-9_])")) for sym in sorted(prod_syms)]

    for rel, added in test_added:
        for line in added:
            if MOCK_PATCH_RE.search(line):
                for sym, s_re in sym_res:
                    if s_re.search(line):
                        _add(f"SELF_MOCKED_SUT: {rel} mocks/patches modified production symbol '{sym}'")
        for tname, body in _extract_test_blocks(added):
            has_mock = any(MOCK_ASSERT_RE.search(ln) for ln in body)
            has_state = any(STATE_ASSERT_RE.search(ln) for ln in body if not MOCK_ASSERT_RE.search(ln))
            if has_mock and not has_state:
                _add(f"MOCK_ONLY_ASSERTION: {rel} ({tname}) -- asserts mock calls without verifying return/state invariant")

    return flags
