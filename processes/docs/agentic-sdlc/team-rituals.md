# Team Rituals for the Agentic SDLC

Traditional agile ceremonies assume humans do the implementation work and need coordination to deliver incrementally. In the agentic SDLC, AI agents handle triage, specification, implementation, and archival. The bottleneck shifts from "how do we coordinate coding work?" to "how do we move work through human gates efficiently?"

This guide redefines team rituals for that reality.

---

## The Bottleneck Shift

In a traditional sprint, the scarce resource is developer time. Rituals exist to allocate that time wisely (planning), surface blockers quickly (standup), and improve the allocation over time (retro).

In the agentic model, the scarce resources are:

- **Human judgment** — spec approval, code review, maintainer acceptance, deployment validation
- **Shared context** — understanding what changed across projects and why
- **System quality** — ensuring agents improve rather than drift

Rituals should serve these three needs. Everything else is ceremony without purpose.

---

## Rituals to Adopt

### Prioritization Commit

| | |
|---|---|
| **Replaces** | Sprint planning, sprint kickoff |
| **Cadence** | Weekly (30 min) |
| **Attendees** | Product stewards, domain architects, contributors |
| **Output** | Ordered intake list for the week; individual gate commitments |

Each person declares what enters the pipeline ("approve specs X and Y for implementation") and what they will unblock ("review MRs A and B"). This is the intake valve — without it, AI agents generate unbounded work that overwhelms reviewers.

The meeting answers two questions:
1. What is worth specifying next? (Prioritization)
2. Who commits to clearing which gates this week? (Capacity)

No implementation backlog is discussed. The triage agent and spec agent produce work; humans decide what proceeds.

### Gate Review

| | |
|---|---|
| **Replaces** | Daily standup |
| **Cadence** | Async-first; optional 15 min sync 2-3x/week |
| **Attendees** | Anyone with pending gate responsibilities |
| **Output** | Unblocked work items |

Each person posts async: "What is waiting for my judgment?" A brief sync exists only to resolve cross-project dependencies or escalate items that have aged past the SLA.

The repository already tracks state via `metadata.yaml` timestamps. A dashboard showing "specs awaiting review > 48h" or "MRs awaiting maintainer acceptance > 72h" replaces verbal status updates.

Rules:
- No "what did you do yesterday?" — the commit log answers that
- No implementation status — agents handle that
- Only discuss items blocked on human decisions

### Spec Critique

| | |
|---|---|
| **Replaces** | Backlog refinement, story decomposition |
| **Cadence** | On-demand (triggered when M or L spec is ready for review) |
| **Attendees** | 2-3 people with relevant domain knowledge |
| **Output** | Feedback incorporated before formal Gate 3 approval |

The spec agent produces the draft. For complex work (M/L complexity), convene a brief critique before formal approval:

- Did the agent miss a failure mode?
- Is the Zachman grounding correct for this domain?
- Does the SCOUT decomposition cover the real edge cases?
- Are the compatibility implications fully assessed?

This keeps Gate 3 approval fast because objections surface informally before the formal gate.

### Merge Showcase

| | |
|---|---|
| **Replaces** | Sprint demo, sprint review |
| **Cadence** | Weekly or biweekly (20-30 min) |
| **Attendees** | All contributors across projects |
| **Output** | Shared context; known downstream impacts to watch |

The archivist updates the CHANGELOG and syncs downstream systems automatically. But the "why" and "so what" still need a human voice.

For each notable merge since last showcase:
- What problem did it solve?
- What surprised us during review?
- What downstream impact should others watch for?

This builds shared context across projects without requiring everyone to review every MR.

### Process Retro

| | |
|---|---|
| **Replaces** | Sprint retrospective |
| **Cadence** | Biweekly (45 min) |
| **Attendees** | All team members + AI workflow steward |
| **Output** | System tuning PRs; one human process improvement max |

The retro shifts from "how did the team perform?" to "how is the system performing?"

