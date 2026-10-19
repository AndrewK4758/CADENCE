# Inner-Source SDLC Charter

## Purpose

This charter establishes a common enterprise-wide model for building, changing, reviewing, releasing, and maintaining software using inner-source practices inspired by mature open source projects. It creates a ground-floor governance framework that prioritizes transparency, maintainability, compatibility, and shared ownership while allowing each domain, product area, and team to add stricter controls that fit its risk profile and operating model.

The charter is designed to solve a common modern delivery gap: product artifacts and code generation can now be accelerated by AI, but many organizations still lack a disciplined, transparent middle layer for backlog shaping, prioritization, acceptance, and compatibility governance. The SCOUT methodology (State, Constraints, Outputs, Updates, Triggers) provides the structured specification and implementation discipline that operationalizes this charter, ensuring every change is systematically decomposed, tested, and governed before reaching production.

## Scope

This charter applies to all software delivery domains that opt into the Inner-Source SDLC model, including customer-facing applications, internal platforms, APIs, shared libraries, data services, integration layers, and line-of-business systems. It governs the lifecycle of feature requests, defects, design proposals, implementation, review, release, and post-release stewardship.

Each adopting domain may define additional policies, templates, service-level objectives, and approval thresholds, but no local policy may weaken the minimum controls established in this charter for traceability, review, compatibility, and human accountability.

## Principles

### Transparent by Default

Work items, decision records, design discussions, acceptance criteria, and non-sensitive implementation plans should be visible to the relevant enterprise community by default. Mature open source projects rely on written, reviewable decisions rather than tribal knowledge, and inner-source practices adapt that model inside the enterprise.

### Human-Gated, Machine-Assisted

AI systems may draft, summarize, classify, decompose, and analyze work, but accountable humans retain authority for prioritization, approval, merge, release, and exception handling. This preserves the strengths of automation without outsourcing judgment, risk ownership, or stewardship.

### Compatibility as a Product Obligation

Backward compatibility for supported interfaces, schemas, events, contracts, and operational behaviors must be treated as an explicit product commitment rather than an implied engineering preference. Mature open source communities maintain trust by preserving stable contracts across upstream and downstream dependencies, and enterprise domains should do the same.

### Shared Ownership, Clear Authority

Any contributor may propose improvements, report defects, or draft changes, but named maintainers and domain stewards hold final responsibility for acceptance decisions within their scope. Egalitarian participation works when decision rights are documented rather than assumed.

### Repository-Centered Governance

The versioned repository is the system of record for specifications, decisions, test plans, compatibility contracts, and release history. External systems such as project trackers, wikis, and communication tools receive synchronized projections but are not authoritative. Git provides immutability, cryptographic auditability, attribution, and compliance evidence that no ticket-tracking or wiki tool can match. Information flows outward from the repository to downstream systems, never the reverse.

### Specification Before Implementation

No implementation begins without an approved specification that includes acceptance criteria, systematic edge-case analysis, and compatibility impact assessment (at Low tier, where no `spec.md` is produced, a triaged `problem.md` with its acceptance-criteria checklist is the approved intent record instead, per `docs/policies/change-tiers.md`). The specification is the contract between intent and delivery. This discipline is what enables AI-assisted implementation at scale: agents can implement reliably from a complete spec, but not from an ambiguous ticket or informal conversation.

### Minimum Process, Maximum Clarity

The goal of this charter is not bureaucratic volume. The goal is to make change easy to propose, easy to understand, and safe to approve by standardizing the smallest useful set of artifacts, gates, and records.

## Operating Model

### Required Artifacts

Every participating domain must maintain the following artifacts in its repository as the system of record:

- **Problem statement** (`problem.md`) — for each work item: problem framing, intended user, expected value, constraints, initial acceptance criteria, and affected dependencies.
- **Specification** (`spec.md`) — for changes above the domain's impact threshold: structured design grounded in the Zachman framework (What, How, Where, Who, When, Why across scope, business, system, and technology layers), SCOUT behavioral decomposition, quality facet evaluation, and compatibility impact analysis.
- **Test plan** (`test-plan.md`) — Gherkin BDD scenarios derived mechanically from the SCOUT decomposition, ordered for incremental TDD implementation.
- **Decision log** (`decisions.md`) — immutable, append-only record of accepted, rejected, superseded, or deferred proposals with rationale.
- **Machine-readable metadata** (`metadata.yaml`) — classification, priority, scope, status, timestamps, and identifiers for automation and reporting.
- **Project intent** (`PROJECT_INTENT.md`) — the project's standing answer to "does this work belong here?": mission, scope, non-goals, quality stance, architecture invariants, and contribution posture. Authored on first CLAIRE adoption; amended via documented process. Grounds the maintainer's accept/reject reasoning by citation rather than personal taste.
- **Surface registry** — a single inventory of all public interfaces (APIs, events, schemas, contracts) with stability levels, guarantee periods, consumers, and sunset dates.
- **Deprecation policy** — minimum deprecation periods by surface type, runtime signaling requirements, migration guide standards, and emergency procedures.
- **Contribution standards** — coding, testing, documentation, review, and release expectations.

