# CLAIRE Org Configuration

*Extends [CLAIRE.md](../../specs/CLAIRE.md) with org-wide standards. Replace the placeholders in this file with your own organization's tools, policies, and conventions. Use this instead of the generic template for any project in your org.*

**Vocabulary:** *CLAIRE* is the umbrella framework. *SCOUT* (State, Constraints, Outputs, Updates, Triggers) is the behavioral decomposition tool CLAIRE uses in Phase 3. This document customizes CLAIRE for one organization; the SCOUT decomposition itself is unchanged from the framework definition.

**How this relates to CLAIRE:** The generic CLAIRE template defines 9 facets and lets the LLM select 4-6 per project. This document pre-selects 3 mandatory facets with org-level measures baked in, plus 2 triggered mandatory facets (Data Integrity and Backwards Compatibility) that activate when their trigger condition fires — Data Integrity when the system captures/manipulates/persists owned data, Backwards Compatibility when the change touches registered public surfaces — and leaves 2 open slots for project-specific facets. It also pre-fills portions of the Zachman Grounding (Phase 1) that are constant across the org — infrastructure, secrets, CI/CD, identity.

> **How to use this file:** This is a template. Replace `<placeholder>` markers with your org's actual choices, drop rows that don't apply, and add rows that do. The headings, mandatory-facet count, and precedence shape are deliberately preserved — adjust the *content*, not the *structure*. See [`specs/EXAMPLES/`](../../specs/EXAMPLES/) for fully-filled examples at different scales (solo dev, startup SaaS, regulated enterprise). When you have filled it in, **rename this file to `CLAIRE_ORG.md`** (`mv CLAIRE_ORG_TEMPLATE.md CLAIRE_ORG.md`) — that is the name the framework's agents read. Keep the `_TEMPLATE` original framework-owned: a future framework update re-delivers it, and diffing it against your `CLAIRE_ORG.md` surfaces new measures to adopt.

---

## Pre-Filled Zachman Constants

These facts apply to every project in your org. The LLM should include them in `ZACHMAN_FACTS.md` without re-discovering them, then layer project-specific facts on top.

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
| Branch strategy | `<your branch model>` — the bound strategy, integration branch, its protection, and the branch-naming convention are declared by the **Branch-Strategy Binding** section below (`CLAIRE_ORG.md#branch-strategy-binding`); this row defers to it rather than naming the integration branch here. The role narrative lives in the bound doc under `docs/policies/branch-strategy/` |
| CI pipeline stages | `<your stage list>` |
| Security scanning | `<SAST / SCA / IaC scanners>` |
| Release cadence | `<your cadence>`. The bound version scheme, the legal version-string spelling, and which cuts qualify toward a "release cycle" guarantee are declared by the **Version-Scheme Binding** section below (`CLAIRE_ORG.md#version-scheme-binding`); this row defers to it rather than naming the scheme here |
| Rollback | `<your rollback mechanism>` |
| Compliance | `<your compliance regime, if any>` |

### Phase 1 instructions for the LLM

When running Phase 1 on a project in this org:
1. Copy the constants above into `ZACHMAN_FACTS.md` as-is.
2. Explore the codebase for project-specific facts in each column.
3. For **Where**: identify which org-constant services this project actually uses (not all projects use all services). Add any project-specific services (databases, external APIs, SaaS integrations).
4. For **Who**: identify project-specific roles beyond the org IdP (e.g., service-account groups, API key consumers, admin vs. user tiers).
5. For **What**, **How**, **When**: these are entirely project-specific — discover from code.

---

## Effort Estimation — the triage and spec-author agents own `estimated_effort`

`estimated_effort` (the human-readable schedule estimate in `specs/{id}/metadata.yaml`) is **agent-owned
and maintained by exactly two agents**. This directive **adds `estimated_effort` to the metadata those two
agents are responsible for**, supplementing the field lists in their own definitions:

- **triage-agent** sets an **initial** `estimated_effort` when it creates the spec stub — a first-pass
  estimate grounded in the issue's `scope` (S/M/L/XL), `tier`, and the problem analysis.
- **spec-author** **updates** `estimated_effort` when it authors or refines the spec — adjusting the
  triage first-pass to reflect the fuller design (files touched, SCOUT decomposition, alternatives).

Rules:
- These are the **only** two agents that write `estimated_effort`. The implementer, code-reviewer,
  maintainer, archivist, and migration-author **must not** change it — it is a planning input, not an
  implementation artifact. The decomposition / `/claire-elicit` handoff carries this through its triage-agent and
  spec-author steps, so **every** decomposition child receives an estimate too (closing the gap where
  decomposition children could be left blank while an independently-triaged sibling had an estimate).
- **Derive the value from the canonical Estimation Scale** in
  [`docs/agentic-sdlc/team-rituals.md`](team-rituals.md) ("Metrics That Replace Rituals" → *Estimation
  Scale*) — do **not** invent a number or estimate from line/file counts. That table is the single source
  of truth for the `scope`-bucket → representative `estimated_effort` mapping (do not restate the durations
  here — read them there), and it sizes **epics as the child-track critical path**, not their own bucket.
  Record the representative value; note any in-band deviation in `decisions.md`.
- The value is a **human-readable duration**. Whether and how it is projected to an external tracker is
  governed by the [Tracker Binding](#tracker-binding) (its *Projection triggers & sync discipline*
  subsection, and the bound `/sync-*` skill for any vendor-specific worklog mapping); follow whatever that
  binding specifies. This section takes no position on the tracker stance.
