---
name: cadence-merge
description: Mechanize Workflow Step 07 (Merge) -- validate tier-required review/maintainer gates, rebase onto the bound integration branch, re-run verification, update merged metadata + tracker, clean up worktrees, and hand off to /cadence-archive.
argument-hint: "<ticket-id> [--no-archive]"
arguments: [ticket_id, flags]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Execute **Workflow Step 07 (Merge)** (`docs/guides/workflow/07-merge.md`) for `$ticket_id`: verify all tier-required human and automated gates have passed, confirm the branch sits cleanly on top of the repository's bound integration branch (`CADENCE_ORG.md#branch-strategy-binding`, never hardcoding `main` or `develop`), execute or merge the approved PR/MR without bypassing hooks, record `status: merged` and `merged_at`, sync the bound tracker, prune temporary worktree state, and chain `/cadence-archive $ticket_id` unless `--no-archive` is specified.

Because `/cadence-merge` performs protected-branch merge confirmation, possible tracker sync, and worktree/branch cleanup, it runs in the primary turn and delegates non-trivial merge conflict resolution or code adjustments back to `Deep-reasoning` (`xhigh` effort).

## Prerequisites (Fail-Closed — Never Bypass Gates)

Before mutating any git branch or metadata:

1. **Resolve ticket state and `#branch-strategy-binding`:**
   - Read `specs/$ticket_id/metadata.yaml` and `specs/$ticket_id/submission.md` (and run `.agents/skills/cadence-cycle/scripts/read_state.py $ticket_id` when installed).
   - Read `docs/agentic-sdlc/CADENCE_ORG.md#branch-strategy-binding` (`bound-strategy`, `integration-branch`, `integration-branch-protected`, `branch-naming-convention`). Halt fail-closed if `bound-strategy` or `integration-branch` is missing, empty, or `<placeholder>`. Echo `integration_branch=<name>` in status output.
2. **Validate tier & required human gates (`docs/policies/change-tiers.md`):**
   - Normalize `tier:` from `metadata.yaml` (`trivial | low | medium | high`). Halt immediately if empty or unrecognized (never default to Low).
   - **Medium / High tier:** confirm **both** (a) Gate 2 Code Review recorded `0` blocking findings in `submission.md` (and latest cycle ledger if present), **and** (b) Gate 3 Maintainer Acceptance is recorded (`maintainer_approved_at:` non-empty in `metadata.yaml` and `Accept` verdict recorded). If missing, halt and direct operator to `/cadence-review` or `/cadence-maintain`.
   - **Low tier:** confirm Gate 2 Code Review approved with `0` blocking findings (`out-of-scope-defect` follow-ups dispositioned per `submission.md`); Gate 3 is not required.
   - **Trivial tier:** confirm CI checks green (and 1 reviewer if config/deps/release per `change-tiers.md`).
3. **Check git & worktree cleanliness:**
   - Locate the ticket branch (`metadata.yaml` `branch:` or current worktree branch matching `{phase}/{type}/{id}`) and its forge MR/PR (`merge_request:` in `metadata.yaml` when forge-backed).
   - Refuse to proceed with uncommitted dirty files unrelated to finalizing `merged` metadata.

## Steps

### 1. Rebase onto latest `<integration-branch>` & re-verify

Check whether the ticket branch is behind the latest `<integration-branch>` (fetching `origin <integration-branch>` if a remote exists, else checking local `<integration-branch>` tip):

- If behind `<integration-branch>`, rebase the ticket worktree branch onto `<integration-branch>` **before** merging (never leave stale base conflicts hidden):
  - For trivial append-only conflicts (e.g., `CHANGELOG.md`, surface registries), preserve **both** sides' additions cleanly rather than using blind `--ours`/`--theirs`.
  - For code conflicts affecting logic or contracts, delegate resolution to `cadence-implementer` (`Deep-reasoning` tier, `xhigh` effort) in the ticket's worktree rather than forcing ad-hoc edits.
- Re-run the repository's canonical test/gate suite after rebase (or confirm CI is green on the rebased head SHA). Route outputs `>30` lines or non-zero exits through `offload_log_triage` (`:11434`, saving raw log to `/tmp/agy-last-triage.log`). If conflict resolution modified code, run `offload_deep_review(diff_range="<integration-branch>...HEAD", cwd="<repo-root>")` before proceeding.

### 2. Confirm merge posture & land onto `<integration-branch>`

Honor `integration-branch-protected`:
- **Never** pass `--no-verify` or push direct ad-hoc commits straight onto a protected integration branch.
- **When remote PR/MR is open (`merge_request:` URL / `gh` / `glab` available):** confirm target base is `<integration-branch>`, verify CI status checks pass, prompt for operator confirmation (`Merge PR/MR into <integration-branch>? (yes/no)`), execute the squash/merge (`gh pr merge` / `glab mr merge`), and update local `<integration-branch>` (`git pull --ff-only origin <integration-branch>`).
- **When operating local-only (no remote / explicit operator local-merge authorization):** prompt for explicit confirmation (`Fast-forward / squash-merge branch <branch> into <integration-branch>? (yes/no)`), fast-forward or squash cleanly into `<integration-branch>`, and verify the merge commit is an ancestor of `<integration-branch>`.

### 3. Record `status: merged` + sync tracker + clean up worktree

1. Capture exact second-precision UTC timestamp: `date -u +%Y-%m-%dT%H:%M:%SZ`.
2. Update `specs/$ticket_id/metadata.yaml` setting `status: merged` and `merged_at: "<UTC>"` (preserving existing fields/quoting rules).
3. If `CADENCE_ORG.md#tracker-binding` resolves to a live tracker for this ticket's prefix, invoke the designated `/cadence-sync-*` skill for `$ticket_id` once to project `merged` status.
4. Safely clean up the temporary ticket worktree and branch **only after confirming** the ticket's changes are reachable on `<integration-branch>` (`git worktree remove` + `git branch -d` — never `git branch -D` blindly on unverified commits).

### 4. Hand off to archival

Unless `--no-archive` was passed or the ticket is `Trivial` without a `specs/$ticket_id/` directory:
- Invoke `/cadence-archive $ticket_id` (or prompt/display the exact runnable command `/cadence-archive $ticket_id` if the runtime lacks command composition).
- Report final summary: ticket ID, tier, integration branch, merge commit/PR URL, `merged_at`, tracker sync outcome, worktree cleanup status, and next step (`/cadence-archive`).

## Constraints

- **Never hardcode `main` or `develop`.** Always resolve `<integration-branch>` from `CADENCE_ORG.md#branch-strategy-binding`.
- **Never bypass human gates or hooks.** Never merge Medium/High tickets without Gate 2 + Gate 3 (`maintainer_approved_at`), never merge Low tickets without Gate 2, and never use `--no-verify`.
- **Single-writer safety on `metadata.yaml` update & worktree removal.** Confirm merge landed on `<integration-branch>` before deleting any branch/worktree.

## Examples

```text
/cadence-merge BTG-142
/cadence-merge BTG-142 --no-archive
```

## Local Model Offload Integration (:11434)
- Post-rebase test, build, and gate outputs exceeding 30 lines or exiting non-zero automatically pipe through `offload_log_triage` (`:11434`), saving raw logs to `/tmp/agy-last-triage.log`.
- Any rebase conflict resolution touching production code triggers `offload_deep_review` (`:11434`) prior to merge.
