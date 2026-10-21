# CHORD Reference

> **Vocabulary.** *CADENCE* (*Contextual Architecture, Decomposition, Execution, Navigation, Consolidation & Enshrinement*) is the umbrella specification and lifecycle framework (see [`specs/CADENCE.md`](../../specs/CADENCE.md) for the portable manual). *CHORD* — **C**onditions, **H**andling / Triggers, **O**utcomes, **R**ules, **D**eltas — is the behavioral decomposition engine CADENCE runs in Phase 3. This document is the repository-level reference for CHORD as practiced here: the five behavioral dimensions, mechanical observability seam derivation, the five-document artifact model, TDD execution discipline, and local hardware coprocessor offload integration. For the complete five-phase specification manual (Contextual Grounding Matrix, Pillar Library Construction, CHORD Decomposition, Iteration Spec Generation, and Iteration Comparison), consult `specs/CADENCE.md`.

## Behavioral Decomposition

CHORD turns every acceptance criterion into a verifiable behavioral contract. The `cadence-spec-author` agent performs this decomposition during CADENCE Phase 3 (after Phase 1 grounds the system in the Contextual Grounding Matrix and Phase 2 selects the governing Engineering Pillars).

### The Five Dimensions

| Dimension | What It Captures | Becomes in the Test |
|---|---|---|
| **Conditions** | Preconditions: system state that must hold before the behavior executes | `Given` -- test arrangement |
| **Handling** | Triggers: input parameters, commands, or events that initiate the behavior | `When` -- the action under test |
| **Outcomes** | Observable external emissions: responses, notifications, downstream calls, events | `Then` -- verify external interactions |
| **Rules** | Business invariants and domain constraints that govern the behavior | `Then` -- verify domain invariants |
| **Deltas** | Internal state mutations: updates to domain entities or persistent storage | `Then` -- verify state mutations |

The five letters form the **CHORD** mnemonic and map directly onto BDD test structure: **C**onditions (`Given`) → **H**andling (`When`) → **O**utcomes, **R**ules, **D**eltas (`Then`).

### The Edge Case Engine

For each CHORD dimension, ask "what happens when this dimension is violated?":

| Dimension | Violation | Produces |
|---|---|---|
| Conditions | Entity missing? Wrong lifecycle state? Expired? | Not-found errors, precondition validation failures |
| Handling | Null? Empty? Wrong type? Unauthorized caller? | Input validation errors, authentication/authorization failures |
| Outcomes | Downstream service unreachable? Timeout? | Resilience, retry, and graceful degradation scenarios |
| Rules | Domain invariant violated? Quota or limit exceeded? | Business rule rejection scenarios |
| Deltas | Concurrent modification? Partial write failure? | Optimistic concurrency conflict and rollback scenarios |

This derivation is mechanical rather than improvised. Five dimensions, each with a bounded catalog of failure modes, guarantee consistent edge-case coverage regardless of time pressure or author familiarity.

### CHORD-to-Gherkin

Every CHORD decomposition translates directly into Gherkin scenarios:

```gherkin
# Happy path: Conditions → Given, Handling → When, Deltas + Outcomes + Rules → Then
Scenario: S-1.1 -- Primary success path
  Given {conditions from CHORD}
  When {handling trigger from CHORD}
  Then {deltas from CHORD}
  And {outcomes from CHORD}

# Edge case: what if the required condition is violated?
Scenario: S-1.2 -- Entity not found
  Given {condition violation}
  When {same handling trigger}
  Then {error response with specific message}
```

Scenarios remain **framework-agnostic**. At implementation time, `cadence-implementer` inspects the repository's existing test suites to discover the test runner, assertion style, and fixture conventions.

---

## Reading Legacy Pre-CHORD Records

This reference supersedes `prism-reference.md` (BTG-332). PRISM -- Preconditions, Rules,
Inputs, Side-effects, Mutations -- was the legacy predecessor name for the  <!-- brand-residual:historical DEC-038 -->
same five-dimension behavioral decomposition tool, relabeled and ordered into the **CHORD** mnemonic; each dimension's behavioral role and corresponding runtime seam family remain 1-to-1:

