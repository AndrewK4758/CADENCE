# Skills (Slash Commands)

Slash commands in `.agents/skills/` (projected to `.gemini/skills/` or `.claude/skills/` per `docs/policies/cli-runtime-adoption-policy.md`) provide the primary operator interface for the CADENCE agentic SDLC. Invoke them directly in your agentic coding runtime (reference runtime: Google Antigravity / Gemini CLI).

---

## Automatic Local Hardware Coprocessor Offload Across Commands (Optional, Cloud-Only Fallback)

When the optional local hardware coprocessor pipeline (`local-offload` MCP server on `127.0.0.1:11434` + `log-triage` and `repo-scout` subagents) is available, read-only discovery, test/build log compaction, and pre-review mechanical sweeps offload automatically; when `:11434` is unavailable, skills degrade cleanly to cloud-only execution:

- **Semantic Discovery (`embedding` on `127.0.0.1:11434`)**:
  - `embedding` (`embeddinggemma-2`) + `local_semantic_embed`: Activated during `/cadence-propose`, `/cadence-triage`, `/cadence-spec`, `/cadence-archive`, and `/cadence-retro` to run semantic duplicate detection, search `production-insights.md` / `intent-insights.md`, cluster cross-ticket patterns, and locate codebase symbols without bloating the primary model's context window.
- **On-Demand Inference (`inference` on `127.0.0.1:11434`)**:
  - `inference` via `offload_log_triage` / `log-triage` and `repo-scout`: Activated during `/cadence-implement`, `/cadence-refactor`, `/cadence-merge`, and `/cadence-doctor` to compact verbose test runner and compiler logs into verbatim failure lines, `file:line` coordinates, and coverage metrics while preserving the full raw log at `/tmp/agy-last-triage.log`.
  - `inference` via `offload_deep_review`: Activated during `/cadence-review` and `/cadence-maintain` for advisory pre-review sweeps checking Pillar 3 (`<400`-line file ceiling), comment discipline, and CHORD observability seam completeness before the `Deep-reasoning` tier (`xhigh` effort) issues gate verdicts.

All local coprocessor models run with `enable_write_tools: false` and never modify repository files.

---

## `/cadence-adopt <target-repo-root>`

Provision the CADENCE framework file set into a target repository. Wraps the canonical adoption script and never overwrites a file that already exists in the target tree. Run this command first when bootstrapping a repository into CADENCE — every downstream skill requires an adopted repository structure.

```
/cadence-adopt /path/to/your-repo
```

