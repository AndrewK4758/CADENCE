---
name: cadence-parallel
description: Execute the end-to-end triage-to-archive CADENCE pipeline concurrently across multiple tickets using isolated git worktrees and optional local coprocessor offload (:11434, cloud fallback when absent) for parallel implementation and review.
argument-hint: "<ticket-id-1> [ticket-id-2] [ticket-id-3] ..."
arguments: [ticket_ids]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---


## Task

Drive the complete CADENCE lifecycle (Problem -> Triage -> Spec -> [Human Gate: Spec Approval] -> Implementation -> [Human Gate: Code Review] -> [Human Gate: Maintainer Acceptance] -> Merge -> Archive) across all tickets in `$ticket_ids` concurrently, fanning out independent per-ticket work in parallel rather than serially. Every lifecycle phase delegates to the exact same specialized subagent used by the single-ticket skills (`cadence-triage-agent` subagent, `cadence-architect` subagent, `cadence-explorer` subagent, `cadence-spec-author` subagent, `cadence-implementer` subagent, `cadence-reviewer` subagent, `cadence-security-auditor` subagent when triggered, `cadence-maintainer` subagent, `cadence-archivist` subagent) -- this skill governs *concurrent fan-out, worktree isolation, and sequencing*, without altering any individual role's responsibilities. Each ticket traverses the path mandated by its assigned change tier in `docs/policies/change-tiers.md`: a Medium or High-tier ticket executes every phase and human gate above, whereas a Low-tier ticket bypasses Spec authoring as well as the Spec Approval and Maintainer Acceptance gates -- advancing along `triage -> implementation -> [Human Gate: Code Review] -> merge`, with Code Review serving as its single human gate. Each step below routes tickets conditionally according to their tier.

Human approval gates remain strictly mandatory and evaluated per ticket: present each ticket's gate decision to the requester immediately upon that ticket reaching the gate, regardless of the progress of sibling tickets in the batch. Never bundle gate approvals across tickets unless explicitly requested by the user.

## Prerequisites

- Every identifier in `$ticket_ids` must map either to an existing `specs/<id>/problem.md` or to a raw problem statement that the `cadence-triage-agent` subagent can triage from scratch.
- The working tree must be clean enough to record a synchronization checkpoint commit prior to launching implementation worktrees (Step 3). If unrelated uncommitted modifications exist in the working tree, ask the requester how to handle them rather than sweeping them into the batch checkpoint.

## Cross-ticket dependencies

Prior to launching implementation worktrees (Step 4), inspect each ticket's `problem.md` and `metadata.yaml` for declared dependencies (such as a Constraints/Dependencies entry referencing another ticket in `$ticket_ids`, or an equivalent dependency link). A ticket that depends on another ticket in the current batch still completes Triage and Spec authoring concurrently, but its **implementation phase is held** until the prerequisite ticket reaches `merged` status. Always report this dependency hold explicitly in status updates -- never stall a ticket silently.

## Steps

### 1. Triage (concurrent, no isolation needed)

For every ticket in `$ticket_ids`, invoke the `cadence-triage-agent` subagent following the exact `/cadence-triage` protocol. Because each triage run reads and writes exclusively within its own `specs/<id>/` directory (with optional `local_semantic_embed` / `repo-scout` on `:11434` when reachable, else cloud-only `Grep`/`Glob`), dispatch all triage subagents concurrently rather than sequentially.

For any ticket classified as Medium or High tier with unanswered elicitation probes, offer the interactive `/cadence-elicit` interview (per `/cadence-triage` Step 5) before advancing that ticket to Step 2. If the requester declines the interview for a specific ticket, leave unresolved probes transparently flagged so `cadence-spec-author` surfaces them under `## Open Questions` (and `certainty-gate.sh` handles escalation at Gate 1) rather than inventing silent assumptions.

### 2. Spec authoring (concurrent, no isolation needed)

Read each triaged ticket's `tier:` field from `specs/<id>/metadata.yaml` and route strictly by tier -- Spec authoring in this step applies only to Medium and High-tier tickets:

