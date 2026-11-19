# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow `calver-yyyy-ww` (`YYYY.WW.PATCH`, milestone tag `cadence-v1.1.0`).

## [Unreleased]

### Added

- **Pre-Gate-1 Spec Challenger & Zero-Spec Adversarial Cold Breaker:** Added strictly read-only `Deep-reasoning` (`effort: xhigh`) subagents `cadence-spec-challenger` (Pre-Gate-1 falsification at `/cadence-spec` Step 4.5) and `cadence-breaker` (zero-spec disposable `/tmp` fault-injection breaker at Gate 2 alongside `skills/cadence-review/breaker-trigger.sh`), plus `tests/test-review-hardening.sh` (`T12`) and updated evals across core workflow skills.
- **Satellite `--code-root` multi-repo scanning:** Added repeatable `--code-root <dir>` flags to `security-trigger.sh`, `breaker-trigger.sh`, and `certainty-gate.sh` (`certainty_claims.py` multi-repo diff collector) and expanded `security-trigger.sh` signals (`redact`/`scrub`/`sanitize`/`guardrail`, `AbortController`/`ioredis`/`maxRetriesPerRequest`, `docker-stack`/`swarm`).
- **Automated PR & bound-tracker listener (`/cadence-watch`):** Added `/cadence-watch` with `pr_watch.py` and `watch_sources.py` to monitor GitHub PRs, GitLab MRs, and bound Jira/YouTrack ticket comments (`--once`, `--watch`, `--all`), mirror unseen feedback into `submission.md` using write-after-completion watermarks and reply loop suppression, advance merged `spec_mr` -> `/cadence-build` and merged `merge_request` -> `/cadence-archive`, remediate in-scope change requests/CI failures, and escalate scope changes or hand approved PRs to `/cadence-close` without silent self-merge.

### Changed

- **End-to-end review hardening & Anti-Downgrade enforcement:** Updated `docs/policies/finding-classes.md` with the Anti-Downgrade & Anti-Rationalization Clause; strengthened `cadence-reviewer` (`[spec-contradicts-codebase]`, Active Mock-Blind-Spot verification, whole-lifecycle `await`/sibling sweep), `cadence-security-auditor`, `cadence-maintainer` (Gate 2 clearance + Residual & Mock-Blind-Spot Backstop), `cadence-implementer`, and `/cadence-watch`/`/cadence-review`/`/cadence-spec`/`/cadence-parallel`/`/cadence-build`/`/cadence-maintain`/`doctor.sh`.

- **Interactive `/cadence-watch` handoff prompts across PR-facing stage skills:** Added opt-in confirmation prompts (`watch` / `once` / `no`, skipped when non-interactive or invoked inside a parent orchestrator) at PR-ready boundaries in `/cadence-define`, `/cadence-build`, `/cadence-parallel`, `/cadence-close` (on Gate 3 `Postpone`/`Reject`), and standalone `/cadence-spec`, `/cadence-implement`, `/cadence-review`, and `/cadence-maintain`.
- **README cloud/hybrid deployment & AI harness offload architecture:** Clarified that CADENCE runs provider-neutrally across cloud-only, hybrid cloud + local offload, and local-only setups, marked local GPU setup steps as optional, and added a Mermaid diagram showing how AI CLI harnesses, hooks, cloud frontier models, `local-offload` FastMCP/subagents, and `llama-swap` (`:11434`) interoperate.

## [2026.47.0] - 2026-11-18

> Milestone release **`cadence-v1.1.0`**. See [cadence-v1.1.0 release notes](docs/releases/cadence-v1.1.0.md) for narrative context and upgrade notes.

### Added

- **Consolidated 4-stage lifecycle orchestrators:** Added `/cadence-onboard`, `/cadence-define`, `/cadence-build`, `/cadence-close`, and `/cadence-housekeep` (replacing earlier `cadence-prep` and `cadence-cycle` names) to chain multi-step intake, specification, implementation/review, integration/archival, and maintenance workflows behind single entrypoints (`7e543a7`).
- **Governance, architecture, and retrospective skills:** Added `/cadence-doctor`, `/cadence-eject`, `/cadence-merge`, `/cadence-propose`, `/cadence-refactor` (`53ce988`), and `/cadence-retro` with `retro_scan.py` for cross-ticket retrospective synthesis (`addcd51`, `c240d96`).
- **Hybrid security review subagent and gate:** Added the `cadence-security-auditor` agent and `skills/cadence-review/security-trigger.sh` hybrid dispatch gates (`aa4545c`, `d47c9e5`, `tests/test-security-trigger.sh`).
- **Deterministic spec traceability and offline eval suite:** Added `verify-facts --trace` AC-to-code/test verification (`0cbf3b7`, `3c59647`, `tests/test-trace-gates.sh`) and offline deterministic `evals.json` coverage across all 28 CADENCE skills (`1d7a41b`, `cf3adab`, `9478ab2`, `tests/run-evals.sh`).
- **Complete local coprocessor offload stack & Blitz adapter:** Added `local-offload` FastMCP server (`:11434`), `repo-scout` and `log-triage` subagents, `llama-swap` configuration templates, Turn 0/1 inline MCP schemas, AST-aligned top-k slices, per-PID logs, and Blitz runtime adapter (`8654f72`, `c2a3141`, `d0af6c5`, `ca74716`, `296ffee`, `9754086`, `163a26b`, `4f20075`, `b6a1363`, `3435409`).

### Changed

- **Provider-neutral capability tiers and effort levels:** Decoupled skills and agents from provider-specific model aliases, standardized capability-tier routing, enforced `xhigh` effort across implementation and architecture agents, and standardized coprocessor aliases (`b0f4ecb`, `db88e04`, `fb93ebc`, `e91e908`).
- **Spec invariant and review quality checks:** Added Layer-1.5 spec invariant checks, symbol-proximity fact verification, pre-Gate-1 adversarial challenge, separate review passes, and symlink-safe root resolution (`2520a6c`, `87a5e6f`).
- **Refactored adopt, eject, and upgrade engines:** Reworked `cadence-adopt`, `cadence-eject`, and `cadence-upgrade` with footprint checks, `upgrade-removals.sh`, and deterministic verification tests T1a-T8 (`26eb6c2`, `b334df0`, `41da4a9`).

### Fixed

- **Framework-neutral global installs:** Updated `hooks/hooks.global.json` and `import/link-sdlc.sh --global` so global user directories carry only neutral offload hooks, `repo-scout`, and `log-triage`, preventing global methodology cross-contamination (`b4228da`).
- **Blitz agent frontmatter & portable hooks:** Removed non-standard frontmatter keys rejected by strict parsers, eliminated `__pycache__` tracking, and hardened portable hook and Antigravity schema paths (`d4244b1`, `59846f2`, `466c632`).
