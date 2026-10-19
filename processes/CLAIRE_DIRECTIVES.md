# CLAIRE Directives

> **Framework-owned — do not edit.** This file carries the CLAIRE directives every
> agent in this repository reads. `/claire-adopt` installs it verbatim and
> `/claire-upgrade` replaces it on core upgrade, so local edits are surfaced as a
> merge conflict and lost. Your own project's directives belong in `CLAUDE.md`, which
> imports this file and which CLAIRE never edits outside its managed block.

## Behaviors

1. **Don't assume. Don't hide confusion. Surface tradeoffs.** When requirements are ambiguous, ask. When two approaches each have costs, name both costs. Never silently pick one interpretation over another.

2. **Minimum code that solves the problem. Nothing speculative.** No abstractions for hypothetical future use. No "while we're here" additions. If it isn't required by the current acceptance criteria, it doesn't exist yet.

3. **Touch only what you must. Clean up only your own mess.** Don't refactor adjacent code. Don't "improve" files you opened for context. If you introduced a problem, fix it. If it was already there, leave it alone.

4. **Define success criteria. Iterate until verified.** Before starting, state what "done" looks like. After finishing, verify against those criteria. Tests pass, behavior matches spec, no regressions. If you can't verify it, say so.

5. **Fail loud. Never fall back silently.** When a binding, id, tier, tool, or expected state is missing or contradictory, halt with an error naming exactly what is missing. Never substitute a guess, never scan around a missing allocator, never no-op. A silent fallback is an ungoverned decision.

6. **A fact changed anywhere is reconciled everywhere.** When a fact lives in more than one representation — spec, template, instance, role, summary doc — the change is not done until every representation agrees. Sweep them in the same change; a drifted copy is a defect, not a cleanup item. This includes code comments: a comment a change makes inaccurate is updated or deleted in the same change (`docs/policies/comment-discipline.md`).

