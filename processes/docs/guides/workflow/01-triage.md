# Workflow Step 01 — Triage

> Part of the per-step workflow guide series. This document details the **Triage** step. For the preceding step see [`00-problem.md`](00-problem.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Triage (`/cadence-triage`) |
| **Who** | Contributor / Implementer (invokes the skill; `cadence-triage-agent` + `repo-scout` perform the analysis) |
| **Consumes** | An intent issue in the bound tracker with a *Proceed* verdict from the [Problem](00-problem.md) step |
| **Produces** | `specs/{ticket-id}/problem.md` + `metadata.yaml`, classification, change tier, and a tracker triage projection |
| **Leads to** | [Spec](02-spec.md) — or `/cadence-elicit`, redirect, or decline (see [Recommended next step](#recommended-next-step)) |

---

## Purpose

Triage converts an approved *intent issue* into a **tracked, classified, right-sized unit of work** anchored inside the repository. It answers six foundational questions: *What category of change is this? How large is its blast radius? Does it duplicate or extend open or archived work? Does it remain aligned with `PROJECT_INTENT.md` upon code inspection? Which domain entities and layers does it touch? Which change tier governs the rest of its lifecycle?*

Triage is the first step that writes artifacts into the Git repository. Whereas the [Problem](00-problem.md) step lived in the issue tracker, Triage initializes the `specs/{ticket-id}/` directory and seeds `problem.md` and `metadata.yaml` so every downstream phase operates against a versioned, machine-readable contract.

## Who does what

Invoke Triage from your agentic CLI runtime (`.agents/skills/cadence-triage/` or `.gemini/` on Antigravity):

```
/cadence-triage <ticket-id>            # e.g. /cadence-triage TT-6547 — an existing tracker issue
/cadence-triage "short problem text"   # an inline problem description to reserve and triage
/cadence-triage --file-only <draft>    # non-interactive follow-up filing from a review gate
```

The `/cadence-triage` skill orchestrates the workflow, resolves the repository's ID-allocation and tracker bindings (`CADENCE_ORG.md` §9 and §10), and delegates codebase exploration and artifact drafting to the **`cadence-triage-agent`** subagent. Because interactive user questioning cannot happen inside a background subagent, any follow-on probe interview (`/cadence-elicit`) runs in the main turn after the subagent returns — see [Probe interview (elicitation)](#probe-interview-elicitation).

## Entry modes

How `/cadence-triage` originates or loads the work item depends on the argument provided and the repository's bindings in `CADENCE_ORG.md`:

| Input | Situation | What the skill does |
|---|---|---|
| **Ticket ID, local spec exists** (`specs/{id}/` present) | Re-triage of existing work | Reads the existing `specs/{id}/problem.md` as the primary problem statement; tracker refresh is optional. |
| **Ticket ID, no local spec** | **Seed-read / Import** — issue filed first in the bound tracker | Resolves the bound tracker from `CADENCE_ORG.md` §9/§10, performs a governed one-time seed-read of the tracker issue's summary/description, and seeds `specs/{id}/problem.md` + provenance fields in `metadata.yaml`. |
| **Free-text description** (or `--file-only <draft-path>`) | Brand-new problem originated from the CLI or a gate disposition | Allocates the next authoritative ticket ID per `CADENCE_ORG.md` §10 (reserving from the bound tracker or minting via `mint-id.sh` when unbound), then creates `specs/{id}/problem.md` and `metadata.yaml` in the same governed operation. |

The resolved ticket ID is **authoritative** and is used verbatim for `specs/{ticket-id}/` and all branch names. When an external allocator is bound in `CADENCE_ORG.md` §10, `/cadence-triage` never fabricates a local fallback ID if the tracker is unreachable — it **halts loudly** (`CADENCE_DIRECTIVES.md` Behavior 5). Furthermore, every ticket-ID allocation is strictly paired in the same operation with `specs/<id>/problem.md` and `metadata.yaml` (`idalloc.reserve.unpaired_artifact_creation`).

## Automatic Local Offload during Triage (`repo-scout` & `local_semantic_embed`)

Before scanning files manually, `cadence-triage-agent` automatically leverages CADENCE's read-only local hardware coprocessors (`enable_write_tools: false`) to accelerate discovery at **0 MB GPU VRAM**:

1. **Semantic Duplicate & Prior-Art Search (`local_semantic_embed` on `local-embed-cpu`):** Queries `nomic-embed-text` (running on the Ryzen 9 9955HX3D 3D V-Cache CPU server, port `11434`) across `specs/`, `archive/`, `docs/ADR/`, `docs/agentic-sdlc/production-insights.md`, and `docs/agentic-sdlc/intent-insights.md` to locate semantically related tickets, prior architectural rulings, and recurring failure patterns even when exact keywords differ.
2. **Parallel Codebase & Boundary Mapping (`repo-scout` on `local-moe-hybrid`):** Invokes the read-only `repo-scout` subagent (powered by `local_semantic_embed` + `gemma-4-26b-a4b`) to map implicated domain entities, bounded contexts, registered surfaces (`surface-registry.md` / `cadence-surfaces.md`), and cross-boundary contracts without polluting the primary reasoning model's context window.

All findings returned by `repo-scout` and `local_semantic_embed` are verified by the primary model before being written into `problem.md` and `metadata.yaml`.

## What happens

Working read-only over application source code, `cadence-triage-agent` executes a structured nine-step assessment:

1. **Understand the problem.** Parse the problem description and initial acceptance criteria, identify ambiguities, and count unanswered elicitation probes in `problem.md`.
2. **Scope-check against project intent.** Evaluate the request against [`PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — checking Mission, In-Scope / Out-of-Scope tables, Non-Goals, and Architecture Invariants. Any conflict is **flagged immediately** as a candidate for Redirect, Intent Amendment, or Decline rather than quietly carried into specification.
3. **Locate implicated code (via `repo-scout`).** Identify the exact domain entities, application services, endpoints/controllers, and persistence repositories involved.
4. **Search prior work & duplicates (via `local_semantic_embed`).** Check active `specs/` and completed `archive/` directories for duplicate, overlapping, or foundational tickets, recording any `duplicate-of`, `related-to`, or `extends` links.
5. **Classify the work item.** Assign **Type** (`bug` | `feature` | `tech-debt` | `security` | `documentation` | `epic`), **Priority** (`critical` | `high` | `medium` | `low`), and **Scope** (`S` = hours | `M` = days | `L` = 1 week | `XL` = multi-week).
6. **Production-signal analysis (for `bug` tickets).** Categorize the failure signal (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, or `BOUNDARY_FAULT`), map it to the violated **CHORD** dimension (Conditions, Handling/Triggers, Outcomes, Rules, Deltas), check [`production-insights.md`](../../agentic-sdlc/production-insights.md) for prior occurrences, and append a new `PROD-{NNN}` entry recommending a concrete CHORD observability seam.
7. **Assess blast radius.** Enumerate affected `domain_entities`, `affected_layers`, `affected_integrations`, registered public surfaces (`surface-registry.md` / `cadence-surfaces.md`), and database migration requirements.
8. **Assign capitalization category** — `cap-dev` (net-new capability), `cap-maint` (enhancement to existing capability), or `expense` (defect remediation, research, or maintenance).
9. **Validate and assign the change tier.** Evaluate the objective triggers in [`change-tiers.md`](../../policies/change-tiers.md) (`Trivial`, `Low`, `Medium`, or `High`) to right-size the downstream workflow gates.

Every triaged ticket is also screened for security posture triggers (authentication, authorization, PII, untrusted input, OWASP Top 10) regardless of ticket type.

## Outputs

| Artifact | Content |
|---|---|
| [`specs/{ticket-id}/problem.md`](../../../specs/TEMPLATE/problem.md) | Instantiated from the template and populated with problem framing, affected users, desired outcome, acceptance criteria, constraints, and code pointers. |
| [`specs/{ticket-id}/metadata.yaml`](../../../specs/TEMPLATE/metadata.yaml) | Populated with `type`, `priority`, `scope`, `tier`, `capitalization`, `status: triaged`, `domain_entities`, `affected_layers`, `affected_integrations`, seed-read provenance (when imported), and observability fields (for bugs). |
| [`production-insights.md`](../../agentic-sdlc/production-insights.md) | (Bugs only) A new categorized `PROD-{NNN}` entry mapping the defect to its violated CHORD dimension and recommended seam (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, or `BOUNDARY_FAULT`). |
| Tracker triage projection | Classification, intent-fit check, impacted code areas, duplicate check results, and recommended next step synced to the bound tracker (`CADENCE_ORG.md` §9). |
| `stage_effort` + `actual_effort` | Triage stage effort appended to `metadata.yaml` and accumulated into `actual_effort` per [`CADENCE_ORG.md`](../../agentic-sdlc/CADENCE_ORG.md). |

Once `cadence-triage-agent` finishes writing the repository artifacts, `/cadence-triage` invokes the **bound tracker-sync skill** (resolved from `CADENCE_ORG.md#tracker-binding`, e.g., `/cadence-sync-jira` or `/cadence-sync-youtrack`) to project the triaged metadata and `problem.md` to the external tracker.

## Probe interview (elicitation)

`problem.md` includes structured **elicitation probes** (such as *"How would you know this shipped wrong?"* or *"What existing behavior must not change?"*). For **Medium- or High-tier** tickets that still have **unanswered** probes after initial triage, `/cadence-triage` offers in the same interactive turn to walk through them:

> *"N probe(s) are unanswered. Walk through them now? (yes/no)"*

If you answer **yes**, it invokes [`/cadence-elicit`](../../../AGENTS.md) (presenting probes via the runtime's native question control) and records your responses in `problem.md` under `## Elicited Intent`. For **Trivial- or Low-tier** tickets — or when all probes are already answered — no elicitation interview is prompted, matching the tier rules in [`change-tiers.md`](../../policies/change-tiers.md).

## Recommended next step

Every triage run concludes with a single explicit recommendation:

- **Spec authoring (`/cadence-spec`)** — standard path for Medium and High tiers; or proceed directly to `/cadence-implement` for Low tier (where `problem.md`'s acceptance criteria serve as the spec contract).
- **Needs clarification (`/cadence-elicit`)** — unanswered probes or ambiguous scope require stakeholder input before specification.
- **Duplicate of `<id>`** — work is already covered by an existing ticket; link and close.
- **Redirect** — capability belongs in another repository per `PROJECT_INTENT.md`.
- **Propose intent amendment** — requires amending `PROJECT_INTENT.md` Section 10 before work can proceed.
- **Decline** — conflicts with a documented Non-Goal or Scope-Out boundary in `PROJECT_INTENT.md`.

## Definition of done

- [ ] `specs/{ticket-id}/problem.md` and `metadata.yaml` created under the authoritative ticket ID.
- [ ] `type`, `priority`, `scope`, `capitalization`, and **`tier`** recorded in `metadata.yaml` (`status: triaged`).
- [ ] Alignment verified against `PROJECT_INTENT.md` (with any mismatch flagged).
- [ ] Related code symbols and prior work in `specs/` and `archive/` searched via `repo-scout` and `local_semantic_embed`.
- [ ] (For bugs) Production signal categorized (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`) and appended to `production-insights.md`.
- [ ] Triage `stage_effort` recorded and ticket projected to the bound tracker (`CADENCE_ORG.md` §9).
- [ ] One clear recommended next step reported.

## What this step is NOT

- **Not a design specification.** Triage produces no Contextual Grounding Matrix (6W×4L), no CHORD behavioral decomposition, and no Gherkin `test-plan.md` — those belong to [`02-spec.md`](02-spec.md).
- **Not a code-editing phase.** Triage is strictly read-only over production and test code; it writes only under `specs/{ticket-id}/` and (for bugs) `docs/agentic-sdlc/production-insights.md`.
- **Not local ID guessing.** Whenever an external allocator is bound in `CADENCE_ORG.md` §10, ticket keys are reserved or seed-read from the tracker, never invented locally.
- **Not the elicitation interview itself.** `/cadence-triage` detects unanswered probes and offers the handoff; `/cadence-elicit` conducts the probe interview.

## Related documents

- [`00-problem.md`](00-problem.md) — the preceding step (filing the intent issue).
- [`02-spec.md`](02-spec.md) — the next step for Medium- and High-tier tickets.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier applicability matrix.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — objective triggers governing tier assignment.
- [`../../agentic-sdlc/CADENCE_ORG.md`](../../agentic-sdlc/CADENCE_ORG.md) — tracker binding (§9) and ID-allocation binding (§10).
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the repository charter against which scope is checked.
- [`../../../specs/TEMPLATE/problem.md`](../../../specs/TEMPLATE/problem.md) · [`metadata.yaml`](../../../specs/TEMPLATE/metadata.yaml) — the templates populated during Triage.
