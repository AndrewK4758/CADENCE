# DORA Metrics & Agent Quality — How to Know If It's Working

This guide defines how to evaluate a CADENCE repository across two complementary axes: **delivery outcomes** (the four DORA metrics — is the workflow shipping reliable software at a healthy pace?) and **agent & gate calibration** (are the AI agents producing accurate artifacts, and are the human gates catching what only humans can?).

## Principles

1. **Measure outcomes, not activity.** "Number of specifications authored" is raw activity; "elapsed time from problem intake to verified fix in production" is a delivery outcome.
2. **Trends over single-point absolutes.** One slow MR is noise; three consecutive months of rising lead time signals a structural bottleneck.
3. **Metrics trigger investigation, never blame.** When an indicator turns red, treat it as a diagnostic signal that a system input or gate constraint shifted — find out why.
4. **Never optimize a speed metric in isolation.** Pair every throughput metric with a stability metric. Shipping fast and broken is strictly worse than shipping deliberately and cleanly.
5. **Agent quality metrics diagnose repository context, not model intelligence.** A spike in Gate 1 spec rejections almost always means `AGENTS.md`, `CADENCE_ORG.md`, or `docs/SYSTEM_OVERVIEW.md` has drifted from reality — fix the context documents that feed the agent.

---

## Part 1: DORA Metrics (Process Outcomes)

The four standard DORA metrics measure whether the CADENCE delivery pipeline is producing value predictably and safely.

### 1. Deployment Frequency

**Definition:** How frequently changes are deployed to production.

**Measured as:** Completed production deployments per week (derived from CD pipeline events).

**Healthy range:**

| Rating | Frequency | Meaning |
|---|---|---|
| Elite | Multiple per day | Process enables continuous delivery |
| High | Daily to weekly | Healthy flow, gates aren't bottlenecking |
| Medium | Weekly to monthly | Gates or pipeline may be creating queues |
| Low | Monthly or less | Process is too heavy for the change volume |

### 2. Lead Time for Changes

**Definition:** Elapsed time from first commit on a ticket branch to production deployment.

**Measured as:** `deployed_at - first_commit_at` (computed from Git commit timestamps and CD deployment logs).

**Healthy by tier:**

| Tier | Target (P50) | Investigate if |
|---|---|---|
| Trivial | < 1 day | > 2 days |
| Low | 1-3 days | > 5 days |
| Medium | 3-7 days | > 14 days |
| High | 1-3 weeks | > 4 weeks |

**Degradation signals:**
- Human review gates queued up (reviewers overloaded or SLA too wide)
- Specifications sent back repeatedly for regeneration (unclear `problem.md` or stale `AGENTS.md`)
- Slow CI execution (ephemeral environment provisioning or chaos suite runtime)
- Systematic over-tiering (single-context Low changes misclassified as Medium)

### 3. Change Failure Rate

**Definition:** Percentage of production deployments that trigger a production incident, rollback, or emergency hotfix within 7 calendar days.

**Measured as:** `(deployments_requiring_remediation / total_deployments) * 100` per month.

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Elite | < 5% | Gates and tests catch nearly everything |
| High | 5-10% | Healthy — some failures are expected |
| Medium | 10-15% | Process gaps — investigate which gate is leaking |
| Low | > 15% | Systemic problem — diagnose before shipping more |

**Degradation signals:**
- Chaos profile catalog (`docs/policies/chaos-profiles.md`) missing an active production fault mode
- Journey invariants in `test-plan.md` underspecified
- Reviewers rubber-stamping at Gate 2 or Gate 3 without verifying system mental model
- Specifications written at too high an abstraction level (CHORD rules/conditions not grounded in real code)

### 4. Mean Time to Recovery (MTTR)

**Definition:** Elapsed time from production incident detection to a verified remediation deployed in production.

**Measured as:** `hotfix_deployed_at - incident_detected_at`.

**Healthy range:**

