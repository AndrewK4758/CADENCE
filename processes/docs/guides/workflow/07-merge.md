# Workflow Step 07 — Merge

> Part of the per-step workflow guide series. This guide details the **Merge** step. For the preceding gate see [`06-maintainer-acceptance.md`](06-maintainer-acceptance.md); for the end-to-end workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Branch roles and protection rules are governed by the repository's [Branch Strategy Binding](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding) and its bound strategy policy under [`docs/policies/branch-strategy/`](../../policies/branch-strategy/).

| | |
|---|---|
| **Step** | Merge |
| **Who** | Reviewer / Maintainer |
| **Consumes** | A remote MR/PR whose required tier gates have passed — Maintainer Accepted (Medium/High) or Code Reviewed (Low/Trivial) |
| **Produces** | The squash-merged change on the bound integration branch (`develop` or `main` per `CADENCE_ORG.md` §15); `status: merged` + `merged_at` set |
| **Leads to** | [Archive](08-archive.md) (`/cadence-archive`) |

---

## Purpose

Merge is the explicit transition where reviewed, gate-approved work lands on the repository's integration branch and becomes part of the project's accepted state. CADENCE separates **Merge** from [Gate 3: Maintainer Acceptance](06-maintainer-acceptance.md) by design: Gate 3 *authorizes* acceptance, while Step 07 *executes* the remote MR/PR merge through the forge gate and synchronizes the local integration branch.

## Resolving the integration branch (`CADENCE_ORG.md` §15)

Every repository declares its branching topology and integration branch name in [`CADENCE_ORG.md#branch-strategy-binding`](../../agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding) (§15), backed by one of the two portable strategy policies:

- **[`long-lived-feature-release.md`](../../policies/branch-strategy/long-lived-feature-release.md)** — `develop` serves as the persistent integration branch where all feature MRs merge, `release/*` branches handle release stabilization, and `master`/`main` acts as the production mirror:

  | Branch | Role | Merge target for features? |
  |---|---|---|
  | `develop` | Integration branch — current accepted state | **Yes** |
  | `release/*` | Stabilization — cut from `develop`, promoted to `master`/`main` | No |
  | `master` / `main` | Production mirror — what is deployed | No |
  | `impl/{type}/{id}` | Short-lived per-ticket worktree branch; merges into `develop` via remote MR/PR | n/a |

- **[`trunk-based.md`](../../policies/branch-strategy/trunk-based.md)** — a single long-lived trunk (`main`) serves as the integration branch into which all short-lived `impl/{type}/{id}` branches merge via remote MR/PR, with releases cut as tags or ephemeral branches from the trunk tip.

Under both strategies, **"is this change merged?" always resolves against the bound integration branch** (`develop` in `long-lived-feature-release`, `main` in `trunk-based`). Under `long-lived-feature-release`, promoting commits from `develop` through `release/*` to the production mirror is a separate release activity outside the per-ticket merge and archive cycle — a commit reachable on `develop` **counts as merged** even before it reaches the production mirror.

## The integration branch is protected — every change merges via remote MR/PR

**Never commit or merge directly into local `develop` or `main`.** Every change — production code, tests, specification artifacts, `status` transitions in `metadata.yaml`, documentation, and archival commits — is authored in a dedicated `git worktree` on its phase branch (`spec/{type}/{id}`, `impl/{type}/{id}`, `archive/{type}/{id}`), pushed to `origin`, opened as a remote Pull Request / Merge Request targeting the integration branch (`gh pr create --base <integration-branch>` or `glab mr create --target-branch <integration-branch>`), merged on the remote (`gh pr merge` / `glab mr merge`), and then pulled into the local integration branch checkout (`git pull origin <integration-branch>`).

There is no "small enough to push straight to the integration branch" exception. Process right-sizing ([`change-tiers.md`](../../policies/change-tiers.md)) adjusts *which review gates run*, never branch protection.

## Automatic Local Offload during Pre-Merge Verification (`offload_log_triage`)

