#!/usr/bin/env python3
"""Resolve a CLAIRE ticket's machine-readable state in one shot.

SHARED FILE -- byte-identical copies of this script live in the scripts/ dir of
every claire-* skill that reads ticket state. They are copies rather than one
shared import because the skills are distributed separately and each has to
stand alone.

Keeping them identical is deliberate and cheap to enforce: this file contains NO
per-skill text. The skill's own name is derived at runtime from the path it sits
in (SKILL_NAME below), so the halt prefix and the not-a-CLAIRE-repo message
come out right in every copy without any copy differing. That turns "have these
drifted?" into a checksum comparison rather than a careful diff:

    md5sum ~/.claude/skills/claire-*/scripts/read_state.py \
      | awk '{print $1}' | sort -u | wc -l     # must print 1

Fix any copy, then propagate it to the others verbatim. Do not hand-edit one.

What must NEVER be renamed to match a skill: the cycle-ledger marker below reads
`claire-run:cycle` in every copy. It is the SHARED marker name each skill
writes and reads, which is what lets a ticket started by one be continued by
another. The implement-phase skill caps its review cycles on those counts, so
a renamed
marker would read every ticket as zero completed cycles and restart a capped
review at one.

The calling skill re-reads ticket state on every loop iteration. Doing that by hand
costs a Read of metadata.yaml plus a grep of CLAIRE_ORG.md plus a scan of
submission.md each time, and invites three separate chances to misread a field.
This prints the whole state block instead.

Why not yaml.safe_load: agents that write metadata.yaml wrap long scalars across
lines, which is valid YAML but has repeatedly produced values that read fine to a
human and wrong to a naive parser. The scalar reader below joins continuation
lines explicitly and refuses to guess.

Every failure here exits non-zero with a named cause. A missing binding, a
missing ticket, or an unreadable status is a halt condition for the caller --
never a default to fall back on.

Usage:  read_state.py <ticket-id> [--repo-root DIR]
Exit:   0 state printed | 2 halt (cause on stderr)
"""

import argparse
import os
import re
import sys

FIELDS = (
    "status",
    "tier",
    "spec_mr",
    "merge_request",
    "branch",
    # Distinguishes "the human approved the spec content" from "the spec MR
    # landed". `status` only tracks the latter, so without this a run that died
    # between the two re-asks the open questions and can fork the spec from the
    # decision already recorded in it.
    "spec_approved_at",
    # Not dispatched on, but load-bearing for the progress guard: /claire-maintain
    # advances a ticket by setting this and nothing else -- status stays
    # `in-review`. Omitting it made a successful /claire-maintain indistinguishable
    # from a no-op, so the guard fired and the run halted before monitoring.
    "maintainer_approved_at",
)

# Fields whose change means "the run advanced". Emitted pre-assembled as
# guard_tuple= so the caller compares one string instead of rebuilding a tuple
# from memory each iteration and forgetting a member.
GUARD_FIELDS = (
    "location",
    "status",
    "spec_mr",
    "merge_request",
    "maintainer_approved_at",
    "ledger_cycles_completed",
)
STAGES = ("triage", "spec", "implementation", "code-review", "maintainer", "archive")

ORG_REL = os.path.join("docs", "agentic-sdlc", "CLAIRE_ORG.md")

# The cycle ledger /claire-run appends to submission.md. Kept as an HTML
# comment so it is invisible in rendered markdown, greppable, and consistent
# with how CLAIRE_ORG.md carries its own machine-readable bindings.
LEDGER_RE = re.compile(
    r"<!--\s*claire-run:cycle\s+n=(?P<n>\d+)\s+phase=(?P<phase>[a-z-]+)\s+"
    r"blocking=(?P<blocking>\d+)\s+nonblocking=(?P<nonblocking>\d+)"
)

SCALAR_RE = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_]*):(?P<rest>.*)$")


