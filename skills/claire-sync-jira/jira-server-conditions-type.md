# `/claire-sync-jira` — reported conditions: the untyped ticket

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-173).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-conditions.md` — every script writes its result to **stdout**
as `key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines.
Nothing here is a second implementation; each condition below is emitted by the named script.

**This file is a fourth part of one catalogue, not a fourth catalogue.** BTG-173 split it off with 7
lines of headroom left in the primary. The record is **split, never truncated** — the same
facet-conflict resolution BTG-102 and BTG-105 each applied (C-3: Operability outranks DX on *content*;
DX is served by the placement instead).

---

## The untyped ticket (`jira-type-lib.sh` + `jira-reserve.sh` — BTG-173)

**An untyped ticket is a sanctioned state, not an error.** `/claire-triage --file-only` files a ticket
*without* classifying it — `/claire-triage` F3 writes `tier: ""` and **no `type:`**, because filing is
explicitly not the triage stage — and F5 then requires that ticket to be **projected** to the bound
tracker. On a Jira Server binding those two requirements used to be mutually unsatisfiable: the
projection resolved `.type` through `issue_type_map`, found no `""` key, and **HALTed** `4` at step 4 of
9, so the description was never applied and steps 5–9 (transition, worklog, assign, link, epic) never
ran. It reproduced identically on 4 of 4 tickets in the session that found it.

The two halves of the adapter now state **one doctrine**: *an untyped ticket receives a **declared
placeholder** type at create, and is **never re-typed** by an update until classification assigns a real
one.* Neither half acts silently — that is what each condition below is for.

The rule that did **not** change: *a guessed issue type is an ungoverned decision.* Declining to assert
a type the repo does not hold is not guessing it. The exception is narrowed to the one state that cannot
be a mistake, and both narrowings are load-bearing:

- **Emptiness, never lookup failure.** A **non-empty** type the map cannot resolve still HALTs with
  `syncjs.config.marker_unresolved` and exit **4**. A genuine configuration gap is never swallowed
  under this path.
- **Update, never create.** `--mode create` with an empty type still HALTs. A create must carry a type
  — Jira requires an `issuetype` on create — and there is no live value to leave alone. The asymmetry is
  deliberate, not an oversight.

- **`syncjs.write.type_unasserted`** (Warning, `jira-type-lib.sh` via `jira-write-issue.sh`) — the
  ticket's `type:` is absent, empty or whitespace-only **and** the mode is `update`. The `fields` object
  is sent with **no `issuetype` member**, so the issue keeps the type it already has; **every other
  field still projects** (summary, description, labels, priority, timetracking) and the run exits **0**.
  The decision reaches **both** channels: this line on stderr and `issuetype_projected=no` on stdout, so
  it is auditable from the transcript. The BTG-102 re-type guard is **bypassed**, not merely skipped —
  left running against an empty target it would ask the edit screen about the type `""`, be refused, and
  instruct the operator to perform a Jira **Move to a type that does not exist**. **Operator action:
  none is owed.** Run `/claire-triage` on the id; classification writes a real `type:` and the next sync
  projects it. Not to be confused with **`syncjs.write.issuetype_move_required`**, whose cause is the
  opposite: there the repo *does* assert a type and the instance refused it, so a human Move is owed.
- **`syncjs.reserve.type_placeholder`** (Info, `jira-reserve.sh`) — no `--type` was supplied, so the
  reservation was created at the **declared placeholder** type `tech-debt` (which `issue_type_map`
  renders as this instance's configured value) rather than at a type the repo chose. Jira requires an
  `issuetype` on create, so *some* placeholder is unavoidable; the fix is to **declare** it, not to
  eliminate it. It is a create-time necessity and **never a classification** — the repo continues to
  assert no type until `/claire-triage` on the id assigns one, and this write is the **only** one that will set
  a type until then. **Expect it on every reservation — not only on a `--file-only` filing.** `--type`
  is a supported flag and an explicitly typed reservation declares no placeholder, but **no caller in
  this framework passes it today**: `/claire-triage`'s F2 allocates the id *before* the triage-agent
  classifies, so on every origination path the type is simply not known yet at reserve time. So read
  this line as *"the reservation took the placeholder"* and nothing more. It is **not** a regression
  signal, and its absence means only that whoever invoked `jira-reserve.sh` supplied `--type` directly.
  It reports what has always happened, so no behaviour changed on this path — only its visibility.