| Rating | MTTR | Meaning |
|---|---|---|
| Elite | < 1 hour | Emergency fast-track is working; system is well-understood |
| High | 1-4 hours | Responders can orient and fix quickly |
| Medium | 4-24 hours | System understanding gaps slow diagnosis |
| Low | > 24 hours | Critical gap — responders can't find or fix the problem |

**Degradation signals:**
- `docs/SYSTEM_OVERVIEW.md` or `docs/flows/` are stale (on-call engineers waste time orienting)
- Missing CHORD observability seams (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) for the failure class
- Team hesitating to invoke `docs/policies/emergency-fast-track.md` during active outages
- Cross-boundary code lacking `C7` boundary header comments (`docs/policies/comment-discipline.md`)

---

## Part 2: Agent Quality Metrics

Because CADENCE agents (`cadence-triage-agent`, `cadence-spec-author`, `cadence-implementer`, `cadence-reviewer`, `cadence-maintainer`) draft specifications, code, and review assessments, tracking their rejection and revision rates reveals where repository context (`AGENTS.md`, `CADENCE_ORG.md`, `docs/SYSTEM_OVERVIEW.md`, `docs/flows/`) has gone stale.

### 5. Spec Rejection Rate (Gate 1)

**Definition:** Percentage of specifications rejected or sent back for `/cadence-spec` regeneration at Gate 1 (Spec Approval).

**Measured as:** `specs_rejected_or_regenerated / total_specs_submitted` per month.

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| Calibrated | < 20% | Agent output mostly matches human expectations |
| Drifting | 20-40% | AGENTS.md or SYSTEM_OVERVIEW is getting stale |
| Miscalibrated | > 40% | Agent inputs are significantly wrong — major doc update needed |

**Categorize rejections** — track WHY specifications require regeneration:

| Rejection Category | What it reveals | Fix |
|---|---|---|
| Wrong bounded context | SYSTEM_OVERVIEW.md doesn't match reality | Update bounded context table |
| Missing flow context | Flow docs are incomplete or absent | Create/update docs/flows/ |
| Wrong architecture assumptions | AGENTS.md Architecture section is stale | Update AGENTS.md |
| Incomplete CHORD decomposition | Domain model section missing entities/states | Update AGENTS.md Domain model |
| Poor alternatives considered | Agent lacks context on prior decisions | Add to decisions.md or ADRs |
| Unnecessary complexity | Simplicity pillar not grounded in real constraints | Update CADENCE_ORG.md measures |

**The pattern to watch:** Whenever the same rejection category recurs 3 or more times within a month, the repository's grounding documentation is systematically misleading `cadence-spec-author`. Fix the grounding doc rather than hand-editing individual specs.

### 6. Implementation Blocking Issue Rate (Gate 2)

**Definition:** Median number of `[BLOCKING]` findings raised per MR across both `cadence-reviewer` (including `offload_deep_review` pre-scans) and human code reviewers.

**Measured as:** Count of `[BLOCKING]` findings per MR, segmented by source (agent vs. human) and defect category.

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
| Architecture violation | Agent or human | AGENTS.md Architecture section unclear on layer boundaries |
| Performance concern | Human only | Requires production intuition agents don't have |
| Domain correctness | Human only | Business rules in reviewer's head, not in spec |

**The pattern to watch:** If human reviewers repeatedly catch mechanical defects that `cadence-reviewer` or `offload_deep_review` should have flagged (such as layer-boundary violations or `< 400`-line ceiling breaches), refine the reviewer role instructions in `artifacts/roles/cadence-reviewer.md`. Conversely, if the agent raises recurring false positives on an accepted idiom, document that idiom in `AGENTS.md`.

### 6b. Code Review Rejection Rate (Gate 2 — Human)

**Definition:** Percentage of MRs where a human reviewer requests changes after `cadence-reviewer` returned an `Approve` recommendation.

