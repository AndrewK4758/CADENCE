# Observability Pattern Catalog

Standard structured log event patterns for SCOUT observability seams. All patterns emit structured JSON to stdout (Loki ingestion) and include mandatory correlation fields.

## Standard Fields (all patterns)

Every seam event includes these fields alongside pattern-specific data:

```json
{
  "timestamp": "ISO-8601",
  "level": "ERROR|WARN|INFO",
  "trace_id": "W3C trace ID",
  "span_id": "current span",
  "request_id": "correlation ID",
  "service": "service-name",
  "component": "module.class",
  "seam_type": "IMPOSSIBLE_STATE|LINEAGE_GAP|DECISION_DRIFT|SEAM_VIOLATION",
  "event_name": "domain.operation.seam_name",
  "scout_ac": "AC-N from spec"
}
```

---

## Pattern 1: IMPOSSIBLE_STATE

**Purpose:** Detects when a precondition that should be guaranteed by the system is violated at runtime. Indicates a code path that bypassed validation, a race condition, or a logic error in AI-generated code.

**When to emit:** A function or handler observes system state that contradicts its documented preconditions (from SCOUT State dimension).

**Structured format:**

```json
{
  "seam_type": "IMPOSSIBLE_STATE",
  "event_name": "{domain}.{operation}.precondition_violated",
  "precondition": "Human-readable precondition that was expected to hold",
  "actual_state": "What was actually observed",
  "expected_state": "What was expected",
  "code_location": "Namespace.Class:Method"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="IMPOSSIBLE_STATE"
```

**Mimir metric:**

```
seam_impossible_state_total{service, component, event_name}
```

**Alert rule:** Every IMPOSSIBLE_STATE event generates a **Critical** alert. Zero tolerance — this indicates a logic error.

**Implementation pattern:**

```csharp
if (order.Status != OrderStatus.Draft)
{
    logger.LogError(new {
        seam_type = "IMPOSSIBLE_STATE",
        event_name = "order.submit.precondition_violated",
        precondition = "Order must be in Draft state",
        expected_state = "Draft",
        actual_state = order.Status.ToString(),
        code_location = "OrderService:SubmitOrder"
    });
    throw new InvalidOperationException("Order is not in Draft state");
}
```

---

## Pattern 2: LINEAGE_GAP

**Purpose:** Detects when an expected checkpoint in a trace or audit trail is missing. Indicates a side-effect or mutation that was specified but did not execute.

**When to emit:** A trace or transaction completes without an expected span/checkpoint that the SCOUT Outputs or Updates dimension specifies must exist.

**Structured format:**

```json
{
  "seam_type": "LINEAGE_GAP",
  "event_name": "{domain}.{operation}.{checkpoint_name}_missing",
  "expected_checkpoint": "Name of the span/event that should have appeared",
  "trace_context": "Parent span that should contain the checkpoint",
  "gap_type": "side_effect_missing|mutation_audit_missing|checkpoint_skipped"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="LINEAGE_GAP" | gap_type="mutation_audit_missing"
```

**Mimir metric:**

```
seam_lineage_gap_total{service, component, gap_type, event_name}
```

**Alert rules:**
- `gap_type=mutation_audit_missing` → **Critical** (SOC 2 compliance)
- `gap_type=side_effect_missing` → **High**
- `gap_type=checkpoint_skipped` → **High**

**Detection mechanisms:**

| Gap Type | Detection Method |
|---|---|
| `side_effect_missing` | Post-handler verification: check trace for expected child span |
| `mutation_audit_missing` | Post-commit hook: verify Event_Log has corresponding entry |
| `checkpoint_skipped` | Batch reconciliation: compare expected vs actual checkpoint count per trace |

**Implementation pattern (side-effect verification):**

```csharp
// After handler completes, verify expected side-effects fired
var publishSpan = Activity.Current?.GetChildSpan("order.submitted.publish");
if (publishSpan == null)
{
    logger.LogError(new {
        seam_type = "LINEAGE_GAP",
        event_name = "order.submit.publish_missing",
        expected_checkpoint = "order.submitted.publish",
        trace_context = Activity.Current?.Id,
        gap_type = "side_effect_missing"
    });
}
```

---

## Pattern 3: DECISION_DRIFT

**Purpose:** Detects when a branch decision in business logic is taken at a rate outside its expected baseline distribution. Indicates changed data patterns, feature flag misconfiguration, or logic error in AI-generated branching code.

