---
name: cadence-release
description: Cut a new repository release -- resolve CADENCE_ORG.md#version-scheme-binding (calver-yyyy-ww default or semver), prepare release artifacts + specs/RELEASE-<ver>/submission.md on a release PR branch, confirm with operator before editing/opening PR (Gate A), merge onto integration-branch, and confirm before creating/pushing an annotated tag (Gate B).
argument-hint: "[major|minor|patch]  (optional bump override)"
arguments: [bump_override]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Cut a new release from pending `## [Unreleased]` items in `CHANGELOG.md` using the repository's bound version scheme (`CADENCE_ORG.md#version-scheme-binding`: `calver-yyyy-ww` default or `semver`). This skill executes **inline within the primary conversation turn** -- never inside a delegated subagent -- because it enforces **two mandatory human confirmation pauses**: **Gate A** before mutating files or opening the release PR, and **Gate B** after merging onto `<integration-branch>` before creating and pushing the annotated git tag.

The release workflow never pushes direct commits to a protected `<integration-branch>` (`CADENCE_ORG.md#branch-strategy-binding`): it cuts a `release/RELEASE-<version>` branch/worktree, promotes `[Unreleased]` entries under the new version heading, updates `README.md`, authors `docs/releases/<tag>.md` and `specs/RELEASE-<version>/submission.md`, validates `docs/releases/<tag>.md` against `authored-doc-gate.sh`, commits and opens/merges the release PR (`RELEASE-<version>`), fast-forwards local `<integration-branch>`, and then (upon Gate B confirmation) creates and pushes the annotated `git tag -a <tag>`. Version bump/increment calculation follows `docs/policies/version-scheme/<name>.md` and is **approved by the human operator before any file is modified.**

`$bump_override` is optional. When provided (e.g., `major` | `minor` | `patch` under `semver`, or next week/patch override under `calver-yyyy-ww`), the skill displays both its computed classification from `docs/policies/version-scheme/<name>.md` and the override side by side, warning prominently if an override downgrades a breaking change.

## Prerequisites

Confirm all preconditions prior to proposing a release version:

- **Git repository with version baseline:** at least one existing release tag matching the bound `version-pattern` or a version line in `README.md` to establish the baseline version. If neither exists, ask the operator for the current baseline version.
- **`CHANGELOG.md` present with `## [Unreleased]`:** if missing, halt and inform the operator that `/cadence-release` requires a Keep-a-Changelog-structured `CHANGELOG.md`.
- **Non-empty `[Unreleased]` section:** if `## [Unreleased]` contains zero entries, halt with: `"Nothing to release — [Unreleased] is empty."` Never cut an empty release.
- **Clean git working tree:** inspect `git status --porcelain`. If uncommitted modifications exist, warn the operator and ask whether to continue — a release PR commit must contain only release artifacts (`CHANGELOG.md`, `README.md`, `docs/releases/<tag>.md`, `specs/RELEASE-<version>/submission.md`, plus `authored-doc-ledgers.sh` if updated). Proceed only after explicit operator confirmation.
- **`docs/releases/` directory:** ensure `docs/releases/` exists (creating it inside the release branch if absent).

## Steps

### 1. Gather repository state

- **Current baseline version:** find the highest matching version tag (resolved from `version-pattern`, e.g., `vYYYY.WW.N` or `vX.Y.Z`) and cross-verify it against the `README.md` version declaration. If the git tag and `README.md` disagree, display both values and ask the operator which one is authoritative before proceeding.
- **Release date:** run `date +%F` (ISO-8601 `YYYY-MM-DD`) for the changelog version header and release notes metadata.
- **Unreleased changelog items:** read the `## [Unreleased]` section of `CHANGELOG.md`, capturing every `###` category (`Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`) and its bullet items. These entries drive both the version-bump calculation and the `docs/releases/<tag>.md` draft.
- **Integration branch & remote:** resolve `<integration-branch>` from `CADENCE_ORG.md#branch-strategy-binding` and inspect the tracking remote for PR/MR and Step 7 push commands.

### 1b. Resolve the bound version scheme (mandatory, before computing the bump)

Read the Version-Scheme Binding section (`#version-scheme-binding`) in `docs/agentic-sdlc/CADENCE_ORG.md` and extract `bound-version-scheme`, `version-pattern`, and `cycle-qualifying-cut` from both the machine markers and the field table, verifying that both representations match.

HALT immediately, naming `CADENCE_ORG.md#version-scheme-binding` and performing zero writes, if any of the following conditions occur:
  - the `bound-version-scheme` or `version-pattern` marker is missing
  - either value is blank
  - either value is still an unfilled `<...>` placeholder
  - `bound-version-scheme` references a scheme `<name>` that has no corresponding policy file at `docs/policies/version-scheme/<name>.md`
  - the marker values and the Markdown table rows disagree on any field

Once verified, record: `Version scheme: <name> (CADENCE_ORG.md#version-scheme-binding)` and include that exact line in every status or halt output produced during this release run.

