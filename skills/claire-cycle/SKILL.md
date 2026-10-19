---
name: claire-cycle
description: Drive a CLAIRE ticket through implementation and code review and stop — pick up where the spec landed (or where a Trivial/Low ticket was triaged), run /claire-implement and /claire-review until zero blocking issues, then open the implementation MR, record it in metadata.yaml, and mark it ready for review. Use this skill whenever the user wants a ticket built rather than specced or shipped, as in "implement BTG-123", "build out this ticket", "the spec merged, take it from here", "run the review cycles on this", "get this coded and up for review", or "continue BTG-99" on a ticket already mid-cycle. Prefer this over /claire-run when the goal ends at a reviewable implementation MR, and over /claire-implement or /claire-review individually when more than one cycle may be needed. It picks up exactly where /claire-prep stops, declines cleanly for a ticket whose spec has not landed yet, and does not run /claire-maintain, monitor the merge, or archive. Only runs in a CLAIRE repo, and only on a ticket that already exists there.
---

# claire-cycle

Take one ticket from **the spec having landed** (or a Trivial/Low ticket having
been triaged) up to **the implementation MR being open, recorded, and ready for
review**, then stop.

This is a strict subset of `/claire-run`: same preflight, same worktree
isolation, same state loop, same progress guard, same cycle ledger, same
fail-loud posture. It picks up exactly where `/claire-prep` puts a ticket down
and runs the middle of the pipeline. If you find yourself about to invoke
`/claire-maintain` or `/claire-archive`, or to wait on the merge, you have left this skill's
scope — stop and say so.

Same design premise as `/claire-run`: **the ticket's own artifacts are the
program counter.** Nothing is held between iterations; re-running picks up from
`metadata.yaml`, `submission.md` and the forge, not from memory.

**Three deliberate divergences from `/claire-run`,** each of them the point:

1. **A problem statement is not a valid argument.** This skill implements a
   ticket that already exists in the repo; it does not create one. An argument
   that is not a ticket id is a halt, not an invitation to triage.
2. **The MR goes ready for review at zero blocking issues, not after
   `/claire-maintain`.** `/claire-run` holds the implementation MR as a draft until
   the maintainer has accepted it, because it goes on to ask for the merge. This
   skill stops at a *reviewable* MR and hands the maintainer gate to whoever runs
   next, so ready-for-review is exactly what the end state means here.
3. **`/claire-maintain` never runs, and nothing is monitored.** The run ends the moment
   the MR is ready. Do not report the ticket as accepted or merged.

## Interoperating with `/claire-run` and `/claire-prep`

A ticket may be started by one of these skills and continued by another, so every
durable mark this skill leaves must be one the others already read.

**The cycle ledger keeps `/claire-run`'s marker name — `claire-run:cycle`.**
It is the shared vocabulary, not a piece of branding, and the state readers of all
three skills grep for that exact string. Inventing `claire-cycle:cycle` would
make this skill's own cycles invisible to itself on the next run and to
`/claire-run` forever, so a ticket that had already run three cycles would read
as zero and start again from one — silently re-running work and blowing past the
cap. Write the marker `/claire-run` writes.

The same holds for the fields: `merge_request` is the implementation MR, `spec_mr`
is the spec MR, and neither gets repurposed. Nothing here introduces a new field.

**A held follow-up set is marked by the prefix `Deferred -- held for the maintainer
gate:` in `submission.md`'s `Follow-ups created`** (see *Held follow-ups*). At
Medium and High this skill leaves that set for `/claire-finish` or `/claire-run` to
decide after `/claire-maintain`, so the prefix must stay verbatim for them to find it.

## Reading state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Do not reconstruct the state by hand from `metadata.yaml`. Hand-reading is exactly
the three-separate-chances-to-misread problem this script exists to remove, and it
encodes two fixes that cost real work to find: it refuses `yaml.safe_load`, because
agents wrap long metadata scalars across lines in a way that is valid YAML and wrong
to a naive parser; and it halts on a ticket-id casing mismatch instead of reporting
the ticket absent.

**It is a twin of the copies in `/claire-run` and `/claire-prep`**, deliberately
duplicated so each skill can be distributed on its own. The script's own header lists
the lines that differ and the one that must not — a fix to any copy is not done until
all of them carry it.

If the script is missing, **halt** with cause `read_state_unavailable`.

## Preflight — abort conditions

Each is a hard stop with a named cause, never a fallback:

1. **`docs/agentic-sdlc/CLAIRE_ORG.md` must exist** (in the working directory or
   a parent). Its absence means this is not a CLAIRE repo and none of the phase
   skills will behave. Abort and say so.
