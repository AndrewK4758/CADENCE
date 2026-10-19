# Branch Strategy: Trunk-Based / Mainline

> **Branch-name-agnostic by binding (BTG-047).** This policy names no hardcoded branch; the integration-branch identifier, its protection posture, and the branch-naming grammar resolve through the [Branch Strategy Binding](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding).

This policy models a **trunk-based (mainline)** branching topology: a single persistent integration branch — "the trunk" — into which all changes merge via short-lived per-change branches. It is one of the two portable strategy specifications shipped with CADENCE; a repository selects it through the [Branch Strategy Binding](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding) (`bound-strategy: trunk-based`).

**Name-agnostic by construction.** No concrete branch name is hardcoded in this document. The integration branch identifier, its protection settings, and the branch-naming convention are **resolved dynamically from the binding** (`CADENCE_ORG.md#branch-strategy-binding`). Wherever this specification refers to "the integration branch", read "the branch declared in the binding's `integration-branch` field".

## The Integration Branch Is the Trunk

**Exactly one long-lived branch exists: the integration branch (the trunk).** All feature work merges into it, it embodies the current accepted state of the project, and it serves as the sole baseline for answering "is this change merged?". Its concrete identifier is specified in the binding's `integration-branch` field.

Unlike the `long-lived-feature-release` topology, a trunk-based repository maintains **no** parallel long-lived production-mirror or stabilization branches. Release points are cut directly from the trunk tip on demand (either as immutable Git tags or ephemeral, short-lived release branches) and never persist as secondary integration targets.

| Branch role | Lifetime | Merge target for features? |
|---|---|---|
| Integration branch (trunk) | Long-lived (the only one) | **Yes** |
| Feature / per-change branch | Short-lived; deleted on merge | n/a — it is what merges in |
| Release point | Ephemeral (tag, or short-lived branch cut from the trunk tip) | No |

The release path is straightforward: cut a release marker directly from the **trunk tip** and never maintain it as a parallel integration target. "Is this merged?" always resolves against the trunk, never against a release marker.

## The Integration Branch Is Protected — No Direct Changes

Whether the integration branch is protected is governed by the binding's `integration-branch-protected` field. **When protection is declared, no commits may be pushed directly to the integration branch.** Every change reaches the trunk exclusively by merging a branch through an MR/PR targeting it. This requirement applies across **all** artifact transitions produced by the SDLC, not merely application source code:

- **Spec creation** (`problem.md`, `spec.md`, `test-plan.md`, stubs) — authored on a branch, merged via MR.
- **Spec approvals** and any `status` transition in `metadata.yaml` — committed on a branch, merged via MR.
- **Implementation** (`Source/` and `Tests/` changes) — authored on a branch, merged via MR.
- **Archive** (moving artifacts to `archive/`, `CHANGELOG.md` updates, ADR/intent promotion) — committed on a branch, merged via MR.
- **Documentation, policy, and config changes** — likewise authored on a branch, merged via MR.

There is no "small enough to commit straight to the trunk" exception. Even a single-file edit follows the `branch → MR → merge` lifecycle. Process right-sizing (see `change-tiers.md`) may compress *which review steps execute*, but it never permits a direct push to a protected integration branch.

Using a dedicated branch per change ensures every transition is reviewable and revertable as a coherent unit, keeping the integration branch continuously aligned with work that cleared an MR gate.

## Branch Naming

The branch-naming convention is specified by the binding's `branch-naming-convention` field. The default grammar shipped with CADENCE is **`{phase}/{type}/{id}`** — three `/`-delimited segments derived deterministically from the ticket's `metadata.yaml`. The branch name is a structured projection of ticket state, not free-form text.

- **`{phase}`** — the lifecycle phase, determined from the ticket's current `status` when the branch is created:

  | `metadata.yaml` `status` | `{phase}` |
  |---|---|
  | `draft`, `triaged`, `spec-in-review` | `spec` |
  | `spec-approved`, `in-progress`, `in-review` | `impl` |
  | `merged`, `archived`, `cancelled` | `archive` |