### 2. Determine the version bump

Load the bump classification rules and version-increment arithmetic from the resolved scheme policy (`docs/policies/version-scheme/<name>.md`); that policy document is the single source of truth for bump terminology and calculation rules. Evaluate the `## [Unreleased]` entries against those rules to compute the candidate next version.

Present the classification alongside the specific changelog bullets that triggered it. Whenever `$bump_override` was passed and **differs** from the computed classification, display both side by side and warn prominently about the override (particularly if forcing a lower bump tier over a breaking change).

### 3. Validate, propose, and CONFIRM the target version (Gate A: pre-edit / release PR confirmation)

Prior to prompting the operator, verify the candidate version string against two binding invariants:

- **`version-pattern` match:** the candidate version string must match the regex/pattern resolved from `version-pattern`. If it fails to match, HALT naming `CADENCE_ORG.md#version-scheme-binding` and the invalid version string without writing anything.
- **Strict monotonicity:** the candidate version must rank strictly greater than the current baseline version under the resolved scheme's comparator. If it does not, HALT naming `CADENCE_ORG.md#version-scheme-binding` and both version strings without writing anything.

Display the proposal to the operator:

```
Version scheme:  <name> (CADENCE_ORG.md#version-scheme-binding)
Current version: <current-tag>
Proposed bump:   <classification>  ->  <target-tag>
Reasoning:       <the entries that drove the classification>
Unreleased entries to ship:
  Added:   N    Changed: N    Fixed: N    Removed: N   ...
```

Prompt with: **"Cut `<target-tag>` as a `<classification>` release and prepare release PR? (yes / a different version)"** and wait for the operator's reply. If the operator supplies an explicit alternative version string, validate their supplied version against `version-pattern` and strict monotonicity before accepting it. **Never modify any file until Gate A is confirmed.** If the operator declines, halt and confirm that no changes were made.

### 4. Apply the release file edits on `release/RELEASE-<version>`

Create or check out a dedicated release branch/worktree (`release/RELEASE-<version>`) off `origin/<integration-branch>` (never commit directly to a protected `<integration-branch>`), then update the release artifacts:

1. **`CHANGELOG.md`** — place the new version header directly **below** `## [Unreleased]`, leaving `## [Unreleased]` empty at the top:
   ```
   ## [Unreleased]

   ## [<version>] - YYYY-MM-DD

   > See [<tag> release notes](docs/releases/<tag>.md) for narrative context and upgrade notes.

   ### Added
   ...   (the former Unreleased groups, unchanged, now under this version)
   ```
   All `### Added` / `### Changed` / `### Fixed` / ... blocks previously under `[Unreleased]` now sit under `[<version>]`, while `## [Unreleased]` remains empty at the top for future work.

2. **`README.md`** — update the version banner line to reference the new version and link its release notes:
   `**Version <version>** | [Release Notes](docs/releases/<tag>.md) | [Changelog](CHANGELOG.md)`

3. **`docs/releases/<tag>.md`** — author the release notes document following the **Release-notes template** below, synthesizing each "What's new" subsection from the corresponding changelog bullets. Remind the operator that the generated narrative is an initial draft they can refine before PR merge.

4. **`specs/RELEASE-<version>/submission.md`** — record the release summary (`version`, scheme, PR scope, and release verification checklist) so the release PR carries an auditable submission record (`docs/policies/change-tiers.md`).

### 4b. Verify the drafted release note via the authored-doc gate BEFORE committing (blocking)

Because `docs/releases/<tag>.md` is authored fresh during `/cadence-release`, it must pass the repository's authored-documentation classifier (`ci-templates/scripts/authored-doc-gate.sh`, and when applicable `dead-citation-gate.sh`) **between** drafting in Step 4 and committing in Step 5 — never after the commit is recorded.

**First, verify that the gate script exists AND is non-empty:**

```
[ -s ci-templates/scripts/authored-doc-gate.sh ]
```

A simple file-existence check (`[ -f ]`) is **insufficient**: a truncated zero-byte file is a valid shell script that exits `0`, which would falsely certify a check that never executed. If `ci-templates/scripts/authored-doc-gate.sh` is **missing or zero bytes**, **halt immediately**, report the missing/empty gate script, and refuse to cut the release.

**When the script is present and non-empty**, execute it against the newly drafted release note:

```
bash ci-templates/scripts/authored-doc-gate.sh --path docs/releases/<tag>.md
```

When `authored-doc-gate.sh` (or an accompanying `dead-citation-gate.sh` check) produces noisy diagnostic output exceeding 30 lines and local offload (`:11434`) is reachable, route the output through `offload_log_triage` (`inference` on `:11434`, saving the complete raw log in `/tmp/agy-last-triage.log`; otherwise inspect directly).

