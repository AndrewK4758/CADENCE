# Workflow Step 06 — Gate: Maintainer Acceptance

> Part of the per-step workflow guide series. This is a **human gate** (Gate 3), assisted by the `/claire-maintain` skill — the AI produces an 8-dimension assessment; a human decides. For the preceding gate see [`05-code-review.md`](05-code-review.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Authoritative gate definition: [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 3.

| | |
|---|---|
| **Gate** | Maintainer Acceptance (a.k.a. Gate 3) |
| **Who** | Reviewer / Maintainer (a human), assisted by the `claire-maintainer` agent via `/claire-maintain` |
| **You are approving** | The MR's **project-level impact** — not code correctness (that was Gate 2) |
| **Consumes** | A code-reviewed MR, its approved spec, `submission.md`, and the project's governing docs |
| **Outcome** | **Accept**, **Postpone**, or **Reject** |

---

## Purpose

This is the **last gate before merge**, and the one that guards the project as a whole. Code review confirmed the change is correct *in itself*; maintainer acceptance asks whether it is right *for the project* — does it stay compatible, fit the architecture, serve the mission, carry acceptable maintenance cost, and ship cleanly? You are the guardian of architectural integrity: the last line of defense against changes nobody fully understands at the system level.

You are approving **project-level impact**, not code correctness. Do not re-run the code reviewer's work — assume correctness was validated at Gate 2.

## When this gate applies

Only **Medium** and **High** tier changes reach this gate. Trivial and Low tier changes merge after code review with no separate maintainer acceptance (see [`change-tiers.md`](../../policies/change-tiers.md) and the matrix in [`../getting-started.md`](../getting-started.md) §2.3).

## Prerequisite: code review is complete

`/claire-maintain` verifies that the **claire-reviewer has approved** (a summary verdict on the forge thread or in `submission.md` `## Discussion`) and that a spec exists at `spec-approved` or later. If code review isn't done, it **stops** and sends you to `/claire-review` first.

## Step 1 — Run the AI assessment

Kick off the structured evaluation from inside Claude Code:

```
/claire-maintain <MR-number-or-branch>     # e.g. /claire-maintain 142   or   /claire-maintain feature/26.5.TT/TT-6547
```

The skill resolves the reference, diffs against `main`, and delegates to the **`claire-maintainer`** agent, which evaluates across **eight dimensions** — grounded in the surface registry, ADRs, `PROJECT_INTENT.md`, and `CLAIRE_ORG.md`, with every finding citing specific evidence:

| # | Dimension | Verdict scale |
|---|---|---|
| 1 | **Backwards compatibility & API stability** | Compatible · Breaking-with-migration · Breaking-without-migration |
| 2 | **Architectural integrity** (ADRs + intent invariants) | Consistent · Minor drift · Significant drift |
| 3 | **Project-intent alignment** (mission / scope / non-goals) | Core mission · Adjacent · Tangential · Out of scope |
| 4 | **Maintenance cost & complexity budget** | Low · Medium · High |
| 5 | **Security impact & threat surface** | No change · Expanded (managed) · Expanded (unmanaged) |
| 6 | **Release readiness** (CHANGELOG, deprecation, migration, rollback) | Ready · Needs documentation · Not ready |
| 7 | **Dependency & supply-chain health** | Healthy · Concerns noted · Blocked |
| 8 | **Documentation currency** (flow docs, SYSTEM_OVERVIEW) | Current · Needs update · Stale |

The agent returns a full **Maintainer Assessment** — a recommendation (Accept/Postpone/Reject), a decision brief, per-dimension verdicts with evidence, blocking issues, non-blocking observations, positive highlights, and any drafted artifacts (CHANGELOG entry, migration plan, deprecation notices). It **recommends only** — it never merges, and its write scope is limited to `specs/`, `docs/`, and `CHANGELOG.md` (never source or tests).

**Blocking is reserved** for real project-level risks: backwards-compatibility violations without a migration path, architecture/ADR or intent-invariant violations, security regressions, un-elapsed deprecation periods, migrations without proven rollback, or off-mission scope creep. Style preferences and minor improvements never block here.

## Step 2 — Orient in the architecture (before evaluating)

Using [`SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md):

1. Locate the bounded context(s) and flow(s) this MR touches.
2. Verify the dependency graph and interaction map still hold after this change merges.
3. If the MR adds a new service, context, or flow — can you **draw it on the existing map**? If not, the documentation is incomplete and must be updated before acceptance.

If the MR's impact on the system architecture is unclear, **postpone** with feedback requesting architectural clarification.

## Step 3 — Judge what only a human can

- **Boundary decisions** — For a mature project: should this functionality live here, or be pushed to the edges (a plugin, sidecar, separate service, another repo)? The AI flags complexity growth; only you make the boundary call.
- **Strategic fit** — Core mission, adjacent, or scope creep? Does it move the project toward or away from its long-term shape?
- **Maintenance trajectory** — Not just "maintainable today" but "where does this put us in six months if we keep adding at this rate?"
- **Team & org context** — Ownership boundaries, capacity for ongoing maintenance, political implications of taking on new responsibility.

**Maturity lens:** greenfield — is this premature structure or abstraction before the domain is understood? Keep it simple enough to throw away. Mature — is this the right home for the code? Are we making the core harder to reason about?

## Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **System model intact** | **Can you draw this change on the system map? Does SYSTEM_OVERVIEW.md still hold? If not, require update.** |
| Backwards compatibility | Public-surface changes handled with deprecation plans? Surface registry updated? |
| Architectural integrity | Follows existing ADRs? Any new pattern justified? |
| Project-goal alignment | Core mission, adjacent, or scope creep? |
| Maintenance cost | How many new dependencies, patterns, or infrastructure pieces? |
| Security impact | Attack-surface changes, trust-boundary shifts, supply-chain risk? |
| Release readiness | CHANGELOG updated? Deprecation notices? Migration + rollback plan? |
| Dependency health | Licenses compatible? Known vulnerabilities? Maintained? |

## Step 5 — Process follow-up tickets from the decision log

Follow-up work discovered earlier in the workflow is **deferred to you, not filed mid-stream** — the implementer is directed to record suggested follow-ups in `specs/{ticket-id}/decisions.md` rather than create tickets ([`04-implementation.md`](04-implementation.md)), and the claire-migration-author logs deferred contraction migrations there as `DEC-N` entries tagged `contraction-pending`. **You own the disposition of every one of them.** Filing ticket creation here keeps the backlog coherent and puts the extract/defer/drop judgment where it belongs.

Read `decisions.md` and, for each suggested follow-up, decide and act:

- **Extract** — genuine, on-mission work that belongs in its own effort: **file a follow-up ticket** in the tracker (Jira). Deferred contraction migrations almost always land here — they are scheduled work, not optional. Link the new ticket back to this one.
- **Defer** — worth doing but not now: leave it in `decisions.md` with your rationale and the condition that would make it actionable, or file it and mark it deferred per your backlog convention.
- **Drop** — not worth doing: record the decision and the reason so it isn't re-raised.

Do **not** silently ignore the follow-up entries. Record your disposition for each in `decisions.md`, and list every ticket you create under **`Follow-ups created`** in `submission.md`'s `## Resolution` so the archive carries the linkage.

> **Contraction is not optional.** A `contraction-pending` tag means destructive schema cleanup was deferred out of an expand migration. That work must become a tracked follow-up ticket before you accept — dropping it leaves permanent schema bloat.

## Your decision

`/claire-maintain` is interactive — it presents the assessment and asks you to choose:

| Outcome | Meaning | What the skill records |
|---|---|---|
| **Accept** | Approve for merge. | Sets `maintainer_approved_at`; writes any drafted CHANGELOG / migration / deprecation docs. |
| **Postpone** | Defer to a later release. | Logs the reason in `decisions.md`; adds `postponed_at` + `postpone_reason` to metadata. |
| **Reject** | Do not merge. | Logs the reason + author guidance in `decisions.md`; adds `rejected_at` + `rejection_reason`. |

The human may have context the AI lacks — the recommendation is never assumed to be the decision.

## Recording the decision

- On **every** path (Accept/Postpone/Reject) the skill records a `maintainer` `stage_effort` entry and accumulates it into `actual_effort` — the evaluation cost is real regardless of verdict.
- The decision fields above are written to `metadata.yaml` / `decisions.md`, then projected to Jira (`/claire-sync-jira`).
- Discussion is mirrored into [`submission.md`](../../../specs/TEMPLATE/submission.md) (`## Resolution` is filled by the maintainer / archivist) so the archive carries the record.

## What this gate is NOT

- **Not code review.** Correctness was Gate 2; here you judge project-level impact. Don't repeat the reviewer's work.
- **Not the AI's call.** `/claire-maintain` recommends and presents evidence; the human accepts/postpones/rejects.
- **Not a merge.** The maintainer never merges — acceptance authorizes it; the merge itself is a separate action.
- **Not for every change.** Trivial/Low tier never reach this gate.

## Related documents

- [`05-code-review.md`](05-code-review.md) — the gate that must pass before this one.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of the four gates (§Gate 3 is this one).
- [`../../SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) — the system map you orient against.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — which tiers reach this gate.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) · [`deprecation-policy.md`](../../policies/deprecation-policy.md) · [`migration-policy.md`](../../policies/migration-policy.md) — the compatibility/release inputs.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the mission/scope/non-goals the change is judged against.
- [`../submitting-changes.md`](../submitting-changes.md) — how the decision is recorded in `submission.md`.
