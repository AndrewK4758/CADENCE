---
name: cadence-prep
description: Advance a CADENCE ticket from intake through specification approval and stop — run /cadence-triage, /cadence-elicit, and /cadence-spec, resolve open specification questions interactively, open the spec-approval MR, record it in metadata.yaml, and publish it ready for review — without monitoring the MR or starting implementation. Activate this skill whenever the user wants a ticket groomed and specced rather than carried all the way to merge, such as "prep BTG-123", "get this ticket specced", "groom this and put the spec PR up", "triage and write the spec for this", "get this ready for spec review", or when supplying a raw problem statement to turn into an approved spec awaiting human review. Prefer this over /cadence-run when the goal ends at spec approval, and over /cadence-triage or /cadence-spec individually when multiple intake/spec stages remain. Declines cleanly with zero mutations when a ticket is already past spec approval. Requires a CADENCE-governed repository.
---

# cadence-prep

Advance a single ticket from its current intake/spec state up to **having its spec-approval MR open, recorded, and published ready for human review**, then stop. (For Low and Trivial tickets, where policy requires no specification, the run stops one phase earlier — see *Stopping at Low and Trivial*.)

This skill executes the exact front half of `/cadence-run`: identical preflight verification, argument resolution, worktree isolation, state-machine loop, progress guard, and fail-loud discipline. It drives intake and specification authoring and deliberately stops before implementation. If you are ever about to invoke `/cadence-implement`, `/cadence-review`, `/cadence-maintain`, or `/cadence-archive`, you have crossed outside `/cadence-prep`'s scope — stop immediately and report that boundary.

Like `/cadence-run`, **the ticket's on-disk artifacts serve as the program counter.** Zero state is cached only in memory across iterations; resuming a run reconstructs everything from `metadata.yaml` and the forge.

**One intentional difference from `/cadence-run` defines this skill's contract.** While `/cadence-run` creates MRs in draft mode and marks them ready only as it enters its merge-monitoring loop (so a draft always signals *no human action requested yet*), `/cadence-prep` never monitors merges. Consequently, marking the spec MR ready for review is `/cadence-prep`'s **final terminal action**: the run finishes the moment the MR is published for human review. Never poll or monitor the MR afterward, and never report the specification as merged.

## Reading state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Never parse `metadata.yaml` manually by hand. Manual reading reintroduces the exact parsing bugs that `read_state.py` was built to eliminate: the script avoids `yaml.safe_load` because agents frequently wrap multi-line scalar values in ways that parse unexpectedly under naive YAML loaders, and it halts on ticket-id case mismatches rather than reporting the ticket `absent` (which would otherwise route an already-classified ticket back into `/cadence-triage`).

**`read_state.py` is an intentional twin of the copy in `/cadence-run` and `/cadence-cycle`** so each skill package remains self-contained. The script header documents the exact lines that differ across skills and the shared logic that must remain identical — any bugfix applied to one copy must be reconciled across all copies in the same change.

If `read_state.py` is absent or unexecutable, **halt** immediately with cause `read_state_unavailable`.

## Preflight — abort conditions

Every preflight failure is an immediate hard stop citing its exact cause, never a fallback:

1. **`docs/agentic-sdlc/CADENCE_ORG.md` must exist** (in the current working directory or an ancestor directory). If absent, this repository is not governed by CADENCE and none of the phase skills can operate. Abort and inform the operator.
2. **The `§15 Branch-Strategy Binding` markers must resolve cleanly.** Never guess or hardcode a branch name — `ADR_CADENCE-0020` establishes §15's machine-readable markers as the sole authority, and assuming `main` in a repository that integrates on `develop` corrupts every diff base and merge-ancestry check.

Because `read_state.py` validates both preconditions and exits non-zero with the cause on `stderr`, running `read_state.py` executes the preflight gate.

## Step 0 — Automatic local discovery and log triage offload

Throughout `/cadence-prep`, enforce automatic local coprocessor offloading before broad file reads or mechanical gate loops:

