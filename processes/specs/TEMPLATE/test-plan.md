# Test Plan: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Executing | Complete

> **The review state of this document**, not the ticket's lifecycle state. `metadata.yaml`'s
> `status:` field is authoritative for the ticket; this line tracks how far *this document* has got.
> They are different vocabularies by design, and neither is a copy of the other -- `Executing` above
> is a state of this plan, and has no counterpart in the ticket lifecycle.

## References

- **Problem:** [problem.md](problem.md) -- acceptance criteria drive every scenario
- **Spec:** [spec.md](spec.md) -- SCOUT analysis decomposes each AC into testable dimensions

## Test Strategy

### Approach: BDD-First with Red-Green-Refactor

Tests for new code are written **before** implementation. Each BDD scenario must:
1. **Red** -- compile (with stubs if needed) and fail, proving the behavior is not yet implemented
2. **Green** -- pass after writing the minimum implementation code
3. **Accumulate** -- all previous tests (including pre-existing tests) must still pass after each new implementation

BDD style applies to **new code only**. Existing tests are not refactored into BDD style. Pre-existing test conventions, frameworks, and patterns are preserved as-is.

### Scope

- **In scope:** {What this test plan covers}
- **Out of scope:** {What is explicitly not tested here -- e.g., "UI rendering, handled by manual review"}

### Test Infrastructure Discovery

Before writing any tests, the implementer must scan the existing test code to discover:

- **Test framework:** {Discovered at implementation time -- e.g., pytest, Jest, xUnit, Go testing, RSpec, JUnit}
- **Assertion style:** {Discovered at implementation time -- e.g., built-in assert, Chai expect, Hamcrest matchers, FluentAssertions}
- **Mocking approach:** {Discovered at implementation time -- e.g., unittest.mock, Jest mocks, testdoubles, Mockito}
- **Test data patterns:** {Discovered at implementation time -- e.g., factories, fixtures, builders, inline setup}
- **Integration test infrastructure:** {Discovered at implementation time -- e.g., Testcontainers, in-memory DB, httptest, Supertest}
- **Naming conventions:** {Discovered at implementation time -- e.g., test_verb_condition, should_verb_when, Given_When_Then}
- **File organization:** {Discovered at implementation time -- e.g., co-located with source, separate test directory, mirrored structure}

The implementer records these findings in the test infrastructure section below and writes all new tests using the discovered conventions.

### Test Levels

| Level | Coverage Target | Location |
|---|---|---|
| Unit (BDD) | Service logic, validators, mappers, domain rules | {Discovered at implementation time} |
| Integration (BDD) | API endpoints, database operations, auth policies | {Discovered at implementation time} |
| Compatibility | API shape regression, consumer contracts, version compat | {Discovered at implementation time} |
| Manual | End-to-end user flows | Reviewer verification in non-prod environment |

---

## Acceptance Criteria Coverage

Map each acceptance criterion to its SCOUT decomposition (from spec.md) and the BDD feature that tests it.

| AC # | Acceptance Criterion | SCOUT Source | Feature | Scenarios | Level | Compatibility Tests |
|---|---|---|---|---|---|---|
| AC-1 | {Criterion from problem.md} | spec.md AC-1 | Feature 1 | S-1.1, S-1.2, S-1.3 | Unit | {Golden: endpoint; Contract: dependency — or N/A} |
| AC-2 | {Criterion from problem.md} | spec.md AC-2 | Feature 2 | S-2.1, S-2.2, S-2.3, S-2.4 | Unit + Integration | {Golden: endpoint; Versioned: v1 compat — or N/A} |
| AC-3 | {Criterion from problem.md} | spec.md AC-3 | Feature 3 | S-3.1 | Integration | {N/A — no public surface affected} |

---

## BDD Features

### Feature 1: {Feature name derived from AC-1}

```gherkin
Feature: {Feature name}
  As a {role from Zachman Who/People}
  I want {capability from AC-1}
  So that {business motivation from Zachman Why/Motivation}

  Background:
    Given {common precondition shared by all scenarios in this feature}

  # --- Happy Path ---

  Rule: {Business rule from SCOUT Constraints for AC-1}

    Scenario: S-1.1 -- {Descriptive name for the primary success path}
      Given {state from SCOUT -- entity state, configuration}
      And {additional precondition if needed}
      When {trigger from SCOUT -- API call, service method, event}
      Then {update from SCOUT -- entity state change verified}
      And {output from SCOUT -- external call verified}

    Scenario: S-1.2 -- {Variation on the happy path}
      Given {different precondition}
      When {same or similar action}
      Then {expected outcome for this variation}

  # --- Edge Cases ---

  Rule: {Boundary or constraint rule from SCOUT}

    Scenario: S-1.3 -- {Edge case name -- boundary condition}
      Given {edge case precondition -- empty collection, max value, null reference}
      When {action that triggers boundary behavior}
      Then {expected graceful handling -- validation error, empty result, default}

  # --- Error Scenarios ---

    Scenario: S-1.4 -- {Error scenario name -- invalid input}
      Given {standard precondition}
      When {invalid input from SCOUT Triggers -- missing field, wrong type, out of range}
      Then {validation failure with specific message}
      And {no mutation occurs -- entity state unchanged}
      And {no side-effect occurs -- external service not called}
```

