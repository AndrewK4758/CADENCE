# Branch Strategy: Long-Lived Feature / Integration / Release

> **Branch-name-agnostic by binding (BTG-047).** This is the reworded successor to the repo's
> original single `branch-strategy.md`: every concrete branch name has been removed from the prose
> and parameterized as a role resolved through the
> [Branch Strategy Binding](../../agentic-sdlc/CLAIRE_ORG.md#branch-strategy-binding). A repo
> selects this strategy by setting the binding's `bound-strategy: long-lived-feature-release`.

This document models a **long-lived feature/integration/release** branch strategy: a persistent
integration branch alongside a persistent production-mirror branch, with stabilization (release) branches
cut between them. It is one of the two portable strategy documents CLAIRE ships; a repo selects it via
the binding (`bound-strategy: long-lived-feature-release`).

**Name-agnostic by construction.** This document never names a concrete branch. The concrete integration
branch name, its protection status, and the branch-naming convention are **resolved from the binding**
(`CLAIRE_ORG.md#branch-strategy-binding`), never hardcoded here. Wherever this document says
"the integration branch" or "the production-mirror branch", read "the branch named by the binding" — the
binding's `integration-branch` field for the former, and the strategy's designated production-mirror role
for the latter.

This strategy exists for repos that keep a separate production-mirror branch alongside the integration
branch, so the default tooling assumption that the production-mirror branch is the merge target does **not**
match the project's reality.

## The Integration Branch vs. the Production-Mirror Branch

**The integration branch is where feature work merges.** It is the branch that represents the current
accepted state of the project, and the base against which "is this merged?" is evaluated. Its concrete name
is declared in the binding's `integration-branch` field.

**The production-mirror branch tracks what is deployed to production.** It is **not** the merge target for
day-to-day feature work, and a change being absent from it does **not** mean it is unmerged.

| Branch role | Lifetime | Merge target for features? |
|---|---|---|
| Integration branch — current accepted state | Long-lived | **Yes** |
| Stabilization / release branch — cut from the integration branch, promoted to the production mirror | Long-lived per release line | No |
| Production-mirror branch — what is deployed | Long-lived | No |
| Feature / per-change branch — merges into the integration branch via PR | Short-lived; deleted on merge | n/a |

The promotion path is: **integration branch → stabilization/release branch → production-mirror branch.**
Feature work always targets the integration branch; stabilization branches are cut for release
stabilization, not day-to-day merges. A version-derivation tool may label prereleases by branch role (e.g.
the integration branch → a prerelease suffix, while release and production-mirror branches are unlabeled);
the version number itself is derived from git state by the `/claire-release` skill.

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

There is no "small enough to commit straight to the integration branch" exception. Even a single-file edit
follows branch → MR → merge. Right-sizing (see `change-tiers.md`) may compress *which review steps run*,
but it never permits a direct commit to a protected integration branch.

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
- **This convention supersedes** any older `{type}/{sprint.team}/{ticket-description}` form: the sprint/team
  token and the free-text description are dropped in favour of the status-driven phase prefix and the
  machine-extractable ticket id. Anything creating or parsing a branch name (the `claire-implementer` agent's
  branch-creation step; the `/claire-review` and `/claire-maintain` branch→ticket resolution) follows this section.

## Implications for the SDLC Workflow

Any workflow step that asks "has this change been merged?" resolves against **the integration branch named
by the binding**, not against the production-mirror branch:

- **PRs** open against the integration branch.
- **`/claire-maintain`** computes the review diff against the integration branch (not against the production
  mirror).
- **`/claire-archive`** treats a change as merged when its commit is reachable on the integration branch (or
  `metadata.yaml` shows `status: merged`). A commit that is on the integration branch but not yet on the
  production-mirror branch **counts as merged** for archival purposes.
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

Promotion of accepted work from the integration branch through a stabilization/release branch to the
production-mirror branch is a separate release activity, not part of the per-ticket merge or archive
lifecycle. Archiving a ticket does not require the change to be present on a release or production-mirror
branch.

## Rationale

Tooling and onboarding defaults frequently treat the production-mirror branch as the integration branch.
Encoding the real convention here — the integration branch integrates, the production-mirror branch mirrors
production — prevents two recurring failure modes: (1) blocking an archive or acceptance because a change
"isn't on the production mirror" when it is in fact merged to the integration branch, and (2) computing
review diffs against the wrong base and surfacing unrelated production-vs-integration drift as if it were
part of the change under review.
