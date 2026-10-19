---
name: cadence-parallel
description: Execute the end-to-end triage-to-archive CADENCE pipeline concurrently across multiple tickets using isolated git worktrees and mandatory local coprocessor offload for parallel implementation and review.
argument-hint: "<ticket-id-1> [ticket-id-2] [ticket-id-3] ..."
arguments: [ticket_ids]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---


## Task

Drive the complete CADENCE lifecycle (Problem -> Triage -> Spec -> [Human Gate: Spec Approval] -> Implementation -> [Human Gate: Code Review] -> [Human Gate: Maintainer Acceptance] -> Merge -> Archive) across all tickets in `$ticket_ids` concurrently, fanning out independent per-ticket work in parallel rather than serially. Every lifecycle phase delegates to the exact same specialized subagent used by the single-ticket skills (`cadence-triage-agent` subagent, `cadence-architect` subagent, `cadence-explorer` subagent, `cadence-spec-author` subagent, `cadence-implementer` subagent, `cadence-reviewer` subagent, `cadence-maintainer` subagent, `cadence-archivist` subagent) -- this skill governs *concurrent fan-out, worktree isolation, and sequencing*, without altering any individual role's responsibilities. Each ticket traverses the path mandated by its assigned change tier in `docs/policies/change-tiers.md`: a Medium or High-tier ticket executes every phase and human gate above, whereas a Low-tier ticket bypasses Spec authoring as well as the Spec Approval and Maintainer Acceptance gates -- advancing along `triage -> implementation -> [Human Gate: Code Review] -> merge`, with Code Review serving as its single human gate. Each step below routes tickets conditionally according to their tier.

Human approval gates remain strictly mandatory and evaluated per ticket: present each ticket's gate decision to the requester immediately upon that ticket reaching the gate, regardless of the progress of sibling tickets in the batch. Never bundle gate approvals across tickets unless explicitly requested by the user.

## Prerequisites

- Every identifier in `$ticket_ids` must map either to an existing `specs/<id>/problem.md` or to a raw problem statement that the `cadence-triage-agent` subagent can triage from scratch.
- The working tree must be clean enough to record a synchronization checkpoint commit prior to launching implementation worktrees (Step 3). If unrelated uncommitted modifications exist in the working tree, ask the requester how to handle them rather than sweeping them into the batch checkpoint.

## Cross-ticket dependencies

Prior to launching implementation worktrees (Step 4), inspect each ticket's `problem.md` and `metadata.yaml` for declared dependencies (such as a Constraints/Dependencies entry referencing another ticket in `$ticket_ids`, or an equivalent dependency link). A ticket that depends on another ticket in the current batch still completes Triage and Spec authoring concurrently, but its **implementation phase is held** until the prerequisite ticket reaches `merged` status. Always report this dependency hold explicitly in status updates -- never stall a ticket silently.

## Steps

### 1. Triage (concurrent, no isolation needed)