### Feature 2: {Feature name derived from AC-2}

```gherkin
Feature: {Feature name}
  As a {role}
  I want {capability from AC-2}
  So that {business motivation}

  # --- Happy Path ---

  Rule: {Business rule from SCOUT Constraints for AC-2}

    Scenario Outline: S-2.1 -- {Parameterized happy path}
      Given a {entity} in <initial_state> state
      And {other precondition}
      When {action} is performed with <parameter>
      Then the {entity} state should be <expected_state>
      And {mutation or side-effect}

      Examples:
        | initial_state | parameter | expected_state |
        | Draft         | value_a   | Active         |
        | Active        | value_b   | Archived       |
        | Archived      | value_c   | Active         |

  # --- Edge Cases ---

    Scenario: S-2.2 -- {Concurrent modification}
      Given {entity} exists in a known state
      And another process has modified the {entity} since it was read
      When {action} is attempted
      Then a concurrency conflict is returned
      And the original state is preserved

  # --- Error Scenarios ---

    Scenario: S-2.3 -- {Authorization failure}
      Given a user without the required {role/permission}
      When {action} is attempted
      Then an authorization failure is returned
      And no state changes occur

    Scenario: S-2.4 -- {Entity not found}
      Given no {entity} exists with the specified ID
      When {action} is attempted
      Then a failure result is returned with message "{Entity} with ID '{id}' not found."
```

### Feature 3: {Feature name derived from AC-3 -- integration level}

```gherkin
Feature: {Feature name}
  As a {role}
  I want {capability from AC-3}
  So that {business motivation}

  # Integration-level scenarios test the full request stack

    Scenario: S-3.1 -- {End-to-end API operation}
      Given {entity} exists in the data store with {precondition state}
      And the user has valid credentials with {required permissions}
      When a {HTTP_METHOD} request is sent to /api/v1/{resource}/{id}
      Then the response status code is {expected status}
      And the response body contains {expected fields}
      And the data store reflects {expected state changes}
```

---

## Observability Seam Scenarios

Derived from the Observability Seams section of spec.md. Each seam is a testable behavior that verifies production monitoring will detect divergence from specified behavior. See `docs/policies/observability-patterns.md` for the four standard seam types.

If the spec's Observability Seams table is empty or has "None," omit this section.

### Feature: Observability Seams

```gherkin
Feature: Production observability seams
  As a platform operator
  I want runtime assertions at SCOUT dimension boundaries
  So that production divergence from spec is detectable without human observation

  # --- IMPOSSIBLE_STATE seams (from Preconditions) ---

  Rule: Precondition violations are detected and logged at runtime

    Scenario: OS-{N}.1 -- Precondition violation emits IMPOSSIBLE_STATE event
      Given {entity} exists in {state that violates the precondition}
      And the system bypasses normal validation (direct invocation / race condition)
      When {operation} is attempted
      Then a structured log event is emitted with seam_type "IMPOSSIBLE_STATE"
      And the event includes event_name "{domain}.{op}.precondition_violated"
      And the event includes expected_state "{valid state}" and actual_state "{invalid state}"
      And the operation is rejected

    Scenario: OS-{N}.2 -- Normal operation does not trigger IMPOSSIBLE_STATE
      Given {entity} exists in {valid state}
      When {operation} is performed successfully
      Then no IMPOSSIBLE_STATE event is emitted

  # --- DECISION_DRIFT seams (from Rules with branching) ---

  Rule: Branch decisions emit metrics for distribution monitoring

    Scenario: OS-{N}.3 -- Branch decision emits metric counter
      Given {conditions that cause branch A to be taken}
      When {operation} is performed
      Then the metric seam_decision_branch_total increments with branch_taken="A"

    Scenario: OS-{N}.4 -- Alternative branch emits its own metric
      Given {conditions that cause branch B to be taken}
      When {operation} is performed
      Then the metric seam_decision_branch_total increments with branch_taken="B"

  # --- LINEAGE_GAP seams (from Side-effects and Mutations) ---

  Rule: Missing side-effects and audit records are detected

    Scenario: OS-{N}.5 -- Missing side-effect emits LINEAGE_GAP event
      Given {entity} in valid state for {operation}
      And {external service / event bus} is configured to silently fail (no error, no execution)
      When {operation} completes
      Then a structured log event is emitted with seam_type "LINEAGE_GAP"
      And the event includes gap_type "side_effect_missing"
      And the event identifies the missing checkpoint "{expected span name}"

    Scenario: OS-{N}.6 -- Missing audit record emits LINEAGE_GAP event
      Given {entity} in valid state for {operation}
      And the audit subsystem is configured to silently fail
      When {operation} completes and the mutation is committed
      Then a structured log event is emitted with seam_type "LINEAGE_GAP"
      And the event includes gap_type "mutation_audit_missing"
```