Standard templates for these artifacts are provided and should be adopted or adapted by each domain. External systems (Jira, Confluence, wikis) receive one-directional synchronized projections from these repository artifacts but are never authoritative.

### Lifecycle Phases

The standard Inner-Source SDLC lifecycle consists of seven phases, three automated and four requiring human judgment:

| Phase | Mode | Description | Key Output |
|---|---|---|---|
| 1. Triage | AI-assisted | Classify incoming issue, check duplicates, assess scope and impact, assign metadata | `problem.md`, `metadata.yaml` |
| 2. Specification | AI-assisted | Zachman grounding, SCOUT decomposition, quality facet evaluation, compatibility analysis, test plan generation | `spec.md`, `test-plan.md`, `decisions.md` |
| 3. Spec review | Human gate | Architects and stakeholders validate completeness, correctness, and fitness of the specification | Approved spec (merge to main) |
| 4. Implementation | AI-assisted | Strict BDD-first TDD: one failing test per scenario, minimum code to pass, all prior tests green, commit per cycle | Production code + tests |
| 5. Code review and maintainer acceptance | Human gate | Review against spec (acceptance criteria, coverage, architecture, security, compatibility), then evaluate project-level impact (backwards compatibility, architectural integrity, maintenance cost, release readiness) | Approved implementation |
| 6. Merge and release | Human gate | Merge to mainline, deploy to non-production, validate in environment | Released change |
| 7. Archive | AI-assisted | Move specs to archive, update CHANGELOG, promote significant decisions to ADRs, sync downstream systems | Closed loop, audit trail complete |

Domains may add intermediate states or additional gates, but they should map clearly back to these phases so that portfolio reporting and governance remain consistent across the enterprise.

## Roles and Responsibilities

### Human Roles

| Role | Core responsibilities | Phase authority |
|---|---|---|
| Contributor | Proposes issues, drafts changes, submits pull requests, improves tests and docs. | Phases 1–4 (input and drafting) |
| Maintainer | Owns acceptance into the codebase, enforces standards, protects compatibility and architectural integrity. | Phase 5 (final acceptance decision) |
| Product steward | Owns business intent, story quality, prioritization inputs, and acceptance criteria. | Phase 3 (spec approval), Phase 6 (release validation) |
| Domain architect or technical steward | Reviews changes with cross-team, platform, data, security, or compatibility impact. | Phase 3 (spec approval), Phase 5 (architectural review) |
| Release steward | Coordinates release readiness, change communication, rollback planning, and support signals. | Phase 6 (release authorization) |
| AI workflow steward | Governs agent behavior, permissions, auditability, and quality thresholds. | Cross-cutting (agent configuration and oversight) |

These roles may be performed by different people or combined in smaller teams, but the responsibilities themselves must always be explicitly assigned.

For contributor onboarding, the contribution ladder (Contributor → Recurring Contributor → Trusted Committer → Maintainer), review SLA commitments, and the Trusted Committer role, see the [Contributor Experience Guide](../guides/contributor_experience_guide.md).

### AI Agent Roles

AI agents operate within explicitly scoped permissions and produce draft outputs that require human approval at designated gates.