2. **The `§15 Branch-Strategy Binding` markers must resolve.** Never hardcode a
   branch name — ADR-0020 makes those markers the machine-readable source, and
   guessing `main` in a repo that integrates elsewhere corrupts every diff base and
   every "did this land?" check.

`read_state.py` performs both, and exits non-zero with the cause on stderr, so
running it is the preflight.

## Step 1 — resolve the argument

**The argument must be a ticket id, and that ticket must already exist here.**

- **Ticket-id shaped** (`PREFIX-123`) **and `specs/<id>/` exists** → that is the
  ticket; go to the admission gate.
- **Ticket-id shaped, `archive/<id>/` exists** → the ticket is archived. Nothing to
  do; say so and stop.
- **Ticket-id shaped but no such directory** → **halt** with cause
  `ticket_not_established`. This is the tracker-first case, and it is not this
  skill's: there is no `problem.md` to implement against and no tier to pick a
  contract from. Name `/claire-triage <TICKET-ID>` (or `/claire-prep`) as what
  establishes it, and stop. Do **not** invoke `/claire-triage` yourself to keep going —
  that would quietly widen this skill past the window it advertises.
- **Not ticket-id shaped** → **halt** with cause `not_a_ticket_id`, quoting the
  argument. A problem statement is a valid start for `/claire-prep` and
  `/claire-run`, and deliberately not for this skill: implementing something that
  has never been triaged means inventing both the tier and the acceptance criteria,
  which is precisely the ungoverned decision the tier contract exists to prevent.

## Step 2 — the admission gate

This skill owns a window, not a ticket. Getting this wrong in the permissive
direction is what costs: implementing against a spec that has not landed, or
re-opening cycles on a ticket a maintainer has already accepted.

Read the state, then dispatch on `status` **and `tier` together** — neither alone
decides it:

| `status` | admitted? |
|---|---|
| `triaged` | **only at tier Trivial or Low** — at Medium/High the spec is still owed |
| `spec-approved` | **only once the spec has landed** — see the gate below |
| `in-progress` | yes |
| `in-review` | **only while the implementation MR is not yet recorded and ready** |
| `draft`, `spec-in-review` | no — the spec phase owns it; name `/claire-prep` |
| `merged`, `archived` | no — nothing to do |
| unreadable, empty, or not in this table | **halt**, naming the field |

**"Nothing to do" is a clean, successful ending, and must not be dressed up as a
failure.** Say which status the ticket is in, whether that is *not yet* or *already
past* this skill's window, and name the skill that owns it now. The two directions
are different news and the operator needs to know which one they got.

**An unrecognized status is a halt, not a "nothing to do."** A recognized status
outside the window means the ticket moved; an unparseable one means the artifact is
wrong, and quietly returning "nothing to do" files that defect under *success*. Name
the value you actually read.

### The gate at `triaged`

- **Tier Trivial or Low** → admitted. No spec is produced at these tiers by policy,
  so there is nothing to wait for: at Low the tier contract is `problem.md`'s
  acceptance criteria, and at Trivial the change is made ad hoc.
- **Tier Medium or High** → **not admitted.** The spec has not been written yet.
  Name `/claire-prep <TICKET-ID>` (or `/claire-spec`) and stop.
- **Absent, empty, or unrecognized tier** → halt. Do not assume Low; an unresolved
  tier means the review contract is unknown, and the contract is the whole input to
  `/claire-implement`.

### The gate at `spec-approved` — the spec must have *landed*

**Check this on entry every time.** A status field is a claim about an artifact, not
proof that it reached anyone, and `status: spec-approved` is true from the moment the
approving commit is authored — which is *before* its MR merges, by design. So the
status cannot double as "the spec landed."

- **Tier Low or Trivial** → no spec is produced at these tiers, so there is no spec
  MR and nothing to wait for. **Admitted.** Do not run the check below against a
  ticket that was never going to have a spec.
- **Tier Medium or High** → ask where the spec actually is:

  ```bash
  git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
  ```

  A `spec.md` present on the integration branch means the spec landed. That is the
  check, and it is better than reading `spec_mr`'s state because it asks about the
  thing that matters — is the contract in the tree the implementation branch will be
  cut from — rather than about a field that may never have been written. Corroborate
  with the forge when you can reach it (`gh pr view "$SPEC_MR" --json state`), but do
  not depend on it.

  - **Spec on the integration branch** → admitted.
  - **Spec not there** → **not admitted, and this is *not yet* rather than never.**
    The spec exists locally or in an open MR and has not merged. Say so, name
    `/claire-prep <TICKET-ID>` (to propose it) or `/claire-run` (to wait on it),
    and stop.