# The skill this copy belongs to: <skill-dir>/scripts/read_state.py -> <skill-dir>.
# Derived rather than hardcoded so every copy can stay byte-identical; see the
# module docstring. Falls back to a generic name if the layout is ever different,
# because a slightly wrong prefix is not worth crashing a state read over.
SKILL_NAME = os.path.basename(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
) or "claire"


def halt(cause, message):
    sys.stderr.write("%s.halt %s: %s\n" % (SKILL_NAME, cause, message))
    raise SystemExit(2)


def find_repo_root(start):
    """Walk up until CLAIRE_ORG.md appears. Its absence is the skill's abort."""
    cur = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(cur, ORG_REL)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            halt(
                "not_a_claire_repo",
                "%s not found in %s or any parent -- /%s only runs in a "
                "CLAIRE repo" % (ORG_REL, os.path.abspath(start), SKILL_NAME),
            )
        cur = parent


def resolve_binding(repo_root, field):
    """Read a §15 Branch-Strategy Binding marker.

    ADR-0020 makes these markers the machine-readable source; a hardcoded branch
    name is exactly what it forbids. Absent/empty/placeholder fails loud.
    """
    path = os.path.join(repo_root, ORG_REL)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r"<!--\s*%s:\s*(?P<v>[^>]*?)\s*-->" % re.escape(field), text)
    if not m:
        halt("binding_absent", "no <!-- %s: ... --> marker in %s" % (field, ORG_REL))
    value = m.group("v").strip()
    # `<...>` is the un-substituted-placeholder form. Braces are NOT: the
    # branch-naming-convention's legitimate value is a pattern like
    # {phase}/{type}/{id}, so rejecting `{` would fail every healthy repo.
    if not value or value.startswith("<"):
        halt(
            "binding_unset",
            "%s in %s is empty or an un-substituted placeholder (%r)"
            % (field, ORG_REL, value),
        )
    return value


