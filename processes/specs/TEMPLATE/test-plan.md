# Test Plan: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Executing | Complete

> **Document review status**, distinct from the ticket's lifecycle state. `metadata.yaml`'s
> `status:` field is authoritative for the ticket; this line tracks how far *this test plan* has progressed.
> They are separate vocabularies by design, and neither mirrors the other -- `Executing` above
> is a state of this test plan and has no counterpart in the ticket lifecycle.

## References

- **Problem:** [problem.md](problem.md) -- acceptance criteria drive every test scenario
- **Spec:** [spec.md](spec.md) -- CHORD analysis decomposes each AC into verifiable behavioral dimensions

## Test Strategy

### Approach: BDD-First with Red-Green-Refactor

Tests for newly introduced behavior are authored **before** production code. Every BDD scenario executes through a strict cycle:
1. **Red** -- compile (adding minimal stubs where necessary) and fail, proving the target behavior is not yet present
2. **Green** -- pass after introducing the minimum production code required for that scenario
3. **Accumulate** -- re-run all prior tests (including the pre-existing test suite, using `offload_log_triage` / `log-triage` on `:11434` to compact verbose output while preserving verbatim failures in `/tmp/agy-last-triage.log`) and verify zero regressions

BDD formatting applies to **newly authored tests only**. Existing tests are never rewritten into BDD style; pre-existing test frameworks, helpers, and conventions remain untouched.

### Scope

- **In scope:** {What behavioral contracts and components this test plan verifies}
- **Out of scope:** {What is explicitly excluded from automated testing here -- e.g., "visual layout polish, verified during manual deploy validation"}

### Test Infrastructure Discovery

Before writing the first test, `cadence-implementer` scans the repository's existing test suites to discover:

- **Test framework:** {Discovered at implementation time -- e.g., pytest, Jest, xUnit, Go testing, RSpec, JUnit}
- **Assertion style:** {Discovered at implementation time -- e.g., built-in assert, Chai expect, Hamcrest matchers, FluentAssertions}
- **Mocking approach:** {Discovered at implementation time -- e.g., unittest.mock, Jest mocks, testdoubles, Mockito}
- **Test data patterns:** {Discovered at implementation time -- e.g., factories, fixtures, builders, inline setup}
- **Integration test infrastructure:** {Discovered at implementation time -- e.g., Testcontainers, in-memory DB, httptest, Supertest}
- **Naming conventions:** {Discovered at implementation time -- e.g., test_verb_condition, should_verb_when, Given_When_Then}
- **File organization:** {Discovered at implementation time -- e.g., co-located with source, separate test directory, mirrored structure}

The implementer records these discovered conventions above and writes all new tests to match them.

### Test Levels

| Level | Coverage Target | Location |
|---|---|---|
| Unit (BDD) | Service logic, validators, mappers, domain rules | {Discovered at implementation time} |
| Integration (BDD) | API endpoints, database operations, auth policies | {Discovered at implementation time} |
| Compatibility | API shape regression, consumer contracts, version compat | {Discovered at implementation time} |
| Manual | End-to-end user flows | Reviewer verification in non-prod environment |

---

## Acceptance Criteria Coverage

Map each acceptance criterion to its CHORD decomposition (from `spec.md`) and the BDD feature that verifies it.

| AC # | Acceptance Criterion | CHORD Source | Feature | Scenarios | Level | Compatibility Tests |
|---|---|---|---|---|---|---|
| AC-1 | {Criterion from problem.md} | spec.md AC-1 | Feature 1 | S-1.1, S-1.2, S-1.3 | Unit | {Golden: endpoint; Contract: dependency — or N/A} |
| AC-2 | {Criterion from problem.md} | spec.md AC-2 | Feature 2 | S-2.1, S-2.2, S-2.3, S-2.4 | Unit + Integration | {Golden: endpoint; Versioned: v1 compat — or N/A} |
| AC-3 | {Criterion from problem.md} | spec.md AC-3 | Feature 3 | S-3.1 | Integration | {N/A — no public surface affected} |

---

## BDD Features

### Feature 1: {Feature name derived from AC-1}

