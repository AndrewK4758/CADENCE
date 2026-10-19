# Contributor Experience Guide

This guide describes how work is proposed, reviewed, and merged in any repository that has adopted CLAIRE and the Inner-Source SDLC. It applies to **anyone proposing work in the repo** — including the owning team. Repo-first SDLC means there are no shortcuts for owners: every change starts with an intent issue, and every change is reviewed against the project's stated intent.

If you are part of the owning team, this guide describes your day-to-day workflow. If you are outside the owning team, it describes how to propose a change without guessing at the team's expectations. Both audiences read the same document because the process is the same.

## The starting point: PROJECT_INTENT.md

Every CLAIRE-adopting repository has a `PROJECT_INTENT.md` at its root. Read it first. It tells you:

- **Mission** — what the project exists to do.
- **Scope** — what kinds of work belong here, and what does not.
- **Non-Goals** — explicit things the project will not do, with reasons.
- **Quality Stance** — what the project optimizes for when qualities conflict.
- **Architecture Invariants** — structural commitments that cannot be violated without amending intent.
- **Contribution Posture** — whether contributions from outside the owning team are welcome, and what kinds.
- **SLAs and ladder thresholds** — the project's specific commitments for review timing and contributor advancement.

If your idea fits the intent, you can proceed to filing an intent issue. If it does not fit, you have three paths: redirect to an adjacent project, propose an intent amendment (Section 10 of `PROJECT_INTENT.md`), or accept that this is not the right home for the work. Do not try to slip out-of-scope work past review — the maintainer reviews against intent, not against personal preference.

If `PROJECT_INTENT.md` does not exist yet in a repo claiming CLAIRE adoption, that is itself a valid first contribution: file an intent issue proposing it, using the template at `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`.

## How work happens here

```
Intent issue → Triage → Spec → [Spec approval] → Implementation →
[Code review] → [Maintainer acceptance] → Merge → Archive
```

This applies uniformly. The owning team does not skip the intent issue, the spec, or the human gates.

The lightweight track (described below) compresses but does not eliminate these steps for small, low-risk changes.

> **Editing an agent or skill?** `.claude/agents/` and `.claude/skills/` are **generated** from the runtime-neutral source under `artifacts/` by `ci-templates/scripts/claire-compile.sh`. Edit `artifacts/roles/` or `artifacts/commands/` and recompile — never edit the `.claude/` trees directly, or your change is overwritten on the next compile. See `artifacts/SCHEMA.md` and ADR_CLAIRE-0008.

### Drift prevention: the compile gate

The recompile rule above is no longer left to memory — a compile gate enforces it mechanically. The gate runs one runner, `ci-templates/scripts/run-gates.sh`, which composes the existing checks (round-trip compile, manifest sync, reproducible build, schema, and the vendor-reference sweep) and exits non-zero if `.claude/` has drifted from `artifacts/`, the manifest is stale, the build is non-reproducible, or a primitive leaked. It runs locally:

- **Pre-commit hook (opt-in, the primary fast local guard).** Install it once, explicitly:
  ```
  bash ci-templates/scripts/install-hooks.sh
  ```
  After that, the same gate runs locally on every `git commit` and aborts the commit if anything has drifted — so you catch drift before you push, not after. The installer never runs by itself (no tool, skill, or agent installs it) and refuses to clobber an existing hook. To skip the hook for a work-in-progress commit, use `git commit --no-verify`.

Whether this repository ALSO runs the gate on a CI substrate after a push is recorded in one place, `docs/agentic-sdlc/CLAIRE_ORG.md` section 1 *Where (Network)*'s CI/CD row, and is deliberately not restated here. In YOUR repository that answer is whatever your own configuration says: this guide describes the reference implementation's local guard and assumes nothing about your forge.

Whatever that row says, there is only ever one runner: a post-push check would invoke the same `run-gates.sh` this hook does, so the two cannot reach different verdicts.

## Filing an intent issue

An intent issue is a short proposal — three to five sentences — describing what you plan to change and why. It is not a specification. It is the social contract: *"I intend to work on this; is that useful?"*

A good intent issue includes:

- **Problem.** What is wrong, missing, or unclear (one to two sentences).
- **Proposed approach.** A sketch, not a design (two to three sentences).
- **Surfaces affected.** Which public surfaces, if any, would change.
- **Ask.** What you need from the maintainer — confirmation to proceed, guidance, a redirect, or a "not now."

The maintainer responds with one of:

- **Proceed.** The work fits intent. File a spec, or submit a lightweight change proposal — see [`submitting-changes.md`](submitting-changes.md) for the three supported workflows (GitLab MR, GitHub PR, SourceHut patchset via `git send-email`).
- **Modify.** The work fits intent but the approach needs adjustment.
- **Redirect.** The work belongs in a different project; here is where.
- **Decline.** The work does not fit intent. Includes a citation to the relevant Non-Goal or Scope-Out entry.
- **Amend first.** The work would require changing intent; here is how to propose that.

A "decline" or "amend first" is not a rejection of the contributor. It is a redirect to the right shape of conversation.

## Tracks

### Lightweight track

