# Project Intent

> **This is a template.** Copy it to the root of your repository as `PROJECT_INTENT.md` upon initial CADENCE adoption, then populate each section with your project's charter specifics. Replace this callout with a one-sentence repository summary once the document is complete.
>
> Sections marked **(Required)** must be populated before the `cadence-maintainer` agent can evaluate MRs against repository intent. Sections marked **(Recommended)** sharpen architectural governance but are non-blocking.

## How to use this document

`PROJECT_INTENT.md` provides the standing answer to the question every incoming proposal asks: *does this work belong in this repository?* It records the project's mission, scope boundaries, quality priorities, architectural invariants, and contribution posture so contributors can self-orient and the maintainer can evaluate changes consistently.

It is a living charter. Structural changes follow the **Amendment Process** (Section 10). Editorial updates — clarifying phrasing, repairing links, expanding examples — may be committed by any maintainer at any time.

The charter serves three audiences:

- **Contributors** consult it before filing an issue to verify that their proposal fits the repository's mission.
- **The `cadence-maintainer` agent** reads it during Gate 3 to assess MRs for charter alignment, scope adherence, and architectural fit.
- **The owning team** uses it when prioritizing intake so the codebase does not drift from its core purpose.

Fill in or remove any empty optional sections; never leave un-substituted placeholders in the committed root `PROJECT_INTENT.md`.

---

## 1. Mission **(Required)**

*One paragraph. What does this project exist to accomplish, and who benefits when it succeeds? State the core "why," not a feature catalog. Any engineer unfamiliar with the codebase should be able to read this paragraph and explain the project's purpose to a colleague.*

> **Example.** This service ingests claims records from upstream payer systems, normalizes them into the canonical claims schema, and publishes them to downstream reporting and analytics consumers. It serves the analytics platform team by providing a single consistent claims feed so downstream consumers never have to implement payer-specific parsing rules.

