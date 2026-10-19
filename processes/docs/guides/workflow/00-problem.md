# Workflow Step 00 — Problem

> Part of the per-step workflow guide series. This document details the **Problem** step, the entry point of the CLAIRE workflow. For the whole-workflow overview, see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Problem (the intent issue) |
| **Who** | Anyone (the requestor / author) |
| **Produces** | An intent issue with a maintainer verdict of *Proceed* (or *Modify*) |
| **Leads to** | [Triage](#where-this-goes-next) — where the spec stub `specs/{ticket-id}/problem.md` is created |

---

## Purpose

The Problem step exists to answer one question before any work begins: **is this worth doing, and does it belong here?** It captures *what is wrong* and *what success looks like* — in business terms, not solution terms — and gets an explicit go/no-go from the maintainer.

It is the **social contract** of the workflow: *"I intend to work on this; is that useful?"* Nothing downstream — no spec, no code, no review — happens until this contract is agreed. The step is deliberately cheap so that a bad-fit idea is caught in three sentences rather than after a spec is written.

## Preconditions

Before filing, the author reads [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) at the repo root and confirms the idea plausibly fits:

- **Mission** — what the project exists to do.
- **Scope / Non-Goals** — what belongs here and what is explicitly refused.
- **Architecture Invariants** — structural commitments the change must not violate.

If the idea clearly falls outside intent, the author has three honest paths instead of filing: redirect it to an adjacent project, propose an intent amendment (`PROJECT_INTENT.md` §10), or accept that this is not the right home. Do not try to slip out-of-scope work past this step — the maintainer reviews against intent, and the mismatch surfaces here or at the maintainer gate regardless.

## What happens

1. **Observe the problem.** Start from an observable symptom, gap, or pain — a support-ticket trend, a broken behavior, a missing capability, an operational inefficiency. Not an assumed root cause and not a pre-chosen solution.
2. **Check intent fit.** Read `PROJECT_INTENT.md` (above) and decide the idea belongs here.
3. **File the intent issue.** Write the short proposal described below and file it **in the issue tracker (Jira)** — not in the forge. Intent issues live in the tracker; the forge (GitLab/GitHub) is for the change proposal (MR/PR) later, not for capturing the problem.
4. **Receive the maintainer's verdict** and act on it (see [Maintainer response](#maintainer-response)).

The Problem step is complete when the maintainer returns **Proceed** (or **Modify** with an agreed adjustment). Only then does the work advance to **Triage**, where the `specs/{ticket-id}/` folder and its `problem.md` stub are first created.

## The intent issue — anatomy

An intent issue is **three to five sentences**, not a specification. It is a proposal, not a design. It includes:

- **Problem** — what is wrong, missing, or unclear (one to two sentences). State the observable symptom, not the assumed cause.
- **Proposed approach** — a sketch, not a design (two to three sentences).
- **Surfaces affected** — which public surfaces, if any, would change (endpoints, events, schemas, shared contracts). State "no public surfaces" if that is the case.
- **Ask** — what you need from the maintainer: confirmation to proceed, guidance, a redirect, or a "not now."

Frame the desired outcome in business terms — *"users can Y without Z"* — rather than *"build feature X."* The solution is decided later, in the Spec step; committing to one here defeats the purpose of the gate.

> **Relationship to `problem.md`.** The intent issue is the seed; the fuller [`problem.md`](../../../specs/TEMPLATE/problem.md) artifact (Business Context, Affected Users, Desired Outcome, Acceptance Criteria, Constraints, Out of Scope, plus the elicitation probes) is populated **later**, starting at Triage and refined via [`/claire-elicit`](../../../CLAUDE.md). Do not attempt to fill the whole template at this step — you would be specifying before the go/no-go.

## How to file an intent issue

Intent issues live in the **issue tracker**, not in the forge and not under `specs/`. This project's tracker is an on-prem **Jira Server / Data Center** instance (see [`../../policies/ticket-management-system.md`](../../policies/ticket-management-system.md)). There is no `specs/{ticket-id}/` folder yet — that is created downstream at Triage — so at this step you are creating a *tracker issue*, nothing in the repo.

There are two supported routes. Both end in the same place: a tracker issue the maintainer can rule on.

**Route A — file directly in Jira (the default for requestors).**

1. Create a new issue in the project's Jira tracker. **Always file it as issue type `Issue`** — not Story, Task, Bug, or any other type — and **create it in the backlog only, never directly into a sprint.** An intent issue is an ungated proposal awaiting a maintainer verdict; it does not belong to committed sprint work until it has passed this gate and been triaged.
2. **Summary** — the one-line problem framing, in business terms (*"users can Y without Z"*), not a solution title.
3. **Description** — the four parts from [the anatomy above](#the-intent-issue--anatomy): **Problem**, **Proposed approach**, **Surfaces affected**, **Ask**. Three to five sentences total; do not paste the `problem.md` template.
4. Assign or flag it for the maintainer and submit.

The issue now carries a real Jira key (e.g. `CTS-42`). On a **Proceed**/**Modify** verdict it enters the repo at Triage, where the triage agent **imports** that Jira issue — fetching its Summary and Description — and seeds `specs/CTS-42/problem.md` from it. You do not reserve or invent the key; Jira owns the number space.

**Route B — hand the text to `/claire-triage` (for contributors already working in the repo).**

If you are inside the repo with the agentic tooling and would rather not open Jira by hand, pass the same four-part text to [`/claire-triage "..."`](../../../CLAUDE.md). The triage skill **reserves** a fresh key from Jira *before* creating the stub, so the tracker and the repo stay in step. Note this front-loads Triage — the maintainer go/no-go still governs whether the work proceeds past this step.

> **Which route?** Route A keeps the intent gate cheap and tracker-first, which is why it is the default: the maintainer rules before any repo artifact exists. Use Route B only when you are already mid-flow in the repo and want the key reserved for you. If Jira is unreachable during Route B, `/claire-triage` stops and reports rather than guessing a number — never fabricate a key.

Whichever route you use, the number space is authoritative in **Jira**, not in the local `specs/` sequence — the two have diverged, so never assume the next local folder number is your ticket's key.

> **Type and placement — non-negotiable.** An intent issue is **always** filed as Jira issue type **`Issue`** and lives **only in the backlog — never in a sprint.** This holds for every route and every change size, including the owning team and lightweight-track work. It stays in the backlog until the maintainer returns *Proceed*/*Modify* and Triage pulls it forward; putting an ungated proposal into a sprint commits work that has not passed the intent gate.

## Maintainer response

The maintainer returns exactly one verdict:

| Verdict | Meaning | What you do |
|---|---|---|
| **Proceed** | The work fits intent. | Advance to Triage; file a spec (or a lightweight `submission.md` on the lightweight track). |
| **Modify** | Fits intent, but the approach needs adjustment. | Adjust as directed, then proceed. |
| **Redirect** | Belongs in a different project. | Take it to the named project. |
| **Decline** | Does not fit intent. | Stop here. The verdict cites the relevant Non-Goal or Scope-Out entry. |
| **Amend first** | Would require changing intent. | Propose an intent amendment before any work. |

A *Decline* or *Amend first* is not a rejection of the contributor — it is a redirect to the right shape of conversation.

## Definition of done

- [ ] Idea checked against `PROJECT_INTENT.md` (mission, scope, non-goals, invariants).
- [ ] Intent issue filed **in the tracker (Jira), not the forge**, with all four parts: Problem, Proposed approach, Surfaces affected, Ask.
- [ ] Filed as issue type **`Issue`** and placed **in the backlog, not a sprint**.
- [ ] Problem framed as an observable outcome, not a pre-chosen solution.
- [ ] Maintainer verdict received and recorded.
- [ ] Verdict is **Proceed** or **Modify** (any other verdict ends or reroutes the work here).

## What this step is NOT

- **Not a specification.** No Zachman grid, no PRISM decomposition, no test plan — those belong to the Spec step.
- **Not solution design.** The proposed approach is a one-line sketch, not an architecture.
- **Not `specs/{ticket-id}/` creation.** The spec folder and `problem.md` stub are created at **Triage**, not here.
- **Not skippable.** Every change files an intent issue, including the owning team and lightweight-track changes.

## Where this goes next

On a **Proceed**/**Modify** verdict, the work enters **Triage**, where the triage agent classifies the issue, assesses scope and impact, assigns a change tier, and creates the `specs/{ticket-id}/problem.md` stub. See [`getting-started.md`](../getting-started.md) §2.3 for the full step-by-step workflow and the per-tier applicability matrix.

## Related documents

- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and tier matrix.
- [`../contributor_experience_guide.md`](../contributor_experience_guide.md) — "Filing an intent issue" and the lightweight vs. standard tracks.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — how the change is right-sized once triaged.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the intent every Problem is measured against.
- [`../../../specs/TEMPLATE/problem.md`](../../../specs/TEMPLATE/problem.md) — the artifact populated downstream, starting at Triage.
