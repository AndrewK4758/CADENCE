# Specification: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Implementation | Complete | Superseded

> **Document review status**, distinct from the ticket's lifecycle state. `metadata.yaml`'s
> `status:` field is authoritative for the ticket; this line tracks how far *this document* has progressed.
> They are separate vocabularies by design, and neither is a copy of the other.

## Problem Reference

See [problem.md](problem.md) for the complete problem statement and acceptance criteria.

## Contextual Grounding Matrix (6W×4L)

This matrix ensures the proposed design is grounded across all six interrogatives at the four abstraction layers relevant to the system. Not every cell requires an entry -- populate cells where the design makes a concrete architectural claim or decision.

### Org-Level Constants

{If your organization maintains a CADENCE organization configuration (`CADENCE_ORG.md`), copy its pre-populated Contextual Grounding constants here (Where, Who, Why). Otherwise, leave this subsection empty and populate the matrix below from codebase exploration or the problem statement.}

### Scope (Planner / Business Context)

| What (Data) | How (Function) | Where (Network) | Who (People) | When (Time) | Why (Motivation) |
|---|---|---|---|---|---|
| {What business entities are involved?} | {What business processes change?} | {Where in the system landscape does this operate?} | {Who are the actors?} | {What temporal aspects matter?} | {Why does this exist? Link back to business driver from problem.md} |

### Business Model (Owner / Domain Model)

| What (Data) | How (Function) | Where (Network) | Who (People) | When (Time) | Why (Motivation) |
|---|---|---|---|---|---|
| {Domain entities and relationships} | {Domain operations and workflows} | {Service boundaries and external integrations} | {Authorization model and role-based access} | {Lifecycle states and transitions} | {Domain rules and invariants} |

### System Model (Designer / Application Architecture)

| What (Data) | How (Function) | Where (Network) | Who (People) | When (Time) | Why (Motivation) |
|---|---|---|---|---|---|
| {Data structures, DTOs, schema changes} | {Service methods, API endpoints, validation rules} | {Inter-service communication, protocols, transports} | {Auth policies, roles, claims required} | {Temporal queries, caching TTLs, scheduling} | {Design rationale for system-level decisions} |

### Technology Model (Builder / Implementation)

| What (Data) | How (Function) | Where (Network) | Who (People) | When (Time) | Why (Motivation) |
|---|---|---|---|---|---|
| {ORM entities, migrations, column types} | {Classes, methods, validation rules, mappers} | {Connection strings, endpoint URLs, message queues} | {Auth scopes, JWT claims, middleware config} | {Temporal tables, background job schedules} | {Technology choices and constraints} |

## CHORD Analysis

CHORD (**C**onditions, **H**andling / Triggers, **O**utcomes, **R**ules, **D**eltas) decomposes every acceptance criterion into testable behavioral primitives. The `cadence-spec-author` agent populates this analysis, and the Gherkin scenarios in `test-plan.md` are derived directly from it.

### CHORD Decomposition

For each acceptance criterion from `problem.md`, decompose into the five CHORD dimensions:

#### AC-1: {Acceptance criterion text from problem.md}

| Dimension | Description | Details |
|---|---|---|
| **Conditions** | System state and preconditions that must hold before execution (`Given`) | {E.g., "An active Order exists with at least one LineItem in Draft state"} |
| **Handling** | Input parameters, commands, or events that trigger the behavior (`When`) | {E.g., "POST /api/v1/orders/{id}/submit with valid auth token"} |
| **Outcomes** | Observable external responses, notifications, or downstream calls (`Then` — external) | {E.g., "Publishes order.submitted event; sends confirmation email"} |
| **Rules** | Business invariants and domain constraints governing the behavior (`Then` — invariants) | {E.g., "An order cannot be submitted unless all line items have a valid price"} |
| **Deltas** | Internal state mutations to domain entities or persistent storage (`Then` — internal) | {E.g., "Order.status changes from Draft to Submitted; Order.submittedAt set to current UTC"} |

**Edge case derivation:** For each CHORD dimension, ask "what happens if this dimension is violated?"

| Dimension | "What If" | Example Edge Case |
|---|---|---|
| Conditions | Entity missing? Wrong state? Expired? | Order does not exist; Order already cancelled |
| Handling | Null? Empty? Wrong type? Unauthorized? | Missing auth token; invalid order ID format |
| Outcomes | External service fails? Timeout? | Email service unreachable; event bus down |
| Rules | Invariant broken? Constraint exceeded? | No line items; total exceeds credit limit |
| Deltas | Concurrent modification? | Another user submitted the order simultaneously |