This script is the **exact same classifier** executed by the `authored-doc` CI gate, `cadence-triage-agent`'s PROD-entry checks, and `/cadence-archive`'s insights checks. Interpret its exit code strictly (`0 clean ; 1 violation ; 2 setup failure`):
- **Exit 0:** proceed to Step 5.
- **Exit 1:** resolve every reported violation via **LEDGER ROW** (sentence-anchored row in `ci-templates/scripts/authored-doc-ledgers.sh`) or **REVISE THE DRAFT** and re-run until exit `0`.
- **Exit 2 (or any other non-zero exit code):** **halt immediately**.

### 5. Commit and land release PR onto `<integration-branch>`

Display `git --no-pager diff --stat` and stage only the release files (`CHANGELOG.md`, `README.md`, `docs/releases/<tag>.md`, `specs/RELEASE-<version>/submission.md`, plus `ci-templates/scripts/authored-doc-ledgers.sh` if updated in Step 4b):

```
RELEASE-<version>: cut <tag> — CHANGELOG, README, release notes, submission
```

Include the repository's standard `Co-Authored-By` trailer. Push `release/RELEASE-<version>`, open the PR targeting `<integration-branch>`, verify checks pass, merge via forge PR (`gh pr merge` / `glab mr merge`) — or local fast-forward only if no protected remote integration branch exists — and run `git pull --ff-only origin <integration-branch>`.

### 6. Gate B: CONFIRM, create annotated git tag, and push (mandatory post-merge gate)

Only **after** the release PR has merged onto `<integration-branch>` and local `<integration-branch>` is fast-forwarded to the merge commit, prompt with the exact confirmation (**Gate B**):

**"Create annotated tag `<tag>` on `<integration-branch>` and push to `<remote>`? (yes/no)"**

When the operator responds `yes`, create the **annotated** git tag and push it:

```bash
git tag -a <tag> -F <message-file>
git push <remote> <tag>
```

Compose the tag annotation as a plain-text summary matching the preceding release tag (`git tag -l --format='%(contents)' <prev-tag>`). On any non-`yes` response, stop cleanly without tagging or pushing and print the manual `git tag -a` / `git push` commands so the operator can tag/push later.

### 7. Report outcome

Output a final summary detailing: the released `<tag>`, scheme (`<name>`), bump/classification justification, release PR URL, `specs/RELEASE-<version>/submission.md` path, `docs/releases/<tag>.md`, annotated tag SHA, and remote push status.

## Out of Scope

- **Deciding *when* to cut a release.** The operator invokes `/cadence-release` deliberately; the skill never auto-triggers based on changelog length.
- **Inventing product motivation not in the changelog.**
- **GitHub/GitLab Release objects or binary uploads.** Publishing forge Release pages or build artifacts is separate from creating/pushing the annotated git tag.
- **External issue-tracker status synchronization.** Updating bound YouTrack or Jira tickets is handled by `/cadence-archive` (`CADENCE_ORG.md#tracker-binding`) and the tracker sync skills, never subagents or `/cadence-release`.
- **Per-ticket `metadata.yaml` release timestamps.** `/cadence-release` never modifies `specs/*/metadata.yaml` or `archive/*/metadata.yaml` (`released_at`/`deployed_at`); recording per-ticket deployment milestones remains a separate action (PI-029).
- **Full spec/test-plan directories for releases.** Under `docs/policies/change-tiers.md`, cutting a release requires no `spec.md`/`test-plan.md`, though it **does** include `specs/RELEASE-<version>/submission.md` in the release PR commit.
- **Destructive history rewrites.** The skill never resets merged commits or force-deletes published tags automatically.

---

## Release-notes template

Format `docs/releases/vX.Y.Z.md` using the following structure (preserving the exact section headings and populating content from the `[Unreleased]` changelog items):

```markdown
# vX.Y.Z — <release title>

**Released:** YYYY-MM-DD
**Tag:** [`vX.Y.Z`](<repo refs URL>/vX.Y.Z)
**Full changelog:** [`CHANGELOG.md` § [X.Y.Z]](../../CHANGELOG.md)

## TL;DR

<2-4 sentences: the theme of the release and why it matters.> N changes, all <additive|with one breaking change>:

1. **<Headline 1>** — <one line.>
2. **<Headline 2>** — <one line.>
...

This is a **<major|minor|patch> version**: <one line on compatibility — what, if anything, adopters must do.>

---

## What's new

### <Change 1 title>

**Spec/Commit:** <archive/TICKET/ or commit SHA> · **Surfaces:** <files>

<A paragraph drawn from the changelog entry — the what and the why.>

### <Change 2 title>
...

---

## Breaking changes

<"None. All changes are additive." — or, for MAJOR, an itemized list of each broken contract and what replaces it.>

---

## Upgrade notes for existing adopters

- <No action required — or the concrete steps.>
- <Per-surface guidance for anyone who consumes the changed surfaces.>
```

## Worked Examples

Consult the repository's bound version-scheme policy (`docs/policies/version-scheme/<name>.md`, identified by Step 1b's `Version scheme:` output line) for classification criteria, version increment rules, and complete worked examples.
