---
name: claire-release
description: Cut a new release -- resolve the repository's bound version scheme, determine the bump (major/minor/patch) from the [Unreleased] changelog, confirm it with the user, then finalize CHANGELOG, bump README, write release notes, commit, annotate a tag, and push.
argument-hint: "[major|minor|patch]  (optional bump override)"
arguments: [bump_override]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Cut a new release from the accumulated `## [Unreleased]` entries in `CHANGELOG.md`. This skill runs **inline in the main turn** — not in a subagent — because it must pause twice for human confirmation (once on the proposed version, once before pushing). A subagent cannot pause for input.

The release procedure is deterministic and mirrors the prior cut (`git log --grep '^RELEASE-'`): finalize the changelog section, open a fresh `[Unreleased]`, bump the README version line, write a `docs/releases/vX.Y.Z.md` narrative, commit, annotate a tag, and push the branch and tag. The one judgment call — **major vs. minor vs. patch** — is computed from the entry content, proposed with reasoning, and **confirmed by the user before anything is written.**

`$bump_override` is optional. When supplied (`major` | `minor` | `patch`), it overrides the computed bump — but the skill still shows its own analysis and warns if the override disagrees, so an accidental downgrade (e.g. forcing `patch` over a breaking change) is caught.

## Prerequisites

Verify before proposing anything:

- **A git repository** with at least one prior release tag, or a README version line to seed the current version. If neither exists, ask the user for the current version.
- **`CHANGELOG.md` exists** and has a `## [Unreleased]` section. If absent, stop and tell the user this skill expects a Keep-a-Changelog-formatted `CHANGELOG.md`.
- **`[Unreleased]` is non-empty.** If it has no entries, stop: "Nothing to release — `[Unreleased]` is empty." Do not cut an empty release.
- **Clean working tree.** Run `git status --porcelain`. If there are uncommitted changes, warn the user and ask whether to proceed — the release commit should be isolated to the generated files. Proceed only on confirmation.
- **`docs/releases/` exists** (create it if missing — releases live there by convention).

## Steps

### 1. Gather state

- **Current version:** the highest version tag (`git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`), cross-checked against the README version line (`grep -nE 'Version [0-9]+\.[0-9]+\.[0-9]+' README.md`). If the tag and README disagree, surface both and ask the user which is authoritative before continuing.
- **Today's date:** `date +%F` (ISO `YYYY-MM-DD`). Use it for the changelog heading and release notes.
- **Unreleased entries:** read the `## [Unreleased]` block of `CHANGELOG.md` — capture each `###` group (`Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`) and its bullets. This content is the raw material for both the bump decision and the release-notes draft.
- **Current branch + upstream:** `git rev-parse --abbrev-ref HEAD` and its tracking remote, for the push step.

### 1b. Resolve the version scheme (mandatory, before anything is computed)

Read `docs/agentic-sdlc/CLAIRE_ORG.md`'s Version-Scheme Binding (`#version-scheme-binding`)
and resolve `bound-version-scheme`, `version-pattern` and `cycle-qualifying-cut` from its
markers and field table, which must agree.

HALT, naming `CLAIRE_ORG.md#version-scheme-binding` and writing nothing, on any of:
  - the `bound-version-scheme` or `version-pattern` marker is absent
  - the value is empty
  - the value is an un-substituted placeholder
  - `bound-version-scheme` names a scheme with no `docs/policies/version-scheme/<name>.md`
  - the marker block and the field table disagree on any field

On resolution, state: `Version scheme: <name> (CLAIRE_ORG.md#version-scheme-binding)` and
carry that line into every subsequent message this run produces, including any later halt.

### 2. Determine the bump

Read the classification rules and the next-version rule from the resolved scheme document
(`docs/policies/version-scheme/<name>.md`); it supplies the bump vocabulary and the
arithmetic, and this skill declares no second copy of either. Classify the `[Unreleased]`
content against those rules and compute the proposed next version accordingly.

State the classification with the specific entries that drove it. If `$bump_override` was supplied and **disagrees** with the computed bump, show both and flag the disagreement prominently (especially a forced *down*grade past a breaking change — that is the dangerous case).

### 3. Validate, propose and CONFIRM the version (mandatory gate)

