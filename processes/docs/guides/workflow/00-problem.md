# Workflow Step 00 — Problem

> Part of the per-step workflow guide series. This guide covers the **Problem** step — the entry point of the CADENCE lifecycle. For the end-to-end workflow map, see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Problem (the intent issue) |
| **Who** | Anyone (the requester / contributor) |
| **Produces** | An intent issue carrying a maintainer verdict of *Proceed* (or *Modify*) |
| **Leads to** | [Triage](#where-this-goes-next) — where the repository spec stub `specs/{ticket-id}/problem.md` is initialized |

---

## Purpose

The Problem step answers one fundamental question before any engineering effort is invested: **is this work worth doing, and does it belong in this repository?** It frames *what is broken or missing* and *what a successful outcome looks like* — in business and user terms rather than implementation details — and secures an explicit go/no-go ruling from the maintainer.

Think of it as the **social contract** at the front door of the workflow: *"I intend to solve this problem; does that align with project intent?"* Nothing downstream — no specification, no code, no review — begins until this contract is confirmed. Keeping this step to three to five sentences ensures that an out-of-scope idea is redirected in two minutes rather than after a full specification has been drafted.

## Preconditions

Before filing an intent issue, read [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) at the repository root and verify that the proposal fits:

- **Mission** — what the project exists to accomplish.
- **Scope / Non-Goals** — which capabilities belong here and which are explicitly excluded.
- **Architecture Invariants** — structural commitments that no change may violate.

If the proposal falls outside `PROJECT_INTENT.md`, choose one of three constructive paths instead of filing a standard work item: route it to the appropriate adjacent project, propose a formal intent amendment (`PROJECT_INTENT.md` §10), or set the idea aside. Never try to slip out-of-scope work past intake — both `/cadence-triage` and the Maintainer Acceptance gate check alignment against `PROJECT_INTENT.md`.

## What happens

1. **Observe the problem.** Start from a concrete, observable symptom, user friction point, or operational gap — such as a support trend, a regression, a missing capability, or an operational bottleneck — rather than an unverified root-cause guess or a pre-selected technical solution.
2. **Verify intent alignment.** Check `PROJECT_INTENT.md` (above) to confirm this repository is the right home.
3. **File the intent issue.** Draft the concise four-part proposal below and file it **in the bound issue tracker** (e.g., Jira or YouTrack per `CADENCE_ORG.md` §9) — not as a merge request in the forge. Intent issues originate in the tracker; the forge (GitLab/GitHub/SourceHut) is used later when submitting the change proposal (`submission.md`).
4. **Receive the maintainer's ruling** and follow its disposition (see [Maintainer response](#maintainer-response)).

The Problem step concludes once the maintainer returns **Proceed** (or **Modify** with an agreed scope adjustment). Only then does the item enter **Triage** (`01-triage.md`), where `specs/{ticket-id}/` and its `problem.md` stub are created in the repository.

## The intent issue — anatomy

An intent issue is **three to five sentences total**, never a full design document. It contains four concise elements:

- **Problem** — what is broken, missing, or unclear (one to two sentences focusing on observable symptoms).
- **Proposed approach** — a high-level sketch of the direction, not a detailed architecture (two to three sentences).
- **Surfaces affected** — which public or registered surfaces, if any, would be touched (endpoints, events, schemas, shared contracts, CLI flags). Write "no public surfaces" when none are affected.
- **Ask** — what you need from the maintainer: confirmation to proceed, architectural guidance, a redirect, or a "not now."

State the desired outcome in user or business terms — *"operators can Y without manual Z"* — rather than *"add table X."* Concrete technical design belongs in the Spec step (`02-spec.md`); locking in an implementation here short-circuits design exploration.

> **Relationship to `problem.md`.** The intent issue serves as the initial seed; the full [`problem.md`](../../../specs/TEMPLATE/problem.md) repository artifact (Business Context, Affected Users, Desired Outcome, Acceptance Criteria, Constraints, Out of Scope, and elicitation probes) is populated **downstream**, beginning at Triage (`01-triage.md`) and refined through [`/cadence-elicit`](../../../AGENTS.md). Do not fill out the full `problem.md` template prior to receiving the maintainer's go/no-go.

## How to file an intent issue

Intent issues are created in the **bound issue tracker** (`CADENCE_ORG.md#tracker-binding`), not in the code forge and not by manually creating folders under `specs/`. Because `specs/{ticket-id}/` is initialized downstream during `/cadence-triage`, this step creates only the *tracker issue* (or hands the text to `/cadence-triage` to reserve the tracker key first).

Two routes are supported, and both produce a tracked issue under the authoritative tracker key:

**Route A — file directly in the issue tracker (default for requesters).**

1. Open a new issue in the project's bound tracker (e.g., Jira). **Always file it with issue type `Issue`** — not Story, Task, or Bug — and **place it in the backlog only, never directly into an active sprint.** An intent issue is an unapproved proposal awaiting a maintainer verdict; it must not enter committed sprint work until it passes this gate and completes Triage.
2. **Summary** — a one-line problem statement phrased in outcome terms (*"users can Y without Z"*), not an implementation title.
3. **Description** — the four elements from [the anatomy above](#the-intent-issue--anatomy): **Problem**, **Proposed approach**, **Surfaces affected**, and **Ask** (three to five sentences total).
4. Assign or flag the issue for the maintainer.

The tracker assigns an authoritative key (for example, `CTS-42`). Once the maintainer rules **Proceed** or **Modify**, `/cadence-triage CTS-42` **imports** that tracker issue — reading its Summary and Description via the bound tracker skill (`CADENCE_ORG.md` §9/§10) — and seeds `specs/CTS-42/problem.md` from it. Never invent or guess a ticket number locally when a tracker is bound.

**Route B — pass the proposal inline to `/cadence-triage` (for contributors already working in the CLI).**

When you are already inside your agentic CLI environment (`.agents/` or `.gemini/` on Antigravity) and want to originate and triage in one flow, pass your four-part proposal text directly to [`/cadence-triage "..."`](../../../AGENTS.md). Under a `reserve-from-tracker` binding (`CADENCE_ORG.md` §10), `/cadence-triage` **reserves** the next authoritative key from the tracker *before* creating `specs/<id>/problem.md` + `metadata.yaml`, keeping the tracker and repository strictly paired.

> **Which route should I pick?** Route A keeps the initial intent check ultra-lightweight in the tracker before any repository files are touched. Choose Route B when you already have maintainer alignment (or are a maintainer originating in-scope work) and want the tracker key reserved and triaged in a single command. If the bound tracker is unreachable during Route B, `/cadence-triage` halts loudly rather than fabricating a local number.

Under either route, when an external allocator is bound in `CADENCE_ORG.md` §10, the tracker owns the number space — never guess the next ticket ID by incrementing folder names in `specs/`.

> **Issue type and backlog placement — non-negotiable.** Every intent issue is filed as tracker type **`Issue`** and placed **in the backlog, never directly into an active sprint.** This rule applies across all routes, all change tiers, and all contributors (including core maintainers). Work moves into an active sprint only after passing the intent gate and completing Triage.

## Maintainer response

The maintainer evaluates the intent issue against `PROJECT_INTENT.md` and records one of five verdicts:

| Verdict | Meaning | What you do |
|---|---|---|
| **Proceed** | The work fits intent. | Advance to Triage; file a spec (or a lightweight `submission.md` on the lightweight track). |
| **Modify** | Fits intent, but the approach needs adjustment. | Adjust as directed, then proceed. |
| **Redirect** | Belongs in a different project. | Take it to the named project. |
| **Decline** | Does not fit intent. | Stop here. The verdict cites the relevant Non-Goal or Scope-Out entry. |
| **Amend first** | Would require changing intent. | Propose an intent amendment before any work. |

A *Decline* or *Amend first* disposition redirects energy before code is written — it is a healthy governance outcome, never a personal rebuke.

## Definition of done

- [ ] Proposal checked against `PROJECT_INTENT.md` (mission, scope, non-goals, architecture invariants).
- [ ] Intent issue filed **in the bound tracker (not the forge)** containing all four elements: Problem, Proposed approach, Surfaces affected, and Ask.
- [ ] Filed as issue type **`Issue`** and placed **in the backlog, not an active sprint**.
- [ ] Problem framed around an observable user/system outcome rather than a pre-selected implementation.
- [ ] Maintainer verdict received and recorded on the issue.
- [ ] Verdict is **Proceed** or **Modify** (any other verdict concludes or redirects the item here).

## What this step is NOT

- **Not a technical specification.** No Contextual Grounding Matrix (6W×4L), no CHORD decomposition, and no Gherkin test plan — those belong to the Spec step (`02-spec.md`).
- **Not architecture design.** The proposed approach is a two-sentence directional sketch, not class signatures.
- **Not manual `specs/{ticket-id}/` creation.** The repository spec directory and `problem.md` stub are created at **Triage** (`01-triage.md`), never manually at this step.
- **Not optional.** Every change starts with an intent issue, including core team and lightweight-track work.

## Where this goes next

Once the maintainer rules **Proceed** or **Modify**, the ticket advances to **Triage** ([`01-triage.md`](01-triage.md)), where `/cadence-triage` classifies the work item, checks for duplicates and prior insights via `repo-scout` / `local_semantic_embed`, assigns the change tier, and initializes `specs/{ticket-id}/problem.md` and `metadata.yaml`. See [`../getting-started.md`](../getting-started.md) §2.3 for the full lifecycle overview.

## Related documents

- [`01-triage.md`](01-triage.md) — the next step in the workflow.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../contributor_experience_guide.md`](../contributor_experience_guide.md) — "Filing an intent issue" and lightweight vs. standard tracks.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — how changes are right-sized at Triage.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the repository charter every Problem is evaluated against.
- [`../../../specs/TEMPLATE/problem.md`](../../../specs/TEMPLATE/problem.md) — the repository template populated starting at Triage.