Implementing ahead of the spec merge is not merely out of order. Phase branches cut
fresh from the integration branch rather than stacking, so an implementation branch
cut before the spec lands is based on a tree that does not contain the spec — the
diff `/claire-review` later evaluates is missing the very contract it checks against,
and the spec's own commits get dragged into the implementation MR or lost.

### The gate at `in-review` — is the MR already reviewable?

`in-review` is ambiguous by itself: it covers an interrupted cycle, an exhausted
cycle, a finished cycle whose MR is waiting on a maintainer, and a ticket already
accepted. This skill's window closes the moment the implementation MR is **recorded
in `merge_request` and no longer a draft**, so resolve it in this order:

0. **Tier Trivial** → short-circuit the cycle arithmetic entirely; there never were
   any cycles, and running the counts against zero of them invites a nonsense
   reading. Go to *The Trivial path*.
1. **`merge_request` empty** → admitted; the MR was never opened.
2. **`merge_request` set** → ask the forge:
   `gh pr view "$MERGE_REQUEST" --json state,isDraft,url`.
   - `OPEN` and still a draft → admitted; the work may be finished but nobody has
     been asked to look at it.
   - `OPEN` and already ready → **nothing to do**; the window is closed and
     `/claire-maintain` (or `/claire-run`) owns it.
   - `MERGED` → **nothing to do**; report the drift, because `status: in-review`
     over a merged MR is stale and the next run needs to know.
   - `CLOSED` unmerged → **halt.** A human rejected this MR; re-opening cycles
     unasked overrides that decision.
   - **Unreachable** → not a halt. That is a fact about your environment, not about
     the ticket. Fall back to the local evidence, say which part you could not
     verify, and prefer the *cautious* reading: if you cannot tell whether the MR is
     already ready, do not start new cycles on it.

## Step 3 — the state loop

Each iteration does two things, **in this order**: establish isolation, then read
state. Reading first and entering afterwards resolves the state from a checkout you
are about to walk away from.

### Iteration step 0 — ensure worktree isolation (agent mode only)

**Agent mode** means this session was dispatched as a background agent — `claude
--bg`, or from the agent view of `claude agents` — as opposed to a foreground
session with an operator at the keyboard. Ask the CLI which kind of session owns
this run; never infer it from how autonomous the run feels:

```bash
claude agents --json 2>/dev/null | python3 -c '
import json, os, sys
sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
try:
    rows = json.load(sys.stdin)
except Exception:
    rows = []
m = [r for r in rows if r.get("sessionId") == sid]
print("session kind=%s" % (m[0]["kind"] if m else "unknown"))'
```

`kind=background` is agent mode. **`interactive`, `unknown`, and any failure of the
command are all not agent mode** — the check fails toward doing nothing, which is
the safe direction.

**The lookup identifies the session, and a delegated subagent is not its own
session — so `kind=background` alone does not mean "isolate".** A subagent spawned
by the Agent tool inherits its parent's `CLAUDE_CODE_SESSION_ID`, so this command
finds the *parent's* row and reports the parent's kind. Measured, not assumed: a
subagent of a background session printed that session's own id and matched its row,
and had no row of its own. The row carries `cwd`, `kind`, `name`, `pid`, `state` —
no parent and no caller — so nothing in its output closes the gap.

Answer that from your own invocation instead, which is the one place it is
unambiguous: **a delegate was handed its task by another agent rather than by a
person.** Both must hold before isolating — `kind=background` **and** this run being
the session's top-level run rather than a delegate of it. If you cannot tell, do not
isolate and say so: a subagent that isolates strands its work in a tree its parent
cannot see.

**Do not try to detect this from `AI_AGENT` or `CLAUDE_CODE_CHILD_SESSION`.** The
CLI stamps *every* process the assistant spawns with `CLAUDE_CODE_CHILD_SESSION=1`
and `AI_AGENT=claude-code_<version>_agent`, so a plain `claude -p` and a real
background agent are byte-identical on both. This was measured.

**Print the branch you took and the kind you observed** — that line is the only way
a wrong classification ever gets noticed.

Isolation matters more here than in the spec phases: `/claire-implement` writes source and
tests and commits repeatedly, so two runs sharing a checkout do not merely race on
`HEAD`, they interleave commits into each other's branches.

Are you already in one?

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
  && echo launch-checkout || echo in-worktree
