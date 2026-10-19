---
name: cadence-release
description: Cut a new repository release -- verify the bound version scheme in CADENCE_ORG.md, classify the bump (major/minor/patch) from [Unreleased] changelog entries, confirm with the operator, update CHANGELOG and README, draft and gate-check release notes, commit, create an annotated tag, and push.
argument-hint: "[major|minor|patch]  (optional bump override)"
arguments: [bump_override]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Cut a new release from the pending `## [Unreleased]` items in `CHANGELOG.md`. This skill executes **inline within the primary conversation turn** — never inside a delegated subagent — because it requires two interactive human confirmation pauses (first to approve the target version string, and second before pushing to the remote repository).

The release workflow is deterministic and follows the established `RELEASE-` commit convention (`git log --grep '^RELEASE-'`): promote the `[Unreleased]` changelog entries under the new version heading, leave a fresh empty `## [Unreleased]` section above it, update the version badge/line in `README.md`, author the `docs/releases/vX.Y.Z.md` release narrative, validate the drafted release notes against `authored-doc-gate.sh`, create the release commit and annotated git tag, and push both branch and tag after confirmation. The sole analytical decision — **major vs. minor vs. patch** — is derived from the `[Unreleased]` entries per the repository's bound version scheme, explained with explicit reasoning, and **approved by the human operator before any file is modified.**

`$bump_override` is optional. When provided (`major` | `minor` | `patch`), it overrides the calculated bump level — however, the skill still performs and displays its own classification analysis and highlights any discrepancy prominently so an unintended downgrade (such as forcing `patch` when a breaking change is present) is immediately visible.

## Prerequisites

Confirm all preconditions prior to proposing a release version:

- **Git repository with version baseline:** at least one existing `vX.Y.Z` release tag or a version line in `README.md` to establish the current baseline version. If neither exists, ask the operator for the current baseline version.
- **`CHANGELOG.md` present with `## [Unreleased]`:** if missing, halt and inform the operator that `/cadence-release` requires a Keep-a-Changelog-structured `CHANGELOG.md`.
- **Non-empty `[Unreleased]` section:** if `## [Unreleased]` contains zero entries, halt with: `"Nothing to release — [Unreleased] is empty."` Never cut an empty release.
- **Clean git working tree:** inspect `git status --porcelain`. If uncommitted modifications exist, warn the operator and ask whether to continue — a release commit must contain only the three release artifacts. Proceed only after explicit operator confirmation.
- **`docs/releases/` directory:** ensure `docs/releases/` exists (creating the directory if absent, since release notes reside there by convention).

## Steps

### 1. Gather repository state

- **Current baseline version:** find the highest semantic version tag (`git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`) and cross-verify it against the `README.md` version declaration (`grep -nE 'Version [0-9]+\.[0-9]+\.[0-9]+' README.md`). If the git tag and `README.md` disagree, display both values and ask the operator which one is authoritative before proceeding.
- **Release date:** run `date +%F` (ISO-8601 `YYYY-MM-DD`) for the changelog version header and release notes metadata.
- **Unreleased changelog items:** read the `## [Unreleased]` section of `CHANGELOG.md`, capturing every `###` category (`Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`) and its bullet items. These entries drive both the version-bump calculation and the `docs/releases/vX.Y.Z.md` draft.
- **Active branch and remote:** inspect `git rev-parse --abbrev-ref HEAD` and its upstream tracking remote for Step 7's push command.

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

### 3. Validate, propose, and CONFIRM the target version (mandatory human gate)

Prior to prompting the operator, verify the candidate version string against two binding invariants:

- **`version-pattern` match:** the candidate version string must match the regex/pattern resolved from `version-pattern`. If it fails to match, HALT naming `CADENCE_ORG.md#version-scheme-binding` and the invalid version string without writing anything.
- **Strict monotonicity:** the candidate version must rank strictly greater than the current baseline version under `version_cmp` (three dot-separated integer fields). If it does not, HALT naming `CADENCE_ORG.md#version-scheme-binding` and both version strings without writing anything.

Display the proposal to the operator:

```
Version scheme:  <name> (CADENCE_ORG.md#version-scheme-binding)
Current version: vX.Y.Z
Proposed bump:   <MAJOR|MINOR|PATCH>  →  vX'.Y'.Z'
Reasoning:       <the entries that drove the classification>
Unreleased entries to ship:
  Added:   N    Changed: N    Fixed: N    Removed: N   ...
```

