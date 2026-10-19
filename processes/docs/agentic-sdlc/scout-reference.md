# SCOUT Reference

> **Vocabulary.** *CLAIRE* is the umbrella spec-generation framework (see [`specs/CLAIRE.md`](../../specs/CLAIRE.md) for the portable definition). *SCOUT* — State, Constraints, Outputs, Updates, Triggers — is the behavioral decomposition tool CLAIRE uses in Phase 3. This document is the project-specific reference for SCOUT as practiced here: the five dimensions, observability seam derivation, the five-document artifact model, and TDD discipline. For the canonical framework definition (Zachman grounding, facet library construction, SCOUT decomposition, iteration spec generation, comparison), read `specs/CLAIRE.md`.

## Behavioral Decomposition

SCOUT transforms each acceptance criterion into a testable behavioral contract. The spec-author performs this decomposition during CLAIRE Phase 3 (after Phase 1 grounds the system and Phase 2 selects the governing facets).

### The Five Dimensions

| Dimension | What It Captures | Becomes in the Test |
|---|---|---|
| **State** | Preconditions: system state that must be true before the behavior executes | `Given` -- test setup |
| **Constraints** | Business rules and invariants that govern the behavior | `Then` -- the contract being verified |
| **Outputs** | Observable side-effects: external calls, notifications, events | `Then` -- verify external interactions |
| **Updates** | Mutations: state changes to entities or persistent storage | `Then` -- verify state changes |
| **Triggers** | Data, parameters, or events that initiate the behavior | `When` -- the action under test |

The letters are ordered for the mnemonic, not for execution. In a test they run as **S**tate → **T**riggers → **C**onstraints, **O**utputs, **U**pdates (`Given` → `When` → `Then`).

### The Edge Case Engine

For each dimension, ask "what if this is violated?":

| Dimension | Violation | Produces |
|---|---|---|
| State | Entity missing? Wrong state? Expired? | Not-found errors, state validation failures |
| Constraints | Invariant broken? Limit exceeded? | Business rule violation scenarios |
| Outputs | External service fails? Timeout? | Resilience and error handling scenarios |
| Updates | Concurrent modification? | Optimistic concurrency conflict scenarios |
| Triggers | Null? Empty? Wrong type? Unauthorized? | Validation errors, auth failures |

This is mechanical, not creative. Five dimensions, each with a finite set of violation types. The result is edge case coverage that does not depend on individual experience or time pressure.

### SCOUT-to-Gherkin

Each SCOUT decomposition produces Gherkin scenarios directly:

```gherkin
# Happy path: State → Given, Triggers → When, Updates + Outputs → Then
Scenario: S-1.1 -- Primary success path
  Given {state from SCOUT}
  When {trigger from SCOUT}
  Then {update from SCOUT}
  And {output from SCOUT}

# Edge case: what if the required state is violated?
Scenario: S-1.2 -- Entity not found
  Given {state violation}
  When {same trigger}
  Then {error response with specific message}
```

The scenarios are **framework-agnostic**. The implementer agent discovers the project's test framework, assertion library, and conventions at implementation time.

---

## Reading Records Made Before SCOUT

This document replaces `prism-reference.md` (BTG-332). PRISM -- Preconditions, Rules,
Inputs, Side-effects, Mutations -- was SCOUT's CLAIRE-era predecessor name for the  <!-- brand-residual:historical DEC-038 -->
same tool and the same five dimensions, relabeled and reordered for the mnemonic; the
seam type each dimension produces did not change.

| PRISM | SCOUT | Seam (unchanged) |
|---|---|---|
| Preconditions | State | `IMPOSSIBLE_STATE` |
| Rules | Constraints | `DECISION_DRIFT` |
| Inputs | Triggers | `SEAM_VIOLATION` |
| Side-effects | Outputs | `LINEAGE_GAP` |
| Mutations | Updates | `LINEAGE_GAP` |