#### AC-2: {Next acceptance criterion}

| Dimension | Description | Details |
|---|---|---|
| **Conditions** | | {Fill in} |
| **Handling** | | {Fill in} |
| **Outcomes** | | {Fill in} |
| **Rules** | | {Fill in} |
| **Deltas** | | {Fill in} |

### CHORD-to-BDD Mapping

Each CHORD dimension maps directly to a behavioral test concern:

| CHORD Dimension | BDD Role | Test Concern |
|---|---|---|
| Conditions | Arrange / `Given` | Establish the required initial system state |
| Handling | Act / `When` | Execute the action, request, or event under test |
| Outcomes | Assertion (external) / `Then` | Verify external service calls, responses, or event emissions |
| Rules | Assertion (invariant) / `Then` | Verify domain invariants and business rules hold |
| Deltas | Assertion (internal) / `Then` | Verify entity mutations and persistent state updates |

`test-plan.md` translates each CHORD decomposition into executable BDD scenarios. See [test-plan.md](test-plan.md) for the full scenario suite.

---

## CADENCE Pillar Evaluation

Evaluate the proposed design against the governing engineering pillars active for this repository. When your organization maintains a `CADENCE_ORG.md` configuration with mandatory pillars, include those first, followed by any repository-specific pillars from the pillar library. When two pillars conflict, resolve the trade-off using the precedence order from your organization configuration or the CADENCE default: Data & Audit Fidelity > Security Boundary Posture > Surface Compatibility (when triggered) > Structural Simplicity > Operational Resilience > Agentic Ergonomics > remaining pillars.

A pillar whose every measure evaluates to `Pass` may be condensed to `**All measures Pass.**` followed by a brief justification per measure group, in place of the full table below. Any `Flag` requires retaining the full table. The full table is always valid.

### Pillar 1: Structural Simplicity

| Measure | Target | This Design | Status |
|---|---|---|---|
| Runtime service count | Minimum needed | {Does this change add a new service? If yes, justify.} | {Pass/Flag} |
| State management layers | 1 (DB or primary store is source of truth) | {Does this change add a cache or secondary state store?} | {Pass/Flag} |
| Config to add a capability | Minimal (target from pillar library) | {How many files must change to wire up the new behavior?} | {Pass/Flag} |

**Decision rule applied:** Between two valid designs, did we select the one that requires reading fewer files to understand?

**Anti-patterns checked:**
- [ ] No cache added without profiling evidence
- [ ] No shared utility library for single-project functions
- [ ] No abstract factory for config with only one implementation

### Pillar 2: Operational Resilience

| Measure | Target | This Design | Status |
|---|---|---|---|
| CI pipeline impact | Target from pillar library; uses standard CI templates | {Does this change affect pipeline jobs?} | {Pass/Flag} |
| Secrets handling | All via secrets manager; zero in env vars or source code | {Does this change introduce or reference secrets?} | {Pass/Flag} |
| Health check coverage | All dependencies checked | {Does this change add a new dependency that needs a health check?} | {Pass/Flag} |
| Logging | Structured JSON to stdout with trace/span/request IDs | {Do new log statements include correlation IDs?} | {Pass/Flag} |
| Distributed tracing | W3C Trace Context propagated on inter-service calls | {Do new service calls propagate trace context?} | {Pass/Flag} |
| Metrics | Request count, latency histogram, error rate for new endpoints | {Are metrics emitted for new endpoints?} | {Pass/Flag} |
| Alert coverage | Latency/error alerts for new dependencies and critical paths | {Are alert rules defined?} | {Pass/Flag} |
| Rollback plan | Documented; tested before go-live | {See Migration Strategy section} | {Pass/Flag} |

**Anti-patterns checked:**
- [ ] No custom CI scripts duplicating standard template functionality
- [ ] No secrets in source-controlled files
- [ ] No unstructured log strings
- [ ] No log lines missing trace/request correlation IDs
- [ ] No new endpoints without latency and error rate metrics
- [ ] No new external dependencies without health-check integration and alerting
- [ ] No observability deferred to a follow-up ticket

### Pillar 3: Agentic Ergonomics

