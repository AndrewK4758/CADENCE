# Contributor Experience Guide

This guide explains how changes are proposed, specified, reviewed, and merged in any repository that has adopted CADENCE and the Inner-Source SDLC. It governs **everyone proposing work in the repository** — including members of the core owning team. Under a repo-first SDLC there are no backdoor shortcuts for owners: every modification starts with an intent issue, and every change is evaluated against the repository's declared intent.

If you belong to the owning team, this document describes your daily engineering workflow. If you are contributing from another team, it shows you how to propose and land a change without having to guess unwritten team conventions. Both audiences read the exact same guide because the rules are identical.

## The starting point: PROJECT_INTENT.md

Every CADENCE-adopting repository maintains a `PROJECT_INTENT.md` at its root. Read it before drafting any proposal. It establishes:

- **Mission** — why this repository exists and what problem space it serves.
- **Scope** — which capabilities belong in this codebase and which belong elsewhere.
- **Non-Goals** — explicit capabilities the project refuses to take on, paired with the rationale.
- **Quality Stance** — how the project resolves tradeoffs when engineering qualities pull in opposite directions.
- **Architecture Invariants** — structural rules that no change may violate without first amending project intent.
- **Contribution Posture** — whether cross-team contributions are accepted and under what conditions.
- **SLAs and ladder thresholds** — the team's concrete commitments for review turnaround and contributor progression.

When your proposal aligns with `PROJECT_INTENT.md`, proceed to filing an intent issue. When it falls outside current intent, you have three constructive options: route the work to the appropriate adjacent repository, submit an intent-amendment proposal (`PROJECT_INTENT.md` Section 10), or accept that this repository is not the right home. Never attempt to sneak out-of-scope changes through code review — the maintainer evaluates every MR against `PROJECT_INTENT.md`, not personal whim.

If a repository claiming CADENCE adoption does not yet have a `PROJECT_INTENT.md`, authoring one from `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md` is itself an ideal first contribution.

## How work happens here

```
Intent issue → Triage → Spec → [Spec approval] → Implementation →
[Code review] → [Maintainer acceptance] → Merge → Archive
```

This lifecycle applies across the board. Core team members do not bypass the intent issue, the specification, or the human review gates.

For small, low-blast-radius changes, the lightweight track (detailed below) condenses the artifact ceremony without skipping human accountability.

> **Editing an agent or skill?** `.agents/agents/` and `.agents/skills/` (as well as `.gemini/` on Antigravity) are **generated** from the runtime-neutral source tree under `artifacts/` by `ci-templates/scripts/cadence-compile.sh`. Always edit `artifacts/roles/` or `artifacts/commands/` and recompile — never edit the compiled `.agents/` or `.gemini/` directories directly, or your edits will be overwritten on the next compile pass. See `artifacts/SCHEMA.md` and ADR_CADENCE-0008.

### Drift prevention: the compile gate

The recompile rule is enforced mechanically rather than left to human memory. A single gate runner, `ci-templates/scripts/run-gates.sh`, executes the full suite of structural checks (round-trip compile verification, manifest synchronization, reproducible build verification, schema validation, and the vendor-reference sweep) and exits non-zero whenever `.agents/` (or the bound runtime install tree) has drifted from `artifacts/`, the manifest is out of date, the build is non-deterministic, or a vendor-specific primitive leaked into neutral prose. You can wire it locally:

- **Pre-commit hook (opt-in, fast local guard).** Install it once in your checkout:
  ```
  bash ci-templates/scripts/install-hooks.sh
  ```
  Once installed, `run-gates.sh` executes automatically on every `git commit` and aborts the commit if any compiled surface has drifted — catching discrepancies before you push. The installer never runs silently on its own (no agent or skill invokes it behind your back) and refuses to overwrite an existing pre-commit hook. To bypass the hook temporarily for a work-in-progress commit, pass `git commit --no-verify`.

Whether a repository also runs `run-gates.sh` on a remote CI runner after push is declared in a single place — `docs/agentic-sdlc/CADENCE_ORG.md` section 1 *Where (Network)*'s CI/CD row — and is deliberately not duplicated here. In your repository, that setting reflects your own infrastructure: this guide documents the local pre-commit guard without making assumptions about your remote forge.

Regardless of where it runs, there is only one gate script: any remote CI check invokes the exact same `run-gates.sh` binary as the local pre-commit hook, guaranteeing both reach identical verdicts.

## Filing an intent issue

An intent issue is a concise proposal — three to five sentences — stating what you want to change and why. It is not a full technical specification; it is the lightweight social contract: *"I plan to work on this problem; does it belong here?"*

