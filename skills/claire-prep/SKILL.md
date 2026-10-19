---
name: claire-prep
description: Take a CLAIRE ticket from intake through spec approval and stop — triage, /claire-spec, resolve the spec's open questions, open the spec-approval MR, record it in metadata.yaml, mark it ready for review — without monitoring that MR and without implementing anything. Use this skill whenever the user wants a ticket worked up rather than taken all the way to done, as in "prep BTG-123", "get this ticket specced", "groom this and put the spec PR up", "triage and write the spec for this", "get this ready for spec review", or when they hand over a raw problem statement and want it turned into an approved spec waiting on a human. Prefer this over /claire-run when the goal ends at spec approval, and over /claire-triage or /claire-spec individually when more than one of those phases remains. It declines cleanly, without doing anything, for a ticket already past spec approval. Only runs in a CLAIRE repo.
---

# claire-prep

Take one ticket from wherever it is up to **the spec-approval MR being open and
ready for review**, then stop. (At Low and Trivial, where policy produces no spec, it
stops one step earlier — see *Stopping at Low and Trivial*.)

This is a strict subset of `/claire-run`: same preflight, same argument
resolution, same worktree isolation, same state loop, same progress guard, same
fail-loud posture. It runs the front half of that pipeline and declines to run the
back half. If you find yourself about to invoke `/claire-implement`, `/claire-review`,
`/claire-maintain`, or `/claire-archive`, you have left this skill's scope — stop and say so.

Same design premise as `/claire-run`: **the ticket's own artifacts are the
program counter.** Nothing is held between iterations; re-running picks up from
`metadata.yaml` and the forge, not from memory.

**One deliberate divergence from `/claire-run`, and it is the whole point.**
`/claire-run` opens MRs as drafts and publishes them at the moment it starts
monitoring, so that a draft always means *nobody is waiting on you yet*. This skill
never monitors, so publishing is instead its **terminal act**: the run ends the moment
its MR is ready for review, because handing that decision to a human is the
deliverable. Do not monitor it afterwards, and do not report it as merged.

## Reading state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Do not reconstruct the state by hand from `metadata.yaml`. Hand-reading is exactly
the three-separate-chances-to-misread problem this script exists to remove, and it
encodes two fixes that cost real work to find: it refuses `yaml.safe_load`, because
agents wrap long metadata scalars across lines in a way that is valid YAML and wrong
to a naive parser; and it halts on a ticket-id casing mismatch instead of reporting
the ticket absent, because "absent" routes to `/claire-triage` and would re-triage a ticket
that already has a classification.

**It is a twin of `/claire-run`'s copy, deliberately duplicated** so each skill can
be distributed on its own. The script's own header lists the three lines that differ
and the one that must not — a fix to either copy is not done until both carry it.

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

The argument is either a ticket id or a problem statement.

- **Ticket-id shaped** (`PREFIX-123`) **and** `specs/<id>/` or `archive/<id>/`
  exists → that is the ticket; go to the admission gate.
- **Ticket-id shaped but no such directory** → the **tracker-first** case, not an
  error: the issue was filed in the bound tracker and has no local artifacts yet.
  This is admissible — but before handing it on, **resolve §9 Tracker Binding in
  `CLAIRE_ORG.md`**, because the whole case rests on there being a tracker to pull
  from:

  - **A tracker is bound** → invoke `/claire-triage <TICKET-ID>`; that skill knows how to
    pull the issue and create the stub. Then continue with the same id. If `/claire-triage`
    cannot resolve that particular issue, let its failure surface rather than
    inventing a ticket to keep going.
  - **`Bound tracker(s): None`** → **halt** with cause `no_bound_tracker`, naming §9.
    There is no source the id could be resolved from, so `/claire-triage` has nothing to
    read and would fail for a reason you already knew. Say that the id may still be
    valid somewhere you cannot see, and that a problem statement — rather than an id
    — is the way in for a repo with no tracker.

  Checking first rather than letting the delegate discover it costs one grep and
  keeps the run from spending a phase invocation to learn something §9 states
  outright. It is not a rare configuration: an inner-source repo with no tracker is
  exactly the case, and there the tracker-first path is unreachable by construction.