For every ticket in `$ticket_ids`, invoke the `cadence-triage-agent` subagent following the exact `/cadence-triage` protocol. Because each triage run reads and writes exclusively within its own `specs/<id>/` directory (while using `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) / `local-moe-hybrid` for insight and symbol lookups), dispatch all triage subagents concurrently rather than sequentially.

For any ticket classified as Medium or High tier with unanswered elicitation probes, offer the interactive `/cadence-elicit` interview (per `/cadence-triage` Step 5) before advancing that ticket to Step 2. If the requester declines the interview for a specific ticket, they are opting for the `cadence-spec-author` subagent to infer answers and document explicit `[ASSUMED]` markers during Step 2 -- confirm that choice explicitly and proceed.

### 2. Spec authoring (concurrent, no isolation needed)

Read each triaged ticket's `tier:` field from `specs/<id>/metadata.yaml` and route strictly by tier -- Spec authoring in this step applies only to Medium and High-tier tickets:

- **Low tier** -> do NOT invoke `cadence-spec-author` (nor the High-tier `cadence-architect` pre-flight, which never applies below High tier). By policy (`docs/policies/change-tiers.md`), a Low-tier ticket relies solely on its `problem.md` acceptance criteria without a `spec.md` or Spec Approval gate; advance it directly from Step 1 (Triage) to Step 4 (Implementation), mirroring the single-ticket Low path (`triage -> skip /cadence-spec -> /cadence-implement -> /cadence-review`). Log its status as "Low tier -- routed straight to implementation".
- **Medium/High tier** -> for High-tier tickets, execute the `cadence-architect` subagent pre-flight first, then delegate to the `cadence-spec-author` subagent following the exact `/cadence-spec` sequence. **Following `/cadence-spec` means dispatching the `cadence-explorer` subagent FIRST** -- invoke `cadence-explorer` so it writes `specs/<id>/design-options.md` *before* launching `cadence-spec-author`, never after and never concurrently. Divergent exploration is an explicit orchestration step of *this* skill, never an internal sub-call inside `cadence-spec-author` (since an agent that invents its own alternatives could tailor them to justify a predetermined choice). Tier gating is **inherited directly from this branch** -- only Medium and High tickets enter this arm, ensuring no `design-options.md` is generated for Low or Trivial tickets. If `cadence-explorer` fails on a particular ticket, surface the error and ask the requester whether to proceed without exploration for that ticket; if confirmed, `cadence-spec-author` records the explicit **not-performed marker** and notes the omission in `spec.md`. **Never bypass exploration silently**, and never apply one ticket's exploration waiver across other tickets in the batch.
- **Trivial tier** -> outside the scope of `/cadence-parallel`: Trivial changes require no agent lifecycle phases (`change-tiers.md`: no spec-author, implementer, reviewer, or maintainer). Report the Trivial classification and handle it outside this pipeline without dispatching subagents.
- **Tier missing, blank, or invalid** (anything other than `{Trivial, Low, Medium, High}`) -> never guess the tier. Pause that specific ticket, output the invalid or missing `tier:` value verbatim, and request that a valid `tier:` be recorded (or `/cadence-triage` re-run) before advancing it. **Never default to Low** -- silently routing an untiered ticket to implementation would bypass mandatory specification and human approval gates required for Medium/High work. Remaining tickets in the batch continue normally.

Run all eligible Spec authoring delegations in parallel -- each writes to its own `specs/<id>/` directory and makes only additive updates to shared registries (such as `docs/policies/surface-registry.md`).

Whenever `cadence-architect` or `cadence-spec-author` raises a genuine product or architectural fork that belongs to the human requester (such as a scope boundary, security posture tradeoff, or breaking contract decision), pause that ticket and ask the requester before finalizing its spec -- never allow a subagent to silently make a material design choice on the human's behalf.

### 3. Checkpoint before implementation (mandatory, blocking)

**Execute this checkpoint once for the batch after all Medium/High-tier tickets entering implementation have passed their [Human Gate: Spec Approval] and all Low-tier tickets have their triaged `problem.md` acceptance criteria ready (Low-tier tickets have no Spec Approval gate) -- never skip this checkpoint.** Because each isolated implementation worktree branches off the shared integration branch (defined in `CADENCE_ORG.md#branch-strategy-binding`), if that integration branch lacks the batch's approved artifacts (`spec.md` and `test-plan.md` for Medium/High; `problem.md` acceptance criteria for Low per `docs/policies/change-tiers.md`), an isolated implementer worktree will start without its governing specification and either halt or hallucinate an unapproved design.

1. Stage and commit all pending specification and triage artifacts for the batch according to each member's tier: for Medium/High tickets, include `problem.md`, `metadata.yaml`, `spec.md`, `test-plan.md`, `design-options.md`, and `decisions.md`; for Low tickets, include `problem.md` (with approved acceptance criteria), `metadata.yaml`, and `decisions.md` if present (no `spec.md` or `test-plan.md` exists at Low tier); plus any updated shared documentation.
2. Merge that checkpoint commit into the shared integration branch (using fast-forward when possible).
3. If remote push credentials are available in the environment, push the updated integration branch to `origin`. If remote push is unavailable or restricted, keep the local merge and inform the requester that isolated implementation worktrees must be branched from the local integration branch rather than the remote tracking ref.

Always obtain explicit approval at each Medium/High ticket's [Human Gate: Spec Approval] prior to including its spec in the checkpoint commit -- unapproved specs must never be merged into the shared branch from which implementer worktrees are created. Low-tier tickets require no Spec Approval gate (`change-tiers.md`); their triaged `problem.md` acceptance criteria (along with `metadata.yaml` and optional `decisions.md`) fold directly into the checkpoint in accordance with the Stale-Seed Worktree safeguards in `docs/guides/parallel-sdlc-usage.md`.

### 4. Implementation (concurrent, isolated per ticket, with mandatory local log triage)

For every approved, dependency-unblocked ticket (see Cross-ticket dependencies), dispatch the `cadence-implementer` subagent following `/cadence-implement`, with two mandatory parallel-execution safeguards:
1. **Dedicated worktree isolation:** every ticket's implementation runs inside its own dedicated git worktree branched from the Step 3 checkpoint commit -- never share a single worktree between concurrent ticket implementations, as overlapping file edits will corrupt both runs.
2. **Automatic local test/build log offload:** across all concurrent worktree test and build executions during Red-Green-Refactor TDD cycles, **automatically enforce `offload_log_triage` (`local-fast-cpu` on `:9379`, or the `log-triage` subagent)** to compact noisy test runner, compiler, and linter logs while preserving verbatim failing assertions, exact command evidence, coverage metrics, and `file:line` coordinates (with full raw output written to `/tmp/agy-last-triage.log`). This prevents parallel test suites from exhausting context windows or GPU VRAM.

Guard explicitly against two worktree failure modes:

- **Worktree branched prior to Step 3's checkpoint or from a stale ref.** If a `cadence-implementer` subagent reports that its ticket's governing artifacts (`spec.md` at Medium/High tier; `problem.md` acceptance criteria at Low tier per `docs/policies/change-tiers.md`) are missing in its worktree, forbid it from guessing or synthesizing requirements. Provide the absolute path to the committed specification in the primary checkout so it can read from there, or terminate and re-create its worktree from the updated integration branch tip.
- **Never resume an implementation subagent context that produced zero file modifications.** When a delegated implementation attempt exits without having written or committed anything (due to a blocker, missing spec, or tool error), treat that context as terminated: diagnose and resolve the underlying cause, then launch a fresh subagent in a newly created worktree rather than messaging the no-op subagent context -- an untouched worktree may have been garbage-collected, causing a resumed session to fall back to the parent checkout's working directory.

### 5. Code review and Maintainer acceptance (concurrent, per ticket, with mandatory local pre-review offload)

As each ticket completes implementation in its isolated worktree:
1. **Automatic local pre-review scan:** before invoking `cadence-reviewer`, **automatically run `offload_deep_review` (`local-moe-hybrid` on `:9380`)** against that ticket's worktree diff to perform an advisory mechanical pre-scan checking the `<400`-line file ceiling, comment discipline, Engineering Pillars, and CHORD observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).
2. **Reviewer delegation:** invoke the `cadence-reviewer` subagent (following `/cadence-review`) against the ticket's isolated worktree, passing the `offload_deep_review` pre-scan findings for verification. Surface the [Human Gate: Code Review] to the requester as soon as the review report is ready.

Once Code Review is approved:
- For a **Medium/High-tier ticket**, invoke the `cadence-maintainer` subagent (following `/cadence-maintain`) against that ticket's isolated worktree and surface the [Human Gate: Maintainer Acceptance] immediately upon completion.
- For a **Low-tier ticket**, there is no Maintainer Acceptance gate (`change-tiers.md`: Code Review is the sole human gate for Low tier); do not invoke `cadence-maintainer` -- Code Review approval clears the ticket directly for Step 6 merge. (While `cadence-maintainer` self-checks tier and declines Low-tier tickets if called, skipping the dispatch here avoids unnecessary overhead.)

**Every follow-up modification requested at either gate (addressing review findings, adding a maintainer changelog entry, or updating `metadata.yaml` timestamps) must be executed by delegating back into the subagent context that owns that ticket's isolated worktree -- never from another ticket's worktree and never directly by a read-only reviewer/maintainer context.** Roles dispatched for evaluation lack safe write ownership of the worktree; always route file mutations back to the worktree's owning implementation context.

### 6. Merge and archive (sequential per ticket, respecting dependencies)

As each ticket clears its final tier-appropriate human gate (Maintainer Acceptance for Medium/High tier; Code Review for Low tier per `docs/policies/change-tiers.md`), merge its isolated worktree branch into the shared integration branch and invoke the `cadence-archivist` subagent (following `/cadence-archive`). Never hold a Low-tier ticket waiting for a Maintainer Acceptance gate that does not exist for its tier. Execute merges in dependency order so that prerequisite tickets land on the integration branch before dependent tickets begin Step 4 implementation.

**Always rebase each ticket's worktree branch onto the latest integration-branch `HEAD` immediately prior to merging, even when the ticket declares zero logical dependencies on sibling tickets.** Concurrent tickets built from the same Step 3 checkpoint frequently touch shared append-only surfaces (`CHANGELOG.md`, `surface-registry.md`, config manifests) simply because they executed in parallel. Once the first ticket in the batch merges into the integration branch, every remaining ticket's branch is behind `HEAD` and can encounter merge conflicts on those shared files. Delegate the rebase and any conflict resolution back to the subagent context owning that ticket's worktree (per Step 5's write-ownership rule) -- resolving shared-file conflicts by preserving both tickets' additions (for example, keeping both `CHANGELOG.md` entries) rather than discarding either side with a blind `--ours` or `--theirs`. After rebasing, re-run the ticket's full test suite in the worktree (routing test output through `offload_log_triage` on `:9379`) to verify everything passes before completing the merge.