7. **Native vs. CLAIRE skill — when it's ambiguous, ask; never silently pick.** Many requests can be satisfied two ways: performed **directly/natively** (ad-hoc edits in the current turn) or routed through the governed **CLAIRE skill** for that phase (`/claire-triage`, `/claire-elicit`, `/claire-spec`, `/claire-implement`, `/claire-review`, `/claire-maintain`, `/claire-migrate`, `/claire-archive`). These are not equivalent — the skill path carries the human gates, TDD discipline, spec artifacts, effort accumulation, and tracker projection; the native path carries none of them. When a request's verb overlaps a skill's phase and the intended path is not explicit, **stop and prompt the user to choose** rather than defaulting to either. For example, "implement XYZ" is ambiguous: it may mean an ad-hoc direct implementation, or the governed `/claire-implement XYZ` red-green-refactor workflow — ask which. **"File an issue for X", "file a ticket", "open a ticket" and "file a follow-up ticket" are `/claire-triage`-phase verbs and sit squarely inside this rule** — they overlap `/claire-triage`'s *phase* without naming it, which is exactly the case this rule exists to catch. Handled natively, such a request can reach a tracker `reserve` on its own and leave an id allocated with no `specs/<id>/` trail (`idalloc.reserve.unpaired_artifact_creation`). So ask which path is wanted, and name the sanctioned destination when you do: **`/claire-triage --file-only <draft-path>`** files a ticket — write the description to a file first (`specs/drafts/` is the recommended home), then pass the bare path; the id is allocated, both artifacts are written at `status: draft`, and no classification runs — which is usually what "just file it" means. The path form exists because free text does not reliably survive the argument channel (`artifacts/SCHEMA.md`, *What `arguments:` is, and what it is not*), and a mangled path simply fails to open, so the run halts instead of filing a ticket about a word nobody sent. The older inline form **`/claire-triage --file-only "<description>"`** still works and is **DEPRECATED**, sunsetting in 2 release cycles; see `docs/migrations/triage-file-only-draft-path.md`. This is signage, not a mechanism: it does not, and is not claimed to, stop a bare `reserve` — see `CLAIRE_ORG.md#id-allocation-binding` (*Reservation pairing*) for the rule itself. The request is unambiguous (no prompt needed) only when the user names the skill explicitly (`/claire-implement XYZ`), or clearly signals ad-hoc intent ("just make a quick edit", "don't use the workflow", "prototype this"). This is the [Behavior 1](#behaviors) ask-don't-assume rule applied to path selection; it is not overridden by a request merely sounding actionable.

8. **A test's subject is the software, never the governance document that describes it.** Tests validate what this repository's product does when it runs; a test never reads, parses, or asserts on the documents that describe how that product is built. The forbidden subjects, the set that remains in scope, how the rule is scoped, and each role's obligation are stated **once**, in [`docs/policies/test-scope.md`](docs/policies/test-scope.md) -- this behavior points at that document and deliberately keeps no second copy of it.

---

## Frameworks

### Zachman Framework — Structured Design Grounding

Every specification is grounded in the Zachman Framework: six interrogatives (What, How, Where, Who, When, Why) examined at four abstraction levels (Scope, Business Model, System Model, Technology Model). This prevents premature implementation by forcing reasoning through business context and domain model before touching code.

Org-level constants (infrastructure, identity, CI/CD, compliance) are pre-filled from `docs/agentic-sdlc/CLAIRE_ORG.md`. Project-specific facts are discovered from the codebase.

### CLAIRE — Spec Generation Framework

CLAIRE is the umbrella framework that refracts a problem statement into governed iteration specs through five phases: Zachman Grounding, Facet Library Construction, SCOUT Decomposition, Iteration Spec Generation, and (when more than one iteration is produced) Comparison.

**Quality Facets** — Three always-on mandatory facets evaluate every spec:

1. **Simplicity** — Fewest moving parts. No cache without profiling. <=3 files to wire a new capability.
2. **Operability** — Deployable, observable, recoverable. Structured logging, tracing, metrics, alerting ship with the feature.
3. **Developer Experience (Agentic)** — Files <400 lines (raised from 300 by PI-037: 400 stays comfortably single-pass-readable for an agent while avoiding over-fragmentation — splitting a coherent module across many files fights the "reads <=5 files" goal), **except scenario-indexed BDD test harnesses** (`ci-templates/scripts/tests/*.test.sh` and `ci-templates/scripts/tests/*-lib/*.sh`), which carry no whole-file ceiling and are governed per function instead — scenario function <=150 lines, any function <=400. A harness is its entry point together with the scenario modules that entry point sources: one artifact, one measure. Those globs and no others; `CLAIRE_ORG.md` §2 Facet 3 is canonical and states why. One example sufficient to produce a correct new instance. Agent reads <=5 files.

Plus two triggered mandatory facets. **Data Integrity** — 100% audit coverage, actor identity from auth never input, multi-table writes documented — activates whenever the system captures, manipulates, or persists data it owns (in this repo the artifact set is that data, so it is effectively always-on; it collapses out only for a data-free change). **Backwards Compatibility** activates when touching registered public surfaces — in this repo the artifacts are the adopter surface, so it too is effectively always-on. This repo's facet library also carries two project-specific facets, **Source Confidentiality** and **Replaceability**, and omits Security Posture (no runtime trust chain). See `docs/agentic-sdlc/CLAIRE_ORG.md` §6.

Precedence when facets conflict (this repo): Data Integrity (when triggered; effectively always-on here) > Backwards Compat (when triggered) > Source Confidentiality > Simplicity > Replaceability > Operability > DX. (Org default: Data Integrity (when triggered) > Security > Backwards Compat (when triggered) > Simplicity > Operability > DX.)

### SCOUT — Behavioral Decomposition

SCOUT is the tool CLAIRE uses in Phase 3 to turn each acceptance criterion into a testable behavioral contract. Each AC is decomposed into five dimensions:

| Dimension | Role |
|---|---|
| **S**tate | What must be true before (`Given`) |
| **C**onstraints | Business invariants to verify (`Then`) |
| **O**utputs | Observable external outputs (`Then` — external) |
| **U**pdates | State changes to entities/storage (`Then` — internal) |
| **T**riggers | What triggers the behavior (`When`) |

Edge cases are derived mechanically by asking "what if this dimension is violated?" — not ad-hoc. Observability seams (IMPOSSIBLE_STATE, DECISION_DRIFT, SEAM_VIOLATION, LINEAGE_GAP) are likewise derived mechanically — one seam type per dimension.

Portable framework definition: `specs/CLAIRE.md`
Project-specific reference (5 dimensions, seam derivation, five-document model, TDD discipline): `docs/agentic-sdlc/scout-reference.md`
Org configuration: `docs/agentic-sdlc/CLAIRE_ORG.md`

---

## Agents

Agents are specialized subagents in `.claude/agents/`. Each has a constrained role, tool set, and model.

> **Source of record:** `.claude/agents/*/AGENT.md` are **generated build outputs**, compiled from the runtime-neutral source under `artifacts/roles/` by `ci-templates/scripts/claire-compile.sh`. Edit the neutral source and recompile — **never edit `.claude/agents/` directly**, or your change is overwritten on the next compile. (PI-012 / ADR_CLAIRE-0008)

| Agent | Purpose | Phase |
|---|---|---|
| `claire-triage-agent` | Classify, assess scope, check duplicates, create spec stub | Triage |
| `claire-architect` | High-tier pre-flight (opt-in at Medium): surface implicit cross-boundary contracts and produce draft Gherkin specs before spec authoring | Specification |
| `claire-explorer` | Independently produce 2-3 structurally distinct, steelmanned design options — no ranking | Specification |
| `claire-spec-author` | Design solution using Zachman + SCOUT, produce spec and test plan | Specification |
| `claire-reviewer` | Review MR against its tier contract (spec at Medium/High, problem.md ACs at Low) — criteria, coverage, security | Code Review |
| `claire-implementer` | Implement the ticket's tier contract (spec at Medium/High, problem.md ACs at Low) via strict BDD red-green-refactor TDD | Implementation |
| `claire-maintainer` | Evaluate MR for project-level acceptance — compat, architecture, mission | Maintainer Review |
| `claire-archivist` | Archive completed work, update CHANGELOG, sync the repo's bound tracker | Archive |
| `claire-migration-author` | Author EF Core migrations using expand/contract pattern | Migration |

Key constraints:
- Read-only agents (architect, code-reviewer) cannot write files
- Implementer writes Source/ and Tests/ plus the ticket's `specs/` artifacts (submission.md draft, test-plan discovery fields)
- All agents follow the behaviors above

---

## Skills

Skills are user-invocable workflow commands in `.claude/skills/`.

> **Source of record:** `.claude/skills/*/SKILL.md` are **generated** from `artifacts/commands/` by `claire-compile.sh`. Edit the neutral source and recompile — **never edit `.claude/skills/` directly**. (PI-012 / ADR_CLAIRE-0008)

| Command | What It Does |
|---|---|
| `/claire-adopt` | Copy the framework file set into a target repository (never overwrites existing files) |
| `/claire-upgrade` | Merge a newer CLAIRE core into an adopter's customized tree using the version stamp as the 3-way-merge base — clean changes auto-apply, conflicts surface for human resolution (never a silent merge), the apply is atomic, and the stamp advances only on a fully-clean apply |
| `/claire-interview` | Walk an adopter through filling `<placeholder>` cells in `CLAIRE_ORG.md`'s Zachman Where/Who/Why tables — 3 evidence-based candidates + N/A + type-my-own per row; a `--re-interview` flag re-opens every row. N/A is non-destructive (row retained); scope is the Where/Who/Why tables only. Invoked from `/claire-upgrade`'s post-upgrade flow when the org-fold produced no staged conflict |
| `/claire-triage` | Triage an incoming issue — classify, assess, create spec stub. With `--file-only` it **files** instead of triaging: `/claire-triage --file-only <draft-path>` (write the description to a file, pass the bare path) allocates an id and always writes `specs/<id>/problem.md` + `metadata.yaml` at `status: draft` with no tier, running no classification; a later `/claire-triage <id>` is what classifies it. The inline `--file-only "<description>"` form is deprecated for 2 release cycles (`docs/migrations/triage-file-only-draft-path.md`) |
| `/claire-elicit` | Walk a requester through unfilled probe questions; appends answers to problem.md as Elicited Intent |
| `/claire-spec` | Generate specification from triaged issue using Zachman + SCOUT |
| `/claire-implement` | Implement a ticket's tier contract via strict BDD red-green-refactor TDD — approved spec (Medium/High) or problem.md ACs (Low) |
| `/claire-review` | Review MR against its tier contract — approved spec (Medium/High) or problem.md ACs (Low) |
| `/claire-maintain` | Evaluate MR for project-level acceptance |
| `/claire-migrate` | Author EF Core database migration (expand/contract) |
| `/claire-archive` | Archive merged ticket — move artifacts, update CHANGELOG, sync external systems |
| `/claire-parallel` | Run the full triage-to-archive pipeline across a batch of tickets concurrently, with isolated per-ticket implementation worktrees. Prefer for batches of related, mostly-independent tickets; run the single-ticket skills sequentially for complex dependency chains, a single ticket, or when human-gate pacing matters more than parallelism. See [`docs/guides/parallel-sdlc-usage.md`](docs/guides/parallel-sdlc-usage.md) |
| `/claire-mint` | Reserve (or peek) the next collision-safe id for a prefix (PI/ADR/II/PROD/any) against the shared, flock-atomic reserve ledger — used internally by `/claire-triage`, `/claire-archive`, `/claire-adopt`, `/claire-upgrade` |
| `/claire-sync-jira` | Sync spec metadata and status to on-prem Jira Server/DC (PAT auth) |
| `/claire-bump-model` | Bump the model declaration in agent YAML frontmatter from one version to another |
| `/claire-release` | Cut a new release — determine the major/minor/patch bump from the Unreleased changelog (with confirmation), then finalize CHANGELOG, bump README, write release notes, commit, annotate a tag, and push |

---

## Workflow

```
Problem → Triage → Spec → [Human Gate: Spec Review] → Implementation →
[Human Gate: Code Review] → [Human Gate: Maintainer Acceptance] → Merge → Archive
(+ [Human Gate: Deploy Validation] on High-tier changes)
```

Human gates are mandatory. Agents recommend; humans decide.

**Right-sizing:** Not every change follows the full workflow. Changes are classified into four tiers (Trivial, Low, Medium, High) based on objective triggers. Lower tiers skip steps. See `docs/policies/change-tiers.md` for the full policy. The author proposes a tier; triage validates it against the diff.

**Emergencies:** When production is down, the fast-track compresses to: fix → one reviewer → ship → payback within 48h. See `docs/policies/emergency-fast-track.md`.

**Tracker projection:** Spec changes (metadata.yaml and the spec docs) must be projected to the tracker in the same session; the bound tracker + its sync skill and the "when to sync" trigger discipline are governed by `docs/agentic-sdlc/CLAIRE_ORG.md` §9 (Tracker Binding, *Projection triggers & sync discipline*), and the `/claire-implement` sprint-enforcement contract by §13 (Sprint-Enforcement Binding).

---

## Artifact Structure

```
PROJECT_INTENT.md                   — What this repo is for: mission, scope, non-goals,
                                      quality stance, architecture invariants, contribution posture.
                                      Grounds every accept/reject decision.

artifacts/                          — RUNTIME-NEUTRAL SOURCE OF RECORD for agents + skills
├── roles/                          — neutral source per agent  (→ .claude/agents/, generated)
├── commands/                       — neutral source per skill   (→ .claude/skills/, generated)
├── SCHEMA.md                       — neutral-source field schema (capability vocabulary only)
├── manifest.generated              — derived canonical manifest (committed, CI-checked)
└── footprint.generated             — derived framework↔project boundary (committed, CI-checked)

specs/{ticket-id}/
├── problem.md        — What is wrong, what success looks like
├── design-options.md — The explorer's independent, unranked option set (Medium/High)
├── spec.md           — Zachman grid + SCOUT decomposition + proposed design
├── test-plan.md      — Gherkin scenarios ordered for TDD progression
├── decisions.md      — Immutable decision log (reversals create new entries)
├── submission.md     — Versioned change-proposal: description, forge metadata, discussion, resolution
└── metadata.yaml     — Machine-readable fields for automation and sync

docs/
├── SYSTEM_OVERVIEW.md              — Living system view rooted in business flows
├── flows/                          — Per-flow documentation (one file per business flow)
│   └── TEMPLATE.md
├── agentic-sdlc/
│   ├── PROJECT_INTENT_TEMPLATE.md  — Template for the per-repo PROJECT_INTENT.md
│   ├── intent-insights.md          — Cross-ticket non-bug intent discoveries (II-NNN)
│   └── production-insights.md      — Cross-ticket production-defect insights (PROD-NNN)
└── policies/
    └── doc-maintenance-policy.md   — When and how to update system-level docs
```

Templates: `specs/TEMPLATE/` and `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`
Completed work: `archive/{ticket-id}/`
System documentation: `docs/SYSTEM_OVERVIEW.md` and `docs/flows/`
Project intent: `PROJECT_INTENT.md` at repo root — read by the maintainer agent and consulted by spec-author and triage when grounding scope
Generated artifacts: `.claude/agents/` and `.claude/skills/` are compiled from `artifacts/` by `ci-templates/scripts/claire-compile.sh` — edit the neutral source and recompile, never edit `.claude/` directly (PI-012 / ADR_CLAIRE-0008)

---

## TDD Discipline

The implementer follows strict red-green-refactor for every scenario:

1. **RED** — Write the test. It must fail.
2. **GREEN** — Write minimum code to pass. Nothing more.
3. **ACCUMULATE** — Run full suite. All tests pass.
4. **COMMIT** — One commit per cycle.

Scenarios are ordered: happy path → not-found → validation → variations → boundaries → concurrency → auth → E2E.

BDD applies to new code only. Existing tests are never refactored into BDD style.

A test's subject is application functionality, never a governance document -- see [`docs/policies/test-scope.md`](docs/policies/test-scope.md) for the forbidden subjects, the scoping clause, and each role's obligation.
