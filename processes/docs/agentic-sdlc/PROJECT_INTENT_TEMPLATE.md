# Project Intent

> **This is a template.** Copy it to the root of your repository as `PROJECT_INTENT.md` on first CLAIRE adoption, then fill in each section with your project's specifics. Replace this preamble with a one-line repo description when the document is ready.
>
> Sections marked **(Required)** must be completed before the maintainer agent can evaluate MRs against intent. Sections marked **(Recommended)** strengthen the document but are not blocking.

## How to use this document

`PROJECT_INTENT.md` is the standing answer to the question every intent issue asks: *does this work belong here?* It captures the project's mission, scope, quality stance, architectural commitments, and contribution posture so that contributors can self-select and the maintainer can decide consistently.

It is a living document. Major changes follow the **Amendment Process** (Section 10). Minor edits — clarifying wording, fixing links, expanding examples — can be made by any maintainer at any time.

The document grounds three audiences:

- **Contributors** read it before filing an intent issue to decide whether their idea fits.
- **The maintainer agent** reads it to evaluate MRs for goal alignment, scope, and architectural fit.
- **The owning team** reads it when deciding what work to take on, so the project does not drift from its purpose.

If a section is empty, fill it in or remove it. Do not leave placeholders in the published version.

---

## 1. Mission **(Required)**

*One paragraph. What does this project exist to do, and who benefits when it does it well? This is the "why," not a feature list. A reader unfamiliar with the project should be able to read this section and explain the project's purpose to someone else.*

> **Example.** This service ingests claims data from upstream payer systems, normalizes it into the canonical claims schema, and exposes it to downstream reporting and analytics consumers. The team it serves is the analytics platform; the value it provides is one consistent claims source so that downstream consumers do not each have to handle payer-specific quirks.

