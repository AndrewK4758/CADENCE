# Branch Strategy: Long-Lived Feature / Integration / Release

> **Branch-name-agnostic by binding (BTG-047).** This document succeeds the repository's original single `branch-strategy.md`: all concrete branch names have been abstracted from the narrative and parameterized as roles resolved through the [Branch Strategy Binding](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding). An adopting repository selects this strategy by declaring `bound-strategy: long-lived-feature-release` in the binding.

This policy defines a **long-lived feature/integration/release** branching topology: a persistent integration branch paired with a persistent production-mirror branch, separated by stabilization (release) branches cut between them. It is one of two portable branching strategy specifications shipped with CADENCE; a repository activates it via the binding (`bound-strategy: long-lived-feature-release`).

**Name-agnostic by construction.** No concrete branch identifier appears in this document. The actual integration branch name, its branch-protection posture, and the naming grammar are **resolved dynamically from the binding** (`CADENCE_ORG.md#branch-strategy-binding`) rather than hardcoded here. Whenever this specification refers to "the integration branch" or "the production-mirror branch", it denotes the branch bound to that role — the binding's `integration-branch` setting for the former, and the strategy's designated production-mirror role for the latter.

This topology serves repositories that maintain a dedicated production-mirror branch alongside their primary integration branch, where the common default assumption that the production-mirror branch is the day-to-day merge target does **not** hold.

## The Integration Branch vs. the Production-Mirror Branch

**The integration branch is where feature work merges.** It represents the current accepted state of the codebase and serves as the baseline against which "is this change merged?" is evaluated. Its concrete identifier is declared in the binding's `integration-branch` field.

**The production-mirror branch tracks what is deployed to production.** It is **not** the merge target for routine feature delivery, and the absence of a commit from the production-mirror branch does **not** imply the change is unmerged.

| Branch role | Lifetime | Merge target for features? |
|---|---|---|
| Integration branch — current accepted state | Long-lived | **Yes** |
| Stabilization / release branch — cut from the integration branch, promoted to the production mirror | Long-lived per release line | No |
| Production-mirror branch — what is deployed | Long-lived | No |
| Feature / per-change branch — merges into the integration branch via PR | Short-lived; deleted on merge | n/a |

The promotion flow is: **integration branch → stabilization/release branch → production-mirror branch.**
Feature delivery always targets the integration branch; stabilization branches are cut specifically for release hardening rather than ongoing feature merges. Version-derivation tooling may attach prerelease suffixes according to branch role (for example, marking the integration branch with a prerelease label while leaving release and production-mirror branches unlabeled); the version number itself is derived from git history by the `/cadence-release` skill.

## The Integration Branch Is Protected — No Direct Changes

Whether the integration branch enforces branch protection is declared via the binding's `integration-branch-protected` field. **When protection is declared, no commits are pushed directly to the integration branch.** Every modification reaches the integration branch exclusively by merging a short-lived branch through an MR/PR targeting it. This rule governs **all** artifacts produced across the SDLC, not only application source code:

- **Spec creation** (`problem.md`, `spec.md`, `test-plan.md`, stubs) — authored on a dedicated branch and merged via MR.
- **Spec approvals** and any `status` transition in `metadata.yaml` — committed on a branch and merged via MR.
- **Implementation** (`Source/` and `Tests/` changes) — developed on a branch and merged via MR.
- **Archive** (relocating artifacts to `archive/`, updating `CHANGELOG.md`, promoting ADRs and intent insights) — committed on a branch and merged via MR.
- **Documentation, policy, and configuration updates** — likewise authored on a branch and merged via MR.

There is no "small enough to commit directly to the integration branch" carve-out. Even a single-file adjustment follows the `branch → MR → merge` path. Process right-sizing (see `change-tiers.md`) may streamline *which review gates execute*, but it never authorizes a direct push to a protected integration branch.

Enforcing branch-per-change ensures every state transition remains reviewable and revertable as an atomic unit, guaranteeing the integration branch always reflects work that cleared an explicit MR gate.

## Branch Naming

The branch-naming grammar is declared by the binding's `branch-naming-convention` field. The default convention shipped by CADENCE is **`{phase}/{type}/{id}`** — three `/`-separated segments projected deterministically from the ticket's `metadata.yaml`. The branch name is a structured projection of ticket state rather than free-form text.

- **`{phase}`** — the lifecycle stage, determined from the ticket's current `status` at the moment the branch is created:

  | `metadata.yaml` `status` | `{phase}` |
  |---|---|
  | `draft`, `triaged`, `spec-in-review` | `spec` |
  | `spec-approved`, `in-progress`, `in-review` | `impl` |
  | `merged`, `archived`, `cancelled` | `archive` |