1. **Pre-Discovery (`local_semantic_embed` / `local-moe-hybrid`).** Prior to broad repository file reads during intake triage (Step 1 / `State: draft`), candidate probe grounding (`State: triaged` -> `/cadence-elicit`), or specification authoring (`State: triaged` -> `/cadence-spec`), automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) and/or `local-moe-hybrid` (`local-moe-hybrid` on `:9380`) to search `specs/`, `archive/`, `docs/agentic-sdlc/intent-insights.md`, `docs/agentic-sdlc/production-insights.md`, and affected codebase symbols without polluting the primary context window.
2. **Mechanical Gate Failure Compaction (`offload_log_triage`).** Whenever `/cadence-spec` runs `.agents/skills/cadence-spec/verify-spec.sh` or `.agents/skills/cadence-spec/verify-facts.sh` and receives non-zero exit output, automatically pipe that output through `offload_log_triage` (`local-fast-cpu` on `:9379`, saving the full numbered log to `/tmp/agy-last-triage.log`) to extract verbatim `FAIL` assertions and exact `file:line` coordinates.

## Step 1 — resolve the argument

The supplied argument is either a ticket identifier or a raw problem description:

- **Ticket-id shaped** (`PREFIX-123`) **and** `specs/<id>/` or `archive/<id>/` exists locally → that directory is the target ticket; advance to Step 2 (the admission gate).
- **Ticket-id shaped but neither directory exists locally** → this is the **tracker-first** intake case rather than an error: the issue was created in the external tracker and has no local `specs/<id>/` stub yet. Before delegating to `/cadence-triage`, **inspect §9 Tracker Binding in `CADENCE_ORG.md`**, because tracker-first intake requires a bound tracker to fetch from:

  - **A live tracker is bound** → invoke `/cadence-triage <TICKET-ID>` so triage performs the governed one-time seed-read and writes the local stub, then continue the prep loop with `<TICKET-ID>`. If `/cadence-triage` fails to fetch that issue key, surface its failure verbatim rather than fabricating a local ticket.
  - **`Bound tracker(s): None`** → **halt** with cause `no_bound_tracker`, citing `CADENCE_ORG.md` §9. With no bound tracker, no external source exists to resolve `<TICKET-ID>`, so invoking `/cadence-triage` would fail predictably. Inform the operator that while the key may exist in an external system unlinked to this repo, inner-source repositories with `Bound tracker(s): None` must enter `/cadence-prep` using a free-text problem statement (or `--file-only` draft path) rather than an unallocated tracker key.

  Verifying §9 up front costs a single read and avoids wasting a full subagent invocation on an unreachable path.
- **Any other argument** → treat it as a raw problem statement (which is always admissible since no ticket exists yet). Invoke `/cadence-triage` passing the problem statement **verbatim** so triage classifies the requester's exact words, read back the newly minted ticket identifier, and proceed to Step 2 with that id.

## Step 2 — the admission gate

`/cadence-prep` governs a specific lifecycle window, not the entire ticket lifespan. Prior to mutating anything, verify that the ticket sits inside that window. Permissive admission errors are destructive: admitting a ticket too early or too late either re-triages classified work or opens a duplicate, empty spec MR.

Run `read_state.py` and dispatch on `status`:

| `status` | admitted? |
|---|---|
| `absent` (tracker-first) | yes — after verifying §9 binds a live tracker, route to `/cadence-triage` (Step 1) |
| `draft` | yes |
| `triaged` | yes |
| `spec-in-review` | yes |
| `spec-approved` | **admitted only when the spec MR is missing or unrecorded** — see `State: spec-approved` |
| `in-progress`, `in-review`, `merged`, `archived` | no — nothing to do |
| unreadable, empty, or not in this table | **halt**, citing the `status` field and raw value |

**"Nothing to do" is a clean, normal exit and must never be reported as an error.** State the ticket's current `status`, explain that it has already advanced past `/cadence-prep`'s window, and name the appropriate downstream skill (`/cadence-cycle` for implementation/review cycles, `/cadence-run` for the full pipeline, or the specific phase skill). Never offer to "run the next phase anyway", and never re-open a specification on a ticket already in `in-progress` or `in-review`.

**An unrecognized or empty `status` is a hard halt, never "nothing to do."** A later lifecycle status means the ticket legitimately progressed; a malformed or unknown status means `metadata.yaml` is corrupted, and reporting "nothing to do" would mask that defect as a clean exit. Always quote the exact value read.