```

A linked worktree's `--git-dir` is `<common>/worktrees/<name>`; in the main checkout
the two are identical. **Already in a worktree → nothing to do**; say which one and
carry on.

To enter:

1. Run `read_state.py` **in the launch checkout first** and keep its `location=` and
   `status=` lines. That is the before-reading for the guard below.
2. `EnterWorktree` with name `claire-cycle/<TICKET-ID>`.
3. If `EnterWorktree` is not in this run's tool set, **halt** with cause
   `worktree_unavailable`. Do not carry on in the launch checkout hoping it is fine
   — `/claire-implement` will commit there. This is worth ending a run over precisely
   because the damage lands in a tree that is not yours.

**The staleness guard — do not skip it.** A fresh worktree is cut from the remote
default branch, so any ticket artifact that exists *only* in the launch checkout —
uncommitted, or on a phase branch that has not merged — is simply not there. Re-run
`read_state.py` after entering and compare with the before-reading:

- The **whole `guard_tuple=` line** matches → proceed.
- Anything differs → **halt**, quoting both readings. Do not pick one.

**Compare the `guard_tuple=` line, not just `location` and `status`.** Those two
are the fields most likely to match *while the trees still disagree*, because they
describe where the ticket directory is and what its metadata claims — neither of
which lives on a phase branch. The tuple also carries `spec_mr`, `merge_request` and
`ledger_cycles_completed`, and it is that last one the narrow check silently misses:
the cycle ledger lives in `submission.md` on the implementation branch, so a worktree
cut from the integration branch reads **zero completed cycles** while `location` and
`status` match perfectly. The guard passes, the review cap restarts at one, and
cycles that already ran get run again — the exact class of failure this guard exists
to catch, on the field a capped loop depends on most.

It is the same line the progress guard compares, for the same reason: compare it as
printed rather than rebuilding it from the individual fields, because the members
that matter here are the ones easy to forget.

The other half of that, specific to this skill: a spec present in the launch checkout
and absent in the worktree makes an admitted Medium ticket look like it never landed
its spec at all.

**The worktree's base is the remote default branch, not necessarily the §15
integration branch.** If `integration_branch` names something else, say so once and
cut the implementation branch from `origin/<integration-branch>` explicitly.

**Cleanup is not this skill's job.** A run ends with an implementation branch pushed
and an MR open on it; deleting either destroys the deliverable. Leave the worktree
standing and **report its path and branch**.

### Iteration step 1 — read the state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

**Status always runs ahead of the merge — by design. Never gate on it.** The status
recording a phase's completion is written *into the commit its MR carries*, because
that commit is what everyone downstream reads once it lands. A status naming the next
phase is never proof the last one landed — which is why the `spec-approved` gate asks
the tree, not the field.

**Progress guard.** The state block ends with a pre-assembled `guard_tuple=` line.
Capture it before each iteration and compare it after. **Unchanged → stop and report
what you attempted and what blocked it.** Compare that line as printed; do not
rebuild the tuple by hand.

It carries `ledger_cycles_completed` for a reason that matters here: a completed
implement/review cycle returns the ticket to `in-review` and changes `status` not at
all, so a guard watching only `status` would read a whole cycle as a no-op.

**A halt is not a finish.** The guard firing means something went wrong, so its
report must name the state, the unchanged tuple, and what you attempted.

Stop conditions: the implementation MR is open, recorded and ready for review; the
admission gate returned nothing-to-do; the cycle cap was reached and the operator
did not extend it; an explicit halt; or the progress guard firing.

---

## The Trivial path

At Trivial the governed workflow does not apply and `/claire-implement` refuses the tier
outright, so **make the change yourself, now, as part of this run** — ordinary
edits, no TDD cycle, no spec artifacts.

*Ad hoc* here means **bypassing the governed `/claire-implement` workflow — not handing the
work back to the operator.** You edit the files, you commit, you open the MR.
Describing the steps and stopping is a failure of this state: the whole point of
reaching Trivial is that the change is small enough to just do, and a Trivial ticket
that comes back as a to-do list has cost more than it saved.

Then, in order:

1. Record a short entry in `decisions.md` naming what you changed and that it took
   the ad-hoc path, so the archive still carries why the governed process was
   skipped.
2. Create the MR **as a draft**, record its URL in `merge_request`, and set
   `status: in-review`.
3. Mark it ready for review (*Finishing the implementation MR*) and stop.

**`/claire-review` does not run at this tier** — approval of the MR *is* the review,
which is why a Trivial ticket has no cycles and no ledger entries. It goes straight
from creation to reviewable, and the implement/review cycle below does not apply to
it at all.

`change-tiers.md` describes Trivial documentation-only as "Human reviewer: No —
auto-merge if CI passes." That is **not** grounds to skip the MR: the tier table
governs which CLAIRE review *steps* run, while `integration-branch-protected: yes`
in the §15 binding means the forge itself requires a human-approved MR into the
integration branch. Both hold at once. Do not report this as an unresolved policy
tension.

## Sprint confirmation: once per run, covering every cycle

`/claire-implement` runs the §13 sprint-enforcement guard (`CLAIRE_ORG.md#sprint-enforcement-binding`)
on **every** invocation, and on the Confirm path it prompts and appends a
`decisions.md` entry each time. Driven naively, a four-cycle run asks the operator
the same scope question four times, and an unattended run stalls on cycle two. So
this skill **obtains the confirmation once, before the first `/claire-implement` of the
run, and that one answer covers every implement/review cycle the run goes on to
perform**, including any cycles authorised past the cap.