| Legacy PRISM Dimension | CHORD Dimension | CADENCE Seam Family |
|---|---|---|
| Preconditions | Conditions | `UNSOUND_CONDITION` |
| Rules | Rules | `RULE_DIVERGENCE` |
| Inputs | Handling | `BOUNDARY_FAULT` |
| Side-effects | Outcomes | `DELTA_AUDIT_GAP` |
| Mutations | Deltas | `DELTA_AUDIT_GAP` |

Any historical archive record carrying the legacy `observability_prism_dimension` key in `metadata.yaml`, or a production-insight entry listing `PRISM Dimension`, is interpreted through the mapping table above. That table serves strictly as a read-map for already-archived records on disk, never an authoring alias -- all current specifications and insights write `observability_chord_dimension` with CHORD dimension names.

---

## Observability Seams

Observability Seams project CHORD's behavioral decomposition into live production telemetry. Every CHORD dimension boundary marks a seam where runtime execution can diverge from the specified contract. Seams are structured log events and metrics emitted at those boundaries so divergence is caught automatically in production.

### Why Seams Exist

Code that passes every unit and integration test can still harbor subtle behavioral flaws under real production traffic and data distributions. Automated tests verify known scenarios; observability seams guard against unknown scenarios by continuously asserting CHORD contracts at runtime.

### Seam Derivation from CHORD Dimensions

Each CHORD dimension maps mechanically to a specific seam family:

| CHORD Dimension | Seam Type | What It Detects |
|---|---|---|
| **Conditions** | `UNSOUND_CONDITION` | A handler executed when its required entry conditions were false |
| **Rules** | `RULE_DIVERGENCE` | Business rule branch distribution drifts outside its expected baseline |
| **Outcomes** | `DELTA_AUDIT_GAP` | Expected external call, event emission, or trace span was skipped |
| **Deltas** | `DELTA_AUDIT_GAP` | Internal state mutation committed without its required audit record |
| **Handling** | `BOUNDARY_FAULT` | Post-validation invariant broken after input transformation or mapping |

### Mechanical Derivation Process

**From Conditions → `UNSOUND_CONDITION` assertions:**

Every Conditions entry in the CHORD table becomes a runtime guard that emits a structured alert if violated. When CHORD specifies "Conditions: Order must be in Draft state," the seam emits `UNSOUND_CONDITION` if the submission handler ever executes against a non-Draft order.

Ask: "If this required entry condition were false at runtime despite upstream validation, what state would we observe?"

**From Rules → `RULE_DIVERGENCE` baselines:**

Every domain rule containing branching logic (`if`/`switch`/`match`) receives a branch-distribution metric and baseline. When the production branch ratio drifts beyond the declared threshold window, `RULE_DIVERGENCE` fires.

Ask: "What is the expected branch ratio under normal production traffic, and what shift signals an anomaly?"

**From Outcomes → `DELTA_AUDIT_GAP` checkpoints:**

Every external outcome in the CHORD table becomes a mandatory span or checkpoint in the distributed trace. If a request trace completes without the expected outcome span, emit `DELTA_AUDIT_GAP`.

Ask: "If this external call or event publish silently no-op'd without raising an exception, what would detect the omission?"

**From Deltas → `DELTA_AUDIT_GAP` verification:**

Every persistent state delta requiring an audit trail carries a transactional verification check. If the entity mutation commits without a paired audit record in the same transaction, emit `DELTA_AUDIT_GAP`.

Ask: "If this state mutation succeeded but the audit log entry was omitted, what would detect the gap?"

**From Handling → `BOUNDARY_FAULT` checks:**

Every validated trigger or input payload receives a post-transformation assertion that re-verifies invariants after mapping/deserialization. This catches defects where raw input passes validation but downstream normalization produces an invalid domain value.

Ask: "After this trigger's payload is parsed, mapped, or normalized, could the resulting object violate the original input constraint?"

### Seam Specification Table

The `cadence-spec-author` agent populates this table for each acceptance criterion in `spec.md`:

| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-1 | Conditions | UNSOUND_CONDITION | {domain}.{op}.precondition_violated | {specific condition} | Critical |
| AC-1 | Rules | RULE_DIVERGENCE | {domain}.{op}.branch_distribution | {rate outside [X%, Y%] over window} | Warning |
| AC-1 | Outcomes | DELTA_AUDIT_GAP | {domain}.{op}.{checkpoint}_missing | {trace completes without span} | Critical |
| AC-1 | Deltas | DELTA_AUDIT_GAP | {domain}.{op}.audit_missing | {mutation without audit record} | Critical |

Not every acceptance criterion requires all four seam families. Derive only the seams supported by the AC's CHORD decomposition:
- No branching domain rule → no `RULE_DIVERGENCE` seam
- No external outcome → no outcome `DELTA_AUDIT_GAP` seam
- No audit-mandated mutation → no delta `DELTA_AUDIT_GAP` seam

### Seam-to-Gherkin

Every specified seam generates executable BDD scenarios alongside the core functional scenarios:

```gherkin
# Verifying an UNSOUND_CONDITION seam fires
Scenario: OS-1.1 -- Condition violation emits structured alert
  Given {entity in a state that violates the required Conditions}
  And the system bypasses normal validation (direct invocation / race setup)
  When {operation} is attempted
  Then a structured log event is emitted with seam_type "UNSOUND_CONDITION"
  And the event includes expected_state and actual_state
  And the operation is rejected

# Verifying zero false positives on valid state
Scenario: OS-1.2 -- Normal operation does not trigger seam
  Given {entity in valid state}
  When {operation} is performed successfully
  Then no UNSOUND_CONDITION event is emitted
```

Seam scenarios are scheduled in the `test-plan.md` Implementation Order immediately after the core business-logic scenarios (positions 9–11) and prior to full-stack integration tests.

### References

- Log Pattern Catalog (JSON schemas, queries, metrics): `docs/policies/observability-patterns.md`
- Production Insights (living feedback from production defects): `docs/agentic-sdlc/production-insights.md`

---

## Engineering Pillars

While CHORD behavioral decomposition guarantees the feature behaves as specified, CADENCE **Engineering Pillars** ensure the design fits the system architecture. The organization-level CADENCE configuration (`docs/agentic-sdlc/CADENCE_ORG.md`) defines the mandatory pillars evaluated by every specification.

### The Three Always-On Mandatory Pillars

**1. Structural Simplicity** -- Fewest moving parts required to deliver the capability.
- Zero caching layers added without profiling evidence
- New capabilities wire up in `<=3` files and `<100` lines of configuration
- Between two valid designs, pick the one readable in fewer files

**2. Operational Resilience** -- Deployable, observable, and recoverable on standard infrastructure.
- CI pipeline completes in `<10` minutes using shared templates
- All secrets managed through the organization secrets manager
- Structured JSON logging with trace/span/request IDs for cross-service correlation
- Distributed tracing: all inter-service calls propagate W3C Trace Context headers
- Every new endpoint emits request count, latency histogram, and error rate metrics
- Every new external dependency includes health-check integration and alerting
- Observability ships with the feature -- never deferred to a follow-up ticket
- Rollback procedure documented and verified before go-live