| Agent | Purpose | Supports human role |
|---|---|---|
| Triage agent | Classifies issues, checks duplicates, assesses scope, creates problem stubs | Contributor, Product steward |
| Architect agent | Pre-flight analysis of cross-boundary changes: surfaces implicit contracts, drafts Gherkin seam specs | Domain architect |
| Spec author | Fills Zachman grid, performs SCOUT decomposition, evaluates quality facets, generates test plans | Domain architect, Product steward |
| Implementer | Writes failing tests from Gherkin scenarios (at Low tier, where no test plan is produced, from `problem.md` acceptance criteria instead, per `docs/policies/change-tiers.md`), implements minimum code to pass, maintains TDD discipline | Contributor |
| Migration author | Authors database migrations following the expand/contract pattern | Contributor |
| Code reviewer | First-pass review against spec: checks acceptance criteria coverage, test completeness, architecture compliance | Maintainer |
| Maintainer agent | Evaluates project-level impact across eight dimensions: compatibility, architecture, mission, maintenance cost, security, release readiness, dependencies, documentation currency | Maintainer |
| Archivist | Moves completed specs to archive, updates CHANGELOG, promotes ADRs, syncs downstream systems | Release steward |

Agents produce structured assessments and recommendations. Humans make disposition decisions (accept, reject, postpone, escalate). No agent output reaches production or a downstream system without passing through a human gate.

## Feature Intake and Triage (Phase 1)

New feature ideas may originate from product strategy, customer requests, support trends, operational pain, regulatory change, ecosystem dependency shifts, or internal engineering insights. Each idea must enter the repository as a traceable work item rather than remain as an informal conversation or private request.

The triage agent classifies incoming issues by type (feature, defect, technical debt), assesses scope and impact, checks for duplicates against existing specs and archived work, and produces a structured problem statement. Every triaged item must include, at minimum:

- Problem statement with business context.
- Intended user or stakeholder.
- Expected value or outcome.
- Constraints or compatibility concerns.
- Initial acceptance criteria.
- Related systems, dependencies, or contracts affected.
- Classification metadata: type, priority, scope, capitalization category, affected entities.

AI agents may draft problem statements or decompose larger requests into candidate issues, but a human product steward or maintainer must validate completeness, correctness, and scope before the work is considered ready for prioritization.

## Prioritization and Sequencing

Prioritization decisions must be explicit, reviewable, and based on shared criteria rather than implicit organizational power. Each domain must publish its scoring or ranking model, which should consider business value, risk reduction, compatibility impact, operational urgency, technical dependency order, and implementation cost.

At minimum, prioritization must answer three questions for each item:

- Why now?
- What becomes easier, safer, or more valuable if this is done?
- What is the cost of delay or non-delivery?

AI agents may cluster duplicate requests, summarize related issues, estimate likely impact areas, and suggest sequencing, but they may not set final priority without accountable human approval. Prioritization decisions should be recorded in the decision log with rationale so they can be reviewed and challenged.

## Specification and Design Review (Phase 2–3)

Changes that affect shared libraries, public APIs, core domain models, security posture, compliance obligations, persistence models, interoperability contracts, or user-visible behavior across teams must be specified before implementation begins. Mature open source projects use proposal processes to separate design agreement from coding momentum, which reduces churn and architectural drift.

### Structured Specification Methodology

Specifications must employ a systematic approach to behavioral decomposition rather than relying on ad-hoc analysis. The SCOUT methodology provides this structure by decomposing each acceptance criterion into five dimensions:

- **State** — system state that must be true before the behavior can execute (maps to Given clauses in BDD).
- **Constraints** — business invariants that govern the behavior and define the contract (maps to Then assertions).
- **Outputs** — external calls, notifications, events, or integrations triggered by the behavior.
- **Updates** — state changes to entities, storage, or downstream systems.
- **Triggers** — data, events, or actions that trigger the behavior (maps to When clauses).

For each dimension, the specification must systematically derive edge cases by asking "what if this is violated?" — preconditions not met, rules exceeded, inputs malformed or unauthorized, side-effects failing, mutations conflicting. This mechanical derivation produces comprehensive test coverage without relying on individual intuition.

### Zachman Grounding

Specifications must ground their design in the six interrogatives (What, How, Where, Who, When, Why) across four abstraction levels (Scope, Business Model, System Model, Technology Model). This ensures that design decisions at each layer align with constraints at higher layers and that implicit assumptions are surfaced before implementation.

Each domain should maintain a Zachman configuration document that pre-fills organizational constants (infrastructure, identity systems, CI/CD pipeline, security tooling, compliance requirements) so that individual specifications inherit these without repetition.

### Quality Facet Evaluation

Every specification must be evaluated against a defined set of quality facets. Domains must declare which facets are mandatory (always evaluated) and which are triggered by specific conditions. A recommended baseline:

