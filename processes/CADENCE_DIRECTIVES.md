# CADENCE Directives

> **Framework-governed artifact — do not modify directly.** This document defines the core CADENCE
> directives loaded by every agent operating in this repository. `/cadence-adopt` provisions it
> verbatim and `/cadence-upgrade` refreshes it during framework upgrades, meaning any local
> edits will trigger merge conflicts and be overwritten. Place repository-specific rules in
> `AGENTS.md`, which imports this document and is never modified by CADENCE outside its managed
> block.

## Behaviors

1. **Never guess. Never conceal uncertainty. Expose trade-offs.** Whenever requirements are open to multiple interpretations, ask for clarification. Whenever two technical paths carry distinct costs, state both costs explicitly. Never silently choose one interpretation over another.

2. **Write the minimum code required. Zero speculative scaffolding.** Do not introduce abstractions for hypothetical future needs or bundle unrelated "while we are here" cleanups. If a capability is not demanded by the active acceptance criteria, leave it unbuilt.

3. **Modify only what is necessary. Clean up only your own footprint.** Avoid refactoring neighboring modules or "polishing" files opened solely for context. If your change introduces a defect, repair it; if a flaw pre-existed in surrounding code, leave it untouched.

4. **Establish verification criteria up front. Iterate until proven.** Before writing code, define what "done" means. After implementation, validate against those exact criteria: all tests pass, runtime behavior matches the specification, and zero regressions appear. If something cannot be verified, state that explicitly.

5. **Fail loud and immediately. Never fall back silently.** When a required binding, identifier, tier, tool, or state is absent or contradictory, halt execution with an explicit diagnostic naming what is missing. Never substitute a guess, bypass a missing allocator, or silently no-op. Any silent fallback is an ungoverned decision.

6. **A fact modified in one place must be reconciled everywhere.** Whenever a fact is represented across multiple artifacts — specification, template, instance, role definition, summary document, or code comment — the work is incomplete until every representation agrees within the same change. Sweep all occurrences together; a drifted copy is a defect, not follow-up maintenance. This explicitly governs code comments: any comment rendered stale by a change must be updated or removed in that same change (`docs/policies/comment-discipline.md`).

