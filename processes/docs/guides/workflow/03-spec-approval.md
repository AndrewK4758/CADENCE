# Workflow Step 03 — Gate: Spec Approval

> Part of the per-step workflow guide series. This is a **human governance gate** (Gate 1), not an autonomous agent step — agents draft and verify structure, while accountable humans decide. For the specification authoring step see [`02-spec.md`](02-spec.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. The authoritative gate specification lives in [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 1.

| | |
|---|---|
| **Gate** | Spec Approval (Gate 1 — Spec Review) |
| **Who** | Reviewer, Domain Architect, or Product Steward (a human) |
| **You are approving** | The **architectural design and test plan**, before any code is written |
| **Consumes** | `spec.md` + `test-plan.md` + `decisions.md` at `status: spec-in-review` |
| **Outcome** | **Approve** (→ [Implementation](04-implementation.md)), **Direct edit**, or **Comment & regenerate** |

---

## Purpose

Gate 1 ensures that **an accountable human retains architectural ownership before a single line of production code is written.** During Step 02 (`02-spec.md`), `cadence-spec-author` (assisted by `repo-scout` and `local_semantic_embed` coprocessor discovery) produced a complete specification package, and `.agents/skills/cadence-spec/verify-spec.sh` confirmed its structural integrity. What no automated linter can supply is *engineering and product judgment*: does this design solve the real problem, fit the system architecture cleanly, and commit only to decisions we actually need to make right now?

At Gate 1 you are approving the **blueprint**. Implementation correctness is verified later at [Gate 2: Code Review](05-code-review.md), and repository-wide stewardship is evaluated at [Gate 3: Maintainer Acceptance](06-maintainer-acceptance.md). Here, your core question is: **is this the right design to build, and do its contracts hold together?**

## When this gate applies

Only **Medium-** and **High-tier** changes pass through Gate 1 Spec Approval. Trivial changes require no spec, and Low-tier changes proceed directly from `problem.md` to `/cadence-implement` with Gate 2 Code Review as their single human gate. See the machine-readable table in [`change-tiers.md`](../../policies/change-tiers.md)#per-tier-spec-requirements and [`../getting-started.md`](../getting-started.md) §2.3.

## Automatic Local Pre-Verification at Gate 1

Before the specification reaches your review queue, CADENCE's local coprocessor and gate scripts have already cleared the mechanical checks:

- `repo-scout` and `local_semantic_embed` (`local-embed-cpu` at 0 MB VRAM) surfaced relevant historical ADRs, `production-insights.md` (`PROD-NNN`), and `intent-insights.md` (`II-NNN`) entries during spec authoring so prior lessons are already cited in `spec.md`.
- `.agents/skills/cadence-spec/verify-spec.sh` (or `.gemini/skills/cadence-spec/verify-spec.sh`) verified that all Contextual Grounding Matrix (6W×4L) rows, CHORD decompositions, Engineering Pillar evaluations, and Gherkin scenarios are structurally complete and that zero unresolved template placeholders remain.
- When you want a quick mechanical pre-scan of a large `spec.md` + `test-plan.md` diff before your human review, `offload_deep_review` (`local-moe-hybrid` / `local-12b-gpu`) can audit CHORD-to-Gherkin scenario coverage and seam completeness in seconds — leaving your review bandwidth 100% focused on architectural judgment.

## The non-negotiable: maintain your mental model

**You must be able to place this change clearly within the overall system architecture.** If `spec.md` does not give you enough clarity to update your mental model of the system — which bounded contexts participate, which business flows change, how data crosses boundaries, and which invariants hold — **reject the spec and request regeneration.** This rule is non-negotiable. Approving a specification that no human truly understands is how systems decay into unmaintainable sprawl.

The practical test: after reading `spec.md`, could you explain to a teammate on a whiteboard what this change does to the *system* — not just which classes it edits — without looking back at the document? If not, do not approve it yet.

## What to do

### Step 1 — Orient in the architecture (do this first)

Before reading method signatures or Gherkin scenarios, answer three orientation questions against [`SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) and [`docs/flows/`](../../flows/):

1. Which **bounded context(s)** does this specification modify?
2. Which **business flow(s)** does it extend or alter?
3. What does it **assume about adjacent contexts** — data ownership, event schemas, or upstream/downstream invariants?

If `spec.md` does not make those three answers immediately clear, **stop and return it** with explicit feedback: *"I cannot place this design in the system architecture. Clarify which bounded context owns this state, which flows are modified, and what cross-boundary contracts are assumed."* Whenever a spec introduces a new service, boundary, or flow not yet reflected in `SYSTEM_OVERVIEW.md` or `docs/flows/`, require those updates as part of the ticket's scope.

### Step 2 — Judge what only a human can

- **Architectural fit** — Does the proposed design belong in the layer and bounded context where `spec.md` places it?
- **Business-intent fidelity** — Does this specification genuinely solve the stakeholder problem captured in `problem.md`? Would the requester recognize the outcome as what they asked for?
- **Organizational & roadmap context** — Does this collide with in-flight migrations, adjacent team roadmaps, or operational freezes?
- **Decision timing** — Is the spec locking in premature abstractions or irreversible schema commitments that could be deferred?

### Step 3 — Apply the maturity lens

Calibrate your review to the lifecycle stage of the subsystem:

- **Greenfield / early-stage service:** Is this the *simplest possible* design that lets us ship safely and learn? Are we over-engineering for hypothetical future scale? Bias toward the **Simplicity** pillar.
- **Mature / shared platform service:** Does this honor established ADRs, surface stability guarantees (`surface-registry.md` / `cadence-surfaces.md`), and cross-cutting operational standards? Bias toward **Backwards Compatibility** and architectural consistency.

### Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **Architectural clarity** | **Can you identify which bounded context(s) and flow(s) this touches? If not, reject.** |
| Contextual Grounding Matrix (6W×4L) | Are the required rows populated (`System + Technology` for Medium; all 4 rows for High)? Do lower layers align with upper layers? |
| CHORD decomposition | Is every acceptance criterion decomposed across Conditions, Handling/Triggers, Outcomes, Rules, and Deltas? Are edge cases derived systematically? |
| Engineering Pillars | Are the 3 always-on pillars (Simplicity, Operability, Agentic DX `< 400` lines) and triggered pillars (Data Integrity, Security Posture, Backwards Compatibility) evaluated honestly? Are any tradeoffs resolved via the `CADENCE_ORG.md` precedence matrix? |
| Compatibility impact | Are changes to registered surfaces (`surface-registry.md` / `cadence-surfaces.md`) identified? Are deprecation plans and policy-tooling enumerations complete? |
| Proposed design | Do the proposed file paths and class/method signatures match codebase conventions (`AGENTS.md`)? |
| Alternatives considered | Was at least one credible alternative genuinely weighed and contrasted? |
| Test plan (`test-plan.md`) | Does the Gherkin scenario set cover every CHORD dimension and `OS-{N}` observability seam (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`)? |
| Journey invariants | When declared: are invariants falsifiable, traced to a CHORD Rules/Deltas cell, and mapped to the applicable [`chaos-profiles.md`](../../policies/chaos-profiles.md) profiles (`CP-01`–`CP-11`)? |

Remember: `.agents/skills/cadence-spec/verify-spec.sh` already checked structural presence. Spend your energy on whether the content inside those sections is *architecturally sound*.

## Your decision

Select one of three outcomes:

| Outcome | When | How |
|---|---|---|
| **Approve** | The design is sound, all open questions are resolved, and you can place it in the system architecture. | Record approval (below) and merge the spec MR; the ticket advances to [Implementation](04-implementation.md). |
| **Direct edit** | Minor refinements — naming tweaks, phrasing clarifications, or small signature adjustments. | Edit `spec.md` / `test-plan.md` directly on the spec branch, re-run `verify-spec.sh`, and approve. |
| **Comment & regenerate** | Structural rethink needed, missing boundary context, or flawed CHORD/pillar assumptions. | Record specific review comments explaining what must change, then have the author re-run `/cadence-spec` to regenerate the affected sections so CHORD edge cases and `test-plan.md` scenarios stay synchronized. |

Whenever feedback alters an acceptance criterion or a core architectural boundary, prefer **Comment & regenerate** over manual line edits so that CHORD edge cases, observability seams, and Gherkin scenarios re-derive cleanly together.

## Recording the decision

- Mirror substantive review discussion into [`submission.md`](../../../specs/TEMPLATE/submission.md) (`## Discussion`) or `decisions.md` so the repository archive retains the design rationale after merge (see [`submitting-changes.md`](../submitting-changes.md)).
- On **Approve**, update `specs/{ticket-id}/metadata.yaml` **on the spec MR branch before merging** — set `status: spec-approved` and set `spec_approved_at:` to the ISO 8601 approval date (`YYYY-MM-DD`, e.g., `2026-10-19`, or a full UTC timestamp). Committing `status: spec-approved` on the spec branch ensures that when the spec MR merges into the integration branch (`CADENCE_ORG.md#branch-strategy-binding`), the specification lands on the integration branch already marked approved — satisfying `/cadence-implement`'s P1/P2 precondition checks (`CADENCE_ORG.md` §14).
- Project the `spec-approved` status to the bound tracker (`CADENCE_ORG.md` §9, e.g., `/cadence-sync-jira` or `/cadence-sync-youtrack`).
- On **Comment & regenerate**, `status` remains `spec-in-review` until the revised specification passes re-review.

## What this gate is NOT

- **Not code review.** No production or test code exists yet; you are reviewing the architectural blueprint (`spec.md` and `test-plan.md`).
- **Not a mechanical formatting check.** `verify-spec.sh` already enforced section presence and placeholder removal; your bar is engineering soundness.
- **Not a rubber stamp.** Rejecting a spec because *"I cannot trace how this crosses the bounded context boundary"* is a core responsibility of this gate.
- **Not used for Trivial or Low tiers.** Trivial and Low tier tickets skip Gate 1 per [`change-tiers.md`](../../policies/change-tiers.md).

## Related documents

- [`02-spec.md`](02-spec.md) — the preceding step that generates `spec.md`, `test-plan.md`, and `decisions.md`.
- [`04-implementation.md`](04-implementation.md) — the next step once `status: spec-approved` lands on the integration branch.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier gate matrix.
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of all four human gates (§Gate 1 is this gate).
- [`../../SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) · [`../../flows/`](../../flows/) — architectural maps used during Step 1 orientation.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — `#per-tier-spec-requirements` governing Gate 1 applicability.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) · [`../../policies/cadence-surfaces.md`](../../policies/cadence-surfaces.md) — surface registries verified during compatibility review.
- [`../submitting-changes.md`](../submitting-changes.md) — how review discussions are preserved in the repository.