**When to emit:** A windowed counter of branch decisions deviates from the established baseline by more than the configured threshold. The application emits a metric on every decision; drift detection happens in Mimir, not in application code.

**Structured format (metric emission on every decision):**

```json
{
  "seam_type": "DECISION_DRIFT",
  "event_name": "{domain}.{operation}.branch_distribution",
  "branch_name": "Name of the decision point",
  "branch_taken": "which_branch"
}
```

**Structured format (alert payload when drift detected):**

```json
{
  "seam_type": "DECISION_DRIFT",
  "event_name": "{domain}.{operation}.branch_distribution",
  "branch_name": "Name of the decision point",
  "branch_taken": "which_branch",
  "window_size": "1h",
  "observed_rate": 0.45,
  "baseline_rate": 0.85,
  "threshold": 0.15,
  "deviation": 0.40
}
```

**Mimir metric (emitted on every branch decision):**

```
seam_decision_branch_total{service, component, event_name, branch_taken}
```

**Mimir recording rule (computes ratio over window):**

```
seam_decision_branch_ratio = rate(seam_decision_branch_total{branch_taken="X"}[1h])
                           / rate(seam_decision_branch_total[1h])
```

**Alert rule:** **Warning** severity — requires human investigation, not necessarily a bug.

**Baseline management:**
- Initial baseline: first 7 days of production traffic after feature ships
- Baseline refresh: rolling 30-day average, updated weekly
- Storage: `docs/baselines/{service}/{event_name}.yaml` (committed to repo)
- Threshold default: deviation > 0.15 (15 percentage points)

**Implementation pattern:**

```csharp
// Emit on every decision — drift detection is in Mimir, not here
var branch = order.Total < 100m ? "auto_approve" : "manual_review";
metrics.IncrementCounter("seam_decision_branch_total", new {
    service = "order-service",
    component = "OrderApproval",
    event_name = "order.approval.branch_distribution",
    branch_taken = branch
});
```

---

## Pattern 4: SEAM_VIOLATION

**Purpose:** Detects when an observability seam contract itself is broken — the seam should have fired but did not, or fired with invalid data.

**When to emit:** A health check or reconciliation process discovers that seams are not functioning as specified.

**Structured format:**

```json
{
  "seam_type": "SEAM_VIOLATION",
  "event_name": "{domain}.{operation}.seam_contract_broken",
  "violated_seam": "Name of the seam that failed to fire or fired incorrectly",
  "violation_type": "missing_emission|invalid_payload|stale_baseline",
  "detection_method": "health_check|reconciliation|manual"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="SEAM_VIOLATION"
```

**Mimir metric:**

```
seam_violation_total{service, component, violated_seam, violation_type}
```

**Alert rule:** **High** severity — seam infrastructure is degraded, reducing production visibility.

**Detection mechanisms:**

| Violation Type | Detection Method |
|---|---|
| `missing_emission` | Reconciliation: service handled N requests but emitted 0 seam metrics for a registered seam |
| `invalid_payload` | Schema validation on Loki ingest: seam event missing required fields |
| `stale_baseline` | Scheduled check: baseline file older than 60 days without refresh |

---

## Implementation Checklist

When implementing any seam:

- [ ] Structured JSON event emitted to stdout (Loki picks up)
- [ ] Event includes all standard fields (trace_id, span_id, request_id, service, component)
- [ ] Mimir metric emitted (counter for the seam type)
- [ ] Alert rule defined in Mimir (based on severity from spec)
- [ ] Test scenario verifies the seam fires under trigger condition
- [ ] Test scenario verifies the seam does NOT fire under normal operation (no false positives)
- [ ] Dashboard panel in Grafana for the seam metric
- [ ] Seam registered in service health check (for SEAM_VIOLATION detection)

## Naming Conventions

| Element | Pattern | Example |
|---|---|---|
| Event name | `{domain}.{operation}.{seam_descriptor}` | `order.submit.precondition_violated` |
| Metric name | `seam_{type}_total` | `seam_impossible_state_total` |
| Alert name | `{Service}{SeamType}{Domain}` | `OrderServiceImpossibleStateSubmit` |
| Baseline file | `docs/baselines/{service}/{event_name}.yaml` | `docs/baselines/order-service/order.approval.branch_distribution.yaml` |
