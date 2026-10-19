# Workflow Step 05 — Gate: Code Review

> Part of the per-step workflow guide series. This is a **human governance gate** (Gate 2), assisted by the `/cadence-review` skill — AI agents execute the mechanical and adversarial first pass, and an accountable human makes the approval decision. For the preceding step see [`04-implementation.md`](04-implementation.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Authoritative gate specification: [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 2.

| | |
|---|---|
| **Gate** | Code Review (Gate 2) |
| **Who** | Reviewer (a human), assisted by `cadence-reviewer` + `offload_deep_review` via `/cadence-review` |
| **You are approving** | The **implementation against its approved contract** (`spec.md` at Medium/High tier; `problem.md` ACs at Low tier) |
| **Consumes** | The implementation MR/branch (`impl/{type}/{id}`) at `status: in-review`, its approved contract, and `submission.md` |
| **Outcome** | **Approve**, **Request Changes**, or **Needs Discussion** |

---

## Purpose

Gate 2 verifies that the implementation **faithfully, safely, and cleanly realizes its approved specification** — and that a human reviewer understands how the code change affects the live system. The AI review pipeline (`offload_deep_review` + `cadence-reviewer`) clears the exhaustive mechanical and adversarial checks (AC-to-code mapping, scenario test coverage, Engineering Pillar compliance, comment discipline `C1`–`C8`, and silent-failure probing), freeing the human reviewer to focus on what only a human can supply: production intuition, domain nuance, concurrency reasoning, and long-term maintainability.

At Gate 2 you are evaluating the **implementation against the contract** — not relitigating the approved design (that was [Gate 1: Spec Approval](03-spec-approval.md)) and not making the final repository-wide stewardship call (that is [Gate 3: Maintainer Acceptance](06-maintainer-acceptance.md) for Medium/High tiers).

## When this gate applies

Every change tier that modifies source code or configuration passes through Code Review, with rigor scaled to the tier (see [`change-tiers.md`](../../policies/change-tiers.md) and [`../getting-started.md`](../getting-started.md) §2.3):

- **Trivial** — documentation-only changes auto-merge on green CI (no human reviewer); configuration value changes, dependency bumps, and release cuts require **one** human reviewer.
- **Low** — **one** human reviewer; Gate 2 is the **sole human gate** at Low tier (no separate Gate 1 Spec Approval or Gate 3 Maintainer Acceptance), so `/cadence-review` also serves as the primary follow-up filing point for `out-of-scope-defect` findings.
- **Medium / High** — Gate 2 sits between Gate 1 (Spec Approval) and Gate 3 (Maintainer Acceptance).

## Automatic Local Offload during Code Review (`offload_deep_review` & `offload_log_triage`)

Before `cadence-reviewer` synthesizes its formal review verdict, `/cadence-review` automatically invokes CADENCE's read-only local hardware coprocessors (`enable_write_tools: false`) to run fast mechanical pre-scans:

1. **Advisory Mechanical Pre-Scan (`offload_deep_review` on `local-moe-hybrid` / `local-12b-gpu`):** Scans the diff against `spec.md` / `test-plan.md` to check the Agentic DX `< 400`-line file ceiling, comment discipline rules `C1`–`C8` (`docs/policies/comment-discipline.md`), CHORD observability seam wiring (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`), and non-blocking finding classification (`docs/policies/finding-classes.md`).
2. **Test & Gate Runner Verification (`offload_log_triage` / `log-triage` on `local-fast-cpu`):** Compacts test suite and `run-gates.sh` verification logs at 0 MB VRAM while preserving verbatim assertion output and `file:line` coordinates (with full raw output written to `/tmp/agy-last-triage.log`).

Every advisory finding surfaced by `offload_deep_review` is independently verified by the primary `cadence-reviewer` reasoning model before being included in the review report.

## Step 1 — Run the AI review

Launch the governed review pass from your agentic CLI runtime (`.agents/skills/cadence-review/` or `.gemini/` on Antigravity):

```
/cadence-review <MR-number-or-branch>     # e.g. /cadence-review 142   or   /cadence-review impl/feature/CTS-40
```

> **Always run `/cadence-review`, never a generic `/code-review` command.** Gate 2 requires the **CADENCE** `/cadence-review` skill — which resolves the integration branch from `CADENCE_ORG.md#branch-strategy-binding`, evaluates the diff against the ticket's approved contract (`spec.md` + `test-plan.md` at Medium/High tier, or `problem.md`'s Acceptance Criteria at Low tier), classifies every non-blocking finding under [`finding-classes.md`](../../policies/finding-classes.md), processes `out-of-scope-defect` follow-up candidates, and logs `code-review` `stage_effort` in `metadata.yaml`. A generic IDE diff checker lacks spec awareness, finding classification, and governance tracking, and **never satisfies Gate 2**.

`/cadence-review` resolves the ticket ID from the final `/`-delimited segment of the branch name (`impl/{type}/{id}`), computes the diff against the bound integration branch (`CADENCE_ORG.md` §15), runs the `offload_deep_review` pre-scan, and delegates to the read-only **`cadence-reviewer`** subagent. Because its inputs are repository-resident (`git diff` and `submission.md`), it requires no proprietary forge API tokens. `cadence-reviewer` verifies:

- **Contract compliance** — every acceptance criterion in `spec.md` (or `problem.md` at Low tier) is implemented completely.
- **Test coverage & scope** — every Gherkin scenario in `test-plan.md` (or AC at Low tier) has a passing test tagged per `C5`, and no test reads forbidden governance paths ([`test-scope.md`](../../policies/test-scope.md)).
- **Engineering Pillars** — Simplicity, Operability (structured JSON logs + CHORD seams), Agentic DX (`< 400`-line ceiling), Data Integrity (audit records with actor from auth context), Security Posture, and Backwards Compatibility.
- **Architecture & comment discipline** — Clean Architecture layer boundaries, `C7` boundary comments on cross-boundary files/functions, and `C1`–`C8` comment rules ([`comment-discipline.md`](../../policies/comment-discipline.md)).
- **Documentation freshness** — flow/system doc updates or explicit acknowledgment, plus the two-search reconciliation sweep record (`doc-maintenance-policy.md`; an affirmative flow-doc-absence claim without a recorded search return is **blocking** per BTG-293).
- **Migration safety** — schema/data separation, reversibility, and idempotency guards ([`migration-policy.md`](../../policies/migration-policy.md)).
- **The adversarial lens** — actively hunts for **silent failure paths**: broad catch blocks, silent fallback defaults that violates Behavior 5, unvalidated third-party session state (`CP-11`), and **unchanged callers whose contract the diff subtly altered**.

Every non-blocking observation emitted by `cadence-reviewer` carries one of the five mandatory lowercase class tokens from [`finding-classes.md`](../../policies/finding-classes.md): `out-of-scope-defect`, `adr-owed`, `nit`, `hygiene`, or `observation`. At Step 6 of `/cadence-review`, any `out-of-scope-defect` candidate is deduplicated against `specs/` and `archive/` and presented to the human reviewer for confirmation to file via `/cadence-triage --file-only <draft-path>`.

> **Re-run `/cadence-review` after rebasing onto new upstream changes.** Whenever an implementation branch is rebased onto integration-branch commits that landed after the initial review, run `/cadence-review` again so cross-change interaction defects are caught before merge.

## Step 2 — Orient in the architecture (before reading the diff)

Before inspecting individual code files, confirm from `submission.md` and `spec.md` alone:

1. Which **bounded context** does this MR modify?
2. Which **business flow(s)** (`docs/flows/`) does it participate in?
3. Does `submission.md`'s `## Description` state both clearly?

If you cannot answer those three questions immediately, **return the MR for clarification.** An MR you cannot place in the system architecture is an MR you cannot review safely.

## Step 3 — Judge what only a human can

With the mechanical checklist covered by `offload_deep_review` and `cadence-reviewer`, focus your human review on:

- **System comprehension** — Can you explain to a colleague how this MR changes system behavior without looking at the diff?
- **Subtle production correctness** — Will this hold up under real production traffic, skewed tenant data sizes, and concurrent requests? The AI checks *code-matches-spec*; you check *code-matches-production-reality*.
- **Unwritten domain invariants** — Edge cases or business rules that were missed during spec authoring (and if you spot one, make sure it gets added to `AGENTS.md` or `spec.md`).
- **Operational hazards** — Lock contention, unbounded in-memory collections, N+1 query patterns, or missing backpressure.
- **Cognitive & maintenance load** — Will an on-call engineer be able to diagnose and debug this code at 2 a.m. six months from now?

## Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **Architectural orientation** | **Can you state which bounded context and flow this MR belongs to? If not, request changes.** |
| Contract compliance | Does every AC have a complete, working implementation? |
| Test coverage & `test-scope.md` | Does every scenario have a `C5`-tagged test? Are compatibility/chaos tests present? Zero tests reading governance docs? |
| Engineering Pillar compliance | All files `< 400` lines? Audit trail complete? CHORD seams (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) wired? |
| TDD commit discipline | Does the branch commit log show incremental red-green-accumulate commits per scenario? |
| Architecture & `comment-discipline.md` | Layer boundaries respected? `C7` boundary headers present? No `C3` diff narrative comments? |
| Security posture | Auth gates enforced? Untrusted inputs validated? Zero secret/PII leaks? |

## Your decision

| Outcome | Meaning |
|---|---|
| **Approve** | Implementation matches the approved contract and production reality, all blocking issues are zero, and follow-up dispositions are recorded. Advances to [Gate 3: Maintainer Acceptance](06-maintainer-acceptance.md) (Medium/High) or [Merge](07-merge.md) (Low/Trivial). |
| **Request Changes** | One or more blocking defects remain (silent failure paths, missing AC/scenario coverage, `< 400`-line breach, forbidden test subject, or unrecorded flow-doc-absence sweep). The author fixes on the branch and re-runs `/cadence-review`. |
| **Needs Discussion** | A design conflict or cross-context question requires resolution before a verdict (follow [`conflict-resolution.md`](../../policies/conflict-resolution.md)). |

Silent or partial failure paths are **always blocking**, even if they were overlooked during Gate 1.

## Recording the decision

- Mirror the review assessment, AC checklist, classified non-blocking findings, and human verdict into [`submission.md`](../../../specs/TEMPLATE/submission.md) (`## Discussion`), and record confirmed follow-up dispositions (`Filed`, `Duplicate of <id>`, `Folded into <id>`, `None owed`, `Declined`, or `Deferred` plus the non-blocking class tally) under `## Resolution -> Follow-ups created`.
- `/cadence-review` appends the `code-review` `stage_effort` entry to `metadata.yaml`, accumulates `actual_effort`, and projects to the bound tracker (`CADENCE_ORG.md` §9). **Approving Gate 2 does not alter `metadata.yaml`'s `status`** — the ticket remains `in-review` until Merge (`07-merge.md`).

## What this gate is NOT

- **Not Gate 1 design review.** If Gate 2 uncovers a fundamental flaw in the approved `spec.md`, follow Scenario 1 of [`conflict-resolution.md`](../../policies/conflict-resolution.md) to reopen the spec rather than silently drifting the code away from `spec.md`.
- **Not an autonomous AI sign-off.** `cadence-reviewer` recommends; an accountable human approves.
- **Not a status flip.** `status` stays `in-review` through Gate 2 and Gate 3 until the MR merges into the integration branch.
- **Not skippable for source-code changes.** Every code change requires at least one human code reviewer.

## Related documents

- [`04-implementation.md`](04-implementation.md) — the preceding step that produces the implementation branch and `submission.md`.
- [`06-maintainer-acceptance.md`](06-maintainer-acceptance.md) — Gate 3 (next for Medium/High tier changes).
- [`07-merge.md`](07-merge.md) — Merge step (next for Low/Trivial tier changes after Gate 2 approval).
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of all four human gates (§Gate 2 is this gate).
- [`../../policies/finding-classes.md`](../../policies/finding-classes.md) — the five non-blocking finding classes and follow-up routing rules.
- [`../../policies/comment-discipline.md`](../../policies/comment-discipline.md) · [`../../policies/test-scope.md`](../../policies/test-scope.md) · [`../../policies/doc-maintenance-policy.md`](../../policies/doc-maintenance-policy.md) — normative policies enforced at Gate 2.
- [`../submitting-changes.md`](../submitting-changes.md) — how review discussions and dispositions are recorded in `submission.md`.
