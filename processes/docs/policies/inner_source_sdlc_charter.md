# Inner-Source SDLC Charter

## Purpose

This charter defines a unified enterprise-wide governance model for designing, building, reviewing, releasing, and stewarding software through inner-source practices modeled on mature open-source ecosystems. It establishes a foundational governance baseline that prioritizes transparency, long-term maintainability, backwards compatibility, and shared stewardship while empowering individual domains, product lines, and engineering teams to layer on stricter controls tailored to their risk profile and operational environment.

The charter addresses a central gap in modern AI-accelerated software delivery: while code and artifact generation have become dramatically faster, organizations frequently lack a transparent, disciplined middle layer for intent alignment, backlog shaping, architectural review, and compatibility governance. The **CHORD** methodology (**C**onditions, **H**andling/Triggers, **O**utcomes, **R**ules, **D**eltas) supplies the structured specification and test-derivation discipline that operationalizes this charter, ensuring every change is systematically grounded, decomposed, tested, and verified before reaching production.

## Scope

This charter governs all software engineering domains that adopt the CADENCE Inner-Source SDLC model — spanning customer-facing applications, internal developer platforms, public and private APIs, shared libraries, data pipelines, integration services, and core business systems. It covers the complete lifecycle from feature intake, defect triage, and specification through implementation, review, release, and archival stewardship.

Adopting domains may introduce supplementary policies, domain-specific templates, service-level objectives, and heightened approval gates, but no local addendum may weaken the baseline controls established here for traceability, verification, compatibility guarantees, and human accountability.

## Principles

### Transparent by Default

Work items, decision logs, design tradeoffs, acceptance criteria, and non-sensitive implementation plans are open and inspectable across the enterprise engineering community by default. Mature open-source projects scale through written, reviewable rationale rather than tribal knowledge, and inner-source governance brings that same institutional clarity inside the enterprise.

### Human-Gated, Machine-Assisted

AI agents draft, classify, search, decompose, implement, and pre-screen changes, while accountable humans retain sole authority over prioritization, specification approval, code acceptance, merge, release authorization, and exception handling. This division leverages machine speed and thoroughness without delegating engineering judgment, risk ownership, or architectural stewardship.

### Compatibility as a Product Obligation

Backwards compatibility across published APIs, event schemas, data contracts, CLI surfaces, and operational behaviors is treated as a binding product commitment rather than a best-effort engineering preference. Just as healthy open-source ecosystems earn downstream trust by honoring contract stability and deprecation windows, enterprise domains owe the same predictability to internal and external consumers.

### Shared Ownership, Clear Authority

Any contributor across the organization may file intent issues, report defects, draft specifications, or submit merge requests, while designated maintainers and domain stewards hold clear authority and responsibility for acceptance decisions within their bounded contexts. Broad participation thrives when decision rights are explicitly written down rather than informally assumed.

### Repository-Centered Governance

The version-controlled Git repository is the single authoritative system of record for problem statements, specifications, test plans, decision logs, surface registries, and release history. External tools — such as issue trackers, wikis, and chat channels — receive automated one-way projections from the repository but are never treated as the source of truth. Git provides cryptographic integrity, atomic diff history, branch isolation, and auditability that external trackers cannot replicate. Governance state flows outward from the repository to downstream trackers, never in reverse.

### Specification Before Implementation

No production code is written without an approved specification containing clear acceptance criteria, systematic edge-case derivation, and compatibility impact analysis (at Low tier, where no separate `spec.md` is authored, a triaged `problem.md` with its acceptance-criteria checklist serves as the approved intent contract per `docs/policies/change-tiers.md`). The specification serves as the binding contract between human intent and automated delivery — enabling AI agents to implement changes reliably from an unambiguous blueprint rather than guessing from informal ticket prose.

### Minimum Process, Maximum Clarity

This charter does not exist to generate ceremony. Its goal is to make changes easy to propose, straightforward to reason about, and safe to accept by standardizing the leanest set of artifacts, human gates, and audit records needed to maintain system integrity.

## Operating Model

### Required Artifacts

Every participating domain maintains the following versioned artifacts inside its repository as the authoritative system of record:

- **Problem statement** (`problem.md`) — captures problem framing, affected users, desired business outcome, constraints, acceptance criteria, and impacted dependencies for each work item.
- **Specification** (`spec.md`) — required for Medium- and High-tier changes: structured design grounded in the Contextual Grounding Matrix (6W×4L — What, How, Where, Who, When, Why across Scope, Business, System, and Technology layers), CHORD behavioral decomposition, Engineering Pillar evaluation, and compatibility impact assessment.
- **Test plan** (`test-plan.md`) — framework-agnostic Gherkin BDD scenarios derived mechanically from the CHORD decomposition and sequenced for strict red-green-refactor TDD execution.
- **Decision log** (`decisions.md`) — immutable, append-only record of accepted, rejected, superseded, or deferred design choices and their supporting evidence.
- **Machine-readable metadata** (`metadata.yaml`) — structured classification, priority, scope, tier, lifecycle status, effort tracking, and tracker identifiers consumed by automation and reporting.
- **Project intent** (`PROJECT_INTENT.md`) — the repository's standing charter answering "does this work belong here?": mission, in-scope and out-of-scope boundaries, non-goals, quality stance, architecture invariants, and contribution posture. Authored upon initial CADENCE adoption and amended through a governed process, it grounds maintainer acceptance and rejection decisions in shared principles rather than personal preference.
- **Surface registry** (`docs/policies/surface-registry.md` and `docs/policies/cadence-surfaces.md`) — the inventory of all public and shared interfaces (APIs, events, schemas, CLI flags, configuration bindings) with stability levels, guarantee windows, known consumers, and deprecation logs.
- **Deprecation policy** (`docs/policies/deprecation-policy.md`) — minimum deprecation windows by surface type, runtime and documentation signaling rules, migration guide standards, and emergency breaking-change procedures.
- **Contribution standards** — coding, comment discipline, testing, documentation, review, and release expectations.

Standardized templates for each artifact ship with CADENCE (`specs/TEMPLATE/`) and are instantiated per ticket. External systems (Jira, YouTrack, Confluence) receive synchronized projections from these repository files without ever superseding them.

### Lifecycle Phases

The CADENCE Inner-Source SDLC comprises seven core phases — four AI-assisted execution stages interleaved with three human governance gates (plus an initial human Problem/Intent gate):

| Phase | Mode | Description | Key Output |
|---|---|---|---|
| 1. Triage | AI-assisted | Classify incoming issue, check duplicates, assess scope and impact, assign metadata | `problem.md`, `metadata.yaml` |
| 2. Specification | AI-assisted | Contextual Grounding Matrix (6W×4L), CHORD decomposition, Engineering Pillar evaluation, compatibility analysis, test plan generation | `spec.md`, `test-plan.md`, `decisions.md` |
| 3. Spec review | Human gate | Architects and stakeholders validate completeness, correctness, and fitness of the specification | Approved spec (merge to integration branch) |
| 4. Implementation | AI-assisted | Strict BDD-first TDD: one failing test per scenario, minimum code to pass, all prior tests green, commit per cycle | Production code + tests |
| 5. Code review and maintainer acceptance | Human gate | Review against spec (acceptance criteria, coverage, architecture, security, compatibility), then evaluate project-level impact (backwards compatibility, architectural integrity, maintenance cost, release readiness) | Approved implementation |
| 6. Merge and release | Human gate | Merge to integration branch, deploy to non-production, validate in environment | Released change |
| 7. Archive | AI-assisted | Move specs to archive, update CHANGELOG, promote significant decisions to ADRs, sync downstream systems | Closed loop, audit trail complete |

Adopting domains may introduce domain-specific sub-states or additional sign-off checks, provided they map cleanly onto these canonical lifecycle phases for cross-domain visibility.

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

In smaller teams a single person may wear multiple hats, whereas larger domains separate them; in all cases, each responsibility must have an explicitly named owner.

For contributor onboarding, progression along the contribution ladder (Contributor → Recurring Contributor → Trusted Committer → Maintainer), review SLA commitments, and the Trusted Committer role, consult the [Contributor Experience Guide](../guides/contributor_experience_guide.md).

### AI Agent Roles

AI agents execute within strictly bounded tool permissions (configured in `.agents/agents/` and `.agents/skills/`, or `.gemini/` on Antigravity) and generate draft artifacts and structured evaluations that require human sign-off at designated gates.