| Measure | Target | This Design | Status |
|---|---|---|---|
| File size (authored artifacts) | <400 lines per file | {Will any modified or new authored file exceed 400 lines?} | {Pass/Flag} |
| File size (scenario-indexed BDD harness) | No whole-file ceiling; scenario function <=150 lines, any function <=400 | {Which governed unit applies, and does every function meet it?} | {Pass/Flag} |
| Pattern consistency | New instances follow existing template exactly | {Can an agent produce this by reading 1 existing example?} | {Pass/Flag} |
| Naming conventions | Project conventions followed | {Any naming deviations?} | {Pass/Flag} |

**Decision rule applied:** Would an agent need to read more than 5 files to understand how to add a similar capability? If yes, reduce indirection.

**Anti-patterns checked:**
- [ ] No god files (multiple concerns in one file)
- [ ] No dynamic imports or metaprogramming hiding the call graph
- [ ] No implicit conventions only documented outside the repo

### Pillar 4: Data & Audit Fidelity

| Measure | Target | This Design | Status |
|---|---|---|---|
| Audit coverage | 100% of write operations produce audit records | {Do all new mutations have audit records?} | {Pass/Flag} |
| Mutation metadata | Actor identity (from auth system, never user input) + reason | {Are actor and reason captured for every write?} | {Pass/Flag} |
| Multi-table write sequencing | Step order, failure handling, and cache invalidation documented | {See Proposed Design and CHORD Outcomes/Deltas} | {Pass/Flag} |
| No client-side derived values | Server computes all derived values | {Does the API accept any pre-computed values from the client?} | {Pass/Flag} |

**Anti-patterns checked:**
- [ ] No fire-and-forget multi-step mutations
- [ ] No optimistic updates on multi-table writes
- [ ] No missing audit metadata fields
- [ ] No cascading deletes without user confirmation

### Pillar 5: Surface Compatibility (include when triggered — change touches registered public surfaces or introduces new ones)

| Measure | Target | This Design | Status |
|---|---|---|---|
| Surface registry current | All public surfaces registered, resolved across **every** registry present per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule: `docs/policies/surface-registry.md` (this project's own, **adopter-owned**) and `docs/policies/cadence-surfaces.md` (the CADENCE framework's, **core-owned**). A framework-owned surface records in the core-owned registry, never in the adopter-owned one. | {Are all affected surfaces registered? Any new surfaces to add?} | {Pass/Flag} |
| Breaking change handling | Deprecation plan with sunset date and migration guide | {See Compatibility Impact section} | {Pass/Flag} |
| Golden-file tests | Every stable API response shape has a snapshot test | {Are golden-file tests specified for affected endpoints?} | {Pass/Flag} |
| Consumer contract tests | Every inter-service dependency has a contract test | {Are contract tests specified for affected dependencies?} | {Pass/Flag} |
| Deprecation signals | HTTP headers, structured log warnings, metrics on deprecated surfaces | {Are runtime deprecation signals implemented for any deprecated surfaces?} | {Pass/Flag} |

**Decision rule applied:** Between two designs, did we select the one that does not require existing consumers to change?

**Anti-patterns checked:**
- [ ] No removal of response fields without checking consumer impact via surface registry
- [ ] No endpoint renames without API versioning
- [ ] No semantic changes to event payloads without version bump
- [ ] No new required fields added to existing request contracts
- [ ] No "fix consumers later" without a tracked deprecation entry

### Additional Pillars

{Include any additional pillars active for this repository (Security Boundary Posture, Execution Performance, Automated Verifiability, Modular Replaceability, Origin Confidentiality). Follow the identical layout: measures table, decision rule, and anti-pattern checklist. Refer to your pillar library or `CADENCE_ORG.md` for repository-specific measures.}

### Pillar Conflict Resolution

{Document any trade-offs where two pillars conflicted and how the precedence matrix resolved the disagreement. E.g., "Data & Audit Fidelity required an additional audit ledger table (adding schema surface), overriding Structural Simplicity's preference for fewer tables -- justified because auditability is non-negotiable."}

---

## Observability Seams

Derived mechanically from the CHORD decomposition per the Observability Seams guide (`docs/agentic-sdlc/chord-reference.md`). Every seam translates into both a BDD test scenario and a structured production log event. See `docs/policies/observability-patterns.md` for JSON schemas and runtime emission patterns.

### Prior Production Findings

{Entries from `docs/agentic-sdlc/production-insights.md` relevant to this component. State "None" if no prior findings apply.}