- **`{type}`** — the ticket's `type` field verbatim: `feature` \| `bug` \| `tech-debt` \| `security` \| `documentation` \| `epic`.
- **`{id}`** — the ticket identifier verbatim (e.g., `ORD-40`). Because it is always the **final** segment, a branch name unambiguously resolves back to its ticket by taking the last `/`-delimited component — even when `{type}` contains a hyphen (`tech-debt`).

Examples: `spec/feature/ORD-40` · `impl/bug/ORD-41` · `archive/tech-debt/ORD-25`.

Rules:

- **Casing.** Lowercase the `{phase}` and `{type}` segments; preserve `{id}` in its canonical tracker casing.
- **The phase is fixed at branch-creation time** from the then-current `status`; branches are **never** renamed as the ticket progresses. Because the workflow cuts a fresh branch for each artifact transition — spec authoring, implementation, and archival are distinct MRs — a ticket typically has a separate branch for each phase it traverses, each carrying that phase's prefix. An `epic` ships no code implementation, so it never creates an `impl/` branch.
- Every tool or role that constructs or parses branch names (the `cadence-implementer` agent's branch-creation step; the `/cadence-review` and `/cadence-maintain` branch-to-ticket resolution) adheres to the convention resolved from the binding.

## Implications for the SDLC Workflow

Any workflow step that asks "has this change been merged?" evaluates against **the integration branch named by the binding**, never against a release marker or the existence of a feature branch:

- **PRs / MRs** open against the integration branch.
- **`/cadence-maintain`** computes the review diff against the integration branch resolved from the binding.
- **`/cadence-archive`** treats a change as merged when its commit is reachable on the integration branch (or when `metadata.yaml` records `status: merged`).
- **`metadata.yaml`** fields `status: merged` and `merged_at` are set once the feature PR merges into the integration branch.
- **Branch → ticket resolution** (`/cadence-review`, `/cadence-maintain`) recovers the ticket ID as the **final** `/`-delimited segment of the branch name, per the *Branch Naming* convention above.

## Post-Merge Branch Lifecycle

**Feature branches are deleted once their MR merges — history is not preserved on the feature branch.** The forge is configured to auto-delete head branches upon merge, and merges use **squash** commits, so the branch's granular per-cycle commit history does **not** enter the integration branch's ancestry. This is deliberate: individual red-green-refactor commits are working scaffolding, not the permanent governance record.

The **lifecycle record is preserved in repository artifacts by design**, so deleting the branch loses nothing essential:

- the **squash commit on the integration branch** (capturing the merged change as a single reviewable/revertable unit referencing its PR);
- the ticket's **`archive/{id}/` artifacts** — `decisions.md`, `submission.md`, `summary.md`, `spec.md`, and `test-plan.md`;
- the **`CHANGELOG.md`** entry.

Consequences for tooling and agents:

- Do **not** rely on a post-merge feature branch existing locally or on the remote. "Is this merged?" resolves against the integration branch, never against the presence of the feature branch.
- `/cadence-archive`'s "clean up the feature branch" step is satisfied automatically by the forge's auto-delete setting; a **missing** post-merge branch is the expected state, not drift.
- Pruning local branches after merge is routine workspace maintenance, not a policy violation.

## Promotion to Production

In a trunk-based topology, promoting to production consists of cutting a release marker (tag or ephemeral release branch) from the **trunk tip** and deploying it. This is an independent release activity outside the per-ticket merge or archive lifecycle. Archiving a ticket does not require the change to be present on any release marker — only that it is reachable on the integration branch.

## Rationale

Maintaining a single integration branch with short-lived feature branches minimizes branch divergence and reduces "is this merged?" to a single-branch check. Codifying this convention — one trunk integrates all work while releases are ephemeral markers cut from its tip — prevents two common failure modes: (1) blocking archival or acceptance because a change "isn't on a release branch" when it has already merged to the trunk, and (2) mistaking a release marker for a secondary integration target and computing review diffs against the wrong base.
