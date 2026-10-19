# Chaos Profiles — Standardized Adversarial Test Library

This catalog defines the standardized chaos profiles applied to business journey tests under CADENCE. Each profile models a concrete failure mode observed in distributed production systems. While journey tests declare business invariants, this library defines the adversarial faults injected to test whether those invariants hold under stress.

## How It Works

1. **Spec-author** (`cadence-spec-author`) declares journey invariants in `test-plan.md` — specifying what must remain true regardless of underlying infrastructure faults.
2. **Implementer** (`cadence-implementer`) constructs stateful simulators for external dependencies equipped with programmable chaos toggles.
3. **Journey tests** execute in two distinct passes:
   - **Pass 1 (deterministic):** Executes the happy-path business journey with all dependencies operating normally, asserting state transitions, emitted events, and terminal state.
   - **Pass 2 (chaos):** Replays the exact same journey with each applicable chaos profile activated in turn, asserting that all declared business invariants continue to hold.

## Chaos Profile Catalog

### CP-01: Slow Downstream

**Failure mode:** A downstream dependency responds, but only after a latency spike exceeding normal timeout thresholds.

| Aspect | Detail |
|--------|--------|
| Injection point | Any outbound HTTP/gRPC call or queue publish |
| Parameters | `delay_ms` (default: 5000), `affected_calls` (percentage or specific endpoints) |
| What breaks if unhandled | Cascading timeouts, thread pool exhaustion, user-facing latency spikes |
| Invariants to verify | No data corruption on timeout. Retry/circuit-breaker activates. Partial state is consistent or rolled back. Compensation fires if timeout occurs after side-effect. |

### CP-02: Duplicate Event Delivery

**Failure mode:** An identical event or message is delivered more than once (at-least-once delivery semantics).

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer or webhook handler |
| Parameters | `replay_count` (default: 2), `replay_delay_ms` (default: 0 — immediate duplicate) |
| What breaks if unhandled | Duplicate side-effects (double-charge, double-notification), state corruption from non-idempotent handlers |
| Invariants to verify | Final state identical to single-delivery. Side-effects not duplicated. Idempotency key (if used) correctly deduplicates. |

### CP-03: Out-of-Order Delivery

**Failure mode:** Events or messages arrive at a consumer in a sequence different from the order in which they were emitted.

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer processing ordered events |
| Parameters | `reorder_strategy` (reverse, shuffle, swap_adjacent) |
| What breaks if unhandled | State machine violations, events applied to wrong state, causal invariants broken |
| Invariants to verify | System either reorders correctly (via sequence numbers) or rejects out-of-order events gracefully. No silent state corruption. |

### CP-04: Partial Failure (Mid-Journey)

**Failure mode:** A multi-step workflow fails after one or more earlier steps have already completed and committed.

| Aspect | Detail |
|--------|--------|
| Injection point | Any step N in a multi-step business operation |
| Parameters | `fail_at_step` (1-indexed), `failure_type` (exception, timeout, connection_reset) |
| What breaks if unhandled | Orphaned state (step 1 committed but step 2 never runs), broken referential integrity, dangling side-effects |
| Invariants to verify | Compensation executes for completed steps. Final state is either fully committed or fully rolled back. No orphaned records. Audit trail reflects the partial failure. |

### CP-05: Stale Read Window

**Failure mode:** A business decision is evaluated against state that was concurrently mutated by another process between the read and the subsequent write.

| Aspect | Detail |
|--------|--------|
| Injection point | Any read-then-decide-then-write sequence |
| Parameters | `stale_duration_ms` (simulated delay between read and write), `concurrent_mutation` (what changes in between) |
| What breaks if unhandled | Lost updates, decisions based on invalid state, violated business rules |
| Invariants to verify | Optimistic concurrency detects the conflict. Operation fails or retries with fresh data. Business rules are never violated by acting on stale state. |

### CP-06: Poison Message

**Failure mode:** A malformed, schema-violating, or semantically invalid payload arrives on a queue consumer or webhook endpoint.

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer or webhook handler |
| Parameters | `corruption_type` (missing_field, wrong_type, extra_field, null_required, oversized, encoding_error) |
| What breaks if unhandled | Consumer crash, infinite retry loop, queue blockage (head-of-line blocking) |
| Invariants to verify | Message is rejected or dead-lettered. Consumer does not crash. Processing of subsequent valid messages is not blocked. Structured log emitted identifying the poison message. |

### CP-07: Downstream Total Failure

**Failure mode:** A downstream dependency is completely unreachable (connection refused, DNS resolution failure, or TCP reset).

| Aspect | Detail |
|--------|--------|
| Injection point | Any outbound HTTP/gRPC call |
| Parameters | `failure_type` (connection_refused, dns_failure, tcp_reset), `duration` (transient vs. sustained) |
| What breaks if unhandled | Unhandled exceptions bubbling to user, fire-and-forget mutations lost silently, cascade failures |
| Invariants to verify | Circuit breaker opens. Graceful degradation or clear error to caller. No silent data loss. Retry with backoff for transient failures. DELTA_AUDIT_GAP seam fires if side-effect was expected. |

### CP-08: Clock Skew / Time Anomaly

**Failure mode:** System clocks drift across service nodes, or time-sensitive logic encounters boundary anomalies (DST transitions, leap seconds, UTC midnight rollover).

