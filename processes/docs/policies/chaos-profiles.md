# Chaos Profiles — Standardized Adversarial Test Library

This document defines the standard chaos profiles applied to business journey tests. Each profile represents a real failure mode observed in distributed systems. Journey tests declare invariants; this library defines what attacks those invariants.

## How It Works

1. **Spec-author** declares journey invariants in `test-plan.md` — what must remain true regardless of infrastructure failures.
2. **Implementer** builds stateful simulators for external dependencies with chaos toggles.
3. **Journey tests** run in two passes:
   - **Pass 1 (deterministic):** Happy-path business journey with all dependencies behaving normally. Asserts state transitions, emitted events, and final state.
   - **Pass 2 (chaos):** Same journey replayed with each applicable chaos profile activated. Asserts invariants still hold.

## Chaos Profile Catalog

### CP-01: Slow Downstream

**Failure mode:** A downstream service responds, but after a delay exceeding normal timeout thresholds.

| Aspect | Detail |
|--------|--------|
| Injection point | Any outbound HTTP/gRPC call or queue publish |
| Parameters | `delay_ms` (default: 5000), `affected_calls` (percentage or specific endpoints) |
| What breaks if unhandled | Cascading timeouts, thread pool exhaustion, user-facing latency spikes |
| Invariants to verify | No data corruption on timeout. Retry/circuit-breaker activates. Partial state is consistent or rolled back. Compensation fires if timeout occurs after side-effect. |

### CP-02: Duplicate Event Delivery

**Failure mode:** The same event/message is delivered more than once (at-least-once semantics).

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer or webhook handler |
| Parameters | `replay_count` (default: 2), `replay_delay_ms` (default: 0 — immediate duplicate) |
| What breaks if unhandled | Duplicate side-effects (double-charge, double-notification), state corruption from non-idempotent handlers |
| Invariants to verify | Final state identical to single-delivery. Side-effects not duplicated. Idempotency key (if used) correctly deduplicates. |

### CP-03: Out-of-Order Delivery

**Failure mode:** Events or messages arrive in a different order than they were produced.

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer processing ordered events |
| Parameters | `reorder_strategy` (reverse, shuffle, swap_adjacent) |
| What breaks if unhandled | State machine violations, events applied to wrong state, causal invariants broken |
| Invariants to verify | System either reorders correctly (via sequence numbers) or rejects out-of-order events gracefully. No silent state corruption. |

### CP-04: Partial Failure (Mid-Journey)

**Failure mode:** A multi-step operation fails after some steps have completed and committed.

| Aspect | Detail |
|--------|--------|
| Injection point | Any step N in a multi-step business operation |
| Parameters | `fail_at_step` (1-indexed), `failure_type` (exception, timeout, connection_reset) |
| What breaks if unhandled | Orphaned state (step 1 committed but step 2 never runs), broken referential integrity, dangling side-effects |
| Invariants to verify | Compensation executes for completed steps. Final state is either fully committed or fully rolled back. No orphaned records. Audit trail reflects the partial failure. |

### CP-05: Stale Read Window

**Failure mode:** A decision is made based on data that was modified by another process between read and write.

| Aspect | Detail |
|--------|--------|
| Injection point | Any read-then-decide-then-write sequence |
| Parameters | `stale_duration_ms` (simulated delay between read and write), `concurrent_mutation` (what changes in between) |
| What breaks if unhandled | Lost updates, decisions based on invalid state, violated business rules |
| Invariants to verify | Optimistic concurrency detects the conflict. Operation fails or retries with fresh data. Business rules are never violated by acting on stale state. |

### CP-06: Poison Message

**Failure mode:** A malformed, unexpected, or semantically invalid message arrives on a queue or webhook endpoint.

| Aspect | Detail |
|--------|--------|
| Injection point | Any queue consumer or webhook handler |
| Parameters | `corruption_type` (missing_field, wrong_type, extra_field, null_required, oversized, encoding_error) |
| What breaks if unhandled | Consumer crash, infinite retry loop, queue blockage (head-of-line blocking) |
| Invariants to verify | Message is rejected or dead-lettered. Consumer does not crash. Processing of subsequent valid messages is not blocked. Structured log emitted identifying the poison message. |

### CP-07: Downstream Total Failure

**Failure mode:** A downstream service is completely unreachable (connection refused, DNS failure).

| Aspect | Detail |
|--------|--------|
| Injection point | Any outbound HTTP/gRPC call |
| Parameters | `failure_type` (connection_refused, dns_failure, tcp_reset), `duration` (transient vs. sustained) |
| What breaks if unhandled | Unhandled exceptions bubbling to user, fire-and-forget mutations lost silently, cascade failures |
| Invariants to verify | Circuit breaker opens. Graceful degradation or clear error to caller. No silent data loss. Retry with backoff for transient failures. LINEAGE_GAP seam fires if side-effect was expected. |

