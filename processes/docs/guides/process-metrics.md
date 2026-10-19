# DORA Metrics & Agent Quality — How to Know If It's Working

This guide defines what to measure across two dimensions: **process outcomes** (DORA metrics — is the process delivering?) and **agent quality** (are the AI agents producing good output, and are humans catching what matters?).

## Principles

1. **Measure outcomes, not activity.** "Number of specs written" is activity. "Time from problem filed to fix in production" is an outcome.
2. **Trends over absolutes.** A single slow MR means nothing. Three months of increasing cycle time means something.
3. **Metrics inform investigation, not judgment.** A metric going red means something changed — find out what.
4. **Don't optimize for the metric.** Pair every speed metric with a quality metric. Fast + broken is worse than slow + stable.
5. **Agent metrics diagnose the system, not the model.** High spec rejection rates mean CLAUDE.md is stale or SYSTEM_OVERVIEW is incomplete — it's a documentation problem, not an AI problem.

---

## Part 1: DORA Metrics (Process Outcomes)

The four DORA metrics tell you whether the process is delivering value reliably.

### 1. Deployment Frequency

**Definition:** How often you deploy to production.

**Measured as:** Deployments per week (from CD pipeline completion events)

**Healthy range:**

| Rating | Frequency | Meaning |
|---|---|---|
| Elite | Multiple per day | Process enables continuous delivery |
| High | Daily to weekly | Healthy flow, gates aren't bottlenecking |
| Medium | Weekly to monthly | Gates or pipeline may be creating queues |
| Low | Monthly or less | Process is too heavy for the change volume |

### 2. Lead Time for Changes

**Definition:** Time from first commit to deployment in production.

**Measured as:** `deployed_at - first_commit_at` (from git log and CD pipeline)

**Healthy by tier:**

| Tier | Target (P50) | Investigate if |
|---|---|---|
| Trivial | < 1 day | > 2 days |
| Low | 1-3 days | > 5 days |
| Medium | 3-7 days | > 14 days |
| High | 1-3 weeks | > 4 weeks |

**Degradation signals:**
- Gates bottlenecked (reviewers unavailable or overloaded)
- Specs rejected and reworked (poor problem statements or stale CLAUDE.md)
- Pipeline slow (ephemeral env spinup, chaos matrix duration)
- Tier over-classification (Low work getting Medium treatment)

### 3. Change Failure Rate

**Definition:** Percentage of deployments that cause an incident, rollback, or hotfix within 7 days.

**Measured as:** `(deployments_requiring_remediation / total_deployments) * 100` per month

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Elite | < 5% | Gates and tests catch nearly everything |
| High | 5-10% | Healthy — some failures are expected |
| Medium | 10-15% | Process gaps — investigate which gate is leaking |
| Low | > 15% | Systemic problem — diagnose before shipping more |

