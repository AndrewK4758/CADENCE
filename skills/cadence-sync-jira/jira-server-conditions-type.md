# `/cadence-sync-jira` — reported conditions: the untyped ticket

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-173).
Boundary invariant: matches its sibling
`.agents/skills/cadence-sync-jira/jira-server-conditions.md` — every script writes its machine result to **stdout**
as `key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines.
Nothing here constitutes a separate implementation; every condition below is emitted by the named script.

**This file is the fourth part of a single unified catalogue, not a fourth independent catalogue.** BTG-173 split it off when only 7
lines of headroom remained in the primary file. The record is **split, never truncated** — the same
pillar-tension resolution BTG-102 and BTG-105 applied (C-3: Operability outranks Agentic DX on *content*;
DX is served by file placement instead).

---

## The untyped ticket (`jira-type-lib.sh` + `jira-reserve.sh` — BTG-173)

**An untyped ticket is a sanctioned lifecycle state, not an error.** `/cadence-triage --file-only` files a ticket
*without* classifying it — `/cadence-triage` F3 writes `tier: ""` and **no `type:`**, because filing is
explicitly distinct from the triage classification stage — and F5 then requires that ticket to be **projected** to the bound
tracker. On a Jira Server binding, those two requirements were previously mutually unsatisfiable: the
projection resolved `.type` through `issue_type_map`, found no `""` key, and **HALTed** with exit `4` at step 4 of
9, preventing the description from being applied and skipping steps 5–9 (transition, worklog, assign, link, epic).
This failure reproduced identically on 4 of 4 tickets in the session that uncovered it.

The two halves of the adapter now enforce **one unified doctrine**: *an untyped ticket receives a **declared
placeholder** type at creation, and is **never re-typed** by an update until classification assigns a real
type.* Neither half acts silently — that is what the two conditions below provide.

The core rule that did **not** change: *a guessed issue type is an ungoverned decision.* Declining to assert
a type the repository does not hold is not guessing it. The exception is narrowed to the single state that cannot
be a configuration mistake, and both narrowings are load-bearing:

- **Emptiness, never lookup failure.** A **non-empty** type that `issue_type_map` cannot resolve still HALTs with
  `syncjs.config.marker_unresolved` and exit **4**. A genuine configuration gap is never swallowed
  by this path.
- **Update, never create.** `--mode create` with an empty type still HALTs. A create request must carry a type
  — Jira requires an `issuetype` on issue creation — and there is no live value to leave untouched. This asymmetry is
  deliberate, not an oversight.

- **`syncjs.write.type_unasserted`** (Warning, `jira-type-lib.sh` via `jira-write-issue.sh`) — the
  ticket's `type:` is absent, empty, or whitespace-only **and** the mode is `update`. The `fields` object
  is sent with **no `issuetype` member**, so the issue retains the type it already holds; **every other
  field still projects** (summary, description, labels, priority, timetracking) and the run exits **0**.
  The decision is recorded on **both** channels: this line on stderr and `issuetype_projected=no` on stdout, making
  it auditable from the transcript. The BTG-102 re-type guard is **bypassed**, not merely skipped —
  if left running against an empty target it would query the edit screen about the type `""`, be refused, and
  instruct the operator to perform a Jira **Move to a type that does not exist**. **Operator action:
  none is owed.** Run `/cadence-triage` on the id; classification writes a real `type:` and the next sync
  projects it. Do not confuse this with **`syncjs.write.issuetype_move_required`**, whose cause is the
  exact opposite: there the repository *does* assert a type and the instance refused it, so a human Move is owed.
- **`syncjs.reserve.type_placeholder`** (Info, `jira-reserve.sh`) — no `--type` was supplied, so the
  reservation was created at the **declared placeholder** type `tech-debt` (which `issue_type_map`
  resolves to this instance's configured value) rather than at a type chosen by the repository. Jira requires an
  `issuetype` on create, so *some* placeholder is unavoidable; the remedy is to **declare** it, not to
  eliminate it. It is a create-time necessity and **never a classification** — the repository continues to
  assert no type until `/cadence-triage` on the id assigns one, and this write is the **only** one that sets
  a type until then. **Expect this condition on every reservation — not only on a `--file-only` filing.** `--type`
  is a supported flag and an explicitly typed reservation declares no placeholder, but **no caller in
  this framework passes it today**: `/cadence-triage`'s F2 allocates the id *before* the triage agent
  classifies, so on every origination path the type is not yet known at reservation time. Read
  this line simply as *"the reservation took the placeholder"* and nothing more. It is **not** a regression
  signal, and its absence means only that whoever invoked `jira-reserve.sh` supplied `--type` directly.
  It reports what has always happened, so no runtime behavior changed on this path — only its visibility.