- **`actual_effort`** is **accumulated per stage** — not derived from git history and not filled at triage
  or spec time by these two estimating agents. Each stage's owner appends its own measured increment as the
  stage completes; see [Actual Effort Accumulation](#actual-effort-accumulation) below.
- A human may always override an agent's estimate; the agents **set and refine** it, they do not lock it.

---

## Actual Effort Accumulation

`actual_effort` (`specs/{id}/metadata.yaml`) is a **running total that grows as the spec advances**, not a
figure computed once at archive time. This directive is defined **here, once**, for every CLAIRE stage —
the individual skills and agents do **not** each restate the measurement or rounding rules; they follow this
section. (This is the counterpart to [Effort Estimation](#effort-estimation--the-triage-and-spec-author-agents-own-estimated_effort)
above: that section owns the *planning* estimate, this one owns the *realized* effort.)

### Single-source-of-truth: never restate the multiplier value elsewhere

The per-stage review multiplier values are defined **here and only here** — this section is their single
source of truth. Agents and skills MUST NOT restate, copy, or embed any numeric multiplier value (for
example `1.5×`, `1.75×`, `1.1×`) or any worked multiplication expression (for example `20m × 1.5 = 30m`)
**anywhere outside this section**. The worked examples *within* this section (the table below and the
rounding examples) are the authoritative definition and are the sole permitted place the values appear.
Specifically, the three leak surfaces this rule closes are:

- **Agent / skill source** — `artifacts/roles/`, `artifacts/commands/`, and the generated `.claude/` trees
  reference the multiplier only by name ("the per-stage review multiplier", pointing to this section), never
  by value.
- **`metadata.yaml` `stage_effort` comments** — these record only the computed `effort` duration and,
  optionally, a brief description of the work performed. They MUST NOT annotate the entry with the multiplier
  value or the multiplication that produced the duration.
- **Sync / worklog text** — any tracker-sync worklog comment MUST NOT carry the multiplier value; it uses
  only a stable idempotency marker and the computed duration. (Whether any sync runs is governed by the
  [Tracker Binding](#tracker-binding); this rule binds any sync that does.)

Keeping the value in one place is what lets an adopter change a multiplier here — without any stale
hard-coded copy surviving elsewhere to compute incorrect effort.

### The six stages

Each of the six workflow stages records the effort spent working it, at the moment that stage completes:

> **These multiplier values are starting defaults for a newly-adopted project, not fixed constants.** They
> are deliberately generous to cover the heavy operator review a team incurs while it is still learning the
> workflow. As CLAIRE adoption matures within the project — reviews get faster, gates raise fewer
> surprises, and agents need less correction — the team is expected to **revise these values downward** to
> reflect the lower real review cost. Tune them here, in this one place; every skill and agent reads the
> revised values from this section (see the single-source-of-truth rule above).

| Stage (`stage_effort.stage`) | Owned by (completes the stage) | Review multiplier |
|---|---|---|
| `triage`         | `/claire-triage` (triage-agent) | **1.0×** |
| `spec`           | `/claire-spec` (spec-author) | **1.0×** — Spec Approval gate |
| `implementation` | `/claire-implement` (implementer) | **1.0×** |
| `code-review`    | `/claire-review` (code-reviewer) | **1.0×** — Code Review gate |
| `maintainer`     | `/claire-maintain` (maintainer) | **1.0×** — Maintainer Acceptance gate |
| `archive`        | `/claire-archive` (archivist) | **1.0×** — mostly bookkeeping |

These six are the workflow lifecycle stages (the `status` progression in `CLAUDE.md`). A stage is a
**lifecycle phase with its own `status`/gate**, not merely any skill that runs during the spec. Neither
`/claire-migrate` nor `/claire-elicit` is a stage — but they differ in how their effort is captured:

- **`/claire-migrate` gets no entry of its own.** Authoring migrations is Implementation work: it runs *inside*
  the implementer's single operation (an approved spec while entities change), so its effort is already
  inside the one **`implementation`** increment `/claire-implement` records. Nothing to record separately.
- **`/claire-elicit` records its own `claire-triage` increment.** Probe elicitation is intake elaboration that belongs to
  the **`claire-triage`** stage — but it is a *separate skill invocation* (offered from `/claire-triage` step 5, or run
  standalone as `/claire-elicit <id>`), and `/claire-triage` records its own increment in step 3, **before** the elicit
  offer. So the triage classification's increment can never cover the elicit interview. `/claire-elicit` therefore
  appends its **own `stage_effort` entry labelled `stage: triage`** whenever it does work. The `claire-triage`
  stage can thus carry **more than one entry** (classification, then elicitation) — each is its own
  `stage_effort` entry, and each uses the `claire-triage` multiplier.

Following the orchestration-boundary rule in the
[Tracker Binding](#tracker-binding) (*Projection triggers & sync discipline*), each stage's
increment is written **in the main turn**, into the same `metadata.yaml` state any configured tracker sync
then projects, by
the stage's orchestrating skill (`/claire-triage`, `/claire-spec`, `/claire-implement`, `/claire-review`, `/claire-maintain`, and
`/claire-elicit` for a further `claire-triage` increment) — the concrete recording step lives in each of those skills.
The one exception is **`archive`**, whose final metadata is written by the `claire-archivist` subagent as it moves
the spec; the archivist records the `archive` increment there and the `/claire-archive` skill projects it on the
following sync where one is configured. `/claire-review` is otherwise a read-only stage — its sole `metadata.yaml` write is this
effort bookkeeping; the `claire-reviewer` agent stays read-only.

### How the increment is measured and rounded

- **Source — agent-observed session time.** Start from the wall-clock working time the stage's owner spent
  on that stage in the session that completed it. It is a realized-effort figure, not a calendar span
  derived from the lifecycle timestamps and not a git-history calculation.
- **Operator-review multiplier — apply the stage's multiplier to the observed clock time.** The agent's
  session captures only its own working time; it does **not** include the operator's review at the
  **beginning and end** of the stage. To account for that human time, multiply the observed clock time by
  the stage's **Review multiplier** (the per-stage column in the table above) before rounding. **All six
  stages ship the same neutral default (`1.0×`)**, so out of the box the multiplier adds nothing and the
  recorded figure is the observed time, rounded. The markup is **opt-in**: raise these values here if your
  team incurs material operator review, or let each operator calibrate their own through the per-operator
  override below. The multiplied value is what gets rounded and recorded.
- **Rounding — up to the next 15-minute increment, never down.** Round the **multiplied** time **up** to the
  next multiple of 15 minutes. Worked examples (stage: observed × multiplier → recorded):
  `claire-triage` 20m × 1.0 = 20m → `30m`; `spec` 38m × 1.0 = 38m → `45m`;
  `implementation` 1h02m × 1.0 = 1h02m → `1h 15m`; `code-review` 30m × 1.0 = 30m → `30m`;
  `archive` 10m × 1.0 = 10m → `15m`. The floor is one increment: every completed stage whose computed
  time is **greater than zero** records **at least `15m`**, and is never rounded down.

  **The one exception — a computed time of exactly zero records `0m`.** When the resolved multiplier is
  `0` (reachable only through the per-operator override below, never a shipped default) or the observed
  time is zero, the product is zero and the recorded value is exactly **`0m`**, not lifted to the floor.
  Any non-zero product, however small, still rounds **up** to `15m`.
- **Format.** A human-readable duration (`0m`, `15m`, `45m`, `1h 30m`, `2h`). A zero total renders `0m`,
  never `0h`.

### Per-operator override — calibrate your own review time without editing this file

Each stage's multiplier may be overridden **per user, through the environment**, because review time is a
property of the *operator*, not of the project. The variable name is derived mechanically from the stage
id — uppercase it and map `-` to `_`:

    CLAIRE_STAGE_EFFORT_MULTIPLIER_<STAGE>

giving `..._TRIAGE`, `..._SPEC`, `..._IMPLEMENTATION`, `..._CODE_REVIEW`, `..._MAINTAINER`, `..._ARCHIVE`.
(`code-review` → `_CODE_REVIEW`: a hyphen is not a valid POSIX shell identifier character, so a hyphenated
name could not be set with `export`.)

Whole numbers and decimals are accepted, including everything in `[0, 1]`; `0` is valid and records a real
`0m` stage. An `x` or `×` suffix is **not** accepted. An absent, empty, non-numeric, suffixed, negative or
padded value is **quietly ignored** in favour of this section's table value — no halt, no warning. Note
the cost: a typo'd `1.5x` is indistinguishable from setting nothing at all. An unparseable stage table or
an unknown stage id, by contrast, is still a hard failure.

All seven recording sites call one script,
`ci-templates/scripts/stage-effort.sh --stage <id> --observed <minutes>`, which resolves the override,
falls back to this table, multiplies, rounds, and prints the finished duration — so the sites agree
structurally, and no multiplier value ever reaches an agent.

### What gets written, at each stage's completion

1. **Append one entry to `stage_effort`** — an append-only log — with `stage`, the rounded `effort`, and
   `at` (the stage-completion timestamp, ISO 8601). The pair `(stage, at)` is the entry's stable identity.
2. **Add the increment to `actual_effort`** — the accumulated total is the sum of every `stage_effort`
   entry's `effort`. (Because each entry is already rounded to 15m, the total lands on a 15-minute boundary
   too.)

Both writes land in the **same `metadata.yaml` edit** that advances the stage, so — where a tracker sync is
configured — the immediate-sync trigger (policy §2) carries the new increment with the status change.

### Projection to the tracker

Whether and how these increments are projected to an external tracker is governed by the
[Tracker Binding](#tracker-binding) (its *Projection triggers & sync discipline* subsection for the trigger,
and the bound `/sync-*` skill for the per-stage worklog mapping and idempotency rules) — including whether any
projection happens at all. This section takes no position on the tracker stance; it owns only *what* is
recorded in `metadata.yaml` and *when*. Follow whatever that binding
specifies.

### Archive no longer computes it

Because the total is accumulated as the spec advances, the **archivist does not compute `actual_effort`
from git history**. At archive it appends its own `archive`-stage increment like any other stage; the value
that reaches the archived `metadata.yaml` is the accumulated running total, unchanged by any git-log
calculation.

---

## Ticket Type: `epic` (decomposition parent)

`epic` is a **structural** value in the `metadata.yaml` `type` enum
(`feature | bug | tech-debt | security | documentation | epic`). The other five classify a single unit of
work; `epic` marks a **tracking parent that owns no implementation of its own**.

**Decision rule — assign `type: epic` when BOTH hold:**
1. the ticket has **`decomposed_into:` links** (a populated child track — mirrored by each child's
   `decomposed_from:` and by `related_tickets.child_decomposition`), **and**
2. it has **no implementation of its own** — it ships no source/test changes; its acceptance is the rollup
   of its children landing (its `spec.md`, if any, is a coordination/rollup spec, not a unit design).

If only one holds it is **not** an epic: a ticket with child links *and* its own code is a normal typed
ticket that also spawned follow-ups; a ticket with no implementation *and* no `decomposed_into` is just
unstarted, a spike, or documentation.

**When it is assigned — at decomposition, not initial triage.** An incoming issue is first classified as
one of the five leaf types from its own evidence (the triage-agent does not pick `epic` for a fresh
issue). A ticket is **promoted to `epic` only when it is decomposed** — by the decomposition / `/claire-elicit`
handoff, or by a re-triage that splits it into a child track and moves the implementation to the children.
**The agent that populates `decomposed_into` sets `type: epic` in the same operation.** If a decomposition
is ever collapsed back into one implementable ticket, the type reverts to the appropriate leaf type.

**Why a distinct type (not just inferred from `decomposed_into`).** Making it explicit lets every consumer
— gates, metrics, the tracker projection — treat parents differently from leaves without re-deriving the
relationship: e.g. an epic is sized as its child-track **critical path**, not a single `scope` bucket (see
Effort Estimation above), and it is exempt from per-unit implementation checks.

**Tracker projection — governed by the binding, not here.** How a `type: epic` ticket projects to an external
tracker (issue type, estimate, links) is defined by the [Tracker Binding](#tracker-binding) and the bound
`/sync-*` skill's projection mappings — not by this document. A sync **must not guess** a projection for a
`type: epic` ticket: if the binding's skill leaves it unmapped, report it as an unmapped type and stop rather
than defaulting it to a generic issue type.

---

## Mandatory Facets (3 always-on + 2 triggered)

These 3 always-on facets are pre-selected and pre-customized for every project in this org. The LLM must include them in every `FACET_LIBRARY.md` it generates. It may tighten the measures or add anti-patterns, but must not remove or weaken them.

Two more facets — **Data Integrity** and **Backwards Compatibility** — are triggered mandatory. Data Integrity must be included whenever the system captures, manipulates, or persists data it owns; Backwards Compatibility whenever the change touches a **registered surface** -- resolved across every registry present (`docs/policies/surface-registry.md`, yours; `docs/policies/claire-surfaces.md`, CLAIRE's own, if you adopted at or after v4.0.0) -- or introduces a new public surface. Both fail closed: when in doubt, include them. See the [Triggered Mandatory Facets](#triggered-mandatory-facets) section below.

### Facet 1: Simplicity (Mandatory)

**Definition:** The system should have the fewest moving parts necessary to deliver the required capability.

**Zachman alignment:** How (Process), What (Data)

**Org-specific measures:**
- Runtime service count: target is the minimum needed. Every new service carries fixed overhead (deployment manifest, health check, secret path, alerting). Make that overhead visible when proposing a new service.
- State management layers: target 1. Frontends use a single client-side cache (e.g., React Query, SWR). Backends treat the database as the single source of truth — no application-level caches unless proven necessary by profiling.
- Lines of configuration to add a new capability: target <100. If adding an endpoint, a UI view, or a CLI command requires modifying more than 3 files, the architecture has too much ceremony.
- Build step count in CI: target 3-5 jobs. If the pipeline exceeds 8 jobs, consolidate.

**Org-specific anti-patterns:**
- Adding a cache layer "for performance" without profiling first — most workloads at this org are well-served by the primary datastore with proper indexes.
- Creating a shared utility library for functions used in only one project — extract to a shared package only when 2+ projects depend on it.
- Abstract factory patterns for config that will only ever have one implementation.

**Decision rule:** When choosing between two approaches, pick the one that a new team member (or AI coding agent) can understand by reading fewer files.

---

### Facet 2: Operability (Mandatory)

**Definition:** The system must be deployable, observable, and recoverable by the team that built it, using the org's standard infrastructure.

**Zachman alignment:** Where (Network), When (Timing), Why (Motivation)

**Org-specific measures:**
- Time from `git push` to running in dev: target <10 minutes. The CI pipeline should use the org's shared templates — not custom scripts that duplicate template functionality.
- Secrets: all secrets via the org's secrets manager. Zero secrets in environment variables, `.env` files, or container build args (use build-time secret mounts).
- Health check: every deployable service exposes a health endpoint that checks all dependencies (DB connectivity, external service reachability). The deployment system uses this for readiness probes.
- Logging: structured JSON to stdout. The log collector picks it up automatically. No custom log file paths unless the runtime requires it. Every log line must include trace ID, span ID, and request ID for cross-service correlation.
- Distributed tracing: all inter-service calls propagate W3C Trace Context headers. Traces must be visible in the org tracing backend. New service-to-service integrations require trace propagation before go-live.
- Metric emission: every new API endpoint emits request count, latency histogram (p50/p95/p99), and error rate metrics. Use standard metric naming conventions.
- Alert coverage: every new external dependency or critical code path has an alert rule (latency > threshold, error rate > threshold). Changes affecting request paths must be observable on the oncall latency dashboard.
- Environment & asset parity: every declarative reference to an externally-served asset or resource (fonts/glyphs/sprites/tiles, CSS font stacks, CDN URLs, env-specific hostnames, DB features/extensions, feature flags) must resolve against the target deployment's actual inventory — especially under an offline/air-gapped or self-hosted invariant. An asset a third-party engine *defaults to* but the environment does not serve is a deployment failure that unit fakes will not catch.
- Rollback: a documented, single-action rollback path (e.g., redeploy previous artifact). Rollback procedure must be documented in the spec and tested before go-live.
- Observability seams: every new behavior derived from SCOUT analysis has corresponding seam events specified in the spec's Observability Seams table. For components with prior entries in `docs/agentic-sdlc/production-insights.md`, seam coverage is mandatory. See `docs/policies/observability-patterns.md` for the four standard patterns (IMPOSSIBLE_STATE, LINEAGE_GAP, DECISION_DRIFT, SEAM_VIOLATION).

**Org-specific anti-patterns:**
- Custom CI scripts that duplicate functionality already in the shared templates (e.g., writing your own container build job instead of extending the shared template).
- Secrets in compose files or `.env.example` that contain real values (even for dev).
- Log messages that are unstructured strings requiring regex to parse downstream.
- Log lines missing trace/request correlation IDs — every log entry must be joinable to its distributed trace.
- New endpoints without latency and error rate metrics — if it can't be observed, it can't be debugged in production.
- New external dependencies without health-check integration and alerting — silent failures in dependencies are a common oncall incident source.
- Observability added "later" as a follow-up ticket — it ships with the feature or the feature doesn't ship.
- Missing observability seams on components with prior production incidents — if `production-insights.md` has entries for a component, new work on that component without seam requirements is a process failure.
- IMPOSSIBLE_STATE assertions deferred to "later" — if the SCOUT analysis identifies preconditions, the runtime assertion ships with the feature.
- Deploying to a new port without updating the deployment manifest or the upstream proxy config.
- Declarative config (map/layer specs, ORM mappings, CSS, IaC/k8s manifests, GraphQL schemas) that references an asset or relies on an engine default the target environment does not provide — the gap is an omission, not a wrong line, and shared-assumption fakes keep the suite green.

**Decision rule:** If a feature requires a new ops procedure or lacks observability coverage (logging, tracing, metrics, alerting), it is not ready to deploy — document and flag for platform team review before implementation.

---

### Facet 3: Developer Experience — Agentic Coding (Mandatory)

**Definition:** The codebase must be optimized for AI-assisted development. AI coding tools are first-class contributors. The architecture must maximize the probability that an agent produces correct code on the first attempt.

**Zachman alignment:** How (Process), What (Data)

**Org-specific measures:**
- File size: target <400 lines. Agents lose accuracy and context past roughly that size.
- File size, scenario-indexed BDD test harnesses — if your repo keeps test harnesses that
  index one test function per behavioural scenario, name their glob here and govern them per
  function rather than per file: no whole-file ceiling, every scenario function ≤150 lines,
  every function including helpers ≤400 lines, and fixture data carrying no line measure.
  If a harness in your repo grows past a readable single file and its scenarios move into
  modules the entry point sources, name THAT glob here too, whatever your repo calls those
  directories. A harness is its entry point together with the scenario modules that entry
  point sources: one artifact, one measure. Naming only the entry-point glob puts the
  sourced modules back under the whole-file ceiling the split was performed to satisfy.
  - WHY this is a carve-out and not an exemption of convenience: a scenario-indexed
    harness's single-file shape is actively rewarded by this facet's other measures —
    reading fewer files to make a correct change, and producing a new instance from one
    example — so splitting its scenarios away from the resolver they exercise would
    satisfy a line count by worsening the facet's own goal. State the reason beside the
    clause; an exemption whose reason is not written down is read as convenience.
  - SCOPE: name the globs this bullet governs and rule on those globs only. Choose both numbers against your own
    measured distribution, not by copying these: a ceiling nothing meets reproduces the
    defect at a new number, and one everything clears by a wide margin is decoration.
- CLAUDE.md present: every repo must have a `CLAUDE.md` at the project root documenting architecture, commands, gotchas, and testing patterns. Use `.claude/rules/*.md` for topic-scoped guidance that auto-loads based on file paths being edited.
- Type coverage: 100% for typed-language projects (TypeScript strict mode, equivalent). For dynamic languages, type hints on all public function signatures with a type checker in CI.
- Pattern consistency: every instance of a repeated structure (API endpoint, UI view, test file, DB migration) follows an identical template. An agent adding a new instance should need to read exactly 1 existing example to produce a correct copy.
- Naming conventions: one convention per language, no exceptions. Document the choice in `CLAUDE.md`.

**Org-specific anti-patterns:**
- A single "god file" that handles multiple concerns (routing + validation + DB + response formatting). This is the primary reason agents produce incorrect code — they can't isolate the change target.
- Dynamic imports, metaprogramming, or monkey-patching that hides the call graph from static analysis.
- Implicit conventions documented only in chat or wiki — if it affects how code is written, it belongs in `CLAUDE.md` or `.claude/rules/`.
- Test fixtures defined in a shared file that's grown past 500 lines — split by feature area.

**Decision rule:** When an agent would need to read more than 5 files to understand how to add a new capability, the architecture has too much indirection — reduce it.

---

## Triggered Mandatory Facets

### Facet 4: Data Integrity (Triggered Mandatory)

**Activation rule:** This facet is mandatory whenever the system captures, manipulates, or persists data it owns — a database, a file store, a ledger, an audit log, or any owned record of user-provided input. Evaluate this at Zachman grounding (the What interrogative). When in doubt, active — the cost of an "N/A" evaluation is low; the cost of a missed unaudited mutation is high. Third-party-embedded data (a hosted form, an embedded payment or analytics widget) is in-doubt-therefore-active unless the integration is explicitly registered as fully delegated — i.e. the third party is the sole system of record for that data and this system neither persists nor derives from it. If the system captures/persists no owned data, mark "Data Integrity: Not triggered — the system captures/persists no owned data" and skip the evaluation.

**Definition:** Every mutation must be auditable and consistent with the system's data contracts. Audit trail requirements (compliance, debuggability, user-facing change history) all flow from this facet.

**Zachman alignment:** What (Data), When (Timing), Who (People)

**Org-specific measures:**
- Audit coverage: 100% of write operations must produce an audit record. For SQL databases, this means an event log table or database-level triggers. For document stores, this means a change history field or a separate audit collection.
- Mutation metadata: every write must capture the identity of the actor (from the IdP / proxy headers — never from user input) and the reason for the change (user-provided where applicable).
- Multi-table write sequencing: when a user action triggers writes to 2+ tables, the spec must document the step order, what happens if an intermediate step fails, and which query caches are invalidated on success.
- No client-side computation submitted to the API: the frontend sends what the user entered; the server computes derived values. This prevents divergence between what the user saw and what was stored.
- Cache-to-source consistency: after every mutation, the relevant caches (client-side query caches, server-side caches, CDN) must be invalidated — not manually patched.

**Org-specific anti-patterns:**
- Fire-and-forget multi-step mutations where a later step can fail silently, leaving the data in a partial state with no indication to the user.
- Optimistic updates for multi-table writes — only use optimistic updates for single-field, single-table edits where rollback is trivial.
- Missing the actor or reason field in a mutation payload — if the API accepts the write without audit metadata, that's an API bug, not a frontend shortcut.
- Deleting or archiving records without a confirmation step that shows the user what will be affected (especially when cascading to child records).

**Decision rule:** When in doubt about whether to show a loading spinner or use an optimistic update, show the spinner. Perceived speed is a luxury; audit correctness is a durable requirement.

---

### Facet 5: Backwards Compatibility (Triggered Mandatory)

**Activation rule:** This facet is mandatory whenever the change touches, modifies, or removes a **registered surface** -- resolved across **every** registry present per `docs/policies/change-tiers.md`'s *Resolving "registered surface"* rule: `docs/policies/surface-registry.md` (yours, adopter-owned) and, if you adopted at or after v4.0.0, `docs/policies/claire-surfaces.md` (CLAIRE's own, core-owned) -- or introduces a new API endpoint, event schema, DTO contract, or configuration key that will be consumed by another service. If the change is entirely internal (no registered surfaces affected, no new public surfaces introduced), this facet may be omitted. When in doubt, include it — the cost of a "N/A" evaluation is low; the cost of a missed breaking change is high.

**Definition:** Public surfaces — APIs, events, schemas, and configuration contracts — must remain backwards-compatible for their documented guarantee period. Breaking changes require a deprecation lifecycle with consumer signaling, migration documentation, and compatibility tests.

**Zachman alignment:** How (Process), What (Data), When (Timing)

**Org-specific measures:**
- Public Surface Registry: `docs/policies/surface-registry.md` exists and is current. (If you adopted at or after v4.0.0 the core-owned `docs/policies/claire-surfaces.md` sits beside it, holding CLAIRE's own surfaces; it is maintained by core upgrades and is **not** yours to fill in, but a "registered surface" resolves across both.) Every public API endpoint, event schema, shared DTO, and configuration contract consumed by another service is registered with a stability level and guarantee period.
- Compatibility guarantee: all surfaces marked **Stable** in the registry carry a minimum guarantee period (see [Deprecation Policy](../policies/deprecation-policy.md)). No stable surface removed or semantically changed without completing the full deprecation lifecycle.
- Breaking change detection: every spec evaluates its changes against the surface registry in a "Compatibility Impact" section. Breaking changes are classified (additive / modification / removal) with explicit deprecation plans.
- Deprecation signals: deprecated surfaces emit runtime signals — HTTP `Deprecation` and `Sunset` headers, structured log warnings, and `deprecated_surface_calls_total` metrics. Consumers discover deprecation through the API itself, not just documentation.
- Golden-file tests: every stable API response shape and event payload has a committed snapshot. CI fails if the actual output diverges from the golden file without an explicit, reviewed update.
- Consumer-driven contract tests: every inter-service dependency has a contract test written from the consumer's perspective. The producer runs the test; violations are blocking.
- Versioned integration tests: when multiple API versions are supported, integration tests replay requests from the previous version against the current service to verify old clients still work.
- Version support: at most current + 1 previous API version maintained concurrently. New versions triggered only by breaking changes that cannot be made additive.

**Org-specific anti-patterns:**
- Removing a DTO field without checking which services consume that response — the surface registry exists to answer this question.
- Renaming an API endpoint without versioning — consumers break silently.
- Changing event payload semantics (e.g., `null` now means "not set" instead of "all") without a version bump — syntactically invisible breakage is the hardest to debug.
- Adding a required field to an existing request contract — existing consumers will fail to validate.
- Dropping a database column consumed by another service without a coordinated migration plan.
- "We'll fix consumers later" without a tracked deprecation entry in the registry — promises without deadlines are not promises.
- Updating a golden file without reviewing the diff in the MR — golden-file changes should be scrutinized as contract changes, not rubber-stamped.

**Decision rule:** When two approaches are equivalent in all other facets, pick the one that does not require existing consumers to change.

---

## Production Feedback Loop

CLAIRE is not a one-shot specification process. Production behavior feeds back into future specifications through the living document `docs/agentic-sdlc/production-insights.md`.

### Feedback Cycle

```
Production Bug → Triage (categorize + map to SCOUT dimension) → production-insights.md
                                                                        ↓
New Feature/Fix in Same Component → Spec Author reads insights → Seam requirements added
                                                                        ↓
Implementation → Implementer adds seams via TDD → Seams detect future issues in production
                                                                        ↓
Production → Seam fires with structured signal → Next bug triaged with better context → Loop
```

### Agent Responsibilities in the Feedback Loop

| Agent | Action |
|---|---|
| **triage-agent** | Categorizes BUGs into LOGIC_FAULT / LINEAGE_GAP / DRIFT_SIGNAL / SEAM_VIOLATION; maps to SCOUT dimension; appends to `production-insights.md` |
| **spec-author** | Reads `production-insights.md` before writing a spec; adds observability seam requirements for components with prior findings; gives extra edge-case emphasis on weak dimensions |
| **implementer** | Reads insights for affected domain; implements seams alongside business logic as TDD scenarios; emits structured events per the Log Pattern Catalog |
| **archivist** | Quarterly pattern summary in `production-insights.md`; promotes recurring patterns to ADRs |

### References

- Observability Seams derivation: `docs/agentic-sdlc/scout-reference.md` (Observability Seams section)
- Log Pattern Catalog: `docs/policies/observability-patterns.md`
- Production Insights (living): `docs/agentic-sdlc/production-insights.md`

---

## Model Tier Mapping

This section declares the concrete model identifiers used by the agents in this repo's dogfooded runtime. Tier names are stable and form part of the Backwards Compatibility contract (see the Configuration Contracts row for `CLAIRE_ORG.md#model-tier-mapping` in [`docs/policies/claire-surfaces.md`](../policies/claire-surfaces.md) -- that row is **core-owned** and is not in the adopter-owned [`docs/policies/surface-registry.md`](../policies/surface-registry.md)). Concrete model identifiers are runtime-specific and may change via `/claire-bump-model`.

**This repo's runtime:** Claude Code.

### Capability Tiers

| Tier | Purpose |
|---|---|
| Deep-reasoning | Cross-artifact analysis, design trade-offs, security, architecture compliance. Carries the spec gate, code-review gate, and maintainer gate. |
| Fast-mechanical | Execution against an already-resolved contract — classification, file movement, template filling, tracker sync, and implementation of an approved spec. Carries no human gate; the judgment is bounded by a decision another role already made, not absent. |

### Tier → Concrete Model

| Tier | Concrete Model (Claude Code) |
|---|---|
| Deep-reasoning | claude-opus-5-5 |
| Fast-mechanical | claude-sonnet-5 |

### Tier → Agents

| Tier | Agents |
|---|---|
| Deep-reasoning | claire-architect, claire-explorer, claire-spec-author, claire-reviewer, claire-migration-author, claire-maintainer |
| Fast-mechanical | claire-triage-agent, claire-archivist, claire-implementer |

> **The implementer and code-reviewer do not run the same concrete model.** The implementer sits on Fast-mechanical and the code-reviewer on Deep-reasoning; treat that as a *consequence* of where each role's work sits, not as a decorrelation decision. The review gate's independence from the implementer is **structural** — the reviewer runs in isolated context and re-derives expected behavior from the spec — rather than depending on which model backs it. Splitting the code-reviewer onto a different-family model for decorrelation is deferred (no comparable-capability candidate is available in-region) and would be an architectural change to this mapping, not a `/claire-bump-model` bump. See [ADR_CLAIRE-0007](../ADR/0007-review-gate-independence-is-structural.md).

### Adopter substitution

If you run CLAIRE on a different agentic-coding runtime, substitute the concrete-model column with your runtime's model identifiers. Keep the tier names and agent assignments unchanged unless you have a documented reason to remap (record it as a decision in your repo's `decisions.md`).

The `/claire-bump-model` skill updates the concrete-model column when you bump a model version. The skill refuses cross-tier substitutions — those are architectural choices that warrant a spec, not a version bump.

---

## Runtime Binding

The single mandatory home for **runtime coupling** (ADR_CLAIRE-0008 clause 4) — the runtime-axis analog of the Model Tier Mapping above. Fill in your runtime(s); keep the RC-* rows. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#runtime-binding`). All framework artifacts are authored against the abstract Runtime Capability Contract (RC-1…RC-6); concrete primitives are confined to this section (the runtime-primitive CI sweep enforces that).

**Bound runtime(s):** `<your runtime(s) — e.g. Claude Code; or OpenCode-primary + an external review model>`

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

- `<where compiled roles land>`, `<where compiled commands land>`, `<runtime config file>`.
- `<the adapter/compile command that emits them from the neutral source>`.

### Role → (runtime, capability-tier) assignment (clause 6)

Assign each role to a `(runtime, tier)` pair. A project may run most roles on one runtime and bind the **review roles (code-reviewer, maintainer) to an independent, stronger model/runtime** — making ADR_CLAIRE-0007 gate independence *physical*, not merely contextual. A same-runtime, same-model review binding is a portability-and-governance exception that must be justified at maintainer review.

| Roles | Runtime | Tier |
|---|---|---|
| `<implementation / authoring roles>` | `<runtime>` | Deep-reasoning |
| `<review roles: code-reviewer, maintainer>` | `<independent runtime / model>` | Deep-reasoning |
| `<mechanical roles: triage, archive>` | `<runtime>` | Fast-mechanical |

---

## Tracker Binding

The single mandatory home for external work-item **tracker coupling** (ADR_CLAIRE-0010 clause 2) — the tracker-axis analog of the Runtime Binding above. Fill in your tracker(s); keep the resolution rule. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#tracker-binding`). Framework prose names "the repo's bound tracker"; the concrete choice is confined to this section.

Declare your tracker(s) as **rows of the *Per-prefix tracker bindings* table below** — that table is this section's only declaration form. A repo-wide `**Bound tracker(s):**` line was the former form and was REMOVED (BTG-242); a file that still carries one HALTs `tracker.binding.form_removed`. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

### TS-* capability → concrete sync skill

| TS | Capability | Your binding |
|---|---|---|
| TS-1 | Work-item sync (spec metadata + status → tracker; repo→tracker, one-directional) | `<your /sync-* skill — e.g. /claire-sync-jira>` |

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

- A sync **resolves** its target tracker from this section — the ticket-id prefix's row in *Per-prefix tracker bindings* → the matching `TS-1` skill mapping. Name match is case-insensitive and trimmed; prefix matching is case-exact.
- **No `#tracker-binding` declaration ⇒ FAIL LOUD** with an actionable error ("no tracker bound; declare one in `CLAIRE_ORG.md#tracker-binding`"). Never default to a tracker; never silently no-op. A per-prefix table with **no data row** — the shape this template ships — declares nothing and is exactly this case (`tracker.binding.table_missing`). An un-substituted placeholder (this template's `<...>` markers still present) in a cell is likewise treated as no binding.
- A `**Bound tracker(s):**` line, the REMOVED repo-wide form, ⇒ HALT (`tracker.binding.form_removed`) whatever the table says. The check runs BEFORE any row is read.
- **Bound tracker mapped to an UNINSTALLED skill ⇒ FAIL LOUD** naming the missing skill; a declared tracker with no `TS-*` mapping fails loud naming the unmapped tracker. Never a silent fallback.
- **AUDIT:** record the resolved tracker + its binding source + the mapped skill **before** contacting the tracker, so the selection is traceable and a wrong-tracker write is visible up front.
- UNMATCHED PREFIX => the single keyless inner-source WILDCARD row (`*`) if declared, else FAIL LOUD. Never another row, never a removed declaration, never a guessed tracker. This is the **EXPLICIT INVERSE** of the Id Allocation Binding's unmatched-prefix rule — do **NOT** copy that section's polarity here.

### Connection config

Tracker connection details (base URL, project key, credentials) are **not** declared here — they stay in the `/sync-*` skill + `metadata.yaml` + env/MCP (declarative name→skill lookup only).

### Projection triggers & sync discipline

The tracker-vendor-neutral "when to sync" contract every syncing skill/agent/hook resolves (homed here by BTG-024; the vendor-specific mechanics live in your bound `/sync-*` skill). Keep these clauses; they do not change per tracker.

- **Trigger classes:** **IMMEDIATE** — any change to any field of a `specs/<id>/metadata.yaml` (or `archive/<id>/metadata.yaml`) owes a sync in the same session; **END-OF-OPERATION** — a `problem.md` / `spec.md` / `test-plan.md` change owes one sync at the operation's end.
- **Status-lifecycle subset:** the canonical `status` transitions (`triaged` → `spec-in-review` → `spec-approved` → `in-progress` → `in-review` → `merged` → `archived`) each owe an IMMEDIATE sync — named vendor-neutrally as "run the bound `/sync-*` skill". A transition to `cancelled` — the terminal-without-merge branch off that line, from whichever state the ticket stopped in — owes the same sync on the same terms.
- **Orchestration boundary:** subagents write artifacts + set `status` but run **no** sync; the orchestrating main-turn skill owns the sync after the subagent returns.
- **Enforcement:** agent/skill discipline is primary (it runs the sync); the two `tms-*` backstop hooks detect a missed sync (they cannot run it) and resolve fire-vs-inert from the ticket prefix's row in *Per-prefix tracker bindings* above.
- **"What synced means":** the bound `/sync-*` skill completed and reported success for the ticket this session; a sync that cannot complete is surfaced, never silently skipped.
- **A row resolving to `None — inner-source` (including the `*` wildcard row) ⇒ every trigger is a declared SKIP** for that prefix (no external write; backstop hooks inert).

---

## Id Allocation Binding

The single mandatory home for ticket **identity / id-allocation coupling** (ADR_CLAIRE-0011 clause 4; ADR_CLAIRE-0010 clause 2) — the identity-axis analog of the Tracker Binding above. Fill in your allocator (or leave the closed default). Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#id-allocation-binding`). Framework prose resolves the bound tracker for a seed-read from `#tracker-binding` vendor-neutrally; the concrete choice is confined to that section.

Declare your allocator(s) as **rows of the *Per-prefix allocator bindings* table below** — that table is this section's only declaration form. A repo-wide `**Bound allocator(s):**` line was the former form and was REMOVED (BTG-242); a file that still carries one HALTs `idalloc.binding.form_removed`. The repo-wide `id_scheme:` field below is a DIFFERENT field, is **retained**, and must stay. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

### IA-* capability → concrete allocator

| IA | Capability | Your binding |
|---|---|---|
| IA-1 | Ticket id allocation + tracker-originated seed-read | `<your allocator, or "n/a — closed default; triage mints by convention">` |

### id_scheme

- **id_scheme:** `<PROJECT-KEY>-NNN` — the recognizable shape of a tracker-reserved id. A `/claire-triage` argument matching this scheme with **no** `specs/<id>/` is a tracker-originated seed-read candidate.

### Per-prefix allocator bindings

*THE ONLY DECLARATION FORM (BTG-179, sole form since BTG-242), parallel in shape to the Tracker Binding's. A row's `reserve-from-tracker` allocator resolves its concrete adapter from **THE SAME PREFIX'S tracker-binding row**, vendor-neutrally, never hardcoded.*

*This table SHIPS EMPTY (header only), and — **unlike the Tracker Binding's** — an empty one does **NOT** fail loud. Every prefix is then unmatched, and an unmatched prefix MINTS. That asymmetry is deliberate: a missing tracker binding could mis-route a sync, while a missing allocator binding is the byte-identical legacy behavior of every repo that never declared one.*

| Ticket prefix | Bound allocator | id_scheme |
|---------------|-----------------|-----------|

### Resolution rule  (NOTE: the absent-default is the INVERSE of the Tracker Binding)

- ABSENT (no per-prefix row matches the ticket prefix, including a table with no rows at all) / un-substituted PLACEHOLDER / `None — closed default` => MINT BY CONVENTION (the closed default). On this path CLAIRE mints ticket ids from the **local collision-safe allocator** (`/claire-mint`, PI-039): `/claire-triage` obtains each id via `mint-id.sh --reserve <ticket-prefix>` against a shared, flock-atomic reserve ledger (git-common-dir), so parallel worktrees never collide. ADR/II/PROD ids are **always** minted locally regardless of this binding; only the **ticket** prefix defers to a declared external allocator below.
- **Polarity note:** the bullet above is the **EXPLICIT INVERSE** of `#tracker-binding`'s "absent ⇒ FAIL LOUD". A missing id-allocation binding is **not** an error — it is the byte-identical legacy behavior (your repo mints ids by convention as before). **Do NOT copy the Tracker Binding's fail-loud default here.**
- DECLARED allocator + `id_scheme` => a `/claire-triage <PROJECT-KEY>-NNN` with no `specs/<id>/` triggers a **governed, one-time, non-authoritative** seed-read (ADR_CLAIRE-0011 cl.2): record the selection, read the tracker summary once, write the provenance markers (`## Source:` block in `problem.md` + `originated_from_tracker:` / `seed_read_at:` in `metadata.yaml`). A non-matching argument falls through to mint.
- The bound tracker for the seed-read is **RESOLVED FROM `#tracker-binding`** (vendor-neutral) — never hardcoded.
- **AUDIT:** record the resolved allocator + id + binding source **before** contacting the tracker.
- UNMATCHED PREFIX (no row in the per-prefix table) => MINT BY CONVENTION — the closed default, and the **EXPLICIT INVERSE** of the Tracker Binding's unmatched-prefix FAIL LOUD. Do **NOT** copy that section's polarity here. Nothing is reported: this is not a degraded answer, it is THE answer. ADR / II / PROD numbering stays independent of this section and consults no prefix row.

### Reservation pairing (the allocation obligation)

- SCOPE — **TICKET ids only.** This clause governs the allocation of a ticket id: a tracker `reserve` on a reserve-from-tracker binding, or a convention mint of the **ticket** prefix via the allocator sidecar. **ADR / II / PROD numbering is §10-INDEPENDENT** (always minted locally, even by a tracker-bound adopter) and carries **NO** pairing obligation — those ids have no `specs/<id>/` by design, so an unpaired ADR / II / PROD id is CORRECT, never the defect state below.
- A TICKET-id ALLOCATION is PAIRED, within the SAME governed operation, with the creation of `specs/<id>/problem.md` and `specs/<id>/metadata.yaml`.
- A TICKET-id allocation left unpaired is the named defect state `idalloc.reserve.unpaired_artifact_creation`. It is a defect, never an accepted outcome.
- The obligation is DECLARED before the tracker is contacted (extends the AUDIT record-before-contact rule above) and DISCHARGED by the operation that allocated.
- This clause is the CANONICAL statement of the pairing rule. Adapter and skill prose CITE it; none restates it.
- LIMITATION (honest, no-runtime): this is prompt-ordering plus a structural gate, not a transaction — the same limitation the Tracker Binding's per-item audit records for itself.

---

## Sprint-Enforcement Binding

The single mandatory home for the **`/claire-implement` sprint-enforcement contract** (BTG-004; homed here by BTG-024) — a per-repo config binding parallel to the Tracker and Id Allocation bindings above. The `/claire-implement` sprint-enforcement guard reads it before implementation begins. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#sprint-enforcement-binding`).

Declare enforcement as **rows of the *Per-prefix sprint-enforcement bindings* table below** — that table is this section's only declaration form. The three repo-level `sprint-enforcement-enabled` / `sprint-check-skill` / `sprint-check-fallback` HTML markers were the former form and were REMOVED (BTG-242); a file that still carries any of them HALTs `sprint.binding.form_removed`. Deleting them is safe: a prefix with no row now resolves DISABLED **by rule**, which is what an absent or `no` marker already meant. See [`docs/migrations/scalar-binding-removal.md`](../migrations/scalar-binding-removal.md).

| Field | Value | Meaning |
|-------|-------|---------|
| `sprint_enforcement_enabled` | `<No \| Yes>` | No ⇒ no tracker query; guard takes the Confirm path. Yes ⇒ guard queries the bound tracker. |
| `sprint_check_skill` | `<n/a \| the bound /sync-* skill>` | (when enabled) the skill the guard defers to — resolved from `#tracker-binding`, never hardcoded. |
| `sprint_check_fallback` | `<n/a \| Block \| Confirm>` | (when enabled) the verdict applied when the sprint check is inconclusive. |

**Resolution rule:** a prefix with **no row**, or a row whose enablement is malformed in the ways named below, resolves to **DISABLED** (the Confirm path) — fail-safe-toward-disabled / opt-in. Only an explicit `Yes` on a prefix's row enables the tracker query. The guard runs on **every** `/claire-implement` invocation at **all tiers** (not subject to the Trivial/Low integration-branch exemption).

### Per-prefix sprint-enforcement bindings

*THE ONLY DECLARATION FORM (BTG-179, sole form since BTG-242). Add one row per ticket-id prefix that wants the guard. This table SHIPS EMPTY (header only), and an empty one resolves DISABLED for every prefix — which is the state a new repo should be in.*

*This section still differs IN KIND from the Tracker and Id Allocation bindings: a prefix WITHOUT a row is answered by a RULE (DISABLED, fallback Confirm), not by a halt and not by a mint. There is no wildcard row here and no repo-wide switch, deliberately — a mandatory wildcard would make an unmatched prefix fail loud, which is the Tracker Binding's polarity imported into this one. A prefix only needs a row when it wants something the rule does not already give it.*

| Ticket prefix | `sprint_enforcement_enabled` | `sprint_check_skill` | `sprint_check_fallback` |
|---------------|------------------------------|----------------------|-------------------------|

*A row's `sprint_check_skill` cell is a POINTER, not a value: write "resolved from `#tracker-binding`'s `<PREFIX>` row". The sprint-check skill and the sync skill MUST be the same adapter for a given prefix, and naming one here independently is how the two come to disagree.*

#### Per-prefix resolution (BTG-179; the ONLY form since BTG-242)

These bullets are how every resolution of this section is performed; they no longer qualify a second form, because there is no second form.

- ANY of the three removed `sprint-*` HTML markers present in this section => HALT (`sprint.binding.form_removed`), checked BEFORE any row is read, on the marker's PRESENCE and never on its value.
- MATCHED PREFIX, `Yes` => ENABLED for that prefix; the skill is resolved from that same prefix's `#tracker-binding` row, never hardcoded, and the fallback is that row's own verdict.
- MATCHED PREFIX, `No` => DISABLED for that prefix (the Confirm path).
- MATCHED PREFIX, `Yes`, on a prefix bound to no tracker => HALT (`sprint.binding.enabled_without_tracker`) — sprint enforcement is a tracker QUERY and there is nothing to query. A typed statement of intent that cannot be honoured is REFUSED, never quietly downgraded.
- MATCHED PREFIX, any other value => HALT (`sprint.binding.marker_unrecognized`). `disabled` is the safe reading of "we cannot tell", not of "you said something we do not understand".
- UNMATCHED PREFIX => **DISABLED, by this rule**: `enabled=no`, `skill=n/a`, `fallback=Confirm`, `source=default`, exit 0, and NOTHING reported. This is this section's own polarity stated directly; it is **neither** `#tracker-binding`'s FAIL LOUD **nor** `#id-allocation-binding`'s MINT — do **NOT** copy either here. `fallback` is reported even while DISABLED, because disabled is not the absence of a verdict.
- **RETIRED with the markers (BTG-242):** the *inherited repo-level `yes`* degrade and its diagnostic. There is no repo level left to inherit from. The EXPLICIT contradiction — a typed per-prefix `Yes` on a trackerless prefix — still HALTs, above.

---

## Integration-Branch Enforcement Binding

The single mandatory home for the **`/claire-implement` integration-branch enforcement contract** (BTG-028) — a per-repo config binding parallel to the Sprint-Enforcement Binding above. The `/claire-implement` integration-branch preconditions (BTG-001's P1/P2 — and the `claire-implementer` role's Phase 0 mirror on direct delegation) read it, for a **Medium/High** ticket only, **before** evaluating P1/P2. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#integration-branch-enforcement-binding`).

<!-- integration-branch-enforcement-enabled: yes -->
<!-- ^ The integration-branch enforcement contract the /claire-implement P1/P2 gate (and the
     implementer Phase 0 mirror) reads. This template ships the SAFER DEFAULT — enabled=yes —
     so a new adopter inherits the gate ON (it protects the spec-approval boundary). enabled=yes
     => the Medium/High gate runs BTG-001's P1/P2; enabled=no => the gate is skipped for your
     repo. An ABSENT / EMPTY / un-substituted PLACEHOLDER / unrecognized marker FAILS LOUD
     (never a silent default) — so leave a concrete yes/no here, NOT a placeholder token. Keep
     this marker in sync with the table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `integration_branch_enforcement_enabled` | **Yes** | adopter default ON — the Medium/High integration-branch gate runs BTG-001's P1/P2. Set to `No` if your topology has no shared integration branch. |

**Resolution rule (Medium/High only; Trivial/Low are tier-exempt and do NOT read this binding):** resolve `integration-branch-enforcement-enabled` **before** P1/P2 — `yes` → run BTG-001's P1/P2; `no` → skip both (labeled notice, no P1/P2); **ABSENT / EMPTY / un-substituted PLACEHOLDER / any unrecognized value → HALT (fail-loud)** naming the binding. Never silently default on or off.

**POLARITY NOTE (the Sprint-vs-Integration-Branch trap):** this binding's absent-value default is the **EXPLICIT INVERSE** of the Sprint-Enforcement Binding's. A missing sprint-enforcement marker resolves to DISABLED; a missing integration-branch-enforcement marker **FAILS LOUD** — silently dropping a safety gate is worse than a one-line prompt. Do **NOT** copy the Sprint-Enforcement Binding's absent⇒disabled default here.

---

## Branch-Strategy Binding

The single mandatory home for the repo's **branch-strategy selection + its configurable properties** — a per-repo config binding parallel to the Tracker / Id-Allocation / Sprint-Enforcement / Integration-Branch Enforcement bindings above. Every SDLC skill/agent that needs the integration-branch name, its protection status, or the branch-naming convention resolves them from this section (ADR_CLAIRE-0020, which **supersedes** ADR_CLAIRE-0016's `branch-strategy.md`-authoritative resolution order). Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#branch-strategy-binding`). The bound strategy document supplies the role narrative only; it names no branch.

<!-- bound-strategy: long-lived-feature-release -->
<!-- integration-branch: develop -->
<!-- integration-branch-protected: yes -->
<!-- branch-naming-convention: {phase}/{type}/{id} -->
<!-- ^ The branch-strategy contract every "is this merged?" / diff-base / branch-naming
     consumer reads (ADR_CLAIRE-0020). This template ships a CONCRETE default (long-lived /
     develop / protected) — NOT a placeholder token — so a new adopter inherits a working
     binding out of the box; change bound-strategy to `trunk-based` and rename
     integration-branch to your integration branch if your topology differs. An ABSENT /
     EMPTY / un-substituted PLACEHOLDER `bound-strategy` or `integration-branch` FAILS LOUD
     (never a silent default) — so leave a concrete value here, NOT a placeholder. Keep
     these markers in sync with the table below. -->

| Field | Value | Meaning |
|-------|-------|---------|
| `bound-strategy` | **long-lived-feature-release** | resolves to `docs/policies/branch-strategy/long-lived-feature-release.md` (the role narrative) |
| `integration-branch` | **develop** | the branch "is this merged?" resolves against — rename to your integration branch |
| `integration-branch-protected` | **yes** | no direct commits; every change reaches it via an MR |
| `branch-naming-convention` | **{phase}/{type}/{id}** | machine-readable pattern; full narrative in the bound doc |

**Resolution rule:** a consumer resolves the four fields from the markers/table above; the bound strategy document (`docs/policies/branch-strategy/<bound-strategy>.md`) provides the role narrative only. **ABSENT / EMPTY / un-substituted PLACEHOLDER `bound-strategy` or `integration-branch` → HALT (fail-loud)** naming the binding (preserves ADR_CLAIRE-0016 clause-3 fail-closed); a `bound-strategy` naming a doc that does not exist under `docs/policies/branch-strategy/` also fails loud. **AUDIT:** the resolved integration-branch name is echoed in every skip/halt/proceed message so resolution is traceable.

**Not in scope at v1:** a third/Nth strategy document; a CI gate verifying `integration-branch-protected` against the forge's actual branch-protection state; forge-API connection config.

---

## Test-Scope Binding

The single mandatory home for the **test-scope enforcement contract** (BTG-203) — a per-repo config binding parallel to the bindings above. The three roles governed by `docs/policies/test-scope.md` — `claire-implementer`, `claire-reviewer` and `claire-spec-author` — read it **before** enforcing that policy, to decide whether the rule reaches your repository at all. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#test-scope-binding`).

The question it answers is the policy's own scoping clause made machine-readable: *are your governance documents a description of your product, or are they the product?* For almost every adopter the answer is the former, which is why the default is ON.

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
| `test_scope_enforcement_enabled` | **Yes** | adopter default ON — a test whose subject is a governance document is a blocking review finding. Set to `No` only if your product **is** the governed document corpus. |

**Resolution rule:** resolve `test-scope-enforcement-enabled` before enforcing anything — `yes` → the test-scope policy is ENFORCED for your repository; `no` → it is NOT ENFORCED, and a test whose subject is a governance document is legitimate here. An **ABSENT**, **EMPTY**, **un-substituted PLACEHOLDER**, or otherwise **UNRECOGNIZED** value resolves to **NOT ENFORCED**; on the unrecognized case, resolve NOT ENFORCED **and report why**, so a typo degrades loudly rather than into a guard that is off and looks on. No ambiguous value ever resolves to ENFORCED, and none halts.

**POLARITY NOTE (which sibling's default this binding does and does not inherit):** this binding's absent-value default is the **Sprint-Enforcement Binding's, not the Integration-Branch Enforcement Binding's**. A missing marker resolves to NOT ENFORCED — fail-safe-toward-disabled. It **DOES NOT** inherit the integration-branch binding's absent⇒HALT polarity, and copying that here would be a defect rather than a tightening: a repository upgrading from a CLAIRE version that predates the org-fold epoch never receives this appended template section at all, so a HALT-on-absent rule would stop `/claire-implement` in every such repository at once. The consequence for you is the one to state plainly: because this section ships the concrete value `yes`, a repository that RECEIVES it is ENFORCED from that moment, including an already-adopted repository that receives it through a bare `/claire-upgrade`'s org-fold, with no declaration required. If your repository deliberately maintains prose-guard tests, you turn the rule **off** by declaring `no`. The absent-value default above governs only a repository that never receives this section at all.

---

## Version-Scheme Binding

The single mandatory home for the repository's **version-scheme selection and the properties derived from it**, a per-repo config binding parallel to the bindings above. Every consumer that needs to know how your repository numbers a release, what spelling of a version string is legal, or which cuts count toward a "release cycle" guarantee, resolves it from this section. Register it in your `docs/policies/surface-registry.md` as a Stable Configuration Contract (`CLAIRE_ORG.md#version-scheme-binding`). The bound scheme document (`docs/policies/version-scheme/<bound-version-scheme>.md`) supplies the bump vocabulary and the next-version rule only; it declares no value this section does not also carry.

<!-- bound-version-scheme: calver-yyyy-ww -->
<!-- version-pattern: ^[0-9]{4}\.(0[1-9]|[1-4][0-9]|5[0-3])\.(0|[1-9][0-9]*)$ -->
<!-- cycle-qualifying-cut: non-patch -->
<!-- ^ The version-scheme contract every release-producing and guarantee-reading consumer
     reads. This template ships a CONCRETE default (calver-yyyy-ww / the zero-padded
     ISO-week pattern / non-patch) -- NOT a placeholder token -- so a new adopter inherits a
     working binding out of the box, matching the same scheme this framework binds itself
     to (DEC-022: the template's shipped value is also what /claire-upgrade's org-fold
     appends into an ALREADY-adopted repository's own CLAIRE_ORG.md, not only a new
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
| `version-pattern` | (as the marker above) | the one legal spelling; zero-padded two-digit ISO week, the form `date +%G.%V` emits natively |
| `cycle-qualifying-cut` | **non-patch** | a release cycle is one cut that advances any component other than the trailing patch field; a patch-only cut does not count toward a guarantee window |

**Resolution rule:** a consumer resolves the three fields from the markers/table above, which must agree; the bound scheme document provides the bump vocabulary and the next-version rule only. **ABSENT / EMPTY / un-substituted PLACEHOLDER `bound-version-scheme` or `version-pattern`, an unrecognized scheme name, or a `bound-version-scheme` naming a document that does not exist under `docs/policies/version-scheme/` → HALT (fail-loud)** naming the binding, writing nothing.

**MONOTONICITY:** a version a consumer proposes must rank strictly above the current version under the ordering `version_cmp` implements (three dot-separated numeric fields). A proposal that does not is refused, naming both values.

**AUDIT:** the resolved scheme name is echoed in every skip/halt/proceed message so resolution is traceable.

**POLARITY NOTE (the Version-Scheme-vs-Test-Scope trap):** this binding's absent-value default is the **Integration-Branch Enforcement Binding's and the Branch-Strategy Binding's, NOT the Test-Scope Binding's**. A missing `bound-version-scheme` or `version-pattern` marker **FAILS LOUD**, because a version number written under the wrong scheme is written into a tag, a README line and a `.claire-version` stamp that a later upgrade resolves against, and none of those is recoverable by a later re-read. Do **NOT** copy the Test-Scope Binding's absent⇒NOT-ENFORCED default here.

**Not in scope at v1:** a third scheme document; a gate verifying that already-shipped tags match `version-pattern`; a normalizer shared with `version_cmp` and the `.claire-version` writer.

---

## Worklog Attribution Split

Added by **BTG-315** under Gate 1's OQ-1 ruling; appended here UNNUMBERED (renumber it to
match your own document's section sequence if you like — no reader depends on the
ordinal, only on the heading text). The single per-repo home for the **per-stage
operator-share factor** `ci-templates/scripts/worklog-split.sh` resolves when
projecting a `stage_effort` entry to a tracker whose Tracker Binding per-prefix row
names a non-empty agent-time user. **Inert** until that condition holds: leave every
Agent-time user cell empty above and this table is never read and can never affect your
projection.

This is **projection-only** configuration: it governs how one already-recorded
`stage_effort` entry is split into up to two tracker worklogs at post time. It never
changes how `stage_effort` itself is calculated or how it is recorded in `metadata.yaml`.

| Stage (`stage_effort.stage`) | Operator share (factor) |
|---|---|
| `triage`         | **0.5** |
| `spec`           | **0.5** |
| `implementation` | **0.5** |
| `code-review`    | **0.5** |
| `maintainer`     | **0.5** |
| `archive`        | **0.5** |

**Accept grammar:** a value is present and matches `^([0-9]+(\.[0-9]+)?|\.[0-9]+)$`
(whole numbers, decimals, the leading-dot form), with at most 9 significant fractional
digits once trailing fractional zeros are stripped, and lies in the closed interval
`[0, 1]`.

**Per-operator override:** `CLAIRE_WORKLOG_FACTOR_<STAGE>` (name derived mechanically —
uppercase the stage id, map `-` to `_`), one per stage: `CLAIRE_WORKLOG_FACTOR_TRIAGE`,
`CLAIRE_WORKLOG_FACTOR_SPEC`, `CLAIRE_WORKLOG_FACTOR_IMPLEMENTATION`,
`CLAIRE_WORKLOG_FACTOR_CODE_REVIEW`, `CLAIRE_WORKLOG_FACTOR_MAINTAINER`,
`CLAIRE_WORKLOG_FACTOR_ARCHIVE`. An override failing the grammar is quietly ignored (no
halt, no warning). A table value that is missing or invalid resolves to `1` (all
operator) and emits the non-halting warning `worklogsplit.factor.org_value_unusable
stage=<id> cause=<missing|invalid>` — never the value, and only in split mode.

**Split rule:** the agent leg is the entry's minutes times one minus the factor, floored
to the next-lower 15-minute increment; the operator leg takes the remainder. The two
legs always sum to the entry, and any off-15-minute-boundary remainder lands on the
operator. A leg that computes to `0m` posts no worklog for that party.

**Single-source-of-truth rule:** a factor value is never restated anywhere else. The
resolved factor is computed once, inside `worklog-split.sh`, and never leaves that
script on any channel.

**Tiering note:** a future change to the table's VALUES is Trivial tier; a change that
adds, removes or renames a stage key, or changes the table's shape, is evaluated on its
own merits under your `change-tiers.md`'s Configuration: value-vs-shape rule.

---

## Open Facet Slots (2 of 6)

The LLM selects 0-2 additional facets from the CLAIRE standard catalog based on the project's problem statement and Zachman facts. Note: the two triggered mandatory facets (Data Integrity, Backwards Compatibility) do not consume an open slot — each activates on its own trigger (owned-data capture for Data Integrity; surface-registry overlap for Backwards Compatibility) and sits alongside the 3 always-on mandatory facets when active.

### Selection guidance

| If the problem statement involves... | Add this facet |
|---------------------------------------|---------------|
| Auth changes, user input handling, PII, new client-side code | **Security Posture** |
| Latency complaints, large datasets, scale concerns | **Performance Efficiency** |
| Existing test suite to preserve, reliability requirements | **Testability** |
| Technology migration, library swap, long-lived system | **Replaceability** |

If none of the above apply, use only the 3 always-on mandatory facets (plus Data Integrity and Backwards Compatibility when triggered). A minimal library is preferable to padding with facets that don't materially shape the spec.

When an open-slot facet is selected, customize it following the instructions in the generic CLAIRE template (Phase 2: Customization Instructions). Use project-specific measures and anti-patterns grounded in the Zachman facts, not the generic "typical" lists.

---

## Precedence Matrix (Org Default)

This ordering resolves conflicts when two facets disagree. Override per project only with written justification in the facet library.

```
1. Data Integrity            — audit and consistency are non-negotiable (when triggered)
2. Security Posture          — the identity / trust chain must not be weakened
3. Backwards Compatibility   — public contracts are promises to consumers (when triggered)
4. Simplicity                — fewer parts; complexity is a tax on a small team
5. Operability               — the team that builds it runs it; observable by default
6. DX (Agentic)              — optimize for AI-assisted development, not at correctness cost
7. [Open slot facet A]       — project-specific
8. [Open slot facet B]       — project-specific
```

Note: both Data Integrity (#1) and Backwards Compatibility (#3) apply only when their facet is triggered — Data Integrity when the system owns data it captures/manipulates/persists, Backwards Compatibility when the change touches registered public surfaces. When a triggered facet is dormant, the effective precedence collapses past its position.

**Why Data Integrity is #1 when triggered (not Security):** For any system that owns data, the most common failure mode in practice is not a security breach — it's a mutation that wasn't logged, a cache that wasn't invalidated, or a multi-step write that partially failed without the user knowing. Auditors and incident responders both check the data trail first, so when the facet is triggered it outranks the rest. Security Posture is #2 because the IdP + server-side enforcement pattern is normally well-established and rarely the source of new risk. (For a system that owns no data, Data Integrity is dormant and the effective ordering begins at Security Posture.) A compliance-heavy org may pin Data Integrity always-on as a documented per-project override (per the portable framework's "Compliance-heavy orgs: Data Integrity is mandatory" pattern) — the triggered default changes only the *default*, it never removes the facet.

**Why Backwards Compatibility is #3:** Breaking a public API silently is a data integrity issue for consumers — they send or receive data they can no longer trust. It ranks above Simplicity because a simpler approach that breaks consumers is more expensive than a slightly more complex approach that maintains compatibility.

---

## Using This Template

### For a new project

```
You have access to the filled-in CLAIRE org configuration in
docs/agentic-sdlc/CLAIRE_ORG.md and the generic CLAIRE
framework in specs/CLAIRE.md.

Here is my problem statement:

[paste problem statement using VERB + SCOPE + WHY + CONSTRAINTS format]

Run CLAIRE using the org configuration. The 3 always-on mandatory
facets are pre-defined — start Phase 1 by copying the Zachman constants,
then explore the codebase for project-specific facts. In Phase 2, include
the 3 always-on mandatory facets, check if Data Integrity is triggered
(system captures/manipulates/persists owned data) and if Backwards
Compatibility is triggered (change touches registered public surfaces),
and select 0-2 additional facets based on the problem statement. In Phase 3, perform SCOUT
decomposition for every acceptance criterion and derive observability
seams. Proceed through Phases 4-5 as normal.
```

### For an existing project that already has a FACET_LIBRARY.md

Check the existing library against this template:
1. Are all 3 always-on mandatory facets present (Simplicity, Operability, DX Agentic)?
2. Are both triggered mandatory facets (Data Integrity, Backwards Compatibility) defined and ready to activate when applicable?
3. Are the org-specific measures included (not just the generic "typical" measures)?
4. Does the Operability facet include the observability measures (tracing, metrics, alerting)?
5. Is the precedence matrix consistent with the org default?
6. Does the project have a `docs/policies/surface-registry.md`? If not, create one from the template.

If not, update the library. The mandatory facets and precedence are org policy, not project preferences.

### Updating this template

This template should be updated when:
- The org adopts a new org-wide standard (e.g., new observability tool, new CI template, new compliance requirement)
- A mandatory facet's measures or anti-patterns are found to be insufficient based on real project experience
- The precedence matrix needs adjustment based on incident post-mortems

Changes to this template should be reviewed by the platform/architecture team since they affect all future CLAIRE runs.
