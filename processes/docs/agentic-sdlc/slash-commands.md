# Skills (Slash Commands)

These are the primary interface for working with the agentic SDLC. Run them in your agentic coding tool (reference instance: Claude Code).

## `/claire-adopt <target-repo-root>`

Copy the CLAIRE framework file set into a target repository. Wraps the canonical bash script; never overwrites a file that already exists in the target. Use this when bootstrapping a new repo into the framework — it is the prerequisite for every other skill (without an adopted repo, there is nothing to triage or spec against).

```
/claire-adopt /path/to/your-repo
```

**Alternative for adopters whose agentic coding tool does not load this skill:** run `scripts/adopt-claire.sh <target>` from a clone — the script is identical (the skill wraps it).

**Outputs:** Per-file `copied: <path>` / `skip (exists): <path>` audit lines, followed by `Done: N copied, M skipped (already present).` Files are written into the target repo with the same paths they have in the source repo.

## `/claire-upgrade <new-version>`

Merge a newer CLAIRE core into an adopter's customized tree, using the PI-021 `.claire-version` stamp as the 3-way-merge base. Wraps the canonical merge engine; clean hunks auto-apply and are reported, conflicts are surfaced for human resolution (never a silent merge), the apply is atomic, and the stamp advances only on a fully-clean apply. Use this when an adopting repo that customized CLAIRE needs to pull in a newer framework release — it is the upgrade-time counterpart to `/claire-adopt`.

```
/claire-upgrade 3.8.0
/claire-upgrade 3.8.0 --dry-run
```

**`--dry-run` (preview, recommended):** compute the full 3-way merge in memory and report the outcome — total files in scope, how many would apply cleanly, how many would conflict, and the conflicting paths — to stdout, **writing nothing** (no `.claire-version` advance, no staging directory, no footprint write, no work-tree apply). The exit code is CI-keyable: **0** on a would-be-clean apply, **non-zero** on would-be-conflicts.

**Pre-PI-021 adopters (no installed command tree yet):** a compiled-only adopter that predates the `.claire-version` stamp has no installed `.claude/skills/claire-upgrade/` tree to invoke. Run the engine directly from a local **core checkout** of the framework, pointing it at the adopter repo:

```
UPGRADE_TARGET=<adopter-repo> bash <core>/artifacts/commands/claire-upgrade/upgrade-claire.sh <new-version>
```

The engine first runs the Step-0 footprint pre-check. If the `artifacts/footprint.generated` merge boundary is absent it halts (before any stamp write) and points at the auto-generate — run it, with explicit confirmation, via the engine's Step-0 mode: `AUTOGEN_CONFIRM=1 UPGRADE_TARGET=<repo> UPGRADE_CORE=<core> bash <core>/artifacts/commands/claire-upgrade/upgrade-claire.sh --autogen-footprint` (derives the footprint atomically from the core checkout). Once it exists, the same invocation performs the merge; add `--dry-run` to preview first. See the skill body (`.claude/skills/claire-upgrade/SKILL.md`) for the full pre-PI-021 flow.

**Alternative for adopters whose agentic coding tool does not load this skill:** invoke the sidecar `.claude/skills/claire-upgrade/upgrade-claire.sh <new-version>` directly — the script is identical (the skill wraps it).

## `/claire-triage [--file-only] [ticket-id | draft-path | problem description]`

Classify an incoming issue, search the codebase for related code, check for prior work, and create the spec stub.

```
/claire-triage TT-1234
/claire-triage "Users report 500 error when activating campaigns with no bundles"
```

**Outputs:** `specs/{ticket-id}/problem.md`, `specs/{ticket-id}/metadata.yaml`

**`--file-only` — file a ticket without triaging it.** The optional flag switches the skill to a filing mode: it allocates an id through the same `CLAIRE_ORG.md#id-allocation-binding` allocator, **always** writes both artifacts in that same operation, and runs **no** classification at all — no agent delegation, no duplicate scan, no type/priority/scope, and **no tier**. Use it when the request is "file an issue for X" and classifying now would be guessing; run `/claire-triage <id>` afterwards to classify. With the flag absent every existing invocation behaves exactly as before.

```
/claire-triage --file-only specs/drafts/expired-coupons.md
```