| Agent | Purpose | Supports human role |
|---|---|---|
| Triage agent (`cadence-triage-agent`) | Classifies issues, checks duplicates, assesses scope, creates problem stubs | Contributor, Product steward |
| Architect agent (`cadence-architect`) | Pre-flight analysis of cross-boundary changes: surfaces implicit contracts, drafts Gherkin seam specs | Domain architect |
| Spec author (`cadence-spec-author`) | Fills Contextual Grounding Matrix (6W×4L), performs CHORD decomposition, evaluates Engineering Pillars, generates test plans | Domain architect, Product steward |
| Implementer (`cadence-implementer`) | Writes failing tests from Gherkin scenarios (at Low tier, where no test plan is produced, from `problem.md` acceptance criteria instead, per `docs/policies/change-tiers.md`), implements minimum code to pass, maintains TDD discipline | Contributor |
| Migration author (`cadence-migration-author`) | Authors database migrations following the expand/contract pattern | Contributor |
| Code reviewer (`cadence-reviewer`) | First-pass review against spec: checks acceptance criteria coverage, test completeness, architecture compliance | Maintainer |
| Maintainer agent (`cadence-maintainer`) | Evaluates project-level impact across eight dimensions: compatibility, architecture, mission, maintenance cost, security, release readiness, dependencies, documentation currency | Maintainer |
| Archivist (`cadence-archivist`) | Moves completed specs to archive, updates CHANGELOG, promotes ADRs, syncs downstream systems | Release steward |

Agents produce structured evidence and recommendations; accountable humans make all disposition decisions (accept, reject, postpone, escalate). No agent-authored artifact merges to the integration branch or alters production without passing through a human gate.

## Feature Intake and Triage (Phase 1)

Work items originate from product roadmaps, user feedback, support trends, operational telemetry, regulatory changes, dependency upgrades, or internal engineering improvements. Every proposal enters the workflow as a traceable issue rather than an unrecorded chat request.

During Phase 1, `cadence-triage-agent` (assisted by zero-VRAM local semantic search via `local_semantic_embed` and `repo-scout` when configured) classifies the incoming issue by type (`feature`, `bug`, `tech-debt`, `security`, `documentation`, `epic`), evaluates scope against `PROJECT_INTENT.md`, searches `specs/` and `archive/` for duplicates or prior art, and populates a structured problem statement. Every triaged item captures at minimum:

- Problem statement grounded in observable business context.
- Affected users or stakeholders.
- Desired business outcome or value.
- Known architectural or compatibility constraints.
- Testable initial acceptance criteria.
- Impacted domain entities, architectural layers, and integrations.
- Structured metadata in `metadata.yaml`: type, priority, scope, change tier, capitalization category, and affected entities.

While AI agents draft problem stubs and surface prior work, a human product steward or maintainer validates scope alignment and completeness before the ticket is scheduled for delivery.

## Prioritization and Sequencing

Prioritization must be transparent, auditable, and driven by explicit criteria rather than informal organizational clout. Each adopting domain publishes its prioritization rubric weighing business value, risk mitigation, compatibility obligations, operational urgency, dependency sequencing, and engineering effort.

At minimum, scheduling a work item answers three questions:

- Why now?
- What becomes safer, simpler, or more valuable once this ships?
- What is the concrete cost of delay or non-delivery?

AI agents may cluster related tickets, flag duplicate requests, map dependency chains, and suggest implementation ordering, but accountable humans own final sprint and roadmap commitments. Significant prioritization tradeoffs are logged in `decisions.md`.

## Specification and Design Review (Phase 2–3)

Every change affecting shared libraries, public APIs, core domain models, security posture, compliance controls, persistence schemas, cross-service contracts, or cross-team user workflows must be formally specified and approved before implementation starts. Separating design consensus from coding execution prevents costly mid-implementation rework and architectural drift.

### Structured Specification Methodology

Specifications apply a deterministic behavioral decomposition methodology rather than ad-hoc prose. The **CHORD** framework decomposes every acceptance criterion across five orthogonal dimensions:

- **Conditions** — system state and preconditions that must hold before the behavior executes (maps to `Given` clauses in Gherkin).
- **Handling / Triggers** — inputs, commands, events, or schedules that initiate the behavior (maps to `When` clauses in Gherkin).
- **Outcomes** — external responses, emitted events, outbound calls, or notifications produced by the behavior (maps to external `Then` assertions).
- **Rules** — business invariants, validation constraints, and authorization policies governing the behavior (maps to invariant `Then` assertions).
- **Deltas** — internal state mutations, database writes, and audit-trail records persisted by the behavior (maps to state-mutation `Then` assertions).

For each CHORD dimension, the specification mechanically derives edge cases by asking "what happens when this dimension is violated?" — unsatisfied conditions, malformed or unauthorized triggers, failed outbound outcomes, breached business rules, or conflicting state deltas. This systematic interrogation yields comprehensive Gherkin test scenarios and four production observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) without relying on guesswork.