**Mandatory facets (always evaluated):**
- **Simplicity** — fewest moving parts necessary; no premature optimization or abstraction.
- **Operability** — deployable, observable, and recoverable using standard infrastructure.
- **Developer experience** — optimized for the domain's primary development workflow (including AI-assisted coding where applicable).
- **Data integrity** — every mutation auditable; compliance obligations satisfied.

**Triggered facet (when public surfaces are affected):**
- **Backwards compatibility** — public contracts are promises to consumers; breaking changes require full deprecation lifecycle.

**Optional facets (0–2 additional, selected per problem):**
- Security posture, performance efficiency, testability, replaceability.

When facets conflict, domains must define a precedence matrix that resolves disputes deterministically. Data integrity and security should always outrank convenience or speed.

### Specification Review Gate

Each domain must define thresholds for when a full specification is mandatory, but the baseline categories above (shared libraries, public APIs, core domain models, security, compliance, persistence, interoperability, cross-team user-visible behavior) are compulsory enterprise-wide.

Specifications must include: problem framing, Zachman grounding, SCOUT decomposition for each acceptance criterion, quality facet evaluation, compatibility impact analysis, proposed approach, alternatives considered, migration or rollback approach, unresolved questions, and approval status.

Human reviewers at the spec review gate must verify:
- Zachman grid is complete and lower levels align with higher.
- SCOUT decomposition covers every acceptance criterion.
- Edge cases are derived systematically, not cherry-picked.
- Quality facet evaluations are honest and violations justified.
- Compatibility impact is identified and migration plans drafted where needed.

For detailed guidance on what the human reviewer should focus on (vs. what the AI already verified), the iterative feedback loop, and how reviewer focus shifts by project maturity, see [Human Gates & Governance](../agentic-sdlc/human-gates.md).

## Implementation Standards (Phase 4)