When verifying final pre-merge CI / local gate checks (`ci-templates/scripts/run-gates.sh` or the repository's full test runner) before executing `gh pr merge` / `glab mr merge`, CADENCE automatically routes command output through the read-only `offload_log_triage` / `log-triage` coprocessor (`local-fast-cpu` at **0 MB VRAM**). This compacts multi-thousand-line build and test logs into a clean pass/fail summary with verbatim error coordinates while saving the complete unedited log to `/tmp/agy-last-triage.log`.

## What to do

1. **Confirm all required gates for the ticket's tier have passed:**
   - **Trivial tier** — CI pipeline green; documentation-only changes auto-merge, while config-value, dependency, and release-cut MRs have one human reviewer approval.
   - **Low tier** — Gate 2 Code Review ([`05-code-review.md`](05-code-review.md)) approved by one human reviewer, with all `out-of-scope-defect` follow-up dispositions recorded in `submission.md`.
   - **Medium / High tier** — both Gate 2 Code Review ([`05-code-review.md`](05-code-review.md)) and Gate 3 Maintainer Acceptance ([`06-maintainer-acceptance.md`](06-maintainer-acceptance.md)) approved (`maintainer_approved_at` set in `metadata.yaml`).
2. **Merge the remote MR/PR into the integration branch** on the forge (`gh pr merge --squash` or `glab mr merge`) once target CI is green, and pull the updated integration branch locally (`git pull origin <integration-branch>`).
3. **Verify post-merge lifecycle state.** Ensure `metadata.yaml` records `status: merged` and `merged_at` (and project the `merged` status to the bound tracker per `CADENCE_ORG.md` §9). The forge automatically deletes the short-lived `impl/{type}/{id}` head branch upon merge, and the local worktree can be pruned cleanly.

> **"Is it merged?" always checks the bound integration branch.** Once the squash merge commit is reachable on the integration branch (`develop` or `main` per `CADENCE_ORG.md` §15), the ticket is ready for [Step 08 — Archive](08-archive.md) (`/cadence-archive`).

## Definition of done

- [ ] All required human and CI gates for the ticket's tier have passed.
- [ ] The remote MR/PR merged cleanly into the bound integration branch with green CI.
- [ ] Local integration branch updated via `git pull origin <integration-branch>` and worktree cleaned up.
- [ ] `metadata.yaml` reflects `status: merged` and `merged_at`, projected to the bound tracker.

## What this step is NOT

- **Not a direct local commit or local merge.** Changes always merge via a remote PR/MR on the forge and are pulled down to the local integration branch.
- **Not a direct merge into the production-mirror branch (`master`/`main` under `long-lived-feature-release`).** Feature MRs target the integration branch (`develop`); production-mirror promotion happens only via release branches/PRs.
- **Not Gate 3 authorization.** Maintainer Acceptance ([`06-maintainer-acceptance.md`](06-maintainer-acceptance.md)) *authorizes* the merge; this step *executes* it.
- **Not ticket archival.** Relocating `specs/{ticket-id}/` to `archive/{ticket-id}/` and updating `CHANGELOG.md` happens next in [`08-archive.md`](08-archive.md).

## Related documents

- [`06-maintainer-acceptance.md`](06-maintainer-acceptance.md) — Gate 3, which authorizes the merge for Medium and High tier changes.
- [`05-code-review.md`](05-code-review.md) — Gate 2, which authorizes the merge for Low tier changes.
- [`08-archive.md`](08-archive.md) — the final lifecycle step (`/cadence-archive`), executed once the change lands on the integration branch.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../policies/branch-strategy/long-lived-feature-release.md`](../../policies/branch-strategy/long-lived-feature-release.md) · [`trunk-based.md`](../../policies/branch-strategy/trunk-based.md) — authoritative branch-strategy policies.
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — tier gate requirements prior to merge.
- [`../submitting-changes.md`](../submitting-changes.md) — forge-specific MR/PR/patchset workflows.