**CLI fallback (when your coding tool has not yet loaded the skill tree):** execute `.agents/skills/cadence-adopt/adopt-cadence.sh <target>` (or `skills/cadence-adopt/adopt-cadence.sh <target>` from a core checkout).

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
UPGRADE_TARGET=<adopter-repo> bash <core>/skills/cadence-upgrade/upgrade-cadence.sh <new-version>
```

The engine first executes the Step-0 footprint check. When the `artifacts/footprint.generated` boundary manifest is missing, it halts before touching `.cadence-version` and prints the Step-0 auto-generation command: `AUTOGEN_CONFIRM=1 UPGRADE_TARGET=<repo> UPGRADE_CORE=<core> bash <core>/skills/cadence-upgrade/upgrade-cadence.sh --autogen-footprint` (which derives the footprint atomically from the core checkout). Once `footprint.generated` exists, re-run the upgrade command (optionally with `--dry-run` first). See `.agents/skills/cadence-upgrade/SKILL.md` for full details.

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

This skill is **tier-gated**: it executes only on Medium or High tier tickets and refuses Trivial or Low tier work (reading `tier` from `specs/{ticket-id}/metadata.yaml` without altering it). It enforces a **hard ceiling of 7 probes** per invocation (the standard `problem.md` template includes 5 fixed probes in slots 1–5; slots 6–7 hold optional adaptive follow-up questions tailored to critical ambiguities). See `docs/policies/change-tiers.md`.

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

Execute a ticket's approved tier contract using strict BDD red-green-refactor TDD — one Gherkin scenario per commit cycle, database migrations via expand/contract, and journey invariant tests under chaos profiles. Delegates to `cadence-implementer`, which works sequentially through the Implementation Order (from `test-plan.md` at Medium/High tier, or derived from `problem.md` acceptance criteria at Low tier) in red-green-accumulate-commit loops while using `offload_log_triage` / `log-triage` on `:11434` to compact test output and gating transition on `verify-facts.sh --trace` plus `offload_deep_review`.

```
/cadence-implement TT-1234
```

**Prerequisite:** For Medium/High tier tickets, the specification must exist and hold human Gate 1 approval (`metadata.yaml` has `status: spec-approved` and all required Gate 1 rulings recorded in `decisions.md`). The skill refuses to bypass this gate.

**Outputs:** Feature branch containing one atomic commit per red-green scenario cycle, a 100% passing test suite, cross-boundary documentation, a drafted `specs/{ticket-id}/submission.md`, and `metadata.yaml` advanced to `status: in-review`.

## `/cadence-review [MR number or branch name]`

Review a submitted change proposal against its governing tier contract (`spec.md` + `test-plan.md` at Medium/High tier, or `problem.md` acceptance criteria at Low tier). Runs an advisory local pre-review sweep (`offload_deep_review` on `:11434`), mechanical spec/AC traceability (`verify-facts.sh --trace`), and `security-trigger.sh`, followed by `cadence-reviewer` (plus `cadence-security-auditor` at `xhigh` effort when `High` tier or security/concurrency signals trigger), verifying acceptance criteria implementation, BDD test coverage, CADENCE Engineering Pillar compliance, architecture boundaries, and security posture, and applying the two-axis adversarial review lens: *verify-the-claim* (checking every safety assumption against authoritative seed/config/code sources) and *locate-the-failure* (probing inside the diff, in consumed code, in callers, and in unchanged sibling code whose assumptions were invalidated), plus silent-failure probes (silent fallbacks, broad catch blocks, multi-writer invariant gaps, state reuse across transitions, fake blind spots, and environment asset parity).

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

Author reversible, idempotent schema and data migrations across stacks following the expand/contract discipline. Defaults to `expand` mode (strictly additive changes shipped alongside the feature, invoked after entity/model and interim compatibility code changes are committed). Pass `--contract` in a follow-up ticket/MR to remove retired schema elements once production telemetry confirms zero legacy usage.

```
/cadence-migrate TT-1234
/cadence-migrate TT-1234 --contract
```

**Prerequisite:** Domain/ORM/schema model changes (plus Phase 2.25 interim compatibility code where needed) must be committed before running in `expand` mode.

**Outputs:** Reversible, idempotent migration files in the project's migrations directory, verified via a local `apply → rollback → reapply` cycle. `cadence-migration-author` discovers the repository's ORM/migration framework, migrations path, and database provider automatically (see `docs/guides/ef-migration-examples.md` for .NET examples).

## `/cadence-archive [ticket-id]`

Enshrine a merged ticket into the permanent repository archive. `/cadence-archive` executes pre- and post-relocation `dead-citation-gate.sh` sweeps, delegates artifact relocation (`specs/{ticket-id}/` to `archive/{ticket-id}/`), `summary.md` generation (including `merged_at` backfill if unset), `CHANGELOG.md` updates, `production-insights.md` (`Closed by:`), and ADR/insight promotion to `cadence-archivist`, and invokes the bound external tracker sync skill (`CADENCE_ORG.md#tracker-binding`) once `cadence-archivist` returns.

```
/cadence-archive TT-1234
```

**Prerequisite:** The change proposal must be merged (`metadata.yaml` shows `status: merged`, or the merge commit is reachable on the integration branch resolved from `CADENCE_ORG.md#branch-strategy-binding` — ADR_CADENCE-0020; never hardcode a branch name).

**Blocking citation sweeps (BTG-083 / PROD_CADENCE-009, BTG-133 / PROD_CADENCE-015):** moving `specs/{ticket-id}/` to `archive/{ticket-id}/` turns any remaining reference to `specs/{ticket-id}/` into a broken link, so after moving the directory the archivist runs `ci-templates/scripts/dead-citation-gate.sh --id {ticket-id}` (step 2b). Because step 2 also writes **newly promoted files** (ADRs and intent-insight entries) that may cite a *different*, previously archived ticket's `specs/` path, a single-ticket scan cannot catch those cross-ticket references. Therefore, once step 2b exits 0, the archivist immediately runs `ci-templates/scripts/dead-citation-gate.sh --except-id {ticket-id}` (step 2c) to sweep every archived ticket ID except the current one. **One shared classifier, three call sites** — the `dead-citation` CI gate, step 2b, and step 2c. Every reported hit from either step requires an explicit disposition: **REPOINT** (the default; updating the link to the target ticket's `archive/` path) or **EXEMPT** (an allowlist entry recording the exemption class and rationale). Any hit flagged `NOT-A-COMMENT` is executable code and must be dispositioned individually; nothing is silently rewritten, and `--emit-baseline` is never used to suppress a hit. **Archival cannot complete while any citation hit from step 2b or 2c remains undispositioned.**