```gherkin
Feature: {Feature name}
  As a {role from Contextual Grounding Who/People}
  I want {capability from AC-1}
  So that {business motivation from Contextual Grounding Why/Motivation}

  Background:
    Given {common precondition shared by all scenarios in this feature}

  # --- Happy Path ---

  Rule: {Business rule from CHORD Rules for AC-1}

    Scenario: S-1.1 -- {Descriptive name for the primary success path}
      Given {conditions from CHORD -- entity state, configuration}
      And {additional precondition if needed}
      When {handling trigger from CHORD -- API call, service method, event}
      Then {deltas from CHORD -- entity state change verified}
      And {outcomes from CHORD -- external call verified}

    Scenario: S-1.2 -- {Variation on the happy path}
      Given {different precondition}
      When {same or similar action}
      Then {expected outcome for this variation}

  # --- Edge Cases ---

  Rule: {Boundary or constraint rule from CHORD}

    Scenario: S-1.3 -- {Edge case name -- boundary condition}
      Given {edge case precondition -- empty collection, max value, null reference}
      When {action that triggers boundary behavior}
      Then {expected graceful handling -- validation error, empty result, default}

  # --- Error Scenarios ---

    Scenario: S-1.4 -- {Error scenario name -- invalid input}
      Given {standard precondition}
      When {invalid input from CHORD Handling -- missing field, wrong type, out of range}
      Then {validation failure with specific message}
      And {no delta mutation occurs -- entity state unchanged}
      And {no external outcome occurs -- external service not called}
```

### Feature 2: {Feature name derived from AC-2}

```gherkin
Feature: {Feature name}
  As a {role}
  I want {capability from AC-2}
  So that {business motivation}

  # --- Happy Path ---

  Rule: {Business rule from CHORD Rules for AC-2}

    Scenario Outline: S-2.1 -- {Parameterized happy path}
      Given a {entity} in <initial_state> state
      And {other precondition}
      When {action} is performed with <parameter>
      Then the {entity} state should be <expected_state>
      And {delta mutation or external outcome}

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

Derived from the Observability Seams section of `spec.md`. Each seam scenario verifies that production telemetry will emit a structured alert whenever runtime behavior diverges from the CHORD contract. See `docs/policies/observability-patterns.md` for the four standard seam families (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `DELTA_AUDIT_GAP`, `BOUNDARY_FAULT`).

When the specification's Observability Seams table is empty or marked "None," omit this section.

### Feature: Observability Seams

```gherkin
Feature: Production observability seams
  As a platform operator
  I want runtime assertions at CHORD dimension boundaries
  So that production divergence from spec is detectable without human observation

  # --- UNSOUND_CONDITION seams (from Conditions) ---

  Rule: Condition violations are detected and logged at runtime

    Scenario: OS-{N}.1 -- Condition violation emits UNSOUND_CONDITION event
      Given {entity} exists in {state that violates the required Condition}
      And the system bypasses normal validation (direct invocation / race condition)
      When {operation} is attempted
      Then a structured log event is emitted with seam_type "UNSOUND_CONDITION"
      And the event includes event_name "{domain}.{op}.precondition_violated"
      And the event includes expected_state "{valid state}" and actual_state "{invalid state}"
      And the operation is rejected

    Scenario: OS-{N}.2 -- Normal operation does not trigger UNSOUND_CONDITION
      Given {entity} exists in {valid state}
      When {operation} is performed successfully
      Then no UNSOUND_CONDITION event is emitted

  # --- RULE_DIVERGENCE seams (from Rules with branching) ---

  Rule: Branch decisions emit metrics for distribution monitoring

    Scenario: OS-{N}.3 -- Branch decision emits metric counter
      Given {conditions that cause branch A to be taken}
      When {operation} is performed
      Then the metric seam_decision_branch_total increments with branch_taken="A"

    Scenario: OS-{N}.4 -- Alternative branch emits its own metric
      Given {conditions that cause branch B to be taken}
      When {operation} is performed
      Then the metric seam_decision_branch_total increments with branch_taken="B"

  # --- DELTA_AUDIT_GAP seams (from Outcomes and Deltas) ---

  Rule: Missing external outcomes and audit records are detected

    Scenario: OS-{N}.5 -- Missing external outcome emits DELTA_AUDIT_GAP event
      Given {entity} in valid state for {operation}
      And {external service / event bus} is configured to silently fail (no error, no execution)
      When {operation} completes
      Then a structured log event is emitted with seam_type "DELTA_AUDIT_GAP"
      And the event includes gap_type "side_effect_missing"
      And the event identifies the missing checkpoint "{expected span name}"

    Scenario: OS-{N}.6 -- Missing audit record emits DELTA_AUDIT_GAP event
      Given {entity} in valid state for {operation}
      And the audit subsystem is configured to silently fail
      When {operation} completes and the mutation is committed
      Then a structured log event is emitted with seam_type "DELTA_AUDIT_GAP"
      And the event includes gap_type "mutation_audit_missing"
