# Specification: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Implementation | Complete | Superseded

> **The review state of this document**, not the ticket's lifecycle state. `metadata.yaml`'s
> `status:` field is authoritative for the ticket; this line tracks how far *this document* has got.
> They are different vocabularies by design, and neither is a copy of the other.

## Problem Reference

See [problem.md](problem.md) for the full problem statement and acceptance criteria.

## Zachman Framework Grounding

This grid ensures the design is examined across all six interrogatives at the abstraction levels relevant to the project. Not every cell requires an entry -- fill in cells where the design makes a meaningful claim or decision.

### Org-Level Constants

{If your organization has a CLAIRE org configuration, copy its pre-filled Zachman constants here (Where, Who, Why). If not, leave this section empty and fill everything in the grid below from codebase exploration or the problem statement.}

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

## SCOUT Analysis

SCOUT (State, Constraints, Outputs, Updates, Triggers) decomposes each acceptance criterion into behavioral primitives. The spec-author fills this table; the test-plan.md scenarios are derived from it.

### SCOUT Decomposition

For each acceptance criterion from problem.md, decompose into SCOUT dimensions:

#### AC-1: {Acceptance criterion text from problem.md}

| Dimension | Description | Details |
|---|---|---|
| **State** | System state that must be true before the behavior executes | {E.g., "An active Order exists with at least one LineItem in Draft state"} |
| **Constraints** | Business invariants and domain logic that govern the behavior | {E.g., "An order cannot be submitted unless all line items have a valid price"} |
| **Outputs** | Observable outputs, notifications, or external system calls | {E.g., "Publishes order.submitted event; sends confirmation email"} |
| **Updates** | State changes to domain entities or persistent storage | {E.g., "Order.status changes from Draft to Submitted; Order.submittedAt set to current UTC"} |
| **Triggers** | Data, parameters, or events that trigger the behavior | {E.g., "POST /api/v1/orders/{id}/submit with valid auth token"} |

**Edge case derivation:** For each dimension, ask "what if this is violated?"

| Dimension | "What If" | Example Edge Case |
|---|---|---|
| State | Entity missing? Wrong state? Expired? | Order does not exist; Order already cancelled |
| Constraints | Invariant broken? Constraint exceeded? | No line items; total exceeds credit limit |
| Outputs | External service fails? Timeout? | Email service unreachable; event bus down |
| Updates | Concurrent modification? | Another user submitted the order simultaneously |
| Triggers | Null? Empty? Wrong type? Unauthorized? | Missing auth token; invalid order ID format |

#### AC-2: {Next acceptance criterion}

| Dimension | Description | Details |
|---|---|---|
| **State** | | {Fill in} |
| **Constraints** | | {Fill in} |
| **Outputs** | | {Fill in} |
| **Updates** | | {Fill in} |
| **Triggers** | | {Fill in} |

### SCOUT-to-BDD Mapping

Each SCOUT dimension maps to a behavioral test concern:

| SCOUT Dimension | BDD Role | Test Concern |
|---|---|---|
| State | Arrange / `Given` | Establish the system state the test requires |
| Constraints | Assertion / `Then` | The invariant being verified |
| Outputs | Assertion (external) | Verify calls to external services or event emissions |
| Updates | Assertion (internal) | Verify entity state changes and persistence |
| Triggers | Act / `When` | The action or event under test |

The test-plan.md translates each SCOUT decomposition into executable BDD scenarios. See [test-plan.md](test-plan.md) for the full specification.

---

## CLAIRE Facet Evaluation

Evaluate the proposed design against the governing facets selected for this project. If your organization has a CLAIRE org configuration with mandatory facets, include those first, then add any project-specific facets from the facet library. If two facets conflict, use the precedence matrix from your org config or the CLAIRE default: Data Integrity > Security Posture > Backwards Compatibility (when triggered) > Simplicity > Operability > DX (Agentic) > remaining facets.

A facet whose every measure is `Pass` may be written as `**All measures Pass.**` followed by its basis per measure group, instead of the full table below. Any `Flag` keeps the full table. The full table is always valid.

### Facet 1: Simplicity