### Contextual Grounding Matrix (6W×4L)

Specifications ground their architecture across the six interrogatives (What, How, Where, Who, When, Why) spanning four abstraction layers (Scope, Business Model, System Model, Technology Model). Filling the Contextual Grounding Matrix (6W×4L) ensures that low-level technology choices align with high-level business constraints and surfaces hidden assumptions before coding begins.

Each domain maintains an organizational configuration document (`docs/agentic-sdlc/CADENCE_ORG.md`) that pre-populates standing organizational constants (cloud infrastructure, identity providers, CI/CD pipelines, observability stack, compliance regimes) so individual specifications inherit them automatically.

### Engineering Pillar Evaluation

Every specification is evaluated against the domain's defined **Engineering Pillars**. Domains declare in `CADENCE_ORG.md` which pillars are always-on mandatory, which are conditionally triggered, and how conflicts are resolved. The standard CADENCE baseline comprises:

**Always-on mandatory pillars:**
- **Simplicity** — fewest moving parts required to solve the problem; no speculative abstractions or unprofiled caching; `<= 3` files to wire a typical capability.
- **Operability** — deployable, observable, and recoverable via standard telemetry (structured JSON logging, distributed tracing, Mimir metrics, and CHORD seams).
- **Developer Experience (Agentic DX)** — single-pass readability for both humans and AI agents (files strictly `< 400` lines; agent reads `<= 5` files to orient).

**Conditionally triggered mandatory pillars:**
- **Data Integrity** (triggered whenever owned data is mutated) — 100% audit-trail coverage; actor identity bound from authenticated context, never caller input.
- **Security Posture** (triggered when touching auth, PII, user input, or client code) — explicit authorization gates, input validation, zero secret leakage.
- **Backwards Compatibility** (triggered when touching registered public surfaces) — public contracts honored; breaking changes follow the full deprecation lifecycle.

**Optional pillars (0–2 selected per ticket):**
- Performance efficiency, testability, replaceability.

Whenever two pillars pull in opposite directions, the precedence matrix in `CADENCE_ORG.md` resolves the tradeoff deterministically (with Data Integrity and Security Posture always outranking convenience or raw speed).

### Specification Review Gate

Domains define objective tier triggers in `docs/policies/change-tiers.md`, while the compulsory enterprise categories (shared libraries, public APIs, core domain models, security, compliance, persistence schemas, cross-service contracts) always require a full specification.

A complete specification package includes: problem framing, Contextual Grounding Matrix (6W×4L), CHORD decomposition for every acceptance criterion, Engineering Pillar evaluations, compatibility impact analysis, proposed file-level design signatures, alternatives considered, migration/rollback strategy, open questions (resolved before approval), and `verify-spec.sh` structural verification.

At Gate 1 (Spec Approval), human reviewers verify:
- The Contextual Grounding Matrix (6W×4L) is coherent and lower layers honor higher-layer constraints.
- CHORD decomposition covers every acceptance criterion completely.
- Edge cases and observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) are derived systematically.
- Engineering Pillar evaluations are candid and any trade-offs are justified via the precedence matrix.
- Compatibility impacts are cataloged and deprecation/migration plans are complete.

For detailed guidance on how human reviewers focus their judgment alongside AI structural checks, see [Human Gates & Governance](../agentic-sdlc/human-gates.md).

## Implementation Standards (Phase 4)

Implementation is always bound to an approved contract (`spec.md` + `test-plan.md` at `status: spec-approved` for Medium/High tiers, or a triaged `problem.md`'s acceptance criteria for Low tier per `docs/policies/change-tiers.md`). Direct commits to the integration branch without traceable ticket context are forbidden outside formally declared emergency fast-tracks (`docs/policies/emergency-fast-track.md`).

### BDD-First Test-Driven Development

Implementation follows strict BDD-first red-green-refactor TDD, executing the scenarios in `test-plan.md`'s Implementation Order (or `problem.md`'s acceptance criteria at Low tier):

1. **Red** — Author a single failing test from the next Gherkin scenario in `test-plan.md` (or the next acceptance criterion in `problem.md` at Low tier). Verify that it fails for the expected behavioral reason before writing production code.
2. **Green** — Write the minimum production code needed to make the failing test pass. Write zero speculative code for later scenarios.
3. **Accumulate** — Run the complete test suite across the repository (using `offload_log_triage` / `log-triage` to compact verbose test runner output while preserving exact pass/fail counts and verbatim failure coordinates). Every existing test must stay green.
4. **Commit** — Create one atomic Git commit per red-green cycle referencing the ticket and scenario ID (`{TICKET-ID} S-{N}`).