| Aspect | Detail |
|--------|--------|
| Injection point | Any time-dependent logic (TTL, scheduling, rate limiting, windowed aggregations) |
| Parameters | `skew_ms` (clock drift), `time_scenario` (dst_transition, midnight_utc, leap_second) |
| What breaks if unhandled | Premature expiry, missed schedules, double-execution of time-windowed jobs, incorrect audit timestamps |
| Invariants to verify | Time comparisons use consistent clock source. TTLs are not violated by clock skew within documented tolerance. Audit timestamps remain monotonic within a single process. |

### CP-09: Resource Exhaustion

**Failure mode:** A shared runtime resource (database connection pool, thread pool, file descriptors, or memory) reaches saturation.

| Aspect | Detail |
|--------|--------|
| Injection point | Database connection pool, HTTP client pool, file handles, memory allocation |
| Parameters | `resource_type`, `saturation_pct` (e.g., 100% = fully exhausted) |
| What breaks if unhandled | Deadlocks, OOM crashes, request queuing with unbounded growth, cascading pool exhaustion |
| Invariants to verify | Backpressure signal propagates (503, queue full rejection). No silent data loss. System recovers when resource is freed. No deadlock. |

### CP-10: Split Brain / Network Partition

**Failure mode:** Two instances of the same service lose connectivity with each other or with a shared coordination store (e.g., leader election split).

| Aspect | Detail |
|--------|--------|
| Injection point | Any distributed coordination mechanism (distributed lock, leader election, cache invalidation) |
| Parameters | `partition_duration_ms`, `partition_scope` (inter-service, intra-service-instances) |
| What breaks if unhandled | Dual writes from two "leaders", divergent state, stale cache served indefinitely |
| Invariants to verify | At most one writer for protected resources. Partition detection triggers fallback. Divergent state is reconciled after partition heals. |

### CP-11: Session / Context Divergence

**Failure mode:** A third-party system's internal session or context state diverges from what the caller believes it to be. The session ID, token, cursor, or context handle held by the caller has been silently invalidated, rotated, expired, or forked by the external system — frequently without returning an error distinguishable from a normal transport response.

**Origin:** Introduced after an adopting repository's journey testing required an explicit evaluation of whether any existing profile modeled a session-consistency fault against a stateful third-party API. That evaluation confirmed CP-05 covers concurrent mutation of data owned by this system, and CP-10 covers this system's own distributed coordination, whereas neither models state divergence inside a third party's own session lifecycle. Because adopters treat their installed copy of this catalog as read-only, the gap was filed upstream against this catalog rather than patched locally.

| Aspect | Detail |
|--------|--------|
| Injection point | Any call carrying a session id, auth/refresh token, cursor, or context handle that a stateful third party issued and owns |
| Parameters | `divergence_type` (invalidated, rotated, expired, forked), `diverge_at_call` (1-indexed call in the sequence at which the handle goes stale), `silent` (true = the third party answers successfully against a different session rather than erroring) |
| What breaks if unhandled | Work applied to the wrong session or context, writes silently lost that the caller believes succeeded, an unbreakable re-authenticate loop, cross-session data exposure when a rotated handle is replayed |
| Invariants to verify | Divergence is detected rather than assumed away — the caller validates the session identity it got back, not just the transport status. Re-establishing a session neither duplicates nor loses already-applied work. No operation is attributed to a session other than the one it was issued against. A divergence the caller cannot reconcile fails loudly (UNSOUND_CONDITION or DELTA_AUDIT_GAP seam fires) rather than continuing against a wrong context. |

## Applicability Matrix

Not every chaos profile applies to every business journey. The `cadence-spec-author` does NOT cherry-pick profiles — the `cadence-implementer` determines applicability mechanically from the infrastructure patterns the journey exercises:

| Journey Uses | Applicable Profiles |
|---|---|
| Outbound HTTP/gRPC calls | CP-01, CP-07, CP-09 |
| Queue consumption | CP-02, CP-03, CP-06 |
| Multi-step mutations | CP-04, CP-05 |
| Time-dependent logic | CP-08 |
| Distributed coordination | CP-10 |
| Any external dependency | CP-07, CP-09 |
| Third-party session/context handles | CP-11 |

## Stateful Simulator Requirements

Every external dependency referenced by a specification must be backed by a stateful simulator (test double) that:

1. **Supports deterministic mode:** Returns preconfigured responses during Pass 1 (the happy-path journey test).
2. **Supports chaos toggles:** Allows each applicable chaos profile to be activated independently via test configuration.
3. **Records interactions:** Captures all invocations made against the simulator for assertion (verifying expected calls, absence of unexpected calls, and invocation ordering).
4. **Supports state transitions:** For stateful dependencies (databases, caches, session stores), maintains coherent state across calls within a single test execution.
5. **Is deterministic under chaos:** Given an identical seed and profile configuration, produces the exact same fault sequence on every run — zero flaky tests.

## Adding New Profiles

When a production incident uncovers a failure mode not yet represented in this catalog:

1. Add the new `CP-NN` profile to this catalog using the standard structure (failure mode, injection point, parameters, what breaks if unhandled, invariants to verify).
2. Map the profile in the Applicability Matrix above.
3. Existing journey tests that exercise the corresponding infrastructure pattern automatically inherit coverage on their next execution.
4. Record the motivating production incident in the profile's description.
