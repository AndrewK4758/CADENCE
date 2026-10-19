---
name: claire-parallel
description: Run the full triage-to-archive SDLC pipeline across multiple related tickets concurrently, with safe git isolation for parallel implementation
argument-hint: "<ticket-id-1> [ticket-id-2] [ticket-id-3] ..."
arguments: [ticket_ids]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---


## Task

Run the standard workflow (Problem -> Triage -> Spec -> [Human Gate: Spec Approval] -> Implementation -> [Human Gate: Code Review] -> [Human Gate: Maintainer Acceptance] -> Merge -> Archive) across every ticket in `$ticket_ids` at once, dispatching independent work concurrently instead of one ticket at a time. Each phase still delegates to the same role the single-ticket skills use (`claire-triage-agent` subagent, `claire-architect` subagent, `claire-explorer` subagent, `claire-spec-author` subagent, `claire-implementer` subagent, `claire-reviewer` subagent, `claire-maintainer` subagent, `claire-archivist` subagent) -- this skill only changes the *fan-out and sequencing*, not what any role does. Each ticket follows its own tier's path through that workflow per `docs/policies/change-tiers.md`: a Medium/High-tier member runs every phase and gate above, while a Low-tier member skips Spec authoring and has no Spec Approval or Maintainer Acceptance gate -- it routes triage -> implementation -> [Human Gate: Code Review] -> merge, its sole human gate being Code Review. The per-step routing below is tier-conditional accordingly.

Human gates remain mandatory and per-ticket: surface each ticket's gate decision to the requester as soon as that ticket reaches it, independent of how far along the other tickets are. Do not batch gate decisions together unless the requester asks you to.

## Prerequisites

- Every id in `$ticket_ids` must resolve to either an existing `specs/<id>/problem.md` or a description the `claire-triage-agent` subagent can triage fresh.
- A clean-enough working tree to commit a checkpoint before implementation begins (step 3). If the tree has unrelated in-flight changes that do not belong to this batch, ask the requester how to proceed rather than commit them.

## Cross-ticket dependencies

Before dispatching implementation (step 4), check each ticket's `problem.md` and `metadata.yaml` for an explicit dependency note (a Constraints/Dependencies line naming another ticket in `$ticket_ids`, or an equivalent tag). A ticket with an unresolved dependency on another ticket in this batch still triages and specs normally, but its **implementation phase waits** until the dependency reaches `merged` status. State this explicitly whenever reporting that ticket's status -- never hold it silently.

## Steps

### 1. Triage (concurrent, no isolation needed)

For each ticket in `$ticket_ids`, delegate to the `claire-triage-agent` subagent exactly as `/claire-triage` does. These delegations are independent -- each reads/writes only its own `specs/<id>/` directory -- so dispatch them concurrently rather than one at a time.

For any ticket the triage-agent flags as Medium/High tier with unfilled probes, offer the `/claire-elicit` interview (as `/claire-triage` step 5 describes) before moving that ticket to step 2. A requester who declines the interview for a given ticket is choosing to let the `claire-spec-author` subagent infer and flag assumptions instead (step 2) -- confirm that reading, then proceed.

### 2. Spec authoring (concurrent, no isolation needed)

Resolve each triaged ticket's `tier:` from its `metadata.yaml` first, and route on it -- this step's spec-authoring runs only for Medium/High-tier members:

- Low tier -> do NOT dispatch the `claire-spec-author` subagent (nor the `claire-architect` subagent pre-flight, which by definition cannot apply below High tier). A Low-tier ticket produces no `spec.md` by policy (`docs/policies/change-tiers.md`: Low = `problem.md` acceptance criteria only, no Spec authoring, no Spec Approval gate); route it directly from step 1 (Triage) to step 4 (Implementation), matching the single-ticket Low workflow (`triage -> skip /claire-spec -> /claire-implement -> /claire-review`). Record it as "Low tier -- routed straight to implementation" in status.
- Medium/High tier -> run the High-tier `claire-architect` subagent pre-flight first if its tier is High, then delegate to the `claire-spec-author` subagent exactly as `/claire-spec` does. **Doing it "exactly as `/claire-spec` does" means the `claire-explorer` subagent runs FIRST** -- delegate to the `claire-explorer` subagent and let it produce that ticket's `specs/<id>/design-options.md` *before* the `claire-spec-author` subagent is dispatched, never after and never in parallel. The explorer is a step of *this* skill, never a sub-call the spec-author makes internally: an agent that can generate its own options can also launder the appearance of having considered them. Tier gating is **inherited, not re-implemented** -- this arm is the only one that reaches the explorer, so no `design-options.md` is produced for a Low or Trivial member. If the explorer cannot run for a given ticket, report that failure and ask whether to proceed without exploration for that ticket; if the requester chooses to proceed, the spec-author records the explicit **not-performed marker** and that ticket's spec discloses the gap. **Never skip this silently**, and never let one member's explorer failure decide the question for the rest of the batch.
- Trivial tier -> not applicable to this pipeline: Trivial work needs no agent phase (`change-tiers.md`: no spec-author, implementer, code-reviewer, or maintainer). Report it and handle it outside `/claire-parallel`; dispatch no role for it.
- Tier absent, empty, or unrecognized (any value outside {Trivial, Low, Medium, High}) -> do NOT guess the route. Hold that member, report the unresolved tier value verbatim, and ask that a valid `tier:` be set (or `/claire-triage` re-run) before it proceeds. NEVER assume Low -- silently routing an unresolved-tier ticket straight to implementation would skip a spec and gates a Medium/High ticket requires. Other batch members continue unaffected.

