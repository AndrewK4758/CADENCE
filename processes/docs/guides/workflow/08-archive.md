# Workflow Step 08 — Archive

> Part of the per-step workflow guide series. This document details the **Archive** step, the final step of the CLAIRE workflow. For the preceding step see [`07-merge.md`](07-merge.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3.

| | |
|---|---|
| **Step** | Archive (`/claire-archive`) |
| **Who** | Reviewer (invokes the skill; the `claire-archivist` subagent does the work) |
| **Consumes** | A merged ticket — `status: merged`, or its commit reachable on `develop` |
| **Produces** | `archive/{ticket-id}/` + `summary.md`, updated CHANGELOG, promoted ADRs/insights; `status: archived` |
| **Leads to** | — (workflow complete) |

---

## Purpose

Archive closes the loop: it moves a completed ticket's artifacts out of the active `specs/` tree into `archive/`, captures what happened, and **feeds the project's learning back into its living records** — the CHANGELOG, the ADR log, intent insights, and the tracker. It is what keeps `specs/` a set of *in-flight* work and turns finished work into durable, searchable project memory.

## Prerequisite: the change is merged

`/claire-archive` runs **after merge**. It verifies the ticket is merged — `metadata.yaml` shows `status: merged`, or the merge commit is reachable on `develop` (a commit on `develop` counts as merged even if not yet on `release/*` or `master`; see [`branch-strategy.md`](../../policies/branch-strategy.md)). If the MR isn't merged yet, it stops and tells you to complete the merge first. If `specs/{ticket-id}/` is already gone and `archive/{ticket-id}/` exists, it reports the ticket is already archived.

## Who does what

You drive the step from inside Claude Code:

```
/claire-archive <ticket-id>           # e.g. /claire-archive TT-6547
```

The skill delegates to the **`claire-archivist`** subagent. Like every other artifact change, the archival itself happens **on a branch and merges into `develop` via an MR** — moving files to `archive/`, updating the CHANGELOG, and promoting ADRs are all reviewable transitions, not direct commits.

## What happens

The `claire-archivist` performs the closeout:

1. **Finalize `submission.md`** — fill `## Resolution` (and any outstanding `## Discussion`) from the merge commit, so the archived record is complete.
2. **Move the artifacts** — relocate `specs/{ticket-id}/` to `archive/{ticket-id}/`.
3. **Generate `summary.md`** — a closeout summary with metrics drawn from git history.
4. **Record the archive stage effort** — append an `archive` `stage_effort` entry and accumulate it into `actual_effort` (per `CLAIRE_ORG.md` "Actual Effort Accumulation"). Effort is *accumulated*, never recomputed from git history at archive time.
5. **Update [`CHANGELOG.md`](../../../CHANGELOG.md)** — add the entry in Keep a Changelog format.
6. **Promote durable knowledge** — ADR-worthy decisions to [`docs/ADR/`](../../ADR/); qualifying non-bug discoveries to [`intent-insights.md`](../../agentic-sdlc/intent-insights.md).
7. **Sync external systems** — run the designated tracker-sync skill (`/claire-sync-jira`) to project `status: archived`.
8. **Propose flow-doc updates** — flagged for **human review**, not auto-applied.
9. **Clean up the feature branch.**

## Outputs

| Artifact | Content |
|---|---|
| `archive/{ticket-id}/` | The full spec artifact set, moved from `specs/`. |
| `archive/{ticket-id}/summary.md` | Closeout summary with git-history metrics. |
| `archive/{ticket-id}/metadata.yaml` | `status: archived`, `archived_at` set, `archive` `stage_effort` recorded. |
| [`CHANGELOG.md`](../../../CHANGELOG.md) | New entry for the change. |
| [`docs/ADR/`](../../ADR/) · [`intent-insights.md`](../../agentic-sdlc/intent-insights.md) | Any promoted decisions / insights. |
| Jira | `archived` status projected. |
| Flow-doc proposals | Drafted and flagged for human review (not written blindly). |

## Definition of done

- [ ] All artifacts live under `archive/{ticket-id}/` and `summary.md` exists.
- [ ] `CHANGELOG.md` updated; `metadata.yaml` shows `status: archived` with `archived_at` set.
- [ ] The `archive` `stage_effort` entry is recorded and `actual_effort` reflects it (accumulated, not recomputed).
- [ ] ADRs / intent insights promoted where warranted.
- [ ] External systems updated (or noted as unavailable).
- [ ] Any flow-doc proposals surfaced for human review.

## What this step is NOT

- **Not pre-merge.** Archival happens only after the change is merged to `develop`.
- **Not effort recomputation.** `actual_effort` is the accumulated sum of stage entries — the archivist adds the archive stage, it does not derive the total from git history.
- **Not auto-doc-editing.** Flow-doc and SYSTEM_OVERVIEW changes are *proposed* for human sign-off, never applied silently.
- **Not a direct commit.** The archive changes land on `develop` through an MR like every other transition.

## Related documents

- [`07-merge.md`](07-merge.md) — the preceding step; archival requires the change be merged first.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../policies/branch-strategy.md`](../../policies/branch-strategy.md) — why "merged" resolves against `develop`.
- [`../../policies/ticket-management-system.md`](../../policies/ticket-management-system.md) — the tracker-sync trigger for the `archived` status.
- [`../../ADR/`](../../ADR/) · [`../../agentic-sdlc/intent-insights.md`](../../agentic-sdlc/intent-insights.md) — where durable knowledge is promoted.
- [`../../../specs/TEMPLATE/submission.md`](../../../specs/TEMPLATE/submission.md) — the record finalized at archival.