**The DRAFT-PATH form above is the recommended one (BTG-281).** Write the problem statement to a
file first, then pass its path as a single bare token. A skill argument that is not a single bare
token is not reliably delivered to the loaded skill body: it can arrive as a stray word from the
middle of the text, or empty. A mangled *path* names a file that does not open, so the skill halts
naming the unresolved token and burns no id -- whereas a mangled inline description is
indistinguishable from a legitimate short one and is filed as though it were the problem.

**The inline free-text form is DEPRECATED**, sunsetting in **2 release cycles**; it still works and
emits a deprecation notice. Migration: [`docs/migrations/triage-file-only-draft-path.md`](../migrations/triage-file-only-draft-path.md).

```
/claire-triage --file-only "checkout total ignores expired coupons"   # deprecated
```

**Outputs (`--file-only`):** the same two files — `specs/{ticket-id}/problem.md` (the description recorded verbatim, Status `Draft`, every probe left unanswered) and `specs/{ticket-id}/metadata.yaml` with **`status: draft`** and **no tier** (`tier: ""`, carrying the reason). Downstream skills halt fail-closed on that empty tier, which is intended: the ticket is filed, not triaged. Where a tracker is bound the filed ticket is projected once; where none is (`#tracker-binding` = None) the skip is reported, never silently omitted.

## `/claire-elicit <ticket-id>`

Walk a human requester through any unfilled probe questions in `specs/{ticket-id}/problem.md` and capture verbatim answers as a structured `## Elicited Intent` section appended to the file. Use this after `/claire-triage` when the triage agent suggests it — typically because probe questions in the per-ticket problem.md are still marked `_(not yet answered)_`.