## Step 3 — the state loop

Every loop iteration performs two operations **in strict sequence**: first verify worktree isolation, then read ticket state. Reading state prior to entering the worktree would inspect a launch checkout you are about to leave behind.

### Iteration step 0 — ensure worktree isolation (agent mode only)

**Agent mode** applies when this session was launched as an autonomous background agent — e.g., `claude --bg`, from the `claude agents` background view, or an isolated background subagent — rather than an interactive foreground terminal with a human at the keyboard. Query the CLI directly to determine the session kind rather than guessing:

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

`kind=background` indicates a background session. **`interactive`, `unknown`, or any command error means NOT agent mode** — failing safe toward not moving the working directory when uncertain.

**Because `CLAUDE_CODE_SESSION_ID` identifies the top-level session and is inherited by delegated subagents, `kind=background` alone is necessary but not sufficient to isolate.** A subagent spawned via the Agent/subagent tool inherits its parent's session ID and matches the parent's `kind=background` row in `claude agents --json` (which lists only top-level sessions: `cwd`, `kind`, `name`, `pid`, `state`, without parent/caller fields).

Therefore, combine the CLI check with your own invocation context: **a delegated subagent was invoked by a parent agent (often with a designated working directory), whereas a top-level background agent was dispatched directly for the ticket.** Isolate into a worktree **if and only if** `kind=background` **and** this run is the top-level session rather than a delegated subagent. If uncertain, do not isolate and state why: a subagent that creates its own nested worktree strands its commits where the calling parent agent cannot see them.

**Never rely on `AI_AGENT` or `CLAUDE_CODE_CHILD_SESSION` to detect background mode.** Every subprocess spawned by the assistant carries `CLAUDE_CODE_CHILD_SESSION=1` and `AI_AGENT=claude-code_<version>_agent`, making foreground `claude -p` runs and background agents indistinguishable on those variables.

**Always print the observed `session kind=...` and which isolation branch was taken** so any misclassified session is immediately visible in the run log.

- **Not agent mode → stay in the current checkout.** Never silently switch a foreground operator's working directory into a linked worktree, and never isolate inside a delegated subagent that shares its parent's worktree by design.
- **Agent mode → enter a dedicated linked worktree before executing any phase skill.** Multiple background agents frequently start in the same primary repository checkout; because `/cadence-triage` and `/cadence-spec` switch branches and create commits, two background agents sharing one working tree will collide on `HEAD` and corrupt each other's branches.

Check whether the current directory is already a linked worktree:

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
  && echo launch-checkout || echo in-worktree
