# Team Rituals for the Agentic SDLC

Traditional agile ceremonies assume human engineers write every line of code by hand and need daily synchronization to coordinate incremental implementation. In the CADENCE agentic SDLC, AI agents execute triage, exploration, specification, TDD implementation, and archival. The team's constraint shifts from *"how do we coordinate manual coding?"* to *"how do we move high-leverage decisions cleanly through human gates?"*

This guide defines the team rituals built for that operating model.

---

## The Bottleneck Shift

In a conventional sprint, developer coding bandwidth is the scarce resource. Ceremonies exist to allocate coding hours (sprint planning), surface implementation blockers (daily standup), and refine estimation accuracy (sprint retro).

In the CADENCE model, the scarce resources are:

- **Human judgment** — Gate 1 Spec Review, Gate 2 Code Review, Gate 3 Maintainer Acceptance, and Gate 4 Deploy Validation
- **Shared architectural context** — keeping every engineer's mental model synchronized as changes land rapidly across bounded contexts
- **System & agent calibration** — ensuring agents, prompts, and engineering pillars sharpen rather than drift over time

Every team ritual must serve one of these three needs; anything else is legacy ceremony.

---

## Rituals to Adopt

### Prioritization Commit

| | |
|---|---|
| **Replaces** | Sprint planning, sprint kickoff |
| **Cadence** | Weekly (30 min) |
| **Attendees** | Product stewards, domain architects, maintainers, contributors |
| **Output** | Ranked weekly intake queue; explicit human gate ownership commitments |

Each participant commits to what enters the specification pipeline (*"run `/cadence-spec` and clear Gate 1 for tickets X and Y"*) and which in-flight reviews they will clear (*"complete Gate 2 / Gate 3 review on MRs A and B"*). This ritual acts as the intake governor — without it, agents can generate specs and MRs far faster than humans can thoughtfully review them.

The session answers two questions:
1. Which problems merit specification next? (Intake prioritization)
2. Who is accountable for clearing which human gates this week? (Review capacity)

Implementation task breakdowns are never discussed here; `cadence-triage-agent` and `cadence-spec-author` prepare the artifacts, and humans govern what advances.

### Gate Review

| | |
|---|---|
| **Replaces** | Daily standup |
| **Cadence** | Async-first; optional 15 min live sync 2–3x/week |
| **Attendees** | Engineers and maintainers holding pending gate reviews |
| **Output** | Unblocked gates and cleared review bottlenecks |

Participants post asynchronously: *"What tickets or MRs are waiting on my gate judgment today?"* A brief live sync convenes only to resolve cross-repository contention or escalate items approaching their SLA ceiling.

Because `metadata.yaml` records every lifecycle transition timestamp, an automated query showing *"specs awaiting Gate 1 > 48h"* and *"MRs awaiting Gate 2/3 > 72h"* replaces verbal status reporting.

Rules:
- Never ask *"what did you code yesterday?"* — git history and `stage_effort` logs already record that
- Never discuss in-progress agent TDD loops — `cadence-implementer` handles execution
- Focus strictly on items blocked on a human gate decision

### Spec Critique

| | |
|---|---|
| **Replaces** | Backlog refinement, story-splitting workshops |
| **Cadence** | On-demand (triggered when an M, L, or XL specification enters Gate 1 review) |
| **Attendees** | 2–3 engineers/architects with deep domain context |
| **Output** | Architectural feedback folded into `spec.md` prior to formal Gate 1 sign-off |

When `cadence-explorer` and `cadence-spec-author` finish drafting a Medium or High tier specification (`scope: M | L | XL`), convene a focused 20-minute critique before recording formal Gate 1 approval:

- Did the explorer's option set in `design-options.md` miss a viable architectural alternative or an unstated failure mode?
- Is the Contextual Grounding Matrix (6W×4L) accurate for this bounded context?
- Does the CHORD decomposition (Conditions, Handling, Outcomes, Rules, Deltas) capture the real domain invariants and observability seams?
- Are surface compatibility and migration impacts completely accounted for?

Catching structural misunderstandings here keeps formal Gate 1 sign-off fast and rigorous.

### Merge Showcase

| | |
|---|---|
| **Replaces** | Sprint demo, sprint review |
| **Cadence** | Weekly or biweekly (20–30 min) |
| **Attendees** | All contributors across neighboring repositories |
| **Output** | Shared mental models; visibility into cross-context impacts |

While `cadence-archivist` automatically updates `CHANGELOG.md` and projects status to external trackers, keeping human mental models aligned requires human narrative.

For each notable ticket merged since the prior showcase, the reviewer or author briefly covers:
- What domain problem did this solve?
- Which design option won in `design-options.md`, and what trade-off surprised us during review?
- What downstream behavioral or surface changes should neighboring teams watch for?

### Process Retro

| | |
|---|---|
| **Replaces** | Sprint retrospective |
| **Cadence** | Biweekly (45 min) |
| **Attendees** | Engineering team + AI Workflow Steward |
| **Output** | Governance/prompt tuning MRs; at most one human process adjustment |

