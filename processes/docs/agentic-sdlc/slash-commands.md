# Skills (Slash Commands)

Slash commands in `.agents/skills/` (projected to `.gemini/skills/` or `.claude/skills/` per `docs/policies/cli-runtime-adoption-policy.md`) provide the primary operator interface for the CADENCE agentic SDLC. Invoke them directly in your agentic coding runtime (reference runtime: Google Antigravity / Gemini CLI).

---

## Automatic Local Hardware Coprocessor Offload Across Commands

When executing CADENCE slash commands, read-only discovery, test/build log compaction, and pre-review mechanical sweeps automatically offload to the local 2-tier hardware coprocessor pipeline (`local-offload` MCP server + `log-triage` and `repo-scout` subagents):

- **Tier 1 — Always-On Zero-VRAM CPU (`127.0.0.1:9379`)**:
  - `local-embed-cpu` (`nomic-embed-text`, 0 MB VRAM) + `repo-scout`: Activated during `/cadence-triage` and `/cadence-spec` to run semantic duplicate detection, search `production-insights.md` / `intent-insights.md`, and locate codebase symbols without bloating the primary model's context window.
  - `local-fast-cpu` (`gemma-4-e2b-it`, 128MB 3D V-Cache, 0 MB VRAM) + `log-triage` (`offload_log_triage`): Activated during `/cadence-implement` TDD loops and CI verification to compact verbose test runner and compiler logs into verbatim failure lines, `file:line` coordinates, and coverage metrics while preserving the full raw log at `/tmp/agy-last-triage.log`.
- **Tier 2 — On-Demand Hybrid MoE & GPU (`127.0.0.1:9380`)**:
  - `local-moe-hybrid` (`gemma-4-26b-a4b-it`) & `local-12b-gpu` (`gemma-4-12b-it` on RTX 5070 Ti 12GB VRAM) via `offload_deep_review`: Activated during `/cadence-review` and `/cadence-maintain` for advisory pre-review sweeps checking Pillar 3 (`<400`-line file ceiling), comment discipline, and CHORD observability seam completeness before Gemini 4 Argon (`pro`) issues gate verdicts.

All local coprocessor models run with `enable_write_tools: false` and never modify repository files.

---

## `/cadence-adopt <target-repo-root>`

Provision the CADENCE framework file set into a target repository. Wraps the canonical adoption script and never overwrites a file that already exists in the target tree. Run this command first when bootstrapping a repository into CADENCE — every downstream skill requires an adopted repository structure.

```
/cadence-adopt /path/to/your-repo
```

**CLI fallback (when your coding tool has not yet loaded the skill tree):** execute `scripts/adopt-cadence.sh <target>` from a local framework checkout — the skill wraps the exact same script.

**Outputs:** Per-file `copied: <path>` and `skip (exists): <path>` audit lines followed by `Done: N copied, M skipped (already present).` All framework artifacts are installed at their canonical paths in the target repository.

## `/cadence-upgrade <new-version>`

Merge a newer CADENCE core release into an adopter's customized repository tree, using the PI-021 `.cadence-version` stamp as the 3-way merge base. Clean hunks apply automatically and are reported; conflicting files surface for human resolution (never a silent overwrite); application is atomic; and `.cadence-version` advances only when the entire upgrade applies cleanly.

```
/cadence-upgrade 3.8.0
/cadence-upgrade 3.8.0 --dry-run
```

**`--dry-run` (preview mode, recommended):** computes the full 3-way merge in memory and prints the summary — total files in scope, clean auto-apply count, conflict count, and conflicting file paths — to stdout while **writing nothing** (no `.cadence-version` change, no staging directory, no footprint update, and no working-tree edits). Exits **0** when the upgrade would apply cleanly and **non-zero** when conflicts would occur.

**Pre-PI-021 adopters (no installed upgrade command tree yet):** a repository adopted prior to the `.cadence-version` stamp does not yet have `.agents/skills/cadence-upgrade/` installed. Invoke the upgrade engine directly from a local **core checkout** of the framework, pointing `UPGRADE_TARGET` at the adopter repository:

```
UPGRADE_TARGET=<adopter-repo> bash <core>/artifacts/commands/cadence-upgrade/upgrade-cadence.sh <new-version>
```

The engine first executes the Step-0 footprint check. When the `artifacts/footprint.generated` boundary manifest is missing, it halts before touching `.cadence-version` and prints the Step-0 auto-generation command: `AUTOGEN_CONFIRM=1 UPGRADE_TARGET=<repo> UPGRADE_CORE=<core> bash <core>/artifacts/commands/cadence-upgrade/upgrade-cadence.sh --autogen-footprint` (which derives the footprint atomically from the core checkout). Once `footprint.generated` exists, re-run the upgrade command (optionally with `--dry-run` first). See `.agents/skills/cadence-upgrade/SKILL.md` for full details.

**CLI fallback:** run `.agents/skills/cadence-upgrade/upgrade-cadence.sh <new-version>` directly.

## `/cadence-triage [--file-only] [ticket-id | draft-path | problem description]`

Classify an incoming issue, scan the codebase and insight registers (`repo-scout` / `local_semantic_embed`) for related work or duplicates, assign type/priority/scope/tier, and initialize the specification stub.

```
/cadence-triage TT-1234
/cadence-triage "Users report 500 error when activating campaigns with no bundles"
```

**Outputs:** `specs/{ticket-id}/problem.md`, `specs/{ticket-id}/metadata.yaml`

**`--file-only` — file a ticket stub without classifying it.** Passing `--file-only` switches `/cadence-triage` into intake-filing mode: it allocates an identifier through `CADENCE_ORG.md#id-allocation-binding`, **always** writes both `problem.md` and `metadata.yaml` in that same atomic operation, and skips classification entirely — no subagent delegation, no duplicate scan, no type/priority/scope assignment, and **no tier** (`tier: ""`). Use this whenever the operator asks to "file an issue for X" and immediate classification would be premature; run `/cadence-triage <id>` later to classify. Without `--file-only`, standard triage runs as normal.

```
/cadence-triage --file-only specs/drafts/expired-coupons.md
```

**Always prefer the `<draft-path>` form above (BTG-281).** Write the problem description to a file first (for example under `specs/drafts/`), then pass the file path as a single bare token. Multi-word free text passed inline on a skill argument channel can be truncated or split by the runtime; a mangled *file path* fails to open immediately and halts without burning an allocated ID, whereas a truncated inline string would silently file a malformed ticket.

**The inline free-text form is DEPRECATED** and sunsets in **2 release cycles**; it remains functional during the deprecation window and emits a warning. See [`docs/migrations/triage-file-only-draft-path.md`](../migrations/triage-file-only-draft-path.md).

```
/cadence-triage --file-only "checkout total ignores expired coupons"   # deprecated
```

**Outputs (`--file-only`):** `specs/{ticket-id}/problem.md` (recording the draft text verbatim at Status `Draft` with all probe questions left `_(not yet answered)_`) and `specs/{ticket-id}/metadata.yaml` with **`status: draft`** and **`tier: ""`**. Downstream skills fail closed on an empty tier until `/cadence-triage <id>` classifies the ticket. When a tracker is bound, the filed stub is projected immediately; when `#tracker-binding` resolves to `None — inner-source`, the skip is reported explicitly.

## `/cadence-elicit <ticket-id>`

Guide a human stakeholder through unanswered probe questions in `specs/{ticket-id}/problem.md` and append their verbatim responses under a structured `## Elicited Intent` section. Run this after `/cadence-triage` whenever probe questions in `problem.md` remain marked `_(not yet answered)_`.

This skill is **tier-gated**: it executes only on Medium or High tier tickets and refuses Trivial or Low tier work (reading `tier` from `specs/{ticket-id}/metadata.yaml` without altering it). It enforces a **hard ceiling of 7 probes** per invocation (the standard `problem.md` template includes 5 probes; the remaining 2 slots provide forward-compatibility headroom rather than ad-hoc follow-up generation). See `docs/policies/change-tiers.md`.

