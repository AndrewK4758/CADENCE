# Workflow Step 04 — Implementation

> Part of the per-step workflow guide series. This guide details the **Implementation** step. For the preceding human gate see [`03-spec-approval.md`](03-spec-approval.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Implementation (`/cadence-implement`) |
| **Who** | Contributor / Implementer (invokes the skill; `cadence-implementer` + `log-triage` execute the TDD loops) |
| **Consumes** | A ticket **in the active sprint** (when sprint enforcement is enabled in `CADENCE_ORG.md` §13); and — for **Medium/High tiers** — an **approved** specification (`spec.md` + `test-plan.md` at `status: spec-approved`) |
| **Produces** | An `impl/{type}/{id}` branch (in a dedicated git worktree) with tests + production code, one commit per TDD scenario cycle; `submission.md` drafted; `status: in-review` |
| **Leads to** | **[Gate 2: Code Review](05-code-review.md)** — a reviewer evaluates the MR against the approved contract |

---

## Purpose

The Implementation step builds the exact change specified in `spec.md` (or `problem.md`'s acceptance criteria at Low tier) through **strict BDD-first red-green-refactor TDD driven by `test-plan.md`'s Implementation Order**. Zero production code is written before a failing automated test demands it. The output is a clean implementation branch whose commit history narrates the incremental TDD progression — one atomic commit per scenario — ready to open as a remote MR/PR targeting the integration branch.

## Prerequisites

Two precondition gates govern entry into `/cadence-implement`:

### 1. Sprint enforcement check (all tiers, governed by `CADENCE_ORG.md` §13)

Before implementation starts, `/cadence-implement` evaluates the repository's [Sprint-Enforcement Binding](../../agentic-sdlc/CADENCE_ORG.md#sprint-enforcement-binding) (§13) via `ci-templates/scripts/org-binding-resolve.sh --sprint <PREFIX>`. Intent issues originate in the backlog and remain there through Triage ([`00-problem.md`](00-problem.md)); active implementation represents committed sprint work, so the ticket should be assigned to the **current active sprint** across all tiers (Trivial, Low, Medium, High) before coding begins.

### 2. Spec-approval and integration-branch preconditions (`change-tiers.md` & `CADENCE_ORG.md` §14)

`/cadence-implement` reads the authoritative `#per-tier-spec-requirements` table in [`change-tiers.md`](../../policies/change-tiers.md) to verify required artifacts and pre-implementation status:

- **Medium and High tiers:** Require `metadata.yaml`, `problem.md`, `spec.md`, and `test-plan.md` at `status: spec-approved` (and when `CADENCE_ORG.md` §14 `integration-branch-enforcement-enabled` is `yes`, verify P1/P2 that the approved spec is already merged onto the integration branch). If the spec is still at `spec-in-review`, `/cadence-implement` **halts loudly** — [Gate 1: Spec Approval](03-spec-approval.md) is never bypassed.
- **Low tier:** Requires `metadata.yaml` and `problem.md` at `status: triaged` — `problem.md`'s Acceptance Criteria checklist serves as the behavioral contract, with no `spec.md`, `test-plan.md`, or Gate 1 required.
- **Trivial tier:** Requires `metadata.yaml` at `status: triaged`.

## Who does what

Invoke `/cadence-implement` from your agentic CLI runtime (`.agents/skills/cadence-implement/` or `.gemini/` on Antigravity):

```
/cadence-implement <ticket-id>         # e.g. /cadence-implement TT-6547
```

The `/cadence-implement` skill owns **lifecycle status transitions and external tracker projections** (`CADENCE_ORG.md` §9), while delegating code and test authoring to the **`cadence-implementer`** subagent (which in turn delegates database migrations to **`cadence-migration-author`** when schema changes are present). The orchestration sequence is:

1. **Pre-delegation:** Verify preconditions (`change-tiers.md`, §13 sprint guard, §14 integration-branch guard), transition `metadata.yaml` to `status: in-progress` + `implementation_started_at`, and project to the bound tracker (`CADENCE_ORG.md` §9).
2. **Delegation:** Invoke `cadence-implementer` to execute the red-green-accumulate-commit cycles on a dedicated worktree branch (`impl/{type}/{id}`).
3. **Post-delegation:** Once all scenarios pass and exit criteria are verified, transition `metadata.yaml` to `status: in-review`, append the `implementation` `stage_effort` entry into `actual_effort`, and project to the bound tracker.

## Automatic Local Offload during TDD Loops (`log-triage` & `offload_log_triage`)

Running full test suites and builds across dozens of red-green-accumulate cycles generates massive terminal output that would rapidly saturate an LLM's context window if ingested raw. During Step 04, `cadence-implementer` automatically delegates test and build log analysis to CADENCE's read-only local log-triage coprocessor (`enable_write_tools: false`):

1. **Test & Compiler Log Compaction (`offload_log_triage` / `log-triage` on `local-fast-cpu`):** On every **RED**, **GREEN**, and **ACCUMULATE** test execution (as well as migration `apply → rollback → reapply` verification), test runner output is routed through `offload_log_triage` (`gemma-4-e2b` / `gemma-4-26b-a4b` running on the Ryzen 9 9955HX3D 3D V-Cache CPU server, port `9379`, at **0 MB VRAM**).
2. **Verbatim Evidence Preservation:** `offload_log_triage` never paraphrases compiler errors or failing assertions — it returns the exact test runner command evidence, verbatim compiler/assertion error messages, pass/fail/skip counts, test coverage metrics, linter warnings, and exact `file:line` coordinates.
3. **Raw Escape Hatch (`/tmp/agy-last-triage.log`):** Every invocation simultaneously writes the complete, unedited terminal output with line numbers to `/tmp/agy-last-triage.log`, allowing `cadence-implementer` to inspect raw surrounding lines whenever a subtle failure warrants deeper inspection.

All code edits, test authoring, and TDD reasoning remain 100% owned by `cadence-implementer`.

## What happens

`cadence-implementer` executes a deterministic multi-phase TDD workflow:

### Phase 0 — Worktree setup & codebase discovery
Create a dedicated Git worktree and branch named `impl/{type}/{id}` per the repository's [Branch Strategy Binding](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding) (`docs/policies/branch-strategy/`). Discover the repository's existing test runner, assertion/mocking libraries, fixture conventions, and folder structure (`PROJECT_INTENT.md` and `AGENTS.md`). Review matching entries in [`production-insights.md`](../../agentic-sdlc/production-insights.md), load `test-plan.md`'s **Implementation Order** (or `problem.md`'s AC checklist at Low tier) as the execution queue, and run the baseline test suite via `offload_log_triage` / `log-triage` to confirm the repository starts 100% green.

### Phase 1–2 — Strict Red-Green-Accumulate-Commit cycles (unit, then integration)
For each scenario in the Implementation Order (`happy path -> not-found -> validation -> variations -> boundaries -> concurrency -> auth -> E2E`), `cadence-implementer` executes five steps:

1. **RED** — Author a single test for the scenario tagged with its ticket and scenario ID per [`comment-discipline.md`](../../policies/comment-discipline.md) rule `C5` (e.g., `// ABC-123 S-1.1` or `// ABC-123 AC-1` at Low tier; never duplicate the full Gherkin `Given`/`When`/`Then` prose as a comment). Add only minimal signature stubs needed to compile, run the test via `log-triage`, and **confirm it fails for the expected behavioral reason**.
2. **GREEN** — Write the *minimum* production code required to make the failing test pass, respecting the architecture's layer boundaries (Domain → Application → API/Interface → Infrastructure/Data) and keeping every file strictly `< 400` lines (Agentic DX pillar). Write zero speculative code for later scenarios.
3. **ACCUMULATE** — Run the **entire** repository test suite via `offload_log_triage` / `log-triage`. Every single test — new and pre-existing — must pass. Remedy any regression immediately before moving forward.
4. **REFACTOR** (only when needed) — Clean up duplication inside the newly authored code while keeping all tests green and adhering to [`comment-discipline.md`](../../policies/comment-discipline.md) (`C1`–`C8`). Never refactor unrelated files outside the ticket's scope.
5. **COMMIT** — Create one atomic Git commit on the `impl/{type}/{id}` branch containing the test and the production code that satisfies it.

Unit-level scenarios execute first, followed by full-stack integration scenarios.

### Conditional phases (executed when specified by `spec.md` / `test-plan.md`)
- **Interim compatibility code** — when `spec.md`'s Deployment Compatibility section classifies the change as **Prep-required**, commit the null-safe-read / dual-write / fallback compatibility code as a standalone deployable commit **prior to** the schema migration commit.
- **Database migrations** — delegate schema and data migrations to `cadence-migration-author` following the **expand/contract** pattern, commit them separately from application code, and verify `apply → rollback → reapply` idempotency and reversibility per [`migration-policy.md`](../../policies/migration-policy.md).
- **Journey & chaos tests** — when `test-plan.md` declares journey invariants, construct deterministic stateful simulators with programmable chaos toggles, run Pass 1 (deterministic happy path), and then run Pass 2 across every applicable profile in [`chaos-profiles.md`](../../policies/chaos-profiles.md) (`CP-01`–`CP-11`), verifying that all business invariants hold.
- **CHORD observability seams** — implement and test `OS-{N}` scenarios (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) per [`observability-patterns.md`](../../policies/observability-patterns.md) using the exact same red-green-accumulate-commit loop.

### Phase 3.5–4 — Final verification & `submission.md` drafting
Run the complete test suite and linter/formatter one final time (via `offload_log_triage`), verify `run-gates.sh` passes if `artifacts/` were touched, record `branch: impl/{type}/{id}` in `metadata.yaml`, and instantiate **`specs/{ticket-id}/submission.md`** from [`specs/TEMPLATE/submission.md`](../../../specs/TEMPLATE/submission.md) (populating `## Description` and `## Forge metadata` while leaving `## Discussion` and `## Resolution` for the review and maintainer gates).

## Boundary & Comment Discipline (`C1`–`C8`)

All inline comments authored or modified during implementation must comply with [`comment-discipline.md`](../../policies/comment-discipline.md):

- Retain a comment only if deleting it loses information unrecoverable from code, `archive/`/`docs/`, or Git history.
- Multi-line design rationales belong in `decisions.md` (`DEC-NNN`), with at most a compact pointer (`// ABC-123 DEC-4`) in code (`C2`, `C4`).
- Never write diff narrative (`"added for X"`, `"fixed per review"`, `C3`).
- Tag every test with `{TICKET-ID} S-{N}` (or `{TICKET-ID} AC-{N}` at Low tier) without restating Gherkin prose (`C5`).
- On **boundary-crossing files and functions only**, include the minimum `C7` boundary fields: bounded context/flow + external invariant ID/anchor on file headers, and upstream inputs + downstream effects + ticket ID on boundary function docstrings.

## Core discipline (the rules that govern every cycle)

- **Never write production code without a failing test first.**
- **Never skip ACCUMULATE.** Every green scenario is followed by a full suite run (triaged via `offload_log_triage` / `log-triage`).
- **Keep files strictly `< 400` lines** (Agentic DX Engineering Pillar).
- **Touch only what the contract requires.** Leave adjacent files you opened for context untouched, except when reconciling a comment or fact your change itself falsified (`CADENCE_DIRECTIVES.md` Behavior 6).
- **Follow the spec, but trust empirical test failures.** If TDD uncovers an impossible constraint in `spec.md`, record a `DEC-NNN` deviation in `decisions.md` and surface it prominently in `submission.md` — never diverge silently.
- **Log out-of-scope discoveries in `decisions.md` rather than filing mid-stream tickets.** When coding reveals an adjacent defect or a deferred contraction migration (`contraction-pending`), record it in `decisions.md` (or let the gate classify it as `out-of-scope-defect` per [`finding-classes.md`](../../policies/finding-classes.md)) so the human gate confirms follow-up filing via `/cadence-triage --file-only <draft-path>`.

## Commit strategy

Each red-green-accumulate cycle produces one atomic commit on the `impl/{type}/{id}` branch:

```
{ticket} {sprint}: test({scope}): S-1.1 campaign activation with valid bundles
{ticket} {sprint}: test({scope}): S-2.4 campaign not found returns failure
{ticket} {sprint}: migration(expand): add status column [reversible, idempotent]
{ticket} {sprint}: feat({scope}): complete implementation with all BDD tests passing
```

## Exit criteria (Definition of done)

- [ ] Full test suite passes (unit, integration, contract, and journey + chaos passes where applicable), verified via `offload_log_triage`.
- [ ] Every acceptance criterion and `test-plan.md` scenario is covered by a passing automated test carrying its `C5` tag.
- [ ] Commit history on `impl/{type}/{id}` shows one atomic commit per TDD scenario cycle.
- [ ] All modified source files remain strictly `< 400` lines and comply with `comment-discipline.md` (`C1`–`C8`).
- [ ] Database migrations (if any) are separated (schema vs. data), reversible, idempotent, and verified via `apply → rollback → reapply`.
- [ ] Any spec deviations or deferred contraction items are recorded in `decisions.md`.
- [ ] `branch` recorded in `metadata.yaml` and `specs/{ticket-id}/submission.md` populated.
- [ ] Branch pushed to `origin`, remote PR/MR opened against the integration branch, `status: in-review` set, and `implementation` `stage_effort` projected to the bound tracker.

## What this step is NOT

- **Not spec-optional at Medium or High tier.** `/cadence-implement` enforces `#per-tier-spec-requirements` in [`change-tiers.md`](../../policies/change-tiers.md) and halts if a Medium/High ticket lacks `status: spec-approved`.
- **Not direct commits to `develop` or `main`.** All implementation happens on a dedicated worktree branch (`impl/{type}/{id}`) merged via remote PR/MR.
- **Not code-first.** Writing implementation before the failing test violates CADENCE TDD discipline.
- **Not an opportunistic refactoring sweep.** Pre-existing code and tests outside the ticket's scope remain untouched.

## Related documents

- [`03-spec-approval.md`](03-spec-approval.md) — Gate 1, which approves the specification consumed here (Medium/High).
- [`05-code-review.md`](05-code-review.md) — Gate 2, where the resulting implementation MR is reviewed.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — `#per-tier-spec-requirements` table read by `/cadence-implement`.
- [`../../policies/branch-strategy/long-lived-feature-release.md`](../../policies/branch-strategy/long-lived-feature-release.md) · [`trunk-based.md`](../../policies/branch-strategy/trunk-based.md) — branch naming and protection rules.
- [`../../policies/comment-discipline.md`](../../policies/comment-discipline.md) — rules `C1`–`C8` for inline comments and `C5` test tags.
- [`../../policies/migration-policy.md`](../../policies/migration-policy.md) — expand/contract, reversibility, and idempotency requirements.
- [`../../policies/chaos-profiles.md`](../../policies/chaos-profiles.md) · [`../../policies/observability-patterns.md`](../../policies/observability-patterns.md) — chaos profiles (`CP-01`–`CP-11`) and CHORD observability seams (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`).
- [`../submitting-changes.md`](../submitting-changes.md) — how `submission.md` is used to open the MR/PR.