Prompt with the exact question: **"Cut vX'.Y'.Z' as a <bump> release? (yes / a different version)"** and wait for the operator's reply. If the operator supplies an explicit alternative version string (for example, judging an item breaking that heuristic classification treated as additive), validate their supplied version against `version-pattern` and strict monotonicity before accepting it. **Never modify any file until the operator explicitly confirms the target version.** If the operator declines, halt and confirm that no changes were made.

### 4. Apply the release file edits

Once the target version is confirmed, update the three release files (without committing yet):

1. **`CHANGELOG.md`** — place the new version header directly **below** `## [Unreleased]`, leaving `## [Unreleased]` empty at the top:
   ```
   ## [Unreleased]

   ## [X.Y.Z] - YYYY-MM-DD

   > See [vX.Y.Z release notes](docs/releases/vX.Y.Z.md) for narrative context and upgrade notes.

   ### Added
   ...   (the former Unreleased groups, unchanged, now under this version)
   ```
   All `### Added` / `### Changed` / `### Fixed` / … blocks previously under `[Unreleased]` now sit under `[X.Y.Z]`, while `## [Unreleased]` remains as an empty section heading for future work.

2. **`README.md`** — update the version banner line to reference the new version and link its release notes:
   `**Version X.Y.Z** | [Release Notes](docs/releases/vX.Y.Z.md) | [Changelog](CHANGELOG.md)`

3. **`docs/releases/vX.Y.Z.md`** — author the release notes document following the **Release-notes template** section below, synthesizing each "What's new" subsection from the corresponding changelog bullets. Populate **Breaking changes** from any MAJOR entries (or write `"None. All changes are additive."` for minor/patch cuts). Remind the operator that the generated narrative is an initial draft they can refine with deeper architectural context or upgrade nuances before committing.

### 4b. Verify the drafted release note via the authored-doc gate BEFORE committing (blocking)

Because `docs/releases/vX.Y.Z.md` is authored fresh during `/cadence-release`, it must pass the repository's authored-documentation classifier (`ci-templates/scripts/authored-doc-gate.sh`, and when applicable `dead-citation-gate.sh`) **between** drafting in Step 4 and committing in Step 5 — never after the commit is recorded. This prevents stale MCP server keys, unanchored metric restatements, or dead citations from landing in an immutable release note and breaking downstream CI checks.

**First, verify that the gate script exists AND is non-empty:**

```
[ -s ci-templates/scripts/authored-doc-gate.sh ]
```

A simple file-existence check (`[ -f ]`) is **insufficient**: a truncated zero-byte file is a valid shell script that exits `0`, which would falsely certify a check that never executed. If `ci-templates/scripts/authored-doc-gate.sh` is **missing or zero bytes**, **halt immediately**, report the missing/empty gate script, and refuse to cut the release. Never skip the gate silently or infer success from an empty script.

**When the script is present and non-empty**, execute it against the newly drafted release note:

```
bash ci-templates/scripts/authored-doc-gate.sh --path docs/releases/vX.Y.Z.md
```

If `authored-doc-gate.sh` (or an accompanying `dead-citation-gate.sh` check) produces noisy diagnostic output exceeding 30 lines, **automatically route the output through `offload_log_triage` (`local-fast-cpu` on `:9379`)** to extract verbatim violation lines and `file:line` coordinates while preserving the complete raw log in `/tmp/agy-last-triage.log`.

This script is the **exact same classifier** executed by the `authored-doc` CI gate, `cadence-triage-agent`'s PROD-entry checks, and `/cadence-archive`'s insights checks — one canonical gate script that **detects, classifies, and blocks without ever auto-rewriting files.**

Interpret its exit code strictly according to its contract (`0 clean ; 1 violation ; 2 setup failure`):
- **Exit 0:** proceed to Step 5.
- **Exit 1:** resolve every reported violation using one of the two dispositions below before continuing.
- **Exit 2 (or any other non-zero exit code):** **halt immediately** — the gate encountered a setup fault and certified nothing.