- **Anything else** → a problem statement, and admissible by definition: there is no
  ticket yet, so there is nothing further along than this skill's scope. Invoke
  `/claire-triage` with the statement **verbatim** — triage classifies on the requester's
  words — then read back the id it created and continue with it.

## Step 2 — the admission gate

This skill owns a window, not a ticket. Before doing any work, decide whether the
ticket is inside that window. Getting this wrong in the permissive direction is
what costs: re-triaging a classified ticket, or opening a second, empty spec MR.

Read the state, then dispatch on `status`:

| `status` | admitted? |
|---|---|
| `absent` (tracker-first) | yes — but resolve §9 first, then route to `/claire-triage` (see Step 1) |
| `draft` | yes |
| `triaged` | yes |
| `spec-in-review` | yes |
| `spec-approved` | **only if the spec MR is missing or unrecorded** — see that state |
| `in-progress`, `in-review`, `merged`, `archived` | no — nothing to do |
| unreadable, empty, or not in this table | **halt**, naming the field |

**"Nothing to do" is a clean, successful ending, and must not be dressed up as a
failure.** Say which status the ticket is in, say that it is past this skill's
window, and name the skill that owns it now (`/claire-run` for the rest of the
pipeline, or the specific phase skill). Do not offer to do it anyway, and do not
"helpfully" start the next phase — a ticket at `in-review` has an implementation in
flight, and a prep run that decides to re-open its spec is destroying work.

**An unrecognized status is a halt, not a "nothing to do."** The two are different
facts: a later status means the ticket moved on, whereas an unparseable or
unexpected one means the artifact is wrong, and quietly returning "nothing to do"
would file that defect under *success*. Name the value you actually read.

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
the safe direction: the cost is behaving as if this step did not exist, whereas a
false positive relocates a working directory nobody asked to move.

**The lookup identifies the session, and a delegated subagent is not its own
session — so `kind=background` alone does not mean "isolate".** A subagent spawned
by the Agent tool inherits its parent's `CLAUDE_CODE_SESSION_ID`, so this command
finds the *parent's* row and reports the parent's kind. Measured, not assumed: a
subagent of a background session printed that session's own id and matched its row,
and the subagent had no row of its own — `claude agents --json` listed the sessions
and none of the twenty subagents running under one of them.

So the CLI answers *"was the session that owns this run dispatched as a background
agent?"* — which is true for the operator's agent **and** for every delegate it
spawns. It cannot answer *"am I a delegate?"*, and nothing in its output can: the
row carries `cwd`, `kind`, `name`, `pid`, `state`, and no parent or caller.

Answer that second question from your own invocation instead, which is the one place
it is unambiguous: **a delegate was handed its task by another agent rather than by a
person, and usually a specific directory to work in.** You know which you are. Both
must hold before isolating — `kind=background` **and** this run being the session's
top-level run rather than a delegate of it. If you cannot tell, do not isolate and
say so: a subagent that isolates strands its work in a tree its parent cannot see,
which is the very harm this step exists to prevent.

**Do not try to detect this from `AI_AGENT` or `CLAUDE_CODE_CHILD_SESSION`.** It is
the obvious approach and it is wrong. The CLI stamps *every* process the assistant
spawns with `CLAUDE_CODE_CHILD_SESSION=1` and `AI_AGENT=claude-code_<version>_agent`
— the `_agent` suffix means "the assistant launched this command", not "the agent
view dispatched this session". A plain `claude -p` and a real background agent are
byte-identical on both when read from inside a Bash tool. This was measured.

**Print the branch you took and the kind you observed** — that line is the only way
a wrong classification ever gets noticed.

- **Not agent mode → do nothing here.** Never enter a worktree the operator did not
  ask for; it moves the session's working directory out from under them. Foreground
  sessions and `-p` scripted runs land here on `kind` alone; subagents spawned by the
  Agent tool land here on the delegate test above, since a subagent shares its
  parent's checkout deliberately.
- **Agent mode → be in a worktree before running any phase.** Background agents are
  dispatched into the directory the operator launched them from, and several can be
  dispatched against the same one. `/claire-triage` and `/claire-spec` cut branches and
  commit, so two agents sharing a checkout fight over `HEAD` — and an agent working
  in a checkout it does not own has, in practice, already switched an orchestrator's
  branch out from under it mid-run.