### CP-08: Clock Skew / Time Anomaly

**Failure mode:** System clocks disagree between services, or time-based logic encounters edge cases (DST, leap second, midnight rollover).

| Aspect | Detail |
|--------|--------|
| Injection point | Any time-dependent logic (TTL, scheduling, rate limiting, windowed aggregations) |
| Parameters | `skew_ms` (clock drift), `time_scenario` (dst_transition, midnight_utc, leap_second) |
| What breaks if unhandled | Premature expiry, missed schedules, double-execution of time-windowed jobs, incorrect audit timestamps |
| Invariants to verify | Time comparisons use consistent clock source. TTLs are not violated by clock skew within documented tolerance. Audit timestamps remain monotonic within a single process. |

### CP-09: Resource Exhaustion

**Failure mode:** A shared resource (connection pool, thread pool, disk, memory) is exhausted.

| Aspect | Detail |
|--------|--------|
| Injection point | Database connection pool, HTTP client pool, file handles, memory allocation |
| Parameters | `resource_type`, `saturation_pct` (e.g., 100% = fully exhausted) |
| What breaks if unhandled | Deadlocks, OOM crashes, request queuing with unbounded growth, cascading pool exhaustion |
| Invariants to verify | Backpressure signal propagates (503, queue full rejection). No silent data loss. System recovers when resource is freed. No deadlock. |

### CP-10: Split Brain / Network Partition

**Failure mode:** Two instances of the same service cannot communicate with each other or with a shared coordinator (e.g., leader election failure).

| Aspect | Detail |
|--------|--------|
| Injection point | Any distributed coordination mechanism (distributed lock, leader election, cache invalidation) |
| Parameters | `partition_duration_ms`, `partition_scope` (inter-service, intra-service-instances) |
| What breaks if unhandled | Dual writes from two "leaders", divergent state, stale cache served indefinitely |
| Invariants to verify | At most one writer for protected resources. Partition detection triggers fallback. Divergent state is reconciled after partition heals. |

### CP-11: Session / Context Divergence

**Failure mode:** A third-party system's own session or context state diverges from what the caller believes it to be. The session id, token, cursor, or context handle the caller holds has been silently invalidated, rotated, expired, or forked by the third party — often without an error the caller can distinguish from a normal response.

**Origin:** Added after a downstream adopting repository's journey work required an explicit evaluation of whether any existing profile covered a session-consistency fault against a stateful third-party API. That evaluation found CP-05 covers a concurrent mutation of data this system reads and writes, and CP-10 covers this system's own distributed coordination, but that neither models a divergence internal to a third party's own session model. Because adopters treat their installed copy of this catalog as read-only, the gap was filed upstream against this file rather than patched locally.

| Aspect | Detail |
|--------|--------|
| Injection point | Any call carrying a session id, auth/refresh token, cursor, or context handle that a stateful third party issued and owns |
| Parameters | `divergence_type` (invalidated, rotated, expired, forked), `diverge_at_call` (1-indexed call in the sequence at which the handle goes stale), `silent` (true = the third party answers successfully against a different session rather than erroring) |
| What breaks if unhandled | Work applied to the wrong session or context, writes silently lost that the caller believes succeeded, an unbreakable re-authenticate loop, cross-session data exposure when a rotated handle is replayed |
| Invariants to verify | Divergence is detected rather than assumed away — the caller validates the session identity it got back, not just the transport status. Re-establishing a session neither duplicates nor loses already-applied work. No operation is attributed to a session other than the one it was issued against. A divergence the caller cannot reconcile fails loudly (IMPOSSIBLE_STATE or LINEAGE_GAP seam fires) rather than continuing against a wrong context. |

## Applicability Matrix

Not every profile applies to every journey. The spec-author does NOT select profiles — the implementer determines applicability based on which infrastructure patterns the journey uses:

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

Each external dependency referenced in the spec must have a stateful simulator (test double) that:

1. **Supports deterministic mode:** Returns preconfigured responses for the happy-path journey test.
2. **Supports chaos toggles:** Each applicable chaos profile can be activated independently via configuration.
3. **Records interactions:** Captures all calls made to the simulator for assertion (verify expected calls, verify no unexpected calls, verify call order).
4. **Supports state transitions:** For stateful dependencies (databases, caches), the simulator maintains state across calls within a test run.
5. **Is deterministic under chaos:** Given the same seed and profile configuration, produces the same failure sequence. No flaky tests.

## Adding New Profiles

When a production incident reveals a failure mode not covered by existing profiles:

1. Add the new profile to this catalog with the standard structure (failure mode, injection point, parameters, what breaks, invariants).
2. Add it to the Applicability Matrix.
3. Existing journey tests automatically gain coverage on next run (if the journey uses the affected infrastructure pattern).
4. Document the incident that motivated the addition in the profile's description.
