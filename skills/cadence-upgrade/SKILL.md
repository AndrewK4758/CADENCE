---
name: cadence-upgrade
description: Merge a newer CADENCE core release into an adopter's customized repository using the PI-021 version stamp as the 3-way merge base. Wraps the canonical merge engine; clean changes apply atomically, conflicts are staged for human resolution (never silently merged), and the version stamp advances only on a completely clean apply.
argument-hint: "<new-version>"
arguments: [new_version]
allowed-tools: Read Bash Skill
---

## Task

Upgrade the adopter repository in the current working directory to CADENCE core release `$new_version` by delegating to the canonical merge engine at `.agents/skills/cadence-upgrade/upgrade-cadence.sh` (where `.agents/` is the primary neutral runtime surface, `.gemini/` is the canonical Gemini/Antigravity runtime directory, and `.claude/` or other CLI runtime directories are projected off `.agents/` per `docs/policies/cli-runtime-adoption-policy.md`).

This skill does not implement merge mechanics directly — the bash script is the single source of truth for the 3-way merge, atomic work-tree application, version-stamp advancement, and conflict staging. The skill validates arguments, invokes the engine, streams its output verbatim (while also routing noisy conflict/gate/test logs exceeding 30 lines through `offload_log_triage`), and independently verifies that post-conditions landed in the adopter's actual repository rather than relying solely on the exit status.

## Prerequisites

Before running the engine, verify:

1. `$new_version` is supplied, non-empty, and formatted as a dotted semantic version (e.g. `3.7.0`) -- **unless** the caller passed a version-independent operational mode flag (`--seed-ledger`, `--rewrite-vocab`, `--repair`, `--repair-orgfold`; see Steps 4.5, 4.6, 7, and 8), each of which dispatches prior to version-stamp resolution and ignores `$new_version`. When neither a version string nor one of those mode flags is provided, halt with: "Usage: `/cadence-upgrade <new-version>`. The new-version is the CADENCE core version to upgrade to."
2. The current working directory is the adopter repository being upgraded (the merge updates the adopter's compiled `.agents/` tree, projected runtime surfaces, and installed documentation in place). The engine reads `.cadence-version` and the footprint descriptor from this directory.

## Pre-PI-021 adopters (no installed command tree yet)

The `.agents/skills/cadence-upgrade/upgrade-cadence.sh` script path exists in the adopter repository only **after** adoption. A pre-PI-021, compiled-only adopter does not yet have an installed `.agents/skills/cadence-upgrade/` directory to invoke locally. For those repositories, execute the engine directly from a **local core checkout** of CADENCE (a local `git clone` of the framework repository carrying the target release), targeting the adopter repository via the `UPGRADE_TARGET` environment seam:

```bash
UPGRADE_TARGET=<adopter-repo> bash <core>/artifacts/commands/cadence-upgrade/upgrade-cadence.sh <ver>
```

- **When required:** the adopter lacks an installed `.agents/skills` tree (pre-adoption / pre-PI-021). Once the upgrade installs the skill tree (and projects runtime directories per `docs/policies/cli-runtime-adoption-policy.md`), subsequent upgrades use the standard `.agents/skills/cadence-upgrade/upgrade-cadence.sh` path.
- **Locating the core checkout:** clone the CADENCE framework repository locally (or point at an existing local clone **that carries the target version's annotated release tag** — see below). `<core>` is that checkout's root directory; both the merge engine and the eject footprint deriver resolve upstream inputs from it (override via `UPGRADE_CORE` when invoking from outside the core repository).
- **Release tags matter (BTG-311).** Version resolution is restricted to the target version's annotated release tag (`v<ver>` or `<ver>`) whenever that tag is present in `<core>` — preventing the resolver from pulling an unmerged branch or post-release commit into the merge base. A long-lived clone with active development branches works reliably provided its tags are current (`git fetch --tags`); a clone created with `--no-tags`, or a stale mirror missing the target release tag, falls back to the pre-BTG-311 all-refs search and **explicitly warns** that resolution is unadjudicated (emitting a `DRIFT_SIGNAL upgrade.base.resolved_without_tag` seam alongside a stderr notice) instead of trusting it silently. If that notice appears, run `git fetch --tags` inside `<core>` and re-run to obtain tag-bounded (adjudicated) base resolution.
- **Execution flow:** the engine begins with the Step 0 footprint pre-check (below). If the footprint file is missing, it halts and offers instructions for auto-generation; once the footprint is present, the same command executes the 3-way merge. Append `--dry-run` to preview changes without modifying disk state.

## Steps

### 0. Footprint pre-check + auto-generate (pre-PI-021 adopters)

The merge scope boundary is governed by `artifacts/footprint.generated` (consumed directly, never silently re-derived during a merge). A pre-PI-021, compiled-only adopter lacks this file. The engine checks for its existence at the very start of bootstrap: if the footprint descriptor is **absent**, execution halts immediately (prior to any confirm-base prompt or version-stamp write) with a `DELTA_AUDIT_GAP upgrade.boundary.descriptor_missing` seam and an error naming the missing descriptor and referencing this step.

When the footprint descriptor is absent, offer to **auto-generate** it from the core checkout — proceeding only after **explicit operator confirmation** (never silently overwriting a footprint the operator may have started crafting manually). Invoke the engine's dedicated Step 0 mode, `--autogen-footprint`, unlocked by `AUTOGEN_CONFIRM=1` (without that environment variable, the engine writes nothing and reiterates that the footprint is required). This mode invokes the engine's verified helper, which delegates to the canonical eject deriver (`cadence-eject.sh` reading exclusively from the core checkout and writing the descriptor to stdout), captures output into a temporary file, verifies the deriver's exit code, and **atomically moves** the file into place only on zero exit (derive-to-temp-then-move — ensuring a failed or interrupted derivation never truncates or leaves a partial footprint file). **Never** pipe the deriver directly into the destination path with a raw `>` redirect, as the shell truncates the target before the deriver starts. Upon operator confirmation:

```bash
AUTOGEN_CONFIRM=1 UPGRADE_TARGET=<adopter-repo> UPGRADE_CORE=<core> \
  bash <core>/artifacts/commands/cadence-upgrade/upgrade-cadence.sh --autogen-footprint
```

This operation is idempotent: re-deriving against an unchanged core commit produces a byte-identical descriptor. If derivation fails (for instance, `<core>` is unreachable or the deriver script is missing), the engine emits `DELTA_AUDIT_GAP upgrade.footprint.derive_failed`, leaves the destination untouched, and prints an actionable error — halt and repair the core checkout before continuing. Once the footprint descriptor is in place, proceed to Step 1.

### 1. Invoke the engine

Execute the canonical merge engine with the requested target version:

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh "<new_version>"
```

Stream stdout and stderr to the adopter verbatim. Do not alter, condense, or paraphrase the per-file change report or conflict summary — they serve as the permanent audit trail and the operator's conflict-resolution guide. Whenever `upgrade-cadence.sh` conflict diagnostics, gate checks (`authored-doc-gate.sh`, `dead-citation-gate.sh`), or post-upgrade test outputs exceed 30 lines, automatically pass the output through `offload_log_triage` (`local-fast-cpu` on `:11434`) so the operator gets a clean verbatim failure digest while the complete raw output remains preserved in `/tmp/agy-last-triage.log`.

**Vocabulary migration report (BTG-332, D1-D4).** Within the same atomic transaction, the engine also scans, classifies, and rewrites the adopter's active `specs/<id>/**/*.md` and `*.yaml` files (excluding `specs/TEMPLATE/`, `specs/drafts/`, `specs/CADENCE.md`, and any ticket directory listed in `UPGRADE_VOCAB_EXCLUDE` -- see Step 4.6 below) into **CHORD** vocabulary (Conditions, Handling/Triggers, Outcomes, Rules, Deltas; see `docs/agentic-sdlc/chord-reference.md` for the retired-term mapping). A clean apply emits one `upgrade-cadence: vocab rewrite: <path> (<N> line(s))` line per updated spec file, followed by a `upgrade-cadence: vocab retained (historical): <N> line(s) across <N> file(s).` summary whenever frozen historical lines were preserved unchanged. Stream these lines verbatim alongside the framework-file report as part of the single audit trail. Any line that mixes the legacy acronym with a dimension word outside a recognized template pattern is flagged as a **vocab conflict**: it routes into the exact same conflict staging mechanism described in Step 3 (staged under `.cadence-upgrade-staging/` with conflict markers and reported on stderr as `vocab-conflict: <path>:<line>`), blocking the entire apply just like a framework-file conflict — never auto-resolve it.

**Preview first with `--dry-run` (optional, recommended).** Prior to executing a live upgrade, pass `--dry-run` to compute the complete 3-way merge in memory and inspect the outcome — total files in scope, clean-apply count, conflict count, and specific conflicting file paths — **without touching the filesystem**: no `.cadence-version` update, no `.cadence-upgrade-staging/` directory, no footprint write, and no working-tree mutation. Its exit status is CI-friendly: **0** when the upgrade would apply cleanly, **non-zero** when conflicts would occur (allowing pre-merge CI gates to key off it).

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh "<new_version>" --dry-run
```

### 2. Handle the no-stamp bootstrap (pre-PI-021 adopter)

If the engine detects that `.cadence-version` is absent and reports an inferred base version, **present that inferred base version to the operator and obtain explicit confirmation before applying anything** — never proceed with an unconfirmed base. Once the operator confirms, re-run with `--confirm-base`:

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh "<new_version>" --confirm-base "<confirmed-base>"
```

If no base version can be inferred and the operator agrees to a two-way merge without a base, re-invoke with `--two-way` (surfacing every divergence as an explicit conflict for human resolution and never overwriting adopter files silently).

### 3. Handle conflicts (never silent)

When the engine encounters merge conflicts, it writes the marker-annotated conflict files under `.cadence-upgrade-staging/` while leaving the working tree and `.cadence-version` completely untouched. Do NOT attempt automated conflict resolution. Report the conflicting file paths (and if the conflict output exceeds 30 lines, run `offload_log_triage` to summarize the exact conflict coordinates while keeping raw logs in `/tmp/agy-last-triage.log`) and stop — the operator resolves the conflicts and re-invokes the upgrade.

**Base-commit authority when hand-resolving (N-1 / DEC-002, narrowed by BTG-311).** The engine's merge base commit remains the **README-of-record** commit — the commit whose `README.md` declares `**Version X.Y.Z**`, located by `core_commit_for_version` — which is the exact commit to diff against during manual conflict resolution. Under BTG-311, whenever the target version's release tag `vX.Y.Z` (or bare `X.Y.Z`) exists in the core checkout, the README-of-record is resolved **within that tag's ancestry**, meaning it **coincides with the tag commit itself** (the standard case across all releases cut in this repository). Thus, when resolving conflicts on a tag-bounded run, `git show vX.Y.Z` and the engine's resolved base commit are identical. Divergence can occur only in one scenario: a core checkout **lacking the release tag** for that version (pre-tag history or unfetched tags), where the engine falls back to the pre-BTG-311 all-refs scan and **announces** the fallback (`DRIFT_SIGNAL upgrade.base.resolved_without_tag` on stderr). If that signal appeared, diff against the **engine's reported commit** rather than `git show vX.Y.Z` — diffing against the tag would anchor manual resolution to a different base than the engine used, causing the conflict to recur on re-run. See `archive/BTG-311/decisions.md` DEC-002 for details.

**Resolution halts (BTG-311).** Two error conditions cause the engine to abort base resolution before computing any merge inputs — both list all candidate commits discovered and leave `.cadence-version` untouched: (1) the target version's tag exists, yet **no commit in its ancestry** declares that version (`BOUNDARY_FAULT upgrade.base.resolved_outside_release` — typically caused by a shallow clone; fix with `git fetch --unshallow` and re-run); (2) **both** tag formats (`vX.Y.Z` and `X.Y.Z`) exist simultaneously and reference **different** commits (`UNSOUND_CONDITION upgrade.base.tag_spelling_ambiguous` — delete or align the duplicate tag in the core checkout). Neither condition is a file conflict; both halt execution prior to merging. Consult `docs/guides/upgrade-repair-runbook.md` for recovery procedures.

**A base stamp written before this fix (BTG-311 AC-9).** If `.cadence-version` was written by a pre-BTG-311 engine, its stored `commit=` hash may sit chronologically ahead of the tag-bounded target on the next upgrade. The engine announces this condition (`DRIFT_SIGNAL upgrade.base.stamp_ahead_of_target`) and **continues** — never refusing the run — though any conflict surfaced on that hop could stem from the legacy stamp offset rather than an adopter customization. A second, narrower source of the same signal is a stamp generated by `/cadence-adopt` **prior to** BTG-314, which recorded the core checkout's `HEAD` rather than the tagged release commit; the diagnosis and remediation are identical in both cases. See `docs/migrations/version-resolution-tag-bounded.md`.

**PI-033 / G-8 — the one-time `surface-registry.md` split conflict.** When `docs/policies/surface-registry.md` appears in the conflict list, it represents the expected one-time **split-transition conflict** for repositories adopted prior to the framework-surface split: upstream removed framework rows from `surface-registry.md` (relocating them into the upstream-owned `docs/policies/cadence-surfaces.md`) while the adopter had modified adjacent lines. Direct the operator to `docs/migrations/cadence-surfaces-split.md` — the proper resolution is to **keep the adopter's side (their project-specific rows) for `surface-registry.md`** and **accept upstream's new `cadence-surfaces.md`**. Subsequent framework surface additions will never conflict in `surface-registry.md` again.

### 4. Verify the apply landed in the adopter's real repo

Because the merge engine reports completion relative to its own working target, after a clean exit 0 you must **independently** inspect the adopter's canonical repository: confirm that `.cadence-version` now contains `<new_version>` and that in-scope files were updated (including `.agents/` and any projected runtime surfaces per `docs/policies/cli-runtime-adoption-policy.md`). If `.cadence-version` did not advance, do NOT report success — the upgrade likely executed inside a temporary or isolated worktree. Halt and instruct the operator to re-run directly inside the adopter repository.

### 4.5. Seed the id-allocation ledger (create-if-missing, PI-039)

An adopter upgrading from a CADENCE core release prior to PI-039 already has historical records across `specs/`, `archive/`, `docs/ADR/`, `intent-insights.md`, and `production-insights.md`, but lacks a reserve ledger. Execute the engine's scan-and-seed mode to initialize the ledger to the repository's actual high-water marks so that subsequent `--reserve` calls never collide with or reuse historical identifiers:

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh --seed-ledger
```

- **Create-if-missing and idempotent.** Each prefix is seeded via `--seed` only when no ledger entries exist for that prefix yet; any prefix already present in the ledger (from a prior run or manual bootstrap) is skipped without modifying the file. Running `--seed-ledger` on every upgrade is completely safe.
- **§10-gated ticket prefix.** `ADR`, `II`, and `PROD` prefixes are always scanned and seeded regardless of §10. The ticket prefix is seeded only when `CADENCE_ORG.md` §10 is unbound (`None — closed default`); when an external issue tracker is bound, ticket identifiers are minted by that external tracker, so local ticket-prefix scanning and seeding are skipped.
- **Independent of the merge transaction.** `--seed-ledger` dispatches prior to version-stamp evaluation and **never reads, modifies, or advances** `.cadence-version`. It requires no version argument and may be executed either before or after a versioned upgrade.
- **`--dry-run` performs zero writes.** Running `.agents/skills/cadence-upgrade/upgrade-cadence.sh --seed-ledger --dry-run` prints the high-water marks that *would* be seeded per prefix without creating or altering the ledger.

### 4.6. Rewrite adopter-spec vocabulary independently of the stamp (`--rewrite-vocab`, BTG-332 D5)

While Step 1's vocabulary migration executes automatically during a standard versioned upgrade, a feature or ticket branch merged **after** that upgrade completed may introduce specs authored with legacy terminology that a subsequent versioned run over the same stamp would not re-evaluate. Invoke the engine's stamp-independent vocabulary mode to sweep and update those active specs standalone:

```bash
UPGRADE_CORE=<core> .agents/skills/cadence-upgrade/upgrade-cadence.sh --rewrite-vocab
```

- **`UPGRADE_CORE` must reference a separate, current core checkout containing `docs/agentic-sdlc/chord-reference.md`** (code-review cycle 3 B1). If `UPGRADE_CORE` is unset, `$CORE` defaults to the adopter's own working tree (the installed script's parent repo) -- in `--rewrite-vocab` mode the engine fails loud naming `UPGRADE_CORE` rather than classifying specs while unable to deliver or retire the reference docs.
- **Incompatible with a version argument.** Passing `<new-version> --rewrite-vocab` (in either order) fails loud naming `--rewrite-vocab` and the rejected version string rather than silently discarding the version argument (DEC-053 pre-merge fix-up, held candidate c1-4): this mode is strictly stamp-independent and accepts no version parameter.
- **Never removes an existing `.cadence-upgrade-staging/` directory.** If `.cadence-upgrade-staging/` is already present when `--rewrite-vocab` starts -- for example, holding an unresolved `CADENCE_ORG.md` org-fold conflict from Step 1a (`docs/migrations/prism-to-chord.md` Step 1b) -- the engine refuses to run, names `.cadence-upgrade-staging`, and instructs the adopter to resolve or clear it first without writing anything (DEC-053 pre-merge fix-up, held candidate c1-4). It never wipes an existing staging directory to stage new conflicts.
- **All-or-nothing across active spec vocabulary.** Any conflicting line (an acronym combined with a dimension keyword outside known template structures) stages all conflicting spec files under `.cadence-upgrade-staging/` with conflict markers and leaves the working tree untouched; resolve manually and re-run just as in Step 3. The reference-document delivery/retirement step below NEVER triggers a conflict rollback: neither reference document's state blocks the rest of the run (DEC-036).
- **Delivers and retires the reference document in the same pass (DEC-033).** The same invocation installs `docs/agentic-sdlc/chord-reference.md` (whenever the adopter repository does not yet have a file at that path -- any existing file, regardless of content, is treated as already present and left untouched without conflict, code-review B2) and removes `docs/agentic-sdlc/prism-reference.md` when EITHER condition is met: its content (normalizing line endings) matches the committed allowlist of every historical version CADENCE ever shipped (DEC-036; requiring zero `$CORE` git history queries so tarballs, shallow clones, and CRLF working trees behave identically), OR the file is exactly zero bytes (DEC-041, maintainer ruling: the pre-BTG-332 merge engine truncated this path to zero bytes on an adopter's initial hop because it lacked a `REMOVAL_MANIFEST` entry for the path, so empty bytes are recognized as a known upgrade artifact rather than an adopter customization). The pristine/truncated/customized classification is evaluated against a snapshot captured at classification time and re-verified immediately prior to unlinking (BTG-333 AC-2, matching the spec-vocabulary atomic check): if a concurrent write modifies `prism-reference.md` between classification and removal, the engine raises `upgrade.vocab.stale_input` and retains the file rather than deleting based on stale state. Every completed action is logged explicitly (`vocab reference delivered: ...` / `vocab reference retired: ...`, with truncation retirements stating that reason inline) -- even if a subsequent step in the same invocation faults: a failure while removing `prism-reference.md` or staging conflicts never masks an earlier `chord-reference.md` delivery that already succeeded. A customized `prism-reference.md` (matching neither a known release digest nor zero bytes) is kept in place with a prominent `NOTICE:` line, never deleted and never blocking the run; similarly, if `chord-reference.md` is unavailable in `$CORE`, the engine emits a `NOTICE:` line reporting `prism-reference.md` as eligible-but-not-retired. This bridges the first-hop bootstrap gap documented in `docs/migrations/prism-to-chord.md` Step 1: while `chord-reference.md` delivery backfills automatically on a subsequent versioned upgrade via its RECONCILE row, `prism-reference.md` retirement never backfills on ordinary versioned upgrades because `upgrade-removals.sh`'s `REMOVAL_MANIFEST` sees an empty base on every hop after the stamp passes the removal commit. `--rewrite-vocab` provides the dedicated mechanism to retire it at any time.
- **Stamp-independent.** Dispatches prior to version-stamp evaluation (matching `--seed-ledger` in Step 4.5) and **never reads, modifies, or advances** `.cadence-version`. It requires no version parameter and can run before or after a versioned upgrade or on a standalone branch.
- **`--dry-run` performs zero writes.** Running `.agents/skills/cadence-upgrade/upgrade-cadence.sh --rewrite-vocab --dry-run` previews which spec files *would* be rewritten and which reference-document actions *would* occur (using the identical `vocab rewrite:` / `vocab reference ...:` output format) without creating a staging directory or modifying files.
- **Shared exclusion seam.** `UPGRADE_VOCAB_EXCLUDE` (a space-delimited list of ticket directory names under `specs/`) exempts the specified tickets from vocabulary rewriting. It is respected by `vocab_classify_tree` (`upgrade-vocab.sh`), which backs both `--rewrite-vocab` and standard `/cadence-upgrade <new-version>` runs (Step 1) -- exporting it prior to either command skips those ticket directories in both modes. Designed primarily for core's self-hosting `specs/` tree (where historical ticket records must remain frozen), it is equally available to adopters needing targeted exemptions.
- **Two harness-only test variables are strictly gated (BTG-333 AC-7).** `UPGRADE_VOCAB_TEST_SHIPPED_SHA256` and `UPGRADE_VOCAB_TEST_STALE` activate ONLY when a dedicated test-harness marker file exists inside `$CORE` AND `$CORE` differs from `$TARGET` -- a condition never satisfied in production adopter upgrades. Outside the test harness, setting either variable has zero effect on classification, file writes, or unlinking; the engine prints a single `NOTICE:` line naming the ignored variable and proceeds normally without aborting.

### 5. Report outcome

- On a clean apply where `.cadence-version` advanced: output a concise summary of the applied changes and the new version stamp.
- On merge or vocabulary conflicts: list the conflicting paths and their `.cadence-upgrade-staging/` locations; omit any success banner.
- On an engine refusal (unadopted repository, downgrade attempt, or unresolvable base): output the engine's refusal message verbatim and halt.

### 5.5. The template-to-live org-fold (BTG-048)

Following a completely clean apply and **after** `.cadence-version` advances, the engine executes one additional **dependent, best-effort, stamp-independent** stage: it folds inter-version changes from the newly updated `docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md` into the adopter's live `docs/agentic-sdlc/CADENCE_ORG.md` (the active governance document consumed by skills and agents). This fold runs **post-adoption only** — if no live `CADENCE_ORG.md` exists, the fold logs a loud skip (creating the live file belongs to the adopter; the fold never synthesizes one), and base-less runs (`--two-way` or `BASE_EMPTY`) skip it unconditionally. Merging is section-aware: the Contextual Grounding Matrix (6W×4L) Who/Where/Why tables receive newly added template rows (leaving existing adopter rows untouched), the **Runtime Binding** section is preserved byte-for-byte from the live file (reverted), and all remaining sections undergo a 3-way line merge.

**When an org-fold conflict occurs, the live `CADENCE_ORG.md` is NEVER modified in place** (a documented exception specific to this post-stamp stage: unlike the primary file merge, `.cadence-version` has already advanced and is not rolled back — DEC-002). Instead, the marker-annotated merged file is written to `.cadence-upgrade-staging/docs/agentic-sdlc/CADENCE_ORG.md`, a `seam_type=RULE_DIVERGENCE event_name=upgrade.orgfold.conflicts_staged` seam is emitted, and an explicit stderr directive reports the staged file path. Stream the fold output and directive verbatim; if conflicts were staged, instruct the operator to reconcile `.cadence-upgrade-staging/docs/agentic-sdlc/CADENCE_ORG.md` immediately before relying on the live org file. Meanwhile, the live `CADENCE_ORG.md` remains syntactically valid and parseable. A base-less skip, missing live file skip, or unchanged template emits a normal informational log line rather than an error.

### 5.6. Post-upgrade placeholder interview (BTG-053)

After a clean apply and **following** the org-fold stage (Step 5.5), inspect the org-fold's **staged-conflict artifact** to determine whether to interactively populate any `<placeholder>` cells that the fold introduced into the adopter's live `docs/agentic-sdlc/CADENCE_ORG.md` Contextual Grounding Where/Who/Why tables. Routing is controlled strictly by the **filesystem presence of `.cadence-upgrade-staging/docs/agentic-sdlc/CADENCE_ORG.md`** — never by grepping the live `CADENCE_ORG.md` for conflict markers (since BTG-048 DEC-001 guarantees org-fold conflicts are always staged externally and never written into the live file, grepping the live file for markers would be a dead check).

- **Staged conflict file PRESENT** (the org-fold staged a conflict) → **conflict branch**: do **not** automatically invoke `/cadence-interview`. Output a clear **resolve-first** instruction matching the staged-conflict guidance — direct the operator to resolve `.cadence-upgrade-staging/docs/agentic-sdlc/CADENCE_ORG.md`, move it over the live `docs/agentic-sdlc/CADENCE_ORG.md`, and then invoke `/cadence-interview` **manually**. This branch keys solely off the staged file's existence.
- **Staged conflict file ABSENT** (clean fold, skipped fold, or unchanged template) → **clean branch**: invoke `/cadence-interview` in **default mode**. Because `/cadence-interview` is interactive (requiring an explicit human selection for every row) and **no-ops automatically when zero `<placeholder>` cells exist**, auto-invocation never performs silent edits.

The clean-branch invocation relies on runtime **command composition**. On a CLI runtime that lacks command-to-command composition (such as OpenCode), **gracefully degrade** by **printing an explicit run directive** ("Run `/cadence-interview` to populate any new `<placeholder>` cells in `CADENCE_ORG.md`") — mirroring the standard `cadence-elicit`→`cadence-triage` handoff posture without failing the upgrade. No direct Edit/Write tools are added to this skill, preserving the wrapper-only boundary.

This step is strictly **additive**: the core merge, version stamp advancement, and org-fold mechanics remain byte-identical, and the interview never blocks the upgrade transaction.

### 6. Surface the bootstrapping-gap warning (BTG-016b)

If the engine prints a `seam_type=LOGIC_FAULT event_name=upgrade.engine.bootstrapping_gap` line at startup, the **currently installed engine running the upgrade predates a protection epoch (3.8.8) that the target version crosses**. Consequently, seed exclusion (BTG-015), hook relocation (BTG-008), `specs/drafts/` initialization (BTG-010), and `docs/SYSTEM_OVERVIEW.md` exclusion (BTG-018) protections **cannot self-apply during this hop** (because those guards reside in the new engine being installed rather than the old engine executing the merge — structural finding F0). The upgrade still completes normally (the warning is non-fatal); relay the warning verbatim to the operator and, once the upgrade finishes, instruct them to run `/cadence-upgrade --repair` to restore seeds, hooks, and draft ignores. Refer to `docs/guides/upgrade-repair-runbook.md`. A **second, parallel** `bootstrapping_gap` epoch (4.0.1) emits the same seam when the running engine predates the **org-fold** epoch (BTG-048): the template-to-live org-fold cannot execute during the hop that first installs it, and will either self-heal on the subsequent `/cadence-upgrade` or can be triggered **immediately** via `/cadence-upgrade --repair-orgfold` (Step 8 below).

### 7. The `--repair` mode (BTG-016b)

`/cadence-upgrade --repair` is a **standalone remediation command** (outside the merge flow — it never touches `.cadence-version`) that repairs state left behind by a pre-protection bootstrapping upgrade. It is **idempotent** and **atomic per concern**: a failure in one concern is reported clearly without rolling back other concerns that succeeded. Execute it once the adopter repository has been upgraded to the fixed version:

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh --repair [--from <ref>]
```

It remediates five independent concerns:

- **Seeds** — restores each of the five restorable seed documents byte-for-byte from its **pre-upgrade `git` blob** (resolved from the parent of the commit that advanced `.cadence-version`). On **any** history ambiguity (squashed commits, non-linear or merge history, or an unreachable git object), it halts **loud** with `seam_type=DELTA_AUDIT_GAP event_name=upgrade.repair.seed_source_missing`, leaves that seed untouched, and instructs the operator to restore it manually or supply an explicit `--from <ref>` — **never** guessing or synthesizing seed content (DEC-B2). Note that this applies only to the RESTORABLE seed subset, not every `kind=seed` footprint entry: `AGENTS.md` is marked `no-restore` (BTG-198) and is **never** overwritten by `--repair` because it is adopter-owned and never mutated by the merge engine, meaning a restore would only clobber adopter customizations.
- **Hooks** — migrates a **pristine** legacy CADENCE hook from its legacy hooks path into the compiled `.agents/hooks/` tree (and projected runtime hook directories) while updating the settings hook registration (reusing the BTG-008 zero-data-loss guard and emitting `upgrade.hooks.relocated`); a **customized** legacy hook is flagged as a conflict and left in place (with registration unchanged) for manual reconciliation.
- **Drafts** — creates `specs/drafts/.gitignore` (`*` followed by `!.gitignore`) if absent, never overwriting an existing file.
- **Eject** — updates the frozen `ci-templates/scripts/eject-*.sh` scripts from core so that BTG-016a's in-memory backfill covers stale committed footprint descriptors. The committed `artifacts/footprint.generated` file itself is **never** mutated (ADR_CADENCE-0009).
- **Context** (BTG-198) — repairs broken `AGENTS.md` ↔ `CADENCE_DIRECTIVES.md` linkage: restores a missing sidecar, generates a missing context file, and inserts or updates the marker-fenced managed block containing the import directive. All content **outside** the marker fence remains byte-untouched, preserving adopter-specific instructions. This concern runs whenever at least one of the two files exists; a repository missing both has no wiring to repair and will be flagged during the next upgrade's detection pass. Emits `upgrade.repair.context_restored`.

On an already-clean repository, `--repair` outputs `nothing to repair` and exits 0. Stream the per-concern results verbatim, watching specifically for `upgrade.repair.seed_source_missing` (requiring manual seed restoration or `--from <ref>`) and any surfaced hook conflict (which the operator reconciles before re-running `--repair`, leaving already-repaired seeds intact).

### 8. The `--repair-orgfold` mode (BTG-049)

`/cadence-upgrade --repair-orgfold` is a **standalone, stamp-independent command** (following the `--repair` pattern — it never reads, writes, or advances `.cadence-version`) that executes the BTG-048 template-to-live **org-fold stage in isolation**, on demand, against the adopter's live `docs/agentic-sdlc/CADENCE_ORG.md`. It serves as the PI-003 bootstrapping remedy for operators whose **initial** post-4.0.1 upgrade ran under an older pre-fold engine (causing the in-upgrade fold to be skipped) and who want to reconcile `CADENCE_ORG.md` **immediately** rather than waiting for the next version upgrade:

```bash
.agents/skills/cadence-upgrade/upgrade-cadence.sh --repair-orgfold [--from <ref>]
```

- **Base resolution** — computes the `pre-upgrade → current` template delta by resolving the **pre-upgrade** `core@<commit>` from the `commit=` entry inside `.cadence-version` at the **parent of the stamp-advancing commit** (matching `--repair`'s seed-source anchor). On **any** ambiguity (squashed, non-linear, or merge history, or a base commit missing from the core checkout), it halts **loud** with `seam_type=DELTA_AUDIT_GAP event_name=upgrade.orgfold.base_source_missing`, performs no fold, and instructs the operator to provide an explicit `--from <version-or-core-ref>` (where a dotted semantic version resolves via the core README and any other token is treated as a raw core git ref) or point `UPGRADE_CORE` at a clone containing the base commit — **never** guessing a merge base.
- **Reuses the canonical fold engine** — downstream execution invokes BTG-048's `run_orgfold` identically: section-aware routing, Contextual Grounding Matrix row additions, Runtime-Binding preservation, conflict staging **exclusively outside the live file** under `.cadence-upgrade-staging/` (`upgrade.orgfold.conflicts_staged` + explicit stderr instructions), loud non-failing skips (`exit 0`) on `BASE_EMPTY` or an absent live `CADENCE_ORG.md`, and clean no-op when the template is unchanged.
- **Idempotent** — re-running `--repair-orgfold` against an already-folded `CADENCE_ORG.md` leaves the file byte-identical (content-level idempotency, even if the underlying helper prints `applied`).

Stream the fold report and any directives verbatim. Requires a reachable core checkout (`UPGRADE_CORE`) and linear stamp commit ancestry (unless `--from` is supplied). See `docs/guides/upgrade-repair-runbook.md`.

## Constraints

- **Wrap, never reimplement.** The bash script is the single authoritative implementation for the 3-way merge, transactional atomicity, stamp updates, and conflict staging. This skill never performs file merges via native editing tools — its `allowed-tools` intentionally omits Edit and Write.
- **Never a silent merge.** Every conflict is staged for human inspection and resolution; neither side is ever chosen automatically.
- **Transactional atomicity.** A clean upgrade applies all in-scope files at once and advances `.cadence-version`; even a single file or vocabulary conflict blocks the entire auto-apply and leaves `.cadence-version` unchanged.
- **Forward-only upgrades (v1).** Upgrading to the already-stamped version is a clean no-op; downgrading to an older version is refused.
- **Local filesystem only.** Operates strictly against the local adopter repository and a local core checkout; remote URLs are not supported.
- **`--dry-run` performs zero writes.** Preview mode runs the exact 3-way merge calculation in memory and reports results to stdout without mutating `.cadence-version`, `.cadence-upgrade-staging/`, `artifacts/footprint.generated`, or the working tree.
- **Never auto-generate the footprint descriptor without confirmation.** Step 0 always requires explicit operator consent (`AUTOGEN_CONFIRM=1`) before writing `artifacts/footprint.generated`.

## Examples

```
/cadence-upgrade 3.7.0
```

Reads the adopter's `.cadence-version` (merge base) and `artifacts/footprint.generated` (merge scope), reconstructs upstream core at the stamped base and at `3.7.0`, performs a 3-way merge into the adopter's tree, applies clean updates atomically, advances `.cadence-version` to `3.7.0`, and prints the per-file change report.

```
/cadence-upgrade 3.7.0
```

When both the adopter and upstream `3.7.0` modified the same lines in an agent or skill file, the conflicted output is written to `.cadence-upgrade-staging/` with standard conflict markers, the working tree and `.cadence-version` remain untouched, and the conflicting paths are reported for manual resolution.

```
/cadence-upgrade 3.7.0
```

When invoked in a repository lacking `.cadence-version` that already contains an installed CADENCE surface (a pre-PI-021 adopter), the engine infers the base version and pauses for operator confirmation; once confirmed via `--confirm-base`, it writes the bootstrap stamp and executes the 3-way merge.

```
/cadence-upgrade 3.7.0 --dry-run
```

Executes the full 3-way merge in memory and outputs "N in scope; C would apply cleanly; M would conflict" along with any conflicting paths, exiting 0 (clean) or non-zero (conflicts) without modifying any files on disk. Ideal for pre-upgrade previews or CI pre-merge gates.
