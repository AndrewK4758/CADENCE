# Branch Strategy: Trunk-Based / Mainline

> **Branch-name-agnostic by binding (BTG-047).** This document names no concrete branch; the
> integration-branch name, its protection, and the naming convention resolve through the
> [Branch Strategy Binding](../../agentic-sdlc/CLAIRE_ORG.md#branch-strategy-binding).

This document models a **trunk-based (mainline)** branch strategy: a single long-lived integration
branch — "the trunk" — into which all work merges through short-lived per-change branches. It is one of
the two portable strategy documents CLAIRE ships; a repo selects it via the
[Branch Strategy Binding](../../agentic-sdlc/CLAIRE_ORG.md#branch-strategy-binding) (`bound-strategy: trunk-based`).

**Name-agnostic by construction.** This document never names a concrete branch. The concrete integration
branch name, its protection status, and the branch-naming convention are **resolved from the binding**
(`CLAIRE_ORG.md#branch-strategy-binding`), never hardcoded here. Wherever this document says
"the integration branch", read "the branch named by the binding's `integration-branch` field".

## The Integration Branch Is the Trunk

**There is exactly one long-lived branch: the integration branch (the trunk).** It is the branch feature
work merges into, the branch that represents the current accepted state of the project, and the base
against which "is this merged?" is evaluated. Its concrete name is declared in the binding's
`integration-branch` field.

Unlike a long-lived-feature-release model, a trunk-based repo keeps **no** long-lived production-mirror or
stabilization branches. Release points are cut from the trunk tip on demand (as tags or ephemeral,
short-lived release branches) and do not persist as parallel integration targets.

| Branch role | Lifetime | Merge target for features? |
|---|---|---|
| Integration branch (trunk) | Long-lived (the only one) | **Yes** |
| Feature / per-change branch | Short-lived; deleted on merge | n/a — it is what merges in |
| Release point | Ephemeral (tag, or short-lived branch cut from the trunk tip) | No |

The release path is: cut a release marker from the **trunk tip**; do not maintain it as a second
integration target. "Is this merged?" always resolves against the trunk, never against a release marker.

## The Integration Branch Is Protected — No Direct Changes

Whether the integration branch is protected is declared by the binding's `integration-branch-protected`
field. **When protection is declared, nothing commits to the integration branch directly.** Every change
reaches it only by merging a branch through an MR that targets it. This applies to **all** artifact changes
the SDLC produces, not just source code:

- **Spec creation** (`problem.md`, `spec.md`, `test-plan.md`, stubs) — authored on a branch, merged via MR.
- **Spec approvals** and any `status` transition in `metadata.yaml` — committed on a branch, merged via MR.
- **Implementation** (Source/ and Tests/ changes) — on a branch, merged via MR.
- **Archive** (moving artifacts to `archive/`, CHANGELOG updates, ADR/intent promotion) — on a branch, merged via MR.
- **Documentation, policy, and config changes** — likewise on a branch, merged via MR.

There is no "small enough to commit straight to the trunk" exception. Even a single-file edit follows
branch → MR → merge. Right-sizing (see `change-tiers.md`) may compress *which review steps run*, but it
never permits a direct commit to a protected integration branch.

Branch-per-change keeps every transition reviewable and revertable as a unit, and keeps the integration
branch always reflecting a state that passed through an MR gate.

## Branch Naming

The branch-naming convention is declared by the binding's `branch-naming-convention` field. The default
convention CLAIRE ships is **`{phase}/{type}/{id}`** — three `/`-delimited segments derived entirely from
the ticket's `metadata.yaml`. The name is a projection of the ticket's state, not free text.

- **`{phase}`** — the lifecycle phase, selected from the ticket's current `status` at the moment the branch
  is created:

  | `metadata.yaml` `status` | `{phase}` |
  |---|---|
  | `draft`, `triaged`, `spec-in-review` | `spec` |
  | `spec-approved`, `in-progress`, `in-review` | `impl` |
  | `merged`, `archived`, `cancelled` | `archive` |

- **`{type}`** — the ticket's `type` field verbatim: `feature` \| `bug` \| `tech-debt` \| `security` \|
  `documentation` \| `epic`.
- **`{id}`** — the ticket id verbatim (e.g. `ORD-40`). It is always the **last** segment, so a branch always
  resolves back to its ticket by taking the final `/`-delimited component — which stays unambiguous even
  though `{type}` may itself contain a hyphen (`tech-debt`).

Examples: `spec/feature/ORD-40` · `impl/bug/ORD-41` · `archive/tech-debt/ORD-25`.

Rules:

- **Casing.** Lowercase the `{phase}` and `{type}` segments; keep `{id}` in its canonical tracker casing.
- **The phase is fixed at branch-creation time** from the then-current `status`; branches are **not**
  renamed as the ticket advances. Because the workflow cuts a new branch per artifact transition — spec
  authoring, implementation, and archival are separate MRs — a ticket normally has a distinct branch for
  each phase it passes through, each carrying that phase's prefix. An `epic` ships no implementation, so it
  never produces an `impl/` branch.
- Anything creating or parsing a branch name (the `claire-implementer` agent's branch-creation step; the
  `/claire-review` and `/claire-maintain` branch→ticket resolution) follows the convention resolved from the binding.

## Implications for the SDLC Workflow

Any workflow step that asks "has this change been merged?" resolves against **the integration branch
named by the binding**, not against any release marker or the presence of a feature branch:

- **PRs** open against the integration branch.
- **`/claire-maintain`** computes the review diff against the integration branch resolved from the binding.
- **`/claire-archive`** treats a change as merged when its commit is reachable on the integration branch (or
  `metadata.yaml` shows `status: merged`).
- **`metadata.yaml`** `status: merged` / `merged_at` are set once the feature PR merges into the
  integration branch.
- **Branch → ticket resolution** (`/claire-review`, `/claire-maintain`) recovers the ticket id as the **final**
  `/`-delimited segment of the branch name, per the *Branch Naming* convention above.

## Post-Merge Branch Lifecycle

**Feature branches are deleted once their MR merges — history is not kept on the branch.** The forge is
configured to auto-delete a head branch on merge, and merges are **squash** merges, so the branch's
per-cycle commit history does **not** become part of the integration branch's ancestry. This is deliberate:
the granular red-green-per-cycle commits are working history, not the record.

The **lifecycle record is preserved elsewhere, by design**, so deleting the branch loses nothing that
matters:

- the **squash commit on the integration branch** (the merged change as one reviewable/revertable unit,
  referencing its PR);
- the ticket's **`archive/{id}/` artifacts** — `decisions.md`, `submission.md`, `summary.md`, and the
  spec/test-plan;
- the **`CHANGELOG.md`** entry.

Consequences for tooling and agents:

- Do **not** rely on a post-merge feature branch existing (locally or on the remote). "Is this merged?"
  resolves against the integration branch, never against the presence of the branch.
- `/claire-archive`'s "clean up the feature branch" step is satisfied automatically by the forge's auto-delete;
  a **missing** post-merge branch is the expected state, not drift.
- Pruning local branches after merge is routine cleanup, not a policy violation.

## Promotion to Production

In a trunk-based model, promotion to production is cutting a release marker (tag or ephemeral release
branch) from the **trunk tip** and deploying it. It is a separate release activity, not part of the
per-ticket merge or archive lifecycle. Archiving a ticket does not require the change to be present on any
release marker — only reachable on the integration branch.

## Rationale

A single integration branch with short-lived feature branches minimizes long-lived-branch divergence and
keeps "is this merged?" a one-branch question. Encoding the convention here — one trunk integrates,
releases are ephemeral markers cut from its tip — prevents two recurring failure modes: (1) blocking an
archive or acceptance because a change "isn't on a release branch" when it is in fact merged to the trunk,
and (2) treating a release marker as a second integration target and computing review diffs against the
wrong base.