Questions to drive discussion:
- Where are specs getting stuck at gates?
- Are agent outputs requiring excessive rework at review?
- Are we approving specs that turn out underspecified at implementation?
- Are we rejecting work that should have been caught earlier in the pipeline?

Review the decision logs (`decisions.md`) from recent work — were the tradeoffs right in hindsight?

The output is not action items for people. It is tuning the system: adjusting agent prompts, updating CLAUDE.md guidance, refining quality facets, changing gate criteria, or updating this rituals guide. Limit to one human behavior change per retro — system changes scale better.

### Cross-Project Surface Check

| | |
|---|---|
| **Replaces** | Dependency sync, cross-team coordination meetings |
| **Cadence** | Weekly (async-first; sync only on contention) |
| **Attendees** | Anyone modifying or consuming shared surfaces |
| **Output** | Early conflict detection; updated surface registry entries |

Inner-source means multiple contributors touch shared surfaces. A weekly async post:
- "I am about to change X in the surface registry"
- "My spec proposes a new public contract"
- "I plan to deprecate Y — consumers should be aware"

Anyone with a consuming service replies with concerns. Escalate to sync only if there is contention. The surface registry and deprecation policy are the governing artifacts — this ritual ensures people read them before they conflict.

### Agent Calibration

| | |
|---|---|
| **Replaces** | Nothing (new ritual unique to this model) |
| **Cadence** | Monthly (60 min) |
| **Attendees** | AI workflow steward, maintainers, domain architects |
| **Output** | PRs to agent configuration and quality thresholds |

Review agent performance holistically. Pull metrics:
- Spec rejection rate at Gate 3
- Code review rework frequency (how often MRs need revision after agent implementation)
- Implementer test failure patterns
- Gate throughput trends

Are agents improving or drifting? Update agent instructions, quality thresholds, facet weights, or CLAUDE.md guidance. This is the AI Workflow Steward's primary ceremony.

### Incident Review

| | |
|---|---|
| **Replaces** | Nothing (existing practice, adapted) |
| **Cadence** | Per incident |
| **Attendees** | Responders, maintainers, affected stakeholders |
| **Output** | Blameless postmortem; systemic fixes |

Standard blameless postmortem practices apply unchanged. The one addition: if the root cause traces to an agent-authored migration, implementation, or spec gap, add a systemic fix — update the agent's guardrails so the class of error cannot recur. Feed systemic fixes into the next Agent Calibration session.

---

## Rituals to Drop

| Traditional Ritual | Why It No Longer Serves |
|---|---|
| Daily standup | Gate Review (async) provides the same unblocking function without synchronous overhead across unrelated projects |
| Sprint commitment / velocity tracking | Meaningless when AI implementation time is near-zero; measure gate throughput instead |
| Story point estimation | Replace with spec complexity sizing (S/M/L) and historical actuals; see Metrics below |
| Recurring backlog refinement | Triage agent + Prioritization Commit covers intake; Spec Critique handles complex decomposition |
| Sprint kickoff ceremony | Prioritization Commit subsumes this with less overhead |

---

## Metrics That Replace Rituals

Traditional agile uses velocity and burndown to answer "are we on track?" In the agentic model, these metrics answer the equivalent questions:

| Metric | What It Answers | Source |
|---|---|---|
| Gate throughput | How fast is work moving through human gates? | `metadata.yaml` timestamps (created → spec_approved → merged) |
| Gate aging | What is stuck? | Time since last state transition, alerting at 48h (spec review) and 72h (code review) |
| Spec rejection rate | Are we specifying well? | Gate 3 rejections / total specs submitted |
| Rework rate | Are agent implementations meeting quality bar? | MRs requiring revision after initial review |
| Spec complexity distribution | What is the review burden? | S/M/L sizing assigned at triage |
| End-to-end cycle time | How long from problem to production? | `metadata.yaml`: `created_at` → `merged_at` |

