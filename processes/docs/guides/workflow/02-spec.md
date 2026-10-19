# Workflow Step 02 — Spec

> Part of the per-step workflow guide series. This document details the **Spec** step. For the previous step see [`01-triage.md`](01-triage.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Spec (`/claire-spec`) |
| **Who** | Implementer (invokes the skill; the `claire-spec-author` subagent designs and writes) |
| **Consumes** | `specs/{ticket-id}/problem.md` + `metadata.yaml` from [Triage](01-triage.md) |
| **Produces** | `spec.md`, `test-plan.md`, `decisions.md`; status → `spec-in-review` |
| **Leads to** | **[Gate: Spec Approval](#where-this-goes-next)** — a human reviews and approves before any code is written |

---

## Purpose

The Spec step turns a triaged problem into a **complete, reviewable design with an executable BDD test plan** that an implementer can build via strict red-green-refactor TDD. It is where the *what* and *why* from Triage become a concrete *how* — grounded in the Zachman framework, decomposed with PRISM, and evaluated against the CLAIRE quality facets — **before** any production code exists.

Quality cascades from here: everything downstream (implementation, review, acceptance) is judged against this artifact. A vague spec produces vague code; the step exists to force the hard thinking up front, at the cheapest point to change course.

## Tier applicability

Not every change writes a full spec — the tier assigned at Triage decides the depth (see the matrix in [`../getting-started.md`](../getting-started.md) §2.3 and [`change-tiers.md`](../../policies/change-tiers.md)):

| Tier | Spec depth |
|---|---|
| **Trivial** | No spec. A `submission.md` serves as the record (release cuts excepted). |
| **Low** | `problem.md` only — acceptance criteria suffice; no Zachman grid, no PRISM. **This step is skipped.** |
| **Medium** | Full spec: `spec.md` + `test-plan.md` + `decisions.md` + `submission.md`; PRISM on every AC; **abbreviated** Zachman (System + Technology Model rows). |
| **High** | Full spec with **full** Zachman (all four rows) and PRISM on all ACs. |

The rest of this document describes the Medium/High path — i.e. when `/claire-spec` runs.

## Who does what

You drive the step from inside Claude Code:

```
/claire-spec <ticket-id>        # e.g. /claire-spec TT-6547
```

**Prerequisite:** `problem.md` and `metadata.yaml` must already exist (the issue is triaged). If not, the skill sends you to `/claire-triage` first.

The skill orchestrates; the deep-reasoning **`claire-spec-author`** subagent reads the code, designs the change, and writes the artifacts. At Medium/High tier the claire-spec-author may (High: does) invoke the **`claire-architect`** agent for a cross-boundary compatibility pre-flight, folding its Observed/Inferred/Unknown findings into the Compatibility Impact section.

## What happens

The `claire-spec-author` produces the design by working through a fixed sequence:

1. **Read the ground rules.** `CLAIRE_ORG.md` (org Zachman constants, the 3 always-on + 3 triggered mandatory facets, the precedence matrix), the [surface registry](../../policies/surface-registry.md), and the [deprecation policy](../../policies/deprecation-policy.md). The three triggered facets are **Data Integrity** (activates on owned-data capture), **Security Posture** (activates when the change touches authentication, authorization, PII, user input handling, or new client-side code) and **Backwards Compatibility** (activates on registered public surfaces) — each is evaluated when active or explicitly marked not-triggered.
2. **Read production & intent insights.** Filter [`production-insights.md`](../../agentic-sdlc/production-insights.md) and `intent-insights.md` for the ticket's domain entities / layers — prior findings force explicit observability seams and become extra open questions.
3. **Read all related source code** and **discover the project's patterns** (base classes, DTO mapping, validation, data access) so the design follows existing conventions rather than inventing new ones.
4. **Fill the Zachman grid** — org constants first, then project-specific facts across the six interrogatives (What/How/Where/Who/When/Why) at the applicable abstraction levels.
5. **Perform PRISM analysis.** Decompose every acceptance criterion into **P**reconditions, **R**ules, **I**nputs, **S**ide-effects, **M**utations — then derive edge cases mechanically by asking "what if this dimension is violated?"
6. **Derive observability seams** from the PRISM cells (IMPOSSIBLE_STATE from Preconditions, DECISION_DRIFT baselines from branching Rules, LINEAGE_GAP checkpoints from Side-effects/Mutations).
7. **Assess compatibility impact** against the surface registry — classify each affected surface as additive / modification / removal, evaluate breaking changes, draft deprecation plans, and register any new public surfaces.
8. **Analyze deployment compatibility** (when schema changes are proposed) — check old-code-vs-new-schema, new-code-vs-old-schema, and dual-write conflicts; classify as **Simple expansion** or **Prep-required** (needs an interim compatibility release before the migration).
9. **Evaluate against the mandatory facets** — Simplicity, Operability, Agentic DX (always-on), plus Data Integrity, Security Posture and Backwards Compatibility when triggered, and 0–2 optional facets; resolve any conflicts via the precedence matrix.
10. **Document the design** — per-file change descriptions with method/class signatures (never implementations), plus at least one **alternative considered** and identified **risks** with mitigations.
11. **Write the BDD test plan** — map ACs to Gherkin `Feature`s, generate happy-path + edge-case scenarios from PRISM, sequence them for TDD progression, and declare falsifiable journey invariants with chaos-profile coverage where the spec has external dependencies.

If the work turns out to violate a Non-Goal or Architecture Invariant in [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md), the claire-spec-author **stops** and recommends redirect or an intent amendment rather than specifying around it.

## Outputs

| Artifact | Content |
|---|---|
| [`specs/{ticket-id}/spec.md`](../../../specs/TEMPLATE/spec.md) | Zachman grid, PRISM decomposition per AC, facet evaluations, observability seams, existing-code analysis, proposed design, alternatives, compatibility & (if applicable) deployment-compatibility, risks, open questions. |
| [`specs/{ticket-id}/test-plan.md`](../../../specs/TEMPLATE/test-plan.md) | Framework-agnostic Gherkin scenarios, TDD implementation-order table, journey invariants, and compatibility-test specs. |
| [`specs/{ticket-id}/decisions.md`](../../../specs/TEMPLATE/decisions.md) | Initial decision log for choices made during authoring. |
| `metadata.yaml` | `status: spec-in-review`; spec `stage_effort` appended and accumulated into `actual_effort`. |
| [`surface-registry.md`](../../policies/surface-registry.md) | New public surfaces registered (if any). |

After the agent returns, the skill runs the **structural linter** and then projects the status change to Jira via `/claire-sync-jira` (posting the spec `stage_effort` as a per-stage worklog).

## Verification gates

The step has two verification layers before a human ever looks:

1. **Structural (mechanical).** `.claude/skills/claire-spec/verify-spec.sh {ticket-id}` asserts required sections exist, every mandatory facet is evaluated, PRISM and Gherkin are present, and no template placeholders remain. Failures are handed back to the claire-spec-author and the linter is **re-run until it exits zero.** `WARN` lines (e.g. an AC-count mismatch) don't block but are surfaced to the human gate.
2. **Design (judgment).** With the linter green, confirm every AC has a design element and a test case, the Zachman grid is populated where relevant, at least one alternative is documented, and risks are identified.

The linter verifies *structure*, not *soundness* — a green linter is necessary, not sufficient. Whether the design is *right* is the job of the human Spec Approval gate.

## Resolving open questions

The spec's **Open Questions** section captures every unknown the `claire-spec-author` could not settle during authoring — ambiguous requirements, undecided tradeoffs, and questions raised by production/intent insights. **All open questions must be resolved before the spec can be approved.** An unresolved open question is a design decision deferred into implementation, which is exactly what this step exists to prevent — so the Spec Approval gate does not accept a spec that still carries them.

Resolving them is a distinct move from authoring. After `/claire-spec` finishes, prompt with:

```
let's address any open questions
```

This starts an **interview** that walks through each open question one at a time, records the answer, and folds the resolution back into the spec (updating the affected Zachman/PRISM/design sections and the decision log, then clearing the question from Open Questions). When every question is resolved — or explicitly recorded as deferred with a rationale the human accepts — the spec is ready for the approval gate.

## Definition of done

- [ ] `spec.md`, `test-plan.md`, and `decisions.md` written under `specs/{ticket-id}/`.
- [ ] Every acceptance criterion has a PRISM decomposition and at least one happy-path **and** one edge-case Gherkin scenario.
- [ ] All 3 always-on mandatory facets evaluated, plus each triggered facet (Data Integrity, Security Posture, Backwards Compatibility) evaluated or explicitly marked not-triggered; conflicts resolved via the precedence matrix.
- [ ] Observability seams derived from PRISM (or explicitly "None").
- [ ] Compatibility impact assessed; surface registry updated; deployment-compatibility classified if schema changes.
- [ ] At least one alternative documented; risks identified with mitigations.
- [ ] `verify-spec.sh` exits zero; design-completeness confirmed.
- [ ] All open questions resolved (via `let's address any open questions`) or explicitly deferred with an accepted rationale — none left outstanding for approval.
- [ ] `status: spec-in-review`; spec effort recorded and projected to Jira.

## What this step is NOT

- **Not implementation.** Specs carry method/class **signatures**, never implementation bodies.
- **Not framework-specific tests.** The test plan is Gherkin; the implementer translates to the project's test framework at build time.
- **Not approval.** Passing the linter is the floor; a human still owns the Spec Approval gate that follows.
- **Not for every change.** Trivial/Low tier skip this step (see [Tier applicability](#tier-applicability)).

## Where this goes next

The spec lands at `status: spec-in-review` and goes to the **Spec Approval** human gate — a Reviewer or Business Analyst reviews and approves the design (and any `WARN` lines) **before any code is written**. The gate does not approve a spec with unresolved open questions — run `let's address any open questions` first (see [Resolving open questions](#resolving-open-questions)). On approval, the work advances to [Implementation](../getting-started.md). See [`../getting-started.md`](../getting-started.md) §2.3 for the gate and the per-tier matrix.

## Related documents

- [`01-triage.md`](01-triage.md) — the preceding step; produces the `problem.md`/`metadata.yaml` this step consumes.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier applicability matrix.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — the tier that sets this step's depth.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) · [`deprecation-policy.md`](../../policies/deprecation-policy.md) — the compatibility inputs.
- [`../../agentic-sdlc/prism-reference.md`](../../agentic-sdlc/prism-reference.md) — PRISM dimensions, seam derivation, the five-document model.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the intent the design is grounded against.
- [`../../../specs/TEMPLATE/spec.md`](../../../specs/TEMPLATE/spec.md) · [`test-plan.md`](../../../specs/TEMPLATE/test-plan.md) · [`decisions.md`](../../../specs/TEMPLATE/decisions.md) — the templates this step fills.