7. **Direct execution vs. governed CADENCE skill — when ambiguous, ask; never choose silently.** Most engineering requests can be fulfilled in two distinct ways: executed **directly/natively** (ad-hoc edits in the active session) or routed through the governed **CADENCE skill** for that lifecycle stage (`/cadence-triage`, `/cadence-elicit`, `/cadence-spec`, `/cadence-implement`, `/cadence-review`, `/cadence-maintain`, `/cadence-migrate`, `/cadence-archive`). These paths are not interchangeable — the governed skill path enforces human review gates, strict TDD cycles, specification artifacts, stage-effort accounting, and external tracker projection, whereas the native path bypasses all of them. Whenever a user's verb overlaps a governed phase and the intended path is not explicit, **pause and ask the user to choose** instead of defaulting to either. For instance, "implement XYZ" is ambiguous between an immediate ad-hoc edit and the governed `/cadence-implement XYZ` red-green-refactor workflow — always ask. **"File an issue for X", "file a ticket", "open a ticket", and "file a follow-up ticket" are `/cadence-triage`-stage verbs and fall squarely under this directive** — they overlap `/cadence-triage`'s domain without naming the command. Executed natively, such a request can invoke a tracker `reserve` directly and leave an allocated identifier without a paired `specs/<id>/` directory (`idalloc.reserve.unpaired_artifact_creation`). Prompt the user for the intended path and name the sanctioned command: **`/cadence-triage --file-only <draft-path>`** files a ticket — write the problem text to a file first (`specs/drafts/` is the recommended location) and pass the bare file path; the identifier is allocated, both artifacts are created at `status: draft`, and classification is deferred — matching what "just file it" intends. The file-path form is required because free-form text does not reliably survive the skill argument channel (`artifacts/SCHEMA.md`, *What `arguments:` is, and what it is not*), whereas a mangled path fails to open cleanly rather than filing a truncated ticket. The legacy inline form **`/cadence-triage --file-only "<description>"`** remains functional but is **DEPRECATED** and sunsets in 2 release cycles; see `docs/migrations/triage-file-only-draft-path.md`. This directive is procedural signage rather than a mechanical lock: see `CADENCE_ORG.md#id-allocation-binding` (*Reservation pairing*) for the underlying invariant. A request is unambiguous (requiring no prompt) only when the user names the skill explicitly (`/cadence-implement XYZ`) or explicitly requests ad-hoc execution ("make a quick direct edit", "skip the workflow", "prototype this inline"). This applies [Behavior 1](#behaviors) directly to workflow routing.

8. **Tests target application runtime behavior, never the governance prose that describes it.** Automated tests verify what the repository's software product does when executed; no test may read, parse, or assert against the governance markdown documents describing how the product is built. The prohibited targets, the permitted scope, the applicability binding, and each agent role's obligations are defined **once** in [`docs/policies/test-scope.md`](docs/policies/test-scope.md) -- this directive delegates to that policy without duplicating its clauses.

---

## Frameworks

### Contextual Grounding Matrix (6W×4L Grid) — Structured System Grounding

Every specification is anchored in the Contextual Grounding Matrix: six fundamental interrogatives (What, How, Where, Who, When, Why) examined across four abstraction layers (Scope, Business Model, System Model, Technology Model). This prevents premature coding by requiring structured analysis of business context and domain invariants before touching implementation files.

Organization-wide constants (infrastructure, identity, CI/CD, compliance) are pre-populated from `docs/agentic-sdlc/CADENCE_ORG.md`. Repository-specific facts are discovered directly from the codebase.

### CADENCE — Specification & Lifecycle Governance Framework

CADENCE (*Contextual Architecture, Decomposition, Execution, Navigation, Consolidation & Enshrinement*) is the overarching lifecycle framework that refracts a problem statement into governed iteration specifications across five specification phases — Contextual Grounding, Pillar Library Construction, CHORD Decomposition, Iteration Spec Generation, and (when multiple iterations are produced) Iteration Comparison — and drives execution across the seven operational workflow stages (**C**lassify -> **A**rchitect & Explore -> **D**ecompose & Specify -> **E**xecute via TDD -> **N**avigate Gates -> **C**onsolidate -> **E**nshrine).

**Engineering Pillars** — Three always-on mandatory pillars evaluate every specification:

1. **Structural Simplicity** — Fewest moving parts required. Zero caching layers without profiling evidence. At most 3 files modified to wire a new capability.
2. **Operational Resilience** — Deployable, observable, and recoverable by default. Structured JSON logging, distributed tracing, metrics, and alerting ship alongside the feature.
3. **Agentic Ergonomics** — Authored files stay strictly `<400` lines (raised from 300 by PI-037: 400 lines remains single-pass-readable for an AI agent while preventing excessive fragmentation across files that would violate the "reads <=5 files" budget), **except scenario-indexed BDD test harnesses** (`ci-templates/scripts/tests/*.test.sh` and `ci-templates/scripts/tests/*-lib/*.sh`), which carry no whole-file ceiling and are governed per function instead — scenario function `<=150` lines, any function `<=400` lines. A harness comprises its entry point together with the scenario modules sourced by that entry point: one logical artifact, one measure. Those globs and no others apply; `CADENCE_ORG.md` §2 Pillar 3 is canonical and documents the rationale. A single existing example is sufficient for an agent to author a valid new instance. An agent reads `<=5` files to understand and extend a capability.

Plus two triggered mandatory pillars. **Data & Audit Fidelity** — 100% mutation audit coverage, actor identity derived strictly from the auth system rather than caller input, and multi-table write sequencing documented — activates whenever the system captures, mutates, or persists owned data (in this repository the governed artifact set is that data, making it effectively always-on; it is dormant only for data-free changes). **Surface Compatibility** activates whenever a change touches registered public surfaces or introduces new ones — in this repository the framework artifacts form the adopter surface, making it effectively always-on as well. This repository's pillar library also includes two repo-specific pillars, **Origin Confidentiality** and **Modular Replaceability**, and omits Security Boundary Posture (no runtime trust chain). See `docs/agentic-sdlc/CADENCE_ORG.md` §6.

Precedence when pillars conflict (this repository): Data & Audit Fidelity (when triggered; effectively always-on here) > Surface Compatibility (when triggered) > Origin Confidentiality > Structural Simplicity > Modular Replaceability > Operational Resilience > Agentic Ergonomics. (Organization default: Data & Audit Fidelity (when triggered) > Security Boundary Posture > Surface Compatibility (when triggered) > Structural Simplicity > Operational Resilience > Agentic Ergonomics.)

### CHORD — Behavioral Decomposition

CHORD is the behavioral decomposition engine CADENCE uses in Phase 3 to turn each acceptance criterion into a verifiable contract. Every acceptance criterion is decomposed across five dimensions:

| Dimension | Role |
|---|---|
| **C**onditions | Preconditions and system state required before execution (`Given`) |
| **H**andling / Triggers | Events, inputs, or invocations that initiate the behavior (`When`) |
| **O**utcomes | Observable external emissions, responses, or notifications (`Then` — external) |
| **R**ules | Business invariants and domain constraints that must hold (`Then` — invariants) |
| **D**eltas | Internal state mutations and persistence updates (`Then` — internal) |

Edge cases are derived mechanically by asking "what happens when this dimension is violated?" rather than brainstorming ad-hoc. Runtime observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) are likewise derived mechanically — one seam family per CHORD dimension.