**Estimation replacement.** Size specs by complexity (the `scope` field in `metadata.yaml`) and let the
gate-to-gate cycle-time bands below drive the `estimated_effort` value. These are **wall-clock cycle
times** (problem → merged, dominated by human gate reviews since AI implementation time is near-zero), **not
human coding effort** — do not estimate from line/file counts. Track historical actuals and tighten the
bands over time; no planning poker.

### Estimation Scale (prescriptive — agents record the right-hand value)

| `scope` | Spec complexity | Gate-to-gate cycle-time band | `estimated_effort` to record |
|---|---|---|---|
| **S** | trivial / one-file / config | 1/2 day | `2h` |
| **M** | single concern, bounded blast radius | 1 day | `4h` |
| **L** | multi-file or cross-cutting within one subsystem | 2 days | `8h` |
| **XL** | large blast radius or multi-subsystem | 1 week | `2d` |

- The **M → `4h`** cell is the documented anchor ("an M spec takes ~4 hours end-to-end including reviews");
  the **S / L / XL** representatives extend it on the same gate-to-gate basis, and **XL** is a deliberate
  addition to the original S/M/L scale (the `scope` field carries S/M/L/XL, so the scale now covers all
  four).
- **The band and the representative value measure different things**, which is why they are not numerically
  equal. The *band* is wall-clock cycle time (problem → merged, dominated by waiting on human gates); the
  *representative value* is the working time to record. The scale holds them in a consistent ratio of
  roughly **4 recorded hours per elapsed day** — S (½ day → `2h`), M (1 day → `4h`), L (2 days → `8h`),
  XL (1 week → `2d`). Read a row across, not down.
- **Record the band's representative value** (right-hand column) unless a spec has a specific reason to sit
  elsewhere in its band — note any such in-band deviation in `decisions.md`. The value is a human-readable
  duration; a range projects its **upper bound** to the bound tracker's estimate field (for the Jira-Server
  binding, per `jira-write-issue.sh`'s Original/Remaining Estimate co-send, contracted in the
  `/claire-sync-jira` skill's `jira-server-scripts.md` sidecar).
- **Epic / rollup parents** (a ticket decomposed into a child track) are **not** sized by their own `scope`
  bucket. Estimate them as the **critical path** of the child track — the serialized sum along the longest
  dependency chain, taking the longest of any parallel siblings.
- **`actual_effort`** is **accumulated per stage**, never estimated and never computed post-merge from git
  history: each of the six workflow stages appends its agent-observed working time (multiplied by a
  per-stage review multiplier to cover operator review at the stage's start and end, then rounded **up** to
  the next 15-minute increment — unless the computed time is exactly zero, which records `0m`) to a
  `stage_effort` log and to the running `actual_effort` total. See
  `CLAIRE_ORG.md` "Actual Effort Accumulation".

---

## Cadence Summary

| Ritual | Frequency | Duration | Format | Key Output |
|---|---|---|---|---|
| Prioritization Commit | Weekly | 30 min | Sync | Ordered intake list; gate commitments |
| Gate Review | Continuous | Async (15 min sync optional) | Async-first | Unblocked items |
| Spec Critique | On-demand | 20-30 min | Sync | Pre-approval feedback |
| Merge Showcase | Weekly/biweekly | 20-30 min | Sync | Shared context |
| Process Retro | Biweekly | 45 min | Sync | System tuning PRs |
| Cross-Project Surface Check | Weekly | Async (sync on contention) | Async-first | Conflict prevention |
| Agent Calibration | Monthly | 60 min | Sync | Agent config PRs |
| Incident Review | Per incident | As needed | Sync | Postmortem + systemic fix |

---

## Getting Started

Teams adopting these rituals should:

1. Start with Prioritization Commit and Gate Review — these replace the highest-frequency traditional ceremonies
2. Set up gate aging alerts (48h spec review, 72h code review) before dropping standup
3. Run one Process Retro to calibrate — the first retro often reveals that gate SLAs need adjustment
4. Add Merge Showcase once multiple projects are shipping through the pipeline
5. Schedule Agent Calibration after the first month of operation, once enough data exists to evaluate trends