Before presenting anything, validate the proposed version against the binding:

- **`version-pattern`**: the proposed version must match the resolved `version-pattern`. If it does not, HALT naming `CLAIRE_ORG.md#version-scheme-binding` and the offending string; write nothing.
- **Monotonicity**: the proposed version must rank strictly above the current version under `version_cmp`'s ordering (three dot-separated numeric fields). If it does not, HALT naming `CLAIRE_ORG.md#version-scheme-binding` and both versions; write nothing.

Present to the user:

```
Version scheme:  <name> (CLAIRE_ORG.md#version-scheme-binding)
Current version: vX.Y.Z
Proposed bump:   <MAJOR|MINOR|PATCH>  →  vX'.Y'.Z'
Reasoning:       <the entries that drove the classification>
Unreleased entries to ship:
  Added:   N    Changed: N    Fixed: N    Removed: N   ...
```

Ask exactly: **"Cut vX'.Y'.Z' as a <bump> release? (yes / a different version)"** Wait for the answer. Accept an explicit alternative version if the user supplies one (e.g. they judge a change breaking that the rules missed), validating it against `version-pattern` and monotonicity the same way. **Write nothing until the user confirms a version.** If they decline, stop and report no changes made.

### 4. Apply the file edits

With the version confirmed, edit (do not commit yet):

1. **`CHANGELOG.md`** — insert the new version heading immediately **after** `## [Unreleased]`, leaving `[Unreleased]` empty above it:
   ```
   ## [Unreleased]

   ## [X.Y.Z] - YYYY-MM-DD

   > See [vX.Y.Z release notes](docs/releases/vX.Y.Z.md) for narrative context and upgrade notes.

   ### Added
   ...   (the former Unreleased groups, unchanged, now under this version)
   ```
   The `### Added`/`### Changed`/… groups that were under `[Unreleased]` now belong to `[X.Y.Z]`; `[Unreleased]` is left with just its heading.

2. **`README.md`** — bump the version line to the new version and point it at the new notes:
   `**Version X.Y.Z** | [Release Notes](docs/releases/vX.Y.Z.md) | [Changelog](CHANGELOG.md)`

3. **`docs/releases/vX.Y.Z.md`** — write the narrative from the template in the **Release-notes template** section below, drafting each "What's new" entry from the corresponding changelog bullet. Populate **Breaking changes** from any MAJOR signals (or "None. All changes are additive." for minor/patch). Tell the user this is a draft they should read and enrich — the changelog is terse; the notes are where the *why* and upgrade guidance live.

### 4b. Check the drafted release note BEFORE it is committed (blocking)

The release note is the single document `/claire-release` authors from scratch, and it is where the
2026-09-01 baseline sweep found two of its three write-time-preventable defects — an MCP server key the
manifest no longer carries, and a restatement of the file-length measure outside the enumerated set.
Both landed clean and surfaced later as an unrelated harness's red. This step is what stops that
happening again, and it runs **between** the draft in step 4 and the commit in step 5, never after.

**First, test whether the gate is installed AND non-empty:**

```
[ -s ci-templates/scripts/authored-doc-gate.sh ]
```

An existence-only test (`[ -f ]`) is **not sufficient**: a zero-byte file is a valid shell script that
exits 0, so this step would run a truncated gate, read exit 0, and record a clean check that never
happened. A gate that is **absent, or present but zero bytes**, is one and the same condition —
**halt**, name the condition, and do not cut the release. Never a silent skip, and never a clean
result inferred from a gate that could not run.

**If it is installed and non-empty**, check the drafted note:

```
bash ci-templates/scripts/authored-doc-gate.sh --path docs/releases/vX.Y.Z.md
```

This is the **same script** the `authored-doc` CI gate row runs and the **same script** the
triage-agent's PROD-entry append and `/claire-archive`'s insights writes run — one classifier, several
callers, never a second implementation. It **detects, classifies and blocks; it never rewrites.**

Read its exit status as **three different outcomes**, per its own documented contract
(`0 clean ; 1 violation ; 2 setup failure`): **0** proceed to step 5; **1** disposition each hit below;
**2** halt — the gate could not run, so it certifies nothing. Any other non-zero status is handled as a
setup failure rather than interpreted.

