# Conflict Resolution & Escalation

When gates disagree — a spec is approved but the maintainer rejects the MR, or two reviewers have opposing views — the process needs a clear escalation path. Without one, conflicts stall work or get resolved by whoever has the most organizational power, not the best argument.

## Principles

1. **Evidence over authority.** The person with the strongest evidence wins, regardless of title. "The trace shows this will deadlock under concurrent writes" beats "I think it's fine" regardless of who says each.
2. **Decisions are recorded.** Every conflict resolution is logged in `specs/{ticket-id}/decisions.md` so future work has context on why a choice was made.
3. **Escalation is not failure.** Disagreement at gates is the system working — it means reviewers are engaging critically. Escalation is the release valve, not a blame mechanism.
4. **Time-box disagreement.** If a conflict cannot be resolved in one synchronous discussion (30 min max), escalate. Extended async back-and-forth erodes velocity and morale.

## Common Conflict Scenarios

### Scenario 1: Spec approved (Gate 1) but MR rejected (Gate 3)

The maintainer rejects an MR for architectural reasons that were baked into the approved spec.

**Root cause:** The spec review didn't catch the architectural issue, or the issue only became visible during implementation.

**Resolution path:**
1. Maintainer documents the concern in `decisions.md` with evidence (ADR conflict, boundary violation, unsustainable pattern)
2. Spec reviewer (Gate 1 approver) is notified and reviews the maintainer's concern
3. If spec reviewer agrees: spec is reopened, revised, and re-approved before implementation continues
4. If spec reviewer disagrees: escalate to the engineering lead (see Escalation Ladder below)

**Key rule:** The maintainer's rejection is not overridden by pointing to the spec approval. The spec approval predates implementation reality — the maintainer may have information the spec reviewer didn't.

### Scenario 2: Two reviewers disagree at the same gate

One reviewer approves, another blocks. Common at Gate 2 (Code Review) with multiple reviewers.

**Resolution path:**
1. The blocker must articulate a specific, evidence-based concern (not "I would have done it differently")
2. The author addresses the concern or explains why the current approach is correct
3. If the blocker is satisfied: unblock
4. If still unresolved after one round of discussion: the reviewer with the most relevant domain expertise makes the call
5. If domain expertise is equal or unclear: escalate to the maintainer gate (it's designed for exactly this — project-level judgment)

**Key rule:** Style preferences are not blocking. The bar for blocking is: "This will break in production," "This violates an ADR," "This creates a maintenance burden the team hasn't agreed to," or "This violates a policy." "I prefer a different abstraction" is a suggestion, not a block.

### Scenario 3: Author disagrees with reviewer

The author believes the reviewer's concern is wrong or the requested change would make things worse.

**Resolution path:**
1. Author responds with evidence: benchmark, trace, example, or reference to prior art
2. Reviewer evaluates the evidence and either withdraws the concern or reaffirms with counter-evidence
3. If agreement: move on
4. If stalemate: bring in a third reviewer (tie-breaker). The third reviewer reads the discussion and picks a side. Their decision stands.
5. If the third reviewer can't decide: escalate to engineering lead

**Key rule:** The author is not automatically wrong because they're the author. They have the deepest context on the change. But they also have the most bias toward shipping it.

### Scenario 4: Change tier dispute

The author claims Low tier; a reviewer says it should be Medium or High.

**Resolution path:**
1. Refer to `docs/policies/change-tiers.md` objective triggers
2. If the triggers clearly indicate a tier: that tier applies, no discussion needed
3. If the triggers are ambiguous (edge case): the reviewer's call stands — err toward more rigor, not less
4. If the author believes the triggers are wrong (the policy needs updating): follow the process at the higher tier now, file an issue to revise the tier policy separately

**Key rule:** Tier disputes are resolved by the triggers, not by negotiation. If the triggers don't clearly resolve it, the higher tier wins.

### Scenario 5: Fast-track payback not completed within 48h

The payback ticket from an emergency fast-track is overdue.

**Resolution path:**
1. Maintainer flags the overdue payback in the next team sync
2. If there's a legitimate reason (another incident, team member out): extend by 48h, once
3. If it's deprioritized by choice: engineering lead intervenes — payback is mandatory, not best-effort
4. If it's blocked by a deeper issue (the fix revealed the system is worse than thought): convert to a proper High-tier spec and prioritize it

## Escalation Ladder

When local resolution fails, escalate in this order:

| Level | Who | When to use | Decision scope |
|---|---|---|---|
| **1. Peer** | Third reviewer (tie-breaker) | Two reviewers disagree | This specific MR |
| **2. Maintainer** | Project maintainer | Code review can't resolve design concern | Architecture within this repo |
| **3. Engineering Lead** | Tech lead / staff engineer | Spec and maintainer disagree, or cross-repo impact | Architecture across repos |
| **4. Architecture Council** | Group of leads (if org has one) | Systemic disagreement about patterns, boundaries, or standards | Org-wide standards |

**Escalation rules:**
- Never skip a level. Level 1 before Level 2 before Level 3.
- Each level has 24 hours to resolve before escalating further.
- The escalation decision (and who made it) is recorded in `decisions.md`.
- Escalation is always to a person, never to a committee (except Level 4). One human, one decision.

## What Doesn't Constitute a Conflict

Not every disagreement needs this process:

- **Suggestions vs. blocks:** A `[SUGGESTION]` comment is not a conflict — it's a recommendation the author can accept or decline without discussion.
- **Style preferences:** "I would have named this differently" is not actionable unless it violates documented conventions.
- **"I don't understand":** This is a request for clarification, not a block. The author explains; the reviewer re-evaluates. If after explanation the reviewer still can't understand the change, THAT is a signal the change needs better documentation (boundary docs, flow docs, or clearer naming).

## Recording Decisions

Every conflict resolution adds an entry to `specs/{ticket-id}/decisions.md`:

```markdown
## Decision: {short title}

**Date:** {YYYY-MM-DD}
**Conflict:** {what disagreed — Gate X approver vs. Gate Y, or Reviewer A vs. Reviewer B}
**Resolution:** {what was decided and why}
**Evidence:** {what evidence determined the outcome}
**Escalation level:** {1-4, or "Resolved at gate"}
**Decided by:** {who made the final call}
```

This ensures the team learns from conflicts and doesn't relitigate the same disagreements.

## Anti-Patterns

- **HiPPO resolution** (Highest-Paid Person's Opinion): If the engineering lead always sides with the senior engineer regardless of evidence, the escalation ladder is broken. Decisions are evidence-based, not rank-based.
- **Conflict avoidance:** Approving to avoid confrontation, then complaining about the code later. If you have a concern, voice it at the gate. Silent approval is full approval.
- **Weaponized process:** Using tier escalation or gate disagreement to slow down work you don't like for political reasons. If the triggers say Low and the evidence says it's safe, blocking on "principle" is not legitimate.
- **Relitigating settled decisions:** If `decisions.md` records a resolution, it's settled. New evidence can reopen it (add a new decision entry with reversal context), but "I still disagree" without new evidence does not.