{Replace with your project's mission.}

---

## 2. Scope **(Required)**

### In Scope

*The kinds of work that belong in this repo. Be specific — "data normalization for claims" is more useful than "claims-related work."*

- 
- 

### Out of Scope

*Work that looks related but does not belong here. List the adjacent project that should own it instead, when known.*

- {Topic} — owned by {project / team}, not us.
- 

### Adjacent Projects

*Neighboring projects whose intent overlaps. Helps contributors and the maintainer agent redirect work that has been filed in the wrong place.*

| Project | Repo | Relationship |
|---|---|---|
| | | |

---

## 3. Non-Goals **(Required)**

*Explicit things this project will not do, each with a reason. The maintainer agent uses this list to reject scope-creep MRs by citation. A non-goal is not "we have not done this yet" — it is "we have decided not to do this." If a non-goal becomes a goal, that is an amendment (Section 10).*

| Non-Goal | Reason |
|---|---|
| | |

> **Example.** *We do not transform claims data for clinical use cases.* Reason: clinical context requires PHI handling guarantees that exceed this project's compliance scope; clinical transformations are owned by the patient-data domain.

---

## 4. Quality Stance **(Required)**

*What this project optimizes for, ranked. When two qualities conflict, the higher-ranked one wins by default. The maintainer agent uses this ranking to evaluate architectural choices.*

### Ranked Priorities

1. {e.g., Auditability — every state change must be traceable}
2. {e.g., Simplicity — fewer moving parts beats more elegant abstractions}
3. {e.g., Throughput — sustained load matters more than peak latency}
4. ...

### Tradeoffs Accepted

*Specific tradeoffs the project has chosen. Naming them prevents repeated debate.*

- {e.g., We accept higher write latency in exchange for synchronous audit log persistence.}
- 

---

## 5. Public Surfaces **(Required if the project exposes any external surfaces)**

*What this project exposes to other systems. Cross-references the surface registry at `docs/policies/surface-registry.md` if one exists -- and, if this repo adopted CLAIRE at or after v4.0.0, the core-owned `docs/policies/claire-surfaces.md` alongside it, which holds the framework's own surfaces and is not yours to edit. The maintainer agent uses this section to scope backwards-compatibility analysis.*

| Surface | Type | Stability | Consumers |
|---|---|---|---|
| | API / event / schema / CLI / library | experimental / stable / deprecated | |

If this project exposes no public surfaces (purely internal), state that explicitly: *"No public surfaces. All consumption is internal to this team."*

---

## 6. Architecture Invariants **(Recommended)**

*Structural decisions that are not up for debate without amending intent. The maintainer agent treats violations of these invariants as blocking issues. Keep this list short — five to ten items. If you have more than that, you may be conflating invariants with conventions.*

- {e.g., All writes go through the audit pipeline. No direct-to-storage writes.}
- {e.g., No synchronous calls between bounded contexts; cross-context communication is event-driven.}
- 

---

## 7. Stakeholders & Ownership **(Required)**

### Owning Team

*The team responsible for this project. Link to the team page or directory entry; do not list individual names here — they rot.*

- Team: 
- Roster: {link}

### Maintainers

*Current maintainers. Link to a dynamic source (group membership, CODEOWNERS, etc.) rather than hardcoding names.*

- {link}

### Major Consumers

*Other teams or systems that depend on this project. Helps the maintainer agent judge the blast radius of breaking changes.*

- 

---

## 8. Contribution Posture **(Required)**

### Are contributions from outside the owning team welcome?

> {One of: "Yes, all kinds." | "Yes, for the following kinds: …" | "Limited — see below." | "Not currently — file an intent issue to discuss."}

This setting determines how the maintainer agent treats MRs from outside the owning team. Setting it to "Not currently" is a valid choice — it tells external contributors to start with conversation, not code. Reopening contributions later is an edit, not an amendment.

### Prerequisites

- All work begins with an intent issue. No exceptions, including for the owning team.
- {Project-specific prerequisites, if any.}

### Where to ask questions

- {Slack channel, Teams channel, mailing list — must be monitored by at least one maintainer during business hours}

### Review SLAs

The defaults below come from `docs/guides/contributor_experience_guide.md`. Override them here based on your maintainers' actual capacity. Honest SLAs build trust; aspirational SLAs erode it.

| Track | First response | Actionable feedback | Target merge (if approved) |
|---|---|---|---|
| Lightweight | {2 business days} | {5 business days} | {7 business days} |
| Standard | {5 business days} | {10 business days} | Depends on scope |

### Lightweight track LOC threshold

{Default: 50 lines of production code, excluding tests.}

### Ladder thresholds

| Level | Threshold |
|---|---|
| Recurring Contributor | {Default: 3 merged MRs in the trailing 12 months} |
| Trusted Committer | Nominated by a maintainer, confirmed by governance |
| Maintainer | Per the project's governance process |

### Reference

See `docs/guides/contributor_experience_guide.md` for the full contributor workflow, intent issue template, and review etiquette.

---

## 9. Decision Philosophy **(Recommended)**

*Big "why we built it this way" statements and approaches that have already been considered and rejected. Helps contributors avoid relitigating settled decisions. For specific decisions, link to the decision log rather than restating them here.*

### Settled

- {e.g., We chose Postgres over a document store. Reason: claims data is highly relational; the join cost in a document store outweighs the schema flexibility.}
- 

### Considered and rejected

- {e.g., A unified ingest pipeline for both claims and clinical data. Rejected because the compliance scopes diverge.}
- 

See `specs/*/decisions.md` for individual decision rationale.

---

## 10. Amendment Process **(Required)**

### What requires an amendment

A change to this document is an amendment if it modifies any of:

- Mission
- Scope (in or out)
- Non-Goals
- Quality Stance ranking
- Architecture Invariants
- Contribution Posture, when narrowing it (broadening it is an edit, not an amendment)

Other edits — clarifying wording, fixing links, expanding examples, adjusting SLAs to match capacity — can be made by any maintainer at any time without amendment.

### How to amend

1. File an intent issue tagged `intent-amendment` describing the proposed change and its rationale.
2. Open an MR that updates this document and references the intent issue.
3. The MR follows the Standard track (or higher tier) regardless of size: changes to project intent are never lightweight.
4. Approval requires the maintainer's sign-off, recorded in the project's decision log.

### Review cadence

This document is reviewed by the owning team at least once every {6 / 12} months, or whenever any of the following triggers fire:

- A major external dependency or consumer changes.
- The team faces sustained pressure to take on out-of-scope work.
- A significant non-goal is being challenged.
- The team's capacity or composition changes materially.

---

## Document metadata

| Field | Value |
|---|---|
| First adopted | {YYYY-MM-DD} |
| Last amended | {YYYY-MM-DD} |
| Next scheduled review | {YYYY-MM-DD} |
| Maintainer of record | {link} |