### 7. Report

Upon batch completion — and whenever the requester asks for a progress check — display a structured status table with one row per ticket showing its tier, current lifecycle phase, worktree branch, and any pending human gate or dependency blocker. Never allow a ticket to disappear from status reports; if a ticket is waiting on a dependency, paused at a human gate, or halted on an error, state that condition explicitly.

---

## Worked Example (Agentic CLI Runtime)

Delegate each specialist role using the runtime's subagent invocation tool against the compiled `.agents/agents/<role>/AGENT.md` definition (or `.gemini/` for Gemini/Antigravity, or projected `.claude/agents/` per `docs/policies/cli-runtime-adoption-policy.md`). Dispatch independent phases (Steps 1, 2, and per-ticket Step 5 reviews) concurrently so that human gate prompts are surfaced per ticket as soon as each finishes without blocking on slower tickets in the batch.

**Step 3's checkpoint in practice:** commit all tier-approved batch artifacts (`spec.md` and `test-plan.md` for Medium/High; triaged `problem.md` acceptance criteria for Low per `docs/policies/change-tiers.md`), then advance the integration branch (`git -C <integration-branch-checkout> merge --ff-only <batch-branch>`). Attempt `git push` only when remote credentials are permitted in the session -- if a previous push was rejected due to missing SSH keys or policy restrictions, do not loop on alternative credential helpers; report that the checkpoint landed locally and let the operator push when ready.

