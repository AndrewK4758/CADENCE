---
name: claire-upgrade
description: Merge a newer CLAIRE core into an adopter's customized tree using the PI-021 version stamp as the 3-way-merge base. Wraps the canonical merge engine; clean changes auto-apply, conflicts are surfaced for human resolution (never a silent merge), the apply is atomic, and the stamp advances only on a fully-clean apply.
argument-hint: "<new-version>"
arguments: [new_version]
allowed-tools: Read Bash Skill
---

## Task

Upgrade the adopter repo at the current working directory to CLAIRE core `$new_version` by delegating to the canonical merge engine at `.claude/skills/claire-upgrade/upgrade-claire.sh`.

The skill does not implement the merge logic itself — the bash script is the single source of truth for the 3-way merge, the atomic apply, the stamp advance, and the conflict surfacing. The skill validates inputs, invokes the script, streams its output verbatim, and independently verifies the post-conditions landed in the adopter's real repo (never trusting the exit code alone).

## Prerequisites

Before invoking the script, verify:

1. `$new_version` is provided, non-empty, and looks like a dotted semantic version (e.g. `3.7.0`) -- **unless** the invocation is a version-independent mode flag instead (`--seed-ledger`, `--rewrite-vocab`; see Steps 4.5 and 4.6), each of which dispatches before the version-stamp logic and never reads `$new_version`. If neither a version nor one of those flags is provided, stop with: "Usage: `/claire-upgrade <new-version>`. The new-version is the CLAIRE core version to upgrade to."
2. The current working directory is the adopter repo to upgrade (the merge operates on the adopter's compiled tree + installed surface in place). The script reads the version stamp and the footprint descriptor from there.

## Pre-PI-021 adopters (no installed command tree yet)

The `.claude/skills/claire-upgrade/upgrade-claire.sh` path above exists only **after** adoption. A pre-PI-021, compiled-only adopter has no installed `.claude/skills/claire-upgrade/` tree yet, so there is nothing to invoke in their repo. In that case, run the engine directly from a **local core checkout** of CLAIRE (a `git clone` of the framework repo at the target version), pointing it at the adopter repo via the `UPGRADE_TARGET` seam:

```bash
UPGRADE_TARGET=<adopter-repo> bash <core>/artifacts/commands/claire-upgrade/upgrade-claire.sh <ver>
```

- **When this is needed:** the adopter has no installed `.claude/skills` tree yet (pre-adoption / pre-PI-021). Once the upgrade lands the command tree, use the normal `.claude/skills/claire-upgrade/upgrade-claire.sh` invocation instead.
- **Where to find the core checkout:** clone the CLAIRE framework repo locally (or reuse an existing checkout **that carries the target version's release tag** — see the note below). `<core>` is that checkout's root; the engine and the eject deriver both resolve their inputs from it (override with `UPGRADE_CORE` if it is not this script's own repo).
- **Tags matter (BTG-311).** Version resolution is bounded to the target version's annotated release tag (`v<ver>` or `<ver>`) when that tag exists in `<core>` — the resolver never scans an unmerged branch or a post-release commit into the base. A long-lived checkout with active branches works fine as long as it has **fetched tags** (`git fetch --tags`); a checkout cloned with `--no-tags`, or a stale mirror predating the target's release, degrades to the pre-BTG-311 all-refs scan and **announces** that the resolution is unadjudicated (a `DRIFT_SIGNAL upgrade.base.resolved_without_tag` seam plus a stderr notice) rather than silently trusting it. If you see that notice, `git fetch --tags` in `<core>` and re-run to get the tag-bounded (adjudicated) resolution.
- **How to proceed:** the engine first runs the Step 0 footprint pre-check (below). If the footprint is absent it halts and points you at the auto-generate; once it exists, the same invocation performs the merge. Add `--dry-run` to preview first.

## Steps

### 0. Footprint pre-check + auto-generate (pre-PI-021 adopters)

The merge boundary is the `artifacts/footprint.generated` descriptor (consumed, never re-derived). A pre-PI-021, compiled-only adopter does not have one. The engine pre-checks for it at the head of its bootstrap path: if the footprint is **absent**, the run halts immediately (before any confirm-base interaction and before any stamp write) with a `LINEAGE_GAP upgrade.boundary.descriptor_missing` seam and an error naming the missing file and pointing here.

When the footprint is absent, offer to **auto-generate** it from the core checkout — and proceed only with **explicit operator confirmation** (never a silent overwrite of a footprint the operator may have started by hand). Run the engine's dedicated Step-0 mode, `--autogen-footprint`, gated by `AUTOGEN_CONFIRM=1` (the confirmation gate — without it the engine writes nothing and restates that the footprint is still required). That mode routes through the engine's tested helper, which delegates to the single eject deriver (it reads only the core checkout and prints the descriptor to stdout), captures it to a temp file, checks the deriver's exit status, and **atomically moves** it into place only on success (derive-to-temp-then-move — a failed or interrupted derive never truncates or leaves a partial/empty footprint). Do **not** pipe the deriver straight into the destination with a bare `>` redirect — that truncates the destination before the deriver runs. On confirmation:

```bash
AUTOGEN_CONFIRM=1 UPGRADE_TARGET=<adopter-repo> UPGRADE_CORE=<core> \
  bash <core>/artifacts/commands/claire-upgrade/upgrade-claire.sh --autogen-footprint
```

This is idempotent: re-deriving against an unchanged core yields a byte-equivalent descriptor. On a derive failure (e.g. the core checkout is unreachable or the deriver is missing) the engine emits `LINEAGE_GAP upgrade.footprint.derive_failed`, leaves the destination untouched, and surfaces an actionable error — stop and fix the core checkout. Once the footprint exists, proceed to Step 1.

### 1. Invoke the engine

Run the canonical merge engine with the target version:

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh "<new_version>"
```

Stream stdout and stderr to the adopter verbatim. Do not transform, summarize, or paraphrase the per-file change report or the conflict report — they are the audit trail and the human's resolution guide.

**Vocabulary migration report (BTG-332, D1-D4).** Inside the same atomic apply, the engine also classifies and rewrites the adopter's own active `specs/<id>/**/*.md` and `*.yaml` (excluding `specs/TEMPLATE/`, `specs/drafts/`, `specs/CLAIRE.md`, and any ticket directory named in `UPGRADE_VOCAB_EXCLUDE` -- see Step 4.6 below) into SCOUT vocabulary (see `docs/agentic-sdlc/scout-reference.md`'s map for what this retires). A clean run prints one `upgrade-claire: vocab rewrite: <path> (<N> line(s))` line per rewritten spec file, plus a trailing `upgrade-claire: vocab retained (historical): <N> line(s) across <N> file(s).` summary when any frozen (historical) content was left untouched. Stream these verbatim exactly like the framework-file report — they are the same audit trail. A line that mixes the acronym with a dimension word outside a known template shape is a **vocab conflict**: it folds into the SAME conflict machinery Step 3 already describes (staged under `.claire-upgrade-staging/` with conflict markers, reported on stderr as `vocab-conflict: <path>:<line>`), and blocks the whole apply exactly like a framework-file conflict — never resolve it automatically.

**Preview first with `--dry-run` (optional, recommended).** Before committing to the run, pass `--dry-run` to compute the full 3-way merge in memory and report the outcome — total files in scope, how many would apply cleanly, how many would conflict, and the conflicting paths — **writing nothing**: no `.claire-version` advance, no `.claire-upgrade-staging/`, no footprint write, no work-tree apply. The exit code is CI-keyable: **0** on a would-be-clean apply, **non-zero** on would-be-conflicts (so a pre-merge gate can key off it).

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh "<new_version>" --dry-run
```

### 2. Handle the no-stamp bootstrap (pre-PI-021 adopter)

If the engine reports there is no `.claire-version` stamp and presents an inferred base version, **present that inferred base to the human and ask for confirmation before any apply** — never proceed on an unconfirmed base. On confirmation, re-invoke with the confirmed base:

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh "<new_version>" --confirm-base "<confirmed-base>"
```

If no base can be inferred and the human accepts a base-less merge, re-invoke with `--two-way` (every difference is surfaced as a conflict for resolution; nothing is silently overwritten).

### 3. Handle conflicts (never silent)

If the engine reports conflicts, it has staged the conflicted forms (with conflict markers) under `.claire-upgrade-staging/` and left the working tree and the stamp unchanged. Do NOT auto-resolve. Report the conflicting files to the human and stop — the human resolves the conflicts and re-runs.

**Base-commit authority when hand-resolving (N-1 / DEC-002, narrowed by BTG-311).** The engine's base commit is still the **README-of-record** commit — the commit whose `README.md` records `**Version X.Y.Z**`, resolved by `core_commit_for_version` — and it is still the commit to diff against when hand-resolving. What changed under BTG-311: when the target version's release tag `vX.Y.Z` (or the bare `X.Y.Z` spelling) exists in the core checkout, the README-of-record is now resolved **within that tag's own history**, so it **coincides with the tag's own commit** (this is the ordinary case — verified true for every release this repository has ever cut). When hand-resolving a conflict on a tag-resolved run, `git show vX.Y.Z` and the engine's commit are the same commit. The two can still diverge in exactly one population: a core checkout with **no tag** for the target version (pre-tag-adoption history, or a checkout whose tags were never fetched) — the engine falls back to the pre-BTG-311 all-refs scan there and **announces** it (`DRIFT_SIGNAL upgrade.base.resolved_without_tag`, printed to stderr on that run). If you see that notice, diff against the **engine's** commit, **not** `git show vX.Y.Z` — diffing against the tag bases the resolution on a different "ours" than the engine used, and the conflict re-appears on re-run. See `archive/BTG-311/decisions.md` DEC-002 for the full reconciliation with the original N-1 ruling.

**Resolution halts (BTG-311).** Two conditions make the engine refuse to resolve a base at all, before any merge input is computed — both name every candidate they found and leave the stamp untouched: (1) the target version's tag exists but **no commit in its history** declares that version (`SEAM_VIOLATION upgrade.base.resolved_outside_release` — often a shallow clone; `git fetch --unshallow` and re-run); (2) **both** tag spellings (`vX.Y.Z` and `X.Y.Z`) exist and point at **different** commits (`IMPOSSIBLE_STATE upgrade.base.tag_spelling_ambiguous` — remove or correct the duplicate tag in the core checkout). Neither is a merge conflict; both stop the run before the merge starts. See `docs/guides/upgrade-repair-runbook.md` for recovery steps.

**A base stamp written before this fix (BTG-311 AC-9).** If your `.claire-version` was stamped by a pre-BTG-311 engine, its recorded `commit=` may sit ahead of the newly tag-bounded target on your next upgrade. The engine announces this (`DRIFT_SIGNAL upgrade.base.stamp_ahead_of_target`) and **proceeds** — it never refuses — but a conflict you see on that run may be an artifact of the old stamp rather than a genuine customization conflict. A second, narrower cause of the same signal is a stamp written by `/claire-adopt` **before** BTG-314, which stamped the core checkout's HEAD rather than the release commit; the fix and the remedy are the same either way. See `docs/migrations/version-resolution-tag-bounded.md`.

**PI-033 / G-8 — the one-time `surface-registry.md` split conflict.** If `docs/policies/surface-registry.md` is among the conflicted files, this is the expected, one-time **split-transition conflict** for a repo that adopted before the framework-surface split: core removed the framework rows from `surface-registry.md` (they moved to the new core-owned `docs/policies/claire-surfaces.md`) while the adopter had edits on those same lines. Point the operator at `docs/migrations/claire-surfaces-split.md` — the correct resolution is **take the adopter side (their own rows) for `surface-registry.md`** and **accept core's new `claire-surfaces.md`**. This is the **last** `surface-registry.md` conflict from a framework-surface addition.

### 4. Verify the apply landed in the adopter's real repo

The engine reports success based on its own target. After it exits 0 on a clean apply, **independently** re-verify the adopter's canonical repo: the `.claire-version` stamp now records `<new_version>`, and the in-scope files were updated. If the stamp did not advance, do NOT report success — the apply likely ran against a different directory (for example, an isolation worktree). Stop and ask the operator to re-run from the adopter repo.

### 4.5. Seed the id-allocation ledger (create-if-missing, PI-039)

A pre-allocator adopter (upgrading from a CLAIRE core older than PI-039) has months of `specs/`+`archive/`+`docs/ADR/` (and `intent-insights.md`/`production-insights.md`) history but no reserve ledger yet. Run the engine's dedicated scan-and-seed mode to bootstrap the ledger to the adopter's true high-water marks, so the first `--reserve` never collides with or reuses an already-minted id:

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh --seed-ledger
```

- **Create-if-missing, idempotent.** Each prefix is `--seed`ed only if the ledger has no rows for it yet; an already-seeded prefix (a second run, or a hand-bootstrapped ledger) is skipped and the ledger is left byte-untouched. It is safe to run every upgrade.
- **§10-gated ticket prefix.** `ADR`, `II`, and `PROD` are always seeded (§10-independent). The ticket prefix is seeded only when `CLAIRE_ORG.md` §10 is unbound (`None — closed default`); a bound-tracker adopter's ticket ids originate externally, so the ticket prefix is never scanned or seeded locally.
- **Outside the merge transaction.** This mode dispatches before the version-stamp logic and **never reads, writes, or advances** `.claire-version`. It needs no version argument and can run before or after the merge.
- **`--dry-run` writes nothing.** `.claude/skills/claire-upgrade/upgrade-claire.sh --seed-ledger --dry-run` reports what it *would* seed per prefix and creates no ledger.

### 4.6. Rewrite adopter-spec vocabulary independently of the stamp (`--rewrite-vocab`, BTG-332 D5)

The vocabulary migration Step 1 already describes runs automatically inside a normal versioned upgrade, but a ticket branch merged **after** that upgrade already ran carries specs written under the OLD engine and never gets reclassified by a later versioned run over the same stamp. Run the engine's dedicated, stamp-independent mode to sweep and rewrite those specs on their own:

```bash
UPGRADE_CORE=<core> .claude/skills/claire-upgrade/upgrade-claire.sh --rewrite-vocab
```

- **`UPGRADE_CORE` must point at a separate, up-to-date core checkout that ships `docs/agentic-sdlc/scout-reference.md`** (code-review cycle 3 B1). With it unset, `$CORE` falls back to the adopter's own tree (the installed copy's own containing directory) -- this mode fails loud on that, naming `UPGRADE_CORE`, rather than silently classifying specs while doing nothing with either reference file.
- **Never combined with a version argument.** `<new-version> --rewrite-vocab` (in either order) fails loud, naming `--rewrite-vocab` and the rejected version, instead of silently ignoring the version (DEC-053 pre-merge fix-up, held candidate c1-4): this mode is stamp-independent and takes no version.
- **Never deletes a pre-existing `.claire-upgrade-staging/`.** If that directory already exists when this mode starts -- most commonly an org-fold `CLAIRE_ORG.md` conflict Step 1a staged and left unresolved (`docs/migrations/prism-to-scout.md` Step 1b) -- this mode refuses to start, names `.claire-upgrade-staging` and tells the adopter to resolve or remove it first, and writes nothing (DEC-053 pre-merge fix-up, held candidate c1-4). It never overwrites or clears that directory to make room for its own conflict staging.
- **All-or-nothing for spec vocabulary only.** Any conflicting line (an acronym-plus-dimension-word mix outside a known shape) stages every conflicting item under `.claire-upgrade-staging/` with conflict markers and writes nothing else; resolve by hand and re-run, exactly like Step 3. The reference-document swap below NEVER contributes to this: neither reference file's own state blocks anything else in the run (DEC-036).
- **Also delivers/retires the reference document (DEC-033).** The SAME run delivers `docs/agentic-sdlc/scout-reference.md` (if the adopter does not already have ANY copy of it -- an existing copy, whatever its bytes, counts as already available and is left untouched, never a conflict, code-review B2) and retires `docs/agentic-sdlc/prism-reference.md` when EITHER of two conditions holds: its bytes, ignoring line-ending style, are on a committed list of every version CLAIRE itself ever released (DEC-036; no `$CORE` git history is ever read, so a tarball, shallow clone, or CRLF checkout all resolve identically), OR the file is exactly zero bytes (DEC-041, maintainer ruling: the pinned pre-BTG-332 engine's own generic merge truncates this file to empty on a real adopter's very first hop, since that old engine has no `REMOVAL_MANIFEST` row for the path yet -- the row is itself new BTG-332 code -- and this recognizes that as the known artifact rather than a customization). The classification (pristine/truncated/customized) is judged from a snapshot taken at classify time, immediately before it is removed (BTG-333 AC-2, the same re-check pattern the spec-vocabulary path below applies): a write landing on `prism-reference.md` after classification but before removal is caught as `upgrade.vocab.stale_input` and the file is kept, never deleted on the strength of a stale observation. Each written action is reported by name (`vocab reference delivered: ...` / `vocab reference retired: ...`; a truncation retirement names the reason in the same line) -- including when a LATER step in this same run fails: a prism removal failure or a staging fault never hides an earlier scout delivery that already landed. A customized `prism-reference.md` (neither a shipped hash nor empty) is left in place with a loud `NOTICE:` line and is never deleted and never blocks anything else this run; the same is true when `scout-reference.md` is unavailable anywhere, which is reported as a `NOTICE:` line naming `prism-reference.md` as present-and-eligible-but-not-retired. This closes the first-hop bootstrap gap `docs/migrations/prism-to-scout.md` Step 1 describes: delivery and retirement backfill differently on a LATER, ordinary versioned upgrade. `scout-reference.md`'s delivery backfills automatically, once the newly-installed engine's own RECONCILE row runs. `prism-reference.md`'s retirement never does -- that is governed by `upgrade-removals.sh`'s `REMOVAL_MANIFEST` mechanism, whose base-commit reconstruction sees an empty base at every hop after the first (the stamp already points past the commit where core stopped shipping the file), so an ordinary versioned upgrade never retires it, at any later version. This mode is the one place that does, for that transition and for any adopter who has not yet run it.
- **Stamp-independent.** This mode dispatches before the version-stamp logic (the same precedent `--seed-ledger` sets, Step 4.5) and **never reads, writes, or advances** `.claire-version`. It needs no version argument and can run before or after a versioned merge, or on a branch that never runs one at all.
- **`--dry-run` writes nothing.** `.claude/skills/claire-upgrade/upgrade-claire.sh --rewrite-vocab --dry-run` reports which files it *would* rewrite and which reference-document action it *would* take (the same `vocab rewrite:` / `vocab reference ...:` report grammar) and creates no staging directory.
- **Exclusion seam, shared with the ordinary versioned upgrade.** `UPGRADE_VOCAB_EXCLUDE` (space-separated ticket directory names under `specs/`) skips the named tickets. It is read by `vocab_classify_tree` (`upgrade-vocab.sh`), which BOTH this mode and the ordinary `/claire-upgrade <new-version>` merge call (Step 1's vocabulary migration report, above) -- setting it before either invocation excludes the named tickets from both. Primarily for core's own use rewriting its own `specs/` tree (where a ticket's frozen record must stay untouched by this sweep), but available to any adopter who needs the same exclusion.
- **Two further test-only variables are gated to the BTG-332/BTG-333 harness (BTG-333 AC-7).** `UPGRADE_VOCAB_TEST_SHIPPED_SHA256` and `UPGRADE_VOCAB_TEST_STALE` take effect ONLY when a harness-only marker file is present in `$CORE` and `$CORE` is a different directory from `$TARGET` -- a condition no real adopter core can meet. Outside that condition, setting either variable has NO effect on classification, writing, or deletion; the run prints one `NOTICE:` line naming the ignored variable and continues (never a refused run).

### 5. Report outcome

- On a clean apply with the stamp advanced: print one line summarizing what was applied and the new stamp version.
- On conflicts: print the conflicting files and where they are staged for resolution; do not add a success summary.
- On a refusal (never-adopted; older target; unreachable base): print the engine's refusal message verbatim and stop.

### 5.5. The template-to-live org-fold (BTG-048)

On a fully-clean apply, **after** the stamp advances, the engine runs one more **dependent, best-effort, stamp-independent** stage: it folds the just-applied `docs/agentic-sdlc/CLAIRE_ORG_TEMPLATE.md` inter-version changes into the adopter's live `docs/agentic-sdlc/CLAIRE_ORG.md` (the file every skill/agent reads). This is **post-adoption only** — a repo with no live `CLAIRE_ORG.md` is skipped loud (the adopter owns creation; the fold never fabricates it), and a base-less (`--two-way`/`BASE_EMPTY`) run hard-skips it. It routes by section: the Zachman Who/Where/Why tables gain new template rows (existing rows untouched), the **Runtime Binding** section is carried byte-for-byte (reverted), and every other section is 3-way line-merged.

**On a fold conflict the live file is NEVER mutated in place** (a scoped, documented departure ONLY for this fold: unlike the file-level merge, the stamp has already advanced and is not rolled back — DEC-002): the marker-bearing folded form is staged under `.claire-upgrade-staging/docs/agentic-sdlc/CLAIRE_ORG.md`, a `seam_type=DECISION_DRIFT event_name=upgrade.orgfold.conflicts_staged` line fires, and a strong stderr directive names the staged path. Stream the fold's report/directive verbatim; if it staged conflicts, tell the operator to resolve the staged copy immediately before relying on the live file. The live file stays parseable meanwhile. A base-less/no-live skip or an unchanged template is a plain log line, not a failure.

### 5.6. Post-upgrade placeholder interview (BTG-053)

On a fully-clean apply, **after** the org-fold stage (5.5), route on the org-fold's **staged-conflict
artifact** to decide whether to fill any `<placeholder>` cells the fold may have (re)introduced into the
adopter's live `docs/agentic-sdlc/CLAIRE_ORG.md` Zachman Where/Who/Why tables. The signal is the
**existence of `.claire-upgrade-staging/docs/agentic-sdlc/CLAIRE_ORG.md`** — the org-fold's staged
form — never an in-file conflict-marker grep of the live file (BTG-048 DEC-001 guarantees a fold conflict
is staged, never written in place, so a live-file marker check can never be true; keying off it would be a
dead branch).

- **Staged file PRESENT** (the org-fold staged a conflict) → the **conflict path**: do **not** auto-invoke
  `/claire-interview`. Emit a strong **resolve-first** directive in the existing staged-conflict voice —
  tell the operator to reconcile the staged copy
  (`.claire-upgrade-staging/docs/agentic-sdlc/CLAIRE_ORG.md`), replace the live file, and then run
  `/claire-interview` **manually** afterward. The branch keys off **staged-file existence**, never a live-file
  conflict-marker grep.
- **Staged file ABSENT** (a clean fold, a fold that was skipped, or an unchanged template) → the **clean
  path**: invoke `/claire-interview` in **default mode**. The interview is itself interactive (every
  written value is a per-row human choice) and **no-ops when there are no placeholders**, so auto-invoking
  performs no silent write.

The clean-path invoke uses the **command-composition** capability. On a runtime with **no
command-to-command composition** (OpenCode), **degrade** to **printing a run-directive** ("run
`/claire-interview` to fill placeholders") — the same posture as the registered `claire-elicit`→`claire-triage`
handoff; the upgrade **does not fail**. No Edit/Write capability is added (the wrap-only constraint is
preserved).

This step is **additive**: the merge, stamp, and org-fold behavior above is byte-unchanged, and the
interview never blocks the apply.

### 6. Surface the bootstrapping-gap warning (BTG-016b)

If, at run start, the engine emits a `seam_type=LOGIC_FAULT event_name=upgrade.engine.bootstrapping_gap` line, the **running (installed) engine predates a protection epoch (3.8.8) the target crosses** — so the seed exclusion (BTG-015), hook relocation (BTG-008), `specs/drafts/` create (BTG-010), and `docs/SYSTEM_OVERVIEW.md` exclusion (BTG-018) protections **cannot self-apply this run** (they live in the engine being installed, not the one running the merge — structural finding F0). The upgrade still applies (the warning does not abort); surface the warning to the operator verbatim and, once on the fixed version, point them at `/claire-upgrade --repair` to reconcile the seeds/hooks/drafts. See `docs/guides/upgrade-repair-runbook.md`. A **second, parallel** `bootstrapping_gap` epoch (4.0.1) fires the same seam when the running engine predates the **org-fold** epoch (BTG-048): the template-to-live org-fold cannot self-apply on the upgrade that first installs it, and self-heals on the next `/claire-upgrade` — or the operator can fold **immediately** with `/claire-upgrade --repair-orgfold` (the on-demand org-fold, Step 8 below).

### 7. The `--repair` mode (BTG-016b)

`/claire-upgrade --repair` is a **separate operation** (not a merge — it does not touch the version stamp) that reconciles the damage a pre-protection bootstrapping upgrade left behind. It is **idempotent** and **per-concern atomic**: a failure in one concern is named and does not roll back an already-correct concern. Run it after the adopter has reached the fixed version:

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh --repair [--from <ref>]
```

It performs, each concern independently:

- **Seeds** — restores each of the five seed documents byte-for-byte from its **pre-upgrade `git` blob** (the parent of the stamp-advancing commit). On **any** ambiguity (a squashed / non-linear / merge history, or an unreachable blob) it fails **loud** with `seam_type=LINEAGE_GAP event_name=upgrade.repair.seed_source_missing`, restores nothing for that seed, and asks the operator to reconcile it manually or pass an explicit `--from <ref>` — it **never** guesses or fabricates seed content (DEC-B2). The set is the RESTORABLE seed projection, not every `kind=seed` row: `CLAUDE.md` is a seed for the merge but carries the `no-restore` disposition (BTG-198) and is **never** rewritten by this concern — it is adopter-owned, no engine writes it, so there is no pollution to undo and a restore could only revert the adopter's own work.
- **Hooks** — relocates a **pristine** legacy CLAIRE hook from the conventional hooks location to the compiled CLAIRE hooks tree and repoints the settings hook-registration (reused BTG-008 no-data-loss guard, emitting `upgrade.hooks.relocated`); a **customized** legacy hook is surfaced as a conflict and left untouched (registration not repointed) for human reconciliation.
- **Drafts** — create-if-absent `specs/drafts/.gitignore` (`*` then `!.gitignore`), never overwriting an existing one.
- **Eject** — refreshes the frozen `ci-templates/scripts/eject-*.sh` from core so BTG-016a's in-memory backfill covers a stale committed footprint. The committed `artifacts/footprint.generated` is **never** mutated (ADR_CLAIRE-0009).
- **Context** (BTG-198) — re-establishes broken `CLAUDE.md` ↔ `CLAIRE_DIRECTIVES.md` wiring: restores an absent sidecar, generates an absent context file, and writes or replaces the marker-fenced managed block carrying the import line. Everything **outside** that block is left byte-identical, so the adopter's own directives survive. Scoped to a repo that carries at least one of the two files; a repo with neither has no wiring to repair and is reported by the next upgrade's detection instead. Emits `upgrade.repair.context_restored`.

On a clean repo it reports `nothing to repair` and exits 0. Report the per-concern outcome verbatim; watch for `upgrade.repair.seed_source_missing` (a seed needs manual reconciliation) and a surfaced hook conflict (reconcile, then re-run — already-restored seeds are untouched).

### 8. The `--repair-orgfold` mode (BTG-049)

`/claire-upgrade --repair-orgfold` is a **separate, stamp-independent operation** (the `--repair` precedent — it never reads/writes/advances the version stamp) that runs the BTG-048 template-to-live **org-fold stage alone**, on demand, against the current live `docs/agentic-sdlc/CLAIRE_ORG.md`. It is the PI-003 bootstrapping remedy for a fleet operator whose **first** post-4.0.1 upgrade was run by the old, pre-fold engine (so the engine-resident fold silently skipped) and who must reconcile **now** rather than wait for the next upgrade's self-heal:

```bash
.claude/skills/claire-upgrade/upgrade-claire.sh --repair-orgfold [--from <ref>]
```

- **Base resolution** — it folds the `pre-upgrade → current` template delta, so the base is the **pre-upgrade** `core@<commit>`: the `commit=` field of the `.claire-version` blob at the **parent of the stamp-advancing commit** (mirroring `--repair`'s seed-source anchor). On **any** ambiguity (a squashed / non-linear / merge history, or a base unreachable in the core checkout) it fails **loud** with `seam_type=LINEAGE_GAP event_name=upgrade.orgfold.base_source_missing`, dispatches no fold, and asks the operator to pass an explicit `--from <version-or-core-ref>` (a dotted version is resolved through the core README; anything else is a raw core commit ref) or point `UPGRADE_CORE` at a checkout containing the base — it **never** guesses a base.
- **Reuses the fold engine unchanged** — everything downstream is BTG-048's `run_orgfold` verbatim: section-aware routing, Zachman row-add, the Runtime-Binding revert, conflicts **staged never in place** under `.claire-upgrade-staging/` (`upgrade.orgfold.conflicts_staged` + a strong stderr directive), `BASE_EMPTY`/no-live-file **loud skips** (best-effort, exit 0 — the adopter owns live-file creation, never fabricated), and the `template unchanged` clean no-op.
- **Idempotent** — a re-run against an already-reconciled live file leaves its bytes unchanged (content-level idempotency; the reused engine may still print `applied`).

Stream the fold's report/directive verbatim. A reachable core checkout (`UPGRADE_CORE`) and a linear stamp history are required (the same base requirement as the normal merge); on a squash/merge anchor, use `--from`. See `docs/guides/upgrade-repair-runbook.md`.

## Constraints

- **Wrap, do not reimplement.** The bash script is the single source of truth for the merge, the atomicity, the stamp advance, and the conflict surfacing. The skill does NOT inline a merge via other tools — its `allowed-tools` deliberately excludes Edit and Write.
- **Never a silent merge.** A conflict is always surfaced for human resolution; a side is never auto-picked.
- **Atomic.** A clean apply is all-or-nothing; the stamp advances only on a fully-clean apply; a single conflict blocks the whole auto-apply.
- **Forward-only (v1).** An already-stamped target is a no-op; an older target is refused. Multi-version skip upgrades are out of scope.
- **Local only.** The merge operates on the local adopter repo and a local core checkout; no remote targets.
- **`--dry-run` writes nothing.** The preview computes the identical 3-way merge and reports the outcome to stdout only — no stamp advance, no staging directory, no footprint write, no work-tree apply. An inadvertent write under `--dry-run` would be a correctness defect.
- **Never auto-generate the footprint silently.** Step 0 always requires explicit operator confirmation before writing `artifacts/footprint.generated`.

## Examples

```
/claire-upgrade 3.7.0
```

Reads the adopter's `.claire-version` (the base) and `artifacts/footprint.generated` (the merge scope), reconstructs core at the stamped base and at `3.7.0`, 3-way-merges new core into the adopter's customized tree, auto-applies the clean changes, advances the stamp to `3.7.0`, and reports what changed.

```
/claire-upgrade 3.7.0
```

If the adopter and new core both changed the same lines of an agent, the conflicting file is staged under `.claire-upgrade-staging/` with conflict markers, nothing is applied, the stamp stays put, and the conflict is reported for the human to resolve.

```
/claire-upgrade 3.7.0
```

If the repo has no `.claire-version` but carries an installed CLAIRE surface (a pre-PI-021 adopter), the engine infers a base version and asks for confirmation; on confirmation a bootstrap stamp is written and the normal 3-way merge proceeds.

```
/claire-upgrade 3.7.0 --dry-run
```

Computes the full 3-way merge in memory and prints "N in scope; C would apply cleanly; M would conflict" plus the conflicting paths, then exits 0 (would-be-clean) or non-zero (would-be-conflict) — writing nothing. Use it to preview a run, or as a CI pre-merge gate keyed off the exit code.