**Behavior when the classifier script is absent (BTG-099):** both steps first check that `ci-templates/scripts/dead-citation-gate.sh` exists **and is non-empty** (since a zero-byte file would exit 0 and masquerade as a clean sweep). If the script is not installed, archival neither halts nor silently skips: it emits an explicit notice naming the missing gate and PROD_CADENCE-009 risk, offers an optional manual fallback, records `DEAD-CITATION-SWEEP: SKIPPED` or `DEAD-CITATION-SWEEP: MANUAL` in `summary.md`, and proceeds. An installed classifier exiting with status **2** (setup failure) **halts** immediately.

**Outputs:** Enshrined artifacts under `archive/{ticket-id}/` including `summary.md` (with its *Citation Dispositions* table), updated `CHANGELOG.md`, `metadata.yaml` set to `status: archived`, and any proposed updates to `docs/flows/` or `docs/SYSTEM_OVERVIEW.md`.

---

## `/cadence-retro [--since <N|YYYY-MM-DD>] [--include-active] [--promote]`

Synthesize cross-ticket metrics and recurring failure patterns across `archive/*/` via `.agents/skills/cadence-retro/retro_scan.py` and `:11434` semantic clustering (`local_semantic_embed`). Default execution is strictly read-only, reporting tier distribution, recorded `stage_effort` variance, multi-cycle code-review rework hotspots, `Deferred` follow-ups, unguarded citation sweeps, and deduplicated `II-NNN` / `PROD-NNN` insight candidates; promotions run only after explicit operator confirmation using atomic `mint-id.sh --reserve`.

---

## `/cadence-sync-jira [ticket-id | all]`

Project specification metadata, lifecycle status, and stage-effort worklogs from the repository to on-prem Jira Server/DC. Strictly one-directional: the Git repository is the source of truth.

```
/cadence-sync-jira TT-1234
/cadence-sync-jira all
```

---

## `/cadence-bump-model <from-model> <to-model>`

Update the concrete model identifier across matching-tier agent YAML frontmatter (`.agents/agents/*/agent.md` `default_model`), runtime adapters (`ci-templates/scripts/adapters/`), AND the Concrete Model column of `CADENCE_ORG.md#model-tier-mapping` within a single capability tier. Displays a confirmation diff before applying changes and verifies consistency afterward.

**Scope:** Modifies only concrete model declarations for agents belonging to the single matched capability tier in `CADENCE_ORG.md#model-tier-mapping` and runtime adapters (never substituting across tiers even when two tiers temporarily share an alias). Does not alter prose documentation or external routing. Operates on one capability tier per invocation — moving an agent between capability tiers is an architectural change requiring a specification.

**Outputs:** Preview diff across all tier-matched targets, operator confirmation prompt, symlink/adapter verification, and post-apply grep verification. Review with `git diff` and commit via the standard worktree PR workflow.

### Examples (Per-Runtime Substitution)

```text
/cadence-bump-model gemini-4-argon gemini-4-hydrogen      # Gemini runtime: Deep-reasoning bump
/cadence-bump-model claude-opus-5-0 claude-opus-5-5       # Claude runtime: Deep-reasoning bump
/cadence-bump-model gemini-4-hydrogen gemini-3.8-flash    # refused — cross-tier substitution
```

---

## `/cadence-release [<bump-arg>]`

Cut a governed release from the accumulated `## [Unreleased]` entries in `CHANGELOG.md`. Resolves the repository's bound versioning scheme from `CADENCE_ORG.md#version-scheme-binding` (`calver-yyyy-ww` default or `semver`), computes the next version increment (`YYYY.WW.N` under CalVer; `major|minor|patch` under SemVer), presents the proposed version number and rationale, and **requests confirmation (Gate A) before modifying any file or opening the release PR**. Passing an explicit override argument (`YYYY.WW.N` or `major|minor|patch`) forces that version/bump while still displaying the computed analysis and warning if it conflicts with detected changelog entries.

Upon Gate A confirmation, the skill finalizes `## [Unreleased]` as `## [<version>] - <YYYY-MM-DD>`, opens a fresh empty `## [Unreleased]` section, updates the version stamp in `.cadence-version` and `README.md`, drafts `docs/releases/v<version>.md` and `specs/RELEASE-<version>/submission.md`, and commits & opens the release PR. Once merged to the integration branch, Gate B prompts before creating and pushing the **annotated** `v<version>` git tag.

**Scope:** Executes inline in the main session (two explicit confirmation gates). Modifies `CHANGELOG.md`, `README.md`, `.cadence-version`, `docs/releases/v<version>.md`, and `specs/RELEASE-<version>/submission.md`, creating one release PR commit and one annotated tag.