Implementation work must be linked to an approved specification (`spec.md` at Medium/High tier, or a triaged `problem.md`'s acceptance criteria at Low tier, per `docs/policies/change-tiers.md`). Direct-to-mainline changes without traceable context are prohibited except for formally declared emergency procedures with retrospective review.

### BDD-First Test-Driven Development

Implementation must follow strict BDD-first red-green-refactor discipline, using the approved test plan as the implementation roadmap (at Low tier, where no test plan is produced, using `problem.md`'s acceptance-criteria checklist as the roadmap instead, per `docs/policies/change-tiers.md`):

1. **Red** — Write one failing test derived from a Gherkin scenario in the test plan (at Low tier, where no test plan is produced, derived directly from a `problem.md` acceptance criterion instead, per `docs/policies/change-tiers.md`). The test must fail for the right reason before any production code is written.
2. **Green** — Write the minimum production code necessary to make the test pass. No code for future scenarios.
3. **Accumulate** — Run all existing tests. All must pass. Fix regressions before proceeding.
4. **Commit** — One commit per red-green cycle, with a message linking to the scenario.

This cycle repeats for each scenario in the test plan, in the order specified (at Low tier, where no test plan is produced, for each acceptance criterion in `problem.md` instead, per `docs/policies/change-tiers.md`). The implementation order is designed to scaffold interfaces and wiring first (happy path), then error handling (not-found, validation), then edge cases and integration.

### Scope Discipline

All code changes must include the smallest practical scope that satisfies the approved intent, along with relevant tests, documentation updates, and release-impact notes. Mature projects stay maintainable by preventing invisible side effects, oversized changes, and undocumented behavior drift. The specification defines the boundary of what should be implemented — no more, no less.

## Review and Acceptance Gates (Phase 5)

No change is accepted solely because code compiles or an agent produced it. Acceptance requires both mechanical validation and human review.

### Code Review

The code review agent performs first-pass analysis against the change's approved contract (the specification at Medium/High tier, or `problem.md`'s acceptance criteria at Low tier, per `docs/policies/change-tiers.md`), checking:

- Each acceptance criterion has a corresponding implementation.
- Each Gherkin scenario in the test plan has a corresponding test (at Low tier, where no test plan is produced, each acceptance criterion has a corresponding test).
- Commit history demonstrates one red-green TDD cycle per scenario.
- Quality facet compliance: file sizes, audit records, structured logging, observability.
- Architecture compliance: layer boundaries, service patterns, data access.
- Security: authorization policies, input validation, data handling.
- Compatibility: surface registry changes, deprecation signals, golden-file tests.

Human reviewers then evaluate the implementation with full context of the specification and the agent's assessment. The AI handles mechanical checks (spec compliance, test coverage, consistency); the human focuses on judgment the AI cannot provide — subtle correctness, domain knowledge, operational instincts, and design taste. See [Human Gates & Governance](../agentic-sdlc/human-gates.md) for the full responsibility split. Minimum enterprise gates for merge or acceptance are:

- Linked specification with traceable intent.
- Automated validation appropriate to the asset, including tests and static checks.
- Human review by an authorized maintainer or delegate.
- Verification that acceptance criteria are met.
- Compatibility review when supported contracts may be affected.
- Documentation and release notes updated when user-facing or operator-facing behavior changes.

Domains may require stronger controls such as two-maintainer approval, security sign-off, architecture review, or change advisory review. Those stricter rules are encouraged where justified by criticality, data sensitivity, or blast radius.

### Maintainer Acceptance

After code review approval, the maintainer evaluates project-level impact across eight dimensions:

1. **Backwards compatibility** — Are public surface changes handled per the deprecation policy? Is the surface registry updated?
2. **Architectural integrity** — Does the change follow established ADRs? Are new patterns justified?
3. **Mission alignment** — Is this core to the domain's mission, adjacent, or scope creep?
4. **Maintenance cost** — What new dependencies, patterns, or infrastructure does this introduce?
5. **Security impact** — Does this change the attack surface, trust boundaries, or supply chain?
6. **Release readiness** — Is the CHANGELOG updated? Are deprecation notices in place? Is rollback documented?
7. **Dependency health** — Are licenses compatible? Known vulnerabilities? Actively maintained?
8. **Documentation currency** — Do flow docs and the system overview still describe the system accurately after this change?

The maintainer's disposition is Accept, Postpone (with required changes), or Reject (with rationale recorded in the decision log).

### Acceptance Criteria for AI-Generated Code

Code produced wholly or partly by AI must be treated as untrusted until reviewed. The standard for acceptance is not whether the AI output appears plausible, but whether the resulting change is understandable, testable, maintainable, policy-compliant, and safe to operate.

At minimum, reviewers should confirm:

- The change actually implements the approved specification (or `problem.md`'s acceptance criteria at Low tier, per `docs/policies/change-tiers.md`), not just the surface-level request.
- Edge cases and failure paths derived from SCOUT decomposition are covered.
- The code aligns with domain architecture and conventions.
- Dependencies introduced are necessary and approved.
- Security, privacy, and compatibility expectations are satisfied.
- TDD discipline was maintained: tests preceded production code.
- Ownership is clear for future maintenance.

## Compatibility and Dependency Governance

Each domain must identify and document its supported upstream and downstream dependencies, including public APIs, shared schemas, events, libraries, data contracts, and operational integrations. The absence of a written contract does not mean the dependency is unimportant; it means the risk is unmanaged.

### Surface Registry

Each domain must maintain a surface registry that inventories every public or shared interface with:

- Surface identifier and type (REST endpoint, event schema, shared DTO, database contract, configuration key).
- Stability level: **Stable** (full compatibility guarantee), **Beta** (best-effort, may change with notice), **Deprecated** (sunset scheduled), or **Internal** (no external guarantee).
- Guarantee period and support window.
- Known consumers.
- Sunset date (for deprecated surfaces).

The surface registry is the authoritative source for compatibility impact analysis during specification. Changes that affect registered surfaces automatically trigger the backwards compatibility quality facet.

### Deprecation Lifecycle

Breaking changes to stable or beta surfaces require a full deprecation lifecycle:

1. **Runtime signals** — HTTP `Deprecation` and `Sunset` headers on affected endpoints, structured log warnings on deprecated code paths, and `deprecated_surface_calls_total` metrics for monitoring adoption.
2. **Migration guide** — before/after examples, step-by-step instructions, and verification criteria for consumers.
3. **Minimum deprecation period** — defined per surface type (recommended: two release cycles for public APIs, one cycle for inter-service contracts).
4. **Golden-file tests** — snapshot tests that assert response shapes remain stable during the deprecation window.
5. **Consumer-driven contract tests** — for inter-service dependencies, tests that encode downstream expectations.

Breaking changes require an approved exception with migration guidance, communication plans, and an implementation path that minimizes harm to downstream consumers. The exception and its rationale are recorded in the decision log.

## Defect Management

Defects may be identified through user reports, operational telemetry, automated tests, support channels, security disclosures, internal quality activities, or dependency changes. Every defect enters the same Phase 1 triage process as features: the triage agent classifies, checks for duplicates against existing specs and archived work, and produces a structured problem statement.

Each domain must run a regular defect triage process to:

- Confirm whether the report is valid, duplicate, expected behavior, or missing information.
- Assign severity, priority, ownership, and affected component.
- Identify regressions, security concerns, or broad-impact incidents.
- Decide whether the fix requires immediate response, scheduled work, or rejection with rationale.
- For non-trivial fixes: determine whether a full specification is needed or whether the fix is small enough for direct implementation with abbreviated review.

AI agents may support triage by deduplicating reports, proposing labels, clustering symptoms, and drafting follow-up questions, but a human triage owner remains accountable for severity and disposition decisions.

## Release and Post-Release Stewardship (Phase 6–7)

Accepted changes are not complete until they are safely released and observed in operation. Each domain must maintain release notes, operational readiness checks, rollback expectations, and post-release monitoring practices proportional to risk and criticality.

Where appropriate, domains should use staged rollout, canary exposure, feature flags, versioned interfaces, and deprecation windows to reduce downstream disruption. Mature maintainership is measured not only by speed of merge but by reliability after change enters the field.

### Archive and Closed-Loop Governance

After successful release, the archivist agent completes the governance loop:

- Moves specification artifacts from active work to the archive with a completion summary.
- Updates the CHANGELOG in Keep a Changelog format.
- Evaluates significant decisions for promotion to Architecture Decision Records.
- Syncs status and artifacts to downstream systems (project tracker, wiki, test management).
- Records actual effort (from first spec commit to merge timestamp) for capitalization and capacity planning.

This ensures that every delivered change has a complete, auditable trail from problem statement through specification, implementation, review, release, and archive — entirely within the version-controlled repository.

## Governance Model

This charter establishes a layered governance model:

- **Enterprise charter layer (this document):** defines mandatory baseline rules, shared terminology, minimum gates, quality facets, and AI guardrails. No domain policy may weaken these controls.
- **Domain governance layer (organization-level CLAIRE configuration):** defines domain-specific Zachman constants (infrastructure, identity, CI/CD, security tooling), mandatory and optional quality facets, facet precedence matrix, compatibility contracts, approval matrices, release controls, and service expectations. This layer pre-fills organizational constants so individual specifications inherit them without repetition.
- **Team operating layer (project-level configuration):** defines daily workflows, branch strategies, role assignments, agent permissions, and project-specific Zachman facts consistent with the higher layers.

This layering is intentional. Mature open source ecosystems balance common rules with local autonomy, and enterprises should do the same rather than forcing every team into identical mechanics. The CLAIRE configuration hierarchy mirrors this governance layering: organization-level constants flow down to project-level specifications, which flow down to individual work items.

## Decision-Making and Escalation

Decision rights must be documented in writing for every participating domain. At a minimum, domains must define who can approve features, who can approve breaking changes, who can reject proposals, who can override priority in incidents, and how disputes are escalated.

When disagreement exists between product, engineering, architecture, or operations, decisions should default to written rationale, explicit trade-offs, and the smallest reversible next step. If agreement cannot be reached, the issue must escalate to the domain’s designated decision authority with the full written record attached.

## AI Guardrails

AI agents operate within a clearly bounded permission model. Agents are permitted to perform automated work in Phases 1, 2, 4, and 7 (triage, specification, implementation, archive) and to provide structured assessments in Phase 5 (review). Agents are never permitted to act as the final authority for prioritization, specification approval, code acceptance, exception approval, production release authorization, or acceptance of high-risk change.

The boundary is structural, not advisory: agent outputs produce draft artifacts and recommendations that must pass through a human gate before advancing to the next phase. No agent-produced artifact reaches production or a downstream system without human approval.

Every domain using AI agents under this charter must ensure:

- Agent permissions are explicitly scoped in configuration, not implied.
- Agent actions produce auditable artifacts in the repository (commits, structured assessments, metadata updates).
- Human overrides are always available and clearly documented.
- Model outputs can be challenged, corrected, and improved through the standard review process.
- Sensitive data handling follows enterprise security and privacy policy.
- Agent behavior, quality thresholds, and escalation triggers are governed by a named AI workflow steward.

## Metrics and Continuous Improvement

Each domain must review the effectiveness of its Inner-Source SDLC implementation using metrics that reflect both speed and stewardship. Because the repository is the system of record, most metrics can be derived directly from Git history and artifact metadata rather than requiring manual reporting. Suggested measures include:

- **Cycle time** — from first spec commit to merge (actual effort, computed from Git timestamps).
- **Specification coverage** — percentage of implemented work that had an approved spec before implementation began.
- **Defect escape rate** — defects found after release relative to total delivered changes.
- **SCOUT completeness** — percentage of acceptance criteria with full SCOUT decomposition and edge-case derivation.
- **Compatibility incidents** — unplanned breaking changes or deprecation violations.
- **Review latency** — time from implementation MR opened to human approval.
- **Rollback frequency** — changes reverted after release.
- **TDD discipline** — percentage of implementation commits that follow the red-green-refactor pattern.
- **AI-assist acceptance rate** — percentage of agent-produced drafts accepted without major rework.

Metrics must be used to improve the system rather than to punish contributors for surfacing issues. Healthy open source-style governance depends on making work visible and improvable, not hiding problems to satisfy dashboards.

For detailed measurement guidance — including DORA metrics, agent quality diagnostics, gate rejection analysis, and collection strategies — see `docs/guides/process-metrics.md`.

## Minimum Adoption Requirements

A domain may declare adoption of this charter only after it has established:

- A repository configured as the system of record with standard artifact templates (problem, spec, test plan, decisions, metadata).
- A `PROJECT_INTENT.md` at the repository root, completed for the project (mission, scope, non-goals, quality stance, contribution posture; architecture invariants and decision philosophy as needed).
- Named maintainers and decision authorities documented in the repository (typically referenced from `PROJECT_INTENT.md` Section 7).
- A domain-level CLAIRE configuration (Zachman constants, mandatory quality facets, facet precedence matrix).
- A surface registry for public and shared interfaces.
- A deprecation policy consistent with the enterprise baseline.
- Human review gates for specification approval, code acceptance, maintainer acceptance, and release.
- A written policy for AI agent use, including scoped permissions and escalation triggers.
- A regular triage and governance review cadence.
- Contribution standards covering coding, testing, documentation, review, and release expectations.

Domains are encouraged to start small — a single team with meaningful cross-team dependencies makes a good pilot — but they should not claim inner-source maturity without these fundamentals in place.

### Existing Adopters and Charter Amendments

Charter amendments that add new minimum controls take effect on amendment merge. Domains that adopted this charter before a control was added should bring themselves into compliance on their next intent-relevant change (a contribution dispute, a scope question, a non-goal violation triage) or as part of a regular charter compliance review, whichever comes first. The charter has no central audit; compliance is self-declared and self-maintained, consistent with the inner-source principle that domains hold their own stewardship responsibility.

## Amendment and Extension

This charter is intended to be durable but not static. Amendments to the enterprise-wide charter should follow the same principles it imposes on delivery work: visible proposal, written rationale, review by affected stakeholders, documented decision, and clear communication of the resulting change. Charter amendments should be tracked as Architecture Decision Records in the repository.

Domain addenda may extend this charter with stricter policies, additional review gates, stronger compliance obligations, or specialized artifact requirements, provided they remain consistent with the baseline principles and minimum controls defined here.

## Initial Adoption Guidance

A pragmatic first implementation should begin with one domain that has meaningful cross-team dependencies and enough operational importance to justify discipline, but not so much regulatory or organizational complexity that the pilot stalls. Customer-facing APIs, shared platform capabilities, or a moderately critical internal service often make good starting points because they expose compatibility needs clearly and generate visible learning for other domains.

Adoption steps:

1. Fork or clone the inner-source-sdlc repository as the domain's governance foundation.
2. Author `PROJECT_INTENT.md` from the template (`docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`). This is a discussion, not a typing exercise: align the owning team on mission, scope, non-goals, quality stance, and contribution posture before configuring downstream tooling.
3. Configure the domain-level CLAIRE configuration: fill Zachman constants for infrastructure, identity, CI/CD, security, and compliance requirements.
4. Declare mandatory quality facets and define the facet precedence matrix.
5. Populate the surface registry with known public and shared interfaces.
6. Assign human roles (maintainer, product steward, architect, release steward, AI workflow steward) and link them from `PROJECT_INTENT.md` Section 7.
7. Configure agent permissions and establish the first triage cadence.
8. Run one end-to-end cycle (triage → spec → review → implement → review → release → archive) on a real but bounded work item to validate the workflow before scaling.