**Resolve the guard first**, from the repo root, for the ticket's own prefix:

```bash
bash ci-templates/scripts/org-binding-resolve.sh --sprint <PREFIX>
```

It prints `enabled=`, `skill=`, `fallback=` and `source=`. A non-zero exit, or output
missing any of those lines, is a **halt** naming what came back; never assume
`enabled=no` because the resolver failed.

- **`enabled=no`** → the Confirm path. Ask (below).
- **`enabled=yes`** → run `<skill> sprint-check <TICKET-ID>` once, exactly as
  `/claire-implement` would.
  - `in-sprint` → no confirmation is needed; proceed. Nothing is recorded here.
  - `not-in-sprint` → **halt** before any implementation. A Block is never
    overridable by a confirmation, from this skill or anyone else.
  - `inconclusive` → apply `fallback=`: `Block` halts, `Confirm` asks (below).

**Ask once.** Put it to the operator plainly: the ticket id, the resolved verdict
and why it landed on Confirm, and that **a yes covers every `/claire-implement` in this
run**. Only an explicit yes counts. A no, an ambiguous or an empty answer → halt,
write nothing, start no work. **If the run cannot ask** (no operator on the other
end), halt here and never self-confirm; that is exactly the out-of-sprint start the
guard exists to prevent.

**Record it before the first cycle** (write-before-proceed, same shape
`/claire-implement` uses): append a dated entry to `specs/<TICKET-ID>/decisions.md`
with the decision (*"operator confirmed the ticket is in scope for implementation;
this confirmation covers every implement/review cycle of this run"*) and the
confirmer identity resolved from `git config user.name` / `user.email`, else the OS
login, else the literal `identity could not be determined`. Never take identity from
typed input. A write failure is a halt.

**Then, on every `/claire-implement` in the loop**, its own guard still runs and still
issues its Confirm prompt. Answer that prompt **yes on the operator's behalf, citing
the run's recorded confirmation**, and let `/claire-implement` append its own
per-invocation entry as usual. Its contract is untouched: invoking it is still not
the confirmation, the prompt is still issued, and every cycle still leaves its own
audit line. What changes is only who types the yes, and that yes is traceable to one
recorded human answer.

The relay is bounded, and each bound is a halt if crossed:

- **Confirm only.** If a cycle's guard returns a verdict other than the one
  confirmed (it Blocks, or a prefix that was `in-sprint` comes back inconclusive),
  do not relay; stop and report. The confirmation answered one question, not a
  different one that turned up later.
- **This run, this ticket.** It is not a carry-forward. A later run (this skill
  again, or `/claire-run`) asks again, and does not read a previous entry back as
  standing permission. Cite it as context when asking, the same posture as the
  cycle-cap override.
- **Not a cap override.** Confirming scope never authorises cycles past the cap;
  that remains its own question.

## The implement/review cycle

This is the skill's main body, for tiers Low, Medium and High. Trivial does not
come here — see *The Trivial path* above.

**Establish the cycle count first.** Read `ledger_cycles_completed` from the state
block. That ledger is the shared record (see *The cycle ledger*) and is
authoritative. Only if it is empty — a ticket whose earlier cycles predate the ledger
— fall back to reading the `/claire-review` verdicts in `submission.md` and counting
them. Treat `stage_effort` counts as corroboration only, never as the count: effort
recording is frequently skipped, so a zero there means "not recorded", not "did not
happen", and trusting it re-runs cycles that already ran.

**Then obtain the sprint confirmation** (*Sprint confirmation: once per run*,
above) if this run has not already. Then loop:

1. Run `/claire-implement <TICKET-ID>`, relaying the run's confirmation to its
   sprint guard.
2. **After the first `/claire-implement`, ensure an MR exists** — `/claire-implement` does not
   create one. Create it **as a draft** against the resolved integration branch and
   record the URL in `merge_request` immediately. It stays a draft for every cycle
   below: the work is still being iterated on, and nothing asks a human to look at
   it until the blockers are gone. **An MR that exists but is not recorded is
   invisible to the next run**, so record it in the same breath as creating it.
3. Run `/claire-review <TICKET-ID>`, holding its non-blocking candidates rather
   than putting them to the operator (see *Held follow-ups*).
4. Append a ledger entry for the cycle (below).
5. **Blocking issues 0** → leave the loop and go to *Finishing the implementation
   MR*. At tier Low, decide the held set first (*Held follow-ups*, *At the gate*).
6. Otherwise run again, **addressing only the blocking issues**. Non-blocking
   suggestions are deliberately out of scope: acting on them grows the diff, which
   gives the next review a larger surface to find new findings in, and the loop
   stops converging. They are held for one decision at the gate, not filed cycle
   by cycle.

### The cycle cap

**Four `/claire-review` invocations total, counting cycles completed before this run.**
On reaching the cap with blocking issues still open, **stop and ask the operator**
whether to continue — do not halt silently and do not grind on unasked.

An unconverged review after four rounds usually means something the loop cannot fix
by iterating: the spec is wrong, the ticket is too big, or the reviews are chasing a
moving diff. That is a human judgement, which is why the cap exists. But it is a
*checkpoint*, not a wall — the operator may know exactly why round five converges.

- Put it to them plainly: cycles completed, what the last review's blocking issues
  were, and the choice between authorising more cycles (say how many) and stopping
  here for a human look.
- **If they authorise more, record it in `decisions.md`** — the question asked, the
  answer given, and how many further cycles it covers — then continue, still
  appending a ledger entry per cycle.

  **That record is an audit trail, not a carry-forward.** The authorisation covers
  *this* run only: a later run — this skill again, or `/claire-run` — reads the
  ledger, sees the count past the cap, and asks again. That is intended. An override
  is a judgement about one moment in a ticket's life, and re-asking is cheap next to
  a stale "yes" silently licensing an eighth cycle nobody agreed to. So do not build
  a mechanism that reads the override back, and do not treat a previous entry as
  standing permission — cite it as context when you ask, and let the human decide
  again.
- **If the run cannot ask** (no operator on the other end), stop at the cap and
  report it. Never self-authorise: the cap's whole function is to force a decision
  that is not the loop's to make.

### Progress summary

Keep this visible and updated as the loop runs, so an operator can see where a long
run is without reading transcripts:

```
BTG-123  cycle 3/4  —  Reviewing
  cycle 1: blocking 4 · non-blocking 7   ✔ addressed
  cycle 2: blocking 1 · non-blocking 3   ✔ addressed
  cycle 3: blocking ? · non-blocking ?   ← in progress
```

The stage per cycle is either `Implementing` or `Reviewing`.

## Held follow-ups: one decision, at the gate

`/claire-review` step 6 asks, on every cycle, which non-blocking candidates to file.
Inside this loop that question comes too early. A later cycle's blocking fixes can
resolve a candidate, change what it is about, or restate it as a new finding, and a
ticket filed from cycle 1 then describes code that no longer exists. So this skill
**holds** every candidate the loop raises and puts the whole set to a human **once, at
the gate**, after the last cycle has changed what it is going to change.

**What is held:** every non-blocking candidate that the next `/claire-implement` cycle
is not directed to address. Under step 6 of the loop, that is all of them.

### During each cycle

When `/claire-review` reaches step 6c (*present and confirm*), do not show the
candidates to the operator. Answer on their behalf with a **deferral**, never a decline
and never a file. Nobody has decided anything yet, and a decline or a `none owed`
recorded here would stop `/claire-maintain` 6b, and every later reader, from ever
raising the candidate again. Then, after `/claire-review` returns:

1. Under that cycle's review entry in `## Discussion`, list the cycle's held
   candidates, one line each: its one-line description, and the command that would
   file it, `/claire-triage --file-only specs/drafts/<TICKET-ID>-held-c<n>-<k>.md`
   (`n` the cycle, `k` the candidate). The draft is written only if the candidate is
   filed at the gate.
2. Make `## Resolution`'s `Follow-ups created` carry **exactly one** held line
   covering every cycle so far, replacing the one the previous cycle wrote (and
   replacing a `None owed` that an earlier zero-candidate cycle recorded):

   `Deferred -- held for the maintainer gate: <N> candidates from code-review cycles <list>, held because later cycles can change them; candidates and their exact filing commands are in ## Discussion.`

   The prefix `Deferred -- held for the maintainer gate:` is the durable mark every
   sibling skill reads to find a held set. Keep it verbatim.
3. Re-read the field. If `/claire-review` recorded anything other than the deferral
   for this cycle's candidates (a filed id, a decline, `none owed`), stop and report
   the drift. Do not overwrite it: that record may carry a decision someone made.

A cycle with zero candidates adds nothing and leaves an existing held line alone.

### At the gate: reconcile, then decide once

**When:**

- **Tier Medium or High:** not in this skill. The gate is `/claire-maintain`, which
  this skill never runs, so the set stays held and travels with the MR. `/claire-finish`
  and `/claire-run` decide it immediately after `/claire-maintain` returns. Report its
  size when handing over.
- **Tier Low:** at loop exit, once blocking reaches 0, before *Finishing the
  implementation MR*. Low has no maintainer gate (`docs/policies/change-tiers.md`), so
  the end of the final review is its only human decision point, and it is the first
  moment the set is final. Publishing the MR with the set still held would leave it
  with no gate to reach.
- **On resume at Low:** if the loop has already exited and `Follow-ups created` still
  carries the held prefix (an interrupted gate), run this step before publishing.
- **Cap reached, or the run stops early:** the set stays held. Report its size and
  where it will be decided.

**How:**

1. **Collect** every candidate listed as held in `## Discussion`.
2. **Reconcile** each one against the MR's current head and against the candidates
   `/claire-maintain` raised itself, and propose exactly one of: **file as written**;
   **file as rewritten** (the finding still stands but later cycles changed it; give
   the new description and the cycle it came from); **decline, resolved** (name the
   cycle or commit that resolved it); **decline, duplicate** (name the candidate it
   folds into). The agent proposes; the human decides.
3. **Present once:** a numbered list, one line per candidate with its proposal, and ask
   which to file. An empty or unrecognized answer re-prompts exactly once; if the
   second is also empty or unrecognized, the remaining candidates stay held, with that
   reason.
4. **File** each confirmed candidate by writing its final description to its
   `specs/drafts/` path and running `/claire-triage --file-only <that path>`. Never call
   the id allocator directly and never hand-write a ticket's artifacts. On a non-zero
   exit, halt and report the callee's error verbatim. Candidates not yet filed stay
   held, and an id already filed stays filed and recorded.
5. **Record:** replace the held line with the final dispositions in the template's
   forms: one filed line per id (phase `maintainer gate`, or `after final code review`
   at Low), and a `Declined` statement giving the operator's reason per candidate.
   Anything still undecided stays under a `Deferred` line naming why. Every held
   candidate appears exactly once.
6. Commit and push `submission.md` to the MR branch.

**If the run cannot ask** (no operator on the other end), leave the held line as it
is and report it. Never decide the set on the operator's behalf: holding it was only
ever a postponement of their decision.

## The cycle ledger

`submission.md`'s review prose is free-form — across the archive the same fact
appears as `#### BLOCKING (1)`, `**Verdict: Approve** · Blocking: 0`, a table, and
several other shapes. None of it parses reliably, which makes "how many cycles have
run and what did the last one find?" unanswerable at resume time.

So record it. After each `/claire-review`, append one line to `submission.md`'s
`## Discussion` section, directly under that cycle's review entry:

```
<!-- claire-run:cycle n=2 phase=code-review blocking=1 nonblocking=3 at=2026-08-21T14:02:11Z -->
```

**The marker says `claire-run` on purpose** — see *Interoperating* above. It is the
shared name every state reader greps for; a skill-specific one would make these
cycles invisible and restart a capped review at one.

An HTML comment keeps it invisible in rendered markdown while staying greppable, and
matches how `CLAIRE_ORG.md` carries its own machine-readable bindings. Get `at`
from `date -u +%Y-%m-%dT%H:%M:%SZ`.

**Append the marker only — never a copy of these instructions.** This skill greps
`submission.md` for that marker, so writing an explanation of the format into the
file being scanned makes the scan match its own documentation and invent cycles that
never ran. After a delegated agent writes to `submission.md`, re-count the markers
yourself rather than trusting the count it reports.

## Finishing the implementation MR

Reaching zero blocking issues is what makes the MR worth someone's attention, so that
is when it stops being a draft. Publishing is this run's terminal act and its only
externally visible effect, so it gets proved rather than assumed:

```bash
bash <skill-dir>/scripts/ready_mr.sh <pr-url-or-number>
```

It reads `isDraft`, publishes if needed, and then **re-reads to confirm** the MR is
actually no longer a draft. `gh pr ready` exiting 0 is not proof: the forge can accept
a call and change nothing, and a run that reports "ready for review" over an MR still
sitting in draft has produced a review request nobody will ever see. Nothing else
catches that, because there is no monitor downstream to notice the MR never merges.

| exit | meaning | what to do |
|---|---|---|
| 0 | ready for review (`was_draft=yes` published it, `no` it already was) | the run is complete |
| 2 | could not publish, or could not confirm | **halt** naming the MR and the cause |

Every run prints a `ready_mr: pr=… result=… was_draft=… url=…` line on stdout.
**That line is the evidence, and quoting it is how this skill reports its result.**

Before you call it done, check that `merge_request` in `metadata.yaml` matches the
URL in that line. The two can disagree — the MR is on the forge and the field is in a
commit — and a mismatch leaves the next run unable to find the MR this one just made
reviewable.

**Then stop.** Do not run `/claire-maintain`, do not monitor the MR, do not wait for the
merge. The run's purpose was to reach a reviewable implementation and hand over.
Equally: do not report the ticket as approved or merged. It is *reviewable*. Say so,
give the URL, state how many follow-ups are held for the maintainer gate, and name
what happens next — `/claire-maintain <TICKET-ID>`, or `/claire-run
<TICKET-ID>` to carry it through merge and archive.

**Never merge the MR.** Merge approval is a human gate, and self-merging removes the
only decision the operator was holding.

## Run-end checklist

Before ending a run — for **any** reason, including a halt, the progress guard, or a
nothing-to-do — verify each of these and state the result:

1. **The outcome is named as exactly one of:** implementation MR open, recorded and
   ready · nothing to do (with the status, and whether that is *not yet* or *already
   past*) · cycle cap reached awaiting authorisation · halt. "Made some progress" is
   not an outcome.
2. **If the MR was published, its `ready_mr:` line is pasted and `merge_request`
   matches the URL in it.**
3. **The cycle count this run ended on is stated, with the ledger entries to back
   it** — how many cycles were completed before this run, how many it ran, and what
   the last review found. A run that says "the review passed" without the count
   cannot be resumed safely by the next one.
4. **The mode this run concluded it was in was stated, with the session `kind` the
   CLI reported**, and in agent mode the worktree it isolated into, reported as
   *left standing* rather than removed.
5. **The stopping reason is named**, along with what unblocks it or who acts next.
6. **The sprint confirmation is stated**: the resolver's verdict, and whether the
   operator was asked once (with the `decisions.md` entry), no ask was needed
   (`in-sprint`, or the run never reached `/claire-implement`), or the run halted at
   the guard.
7. **The held follow-ups are stated**: how many are held and which gate will decide
   them (`/claire-maintain` via `/claire-finish` or `/claire-run` at Medium/High), or,
   if the Low gate ran here, what was filed (ids), declined, and left deferred.

If any item fails, say so explicitly rather than ending on a summary that implies the
run completed. An incomplete run reported as complete is worse than a halt, because
nobody re-runs it.

## Fail-loud rules

These are the cases where guessing quietly does the most damage:

- A missing or unrecognized `tier`, `status`, or branch binding → halt naming the
  field and the value read. Never substitute a default, and never file it as
  "nothing to do". An unresolved tier is especially fatal here: the tier *is* the
  contract `/claire-implement` and `/claire-review` work against.
- A ticket that does not exist locally, or an argument that is not a ticket id →
  halt. Do not triage it into existence to keep the run going.
- Tier Medium or High whose spec is not on the integration branch → not admitted.
  Never implement against a spec that exists only locally.
- A phase skill that reports success but leaves its status field unchanged → report
  the drift explicitly before reconciling it. Silent reconciliation hides a real
  defect in that skill.
- An MR that exists on the forge but is unrecorded in `metadata.yaml`, or vice versa
  → report the contradiction. Reconcile the first by recording the real URL; **halt**
  on a recorded MR the forge *answers about and denies*. A forge you simply cannot
  reach contradicts nothing — degrade to the local evidence and say what went
  unverified. That leniency is about *reading*; publishing the MR is this skill's end
  state, so an unreachable forge is terminal there and `ready_mr.sh` exits 2.
- A ledger count that disagrees with the `/claire-review` verdicts in `submission.md`
  → report both numbers and stop. Picking the lower one restarts cycles that already
  ran; picking the higher one may skip the cap.
- A sprint guard that cannot be resolved, a Block, or an unanswered Confirm → halt
  before `/claire-implement`. Never relay a yes the operator did not give in this run.
- Any halt names the state it halted in and what would unblock it.


## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- During `/claire-implement` and `/claire-review` cycles, use `offload_log_triage` (`local-fast-cpu`) for test/build output compaction (raw log preserved at `/tmp/agy-last-triage.log`) and `offload_deep_review` (`local-moe-hybrid`) for mechanical pre-review diff checks.