The lightweight track applies when **all** of the following are true:

- The change does not touch any public surface (API, event schema, shared contract, database schema).
- The change does not affect any of the charter's compulsory full-spec categories: shared libraries, public APIs, core domain models, security posture, compliance obligations, persistence models, interoperability contracts, or cross-team user-visible behavior. (See `docs/policies/inner_source_sdlc_charter.md` §Specification Review Gate.)
- The change does not violate any architecture invariant in `PROJECT_INTENT.md`.
- The change is one of: documentation improvement, test coverage addition, bug fix with obvious root cause, configuration correction, or dependency update within the same major version.
- The change fits within the LOC limit set in `PROJECT_INTENT.md` (default: 50 lines of production code, excluding tests).

If any of these conditions is unmet, the change uses the standard track regardless of size.

Lightweight contributions still file an intent issue, but the spec phase is collapsed: a `submission.md` written from [`specs/TEMPLATE/submission.md`](../../specs/TEMPLATE/submission.md) serves as the abbreviated specification, replacing the full `problem.md` / `spec.md` / `test-plan.md` / `decisions.md` set. Its `## Description` section is the body of the MR/PR (GitLab/GitHub) or the cover letter of the patchset (SourceHut) — see [`submitting-changes.md`](submitting-changes.md). It must include, at minimum:

- **Problem framing** — one paragraph stating what is wrong, missing, or unclear.
- **Acceptance criteria** — bulleted, specific enough that a reviewer can verify them.
- **Surfaces touched** — list the files or modules; explicitly state "no public surfaces" if applicable.
- **Test approach** — which tests are added or updated and why.

A single approver — a Trusted Committer or maintainer — performs both the code review and maintainer acceptance evaluations in one pass. The maintainer acceptance is condensed because the lightweight track conditions exclude the categories that drive project-level impact (compatibility, architecture, mission alignment, security surface, dependency health). The approver still confirms each condensed dimension is genuinely not engaged before approving.

### Standard track

All other contributions follow the full CLAIRE lifecycle: intent issue, spec, spec review, implementation, code review, maintainer acceptance.

The contributor may draft the spec. A maintainer reviews and approves it before implementation begins.

### Tier-driven defaults

`docs/policies/change-tiers.md` defines four tiers (Trivial, Low, Medium, High) based on objective triggers (LOC, surface impact, blast radius). Tier determines the depth of process. The lightweight track maps to Trivial and most Low-tier changes. The standard track covers Medium and High.

## Review expectations

Each adopting repo sets its own SLAs in `PROJECT_INTENT.md` based on maintainer capacity. The defaults below are recommendations.

| Track | First response | Actionable feedback | Target merge (if approved) |
|---|---|---|---|
| Lightweight | 2 business days | 5 business days | 7 business days |
| Standard | 5 business days | 10 business days | Depends on scope |

"First response" means a substantive reaction: approval, a question, a concern, or an acknowledgment with an estimated timeline. Bot messages do not count.

If a maintainer cannot meet the stated SLA, the right move is to update `PROJECT_INTENT.md` to widen it — not to silently miss it. Honest SLAs build trust; aspirational SLAs erode it.

### Escalation

If an intent issue or MR receives no response within the SLA:

1. Ping the maintainer in the project's open communication channel.
2. After an additional 24 hours, escalate via the path documented in `PROJECT_INTENT.md` (typically: owning team's manager or the inner-source governance group).
3. Persistent SLA misses are a signal that the maintainer role is under-resourced. Raise it in the team's retrospective rather than blaming individuals.

## The maintainer's job

The maintainer is not a gatekeeper. They are a steward of project intent.

In practice, that means:

- **Decisions are grounded in `PROJECT_INTENT.md`.** When the maintainer accepts or rejects work, they cite intent — Mission, Scope, Non-Goals, Quality Stance, Architecture Invariants, or Contribution Posture. *"I do not like it"* is not a reason; *"this violates the Auditability priority because X"* is.
- **Capacity is finite and visible.** Maintainers commit to SLAs they can actually hit. When capacity is short, the SLA widens publicly. Treat maintainer load as a first-class concern, not a hidden tax.
- **Out-of-scope is a redirect, not a rejection.** If a contribution is out of scope, the maintainer points at the Non-Goal or adjacent project. The contributor leaves with a path forward, not a dead end.
- **Changing intent is a documented process.** When a contribution is good but does not fit current intent, the maintainer explains the amendment process. Intent is not immutable; it changes deliberately.

### What maintainers should not do

- **Silent rejection.** Letting an MR sit until the contributor gives up. If you cannot review within the SLA, say so and provide a timeline.
- **Scope creep.** Requesting unrelated improvements as a condition for merging. File a separate issue.
- **Moving goalposts.** Changing requirements after the contributor has implemented the agreed approach.
- **Gatekeeping knowledge.** Refusing to answer questions or pointing to documentation that does not exist. If the docs are missing, accept a contribution that adds them.
- **Discouraging intent issues.** Treating early proposals as bothersome. Intent issues save everyone time.
- **Personal-taste rejections.** Declining work because you would have written it differently, when it satisfies the spec and the project's stated quality stance.

## Review etiquette

Reviewers:

- Comment on the code, not the person. *"This function has a race condition"* — not *"you did not think about concurrency."*
- Distinguish blocking concerns from suggestions. Use a clear prefix: `[blocking]` or `[suggestion]`.
- Explain *why* a change is needed, not just that it is. Link to the relevant standard, ADR, or section of `PROJECT_INTENT.md`.
- Acknowledge good work. *"Nice approach here"* costs nothing and builds trust.
- Stay in scope. Review against the stated intent of the MR, not a wish list.

Contributors:

- Respond to feedback within 5 business days or indicate that you need more time.
- Ask clarifying questions rather than guessing at the reviewer's intent.
- Accept that maintainers may have context not visible in the MR. If you disagree, say so explicitly and request the rationale — do not quietly comply or quietly refuse.

## Growing as a contributor

Trust grows with familiarity. The ladder below is a default — adopting repos may rename levels, adjust thresholds, or compress levels in `PROJECT_INTENT.md`. The point of the ladder is not bureaucracy; it is that someone who has merged ten things to a repo deserves more latitude than someone making their first contribution.

### Contributor

Anyone who files an intent issue or submits an MR. No prerequisites.

**Privileges:**

- Submit intent issues and MRs.
- Participate in discussions on issues and specs.
- Request mentorship from maintainers.

### Recurring Contributor

A contributor who has met the project's threshold (default: **3 or more merged MRs** in the trailing 12 months — projects override in `PROJECT_INTENT.md`).

**Additional privileges:**

- Nominate issues for "Good First Issue" labeling.
- Provide non-binding review on others' MRs.
- Listed in the repository's CONTRIBUTORS file.
- Projects may grant additional privileges (e.g., direct push to specific doc paths, advisory triage role) by configuring them in `PROJECT_INTENT.md`.

### Trusted Committer

A recurring contributor nominated by a maintainer and confirmed by the project's governance process. Trusted committers serve as the bridge between the owning team and the contributor community.

**Additional privileges:**

- Approve lightweight-track MRs.
- Provide first-response on intent issues from outside the owning team.
- Participate in spec reviews as a domain-knowledgeable voice.
- Invited to roadmap and triage discussions.

**Responsibilities:**

- Respond to questions within the project's stated SLA.
- Provide constructive, specific feedback within review SLAs.
- Flag architectural or compatibility concerns early — before a contributor invests in the wrong direction.
- Rotate the role on a cadence defined by the project (recommended: quarterly) to spread knowledge and prevent burnout.

### Maintainer

Full ownership of acceptance decisions. Promotion follows the project's governance process and requires demonstrated judgment on compatibility, architecture, and stewardship of intent — not merely volume.

## When contributions are out of scope

Out of scope does not mean unwelcome. It means the contribution does not fit the project's stated intent right now. Three paths forward:

1. **Redirect.** The maintainer points to an adjacent project that owns this work.
2. **Amend intent.** If the contribution is good but the project's intent should grow to include it, file an intent-amendment proposal (Section 10 of `PROJECT_INTENT.md`).
3. **Park.** If neither redirect nor amendment fits, the work is documented in the project's decision log as deferred or declined, with rationale. The contributor's effort is preserved; if circumstances change, the decision is revisited.

## Recognition

A healthy inner-source repo credits contributions visibly:

- External contributors are credited in release notes when their work ships.
- A `CONTRIBUTORS.md` file at the repo root lists everyone who has merged work.
- Significant community contributions are highlighted in team communications.

The goal is not vanity metrics. The goal is that contributors who invest in the repo see their investment acknowledged.

## Disagreement

Disagreements about approach are healthy. When they arise:

- Keep the discussion in writing (issue comments, MR/PR threads, or patchset email threads — whichever your forge uses) so others can learn from it.
- Focus on tradeoffs and evidence, not authority. Cite intent, ADRs, prior decisions, or measured outcomes.
- If consensus is not reached, the maintainer makes the call and records the rationale in the decision log.
- A rejected approach is not a rejected contributor.

## Adoption checklist

For a repo adopting this guide for the first time:

- [ ] Author `PROJECT_INTENT.md` from `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md`.
- [ ] Designate at least one maintainer; confirm they have the capacity to meet the stated SLAs.
- [ ] Set up the open communication channel referenced in Contribution Posture.
- [ ] Create the `CONTRIBUTORS.md` file at the repo root.
- [ ] Set ladder thresholds, SLAs, and lightweight-track LOC limit in `PROJECT_INTENT.md`.
- [ ] Link this guide and `PROJECT_INTENT.md` from the repo's README.
- [ ] Schedule the first intent review (default: 6–12 months out).

## Relationship to the charter

This guide implements the contributor-facing surface of the [Inner-Source SDLC Charter](../policies/inner_source_sdlc_charter.md). The charter defines governance and minimum controls; this guide defines the workflow within that framework. Where this guide and the charter conflict, the charter takes precedence.

Repos may extend this guide with additional practices (office hours, pairing sessions, contribution sprints) provided they remain consistent with the charter and with `PROJECT_INTENT.md`.
