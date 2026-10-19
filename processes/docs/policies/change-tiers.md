# Change Tiers — Right-Sizing the Process

Not every change needs the full weight of the agentic SDLC. This policy defines four tiers based on objective triggers, each with a clear set of required and skipped process steps. The goal: appropriate rigor for the risk, no more.

## Tier Assignment

**Author proposes, triage validates.**

1. The author states the tier in the MR description (e.g., `Tier: Low`)
2. The triage agent (or CI check) validates the claim against objective triggers by scanning the diff
3. If the actual change matches a higher tier's triggers, the pipeline flags a mismatch and blocks until the author either:
   - Escalates to the correct tier (and follows its requirements)
   - Justifies why the lower tier applies (reviewer must agree)

Reviewers can also escalate at any gate: "This looks High, not Medium — needs full spec."

### Policy-tooling consistency

When a change modifies a tier, gate, or policy contract in this file or any other `docs/policies/` governance document — **or, since [ADR_CLAIRE-0100](../ADR/0100-the-policy-tooling-enumeration-obligation-extends-to-the-core-surface-registry-and-the-org-bindings.md), `docs/policies/claire-surfaces.md` itself (including its table SHAPE: a new table, a new column, a renamed column — not only its rows) or any `CLAIRE_ORG.md` binding, meaning any section that is a registered surface under the class predicate *a section is a registered surface iff it is a per-adopter-substituted contract that at least one CLAIRE tool or role resolves as a value, **and** is declared as a contract rather than as a practice* (both limbs bind; the second excludes a section that declares itself not a binding, even where a tool does parse it)** — the spec author must **enumerate every skill, agent, and doc that operationalizes or describes the affected policy, and confirm each honors the new contract.** Any tool or doc that does not is fixed in the same change or filed as a named follow-on ticket in the same change -- never left as a dangling risk note. Record the enumeration, which locations resolved, and its outcome in the spec's Compatibility Impact section so the check is auditable at the Code Review and Maintainer gates, not performed silently.

**Resolve the locations before you search; never assume them.** They are the runtime-neutral source of record where the repository has one -- `artifacts/commands/` (skills), `artifacts/roles/` (agents) -- and the installed definitions the host runtime actually loads, in the install tree of the runtime bound in `docs/agentic-sdlc/CLAIRE_ORG.md#runtime-binding` (Runtime Binding), which names that tree so you never have to assume a runtime. An adopting repository holds the installed definitions but NOT the runtime-neutral source, so a scope fixed to the neutral paths alone resolves to nothing there.

**Total non-resolution is a halt, never a finding.** If no searched location resolves any skill definition or any agent definition at all, the enumeration is broken, not empty -- halt and name every path searched. Never report "no tooling operationalizes this policy" on the strength of a path that does not exist in this repository (BTG-188).

**Deliberately NOT in scope:** `docs/guides/`, `docs/flows/`, `docs/agentic-sdlc/` narrative documents and the two insight registers. No tool resolves their content as a value, so the same predicate that draws the boundary above keeps them out. This clause and `artifacts/roles/claire-spec-author.md`'s step-8h scope note are the extension's **two carriers** and must always agree; an extension recorded in only one of them is a drifted representation, not a partial answer.