**Measured as:** `MRs_sent_back_by_human / total_MRs_reaching_human_review` per month.

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
| Domain rule violation | Business rule in reviewer's head, not in spec | Add rule to AGENTS.md Domain model or spec |
| Spec-implementation mismatch | Implementer deviated; agent reviewer didn't catch | Tighten code-reviewer agent instructions |
| Architectural concern ("wrong pattern") | AGENTS.md Architecture section missing the pattern | Update AGENTS.md; add to ADRs if new |
| Test insufficiency | Human spots untested path that agent missed | Add scenario category to spec-author's edge case derivation |

**Key insight:** When human rejection rates climb and the findings fall into mechanical or architectural categories that agents *can* verify, update `AGENTS.md` or the role definitions. When human findings consistently represent "production intuition" or subtle operational hazards, Gate 2 is delivering high-leverage human judgment as intended.

### 6c. Maintainer Rejection Rate (Gate 3)

**Definition:** Percentage of MRs that the human maintainer postpones or rejects at Gate 3 after passing Gate 2 Code Review.

**Measured as:** `(MRs_postponed + MRs_rejected) / total_MRs_reaching_maintainer` per month.

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
| Maintenance cost too high | Too many new dependencies/patterns | Simplicity pillar not being enforced in spec |
| Breaking change without migration | Backwards compatibility missed | Code-reviewer should catch — tighten compatibility checks |
| Documentation currency | Flow docs stale after this change | Doc freshness check in CI should be catching this |
| Release readiness | Missing CHANGELOG, rollback plan, deprecation notices | Implementer checklist incomplete |

**Key insight:** Gate 3 rejections are the most expensive in the lifecycle because the code has already been specified, implemented, and code-reviewed. A high Gate 3 rejection rate signals that upstream gates (Triage intent-fit check or Gate 1 Spec Approval) are letting misaligned work through:

- High "architectural drift" at Gate 3 → strengthen ADR verification at Gate 1.
- High "scope creep" at Gate 3 → tighten `PROJECT_INTENT.md` screening during `/cadence-triage`.
- High "maintenance cost" at Gate 3 → enforce the Simplicity Engineering Pillar more strictly during `/cadence-spec`.

### 6d. Cross-Gate Rejection Correlation

**Definition:** When an MR is rejected or postponed at Gate 3, did an earlier gate surface a warning or suggestion that went unaddressed?

**Measured as:** For every Gate 3 rejection, trace backward across the ticket's artifacts:
- Did Gate 1 approve `spec.md` without resolving a related risk or open question?
- Did Gate 2 log a non-blocking finding (`observation` / `hygiene`) on the same concern that the author left unaddressed?
- Did initial tier classification under-scope a Medium/High change as Low?

**What patterns reveal:**

| Pattern | Signal | Systemic fix |
|---|---|---|
| Gate 1 approved, Gate 3 rejects for architecture | Spec reviewer not checking ADR compliance | Add ADR check to Gate 1 checklist |
| Gate 2 suggested, author ignored, Gate 3 blocks | `[SUGGESTION]` escalation path missing | Clarify when suggestions become blocks at next gate |
| Tier was Low, maintainer says it's High | Author underclassified to skip gates | Tighten CI tier validation triggers |
| Gate 1 approved, Gate 3 rejects for scope | Problem statement too broad, spec didn't narrow | Triage needs sharper scope definition |

**The goal:** Shift defect and alignment discovery left. Catching an architectural mismatch at Gate 1 costs a 10-minute spec regeneration; catching it at Gate 3 costs a full implementation rewrite.

### 7. Regeneration Pattern Analysis

**Definition:** Which sections of `spec.md` and `test-plan.md` require the most frequent edits or regenerations between initial `/cadence-spec` output and Gate 1 approval.