| Measure | Target | This Design | Status |
|---|---|---|---|
| Runtime service count | Minimum needed | {Does this change add a new service? If yes, justify.} | {Pass/Flag} |
| State management layers | 1 (DB or primary store is source of truth) | {Does this change add a cache or secondary state store?} | {Pass/Flag} |
| Config to add a capability | Minimal (target from facet library) | {How many files must change to wire up the new behavior?} | {Pass/Flag} |

**Decision rule applied:** Between two approaches, did we pick the one that requires reading fewer files to understand?

**Anti-patterns checked:**
- [ ] No cache added without profiling evidence
- [ ] No shared utility library for single-project functions
- [ ] No abstract factory for config with only one implementation

### Facet 2: Operability

| Measure | Target | This Design | Status |
|---|---|---|---|
| CI pipeline impact | Target from facet library; uses standard CI templates | {Does this change affect pipeline jobs?} | {Pass/Flag} |
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

### Facet 3: Developer Experience -- Agentic Coding

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

### Facet 4: Data Integrity

| Measure | Target | This Design | Status |
|---|---|---|---|
| Audit coverage | 100% of write operations produce audit records | {Do all new mutations have audit records?} | {Pass/Flag} |
| Mutation metadata | Actor identity (from auth system, never user input) + reason | {Are actor and reason captured for every write?} | {Pass/Flag} |
| Multi-table write sequencing | Step order, failure handling, and cache invalidation documented | {See Proposed Design and SCOUT Outputs/Updates} | {Pass/Flag} |
| No client-side derived values | Server computes all derived values | {Does the API accept any pre-computed values from the client?} | {Pass/Flag} |

**Anti-patterns checked:**
- [ ] No fire-and-forget multi-step mutations
- [ ] No optimistic updates on multi-table writes
- [ ] No missing audit metadata fields
- [ ] No cascading deletes without user confirmation

### Facet 5: Backwards Compatibility (include when triggered — change touches registered public surfaces or introduces new ones)

| Measure | Target | This Design | Status |
|---|---|---|---|
| Surface registry current | All public surfaces registered, resolved across **every** registry present per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule: `docs/policies/surface-registry.md` (this project's own, **adopter-owned**) and `docs/policies/claire-surfaces.md` (the CLAIRE framework's, **core-owned**). A framework-owned surface records in the core-owned registry, never in the adopter-owned one. | {Are all affected surfaces registered? Any new surfaces to add?} | {Pass/Flag} |
| Breaking change handling | Deprecation plan with sunset date and migration guide | {See Compatibility Impact section} | {Pass/Flag} |
| Golden-file tests | Every stable API response shape has a snapshot test | {Are golden-file tests specified for affected endpoints?} | {Pass/Flag} |
| Consumer contract tests | Every inter-service dependency has a contract test | {Are contract tests specified for affected dependencies?} | {Pass/Flag} |
| Deprecation signals | HTTP headers, structured log warnings, metrics on deprecated surfaces | {Are runtime deprecation signals implemented for any deprecated surfaces?} | {Pass/Flag} |

**Decision rule applied:** Between two approaches, did we pick the one that does not require existing consumers to change?

**Anti-patterns checked:**
- [ ] No removal of response fields without checking consumer impact via surface registry
- [ ] No endpoint renames without API versioning
- [ ] No semantic changes to event payloads without version bump
- [ ] No new required fields added to existing request contracts
- [ ] No "fix consumers later" without a tracked deprecation entry

### Additional Facets

{Include any additional facets selected for this project (Security Posture, Performance Efficiency, Testability, Replaceability). Use the same format: measures table, decision rule, anti-pattern checklist. Refer to your facet library or org config for the project-specific measures.}

### Facet Conflict Resolution

{Document any cases where two facets disagreed and how the precedence matrix resolved it. E.g., "Data Integrity required an additional audit table (adds complexity), overriding Simplicity's preference for fewer tables -- justified because compliance is non-negotiable."}

---

## Observability Seams

Derived from SCOUT decomposition per the Observability Seams reference (`docs/agentic-sdlc/scout-reference.md`). Each seam becomes a test scenario and a production log event. See `docs/policies/observability-patterns.md` for JSON schemas and implementation patterns.

### Prior Production Findings

{Entries from `docs/agentic-sdlc/production-insights.md` relevant to this component. "None" if no prior findings exist.}