| PROD Entry | Category | CHORD Dimension | Lesson Applied |
|---|---|---|---|
| PROD-{NNN} | {LOGIC_FAULT / DELTA_AUDIT_GAP / DRIFT_SIGNAL / BOUNDARY_FAULT} | {Conditions / Rules / Handling / Outcomes / Deltas} | {How this specification addresses the prior finding} |

### Seam Specification

For each acceptance criterion's CHORD decomposition, derive the applicable seams mechanically. Not every criterion requires all four seam families — derive only what the behavioral decomposition supports.

| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-1 | Conditions | UNSOUND_CONDITION | {domain}.{op}.precondition_violated | {Specific condition under which precondition is false at runtime} | Critical |
| AC-1 | Rules | RULE_DIVERGENCE | {domain}.{op}.branch_distribution | {Rate outside [X%, Y%] over 1h window} | Warning |
| AC-1 | Outcomes | DELTA_AUDIT_GAP | {domain}.{op}.{checkpoint}_missing | {Trace completes without expected span} | Critical |
| AC-1 | Deltas | DELTA_AUDIT_GAP | {domain}.{op}.audit_missing | {Mutation committed without audit record} | Critical |

### Baseline Definitions (for RULE_DIVERGENCE seams)

{Include only when the specification declares `RULE_DIVERGENCE` seams. Each baseline defines the expected branch distribution under normal production traffic.}

| Event Name | Branch | Expected Rate | Threshold | Window |
|---|---|---|---|---|
| {domain}.{op}.branch_distribution | {branch_name} | {e.g., 0.85} | {e.g., 0.15} | {e.g., 1h} |

---

## Existing Code Analysis

{For greenfield repositories, replace this section with "Architecture Decisions" capturing the foundational technology and structural choices for the new system.}

### Files Affected

| File | Layer/Module | Change Type | Description |
|---|---|---|---|
| `{path/to/entity}` | {Domain / Model} | Modify | {What changes} |
| `{path/to/service}` | {Service / Logic} | Modify | {What changes} |
| `{path/to/controller}` | {API / Route} | Add | {New endpoint} |
| `{path/to/migration}` | {Data / Schema} | Add | {New migration} |

### Current Behavior

{Describe how the system currently operates in the affected area. Cite concrete code paths, data flows, integration boundaries, and `file:line` references.}

### Dependencies

{List upstream and downstream dependencies interacting with this change.}

- **Upstream:** {Services, APIs, or pipelines supplying data into the affected area}
- **Downstream:** {Services, APIs, or consumers reading output from the affected area}
- **Shared:** {Libraries, base types, or helpers referenced by the affected modules}

## Proposed Design

### Overview

{High-level summary of the technical approach. Name the governing architectural style (layered, hexagonal, microservices, event-driven, monolith, etc.) and explain how this change fits within it.}

### Layer / Module Changes

{For each affected layer or module in the repository's architecture, specify the changes. Adapt the subsections below to match your project's structure -- e.g., Domain/Application/API/Data for Clean Architecture, Routes/Handlers/Models for an MVC service, or Functions/Events for serverless.}

#### {Layer/Module 1 Name}

{New or modified domain entities, interfaces, types, or configurations.}

```
// Example: new type, modified interface, or configuration
```

#### {Layer/Module 2 Name}

{New or modified services, validators, handlers, or domain logic.}

```
// Example: service method signature, handler definition
```

#### {API / Route Layer}

{New or modified endpoints, DTOs, request/response contracts, authorization attributes.}

```
// Example: endpoint definition
{HTTP_METHOD} /api/v1/{resource}
Request: { ... }
Response: { ... }
```

#### {Data Layer}

{Schema modifications, migrations, index additions, or seed data.}

```sql
-- Example: schema change
```

### Integration Changes

{Updates to external service clients, new client contracts, or event publishers/subscribers.}

## Design Exploration

Populated by `cadence-spec-author` at step 12 by converging against the `cadence-explorer` agent's independent option set in `design-options.md`. When `design-options.md` is absent, replace this entire section body with the verbatim not-performed marker below -- never leave this section empty, and never populate it as if independent exploration occurred.

**Option set source:** design-options.md (explorer, independent) | NOT PERFORMED

| Option | Structure (one line) | Novelty class | Pillar fit summary |
|---|---|---|---|
| {A -- name} | {where responsibility sits} | {established/adjacent/novel} | {how it lands against the engineering pillars} |