```

---

## Compatibility Tests

Compatibility tests verify that changes do not break existing consumers. They are derived from the "Compatibility Impact" section of `spec.md` and the surface registries -- [adopter-owned](../../docs/policies/surface-registry.md) and [core-owned](../../docs/policies/cadence-surfaces.md). When no public surfaces are touched by this change, state "No compatibility tests required — no public surfaces affected."

### Golden-File Tests (API Shape Regression)

Snapshot tests capturing the exact structural shape of API responses and event payloads. Any unreviewed diff against a committed golden file fails CI and flags an unintended contract modification.

- One golden file per stable API endpoint (response JSON structure including field names, types, and nesting)
- One golden file per stable event schema (payload structure)
- Golden files are committed to the repository; CI fails whenever actual output diverges from the snapshot without an explicit update
- Whenever a golden file is intentionally updated, the diff is reviewed in the MR and the Compatibility Impact section of `spec.md` explains why the contract shape changed

| Surface | Golden File Location | Description |
|---|---|---|
| {GET /api/v1/resource} | {tests/golden/resource_response.json} | {Response shape for resource listing} |

### Consumer-Driven Contract Tests

Tests authored from the consumer's viewpoint verifying that the producer continues to satisfy every consumer expectation.

- One contract per inter-service dependency (what does Service X require from Service Y's response?)
- Contracts assert required fields, expected types, and value invariants — not the entire response payload
- The consuming service owns the contract definition; the producing service executes the test in CI
- Any contract violation is a blocking code-review defect

| Consumer | Producer Surface | Contract Description |
|---|---|---|
| {Service X} | {GET /api/v1/resource} | {Expects fields: id (int), name (string), status (enum: active/inactive)} |

### Versioned Integration Tests (Old Client vs. New Service)

Integration tests replaying recorded requests from prior API versions against the current service implementation to guarantee backwards compatibility.

- One test suite per supported API version (current + 1 prior version)
- Tests replay recorded or fixture requests from the prior version
- Verify: legacy requests are accepted, response shapes remain parseable by legacy clients, and domain semantics are preserved
- When an API version reaches its sunset date, its integration tests are moved to `archive/` rather than deleted (preserving the audit trail)

| API Version | Test Fixture Source | Verification |
|---|---|---|
| {v1} | {tests/fixtures/v1_requests/} | {Old v1 requests still accepted; response parseable by v1 client} |

---

## Journey Invariants & Adversarial Testing

Domain invariants must hold not only on the happy path, but under realistic distributed-system failure modes. This section declares the business truths that must remain unbroken under infrastructure faults. `cadence-implementer` builds stateful simulators for external dependencies and runs the standardized chaos profile catalog (`docs/policies/chaos-profiles.md`) against these invariants.

### Business Journey

Identify the end-to-end business journey this specification participates in. Reference the existing flow document when modifying a known journey, or define a new one here.

- **Journey name:** {e.g., "Order Placement", "Patient Check-In"}
- **Flow doc:** `docs/flows/{flow-name}.md`
- **Entry point:** {What initiates the journey}
- **Terminal states:** {What constitutes completion — both success and terminal failure}

### Journey Invariants

Invariants that must hold across all chaos profiles. These are derived directly from CHORD Rules and Deltas — they represent business guarantees that no infrastructure fault may violate.

| ID | Invariant | CHORD Source | Violated By |
|---|---|---|---|
| JI-1 | {e.g., "An appointment cannot be double-booked for the same provider+timeslot"} | {Rules from AC-N} | {CP-02 (duplicate), CP-05 (stale read)} |
| JI-2 | {e.g., "Payment is never captured without a confirmed order"} | {Conditions from AC-N} | {CP-03 (out-of-order), CP-04 (partial failure)} |
| JI-3 | {e.g., "Every state transition has exactly one audit record"} | {Deltas from AC-N} | {CP-02 (duplicate), CP-04 (partial failure)} |

### External Dependencies & Simulators

List every external dependency touched by the journey. `cadence-implementer` constructs a deterministic stateful simulator for each.

| Dependency | Type | Deterministic Behavior | Applicable Chaos Profiles |
|---|---|---|---|
| {e.g., Payment Gateway} | {HTTP API} | {Returns success for valid cards, decline for test-decline card} | {CP-01, CP-07, CP-09} |
| {e.g., Notification Queue} | {Message Queue} | {Accepts all publishes, records payloads for assertion} | {CP-02, CP-03, CP-06} |

### Chaos Test Expectations

For each applicable chaos profile, specify the expected resilient behavior:

| Profile | Expected Behavior | Invariants Preserved |
|---|---|---|
| CP-01 (Slow Downstream) | {e.g., "Circuit breaker opens after 3 timeouts; operation returns graceful error"} | JI-1, JI-2 |
| CP-02 (Duplicate Event) | {e.g., "Second delivery is idempotently ignored; no duplicate side-effects"} | JI-1, JI-3 |
| CP-04 (Partial Failure) | {e.g., "Compensation reverses step 1 if step 2 fails; audit records partial failure"} | JI-2, JI-3 |

When the specification does not participate in a multi-step journey or has no external dependencies, write: "No journey invariants — this change is internal to a single bounded context with no external dependencies."

---

## Regression Scenarios

Regression scenarios confirm that pre-existing system behavior remains intact after the new implementation lands. These are derived from the "Current Behavior" section of `spec.md` rather than from CHORD decomposition.

Regression tests are authored using the **existing test conventions** (not BDD style) to stay consistent with surrounding test files.

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

The `cadence-implementer` agent executes scenarios in this exact sequence, one scenario at a time, following strict red-green-refactor TDD:

| Order | Scenario | Rationale |
|---|---|---|
| 1 | S-1.1 | Primary happy path -- establishes core behavior and structural wiring |
| 2 | S-2.4 | Entity not found -- simplest failure path, validates error contract |
| 3 | S-1.4 | Validation failure -- drives input validation rule implementation |
| 4 | S-1.2 | Happy path variation -- extends core domain logic |
| 5 | S-2.1 | Parameterized state transitions -- exercises the complete state machine |
| 6 | S-1.3 | Edge case -- boundary conditions |
| 7 | S-2.2 | Concurrent modification -- optimistic concurrency handling |
| 8 | S-2.3 | Authorization failure -- policy enforcement (integration) |
| 9 | OS-{N}.1 | UNSOUND_CONDITION seam -- precondition monitoring (if seam specified) |
| 10 | OS-{N}.3 | RULE_DIVERGENCE seam -- branch metric emission (if seam specified) |
| 11 | OS-{N}.5 | DELTA_AUDIT_GAP seam -- outcome/audit checkpoint (if seam specified) |
| 12 | S-3.1 | Full request stack -- end-to-end integration test |
| 13 | J-1 | Journey test (deterministic) -- full business journey with simulators (if journey invariants declared) |
| 14 | J-2..N | Journey test (chaos) -- one per applicable chaos profile from `docs/policies/chaos-profiles.md` (if journey invariants declared) |
| 15 | R-1 | Regression -- existing behavior preserved |
| 16 | C-1 | Golden-file tests -- API response shape snapshots (if applicable) |
| 17 | C-2 | Consumer contract tests -- inter-service dependency contracts (if applicable) |
| 18 | C-3 | Versioned integration tests -- legacy client compatibility (if applicable) |

Each row represents a single red-green-accumulate-commit cycle. After each green step, the full test suite is executed to verify zero regressions.

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

- {If applicable: target latency, throughput, or dataset volume}
- {E.g., "Endpoint must respond within 200ms at p95 for collections up to 1,000 items"}

### Security

- {Input validation -- injection attacks, XSS, path traversal}
- {Authorization -- verify permission enforcement across all new endpoints (covered by S-2.3)}
- {Data exposure -- verify sensitive or PII fields are never leaked in responses or logs}

---

## Known Limitations

- {Any test coverage gaps that must be tracked for future work}
- {E.g., "Third-party webhook delivery is verified against the stateful simulator rather than the live vendor sandbox"}