| PROD Entry | Category | SCOUT Dimension | Lesson Applied |
|---|---|---|---|
| PROD-{NNN} | {LOGIC_FAULT / LINEAGE_GAP / DRIFT_SIGNAL / SEAM_VIOLATION} | {Preconditions / Rules / Inputs / Side-effects / Mutations} | {How this spec addresses the prior finding} |

### Seam Specification

For each AC's SCOUT decomposition, derive the seams mechanically. Not every AC requires all seam types — only derive what the decomposition supports.

| AC | Dimension | Seam Type | Event Name | Trigger Condition | Severity |
|---|---|---|---|---|---|
| AC-1 | Preconditions | IMPOSSIBLE_STATE | {domain}.{op}.precondition_violated | {Specific condition under which precondition is false at runtime} | Critical |
| AC-1 | Rules | DECISION_DRIFT | {domain}.{op}.branch_distribution | {Rate outside [X%, Y%] over 1h window} | Warning |
| AC-1 | Side-effects | LINEAGE_GAP | {domain}.{op}.{checkpoint}_missing | {Trace completes without expected span} | Critical |
| AC-1 | Mutations | LINEAGE_GAP | {domain}.{op}.audit_missing | {Mutation committed without audit record} | Critical |

### Baseline Definitions (for DECISION_DRIFT seams)

{Only include if the spec has DECISION_DRIFT seams. Each baseline defines the expected distribution of a decision branch under normal traffic.}

| Event Name | Branch | Expected Rate | Threshold | Window |
|---|---|---|---|---|
| {domain}.{op}.branch_distribution | {branch_name} | {e.g., 0.85} | {e.g., 0.15} | {e.g., 1h} |

---

## Existing Code Analysis

{For greenfield projects, replace this section with "Architecture Decisions" documenting the key technology and pattern choices for the new system.}

### Files Affected

| File | Layer/Module | Change Type | Description |
|---|---|---|---|
| `{path/to/entity}` | {Domain / Model} | Modify | {What changes} |
| `{path/to/service}` | {Service / Logic} | Modify | {What changes} |
| `{path/to/controller}` | {API / Route} | Add | {New endpoint} |
| `{path/to/migration}` | {Data / Schema} | Add | {New migration} |

### Current Behavior

{Describe how the system currently behaves in the area being changed. Include relevant code paths, data flows, and integration points. Reference specific files and line numbers.}

### Dependencies

{List upstream and downstream dependencies that this change interacts with.}

- **Upstream:** {Services, APIs, or systems that feed data into the affected area}
- **Downstream:** {Services, APIs, or systems that consume output from the affected area}
- **Shared:** {Libraries, base classes, or utilities used by the affected code}

## Proposed Design

### Overview

{High-level description of the approach. Name the architectural pattern (layered, hexagonal, microservices, serverless, monolith, etc.) and how this change fits within it.}

### Layer / Module Changes

{For each affected layer or module in the project's architecture, describe the changes. Adapt the subsections below to match your project's structure -- e.g., Domain/Application/API/Data for Clean Architecture, or Routes/Handlers/Models for an MVC app, or Functions/Events for serverless.}

#### {Layer/Module 1 Name}

{New or modified entities, interfaces, types, or configurations.}

```
// Example: new type, modified interface, or configuration
```

#### {Layer/Module 2 Name}

{New or modified services, validators, handlers, or business logic.}

```
// Example: service method signature, handler definition
```

#### {API / Route Layer}

{New or modified endpoints, DTOs, request/response models, authorization.}

```
// Example: endpoint definition
{HTTP_METHOD} /api/v1/{resource}
Request: { ... }
Response: { ... }
```

#### {Data Layer}

{Schema changes, migrations, seed data.}

```sql
-- Example: schema change
```

### Integration Changes

{Changes to external service clients, new client interfaces, event publishers/subscribers.}

## Design Exploration

Filled by the spec-author at step 12 by converging against the explorer's independent option set in `design-options.md`. If that artifact is absent, replace this whole section body with the not-performed marker below -- never leave it blank, and never fill it as though exploration ran.

**Option set source:** design-options.md (explorer, independent) | NOT PERFORMED

| Option | Structure (one line) | Novelty class | Facet fit summary |
|---|---|---|---|
| {A -- name} | {where responsibility sits} | {established/adjacent/novel} | {how it lands against the facets} |