A record under the legacy key (`observability_prism_dimension` in a `metadata.yaml`
recorded before the rename), or a production-insight entry's `PRISM Dimension` field,
holds a legacy value. Read it through this table. This is a read map for records
already on disk, not an authoring alias -- new records use `observability_scout_dimension`
with SCOUT values, and nothing in this repository writes the legacy key any more.

---

## Observability Seams

Observability Seams extend SCOUT's behavioral decomposition into production monitoring. Every SCOUT dimension boundary represents a point where the system's actual behavior can diverge from its specified behavior. Seams are structured log events emitted at these boundaries that make divergence detectable at runtime.

### Why Seams Exist

AI-generated code may pass all tests yet contain subtle logic errors that only manifest under production data distributions. Tests verify behavior against known scenarios; seams detect unknown scenarios by asserting SCOUT constraints continuously in production.

### Seam Derivation from SCOUT Dimensions

Each SCOUT dimension produces a specific seam type. This derivation is mechanical — if you have a SCOUT decomposition, you can derive the seams without creative judgment.

| SCOUT Dimension | Seam Type | What It Detects |
|---|---|---|
| **State** | `IMPOSSIBLE_STATE` | A behavior executed when its required state was absent |
| **Constraints** | `DECISION_DRIFT` | Business rule branch distribution deviates from baseline |
| **Outputs** | `LINEAGE_GAP` | Expected external call or checkpoint was skipped |
| **Updates** | `LINEAGE_GAP` | State change did not produce expected audit record |
| **Triggers** | `SEAM_VIOLATION` | Post-validation invariant violated after transformation |

### Mechanical Derivation Process

**From State → IMPOSSIBLE_STATE assertions:**

Each State entry in the SCOUT table becomes a runtime assertion that logs when violated. If SCOUT says "State: Order must be in Draft state," the seam emits `IMPOSSIBLE_STATE` if the submit handler executes with a non-Draft order.

Ask: "If this required state were absent at runtime despite validation, what would I observe?"

**From Constraints → DECISION_DRIFT baselines:**

Each constraint with branching logic (if/switch/match) gets a distribution baseline. The baseline is the expected ratio of branches taken under normal production traffic. Deviation beyond a threshold triggers `DECISION_DRIFT`.

Ask: "What is the expected distribution of this decision under normal traffic? What deviation would indicate a problem?"

**From Outputs → LINEAGE_GAP checkpoints:**

Each output in the SCOUT table becomes a required checkpoint in the trace. If a trace completes without the expected output span, emit `LINEAGE_GAP`.

Ask: "If this external call silently failed (no error, no execution), would anything detect it?"

**From Updates → LINEAGE_GAP verification:**

Each update with audit requirements has a corresponding verification. If the update fires but no audit record appears within the same transaction, emit `LINEAGE_GAP`.

Ask: "If this state change happened but the audit record was not written, would anything detect it?"

**From Triggers → SEAM_VIOLATION checks:**

Each validated trigger has a post-processing assertion that re-checks invariants after transformation. Catches cases where validation passes but downstream transformation produces invalid state.

Ask: "After this trigger's data is transformed/mapped/converted, could the result violate the original validation constraint?"

### Seam Specification Table

The spec-author fills this table for each AC in spec.md:

| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-1 | State | IMPOSSIBLE_STATE | {domain}.{op}.precondition_violated | {specific condition} | Critical |
| AC-1 | Constraints | DECISION_DRIFT | {domain}.{op}.branch_distribution | {rate outside [X%, Y%] over window} | Warning |
| AC-1 | Outputs | LINEAGE_GAP | {domain}.{op}.{checkpoint}_missing | {trace completes without span} | Critical |
| AC-1 | Updates | LINEAGE_GAP | {domain}.{op}.audit_missing | {mutation without audit record} | Critical |

Not every AC requires all seam types. Derive only what the SCOUT decomposition supports:
- No branching constraint → no DECISION_DRIFT seam
- No external output → no LINEAGE_GAP for outputs
- No audit-required update → no LINEAGE_GAP for updates

### Seam-to-Gherkin