**Step 4's worktree isolation in practice:** create or request an isolated git worktree (`git worktree add` or `Workspace: "branch"` / `isolation: "worktree"`) for each `cadence-implementer` invocation. Because a newly created worktree checks out the committed branch state rather than uncommitted working-tree files, completing Step 3's checkpoint beforehand is essential. As defense in depth, also pass the absolute path to the coordinating checkout's `specs/<id>/` directory so the implementer can read its spec even if its worktree ref lagged.

**Guarding against the no-op resume trap:** if an isolated worktree subagent returns having made zero commits or file edits, its ephemeral worktree may be automatically pruned. Sending a follow-up message to that same subagent ID can cause it to execute inside the parent checkout's working directory instead of an isolated worktree. Always spawn a brand-new isolated worktree subagent rather than resuming a zero-change session.

**Routing post-review edits safely:** once a `cadence-implementer` subagent has committed changes on its worktree branch, its worktree persists -- send follow-up instructions to that implementer session (or operate explicitly inside its worktree path) for any branch modifications required during review or maintainer acceptance (such as addressing review comments or recording the maintainer's changelog entry). Never instruct the read-only `cadence-reviewer` or `cadence-maintainer` subagent to force commits via low-level git plumbing.

## Example

```
/cadence-parallel PAK-003 PAK-004 PAK-005 PAK-006
```