```

In a linked worktree, `--git-dir` resolves to `<common>/worktrees/<name>`, whereas in the primary checkout `--git-dir` and `--git-common-dir` are equal. **When already `in-worktree` → log the worktree path and continue.** Evaluating this on every iteration ensures a resumed session re-verifies isolation automatically.

When standing in `launch-checkout` under agent mode, enter a linked worktree:

1. If the ticket already exists locally, run `read_state.py` **in the launch checkout first** and save its complete output (specifically `location=`, `status=`, and `guard_tuple=`). This serves as the baseline for the staleness guard below. (In the tracker-first or free-text problem statement case where no local directory exists yet, there is no pre-entry state to capture.)
2. Invoke `EnterWorktree` named `cadence-prep/<TICKET-ID>` (or a slugified handle derived from the problem statement when no ticket ID has been minted yet).
3. If `EnterWorktree` is unavailable in the runtime's toolset, **halt** immediately with cause `worktree_unavailable`. Never proceed in the shared launch checkout when isolation is required.

**Mandatory worktree staleness guard.** Because a newly created worktree checks out the remote default branch, any uncommitted artifact or unmerged branch state sitting only in the launch checkout will be absent in the new worktree. Immediately re-run `read_state.py` inside the worktree and compare against the launch-checkout reading:

- **The entire `guard_tuple=` line is byte-for-byte identical** → proceed.
- **Any field in `guard_tuple=` differs** → **halt** immediately, quoting both `guard_tuple=` lines verbatim without guessing which tree is authoritative.

**Always compare the full `guard_tuple=` string rather than checking only `location` and `status`.** `guard_tuple=` additionally binds `spec_mr`, `merge_request`, and `ledger_cycles_completed`. Comparing only `location` and `status` misses divergence on unmerged phase branches (and in `/cadence-cycle` would reset `ledger_cycles_completed` to zero, defeating the review-cycle cap). In `/cadence-prep`, the classic failure caught by this guard is a ticket triaged locally in the launch checkout reading as `location=absent` inside the fresh worktree — which would otherwise route to `/cadence-triage` and overwrite the existing classification.

Also remember that untracked files (such as `specs/drafts/`, which is gitignored) are not copied into a new worktree; read any required untracked file from the launch checkout path *prior* to switching into the worktree.

**Verify the integration branch base.** A fresh worktree starts at the remote's default branch, which may differ from `CADENCE_ORG.md` §15's `integration-branch`. When `integration_branch` names a different branch (such as `develop`), log that fact and ensure every phase branch cuts explicitly from `origin/<integration-branch>` rather than worktree `HEAD`.

**Leave the worktree standing at run end.** Because `/cadence-prep` finishes with a pushed spec branch and an open spec MR, deleting the worktree or branch would destroy in-flight work. Keep the worktree intact and **report its filesystem path and branch name** in the run-end checklist.

### Iteration step 1 — read the state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Route according to `status` using the state handlers below.

**Why `status` runs ahead of the forge merge — never treat `status` alone as proof a phase merged.** In CADENCE, `/cadence-spec` and the human open-question rulings write `status: spec-approved` **into the commit on the spec branch before the spec MR merges**, so that merging the MR lands `status: spec-approved` onto the integration branch atomically. Consequently, `status: spec-approved` is already present in `metadata.yaml` while the spec MR is still open (or even before it is opened). Deferring the `status: spec-approved` edit until after merge would merge a file still claiming `spec-in-review`.

Therefore, **a status value naming the next lifecycle stage never proves the prior stage's MR has merged.** Always query the forge and integration branch (as `State: spec-approved` does below) rather than trusting the status string alone.

**Loop progress guard.** Each `read_state.py` invocation outputs a canonical `guard_tuple=` line. Record `guard_tuple=` at the start of each iteration and compare it against the post-iteration reading. **If `guard_tuple=` is unchanged after an iteration → halt immediately and report what action was attempted and what prevented state progression.** Always compare the verbatim `guard_tuple=` line rather than reassembling fields manually.

**Never disguise a progress-guard halt as a normal completion.** When the progress guard trips, report the current state, quote the unchanged `guard_tuple=`, and explain what blocked progression.

Valid loop termination conditions:
1. This run's spec MR (or Low/Trivial capture MR) is open, recorded, and confirmed ready for review (`ready_mr:` exit 0).
2. A Low or Trivial ticket completed triage and the operator chose the hand-off option (or the ticket was already on the integration branch).
3. Step 2's admission gate returned "nothing to do".
4. An explicit fail-loud halt rule fired, or the loop progress guard tripped.

---

## State: `draft`

Invoke `/cadence-triage <TICKET-ID>` (which automatically runs `local_semantic_embed` / `local-moe-hybrid` pre-discovery in its Step 0).

Re-run `read_state.py` afterward. If `status` still reads `draft` even though triage clearly executed (`triaged_at` or a `stage: triage` effort entry was written), report that status-field drift explicitly and update `status: triaged` in `metadata.yaml` so the loop does not re-triage the ticket.

## State: `triaged`

Branch on the normalized `tier` value:

- **Medium or High** → **run `/cadence-elicit <TICKET-ID>` first if unanswered probes remain**, then invoke `/cadence-spec <TICKET-ID>` and continue the state loop. See *Eliciting before the spec is written* below.
- **Low or Trivial** → policy requires no `spec.md` at these tiers, so specification authoring does not apply. Jump to *Stopping at Low and Trivial* below to resolve the single operator hand-off question before exiting.
- **Absent, empty, or unrecognized** → **halt** immediately. Never default an unknown tier to Low.

### Eliciting before the spec is written

For Medium and High tier tickets, `cadence-spec-author` derives the architecture and CHORD decomposition from `problem.md`. Any template probe left unanswered forces the spec author to guess intent silently, baking unverified assumptions into `spec.md`.

Invoke `/cadence-elicit <TICKET-ID>` whenever **all three conditions** hold simultaneously:

1. `tier` is `Medium` or `High`,
2. `specs/<TICKET-ID>/problem.md` still contains >=1 unanswered probe, and
3. `specs/<TICKET-ID>/spec.md` does not yet exist on disk.

Count unanswered template probes mechanically rather than estimating by eye:

```bash
grep -c '_(not yet answered)_' specs/<TICKET-ID>/problem.md
```

**Condition 3 prevents re-triggering elicitation after a spec already exists.** Once `/cadence-spec` has authored `spec.md`, the probes have already been consumed; re-entering `triaged` with `spec.md` on disk advances straight to `/cadence-spec`.

**Never pre-filter `/cadence-elicit` using Iteration step 0's `kind=background` check.** Background session mode (`kind=background`) indicates only that worktree isolation is required to avoid `HEAD` collisions; it does **not** mean no human operator is watching. Background sessions are frequently monitored interactively by an operator who can answer prompts live. Pre-skipping `/cadence-elicit` based on `kind=background` suppresses questions the operator would have answered.

Instead, attempt the interactive call directly and let the runtime outcome govern:

- **Invoke `/cadence-elicit <TICKET-ID>` directly** so it runs its Step 0 `local_semantic_embed` / `local-moe-hybrid` candidate grounding and presents the probe menus to the requester.
- **If the runtime cannot deliver interactive prompts, or the prompts return unanswered**, do not hang the run. Proceed to `/cadence-spec <TICKET-ID>` and state explicitly in the run-end report that elicitation was owed, could not complete interactively, and that `N` probes remained unanswered when the spec was authored.

Unanswered probes **never block** `/cadence-spec` — elicitation is an elaboration aid, not a hard gate, and specs can be authored from the initial problem statement when the requester is unavailable.

**Never log a separate `stage_effort` entry for elicitation inside `/cadence-prep`.** `/cadence-elicit` records its own `stage: triage` effort increment in its Step 7 whenever it writes to disk; logging another entry here would double-count that time.

### Stopping at Low and Trivial

Because `docs/policies/change-tiers.md` requires no `spec.md` or `test-plan.md` at Low or Trivial tier, no specification or spec MR is produced. At Low tier, `problem.md`'s Acceptance Criteria checklist is the implementation contract; at Trivial tier, `/cadence-implement` does not apply at all.

However, stopping immediately after triage at Low/Trivial leaves a gap that Medium/High tickets avoid: **for Medium/High tickets, `problem.md` and `metadata.yaml` reach the integration branch inside the spec MR.** When there is no spec MR, `specs/<TICKET-ID>/` sits only on a local branch (or inside a background worktree), risking lost triage work if that local tree is discarded.

Check first whether `specs/<TICKET-ID>/` has already landed on the integration branch:

```bash
git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
```

If `specs/<TICKET-ID>/` is already present on `origin/<integration-branch>`, nothing needs capturing (and opening a capture MR would fail with an empty diff). Report that the triaged ticket is already on the integration branch, name the next skill (`/cadence-cycle <TICKET-ID>` or `/cadence-implement <TICKET-ID>` at Low; `/cadence-cycle <TICKET-ID>` or `/cadence-run <TICKET-ID>` at Trivial), and stop.

When `specs/<TICKET-ID>/` is **not** yet on `origin/<integration-branch>`, present two explicit choices to the operator:

1. **Hand off for immediate implementation.** Because implementation will commit and carry `specs/<TICKET-ID>/` into the integration branch alongside the code changes, no separate triage-capture MR is needed. **Do not run implementation inside `/cadence-prep`** — hand over by naming the exact command for the tier:
   - At **Low** tier: name `/cadence-implement <TICKET-ID>` (or `/cadence-cycle <TICKET-ID>`), governed by `problem.md`'s Acceptance Criteria.
   - At **Trivial** tier: `/cadence-implement` refuses Trivial work, so name `/cadence-cycle <TICKET-ID>` or `/cadence-run <TICKET-ID>` (whose Trivial path performs the direct edit and opens the MR), or an ordinary direct edit. Never tell the operator to run `/cadence-implement` on a Trivial ticket.
2. **Open a triage-capture MR for later pickup.** Land `specs/<TICKET-ID>/` onto the integration branch now so the triaged stub and classification are preserved upstream until someone picks it up later. This path **is** within `/cadence-prep`'s scope because its deliverable is an open, ready-for-review MR. Cut the branch using **phase `triage`** under `CADENCE_ORG.md` §15's `branch-naming-convention` (e.g., `triage/<type>/<TICKET-ID>` when the pattern is `{phase}/{type}/{id}`), commit `specs/<TICKET-ID>/`, push, create the MR as a draft, publish it via *Finishing the spec MR*, and stop.

   **Always use phase `triage` for the branch name — never `implement/...` or `spec/...`.** Because the capture MR carries only triage artifacts and its URL is not stored in `metadata.yaml`, the `triage/...` branch name is the sole deterministic handle for locating it on the forge.

**Never write a capture MR's URL into `spec_mr` or `merge_request` in `metadata.yaml`.** Populating `spec_mr` would falsely claim a specification exists on a Low/Trivial ticket, while populating `merge_request` would occupy the field needed by the subsequent implementation MR. Output the capture MR URL in the run summary while leaving both metadata fields empty.

Keep `status: triaged` unchanged in `metadata.yaml` under both options.

Two rules govern how the choice between Option 1 and Option 2 is made:
- **When the operator's initial prompt already specified their preference** (e.g., *"triage this and put up a PR so we can build it next sprint"*), execute that choice directly without re-prompting, state which option was taken and why, and note the alternative.
- **When no interactive operator is reachable** (unattended run), default to **Option 2 (capture MR)**: opening a small triage-capture MR preserves the completed triage work upstream rather than stranding it in an unmerged local worktree.

## State: `spec-in-review`

**When `spec_mr` is already populated in `metadata.yaml`** → an MR URL is recorded, so inspect its live state on the forge by jumping directly to step 1 of `State: spec-approved` below (which handles draft MRs needing publication, already-ready MRs, merged MRs, and invalid URLs).

**When `spec_mr` is empty** → groom the specification's open questions and record spec approval before opening the MR:

1. Inspect `specs/<TICKET-ID>/spec.md` for open questions (`## Open Questions`) and `specs/<TICKET-ID>/design-options.md` (when present). Present **each open question (and design option selection) to the human operator as a structured menu of concrete options** rather than an open-ended prompt.
   - **Skip this interactive step if `spec_approved_at` is already populated** in `metadata.yaml` — which indicates an earlier run already collected the human's rulings and crashed before opening or recording the MR. Re-asking settled questions risks recording conflicting rulings.
   - When `**Gate 1 rulings:** required` is present in `spec.md`, record the operator's rulings in `specs/<TICKET-ID>/decisions.md` using the required Gate 1 ruling grammar and verify via `.agents/skills/cadence-spec/verify-facts.sh --rulings <TICKET-ID>` (piping any failure output through `offload_log_triage`).
