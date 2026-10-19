# Workflow Step 03 — Gate: Spec Approval

> Part of the per-step workflow guide series. This is a **human gate**, not an agent-driven step — agents recommend, humans decide. For the step that produces the spec see [`02-spec.md`](02-spec.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. The authoritative gate definition is [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 1.

| | |
|---|---|
| **Gate** | Spec Approval (a.k.a. Gate 1 — Spec Review) |
| **Who** | Reviewer or Business Analyst (a human) |
| **You are approving** | The **design**, not the implementation |
| **Consumes** | `spec.md` + `test-plan.md` + `decisions.md` at `status: spec-in-review` |
| **Outcome** | **Approve** (→ Implementation), **Direct-edit**, or **Comment & regenerate** |

---

## Purpose

This gate exists so that **a human retains architectural ownership before any code is written.** The claire-spec-author produced a structurally complete artifact; the mechanical linter already confirmed the structure. What no AI can supply is *judgment*: does this design solve the real problem, fit the real system, and commit only to what we actually need to decide now?

You are approving the **design on paper**. Implementation correctness is a later gate ([Code Review](../getting-started.md)); intent-in-practice is later still (Deploy Validation). Here, the question is: **is this the right thing to build, and does the design hold together?**

## When this gate applies

Only **Medium** and **High** tier changes reach this gate. Trivial changes need only CI; Low changes go straight to a single Code Review with no separate spec approval. See the tier matrix in [`../getting-started.md`](../getting-started.md) §2.3 and [`change-tiers.md`](../../policies/change-tiers.md).

## The non-negotiable: maintain your mental model

**You must be able to place this change within the overall system architecture.** If the spec does not give you enough to extend your mental model — which bounded contexts are involved, which flows are affected, how data moves, what invariants hold — **reject it and request regeneration.** This is not optional. An approved spec that no human fully understands is a change that erodes the system.

The standard: after approving, you could explain to a colleague what this change does to the *system* — not just the code — without re-reading the spec. If you can't, you don't yet understand it well enough to approve.

## What to do

### Step 1 — Orient in the architecture (do this first)

Before evaluating anything else, answer these using [`SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) and the [flow docs](../../flows/):

1. Which **bounded context(s)** does this spec operate within?
2. Which **business flow(s)** does it modify or extend?
3. What does it **assume about adjacent contexts** — data ownership, event contracts, invariants?

If the spec does not make these answers obvious, **stop and reject** with feedback: *"I cannot place this change in the system architecture. Clarify which context owns this, which flows are affected, and what cross-boundary assumptions exist."* If the change introduces a new boundary/service/flow that you cannot trace in `SYSTEM_OVERVIEW.md` or `docs/flows/`, require that documentation be added before you approve. If it modifies an existing flow whose doc is stale or missing, require the doc be updated as part of the work.

### Step 2 — Judge what only a human can

- **Architectural placement** — Can you trace this change through the system? Does it fit where the spec says it fits?
- **Business-intent fidelity** — Does the spec actually solve the stakeholder's problem? Would the person who raised the issue recognize it as their request? Was anything lost in translation?
- **Organizational context** — Roadmap conflicts, team capacity, timing, political constraints.
- **Decision timing** — Are we committing to something we don't need to decide yet?

### Step 3 — Apply the maturity lens

Weight your attention to where the project sits:

- **Greenfield / early:** Is this the *minimum* spec to ship and learn? Are we making premature architectural commitments? Could a decision be deferred and still ship safely? Err toward simplicity.
- **Mature / extending:** Does this fit the existing architecture? Are cross-cutting concerns (auth, observability, data contracts) addressed? Does the design respect existing boundaries? Err toward architectural discipline.

### Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **Architectural clarity** | **Can you identify which context(s) and flow(s) this touches? If not, reject.** |
| Zachman grid | Are the right cells filled? Do lower levels align with higher? |
| PRISM decomposition | Is every acceptance criterion decomposed? Are edge cases derived, not hand-waved? |
| Facet evaluation | Are the facet assessments honest? Are any violations justified? |
| Compatibility impact | Are public-surface changes identified? Deprecation plans drafted? Surface registry updated? |
| Proposed design | Does it fit the architecture? Are the code signatures correct and idiomatic? |
| Alternatives | Was at least one reasonable alternative genuinely considered? |
| Test plan | Does the Gherkin coverage match the PRISM output? Are compatibility tests specified? |
| Journey invariants | If declared: are they falsifiable, traced to a PRISM Rules/Mutations cell, and correctly mapped to the applicable chaos profiles? |

The AI already handled the mechanical half of this list (completeness, consistency, coverage). Your review focuses on the judgment half — placement, fidelity, taste, and timing.

## Your decision

Reach one of three outcomes:

| Outcome | When | How |
|---|---|---|
| **Approve** | The design is sound and you can place it in the system. | Record approval (below); the work advances to Implementation. |
| **Direct edit** | Small corrections — naming, wording, minor restructuring. | Edit `spec.md` / `test-plan.md` directly on the MR / in the branch. |
| **Comment & regenerate** | Larger rethinks, missing context, or "I don't understand why X was chosen." | Leave comments describing what's wrong or what question needs answering, then have the author run `/claire-spec` to regenerate the affected sections. PRISM re-derives edge cases from the revised decomposition; re-review the result. |

Choose regeneration over direct edit when the change is structural enough that PRISM decomposition or Zachman alignment would be affected — it keeps the spec internally consistent.

## Recording the decision

- The review discussion is mirrored into [`submission.md`](../../../specs/TEMPLATE/submission.md) (`## Discussion`) so the archive carries the record after merge — comment in the forge, but expect the substance in `submission.md`. See [`submitting-changes.md`](../submitting-changes.md).
- On **Approve**, update `specs/{ticket-id}/metadata.yaml` **on the MR branch** — set `status: spec-approved` and `spec_approved_at:` to the approval date. The value only needs to be an ISO 8601 date (`YYYY-MM-DD`, e.g. `2026-07-05`) — a bare calendar date is sufficient, not a precise timestamp; a full ISO 8601 date-time is accepted but not required. Committing these on the branch is what makes the spec **land on the integration branch already marked approved** when the MR merges, rather than leaving the merged spec showing `spec-in-review`. Verify the field name is `spec_approved_at` against [`metadata.yaml`](../../../specs/TEMPLATE/metadata.yaml) before editing.
- Project the status change to Jira (`/claire-sync-jira`) for `{ticket-id}`.
- On a send-back, the ticket stays `spec-in-review` until the regenerated spec returns for re-review.

## What this gate is NOT

- **Not code review.** You are judging the design, not an implementation — there is no code yet.
- **Not a structural check.** The `verify-spec.sh` linter already passed; a green linter is the floor, not your bar.
- **Not a rubber stamp.** "I can't place this in the architecture" is a valid — and required — rejection.
- **Not for every change.** Trivial/Low tier never reach this gate.

## Related documents

- [`02-spec.md`](02-spec.md) — the preceding step; produces the artifacts you review here.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier gate matrix.
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of all four human gates (§Gate 1 is this one).
- [`../../SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) · [`../../flows/`](../../flows/) — what you orient against in Step 1.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — which tiers reach this gate.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) — the compatibility register the spec must keep current.
- [`../submitting-changes.md`](../submitting-changes.md) — how the change proposal and discussion are recorded.