**Measured as:** Inspect Git diffs on `specs/{ticket-id}/` across `spec-in-review` iterations:
- `spec.md` section edits (Contextual Grounding Matrix (6W×4L) rows, CHORD decompositions, Engineering Pillar evaluations, Proposed Design file signatures)
- `test-plan.md` edits (Gherkin scenarios added, removed, or re-sequenced)
- `decisions.md` entries added during spec review

**What frequent regeneration of each section reveals:**

| Section regenerated | Signal | Root cause |
|---|---|---|
| Contextual Grounding Matrix Scope/Business Model rows | Spec-author lacks business context | problem.md needs better stakeholder input |
| Contextual Grounding Matrix System/Technology rows | Architecture assumptions wrong | AGENTS.md Architecture section stale |
| CHORD Conditions | Entity states not documented | AGENTS.md Domain model incomplete |
| CHORD Outcomes | External integrations not documented | AGENTS.md External integrations stale |
| Proposed Design - file paths | Project structure changed since AGENTS.md written | Run AGENTS.md validation (getting-started.md §3) |
| Test plan - scenarios | Acceptance criteria ambiguous | problem.md needs sharper AC definitions |
| Journey invariants | Business rules not explicit | AGENTS.md Domain model missing invariants |

### 8. Agent Drift Detection

**Definition:** The exact same class of error recurring across 3 or more consecutive specifications or implementations generated by the same CADENCE agent role.

**Measured as:** Tag each gate rejection or blocking finding with its root-cause category and alert whenever any single category appears 3+ times within a rolling 14-day window.

**Examples of drift:**

| Drift pattern | Evidence | Fix |
|---|---|---|
| Spec-author consistently places new features in wrong context | 3 specs rejected for "wrong bounded context" in 2 weeks | SYSTEM_OVERVIEW.md bounded contexts table is stale or ambiguous |
| Implementer generates code in wrong directory | 3 MRs with file placement issues | AGENTS.md Architecture section needs explicit path mapping |
| Implementer missing boundary docs on same service boundary | 3 MRs missing docs for Service A → Service B | The boundary isn't documented in SYSTEM_OVERVIEW interaction map |
| Code-reviewer flagging false positives on a pattern | 3 `[BLOCKING]` comments overridden by human reviewer | Code-reviewer agent instructions too strict for this pattern |

**Resolution:** Repetitive agent drift is always a context/documentation defect:
1. Pinpoint which grounding file is stale or incomplete (`AGENTS.md`, `CADENCE_ORG.md`, `docs/SYSTEM_OVERVIEW.md`, `docs/flows/`, or the role definition in `artifacts/roles/`).
2. Reconcile the document (and recompile `.agents/` / `.gemini/` via `cadence-compile.sh` if an agent role changed).
3. Verify on the next ticket that the recurring error disappears.

---

## Part 3: Human Gate Effectiveness

Human gates exist so engineers contribute judgment that models cannot. These metrics verify that human gates remain sharp rather than ceremonial.

### 9. Gate Catch Rate (Retrospective)

**Definition:** Following any production incident, determine retrospectively which pre-merge gate *could* reasonably have intercepted the defect.

**Measured as:** During post-incident review (`docs/policies/emergency-fast-track.md`), tag the incident entry in `docs/agentic-sdlc/production-insights.md` with one of:
- `catchable_at: gate_1` (the specification should have surfaced the design risk or missing CHORD condition)
- `catchable_at: gate_2` (code review should have spotted the implementation flaw)
- `catchable_at: gate_3` (maintainer acceptance should have flagged the cross-system or compatibility hazard)
- `catchable_at: pipeline` (automated unit/integration/contract/chaos tests should have failed)
- `catchable_at: none` (genuinely novel emergent failure mode that no existing gate could reasonably predict)

**Healthy distribution:**

| Catchable at | Target % of incidents | If higher |
|---|---|---|
| Gate 1 (Spec) | < 10% | Specs are missing risk analysis |
| Gate 2 (Code) | < 15% | Reviewers not catching correctness issues |
| Gate 3 (Maintainer) | < 10% | Architectural risks slipping through |
| Pipeline | < 20% | Test coverage gaps — add chaos profiles or journey invariants |
| None (novel) | > 50% | Healthy — most escapes should be genuinely new failure modes |

