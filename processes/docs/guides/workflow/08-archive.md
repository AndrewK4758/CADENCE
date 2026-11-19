# Workflow Step 08 — Archive

> Part of the per-step workflow guide series. This guide details the **Archive** step — the closing phase of the CADENCE lifecycle. For the preceding step see [`07-merge.md`](07-merge.md); for the per-tier matrix see [`../../policies/change-tiers.md`](../../policies/change-tiers.md).

| | |
|---|---|
| **Step** | Archive (`/cadence-archive`) |
| **Who** | Reviewer / Maintainer (invokes `/cadence-archive`, which owns gate sweeps and tracker sync; read-only-on-tracker `cadence-archivist` executes file closeout) |
| **Consumes** | A merged ticket — implementation commit reachable on the bound integration branch (`CADENCE_ORG.md#branch-strategy-binding`) or `status: merged` in `metadata.yaml` (plus `status: cancelled` with `resolution:` on close-out) |
| **Produces** | `archive/{ticket-id}/` + `summary.md`, updated `CHANGELOG.md`, promoted ADRs (`docs/ADR/`) and intent insights (`intent-insights.md`), disposed follow-ups; `status: archived` |
| **Leads to** | — (ticket lifecycle complete) |

---

## Purpose

Archive closes the governance loop: it relocates a completed ticket's specification and review artifacts out of the active `specs/` directory into `archive/{ticket-id}/`, generates a durable closeout summary, disposes of any remaining `adr-owed` or `out-of-scope-defect` findings, and **distills what the team learned back into the repository's standing knowledge base** — `CHANGELOG.md`, `docs/ADR/`, `docs/agentic-sdlc/intent-insights.md`, and the bound issue tracker. Archival keeps `specs/` strictly scoped to *in-flight* work while transforming completed tickets into permanent, searchable institutional memory.

## Prerequisite: the change is merged on the integration branch

`/cadence-archive` runs **only after merge** ([`07-merge.md`](07-merge.md)) or on an explicit `status: cancelled` close-out with populated `resolution:`. Before acting on merged tickets, it resolves the repository's integration branch from [`CADENCE_ORG.md#branch-strategy-binding`](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding) and verifies that the ticket's implementation merge commit is reachable on `<integration-branch>` (`develop` under `long-lived-feature-release`, `main` under `trunk-based`) or `metadata.yaml` shows `status: merged`. If the change has not yet merged, `/cadence-archive` **halts** and instructs you to complete the merge first. If `specs/{ticket-id}/` is already absent and `archive/{ticket-id}/` exists, it reports cleanly that the ticket is already archived.

## Who does what

Invoke `/cadence-archive` from your agentic CLI runtime (`.agents/skills/cadence-archive/` or `.gemini/` on Antigravity):

```
/cadence-archive <ticket-id>           # e.g. /cadence-archive TT-6547
```

`/cadence-archive` handles interactive human confirmation steps (`step 1b` for `adr-owed` promotion/deferral and `step 2e` for any undisposed `out-of-scope-defect` follow-ups per [`finding-classes.md`](../../policies/finding-classes.md)), executes both `dead-citation-gate.sh` sweeps (`--id` and `--except-id`) and `authored-doc-gate.sh`, delegates artifact relocation, `summary.md` generation, `CHANGELOG.md` updates, citation dispositions (`REPOINT`/`EXEMPT`), and ADR/insight drafting (including `Closed by:` notes in `production-insights.md`) to **`cadence-archivist`**, and projects final `archived` status to the bound tracker (`CADENCE_ORG.md#tracker-binding`).

Like every other governed repository change, archival itself is committed **on a dedicated worktree branch (`archive/{type}/{id}`) and merged into the integration branch via a remote MR/PR** — never committed directly to local `develop` or `main`.

## Optional Local Offload during Archival (`local_semantic_embed` & `repo-scout`, Cloud Fallback)

When local offload (`:11434`) is reachable during archival closeout, `/cadence-archive` and `cadence-archivist` use CADENCE's read-only local hardware coprocessors (`enable_write_tools: false`, degrading cleanly to cloud-only `Grep`/`Glob` and direct inspection when offline):