For **each** hit choose exactly one disposition, and **never an edit to a release note that has already
been committed** — a release note is an immutable record of what shipped:

- **LEDGER ROW** (the default) — add an anchored row to that guard's ledger in
  `ci-templates/scripts/authored-doc-ledgers.sh`, anchored on the offending **sentence**, never on the
  file. A path-wide anchor excuses every future line of a growing directory, which is why the MCP
  ledger carries *three* rows for one release note rather than one; the gate reports such a row as a
  violation in its own right.
- **REVISE THE DRAFT** — only while the note is still a draft (it is, at this step) *and* the statement
  is genuinely wrong rather than a record of what shipped.

Do not proceed to step 5 with an undispositioned hit.

### 5. Show the diff and CONFIRM the commit (mandatory gate)

Run `git --no-pager diff --stat` and show the three changed/created files. Ask: **"Commit these as `RELEASE-X.Y.Z`?"** On confirmation, stage exactly those files and commit:

```
RELEASE-X.Y.Z: cut vX.Y.Z — CHANGELOG, README, release notes
```

End the commit body with the `Co-Authored-By` trailer per the repo's commit convention. Do not stage unrelated working-tree changes.

### 6. Create the annotated tag

Create an **annotated** tag (never lightweight — releases must carry a message):

```bash
git tag -a vX.Y.Z -F <message-file>
```

The tag message is a plain-text echo of the release notes: a title line `vX.Y.Z — <release title>`, a short paragraph, the numbered list of headline changes, and a closing line (`<Bump> version — ...; full notes: docs/releases/vX.Y.Z.md`). Match the form of the previous release's tag (`git tag -l --format='%(contents)' <prev-tag>`).

### 7. CONFIRM the push, then push branch + tag (mandatory gate — outward-facing)

Pushing is outward-facing and hard to reverse. Ask exactly: **"Push <branch> and tag vX.Y.Z to <remote>? (yes/no)"** On `yes`:

```bash
git push <remote> <branch>
git push <remote> vX.Y.Z
```

On anything else, stop and report the release is committed and tagged **locally** but not pushed, with the two push commands the user can run themselves.

### 8. Report outcome

Report: the version cut, the bump and its reasoning, the files changed, the tag SHA, and the push status (pushed / local-only with the commands). Note the release-notes path and remind the user the narrative is a draft worth a read.

## Out of Scope

- **Deciding *whether* to release.** The user invokes this skill when ready; it does not poll for "enough changes."
- **Writing the full release narrative.** The skill drafts `vX.Y.Z.md` from the changelog, but the prose, motivation, and upgrade nuance need human judgment — the draft is a starting point.
- **Forge Releases / artifacts.** It creates the git tag only. Publishing a GitHub/GitLab/sr.ht Release object, attaching binaries, or announcing is separate.
- **External tracker sync.** Bound-tracker updates are the archivist's job, not this skill's.
- **Ticket `metadata.yaml` lifecycle fields.** `/claire-release` writes no ticket metadata; in particular it does not set `released_at`/`deployed_at` (the release/deploy milestone fields in `specs/TEMPLATE/metadata.yaml`). Recording the release/deploy milestone per ticket — and deciding which tickets belong to the release — is a manual adopter action at v1 (record-only, PI-029). No release-membership enumeration is performed.
- **`specs/RELEASE-X.Y.Z/` artifacts.** Per `docs/policies/change-tiers.md` a release cut is Trivial tier; if your org requires a `specs/RELEASE-X.Y.Z/submission.md` record, create it separately — this skill follows the lightweight CHANGELOG/README/notes/tag practice.
- **Rewriting history.** If the proposed version is wrong *after* the commit/tag, the skill does not amend or delete tags automatically — it tells the user, who decides (the tag is local until step 7).

---

## Release-notes template

Write `docs/releases/vX.Y.Z.md` in this shape (the headers are load-bearing; fill the prose from the changelog entries):

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

See the resolved scheme document (`docs/policies/version-scheme/<name>.md`, named by
step 1b's `Version scheme:` line) for the classification rules, the next-version rule,
and worked examples under that scheme.
