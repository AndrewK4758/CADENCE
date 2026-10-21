# CADENCE Org Configuration

*Extends [CADENCE.md](../../specs/CADENCE.md) with organization-wide standards. Replace the `<placeholder>` tokens in this file with your organization's tools, policies, and conventions. Use this in place of the generic template for any repository in your organization.*

**Vocabulary:** *CADENCE* (*Contextual Architecture, Decomposition, Execution, Navigation, Consolidation & Enshrinement*) is the umbrella specification and lifecycle framework. *CHORD* (**C**onditions, **H**andling / Triggers, **O**utcomes, **R**ules, **D**eltas) is the behavioral decomposition engine CADENCE runs in Phase 3. This document tailors CADENCE for a single organization; the CHORD decomposition engine itself remains identical to the portable framework definition.

**How this relates to CADENCE:** The portable CADENCE manual defines 9 standard Engineering Pillars and selects 4–6 per project. This configuration pre-selects 3 always-on mandatory pillars with organization-level measures baked in, plus 2 triggered mandatory pillars (Data & Audit Fidelity and Surface Compatibility) that activate automatically whenever their trigger condition holds — Data & Audit Fidelity whenever the system captures, mutates, or persists owned data, and Surface Compatibility whenever the change touches registered public surfaces — leaving 2 open slots for repository-specific pillars. It also pre-populates the Contextual Grounding Matrix (Phase 1) columns that remain constant across the organization — infrastructure, secrets, CI/CD, and identity.

> **How to use this file:** This document is a template. Replace `<placeholder>` markers with your organization's concrete choices, remove rows that do not apply, and add rows that do. Keep the section headings, mandatory-pillar count, and precedence structure intact — customize the *values*, not the *structural schema*. See [`specs/EXAMPLES/`](../../specs/EXAMPLES/) for completed examples across different team scales (solo developer, startup SaaS, regulated enterprise). Once populated, **rename this file to `CADENCE_ORG.md`** (`mv CADENCE_ORG_TEMPLATE.md CADENCE_ORG.md`) — that is the canonical filename read by CADENCE agents and resolver scripts. Leave the `_TEMPLATE` file framework-owned: future `/cadence-upgrade` runs refresh it, and diffing it against your `CADENCE_ORG.md` highlights newly introduced governance measures.

---

## Pre-Filled Contextual Grounding Constants

These baseline facts hold across every repository in your organization. The LLM copies them directly into `CONTEXT_FACTS.md` during Phase 1 without re-discovering them, and then layers repository-specific facts on top.

### Where (Network) — Org Constants

| Service | Standard | Notes |
|---------|----------|-------|
| VCS + CI/CD | `<your VCS and CI system>` | `<shared template location, if any>` |
| Secrets | `<your secrets manager>` | `<auth model, environments>` |
| Artifact registry | `<your registry>` | `<credential pattern at build time>` |
| Package registry | `<your package hosting>` | `<internal package conventions>` |
| Container orchestration | `<your runtime>` | `<deployment tool>` |
| Non-container fallback | `<your fallback>` | `<when it applies>` |
| Observability | `<logs / metrics / traces tools>` | `<structured logging requirement>` |
| IaC | `<your IaC stack>` | `<template location>` |
| CI runners | `<runner constraints>` | `<known gotchas>` |

### Who (People) — Org Constants

| Aspect | Standard |
|--------|----------|
| Identity provider | `<your IdP>` |
| Auth enforcement | Server-side; frontends are untrusted clients |
| Code maintenance | Human engineers + AI coding agents |
| Dependency updates | `<your bot or process>` |

### Why (Motivation) — Org Constants

| Aspect | Standard |
|--------|----------|
| Branch strategy | `<your branch model>` — the bound strategy, integration branch, its protection status, and the branch-naming convention are governed by the **Branch-Strategy Binding** section below (`CADENCE_ORG.md#branch-strategy-binding`); this row defers to that binding rather than naming a branch here. The narrative lives in the bound document under `docs/policies/branch-strategy/` |
| CI pipeline stages | `<your stage list>` |
| Security scanning | `<SAST / SCA / IaC scanners>` |
| Release cadence | `<your cadence>`. The bound version scheme, legal version-string regex, and which cuts count toward a "release cycle" guarantee are governed by the **Version-Scheme Binding** section below (`CADENCE_ORG.md#version-scheme-binding`); this row defers to that binding rather than restating the scheme here |
| Rollback | `<your rollback mechanism>` |
| Compliance | `<your compliance regime, if any>` |

### Phase 1 instructions for the LLM

When executing Phase 1 on any repository in this organization:
1. Copy the organization constants above into `CONTEXT_FACTS.md` verbatim.
2. Inspect the repository codebase to discover project-specific facts for each of the six columns.
3. Under **Where**: note which organization-standard services this repository actively uses (not every service uses every platform component) and append any project-specific dependencies (databases, third-party APIs, queues, SaaS integrations).
4. Under **Who**: document repository-specific actor roles beyond the organization IdP (for example, service-account principals, API key callers, or administrative vs. tenant roles).
5. Under **What**, **How**, and **When**: discover these entirely from the repository's source code and configuration.

---

## Effort Estimation — the triage and spec-author agents own `estimated_effort`

`estimated_effort` (the human-readable schedule estimate stored in `specs/{id}/metadata.yaml`) is **agent-owned
and maintained by exactly two agents**. This directive **adds `estimated_effort` to the metadata fields those two
agents are accountable for**, supplementing the field lists in their role definitions:

- **`cadence-triage-agent`** records an **initial** `estimated_effort` when creating the specification stub — a first-pass
  estimate grounded in the ticket's `scope` (`S`/`M`/`L`/`XL`), `tier`, and initial problem analysis.
- **`cadence-spec-author`** **updates** `estimated_effort` when authoring or refining the specification — calibrating the
  triage estimate to reflect the full architectural design (files affected, CHORD decomposition, and design options).

Rules:
- Only these two agents may write `estimated_effort`. The `cadence-implementer`, `cadence-reviewer`,
  `cadence-maintainer`, `cadence-archivist`, and `cadence-migration-author` agents **must never** modify it — it is a planning baseline, not an
  execution log. The decomposition / `/cadence-elicit` workflow routes through the triage and
  spec-author steps so **every** decomposition child ticket receives its own estimate (preventing child tickets
  from being left blank when split from a parent).
- **Derive the estimate strictly from the canonical Estimation Scale** in
  [`docs/agentic-sdlc/team-rituals.md`](team-rituals.md) ("Metrics That Replace Rituals" → *Estimation
  Scale*) — **never** invent a duration or estimate from line or file counts. That table is the single source
  of truth mapping each `scope` bucket to its representative `estimated_effort` value (do not duplicate the durations
  here — read them from `team-rituals.md`), and it sizes **epics as the critical path of their child track** rather than a single bucket.
  Record the representative value and log any justified in-band deviation in `decisions.md`.