1. **Follow-Up Candidate Deduplication (`local_semantic_embed` via `embedding`):** During step 2e's prior-work check ([`finding-classes.md`](../../policies/finding-classes.md) Routing step 4), queries local semantic vectors (`embedding` on port `11434`) across `specs/` (open tickets) and `archive/` (completed tickets) to classify each remaining `out-of-scope-defect` or deferred `adr-owed` candidate as `new`, `duplicate of <id>`, or `fold into <id>` (recording the exact search terms, searched roots, and hit counts).
2. **ADR & Intent-Insight Lineage Lookup (`repo-scout` via `inference`):** Searches `docs/ADR/`, `docs/agentic-sdlc/intent-insights.md`, and `docs/flows/` to identify the next sequential `ADR-NNN` / `II-NNN` identifiers (via `mint-id.sh`), verify whether a decision supersedes or narrows an existing ADR (`ADR_CADENCE-0073`), and check whether any `docs/flows/` document warrants a post-merge update proposal (`doc-maintenance-policy.md`).

All file moves, markdown authoring, and tracker syncs remain owned by `/cadence-archive` (which runs gate sweeps and tracker sync) and `cadence-archivist` (which authors archival artifacts).

## What happens

`/cadence-archive` and `cadence-archivist` execute a structured closeout sequence:

1. **Dispose of `adr-owed` findings (step 1b).** Present every `adr-owed` entry logged during review (`finding-classes.md`) alongside its recorded precondition and current evidence. The human operator either **promotes** it (`cadence-archivist` then authors the new ADR under `docs/ADR/` citing the ticket and entry) or **defers** it with a stated reason (routing it into step 2e's follow-up filing queue).
2. **Finalize `submission.md` & dispose of remaining follow-ups (step 2e).** Complete `submission.md`'s `## Resolution` section from the merge commit. For any `out-of-scope-defect` (or deferred `adr-owed`) entry lacking a disposition, run the prior-work check across `specs/` and `archive/`, present the `new` / `duplicate of <id>` / `fold into <id>` verdict for human confirmation, invoke `/cadence-triage --file-only <draft-path>` for confirmed `new` items, and record the final disposition and cumulative non-blocking class tally in `submission.md`'s `Follow-ups created` field.
3. **Relocate ticket artifacts & run dead-citation sweeps.** Move `specs/{ticket-id}/` to `archive/{ticket-id}/` via `git mv` on the `archive/{type}/{id}` branch; `/cadence-archive` runs `dead-citation-gate.sh --id {ticket-id}` (and `--except-id {ticket-id}` after promotions) while `cadence-archivist` applies `REPOINT` or `EXEMPT` dispositions.
4. **Generate `archive/{ticket-id}/summary.md`.** Synthesize a concise closeout record capturing the problem solved, key design decisions, files modified, test scenarios delivered, citation dispositions, and cycle-time metrics.
5. **Backfill `merged_at` (if unset) & record archive stage effort.** On merged entry path (a), backfill `merged_at` from the merge commit / forge PR if unset, append the `archive` `stage_effort` entry to `archive/{ticket-id}/metadata.yaml`, set `status: archived` and `archived_at`, and sum the stage entry into `actual_effort` (per `CADENCE_ORG.md#actual-effort-accumulation` — never recomputed from Git commit timestamps).
6. **Update [`CHANGELOG.md`](../../../CHANGELOG.md).** Add a structured entry under `[Unreleased]` (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, or `Security`) in Keep a Changelog format.
7. **Promote durable architectural knowledge.** Write promoted Architecture Decision Records to [`docs/ADR/`](../../ADR/), append reusable non-bug architectural or process discoveries to [`intent-insights.md`](../../agentic-sdlc/intent-insights.md) (`II-{NNN}`), and add `Closed by: {ticket-id}` onto matching `PROD-NNN` records in `production-insights.md`.
8. **Synchronize external tracker (`/cadence-archive` Step 2f).** `/cadence-archive` runs the bound tracker-sync skill (`CADENCE_ORG.md#tracker-binding`, e.g., `/cadence-sync-jira` or `/cadence-sync-youtrack`) using owned-items-only scoped projection to project `status: archived` and the final stage effort worklog.
9. **Surface flow-doc proposals & verify branch cleanup.** Flag any proposed updates to `docs/flows/` or `docs/SYSTEM_OVERVIEW.md` for **explicit human review** (never auto-merged silently, per `doc-maintenance-policy.md`), and verify that the post-merge feature branch was cleaned up.

## Outputs

| Artifact | Content |
|---|---|
| `archive/{ticket-id}/` | The complete specification, test-plan, decision-log, and submission bundle relocated from `specs/{ticket-id}/`. |
| `archive/{ticket-id}/summary.md` | Generated closeout summary with delivery, citation disposition, and effort metrics. |
| `archive/{ticket-id}/metadata.yaml` | Updated with `merged_at` (if unset on merged path), `status: archived`, `archived_at`, and the `archive` `stage_effort` entry accumulated into `actual_effort`. |
| [`CHANGELOG.md`](../../../CHANGELOG.md) | New entry under `[Unreleased]` describing the shipped change. |
| [`docs/ADR/`](../../ADR/) · [`intent-insights.md`](../../agentic-sdlc/intent-insights.md) · [`production-insights.md`](../../agentic-sdlc/production-insights.md) | Promoted ADRs (from confirmed `adr-owed` items), `II-{NNN}` intent insights, and `Closed by:` `PROD-{NNN}` closure notes. |
| Bound tracker (`CADENCE_ORG.md#tracker-binding`) | Final `archived` status and stage effort projected by `/cadence-archive`. |
| Flow-doc proposals | Drafted and surfaced for human maintainer sign-off (when applicable). |

## Definition of done

- [ ] All ticket artifacts reside under `archive/{ticket-id}/` (and `specs/{ticket-id}/` is removed), including a generated `summary.md`.
- [ ] Every `adr-owed` and `out-of-scope-defect` finding carries a complete disposition in `submission.md`'s `Follow-ups created` field (with zero unlabelled or undisposed entries).
- [ ] `CHANGELOG.md` updated under `[Unreleased]`; `metadata.yaml` records `status: archived` and `archived_at`.
- [ ] The `archive` `stage_effort` entry is appended and accumulated into `actual_effort` (never recomputed from Git log timestamps).
- [ ] Promoted ADRs and `intent-insights.md` entries committed where warranted.
- [ ] Bound external tracker synchronized (`status: archived`).
- [ ] Any proposed `docs/flows/` or `docs/SYSTEM_OVERVIEW.md` updates surfaced for human review.
- [ ] Archive branch (`archive/{type}/{id}`) merged into the integration branch via remote MR/PR and pulled locally.

## What this step is NOT

- **Not runnable before merge.** `/cadence-archive` refuses to archive an unmerged ticket.
- **Not timestamp-based effort recomputation.** `actual_effort` is the sum of recorded `stage_effort` entries across stages; the archivist appends the `archive` stage entry and never overwrites prior stages from Git commit spans.
- **Not silent system-doc mutation.** Modifications to `docs/flows/` and `docs/SYSTEM_OVERVIEW.md` always require human sign-off (`doc-maintenance-policy.md`).
- **Not a direct commit to `develop` or `main`.** Like every other artifact transition, archival lands on the integration branch through an `archive/{type}/{id}` branch and remote MR/PR.

## Related documents

- [`07-merge.md`](07-merge.md) — the preceding step; a ticket must be merged on the bound integration branch before `/cadence-archive` runs.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — per-tier requirements and gate matrix.
- [`../../policies/branch-strategy/long-lived-feature-release.md`](../../policies/branch-strategy/long-lived-feature-release.md) · [`trunk-based.md`](../../policies/branch-strategy/trunk-based.md) — how "is this merged?" and post-merge branch cleanup resolve.
- [`../../policies/finding-classes.md`](../../policies/finding-classes.md) — `adr-owed` promotion (step 1b) and `out-of-scope-defect` follow-up filing (step 2e).
- [`../../policies/doc-maintenance-policy.md`](../../policies/doc-maintenance-policy.md) — human approval requirement for `docs/flows/` and `docs/SYSTEM_OVERVIEW.md`.
- [`../../ADR/`](../../ADR/) · [`../../agentic-sdlc/intent-insights.md`](../../agentic-sdlc/intent-insights.md) — destinations for promoted architectural decisions and reusable insights (and use `/cadence-retro` to synthesize cross-ticket trends across `archive/*/`).
- [`../../../specs/TEMPLATE/submission.md`](../../../specs/TEMPLATE/submission.md) — the change-proposal and disposition record finalized at archival.
