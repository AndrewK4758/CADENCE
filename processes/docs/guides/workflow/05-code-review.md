# Workflow Step 05 — Gate: Code Review

> Part of the per-step workflow guide series. This is a **human gate** (Gate 2), assisted by the `/claire-review` skill — the AI does the mechanical pass; a human decides. For the preceding step see [`04-implementation.md`](04-implementation.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Authoritative gate definition: [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 2.

| | |
|---|---|
| **Gate** | Code Review (a.k.a. Gate 2) |
| **Who** | Reviewer (a human), assisted by the `claire-reviewer` agent via `/claire-review` |
| **You are approving** | The **implementation against the spec** |
| **Consumes** | The implementation MR/branch at `status: in-review`, its approved spec, and `submission.md` |
| **Outcome** | **Approve**, **Request Changes**, or **Needs Discussion** |

---

## Purpose

This gate confirms that the code **does what the approved spec said, correctly and safely** — and that a human still understands what it does to the system. The AI reviewer handles the mechanical half (AC-to-code mapping, coverage, patterns, obvious security holes); the human handles the half no AI can: subtle correctness, production instincts, domain knowledge, and design taste.

You are approving the **implementation against the spec** — not the design (that was [Spec Approval](03-spec-approval.md)) and not intent-in-practice (that's Deploy Validation).

## When this gate applies

Every tier that changes code passes a code review, but the weight differs (see [`change-tiers.md`](../../policies/change-tiers.md) and the matrix in [`../getting-started.md`](../getting-started.md) §2.3):

- **Trivial** — documentation-only auto-merges on green CI (no reviewer); config/dependency/release-cut changes get **one** reviewer.
- **Low** — **one** reviewer; this is the only human gate at this tier (no separate spec approval).
- **Medium / High** — code review sits between Spec Approval and Maintainer Acceptance.

## Step 1 — Run the AI review

Kick off the mechanical pass from inside Claude Code:

```
/claire-review <MR-number-or-branch>     # e.g. /claire-review 142   or   /claire-review impl/feature/CTS-40
```

> **Use `/claire-review`, not `/code-review`.** This gate runs the **CLAIRE** `/claire-review` skill — it reviews the MR **against its approved spec** (AC-to-code mapping, Gherkin coverage, facet compliance) and records the `stage_effort` and verdict on the ticket. That is **not** the same as Claude Code's built-in `/code-review`, which is a general-purpose diff review for correctness/quality bugs with no spec, no ticket, and no effort tracking. The built-in tool is a fine ad-hoc aid, but it **does not satisfy this gate** — only `/claire-review` does.

The skill resolves the reference to a branch and ticket, diffs it against `main`, and delegates to the read-only **`claire-reviewer`** agent. Its inputs are forge-neutral — `git diff` and `submission.md` — so no forge API access is needed. The agent checks:

- **Spec compliance** — each acceptance criterion has a corresponding implementation.
- **Test coverage** — each Gherkin scenario has a test; compatibility tests present where required.
- **Architecture** — Clean Architecture layer boundaries, service patterns, data access through repositories.
- **Code quality** — naming, error handling, performance.
- **Security** — authorization, input validation, no data exposure.
- **Migration safety** — reversible + idempotent, if applicable.
- **The adversarial lens** — it probes how the change can fail *silently*: fallbacks/stubs that mask defects, broad `except` clauses, assumptions about consumed code, and **unchanged code whose contract the diff silently changed** (the class diff-only review misses by construction). It does **not** accept a spec's "out of scope / can't happen at this scale" labels at face value — it recomputes the bound against real numbers.

The agent emits a verdict, an AC checklist, and inline comments. **It is read-only** — it writes no code and changes no status; only the review discussion and the code-review `stage_effort` are recorded (see [Recording](#recording-the-decision)).

> **Re-review after integration.** If the branch is later rebased onto dependencies that weren't present at review time (e.g. another ticket landed on `main`), run `/claire-review` again — integration bugs from a now-present collaborator are invisible in a single-branch diff.

## Step 2 — Orient in the architecture (before reading the diff)

Answer, from the MR description and spec reference alone:

1. Which **bounded context** does this MR modify?
2. Which **flow(s)** does it participate in?
3. Does the MR description state these clearly?

If you cannot answer, **send it back.** An MR you cannot place in the system is one you cannot meaningfully review. The standard: after reading the MR, you could explain to a colleague what it does to the *system* — not just the code — without re-reading the diff.

## Step 3 — Judge what only a human can

The AI already cleared the mechanical checklist; spend your attention here:

- **System comprehension** — Can you explain the MR's effect on the system? If not, you don't understand it well enough to approve.
- **Subtle correctness** — Will it actually work in production? Under load? With real data? The AI verifies code-matches-spec; you verify code-matches-reality.
- **Domain knowledge** — Business rules that live in your head, not in the spec.
- **Operational instincts** — "This will time out on the large tenant." "This will deadlock under concurrent writes."
- **Team awareness** — Who else is touching this area? Will it conflict with in-flight work? Does it create a maintenance burden?
- **Design taste** — Right abstraction? Readable in six months? Would you want to debug it at 2am?

## Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **Architectural orientation** | **Can you state which context and flow this MR belongs to? If not, send it back.** |
| Spec compliance | Does each AC have a corresponding implementation? |
| Test coverage | Does each Gherkin scenario have a test? Compatibility tests present? |
| Facet compliance | File sizes, audit records, structured logging, observability, no anti-patterns. |
| TDD discipline | Does the commit history show one red-green cycle per scenario? |
| Architecture | Layer boundaries, service patterns, data access through repository. |
| Security | Auth policies, input validation, no data leaks. |

## Your decision

| Outcome | Meaning |
|---|---|
| **Approve** | Implementation matches the spec and reality; you can place it in the system. It advances toward Maintainer Acceptance (Medium/High) or merge (Low). |
| **Request Changes** | Blocking issues (silent-failure paths, missing coverage, spec gaps). The author fixes on the branch and re-requests review. |
| **Needs Discussion** | The right resolution isn't clear — a design question or cross-team concern to resolve before a verdict. |

Silent/partial-failure paths are **blocking**, even when they stem from an approved decision.

## Recording the decision

- The review — verdict, AC checklist, inline comments — is posted on the forge thread and **mirrored into [`submission.md`](../../../specs/TEMPLATE/submission.md) `## Discussion`** so the archive carries it after merge. See [`submitting-changes.md`](../submitting-changes.md).
- The `/claire-review` skill appends a `code-review` `stage_effort` entry to `metadata.yaml` and projects it to Jira (`/claire-sync-jira`). **The review verdict itself is not a status change** — the ticket stays `in-review`; the `claire-reviewer` agent makes no other repo write.

## What this gate is NOT

- **Not design review.** The design was approved at Gate 1; here you judge the implementation of it.
- **Not the AI's call.** `/claire-review` recommends; the human decides. A green AI pass does not auto-approve.
- **Not a status transition.** Approving here does not itself flip `status`; merge and the maintainer gate handle progression.
- **Not skippable for code changes.** Even Low-tier changes get one human reviewer; only documentation-only Trivial changes auto-merge on CI.

## Related documents

- [`04-implementation.md`](04-implementation.md) — produces the MR reviewed here.
- [`03-spec-approval.md`](03-spec-approval.md) — the design gate this one builds on.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of the four gates (§Gate 2 is this one).
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — how many reviewers each tier requires.
- [`../../policies/branch-strategy.md`](../../policies/branch-strategy.md) — branch naming used to resolve the ticket.
- [`../submitting-changes.md`](../submitting-changes.md) — how the review is recorded in `submission.md`.
