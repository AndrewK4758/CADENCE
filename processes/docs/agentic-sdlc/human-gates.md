# Human Gates & Governance

## The Four Gates

Four mandatory human approval checkpoints govern the CADENCE lifecycle. Agents analyze and recommend; humans decide.

The irreplaceable value humans bring to each gate is *judgment an AI agent cannot supply*: business context, organizational awareness, operational intuition, and architectural taste. AI agents handle mechanical verification — structural completeness, cross-artifact consistency, scenario coverage, and pre-review sweeps. Humans answer "is this the right capability to build, and will it hold up in production?"

**Right-sized by tier.** Not every change traverses all four gates — see `docs/policies/change-tiers.md`. Trivial changes require only passing CI. Low-tier changes require a single code review gate. Medium and High-tier changes progress through the full gate sequence described below.

**Forge-neutral terminology.** This guide uses "MR" as generic shorthand for *a submitted change proposal*. On GitLab that is a Merge Request; on GitHub a Pull Request; on SourceHut a patchset thread on `lists.sr.ht`. Gate requirements are identical across forges; only the transport layer differs. See [`docs/guides/submitting-changes.md`](../guides/submitting-changes.md) for per-forge mechanics. Where this document says "comment on the MR," the SourceHut equivalent is "reply to the patchset thread"; where it says "edit directly on the MR," the SourceHut equivalent is "publish a v2 patchset."

**`submission.md` as the canonical repository record.** Every change proposal is also tracked as a versioned artifact in [`specs/{ticket-id}/submission.md`](../../specs/TEMPLATE/submission.md), which holds the proposal description (matching the MR/PR body or cover letter), the append-only review discussion, and the final gate resolution. Reviewers comment on the forge or mailing list as normal, and the substance is mirrored into `submission.md` so `archive/{ticket-id}/` preserves the complete review record after merge.

## Non-Negotiable: Maintain Your Architectural Mental Model

**Every human reviewer must be able to situate a change within the overall system architecture.** Whenever a specification or MR fails to give you enough clarity to update your mental model of the system — which bounded contexts participate, which business flows change, how data moves across boundaries, and which invariants hold — **reject it and request regeneration.**

This requirement is absolute. Human gates exist so human engineers retain architectural ownership of the system. Approving a change that no human genuinely understands erodes architectural integrity. Specifically:

- **Before approving any gate**, verify you can answer: "Which bounded context or service owns this? Which business flow does it participate in? What assumptions does it make about upstream and downstream contexts?"
- **If you cannot answer those questions** from the specification or MR as written, the artifact is incomplete. Reject it with explicit feedback naming the missing architectural context.
- **If the change introduces a new boundary, service, or business flow** that cannot be traced end-to-end in `docs/SYSTEM_OVERVIEW.md` or `docs/flows/`, require those system documents to be updated prior to approval.
- **If the change alters an existing business flow** whose flow document is missing or outdated, require the flow document to be created or refreshed inside the same MR.

The bar for approval is simple: after signing off, you should be able to explain to a teammate what this change does to the *system* — not merely what lines changed in the diff — without re-opening the files.

---

## How Project Maturity Shifts Reviewer Focus

Weight your review lens according to where the repository sits in its lifecycle:

| Project State | Spec Reviewer Weights (Gate 1) | Maintainer Focus (Gate 3) |
|---|---|---|
| **Greenfield / early** | Business outcome + structural simplicity. "Ship safely to learn." Defer irreversible commitments to the last responsible moment and preserve room for stakeholder iteration. | Is the scope tight enough to learn from quickly? Are we locking in abstractions prematurely? |
| **Mature / extending** | Architectural fit + operational resilience. Does this introduce warranted complexity? Does the design respect established boundaries without accumulating technical debt? | Does this capability belong inside this repository's core, or should it live at the edge (a plugin, sidecar, or separate service/repo)? |