**Winner:** {the option, named as the explorer named it}
**Winning axis over the runner-up:** {name the runner-up AND the facet -- not a generic dismissal}
**Testable flip-condition:** {what would have to become true to reverse this -- checkable by someone other than the author}
**Strongest objection to the chosen option:** {stated as strongly as the explorer steelmanned it}
**Domestication follow-up:** {only if the winner is the novel option: success -> ADR -> local pattern -> baseline}
**Gate 1 outcome:** {filled at Spec Review by the reviewer; see human-gates.md Gate 1 Feedback Loop}

Not-performed marker, used **verbatim** when `design-options.md` is absent:

_Design Exploration NOT PERFORMED -- no independent option set exists for this ticket; what follows in Alternatives Considered is a SELF-AUTHORED fallback. Do not read this as "the option space was explored."_

## Alternatives Considered

At Medium and High tier this section is **derived from the Design Exploration convergence above** -- it records how the runner-up options lost, not a set the author invented after choosing. Where the not-performed marker is present, it is a self-authored fallback and says so.

### Alternative 1: {Name}

- **Approach:** {Brief description}
- **Pros:** {Why it could work}
- **Cons:** {Why it was not chosen}

### Alternative 2: {Name}

- **Approach:** {Brief description}
- **Pros:** {Why it could work}
- **Cons:** {Why it was not chosen}

## Migration Strategy

{If this change requires data migration, schema migration, or feature flagging, describe the rollout plan.}

- **Breaking changes:** {Yes/No -- describe if yes}
- **Migration required:** {Yes/No -- describe steps}
- **Feature flag:** {Yes/No -- flag name and conditions}
- **Rollback plan:** {How to revert if deployment fails}

## Compatibility Impact

Reference: [Adopter surfaces](../../docs/policies/surface-registry.md) | [CLAIRE framework surfaces](../../docs/policies/claire-surfaces.md) | [Deprecation Policy](../../docs/policies/deprecation-policy.md)

### Public Surface Changes

{For each public surface affected by this change, document the impact. If no public surfaces are affected, state "No public surfaces affected by this change."}

| Surface | Type | Change | Breaking? | Deprecation Required? |
|---|---|---|---|---|
| {endpoint, event, DTO, config key} | API / Event / Schema / Config | Added / Modified / Removed | Yes / No | Yes / No |

### New Public Surfaces

{Any new APIs, events, schemas, or configuration keys that should be registered in the surface registry. If none, state "No new public surfaces introduced."}

| Surface | Type | Stability | Guarantee Period | Consumers |
|---|---|---|---|---|
| {endpoint, event, DTO, config key} | API / Event / Schema / Config | Stable / Beta | {e.g., 2 release cycles} | {known or expected consumers} |

### Deprecation Plan

{For any breaking changes to existing stable surfaces. If no breaking changes, state "No deprecations required."}

| Surface | Current Version | Deprecated Version | Sunset Date | Migration Guide |
|---|---|---|---|---|
| {surface} | {current} | {deprecated} | {target date} | {link to docs/migrations/ or inline} |

### Compatibility Test Requirements

{Map each affected surface to the compatibility tests that must be implemented.}

| Test Type | Surface | Description |
|---|---|---|
| Golden-file | {endpoint/event} | Snapshot of response shape for regression detection |
| Consumer contract | {service dependency} | Contract test verifying producer meets consumer expectations |
| Versioned integration | {endpoint} | Old client request against new service response |

## Risks and Open Questions

### Risks

| Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|
| {Description} | High/Medium/Low | High/Medium/Low | {How to mitigate} |

### Open Questions

**Gate 1 rulings:** required -- one ruling line per OQ in decisions.md (human-gates.md Gate 1).

- [ ] **OQ-1:** {Question that needs resolution before or during implementation}
- [ ] **OQ-2:** {Assign to a person or role if known}

## Cross-References

- **Problem:** [problem.md](problem.md)
- **Test Plan:** [test-plan.md](test-plan.md)
- **Decisions:** [decisions.md](decisions.md)
- **ADRs:** {Link to any ADRs created as part of this spec}
- **Related Specs:** {Link to specs for related or dependent work}