If `## Elicited Intent` already exists in `problem.md`, the skill displays a summary and requests explicit confirmation before replacing it.

```
/cadence-elicit PI-005
```

**Outputs:** Appended (or confirmed replacement) `## Elicited Intent` section in `specs/{ticket-id}/problem.md` recording the stakeholder's verbatim answers and provenance timestamp.

## `/cadence-spec [ticket-id]`

Author a complete architectural specification and BDD test plan from a triaged ticket. Requires `specs/{ticket-id}/problem.md` and `specs/{ticket-id}/metadata.yaml` to exist.

For Medium and High tier tickets, `/cadence-spec` executes an **independent design-exploration pre-step** prior to authoring `spec.md`: the skill delegates first to `cadence-explorer`, which produces 2–3 structurally distinct, individually steelmanned architectural options in `design-options.md` without ranking or recommending a winner. Next, `cadence-spec-author` grounds the domain via the Contextual Grounding Matrix (6W×4L) and CHORD decomposition, converges against the explorer's option set, and records the winning option and trade-off axis in `spec.md`'s `## Design Exploration` section. Because `cadence-explorer` is invoked by the orchestrating skill rather than called by `cadence-spec-author`, option generation and option selection are structurally separated. Low and Trivial tier tickets stop at Step 0 and bypass full spec generation.

```
/cadence-spec TT-1234
```

**Outputs:** `specs/{ticket-id}/design-options.md` (Medium/High tier), `specs/{ticket-id}/spec.md`, `specs/{ticket-id}/test-plan.md`, and `specs/{ticket-id}/decisions.md`.

## `/cadence-implement [ticket-id]`

Execute a ticket's approved tier contract using strict BDD red-green-refactor TDD — one Gherkin scenario per commit cycle, database migrations via expand/contract, and journey invariant tests under chaos profiles. Delegates to `cadence-implementer`, which works sequentially through the Implementation Order (from `test-plan.md` at Medium/High tier, or derived from `problem.md` acceptance criteria at Low tier) in red-green-accumulate-commit loops while using `offload_log_triage` / `log-triage` on `:9379` to compact test output.

```
/cadence-implement TT-1234
```

**Prerequisite:** For Medium/High tier tickets, the specification must exist and hold human Gate 1 approval (`metadata.yaml` has `status: spec-approved` and all required Gate 1 rulings recorded in `decisions.md`). The skill refuses to bypass this gate.

**Outputs:** Feature branch containing one atomic commit per red-green scenario cycle, a 100% passing test suite, cross-boundary documentation, a drafted `specs/{ticket-id}/submission.md`, and `metadata.yaml` advanced to `status: in-review`.

## `/cadence-review [MR number or branch name]`

Review a submitted change proposal against its governing tier contract (`spec.md` + `test-plan.md` at Medium/High tier, or `problem.md` acceptance criteria at Low tier). Runs an advisory local pre-review sweep (`offload_deep_review` on `:9380`) followed by `cadence-reviewer`, verifying acceptance criteria implementation, BDD test coverage, CADENCE Engineering Pillar compliance, architecture boundaries, and security posture, and applying the two-axis adversarial review lens: *verify-the-claim* (checking every safety assumption against authoritative seed/config/code sources) and *locate-the-failure* (probing inside the diff, in consumed code, in callers, and in unchanged sibling code whose assumptions were invalidated), plus silent-failure probes (silent fallbacks, broad catch blocks, multi-writer invariant gaps, state reuse across transitions, fake blind spots, and environment asset parity).

```
/cadence-review 142
/cadence-review impl/feature/ORD-40
```

**Outputs:** Structured review report in `submission.md` (and on the forge MR/PR) with overall verdict, AC verification table, pillar compliance audit, and inline `[BLOCKING]` / `[SUGGESTION]` / `[QUESTION]` findings.

## `/cadence-maintain [MR number or branch name]`

