# Workflow Step 04 — Implementation

> Part of the per-step workflow guide series. This document details the **Implementation** step. For the preceding gate see [`03-spec-approval.md`](03-spec-approval.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Implementation (`/claire-implement`) |
| **Who** | Implementer (invokes the skill; the `claire-implementer` subagent writes the code) |
| **Consumes** | A ticket **in the current sprint** (all tiers); and — for **Medium/High tiers** — an **approved** spec (`spec.md` + `test-plan.md` at `status: spec-approved`) |
| **Produces** | A feature branch with tests + code, one commit per red-green cycle; `submission.md` drafted; `status: in-review` |
| **Leads to** | **[Gate: Code Review](../getting-started.md)** — a reviewer checks the MR against the approved spec |

---

## Purpose

The Implementation step builds the change the spec designed, using **strict red-green-refactor TDD driven by the test plan's Gherkin scenarios**. Production code is never written without a failing test first. The result is a feature branch whose commit history tells the TDD story — one commit per scenario — ready to open as an MR.

## Prerequisites

Two entry conditions govern this step.

### The ticket is in the current sprint (all tiers)

The ticket must be pulled from the backlog into the **current sprint** before implementation begins — **this applies to every tier** (Trivial, Low, Medium, High). Intent issues are filed into the backlog and stay there until triaged (see [`00-problem.md`](00-problem.md)); implementation is committed sprint work, so a ticket still sitting in the backlog is not ready to implement. Move it into the active sprint first.

### The spec is approved (Medium and High tiers only)

For **Medium- and High-tier** tickets, `/claire-implement` refuses to start unless `metadata.yaml` shows `status: spec-approved`. If the spec exists but isn't approved, it **stops** — the [Spec Approval](03-spec-approval.md) human gate must pass first and is never bypassed. If no spec exists, it points you to `/claire-spec`.

**Trivial- and Low-tier** tickets carry **no** spec-approval gate (see [`change-tiers.md`](../../policies/change-tiers.md)): Trivial changes need no spec at all, and Low-tier work proceeds from `problem.md` with Code Review as its only human gate.

## Who does what

You drive the step from inside Claude Code:

```
/claire-implement <ticket-id>         # e.g. /claire-implement TT-6547
```

The skill owns the **status transitions and their Jira syncs** (a subagent's context can't sync), and delegates the actual coding to the deep-reasoning **`claire-implementer`** subagent. The implementer may in turn delegate to the **`claire-migration-author`** agent for schema changes. The skill's bracketing:

1. Before delegating — set `status: in-progress` + `implementation_started_at`, then `/claire-sync-jira`.
2. Delegate to the implementer.
3. After the implementer returns and exit criteria are met — set `status: in-review`, record implementation `stage_effort`, then `/claire-sync-jira`.

## What happens

The `claire-implementer` follows a fixed sequence built around the TDD cycle:

### Phase 0 — Setup & discovery
Create the feature branch (named per [`branch-strategy.md`](../../policies/branch-strategy.md)); **discover the existing test infrastructure** (framework, assertion/mocking libraries, base classes, naming) so new tests match house style; read production insights for the affected domain; load the test-plan's **Implementation Order** as the work queue; and run the full suite to confirm a green baseline before touching anything.

### Phase 1–2 — Red-green cycles (unit, then integration)
For each scenario in the Implementation Order, the **core discipline** runs:

1. **RED** — translate the Gherkin scenario into a test (with the scenario preserved as a comment); create only the minimal stubs needed to compile; run it — **it must fail**.
2. **GREEN** — write the *minimum* production code to pass, following the spec's layer order (Domain → Application → API → Data). Nothing for future scenarios.
3. **ACCUMULATE** — run the **full** suite across all projects; every test, including pre-existing ones, must pass. Fix any regression before continuing.
4. **REFACTOR** (only when needed) — remove obvious duplication in the new code; re-run all tests. Never refactor existing code or tests outside scope.
5. **COMMIT** — one commit per cycle, containing both the test and the code that passes it.

Unit scenarios come first; integration scenarios (full HTTP stack) follow, using the discovered integration patterns.

### Conditional phases (only when the spec calls for them)
- **Interim compatibility code** — when the spec's Deployment Compatibility section is **Prep-required**, ship the null-safe-read / dual-write / fallback code as a separately deployable commit that lands **before** the migration.
- **Database migrations** — schema changes are delegated to `claire-migration-author` using the **expand** pattern, committed separately, and verified reversible + idempotent per [`migration-policy.md`](../../policies/migration-policy.md) (apply → rollback → reapply).
- **Journey & chaos tests** — when the test plan declares journey invariants, build stateful simulators, run one deterministic end-to-end pass, then run a chaos pass per profile ([`chaos-profiles.md`](../../policies/chaos-profiles.md)), asserting every invariant still holds.
- **Observability seams** — `OS-{N}` scenarios (IMPOSSIBLE_STATE, DECISION_DRIFT, LINEAGE_GAP, SEAM_VIOLATION) are implemented with the same red-green cycle, after business logic and before full integration tests.

### Phase 3.5–4 — Regression, then finalize
Write regression tests in the **existing** convention (not BDD style); run the full suite one final time; run formatting; verify a clean build; set `branch` in metadata; and **draft `submission.md`** from the template (Description, forge metadata; Discussion/Resolution left for the reviewer/maintainer).

## Boundary documentation

Code that **crosses a service or domain boundary** must anchor itself in the architecture so human understanding doesn't erode. For such code only (not internal single-context code), the implementer adds: a **header comment** naming the bounded context/flow and the external invariants it relies on; **docstrings with integration hints** (upstream inputs, downstream effects, spec reference); and **self-documenting names** (`PublishAppointmentConfirmation`, not `SendMessage`). Files you merely opened for context are left untouched.

## Core discipline (the rule that governs everything)

- **Never write production code without a failing test.** Catch yourself writing untested code → stop and write the test first.
- **Never skip ACCUMULATE.** Every green is followed by running all tests across all projects.
- **BDD style is for new code only.** Existing tests keep their format; never refactor them into Gherkin style.
- **Discover, don't assume.** Learn the framework/libraries/patterns from the codebase; don't hardcode assumptions.
- **Follow the spec, but trust the tests.** If TDD reveals the design is wrong, log the deviation in `decisions.md` and flag it in the MR — don't silently diverge.
- **Stay in scope.** Only the files in the spec's "Files Affected" table; no untested behavior; no out-of-scope refactors.
- **Defer follow-up tickets — do not create them.** When implementation surfaces work that belongs in a separate ticket (out-of-scope discoveries, deferred contraction migrations, tech-debt spotted in passing, an adjacent bug), **do not file a ticket for it here.** Record it in `specs/{ticket-id}/decisions.md` as a suggested follow-up with enough context to act on. The **maintainer** owns follow-up decisions at Gate 3 ([`06-maintainer-acceptance.md`](06-maintainer-acceptance.md)) — deciding whether to extract it into a separate effort, defer it, or drop it. Creating tickets mid-implementation fragments the backlog and pre-empts that judgment.
- **Migrations are reversible and idempotent** — never a stub reverse migration or unguarded SQL.

## Commit strategy

Each red-green cycle is its own commit, so the history reads as the TDD story a reviewer can walk:

```
{ticket} {sprint}: test({scope}): S-1.1 campaign activation with valid bundles
{ticket} {sprint}: test({scope}): S-2.4 campaign not found returns failure
{ticket} {sprint}: migration(expand): add status column [reversible, idempotent]
{ticket} {sprint}: feat({scope}): complete implementation with all BDD tests passing
```

## Exit criteria (Definition of done)

- [ ] Full test suite passes — unit, integration, and journey+chaos where applicable.
- [ ] Every acceptance criterion maps to at least one passing scenario.
- [ ] One commit per red-green cycle in the branch history.
- [ ] Migrations (if any) reversible + idempotent; apply/rollback/reapply verified; committed separately.
- [ ] Interim compatibility code shipped as its own deployable unit (if Prep-required).
- [ ] Boundary documentation present on cross-service/domain code.
- [ ] Any spec deviations logged in `decisions.md`.
- [ ] Any suggested follow-up work recorded in `decisions.md` (not filed as tickets) for the maintainer to handle.
- [ ] `branch` set in metadata; `submission.md` drafted.
- [ ] `status: in-review`; implementation effort recorded and projected to Jira.

## What this step is NOT

- **Not spec-optional at Medium/High tiers.** For Medium- and High-tier tickets, no approved spec (`spec-approved`) → the skill stops; the gate is not bypassed. (Trivial/Low tiers have no spec-approval gate — see [`change-tiers.md`](../../policies/change-tiers.md).)
- **Not backlog-runnable.** The ticket must be in the current sprint first (all tiers).
- **Not code-first.** No production code exists before a failing test demands it.
- **Not a refactor pass.** Existing code and existing tests outside the spec's scope are left alone.
- **Not the status owner inside the agent.** The `claire-implementer` sets only `branch`; the skill owns `status` and all tracker writes.

## Related documents

- [`03-spec-approval.md`](03-spec-approval.md) — the gate that must pass before this step runs.
- [`02-spec.md`](02-spec.md) — produces the `spec.md`/`test-plan.md` that drive implementation.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../policies/branch-strategy.md`](../../policies/branch-strategy.md) — branch naming.
- [`../../policies/migration-policy.md`](../../policies/migration-policy.md) — expand/contract, reversibility, idempotency.
- [`../../policies/chaos-profiles.md`](../../policies/chaos-profiles.md) — the chaos profiles journey tests exercise.
- [`../submitting-changes.md`](../submitting-changes.md) — what happens to `submission.md` at MR time.
- [`../../../specs/TEMPLATE/submission.md`](../../../specs/TEMPLATE/submission.md) — the template the implementer drafts.