Dispatch concurrently -- spec-authoring only touches each ticket's own `specs/<id>/` directory plus shared reference docs (e.g. a surface registry) that are additive, not conflicting, across tickets in the normal case.

If the architect or spec-author surfaces a decision that is genuinely the requester's to make (an architectural fork, a scope question, a security-relevant tradeoff) rather than a matter of executing the ticket's own stated intent, ask before the spec is finalized -- do not let an agent silently pick between materially different designs on the requester's behalf.

### 3. Checkpoint before implementation (mandatory, blocking)

**Do this once per batch, after every Medium/High-tier ticket moving to implementation has cleared its Spec Approval gate below, and every Low-tier ticket has its triaged `problem.md` acceptance criteria committed (a Low-tier ticket has no Spec Approval gate) -- never skip it.** Isolated implementation worktrees are cloned from the shared integration branch (the branch bound by `CLAIRE_ORG.md#branch-strategy-binding`); if that branch does not yet contain each ticket's tier-approved artifacts (the approved spec at Medium/High tier; the triaged `problem.md` acceptance criteria at Low tier, per `docs/policies/change-tiers.md`), an implementer working in isolation will find nothing to implement against and either stall or -- worse -- invent a design no one approved.

1. Commit every outstanding artifact change belonging to this batch, scoped to each member's tier: for a Medium/High member, its `problem.md` updates, `metadata.yaml`, `spec.md`, `test-plan.md`, `decisions.md`; for a Low member, its `problem.md` (the approved acceptance criteria), `metadata.yaml`, and `decisions.md` if present (no `spec.md`/`test-plan.md` exist at Low tier by policy); plus any shared docs touched.
2. Merge that commit into the shared integration branch (fast-forward if possible).
3. If the environment supports pushing to a remote, push. If it does not, proceed with the local merge and tell the requester that any implementation worktree must be seeded from the local merge, not a remote checkout.

Present each Medium/High-tier ticket's [Human Gate: Spec Approval] before folding it into this checkpoint -- an unapproved ticket's spec should not enter the shared branch a batch of implementers will clone from. A Low-tier ticket has no Spec Approval gate to present (`change-tiers.md`); the checkpoint folds in its triaged, approved `problem.md` acceptance criteria (plus `metadata.yaml` and `decisions.md` if present) instead, consistent with the tier-appropriate artifact framing the Stale-Seed Worktree section of `docs/guides/parallel-sdlc-usage.md` establishes for step 4.

### 4. Implementation (concurrent, isolated per ticket)

For each approved, unblocked ticket (see Cross-ticket dependencies), delegate to the `claire-implementer` subagent exactly as `/claire-implement` does, with one addition: **each ticket's implementation happens in its own isolated worktree**, branched from the trunk state established in step 3 -- never share one worktree across two tickets' implementations running at the same time, since they may touch overlapping files.

Two failure modes to guard against explicitly:

- **A ticket's isolated worktree was seeded before step 3's checkpoint landed, or from a stale base.** If the `claire-implementer` subagent reports it cannot find its ticket's tier-approved artifacts (the approved spec at Medium/High tier; the triaged `problem.md` acceptance criteria at Low tier, per `docs/policies/change-tiers.md`) in its own worktree, do not let it guess or fabricate one. Point it at the authoritative spec location (wherever step 3 committed it) and let it re-read from there, or restart it in a freshly-seeded worktree if the first one already diverged.
- **Never resume a delegated implementation context that made zero changes.** If an attempt stops having written nothing (blocked, errored, or otherwise), treat that as a clean failure: diagnose why, fix the actual blocker (usually a missing/stale spec per the point above), and start over in a fresh isolated worktree rather than continuing the same context -- a no-op run's isolated worktree may not persist, and continuing it can silently fall back to write access somewhere unintended.

### 5. Code review and Maintainer acceptance (concurrent, per ticket)

For each implemented ticket, delegate to the `claire-reviewer` subagent exactly as `/claire-review` does, working against that ticket's own isolated worktree. Present the [Human Gate: Code Review] as soon as it's ready.

On approval, for a Medium/High-tier ticket, delegate to the `claire-maintainer` subagent exactly as `/claire-maintain` does, again against that ticket's own isolated worktree, and present the [Human Gate: Maintainer Acceptance] as soon as it's ready. A Low-tier ticket has no Maintainer Acceptance gate (`change-tiers.md`: Low = Code Review as the sole human gate); do not dispatch the `claire-maintainer` subagent for it -- Code Review approval is its final gate before merge (step 6). (Even if dispatched anyway, the `claire-maintainer` subagent self-defends and declines at Low tier, but routing it correctly here avoids a bogus dispatch.)

