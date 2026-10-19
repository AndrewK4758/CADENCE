# Observability Pattern Catalog

Standardized structured log and metric patterns for **CHORD** (**C**onditions, **H**andling/Triggers, **O**utcomes, **R**ules, **D**eltas) observability seams under CADENCE. Every seam emits structured JSON to `stdout` (for Loki ingestion) paired with Mimir counters and mandatory distributed-tracing correlation fields.

## Standard Fields (all patterns)

Every CHORD seam event includes these baseline correlation fields alongside its pattern-specific payload:

```json
{
  "timestamp": "ISO-8601",
  "level": "ERROR|WARN|INFO",
  "trace_id": "W3C trace ID",
  "span_id": "current span",
  "request_id": "correlation ID",
  "service": "service-name",
  "component": "module.class",
  "seam_type": "UNSOUND_CONDITION|DELTA_AUDIT_GAP|RULE_DIVERGENCE|BOUNDARY_FAULT",
  "event_name": "domain.operation.seam_name",
  "chord_ac": "AC-N from spec"
}
```

---

## Pattern 1: UNSOUND_CONDITION

**Purpose:** Detects at runtime when a state precondition that should already be guaranteed by upstream validation or domain invariants is violated. Signals a code path that bypassed validation, a concurrency race condition, or a logic defect in generated code.

**When to emit:** A domain method or handler observes system state that contradicts its documented **CHORD Conditions** (`Given` state preconditions).

**Structured format:**

```json
{
  "seam_type": "UNSOUND_CONDITION",
  "event_name": "{domain}.{operation}.precondition_violated",
  "precondition": "Human-readable precondition that was expected to hold",
  "actual_state": "What was actually observed",
  "expected_state": "What was expected",
  "code_location": "Namespace.Class:Method"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="UNSOUND_CONDITION"
```

**Mimir metric:**

```
seam_unsound_condition_total{service, component, event_name}
```

**Alert rule:** Every `UNSOUND_CONDITION` event fires a **Critical** alert. Zero tolerance — this indicates an invariant breach or logic fault.

**Implementation pattern:**