This loop repeats sequentially across the implementation queue — scaffolding happy-path contracts first, then not-found and validation rules, boundary conditions, concurrency/idempotency, authorization, observability seams, and end-to-end integration.

### Scope Discipline

Every implementation MR is restricted to the minimum footprint required to satisfy its approved contract, accompanied by tests, boundary comments, and documentation updates. Keeping diffs focused prevents hidden side effects, unreviewed scope creep, and architectural erosion.

## Review and Acceptance Gates (Phase 5)

Passing CI or being authored by an AI agent never suffices for merge. Every code change requires both automated verification and accountable human review.

### Code Review

The `cadence-reviewer` agent (augmented by local pre-review mechanical checks via `offload_deep_review` for the `< 400`-line file ceiling, comment discipline `C1`–`C8`, and CHORD seam presence) performs a comprehensive first-pass inspection against the approved contract (`spec.md` at Medium/High tier, or `problem.md` at Low tier), verifying:

- Every acceptance criterion maps to concrete production code.
- Every Gherkin scenario in `test-plan.md` (or AC in `problem.md` at Low tier) is exercised by an automated test.
- Branch commit history reflects one red-green TDD commit per scenario.
- Engineering Pillar compliance: file-size limits (`< 400` lines), audit logging, structured JSON telemetry, and CHORD observability seams.
- Architectural boundaries: layer separation, repository patterns, and boundary header comments (`C7`).
- Security posture: authorization gates, input validation, and PII/secret protection.
- Compatibility discipline: surface registry updates, deprecation headers/metrics, and golden-file contract tests.

Human reviewers at Gate 2 then focus on high-judgment dimensions that AI cannot replace — subtle production failure modes, domain nuances, concurrency hazards, and design maintainability. See [Human Gates & Governance](../agentic-sdlc/human-gates.md) for the complete human/AI division of labor. Minimum enterprise criteria for code review approval are:

- Linked ticket and approved specification contract.
- Green CI pipeline (build, lint, unit/integration/contract/chaos suites, and `run-gates.sh` where applicable).
- Explicit approval by an authorized human reviewer.
- Verified satisfaction of all acceptance criteria.
- Compatibility sign-off whenever registered surfaces are touched.
- Updated flow/system documentation and release notes whenever user- or operator-facing behavior changes.

High-criticality domains may layer on stricter requirements such as dual-reviewer sign-off, dedicated security review, or performance benchmarking.

### Maintainer Acceptance

Following Gate 2 approval on Medium- and High-tier changes, the maintainer (assisted by `cadence-maintainer` via `/cadence-maintain`) evaluates repository-wide stewardship across eight dimensions:

1. **Backwards compatibility** — Are registered surface modifications handled per `deprecation-policy.md`? Are `surface-registry.md` and `cadence-surfaces.md` accurate?
2. **Architectural integrity** — Does the implementation honor ratified ADRs and `PROJECT_INTENT.md` invariants?
3. **Mission alignment** — Does this work advance the core mission, or does it introduce off-mission scope creep?
4. **Maintenance cost** — What ongoing operational, dependency, or cognitive burden does this change add to the codebase?
5. **Security impact** — How does this alter trust boundaries, authentication/authorization flows, or supply-chain exposure?
6. **Release readiness** — Are `CHANGELOG.md`, migration guides, deprecation signals, and rollback procedures in place?
7. **Dependency health** — Are newly introduced packages permissively licensed, vulnerability-free, and actively maintained?
8. **Documentation currency** — Do `docs/flows/` and `docs/SYSTEM_OVERVIEW.md` remain truthful after this change lands?

The human maintainer records a final disposition of **Accept**, **Postpone** (with required pre-conditions), or **Reject** (with documented rationale in `decisions.md`).

### Acceptance Criteria for AI-Generated Code

All AI-authored code is treated as untrusted draft output until verified at the human gates. The bar for acceptance is never "does the diff look plausible at a glance?", but rather "is this change demonstrably correct, tested, understandable by the team, compliant with policy, and safe to operate at 2 a.m.?".

At minimum, reviewers confirm that:

- The implementation faithfully realizes the approved `spec.md` (or `problem.md` ACs at Low tier), including all negative and boundary requirements.
- Edge cases and observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) derived from CHORD are implemented and tested.
- Code structure and naming follow established repository conventions (`AGENTS.md`).
- Any new dependencies are justified and vetted.
- Security, data integrity, and backwards-compatibility pillars are satisfied.
- Strict red-green-refactor TDD order was followed.
- The reviewing human can explain how the change fits into the system architecture without re-reading the diff.

## Compatibility and Dependency Governance

Every domain inventories and governs its upstream and downstream contracts — including REST/gRPC endpoints, event schemas, shared DTOs, CLI flags, database views, and configuration bindings. An undocumented contract is an unmanaged operational risk.

### Surface Registry

Each domain maintains its surface registry (`docs/policies/surface-registry.md`, alongside the framework-owned `docs/policies/cadence-surfaces.md`) cataloging every published interface with:

- Surface identifier and category (API endpoint, event schema, shared DTO, database contract, CLI/skill surface, configuration key).
- Stability tier: **Stable** (full compatibility guarantee), **Beta** (1-cycle guarantee with migration notice), **Deprecated** (active sunset window), or **Internal** (private to the bounded context).
- Minimum guarantee window (in qualifying release cuts).
- Known downstream consumers.
- Scheduled sunset condition (for deprecated surfaces).

The surface registries serve as the authoritative input for compatibility impact analysis during specification authoring. Any change touching a registered surface automatically activates the Backwards Compatibility pillar.

### Deprecation Lifecycle

Breaking modifications to Stable or Beta surfaces require executing the full deprecation lifecycle defined in `docs/policies/deprecation-policy.md`:

1. **Runtime signals** — emit RFC 8594 `Deprecation` and `Sunset` HTTP headers, structured JSON warning logs, and `deprecated_surface_calls_total` Mimir counters.
2. **Migration guide** — publish concrete before/after examples, numbered migration steps, and verification instructions under `docs/migrations/`.
3. **Minimum deprecation period** — honor the required qualifying-cut window for the surface category (e.g., 2 qualifying release cycles for public APIs and agent/skill definitions; 1 cycle for inter-service contracts and config keys).
4. **Golden-file contract tests** — snapshot assertions ensuring legacy response payloads remain byte-compatible throughout the deprecation window.
5. **Consumer-driven contract tests** — automated tests encoding downstream consumer expectations across service boundaries.

Any emergency exception to the standard deprecation window requires documented security/compliance justification, same-day consumer notification, and an explicit entry in the owning surface registry's Deprecation Log.

## Defect Management

Production defects and bug reports enter the exact same Phase 1 `/cadence-triage` intake pipeline as new features: `cadence-triage-agent` classifies severity, checks for duplicates across `specs/` and `archive/`, maps the failure to its violated CHORD dimension (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, or `BOUNDARY_FAULT`), appends a production insight entry to `docs/agentic-sdlc/production-insights.md`, and seeds `problem.md`.

Each domain maintains a regular defect triage cadence to:

- Verify whether incoming reports represent genuine defects, duplicates, intended behavior, or incomplete reproduction data.
- Assign severity, priority, change tier, and bounded-context ownership.
- Spot regressions, security vulnerabilities, or systemic incident clusters.
- Route the defect to emergency fast-track (`docs/policies/emergency-fast-track.md`), scheduled sprint delivery, or documented decline.
- Right-size the process tier (`Low` for isolated single-context fixes; `Medium` or `High` when contracts, schemas, or multiple contexts are affected).

While AI agents accelerate root-cause localization, duplicate detection, and production-signal categorization, a human steward owns final severity and scheduling decisions.

## Release and Post-Release Stewardship (Phase 6–7)

A merged change is not complete until it is safely promoted to production and verified in live operation. Domains maintain release notes (`docs/releases/`), deployment readiness checks, rollback verification, and post-deployment telemetry proportional to change risk.

Where appropriate, teams employ expand/contract schema migrations, feature flags, canary rollouts, and versioned endpoints to decouple deployment from release risk.

### Archive and Closed-Loop Governance

Once a change merges to the integration branch, `cadence-archivist` (invoked via `/cadence-archive`) closes the governance loop:

- Finalizes `submission.md` and moves the ticket's artifact directory from `specs/{ticket-id}/` to `archive/{ticket-id}/` alongside a generated `summary.md`.
- Updates `CHANGELOG.md` in Keep a Changelog format.
- Disposes of `adr-owed` findings by authoring Architecture Decision Records under `docs/ADR/` and promotes reusable non-bug lessons to `docs/agentic-sdlc/intent-insights.md`.
- Projects final `archived` status and accumulated stage effort to the bound external tracker (`CADENCE_ORG.md` §9).
- Records total accumulated `actual_effort` across lifecycle stages for engineering capacity and capitalization reporting.