**Any follow-up edit requested at either gate (a review comment folded in, a maintainer-drafted changelog entry, a metadata timestamp) must be made by delegating back into that same ticket's own isolated worktree -- never from a different ticket's context, and never by the reviewing/accepting role itself unless it already holds write access there.** A role that only read a worktree to evaluate it does not thereby gain safe write access to it; route the edit to whichever role's context owns that worktree.

### 6. Merge and archive (sequential per ticket, respecting dependencies)

Once a ticket clears its final human gate, merge its isolated worktree's branch into the shared integration branch, then delegate to the `claire-archivist` subagent exactly as `/claire-archive` does. The final gate is tier-dependent (`change-tiers.md`): a Medium/High-tier ticket merges once it clears Maintainer Acceptance; a Low-tier ticket has no Maintainer Acceptance gate and merges once it clears Code Review (its sole human gate, from step 5) -- do not wait on a Maintainer Acceptance a Low-tier ticket can never produce. Merge tickets in dependency order -- a ticket other batch members depend on should merge before those dependents' implementation phase begins.

**Rebase each ticket's branch onto the current integration-branch tip immediately before merging it, even when it has no declared dependency on any other ticket in the batch.** Two independent tickets that both finish implementation in the same window will often have both edited the same shared file (a changelog, a config manifest, a registry doc) purely because both were built against the trunk state as it stood *before either one merged* -- this is a routine consequence of running several tickets concurrently, not a sign anything went wrong. Once the first ticket in the batch merges, every other ticket still implementing is now stale relative to trunk and may conflict on merge even with zero logical relationship to what just landed. Route the rebase and any conflict resolution back to the role/context that owns that ticket's worktree (per step 5's routing rule) -- resolve conflicts by keeping both sides' contributions (e.g. both tickets' changelog entries as separate entries), never a wholesale "ours" or "theirs" that silently drops a landed ticket's work. Re-run that ticket's test suite after the rebase before merging.

### 7. Report

At the end of the batch, and at any point the requester asks for status, report a table: one row per ticket, its current phase, and what (if anything) is waiting on a human decision. Never let a ticket go silent -- if it's blocked, waiting, or failed, say so plainly rather than letting it drop out of the status picture.

---

## Worked Example (Claude Code)

Dispatch each role delegation as an `Agent` tool call using the compiled `.claude/agents/<role>/AGENT.md` (e.g. `subagent_type: "implementer"`). Independent delegations (steps 1, 2, and the review/maintainer pass in step 5 across different tickets) are issued as separate `Agent` calls -- either several in one message, or as background agents (`run_in_background: true`) so gate decisions can be surfaced per ticket as they land, without waiting on the slowest ticket in the batch.

**Step 3's checkpoint, concretely:** commit each ticket's tier-approved artifacts (the approved `spec.md`/`test-plan.md` at Medium/High tier; the triaged `problem.md` acceptance criteria at Low tier, per `docs/policies/change-tiers.md`), then `git -C <integration-branch-checkout> merge --ff-only <batch-branch>`. Attempt a `git push` only if credentials are actually available in the environment -- if a prior push attempt in the session was denied (e.g. missing SSH identity, or an auto-mode policy block), do not retry it via a different credential path; report the local-merge-only state to the requester and let them push manually.

**Step 4's isolation, concretely:** use the `Agent` tool's `isolation: "worktree"` parameter for each ticket's `claire-implementer` call. This creates a fresh worktree branched from `origin/<default-branch>` -- it does **not** inherit the invoking session's own uncommitted or unpushed state. This is exactly why step 3 must land first. As defense in depth even after checkpointing, still tell each implementer the absolute path to the coordinating worktree's `specs/<id>/` directory as a fallback read location, in case its own worktree's base predates the checkpoint.

**The no-op-resume trap, concretely:** if an `Agent` call with `isolation: "worktree"` returns having made no file changes, its worktree is liable to be cleaned up automatically. Resuming that `agentId` later via `SendMessage` can silently fall back to write access in the coordinating session's own worktree instead -- which the auto-mode classifier will then (correctly) block as an attempt to mutate a workspace the resumed context does not own. Launch a brand-new `Agent` call with `isolation: "worktree"` again instead of resuming.

**Routing follow-ups, concretely:** once an `claire-implementer` agent has committed real work, its `agentId` and worktree persist -- resume it via `SendMessage` for any edit that belongs on its branch (folding in review feedback, writing a maintainer-drafted changelog entry). Do not ask the `claire-reviewer` or `claire-maintainer` agent to make that commit itself; they were dispatched without write access to that worktree, and reaching for low-level git plumbing to force it is exactly the kind of action the auto-mode classifier exists to stop.

## Example

```
/claire-parallel PAK-003 PAK-004 PAK-005 PAK-006
```