The retrospective shifts focus from *"how did individual developers perform?"* to *"how well is our CADENCE system performing?"*

Core diagnostic questions:
- At which human gate are tickets aging the longest?
- Are `cadence-implementer` MRs requiring multiple rework cycles at Gate 2?
- Are we approving specifications at Gate 1 that turn out to have incomplete CHORD decompositions during TDD?
- Are scope or charter mismatches making it all the way to Gate 3 instead of being caught at triage or Gate 1?

Inspect `decisions.md` and `Gate 1 Design Exploration outcome` logs across recently archived tickets (`archive/*/`) to evaluate whether our trade-offs held up.

The primary output of Process Retro is **system tuning**: refining role definitions under `artifacts/roles/`, updating `AGENTS.md` directives, tightening Engineering Pillar measures in `CADENCE_ORG.md`, or adjusting gate checklists. Cap human-behavior action items at one per retro — encoding improvements into the framework scales permanently.

### Cross-Project Surface Check

| | |
|---|---|
| **Replaces** | Cross-team dependency syncs, change-advisory board meetings |
| **Cadence** | Weekly (async-first; live sync only when contention arises) |
| **Attendees** | Anyone introducing, modifying, or consuming registered public surfaces |
| **Output** | Early contract-conflict detection; current `surface-registry.md` entries |

In an inner-source or multi-service environment, contributors post a brief weekly async notice whenever their active specifications touch `docs/policies/surface-registry.md`:
- *"Ticket X proposes an additive change to surface Y"*
- *"Ticket Z introduces a new stable event schema in context W"*
- *"We plan to deprecate endpoint V with a 2-cycle sunset window"*

Consuming teams reply asynchronously if the proposal affects their service, escalating to a live conversation only when a contract conflict surfaces.

### Agent Calibration

| | |
|---|---|
| **Replaces** | Nothing (purpose-built for the agentic SDLC) |
| **Cadence** | Monthly (60 min) |
| **Attendees** | AI Workflow Steward, maintainers, domain architects |
| **Output** | MRs tuning agent role prompts, local offload thresholds, and pillar rules |

Review aggregate CADENCE telemetry across the trailing month:
- Gate 1 override rate (`accepted with amendment` + `overridden to a different option` in `decisions.md`)
- Gate 1 ruling labels (`diverged`, `examined`, `accepted-as-presented`)
- Gate 2 rework frequency and recurring `[BLOCKING]` finding classes
- `production-insights.md` and `intent-insights.md` trend lines
- Gate throughput and cycle-time bands (`estimated_effort` vs accumulated `actual_effort`)

Use these findings to sharpen `artifacts/roles/`, `CADENCE_ORG.md` pillar measures, `AGENTS.md` rules, and local coprocessor pre-review checks.

### Incident Review

| | |
|---|---|
| **Replaces** | Traditional postmortem (extended for CHORD & agentic guardrails) |
| **Cadence** | Per production incident |
| **Attendees** | Incident responders, maintainers, domain owners |
| **Output** | Blameless postmortem; `production-insights.md` (`PROD-NNN`) entry; systemic guardrail fix |

Standard blameless postmortem practices apply, augmented by two CADENCE feedback steps:
1. Record a `PROD-NNN` entry in `docs/agentic-sdlc/production-insights.md` classifying the defect (`LOGIC_FAULT`, `DELTA_AUDIT_GAP`, `DRIFT_SIGNAL`, or `BOUNDARY_FAULT`) and mapping it to the CHORD dimension where the gap escaped (`Conditions`, `Handling`, `Outcomes`, `Rules`, or `Deltas`).
2. Whenever the defect escaped a specification, migration, or TDD guardrail, encode a systemic prevention rule into the relevant agent role or policy so the entire class of failure is caught mechanically on future tickets.

---

## Rituals to Drop

| Legacy Ceremony | Why It Is Retired in CADENCE |
|---|---|
| Daily standup | Async Gate Review surfaces blocked human gates directly from `metadata.yaml` without interrupting deep work |
| Sprint velocity / story-point burndown | When agent TDD execution takes minutes rather than days, coding velocity is noise; gate throughput and cycle time are the real signals |
| Planning poker / story-point voting | Replaced by deterministic `scope`-bucket sizing (`S`/`M`/`L`/`XL`) mapped to the canonical Estimation Scale below |
| Recurring backlog grooming | `/cadence-triage` + weekly Prioritization Commit handle intake; on-demand Spec Critique handles complex M/L/XL designs |
| Sprint kickoff meetings | Subsumed into the 30-minute weekly Prioritization Commit |

---

## Metrics That Replace Rituals

Instead of story-point velocity and burndown charts, CADENCE tracks six operational flow and quality metrics derived directly from repository artifacts:

| Metric | Question It Answers | Authoritative Source |
|---|---|---|
| Gate throughput | How rapidly are proposals clearing human gates? | `metadata.yaml` timestamps (`created` → `spec-approved` → `merged`) |
| Gate aging | Which tickets or MRs are stalled waiting on human judgment? | Elapsed time since last `status` transition (alerting at `>48h` for Gate 1 and `>72h` for Gate 2/3) |
| Gate 1 override & rejection rate | Are explorer options and specifications hitting the mark? | Gate 1 outcomes and rejections recorded in `decisions.md` |
| Gate 2 rework rate | Are agent implementations meeting the quality bar on the first pass? | Fraction of MRs requiring post-review fix commits during `/cadence-review` |
| Scope complexity distribution | What is the incoming review load across the team? | `scope` (`S`/`M`/`L`/`XL`) and `tier` distribution across active `metadata.yaml` files |
| End-to-end cycle time | How long does it take to go from problem statement to merged solution? | `metadata.yaml`: `created` → `merged` |

**Deterministic estimation.** Size tickets by specification complexity (the `scope` field in `metadata.yaml`) and derive `estimated_effort` directly from the prescriptive table below. The cycle-time band measures **end-to-end wall-clock elapsed time** (problem → merged, dominated by human gate turnaround since agent implementation is fast), **never manual coding hours** — never estimate from line counts or file counts.

### Estimation Scale (prescriptive — agents record the right-hand value)

| `scope` | Spec complexity | Gate-to-gate cycle-time band | `estimated_effort` to record |
|---|---|---|---|
| **S** | trivial / one-file / config | 1/2 day | `2h` |
| **M** | single concern, bounded blast radius | 1 day | `4h` |
| **L** | multi-file or cross-cutting within one subsystem | 2 days | `8h` |
| **XL** | large blast radius or multi-subsystem | 1 week | `2d` |

- The **M → `4h`** row is the canonical anchor ("an M specification takes ~4 hours of active effort across authoring and gate reviews"); the **S / L / XL** rows scale proportionally across all four legal `scope` values (`S`, `M`, `L`, `XL`).
- **The cycle-time band and the recorded `estimated_effort` measure two distinct quantities**, which is why their numbers differ: the *band* reflects elapsed wall-clock calendar time (including queue time waiting on human gates), whereas the *representative value* records active working + review effort at a uniform ratio of roughly **4 recorded hours per elapsed day** — S (`1/2 day` → `2h`), M (`1 day` → `4h`), L (`2 days` → `8h`), XL (`1 week` → `2d`). Always read each row horizontally.
- **Agents record the representative value in the right-hand column** (`cadence-triage-agent` sets the initial value; `cadence-spec-author` refines it if the full specification changes the scope), documenting any in-band deviation in `decisions.md`. When projected to an external tracker (such as Jira Server via `/cadence-sync-jira`), any range projects its **upper bound** to the tracker's Original/Remaining Estimate fields.
- **Epic / decomposition parents** (`type: epic` tickets with a `decomposed_into:` child track) are **never** sized from a single `scope` bucket; their `estimated_effort` is computed as the **critical path** across the child track (the sum along the longest serialized dependency chain, taking the maximum across parallel siblings).
- **`actual_effort` is accumulated per workflow stage**, never estimated up front and never derived post-merge from git commit timestamps: as each of the six workflow stages (`triage`, `spec`, `implementation`, `code-review`, `maintainer`, `archive`) completes, it appends its observed working time (multiplied by the per-stage review multiplier and rounded **up** to the next 15-minute increment — or `0m` when the product is zero) to `stage_effort` and updates the running `actual_effort` sum. See `CADENCE_ORG.md` § "Actual Effort Accumulation".

---

## Cadence Summary

| Ritual | Frequency | Duration | Format | Key Output |
|---|---|---|---|---|
| Prioritization Commit | Weekly | 30 min | Sync | Ranked intake list; human gate commitments |
| Gate Review | Continuous | Async (15 min sync optional) | Async-first | Unblocked human gates |
| Spec Critique | On-demand | 20–30 min | Sync | Pre-Gate-1 architectural feedback on M/L/XL specs |
| Merge Showcase | Weekly/biweekly | 20–30 min | Sync | Shared system mental model |
| Process Retro | Biweekly | 45 min | Sync | Agent/pillar/governance tuning MRs |
| Cross-Project Surface Check | Weekly | Async (sync on contention) | Async-first | Early surface-contract conflict detection |
| Agent Calibration | Monthly | 60 min | Sync | Role prompt, pillar, and offload calibration MRs |
| Incident Review | Per incident | As needed | Sync | Blameless postmortem + `PROD-NNN` insight + systemic guardrail |

---

## Getting Started

Teams transitioning to CADENCE rituals should roll them out in five steps:

1. Launch **Prioritization Commit** and async **Gate Review** first — they immediately replace sprint planning and daily standups
2. Enable **gate-aging visibility** (`>48h` for Gate 1 Spec Review, `>72h` for Gate 2/3 MR Review) before retiring daily standups
3. Hold your first **Process Retro** after two weeks to calibrate gate SLAs and review bandwidth
4. Introduce **Merge Showcase** once multiple bounded contexts or repositories are shipping through CADENCE
5. Run your first **Agent Calibration** session after one month of production operation, using accumulated `decisions.md`, `stage_effort`, and `production-insights.md` data
