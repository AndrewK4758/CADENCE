# cadence-v1.1.0 (2026.47.0): Consolidated Lifecycle Verbs, Offline Evals, and Neutral Globals

**Released:** 2026-11-18
**Tag:** [`cadence-v1.1.0`](https://github.com/AndrewK4758/CADENCE/releases/tag/cadence-v1.1.0) (`2026.47.0`)
**Full changelog:** [`CHANGELOG.md` § [2026.47.0]](../../CHANGELOG.md)

## TL;DR

This release advances CADENCE from `cadence-v1.0.0` to `2026.47.0` (`cadence-v1.1.0`), consolidating multi-step workflows into five high-level lifecycle commands while completing local `:11434` offload reliability, offline skill evaluations, and clean separation of global agent tooling from repository-scoped governance. Highlights:

1. **Consolidated lifecycle verbs**: `/cadence-onboard`, `/cadence-define`, `/cadence-build`, `/cadence-close`, and `/cadence-housekeep` (replacing earlier `cadence-prep` and `cadence-cycle` names).
2. **Expanded skill, audit, and traceability gates**: `/cadence-doctor`, `/cadence-eject`, `/cadence-merge`, `/cadence-propose`, `/cadence-refactor`, `/cadence-retro`, `cadence-security-auditor`, and `verify-facts --trace`.
3. **Offline deterministic evals and regression harness**: Full `tests/run-cadence-tests.sh` (`T1a`–`T8`) and `tests/run-evals.sh` contract coverage across all 28 skills.
4. **Hardened local offload (`:11434`) and neutral globals**: Inline Turn 0/1 MCP schemas, AST-aligned slices, per-PID log triage, and strict isolation of global hooks/subagents from repository-scoped CADENCE machinery.

This release follows the **`calver-yyyy-ww`** scheme (`2026.47.0`). For adopters still referencing earlier `cadence-prep` or `cadence-cycle` skill names, upgrade cleanly using `skills/cadence-upgrade/upgrade-removals.sh`.

---

## What's new

### Consolidated 4-stage lifecycle verbs

**Commit:** [`7e543a7`](https://github.com/AndrewK4758/CADENCE/commit/7e543a7) · **Surfaces:** `skills/cadence-{onboard,define,build,close,housekeep}/`, `skills/cadence-upgrade/upgrade-removals.sh`, `processes/`

Five composite orchestrator skills unify onboarding, specification definition, TDD build + review loops, merge + tracker + archive closeout, and repository housekeeping. The interim `cadence-prep` and `cadence-cycle` identifiers were renamed in-place to `cadence-define` and `cadence-build` across skills, directives, upgrade removal lists, and test harnesses.

### Security auditor, spec traceability, and offline evals

**Commits:** `0cbf3b7`, `aa4545c`, `cf3adab`, `9478ab2`, `addcd51` · **Surfaces:** `agents/cadence-security-auditor/`, `skills/cadence-review/security-trigger.sh`, `skills/cadence-spec/`, `skills/cadence-retro/`, `tests/`

Added deterministic AC-to-code/test tracing via `verify-facts --trace`, hybrid `cadence-security-auditor` triggering in code review, cross-ticket synthesis via `/cadence-retro`, and offline contract evals (`tests/run-evals.sh`) integrated into the regression suite (`tests/run-cadence-tests.sh`).

### Provider-neutral tiers and framework-neutral global setup

**Commits:** `b0f4ecb`, `db88e04`, `fb93ebc`, `b4228da` · **Surfaces:** `agents/`, `skills/`, `hooks/hooks.global.json`, `import/link-sdlc.sh`

Replaced provider-specific model references with neutral capability tiers and `xhigh` implementation/architecture effort settings, and updated `hooks/hooks.global.json` and `import/link-sdlc.sh --global` so global configuration installs only neutral offload hooks, `repo-scout`, and `log-triage`.

### Local coprocessor offload stack (`:11434`) & Blitz adapter

**Commits:** `8654f72`..`3435409` · **Surfaces:** `local-offload/`, `agents/{repo-scout,log-triage}/`, `hooks/`, `import/`

Added `local-offload` FastMCP server support, Blitz strict-frontmatter compatibility and skill symlink discovery, bounded inline payloads (`<3.9KB`), per-PID triage logs, C#/Kotlin/dotdir semantic indexing, thread-safe HTTP pooling, and `llama-swap` configuration sync.

---

## Breaking changes

- **`cadence-prep` -> `cadence-define` and `cadence-cycle` -> `cadence-build`:** Interim skill names introduced during the initial consolidation commit were renamed to `cadence-define` and `cadence-build`; `skills/cadence-upgrade/upgrade-removals.sh` removes the deprecated paths during upgrades.
- **Neutral global `--global` links:** `import/link-sdlc.sh --global` now links only neutral offload coprocessors and hooks into user home directories; CADENCE governance skills and agents are projected per repository via `cadence-adopt` / `import/link-sdlc.sh`.

---

## Upgrade notes for existing adopters

- Upgrade adopted repositories with `/cadence-upgrade` (`skills/cadence-upgrade/upgrade-cadence.sh`), running `--dry-run` first to inspect 3-way merges and deprecated path cleanups.
- Re-run `import/link-sdlc.sh --global` if updating user-level global symlinks so only neutral `local-offload` hooks, `repo-scout`, and `log-triage` are registered globally.
- Verify repository health after upgrading with `/cadence-doctor` (`skills/cadence-doctor/doctor.sh --check-offload`).