Each seam produces test scenarios following the same pattern as business behavior:

```gherkin
# Verifying an IMPOSSIBLE_STATE seam fires
Scenario: OS-1.1 -- State violation emits structured alert
  Given {entity in a state that violates the required State}
  And the system bypasses normal validation (direct invocation / race setup)
  When {operation} is attempted
  Then a structured log event is emitted with seam_type "IMPOSSIBLE_STATE"
  And the event includes expected_state and actual_state
  And the operation is rejected

# Verifying no false positives
Scenario: OS-1.2 -- Normal operation does not trigger seam
  Given {entity in valid state}
  When {operation} is performed successfully
  Then no IMPOSSIBLE_STATE event is emitted
```

Seam scenarios are placed in the Implementation Order after business logic scenarios (positions 7-9) and before integration tests.

### References

- Log Pattern Catalog (JSON schemas, queries, metrics): `docs/policies/observability-patterns.md`
- Production Insights (living feedback from bugs): `docs/agentic-sdlc/production-insights.md`

---

## Quality Facets

While behavioral decomposition ensures the feature works, quality facets ensure the feature fits the system. The org-level CLAIRE config (`docs/agentic-sdlc/CLAIRE_ORG.md`) defines mandatory facets that every spec evaluates against.

### The Three Always-On Mandatory Facets

**1. Simplicity** -- Fewest moving parts necessary.
- No cache without profiling evidence
- New capability wires up in <=3 files, <100 config lines
- Pick the approach readable in fewer files

**2. Operability** -- Deployable, observable, recoverable using standard infra.
- CI pipeline <10 min using shared templates
- All secrets via the org secrets manager
- Structured JSON logging with trace/span/request IDs for cross-service debugging
- Distributed tracing: all inter-service calls propagate W3C Trace Context
- Every new endpoint emits request count, latency histogram, and error rate metrics
- Every new dependency has health-check integration and alerting
- Observability ships with the feature -- never deferred to a follow-up ticket
- Rollback procedure documented and tested