2. Record the resolved answers in `spec.md` / `decisions.md` and update `specs/<TICKET-ID>/metadata.yaml` with `status: spec-approved` and `spec_approved_at` set to the exact UTC timestamp from `date -u +%Y-%m-%dT%H:%M:%SZ`. **Write this status transition now, inside the commit on the spec branch prior to opening/merging the MR** — never defer it until after merge, because the spec MR itself is how `status: spec-approved` lands on the integration branch.
3. Commit and push the spec branch, then execute *Opening the spec MR* below.

## State: `spec-approved`

A ticket in `spec-approved` is admitted into `/cadence-prep` only when its spec MR is still missing, unrecorded, or sitting in draft. Never assume an empty `spec_mr` field proves no MR was ever opened — two opposite situations produce `spec_mr: ""`:

- no spec MR has been created yet → create and publish one;
- a spec MR was created (and possibly already merged), but its URL was never written back to `spec_mr` → **reconcile `spec_mr` with the discovered URL.**

Opening a blind second MR when `spec.md` has already merged onto the integration branch produces a broken empty-diff PR. Always verify against the forge and integration branch first:

1. **When `spec_mr` is non-empty** → query the forge:
   ```bash
   gh pr view "$SPEC_MR" --json state,isDraft,url
   ```
   - `OPEN` and `isDraft: true` → jump to *Finishing the spec MR* to publish it ready for review.
   - `OPEN` and `isDraft: false`, or `MERGED` → **nothing to do**; report the live MR state and exit cleanly.
   - `CLOSED` (unmerged) → **halt.** A human closed/rejected this spec MR; never re-open or replace a rejected spec MR without explicit operator instruction.
   - The forge **responds** that no such PR exists → **halt.** A recorded `spec_mr` URL that the forge explicitly denies is a metadata contradiction to surface, never something to silently overwrite.
   - The forge **is unreachable** (offline, no remote, `gh` auth expired) → **do not halt here.** Network/auth unavailability is an environmental limitation rather than a ticket defect. Fall back to checking local git refs — inspect `spec_mr` and run `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/` — report what local evidence shows, and state explicitly which forge check could not be verified.