- **Low tier** -> do NOT invoke `cadence-explorer`, `cadence-architect`, or `cadence-spec-author`. By policy (`docs/policies/change-tiers.md`), a Low-tier ticket relies solely on its `problem.md` acceptance criteria without a `spec.md` or Spec Approval gate; advance it from Step 1 (Triage) via a `triage/{type}/{id}` capture PR checkpoint to Step 4 (Implementation), mirroring the single-ticket Low path (`triage -> skip /cadence-spec -> /cadence-implement -> /cadence-review`). Log its status as "Low tier -- routed straight to implementation".
- **Medium/High tier** -> follow `/cadence-spec` strictly in order: dispatch `cadence-explorer` FIRST so it writes `specs/<id>/design-options.md`, then run pre-flight `cadence-architect` (**mandatory at `tier: High`, opt-in at `tier: Medium`** per `docs/policies/change-tiers.md`), then delegate to `cadence-spec-author` passing `design-options.md` and `cadence-architect` findings. Divergent exploration is an explicit orchestration step of *this* skill, never an internal sub-call inside `cadence-spec-author` (since an agent that invents its own alternatives could tailor them to justify a predetermined choice). Tier gating is **inherited directly from this branch** -- only Medium and High tickets enter this arm, ensuring no `design-options.md` is generated for Low or Trivial tickets. If `cadence-explorer` fails on a particular ticket, surface the error and ask the requester whether to proceed without exploration for that ticket; if confirmed, `cadence-spec-author` records the explicit **not-performed marker** and notes the omission in `spec.md`. **Never bypass exploration silently**, and never apply one ticket's exploration waiver across other tickets in the batch.
- **Trivial tier** -> outside the scope of `/cadence-parallel`: Trivial changes require no agent lifecycle phases (`change-tiers.md`: no spec-author, implementer, reviewer, or maintainer). Report the Trivial classification and handle it outside this pipeline without dispatching subagents.
- **Tier missing, blank, or invalid** (anything other than `{Trivial, Low, Medium, High}`) -> never guess the tier. Pause that specific ticket, output the invalid or missing `tier:` value verbatim, and request that a valid `tier:` be recorded (or `/cadence-triage` re-run) before advancing it. **Never default to Low** -- silently routing an untiered ticket to implementation would bypass mandatory specification and human approval gates required for Medium/High work. Remaining tickets in the batch continue normally.

Run all eligible Spec authoring delegations in parallel -- each writes to its own `specs/<id>/` directory and makes only additive updates to shared registries (such as `docs/policies/cadence-surfaces.md`).

Whenever `cadence-architect` or `cadence-spec-author` returns a clarification question or genuine product/architectural fork belonging to the human requester (such as a scope boundary, security posture tradeoff, or breaking contract decision), pause that ticket in this orchestrator turn and ask the requester before finalizing its spec -- subagents stay headless.

### 3. Checkpoint before implementation (mandatory, blocking; PR-gated on protected branches)

**Execute this checkpoint before spawning implementation worktrees -- never bypass it.** Because each isolated implementation worktree branches off `origin/<integration-branch>` (`CADENCE_ORG.md#branch-strategy-binding`), if `<integration-branch>` lacks a ticket's approved artifacts (`spec.md`, `test-plan.md`, `decisions.md`, `submission.md` for Medium/High; `problem.md` acceptance criteria + `metadata.yaml` for Low), an isolated implementer worktree will start without its governing contract.

1. For each Medium/High ticket that cleared `[Human Gate: Spec Approval]` (with `status: spec-approved` and `spec_approved_at` recorded in the branch commit) and each Low ticket requiring capture, commit its artifacts on `spec/{type}/{id}` (or `triage/{type}/{id}` at Low), push, and open/publish its spec/triage PR targeting `<integration-branch>`.
2. **Stop before spawning `impl/` worktrees until those spec/triage PRs are merged remotely onto `origin/<integration-branch>`** (never push direct commits or local batch merges straight onto a protected `<integration-branch>`). Local fast-forward checkpoint merges are permitted **only** in explicitly unprotected local-only repositories with no remote integration branch.

Wait for explicit Gate 1 approval and remote merge (then `git fetch` / `--ff-only` pull local `<integration-branch>`) before branching implementation worktrees for that ticket; per `.agents/skills/cadence-build/references/worktree-and-ledger.md`, unmerged specs must never seed `impl/` worktrees.

### 4. Implementation (concurrent, isolated per ticket, with optional local log triage)