---

## Compatibility Tests

Compatibility tests verify that changes do not break existing consumers. These are derived from the "Compatibility Impact" section of spec.md and the surface registries -- [adopter-owned](../../docs/policies/surface-registry.md) and [core-owned](../../docs/policies/claire-surfaces.md). If no public surfaces are affected by this change, state "No compatibility tests required — no public surfaces affected."

### Golden-File Tests (API Shape Regression)

Snapshot tests that capture the exact shape of API responses and event payloads. A diff against the golden file flags unintended contract changes.

- One golden file per stable API endpoint (response body JSON structure with field names, types, and nesting)
- One golden file per stable event schema (payload structure)
- Golden files committed to the repo; CI fails if actual output diverges from the snapshot without an explicit update
- When a golden file is intentionally updated: the diff is reviewed as part of the MR and the Compatibility Impact section documents why the shape changed

| Surface | Golden File Location | Description |
|---|---|---|
| {GET /api/v1/resource} | {tests/golden/resource_response.json} | {Response shape for resource listing} |

### Consumer-Driven Contract Tests

Tests written from the consumer's perspective that verify the producer still satisfies the consumer's expectations.

- One contract per inter-service dependency (what does Service X expect from Service Y's response?)
- Contracts define required fields, expected types, and value constraints — not the full response shape
- The consumer owns the contract definition; the producer runs the test
- Contract violations are blocking issues in code review

| Consumer | Producer Surface | Contract Description |
|---|---|---|
| {Service X} | {GET /api/v1/resource} | {Expects fields: id (int), name (string), status (enum: active/inactive)} |

### Versioned Integration Tests (Old Client vs. New Service)

Integration tests that replay requests from previous API versions against the current service to verify backwards compatibility.

- One test suite per supported API version (current + 1 previous)
- Tests use recorded or fixture requests from the previous version
- Verify: old requests are still accepted, response shape is still parseable by an old client, semantics are unchanged
- When a version is sunset (deprecation period elapsed), its integration tests are archived to `archive/` — not deleted (audit trail)

| API Version | Test Fixture Source | Verification |
|---|---|---|
| {v1} | {tests/fixtures/v1_requests/} | {Old v1 requests still accepted; response parseable by v1 client} |

---

## Journey Invariants & Adversarial Testing

Business logic must hold not just under ideal conditions, but under the real failure modes of distributed systems. This section declares what must remain true regardless of infrastructure chaos. The implementer builds stateful simulators and runs the standardized chaos profile library (see `docs/policies/chaos-profiles.md`) against these invariants.

### Business Journey

Describe the end-to-end business journey this spec participates in. If this spec modifies an existing journey, reference it. If it creates a new one, define it here.

- **Journey name:** {e.g., "Order Placement", "Patient Check-In"}
- **Flow doc:** `docs/flows/{flow-name}.md`
- **Entry point:** {What triggers the journey}
- **Terminal states:** {What constitutes completion — success and failure}

### Journey Invariants

Invariants that must hold under all chaos profiles. These are derived from SCOUT Constraints and Updates — they are the business truths that no infrastructure failure is allowed to violate.

| ID | Invariant | SCOUT Source | Violated By |
|---|---|---|---|
| JI-1 | {e.g., "An appointment cannot be double-booked for the same provider+timeslot"} | {Rules from AC-N} | {CP-02 (duplicate), CP-05 (stale read)} |
| JI-2 | {e.g., "Payment is never captured without a confirmed order"} | {Preconditions from AC-N} | {CP-03 (out-of-order), CP-04 (partial failure)} |
| JI-3 | {e.g., "Every state transition has exactly one audit record"} | {Mutations from AC-N} | {CP-02 (duplicate), CP-04 (partial failure)} |

### External Dependencies & Simulators

List each external dependency the journey touches. The implementer builds a stateful simulator for each.

| Dependency | Type | Deterministic Behavior | Applicable Chaos Profiles |
|---|---|---|---|
| {e.g., Payment Gateway} | {HTTP API} | {Returns success for valid cards, decline for test-decline card} | {CP-01, CP-07, CP-09} |
| {e.g., Notification Queue} | {Message Queue} | {Accepts all publishes, records payloads for assertion} | {CP-02, CP-03, CP-06} |

### Chaos Test Expectations

For each applicable chaos profile, state the expected system behavior:

| Profile | Expected Behavior | Invariants Preserved |
|---|---|---|
| CP-01 (Slow Downstream) | {e.g., "Circuit breaker opens after 3 timeouts; operation returns graceful error"} | JI-1, JI-2 |
| CP-02 (Duplicate Event) | {e.g., "Second delivery is idempotently ignored; no duplicate side-effects"} | JI-1, JI-3 |
| CP-04 (Partial Failure) | {e.g., "Compensation reverses step 1 if step 2 fails; audit records partial failure"} | JI-2, JI-3 |

If the spec does not participate in a multi-step journey or has no external dependencies, state: "No journey invariants — this change is internal to a single bounded context with no external dependencies."

---

## Regression Scenarios

Regression scenarios verify that existing behavior is not broken by the new implementation. These are derived from the "Current Behavior" section of spec.md, not from SCOUT.

Regression tests are written using the **existing test conventions** (not BDD style) to maintain consistency with the surrounding test code.

```gherkin
Feature: {Existing feature name} regression
  Existing behavior that must be preserved after this change.

    Scenario: R-1 -- {Existing operation still works}
      Given {existing entity state that predates this change}
      When {existing operation is performed}
      Then {same result as before the change}
```

---

## Implementation Order

The implementer agent executes scenarios in this order, one at a time, using red-green-refactor:

| Order | Scenario | Rationale |
|---|---|---|
| 1 | S-1.1 | Primary happy path -- establishes the core behavior and scaffolding |
| 2 | S-2.4 | Entity not found -- simplest error case, validates failure path |
| 3 | S-1.4 | Validation failure -- forces validation rule implementation |
| 4 | S-1.2 | Happy path variation -- extends the core behavior |
| 5 | S-2.1 | Parameterized state transitions -- exercises the full state machine |
| 6 | S-1.3 | Edge case -- boundary conditions |
| 7 | S-2.2 | Concurrent modification -- concurrency handling |
| 8 | S-2.3 | Authorization failure -- policy enforcement (integration) |
| 9 | OS-{N}.1 | IMPOSSIBLE_STATE seam -- precondition monitoring (if seam specified) |
| 10 | OS-{N}.3 | DECISION_DRIFT seam -- branch metric emission (if seam specified) |
| 11 | OS-{N}.5 | LINEAGE_GAP seam -- side-effect checkpoint (if seam specified) |
| 12 | S-3.1 | Full request stack -- integration test |
| 13 | J-1 | Journey test (deterministic) -- full business journey with simulators (if journey invariants declared) |
| 14 | J-2..N | Journey test (chaos) -- one per applicable chaos profile from `docs/policies/chaos-profiles.md` (if journey invariants declared) |
| 15 | R-1 | Regression -- existing behavior preserved |
| 16 | C-1 | Golden-file tests -- API response shape snapshots (if applicable) |
| 17 | C-2 | Consumer contract tests -- inter-service dependency contracts (if applicable) |
| 18 | C-3 | Versioned integration tests -- old client compatibility (if applicable) |

Each row is one red-green cycle. After each green, all previous tests are re-run to verify no regression.

---

## Test Data Requirements

| Entity | State | Scenarios |
|---|---|---|
| {Entity A} | {Active, with related records} | S-1.1, S-1.2, S-2.1 |
| {Entity B} | {Draft, minimal setup} | S-1.1, S-1.3, S-2.4 |
| {Entity C} | {Active, with configuration} | S-2.1, S-2.2 |

---

## Non-Functional Considerations

### Performance

- {If applicable: expected response time, throughput, data volume}
- {E.g., "Endpoint should respond within 200ms for collections up to 1,000 items"}

### Security

- {Input validation -- injection attacks, XSS, path traversal}
- {Authorization -- verify permission enforcement for all new endpoints (covered by S-2.3)}
- {Data exposure -- verify sensitive fields are not leaked in responses}

---

## Known Limitations

- {Any test gaps that should be addressed later}
- {E.g., "Third-party webhook delivery not tested due to external dependency -- covered by mock/stub implementation"}