{Replace with your project's mission.}

---

## 2. Scope **(Required)**

### In Scope

*The specific classes of work that belong in this repository. Be concrete — "claims data normalization and schema validation" is actionable; "claims work" is too vague.*

- 
- 

### Out of Scope

*Work that appears adjacent but belongs elsewhere. Name the neighboring repository or team that owns it whenever known.*

- {Topic} — owned by {project / team}, not this repository.
- 

### Adjacent Projects

*Neighboring repositories whose domain boundaries touch this one. Helps contributors and `cadence-maintainer` route misfiled proposals to the right home.*

| Project | Repo | Relationship |
|---|---|---|
| | | |

---

## 3. Non-Goals **(Required)**

*Capabilities this project has explicitly decided NOT to build, each paired with its rationale. The `cadence-maintainer` agent cites this table when rejecting scope-creep MRs. A non-goal is not "work we haven't scheduled yet" — it is "work we have deliberately ruled out." Turning a non-goal into an active goal requires a formal charter amendment (Section 10).*

| Non-Goal | Reason |
|---|---|
| | |

> **Example.** *We do not transform claims records for clinical care workflows.* Reason: clinical workflows carry PHI compliance obligations outside this service's regulatory boundary; clinical data transformations belong to the patient-data domain.

---

## 4. Quality Stance **(Required)**

*The engineering qualities this project optimizes for, in strict priority order. Whenever two qualities pull in opposite directions, the higher-ranked quality prevails by default. `cadence-maintainer` uses this ranking to judge architectural trade-offs.*

### Ranked Priorities

1. {e.g., Data & Audit Fidelity — every state mutation must be traceable}
2. {e.g., Structural Simplicity — fewer moving parts beat clever abstractions}
3. {e.g., Sustained Throughput — predictable batch throughput matters more than single-request peak latency}
4. ...

### Tradeoffs Accepted

*Explicit costs the project willingly accepts to honor its priority ranking. Recording them here prevents re-litigating settled debates during review.*

- {e.g., We accept higher write latency in exchange for synchronous transactional audit log persistence.}
- 

---

## 5. Public Surfaces **(Required if the project exposes any external surfaces)**

*Contracts this repository exposes to external callers or downstream systems. Cross-references the adopter-owned surface registry at `docs/policies/surface-registry.md` -- and, for repositories adopting CADENCE at or after v4.0.0, the core-owned `docs/policies/cadence-surfaces.md` alongside it, which tracks framework-owned surfaces and is maintained by `/cadence-upgrade`. `cadence-maintainer` uses this section to scope surface-compatibility checks.*

| Surface | Type | Stability | Consumers |
|---|---|---|---|
| | API / event / schema / CLI / library | experimental / stable / deprecated | |

When a repository exposes zero external surfaces (purely internal), state that explicitly: *"No public surfaces. All consumption is internal to the owning team."*

---

## 6. Architecture Invariants **(Recommended)**

*Foundational structural rules that cannot be violated without formally amending this charter. `cadence-maintainer` treats any violation of these invariants as a `[BLOCKING]` defect. Keep this list concise — five to ten crisp rules. A longer list usually mixes true invariants with stylistic conventions.*

- {e.g., Every state mutation passes through the transactional audit pipeline; direct-to-storage writes are forbidden.}
- {e.g., Bounded contexts never invoke each other synchronously; all cross-context coordination is event-driven.}
- 

---

## 7. Stakeholders & Ownership **(Required)**

### Owning Team

*The team accountable for this repository. Link to a team directory or roster page rather than hardcoding individual names that quickly go stale.*

- Team: 
- Roster: {link}

### Maintainers

*Active maintainers authorized to approve Gate 3 reviews. Link to a dynamic source of truth (`CODEOWNERS`, group handle, etc.) rather than static names.*

- {link}

### Major Consumers

*Downstream teams or services that depend on this repository. Helps `cadence-maintainer` assess the blast radius of contract changes.*

- 

---

## 8. Contribution Posture **(Required)**

### Are contributions from outside the owning team welcome?

> {One of: "Yes, all kinds." | "Yes, for the following kinds: …" | "Limited — see below." | "Not currently — file an intent issue to discuss."}

This declaration governs how `cadence-maintainer` evaluates MRs from external contributors. Selecting "Not currently" is completely valid — it directs external contributors to start a discussion before writing code. Broadening contribution posture later is a normal edit; narrowing it requires an amendment.

### Prerequisites

- Every change begins with a triaged ticket (`specs/{id}/`). No exceptions, including for the owning team.
- {Project-specific prerequisites, including the sanctioned test runner command.}

### Where to ask questions

- {Slack channel, Teams channel, or mailing list — monitored by at least one maintainer during business hours}

### Review SLAs

The default targets below come from `docs/guides/contributor_experience_guide.md`. Adjust them to match your maintainers' real review bandwidth. Realistic SLAs build contributor trust; aspirational SLAs that are routinely missed erode it.

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

See `docs/guides/contributor_experience_guide.md` for the complete contributor workflow, intent issue template, and review etiquette.

---

## 9. Decision Philosophy **(Recommended)**

*High-level architectural principles and previously rejected approaches. Recording these prevents contributors and agents from re-proposing designs that were already ruled out. Link to specific ADRs or `decisions.md` logs for detailed history.*

### Settled

- {e.g., We use PostgreSQL rather than a document store. Reason: claims records are highly relational, and cross-entity join integrity outweighs schema-less flexibility.}
- 

### Considered and rejected

- {e.g., A single shared ingestion pipeline for both claims and clinical feeds. Rejected because their regulatory and audit boundaries diverge.}
- 

See `specs/*/decisions.md` and `archive/*/decisions.md` for per-ticket decision rationale.

---

## 10. Amendment Process **(Required)**

### What requires an amendment

Modifying any of the following sections constitutes a formal charter amendment:

- Mission
- Scope (in or out)
- Non-Goals
- Quality Stance priority ranking
- Architecture Invariants
- Contribution Posture, when narrowing access (broadening access is a standard edit, not an amendment)

Routine maintenance edits — clarifying wording, updating links, adding examples, or calibrating review SLAs to match team capacity — may be made by any maintainer without a formal amendment.

### How to amend

1. File a ticket tagged `intent-amendment` stating the proposed charter change and its business or architectural rationale.
2. Open an MR updating `PROJECT_INTENT.md` and referencing the ticket.
3. The MR follows the Standard track (Medium or High tier) regardless of line count: changes to `PROJECT_INTENT.md` are never Trivial or Low tier.
4. Ratification requires maintainer sign-off recorded in the ticket's `decisions.md`.

### Review cadence

The owning team reviews `PROJECT_INTENT.md` at least once every {6 / 12} months, or immediately whenever any of the following triggers occur:

- A major upstream dependency or downstream consumer changes.
- The team experiences recurring pressure to accept out-of-scope requests.
- A listed non-goal is actively challenged by stakeholders.
- The owning team's capacity or charter changes significantly.

---

## Document metadata

| Field | Value |
|---|---|
| First adopted | {YYYY-MM-DD} |
| Last amended | {YYYY-MM-DD} |
| Next scheduled review | {YYYY-MM-DD} |
| Maintainer of record | {link} |