For every approved, dependency-unblocked ticket whose spec/triage PR has landed on `origin/<integration-branch>`, dispatch `cadence-implementer` following `/cadence-implement`, with two parallel-execution safeguards:
1. **Dedicated worktree isolation:** every ticket's implementation runs inside its own dedicated git worktree branched from the updated `origin/<integration-branch>` checkpoint ref -- never share a single worktree between concurrent ticket implementations, as overlapping file edits will corrupt both runs.
2. **Optional local test/build log offload (`:11434`, cloud fallback when absent):** across concurrent worktree test and build executions during Red-Green-Refactor TDD cycles, when `:11434` is reachable, pipe test runner, compiler, and linter logs `>30` lines through `offload_log_triage` (`inference` on `:11434`, or `log-triage`) to compact logs to verbatim assertions, metrics, and `file:line` coordinates (raw output in `/tmp/agy-last-triage.log`; degrade cleanly to direct inspection when offline).

Guard explicitly against two worktree failure modes:

- **Worktree branched prior to Step 3's checkpoint or from a stale ref.** If a `cadence-implementer` subagent reports that its ticket's governing artifacts (`spec.md` at Medium/High tier; `problem.md` acceptance criteria at Low tier per `docs/policies/change-tiers.md`) are missing in its worktree, forbid it from guessing or synthesizing requirements. Provide the absolute path to the committed specification in the primary checkout so it can read from there, or terminate and re-create its worktree from the updated integration branch tip.
- **Never resume an implementation subagent context that produced zero file modifications.** When a delegated implementation attempt exits without having written or committed anything (due to a blocker, missing spec, or tool error), treat that context as terminated: diagnose and resolve the underlying cause, then launch a fresh subagent in a newly created worktree rather than messaging the no-op subagent context -- an untouched worktree may have been garbage-collected, causing a resumed session to fall back to the parent checkout's working directory.

### 5. Code review and Maintainer acceptance (concurrent, per ticket, with optional local pre-review offload)

As each ticket completes implementation in its isolated worktree:
1. **Optional local pre-review scan (`:11434`):** when `:11434` is reachable, before invoking `cadence-reviewer`, run `offload_deep_review` (`inference` on `:11434`) against that ticket's worktree diff as an advisory mechanical pre-scan checking the `<400`-line file ceiling, comment discipline, Engineering Pillars, and CHORD observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).
2. **Reviewer & security-auditor delegation:** invoke `cadence-reviewer` (and concurrently `cadence-security-auditor` at `xhigh` effort when `security-trigger.sh <ticket-id>` outputs `decision=TRIGGER` on `High` tier or risk-matched `Low`/`Medium` diffs) against the ticket's isolated worktree, passing any `offload_deep_review` pre-scan and `verify-facts.sh --trace` findings. Merge any security/concurrency findings into `submission.md` via `/cadence-review` Step 5 and surface `[Human Gate: Code Review]` to the requester as soon as review is ready.

Once Code Review is approved:
- For a **Medium/High-tier ticket**, invoke `cadence-maintainer` (via `/cadence-maintain` Gate 3) against that ticket's isolated worktree. Because `cadence-maintainer` is strictly read-only and headless, `/cadence-parallel` / `/cadence-maintain` collects the human `Accept` | `Postpone` | `Reject` ruling and writes all approved post-decision metadata/changelog/decision updates in the ticket's owning worktree!
- For a **Low-tier ticket**, there is no Maintainer Acceptance gate (`change-tiers.md`: Code Review is the sole human gate for Low tier); do not invoke `cadence-maintainer` -- Code Review approval clears the ticket directly for Step 6 merge.

**Every follow-up code or metadata modification requested at either gate must execute in that ticket's owning implementation worktree (via `cadence-implementer` or top-level `/cadence-maintain` / `/cadence-review`) -- never from another ticket's worktree and never directly from read-only `cadence-reviewer`, `cadence-security-auditor`, or `cadence-maintainer`.**

### 6. Merge and archive (sequential per ticket, respecting dependencies)

As each ticket clears its final tier-appropriate human gate (Maintainer Acceptance for Medium/High tier; Code Review for Low tier per `docs/policies/change-tiers.md`), land it via `/cadence-merge` (never pushing direct commits onto protected `<integration-branch>`) and finalize via `/cadence-archive` (`cadence-archivist` in its `archive/{type}/{id}` PR). Execute merges in dependency order so prerequisite tickets land on `origin/<integration-branch>` before dependent tickets start Step 4 implementation.