- **`{type}`** — the ticket's `type` field verbatim: `feature` \| `bug` \| `tech-debt` \| `security` \| `documentation` \| `epic`.
- **`{id}`** — the ticket identifier verbatim (e.g., `ORD-40`). Because it always occupies the **final** segment, any branch name resolves back to its ticket simply by extracting the last `/`-delimited token — remaining unambiguous even when `{type}` contains a hyphen (`tech-debt`).

Examples: `spec/feature/ORD-40` · `impl/bug/ORD-41` · `archive/tech-debt/ORD-25`.

Rules:

- **Casing.** Format the `{phase}` and `{type}` segments in lowercase; preserve `{id}` in its canonical tracker casing.
- **The phase prefix is locked at branch creation** based on the ticket's `status` at that point; branches are **never** renamed as the ticket progresses. Because the workflow opens a distinct branch for each artifact transition — specification authoring, implementation, and archival are separate MRs — a ticket naturally uses a dedicated branch per phase, each bearing its corresponding prefix. An `epic` delivers no direct implementation and therefore never generates an `impl/` branch.
- **This grammar supersedes** legacy `{type}/{sprint.team}/{ticket-description}` patterns: sprint/team tokens and free-text slugs are replaced by the status-driven phase prefix and machine-parseable ticket ID. All tooling and roles that construct or parse branch names (such as the `cadence-implementer` agent's branch creation step and the `/cadence-review` and `/cadence-maintain` branch-to-ticket resolution logic) adhere to this specification.

## Implications for the SDLC Workflow

Every workflow gate or skill that evaluates "has this change been merged?" checks **the integration branch named by the binding**, never the production-mirror branch:

- **PRs / MRs** target the integration branch.
- **`/cadence-maintain`** calculates the review diff against the integration branch (not the production mirror).
- **`/cadence-archive`** considers a change merged once its commit is reachable on the integration branch (or when `metadata.yaml` records `status: merged`). A commit reachable on the integration branch that has not yet been promoted to the production-mirror branch **counts as merged** for archival.
- **`metadata.yaml`** fields `status: merged` and `merged_at` are recorded as soon as the feature PR merges into the integration branch.
- **Branch → ticket resolution** (`/cadence-review`, `/cadence-maintain`) extracts the ticket ID from the **final** `/`-delimited segment of the branch name, following the *Branch Naming* rules above.

## Post-Merge Branch Lifecycle

**Feature branches are deleted automatically upon MR merge — historical record does not live on the feature branch.** The repository forge is configured to auto-delete head branches on merge, and merges use **squash** commits, meaning the branch's granular per-cycle TDD commits do **not** persist in the integration branch's commit graph. This is intentional: red-green-refactor cycle commits serve as working scaffolding during development and review, not the permanent archive.

The **authoritative lifecycle record is preserved in dedicated repository artifacts**, so deleting the feature branch discards no governance context:

- the **squash commit on the integration branch** (capturing the merged change as a single reviewable and revertable unit linked to its PR);
- the ticket's **`archive/{id}/` directory** — containing `decisions.md`, `submission.md`, `summary.md`, `spec.md`, and `test-plan.md`;
- the **`CHANGELOG.md`** release entry.

Consequences for tooling and agents:

- Never depend on a feature branch remaining present (locally or on the remote) after merge. "Is this merged?" is always answered by querying the integration branch, never by checking whether the feature branch still exists.
- `/cadence-archive`'s branch-cleanup step is satisfied automatically when the forge auto-deletes the branch; an **absent** post-merge feature branch is the expected state, not configuration drift.
- Pruning merged local branches is standard workspace hygiene, not a policy violation.

## Promotion to Production

Promoting accepted changes from the integration branch through a stabilization/release branch to the production-mirror branch is a separate release-engineering activity outside the per-ticket merge and archive lifecycle. Archiving a completed ticket does not wait for the change to reach a release or production-mirror branch.

## Rationale

Standard forge defaults and onboarding templates frequently conflate the production-mirror branch with the integration branch. Explicitly codifying their distinct roles here — the integration branch integrates ongoing work while the production-mirror branch reflects deployed production — eliminates two common failure modes: (1) stalling ticket archival or maintainer acceptance because a merged change is not yet on the production mirror, and (2) diffing reviews against the wrong base branch, which pollutes the review with unrelated integration-versus-production delta.