Are you already in one?

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
  && echo launch-checkout || echo in-worktree
```

A linked worktree's `--git-dir` is `<common>/worktrees/<name>`; in the main checkout
the two are identical. **Already in a worktree → nothing to do**; say which one and
carry on. Written as a per-iteration check so a run that resumes in a fresh session
re-establishes isolation rather than quietly continuing in the launch checkout.

To enter:

1. If the ticket resolves locally, run `read_state.py` **in the launch checkout
   first** and keep its `location=` and `status=` lines. That is the before-reading
   for the guard below. (Nothing to capture in the tracker-first or raw-statement
   case — there are no local artifacts yet.)
2. `EnterWorktree` with name `claire-prep/<TICKET-ID>`, or a name derived from the
   problem statement when no id exists yet.
3. If `EnterWorktree` is not in this run's tool set, **halt** with cause
   `worktree_unavailable`. Do not carry on in the launch checkout hoping it is fine
   — the very next phase skill cuts a branch there. This is worth ending a run over
   precisely because the damage lands in a tree that is not yours.

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

The specific catastrophe: a ticket present in the launch checkout and absent in the
worktree reads as `location=absent`, which is the tracker-first case, which routes
to `/claire-triage` — re-triaging an already-triaged ticket and clobbering its
classification. That absence is a fact about where you are standing, not about the
ticket.

Untracked inputs do not survive the move either — `specs/drafts/` is gitignored and
is the one that has actually bitten — so if a phase needs a file git does not track,
read it from the launch checkout path *before* entering.

**The worktree's base is the remote default branch, not necessarily the §15
integration branch.** If `integration_branch` names something else, say so once and
make sure each phase cuts from `origin/<integration-branch>` explicitly rather than
from the worktree's HEAD.

**Cleanup is not this skill's job.** A prep run ends with a spec branch pushed and
an MR open on it — deleting either would destroy the deliverable. Leave the worktree
standing and **report its path and branch** so the operator knows where the run
lived. `/claire-run` cleans up when the ticket reaches `archived`; that is a long
way from here.

### Iteration step 1 — read the state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Dispatch on `status` using the state sections below.

**Status always runs ahead of the merge — by design. Never gate on it.** `/claire-spec`
and the approval it leads to reach the integration branch only through a
human-approved MR, and the status recording that has to be written **into the commit
the MR carries**, because that commit is what everyone downstream reads once it
lands. So by construction `status: spec-approved` is true while the spec MR is still
open. That is correct behavior, not drift, and it must not be "fixed" by deferring
the status write — doing so merges an artifact that contradicts its own state.

The consequence: **a status naming the next phase is never permission to begin it,
and never proof the last one landed.** Only the forge knows whether the work landed,
which is why the `spec-approved` state below asks the forge rather than believing
the field.

**Progress guard.** The state block ends with a pre-assembled `guard_tuple=` line.
Capture it before each iteration and compare it after. **Unchanged → stop and report
what you attempted and what blocked it.** Compare that line as printed; do not
rebuild the tuple by hand.

**A halt is not a finish.** The guard firing means something went wrong, so its
report must name the state, the unchanged tuple, and what you attempted — never just
"no further progress."

Stop conditions: an MR of this run's is open and ready for review, the ticket came
back Low or Trivial and its hand-off decision was made, the admission gate returned
nothing-to-do, an explicit halt below, or the progress guard firing.

---

## State: `draft`

Invoke `/claire-triage <TICKET-ID>`.

Then re-read. If the status is still `draft` but triage clearly ran (`triaged_at` or
a triage `stage_effort` entry appeared), triage completed without writing its status
field — a known drift. Report it and set `status: triaged` yourself rather than
looping.

## State: `triaged`

Dispatch on `tier`:

- **Medium or High** → **elicit first if the probes are still open**, then invoke
  `/claire-spec <TICKET-ID>` and iterate. See *Eliciting before the spec is written*.
- **Low or Trivial** → no spec exists at these tiers, so this skill's remaining work
  is already done. Go to *Stopping at Low and Trivial* below — there is one decision
  to put to the operator before the run ends.
- **Absent, empty, or unrecognized** → halt. Do not assume Low; an unresolved tier
  means the review contract is unknown.

### Eliciting before the spec is written

At Medium and High the spec author works from `problem.md`, so a probe left
unanswered is a question the spec will settle by inference rather than by asking.
Asking costs one conversation; inferring costs a spec built on a guess nobody ever
confirmed, and the guess becomes invisible once it is written up as design.

Run `/claire-elicit <TICKET-ID>` when **all three** hold:

1. `tier` is Medium or High,
2. `problem.md` still carries unanswered probes, and
3. `specs/<TICKET-ID>/spec.md` does not exist yet.

The probes are the template's `> **Probe:**` blocks, each followed by an answer line
reading `_(not yet answered)_` until somebody fills it in. Count them rather than
eyeballing:

```bash
grep -c '_(not yet answered)_' specs/<TICKET-ID>/problem.md
```

**The third condition is what stops this firing twice.** Once `/claire-spec` has run,
the probes have already been consumed as input, so eliciting afterwards is not
informing the spec, it is re-opening settled input behind it. A ticket re-entering
this state with a spec on disk has had its chance and goes straight on.

**`/claire-elicit` is interactive and must finish inside one turn**, so it needs somebody on
the other end. **Do not try to work out in advance whether anybody is there, and in
particular do not reuse *Iteration step 0*'s agent-mode check.** That check answers a
different question. `kind=background` tells you another agent may be sharing this
checkout, which is exactly why it governs worktree isolation. It tells you nothing
about whether a human is watching: a background session can be fully attended, with
an operator reading its output and answering as it goes. Treating the two as one
signal skips prompts that would have been answered.

So ask, and let the outcome decide:

- **Invoke `/claire-elicit <TICKET-ID>` and let it put its questions to the requester**, the
  same way this skill puts the Low and Trivial decision to the operator below, with
  no attendance check in front of it.
- **If the questions cannot be delivered, or come back unanswered**, do not stall on
  a conversation that is not happening. Proceed to `/claire-spec` and say plainly in
  the run-end report that elicitation was owed, did not complete, and that N probes
  went into the spec unanswered. Naming it is the point: an unanswered probe nobody
  mentions becomes an assumption nobody knows was made.

Attempting and falling back cannot be wrong about attendance, because it never
guesses at it. Inferring it can be, and was.

This matters more here than it does elsewhere, because this skill's whole deliverable
is a spec put in front of a human. A probe answered now shapes the spec the reviewer
reads; the same probe answered at the gate arrives after the design is written, and
changing it then costs a revision rather than a sentence.

Unanswered probes do **not** block spec authoring, and this is not a gate. A spec can
be, and has been, written and approved with every probe open, deriving its criteria
from the problem description as authored. This step exists to make that the fallback
rather than the default.

**Do not record effort for the elicitation.** `/claire-elicit` appends its own `triage`
increment when it does work, which is why the `triage` stage can carry more than one
entry. Recording one here would double-count it.

### Stopping at Low and Trivial

No spec is produced at these tiers by policy, so there is no spec to groom and no
spec MR to prepare. That is a complete, successful prep outcome, not a failure — and
not a reason to write a spec anyway. At Low the tier contract is `problem.md`'s
acceptance criteria; at Trivial `/claire-implement` refuses the tier outright.

But stopping here leaves a loose end the Medium/High path does not have. **At those
tiers the triage artifacts reach the integration branch as passengers on the spec
MR.** With no spec MR, `specs/<TICKET-ID>/` exists only on a local branch — in agent
mode, inside a worktree this run is about to leave standing — and a triaged ticket
nobody merges is triage that has to be redone. So do not simply announce the tier and
exit.

First find out whether that loose end is real:

```bash
git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
```

If the artifacts are already upstream there is nothing to capture, and offering to
capture them would propose an MR with an empty diff — the same trap the
`spec-approved` state exists to avoid. Say so and stop.

Otherwise put the choice to the operator as a menu of two concrete options, in
keeping with how this skill handles every other decision it cannot make alone:

1. **Implement it now.** The work is small enough that the governed spec machinery
   was never going to earn its keep, and implementation will carry the triage
   artifacts into the integration branch itself. **This skill does not do it** — that
   is past its window. Hand over by name, and the name depends on the tier: at **Low**
   it is `/claire-implement <TICKET-ID>`, whose contract is `problem.md`'s acceptance
   criteria; at **Trivial** `/claire-implement` refuses the tier, so it is `/claire-run
   <TICKET-ID>` (whose Trivial state makes the change ad hoc) or an ordinary edit the
   operator asks for directly. Do not blur those two — naming `/claire-implement` on a
   Trivial ticket sends the operator to a skill that will turn them away.
2. **Capture the triaged ticket for later.** Land the triage artifacts now so the
   classification is durable and the ticket is visible to everyone, and implement
   whenever it gets picked up. This one **is** in scope, because it ends exactly where
   every other path in this skill ends — an MR open and ready for a human. Cut the
   branch as **phase `triage`** under the §15 `branch_naming_convention` — where that
   convention is `{phase}/{type}/{id}`, this is `triage/<type>/<TICKET-ID>` — then
   push, open it as a draft, publish it with *Finishing the spec MR*, and stop.

   **The phase is `triage` and nothing else.** The branch carries triage output and no
   more, so `implement/…` claims a phase that never ran and takes the name the real
   implementation branch will need. This matters more than branch names usually do:
   the capture MR is recorded in no metadata field, so its branch name is the only
   handle anyone has for finding it again.

**A capture MR is recorded nowhere.** It is not a spec MR and not an implementation
MR, and `metadata.yaml` has no field for it. Writing its URL to `spec_mr` would claim
a spec exists, and writing it to `merge_request` would destroy the slot the real
implementation MR needs. Report the URL in the run summary and leave the metadata
alone — the forge remembers it by head ref if a later run needs to find it.

Leave `status: triaged` as it is either way. The capture MR captures a triaged
ticket; it does not advance one.

Which option the operator picks is genuinely their call — one spends effort now, the
other spends a merge cycle to make the classification durable — so present both and
wait rather than choosing.

Two exceptions, and both still leave the operator informed. **If the request already
answers it**, act on what they said: *"get it somewhere I can pick up later"* is a
choice, not an invitation to a menu. Name the option you took and why, state the other
one, and say what switching would cost — asking someone to re-decide what they just
told you is friction, not diligence. **If the run cannot ask at all** (no operator on
the other end), default to capturing: an unmerged triaged ticket is work already done
that is one lost worktree away from having to be done again, and a capture MR left
open costs a human ten seconds to close.

## State: `spec-in-review`

**If `spec_mr` is already set** → an MR exists, but the field says nothing about its
state. Ask the forge and follow step 1 of the `spec-approved` state below — that path
already distinguishes a draft still to publish, an MR that is live, one that merged
while nobody was looking, and a URL the forge cannot resolve.

**If `spec_mr` is not set** → the spec needs grooming and approval first:

1. Find the spec's open questions. Present **each one to the user as a menu of
   concrete choices** — not an open prompt. Open questions in a spec are decisions
   with a small set of real answers; a menu gets a decision, an open question gets a
   discussion.

   Skip this step if `spec_approved_at` is already set — a previous run resolved the
   questions and died before recording the MR. Re-asking risks a different answer to
   a question already decided, silently forking the spec from the decision recorded
   in it.
2. Record the answers in the spec and mark it approved: `status: spec-approved`,
   `spec_approved_at` set. **Do this now, inside the commit the MR will carry** —
   never deferred until after the merge. The MR *is* how the approved spec reaches
   the integration branch, so whatever the commit says is what everyone downstream
   sees. Flip the status afterwards and the MR merges an artifact still marked
   `spec-in-review`.
3. Commit and push the spec branch, then go to *Opening the spec MR*.

## State: `spec-approved`

Admitted only when the spec MR is missing or unrecorded — so the first job is to
find out which, **and the field is not evidence.** `spec_mr` being empty has two
completely different causes and they need opposite responses:

- the MR was never opened → open one;
- the MR was opened and merged, and nothing wrote the URL back → **record it.**

The second is common and not hypothetical: a run that combines triage and spec into
one PR lands `status: spec-approved` in the integration branch with `spec_mr` still
empty. Treating that as "never proposed" opens a **second spec MR with an empty
diff**, because the spec it would carry is already upstream. Ask before you act:

1. **`spec_mr` set** → `gh pr view "$SPEC_MR" --json state,isDraft,url`.
   - `OPEN` and still a draft → go to *Finishing the spec MR*. An unpublished MR is
     not asking anyone for anything, so this skill's window is not actually closed.
   - `OPEN` and already ready, or `MERGED` → **nothing to do**; report the state and
     stop.
   - `CLOSED` unmerged → **halt.** A human rejected this spec, and re-proposing it
     unasked overrides that decision.
   - The forge **answers** and does not know that MR → **halt.** A recorded MR
     the forge denies is a contradiction, not a reason to open a replacement.
   - The forge **cannot be reached at all** (no remote, `gh` unauthenticated,
     network down) → **not a halt.** That is a fact about your environment, not
     about the ticket, and treating it as one turns *I could not check* into
     *this ticket is broken*. Fall back to the local evidence — `spec_mr` is set,
     and `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/` shows
     whether the spec is upstream — report the verdict that supports, and say
     plainly which part you could not verify and what would settle it.
2. **`spec_mr` empty** → ask the forge whether one exists anyway. Derive the spec
   branch from the §15 `branch_naming_convention` with this ticket's id and the spec
   phase, then:

   ```bash
   gh pr list --head <spec-branch> --state all --json number,url,state,isDraft,mergedAt
   ```

   This works after the fact even where `delete_branch_on_merge` removed the remote
   branch — the forge still records the PR's head ref by name.
3. **Still nothing found** → check whether the spec landed by some other route, which
   is what the combined triage+spec PR looks like:

   ```bash
   git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
   git log --oneline -- specs/<TICKET-ID>/spec.md | head
   ```

   A `spec.md` present on the integration branch means the spec is already merged.
   Recover the PR number from the squash commit's subject (`… (#NNN)`).

Then act on what you found:

| finding | action |
|---|---|
| MR found, `MERGED` (or spec already on the integration branch) | write the URL to `spec_mr`, commit, push — **done**, the spec landed and only the record was missing |
| MR found, `OPEN`, draft | write the URL to `spec_mr`, then *Finishing the spec MR* |
| MR found, `OPEN`, ready | write the URL to `spec_mr` — **done** |
| MR found, `CLOSED` unmerged | **halt** — a human rejected this spec; re-proposing it unasked overrides that decision |
| nothing found and no `spec.md` upstream | genuinely never proposed → *Opening the spec MR* |
| spec is upstream but no PR number is recoverable | **halt** — report that the spec landed and the record cannot be reconstructed. Do not invent a URL, and do not open an MR to "fix" it |

Recording a discovered URL still counts as work: it is what makes the ticket legible
to the next run. Say that you reconciled the field, and say where the URL came from.

**Where the reconciling commit goes depends on what you found.** If the spec MR is
still `OPEN`, its branch still exists — commit the `spec_mr` write there and it joins
the MR already in flight. If the spec already **merged**, that branch is gone and the
integration branch is protected (§15 `integration-branch-protected`), so the one-line
fix needs its own small MR: open it as a draft, publish it with the step below, and
stop. That MR is only a vehicle for the metadata fix — it is not the spec MR, so
nothing records *its* URL anywhere.

---

## Opening the spec MR

Push the spec branch, then open it **as a draft**:

```bash
gh pr create --draft --base <integration-branch> --head <spec-branch> \
  --title ... --body ...
```

The draft window is short here — this skill publishes it moments later — but it is
not pointless. Between creating the MR and writing its URL into `metadata.yaml`
there is a gap, and a run that dies in that gap should leave behind a draft nobody
is waiting on rather than a review request pointing at a ticket whose metadata does
not know it exists.

So the order matters:

1. `gh pr create --draft …`
2. Write the URL to `spec_mr` in `metadata.yaml`, commit, push. **An MR that exists
   but is not recorded is invisible to the next run** — that is precisely the drift
   the `spec-approved` state above exists to clean up.
3. *Finishing the spec MR* — publish it.

## Finishing the spec MR

Publishing is this run's terminal act and its only externally visible effect, so it
gets proved rather than assumed:

```bash
bash <skill-dir>/scripts/ready_mr.sh <pr-url-or-number>
```

It reads `isDraft`, publishes if needed, and then **re-reads to confirm** the MR is
actually no longer a draft. `gh pr ready` exiting 0 is not proof: `--undo` is
documented as plan-dependent, the forge can accept a call and change nothing, and a
run that reports "ready for review" over an MR still sitting in draft has produced a
review request nobody will ever see. Nothing else in this skill catches that, because
there is no monitor downstream to notice the MR never merges.

| exit | meaning | what to do |
|---|---|---|
| 0 | ready for review (`was_draft=yes` published it, `no` it already was) | the run is complete |
| 2 | could not publish, or could not confirm | **halt** naming the MR and the cause |

Every run prints a `ready_mr: pr=… result=… was_draft=… url=…` line on stdout.
**That line is the evidence, and quoting it is how a prep run reports its result.**
A summary that says the MR is ready but carries no such line has not shown that it is.

**Then stop.** Do not monitor it, do not poll it, do not wait for the merge. That is
`/claire-run`'s job and this skill deliberately declines it — the run's whole
purpose was to reach a human decision point and hand over. Equally: do not report the
ticket as approved or merged. It is *proposed*. Say so, give the URL, and name what
happens next.

**Never merge the MR.** Spec approval is a human gate, and self-merging removes the
only decision the operator was holding.

## Run-end checklist

Before ending a run — for **any** reason, including a halt, the progress guard, or a
nothing-to-do — verify each of these and state the result:

1. **The outcome is named as exactly one of:** spec MR open and ready · capture MR
   open and ready (Low/Trivial) · handed off for implementation (Low/Trivial, with the
   skill named) · nothing to do (with the status that closed the window) · halt.
   "Made some progress" is not an outcome.
2. **If an MR was published, its `ready_mr:` line is pasted.** For a spec MR, also
   confirm `spec_mr` in `metadata.yaml` matches the URL in that line: those two can
   disagree — the MR is on the forge and the field is in a commit — and a mismatch is
   the exact drift this skill spends a whole state cleaning up, so check it rather
   than assuming the write landed. A capture MR is recorded nowhere, so there is
   nothing to reconcile it against; report its URL in the summary instead.
3. **The mode this run concluded it was in was stated, with the session `kind` the
   CLI reported**, and in agent mode the worktree it isolated into, reported as
   *left standing* rather than removed. Skipping isolation produces no output at all,
   so a run that never checked reads exactly like one that found itself isolated.
4. **The stopping reason is named**, along with what unblocks it or who acts next.

If any item fails, say so explicitly rather than ending on a summary that implies the
run completed. An incomplete run reported as complete is worse than a halt, because
nobody re-runs it.

## Fail-loud rules

These are the cases where guessing quietly does the most damage:

- A missing or unrecognized `tier`, `status`, or branch binding → halt naming the
  field and the value read. Never substitute a default, and never file it as
  "nothing to do".
- `spec_mr` empty while a spec MR exists on the forge, or `spec_mr` set to something
  **the forge answers about and denies** → report the contradiction. Reconcile the
  first by recording the real URL; **halt** on the second rather than opening a
  replacement. A forge you simply cannot reach contradicts nothing — degrade to the
  local evidence and name what went unverified rather than halting on it.

  **That leniency is about *reading*, not about *acting*, and the difference is
  whether the run can still finish.** Asking the forge a question you can answer
  another way is optional; publishing the MR is not, because it *is* this skill's
  end state. So an unreachable forge is survivable while you are establishing a
  verdict, and terminal once you are trying to open or publish an MR — there,
  `ready_mr.sh` exits 2 and the run halts, because no local evidence substitutes for
  an MR that does not exist. Do not carry "unreachable is not a halt" across that
  line and report a run as complete when nothing was ever published.
- A phase skill that reports success but leaves its status field unchanged → report
  the drift explicitly before reconciling it. Silent reconciliation hides a real
  defect in that skill.
- A spec MR the forge refuses to publish → halt naming the MR. An MR left in draft
  is asking nobody for anything, so the run has not reached its own end state no
  matter how much work preceded it.
- Any halt names the state it halted in and what would unblock it, so the next run —
  or the operator — knows what to do.


## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Use `repo-scout` and `local_semantic_embed` (`local-embed-cpu`) during intake/triage and spec preparation to search the codebase and insights registers at zero GPU VRAM cost.