**Always rebase each ticket's worktree branch onto the latest `origin/<integration-branch>` immediately prior to merging, even when the ticket declares zero logical dependencies on sibling tickets.** Concurrent tickets built from the same checkpoint frequently touch shared append-only surfaces (`CHANGELOG.md`, surface registries) simply because they executed in parallel. Delegate rebase and conflict resolution to the owning implementation worktree (preserving both tickets' append-only additions rather than blind `--ours`/`--theirs`). After rebasing, re-run the ticket's full test suite (routing >30-line output through `offload_log_triage` when `:11434` is reachable); **whenever rebase resolved code/test conflicts OR upstream commits modified files in the diff's bounded context/dependencies, re-run `/cadence-review` before completing the merge**.

### 7. Report

Upon batch completion — and whenever the requester asks for a progress check — display a structured status table with one row per ticket showing its tier, current lifecycle phase, worktree branch, and any pending human gate or dependency blocker. Never allow a ticket to disappear from status reports; if a ticket is waiting on a dependency, paused at a human gate, or halted on an error, state that condition explicitly.

- **Batch Watch Handoff Prompt:** `/cadence-parallel` owns the watch prompt for the batch (suppressing per-ticket inner prompts from delegated stages). Whenever one or more batch tickets have open `spec_mr` or `merge_request` PRs awaiting human gate review/merge and an interactive operator is present, ask whether to invoke `/cadence-watch --all` (`watch` = `--watch` live poll / `once` = `--once` single check / `no` = stop here) or `/cadence-watch <TICKET-ID>` for a single ticket, invoking `/cadence-watch` only on explicit confirmation (skip when unattended or when every batch ticket is archived) and never auto-polling silently.

---

## Worked Example (Agentic CLI Runtime)

Delegate each specialist role using the runtime's subagent invocation tool against `.agents/agents/<role>/agent.md`, preserving each agent's declared capability tier and reasoning effort in `CADENCE_ORG.md#model-tier-mapping` (`Deep-reasoning` at `xhigh` effort for `cadence-architect`, `cadence-explorer`, `cadence-spec-author`, `cadence-implementer` across all tiers, `cadence-migration-author`, `cadence-reviewer`, `cadence-security-auditor`, and `cadence-maintainer`; `Fast-mechanical` at `high` effort for `cadence-triage-agent` and `cadence-archivist`; `local-coprocessor` for `log-triage` and `repo-scout`). Project `.gemini/` or `.claude/agents/` per `docs/policies/cli-runtime-adoption-policy.md`, and dispatch independent phases (Steps 1, 2, and per-ticket Step 5 reviews) concurrently so that human gate prompts are surfaced per ticket as soon as each finishes without blocking on slower tickets in the batch.

**Step 3's checkpoint in practice:** commit each ticket's tier-approved artifacts (`problem.md`, `spec.md`, `test-plan.md`, `design-options.md`, `decisions.md`, `submission.md` for Medium/High; `problem.md` + `metadata.yaml` for Low) on `spec/{type}/{id}` / `triage/{type}/{id}`, open/merge the spec/triage PR onto `origin/<integration-branch>`, and run `git pull --ff-only` in local `<integration-branch>` before branching implementation worktrees. Local `--ff-only` checkpoint merges directly onto `<integration-branch>` are reserved strictly for local-only repositories with no remote protection.

**Step 4's worktree isolation in practice:** create or request an isolated git worktree (`git worktree add` or `Workspace: "branch"` / `isolation: "worktree"`) for each `cadence-implementer` invocation. Because a newly created worktree checks out the committed branch state rather than uncommitted working-tree files, completing Step 3's checkpoint beforehand is essential. As defense in depth, also pass the absolute path to the coordinating checkout's `specs/<id>/` directory so the implementer can read its spec even if its worktree ref lagged.

**Guarding against the no-op resume trap:** if an isolated worktree subagent returns having made zero commits or file edits, its ephemeral worktree may be automatically pruned. Sending a follow-up message to that same subagent ID can cause it to execute inside the parent checkout's working directory instead of an isolated worktree. Always spawn a brand-new isolated worktree subagent rather than resuming a zero-change session.

**Routing post-review edits safely:** once a `cadence-implementer` subagent has committed changes on its worktree branch, its worktree persists -- send follow-up instructions to that implementer session (or operate explicitly inside its worktree path) for any branch modifications required during review or maintainer acceptance (such as addressing review comments or recording the maintainer's changelog entry). Never instruct the read-only `cadence-reviewer`, `cadence-security-auditor`, or `cadence-maintainer` subagent to force commits via low-level git plumbing.

## Example

```
/cadence-parallel PAK-003 PAK-004 PAK-005 PAK-006
```
