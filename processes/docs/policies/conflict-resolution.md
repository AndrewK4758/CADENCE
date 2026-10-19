# Conflict Resolution & Escalation

When governance gates reach conflicting conclusions — for example, a specification passes Gate 1 approval but the maintainer rejects the implementation MR at Gate 3, or two reviewers hold opposing views at Gate 2 — the workflow requires a deterministic escalation path. Without an explicit protocol, disagreements either stall delivery or get settled by organizational hierarchy rather than engineering evidence.

## Principles

1. **Evidence over authority.** The argument backed by verifiable evidence prevails regardless of seniority or title. "The concurrency trace demonstrates a deadlock when two workers write simultaneously" outweighs "I think the locking is fine" no matter who states each position.
2. **Decisions are recorded.** Every resolved disagreement is appended to `specs/{ticket-id}/decisions.md` so future contributors and agents can inspect the exact rationale and evidence behind the outcome.
3. **Escalation is not failure.** Disagreement at review gates indicates the governance model is functioning as intended — reviewers are critically evaluating changes. Escalation serves as a structured release valve, not a mechanism for blame.
4. **Time-box disagreement.** If a technical conflict cannot be settled within a single synchronous conversation (30 minutes maximum), escalate immediately. Prolonged asynchronous back-and-forth drains delivery momentum and team morale.

## Common Conflict Scenarios

### Scenario 1: Spec approved (Gate 1) but MR rejected (Gate 3)

The maintainer rejects an implementation MR on architectural grounds that were already present in the approved specification.

**Root cause:** The Gate 1 spec review missed an architectural constraint, or the structural problem only became apparent once translated into concrete code.

**Resolution path:**
1. The maintainer records the architectural concern in `decisions.md` backed by concrete evidence (ADR contradiction, bounded-context violation, or unsustainable coupling pattern).
2. The Gate 1 spec reviewer is notified and evaluates the maintainer's documented concern.
3. If the spec reviewer concurs: the specification is reopened, revised, and re-approved before implementation resumes.
4. If the spec reviewer disagrees: escalate to the engineering lead (see Escalation Ladder below).

**Key rule:** A maintainer's rejection at Gate 3 cannot be overruled simply by pointing to prior Gate 1 approval. Spec approval predates implementation reality — the maintainer often sees system-level interactions that were not obvious at spec review time.

### Scenario 2: Two reviewers disagree at the same gate

One reviewer approves while another raises a blocking finding — most commonly at Gate 2 (Code Review) when multiple reviewers participate.

**Resolution path:**
1. The blocking reviewer must state a specific, evidence-backed defect or policy violation (never "I would have structured this differently").
2. The author either remedies the issue or provides evidence demonstrating why the current implementation is sound.
3. If the blocking reviewer is satisfied: the block is lifted.
4. If the disagreement persists after one round of exchange: the reviewer with deeper domain expertise in the affected subsystem makes the call.
5. If domain expertise is equal or ambiguous: escalate to the Maintainer gate (Gate 3), which exists specifically to exercise project-wide architectural judgment.

**Key rule:** Personal style preferences are never blocking. A valid block requires demonstrating that: "This will fail in production," "This contradicts a ratified ADR," "This introduces an unapproved operational burden," or "This violates a normative policy." "I prefer an alternative abstraction" is a non-blocking suggestion, never a block.

### Scenario 3: Author disagrees with reviewer

The author believes a reviewer's blocking finding is factually mistaken or that the requested modification would degrade the design.

**Resolution path:**
1. The author replies with concrete evidence: a benchmark, execution trace, reproduction test, or citation to ratified prior art.
2. The reviewer evaluates the evidence and either withdraws the block or reaffirms it with counter-evidence.
3. If consensus is reached: proceed.
4. If deadlocked: bring in a third reviewer as a tie-breaker. The third reviewer inspects the written thread, weighs the evidence, and selects one position. That ruling stands.
5. If the tie-breaker cannot reach a clear verdict: escalate to the engineering lead.

**Key rule:** An author is not automatically wrong merely by being the author — they possess the deepest immediate context on the change. However, they also carry the strongest natural bias toward shipping their work.

### Scenario 4: Change tier dispute

The author classifies a change as Low tier, while a reviewer argues it triggers Medium or High tier requirements.