When in doubt: early-stage systems err toward simplicity and rapid learning; mature systems err toward boundary discipline and contract stability.

---

### Gate 1: Spec Review (Architect)

**You are approving:** The architectural design and behavioral contract, before production code is written.

#### What the AI already did

The `cadence-explorer` agent (at Medium/High tier) generated 2–3 structurally distinct, unranked design options in `design-options.md`, and `cadence-spec-author` grounded the system in the Contextual Grounding Matrix (6W×4L), decomposed every acceptance criterion through CHORD, mechanically derived edge cases and runtime observability seams, evaluated the active CADENCE Engineering Pillars, converged on a winning design option, and authored `test-plan.md` with ordered Gherkin scenarios.

#### First: Orient in the Architecture

Before checking individual sections, answer three questions using `docs/SYSTEM_OVERVIEW.md` and `docs/flows/`:

1. Which bounded context(s) does this specification operate within?
2. Which business flow(s) does it introduce, modify, or extend?
3. What assumptions does it make about neighboring contexts — data ownership, event schemas, or shared invariants?

If `spec.md` does not make those answers immediately clear, **reject and request regeneration**: "I cannot place this change within the system architecture. Clarify which bounded context owns this behavior, which flows are affected, and what cross-boundary assumptions exist."

#### What only you can judge

- **Architectural placement** — Can you trace this change end-to-end across the system map? Does the responsibility sit in the right layer and context?
- **Business intent fidelity** — Does this specification solve the real problem described in `problem.md` without losing nuance?
- **Organizational context** — Sequencing dependencies, team bandwidth, cross-team contention, and delivery timing
- **Stakeholder alignment** — Would the requester who filed `problem.md` recognize this specification as fulfilling their need?
- **Decision timing** — Does the specification lock in an architectural commitment that should remain open for now?

#### Maturity-dependent lens

**Greenfield:** Is this the smallest coherent design we can ship to validate the domain? Are we over-architecting before real usage patterns exist?

**Mature:** Does this honor existing bounded-context seams? Are cross-cutting requirements (auth, auditability, observability seams, surface compatibility) fully addressed?

#### Checklist