**3. Developer Experience (Agentic)** -- Optimized for AI-assisted development.
- Files <400 lines (raised from 300 by PI-037; past ~400 an agent's single-pass accuracy degrades)
  - Except scenario-indexed BDD test harnesses (`ci-templates/scripts/tests/*.test.sh` and
    `ci-templates/scripts/tests/*-lib/*.sh`): no whole-file ceiling, governed per function instead
    (scenario <=150, any function <=400). A harness is its entry point together with the scenario
    modules that entry point sources: one artifact, one measure. Those globs and no others -- see
    `CLAIRE_ORG.md` Section 2 Facet 3, which is canonical and carries the reasoning.
- 1 existing example is sufficient to produce a correct new instance
- Agent reads <=5 files to understand a capability

### Triggered Mandatory Facets

**4. Data Integrity** -- Every mutation auditable. Compliance non-negotiable. Activates automatically whenever the system captures, manipulates, or persists data it owns (a database, a file store, a ledger, an audit log, or any owned record of user-provided input). Fail-closed: when in doubt, active. Skipped only when the system captures/persists no owned data.
- 100% of writes produce audit records
- Actor identity from auth system, never from user input
- Multi-table writes: step order, failure handling, cache invalidation documented

**5. Backwards Compatibility** -- Public contracts are promises to consumers. Activates automatically when a change touches registered public surfaces or introduces new ones. Skipped for purely internal changes.

- All public surfaces registered in `docs/policies/surface-registry.md` (project-owned) or `docs/policies/claire-surfaces.md` (core-owned framework surfaces) with stability level and guarantee period — resolve "registered surface" as the union over every registry present, per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule
- Breaking changes require deprecation annotation, sunset date, and migration guide per `docs/policies/deprecation-policy.md`
- Runtime deprecation signals: HTTP `Deprecation`/`Sunset` headers, structured log warnings, `deprecated_surface_calls_total` metric
- Golden-file tests for every stable API response shape
- Consumer-driven contract tests for every inter-service dependency
- No removal of a stable surface without a completed deprecation period

**6. Security Posture** -- The identity and trust chain must not be weakened. Activates automatically when a change touches authentication, authorization, PII, user input handling, or new client-side code. Fail-closed: when in doubt, active. Activates on what the change *touches*, not what it is *about* -- a documentation or governance change that merely discusses security is dormant. Ratified for this repository by PROJ-001 / ADR-0029; worked example `archive/PROJ-001/`.

- Caller authority established server-side from the authenticated principal, never from a caller-supplied scoping parameter
- Every new endpoint, action, page and interactive component default-denied by attribute or fallback policy
- Per-record authorization at the data-access layer -- a role authorizes an operation, not a row
- PII, financial and legal-document data never logged, never placed in a URL, never returned to an unentitled caller

Note the slot numbers are **library identifiers, not precedence ranks** -- Data Integrity is Facet 4 / rank 1, Backwards Compatibility is Facet 5 / rank 3, Security Posture is Facet 6 / rank 2. Backwards Compatibility keeps slot 5: `specs/TEMPLATE/spec.md` and every live spec write `### Facet 5: Backwards Compatibility`, so the new facet is appended rather than inserted (PROJ-001 DEC-004).

### Precedence Matrix

When facets conflict, this ordering resolves:

```
1. Data Integrity              — compliance is non-negotiable
                                 (when triggered; collapses out otherwise)
2. Security Posture            — auth trust chain must not weaken
                                 (when triggered; collapses out otherwise)
3. Backwards Compatibility     — public contracts are promises to consumers
                                 (when triggered; collapses out otherwise)
4. Simplicity                  — complexity taxes small teams
5. Operability                 — you build it, you run it
6. DX (Agentic)                — optimize for agents, not at correctness cost
7-8. [Open slots]              — project-specific
```

### Open Slots

Select 0-2 additional facets based on the problem:

| Problem Involves | Add |
|---|---|
| Auth changes, PII, user input | Security Posture |
| Latency, large datasets, scale | Performance Efficiency |
| Existing test suite, reliability | Testability |
| Technology migration, library swap | Replaceability |
| Public APIs, consumers, versioning | Backwards Compatibility (if not already triggered) |

**Where the Security Posture row went (PROJ-001 / ADR-0029).** This table used to offer *"Auth changes, PII, user input → Security Posture"*. It no longer does: Security Posture is a **triggered mandatory** facet (see Facet 6 above), so those changes *activate* it rather than making it available to pick, and it can no longer be declined. The open-slot count is unchanged — a triggered mandatory facet consumes no slot.

---

## The Five Documents

Every piece of work flows through five documents. Each one drives the next phase.

### `problem.md` -- What is wrong and what success looks like

Written by the triage agent, refined by the PM. Contains business context, affected users, acceptance criteria (the inputs to SCOUT), constraints, and explicit out-of-scope boundaries.

**You touch this when:** Filing a new issue, reviewing a triage output, refining acceptance criteria.

### `spec.md` -- How to solve it

Written by the spec-author agent. Contains the Zachman grid (grounded in org constants), SCOUT behavioral decomposition for every AC, CLAIRE facet evaluation against all mandatory facets, proposed design with code signatures, alternatives considered, and risks.

**You touch this when:** Reviewing a spec as architect, adding domain context the agent missed, approving or requesting changes.

### `test-plan.md` -- The executable contract

Written by the spec-author agent, derived from SCOUT output. Contains Gherkin scenarios for every behavior and edge case, ordered for TDD progression. Also contains blank Test Infrastructure Discovery fields that the implementer fills after scanning existing test projects.

**You touch this when:** Reviewing test coverage during spec review, verifying the implementation covered all scenarios during code review.

### `decisions.md` -- Why we did it this way

Written by agents and humans throughout the lifecycle. Each entry is immutable -- reversals create new entries that supersede the original. Decisions with project-wide significance are promoted to ADRs during archival.

An **archived** `decisions.md` entry (one under `archive/`) is **never rewritten**. When a later ticket supersedes it, the **superseding decision is recorded in that ticket's own log**, and the archived entry may receive an **additive annotation** pointing forward -- the original entry's text is **never altered, reworded, or deleted**.

A recorded **measurement** -- any figure produced by running something over a tree (a count, a red set, a sweep result, an "N of M" claim) -- is a fact about a **`(tree-state, scope)` pair**, and drift enters the moment it is detached from either. Record every measured figure with **the command that produced it, the SHA it was measured at, and the scope it ranged over**. The **scope** half is the one that earns its keep: naming the domain a figure ranged over puts an incomplete domain on the page, where it is caught at write time rather than two review rounds later -- writing *"measured over `btg-025`, `btg-052`, `btg-027`"* exposes the missing fourth harness immediately, where a bare *"three guards"* hides it. This governs figures a change **produces**; it does not apply to counts read off a document's own visible content. (BTG-079 DEC-012, promoted by BTG-081; extends `archive/BTG-064` DEC-014's *retire loudly, don't re-pin* ruling from code to prose.)

**You touch this when:** Making a design trade-off during review, overriding an agent's recommendation, logging why you chose one approach over another, recording any figure you measured.

### `submission.md` -- The change proposal as a repository artifact

Drafted by the implementer agent at the end of Phase 4 (Finalize), filled in by the author at submission, appended to by reviewers and the maintainer through the human gates. Contains the change-proposal description (the canonical source for MR/PR body or SourceHut cover-letter content), forge metadata, the discussion log, and the resolution. Becomes the immutable archival record of *what was proposed, debated, and decided* — no longer dependent on the forge UI or mailing-list archive.

**You touch this when:** Submitting your change, replying to review feedback, recording the maintainer's accept/postpone/reject verdict, archiving after merge. See [`docs/guides/submitting-changes.md`](../guides/submitting-changes.md) for the per-forge workflow.

---

## TDD Discipline

The implementer agent follows strict red-green-refactor for every scenario in the test plan's Implementation Order.

### The Cycle

```
FOR EACH scenario in the ordered list:

  1. RED        Write the test from the Gherkin scenario.
                Create minimal stubs if needed for compilation.
                Run the test. It MUST FAIL.

  2. GREEN      Write the MINIMUM production code to make the test pass.
                No code for future scenarios.

  3. ACCUMULATE Run the ENTIRE test suite (all projects).
                Every test must pass. Fix regressions before continuing.

  4. COMMIT     One commit per red-green cycle.
```

### Implementation Order

Scenarios are sequenced deliberately:

| Order | Type | What It Forces |
|---|---|---|
| 1 | Primary happy path | Core behavior, interfaces, wiring |
| 2 | Entity not found | Failure path handling |
| 3 | Validation failure | Validation rule implementation |
| 4 | Happy path variations | Extend core behavior |
| 5 | Parameterized transitions | Full state machine |
| 6 | Boundary conditions | Edge cases |
| 7 | Concurrency | Optimistic concurrency handling |
| 8 | Authorization | Policy enforcement (integration) |
| 9 | Full HTTP stack | End-to-end integration |
| 10 | Regression | Existing behavior preserved (uses existing test style, not BDD) |
| 11 | Golden-file | API response shape snapshots for stable surfaces |
| 12 | Consumer contract | Contract tests from consumer perspective |
| 13 | Versioned integration | Old client requests against new service |

### Test Infrastructure Discovery

Before writing any test, the implementer scans existing test projects to discover:
- Test framework, assertion library, mocking library
- Setup patterns (builders, fixtures, factories)
- Integration test infrastructure (base classes, HTTP client, DB lifecycle)
- Naming conventions

New BDD-style tests use discovered conventions. Existing tests are **never refactored or restructured**. BDD applies to new code only.

A test's *subject* is application functionality, never a governance document -- see [`docs/policies/test-scope.md`](../policies/test-scope.md), which states the forbidden subjects once and is the only place they are stated.