**Outputs:** Proposed version + rationale, Gate A pre-edit/PR confirmation, Gate B post-merge annotated-tag confirmation, release-notes document in `docs/releases/v<version>.md`, and `specs/RELEASE-<version>/submission.md`.

### Example

```
/cadence-release           # analyze Unreleased, propose bump per bound scheme, confirm Gate A, open PR, confirm Gate B, tag
/cadence-release minor     # SemVer repo: force minor bump (displays analysis)
/cadence-release patch     # warn if Unreleased contains features or breaking changes
```

---

## `/cadence-propose "<summary>"`

Mechanize Workflow Step 00 (Problem) before IDs are allocated: validates fit against `PROJECT_INTENT.md` and registered surface registries, runs optional `local_semantic_embed` (`:11434`, cloud-only fallback when absent) to surface duplicate tickets or prior `PROD-*`/`II-*` insights, writes a concise 3–5 sentence 4-part outcome proposal (`Problem`, `Proposed approach`, `Surfaces affected`, `Ask`) into `specs/drafts/<slug>.md`, and hands off to `/cadence-triage --file-only specs/drafts/<slug>.md` (or full `/cadence-triage`).

## `/cadence-refactor "<transform-spec>" [scope]`

Execute wide, deterministic, behavior-preserving refactors inside a dedicated worktree under `Fast-mechanical` (`high` effort) over an exhaustive pre-computed manifest (`local_semantic_embed` + `rg` + dual `docs/` searches), halting and escalating to `/cadence-spec` (`Deep-reasoning`, `xhigh`) if registered surfaces, schemas, or behavioral contracts would change, and running canonical tests + optional `offload_deep_review` (`:11434`) post-sweep.

## `/cadence-merge <ticket-id> [--no-archive]`