Evaluate a change proposal at Gate 3 (Maintainer Acceptance) after Gate 2 code review has passed. `cadence-maintainer` assesses eight project-level dimensions — surface compatibility, architectural integrity, `PROJECT_INTENT.md` charter alignment, ongoing maintenance cost, security boundary impact, release readiness, dependency health, and system documentation currency — presents the structured evaluation, and prompts the human maintainer for a final verdict (`Accept`, `Postpone`, or `Reject`).

```
/cadence-maintain 142
/cadence-maintain impl/feature/ORD-40
```

**Prerequisite:** Gate 2 code review (`/cadence-review`) must be completed first.

**Outputs:** 8-dimension maintainer assessment, follow-up candidate dispositions recorded in `submission.md`, and (upon `Accept`) updated metadata, changelog, and surface-registry / deprecation records.

## `/cadence-migrate [ticket-id] [--contract]`

Author EF Core database migrations following the expand/contract discipline. Defaults to `expand` mode (strictly additive changes shipped alongside the feature). Pass `--contract` in a follow-up ticket/MR to remove retired schema elements once production telemetry confirms zero legacy usage.

```
/cadence-migrate TT-1234
/cadence-migrate TT-1234 --contract
```

**Prerequisite:** Domain/ORM entity class changes must be present before running in `expand` mode.

**Outputs:** Reversible, idempotent migration files in the project's migrations directory, verified via a local `apply → rollback → reapply` cycle. `cadence-migration-author` discovers the repository's `DbContext`, migrations path, startup project, and database provider automatically.

## `/cadence-archive [ticket-id]`

Enshrine a merged ticket into the permanent repository archive. Delegates to `cadence-archivist`, which finalizes `submission.md`, moves `specs/{ticket-id}/` to `archive/{ticket-id}/`, **dispositions every inbound citation of the moved `specs/{ticket-id}/` path (blocking — see below)**, compiles `summary.md` with cycle metrics, updates `CHANGELOG.md`, promotes architectural decisions to `docs/ADR/` and intent discoveries to `docs/agentic-sdlc/intent-insights.md`, syncs the bound tracker (`CADENCE_ORG.md#tracker-binding`), and cleans up the merged feature branch.

```
/cadence-archive TT-1234
```

**Prerequisite:** The change proposal must be merged (`metadata.yaml` shows `status: merged`, or the merge commit is reachable on the integration branch resolved from `CADENCE_ORG.md#branch-strategy-binding` — ADR_CADENCE-0020; never hardcode a branch name).

**Blocking citation sweeps (BTG-083 / PROD_CADENCE-009, BTG-133 / PROD_CADENCE-015):** moving `specs/{ticket-id}/` to `archive/{ticket-id}/` turns any remaining reference to `specs/{ticket-id}/` into a broken link, so after moving the directory the archivist runs `ci-templates/scripts/dead-citation-gate.sh --id {ticket-id}` (step 2b). Because step 2 also writes **newly promoted files** (ADRs and intent-insight entries) that may cite a *different*, previously archived ticket's `specs/` path, a single-ticket scan cannot catch those cross-ticket references. Therefore, once step 2b exits 0, the archivist immediately runs `ci-templates/scripts/dead-citation-gate.sh --except-id {ticket-id}` (step 2c) to sweep every archived ticket ID except the current one. **One shared classifier, three call sites** — the `dead-citation` CI gate, step 2b, and step 2c. Every reported hit from either step requires an explicit disposition: **REPOINT** (the default; updating the link to the target ticket's `archive/` path) or **EXEMPT** (an allowlist entry recording the exemption class and rationale). Any hit flagged `NOT-A-COMMENT` is executable code and must be dispositioned individually; nothing is silently rewritten, and `--emit-baseline` is never used to suppress a hit. **Archival cannot complete while any citation hit from step 2b or 2c remains undispositioned.**