For **every** violation reported on exit `1`, apply one of two valid dispositions (**never** edit an already-committed historical release note, since shipped release notes are immutable historical records):

- **LEDGER ROW** (default for intentional historical references) — register an anchored exemption in `ci-templates/scripts/authored-doc-ledgers.sh` keyed to the specific **sentence**, never to a whole file or directory path (path-wide exemptions mask future violations across an entire file and are rejected by the gate itself).
- **REVISE THE DRAFT** — valid because `docs/releases/vX.Y.Z.md` is still an uncommitted draft at Step 4b *and* the flagged phrasing was an unintended inaccuracy rather than an intentional historical reference. Re-run `authored-doc-gate.sh` after editing until it exits `0`.

Never advance to Step 5 while any gate violation remains unresolved.

### 5. Show the diff and CONFIRM the commit (mandatory human gate)

Execute `git --no-pager diff --stat` to display the three modified/created release files. Ask the operator: **"Commit these as `RELEASE-X.Y.Z`?"** Upon confirmation, stage only those files (`CHANGELOG.md`, `README.md`, `docs/releases/vX.Y.Z.md`, plus `ci-templates/scripts/authored-doc-ledgers.sh` if updated in Step 4b) and create the commit:

```
RELEASE-X.Y.Z: cut vX.Y.Z — CHANGELOG, README, release notes
```

Include the repository's standard `Co-Authored-By` trailer at the end of the commit message. Never stage unrelated working-tree files.

### 6. Create the annotated git tag

Create an **annotated** git tag (never a lightweight tag — every CADENCE release tag carries a structured message):

```bash
git tag -a vX.Y.Z -F <message-file>
```

Compose the tag annotation as a plain-text summary matching the release notes: a header line `vX.Y.Z — <release title>`, a brief summary paragraph, the numbered list of headline items, and a footer line (`<Bump> version — ...; full notes: docs/releases/vX.Y.Z.md`). Match the structure of the preceding release tag (`git tag -l --format='%(contents)' <prev-tag>`).

### 7. CONFIRM the push, then push branch + tag (mandatory outward-facing human gate)

Because pushing a release commit and tag to a shared remote is externally visible and permanent, prompt with the exact question: **"Push <branch> and tag vX.Y.Z to <remote>? (yes/no)"** When the operator responds `yes`, execute:

```bash
git push <remote> <branch>
git push <remote> vX.Y.Z
```

On any other response, halt and report that the release commit and annotated tag `vX.Y.Z` are recorded **locally** without being pushed, and print the two `git push` commands so the operator can push manually when ready.

### 8. Report outcome

Output a final summary detailing: the released version string, the bump tier and its justification, the modified file paths, the annotated tag SHA, and the remote push status (pushed vs. local-only with push commands). Include the path to `docs/releases/vX.Y.Z.md` and note if any narrative sections merit further human polish.

## Out of Scope

- **Deciding *when* to cut a release.** The operator invokes `/cadence-release` deliberately; the skill never auto-triggers based on changelog length.
- **Inventing product motivation not in the changelog.** While the skill drafts `docs/releases/vX.Y.Z.md` from `CHANGELOG.md`, nuanced architectural commentary and upgrade advice benefit from human review.
- **GitHub/GitLab Release objects or binary uploads.** This skill creates and pushes the annotated git tag; publishing forge-specific Release pages or build artifacts is separate.
- **External issue-tracker status synchronization.** Updating bound YouTrack or Jira tickets is handled by `cadence-archivist` and the tracker sync skills, not `/cadence-release`.
- **Per-ticket `metadata.yaml` release timestamps.** `/cadence-release` never modifies `specs/*/metadata.yaml` or `archive/*/metadata.yaml` (such as `released_at` or `deployed_at` fields in `specs/TEMPLATE/metadata.yaml`); recording per-ticket deployment milestones remains a separate action (PI-029).
- **`specs/RELEASE-X.Y.Z/` directories.** Under `docs/policies/change-tiers.md`, cutting a release is a Trivial-tier operation governed by the CHANGELOG/README/release-notes/tag workflow rather than a full spec folder.
- **Destructive history rewrites.** If an operator wishes to alter a version after Step 5/6 has committed and tagged locally, the skill does not automatically delete tags or `git reset` — it explains the state and lets the operator decide before Step 7 pushes.

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