| Check | What to Look For |
|---|---|
| **Architectural clarity** | **Can you identify which bounded context(s) and flow(s) this touches? If not, reject.** |
| Contextual Grounding Matrix (6W×4L) | Are the relevant cells populated? Do the System and Technology models align with the Scope and Business models? |
| CHORD decomposition | Is every acceptance criterion decomposed across Conditions, Handling, Outcomes, Rules, and Deltas? Are edge cases and seams derived? |
| Engineering Pillar evaluation | Are pillar assessments candid? Are any flagged trade-offs resolved via the precedence matrix? |
| Compatibility impact | Are affected public surfaces identified across both registries? Are deprecation plans complete where required? |
| Proposed design | Does the design fit the codebase structure? Are interface and endpoint signatures sound? |
| **Design Exploration** | Did an INDEPENDENT `cadence-explorer` agent produce the option set in `design-options.md` rather than `cadence-spec-author` inventing its own strawmen? Are there 2–3 STRUCTURALLY distinct options, each steelmanned on its own merits? Does any option departing from established patterns explicitly label unresolved failure modes as `UNKNOWN` rather than guessing or omitting them? Does the convergence block name the winner, the specific winning pillar axis over the specific runner-up, a falsifiable flip-condition, and the strongest objection to the winner? **Then record your Gate 1 outcome** — see Feedback Loop below. If the section carries the not-performed marker, treat that as a disclosed fallback rather than an automatic pass and decide explicitly whether to accept it. |
| Test plan | Does the Gherkin scenario suite cover every CHORD dimension and derived seam? Are required compatibility tests specified? |
| Journey invariants | When declared: are invariants falsifiable, traced to CHORD Rules/Conditions/Deltas, and mapped to chaos profiles? See [Part 8 of the journey & chaos tests guide](../guides/journey-and-chaos-tests.md#part-8-for-spec-reviewers-gate-1--journey-invariant-quality). A *journey* is an end-to-end business workflow spanning service boundaries or external dependencies; *invariants* are domain truths that must hold even under infrastructure chaos. |

#### Feedback Loop

When a specification requires adjustments, choose one of two paths:

**Direct edit** — For localized edits: naming, prose clarity, or minor table adjustments. Edit `spec.md` or `test-plan.md` directly on the spec branch/MR.

**Comment and regenerate** — For structural changes, missing domain constraints, or reconsidering the chosen design option. Record your feedback on the spec MR and invoke `/cadence-spec` to regenerate the affected sections so CHORD decompositions, observability seams, and Gherkin scenarios stay synchronized. Re-review the regenerated specification.

**Record your Design Exploration outcome.** Whichever review path you take, append **one fixed-form outcome line** to `specs/<ticket-id>/decisions.md` recording your disposition of the spec-author's convergence. Use this exact canonical format (stated here and intentionally omitted from files scanned by the override-rate sweep):

```
Gate 1 Design Exploration outcome: <value> -- <one sentence of why>
```

`<value>` must be one of these three literals:

| Value | Meaning |
|---|---|
| `accepted as recommended` | You accepted the spec-author's chosen winner on its stated pillar axis. |
| `accepted with amendment` | You kept the winning option but modified the rationale, the flip-condition, or the scope of the design. |
| `overridden to a different option` | You selected a different architectural option from `design-options.md`. |

This line is strictly an **append** to `decisions.md`. Never edit or overwrite the spec-author's original convergence entry — `decisions.md` is append-only, and overwriting the recommendation erases the audit trail showing how the human gate shaped the design.

**Override-rate tracking** measures `accepted with amendment` plus `overridden to a different option` divided by total Gate 1 outcomes across `specs/*/decisions.md` and `archive/*/decisions.md`, **excluding `specs/TEMPLATE/`** (so template examples never pollute the count). A sustained near-zero override rate across real multi-option specs is a warning signal that Gate 1 review has become rubber-stamp theater — a calibration finding for Process Retro / Agent Calibration rather than a defect in the current ticket.

**Record your Gate 1 rulings (BTG-331).** Every specification authored from `specs/TEMPLATE/spec.md` carries the sentinel `**Gate 1 rulings:** required` under Open Questions. When present, append **one ruling line per required item** to `specs/<ticket-id>/decisions.md` using this exact grammar:

```
Gate 1 ruling: <item> -- <agree|amend|override> -- <why>
```

`<item>` is the `OQ-N` identifier (or `design` when `design-options.md` exists — though the BTG-201 Design Exploration outcome line above already satisfies `design` without needing a duplicate line). `<why>` states your concrete reasoning. `{{sidecar:cadence-spec:verify-facts.sh}} --rulings <ticket-id>` classifies each ruling line from its content alone:

| Label | Meaning |
|---|---|
| `diverged` | You recorded `amend` or `override` — changing the proposed default. |
| `examined` | You recorded `agree`, and your `<why>` cites an independent resolvable file path or `path:N` coordinate not already cited in `spec.md`. |
| `accepted-as-presented` | You recorded `agree` without an independent file citation. |

The derived label never blocks progression — it provides an objective audit trail of whether an `agree` ruling contributed independent codebase verification. `/cadence-implement` halts only when a **required** item (`OQ-N`, or `design` when owed) lacks a ruling line or when a `Gate N ruling:` line violates the grammar above. Because `decisions.md` is append-only, a later ruling line for the same `<item>` **supersedes** an earlier one. Gate 2 and Gate 3 reviewers may optionally record rulings using the same grammar (`Gate 2 ruling: ...`, `Gate 3 ruling: ...`).

---

### Gate 2: Code Review (Engineer)

**You are approving:** The implementation against its governing tier contract (`spec.md` + `test-plan.md` at Medium/High tier; `problem.md` acceptance criteria at Low tier).

#### What the AI already did

Prior to your review, the local pre-review sweep (`offload_deep_review` on `:11434`) and the `cadence-reviewer` agent have already:
- Verified every acceptance criterion against its production code implementation
- Checked automated test coverage against every Gherkin scenario in `test-plan.md` (or against `problem.md` acceptance criteria at Low tier, per `docs/policies/change-tiers.md`)
- Audited adherence to Contextual Grounding constraints and CADENCE Engineering Pillars (`<400`-line file ceiling, comment discipline, structured logging, audit trail coverage, CHORD observability seams)
- Flagged mechanical, stylistic, and anti-pattern defects
- Applied the two-axis adversarial review lens — **verify-the-claim** (checking every "this is safe because X" assumption against the authoritative source of X in seed data, config, engine docs, sibling writers, and production wiring) and **locate-the-failure** (probing for defects inside the diff, in upstream code it calls, in downstream consumers, and in unchanged sibling code whose assumptions the diff silently invalidated), plus silent-failure probes (silent fallbacks/stubs, overly broad exception handlers, partial multi-writer state updates, stale state across transitions, test-fake blind spots, and environment asset parity gaps)

#### First: Orient in the Architecture

Before inspecting the code diff, verify:

1. Which bounded context does this MR modify?
2. Which business flow(s) does it participate in?
3. Does `submission.md` (and the MR/PR description) state both clearly up front?

If you cannot tell where the change lives in the system from `submission.md` and `spec.md`, **return the MR for clarification** before reviewing line-by-line code.

#### What only you can judge

- **System comprehension** — After reviewing the MR, can you explain its system-level effect to another engineer without looking at the diff? If not, do not approve yet.
- **Production realism** — Will this behave safely under real production traffic, data skew, and failure modes? The AI verifies code-to-spec conformance; you verify code-to-reality conformance.
- **Tacit domain invariants** — Edge cases and operational nuances that live in team experience rather than written specs
- **Operational failure modes** — Lock contention, large-tenant query amplification, retry storms, or memory pressure under load
- **In-flight coordination** — Overlapping work on adjacent branches or upcoming migrations that could collide with this change
- **Long-term maintainability** — Is the abstraction clean, and would you feel confident debugging this module during a 2 a.m. incident?

#### Checklist

| Check | What to Look For |
|---|---|
| **Architectural orientation** | **Can you name the bounded context and business flow this MR modifies? If not, send it back.** |
| Contract compliance | Is every acceptance criterion completely implemented? |
| Test coverage | Does every Gherkin scenario in `test-plan.md` (or every `problem.md` AC at Low tier) have a corresponding automated test? Are compatibility tests included? |
| Pillar compliance | Authored files `<400` lines, 100% mutation audit records, structured JSON logs with correlation IDs, CHORD observability seams emitted, zero anti-patterns |
| TDD commit history | Does git history show clean red-green-accumulate commits progressing through the Implementation Order? |
| Layer & boundary discipline | Clean separation across domain, application, API, and persistence layers |
| Security boundary posture | Server-side principal enforcement, input validation, zero sensitive data exposure |

---

### Gate 3: Maintainer Acceptance (Maintainer)

**You are approving:** The change proposal's repository-level fit and long-term impact — not line-level code correctness (which Gate 2 already verified).

#### What the AI already did

The `cadence-maintainer` agent generated an 8-dimension maintainer assessment evaluating surface compatibility, architectural integrity, `PROJECT_INTENT.md` charter alignment, ongoing maintenance cost, security boundary impact, release readiness, dependency health, and system documentation currency.

#### First: Orient in the Architecture

At Gate 3 you act as the steward of system-wide coherence. Before reviewing the 8 dimensions:

1. Open `docs/SYSTEM_OVERVIEW.md` and locate the bounded context(s) and business flow(s) touched by this MR.
2. Confirm the context interaction map and architectural invariants still hold once this MR lands.
3. Whenever the MR introduces a new service, bounded context, or business flow, verify you can trace it on the system map; if not, require `docs/SYSTEM_OVERVIEW.md` and `docs/flows/` updates before accepting.

If the MR's system-wide impact remains opaque, **postpone** acceptance and request architectural clarification.

#### What only you can judge

- **Repository boundary placement** — In a mature codebase, does this capability belong in core, or should it live in an adapter, plugin, sidecar, or separate repository?
- **Charter alignment** — Does this advance the core mission in `PROJECT_INTENT.md`, or does it edge into a declared non-goal?
- **Compound maintenance trajectory** — Where does our operational and cognitive load land in six months if we accept changes shaped like this one?
- **Ownership & team capacity** — Does the owning team have the bandwidth and domain charter to support this capability long-term?

#### Maturity-dependent lens

**Greenfield:** Are we introducing rigid abstractions before the domain model has stabilized? Keep early structure lightweight enough to evolve rapidly.

**Mature:** Is this the right home for this responsibility? Does it preserve clean seams and keep the core domain model cohesive?

#### Checklist

| Check | What to Look For |
|---|---|
| **System model intact** | **Can you place this change on `docs/SYSTEM_OVERVIEW.md`? Are affected flow docs current? If not, require updates.** |
| Surface compatibility | Are public surface modifications backed by deprecation plans and updated in the surface registry? |
| Architectural integrity | Does the change honor ratified ADRs and `PROJECT_INTENT.md` invariants? Are new patterns warranted? |
| Charter alignment | Does this serve the repository's mission in `PROJECT_INTENT.md` without violating Non-Goals? |
| Maintenance cost | Are new dependencies, operational procedures, or abstractions justified by the value delivered? |
| Security boundary impact | Any expansion of attack surface, trust-boundary shift, or supply-chain exposure? |
| Release readiness | CHANGELOG entry drafted, migration/rollback plan verified, follow-ups dispositioned in `submission.md`? |
| Dependency health | Compatible licenses, active maintenance, and zero known vulnerabilities? |

Your verdict at Gate 3 is **Accept**, **Postpone**, or **Reject**.

---

### Gate 4: Deploy Validation (PM / Stakeholder)

**You are approving:** The deployed capability operating in a non-production environment against the acceptance criteria and `## Functional Validation` checklist in `problem.md`.

Gate 1 verified intent on paper; Gate 4 confirms that the running software delivers the intended business outcome in practice.

---

## Surface Registry & Deprecation Policy

Two living governance documents protect backwards compatibility across the repository.

### The Surface Registries — What Is Public and What Is Promised

**Two registries exist, and "registered surface" resolves across the union of both** (`docs/policies/change-tiers.md`, *Resolving "registered surface"*): `docs/policies/surface-registry.md` records this repository's **adopter-owned** public surfaces, while `docs/policies/cadence-surfaces.md` records the CADENCE framework's **core-owned** surfaces. Framework-owned surfaces are registered exclusively in `cadence-surfaces.md`; project-owned APIs, events, schemas, and configs are registered in `surface-registry.md`.

Each registry entry declares the surface's stability tier (`Stable`, `Beta`, `Deprecated`, `Internal`), guarantee window, known consumers, and sunset date (when deprecated).

**Update discipline:** `cadence-spec-author` proposes registry additions or updates whenever a spec introduces or alters a public surface. `cadence-maintainer` audits the registries during every Gate 3 evaluation and flags any unrecorded surface change as a blocking gap prior to merge.

### `docs/policies/deprecation-policy.md` — Retiring Public Surfaces Safely

Defines minimum guarantee windows by surface class, mandatory runtime deprecation signals (HTTP `Deprecation` and `Sunset` headers, structured log warnings, and `deprecated_surface_calls_total` counters), consumer migration guide standards, version support limits, and emergency breaking-change procedures.

### Compatibility Test Suites

Three automated test suites guard public contracts against accidental breakage:

| Test Type | Purpose |
|---|---|
| **Golden-file tests** | Snapshot API response bodies and event payload shapes; CI fails on any unreviewed structural diff |
| **Consumer-driven contracts** | Authored from the consumer's perspective; verify the producer satisfies every required field and invariant |
| **Versioned integration tests** | Replay recorded requests from prior supported API versions against the current service implementation |

These suites are planned in `specs/TEMPLATE/test-plan.md` and enforced as blocking checks during Gate 2 code review.

---

## Customization

### Adding a New Engineering Pillar

1. Define the pillar in your organization's `docs/agentic-sdlc/CADENCE_ORG.md` with its definition, Contextual Grounding alignment, concrete measures, anti-patterns, and one-sentence decision rule.
2. Insert the pillar into the Precedence Matrix at the rank matching your organization's risk posture.
3. `specs/TEMPLATE/spec.md` includes an `### Additional Pillars` section out of the box — no template structural change is needed.

### Modifying a Specification Template

Edit the template files under `specs/TEMPLATE/`. All CADENCE agents read these templates when initializing new ticket directories, so adjustments take effect immediately on the next `/cadence-triage` or `/cadence-spec` invocation.

### Tuning Agent Behavior

Agent definitions in `.agents/agents/{agent-name}/AGENT.md` (and projected runtime trees such as `.gemini/` or `.claude/` per `docs/policies/cli-runtime-adoption-policy.md`) are compiled from the runtime-neutral source under `artifacts/roles/{agent-name}/` via `ci-templates/scripts/cadence-compile.sh`. Edit the neutral source under `artifacts/roles/` and recompile. Key tuning points per role:

- **`cadence-explorer`:** Tune the number of required options, structural distinctness rules, and `UNKNOWN` failure-mode labeling — while preserving the strict no-ranking rule that guarantees independent exploration
- **`cadence-spec-author`:** Adjust workflow step ordering, add domain-specific modeling rules, or tune pillar evaluation depth
- **`cadence-architect`:** Configure cross-repository boundary mappings, contract dimensions, epistemic classification thresholds, and draft Gherkin contract formats
- **`cadence-implementer`:** Add language- or framework-specific TDD conventions and test-runner invocation rules
- **`cadence-reviewer`:** Tune review dimensions, adversarial verification probes, and `[BLOCKING]` vs `[SUGGESTION]` thresholds
- **`cadence-maintainer`:** Adjust the 8 assessment dimensions, charter-enforcement rules, and post-decision actions
- **`cadence-migration-author`:** Customize ORM/database discovery and expand/contract safety checks
- **`cadence-triage-agent`:** Adjust classification heuristics, scope sizing rules, and tracker seed-read handling
- **`cadence-archivist`:** Customize ADR promotion criteria, insight extraction, and external tracker sync hooks

### Adding a New Skill

Author the neutral command source under `artifacts/commands/{skill-name}/` and compile to `.agents/skills/{skill-name}/SKILL.md` (or create a project-local skill in `.agents/skills/{skill-name}/SKILL.md`) with standard YAML frontmatter:

```yaml
---
name: skill-name
description: What the skill does
argument-hint: "[expected arguments]"
arguments: [arg1, arg2]
allowed-tools: Read Write Edit Glob Grep Bash
---
```

Follow the frontmatter with the numbered execution steps.

> **What `arguments:` does and does not guarantee.** The `arguments:` list declares parameter
> **names** for user hints and documentation only and provides **no shell-like binding guarantee**:
> a `$name` token inside the skill body is advisory prose rather than a guaranteed interpolation
> primitive. A skill **must never rely on** an inline argument token to transport multi-word free
> text; whenever a command needs free-form prose, read it from a file path passed as a single bare
> token. See `artifacts/SCHEMA.md`, *What `arguments:` is, and what it is not* (BTG-281).