**The danger signal:** If `catchable_at: gate_2` exceeds 30% of incidents, human code reviewers are rubber-stamping AI output. Investigate whether reviewers are overloaded, rushing through large diffs, or lacking architectural orientation.

### 10. Rubber-Stamp Detection

**Definition:** Gate approvals exhibiting symptoms of superficial review.

**Indicators:**
- Gate 1, Gate 2, or Gate 3 approval recorded within `< 5 minutes` of assignment on a Medium- or High-tier ticket
- Zero questions, observations, or confirmations recorded on a High-tier MR
- Approval without opening the diff or specification artifacts
- A single reviewer batch-approving 5+ Medium/High MRs within a narrow window without substantive commentary

**This metric diagnoses reviewer load and gate health, never individual culpability.** It surfaces:
- Reviewer saturation (too many MRs routed to too few Trusted Committers / Maintainers)
- Automation complacency ("`cadence-reviewer` and `offload_deep_review` passed, so I don't need to read carefully")
- Context gaps (the assigned reviewer lacks familiarity with the bounded context)

**Response:** When rubber-stamping appears, never pile on extra bureaucratic checkboxes. Instead:
- Rebalance review load across more Trusted Committers
- Enforce the `< 400`-line file ceiling and focused MR scoping so diffs stay single-pass readable
- Require the one-sentence architectural orientation statement in `submission.md` ("Which bounded context and flow does this change modify?")

### 11. Human-Added Value Rate

**Definition:** Proportion of substantive human review comments that surface insights, hazards, or domain rules that the AI review agent (`cadence-reviewer` / `cadence-maintainer`) did NOT flag.

**Measured as:** `human_unique_findings / total_human_comments` (excluding `nit` style comments).

**Healthy range:**

| Rating | Rate | Meaning |
|---|---|---|
| High value | > 60% | Humans catching things agents can't — gates working as designed |
| Overlap | 30-60% | Some redundancy — agents could be configured to catch more |
| Low value | < 30% | Humans mostly echoing agent findings — gates may be unnecessary at this tier |

**If low:** Either codify the repetitive human checks into `AGENTS.md` / `offload_deep_review` so the AI catches them automatically, or check whether Low-risk work is being over-classified as Medium.

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
| Agent quality (5-8) | Biweekly | Maintainer | Update AGENTS.md, SYSTEM_OVERVIEW, or agent instructions |
| Gate effectiveness (9-11) | Monthly | Engineering lead | Adjust gate requirements, reviewer assignments, or tier policy |

---

## Anti-Patterns

- **Stack-ranking individuals:** Every metric in this guide measures *system* performance. Ranking engineers by review speed or agents by rejection count incentivizes gaming and hides root causes.
- **Turning diagnostic metrics into punitive OKRs:** Setting a hard mandate like "Change Failure Rate must stay below 3%" encourages teams to reclassify hotfixes as "routine enhancements" rather than learning from incidents.
- **Blaming the underlying LLM:** When `cadence-spec-author` or `cadence-implementer` repeatedly misses a house convention, the repository's `AGENTS.md` or `SYSTEM_OVERVIEW.md` is missing that fact. Fix the repository's context.
- **Boiling the ocean on day one:** Start by tracking DORA metrics (1–4) and Gate 1 Spec Rejection Rate (metric 5). Introduce the deeper diagnostic metrics (6–11) when a headline trend degrades.
- **Trying to eliminate `catchable_at: none`:** When more than half of rare production incidents fall into `catchable_at: none`, your pre-merge gates are filtering out known failure classes effectively. Feed the new failure mode into `production-insights.md` and `chaos-profiles.md` rather than adding heavyweight manual sign-offs.
