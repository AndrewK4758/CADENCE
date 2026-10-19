# Workflow Step 01 — Triage

> Part of the per-step workflow guide series. This document details the **Triage** step. For the previous step see [`00-problem.md`](00-problem.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Triage (`/claire-triage`) |
| **Who** | Implementer (invokes the skill; the `claire-triage-agent` subagent does the analysis) |
| **Consumes** | An intent issue in the tracker (Jira) with a *Proceed* verdict from the [Problem](00-problem.md) step |
| **Produces** | `specs/{ticket-id}/problem.md` + `metadata.yaml`, a classification, a change tier, a Jira triage comment |
| **Leads to** | [Spec](../getting-started.md) — or `/claire-elicit`, redirect, or decline (see [Recommended next step](#recommended-next-step)) |

---

## Purpose

Triage turns an approved *intent* into a **tracked, classified, scoped unit of work** the repo can reason about. It answers: *What kind of change is this? How big? Does it duplicate existing work? Does it still fit project intent on closer inspection? Which code does it touch? What tier of process does it warrant?*

It is the first step that writes repository artifacts. The [Problem](00-problem.md) step produced an intent issue in the tracker; Triage creates the `specs/{ticket-id}/` folder and seeds it, so all downstream steps have a stable home and a machine-readable record.

## Who does what

You drive Triage by invoking the skill from inside Claude Code:

```
/claire-triage <ticket-id>            # e.g. /claire-triage TT-6547 — an issue already filed in Jira
/claire-triage "short problem text"   # a free-text problem statement
```

The skill orchestrates; the read-only **`claire-triage-agent`** subagent does the analysis and writes the spec stub. Interviewing the requester (elicitation) cannot happen inside a subagent, so the skill handles that back in the main turn — see [Probe interview](#probe-interview-elicitation).

## Entry modes

How the work enters depends on what you hand `/claire-triage`:

| Input | Situation | What the skill does |
|---|---|---|
| **Ticket ID, local spec exists** (`specs/{id}/` present) | Re-triage of known work | Reads existing `problem.md` as the problem statement; a tracker fetch is optional. |
| **Ticket ID, no local spec** | **Import** — a business user filed the issue directly in Jira | Fetches the issue's summary/description/acceptance criteria from Jira and seeds `problem.md` from them. |
| **Free-text description** | A brand-new problem stated inline | **Reserves a ticket key from Jira** (the tracker is the numbering authority), then triages under that key. |

The ticket key is **authoritative** — it is used verbatim for every artifact path. The skill never mints a local id when a tracker is designated; if key reservation or the tracker is unreachable, it **stops and reports** rather than guessing. If the id names neither a local spec nor a real tracker issue, it stops rather than inventing a problem statement. (Governed by [`ticket-management-system.md`](../../policies/ticket-management-system.md) §1.)

## What happens

The `claire-triage-agent` works read-only over the codebase and produces a structured assessment:

1. **Understand the problem.** Read the description and acceptance criteria; note what is unclear. Count unanswered elicitation probes in `problem.md`.
2. **Scope-check against intent.** Compare the issue to [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — In-Scope / Out-of-Scope lists, Non-Goals, and contribution posture. A clear mismatch is **flagged** (candidate for redirect / intent amendment / decline), not silently absorbed into a spec.
3. **Search for related code.** Grep/Glob for the domain entities, services, controllers/endpoints, and data-access code the issue implicates.
4. **Check for prior work & duplicates.** Search `specs/` and `archive/` for related or overlapping specs, decisions, and past implementations; note duplicate-of / related-to / extends relationships.
5. **Classify.** Assign **Type** (bug | feature | tech-debt | security | documentation), **Priority** (critical | high | medium | low), and **Scope** (S = hours | M = days | L = week | XL = multi-week).
6. **Production-signal analysis (bugs only).** Categorize the signal (LOGIC_FAULT, LINEAGE_GAP, DRIFT_SIGNAL, SEAM_VIOLATION), map it to the violated PRISM dimension, check [`production-insights.md`](../../agentic-sdlc/production-insights.md) for a recurring pattern, and append a new `PI-{NNN}` entry recommending an observability seam.
7. **Assess impact.** Which domain entities, architectural layers, and external integrations are touched? Any migration or breaking-change implications?
8. **Determine capitalization** — `cap-dev` (new feature), `cap-maint` (enhancement), or `expense` (bug fix / research / planning).
9. **Assign the change tier.** The author proposes a tier; triage validates it against the evidence and records it. The tier decides how much process the rest of the workflow applies — see the tier matrix in [`../getting-started.md`](../getting-started.md) §2.3 and the full policy in [`change-tiers.md`](../../policies/change-tiers.md).

Always screened for security implications (OWASP Top 10, HIPAA) regardless of type.

## Outputs

| Artifact | Content |
|---|---|
| [`specs/{ticket-id}/problem.md`](../../../specs/TEMPLATE/problem.md) | Seeded from the template, filled with everything known from the issue. |
| [`specs/{ticket-id}/metadata.yaml`](../../../specs/TEMPLATE/metadata.yaml) | Triage fields: type, priority, scope, tier, capitalization, `domain_entities`, `affected_layers`, `affected_integrations`; plus observability fields for bugs. |
| [`production-insights.md`](../../agentic-sdlc/production-insights.md) | (Bugs only) a new categorized `PI-{NNN}` entry mapping the bug to a PRISM dimension. |
| Jira triage comment | Classification, intent-fit verdict, affected code areas, related prior work, and the recommended next step, posted on the ticket. |
| `stage_effort` + `actual_effort` | The triage stage's effort is appended to `metadata.yaml` and accumulated, per [`CLAIRE_ORG.md`](../../agentic-sdlc/CLAIRE_ORG.md) "Actual Effort Accumulation". |

After the agent returns, the skill runs the **designated tracker-sync skill** (`/claire-sync-jira`) once to project the new/updated ticket to Jira (end-of-operation trigger). This is why the [Jira PAT](../getting-started.md) must be in your environment before you triage.

## Probe interview (elicitation)

`problem.md` carries **probe** questions (e.g. "How would you know this shipped wrong?"). For **Medium or High tier** issues with **unanswered** probes, the skill offers, in the same turn, to walk you through them:

> *"N probe(s) are unanswered. Walk through them now? (yes/no)"*

On **yes**, it invokes [`/claire-elicit`](../../../CLAUDE.md) for the ticket and appends the answers to `problem.md` as an `## Elicited Intent` section. For **Trivial/Low** tier, or when all probes are answered, no interview is offered — this matches `/claire-elicit`'s own tier gate in [`change-tiers.md`](../../policies/change-tiers.md).

## Recommended next step

Triage ends with one recommendation, carried in the triage summary:

- **Spec authoring** — the normal path; proceed to the Spec step (or `submission.md` on the lightweight/Trivial track).
- **Needs clarification** — unanswered probes remain; run `/claire-elicit` first.
- **Duplicate of X** — the work already exists; link and stop.
- **Redirect** — belongs in an adjacent project (intent mismatch).
- **Propose intent amendment** — would require changing `PROJECT_INTENT.md` first.
- **Decline** — out of scope; cite the Non-Goal / Scope-Out entry.

## Definition of done

- [ ] `specs/{ticket-id}/problem.md` and `metadata.yaml` created under the authoritative tracker key.
- [ ] Type, priority, scope, and **tier** assigned in `metadata.yaml`.
- [ ] Scope-checked against `PROJECT_INTENT.md`; any mismatch flagged.
- [ ] Related code and prior work searched; duplicate status noted.
- [ ] (Bugs) production signal categorized and a `PI-{NNN}` entry appended.
- [ ] Triage effort recorded; ticket projected to Jira via `/claire-sync-jira`.
- [ ] A single recommended next step stated.

## What this step is NOT

- **Not a specification.** No Zachman grid, PRISM decomposition, or test plan — those are the Spec step.
- **Not code-touching.** Triage is read-only over application code; the agent writes only spec files and (for bugs) `production-insights.md`.
- **Not id invention.** When a tracker is designated, the key is reserved/imported from Jira, never minted locally.
- **Not the elicitation interview itself.** Triage only decides whether to *offer* it; `/claire-elicit` owns the interview.

## Related documents

- [`00-problem.md`](00-problem.md) — the preceding step (the intent issue).
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and the per-tier applicability matrix.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — how the assigned tier right-sizes the rest of the process.
- [`../../policies/ticket-management-system.md`](../../policies/ticket-management-system.md) — the numbering authority, import/reserve operations, and sync triggers.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the intent the scope-check measures against.
- [`../../../specs/TEMPLATE/problem.md`](../../../specs/TEMPLATE/problem.md) · [`metadata.yaml`](../../../specs/TEMPLATE/metadata.yaml) — the templates Triage seeds.
