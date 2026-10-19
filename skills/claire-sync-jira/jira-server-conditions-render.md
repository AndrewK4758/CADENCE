# `/claire-sync-jira` — reported conditions: deterministic markup rendering

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-205).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-conditions.md` — every script writes its result to
**stdout** and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines. Nothing here
is a second implementation; each condition below is emitted by the named script, and this file is the
operator-facing catalogue of what each one means.

**Every name in this file is verified against the emitting line in the script.** A condition that is
documented but never emitted, or emitted but described as something else, is the defect class BTG-075's
re-reviews kept finding.

**This file is a further part of one catalogue, not another catalogue.** BTG-205 split it off because
`jira-server-conditions.md` stood at **398** lines against a `-lt 400` ceiling — one line of headroom —
so the new conditions had nowhere to land in place. **Split, never truncated**, exactly as BTG-102,
BTG-105, BTG-168 and BTG-173 did before it. The contracts of the emitting scripts are in
`.claude/skills/claire-sync-jira/jira-server-scripts-render.md`.

---

## Markup conversion — `jira-md2wiki.sh`

### `syncjs.render.md2wiki_failed` (Critical)

A conversion pass could not complete over its input — an unterminated fenced code block being the case
that actually occurs. The filter exits `1`.

**What makes this a seam rather than an error message: stdout is left EMPTY.** A half-converted
fragment is the single most dangerous output this script could produce, because it looks like a render.
It would be substituted into the template, sent, and accepted with a 2xx, and the defect would be
visible only to a human reading the issue. So the whole conversion is buffered and printed only on
success, and the caller sees nothing to project.

**Operator action:** the fragment is malformed at its source. Fix the `problem.md` section — most often
a fence opened and never closed — and re-run. Do not "recover" by projecting the partial render.

---

## The wholesale-overwrite hazard — `jira-desc-lib.sh`

**Read this before reading either condition below.** On the update path the sync replaces
`description` **wholesale**. That is not merely an update, it is a destructive one: when the fresh
render is worse than what is already live, projecting it replaces better content with worse —
successfully, with a 2xx, and with nothing in the transcript to say so. It was reported from the field
on a re-sync whose source `problem.md` had **not changed**, where a fresh render still differed from
the live value in four ways, each a regression.

**"Do not project the description" is not an available mitigation, and must not become one.** On the
update path a missing `--description-file` halts with `syncjs.description.update_reproject_absent`
(BTG-062), because dropping the field from the update object would silently strand a repo-side edit.
That halt is correct and stays.

**What actually removes the hazard is determinism, not the report.** `jira-md2wiki.sh` is a total
function of its input, so a re-render of an unchanged source is byte-identical and nothing below fires.
The two conditions exist for the cases determinism cannot cover: a description written by some other
converter, or edited by hand in the Jira UI.

**Operator workaround, for an issue whose live description is known to be better than what this
projection would produce:** re-project the live value byte-for-byte — read it back over REST, write it
into the rendered temp file unchanged, and let the sync send it. That satisfies the BTG-062 halt (a
description IS sent) while changing nothing, and it buys time to fix the source artifact rather than
the symptom.

### `syncjs.description.reprojection_delta` (Warning)

The fresh render differs from the issue's live `description`. Names the ticket, the issue key, and how
many lines differ **in each direction** — "they differ" would not tell an operator whether the
projection is adding detail or destroying it. The description **content** is deliberately not logged.

**Non-blocking: the `PUT` proceeds and replaces the live value.** Blocking was considered and rejected
(BTG-205 DEC-005) — it would halt every legitimate description update, and would turn the first
post-upgrade sync of every pre-existing issue into a halt, which is a breaking change to a Stable
surface. What changes is that the overwrite can no longer happen invisibly.

**Expect a burst of these exactly once.** The first sync after adopting the deterministic filter
re-renders every description, so any issue whose live value came from a different converter reports a
delta on that run and never again. That is a one-time, improving transition, not a fault.

**Operator action:** if the source artifacts did not change, read the rendered output before accepting
it. If they did, this is the projection working.

### `syncjs.description.live_read_unavailable` (Warning)

The live `description` could not be read — the instance was unreachable, the read returned a non-2xx,
or the body could not be parsed — so **no comparison was made**. Reported by its own name and never
conflated with "no delta": an unreadable value and an identical one are different facts, and collapsing
them is how a projection gap becomes invisible (the PROD_CLAIRE-006 lesson, one field over).

**The write is unaffected.** The `PUT` body is byte-identical to the body that would have been sent had
the read succeeded; the only thing lost is the operator's chance to see the delta.

**Operator action:** none required. If it repeats, the account may lack browse permission on the issue,
which is worth knowing for its own sake.