- The value is formatted as a **human-readable duration**. Whether and how it projects to an external issue tracker is
  governed by the [Tracker Binding](#tracker-binding) (its *Projection triggers & sync discipline*
  subsection and the bound `/sync-*` skill's field mapping); follow whatever that
  binding declares. This section is tracker-neutral.
- **`actual_effort`** is **accumulated stage by stage** — never computed from git commit timestamps and never populated at triage
  or spec time by the estimating agents. Each workflow stage appends its own measured increment upon completion;
  see [Actual Effort Accumulation](#actual-effort-accumulation) below.
- A human operator may override an agent's estimate at any time; agents **set and refine** the value, they do not lock it.

---

## Actual Effort Accumulation

`actual_effort` (`specs/{id}/metadata.yaml`) is a **cumulative running total that grows as the ticket advances through the lifecycle**, not a
retrospective figure calculated at archive time. This rule is defined **here, once**, for every CADENCE stage —
individual skills and agents **do not** restate the measurement or rounding formulas; they defer to this
section. (Whereas [Effort Estimation](#effort-estimation--the-triage-and-spec-author-agents-own-estimated_effort)
above governs the *planned* estimate, this section governs *realized* stage effort.)

### Single-source-of-truth: never restate the multiplier value elsewhere

The per-stage operator-review multiplier values are defined **in this section and nowhere else** — this table is their single
source of truth. Agents and skills MUST NOT restate, copy, or embed any numeric multiplier value (such as
`1.5×`, `1.75×`, `1.1×`) or any worked multiplication formula (such as `20m × 1.5 = 30m`)
**anywhere outside this section**. The worked examples *inside* this section (the stage table and rounding examples below)
constitute the sole permitted occurrence of those numbers.
Specifically, this rule closes three potential leak surfaces:

- **Agent / skill definitions** — `artifacts/roles/`, `artifacts/commands/`, and the compiled `.agents/` runtime trees
  refer to the multiplier only by name ("the per-stage review multiplier", linking to this section), never
  by numeric value.
- **`metadata.yaml` `stage_effort` entries** — record only the finished `effort` duration and,
  optionally, a concise description of the stage work. Never annotate `stage_effort` comments with the multiplier
  value or the arithmetic expression that produced the duration.
- **Tracker sync / worklog payloads** — any external tracker worklog comment MUST NOT include the multiplier number; it carries
  only a stable idempotency token and the resulting duration. (Whether tracker sync runs is governed by the
  [Tracker Binding](#tracker-binding); this rule binds any sync skill that executes.)

Keeping the multiplier numbers in a single place allows an adopter to tune a multiplier in `CADENCE_ORG.md` without stale
copies elsewhere computing mismatched effort.

### The six stages

Each of the six lifecycle stages records the effort spent executing it at the exact moment that stage completes:

> **These multiplier values are initial defaults for a newly adopted repository, not immutable constants.** They
> can be raised to account for heavier human operator review while a team is onboarding to CADENCE, and
> **tuned downward** as adoption matures — when Gate 1/2/3 reviews move faster, specifications require fewer
> revisions, and agents need less manual steering. Adjust them here in one place; every skill and helper script
> reads the active values from this table (per the single-source-of-truth rule above).

| Stage (`stage_effort.stage`) | Owned by (completes the stage) | Review multiplier |
|---|---|---|
| `triage`         | `/cadence-triage` (`cadence-triage-agent`) | **1.0×** |
| `spec`           | `/cadence-spec` (`cadence-spec-author`) | **1.0×** — Spec Approval gate |
| `implementation` | `/cadence-implement` (`cadence-implementer`) | **1.0×** |
| `code-review`    | `/cadence-review` (`cadence-reviewer`) | **1.0×** — Code Review gate |
| `maintainer`     | `/cadence-maintain` (`cadence-maintainer`) | **1.0×** — Maintainer Acceptance gate |
| `archive`        | `/cadence-archive` (`cadence-archivist`) | **1.0×** — mostly bookkeeping |

These six entries correspond to the canonical workflow lifecycle stages (the `status` progression in `AGENTS.md`). A stage is a
**lifecycle phase with its own `status` transition or human gate**, not merely any skill invoked along the way. Neither
`/cadence-migrate` nor `/cadence-elicit` is a standalone stage — and they differ in how their effort is captured:

- **`/cadence-migrate` records no separate `stage_effort` entry.** Authoring database migrations is part of Implementation: it executes *within*
  the implementer's workflow against an approved specification, so its time is already covered by
  the **`implementation`** increment recorded by `/cadence-implement`.
- **`/cadence-elicit` appends its own `triage` increment.** Stakeholder probe elicitation is intake elaboration belonging to
  the **`triage`** stage — yet it runs as a *separate skill invocation* (either offered at the end of `/cadence-triage` step 5 or invoked
  standalone via `/cadence-elicit <id>`), after `/cadence-triage` has already written its classification increment in step 3.
  Consequently, `/cadence-elicit` appends its **own `stage_effort` entry with `stage: triage`** whenever it performs elicitation work. A ticket's `triage`
  stage may therefore legitimately have **multiple `stage_effort` entries** (initial classification followed by probe elicitation), each
  using the `triage` multiplier.

In accordance with the orchestration-boundary rule in the
[Tracker Binding](#tracker-binding) (*Projection triggers & sync discipline*), each stage's
effort increment is written **in the main orchestrating turn**, into the same `metadata.yaml` update that any configured tracker sync
subsequently projects, by the stage's orchestrating skill (`/cadence-triage`, `/cadence-spec`, `/cadence-implement`, `/cadence-review`, `/cadence-maintain`, and
`/cadence-elicit` for an additional `triage` entry).
The sole exception is **`archive`**, where final metadata is written by the `cadence-archivist` subagent as it relocates
the ticket directory to `archive/`; the archivist records the `archive` increment there, and `/cadence-archive` projects it on the
subsequent sync when a tracker is bound. `/cadence-review` is otherwise a read-only phase — its only write to `metadata.yaml` is this
effort accounting step, while the `cadence-reviewer` subagent remains strictly read-only.

### How the increment is measured and rounded

- **Source — agent-observed session wall-clock time.** Measure the active working duration the stage's owner spent
  executing that stage in the session that completed it. It is an observed session duration, never a calendar delta
  between lifecycle timestamps and never a git-log heuristic.
- **Operator-review multiplier — multiply observed time by the stage's Review multiplier.** Because the agent's
  session clock measures only agent execution and excludes human operator review at the
  **start and end** of the stage, multiply the observed duration by the stage's **Review multiplier** (from the table above) prior to rounding. **All six
  stages ship with a neutral default (`1.0×`)**, meaning out of the box the recorded figure equals the observed time rounded to 15 minutes. Raising the multiplier is **opt-in**: adjust the table values above if your team incurs additional operator review overhead, or calibrate per operator via the environment override below.
- **Rounding — always round UP to the next 15-minute increment, never down.** Round the **multiplied** duration **up** to the
  nearest multiple of 15 minutes. Worked examples (stage: observed × multiplier → recorded):
  `triage` 20m × 1.0 = 20m → `30m`; `spec` 38m × 1.0 = 38m → `45m`;
  `implementation` 1h02m × 1.0 = 1h02m → `1h 15m`; `code-review` 30m × 1.0 = 30m → `30m`;
  `archive` 10m × 1.0 = 10m → `15m`. The minimum floor for any non-zero work is one increment: every completed stage whose product is **greater than zero** records **at least `15m`**.

  **The zero exception — a product of exactly zero records `0m`.** When the effective multiplier is set to
  `0` (via the per-operator environment override below) or the observed duration is zero, the product is zero and the recorded value is **`0m`** rather than `15m`.
  Any positive non-zero product rounds **up** to at least `15m`.
- **Format.** Human-readable duration string (`0m`, `15m`, `45m`, `1h 30m`, `2h`). A zero total is written `0m`,
  never `0h`.

### Per-operator override — calibrate your own review time without editing this file

Because human review speed varies by individual operator rather than by repository, any stage's multiplier can be overridden **per operator via environment variables**. Construct the variable name mechanically from the stage identifier by uppercasing it and replacing `-` with `_`:

    CADENCE_STAGE_EFFORT_MULTIPLIER_<STAGE>

producing `..._TRIAGE`, `..._SPEC`, `..._IMPLEMENTATION`, `..._CODE_REVIEW`, `..._MAINTAINER`, and `..._ARCHIVE`.
(`code-review` maps to `_CODE_REVIEW` because hyphens are not valid POSIX shell variable characters.)

Whole numbers and decimals (including values in `[0, 1]`, where `0` records `0m`) are valid. Do **not** append an `x` or `×` suffix. Any unset, empty, non-numeric, suffixed, negative, or whitespace-padded override is **silently ignored** in favor of the table value above — without halting or warning (note the trade-off: a mistyped `1.5x` falls back to the table default). Conversely, an unparseable stage table in `CADENCE_ORG.md` or an unrecognized `--stage` argument halts immediately.

All seven recording sites invoke the single helper script
`ci-templates/scripts/stage-effort.sh --stage <id> --observed <minutes>`, which resolves the environment override,
falls back to this table, multiplies, rounds, and outputs the formatted duration string — guaranteeing identical math across all skills.

### What gets written, at each stage's completion

1. **Append one entry to `stage_effort`** — an append-only list — containing `stage`, the rounded `effort`, and
   `at` (the ISO 8601 completion timestamp). The tuple `(stage, at)` forms the entry's unique idempotency key.
2. **Update `actual_effort`** — set to the sum of all `stage_effort` entries' `effort` durations (which always lands on a 15-minute boundary).

Both updates occur in the **same `metadata.yaml` write** that advances the ticket's `status`, ensuring that any configured immediate tracker sync projects the new effort increment alongside the status transition.

### Projection to the tracker

Whether and how `stage_effort` increments project to an external issue tracker is governed entirely by the
[Tracker Binding](#tracker-binding) (its *Projection triggers & sync discipline* rules and the bound `/sync-*` skill's worklog logic). This section governs only *what* is written to `metadata.yaml` and *when*.

### Archive no longer computes it

Because `actual_effort` accumulates across stages, **`cadence-archivist` never calculates `actual_effort`
from git commit history**. During `/cadence-archive`, the archivist simply appends its own `archive`-stage increment; the total preserved in `archive/{id}/metadata.yaml` is the accumulated sum of all recorded stages.

---

## Ticket Type: `epic` (decomposition parent)

`epic` is a **structural** value in `metadata.yaml`'s `type` enumeration
(`feature | bug | tech-debt | security | documentation | epic`). Whereas the first five values classify a single implementable unit of
work, `epic` designates a **coordination parent ticket that owns no direct code implementation of its own**.

**Decision rule — assign `type: epic` when BOTH conditions hold:**
1. The ticket has **`decomposed_into:` child links** (an active child track mirrored by each child's
   `decomposed_from:` field and `related_tickets.child_decomposition`), **and**
2. The ticket ships **no direct production/test code of its own** — its completion is the rollup
   of its child tickets landing (its `spec.md`, if present, serves as a cross-child architecture coordination spec rather than a single-unit implementation spec).

If only one condition holds, the ticket is **not** an epic: a ticket that ships code *and* spawns follow-up children retains its leaf type (`feature`, `bug`, etc.), while a ticket with no code *and* no `decomposed_into` children is simply unstarted, a spike, or `documentation`.

**When `type: epic` is assigned — at decomposition time, never at initial triage.** Every incoming ticket is initially classified as one of the five leaf types based on its problem statement (`cadence-triage-agent` never assigns `epic` on initial intake). A ticket is **promoted to `type: epic` only when decomposed** — via `/cadence-elicit` decomposition or a re-triage that splits implementation across a child track.
**Whichever agent populates `decomposed_into:` sets `type: epic` in the same edit.** If a child track is ever collapsed back into the parent for direct implementation, `type` reverts to the appropriate leaf type.

**Why a dedicated type value exists (rather than inferring from `decomposed_into:`).** An explicit `type: epic` lets gates, metrics, and tracker sync scripts distinguish rollup parents from leaf tickets without re-parsing link graphs — for example, sizing an epic as its child-track **critical path** rather than a single `scope` bucket (see Effort Estimation above) and exempting it from leaf implementation checks.

**Tracker projection — governed by the Tracker Binding.** How `type: epic` maps to an external issue tracker (issue type, estimate rollup, parent/child links) is defined by the [Tracker Binding](#tracker-binding) and the bound `/sync-*` skill. A sync script **must never guess** a fallback tracker type for `type: epic`: if the bound sync skill leaves `epic` unmapped, it must halt and report the unmapped type rather than silently creating a generic task.

---

## Mandatory Pillars (3 always-on + 2 triggered)

These 3 always-on Engineering Pillars are pre-selected and pre-customized for every repository in this organization. The LLM must include all three in every `PILLAR_LIBRARY.md` and `spec.md` it generates. Projects may tighten the measures or add repository-specific anti-patterns, but may never remove or weaken them.

Two additional pillars — **Data & Audit Fidelity** and **Surface Compatibility** — are triggered mandatory. Data & Audit Fidelity activates whenever the system captures, mutates, or persists data it owns; Surface Compatibility activates whenever a change touches a **registered surface** -- resolved across every registry present (`docs/policies/surface-registry.md`, adopter-owned; `docs/policies/cadence-surfaces.md`, CADENCE's core-owned registry) -- or introduces a new public surface. Both are fail-closed: when in doubt, include them. See [Triggered Mandatory Pillars](#triggered-mandatory-pillars) below.

### Pillar 1: Structural Simplicity (Mandatory)

**Definition:** The system must have the fewest moving parts required to deliver the specified capability.

**Contextual Grounding alignment:** How (Process), What (Data)

**Org-specific measures:**
- Runtime service count: target is the minimum necessary. Every additional deployable service introduces fixed operational overhead (deployment manifest, health endpoint, secrets wiring, alert rules). Explicitly justify any proposed new service.
- State management layers: target 1. Frontends rely on a single client query cache (such as React Query or SWR). Backends treat the primary database as the single source of truth — zero application-tier caching layers unless backed by profiling data.
- Configuration surface to wire a capability: target `<100` lines across `<=3` files. If adding an endpoint, UI view, or CLI command requires touching more than 3 files, the architecture has excessive ceremony.
- CI pipeline job count: target 3–5 jobs; consolidate if the pipeline exceeds 8 jobs.

**Org-specific anti-patterns:**
- Introducing a caching layer "for performance" without measured profiling evidence — primary datastores with proper indexing handle the vast majority of workloads.
- Extracting a shared utility package for code consumed by only one repository — extract shared libraries only when `2+` repositories depend on them.
- Building abstract factory hierarchies for configuration or adapters that have only a single concrete implementation.

**Decision rule:** When choosing between two valid designs, select the one that a new engineer (or AI coding agent) can understand by reading fewer files.

---

### Pillar 2: Operational Resilience (Mandatory)

**Definition:** The system must be deployable, observable, and recoverable by the team that builds it, running on the organization's standard infrastructure.

**Contextual Grounding alignment:** Where (Network), When (Timing), Why (Motivation)

**Org-specific measures:**
- Commit-to-dev-deploy lead time: target `<10` minutes, using the organization's shared CI/CD templates rather than bespoke pipeline scripts.
- Secrets management: 100% of secrets injected via the organization's secrets manager; zero secrets in source files, `.env` files, or container build args.
- Health checks: every deployable service exposes a readiness/health endpoint verifying all critical dependencies (database connectivity, required upstream services).
- Structured logging: JSON logs written to stdout and collected automatically, with every log entry carrying `trace_id`, `span_id`, and `request_id` for cross-service correlation.
- Distributed tracing: all inter-service requests propagate W3C Trace Context headers and appear in the organization tracing backend prior to production cutover.
- Metric emission: every new endpoint emits request count, latency histogram (`p50`/`p95`/`p99`), and error rate metrics following standard naming conventions.
- Alert coverage: every new external dependency or critical path defines latency and error-rate alert rules and appears on the operational dashboard.
- Environment & asset parity: every declarative reference to an externally served asset or runtime resource (fonts/glyphs/sprites/tiles, CSS font stacks, CDN URLs, environment-specific hostnames, database extensions, feature flags) must resolve against the target deployment environment's actual inventory — particularly in offline, air-gapped, or self-hosted deployments. Relying on a third-party library's default external URL that the target environment cannot reach is a deployment defect that unit tests with shared-assumption fakes will miss.
- Rollback readiness: a documented, single-action rollback procedure verified prior to production go-live.
- Observability seams: every new behavior decomposed via CHORD declares its derived runtime seam events (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) in `spec.md`'s Observability Seams table. For components with prior entries in `docs/agentic-sdlc/production-insights.md`, seam coverage is mandatory. See `docs/policies/observability-patterns.md`.

**Org-specific anti-patterns:**
- Custom CI/CD scripts that duplicate shared pipeline templates.
- Real credentials or tokens committed in compose files or `.env.example` templates.
- Unstructured plain-text log lines that require regex parsing downstream.
- Log entries missing trace/request correlation identifiers.
- Shipping new endpoints without latency and error-rate metrics.
- Adding external dependencies without health checks and alert rules.
- Deferring observability instrumentation to a "follow-up ticket" — telemetry ships with the feature or the feature does not ship.
- Omitting observability seams on components listed in `production-insights.md`.
- Deferring `UNSOUND_CONDITION` runtime precondition guards when CHORD Conditions identify required state.
- Changing service ports without updating deployment manifests and ingress/proxy routing in the same MR.
- Declarative configuration (map styles, ORM mappings, CSS, Kubernetes/IaC manifests, GraphQL schemas) referencing external assets or engine defaults absent from the target environment.

**Decision rule:** Any capability that requires an undocumented manual ops step or lacks full observability coverage (structured logs, trace propagation, metrics, alerts, and CHORD seams) is not ready for deployment — flag it at Gate 1 before implementation begins.

---

### Pillar 3: Agentic Ergonomics (Mandatory)

**Definition:** The codebase is structured for first-attempt accuracy by AI coding agents and rapid comprehension by human reviewers.

**Contextual Grounding alignment:** How (Process), What (Data)

**Org-specific measures:**
- Authored file size: target strictly `<400` lines. Beyond ~400 lines, agent single-pass reasoning accuracy and edit precision drop measurably.
- File size carve-out for scenario-indexed BDD test harnesses — when your repository maintains test harnesses that
  index one test function per behavioral scenario, declare their file globs here and govern them per
  function rather than per file: no whole-file line ceiling, each scenario function `<=150` lines,
  any function (including helpers) `<=400` lines, and embedded fixture data exempt from line caps.
  Whenever a harness grows into an entry point that sources modular scenario files, list **both** the entry-point glob and the sourced scenario-module glob here. A harness is its entry point together with the scenario modules it sources: one logical artifact, one governance rule.
  - WHY this carve-out exists: a scenario-indexed harness's cohesive structure directly serves this pillar's other goals —
    reading `<=5` files to add a scenario and authoring a new test from a single adjacent example — whereas fragmenting scenarios away from their shared test resolver merely to satisfy a whole-file line count degrades agent accuracy. Always keep the rationale next to the glob declaration.
  - SCOPE: name the exact globs governed by this clause and enforce it on those globs alone.
- `AGENTS.md` present at repository root: every repository maintains a root `AGENTS.md` (with `CADENCE_DIRECTIVES.md` imported and CLI runtime projections in `.agents/` / `.gemini/` / `.claude/` per `docs/policies/cli-runtime-adoption-policy.md`) documenting architecture boundaries, build/test commands, conventions, and gotchas.
- Strict type coverage: 100% strict typing in statically typed languages (e.g., TypeScript `strict: true`), and full public-signature type annotations enforced by CI in dynamic languages.
- Pattern uniformity: every instance of a recurring architectural element (API handler, domain service, test suite, database migration) follows one canonical template so an agent reading 1 existing file can author a valid new instance.
- Naming consistency: one naming convention per language, documented in `AGENTS.md` with zero exceptions.

**Org-specific anti-patterns:**
- Multi-concern "god files" combining routing, input validation, data access, and response formatting in a single file.
- Dynamic imports, runtime monkey-patching, or reflection magic that obscures the static call graph.
- Undocumented tribal conventions living only in chat threads or external wikis instead of `AGENTS.md` or `docs/policies/`.
- Monolithic shared test-fixture files exceeding 500 lines — partition fixtures by domain or feature area.

**Decision rule:** Whenever an agent must read more than 5 files to understand how to add a standard capability, the architecture has too much indirection — flatten it.

---

## Triggered Mandatory Pillars

### Pillar 4: Data & Audit Fidelity (Triggered Mandatory)

**Activation rule:** Mandatory whenever the system captures, mutates, or persists data it owns — including relational databases, document stores, file buckets, ledgers, audit logs, or any owned record of caller input. Evaluate this trigger during Phase 1 Contextual Grounding (the **What** interrogative). Fail-closed: when in doubt, activate it. Third-party embedded widgets (hosted payment or analytics forms) trigger this pillar unless explicitly registered as 100% delegated to the external system of record with zero local persistence or derivation. Only when a change touches zero owned data may you record `"Data & Audit Fidelity: Not triggered — the system captures/persists no owned data"` and omit the table.

**Definition:** Every state mutation must be auditable, atomic or compensating across multi-entity writes, and consistent with the system's data contracts.

**Contextual Grounding alignment:** What (Data), When (Timing), Who (People)

**Org-specific measures:**
- Audit trail coverage: 100% of write operations emit an immutable audit record (via transactional audit tables, event ledgers, or document change history).
- Mutation provenance: every write records the authenticated actor identity (extracted server-side from the IdP/auth principal, never trusted from client payload fields) and the mutation reason where applicable.
- Multi-table write sequencing: whenever an operation mutates `2+` tables or stores, `spec.md` documents the exact step order, partial-failure rollback/compensation behavior, and cache invalidation scope.
- Server-authoritative derived values: clients submit raw user intent; the server computes all totals, state transitions, and derived fields.
- Cache invalidation discipline: mutations explicitly invalidate affected client/server/CDN caches rather than relying on unverified optimistic patching.

**Org-specific anti-patterns:**
- Fire-and-forget multi-step writes where a downstream step can fail silently and leave persistent state half-updated.
- Client-side optimistic UI mutations across multi-table workflows where rollback is non-trivial.
- Accepting write requests that omit actor provenance or audit metadata.
- Executing cascading or destructive deletes without an explicit confirmation contract displaying the blast radius.

**Decision rule:** When choosing between an unverified optimistic UI shortcut and a server-confirmed transactional write with a loading indicator, always choose transactional audit fidelity.

---

### Pillar 5: Surface Compatibility (Triggered Mandatory)

**Activation rule:** Mandatory whenever a change modifies, deprecates, or removes a **registered surface** -- resolved across **every** surface registry present per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule: `docs/policies/surface-registry.md` (adopter-owned) and, for repositories adopted at or after v4.0.0, `docs/policies/cadence-surfaces.md` (CADENCE's core-owned registry) -- or introduces a new public API endpoint, event schema, shared DTO contract, CLI flag, or configuration key consumed across boundaries. Purely internal changes that touch zero registered surfaces and introduce no new public contracts may mark this pillar N/A. Fail-closed: when in doubt, activate it.

**Definition:** Public surfaces — APIs, event payloads, schemas, CLI contracts, and configuration keys — must remain backwards-compatible throughout their declared guarantee window. Breaking changes require a governed deprecation lifecycle with runtime signaling, consumer migration guides, and automated compatibility tests.

**Contextual Grounding alignment:** How (Process), What (Data), When (Timing)

**Org-specific measures:**
- Public Surface Registry currency: `docs/policies/surface-registry.md` exists and is kept current alongside `docs/policies/cadence-surfaces.md` (core-owned). Every external endpoint, event schema, shared DTO, and configuration contract is registered with its stability tier and guarantee window.
- Guarantee enforcement: no surface marked **Stable** is removed or semantically altered prior to completing the deprecation window defined in [Deprecation Policy](../policies/deprecation-policy.md).
- Compatibility Impact analysis: every specification classifies affected surfaces (`additive`, `modification`, or `removal`) and links to a deprecation plan for any breaking change.
- Runtime deprecation telemetry: deprecated surfaces emit HTTP `Deprecation` and `Sunset` headers, structured log warnings, and `deprecated_surface_calls_total` metrics so consumers detect deprecation automatically.
- Golden-file snapshot tests: every stable API response and event payload shape is guarded by a committed golden snapshot in CI.
- Consumer-driven contract tests: every inter-service dependency is verified by a consumer-owned contract test executed by the producer in CI.
- Versioned integration tests: whenever multiple API versions are active concurrently (at most `current + 1 previous`), integration tests replay prior-version requests against the current implementation.

**Org-specific anti-patterns:**
- Dropping or renaming a response field without checking consumer registrations in the surface registry.
- Renaming an endpoint path without API versioning.
- Altering event payload semantics (e.g., changing the meaning of `null` or empty arrays) without a schema version bump.
- Adding a new required field to an existing request contract.
- Dropping a shared database column without an expand/contract migration across all consumers.
- Promising to "migrate callers later" without recording a sunset date and deprecation entry in the surface registry.
- Updating golden snapshot files in an MR without explicitly documenting the contract change in `spec.md` and `submission.md`.

**Decision rule:** Whenever two designs satisfy all higher-ranked pillars equally, choose the additive design that requires zero changes from existing consumers.

---

## Production Feedback Loop

CADENCE closes the loop between production operations and specification authoring through the living register `docs/agentic-sdlc/production-insights.md`.

### Feedback Cycle

```
Production Defect → Triage (classify + map to CHORD dimension) → production-insights.md
                                                                          ↓
New Feature/Fix in Same Component → Spec Author reads insights → Seam requirements added
                                                                          ↓
Implementation → Implementer adds seams via TDD → Seams detect future issues in production
                                                                          ↓
Production → Seam fires with structured signal → Next issue triaged with full context → Loop
```

### Agent Responsibilities in the Feedback Loop

| Agent | Action |
|---|---|
| **`cadence-triage-agent`** | Classifies production defects into `LOGIC_FAULT` / `DELTA_AUDIT_GAP` / `DRIFT_SIGNAL` / `BOUNDARY_FAULT`, maps each to its CHORD dimension (`Conditions`, `Handling`, `Outcomes`, `Rules`, `Deltas`), and appends a `PROD-NNN` entry to `production-insights.md` |
| **`cadence-spec-author`** | Queries `production-insights.md` (via `repo-scout` / `local_semantic_embed` on `:11434`) before authoring `spec.md`; mandates CHORD observability seams for components with prior incidents and intensifies edge-case derivation on historically weak dimensions |
| **`cadence-implementer`** | Reviews relevant `PROD-NNN` entries for the target domain; implements CHORD observability seams as red-green-refactor TDD scenarios; emits structured JSON seam events per `docs/policies/observability-patterns.md` |
| **`cadence-archivist`** | Compiles periodic pattern summaries in `production-insights.md` and promotes recurring cross-ticket lessons to formal ADRs |

### References

- Observability Seams derivation: `docs/agentic-sdlc/chord-reference.md` (Observability Seams section)
- Log Pattern Catalog: `docs/policies/observability-patterns.md`
- Production Insights (living register): `docs/agentic-sdlc/production-insights.md`

---

## Model Tier Mapping

This section declares the capability tiers and concrete model identifiers used by CADENCE agents in this repository's runtime, alongside the **2-Tier Local Hardware Coprocessor Offload** pipeline. Capability tier names are stable and form part of the Surface Compatibility contract (see the Configuration Contracts entry for `CADENCE_ORG.md#model-tier-mapping` in [`docs/policies/cadence-surfaces.md`](../policies/cadence-surfaces.md) -- that row is **core-owned** and is not duplicated in the adopter-owned [`docs/policies/surface-registry.md`](../policies/surface-registry.md)). Concrete cloud model identifiers are runtime-specific and may be updated within a tier via `/cadence-bump-model`.

**This repo's primary runtime:** Google Antigravity / Gemini CLI (`.agents/` canonical source with `.gemini/` reference runtime projection; see `docs/policies/cli-runtime-adoption-policy.md`).

### Capability Tiers

| Tier | Purpose |
|---|---|
| Deep-reasoning | Cross-artifact architectural synthesis, design exploration, CHORD behavioral decomposition, security boundary analysis, and gate evaluations. Governs the Spec Review gate, Code Review gate, and Maintainer Acceptance gate. |
| Fast-mechanical | Deterministic execution against an established contract — intake classification, artifact archival, template population, tracker synchronization, and red-green-refactor TDD execution of an approved specification. Bounded by decisions already ratified upstream. |
| Local-coprocessor (Tier 1 & Tier 2) | Read-only local hardware offload (`enable_write_tools: false`) for zero-VRAM semantic retrieval, noisy test/compiler log compaction, and pre-review mechanical sweeps (`<400`-line file ceiling, comment discipline, CHORD seam presence). |

### Tier → Concrete Model

| Tier | Concrete Model (Gemini / Antigravity) |
|---|---|
| Deep-reasoning | gemini-4-argon (`pro`) |
| Fast-mechanical | gemini-3.8-flash (`flash`) |
| Local-coprocessor Tier 1 (Always-On CPU `:11434`) | `local-fast-cpu` (`gemma-4-e2b-it`, 128MB 3D V-Cache, 0 VRAM) + `local-embed-cpu` (`nomic-embed-text`, 0 VRAM) |
| Local-coprocessor Tier 2 (On-Demand Hybrid/GPU `:11434`) | `local-moe-hybrid` (`gemma-4-26b-a4b-it`) + `local-12b-gpu` (`gemma-4-12b-it`, RTX 5070 Ti 12GB VRAM) |

### Tier → Agents

| Tier | Agents |
|---|---|
| Deep-reasoning | cadence-architect, cadence-explorer, cadence-spec-author, cadence-reviewer, cadence-migration-author, cadence-maintainer |
| Fast-mechanical | cadence-triage-agent, cadence-archivist, cadence-implementer |
| Local-coprocessor (Read-Only Subagents & MCP Tools) | `log-triage` (`offload_log_triage`), `repo-scout` (`local_semantic_embed`), `offload_deep_review` |

> **Why `cadence-implementer` and `cadence-reviewer` sit on distinct capability tiers.** `cadence-implementer` executes on Fast-mechanical (or Deep-reasoning when overridden for complex multi-context TDD) while `cadence-reviewer` runs on Deep-reasoning. More importantly, review-gate independence from the implementer is **structural** — `cadence-reviewer` runs in an isolated context window, re-derives expected behavior directly from `spec.md` and `test-plan.md` (assisted by `offload_deep_review` mechanical pre-scans on `:11434`), and never inherits the implementer's session reasoning. See [ADR_CADENCE-0007](../ADR/0007-review-gate-independence-is-structural.md).

### Automatic 2-Tier Local Hardware Coprocessor Offload Rules

1. **Zero Autonomous File Writes:** Local coprocessor models (`gemma-4-e2b-it`, `gemma-4-12b-it`, `gemma-4-26b-a4b-it`, `nomic-embed-text`) act strictly as read-only analytical and retrieval coprocessors (`enable_write_tools: false`). All planning, specification authoring, code generation, and gate verdicts remain 100% owned by the primary cloud tiers.
2. **Verbatim Log Extraction + Raw Escape Hatch:** During `/cadence-implement` TDD cycles, `offload_log_triage` (`local-fast-cpu` on `:11434`) compacts verbose test/compiler output into verbatim error lines, `file:line` coordinates, and coverage metrics while writing the complete unedited log with line numbers to `/tmp/agy-last-triage.log` for deeper inspection whenever needed.
3. **Zero-VRAM Semantic Discovery & On-Demand Pre-Review Sweeps:** `/cadence-triage` and `/cadence-spec` use `local_semantic_embed` / `repo-scout` (`:11434`) to search insights and codebase symbols at 0 MB GPU VRAM, while `/cadence-review` and `/cadence-maintain` invoke `offload_deep_review` (`:11434`) for advisory mechanical checks prior to issuing gate verdicts.

### Adopter substitution

When running CADENCE on an alternative agentic-coding runtime, replace the Concrete Model column with your runtime's model identifiers while keeping the capability tier names and agent assignments intact (record any justified role re-tiering in `decisions.md`).

Use `/cadence-bump-model` to bump a concrete model version within a single tier; cross-tier changes are refused by the skill and require a governed specification.

---

## Runtime Binding

The single mandatory home for **runtime coupling** (ADR_CADENCE-0008 clause 4) — the runtime-axis counterpart to the Model Tier Mapping above. Populate your runtime(s) below while preserving the `RC-*` rows. Register this section in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#runtime-binding`). All framework roles and skills are authored against the abstract Runtime Capability Contract (`RC-1`…`RC-6`) in `artifacts/` and compiled into `.agents/` (and projected to `.gemini/` or `.claude/` per `docs/policies/cli-runtime-adoption-policy.md`); concrete runtime primitives are confined to this section.

**Bound runtime(s):** `<your runtime(s) — e.g. Google Antigravity / Gemini CLI (.gemini/ + .agents/); or Claude Code (.claude/ projected from .agents/)>`

### RC-* capability → runtime primitive

| RC | Capability | Your runtime's primitive |
|---|---|---|
| RC-1 | Role execution | `<named role in isolated context: body + tool allowlist + capability tier>` |
| RC-2 | Workflow commands | `<named, user-invokable, argument-taking command with a Markdown body>` |
| RC-3 | Delegation & composition | `<command→role handoff + command→command, passing a structured payload>` |
| RC-4 | File & shell tools | `<read / write / edit / glob / content-search / shell>` |
| RC-5 | Access-mode enforcement | `<read-only mode for human gates; unattended auto-edit mode for TDD/archive>` |
| RC-6 | Artifact install & discovery | `<install location the runtime loads from + a manifest of framework artifacts>` |

### Install paths & config

- `<where compiled roles land — e.g. .agents/agents/>`, `<where compiled commands land — e.g. .agents/skills/>`, `<runtime config file — e.g. AGENTS.md>`.
- `<the adapter/compile command that emits them from the neutral source — e.g. ci-templates/scripts/cadence-compile.sh>`.

### Role → (runtime, capability-tier) assignment (clause 6)

Assign each role group to a `(runtime, tier)` pair. A repository may execute authoring and implementation roles on one runtime and bind the **review roles (`cadence-reviewer`, `cadence-maintainer`) to an independent model or runtime** — making ADR_CADENCE-0007 gate independence *physical* as well as contextual.

| Roles | Runtime | Tier |
|---|---|---|
| `<implementation / authoring roles>` | `<runtime>` | Deep-reasoning |
| `<review roles: cadence-reviewer, cadence-maintainer>` | `<independent runtime / model>` | Deep-reasoning |
| `<mechanical roles: triage, archive>` | `<runtime>` | Fast-mechanical |

---

## Tracker Binding

The single mandatory home for external work-item **tracker coupling** (ADR_CADENCE-0010 clause 2) — the tracker-axis counterpart to the Runtime Binding above. Populate your tracker row(s) below and keep the resolution rules intact. Register this section in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#tracker-binding`). Framework prose refers to "the repo's bound tracker" vendor-neutrally; the concrete tracker choice lives exclusively in this section.

Declare your tracker(s) as **rows of the *Per-prefix tracker bindings* table below** — that table is this section's sole legal declaration form. The legacy repo-wide `**Bound tracker(s):**` line was REMOVED (BTG-242); any file still containing that line HALTs with `tracker.binding.form_removed`. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

### TS-* capability → concrete sync skill

| TS | Capability | Your binding |
|---|---|---|
| TS-1 | Work-item sync (spec metadata + status → tracker; repo→tracker, one-directional) | `<your /sync-* skill — e.g. /cadence-sync-jira>` |

### Per-prefix tracker bindings

*THE ONLY DECLARATION FORM (BTG-179, sole form since BTG-242). One row per ticket-id prefix. **This table SHIPS EMPTY (header only) and an empty table declares nothing** — §9's polarity for "declares nothing" is FAIL LOUD (`tracker.binding.table_missing`), so add at least one row before your first sync. A header and a separator are not a table.*

| Ticket prefix | Bound tracker | Project key(s) | TS-1 sync skill | Agent-time user |
|---------------|---------------|----------------|-----------------|------------------|

*A row binding a REAL tracker MUST carry a project key. A single WILDCARD row — prefix cell `*`, bound to `None — inner-source`, project key EMPTY — is how you declare "every other prefix is inner-source", and it is also the whole declaration for a repo that has no tracker at all; without one, an unmatched prefix FAILS LOUD. A keyless inner-source row naming a REAL prefix is malformed (`tracker.binding.wildcard_malformed`) — the wildcard shape is `*` with an empty key.*

*The fifth column, `Agent-time user`, is OPTIONAL and SHIPS WITH NO VALUE IN ANY ROW
(BTG-315 AC-7) — this upgrade never supplies a default. Leave it empty to keep every
worklog projection unsplit, byte-identical to before you upgraded. Fill it with a Jira
username (passed verbatim) or a YouTrack login to turn on the operator/agent worklog
split governed by [Worklog Attribution Split](#worklog-attribution-split) below. A `*`
wildcard row may never carry a value (`tracker.binding.wildcard_agent_user`).*

### Resolution rule

- Every tracker sync **resolves** its target tracker from this section — matching the ticket-id prefix's row in *Per-prefix tracker bindings* and its `TS-1` sync skill. Tracker name matching is case-insensitive and whitespace-trimmed; ticket prefix matching is case-exact.
- **No `#tracker-binding` declaration ⇒ FAIL LOUD** with an actionable diagnostic ("no tracker bound; declare one in `CADENCE_ORG.md#tracker-binding`"). Never guess a default tracker and never silently no-op. A per-prefix table with **zero data rows** — the initial template state — declares nothing and triggers `tracker.binding.table_missing`. Any cell still holding an un-substituted `<...>` or `{{...}}` placeholder is likewise treated as unbound.
- Presence of the removed `**Bound tracker(s):**` scalar line ⇒ HALT (`tracker.binding.form_removed`) regardless of table contents; this guard runs BEFORE any table row is parsed.
- **Bound tracker mapped to an UNINSTALLED skill ⇒ FAIL LOUD** naming the missing skill; a declared tracker lacking a `TS-*` skill mapping fails loud naming the unmapped tracker. Never fall back silently.
- **AUDIT:** log the resolved tracker, its binding source, and the mapped sync skill **before** contacting the external tracker so every external write is auditable up front.
- UNMATCHED PREFIX => resolves to the single keyless inner-source WILDCARD row (`*`) if present, otherwise FAILS LOUD. Never fall through to another prefix's row or guess a tracker. Note that this is the **EXPLICIT INVERSE** of the Id Allocation Binding's unmatched-prefix rule — do **NOT** copy that section's polarity here.

### Connection config

External tracker connection settings (base URL, credentials, tokens) are **never** stored in this file — they reside in the bound `/sync-*` skill, `metadata.yaml`, and environment/MCP configuration.

### Projection triggers & sync discipline

This subsection defines the tracker-vendor-neutral "when to sync" contract obeyed by every syncing skill, agent, and hook (homed here by BTG-024; vendor-specific API mechanics live inside the bound `/sync-*` skill). Preserve these clauses intact:

- **Trigger classes:** **IMMEDIATE** — any modification to any field of `specs/<id>/metadata.yaml` (or `archive/<id>/metadata.yaml`) requires a tracker sync within the same session; **END-OF-OPERATION** — edits to `problem.md`, `spec.md`, or `test-plan.md` require one tracker sync at the completion of that skill operation.
- **Status-lifecycle subset:** every canonical `status` transition (`triaged` → `spec-in-review` → `spec-approved` → `in-progress` → `in-review` → `merged` → `archived`, plus `cancelled` from any prior state) triggers an IMMEDIATE sync via the bound `/sync-*` skill.
- **Orchestration boundary:** subagents author files and update `status` in `metadata.yaml` but execute **no** external tracker sync; the main-turn orchestrating skill executes the sync once the subagent returns.
- **Enforcement:** skill execution discipline is primary, backed by the two `tms-*` hooks in `.agents/hooks/` which detect any missed sync and resolve active-vs-inert per prefix from *Per-prefix tracker bindings* above.
- **"What synced means":** the bound `/sync-*` skill ran and reported success for the ticket during the current session; any sync failure is surfaced loudly, never ignored.
- **A prefix resolving to `None — inner-source` (including via the `*` wildcard row) ⇒ every sync trigger is an explicit SKIP** for that prefix (no external network call; backstop hooks remain inert).

---

## Id Allocation Binding

The single mandatory home for ticket **identity and ID-allocation coupling** (ADR_CADENCE-0011 clause 4; ADR_CADENCE-0010 clause 2) — the identity-axis counterpart to the Tracker Binding above. Populate your allocator rows below or retain the closed local-mint default. Register this section in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#id-allocation-binding`). When a tracker-originated seed-read runs, the concrete tracker is resolved vendor-neutrally from `#tracker-binding`.

Declare your allocator(s) as **rows of the *Per-prefix allocator bindings* table below** — that table is this section's sole declaration form. The legacy repo-wide `**Bound allocator(s):**` scalar line was REMOVED (BTG-242); any file still carrying it HALTs with `idalloc.binding.form_removed`. By contrast, the repo-wide `id_scheme:` field below is a SEPARATE contract, is **retained**, and must remain present. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

### IA-* capability → concrete allocator

| IA | Capability | Your binding |
|---|---|---|
| IA-1 | Ticket id allocation + tracker-originated seed-read | `<your allocator, or "n/a — closed default; triage mints by convention">` |

### id_scheme

- **id_scheme:** `<PROJECT-KEY>-NNN` — the pattern of a tracker-allocated ticket identifier. Passing an argument matching this scheme to `/cadence-triage` when no `specs/<id>/` directory exists yet triggers a tracker-originated seed-read candidate.

### Per-prefix allocator bindings

*THE ONLY DECLARATION FORM (BTG-179, sole form since BTG-242), parallel in shape to the Tracker Binding's. A row's `reserve-from-tracker` allocator resolves its concrete adapter from **THE SAME PREFIX'S tracker-binding row**, vendor-neutrally, never hardcoded.*

*This table SHIPS EMPTY (header only), and — **unlike the Tracker Binding's** — an empty one does **NOT** fail loud. Every prefix is then unmatched, and an unmatched prefix MINTS. That asymmetry is deliberate: a missing tracker binding could mis-route a sync, while a missing allocator binding is the byte-identical legacy behavior of every repo that never declared one.*

| Ticket prefix | Bound allocator | id_scheme |
|---------------|-----------------|-----------|

### Resolution rule  (NOTE: the absent-default is the INVERSE of the Tracker Binding)

- ABSENT (no per-prefix row matches the ticket prefix, including when the table has zero data rows) / un-substituted PLACEHOLDER / `None — closed default` => **MINT BY CONVENTION** (the closed default). On this path CADENCE allocates ticket IDs via the **local collision-safe allocator** (`/cadence-mint`, PI-039): `/cadence-triage` calls `mint-id.sh --reserve <ticket-prefix>` against the flock-atomic reserve ledger in `git-common-dir`, guaranteeing zero collisions across concurrent git worktrees. `ADR`, `II`, and `PROD` identifiers are **always** minted locally regardless of this binding; only **ticket** prefixes consult the table above.
- **Polarity note:** the absent-default above is the **EXPLICIT INVERSE** of `#tracker-binding`'s "absent ⇒ FAIL LOUD". An empty or unmatched allocator table is **not** an error — it preserves the standard local-minting behavior for repositories that do not reserve IDs from an external tracker. **Never copy the Tracker Binding's fail-loud default into this section.**
- DECLARED allocator + matching `id_scheme` => invoking `/cadence-triage <PROJECT-KEY>-NNN` when `specs/<id>/` does not yet exist performs a **governed, one-time, non-authoritative** seed-read (ADR_CADENCE-0011 cl.2): log the resolution, read the tracker issue summary once, and write the provenance fields (`## Source:` block in `problem.md` plus `originated_from_tracker:` and `seed_read_at:` in `metadata.yaml`). Any argument not matching `id_scheme` falls through to local minting.
- The external tracker contacted for a seed-read is **RESOLVED FROM `#tracker-binding`** (vendor-neutrally) — never hardcoded.
- **AUDIT:** record the resolved allocator, identifier, and binding source **before** contacting the external tracker.
- UNMATCHED PREFIX (no matching row in `### Per-prefix allocator bindings`) => **MINT BY CONVENTION** — the closed default, and the **EXPLICIT INVERSE** of the Tracker Binding's unmatched-prefix halt. Nothing is flagged as an error because local minting is the intended outcome. `ADR` / `II` / `PROD` numbering remains independent of this section.

### Reservation pairing (the allocation obligation)

- SCOPE — **TICKET identifiers only.** This obligation governs every allocation of a ticket ID (whether via an external tracker `reserve` call on a `reserve-from-tracker` row or via local convention minting). **`ADR` / `II` / `PROD` numbering is §10-independent** (always minted locally) and carries **NO** `specs/<id>/` pairing requirement because those registers do not live under `specs/`.
- Every TICKET-ID ALLOCATION must be **PAIRED, within the SAME governed operation**, with the creation of both `specs/<id>/problem.md` and `specs/<id>/metadata.yaml`.
- Any ticket ID allocated without creating both files in the same operation enters the named defect state `idalloc.reserve.unpaired_artifact_creation`.
- The pairing obligation is **DECLARED before contacting the allocator/tracker** and **DISCHARGED when both files are written**.
- This subsection is the **CANONICAL** definition of the reservation-pairing invariant; skills and adapter scripts cite it rather than restating it.
- LIMITATION: this guard combines prompt sequencing with a structural check rather than a distributed two-phase commit across external HTTP trackers.

---

## Sprint-Enforcement Binding

The single mandatory home for the **`/cadence-implement` sprint-enforcement contract** (BTG-004; homed here by BTG-024) — a per-repository configuration binding parallel to the Tracker and Id Allocation bindings above. The `/cadence-implement` pre-flight guard consults this section before TDD implementation begins. Register it in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#sprint-enforcement-binding`).

Declare sprint enforcement as **rows of the *Per-prefix sprint-enforcement bindings* table below** — that table is this section's sole legal declaration form. The three legacy repo-level HTML comment markers (`sprint-enforcement-enabled`, `sprint-check-skill`, `sprint-check-fallback`) were REMOVED (BTG-242); any file still containing any of those markers HALTs with `sprint.binding.form_removed`. Removing them is safe because an unmatched prefix resolves to **DISABLED** by rule (`fallback=Confirm`), matching what `no` or an absent marker previously produced. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

| Field | Value | Meaning |
|-------|-------|---------|
| `sprint_enforcement_enabled` | `<No \| Yes>` | `No` ⇒ no tracker sprint query; guard takes the Confirm path. `Yes` ⇒ guard queries the bound tracker's active sprint. |
| `sprint_check_skill` | `<n/a \| the bound /sync-* skill>` | (when enabled) the sync skill that executes the sprint check — resolved from `#tracker-binding`, never hardcoded. |
| `sprint_check_fallback` | `<n/a \| Block \| Confirm>` | (when enabled) the fallback verdict applied if the tracker sprint query is inconclusive. |

**Resolution rule:** any ticket prefix with **no row** in the table below resolves to **DISABLED** (`fallback=Confirm`) — fail-safe-toward-disabled / opt-in. Only an explicit `Yes` row for that prefix enables the active-sprint tracker query. The sprint guard runs on **every** `/cadence-implement` invocation across **all change tiers**.

### Per-prefix sprint-enforcement bindings

*THE ONLY DECLARATION FORM (BTG-179, sole form since BTG-242). Add one row per ticket-id prefix that wants the guard. This table SHIPS EMPTY (header only), and an empty one resolves DISABLED for every prefix — which is the state a new repo should be in.*

*This section still differs IN KIND from the Tracker and Id Allocation bindings: a prefix WITHOUT a row is answered by a RULE (DISABLED, fallback Confirm), not by a halt and not by a mint. There is no wildcard row here and no repo-wide switch, deliberately — a mandatory wildcard would make an unmatched prefix fail loud, which is the Tracker Binding's polarity imported into this one. A prefix only needs a row when it wants something the rule does not already give it.*

| Ticket prefix | `sprint_enforcement_enabled` | `sprint_check_skill` | `sprint_check_fallback` |
|---------------|------------------------------|----------------------|-------------------------|

*A row's `sprint_check_skill` cell is a POINTER, not a value: write "resolved from `#tracker-binding`'s `<PREFIX>` row". The sprint-check skill and the sync skill MUST be the same adapter for a given prefix, and naming one here independently is how the two come to disagree.*

#### Per-prefix resolution (BTG-179; the ONLY form since BTG-242)

Every query of this section resolves through these exact rules:

- ANY of the three retired `sprint-*` HTML comment markers present in this section => HALT (`sprint.binding.form_removed`), checked BEFORE any table row is parsed, based strictly on the marker's PRESENCE regardless of its value.
- MATCHED PREFIX with `Yes` => **ENABLED** for that prefix; the sprint-check skill is resolved from that same prefix's `#tracker-binding` row (never hardcoded), and the fallback is taken from the row's `sprint_check_fallback` cell (`Block` or `Confirm`).
- MATCHED PREFIX with `No` => **DISABLED** for that prefix (taking the Confirm path).
- MATCHED PREFIX with `Yes` on a prefix bound to `None — inner-source` (no tracker) => HALT (`sprint.binding.enabled_without_tracker`) — sprint enforcement requires an external tracker to query, so an explicit `Yes` on a trackerless prefix is a contradictory configuration and is refused loudly.
- MATCHED PREFIX with any other value => HALT (`sprint.binding.marker_unrecognized`).
- UNMATCHED PREFIX => **DISABLED by rule**: `enabled=no`, `skill=n/a`, `fallback=Confirm`, `source=default`, exit 0, with no warning emitted. This polarity is unique to §13 — it is **neither** `#tracker-binding`'s FAIL LOUD **nor** `#id-allocation-binding`'s MINT.
- **RETIRED with the scalar markers (BTG-242):** the legacy *inherited repo-level `yes`* fallback diagnostic no longer exists because there is no repo-level scalar left to inherit from.

---

## Integration-Branch Enforcement Binding

The single mandatory home for the **`/cadence-implement` integration-branch enforcement contract** (BTG-028) — a per-repository configuration binding parallel to the Sprint-Enforcement Binding above. The `/cadence-implement` integration-branch preconditions (BTG-001's P1/P2 — and the `cadence-implementer` role's Phase 0 check on direct delegation) read this binding for **Medium and High** tier tickets **prior** to evaluating P1/P2. Register it in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#integration-branch-enforcement-binding`).

<!-- integration-branch-enforcement-enabled: yes -->
<!-- ^ The integration-branch enforcement contract the /cadence-implement P1/P2 gate (and the
     implementer Phase 0 mirror) reads. This template ships the SAFER DEFAULT — enabled=yes —
     so a new adopter inherits the gate ON (it protects the spec-approval boundary). enabled=yes
     => the Medium/High gate runs BTG-001's P1/P2; enabled=no => the gate is skipped for your
     repo. An ABSENT / EMPTY / un-substituted PLACEHOLDER / unrecognized marker FAILS LOUD
     (never a silent default) — so leave a concrete yes/no here, NOT a placeholder token. Keep
     this marker in sync with the table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `integration_branch_enforcement_enabled` | **Yes** | adopter default ON — the Medium/High integration-branch gate enforces BTG-001's P1/P2 preconditions. Set to `No` only if your repository workflow has no shared integration branch. |

**Resolution rule (Medium/High tier only; Trivial/Low are tier-exempt and do NOT consult this binding):** resolve `integration-branch-enforcement-enabled` **before** checking P1/P2 — `yes` → enforce BTG-001's P1/P2 preconditions; `no` → skip both with an explicit labeled notice; **ABSENT / EMPTY / un-substituted PLACEHOLDER / unrecognized value → HALT (fail-loud)** naming this binding. Never silently default on or off.

**POLARITY NOTE (Sprint vs. Integration-Branch asymmetry):** this binding's absent-value behavior is the **EXPLICIT INVERSE** of the Sprint-Enforcement Binding's. Whereas an absent sprint-enforcement row resolves to DISABLED, an absent or corrupted `integration-branch-enforcement-enabled` marker **FAILS LOUD** — because silently bypassing the spec-approval branch boundary is a governance safety failure. Never copy the Sprint-Enforcement Binding's absent⇒disabled polarity here.

---

## Branch-Strategy Binding

The single mandatory home for the repository's **branch-strategy selection and its configurable parameters** — a per-repository configuration binding parallel to the bindings above. Every CADENCE skill, agent, and script that needs the integration-branch name, its protection state, or the branch-naming pattern resolves them from this section (ADR_CADENCE-0020, superseding ADR_CADENCE-0016's earlier resolution order). Register it in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#branch-strategy-binding`). The bound strategy document under `docs/policies/branch-strategy/` supplies the role narrative only; it hardcodes no branch names.

<!-- bound-strategy: long-lived-feature-release -->
<!-- integration-branch: develop -->
<!-- integration-branch-protected: yes -->
<!-- branch-naming-convention: {phase}/{type}/{id} -->
<!-- ^ The branch-strategy contract every "is this merged?" / diff-base / branch-naming
     consumer reads (ADR_CADENCE-0020). This template ships a CONCRETE default (long-lived /
     develop / protected) — NOT a placeholder token — so a new adopter inherits a working
     binding out of the box; change bound-strategy to `trunk-based` and rename
     integration-branch to your integration branch if your topology differs. An ABSENT /
     EMPTY / un-substituted PLACEHOLDER `bound-strategy` or `integration-branch` FAILS LOUD
     (never a silent default) — so leave a concrete value here, NOT a placeholder. Keep
     these markers in sync with the table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `bound-strategy` | **long-lived-feature-release** | resolves to `docs/policies/branch-strategy/long-lived-feature-release.md` (the role narrative) |
| `integration-branch` | **develop** | the target branch against which "is this merged?" and diff bases resolve — update if your repo uses a different integration branch |
| `integration-branch-protected` | **yes** | direct commits forbidden; all changes land via reviewed PRs/MRs from isolated worktrees |
| `branch-naming-convention` | **{phase}/{type}/{id}** | machine-readable branch pattern; full details in the bound strategy doc |

**Resolution rule:** consumers read the four fields from the HTML markers and table above; the bound strategy document (`docs/policies/branch-strategy/<bound-strategy>.md`) provides the conceptual workflow narrative only. **ABSENT / EMPTY / un-substituted PLACEHOLDER `bound-strategy` or `integration-branch` → HALT (fail-loud)** naming this binding (preserving ADR_CADENCE-0016 clause-3 fail-closed behavior); a `bound-strategy` pointing to a file that does not exist under `docs/policies/branch-strategy/` likewise fails loud. **AUDIT:** echo the resolved `integration-branch` name in every skip/halt/proceed diagnostic so branch resolution is always transparent.

**Out of scope at v1:** additional strategy documents beyond `long-lived-feature-release` and `trunk-based`; live forge-API verification of `integration-branch-protected`; forge connection credentials.

---

## Test-Scope Binding

The single mandatory home for the **test-scope enforcement contract** (BTG-203) — a per-repository configuration binding parallel to the bindings above. The three roles governed by `docs/policies/test-scope.md` — `cadence-implementer`, `cadence-reviewer`, and `cadence-spec-author` — consult this binding **before** enforcing that policy to determine whether the rule applies to your repository. Register it in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#test-scope-binding`).

This binding makes the policy's scoping question machine-readable: *are your governance documents a description of how your software product is built, or are those documents themselves the shipped product?* For almost every adopting software repository the answer is the former, which is why the shipped default is `yes` (ENFORCED).

<!-- test-scope-enforcement-enabled: yes -->
<!-- ^ The test-scope enforcement contract the three governed roles read (BTG-203). This
     template ships the DEFAULT FOR AN ADOPTER — enabled=yes — so a new adoption is enforced
     from the start: tests validate application behaviour, never the prose that describes how
     the application is built. enabled=no => the rule does NOT reach your repo; set it only
     if your PRODUCT is the governed document corpus (a framework, a standards body, a
     documentation generator), which is the counter-example the policy names. An ABSENT /
     EMPTY / un-substituted PLACEHOLDER / unrecognized marker resolves to NOT ENFORCED — see
     the polarity note below, and note this is the OPPOSITE of the Integration-Branch
     Enforcement Binding above. Keep this marker in sync with the table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `test_scope_enforcement_enabled` | **Yes** | adopter default ON — any test whose subject is a governance markdown document is a `[BLOCKING]` defect. Set to `No` only if your repository's shipped product **is** a governed document corpus. |

**Resolution rule:** resolve `test-scope-enforcement-enabled` prior to applying `docs/policies/test-scope.md` — `yes` → the test-scope policy is **ENFORCED** for this repository; `no` → it is **NOT ENFORCED**, permitting prose/governance assertions where documents are the product. Any **ABSENT**, **EMPTY**, **un-substituted PLACEHOLDER**, or **UNRECOGNIZED** value resolves to **NOT ENFORCED**; when the value is present but unrecognized, resolve to NOT ENFORCED **and emit a diagnostic naming why**, so a typo is surfaced visibly rather than failing silently. No ambiguous value ever resolves to ENFORCED or halts execution.

**POLARITY NOTE (Sprint-Enforcement vs. Integration-Branch alignment):** this binding's absent-value behavior matches the **Sprint-Enforcement Binding** (`absent ⇒ NOT ENFORCED`), **not** the Integration-Branch Enforcement Binding (`absent ⇒ HALT`). A repository upgrading from an older framework version that predates this section would halt on every `/cadence-implement` run if absence were fatal. Because this template ships with the concrete value `yes`, every new adoption (and every existing adoption that pulls this section in via `/cadence-upgrade`'s org-fold) has the rule **ENFORCED** immediately; repositories whose product is a document corpus opt out explicitly by setting `no`.

---

## Version-Scheme Binding

The single mandatory home for the repository's **version-scheme selection and its derived properties**, a per-repository configuration binding parallel to the sections above. Every release skill, deprecation check, and version comparator resolves how your repository numbers releases, what version string regex is legal, and which cuts count toward a "release cycle" guarantee window from this section. Register it in `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CADENCE_ORG.md#version-scheme-binding`). The bound scheme document (`docs/policies/version-scheme/<bound-version-scheme>.md`) defines the bump rules and vocabulary only.

<!-- bound-version-scheme: calver-yyyy-ww -->
<!-- version-pattern: ^[0-9]{4}\.(0[1-9]|[1-4][0-9]|5[0-3])\.(0|[1-9][0-9]*)$ -->
<!-- cycle-qualifying-cut: non-patch -->
<!-- ^ The version-scheme contract every release-producing and guarantee-reading consumer
     reads. This template ships a CONCRETE default (calver-yyyy-ww / the zero-padded
     ISO-week pattern / non-patch) -- NOT a placeholder token -- so a new adopter inherits a
     working binding out of the box, matching the same scheme this framework binds itself
     to (DEC-022: the template's shipped value is also what /cadence-upgrade's org-fold
     appends into an ALREADY-adopted repository's own CADENCE_ORG.md, not only a new
     adoption's -- see docs/migrations/version-scheme-binding.md for the full consequence
     and how to keep semver instead). cycle-qualifying-cut names which cuts count as "one
     release cycle" for a deprecation/guarantee window: a cut QUALIFIES when it advances any
     component other than the trailing patch field; a patch-only cut does NOT count. This
     is uniform across every bound scheme -- it is deliberately not a calendar length,
     because a scheme may permit at most one qualifying cut per calendar interval (and some
     intervals none), so no fixed calendar figure can stand in for an actual count. An
     ABSENT / EMPTY / un-substituted PLACEHOLDER `bound-version-scheme` or `version-pattern`,
     an unrecognized scheme name, or a `bound-version-scheme` naming a document that does not
     exist under docs/policies/version-scheme/ FAILS LOUD (never a silent default) -- so
     leave a concrete value here, NOT a placeholder. Keep these markers in sync with the
     table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `bound-version-scheme` | **calver-yyyy-ww** | resolves to `docs/policies/version-scheme/calver-yyyy-ww.md` |
| `version-pattern` | (as the marker above) | the sole legal version-string regex; zero-padded two-digit ISO week (`date +%G.%V`) |
| `cycle-qualifying-cut` | **non-patch** | a "release cycle" is one release cut that advances any version component other than the trailing patch number; patch-only cuts do not decrement deprecation guarantee windows |

**Resolution rule:** consumers read the three fields from the HTML markers and table above, which must match; the bound scheme document under `docs/policies/version-scheme/` supplies the bump rules. **ABSENT / EMPTY / un-substituted PLACEHOLDER `bound-version-scheme` or `version-pattern`, an unrecognized scheme identifier, or a `bound-version-scheme` whose document does not exist under `docs/policies/version-scheme/` → HALT (fail-loud)** naming this binding before writing any file or tag.

**MONOTONICITY:** every proposed new version must rank strictly greater than the current version under `version_cmp` (three dot-separated numeric components); any non-increasing version proposal is refused loudly naming both versions.

**AUDIT:** echo the resolved version-scheme name in every release/upgrade diagnostic.

**POLARITY NOTE (Version-Scheme vs. Test-Scope asymmetry):** this binding's absent-value behavior matches the **Integration-Branch Enforcement Binding and Branch-Strategy Binding (`absent ⇒ HALT`), NOT the Test-Scope Binding**. A missing or malformed `bound-version-scheme` or `version-pattern` **FAILS LOUD** because cutting a git tag, `README.md` stamp, or `.cadence-version` file under an unintended scheme creates irreversible release artifacts.

**Out of scope at v1:** a third versioning scheme beyond `calver-yyyy-ww` and `semver`; retrospective validation of historical git tags against `version-pattern`; a shared normalizer across `version_cmp` and `.cadence-version`.

---

## Worklog Attribution Split

Added by **BTG-315** under Gate 1's OQ-1 ruling; appended here UNNUMBERED (renumber to match your own `CADENCE_ORG.md` section sequence if desired — parsers match the heading text, never the section ordinal). This section is the single per-repository home for the **per-stage operator-share factor** read by `ci-templates/scripts/worklog-split.sh` when projecting a `stage_effort` entry to a tracker whose *Per-prefix tracker bindings* row declares a non-empty `Agent-time user`. **Completely inert** while `Agent-time user` cells remain empty above.

This table governs **tracker worklog projection only**: it controls how a single recorded `stage_effort` entry is split into at most two tracker worklogs (operator leg + agent leg) at sync time, without altering how `stage_effort` or `actual_effort` is computed or stored in `metadata.yaml`.

| Stage (`stage_effort.stage`) | Operator share (factor) |
|---|---|
| `triage`         | **0.5** |
| `spec`           | **0.5** |
| `implementation` | **0.5** |
| `code-review`    | **0.5** |
| `maintainer`     | **0.5** |
| `archive`        | **0.5** |

**Accepted value grammar:** a non-empty decimal or integer matching `^([0-9]+(\.[0-9]+)?|\.[0-9]+)$`, with at most 9 significant fractional digits after stripping trailing zeros, within the closed interval `[0, 1]`.

**Per-operator environment override:** `CADENCE_WORKLOG_FACTOR_<STAGE>` (constructed mechanically by uppercasing the stage identifier and mapping `-` to `_`): `CADENCE_WORKLOG_FACTOR_TRIAGE`, `CADENCE_WORKLOG_FACTOR_SPEC`, `CADENCE_WORKLOG_FACTOR_IMPLEMENTATION`, `CADENCE_WORKLOG_FACTOR_CODE_REVIEW`, `CADENCE_WORKLOG_FACTOR_MAINTAINER`, and `CADENCE_WORKLOG_FACTOR_ARCHIVE`. Any environment override that violates the grammar above is silently ignored in favor of the table value. If a table cell itself is missing or invalid while split mode is active, it defaults to `1` (100% operator attribution) and emits the non-halting diagnostic `worklogsplit.factor.org_value_unusable stage=<id> cause=<missing|invalid>`.

**Split arithmetic:** the agent leg equals `entry_minutes × (1 - factor)`, floored to the nearest lower 15-minute increment; the operator leg receives the exact remainder (`entry_minutes - agent_minutes`). The two legs always sum to the recorded `stage_effort` duration, and any sub-15-minute remainder stays with the operator leg. Any leg that evaluates to `0m` posts no worklog entry for that party.

**Single-source-of-truth rule:** never restate these factor numbers outside this section; `worklog-split.sh` resolves them internally and outputs only the resulting leg durations.

**Change-tier note:** tuning the numeric factor values in the table above is a Trivial-tier configuration edit; adding, removing, or renaming stage rows is a structural change evaluated under `docs/policies/change-tiers.md`'s Configuration value-vs-shape rule.

---

## Open Pillar Slots (2 of 6)

During Phase 2, the LLM selects 0–2 additional repository-specific pillars from the standard CADENCE catalog based on the problem statement and Contextual Grounding facts. Note that the triggered mandatory pillars (Data & Audit Fidelity, Surface Compatibility, and Security Boundary Posture when ratified as triggered-mandatory) do **not** consume an open slot — they activate automatically whenever their trigger condition fires and sit alongside the 3 always-on mandatory pillars.

### Selection guidance

| If the problem statement involves... | Add this pillar |
|---------------------------------------|---------------|
| Auth changes, user input handling, PII, new client-side code | **Security Boundary Posture** |
| Latency complaints, large datasets, scale concerns | **Execution Performance** |
| Existing test suite to preserve, reliability requirements | **Automated Verifiability** |
| Technology migration, library swap, long-lived system | **Modular Replaceability** |

When none of the rows above apply, use only the 3 always-on mandatory pillars (plus any triggered mandatory pillars that activate). A focused, high-signal pillar library is always preferable to padding a specification with pillars that do not shape the design.

Customize every selected open-slot pillar using concrete numbers and file references from `CONTEXT_FACTS.md` (following Phase 2 Customization Instructions in `specs/CADENCE.md`) rather than leaving generic boilerplate measures.

---

## Precedence Matrix (Org Default)

When two active pillars pull a design in opposite directions, this precedence ranking resolves the trade-off. Any repository-specific deviation from this order requires written justification in `PILLAR_LIBRARY.md` and `decisions.md`.

```
1. Data & Audit Fidelity       — auditability and consistency are non-negotiable (when triggered)
2. Security Boundary Posture   — the identity and trust chain must never weaken
3. Surface Compatibility       — public contracts are promises to consumers (when triggered)
4. Structural Simplicity       — fewer moving parts; complexity taxes every change
5. Operational Resilience      — the team that builds it operates it; observable by default
6. Agentic Ergonomics          — optimize for AI-assisted development, never at correctness cost
7. [Open slot pillar A]        — repository-specific
8. [Open slot pillar B]        — repository-specific
```

Note: Data & Audit Fidelity (#1) and Surface Compatibility (#3) apply whenever their trigger condition holds — Data & Audit Fidelity when the system captures, mutates, or persists owned data, and Surface Compatibility when the change touches registered public surfaces or introduces new ones. Whenever a triggered pillar is dormant, the active precedence order collapses past its slot.

**Why Data & Audit Fidelity ranks #1 when triggered:** In any system that owns persistent state, the most frequent and damaging production failure mode is an unlogged state mutation, an un-invalidated cache, or a multi-table write that partially fails without compensation. Incident responders and compliance auditors alike depend on an unbroken data trail, so whenever owned data is mutated, Data & Audit Fidelity outranks every other concern. Security Boundary Posture sits at #2 because authentication and server-side principal enforcement are foundational invariants across all endpoints. (In a stateless service that owns zero persistent data, Data & Audit Fidelity is dormant and Security Boundary Posture becomes #1.) Organizations under strict regulatory regimes (such as HIPAA or SOC 2) may pin Data & Audit Fidelity as always-on in their `CADENCE_ORG.md`.

**Why Surface Compatibility ranks #3:** Silently breaking a public contract corrupts downstream consumers' data and operational stability. It outranks Structural Simplicity because accepting a slightly more nuanced internal implementation (such as an expand/contract bridge or versioned endpoint) is far cheaper than breaking external callers.

---

## Using This Template

### For a new project

```
You have access to the populated CADENCE organization configuration in
docs/agentic-sdlc/CADENCE_ORG.md and the portable CADENCE
framework manual in specs/CADENCE.md.

Here is my problem statement:

[paste problem statement using VERB + SCOPE + WHY + CONSTRAINTS format]

Run CADENCE using the organization configuration. The 3 always-on mandatory
pillars are pre-defined — begin Phase 1 by copying the Contextual Grounding
organization constants into CONTEXT_FACTS.md, then explore the codebase for
repository-specific facts. In Phase 2, include the 3 always-on mandatory
pillars, evaluate whether Data & Audit Fidelity is triggered (system captures,
mutates, or persists owned data) and whether Surface Compatibility is triggered
(change touches registered public surfaces or introduces new ones), and select
0-2 open-slot pillars based on the problem statement. In Phase 3, perform CHORD
decomposition for every acceptance criterion and derive runtime observability
seams. Proceed through Phases 4-5 as normal.
```

### For an existing project that already has a PILLAR_LIBRARY.md

Audit the repository's existing pillar library against this template:
1. Are all 3 always-on mandatory pillars present (Structural Simplicity, Operational Resilience, Agentic Ergonomics)?
2. Are the triggered mandatory pillars (Data & Audit Fidelity, Surface Compatibility) defined with their activation rules?
3. Are the organization-specific concrete measures included rather than generic placeholders?
4. Does the Operational Resilience pillar include full telemetry and CHORD seam requirements (structured logs, W3C tracing, metrics, alerts, and runtime seams)?
5. Does the precedence matrix align with the organization default (or document an approved rationale for any deviation)?
6. Does the repository maintain `docs/policies/surface-registry.md` (alongside `docs/policies/cadence-surfaces.md`)? If not, initialize it from the policy template.

### Updating this template

Update `CADENCE_ORG_TEMPLATE.md` (and propagate via `/cadence-upgrade`) whenever:
- The organization adopts a new platform standard (observability backend, CI/CD template, secrets manager, or compliance regime)
- Production incidents (`production-insights.md`) reveal a gap in a mandatory pillar's measures or anti-patterns
- Postmortem findings warrant adjusting the default Precedence Matrix

All updates to this template require architecture/maintainer review at Gate 3 because they govern future CADENCE runs across every adopting repository.