Portable framework manual: `specs/CADENCE.md`
Project-specific CHORD & TDD reference (5 dimensions, seam derivation, five-document model, TDD discipline): `docs/agentic-sdlc/chord-reference.md`
Organization configuration: `docs/agentic-sdlc/CADENCE_ORG.md`

---

## Agents & Model Routing

Agents are specialized subagents compiled into `.agents/agents/` (with `.gemini/` serving as the Gemini/Antigravity reference runtime and `.claude/` or other CLI directories projected off `.agents/` per `docs/policies/cli-runtime-adoption-policy.md`). Each agent operates under a constrained role, tool allowlist, and capability tier.

> **Source of record:** `.agents/agents/*/AGENT.md` are **generated build outputs**, compiled from the runtime-neutral source under `artifacts/roles/` by `ci-templates/scripts/cadence-compile.sh`. Edit the neutral source under `artifacts/roles/` and recompile — **never edit `.agents/agents/` directly**, or your changes will be overwritten on the next compile. (PI-012 / ADR_CADENCE-0008)

| Agent | Purpose | Phase | Primary Model Tier |
|---|---|---|---|
| `cadence-triage-agent` | Classify incoming issue, assess scope, scan duplicates, create spec stub | Classify (Triage) | Fast-mechanical (`gemini-3.8-flash` / `flash`) |
| `cadence-architect` | High-tier pre-flight (opt-in at Medium): surface implicit cross-boundary contracts and draft Gherkin specs before spec authoring | Architect & Explore | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-explorer` | Independently produce 2-3 structurally distinct, steelmanned design options — without ranking | Architect & Explore | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-spec-author` | Ground solution via Contextual Grounding Matrix + CHORD, author spec and test plan | Decompose & Specify | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-implementer` | Execute the ticket's tier contract (spec at Medium/High, `problem.md` ACs at Low) via strict BDD red-green-refactor TDD | Execute via TDD | Deep-reasoning / Fast-mechanical (`gemini-4-argon` / `pro`) |
| `cadence-migration-author` | Author EF Core schema and data migrations using the expand/contract pattern | Execute via TDD (Migration) | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-reviewer` | Review MR against its tier contract (spec at Medium/High, `problem.md` ACs at Low) — criteria, coverage, security | Navigate Gates (Code Review) | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-maintainer` | Evaluate MR for project-level acceptance — compatibility, architecture, charter alignment | Navigate Gates (Maintainer Review) | Deep-reasoning (`gemini-4-argon` / `pro`) |
| `cadence-archivist` | Enshrine completed work in `archive/`, update CHANGELOG, sync the repo's bound tracker | Consolidate & Enshrine (Archive) | Fast-mechanical (`gemini-3.8-flash` / `flash`) |

Key constraints:
- Read-only agents (`cadence-architect`, `cadence-reviewer`) cannot write or modify repository files
- `cadence-implementer` writes application source and test files plus the ticket's `specs/` execution artifacts (`submission.md` draft, `test-plan.md` infrastructure discovery fields)
- All agents enforce the core behaviors above

### Automatic 2-Tier Local Hardware Coprocessor Offload

Alongside the cloud reasoning tiers (`gemini-4-argon` / `pro` and `gemini-3.8-flash` / `flash`), CADENCE integrates an automatic **2-Tier Local Hardware Coprocessor Offload** pipeline via the `local-offload` MCP server (`offload_log_triage`, `offload_deep_review`, `local_semantic_embed`) and read-only helper subagents (`log-triage`, `repo-scout`):

- **Tier 1 — Always-On Zero-VRAM CPU (`127.0.0.1:9379`)**: Runs `local-fast-cpu` (`gemma-4-e2b-it`, 128MB 3D V-Cache, 0 MB GPU VRAM) and `local-embed-cpu` (`nomic-embed-text`, 768-dim embeddings). Automatically handles noisy test/build/compiler log compaction during `/cadence-implement` TDD loops (`offload_log_triage`, writing full raw output with line numbers to `/tmp/agy-last-triage.log`) and semantic repository/insight/duplicate discovery during `/cadence-triage` and `/cadence-spec` (`local_semantic_embed` / `repo-scout`).
- **Tier 2 — On-Demand Hybrid MoE & GPU (`127.0.0.1:9380`)**: Runs `local-moe-hybrid` (`gemma-4-26b-a4b-it`) and `local-12b-gpu` (`gemma-4-12b-it` on RTX 5070 Ti 12GB VRAM). Automatically runs advisory pre-review mechanical sweeps (`offload_deep_review`) checking the `<400`-line file ceiling, comment discipline, and CHORD seam completeness before `cadence-reviewer` and `cadence-maintainer` issue gate verdicts.
- **Strict Read-Only Guardrail**: Local models act exclusively as read-only analytical and retrieval coprocessors (`enable_write_tools: false`) and never author or edit project files.

---

## Skills

Skills are user-invokable slash-command workflows compiled into `.agents/skills/` (and projected to `.gemini/` or `.claude/` per `docs/policies/cli-runtime-adoption-policy.md`).

> **Source of record:** `.agents/skills/*/SKILL.md` are **generated** from `artifacts/commands/` by `cadence-compile.sh`. Edit the neutral source and recompile — **never edit `.agents/skills/` directly**. (PI-012 / ADR_CADENCE-0008)

| Command | What It Does |
|---|---|
| `/cadence-adopt` | Provision the CADENCE framework file set into a target repository (never overwrites existing files) |
| `/cadence-upgrade` | Merge a newer CADENCE core release into an adopter's customized tree using `.cadence-version` as the 3-way merge base — clean diffs apply automatically, conflicts surface for human resolution (never a silent merge), application is atomic, and the version stamp advances only on a completely clean apply |
| `/cadence-interview` | Guide an adopter through populating `<placeholder>` cells in `CADENCE_ORG.md`'s Contextual Grounding Where/Who/Why tables — offering 3 codebase-evidenced candidates + N/A + custom entry per row; `--re-interview` re-opens every row. N/A is non-destructive (retains the row); scope is strictly the Where/Who/Why tables. Invoked automatically by `/cadence-upgrade`'s post-upgrade flow when the org-fold produces no staged conflict |
| `/cadence-triage` | Classify an incoming issue — assess scope/tier, check duplicates, and create the spec stub. With `--file-only`, it **files** without classifying: `/cadence-triage --file-only <draft-path>` (write the problem description to a file first and pass the bare path) allocates an id and writes `specs/<id>/problem.md` + `metadata.yaml` at `status: draft` with an empty tier; a subsequent `/cadence-triage <id>` classifies it. The inline `--file-only "<description>"` form is deprecated for 2 release cycles (`docs/migrations/triage-file-only-draft-path.md`) |
| `/cadence-elicit` | Walk a human requester through unanswered probe questions in `problem.md` and append verbatim responses under `## Elicited Intent` |
| `/cadence-spec` | Author a complete specification and test plan from a triaged issue using Contextual Grounding + CHORD |
| `/cadence-implement` | Execute a ticket's tier contract via strict BDD red-green-refactor TDD — approved spec (Medium/High) or `problem.md` ACs (Low) |
| `/cadence-review` | Review an MR against its tier contract — approved spec (Medium/High) or `problem.md` ACs (Low) |
| `/cadence-maintain` | Evaluate an MR for project-level maintainer acceptance |
| `/cadence-migrate` | Author EF Core database migrations using the expand/contract pattern |
| `/cadence-archive` | Enshrine a merged ticket — move spec artifacts to `archive/`, update CHANGELOG, and sync bound external trackers |
| `/cadence-parallel` | Execute the end-to-end triage-to-archive pipeline concurrently across a batch of independent tickets using isolated per-ticket git worktrees. Recommended for batches of related, mostly independent tickets; use single-ticket commands sequentially for tightly coupled dependency chains or when human-gate pacing outweighs concurrency. See [`docs/guides/parallel-sdlc-usage.md`](docs/guides/parallel-sdlc-usage.md) |
| `/cadence-mint` | Reserve (or peek) the next collision-safe identifier for a prefix (PI/ADR/II/PROD/custom) against the shared, flock-atomic reserve ledger — invoked internally by `/cadence-triage`, `/cadence-archive`, `/cadence-adopt`, and `/cadence-upgrade` |
| `/cadence-sync-jira` | Project spec metadata and lifecycle status to on-prem Jira Server/DC (PAT authentication) |
| `/cadence-bump-model` | Update the concrete model identifier in agent YAML frontmatter and `CADENCE_ORG.md#model-tier-mapping` within a single capability tier |
| `/cadence-release` | Cut a governed release — compute the major/minor/patch version bump from `[Unreleased]` changelog entries (with operator confirmation), finalize CHANGELOG, update README, draft release notes, commit, create an annotated git tag, and push |

---

## Workflow

```
Problem → Classify (Triage) → Architect & Explore / Decompose & Specify (Spec) →
[Human Gate: Spec Review] → Execute via TDD (Implementation) →
[Human Gate: Code Review] → [Human Gate: Maintainer Acceptance] → Consolidate (Merge) → Enshrine (Archive)
(+ [Human Gate: Deploy Validation] on High-tier changes)
```

Human gates are mandatory checkpoints. Agents analyze and recommend; humans decide.

**Right-sizing by change tier:** Not every change requires the full ceremony. Changes are classified into four tiers (Trivial, Low, Medium, High) using objective triggers, and lower tiers bypass unnecessary stages. See `docs/policies/change-tiers.md` for the complete policy. The author proposes a tier; triage validates it against the actual scope.

**Emergency fast-track:** When production is degraded or down, the workflow compresses to: fix → single reviewer → deploy → governance payback within 48 hours. See `docs/policies/emergency-fast-track.md`.

**Tracker projection:** Changes to `metadata.yaml` and specification documents (`problem.md`, `spec.md`, `test-plan.md`) must be projected to the repository's bound tracker within the same session. The bound tracker, its `/sync-*` skill, and the projection trigger rules are governed by `docs/agentic-sdlc/CADENCE_ORG.md` §9 (Tracker Binding, *Projection triggers & sync discipline*), while `/cadence-implement` sprint enforcement is governed by §13 (Sprint-Enforcement Binding).

---

## Artifact Structure

```
PROJECT_INTENT.md                   — Repository charter: mission, scope, non-goals,
                                      quality stance, architecture invariants, contribution posture.
                                      Grounds every maintainer accept/reject decision.

artifacts/                          — RUNTIME-NEUTRAL SOURCE OF RECORD for agents + skills
├── roles/                          — neutral source per agent  (→ .agents/agents/, generated)
├── commands/                       — neutral source per skill   (→ .agents/skills/, generated)
├── SCHEMA.md                       — neutral-source field schema (capability vocabulary only)
├── manifest.generated              — derived canonical manifest (committed, CI-checked)
└── footprint.generated             — derived framework↔project boundary (committed, CI-checked)

specs/{ticket-id}/
├── problem.md        — Problem statement, business context, and acceptance criteria
├── design-options.md — Explorer's independent, unranked architectural option set (Medium/High)
├── spec.md           — Contextual Grounding Matrix + CHORD decomposition + proposed design
├── test-plan.md      — Gherkin scenarios sequenced for red-green-refactor TDD progression
├── decisions.md      — Immutable decision log (reversals append new superseding entries)
├── submission.md     — Versioned change proposal: description, forge metadata, discussion, resolution
└── metadata.yaml     — Machine-readable lifecycle state, effort accounting, and tracker sync fields

docs/
├── SYSTEM_OVERVIEW.md              — Living architectural map rooted in business flows
├── flows/                          — Per-flow documentation (one file per business flow)
│   └── TEMPLATE.md
├── agentic-sdlc/
│   ├── PROJECT_INTENT_TEMPLATE.md  — Template for the repository's root PROJECT_INTENT.md
│   ├── intent-insights.md          — Cross-ticket non-bug architectural/domain discoveries (II-NNN)
│   └── production-insights.md      — Cross-ticket production-defect insights (PROD-NNN)
└── policies/
    ├── cli-runtime-adoption-policy.md — Canonical .agents/ layout and CLI runtime projection rules
    └── doc-maintenance-policy.md   — When and how system-level documentation is updated
```

Templates: `specs/TEMPLATE/` and `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`
Enshrined work: `archive/{ticket-id}/`
System documentation: `docs/SYSTEM_OVERVIEW.md` and `docs/flows/`
Project charter: `PROJECT_INTENT.md` at repository root — evaluated by `cadence-maintainer` and consulted by `cadence-spec-author` and `cadence-triage-agent` when grounding scope
Generated runtime trees: `.agents/agents/` and `.agents/skills/` are compiled from `artifacts/` by `ci-templates/scripts/cadence-compile.sh` (with `.gemini/` or `.claude/` projected per `docs/policies/cli-runtime-adoption-policy.md`) — always edit the neutral source under `artifacts/` and recompile, never edit `.agents/` directly (PI-012 / ADR_CADENCE-0008)

---

## TDD Discipline

The `cadence-implementer` agent executes strict red-green-refactor cycles for every scenario in sequence:

1. **RED** — Author the failing test for the current scenario. Confirm it fails for the expected reason.
2. **GREEN** — Write the minimum production code required to make the test pass. Nothing extra.
3. **ACCUMULATE** — Execute the complete test suite (using `offload_log_triage` / `log-triage` on `:9379` to compact verbose test logs while preserving verbatim failure output in `/tmp/agy-last-triage.log`). Every test must pass.
4. **COMMIT** — Create one atomic commit per scenario cycle.

Scenarios are executed in strict order: happy path → not-found → validation → variations → boundaries → concurrency → auth → E2E.

BDD conventions apply exclusively to newly authored tests. Pre-existing tests are never rewritten into BDD format.

A test's subject is runtime application behavior, never a governance document -- see [`docs/policies/test-scope.md`](docs/policies/test-scope.md) for the prohibited subjects, the applicability binding, and each role's enforcement obligation.