This closed loop guarantees that every change shipped by the repository leaves a permanent, self-contained audit trail from initial intent through specification, TDD implementation, multi-gate review, release, and archival.

## Governance Model

This charter operates through a three-tier configuration hierarchy:

- **Enterprise charter layer (this document):** establishes non-negotiable baseline principles, shared CHORD and Contextual Grounding Matrix (6W×4L) vocabulary, mandatory human gates, Engineering Pillars, and AI safety guardrails. No domain or team policy may dilute these baseline rules.
- **Organization governance layer (`docs/agentic-sdlc/CADENCE_ORG.md`):** binds organization-wide constants across the Contextual Grounding Matrix (6W×4L), mandatory and triggered Engineering Pillars, the pillar precedence matrix, model tier mappings, runtime bindings (`.agents/` primary and `.gemini/` for Antigravity), tracker and ID-allocation bindings, branch strategy, and version scheme.
- **Project operating layer (`PROJECT_INTENT.md` and `AGENTS.md`):** declares repository-specific mission, scope boundaries, non-goals, architecture invariants, domain model, build/test commands, and contribution SLAs consistent with the upper layers.

This layered architecture balances enterprise-wide auditability with local engineering autonomy: organizational constants flow automatically into project specifications, eliminating repetitive boilerplate across individual tickets.

## Decision-Making and Escalation

Every adopting domain documents its decision authorities explicitly — naming who approves specifications (Gate 1), who approves code reviews (Gate 2), who holds maintainer acceptance authority (Gate 3), who authorizes emergency fast-tracks, and how cross-gate disagreements escalate.

Whenever product, architecture, and engineering perspectives conflict, resolution defaults to empirical evidence, written trade-off analysis in `decisions.md`, and the escalation ladder defined in `docs/policies/conflict-resolution.md`.

## AI Guardrails

AI agents operate within a strictly enforced permission boundary. Agents perform automated drafting, analysis, implementation, and archival work in Phases 1, 2, 4, and 7, and supply structured review assessments in Phase 5. Agents are **never** authorized to act as the final approver for prioritization, specification sign-off (Gate 1), code review approval (Gate 2), maintainer acceptance (Gate 3), production release, or policy exceptions.

Furthermore, local hardware coprocessor models (`gemma-4-e2b`, `gemma-4-12b`, `gemma-4-26b-a4b`, `nomic-embed-text` accessed via `local-offload` MCP tools and the `repo-scout` / `log-triage` subagents) operate strictly as **read-only coprocessors** (`enable_write_tools: false`): they accelerate semantic code discovery, test/build log triage, and mechanical pre-review checks while primary reasoning and all file writes remain exclusively with the primary reasoning model and human gates.

Every domain operating AI agents under this charter ensures that:

- Agent tool permissions are declaratively scoped in `artifacts/` and compiled to `.agents/` (or `.gemini/`), never left unbounded.
- Every agent action produces version-controlled, inspectable repository artifacts (`problem.md`, `spec.md`, `test-plan.md`, `decisions.md`, `submission.md`, `metadata.yaml`).
- Human override and rejection paths are built into every gate.
- Agent drift or recurring rejection patterns are treated as documentation/context defects and corrected at the source (`docs/guides/process-metrics.md`).
- Credential, PII, and secret handling complies with enterprise security policies.
- An accountable human AI workflow steward oversees agent configurations and gate thresholds.

## Metrics and Continuous Improvement

Adopting domains evaluate the health of their CADENCE implementation using outcome and quality telemetry derived directly from Git history and `metadata.yaml` records rather than manual status reporting:

- **Cycle time / Lead time** — elapsed duration from initial ticket commit to production deployment, stratified by change tier.
- **Specification coverage** — percentage of Medium- and High-tier changes backed by an approved specification prior to implementation.
- **Change failure / Defect escape rate** — proportion of deployments requiring a hotfix or rollback within 7 days.
- **CHORD completeness** — percentage of acceptance criteria carrying complete CHORD five-dimension decomposition, edge-case derivation, and observability seams.
- **Compatibility incidents** — count of unannounced breaking changes or deprecation-window violations.
- **Review turnaround latency** — elapsed time from MR submission to human gate sign-off against `PROJECT_INTENT.md` SLAs.
- **Rollback frequency** — rate of post-merge reverts across bounded contexts.
- **TDD discipline** — proportion of implementation branches exhibiting clean per-scenario red-green commit history.
- **Gate rejection & calibration rates** — spec rejection rate at Gate 1, blocking issue rate at Gate 2, and maintainer postponement/rejection rate at Gate 3.