**Resolution path:**
1. Consult the objective trigger tables in `docs/policies/change-tiers.md`.
2. If the objective triggers unambiguously match a tier: that tier governs immediately without further debate.
3. If a genuine boundary ambiguity exists: the reviewer's higher-tier classification prevails — always err toward greater verification rigor rather than less.
4. If the author believes the policy triggers themselves are flawed: comply with the higher tier for the current ticket, and file a separate follow-up issue proposing an amendment to `change-tiers.md`.

**Key rule:** Tier disputes are settled by evaluating objective diff triggers, never by bargaining. Whenever trigger evaluation is genuinely ambiguous, the higher tier wins.

### Scenario 5: Fast-track payback not completed within 48h

The mandatory retroactive payback ticket following an emergency fast-track deployment has breached its 48-hour SLA.

**Resolution path:**
1. The maintainer surfaces the overdue payback ticket at the next team synchronization.
2. If a legitimate operational blocker prevented completion (e.g., a secondary production incident or responder absence): grant a single 48-hour extension.
3. If payback was deprioritized in favor of routine feature work: the engineering lead intervenes — fast-track payback is a mandatory governance obligation, not best-effort cleanup.
4. If payback revealed that the underlying subsystem is more fragile than understood during the incident: promote the payback ticket into a full High-tier specification and prioritize its delivery.

## Escalation Ladder

When gate-level resolution does not settle a dispute, escalate sequentially through these levels:

| Level | Who | When to use | Decision scope |
|---|---|---|---|
| **1. Peer** | Third reviewer (tie-breaker) | Two reviewers disagree | This specific MR |
| **2. Maintainer** | Project maintainer | Code review can't resolve design concern | Architecture within this repo |
| **3. Engineering Lead** | Tech lead / staff engineer | Spec and maintainer disagree, or cross-repo impact | Architecture across repos |
| **4. Architecture Council** | Group of leads (if org has one) | Systemic disagreement about patterns, boundaries, or standards | Org-wide standards |

**Escalation rules:**
- Never skip a rung on the ladder. Resolve at Level 1 before Level 2, and Level 2 before Level 3.
- Each escalation level has a maximum 24-hour window to issue a ruling before escalating to the next rung.
- Both the ruling and the decision-maker's identity must be recorded in `specs/{ticket-id}/decisions.md`.
- Every escalation targets a single accountable individual rather than a committee (with the sole exception of Level 4). One human, one decision.

## What Doesn't Constitute a Conflict

Routine review exchanges that do not require this escalation workflow:

- **Suggestions vs. blocks:** A non-blocking `[SUGGESTION]` (or `nit` / `observation` class finding) is not a conflict — the author may adopt or decline it without escalation.
- **Style preferences:** "I would have named this helper differently" is non-actionable unless it violates an explicit rule in `comment-discipline.md` or `AGENTS.md`.
- **"I don't understand":** A reviewer asking for clarification is raising a comprehension signal, not a block. The author clarifies; the reviewer re-evaluates. If the reviewer still cannot follow the logic after explanation, *that* signals the code or boundary documentation needs clearer structure before merge.

## Recording Decisions

Every escalated conflict resolution appends a structured record to `specs/{ticket-id}/decisions.md`:

```markdown
## Decision: {short title}

**Date:** {YYYY-MM-DD}
**Conflict:** {what disagreed — Gate X approver vs. Gate Y, or Reviewer A vs. Reviewer B}
**Resolution:** {what was decided and why}
**Evidence:** {what evidence determined the outcome}
**Escalation level:** {1-4, or "Resolved at gate"}
**Decided by:** {who made the final call}
```

Logging resolutions in the repository ensures the team compounds institutional knowledge instead of relitigating identical design tradeoffs across future tickets.

## Anti-Patterns

- **HiPPO resolution** (Highest-Paid Person's Opinion): If an engineering leadreflexively backs the most senior engineer without weighing the technical evidence, the escalation ladder is compromised. Rulings must be grounded in evidence, not rank.
- **Conflict avoidance:** Rubber-stamping a review to avoid friction and complaining about the design afterward. Raise concerns at the gate where they belong; silent approval constitutes full endorsement.
- **Weaponized process:** Invoking tier escalation or gate blocks to stall a change for political reasons when objective triggers classify it as Low and all tests pass.
- **Relitigating settled decisions:** Once `decisions.md` records a ratified resolution, the question is closed. Newly discovered empirical evidence can reopen a decision (recorded via a new superseding `DEC` entry), but repeating "I still disagree" without new evidence never reopens a gate.
