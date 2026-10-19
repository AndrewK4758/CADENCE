# Workflow Step 07 — Merge

> Part of the per-step workflow guide series. This document details the **Merge** step. For the preceding gate see [`06-maintainer-acceptance.md`](06-maintainer-acceptance.md); for the whole-workflow overview see [`../getting-started.md`](../getting-started.md) §2.3. Branch roles are governed by [`branch-strategy.md`](../../policies/branch-strategy.md).

| | |
|---|---|
| **Step** | Merge |
| **Who** | Reviewer |
| **Consumes** | An MR whose gates have passed — accepted (Medium/High) or code-reviewed (Low) |
| **Produces** | The change landed on `develop`; `status: merged` + `merged_at` set |
| **Leads to** | [Archive](08-archive.md) |

---

## Purpose

Merge is the point where reviewed, accepted work becomes part of the project's current accepted state. It is deliberately a **separate, explicit step** — the maintainer *authorizes* acceptance, but the merge itself is a distinct action that lands the branch on the integration branch through the MR gate.

## The integration branch is `develop`

**`develop` is the integration / main branch** — the branch feature work merges into and the branch that represents the current accepted state. This project does **not** use `master`/`main` as the merge target:

| Branch | Role | Merge target for features? |
|---|---|---|
| `develop` | Integration / main — current accepted state | **Yes** |
| `release/*` | Stabilization — cut from `develop`, promoted to `master` | No |
| `master` | Production mirror — what's deployed | No |
| `feature/*` | Per-ticket work; merges into `develop` via MR | n/a |

The promotion path is `develop` → `release/*` → `master`, and that promotion is a **separate release activity**, not part of the per-ticket merge or archive lifecycle. A change being absent from `master` does **not** mean it is unmerged.

## `develop` is protected — everything merges through an MR

**Nothing commits to `develop` directly.** Every change — source, spec artifacts, `status` transitions in `metadata.yaml`, docs, config — reaches `develop` only by merging a branch through an MR that targets `develop`. There is no "small enough to commit straight to `develop`" exception; even a single-file edit follows branch → MR → merge. Right-sizing by tier (see [`change-tiers.md`](../../policies/change-tiers.md)) may compress *which review steps run*, but it never permits a direct commit.

This keeps every transition reviewable and revertable as a unit, and keeps `develop` always reflecting a state that passed through a gate.

## What to do

1. **Confirm the gates for the change's tier have passed.**
   - **Low tier** — one Code Review approval ([`05-code-review.md`](05-code-review.md)) is sufficient.
   - **Medium / High tier** — Maintainer Acceptance ([`06-maintainer-acceptance.md`](06-maintainer-acceptance.md)) returned **Accept** (`maintainer_approved_at` is set).
   - **Trivial** — CI green; documentation-only auto-merges, config/deps needs one reviewer.
2. **Merge the MR into `develop`** through the forge (or the SourceHut equivalent). CI on the merge target must be green.
3. **Confirm the lifecycle fields land.** Once the feature MR merges into `develop`, `metadata.yaml` shows `status: merged` and `merged_at` is set. Because these fields live on the branch, they arrive on `develop` with the merge.

> **"Is it merged?" resolves against `develop`.** A commit reachable on `develop` counts as merged for every downstream step, including archival — regardless of whether it has been promoted to `release/*` or `master`.

## Definition of done

- [ ] The change's tier gates have passed (code review, and maintainer acceptance for Medium/High).
- [ ] The MR merged into `develop` with green CI on the target.
- [ ] `metadata.yaml` shows `status: merged` with `merged_at` set, present on `develop`.

## What this step is NOT

- **Not a merge to `master`.** Feature work targets `develop`; `master` is a production mirror updated via the separate release-promotion path.
- **Not a direct commit.** `develop` is protected — no change lands without an MR, regardless of size.
- **Not the maintainer's authorization.** Acceptance (Gate 3) *authorizes*; this step *performs* the merge.
- **Not archival.** Moving artifacts to `archive/` and updating the CHANGELOG is the next step, [`/claire-archive`](08-archive.md).

## Related documents

- [`06-maintainer-acceptance.md`](06-maintainer-acceptance.md) — the gate that authorizes the merge (Medium/High).
- [`05-code-review.md`](05-code-review.md) — the gate that authorizes the merge (Low).
- [`08-archive.md`](08-archive.md) — the next step, run once the change is on `develop`.
- [`../getting-started.md`](../getting-started.md) — whole-workflow overview and per-tier matrix.
- [`../../policies/branch-strategy.md`](../../policies/branch-strategy.md) — the authoritative branch-role policy (`develop` vs `master`, protection, "is it merged?").
- [`../../policies/change-tiers.md`](../../policies/change-tiers.md) — which gates each tier requires before merge.
- [`../submitting-changes.md`](../submitting-changes.md) — how MRs are submitted across forges.