Mechanize Workflow Step 07 (Merge): checks tier-conditional Gate 2 / Gate 3 approval (`maintainer_approved_at` for Medium/High; Gate 2 only for Low), resolves the integration branch dynamically from `CADENCE_ORG.md#branch-strategy-binding`, rebases cleanly and re-runs verification (re-running `/cadence-review` whenever code/test conflicts are resolved or upstream changes touch the diff's bounded context), merges via forge PR without `--no-verify`, fast-forwards local integration branch (`git pull --ff-only`, zero direct commits on protected integration branches), syncs `merged` to the bound tracker, prunes temporary worktree state, and hands off to `/cadence-archive` (which persists `merged_at` if unset alongside `status: archived` on `archive/{type}/{id}`) unless `--no-archive` is passed.

## `/cadence-doctor [--ticket <id>] [--check-offload] [--full]`

Run a strictly read-only repository audit via `.agents/skills/cadence-doctor/doctor.sh`: verifies linkage, `#*-binding` markers, `<400`-line file ceilings, eject footprint freshness, `mint-id.sh --peek`, installed governance gates (never silently passing 0-byte scripts), optional ticket checks (`verify-spec.sh`, `verify-facts.sh --rulings/--trace`, `ac-classify.sh`, `certainty-gate.sh`), and optional `:11434` offload reachability.

## `/cadence-certainty <ticket-id> [--stage auto|spec|implement|review] [--base <ref>] [--require-evidence]`

Run the deterministic hybrid empirical certainty gate (`.agents/skills/cadence-certainty/certainty-gate.sh`) across Layer 1 zero-schema checks (unanswered probes, unmapped `UNKNOWN`s/draft contracts, undeclared diff blast radius, dormant Security/Data pillar contradictions via `security-trigger.sh`, `verify-facts.sh` `UNVERIFIABLE` ratio, and review cycle oscillation) and Layer 2 `specs/<id>/evidence.yaml` proof checks (`observed` refs/symbols/substrings, pure-Python `absence` regexes, acyclic `inferred` DAG depth `<=2`, and `HEAD`-SHA + SHA-256 test receipts). Exits `0` (`PROCEED`), `1` (`HALT` for mechanical/proof fixes), or `2` (`ESCALATE_HUMAN` pausing for targeted rulings in `decisions.md`).

## `/cadence-trainlog <status|ingest|export|tag|verify> [options]`

Inspect, backfill, confidentiality-tag, verify, and export captured CADENCE turn logs (recorded on every CADENCE repo `Stop` event by `.agents/hooks/cadence-turn-logger.sh` into external `${CADENCE_TURN_LOG_DIR:-~/.local/share/cadence-turn-logs}`, `0600` perms, opt-out `CADENCE_TURN_LOG=0`) into secret-scrubbed Open-Weight `sft`, `dpo` (`gate_failed` -> `verified_pass` pairs), or `rlvr` JSONL datasets while failing closed (`CHINESE_WALL_VIOLATION`, exit `2`) on cross-client mixing.

## `/cadence-eject <source-repo-root> <destination-dir> | --check-footprint`

Wrap `cadence-eject.sh` to validate the eject footprint descriptor read-only or export a CADENCE-stripped deliverable copy after previewing strip scope (plus BL-003 history boundary), obtaining operator confirmation, and verifying CADENCE directories are absent from `<destination-dir>`.

---

## Consolidated Stage Workflows

## `/cadence-onboard <target-repo-root> [--linked] [--gitignore-machinery] [--skip-interview]`

Onboard a repository to CADENCE end-to-end: runs `adopt-cadence.sh`, optionally links `.agents/` and `.gemini/` to canonical core via `import/link-sdlc.sh --replace` when `--linked` is passed, completes `/cadence-interview` bindings in `CADENCE_ORG.md`, and verifies repository + offload health via `/cadence-doctor --check-offload`.

## `/cadence-define [--propose] <ticket-id-or-problem>`

Advance a ticket through the entire definition phase and stop before implementation: optionally drafts Step 00 (`--propose` -> `/cadence-propose`), then chains `/cadence-triage`, `/cadence-elicit`, and `/cadence-spec`, resolves open questions / Gate 1 rulings, opens/publishes the spec-approval MR (`read_state.py` / `ready_mr.sh`), and offers an interactive opt-in `/cadence-watch` handoff prompt (`watch` / `once` / `no`).

## `/cadence-build <ticket-id> [--with-migrations] [--max-cycles 4]`

Advance an approved/triaged ticket through implementation and verification: ensures isolated worktree setup, checks `#integration-branch-enforcement` and `#sprint-enforcement-binding`, chains `/cadence-implement` (and runs `/cadence-migrate` *after* entity/interim compatibility commits when `--with-migrations` or schema/SQL specs trigger it), runs iterative `/cadence-review` + `security-trigger.sh`/`cadence-security-auditor` loops tracked via `<!-- cadence-run:cycle ... -->` markers (cycle cap `4`), readies the PR for Gate 3 or merge, and offers an interactive opt-in `/cadence-watch` handoff prompt (`watch` / `once` / `no`).

## `/cadence-close <ticket-id> [--no-archive]`

Close out a code-reviewed ticket through Gate 3 and cleanup: inspects `read_state.py`, runs tier-conditional Gate 3 `/cadence-maintain` (`Medium`/`High` when `maintainer_approved_at` is unset; skipped on `Low`/`Trivial`), lands via `/cadence-merge` + tracker sync without `--no-verify`, and chains `/cadence-archive` + post-close `doctor.sh` unless `--no-archive` is set.

## `/cadence-housekeep [--since <N>] [--include-active] [--full] [--promote] [--with-release [<bump-arg>]]`

Run repository hygiene in one command: executes read-only `/cadence-doctor --check-offload [--full]` and `/cadence-retro`, gates `--promote` (`II-*`/`PROD-*` ID minting) behind explicit operator confirmation, and gates optional `--with-release` behind a clean doctor pass and `/cadence-release` confirmations.

## `/cadence-watch [<ticket-id> | --all] [--once | --watch] [--interval <sec>] [--timeout <sec>] [--no-tracker] [--dry-run]`

Listen to open GitHub PRs (`gh`), GitLab MRs (`glab`), and bound Jira/YouTrack ticket comments (`CADENCE_ORG.md#tracker-binding`) via `.agents/skills/cadence-watch/scripts/pr_watch.py`: mirrors unseen external feedback into `specs/<id>/submission.md` `## Discussion` using write-after-completion watermarks and `<!-- cadence-watch:reply -->` loop suppression, automatically triggers `/cadence-build` when a `spec_mr` merges or post-merge tracker sync + `/cadence-archive` when a `merge_request` merges, remediates in-scope change requests or CI failures within approved scope (`offload_deep_review` / `offload_log_triage`), halts on scope/tier changes or cycle cap `>=4`, and hands `APPROVED` implementation PRs to `/cadence-close` without ever self-merging silently. PR-facing CADENCE stage commands (`/cadence-define`, `/cadence-build`, `/cadence-parallel`, `/cadence-close` on Gate 3 deferral/rejection, and standalone `/cadence-spec`, `/cadence-implement`, `/cadence-review`, `/cadence-maintain`) prompt interactively at run end whether to invoke `/cadence-watch` (`watch` / `once` / `no`) without auto-polling silently.