**Winner:** {the chosen option, named exactly as the explorer named it}
**Winning axis over the runner-up:** {name both the runner-up option AND the decisive engineering pillar -- never a generic dismissal}
**Testable flip-condition:** {what concrete fact would have to change to reverse this choice -- verifiable by someone other than the author}
**Strongest objection to the chosen option:** {stated at full steelmanned strength from the explorer's analysis}
**Domestication follow-up:** {only when the chosen winner is the novel option: success -> ADR -> local pattern -> baseline}
**Gate 1 outcome:** {recorded at Spec Review by the human reviewer; see `human-gates.md` Gate 1 Feedback Loop}

Not-performed marker, used **verbatim** when `design-options.md` is absent:

_Design Exploration NOT PERFORMED -- no independent option set exists for this ticket; what follows in Alternatives Considered is a SELF-AUTHORED fallback. Do not read this as "the option space was explored."_

## Alternatives Considered

At Medium and High tiers this section is **derived directly from the Design Exploration convergence above** -- it documents why the runner-up options were not selected, rather than inventing post-hoc strawmen after choosing. Whenever the not-performed marker is present above, this section is a self-authored fallback and explicitly states so.

### Alternative 1: {Name}

- **Approach:** {Brief description}
- **Pros:** {Why it is viable}
- **Cons:** {Why it lost to the chosen design}

### Alternative 2: {Name}

- **Approach:** {Brief description}
- **Pros:** {Why it is viable}
- **Cons:** {Why it lost to the chosen design}

## Migration Strategy

{When this change involves data migration, schema evolution, or feature-flag rollout, specify the execution and rollback plan.}

- **Breaking changes:** {Yes/No -- detail if yes}
- **Migration required:** {Yes/No -- list expand/contract steps}
- **Feature flag:** {Yes/No -- flag key and activation conditions}
- **Rollback plan:** {Exact steps to revert safely if deployment fails}

## Compatibility Impact

Reference: [Adopter surfaces](../../docs/policies/surface-registry.md) | [CADENCE framework surfaces](../../docs/policies/cadence-surfaces.md) | [Deprecation Policy](../../docs/policies/deprecation-policy.md)

### Public Surface Changes

{Document the impact on every public surface touched by this change. When no public surfaces are affected, write "No public surfaces affected by this change."}

| Surface | Type | Change | Breaking? | Deprecation Required? |
|---|---|---|---|---|
| {endpoint, event, DTO, config key} | API / Event / Schema / Config | Added / Modified / Removed | Yes / No | Yes / No |

### New Public Surfaces

{List any new APIs, events, schemas, or configuration keys that must be added to the surface registry. When none are introduced, write "No new public surfaces introduced."}

| Surface | Type | Stability | Guarantee Period | Consumers |
|---|---|---|---|---|
| {endpoint, event, DTO, config key} | API / Event / Schema / Config | Stable / Beta | {e.g., 2 release cycles} | {known or expected consumers} |

### Deprecation Plan

{Complete for any breaking modifications or removals of existing stable surfaces. When no breaking changes exist, write "No deprecations required."}

| Surface | Current Version | Deprecated Version | Sunset Date | Migration Guide |
|---|---|---|---|---|
| {surface} | {current} | {deprecated} | {target date} | {link to docs/migrations/ or inline} |

### Compatibility Test Requirements

{Map every affected surface to the compatibility test suites required to guard it.}

| Test Type | Surface | Description |
|---|---|---|
| Golden-file | {endpoint/event} | Snapshot of response/payload shape for regression detection |
| Consumer contract | {service dependency} | Contract test verifying producer satisfies consumer expectations |
| Versioned integration | {endpoint} | Replay of prior-version client request against current service response |

## Risks and Open Questions

### Risks

| Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|
| {Description} | High/Medium/Low | High/Medium/Low | {How to mitigate} |

### Open Questions

**Gate 1 rulings:** required -- one ruling line per OQ in decisions.md (human-gates.md Gate 1).

- [ ] **OQ-1:** {Question requiring human resolution before or during implementation}
- [ ] **OQ-2:** {Assign to a specific person or role where known}

## Cross-References

- **Problem:** [problem.md](problem.md)
- **Test Plan:** [test-plan.md](test-plan.md)
- **Decisions:** [decisions.md](decisions.md)
- **ADRs:** {Links to any ADRs authored or referenced by this spec}
- **Related Specs:** {Links to specifications for related or dependent tickets}