**Degradation signals:**
- Chaos profiles don't cover production failure modes
- Journey invariants are incomplete
- Reviewers are rubber-stamping (not maintaining mental model)
- Specs are too abstract (acceptance criteria don't match reality)

### 4. Mean Time to Recovery (MTTR)

**Definition:** Time from incident detection to production fix deployed.

**Measured as:** `hotfix_deployed_at - incident_detected_at`

**Healthy range:**

| Rating | MTTR | Meaning |
|---|---|---|
| Elite | < 1 hour | Emergency fast-track is working; system is well-understood |
| High | 1-4 hours | Responders can orient and fix quickly |
| Medium | 4-24 hours | System understanding gaps slow diagnosis |
| Low | > 24 hours | Critical gap — responders can't find or fix the problem |

**Degradation signals:**
- SYSTEM_OVERVIEW or flow docs are stale (responders can't orient)
- No observability seams detecting the failure category
- Emergency fast-track not being used (team defaulting to full process during incidents)
- Fix requires understanding code with no boundary documentation

---

## Part 2: Agent Quality Metrics

With AI agents generating specs, code, and reviews, you need visibility into *their* output quality. Rejection patterns are the primary signal — they reveal where agent inputs (CLAUDE.md, SYSTEM_OVERVIEW, flow docs) are stale or incomplete.

### 5. Spec Rejection Rate (Gate 1)

**Definition:** Percentage of specs rejected (or sent back for regeneration) at the Spec Review gate.

**Measured as:** `specs_rejected_or_regenerated / total_specs_submitted` per month

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Calibrated | < 20% | Agent output mostly matches human expectations |
| Drifting | 20-40% | CLAUDE.md or SYSTEM_OVERVIEW is getting stale |
| Miscalibrated | > 40% | Agent inputs are significantly wrong — major doc update needed |

**Categorize rejections** — track WHY specs are rejected:

| Rejection Category | What it reveals | Fix |
|---|---|---|
| Wrong bounded context | SYSTEM_OVERVIEW.md doesn't match reality | Update bounded context table |
| Missing flow context | Flow docs are incomplete or absent | Create/update docs/flows/ |
| Wrong architecture assumptions | CLAUDE.md Architecture section is stale | Update CLAUDE.md |
| Incomplete SCOUT decomposition | Domain model section missing entities/states | Update CLAUDE.md Domain model |
| Poor alternatives considered | Agent lacks context on prior decisions | Add to decisions.md or ADRs |
| Unnecessary complexity | Simplicity facet not grounded in real constraints | Update CLAIRE_ORG.md measures |

**The pattern to watch:** If the same rejection category appears 3+ times in a month, the documentation is systematically wrong about something. Fix the docs, not the agent.

### 6. Implementation Blocking Issue Rate (Gate 2)

**Definition:** Average number of blocking issues per MR found by the code-reviewer agent AND human reviewers.

**Measured as:** Count of `[BLOCKING]` comments per MR, categorized by source (agent vs. human) and type.

**Healthy range:**

| Rating | Blocking issues / MR (P50) | Meaning |
|---|---|---|
| Clean | 0-1 | Specs are clear, implementer is well-calibrated |
| Normal | 2-3 | Expected iteration |
| Noisy | 4+ | Spec ambiguity or implementer miscalibration |

**Categorize blocking issues:**

| Issue Category | Source | What it reveals |
|---|---|---|
| Spec deviation | Agent or human | Implementer misread the spec, or spec is ambiguous |
| Missing tests | Agent | Implementer skipped scenarios from test-plan |
| Boundary docs missing | Agent | Implementer not following boundary documentation requirements |
| Security vulnerability | Agent or human | Implementer generating insecure patterns |
| Architecture violation | Agent or human | CLAUDE.md Architecture section unclear on layer boundaries |
| Performance concern | Human only | Requires production intuition agents don't have |
| Domain correctness | Human only | Business rules in reviewer's head, not in spec |

**The pattern to watch:** If human reviewers consistently catch issues in a category the agent should catch (e.g., architecture violations), the code-reviewer agent's instructions need updating. If agents consistently flag false positives in a category, their rules are too strict.

### 6b. Code Review Rejection Rate (Gate 2 — Human)

**Definition:** Percentage of MRs that human reviewers reject (request changes) after the code-reviewer agent has already passed them.

**Measured as:** `MRs_sent_back_by_human / total_MRs_reaching_human_review` per month

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Calibrated | < 15% | Agent + implementer producing good output; humans mostly confirming |
| Gap detected | 15-30% | Humans catching things agents miss — investigate the categories |
| Systemic miss | > 30% | Code-reviewer agent or implementer is systematically wrong |

**Categorize human rejections at Gate 2:**

| Rejection Category | What it reveals | Fix |
|---|---|---|
| "Can't place this in the system" | MR description missing context, or SYSTEM_OVERVIEW stale | Enforce MR template; update docs |
| Production intuition ("this will timeout") | Legitimate human-only catch — not fixable by agents | Healthy — this is why the gate exists |
| Domain rule violation | Business rule in reviewer's head, not in spec | Add rule to CLAUDE.md Domain model or spec |
| Spec-implementation mismatch | Implementer deviated; agent reviewer didn't catch | Tighten code-reviewer agent instructions |
| Architectural concern ("wrong pattern") | CLAUDE.md Architecture section missing the pattern | Update CLAUDE.md; add to ADRs if new |
| Test insufficiency | Human spots untested path that agent missed | Add scenario category to spec-author's edge case derivation |

**Key insight:** If human rejection rate is high AND the rejection categories are things agents *should* catch, your agent instructions or documentation are the problem. If rejection categories are consistently "production intuition" or "domain knowledge," the gate is working as designed — humans are adding irreplaceable value.

### 6c. Maintainer Rejection Rate (Gate 3)

**Definition:** Percentage of MRs that the maintainer postpones or rejects after code review has passed.

**Measured as:** `(MRs_postponed + MRs_rejected) / total_MRs_reaching_maintainer` per month

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Aligned | < 10% | Specs and implementation match project direction |
| Drift | 10-25% | Some work reaching maintainer that shouldn't — tier or spec quality issue |
| Misaligned | > 25% | Systemic disconnect between spec approval and project strategy |

**Categorize maintainer rejections:**

| Rejection Category | What it reveals | Fix |
|---|---|---|
| Architectural drift | New patterns conflict with ADRs | Spec reviewer (Gate 1) should catch this — tighten spec review checklist |
| Scope creep | Change is tangential to project goals | Problem statement quality issue — triage should filter better |
| Maintenance cost too high | Too many new dependencies/patterns | Simplicity facet not being enforced in spec |
| Breaking change without migration | Backwards compatibility missed | Code-reviewer should catch — tighten compatibility checks |
| Documentation currency | Flow docs stale after this change | Doc freshness check in CI should be catching this |
| Release readiness | Missing CHANGELOG, rollback plan, deprecation notices | Implementer checklist incomplete |

**Key insight:** Maintainer rejections are the most expensive — the work is fully built before being rejected. High maintainer rejection rate means upstream gates (spec review, tier assignment) are letting through work that shouldn't reach this point. The fix is almost always upstream:

- If "architectural drift" is high → Gate 1 (spec review) isn't checking architecture
- If "scope creep" is high → Triage isn't filtering well, or problem statements are too broad
- If "maintenance cost" is high → Spec-author isn't evaluating Simplicity facet honestly

### 6d. Cross-Gate Rejection Correlation

**Definition:** When an MR is rejected at Gate 3, was there a signal at Gate 1 or Gate 2 that was missed?

**Measured as:** For each maintainer rejection, retrospectively check:
- Did the spec reviewer approve without addressing the concern?
- Did the code reviewer flag a related `[SUGGESTION]` that was ignored?
- Did the tier assignment underestimate the change?

**What patterns reveal:**

| Pattern | Signal | Systemic fix |
|---|---|---|
| Gate 1 approved, Gate 3 rejects for architecture | Spec reviewer not checking ADR compliance | Add ADR check to Gate 1 checklist |
| Gate 2 suggested, author ignored, Gate 3 blocks | `[SUGGESTION]` escalation path missing | Clarify when suggestions become blocks at next gate |
| Tier was Low, maintainer says it's High | Author underclassified to skip gates | Tighten CI tier validation triggers |
| Gate 1 approved, Gate 3 rejects for scope | Problem statement too broad, spec didn't narrow | Triage needs sharper scope definition |

**The goal:** Push rejections upstream. A rejection at Gate 3 costs the most (full implementation done). A rejection at Gate 1 costs the least (only a spec to rework). Invest in Gate 1 quality to reduce Gate 3 rejections.

### 7. Regeneration Pattern Analysis

**Definition:** Which spec sections are most frequently regenerated after Gate 1 feedback.

**Measured as:** Track which files are modified between spec submission and spec approval:
- `spec.md` section edits (Zachman grid rows, SCOUT decompositions, proposed design)
- `test-plan.md` modifications (scenarios added/removed/rewritten)
- `decisions.md` additions during review

**What frequent regeneration of each section reveals:**

| Section regenerated | Signal | Root cause |
|---|---|---|
| Zachman Scope/Business Model rows | Spec-author lacks business context | problem.md needs better stakeholder input |
| Zachman System/Technology rows | Architecture assumptions wrong | CLAUDE.md Architecture section stale |
| SCOUT State | Entity states not documented | CLAUDE.md Domain model incomplete |
| SCOUT Outputs | External integrations not documented | CLAUDE.md External integrations stale |
| Proposed Design - file paths | Project structure changed since CLAUDE.md written | Run CLAUDE.md validation (getting-started.md §3) |
| Test plan - scenarios | Acceptance criteria ambiguous | problem.md needs sharper AC definitions |
| Journey invariants | Business rules not explicit | CLAUDE.md Domain model missing invariants |

### 8. Agent Drift Detection

**Definition:** The same error pattern appearing in 3+ consecutive specs or implementations from the same agent.

**Measured as:** Tag each rejection/blocking issue with a category. Alert when any category occurs 3+ times in a rolling 2-week window.

**Examples of drift:**

| Drift pattern | Evidence | Fix |
|---|---|---|
| Spec-author consistently places new features in wrong context | 3 specs rejected for "wrong bounded context" in 2 weeks | SYSTEM_OVERVIEW.md bounded contexts table is stale or ambiguous |
| Implementer generates code in wrong directory | 3 MRs with file placement issues | CLAUDE.md Architecture section needs explicit path mapping |
| Implementer missing boundary docs on same service boundary | 3 MRs missing docs for Service A → Service B | The boundary isn't documented in SYSTEM_OVERVIEW interaction map |
| Code-reviewer flagging false positives on a pattern | 3 `[BLOCKING]` comments overridden by human reviewer | Code-reviewer agent instructions too strict for this pattern |

**Resolution:** Agent drift is always a documentation problem. When detected:
1. Identify which document is wrong or missing (CLAUDE.md, SYSTEM_OVERVIEW, flow docs, agent AGENT.md)
2. Fix the document
3. Verify: run the agent against the next piece of work and confirm the drift stops

---

## Part 3: Human Gate Effectiveness

The gates exist so humans catch what agents can't. These metrics verify the gates are actually working.

### 9. Gate Catch Rate (Retrospective)

**Definition:** For each production incident, retrospectively assess: which gate *could* have caught this?

**Measured as:** After each incident, during post-incident review, tag the incident with:
- `catchable_at: gate_1` (spec should have identified the risk)
- `catchable_at: gate_2` (code review should have caught the pattern)
- `catchable_at: gate_3` (maintainer should have flagged the architectural risk)
- `catchable_at: pipeline` (CI tests should have detected the failure)
- `catchable_at: none` (genuinely novel — no gate could reasonably have caught it)

**Healthy distribution:**

| Catchable at | Target % of incidents | If higher |
|---|---|---|
| Gate 1 (Spec) | < 10% | Specs are missing risk analysis |
| Gate 2 (Code) | < 15% | Reviewers not catching correctness issues |
| Gate 3 (Maintainer) | < 10% | Architectural risks slipping through |
| Pipeline | < 20% | Test coverage gaps — add chaos profiles or journey invariants |
| None (novel) | > 50% | Healthy — most escapes should be genuinely new failure modes |

**The danger signal:** If "catchable at gate_2" is > 30%, human reviewers are not engaging critically. Investigate: are they rubber-stamping? Overwhelmed? Missing domain context?

### 10. Rubber-Stamp Detection

**Definition:** Approvals that show signs of insufficient review depth.

**Indicators:**
- Approval within < 5 minutes of MR being assigned (for Medium/High tier)
- Zero comments on a High-tier MR (no questions, no suggestions, no confirmations)
- Approval without any commits to the reviewer's browser (they didn't open the diff — requires tooling integration)
- Repeated same-day approval from one reviewer across 5+ MRs (batch-reviewing without depth)

**This is NOT measured to blame individuals.** It's measured to detect:
- Reviewer overload (too many MRs assigned → quality drops)
- Gate becoming ceremonial (everyone approves because "the agent already checked it")
- Missing domain expertise (reviewer doesn't know enough to ask questions)

**Response:** If rubber-stamping is detected, don't add more process. Instead:
- Reduce reviewer load (fewer MRs per reviewer per day)
- Rotate reviewers to spread knowledge
- Make the "orient in architecture" step mandatory in the PR template (checkbox: "I can state which context and flow this belongs to")

### 11. Human-Added Value Rate

**Definition:** Percentage of human review comments that identify issues the agent did NOT flag.

**Measured as:** `human_unique_findings / total_human_comments` (excluding style suggestions)

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| High value | > 60% | Humans catching things agents can't — gates working as designed |
| Overlap | 30-60% | Some redundancy — agents could be configured to catch more |
| Low value | < 30% | Humans mostly echoing agent findings — gates may be unnecessary at this tier |

**If low:** Consider whether the tier is correct. If humans add little beyond what agents find, the change may be over-tiered (should be Low instead of Medium, skipping some gates).

---

## Collection Strategy

### Automated (build into CI/CD)

| Metric | Source | How |
|---|---|---|
| Deployment frequency | CD pipeline | Count successful deploy jobs per week |
| Lead time | Git + CD | `deployed_at - first_commit_at` |
| Change failure rate | Incident system + CD | Count hotfix deploys within 7 days of feature deploy |
| MTTR | Incident system + CD | `hotfix_deployed_at - alert_fired_at` |
| Pipeline duration | CI | Job timing metadata |
| Blocking issues per MR | Code-reviewer output | Parse `[BLOCKING]` tags in MR comments |
| Doc freshness failures | CI | Count doc-check stage failures |

### Semi-Automated (requires tagging)

| Metric | Source | How |
|---|---|---|
| Spec rejection rate | metadata.yaml status transitions | Count `spec-in-review → spec-in-review` cycles |
| Rejection categories | Gate 1 reviewer comments | Tag with category during review |
| Regeneration patterns | Git diff on spec files between reviews | Automated diff analysis |
| Agent drift | Rejection category time-series | Alert on 3+ same-category in 2 weeks |

### Manual (post-incident and monthly review)

| Metric | Source | How |
|---|---|---|
| Gate catch rate | Post-incident review | Human tags during retrospective |
| Rubber-stamp detection | MR metadata + timing | Review approval timing vs. MR size |
| Human-added value rate | MR comment analysis | Monthly sample of 10 MRs |
| Insight recurrence | production-insights.md | Tag related insights |

---

## Review Cadence

| Metric Set | Frequency | Who | Action if degraded |
|---|---|---|---|
| DORA (1-4) | Weekly at team sync | Team lead | Investigate bottleneck, adjust tiers or reviewer load |
| Agent quality (5-8) | Biweekly | Maintainer | Update CLAUDE.md, SYSTEM_OVERVIEW, or agent instructions |
| Gate effectiveness (9-11) | Monthly | Engineering lead | Adjust gate requirements, reviewer assignments, or tier policy |

---

## Anti-Patterns

- **Measuring individuals:** These are system metrics. Never rank reviewers by approval speed or agents by rejection rate. The system produces the outcomes; fix the system.
- **Metric targets as OKRs:** "Achieve < 5% change failure rate" incentivizes not counting rollbacks. Track trends, investigate anomalies — don't gamify.
- **Blaming the model:** High spec rejection rate means the agent's *inputs* are wrong (your docs), not that the model is bad. Fix the inputs.
- **Over-collecting:** Start with DORA (metrics 1-4) and spec rejection rate (metric 5). Add the rest only when those degrade and you need diagnostics.
- **Ignoring the "none" category:** If most incidents are "catchable at none," that's healthy — it means your process catches what it can and novel failures are genuinely novel. Don't add gates to catch the uncatchable.
