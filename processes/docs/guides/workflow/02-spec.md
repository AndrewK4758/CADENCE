# Workflow Step 02 — Spec

> Part of the per-step workflow guide series. This guide details the **Spec** step. For the preceding step see [`01-triage.md`](01-triage.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Spec (`/cadence-spec`) |
| **Who** | Contributor / Implementer (invokes the skill; `cadence-spec-author` + `repo-scout` design and author) |
| **Consumes** | `specs/{ticket-id}/problem.md` + `metadata.yaml` from [Triage](01-triage.md) |
| **Produces** | `spec.md`, `test-plan.md`, `decisions.md`; `status: spec-in-review` |
| **Leads to** | **[Gate: Spec Approval](03-spec-approval.md)** — a human reviews and approves the design before any production code is written |

---

## Purpose

The Spec step transforms a triaged problem statement into a **complete, reviewable architectural specification paired with an executable Gherkin BDD test plan** that `cadence-implementer` can build through strict red-green-refactor TDD. Here, the *what* and *why* captured at Triage become an explicit *how* — grounded in the **Contextual Grounding Matrix (6W×4L)**, decomposed with **CHORD** (**C**onditions, **H**andling/Triggers, **O**utcomes, **R**ules, **D**eltas), and evaluated against the **CADENCE Engineering Pillars** — **before** a single line of production code is written.

Engineering quality compounds from this step: every downstream phase (TDD implementation, Gate 2 Code Review, Gate 3 Maintainer Acceptance) evaluates the change against this specification. Ambiguous specs yield brittle code; `/cadence-spec` resolves structural tradeoffs up front when course corrections are cheapest.

## Tier applicability

Whether a ticket requires a full specification is governed by the change tier assigned at Triage (see the matrix in [`../getting-started.md`](../getting-started.md) §2.3 and the authoritative table in [`change-tiers.md`](../../policies/change-tiers.md)#per-tier-spec-requirements):

| Tier | Spec depth |
|---|---|
| **Trivial** | No spec. A `submission.md` serves as the record on release cuts; docs/config value changes need only `metadata.yaml`. |
| **Low** | `problem.md` only — acceptance criteria suffice; no Contextual Grounding Matrix (6W×4L), no CHORD decomposition. **This step is skipped.** |
| **Medium** | Full spec: `spec.md` + `test-plan.md` + `decisions.md` + `submission.md`; CHORD decomposition on every AC; **abbreviated** Contextual Grounding Matrix (System Model + Technology Model rows). |
| **High** | Full spec with **complete** Contextual Grounding Matrix (all four rows: Scope, Business Model, System Model, Technology Model) and CHORD decomposition on all ACs. |

The remainder of this guide covers the Medium and High tier workflow — i.e., whenever `/cadence-spec` runs.

## Who does what

Invoke `/cadence-spec` from your agentic CLI runtime (`.agents/skills/cadence-spec/` or `.gemini/` on Antigravity):

```
/cadence-spec <ticket-id>        # e.g. /cadence-spec TT-6547
```

**Prerequisite:** `specs/{ticket-id}/problem.md` and `metadata.yaml` must already exist (`status: triaged`). If either is missing, `/cadence-spec` halts and directs you to run `/cadence-triage` first.

The `/cadence-spec` skill orchestrates the phase while delegating deep architectural synthesis to the **`cadence-spec-author`** subagent. At Medium tier (opt-in when touching a Stable registered surface or adding a new internal service integration) and High tier (mandatory), `cadence-spec-author` invokes the **`cadence-architect`** subagent for a cross-boundary compatibility pre-flight, incorporating its Observed/Inferred/Unknown findings and Draft Contracts directly into `spec.md`'s Compatibility Impact section. When divergent design options warrant exploration before committing to one architecture, the **`cadence-explorer`** subagent may produce `design-options.md` as an input to `cadence-spec-author`.

## Automatic Local Offload during Spec Discovery (`repo-scout` & `local_semantic_embed`)

During steps 2 and 3 of specification authoring, `cadence-spec-author` automatically offloads broad codebase and history exploration to CADENCE's read-only local hardware coprocessors (`enable_write_tools: false`):

1. **Semantic Insight & ADR Retrieval (`local_semantic_embed` on `local-embed-cpu`):** Runs zero-VRAM semantic vector queries (`nomic-embed-text` on port `11434`) across [`production-insights.md`](../../agentic-sdlc/production-insights.md), [`intent-insights.md`](../../agentic-sdlc/intent-insights.md), `docs/ADR/`, and `archive/` to surface prior incidents, architectural constraints, and mandatory CHORD observability seams affecting the target domain entities.
2. **Parallel Pattern & Seam Discovery (`repo-scout` on `local-moe-hybrid`):** Dispatches `repo-scout` (`nomic-embed-text` + `gemma-4-26b-a4b`) to map existing base classes, DTO mappers, repository patterns, registered surfaces (`surface-registry.md` and `cadence-surfaces.md`), and operationalizing skills/agents (for `change-tiers.md` policy-tooling consistency enumeration) — returning exact file/line references without bloating the primary reasoning model's context window.

Primary reasoning, CHORD decomposition, Engineering Pillar evaluation, and all file writes remain 100% owned by the primary `cadence-spec-author` model.

## What happens

`cadence-spec-author` authors the specification package by executing an eleven-step sequence:

1. **Load organizational & surface contracts.** Read `CADENCE_ORG.md` (Contextual Grounding Matrix constants, the 3 always-on + 3 triggered mandatory Engineering Pillars, and the pillar precedence matrix), [`surface-registry.md`](../../policies/surface-registry.md), [`cadence-surfaces.md`](../../policies/cadence-surfaces.md), and [`deprecation-policy.md`](../../policies/deprecation-policy.md). The three conditionally triggered pillars are **Data Integrity** (activates whenever owned data is captured or mutated), **Security Posture** (activates whenever authentication, authorization, PII, untrusted input, or client-side code is touched), and **Backwards Compatibility** (activates whenever a registered surface in `surface-registry.md` or `cadence-surfaces.md` is touched) — each triggered pillar is evaluated in full or explicitly marked not-triggered.
2. **Retrieve production & intent insights (via `local_semantic_embed`).** Filter [`production-insights.md`](../../agentic-sdlc/production-insights.md) and [`intent-insights.md`](../../agentic-sdlc/intent-insights.md) for matching domain entities and layers — matching insights mandate explicit CHORD observability seams and surface domain-specific open questions.
3. **Inspect existing source patterns (via `repo-scout`).** Discover the repository's established conventions (domain entities, validation, error handling, persistence, test fixtures) so the proposed design honors house idioms rather than inventing competing patterns.
4. **Populate the Contextual Grounding Matrix (6W×4L)** — inherit organizational constants from `CADENCE_ORG.md`, then fill ticket-specific facts across the six interrogatives (What, How, Where, Who, When, Why) at the required abstraction layers (System + Technology rows for Medium tier; all four rows — Scope, Business Model, System Model, Technology Model — for High tier).
5. **Execute CHORD behavioral decomposition.** Decompose every acceptance criterion into **C**onditions (`Given` state preconditions), **H**andling/Triggers (`When` initiating events/inputs), **O**utcomes (`Then` external responses/emissions), **R**ules (`Then` business invariants/constraints), and **D**eltas (`Then` internal state mutations/audit writes) — then mechanically derive edge cases by asking *"what happens if this CHORD dimension is violated?"*
6. **Derive CHORD observability seams** mechanically from the decomposition (`UNSOUND_CONDITION` from violated Conditions, `RULE_DIVERGENCE` baselines from branching Rules, `BOUNDARY_FAULT` from broken Handling/Outcomes contracts, and `DELTA_AUDIT_GAP` checkpoints from missing Outcomes/Deltas).
7. **Assess compatibility impact** across every present surface registry (`surface-registry.md` and `cadence-surfaces.md`) — classify each touched surface as additive, modification, or removal, draft deprecation/migration plans where required, register net-new public surfaces, and perform the policy-tooling consistency enumeration when modifying a governance policy or `CADENCE_ORG.md` binding (`change-tiers.md`).
8. **Analyze deployment compatibility** (whenever database schema changes are proposed) — evaluate old-code-vs-new-schema, new-code-vs-old-schema, and dual-write behavior, classifying the rollout as **Simple expansion** or **Prep-required** (requiring an interim compatibility release before the schema migration).
9. **Evaluate against the Engineering Pillars** — Simplicity, Operability, and Agentic DX (`< 400`-line file ceiling, `<= 5` files read to orient) always-on, plus Data Integrity, Security Posture, and Backwards Compatibility when triggered, and 0–2 optional pillars; resolve any inter-pillar tension deterministically via the `CADENCE_ORG.md` precedence matrix.
10. **Specify the proposed design** — per-file modification table and exact class/method/interface **signatures** (never implementation bodies), alongside at least one genuine **alternative considered** and a table of **risks and mitigations**.
11. **Generate the Gherkin BDD test plan (`test-plan.md`)** — map every AC to a Gherkin `Feature`, translate happy-path, negative, boundary, concurrency, auth, and `OS-{N}` observability-seam cases from CHORD into `Scenario` blocks, order them in the **Implementation Order** table for incremental TDD (`happy path -> not-found -> validation -> variations -> boundaries -> concurrency -> auth -> E2E`), and declare falsifiable journey invariants mapped to [`chaos-profiles.md`](../../policies/chaos-profiles.md) (`CP-01` through `CP-11`) whenever external dependencies or multi-step mutations are involved.

If the analysis reveals that the requested change violates a Non-Goal or Architecture Invariant in [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md), `cadence-spec-author` **halts** and recommends a Redirect or Section 10 Intent Amendment rather than designing around the invariant.

## Outputs

| Artifact | Content |
|---|---|
| [`specs/{ticket-id}/spec.md`](../../../specs/TEMPLATE/spec.md) | Contextual Grounding Matrix (6W×4L), CHORD decomposition per AC, Engineering Pillar evaluations, CHORD observability seams, existing-code analysis, proposed file/signature design, alternatives considered, compatibility & deployment-compatibility analysis, risks, and open questions. |
| [`specs/{ticket-id}/test-plan.md`](../../../specs/TEMPLATE/test-plan.md) | Stack-agnostic Gherkin scenarios, TDD Implementation Order table, journey invariants with chaos profile mappings, and contract/compatibility test specifications. |
| [`specs/{ticket-id}/decisions.md`](../../../specs/TEMPLATE/decisions.md) | Append-only decision log capturing architectural choices (`DEC-NNN`) made during specification. |
| `metadata.yaml` | Updated to `status: spec-in-review`; specification `stage_effort` appended and summed into `actual_effort`. |
| [`surface-registry.md`](../../policies/surface-registry.md) | Newly introduced adopter-owned public surfaces registered (if any). |

Once `cadence-spec-author` returns, `/cadence-spec` runs the **mechanical specification linter** and projects the updated artifacts and `spec-in-review` status to the bound tracker (`CADENCE_ORG.md` §9).

## Verification gates

Every specification passes through two verification layers before a human reviewer is asked to approve it:

1. **Structural verification (mechanical).** `.agents/skills/cadence-spec/verify-spec.sh {ticket-id}` (or `.gemini/skills/cadence-spec/verify-spec.sh {ticket-id}` on Antigravity) verifies that all required headings exist, every mandatory Engineering Pillar is evaluated, CHORD tables and Gherkin scenarios are populated, chaos profile citations (`CP-NN`) resolve via `chaos-citation-gate.sh`, and zero un-substituted template placeholders remain. Any structural failure is returned to `cadence-spec-author` and the linter is **re-run until it exits zero.** Non-blocking `WARN` diagnostics (such as an AC count note) are surfaced explicitly for Gate 1 review.
2. **Design completeness (semantic).** With the mechanical linter green, confirm that every AC maps to concrete design signatures and Gherkin scenarios, the Contextual Grounding Matrix (6W×4L) aligns across layers, at least one substantive alternative was weighed, and all risks carry mitigations.

Passing `verify-spec.sh` is the structural floor, not the ceiling — evaluating whether the architecture is *sound* belongs to the human Reviewer at [Gate 1: Spec Approval](03-spec-approval.md).

## Resolving open questions

The specification's **Open Questions** section collects every ambiguity or design fork that `cadence-spec-author` could not settle unilaterally from repository evidence — stakeholder policy choices, unconfirmed upstream contracts, or questions triggered by `production-insights.md` / `intent-insights.md`. **Every open question must be resolved before the specification can pass Gate 1 Approval.** Leaving an open question unresolved pushes an architectural decision into implementation, which is the exact failure mode `/cadence-spec` exists to prevent.

After `/cadence-spec` completes, resolve open questions interactively by prompting:

```
let's address any open questions
```

This launches a structured **resolution interview** that steps through each open question one by one, records your decision as a `DEC-NNN` entry in `decisions.md`, reconciles the affected Contextual Grounding Matrix (6W×4L), CHORD, Proposed Design, and `test-plan.md` sections (`CADENCE_DIRECTIVES.md` Behavior 6), and removes the resolved item from Open Questions. Once the Open Questions section is empty (or any remaining item carries an explicit deferral rationale accepted by the reviewer), the specification is ready for Gate 1.

## Definition of done

- [ ] `spec.md`, `test-plan.md`, and `decisions.md` authored under `specs/{ticket-id}/`.
- [ ] Every acceptance criterion has a complete 5-dimension **CHORD** decomposition and at least one happy-path **and** one negative/edge-case Gherkin scenario.
- [ ] All 3 always-on mandatory Engineering Pillars (Simplicity, Operability, Agentic DX) evaluated, plus each triggered pillar (Data Integrity, Security Posture, Backwards Compatibility) evaluated or explicitly marked not-triggered; any inter-pillar conflicts resolved via the `CADENCE_ORG.md` precedence matrix.
- [ ] CHORD observability seams (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) derived and mapped to `OS-{N}` scenarios (or explicitly justified as "None").
- [ ] Compatibility impact assessed across `surface-registry.md` and `cadence-surfaces.md`; deployment-compatibility classified (`Simple expansion` vs. `Prep-required`) when schema changes exist.
- [ ] At least one alternative considered and documented; risks paired with mitigations.
- [ ] `.agents/skills/cadence-spec/verify-spec.sh` exits zero.
- [ ] All open questions resolved and folded into `spec.md`, `test-plan.md`, and `decisions.md`.
- [ ] `status: spec-in-review` set in `metadata.yaml`; spec `stage_effort` recorded and projected to the bound tracker.

## What this step is NOT

- **Not production code implementation.** Specifications declare file paths and method/type **signatures**, never method bodies.
- **Not framework-coupled test code.** `test-plan.md` is authored in portable Gherkin; `cadence-implementer` translates scenarios into the repository's test runner during [`04-implementation.md`](04-implementation.md).
- **Not self-approving.** A zero exit from `verify-spec.sh` confirms structure; a human still owns [Gate 1: Spec Approval](03-spec-approval.md).
- **Not required for Trivial or Low tiers.** Trivial and Low tier changes bypass `/cadence-spec` per [`change-tiers.md`](../../policies/change-tiers.md).

## Where this goes next

With `status: spec-in-review` and zero unresolved open questions, the specification branch opens as an MR targeting the integration branch (`CADENCE_ORG.md#branch-strategy-binding`) and enters **[Gate 1: Spec Approval](03-spec-approval.md)** — where a human Reviewer or Domain Architect validates and approves the design **before any code is written**. Once approved (`status: spec-approved`), the ticket advances to [Implementation](04-implementation.md).

## Related documents

- [`01-triage.md`](01-triage.md) — the preceding step that produces `problem.md` and `metadata.yaml`.
- [`03-spec-approval.md`](03-spec-approval.md) — the human gate that reviews and approves the output of this step.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier applicability matrix.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — objective triggers and `#per-tier-spec-requirements`.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) · [`../../policies/cadence-surfaces.md`](../../policies/cadence-surfaces.md) · [`../../policies/deprecation-policy.md`](../../policies/deprecation-policy.md) — surface compatibility inputs.
- [`../../agentic-sdlc/chord-reference.md`](../../agentic-sdlc/chord-reference.md) — CHORD five-dimension decomposition, seam derivation (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`), and the five-artifact model.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the repository charter grounding every design.
- [`../../../specs/TEMPLATE/spec.md`](../../../specs/TEMPLATE/spec.md) · [`test-plan.md`](../../../specs/TEMPLATE/test-plan.md) · [`decisions.md`](../../../specs/TEMPLATE/decisions.md) — the templates populated during `/cadence-spec`.