def strip_comment(raw):
    """Drop a trailing # comment that is not inside quotes."""
    out, quote = [], None
    for ch in raw:
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out).strip()


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def read_scalars(path, keys):
    """Read top-level scalars, joining wrapped continuation lines."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    found = {}
    i = 0
    while i < len(lines):
        m = SCALAR_RE.match(lines[i])
        if not m or m.group("key") not in keys:
            i += 1
            continue
        rest = strip_comment(m.group("rest"))
        # A value that opens a quote without closing it continues on the
        # following indented lines -- the wrapped-scalar case that breaks
        # line-at-a-time readers.
        if rest[:1] in ("\"", "'") and not (len(rest) > 1 and rest[-1] == rest[0]):
            quote, j = rest[0], i + 1
            while j < len(lines) and not rest.endswith(quote):
                rest = rest + " " + strip_comment(lines[j].strip())
                j += 1
            i = j
        else:
            i += 1
        found[m.group("key")] = unquote(rest).strip()
    return found


def count_stages(path):
    """Count stage_effort entries per stage.

    Advisory only. Effort recording is known to be skipped, so a zero here means
    'not recorded', never 'did not happen' -- the caller must not treat this as
    the cycle count.
    """
    counts = dict.fromkeys(STAGES, 0)
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^\s*-\s+stage:\s*(?P<s>[a-z-]+)", line)
            if m and m.group("s") in counts:
                counts[m.group("s")] += 1
    return counts


def read_ledger(spec_dir):
    """Parse /claire-run's own cycle markers from submission.md."""
    path = os.path.join(spec_dir, "submission.md")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    return [
        {
            "n": int(m.group("n")),
            "phase": m.group("phase"),
            "blocking": int(m.group("blocking")),
            "nonblocking": int(m.group("nonblocking")),
        }
        for m in LEDGER_RE.finditer(text)
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ticket_id")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()

    root = find_repo_root(args.repo_root)
    tid = args.ticket_id

    spec_dir = os.path.join(root, "specs", tid)
    location = "specs"
    if not os.path.isdir(spec_dir):
        alt = os.path.join(root, "archive", tid)
        if os.path.isdir(alt):
            spec_dir, location = alt, "archive"
        else:
            # Before declaring tracker-first, rule out a casing mismatch.
            # `acme-101` and `ACME-101` are the same ticket to a human, but a
            # case-sensitive miss would report location=absent -- which now
            # routes to /claire-triage and would RE-TRIAGE an already-triaged ticket,
            # clobbering its classification. Only a ticket absent under every
            # casing is genuinely tracker-first. The corrected id is reported,
            # not silently substituted.
            match = None
            for where in ("specs", "archive"):
                base = os.path.join(root, where)
                if not os.path.isdir(base):
                    continue
                for entry in sorted(os.listdir(base)):
                    if entry.lower() == tid.lower() and os.path.isdir(
                        os.path.join(base, entry)
                    ):
                        match = (os.path.join(base, entry), where, entry)
                        break
                if match:
                    break
            if match:
                halt(
                    "ticket_id_case_mismatch",
                    "no %s/%s, but %s/%s exists -- ids are case-sensitive here. "
                    "Re-run with the exact id %s. (Proceeding would look like the "
                    "tracker-first case and re-triage a ticket that already exists.)"
                    % (match[1], tid, match[1], match[2], match[2]),
                )
            # No local artifacts is NOT a failure -- it is the tracker-first
            # case, where the issue was filed in the bound tracker and /claire-triage
            # has yet to create the stub. Report it as a state and exit 0 so the
            # caller can route to /claire-triage; halting here would refuse the normal
            # starting point for tracker-originated work.
            print(
                "\n".join(
                    [
                        "repo_root=%s" % root,
                        "ticket_id=%s" % tid,
                        "spec_dir=",
                        "location=absent",
                        "integration_branch=%s" % resolve_binding(root, "integration-branch"),
                        "branch_naming_convention=%s"
                        % resolve_binding(root, "branch-naming-convention"),
                        "status=absent",
                        "guard_tuple=%s"
                        % "|".join("%s=" % f for f in GUARD_FIELDS).replace(
                            "location=", "location=absent"
                        ),
                        "next_action=tracker-first: no local artifacts; hand this id to /claire-triage",
                    ]
                )
            )
            return

    meta = os.path.join(spec_dir, "metadata.yaml")
    if not os.path.isfile(meta):
        halt("metadata_absent", "%s has no metadata.yaml" % spec_dir)

    scalars = read_scalars(meta, set(FIELDS))
    if not scalars.get("status"):
        halt("status_unreadable", "could not resolve a status: value from %s" % meta)

    out = [
        "repo_root=%s" % root,
        "ticket_id=%s" % tid,
        "spec_dir=%s" % os.path.relpath(spec_dir, root),
        "location=%s" % location,
        "integration_branch=%s" % resolve_binding(root, "integration-branch"),
        "branch_naming_convention=%s" % resolve_binding(root, "branch-naming-convention"),
    ]
    for f in FIELDS:
        out.append("%s=%s" % (f, scalars.get(f, "")))

    counts = count_stages(meta)
    out.append(
        "stage_effort_counts=%s"
        % ",".join("%s:%d" % (s, counts[s]) for s in STAGES)
    )

    ledger = read_ledger(spec_dir)
    cycles_completed = len({e["n"] for e in ledger})
    out.append("ledger_entries=%d" % len(ledger))
    out.append("ledger_cycles_completed=%d" % cycles_completed)
    if ledger:
        last = sorted(ledger, key=lambda e: e["n"])[-1]
        out.append(
            "ledger_last=n=%d,phase=%s,blocking=%d,nonblocking=%d"
            % (last["n"], last["phase"], last["blocking"], last["nonblocking"])
        )
    else:
        out.append("ledger_last=")

    guard_values = {
        "location": location,
        "ledger_cycles_completed": str(cycles_completed),
    }
    out.append(
        "guard_tuple=%s"
        % "|".join(
            "%s=%s" % (f, guard_values.get(f, scalars.get(f, "")))
            for f in GUARD_FIELDS
        )
    )

    print("\n".join(out))


if __name__ == "__main__":
    main()