**Behavior when the classifier script is absent (BTG-099):** both steps first check that `ci-templates/scripts/dead-citation-gate.sh` exists **and is non-empty** (since a zero-byte file would exit 0 and masquerade as a clean sweep). If the script is not installed, archival neither halts nor silently skips: it emits an explicit notice naming the missing gate and PROD_CADENCE-009 risk, offers an optional manual fallback, records `DEAD-CITATION-SWEEP: SKIPPED` or `DEAD-CITATION-SWEEP: MANUAL` in `summary.md`, and proceeds. An installed classifier exiting with status **2** (setup failure) **halts** immediately.

**Outputs:** Enshrined artifacts under `archive/{ticket-id}/` including `summary.md` (with its *Citation Dispositions* table), updated `CHANGELOG.md`, `metadata.yaml` set to `status: archived`, and any proposed updates to `docs/flows/` or `docs/SYSTEM_OVERVIEW.md`.

---

## `/cadence-sync-jira [ticket-id | all]`

Project specification metadata, lifecycle status, and stage-effort worklogs from the repository to on-prem Jira Server/DC. Strictly one-directional: the Git repository is the source of truth.

```
/cadence-sync-jira TT-1234
/cadence-sync-jira all
```

---

## `/cadence-bump-model <from-model> <to-model>`

Update the concrete model identifier across agent YAML frontmatter (`.agents/agents/*/AGENT.md` and `artifacts/roles/*/ROLE.md`) AND the Concrete Model column of `CADENCE_ORG.md#model-tier-mapping` within a single capability tier. Displays a confirmation diff before applying changes and verifies consistency afterward.

**Scope:** Modifies only `model:` declarations in agent frontmatter and the matching tier row in `CADENCE_ORG.md#model-tier-mapping`. Does not alter prose documentation, CI scripts, or external routing. Operates on one capability tier per invocation — moving an agent between capability tiers is an architectural change requiring a specification.

**Outputs:** Preview diff across all targets, operator confirmation prompt, and post-apply verification. Review with `git diff` and commit via the standard worktree PR workflow.

### Example (Gemini / Antigravity Runtime)

```
/cadence-bump-model gemini-3.5-pro gemini-4-argon
/cadence-bump-model gemini-3.5-flash gemini-3.8-flash

/cadence-bump-model gemini-4-argon gemini-3.8-flash  # refused — cross-tier substitution
```

---

## `/cadence-release [major|minor|patch]`

Cut a governed release from the accumulated `## [Unreleased]` entries in `CHANGELOG.md`. Resolves the repository's bound versioning scheme from `CADENCE_ORG.md#version-scheme-binding`, computes the appropriate version increment under that scheme's rules (**major** for breaking surface changes or enacted deprecations; **minor** for additive capabilities, new agents/skills, or non-breaking enhancements; **patch** for bug fixes and documentation updates), presents the proposed version number and rationale, and **requests operator confirmation before modifying any file**. Passing an explicit `major|minor|patch` argument forces that bump level while still displaying the computed analysis and warning if the forced level under-bumps a breaking change.

Upon confirmation, the skill finalizes `## [Unreleased]` as `## [X.Y.Z] - <YYYY-MM-DD>`, opens a fresh empty `## [Unreleased]` section, updates the version stamp in `README.md` (and `.cadence-version` where applicable), drafts `docs/releases/vX.Y.Z.md`, creates the `RELEASE-X.Y.Z` commit and an **annotated** git tag, and prompts a second time before pushing the branch and tag to `origin`.

**Scope:** Executes inline in the main session (because it pauses for two operator confirmations). Modifies `CHANGELOG.md`, `README.md`, and `docs/releases/vX.Y.Z.md`, creating one commit and one annotated tag.

**Outputs:** Proposed version + rationale, two confirmation checkpoints (pre-edit and pre-push), the release commit, the annotated tag, and a drafted release-notes document in `docs/releases/vX.Y.Z.md`.

### Example

```
/cadence-release           # analyze Unreleased, propose bump, confirm, cut, tag, push
/cadence-release minor     # force minor bump (still displays analysis)
/cadence-release patch     # force patch — warns if Unreleased contains features or breaking changes
```
