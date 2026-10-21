# Workflow Step 06 — Gate: Maintainer Acceptance

> Part of the per-step workflow guide series. This is a **human governance gate** (Gate 3), assisted by the `/cadence-maintain` skill — the AI produces a structured 8-dimension project-impact evaluation, and the human Maintainer makes the final acceptance decision. For the preceding gate see [`05-code-review.md`](05-code-review.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Authoritative gate specification: [`human-gates.md`](../../agentic-sdlc/human-gates.md) §Gate 3.

| | |
|---|---|
| **Gate** | Maintainer Acceptance (Gate 3) |
| **Who** | Project Maintainer (a human), assisted by `cadence-maintainer` + `offload_deep_review` via `/cadence-maintain` |
| **You are approving** | The MR's **repository-wide and architectural impact** — not line-level code correctness (that was Gate 2) |
| **Consumes** | A Gate 2-approved MR, its approved `spec.md`, `submission.md`, and the repository's governing documents |
| **Outcome** | **Accept**, **Postpone**, or **Reject** |

---

## Purpose

Gate 3 is the **final governance gate prior to merge**, safeguarding the long-term coherence of the repository as a whole. While Gate 2 (Code Review) verified that the code is correct *in isolation against its spec*, Maintainer Acceptance asks whether the change is right *for the project over the next two years*: Does it honor backwards-compatibility guarantees? Does it preserve architectural invariants and ADRs? Does it stay true to `PROJECT_INTENT.md`? Is its ongoing maintenance burden justified, and is it ready to ship cleanly?

As Maintainer, you evaluate **system-level stewardship**, not line-by-line implementation mechanics. Trust Gate 2's correctness verification and focus your attention on architectural boundaries, compatibility contracts, and project trajectory.

## When this gate applies

Only **Medium-** and **High-tier** changes pass through Gate 3 Maintainer Acceptance. Trivial and Low-tier changes proceed directly from Gate 2 Code Review to [Merge](07-merge.md) without a separate maintainer gate (see [`change-tiers.md`](../../policies/change-tiers.md) and [`../getting-started.md`](../getting-started.md) §2.3).

## Prerequisite: Gate 2 Code Review has passed

Before running its evaluation, `/cadence-maintain` verifies that **Gate 2 Code Review has approved the MR** (recorded in `submission.md` `## Discussion` or on the forge thread) and that the ticket's specification is at `status: spec-approved` or `in-review`. If Gate 2 has not yet passed, `/cadence-maintain` **halts** and directs you to complete `/cadence-review` first.

## Automatic Local Offload during Maintainer Acceptance (`offload_deep_review` & `local_semantic_embed`)

To give `cadence-maintainer` and the human Maintainer complete repository-wide visibility without context bloat, `/cadence-maintain` automatically engages CADENCE's read-only local hardware coprocessors (`enable_write_tools: false`):

1. **Cross-Boundary & Pillar Pre-Scan (`offload_deep_review` on `local-moe-hybrid` / `local-12b-gpu`):** Audits the full integration-branch diff against `docs/policies/surface-registry.md`, `docs/policies/cadence-surfaces.md`, `docs/policies/deprecation-policy.md`, and `docs/policies/doc-maintenance-policy.md` (including verifying the two-search reconciliation sweep record and `< 400`-line file ceiling).
2. **Semantic ADR & Intent Alignment Check (`local_semantic_embed` / `repo-scout` on `local-embed-cpu`):** Runs zero-VRAM semantic searches (`nomic-embed-text` on port `11434`) across `docs/ADR/`, `PROJECT_INTENT.md`, and `docs/flows/` to detect subtle contradictions against ratified ADRs or un-updated flow narratives.

All pre-scan signals are verified by the primary `cadence-maintainer` reasoning model before producing the 8-dimension Maintainer Assessment.

## Step 1 — Run the AI assessment

Invoke `/cadence-maintain` from your agentic CLI runtime (`.agents/skills/cadence-maintain/` or `.gemini/` on Antigravity):

```
/cadence-maintain <MR-number-or-branch>     # e.g. /cadence-maintain 142   or   /cadence-maintain impl/feature/TT-6547
```

`/cadence-maintain` resolves the ticket ID from the branch name (`impl/{type}/{id}`), computes the diff against the integration branch declared in `CADENCE_ORG.md#branch-strategy-binding` (§15), and delegates to the **`cadence-maintainer`** subagent. The agent evaluates the change across **eight stewardship dimensions** — grounded in `surface-registry.md`, `cadence-surfaces.md`, `docs/ADR/`, `PROJECT_INTENT.md`, and `CADENCE_ORG.md`, citing concrete file and line evidence for every verdict:

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

`cadence-maintainer` returns a structured **Maintainer Assessment** containing an overall recommendation (`Accept` / `Postpone` / `Reject`), an executive decision brief, per-dimension verdicts with evidence, blocking issues, classified non-blocking observations (`out-of-scope-defect`, `adr-owed`, `nit`, `hygiene`, `observation` per [`finding-classes.md`](../../policies/finding-classes.md)), positive highlights, and any drafted release/documentation artifacts (`CHANGELOG.md` entry, migration guide, deprecation notice). The agent **recommends only** — it never merges the MR, and its write scope is restricted strictly to `specs/`, `docs/`, and `CHANGELOG.md` (never production source or test code).

**Blocking at Gate 3 is reserved** for genuine project-level hazards: unmigrated breaking changes to registered surfaces, violations of ratified ADRs or `PROJECT_INTENT.md` invariants, unmanaged security surface expansion, un-elapsed deprecation windows, irreversible schema migrations lacking an approved exception, or unrecorded reconciliation sweeps (`doc-maintenance-policy.md`).

## Step 2 — Orient in the architecture (before evaluating)

Open [`SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) and [`docs/flows/`](../../flows/):

1. Locate the bounded context(s) and business flow(s) modified by this MR.
2. Confirm that the service dependency graph and context interaction map remain truthful once this change merges.
3. If the MR introduces a new service, bounded context, external integration, or business flow — verify that you can **trace it directly on the documented system map**. If `SYSTEM_OVERVIEW.md` or `docs/flows/` has not been updated to reflect it, require that update before accepting.

If the MR's system-level impact remains opaque after reading `submission.md` and `spec.md`, **postpone** and request architectural clarification.

## Step 3 — Judge what only a human can

- **Core vs. edge placement** — For a mature codebase: does this capability belong in the core service, or should it live in an adapter, plugin, sidecar, or adjacent repository?
- **Strategic alignment** — Does this change move the codebase closer to or further from the long-term vision in `PROJECT_INTENT.md`?
- **Six-month maintenance trajectory** — Not merely *"is this code clean today?"*, but *"what happens to our operational complexity if we accept five more changes shaped like this over the next two quarters?"*
- **Cross-team ownership & SLA impact** — Does this introduce an operational dependency or support surface the owning team is not staffed to maintain?

## Step 4 — Work the checklist

| Check | What to look for |
|---|---|
| **System model intact** | **Can you draw this change on the system map? Do `SYSTEM_OVERVIEW.md` and `docs/flows/` still hold? If not, require update.** |
| Backwards compatibility | Registered surface changes in `surface-registry.md` and `cadence-surfaces.md` handled per `deprecation-policy.md`? Policy-tooling enumeration recorded if governance docs changed? |
| Architectural integrity | Honors ratified ADRs in `docs/ADR/`? Any novel pattern justified and flagged `adr-owed` where appropriate? |
| Project-intent alignment | Advances Core Mission in `PROJECT_INTENT.md` without violating Non-Goals or Architecture Invariants? |
| Maintenance cost | Respects the Simplicity Engineering Pillar? Fewest moving parts? |
| Security impact | Trust boundaries, auth policies, and supply-chain exposure properly governed? |
| Release readiness | `CHANGELOG.md` updated? Deprecation headers/metrics wired? Migration + rollback verified? |
| Dependency health | New packages license-compatible, vulnerability-free, and actively maintained? |

## Step 5 — Dispose of follow-up candidates (`out-of-scope-defect` & `contraction-pending`)

At Step 6b of `/cadence-maintain`, any undisposed `out-of-scope-defect` findings (raised by `cadence-reviewer` or `cadence-maintainer` under [`finding-classes.md`](../../policies/finding-classes.md), as well as deferred `contraction-pending` schema migrations recorded in `decisions.md`) are deduplicated against `specs/` and `archive/` and presented for your explicit human disposition:

- **Confirm `new` → File follow-up ticket:** `/cadence-maintain` writes the candidate description to `specs/drafts/<ticket-id>-maintain-<UTC>-<N>.md` and invokes `/cadence-triage --file-only <draft-path>` (`cadence-surfaces.md` `follow-up filing composition contract v1`). Deferred `contraction-pending` migrations must always be tracked as follow-up tickets so temporary expand columns are not left behind permanently.
- **Confirm `duplicate of <id>`:** No new ticket is allocated; recorded as `Duplicate of <id>` in `submission.md`.
- **Confirm `fold into <id>`:** When an open `draft` or `triaged` ticket covers the area, appends a dated note to that ticket's `problem.md` `## Notes`, projects to the tracker, and records `Folded into <id>`.
- **Decline:** Records `Declined` with your explicit reason in `submission.md` `## Resolution -> Follow-ups created` so the item is not re-prompted at `/cadence-archive`.

Note that `adr-owed` findings are logged in the cumulative tally here and routed exclusively to `/cadence-archive` step 1b for ADR promotion after merge (`finding-classes.md`).

## Your decision

`/cadence-maintain` presents the 8-dimension assessment and prompts for your decision:

| Outcome | Meaning | What the skill records |
|---|---|---|
| **Accept** | Authorize the MR for merge into the integration branch. | Sets `maintainer_approved_at` in `metadata.yaml`; commits any approved `CHANGELOG.md` / migration / deprecation updates; records follow-up dispositions in `submission.md`. |
| **Postpone** | Defer merge until specific conditions or release windows are met. | Appends rationale to `decisions.md`; sets `postponed_at` + `postpone_reason` in `metadata.yaml`. |
| **Reject** | Decline the MR on architectural or intent grounds. | Appends rationale and author guidance to `decisions.md`; sets `rejected_at` + `rejection_reason` in `metadata.yaml` (see [`conflict-resolution.md`](../../policies/conflict-resolution.md) Scenario 1 if rejecting a design approved at Gate 1). |

## Recording the decision

- Across **every** outcome (`Accept`, `Postpone`, or `Reject`), `/cadence-maintain` appends a `maintainer` `stage_effort` entry to `metadata.yaml`, accumulates `actual_effort`, and projects the updated state to the bound tracker (`CADENCE_ORG.md` §9).
- The full Maintainer Assessment and follow-up dispositions are recorded in [`submission.md`](../../../specs/TEMPLATE/submission.md) (`## Discussion` and `## Resolution`) so the permanent archive preserves the complete stewardship record.

## What this gate is NOT

- **Not a repeat of Gate 2 Code Review.** Line-level correctness was verified at Gate 2; Gate 3 evaluates repository-wide stewardship across the eight dimensions.
- **Not an autonomous AI decision.** `cadence-maintainer` provides evidence-backed recommendations; the human Maintainer decides.
- **Not the merge action itself.** `Accept` authorizes the merge; the actual merge into the integration branch happens in [Step 07 — Merge](07-merge.md).
- **Not applicable to Trivial or Low tiers.** Trivial and Low tier tickets merge directly after Gate 2 per [`change-tiers.md`](../../policies/change-tiers.md).

## Related documents

- [`05-code-review.md`](05-code-review.md) — Gate 2, which must pass before Gate 3 runs.
- [`07-merge.md`](07-merge.md) — the next step once Gate 3 returns **Accept**.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier gate matrix.
- [`../../agentic-sdlc/human-gates.md`](../../agentic-sdlc/human-gates.md) — authoritative definition of all four human gates (§Gate 3 is this gate).
- [`../../SYSTEM_OVERVIEW.md`](../../SYSTEM_OVERVIEW.md) · [`../../flows/`](../../flows/) — system architecture maps verified in Step 2.
- [`../../policies/finding-classes.md`](../../policies/finding-classes.md) — non-blocking finding classes and follow-up filing rules.
- [`../../policies/surface-registry.md`](../../policies/surface-registry.md) · [`../../policies/cadence-surfaces.md`](../../policies/cadence-surfaces.md) · [`../../policies/deprecation-policy.md`](../../policies/deprecation-policy.md) · [`../../policies/migration-policy.md`](../../policies/migration-policy.md) — compatibility and release policies verified here.
- [`../../../PROJECT_INTENT.md`](../../../PROJECT_INTENT.md) — the repository charter grounding Dimension 2 and Dimension 3.