2. **When `spec_mr` is empty** → query the forge by branch head ref first. Construct `<spec-branch>` from `CADENCE_ORG.md` §15's `branch-naming-convention` for the `spec` phase and `<TICKET-ID>`, then run:

   ```bash
   gh pr list --head <spec-branch> --state all --json number,url,state,isDraft,mergedAt
   ```

   This query locates merged PRs even when `delete_branch_on_merge` deleted the remote branch after merging.
3. **When `gh pr list` returns no match** → check whether `spec.md` already landed on the integration branch via a combined branch or different ref name:

   ```bash
   git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
   git log --oneline -- specs/<TICKET-ID>/spec.md | head
   ```

   If `specs/<TICKET-ID>/spec.md` is present on `origin/<integration-branch>`, the specification has already merged; extract the PR number from the merge/squash commit subject (`… (#NNN)`).

Dispatch on the discovery result:

| finding | action |
|---|---|
| MR found with `MERGED` (or `spec.md` already on the integration branch with recoverable PR URL) | write the URL to `spec_mr` in `metadata.yaml`, commit, and push — **done** (the spec already landed; only the metadata pointer was missing) |
| MR found with `OPEN` and `isDraft: true` | write the URL to `spec_mr`, commit, push, then run *Finishing the spec MR* |
| MR found with `OPEN` and `isDraft: false` | write the URL to `spec_mr`, commit, and push — **done** |
| MR found with `CLOSED` (unmerged) | **halt** — a human rejected this spec MR; never re-propose it unasked |
| no MR found and no `spec.md` on the integration branch | specification has genuinely never been proposed → run *Opening the spec MR* |
| `spec.md` is on the integration branch but no PR URL/number can be recovered | **halt** — report that the spec merged upstream without a recoverable PR reference; never fabricate a URL or open a dummy MR |