**3. Agentic Ergonomics** -- Optimized for high-accuracy AI-assisted engineering.
- Authored files stay strictly `<400` lines (raised from 300 by PI-037; beyond ~400 lines an agent's single-pass accuracy degrades)
  - Except scenario-indexed BDD test harnesses (`ci-templates/scripts/tests/*.test.sh` and
    `ci-templates/scripts/tests/*-lib/*.sh`): no whole-file ceiling, governed per function instead
    (scenario function `<=150` lines, any function `<=400` lines). A harness is its entry point together with the scenario
    modules sourced by that entry point: one logical artifact, one measure. Those globs and no others -- see
    `CADENCE_ORG.md` Section 2 Pillar 3, which is canonical and documents the rationale.
- One existing example is sufficient for an agent to author a valid new instance
- An agent reads `<=5` files to understand and extend a capability

### Triggered Mandatory Pillars

**4. Data & Audit Fidelity** -- Every mutation is auditable and consistent. Activates automatically whenever the system captures, mutates, or persists data it owns (a database, a file store, a ledger, an audit log, or any owned record of user-provided input). Fail-closed: when in doubt, active. Dormant only when the system captures/persists zero owned data.
- 100% of write operations produce audit records
- Actor identity is derived from the authentication system, never from caller input
- Multi-table writes document step ordering, partial-failure handling, and cache invalidation

**5. Surface Compatibility** -- Public contracts are durable promises to consumers. Activates automatically whenever a change touches registered public surfaces or introduces new ones. Dormant for purely internal changes.

- All public surfaces registered in `docs/policies/surface-registry.md` (adopter-owned) or `docs/policies/cadence-surfaces.md` (core-owned framework surfaces) with stability level and guarantee window — resolve "registered surface" as the union across every registry present per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule
- Breaking changes require deprecation annotations, sunset dates, and migration guides per `docs/policies/deprecation-policy.md`
- Runtime deprecation signals: HTTP `Deprecation`/`Sunset` headers, structured log warnings, and `deprecated_surface_calls_total` metrics
- Golden-file snapshot tests for every stable API response shape
- Consumer-driven contract tests for every inter-service dependency
- Zero removal of a stable surface prior to completing its deprecation window

**6. Security Boundary Posture** -- The identity and trust chain must never be weakened. Activates automatically whenever a change touches authentication, authorization, PII, user input handling, or new client-side code. Fail-closed: when in doubt, active. Triggers on what the change *touches* at runtime, not what its prose discusses -- a governance or documentation edit that merely mentions security remains dormant. Ratified for this repository by PROJ-001 / ADR-0029; worked example `archive/PROJ-001/`.

- Caller authority established server-side from the authenticated principal, never from a caller-supplied scoping parameter
- Every new endpoint, action, page, and interactive component default-denied by attribute or fallback policy
- Per-record authorization enforced at the data-access layer -- a role authorizes an operation, not a row
- PII, financial, and legal-document fields are never logged, never placed in URLs, and never returned to unentitled callers

Note that pillar slot numbers are **catalog identifiers, not precedence ranks** -- Data & Audit Fidelity is Pillar 4 / rank 1, Surface Compatibility is Pillar 5 / rank 3, and Security Boundary Posture is Pillar 6 / rank 2. Surface Compatibility retains slot 5 because `specs/TEMPLATE/spec.md` and active specifications write `### Pillar 5: Surface Compatibility`, so Pillar 6 was appended rather than inserted (PROJ-001 DEC-004).

### Precedence Matrix

When two pillars pull in opposite directions, this precedence order resolves the conflict:

```
1. Data & Audit Fidelity       — auditability and consistency are non-negotiable
                                 (when triggered; collapses out otherwise)
2. Security Boundary Posture   — auth trust chain must never weaken
                                 (when triggered; collapses out otherwise)
3. Surface Compatibility       — public contracts are promises to consumers
                                 (when triggered; collapses out otherwise)
4. Structural Simplicity       — complexity taxes small teams
5. Operational Resilience      — you build it, you operate it
6. Agentic Ergonomics          — optimize for agents, never at correctness cost
7-8. [Open slots]              — repository-specific pillars
```

### Open Slots

Select 0–2 additional repository-specific pillars based on the problem domain:

| Problem Involves | Add |
|---|---|
| Auth changes, PII, user input | Security Boundary Posture |
| Latency, large datasets, scale | Execution Performance |
| Existing test suite, reliability | Automated Verifiability |
| Technology migration, library swap | Modular Replaceability |
| Public APIs, consumers, versioning | Surface Compatibility (if not already triggered) |

**Why the Security Boundary Posture row is now triggered-mandatory (PROJ-001 / ADR-0029).** This table previously offered *"Auth changes, PII, user input → Security Boundary Posture"* as an optional open slot. Because Security Boundary Posture is now a **triggered mandatory** pillar (Pillar 6 above), touching those areas *activates* it automatically rather than leaving it optional, and it consumes zero open slots.

---

## The Five Documents

Every governed ticket progresses through five core artifacts in `specs/{ticket-id}/`. Each artifact feeds the next stage of the CADENCE lifecycle.

### `problem.md` -- What is wrong and what success looks like

Authored by `cadence-triage-agent` and refined with the stakeholder (via `/cadence-elicit` when probe questions remain open). Captures business context, affected actors, acceptance criteria (the inputs to CHORD decomposition), constraints, and explicit out-of-scope boundaries.

**You touch this when:** Filing a new issue, reviewing triage output, answering elicitation probes, or refining acceptance criteria.

### `spec.md` -- How to solve it

Authored by `cadence-spec-author` (converging against `design-options.md` produced independently by `cadence-explorer` at Medium/High tier). Contains the Contextual Grounding Matrix (6W×4L) grounded in organization constants, CHORD behavioral decomposition for every acceptance criterion, CADENCE Pillar Evaluation across all active pillars, proposed design with code signatures, design exploration convergence, and risk analysis.

**You touch this when:** Reviewing a specification at Gate 1 (Spec Review), supplying domain context the agent missed, or recording Gate 1 rulings.

### `test-plan.md` -- The executable contract

Authored by `cadence-spec-author` directly from the CHORD decomposition. Contains Gherkin scenarios covering every happy path, edge case, and observability seam, sequenced in strict TDD implementation order. Also carries Test Infrastructure Discovery fields populated by `cadence-implementer` after scanning the repository's existing test suites.

**You touch this when:** Reviewing scenario coverage at Gate 1, or verifying during Gate 2 (Code Review) that every scenario was implemented and tested.

### `decisions.md` -- Why we built it this way

Appended by agents and human reviewers across the ticket lifecycle. Every entry is immutable -- reversals append a new entry that cites and supersedes the prior one. Decisions with repository-wide architectural impact are promoted to formal ADRs in `docs/ADR/` during `/cadence-archive`.

An **archived** `decisions.md` entry (under `archive/`) is **never rewritten**. When a subsequent ticket supersedes an archived decision, the **superseding decision is recorded in the new ticket's own `decisions.md`**, and the archived log may receive only an **additive forward-pointer annotation** -- the historical text is never edited, reworded, or deleted.

Any recorded **measurement** -- a count, red-test tally, sweep result, or "N of M" figure produced by inspecting the tree -- is a statement about a specific **`(tree-state, scope)` pair**, and drifts the instant it is separated from either. Record every measured figure alongside **the exact command that produced it, the commit SHA measured, and the scope it ranged over**. Naming the **scope** explicitly exposes incomplete coverage immediately at authoring time rather than review rounds later (BTG-079 DEC-012, promoted by BTG-081; extends `archive/BTG-064` DEC-014's *retire loudly, don't re-pin* rule from code to governance prose).

**You touch this when:** Recording a design trade-off, overriding an agent's recommendation, logging Gate 1/2/3 rulings, or recording a measured figure.

### `submission.md` -- The change proposal as a repository artifact

Drafted by `cadence-implementer` during Phase 4 (Finalize), completed by the author upon opening the MR/PR, and appended to by reviewers and the maintainer across the human gates. Carries the canonical change-proposal description, forge metadata, append-only review discussion, and final gate resolution including follow-up dispositions. Enshrined in `archive/{ticket-id}/` upon merge so the full review record survives independently of any external forge UI.

**You touch this when:** Submitting a change proposal, mirroring review threads, recording the maintainer verdict, or archiving after merge. See [`docs/guides/submitting-changes.md`](../guides/submitting-changes.md) for per-forge workflows.

---

## TDD Discipline & Local Coprocessor Offload

The `cadence-implementer` agent executes strict red-green-refactor cycles for every scenario listed in `test-plan.md`'s Implementation Order.

### The Cycle

```
FOR EACH scenario in the ordered list:

  1. RED        Write the failing test from the Gherkin scenario.
                Add minimal stubs if required for compilation.
                Run the test (via offload_log_triage / log-triage). It MUST FAIL.

  2. GREEN      Write the MINIMUM production code required to pass the test.
                Zero speculative code for later scenarios.

  3. ACCUMULATE Run the ENTIRE repository test suite.
                Every test must pass. Fix any regression before advancing.

  4. COMMIT     Create one atomic git commit per red-green cycle.
```

### Automatic 2-Tier Local Hardware Coprocessor Offload in the Workflow

To keep the primary cloud model's context window clean and preserve 100% verbatim diagnostic accuracy, CADENCE routes read-only discovery, log triage, and mechanical pre-review sweeps through a local 2-tier hardware coprocessor pipeline (`local-offload` MCP server + `log-triage` and `repo-scout` subagents):

| Coprocessor Tier | Endpoint & Models | Role in CHORD & TDD Workflow |
|---|---|---|
| **Tier 1: Always-On Zero-VRAM CPU** | `127.0.0.1:11434` (`local-fast-cpu` `gemma-4-e2b-it` + `local-embed-cpu` `nomic-embed-text`, 0 MB GPU VRAM) | **TDD Log Triage (`offload_log_triage` / `log-triage`):** Compacts noisy test runner and compiler output during RED/GREEN/ACCUMULATE loops, extracting verbatim failing assertions, `file:line` coordinates, and coverage metrics while writing full unedited output with line numbers to `/tmp/agy-last-triage.log`.<br>**Semantic Discovery (`local_semantic_embed` / `repo-scout`):** Indexes and searches `production-insights.md`, `intent-insights.md`, archived specs, and codebase symbols during Contextual Grounding and CHORD preparation. |
| **Tier 2: On-Demand Hybrid MoE & GPU** | `127.0.0.1:11434` (`local-moe-hybrid` `gemma-4-26b-a4b-it` + `local-12b-gpu` `gemma-4-12b-it`, RTX 5070 Ti 12GB VRAM) | **Pre-Review Mechanical Sweep (`offload_deep_review`):** Audits diffs against Pillar 3 (`<400`-line file ceiling), comment discipline, and CHORD observability seam completeness (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) prior to Gate 2 and Gate 3 reviews. |

All local coprocessor models operate under a strict read-only guardrail (`enable_write_tools: false`) and never modify repository files.

### Implementation Order

Scenarios are ordered to build behavior incrementally from core happy path to boundary guards:

| Order | Type | What It Forces |
|---|---|---|
| 1 | Primary happy path | Core domain behavior, interfaces, and wiring |
| 2 | Entity not found | Missing-resource failure path handling |
| 3 | Validation failure | Input validation rule implementation |
| 4 | Happy path variations | Extension of core behavior across valid inputs |
| 5 | Parameterized transitions | Complete domain state machine transitions |
| 6 | Boundary conditions | Edge-case limits and empty/max collections |
| 7 | Concurrency | Optimistic concurrency conflict detection |
| 8 | Authorization | Access-control policy enforcement (integration) |
| 9 | Observability seams | `UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `DELTA_AUDIT_GAP`, `BOUNDARY_FAULT` assertions |
| 10 | Full HTTP / request stack | End-to-end integration verification |
| 11 | Regression | Preservation of pre-existing behavior (uses existing test style, not BDD) |
| 12 | Golden-file | API response and event payload shape snapshots for stable surfaces |
| 13 | Consumer contract | Producer verification against consumer-owned contracts |
| 14 | Versioned integration | Replay of prior-version client requests against current service |

### Test Infrastructure Discovery

Before authoring any test, `cadence-implementer` inspects the repository's existing test suites to identify:
- Test runner, assertion library, and mocking/faking conventions
- Data setup patterns (builders, fixtures, factories)
- Integration test harness (base classes, HTTP test client, database lifecycle)
- File organization and naming conventions

Newly authored BDD scenarios follow the discovered conventions. Pre-existing tests are **never refactored or rewritten into BDD style**.

A test's *subject* is runtime application behavior, never a governance markdown document -- see [`docs/policies/test-scope.md`](../policies/test-scope.md), which defines the prohibited subjects once for the entire framework.