The skill is **tier-gated**: it proceeds only for Medium or High tier tickets and refuses Trivial or Low. The tier is read from `specs/{ticket-id}/metadata.yaml`; the skill does not modify it. It also enforces a **hard cap** of 7 probes per invocation (today's template ships 5; the extra slots are forward-compatibility headroom, not slots for skill-generated follow-up questions). See `docs/policies/change-tiers.md` for tier definitions.

If an `## Elicited Intent` section already exists, the skill summarizes it and asks for explicit confirmation before overwriting.

```
/claire-elicit PI-005
```

**Outputs:** Appended (or replaced, with explicit confirmation) `## Elicited Intent` section in `specs/{ticket-id}/problem.md` containing the requester's verbatim answers and a provenance label.

## `/claire-spec [ticket-id]`

Generate a complete specification from a triaged issue. Requires `problem.md` and `metadata.yaml` to exist.

At Medium and High tier the skill runs an **independent design-exploration pre-step** before the
spec is authored: it delegates to the `claire-explorer` agent, which produces two or three structurally
distinct, individually steelmanned options with no ranking and no recommendation. The
`claire-spec-author` then converges against that option set and records the choice in the spec's
Design Exploration section. The explorer is a step of this skill, never a sub-call the
`claire-spec-author` makes, so the agent that produces the options is not the agent that picks one.
Low and Trivial tier stop at Step 0 and never reach this step.

```
/claire-spec TT-1234
```

**Outputs:** `specs/{ticket-id}/design-options.md` (Medium/High only), `specs/{ticket-id}/spec.md`, `specs/{ticket-id}/test-plan.md`, `specs/{ticket-id}/decisions.md`

## `/claire-implement [ticket-id]`

Implement an approved specification using strict BDD red-green-refactor TDD — one Gherkin scenario per cycle, migrations via expand/contract, journey tests with chaos profiles. Delegates to the implementer agent, which works through the Implementation Order (from `test-plan.md` at Medium/High tier, or derived from `problem.md`'s acceptance criteria at Low tier) in red-green-accumulate-commit cycles.

```
/claire-implement TT-1234
```

**Prerequisite:** Spec must exist and be human-approved (`metadata.yaml` shows `status: spec-approved`). The skill will not bypass this gate.

**Outputs:** Feature branch with one commit per red-green cycle, full passing test suite, boundary documentation on cross-service code, drafted `specs/{ticket-id}/submission.md`, and `metadata.yaml` updated to `status: in-review`.

## `/claire-review [MR number or branch name]`

Review a merge request against its tier contract — the approved spec at Medium/High tier, `problem.md`'s acceptance criteria at Low tier. Checks acceptance criteria, test coverage, facet compliance, architecture, and security, then applies a two-axis adversarial lens: *verify-the-claim* (every "this is safe because X" is checked against the real source of X — real seed/config numbers, engine docs, every sibling writer, prod wiring, the canonical story file — never inherited) and *locate-the-failure* (places each candidate failure by its position relative to the diff: in it / in code it consumes / in code that consumes it / in unchanged code whose contract it silently changed — the last is the one diff-review misses by construction), scaling effort to change size, then probes how the change can fail *silently* (fallbacks/stubs, broad `except` clauses, consumed-contract assumptions, invariant completeness across all writers of newly-shared state, reused-state-across-transitions, test/config-environment fidelity, test/fake blind spots, declarative-config & runtime-engine omissions, claimed-bounds/out-of-scope recomputed against real numbers).

```
/claire-review 142
/claire-review impl/feature/ORD-40
```

**Outputs:** Structured MR comments with verdict, AC checklist, facet compliance, and inline [BLOCKING]/[SUGGESTION]/[QUESTION] comments.

## `/claire-maintain [MR number or branch name]`

Evaluate an MR for project-level acceptance after code review. The maintainer agent assesses backwards compatibility, architectural integrity, project goal alignment, maintenance cost, security impact, release readiness, and dependency health -- then presents a structured assessment and asks for your decision.

```
/claire-maintain 142
/claire-maintain impl/feature/ORD-40
```

**Prerequisite:** Code review must be completed first (`/claire-review`).

**Outputs:** Structured maintainer assessment with 8 dimension evaluations, blocking issues, and a decision prompt (Accept / Postpone / Reject). Based on your decision, updates metadata, changelog, and deprecation documentation.

## `/claire-migrate [ticket-id] [--contract]`

Author database migrations using the expand/contract pattern. Default mode is `expand` (additive, ships with the feature). Use `--contract` for follow-up cleanup after production verification.

```
/claire-migrate TT-1234
/claire-migrate TT-1234 --contract
```

**Prerequisite:** Entity class changes must be complete before running in expand mode.

**Outputs:** Migration files in the project's migrations directory. Expansion migrations are verified as backwards-compatible (no destructive operations). Contraction migrations are verified as safe to apply after the feature has been running in production.

The migration-author agent discovers your project structure (DbContext, migrations directory, startup project, DB provider) at runtime.

## `/claire-archive [ticket-id]`

Archive a merged ticket. Delegates to the archivist agent, which finalizes `submission.md`, moves `specs/{ticket-id}/` to `archive/{ticket-id}/`, **dispositions every inbound citation of the moved path (blocking — see below)**, generates a summary with metrics from git history, updates CHANGELOG.md, promotes ADR-worthy decisions and intent insights, syncs the repo's bound tracker (`CLAIRE_ORG.md#tracker-binding`), and cleans up the feature branch.

```
/claire-archive TT-1234
```

**Prerequisite:** The change proposal must be merged (`metadata.yaml` shows `status: merged`, or the merge commit is reachable on the integration branch resolved from `CLAIRE_ORG.md#branch-strategy-binding` — ADR_CLAIRE-0020; never hardcode a branch name).

**Blocking steps (BTG-083 / PROD_CLAIRE-009, BTG-133 / PROD_CLAIRE-015):** the move turns every external reference to `specs/{ticket-id}/` into a dead pointer, so after the move the archivist runs `ci-templates/scripts/dead-citation-gate.sh --id {ticket-id}` (step 2b). But `/claire-archive`'s step 2 also writes **new files** into that tree before either sweep runs — the ADR promotion and the intent-insight promotion — and those routinely cite a **different**, already-archived ticket's `specs/` path. The gap is one of **scope, not ordering**: a single-id scan is structurally unable to see such a citation, whenever it runs. So once 2b has exited 0 the archivist also runs `ci-templates/scripts/dead-citation-gate.sh --except-id {ticket-id}` (step 2c), which sweeps every archived id **except** this one. **One classifier, three callers** — the `dead-citation` CI gate row, 2b, and 2c — never a second implementation. Each hit from either step gets exactly one disposition: **REPOINT** (the default; for 2c the target is the **other** ticket's archive directory) or **EXEMPT** (an allowlist entry naming the class and the reason). A hit reported as `NOT-A-COMMENT` is code and is dispositioned individually; nothing is ever auto-rewritten, and `--emit-baseline` is never a way to clear a hit. **Archival does not complete while any hit from either step is undispositioned.**

**Conditional on the classifier being installed (BTG-099):** both steps first test that `ci-templates/scripts/dead-citation-gate.sh` exists **and is non-empty** (a zero-byte script exits 0 and would be read as a clean sweep). If the classifier is not installed, the step does **not** halt and does **not** silently skip: it emits a named notice — the gate is not installed, PROD_CLAIRE-009 rot is unguarded for this archival, how to enable it, and an explicitly ungoverned one-off manual fallback the operator may take or decline — records the outcome in `summary.md` under `DEAD-CITATION-SWEEP: SKIPPED` or `DEAD-CITATION-SWEEP: MANUAL`, and continues. An installed classifier that exits **2** (its setup-failure status) **halts** under a distinct name.

**Outputs:** All artifacts under `archive/{ticket-id}/` including `summary.md` (carrying a *Citation Dispositions* table), updated CHANGELOG.md, `metadata.yaml` set to `status: archived`, and any flow doc update proposals flagged for human review.

---

## `/claire-sync-jira [ticket-id | all]`

Push spec metadata from the repo to Jira Server/DC. One-directional: repo is source of truth.

```
/claire-sync-jira TT-1234
/claire-sync-jira all
```

---

## `/claire-bump-model <from-model> <to-model>`

Bump the model declaration in agent YAML frontmatter AND in the concrete-model column of `CLAIRE_ORG.md#model-tier-mapping`, from one version to another. Finds all references in `.claude/agents/*/AGENT.md` plus the matching mapping row, and substitutes them after a confirmation diff.

**Scope:** Operates only on `model:` fields in agent YAML frontmatter and the concrete-model column of the tier-mapping table in `CLAIRE_ORG.md#model-tier-mapping`. Does not touch documentation prose, CI configuration, external routing, or any other system. One tier per invocation — cross-tier changes are architectural decisions that warrant a spec.

**Outputs:** Diff of edits across both targets, confirmation prompt, post-edit verification of both. Changes are not committed automatically — review with `git diff` and commit per your normal workflow.

### Example (Claude Code)

This repo dogfoods Claude Code. Concrete invocations:

```
/claire-bump-model claude-opus-4-6 claude-opus-4-7
/claire-bump-model claude-sonnet-4-5 claude-sonnet-4-6

/claire-bump-model claude-opus-4-6 claude-sonnet-4-7  # refused — cross-tier
```

---

## `/claire-release [major|minor|patch]`

Cut a new release from the accumulated `## [Unreleased]` entries in `CHANGELOG.md`. Resolves the repository's bound version scheme from `CLAIRE_ORG.md#version-scheme-binding` and determines the bump from the entry content under that scheme's rule (**major** for any breaking change: removed/renamed surface, broken contract, enacted deprecation; **minor** for additive capability: new agents/skills/probes, non-breaking changes; **patch** for fixes/docs only), proposes the next version with its reasoning, and **confirms with the user before writing anything**. The optional argument forces a bump, but the skill still shows its own analysis and warns on a disagreement (e.g. a forced downgrade past a breaking change).

On confirmation it runs the full cut: finalize `[Unreleased]` as `[X.Y.Z] - <date>` and open a fresh empty `[Unreleased]`, bump the README version line, draft `docs/releases/vX.Y.Z.md`, commit `RELEASE-X.Y.Z`, create an **annotated** tag, and — after a final confirmation, since pushing is outward-facing — push the branch and tag.

**Scope:** Runs inline (it pauses for confirmation, so no subagent). Touches `CHANGELOG.md`, `README.md`, and `docs/releases/vX.Y.Z.md`; creates one commit and one annotated tag. Does **not** publish a forge Release object, sync external trackers, or rewrite history — the tag stays local until you confirm the push.

**Outputs:** The proposed version + reasoning, two confirmation gates (version, then push), the release commit, the annotated tag, and a drafted release-notes file the author should read and enrich.

### Example

```
/claire-release           # analyze Unreleased, propose a bump, confirm, cut, tag, push
/claire-release minor     # force a minor bump (still shows analysis)
/claire-release patch     # force patch — warns if the changelog looks like a feature or breaking change
```