Every well-formed intent issue covers four points:

- **Problem.** What is broken, missing, or confusing (one to two sentences).
- **Proposed approach.** A high-level direction rather than a detailed design (two to three sentences).
- **Surfaces affected.** Which public or registered surfaces, if any, would be touched.
- **Ask.** What you need from the maintainer — a green light to proceed, architectural pointers, a redirect, or a "not right now."

The maintainer replies with one of five dispositions:

- **Proceed.** The proposal fits project intent. Advance to Triage and author a specification, or submit a lightweight change proposal — see [`submitting-changes.md`](submitting-changes.md) for the three supported forge workflows (GitLab MR, GitHub PR, and SourceHut patchset via `git send-email`).
- **Modify.** The goal fits project intent, but the proposed direction needs adjustment before proceeding.
- **Redirect.** The capability belongs in an adjacent repository or service (with a pointer to the right home).
- **Decline.** The proposal conflicts with project intent, citing the specific Non-Goal or Scope-Out clause in `PROJECT_INTENT.md`.
- **Amend first.** Delivering this work requires expanding or modifying `PROJECT_INTENT.md` first; here is how to propose that amendment.

A *Decline* or *Amend first* response is never a personal rejection of the contributor — it simply routes the discussion to the appropriate governance level before engineering hours are spent.

## Tracks

### Lightweight track

A change qualifies for the lightweight track only when **every one** of the following conditions holds:

- No public or registered surface is touched (API endpoints, event schemas, shared DTOs, CLI contracts, database schemas).
- None of the charter's compulsory full-specification categories are affected: shared libraries, public APIs, core domain models, security posture, compliance controls, persistence schemas, interoperability contracts, or cross-team user-visible behavior (see `docs/policies/inner_source_sdlc_charter.md` §Specification Review Gate).
- Every architecture invariant in `PROJECT_INTENT.md` is preserved.
- The work is strictly one of: a documentation improvement, an additional test case, an isolated bug fix with an obvious root cause, a configuration value update, or a non-breaking dependency bump within the same major version.
- The production diff stays within the LOC ceiling declared in `PROJECT_INTENT.md` (default: 50 lines of production code, excluding tests).

If even one of these conditions is not met, the change follows the standard track regardless of how small the diff looks.

Lightweight changes still begin with an intent issue, but the formal multi-file specification phase is condensed: a single `submission.md` instantiated from [`specs/TEMPLATE/submission.md`](../../specs/TEMPLATE/submission.md) acts as the abbreviated specification in place of the full `problem.md` / `spec.md` / `test-plan.md` / `decisions.md` bundle. Its `## Description` section populates the MR/PR body (on GitLab/GitHub) or the patchset cover letter (on SourceHut) — see [`submitting-changes.md`](submitting-changes.md). At minimum, it must specify:

- **Problem framing** — a concise paragraph explaining what is broken, missing, or unclear.
- **Acceptance criteria** — specific, falsifiable bullets a reviewer can verify directly.
- **Surfaces touched** — the modified files or modules, explicitly noting "no public surfaces" when none are affected.
- **Test approach** — which automated tests were added or updated and what they verify.

A single human approver — either a Trusted Committer or a Maintainer — conducts both the code review and maintainer acceptance checks in a single pass. Maintainer acceptance is streamlined because the lightweight eligibility rules rule out the primary drivers of project-level risk (compatibility breakage, architectural drift, mission creep, security expansion, new dependencies). The reviewer explicitly confirms that none of those dimensions are engaged before approving.

### Standard track

All other changes traverse the complete CADENCE lifecycle: intent issue, `/cadence-triage`, `/cadence-spec`, Gate 1 Spec Approval, `/cadence-implement`, Gate 2 Code Review (`/cadence-review`), Gate 3 Maintainer Acceptance (`/cadence-maintain`), Merge, and `/cadence-archive`.

Any contributor may author the specification; a designated reviewer/maintainer approves it at Gate 1 before implementation begins.

### Tier-driven defaults

`docs/policies/change-tiers.md` defines four objective tiers (Trivial, Low, Medium, High) based on diff triggers (surface impact, schema changes, bounded-context crossings). The lightweight track corresponds to Trivial and narrow Low-tier work, while the standard track governs Medium and High tiers.

## Review expectations

Every adopting repository publishes its own review turnaround SLAs in `PROJECT_INTENT.md` calibrated to realistic maintainer bandwidth. The table below provides the recommended defaults:

| Track | First response | Actionable feedback | Target merge (if approved) |
|---|---|---|---|
| Lightweight | 2 business days | 5 business days | 7 business days |
| Standard | 5 business days | 10 business days | Depends on scope |

"First response" means a substantive human reply: an approval, a clarifying question, an architectural concern, or an acknowledgment with a concrete review date. Automated bot replies never count toward the SLA.

Whenever maintainer bandwidth tightens and the team cannot consistently meet its published SLA, the honest remedy is to widen the SLA numbers in `PROJECT_INTENT.md` — never to miss them silently. Realistic SLAs sustain contributor trust; aspirational SLAs that are routinely ignored destroy it.

### Escalation

When an intent issue or MR receives no human response within the published SLA:

1. Ping the maintainer in the repository's public communication channel (listed in `PROJECT_INTENT.md`).
2. If no response arrives within an additional 24 business hours, escalate along the path documented in `PROJECT_INTENT.md` (typically the owning team's engineering lead or the inner-source stewardship group).
3. Recurring SLA breaches signal that maintainership is under-resourced — address capacity at the team retrospective rather than blaming individual maintainers.

## The maintainer's job

Maintainers act as stewards of project intent, not arbitrary gatekeepers.

In day-to-day practice, stewardship means:

- **Every disposition cites `PROJECT_INTENT.md`.** Whether accepting, requesting changes, or declining, the maintainer grounds the decision in documented Mission, Scope, Non-Goals, Quality Stance, Architecture Invariants, or Contribution Posture. *"I don't like this style"* is invalid; *"this conflicts with our Data Integrity pillar because mutations bypass the audit log"* is actionable and objective.
- **Maintainer bandwidth is finite and transparent.** Maintainers commit only to turnaround windows they can reliably honor and update `PROJECT_INTENT.md` openly when capacity shifts.
- **Out-of-scope proposals receive a redirect, not a dead end.** When a proposal belongs elsewhere, the maintainer cites the relevant Non-Goal and points the contributor toward the appropriate repository or intent-amendment path.
- **Intent evolves through a documented process.** When a strong contribution reveals that `PROJECT_INTENT.md` is too narrow, the maintainer guides the contributor through a Section 10 intent amendment.

### What maintainers should not do

- **Pocket vetoes / silent ignoring.** Leaving an intent issue or MR unreviewed until the author walks away. If bandwidth is constrained, say so upfront and state when you can review.
- **Unscoped piggybacking.** Demanding unrelated cleanups or feature additions as a hostage condition for merging an in-scope MR. File a separate follow-up ticket instead (`docs/policies/finding-classes.md`).
- **Moving the goalposts.** Rewriting acceptance criteria at Gate 2 or Gate 3 after the contributor implemented the exact design approved at Gate 1 (unless a genuine production hazard surfaced, in which case follow `docs/policies/conflict-resolution.md` Scenario 1).
- **Hoarding tribal knowledge.** Rejecting contributions for violating unwritten rules. If a convention matters, codify it in `AGENTS.md` or `PROJECT_INTENT.md`.
- **Treating intent issues as noise.** Early 4-sentence intent checks prevent wasted multi-day implementations.
- **Taste-based blocks.** Blocking an MR that satisfies its approved spec, passes all tests, and honors every Engineering Pillar simply because you would have coded it differently.

## Review etiquette

For reviewers:

- Critique the code and architecture, never the author. Write *"This handler has a stale-read window under concurrent updates"* — never *"You didn't think about concurrency."*
- Label findings clearly using `[blocking]` or `[suggestion]` (and the five normative non-blocking finding classes in `docs/policies/finding-classes.md`: `out-of-scope-defect`, `adr-owed`, `nit`, `hygiene`, `observation`).
- Explain the *why* behind every blocking finding, citing the specific policy, ADR, spec requirement, or `PROJECT_INTENT.md` invariant.
- Call out well-crafted work — acknowledging a clean test or clear boundary design reinforces quality standards.
- Keep reviews scoped to the ticket's approved contract.

For contributors:

- Reply to review feedback within 5 business days (or post a quick note if you need more time).
- Ask for clarification whenever a review comment is ambiguous rather than guessing.
- Recognize that maintainers hold system-wide context that may not be obvious from a single file. If you disagree with a finding, reply with concrete evidence (`docs/policies/conflict-resolution.md` Scenario 3) rather than complying silently or ignoring the comment.

## Growing as a contributor

Trust scales with demonstrated alignment. Adopting repositories may customize the thresholds or level names below in `PROJECT_INTENT.md`; the purpose of the ladder is to recognize contributors who consistently deliver clean, well-specified changes.

### Contributor

Anyone who opens an intent issue or submits a change proposal. Zero prerequisites.

**Privileges:**

- File intent issues, specifications, and MRs.
- Participate in design and review discussions.
- Request onboarding guidance from Trusted Committers or Maintainers.

### Recurring Contributor

A contributor who has reached the repository's activity threshold (default: **3 or more merged MRs** within the trailing 12 months, customizable in `PROJECT_INTENT.md`).

**Additional privileges:**

- Nominate backlog tickets as "Good First Issue" candidates.
- Provide advisory peer reviews on MRs.
- Listed in `CONTRIBUTORS.md` at the repository root.
- Eligible for repo-specific permissions configured in `PROJECT_INTENT.md` (such as advisory triage assistance).

### Trusted Committer

An experienced recurring contributor nominated by a Maintainer and ratified through the repository's governance process. Trusted Committers bridge the core owning team and external inner-source contributors.

**Additional privileges:**

- Approve lightweight-track MRs (performing the combined Gate 2/Gate 3 check).
- Provide official first-response verdicts on incoming intent issues.
- Participate in Gate 1 Specification Approval reviews.
- Join roadmap and backlog triage sessions.

**Responsibilities:**

- Meet the repository's published review turnaround SLAs.
- Deliver specific, evidence-backed review feedback.
- Catch architectural or compatibility misalignments early — at the intent issue or spec stage rather than after code is written.
- Rotate active triage/review duty on the schedule set by the project (recommended: quarterly) to share context and prevent reviewer fatigue.

### Maintainer

Holds final stewardship authority over Gate 3 Maintainer Acceptance, surface compatibility, and `PROJECT_INTENT.md` integrity. Promotion to Maintainer follows the domain's governance process and reflects sustained architectural judgment and stewardship, not raw commit count.

## When contributions are out of scope

When a proposal falls outside `PROJECT_INTENT.md`, it is not a dead end — it follows one of three structured paths:

1. **Redirect.** The maintainer identifies the adjacent repository or service where the capability belongs.
2. **Amend intent.** If the capability is valuable and the project's scope should expand to cover it, the contributor or maintainer proposes a Section 10 amendment to `PROJECT_INTENT.md`.
3. **Park.** When neither redirection nor immediate amendment applies, the proposal and rationale are logged in `decisions.md` as deferred or declined so the context is preserved if priorities shift later.

## Recognition

Healthy inner-source repositories make contributor impact visible:

- Cross-team contributors are credited by name in `docs/releases/` and `CHANGELOG.md` when their changes ship.
- `CONTRIBUTORS.md` at the repository root records everyone who has landed work.
- High-impact cross-boundary contributions are highlighted in engineering-wide updates.

## Disagreement

Technical disagreement is a normal part of rigorous engineering. When perspectives differ:

- Keep the discussion in the written record (tracker comments, MR/PR threads, or patchset emails mirrored into `submission.md`) so future readers benefit from the context.
- Ground arguments in empirical evidence, benchmarks, traces, ratified ADRs, and `PROJECT_INTENT.md` rather than job titles.
- When consensus cannot be reached within a time-boxed discussion, follow the escalation ladder in [`docs/policies/conflict-resolution.md`](../policies/conflict-resolution.md) and log the outcome in `decisions.md`.

## Adoption checklist

When onboarding a repository onto this guide for the first time:

- [ ] Author `PROJECT_INTENT.md` at the repository root from `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`.
- [ ] Name at least one accountable Maintainer and verify they have bandwidth for the declared SLAs.
- [ ] Configure the open communication channel referenced in `PROJECT_INTENT.md`.
- [ ] Create `CONTRIBUTORS.md` at the repository root.
- [ ] Record contributor ladder thresholds, review SLAs, and lightweight-track LOC limits in `PROJECT_INTENT.md`.
- [ ] Link both this guide and `PROJECT_INTENT.md` prominently from `README.md`.
- [ ] Schedule the recurring `PROJECT_INTENT.md` stewardship review (default: every 6–12 months).

## Relationship to the charter

This guide operationalizes the contributor-facing workflow of the [Inner-Source SDLC Charter](../policies/inner_source_sdlc_charter.md). The charter establishes enterprise-wide baseline governance; this guide details how contributors and maintainers collaborate day to day within those guardrails. In any case of ambiguity between this guide and the charter, the charter governs.

Adopting teams may supplement this guide with local practices (pairing hours, architecture office hours, inner-source hack days) provided they remain aligned with the charter and `PROJECT_INTENT.md`.