This is a workflow-embedded forcing function, not a reminder: it exists because a recorded-but-unembedded lesson (PROD_CLAIRE-004's) demonstrably failed to prevent recurrence (PROD_CLAIRE-005). See [ADR_CLAIRE-0013](../ADR/0013-governance-doc-changes-enumerate-operationalizing-tooling.md) for the rationale and `artifacts/roles/claire-spec-author.md` (step 8h, "Policy-tooling consistency check") -- in an adopting repository, the installed copy of that same agent definition -- for the spec-author's operational procedure.

### Resolving "registered surface"

Several triggers below turn on whether a change touches a **registered surface**. A *registered surface* is any surface listed in **any** surface-registry document present in the repository being classified. **CLAIRE defines exactly two such documents, and the enumeration below is the complete set** — the opening clause quantifies over *presence*, not over *membership*, so "any document present" means "each of these two that this repository has", never "these two and whatever else looks like a registry". Consult every one that is present:

- `docs/policies/surface-registry.md` — this project's own, **adopter-owned** surfaces.
- `docs/policies/claire-surfaces.md` — the CLAIRE framework's **core-owned** surfaces. Present in the framework repo and in every repo that adopted at or after v4.0.0.

**`PROJECT_INTENT.md` section 5 is NOT one of them** (BTG-275, ruled at its spec-approval gate). Its *Public Surfaces* table is the repository's **charter** — a statement of what it holds itself out as offering — not a surface-registry document, so it does not participate in this rule and a surface listed only there is not registered by that listing. `ADR_CLAIRE-0028`'s "every surface-registry **document** present" does not reach it. This was a live contradiction until BTG-275 settled it: section 5 calls `docs/policies/*.md` Stable wholesale, while `docs/policies/test-scope.md` and `docs/policies/change-tiers.md` each carry a **Beta** row, so a classifier who read section 5 as a registry reached two stabilities for one file. Where the charter and a registry row both speak, **the registry row governs** — it is what carries a guarantee period, a consumer list and a deprecation obligation.

Three rules govern the resolution:

1. **Union, not choice.** A change touches a registered surface if it touches a surface listed in *any* present registry. Consult all of them before concluding "none".
2. **Absent is not an error.** A registry document that does not exist in this repository contributes no surfaces, and its absence needs no comment.
3. **Empty is never evidence.** A registry that exists but lists no surfaces contributes no surfaces — and is never, on its own, grounds for concluding that a change touches no registered surface. If every present registry is empty, the trigger cannot be evaluated: say so and escalate rather than resolving it permissively.

If no registry document is present at all, the surface triggers cannot be evaluated. Halt and name the documents that were looked for — never treat their absence as "no registered surfaces".

**This document is itself a registered surface**, and says so here rather than leaving a reader to discover it: `docs/policies/change-tiers.md` is registered **whole**, at **Beta**, with a guarantee period of **1 release cycle**, in `docs/policies/claire-surfaces.md` (BTG-275, discharging BTG-082 DEC-003). The narrower `#per-tier-spec-requirements` section carries its own row at the **same** level and period, so the two rows and this sentence give one answer. Earlier prose describing this file as *Stable* was a characterization no row ever carried and has been withdrawn.

Every trigger below that turns on registered surfaces resolves through this rule; none names a registry document of its own. Which surfaces belong in which registry is background, recorded in [the surface-registry split note](../migrations/claire-surfaces-split.md), and what changed for adopters when this rule replaced the previous single-registry wording is recorded in [the resolution migration note](../migrations/registered-surface-resolution.md) — both are background, and this rule is fully decidable without reading either.

---

## The Four Tiers

### Trivial

**Triggers (all must be true):**
- No source code changes -- only documentation, dependency updates, or **configuration
  values** (see [Configuration: value vs. shape](#configuration-value-vs-shape))
- No new API surfaces, events, or schema changes
- No behavioral changes to production code

**What's required:**

| Step | Documentation-only | Config / Dependencies | Release cut |
|---|---|---|---|
| CI checks (lint, build) | Yes | Yes | Yes |
| Human reviewer | No — auto-merge if CI passes | Yes — one reviewer | Yes — release manager |
| Spec (problem.md) | No | No | No |
| `submission.md` | No | No | **Yes — at `specs/RELEASE-X.Y.Z/submission.md`** |
| Agents | No | No | No |
| Tests | No (unless doc build/link check) | Yes — verify no breakage | No (release-cut commit is documentation-only) |

**Examples:** README updates, CHANGELOG edits, comment fixes, adding a dev dependency, changing an
existing non-secret configuration **value** (no key added, removed, or retyped -- see
[Configuration: value vs. shape](#configuration-value-vs-shape)), fixing a typo in an error
message string.

#### Configuration: value vs. shape

A configuration change qualifies for Trivial when it changes **values only**. It does not
automatically qualify when it changes the configuration's **shape**.

A change is **value-only** when *all four* of these hold across the whole diff:

1. **Key set unchanged** -- no configuration key is added, removed, renamed, or moved to a
   different section or file.
2. **Types unchanged** -- every changed key's value keeps the same type and shape: a scalar stays
   the same scalar type, a list stays a list, a map stays a map with the same key set.
3. **No secrets** -- no changed key holds a secret or credential. Secret rotation follows your
   secrets-handling path, never this one.
4. **Nothing but configuration in the diff** -- no source file, test, migration, or build script
   changes in the same change.

Anything else is a **shape** change: a **schema** key added, removed, renamed or moved, or a
value's type changed. A shape change does **not** automatically qualify for Trivial -- and it carries no
automatic tier of its own either. It is evaluated against the Low, Medium and High triggers below
on its own merits. (In practice a new key is usually added *because* new code reads it, and that
source-code change independently triggers at least Low.)

**What counts as a key.** Predicate 1 is about configuration whose **keys are a fixed schema** --
the names consumers bind to. Some configuration instead holds a **name-keyed lookup dictionary**,
whose keys are data: one half of a data pair, looked up by matching a value carried elsewhere in
the same configuration, never referenced by name in code. Retargeting such a dictionary --
swapping which names it carries -- changes **values**, not shape, and keeps the Trivial grant.
What identifies one is that no consumer names any of its keys: a consumer that hard-codes one has
taken a dependency the structure never offered. A **schema** key added, removed, renamed or moved
is still a shape change. One residual this grant does not cover: because such a dictionary is one
half of a data pair, retargeting it carries a **pairing-consistency obligation** -- every name the
other half still points at must remain resolvable -- and the Trivial grant does not check that.
Retarget both halves together, or verify the pairing separately; a half-landed retarget type-checks
and classifies Trivial while leaving a target nothing can reach.

**A value-only change stays Trivial even when the setting affects runtime behavior.** Feature
flags, routing rules, timeouts and thresholds are configuration precisely so their values can
change without a code change. "It affects runtime behavior" describes all configuration, so it
cannot, on its own, be an escalation trigger.

**What counts as configuration.** A data document your application reads for its settings and
that contains no executable logic. Settings expressed **in code** -- a constants class, a settings
module, a hardcoded default -- are source code: changing them is a source-code change and this
rule does not apply. Where a file mixes data with executable logic, treat it as source code.

**Why a value change is safe at this tier.** Shape is what consumers bind to, and it is unchanged;
the reachable code paths are the ones already shipped and tested; and a well-formed test suite
never asserts against the application's real configuration values -- it uses mock or fixture values
independent of them -- so a value change cannot invalidate the suite. Note that Trivial for
configuration is not an unreviewed merge: the table above requires one reviewer and a test run for
the `Config / Dependencies` column, which is where a suite that does depend on real configuration
values shows up.

#### Release cuts

A **release cut** is a commit that bumps the version badge, adds release notes under `docs/releases/v<version>.md` (`<version>` in the shape the repository's [version-scheme binding](../agentic-sdlc/CLAIRE_ORG.md#version-scheme-binding) declares -- `X.Y.Z` under `semver`, `YYYY.WW.PATCH` under `calver-yyyy-ww`), and moves `CHANGELOG.md`'s `[Unreleased]` section into a versioned entry. Release cuts qualify as Trivial in every other respect, **but they always require a `submission.md` at `specs/RELEASE-<version>/submission.md`**, written before tagging, capturing the release as a change proposal: what's being packaged, the discussion record from the cut, and the resolution (tag SHA, push timestamp, merge-into-trunk plan).

The rationale is archival: a release is the most consequential commit a project makes (it's a contract with downstream consumers), and it benefits from the same versioned, repo-resident discussion record that v3.2.0 introduced for substantive changes. The release notes capture *what shipped*; `submission.md` captures *what we proposed, debated, and decided about cutting the release.*

The `submission.md` should ideally be authored on the release branch *before* `git tag`, so the tag includes it. If the artifact is missed at tag time, backfill it as a follow-up commit on the release branch with a `Backfill note` block at the top explaining the sequence — do *not* move the published tag.

---

### Low

**Triggers (any one):**
- Source code changes **within a single bounded context**
- No new public surfaces (endpoints, events, queues)
- No database schema changes
- No changes to registered surfaces (resolve per [Resolving "registered surface"](#resolving-registered-surface) — consult **every** registry present; an empty one is not evidence)
- No cross-boundary dependencies introduced

**What's required:**

| Step | Required |
|---|---|
| CI pipeline | Validate + Unit Tests + Doc Check |
| Spec | `problem.md` only (acceptance criteria sufficient, no Zachman grid) |
| SCOUT decomposition | No |
| Agents | code-reviewer only |
| Human gates | Code Review (1 reviewer) |
| Maintainer gate | No |
| Integration tests | Only if touching data access |
| Journey / Chaos | No |
| Migration verify | No (no schema changes allowed at this tier) |
| Boundary documentation | No (single context, no boundary crossing) |
| Flow doc update | No |

**Examples:** Bug fix within a service, internal refactor (rename, extract method), adding validation to an existing endpoint, performance optimization that doesn't change behavior.

> **`/claire-implement` at Low tier.** The `/claire-implement` skill and implementer agent read `metadata.yaml`'s `tier: Low` and accept `problem.md`'s acceptance criteria as the sole spec input -- no `spec.md`, `test-plan.md`, or `status: spec-approved` is required. The implementer derives its Implementation Order directly from the AC checklist using the standard TDD sequencing rule and applies the same strict red-green-accumulate-commit discipline. See `artifacts/commands/claire-implement.md` (Prerequisites) and `artifacts/roles/claire-implementer.md` (Inputs / Low tier).

> **Follow-up filing point, per tier.** A follow-up named at a gate is filed at a gate, via
> `/claire-triage --file-only`, on explicit human confirmation. Which gate that is depends on the tier:
> **Low** -- `/claire-review` is the filing point, because it is the only human gate a Low-tier ticket
> reaches (the Low row above gives `Maintainer gate | No`); `/claire-archive` remains the completeness
> backstop. **Trivial** -- the Trivial table gives `Agents | No`, so `/claire-review` never runs and
> **no governed phase raises a candidate at all**. Coverage there is `/claire-archive` alone, and only for
> the one Trivial case that carries a change-proposal record: a release cut. That is a finding about
> what is reachable, not an omission to be fixed later -- recorded here so a reader does not believe
> coverage exists where it cannot. **Medium and High** -- `/claire-review`, then `/claire-maintain`, then
> `/claire-archive`, in that order, each presenting only the candidates that carry no disposition yet.
> Every path records the outcome in `submission.md`'s `Follow-ups created`, which is never left
> empty and never a bare none-shaped token. Candidates are `out-of-scope-defect` findings
> (`docs/policies/finding-classes.md`); `adr-owed` is disposed of at `/claire-archive` only, at
> every tier that reaches it.

> **`/claire-review` at Low tier.** The `/claire-review` skill and `claire-reviewer` agent read `metadata.yaml`'s `tier: Low` and review the change against `problem.md`'s Acceptance Criteria checklist (plus `decisions.md` if present) as the behavioral contract. `spec.md` and `test-plan.md` are not produced at Low tier, so their absence is compliant and is never flagged as a process violation; Test Coverage is verified against the AC checklist rather than a `test-plan.md`. Medium/High review is byte-preserved. If the tier is absent or unrecognized, the review falls back to the Medium/High (spec-driven) contract and notes the unresolved tier -- it never assumes Low. See `artifacts/commands/claire-review.md` (step 2) and `artifacts/roles/claire-reviewer.md` (Inputs / Low tier).

---

### Medium

**Triggers (any one):**
- New feature **within one bounded context**
- Touches a registered public surface (modifies an existing endpoint's behavior) — resolve per [Resolving "registered surface"](#resolving-registered-surface)
  - *UI page routes* (the UI Page Routes category of `docs/policies/surface-registry.md`): adding a
    route, adding an alias, or changing a registered route's authorization gate or accepted query keys
    touches a registered surface -- at least Medium. A rename that keeps the old path as a registered
    alias is Medium. Deprecating or removing a route path, including a rename that drops the old path,
    is High under "Deprecates or removes a registered public surface" below. Not a route-surface
    change: edits inside a page that alter none of its path, gate or query keys; in-app navigation
    call sites. (CNJ-971)
- Database schema change (new column, new table within one context)
- New internal integration (calling an existing internal service for the first time)

**What's required:**

| Step | Required |
|---|---|
| CI pipeline | Full pipeline except chaos matrix |
| Spec | Full: problem.md + spec.md + test-plan.md + decisions.md + submission.md (plus `design-options.md` when the explorer pre-step runs — an input, not a required artifact; the machine-readable table below is authoritative for `/claire-implement`) |
| SCOUT decomposition | Yes |
| Zachman grid | Abbreviated — System Model and Technology Model rows only (skip Scope and Business Model if the business context is obvious) |
| Agents | explorer, spec-author, code-reviewer, maintainer; **architect (optional)** — see note below |
| Human gates | Spec Review + Code Review + Maintainer |
| Integration tests | Yes |
| Contract tests | Yes, if touching registered surfaces |
| Journey / Chaos | Only if the feature has external dependencies or multi-step mutations |
| Migration verify | Yes, if schema changes present |
| Boundary documentation | Only if calling another service |
| Flow doc update | Only if modifying an existing flow's sequence |

**Architect at Medium tier (opt-in):** The spec-author may invoke the architect agent during step 8 of spec authoring (compatibility-impact assessment) when **either** of the following is true:
- The change touches a Stable-tier registered surface — resolve per [Resolving "registered surface"](#resolving-registered-surface), then read the matched row's stability level — or
- The change introduces a new internal integration (a new call to an existing internal service).

When invoked, the architect's output (Observed/Inferred/Unknown findings, Draft Contracts, Open Questions) feeds directly into the spec's compatibility-impact section. Invocation at Medium tier remains opt-in by the spec-author; it is never mandatory unless the change escalates to High tier.

**Examples:** Adding a new field to an existing API response, new database column with backfill, new validation rule that changes existing behavior, integrating with an internal notification service.

---

### High

**Triggers (any one):**
- Crosses bounded context boundaries (produces/consumes events across contexts)
- New service, new bounded context, or new event/queue type
- Deprecates or removes a registered public surface — resolve per [Resolving "registered surface"](#resolving-registered-surface)
- Changes data ownership (which context writes to which tables)
- New external system integration
- Multi-service deployment coordination required

**What's required:**

| Step | Required |
|---|---|
| CI pipeline | Full pipeline including chaos matrix |
| Spec | Full: all artifacts (plus `design-options.md` when the explorer pre-step runs — an input, not a required artifact; the machine-readable table below is authoritative for `/claire-implement`) |
| SCOUT decomposition | Yes, all ACs |
| Zachman grid | Full — all four rows (Scope, Business Model, System Model, Technology Model) |
| Agents | All: architect, explorer, spec-author, code-reviewer, maintainer, migration-author (if schema) |
| Human gates | All 4: Spec Review + Code Review + Maintainer + Deploy Validation |
| Integration tests | Yes |
| Contract tests | Yes — golden-file + consumer contracts + versioned integration |
| Journey tests | Yes — deterministic pass required |
| Chaos matrix | Yes — all applicable profiles |
| Migration verify | Yes, if schema changes present |
| Boundary documentation | Yes — header comments, integration-hint docstrings |
| Flow doc update | Yes — create or update `docs/flows/{flow-name}.md` |
| SYSTEM_OVERVIEW.md update | Yes, if new service/context/dependency |

**Examples:** Adding a new microservice, introducing an event-driven flow between two contexts, deprecating a public API version, changing which service owns a database table, integrating with a new third-party payment provider.

---

## Per-Tier Spec Requirements

**Machine-readable contract — authoritative for `/claire-implement`.**

`/claire-implement` (and the `claire-implementer` role's direct-delegation Phase 0 mirror) reads **THIS table** —
not the prose "What's required" tables above — to decide, before implementation begins: which spec
artifacts a ticket of a given tier must have, whether the spec-approval human gate applies, and which
pre-implementation `status` is valid. This table is the **sole authority** the `/claire-implement` skill
consults for that decision. Editing a cell here changes `/claire-implement` behavior with **no** edit to the
skill source (`artifacts/commands/claire-implement.md`).

The prose tier definitions above remain the human-facing narrative. Where a reader needs the exact
inputs the skill enforces, **this table is authoritative for the skill**; keep the two consistent, but
the skill only ever reads this table.

| Tier    | Required spec artifacts (must exist)              | Spec-approval gate applies | Valid pre-implementation status |
|---------|--------------------------------------------------|----------------------------|---------------------------------|
| Trivial | metadata.yaml                                    | No                         | triaged                         |
| Low     | metadata.yaml, problem.md                        | No                         | triaged                         |
| Medium  | metadata.yaml, problem.md, spec.md, test-plan.md | Yes                        | spec-approved                   |
| High    | metadata.yaml, problem.md, spec.md, test-plan.md | Yes                        | spec-approved                   |

Notes:

- **Required spec artifacts** are file-existence requirements under `specs/<ticket-id>/`. Artifacts
  present beyond the required set are used without error (never treated as forbidden).
- **Spec-approval gate applies = Yes** means `/claire-implement` requires the spec to have passed the human
  Spec Review gate (`status: spec-approved`, or a later lifecycle status once implementation has
  begun) before proceeding. **= No** means the gate is not applied and the tier's *Valid
  pre-implementation status* (e.g. `triaged`) is sufficient to proceed past the spec gate.
- If this section is **absent or unparseable** (e.g. an older `change-tiers.md` fork), `/claire-implement`
  **halts** with a configuration error naming this file (fail-closed) rather than assuming a
  permissive (skip all gates) or restrictive (assume a full spec) default.

---

## Quick Reference

```
┌──────────────────────────────────────────────────────────────────┐
│                        CHANGE TIER DECISION                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Does it change source code?                                       │
│    NO  ↓                                                           │
│      Is it a configuration change?                                 │
│        NO  → Trivial   (docs, dependency update)                   │
│        YES ↓                                                       │
│          Value-only? (schema key set + types unchanged, no secret, │
│                       no source/test/migration/build file)         │
│            YES → Trivial                                           │
│            NO  ↓  (shape change -- evaluate below on its merits)   │
│    YES ↓                                                           │
│                                                                    │
│  Does it cross a bounded context boundary?                         │
│    YES → High                                                      │
│    NO  ↓                                                           │
│                                                                    │
│  Does it add/modify a public surface, schema, or integration?      │
│    YES → Medium                                                    │
│    NO  ↓                                                           │
│                                                                    │
│  Is it contained within a single context with no new surfaces?     │
│    YES → Low                                                       │
│                                                                    │
└──────────────────────────────────────────────────────────────────┘
```

## Tier Validation in CI

The doc-freshness check script (`ci-templates/scripts/check-doc-freshness.sh`) can be extended to validate tier claims:

1. Parse `Tier: X` from MR description
2. Scan diff for tier triggers:
   - New files matching surface patterns → at least Medium
   - Changes to files in multiple bounded contexts (by folder convention) → High
   - Migration files present → at least Medium
   - New event/queue types → High
   - Configuration file changed with an altered key set, a changed value type, a secret key, or
     alongside a source file, test, migration or build script → a **shape** change, evaluated
     against the Low/Medium/High triggers on its own merits; a value-only configuration diff →
     Trivial
3. If detected tier > claimed tier → fail with: "This change triggers Tier {X} requirements. Update your MR or justify the lower tier."

## Escalation

At any gate, a reviewer can escalate:

> "This is classified as Low but introduces a new integration with the payment service. Escalating to Medium — please add a spec with SCOUT decomposition."

The author either complies or justifies. The reviewer has final say. Disagreements escalate to the maintainer (or tech lead if the maintainer is the author).

**When an escalation lands after implementation has begun**, the ticket owes the new tier's spec artifacts by one of exactly two paths, and the escalating decision entry must name which: **backfill** them, or **promote** existing `decisions.md` entries in lieu of them. Promotion is available **only where the promoted entries predate and drove the implementation** — they were recorded to direct the work and the work followed them — and the escalating entry must name each promoted entry and state why it qualifies. Entries written after the code they describe do not qualify: that ticket backfills. An append-only correction to a qualifying entry does not disqualify it. An escalation raised before implementation begins is unaffected — that ticket simply runs the higher tier's workflow forward.

## Anti-Gaming

- **Splitting a High change into multiple Low MRs** to avoid process: The maintainer gate catches this. If a sequence of Low MRs collectively constitutes a High change (new flow, new service built incrementally), the maintainer flags it and requires retroactive documentation.
- **Claiming Trivial for a configuration change that alters the configuration's shape:** the
  Trivial grant covers configuration **values** only -- see
  [Configuration: value vs. shape](#configuration-value-vs-shape). A **schema** key added, removed,
  renamed or moved, a value's type changed, a secret touched, or a source file, test, migration or build
  script in the same diff takes the change out of the grant, and it is evaluated against the
  Low/Medium/High triggers
  on its own merits. CI can validate those four predicates from the diff. What CI must *not* treat
  as gaming is a value-only change to a setting that affects runtime behavior -- that is what
  configuration is for.
- **"It's just a refactor"** for changes that alter public behavior: The contract tests catch this. If golden files change, it's at least Medium regardless of the author's claim.