**Where to commit a reconciled `spec_mr` URL:**
- If the discovered spec MR is still `OPEN`, check out its spec branch, commit the `spec_mr` update there, and push so it joins the open MR.
- If the spec MR has already `MERGED` and the integration branch is protected (`CADENCE_ORG.md` §15 `integration-branch-protected: yes`), cut a tiny metadata reconciliation branch, open a draft MR for the one-line `spec_mr` fix, publish it via *Finishing the spec MR*, and stop (without recording that housekeeping MR's own URL in `spec_mr`).

---

## Opening the spec MR

Push the spec branch to `origin`, then create the pull request **in draft mode**:

```bash
gh pr create --draft --base <integration-branch> --head <spec-branch> \
  --title ... --body ...
```

Creating the MR as a draft first closes the crash window between PR creation on the forge and recording `spec_mr` in `metadata.yaml`: if the session terminates between steps 1 and 2, the forge holds an unannounced draft rather than a live review request whose ticket metadata does not yet record `spec_mr`.

Execute these three steps in exact order:

1. `gh pr create --draft --base <integration-branch> --head <spec-branch> ...`
2. Record the returned PR URL in `spec_mr` inside `specs/<TICKET-ID>/metadata.yaml`, commit, and push to `<spec-branch>`.
3. Execute *Finishing the spec MR* below to publish it ready for review.

## Finishing the spec MR

Marking the MR ready for review is `/cadence-prep`'s terminal externally visible action, so verify publication mechanically via `ready_mr.sh`:

```bash
bash <skill-dir>/scripts/ready_mr.sh <pr-url-or-number>
```

`ready_mr.sh` checks `isDraft`, invokes `gh pr ready` when needed, and **re-queries the forge afterward** to prove `isDraft` is now `false` (because `gh pr ready` can exit `0` without changing state on certain forge plans/permissions).

| exit | meaning | what to do |
|---|---|---|
| 0 | confirmed ready for review (`was_draft=yes` transitioned it; `was_draft=no` was already ready) | prep run is complete |
| 2 | failed to publish or failed post-publish confirmation | **halt** citing the MR URL/number and exact failure cause |

`ready_mr.sh` emits a structured evidence line on stdout:
`ready_mr: pr=… result=… was_draft=… url=…`
**Always quote that verbatim `ready_mr:` line in the run summary** as proof the MR is live for reviewers.

**Then stop immediately.** Never poll the MR, never wait for CI or human approval, and never invoke `/cadence-implement`. State clearly that the specification is *proposed and ready for human review*, provide the MR URL, and name the next step once a human merges it (`/cadence-cycle <TICKET-ID>` or `/cadence-run <TICKET-ID>`).

**Never self-merge the spec MR.** Specification approval is a mandatory human gate.

## Run-end checklist

Prior to ending `/cadence-prep` — across **every** exit path, including halts, progress-guard trips, and nothing-to-do exits — verify and explicitly report all four items:

1. **Terminal outcome classification** — name **exactly one** of:
   - `spec MR open and ready`
   - `capture MR open and ready` (Low/Trivial)
   - `handed off for implementation` (Low/Trivial, naming the exact target skill)
   - `nothing to do` (naming the current `status` that placed the ticket outside `/cadence-prep`'s window)
   - `halt` (naming the exact state and cause)
   Never report vague partial progress such as `"made some progress"`.
2. **Verbatim `ready_mr:` evidence line** whenever an MR was published. For a spec MR, also verify that `spec_mr` in `metadata.yaml` equals the `url=` in `ready_mr:` (for a Low/Trivial capture MR, confirm `spec_mr` and `merge_request` remain untouched and report the URL in the summary).
3. **Session mode and worktree status** — report the observed `session kind=...` from Iteration step 0, whether agent-mode isolation ran, and (when isolated) the worktree path and branch *left standing*.
4. **Stopping reason and next actor** — state why the run stopped and who acts next (e.g., human reviewer on the spec MR, or what unblocks a halt).

If any checklist item fails verification, report the failure explicitly rather than presenting the run as complete.

## Fail-loud rules

Never guess silently on any of the following conditions:

- Missing, empty, or unrecognized `tier`, `status`, or `CADENCE_ORG.md` §15 branch binding → **halt** naming the attribute and quoting the raw value read. Never substitute a default or report "nothing to do".
- `spec_mr` empty while an MR already exists on the forge, or `spec_mr` populated with a URL **that the reachable forge explicitly denies** → report the discrepancy; reconcile the first by recording the discovered URL, and **halt** on the second without opening a replacement MR.
  - **Distinguish reading from publishing when the forge is unreachable:** while *inspecting* state, an unreachable forge degrades gracefully to local git evidence (`git ls-tree origin/<integration-branch>`) with an explicit disclosure; when *opening or publishing* the spec MR at the end of the run, forge reachability is mandatory — `ready_mr.sh` exits `2` and the run **halts**, because `/cadence-prep` cannot complete its deliverable without a published MR.
- A delegated phase skill (`/cadence-triage` or `/cadence-spec`) exits cleanly but leaves `status` unchanged in `metadata.yaml` → report the status drift explicitly before reconciling the field.
- `ready_mr.sh` exits non-zero or leaves `isDraft: true` → **halt** naming the MR.
- Every halt message must name the state where the halt occurred and the concrete action required to unblock it.

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 0 automatically invokes `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) and `local-moe-hybrid` (`local-moe-hybrid` on `:9380`) during intake triage, probe candidate grounding, and specification preparation to search codebase symbols and insights registers at zero GPU VRAM cost.
- Step 0 automatically routes any `verify-spec.sh` or `verify-facts.sh` failure output through `offload_log_triage` (`local-fast-cpu` on `:9379`, saving raw numbered output to `/tmp/agy-last-triage.log`).