Telemetry exists to diagnose documentation gaps and process bottlenecks — never to stack-rank individual engineers. For full metric definitions, diagnostic tables, and review cadences, consult `docs/guides/process-metrics.md`.

## Minimum Adoption Requirements

An engineering domain may declare full compliance with this charter once it has established:

- A Git repository configured as the authoritative system of record with standard CADENCE artifact templates (`specs/TEMPLATE/`).
- A completed `PROJECT_INTENT.md` at the repository root defining mission, scope, non-goals, quality stance, architecture invariants, and contribution posture.
- Named human maintainers and gate authorities linked from `PROJECT_INTENT.md` Section 7.
- A bound organizational configuration (`docs/agentic-sdlc/CADENCE_ORG.md`) specifying Contextual Grounding Matrix (6W×4L) constants, mandatory and triggered Engineering Pillars, the pillar precedence matrix, and runtime/tracker/branch/version bindings.
- Populated surface registries (`docs/policies/surface-registry.md` alongside `docs/policies/cadence-surfaces.md`).
- A normative deprecation policy (`docs/policies/deprecation-policy.md`) aligned with the enterprise baseline.
- Active human review gates for Spec Approval (Gate 1), Code Review (Gate 2), Maintainer Acceptance (Gate 3), and Deploy Validation (Gate 4).
- Compiled agent and skill definitions under `.agents/` (or `.gemini/`) with scoped permissions and pre-commit drift gates (`run-gates.sh`).
- Regular triage, post-incident review, and metrics review cadences (`docs/agentic-sdlc/team-rituals.md`).
- Documented contribution standards (`AGENTS.md` and `docs/guides/contributor_experience_guide.md`).

Domains are encouraged to pilot CADENCE in a single bounded service with meaningful cross-team interfaces before expanding across the wider portfolio.

### Existing Adopters and Charter Amendments

Amendments that introduce new baseline controls take effect upon merge to the framework trunk. Domains that adopted prior to an amendment bring their repositories into conformance on their next intent-relevant change or during their scheduled `/cadence-upgrade` / governance review cadence. Compliance remains repository-resident and auditable via Git history, consistent with inner-source stewardship principles.

## Amendment and Extension

This charter is designed to evolve deliberately. Proposed amendments to the enterprise baseline follow the exact same discipline required of software changes: an explicit problem statement, written rationale, stakeholder review, a ratified Architecture Decision Record (`docs/ADR/`), and clear migration notes.

Individual domains may layer stricter addenda, additional compliance checks, or tighter SLAs onto this charter provided they preserve every baseline control defined herein.

## Initial Adoption Guidance

The highest-leverage starting point for a new domain is a service with active cross-team consumers and clear operational visibility — such as a shared platform API or core domain service — where contract stability and structured specifications deliver immediate value without stalling on organizational complexity.

Recommended adoption sequence:

1. Bootstrap the repository with the CADENCE governance tree (`adopt-cadence.sh`).
2. Author `PROJECT_INTENT.md` from `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md` as a collaborative team alignment exercise covering mission, scope, non-goals, quality stance, and contribution posture.
3. Configure `docs/agentic-sdlc/CADENCE_ORG.md`: populate Contextual Grounding Matrix (6W×4L) constants and bind your runtime (`.agents/` or `.gemini/`), tracker, ID allocator, branch strategy, and version scheme.
4. Confirm mandatory and triggered Engineering Pillars and the pillar precedence matrix in `CADENCE_ORG.md`.
5. Inventory existing public endpoints, events, and contracts in `docs/policies/surface-registry.md`.
6. Designate human maintainers, reviewers, and stewards in `PROJECT_INTENT.md` Section 7.
7. Install the local compile/drift hook (`bash ci-templates/scripts/install-hooks.sh`) and verify agent/skill definitions.
8. Execute one complete end-to-end ticket lifecycle (`/cadence-triage` → `/cadence-spec` → Spec Approval → `/cadence-implement` → `/cadence-review` → `/cadence-maintain` → Merge → `/cadence-archive`) on a bounded real-world change to calibrate the team before scaling out.