```csharp
if (order.Status != OrderStatus.Draft)
{
    logger.LogError(new {
        seam_type = "UNSOUND_CONDITION",
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

## Pattern 2: DELTA_AUDIT_GAP

**Purpose:** Detects when an expected checkpoint in a distributed trace or mutation audit trail is absent. Indicates that an outbound side-effect or internal state mutation required by the specification failed to execute or record.

**When to emit:** A trace or transaction finishes without an expected child span or audit record specified by the **CHORD Outcomes** or **CHORD Deltas** dimensions.

**Structured format:**

```json
{
  "seam_type": "DELTA_AUDIT_GAP",
  "event_name": "{domain}.{operation}.{checkpoint_name}_missing",
  "expected_checkpoint": "Name of the span/event that should have appeared",
  "trace_context": "Parent span that should contain the checkpoint",
  "gap_type": "side_effect_missing|mutation_audit_missing|checkpoint_skipped"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="DELTA_AUDIT_GAP" | gap_type="mutation_audit_missing"
```

**Mimir metric:**

```
seam_delta_audit_gap_total{service, component, gap_type, event_name}
```

**Alert rules:**
- `gap_type=mutation_audit_missing` → **Critical** (Data Integrity / SOC 2 audit compliance)
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
        seam_type = "DELTA_AUDIT_GAP",
        event_name = "order.submit.publish_missing",
        expected_checkpoint = "order.submitted.publish",
        trace_context = Activity.Current?.Id,
        gap_type = "side_effect_missing"
    });
}
```

---

## Pattern 3: RULE_DIVERGENCE

**Purpose:** Detects when a business-rule branch decision deviates significantly from its established historical baseline distribution. Signals shifted upstream traffic patterns, misconfigured feature flags, or subtle branching defects in generated code.

**When to emit:** A windowed counter of **CHORD Rules** branch outcomes diverges from its committed baseline ratio beyond the configured threshold. Application code increments a lightweight counter on each decision; divergence calculation runs in Mimir recording/alerting rules rather than inside the request path.

**Structured format (metric emission on every decision):**

```json
{
  "seam_type": "RULE_DIVERGENCE",
  "event_name": "{domain}.{operation}.branch_distribution",
  "branch_name": "Name of the decision point",
  "branch_taken": "which_branch"
}
```

**Structured format (alert payload when divergence detected):**

```json
{
  "seam_type": "RULE_DIVERGENCE",
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
seam_rule_branch_total{service, component, event_name, branch_taken}
```

**Mimir recording rule (computes ratio over window):**

```
seam_rule_branch_ratio = rate(seam_rule_branch_total{branch_taken="X"}[1h])
                       / rate(seam_rule_branch_total[1h])
```

**Alert rule:** **Warning** severity — prompts human investigation into whether traffic shifted or a rule regressed.

**Baseline management:**
- Initial baseline: captured across the first 7 days of production traffic after a feature ships
- Baseline refresh: rolling 30-day average updated weekly
- Storage: `docs/baselines/{service}/{event_name}.yaml` (versioned in the repository)
- Threshold default: absolute ratio deviation > 0.15 (15 percentage points)

**Implementation pattern:**

```csharp
// Emit on every decision — divergence detection runs in Mimir, not in-process
var branch = order.Total < 100m ? "auto_approve" : "manual_review";
metrics.IncrementCounter("seam_rule_branch_total", new {
    service = "order-service",
    component = "OrderApproval",
    event_name = "order.approval.branch_distribution",
    branch_taken = branch
});
```

---

## Pattern 4: BOUNDARY_FAULT

**Purpose:** Detects when a cross-boundary contract or an observability seam contract itself is violated — either an external boundary returned an uncontracted payload/fault or a registered seam failed to emit valid telemetry.

**When to emit:** A boundary adapter, health check, or telemetry reconciliation job detects that a cross-boundary or seam contract specified by **CHORD Handling/Outcomes** is broken.

**Structured format:**

```json
{
  "seam_type": "BOUNDARY_FAULT",
  "event_name": "{domain}.{operation}.seam_contract_broken",
  "violated_seam": "Name of the seam or boundary contract that failed",
  "violation_type": "missing_emission|invalid_payload|stale_baseline",
  "detection_method": "health_check|reconciliation|manual"
}
```

**Loki query:**

```logql
{service="X"} | json | seam_type="BOUNDARY_FAULT"
```

**Mimir metric:**

```
seam_boundary_fault_total{service, component, violated_seam, violation_type}
```

**Alert rule:** **High** severity — indicates boundary or telemetry degradation that blinds production observability.

**Detection mechanisms:**

| Violation Type | Detection Method |
|---|---|
| `missing_emission` | Reconciliation: service handled N requests but emitted 0 seam metrics for a registered seam |
| `invalid_payload` | Schema validation on Loki ingest: seam event missing required fields |
| `stale_baseline` | Scheduled check: baseline file older than 60 days without refresh |

---

## Automatic Local Offload Verification across Workflow Stages

CADENCE weaves read-only local model offloading (`local-offload` MCP server and `repo-scout` / `log-triage` subagents) directly into the lifecycle of CHORD observability seams so that seam discovery, TDD verification, and pre-review auditing happen automatically at near-zero latency:

1. **Triage & Spec Discovery (`01-triage`, `02-spec`):** `cadence-triage-agent` and `cadence-spec-author` invoke `repo-scout` and `local_semantic_embed` (`local-embed-cpu` on Ryzen 9 9955HX3D at 0 MB VRAM) to semantically search `docs/agentic-sdlc/production-insights.md`, `docs/baselines/`, and existing `UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, and `BOUNDARY_FAULT` emitters across the codebase before drafting `OS-{N}` seam specifications.
2. **Implementation TDD Verification (`04-implementation`):** When `cadence-implementer` runs the red-green-accumulate test loop for `OS-{N}` seam scenarios, it delegates test runner log capture to `log-triage` / `offload_log_triage` (`local-fast-cpu`). The local coprocessor extracts verbatim assertion failures, structured JSON log emissions, and `file:line` coordinates while writing the complete raw output to `/tmp/agy-last-triage.log`.
3. **Pre-Review Mechanical Seam Audit (`05-code-review`, `06-maintainer-acceptance`):** Before `cadence-reviewer` and `cadence-maintainer` issue gate assessments, `offload_deep_review` (`local-moe-hybrid` / `local-12b-gpu`) performs an advisory mechanical scan of the diff against `spec.md` to confirm every declared CHORD seam (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) is wired with all required correlation fields and paired with positive and negative test scenarios.

---

## Implementation Checklist

When implementing any CHORD observability seam:

- [ ] Structured JSON event emitted to `stdout` (for Loki ingestion)
- [ ] Event includes all mandatory correlation fields (`trace_id`, `span_id`, `request_id`, `service`, `component`, `seam_type`, `event_name`, `chord_ac`)
- [ ] Mimir counter emitted for the seam type (`seam_unsound_condition_total`, `seam_delta_audit_gap_total`, `seam_rule_branch_total`, or `seam_boundary_fault_total`)
- [ ] Alert rule configured in Mimir matching the severity declared in `spec.md`
- [ ] Positive test scenario verifies the seam fires when the violation condition is triggered (verified via `offload_log_triage`)
- [ ] Negative test scenario verifies the seam does NOT fire during normal happy-path execution (zero false positives)
- [ ] Grafana dashboard panel provisioned for the seam metric
- [ ] Seam registered in service health/reconciliation check (for `BOUNDARY_FAULT` detection)

## Naming Conventions

| Element | Pattern | Example |
|---|---|---|
| Event name | `{domain}.{operation}.{seam_descriptor}` | `order.submit.precondition_violated` |
| Metric name | `seam_{type}_total` | `seam_unsound_condition_total` |
| Alert name | `{Service}{SeamType}{Domain}` | `OrderServiceUnsoundConditionSubmit` |
| Baseline file | `docs/baselines/{service}/{event_name}.yaml` | `docs/baselines/order-service/order.approval.branch_distribution.yaml` |
