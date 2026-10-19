# Human Gates & Governance

## The Four Gates

Four mandatory approval points. Agents recommend; humans decide.

The unique value humans add at each gate is *judgment the AI cannot provide*: business context, organizational awareness, production instincts, and taste. The AI handles mechanical verification — completeness, consistency, coverage. The human handles "is this the right thing to build, and will it actually work?"

**Not all changes pass through all gates.** The process is right-sized by tier — see `docs/policies/change-tiers.md`. Trivial changes need only CI. Low changes need one code reviewer. Medium and High changes use progressively more gates. The table below applies to **Medium and High** tier changes (the full process).

**Forge-neutral language.** This document uses "MR" as the generic shorthand for *the change proposal*. On GitLab that's a Merge Request; on GitHub a Pull Request; on SourceHut a patchset thread on `lists.sr.ht`. Gate behavior is identical across forges; only the transport differs. See [`docs/guides/submitting-changes.md`](../guides/submitting-changes.md) for the three workflows. Where this document says "comment on the MR," the SourceHut equivalent is "reply on the patchset thread." Where it says "edit directly on the MR," the SourceHut equivalent is "send a v2 of the patchset."

**`submission.md` as the canonical record.** The change proposal is also a versioned repository artifact: [`specs/{ticket-id}/submission.md`](../../specs/TEMPLATE/submission.md) carries the description (the same content as the MR body / PR body / cover letter), the discussion log, and the final resolution. Reviewers should treat `submission.md` as authoritative — comment in the forge / on the mailing list, but expect the substance to be mirrored back to `submission.md` so the archive carries the record after merge.

## Non-Negotiable: Maintain Your Mental Model

**Every reviewer must be able to place a change within the overall system architecture.** If a spec or MR does not provide enough clarity for you to extend your mental model of how the system works — which bounded contexts are involved, which flows are affected, how data moves, what invariants hold — **reject it and request regeneration.**

This is not optional. The purpose of human gates is to ensure humans retain architectural ownership. An approved change that no human fully understands is a change that erodes the system. Specifically:

- **Before approving anything**, answer: "Which context/service does this live in? Which flow does it participate in? What does it assume about the rest of the system?"
- **If you cannot answer those questions** from the spec or MR as presented, it is incomplete. Reject it with feedback explaining what architectural context is missing.
- **If the change introduces a new boundary, service, or flow** and you cannot trace it end-to-end in `docs/SYSTEM_OVERVIEW.md` or `docs/flows/`, require that documentation be added before approval.
- **If the change modifies an existing flow** and the flow doc is stale or absent, require it be updated or created as part of the MR.

The standard is: after approving, you could explain to a colleague what this change does to the system — not just the code — without re-reading the diff. If you cannot, you do not yet understand it well enough to approve.

---

## How Project Maturity Shifts Your Focus

Reviewer attention should weight differently depending on where the project sits in its lifecycle.

| Project State | Spec Reviewer Weights | Maintainer Focus |
|---|---|---|
| **Greenfield / early** | Business goals + simplicity. "Ship safely to learn." Defer decisions to the last responsible moment. Preserve flexibility for stakeholder feedback. | Is the scope small enough to learn from? Are we locking in decisions too early? |
| **Mature / extending** | Architecture + fitness. Does this add warranted complexity? Does the design fit the existing system without creating debt? | Should this functionality remain in this codebase, or be pushed toward the edges or into another repo? |

This isn't binary — use judgment. But when in doubt: early projects err toward simplicity and learning; mature projects err toward architectural discipline and boundary enforcement.

---

### Gate 1: Spec Review (Architect)

**You are approving:** The design, not the implementation.

#### What the AI already did

The spec-author agent produced a Zachman-aligned grid, decomposed every AC through SCOUT, derived edge cases mechanically, evaluated quality facets, and drafted a test plan with Gherkin scenarios. The structure is complete.

#### First: Orient in the Architecture

Before evaluating anything else, answer these questions using `docs/SYSTEM_OVERVIEW.md` and `docs/flows/`:

1. Which bounded context(s) does this spec operate within?
2. Which business flow(s) does it modify or extend?
3. What does it assume about adjacent contexts — data ownership, event contracts, invariants?

If the spec does not make these answers obvious, **reject and request regeneration** with feedback: "I cannot place this change in the system architecture. Clarify which context owns this, which flows are affected, and what cross-boundary assumptions exist."

#### What only you can judge

- **Architectural placement** — Can you trace this change through the system? Does it fit where the spec says it fits?
- **Business intent fidelity** — Does this spec actually solve the problem the stakeholder described? Was anything lost in translation?
- **Organizational context** — Roadmap conflicts, team capacity, political constraints, timing concerns
- **Stakeholder alignment** — Would the person who raised this issue recognize this spec as their request?
- **Decision timing** — Are we committing to something we don't need to decide yet?

#### Maturity-dependent lens

**Greenfield:** Is this the minimum spec to ship and learn? Are we making premature architectural commitments? Could we defer a decision and still ship safely?

**Mature:** Does this fit the existing architecture? Are cross-cutting concerns (auth, observability, data contracts) addressed? Does the proposed design respect existing boundaries?

#### Checklist

| Check | What to Look For |
|---|---|
| **Architectural clarity** | **Can you identify which context(s) and flow(s) this touches? If not, reject.** |
| Zachman grid | Are the right cells filled? Do lower levels align with higher? |
| SCOUT decomposition | Is every AC decomposed? Are edge cases derived? |
| Facet evaluation | Are evaluations honest? Are violations justified? |
| Compatibility impact | Are public surface changes identified? Deprecation plans drafted? |
| Proposed design | Does it fit the architecture? Are code signatures correct? |
| **Design Exploration** | Did an INDEPENDENT explorer produce the options, in `design-options.md`, rather than the spec-author authoring its own counter-case? Are there 2-3 STRUCTURALLY distinct options, each steelmanned on its own terms? Does the option departing from established patterns label its failure modes UNKNOWN rather than omitting or guessing them? Does the convergence record name the winner, the specific axis over the specific runner-up, a testable flip-condition, and the strongest objection to the chosen option? **Then record your own outcome** — see Feedback Loop. If the section carries the not-performed marker, that is a disclosed fallback, not a pass: decide deliberately whether to accept it. |
| Test plan | Does the Gherkin coverage match the SCOUT output? Compatibility tests specified? |
| Journey invariants | If declared: are they falsifiable, traced to SCOUT, and correctly mapped to chaos profiles? See [Part 8 of the journey & chaos tests guide](../guides/journey-and-chaos-tests.md#part-8-for-spec-reviewers-gate-1--journey-invariant-quality). A *journey* is an end-to-end business operation that crosses service boundaries or external dependencies (e.g., "Patient Check-In" spanning insurance verification, payment, and provider notification). *Invariants* are business truths that must hold regardless of infrastructure failures — universal constraints like "payment is never captured without prior verification" that chaos tests assert under adversarial conditions. |

#### Feedback Loop

You have two paths when the spec needs changes:

**Direct edit** — For small corrections: naming, wording, minor restructuring. Edit `spec.md` or `test-plan.md` directly on the MR.

**Comment and regenerate** — For larger rethinks, missing context, or "I don't understand why X was chosen." Leave comments on the spec MR describing what's wrong or what question needs answering. Then invoke `/claire-spec` to regenerate the affected sections. The spec-author will incorporate your feedback, and SCOUT will re-derive edge cases from the revised decomposition. Re-review the updated spec.

Use your judgment on which path: if the change is structural enough that SCOUT decomposition or Zachman alignment would be affected, regeneration keeps the spec internally consistent.

**Record your Design Exploration outcome.** Whichever path you take, append **one fixed-form line** to `specs/<ticket-id>/decisions.md` recording what you did with the spec-author's convergence. The canonical form, stated here and deliberately **not** reproduced inside any file the counting sweep reads:

```
Gate 1 Design Exploration outcome: <value> -- <one sentence of why>
```

`<value>` is exactly one of three:

| Value | Meaning |
|---|---|
| `accepted as recommended` | You kept the spec-author's winner, on its stated axis. |
| `accepted with amendment` | You kept the winner but changed the reasoning, the flip-condition, or the scope of the choice. |
| `overridden to a different option` | You selected a different option from `design-options.md`. |

The line is an **append**. It never edits the convergence entry it may disagree with — `decisions.md` is immutable, and a disagreement that overwrites the claim it disagrees with destroys the evidence that the gate did anything.

**Override-rate** is the count of `accepted with amendment` plus `overridden to a different option` over the total, swept across `specs/*/decisions.md` and `archive/*/decisions.md`, **excluding `specs/TEMPLATE/`** — the template would otherwise be counted by its own documented example, which is how a sentinel poisons its own sweep. A sustained near-zero override-rate over a real option set is the signal that this gate has become theater. That is a finding for a future ticket, not a defect in the spec in front of you. Whatever baseline your project starts from is a declared first hypothesis, not a measurement: correct it from your first full review window rather than defending it.

**Record your Gate 1 rulings (BTG-331).** A spec authored under `specs/TEMPLATE/spec.md`'s post-BTG-331 form carries the sentinel `**Gate 1 rulings:** required` in its Open Questions. When it does, append **one line per required item** to `specs/<ticket-id>/decisions.md`, in this fixed grammar:

```
Gate 1 ruling: <item> -- <agree|amend|override> -- <why>
```

`<item>` is the `OQ-N` id (or `design`, when `design-options.md` exists — the BTG-201 outcome line above already covers it and needs no separate `design` line). `<why>` is your own reasoning, not restated boilerplate. `{{sidecar:claire-spec:verify-facts.sh}} --rulings <ticket-id>` derives a label from each line's content, never from who wrote it:

| Label | Meaning |
|---|---|
| `diverged` | You wrote `amend` or `override` — you changed the presented default. |
| `examined` | You wrote `agree`, and your `<why>` independently cites a resolvable path or `path:N` that the spec itself did not already cite. |
| `accepted-as-presented` | You wrote `agree` with no such independent citation. |

The label never blocks and is never a verdict on you — it is a machine-checkable trace of whether a `agree` carried contributed evidence, so a reviewer's own later audit does not have to trust self-report. `/claire-implement` only refuses to start while a **required** item (an `OQ-N`, or `design` when owed) has **no** ruling line, or a `Gate N ruling:` line fails the grammar above — never on the label. A later ruling line for the same item **supersedes** an earlier one (`decisions.md` is append-only; never edit a prior line). Gate 2 and Gate 3 may use the same grammar (`Gate 2 ruling: ...`, `Gate 3 ruling: ...`) — reported by the checker, never required.

---

### Gate 2: Code Review (Engineer)

**You are approving:** The implementation against the spec.

#### What the AI already did

The AI code-reviewer has already:
- Matched every acceptance criterion to its corresponding implementation
- Verified test coverage against each Gherkin scenario in the test plan (at Low tier, where no test plan is produced, against each `problem.md` acceptance criterion instead, per `docs/policies/change-tiers.md`)
- Scanned the codebase for consistency and maintainability issues
- Checked Zachman guardrails and facet compliance
- Flagged mechanical issues (style, patterns, anti-patterns)
- Applied the two-axis adversarial lens — verified each "this is safe because X" claim against the real source of X (real seed/config numbers, engine docs, every sibling writer, prod wiring, the canonical story file — never inherited), and located each candidate failure by its position relative to the diff (in it / in code it consumes / in code that consumes it / in unchanged code whose contract it silently changed — the last is the one diff-review misses by construction), then probed for silent-failure paths (fallbacks/stubs that mask defects, broad `except` clauses, consumed-contract assumptions, invariant completeness across all writers of newly-shared state, reused-state-across-transitions, test/config-environment fidelity, test/fake blind spots, declarative-config & runtime-engine omissions, claimed-bounds/out-of-scope recomputed against real numbers)

#### First: Orient in the Architecture

Before reading the diff, answer:

1. Which bounded context does this MR modify?
2. Which flow(s) does it participate in?
3. Does the MR description state these clearly?

If you cannot answer from the MR description and spec reference alone, **send it back.** An MR that a reviewer cannot place in the system is an MR that cannot be meaningfully reviewed.

#### What only you can judge

- **System comprehension** — After reading this MR, can you explain what it does to the system (not just the code) to a colleague? If not, you don't understand it well enough to approve.
- **Subtle correctness** — Will this actually work in production? Under load? With real data? The AI verifies the code matches the spec; you verify the code matches reality.
- **Domain knowledge** — Business rules the AI can't verify because they live in your head, not in the spec
- **Operational instincts** — "This will time out on the large tenant" or "This will deadlock under concurrent writes"
- **Team awareness** — Who else is touching this area? Will this conflict with in-flight work? Does this create a maintenance burden for the team?
- **Design taste** — Is this the right abstraction? Is the code going to be readable in six months? Would you want to debug this at 2am?

#### Checklist

| Check | What to Look For |
|---|---|
| **Architectural orientation** | **Can you state which context and flow this MR belongs to? If not, send it back.** |
| Spec compliance | Does each AC have a corresponding implementation? |
| Test coverage | Does each Gherkin scenario have a test (at Low tier, where no test plan is produced, does each `problem.md` acceptance criterion have a test instead, per `docs/policies/change-tiers.md`)? Compatibility tests present? |
| Facet compliance | File sizes, audit records, structured logging, observability, no anti-patterns |
| TDD discipline | Does the commit history show one red-green cycle per scenario? |
| Architecture | Layer boundaries, service patterns, data access through repository |
| Security | Auth policies, input validation, no data leaks |

The AI catches the mechanical issues in this checklist. Your review focuses on design judgment, production instincts, and subtle correctness that requires context the AI doesn't have.

---

### Gate 3: Maintainer Acceptance (Maintainer)

**You are approving:** The MR's project-level impact — not code correctness (that was Gate 2).

#### What the AI already did

The AI maintainer agent produced a structured 8-dimension assessment covering backwards compatibility, architectural integrity, goal alignment, maintenance cost, security impact, release readiness, dependency health, and documentation currency.

#### First: Orient in the Architecture

At this gate you are the guardian of architectural integrity. Before evaluating dimensions:

1. Open `docs/SYSTEM_OVERVIEW.md`. Locate the bounded context(s) and flow(s) this MR touches.
2. Verify the dependency graph and interaction map still hold after this change merges.
3. If this MR adds a new service, context, or flow — can you draw it on the existing map? If not, the documentation is incomplete and must be updated before acceptance.

If the MR's impact on the system architecture is unclear to you, **postpone** with feedback requesting architectural clarification. You are the last line of defense against changes that nobody fully understands at the system level.

#### What only you can judge

- **Boundary decisions** — For mature projects: should this functionality remain in this codebase, or should it be pushed toward the edges (a plugin, a sidecar, a separate service, another repo entirely)? The AI can flag complexity growth but cannot make architectural boundary decisions.
- **Strategic fit** — Is this core mission, adjacent, or scope creep? Does it move the project toward or away from its long-term shape?
- **Maintenance trajectory** — Not just "is this maintainable today" but "where does this put us in 6 months if we keep adding at this rate?"
- **Team and org context** — Ownership boundaries, team capacity for ongoing maintenance, political implications of taking on new responsibility

#### Maturity-dependent lens

**Greenfield:** Is this adding premature structure? Are we creating abstractions before we understand the domain? Keep it simple enough to throw away.

**Mature:** Is this the right place for this code? Could it be a library, a separate service, or pushed to a consumer? Are we making the core harder to reason about?

#### Checklist

| Check | What to Look For |
|---|---|
| **System model intact** | **Can you draw this change on the system map? Does SYSTEM_OVERVIEW.md still hold? If not, require update.** |
| Backwards compatibility | Are public surface changes handled with deprecation plans? Surface registry updated? |
| Architectural integrity | Does the change follow existing ADRs? Any new patterns justified? |
| Project goal alignment | Is this core mission, adjacent, or scope creep? |
| Maintenance cost | How many new dependencies, patterns, or infrastructure pieces? |
| Security impact | Attack surface changes, trust boundary shifts, supply chain risk? |
| Release readiness | CHANGELOG updated? Deprecation notices? Migration plan? Rollback documented? |
| Dependency health | Licenses compatible? Known vulnerabilities? Maintained? |

Your decision is **Accept**, **Postpone**, or **Reject**.

---

### Gate 4: Deploy Validation (PM)

**You are approving:** The feature works as intended in a non-prod environment, matching the acceptance criteria in `problem.md`.

This is the stakeholder's moment: does the shipped thing match what was asked for? The spec review validated intent on paper; deploy validation validates intent in practice.

---

## Surface Registry & Deprecation Policy

Two living documents govern backwards compatibility across the project.

### The surface registries — What's public and what's promised

**There are two, and a "registered surface" resolves across both** (`docs/policies/change-tiers.md`, *Resolving "registered surface"*): `docs/policies/surface-registry.md` holds this project's own **adopter-owned** surfaces, and `docs/policies/claire-surfaces.md` holds the CLAIRE framework's **core-owned** ones. A framework-owned surface records in the core-owned registry, in the surface's own row; a row written to the adopter-owned one announces it where no consumer of that surface reads.

Between them they register every public API endpoint, event schema, DTO/response contract, database contract, and configuration key. Each entry records its stability level (Stable, Beta, Deprecated, Internal), guarantee period, known consumers, and sunset date (if deprecated).

**Update policy:** The spec-author adds entries when a spec introduces new public surfaces. The maintainer reads the registry during every MR evaluation, and verifies it is updated for every surface the change adds, deprecates or alters, flagging any gap for the human gate to decide — that gate verification is the operative control, and it is unchanged. Nothing re-checks the registry after merge; the check happens before the change lands, not after.

### `docs/policies/deprecation-policy.md` — How to retire a surface

Covers minimum deprecation periods by surface type, runtime signaling requirements (HTTP `Deprecation`/`Sunset` headers, structured log warnings, `deprecated_surface_calls_total` metrics), migration documentation standards, the sunset process, version support matrix, and emergency breaking change procedures.

### Compatibility Test Suites

Three categories of tests verify that changes do not break existing consumers:

| Test Type | Purpose |
|---|---|
| **Golden-file tests** | Snapshot API response shapes and event payloads; CI fails on unreviewed drift |
| **Consumer-driven contracts** | Written from the consumer's perspective; verify the producer still satisfies expectations |
| **Versioned integration tests** | Replay requests from previous API versions against the current service |

These are specified in `specs/TEMPLATE/test-plan.md` and enforced as blocking issues during code review.

---

## Customization

### Adding a new facet

1. Define the facet in your org CLAIRE config (`docs/agentic-sdlc/CLAIRE_ORG.md`) with: definition, Zachman alignment, measures, anti-patterns, and decision rule.
2. Add it to the precedence matrix with a position that reflects your org priorities.
3. The spec template (`specs/TEMPLATE/spec.md`) already has open-slot facet guidance — no template change needed.

### Modifying a template

Edit the files in `specs/TEMPLATE/`. All agents read these templates when creating new spec directories. Changes take effect immediately for the next `/claire-triage` or `/claire-spec` run.

### Tuning agent behavior

Edit the agent's `AGENT.md` file in `.claude/agents/{agent-name}/`. Key tuning points:

- **explorer:** Adjust how many options are required, what counts as structurally distinct, and the UNKNOWN-labelling rule for unresolved failure modes — but not the no-ranking constraint, which is the role's whole point
- **spec-author:** Adjust step order, add domain-specific instructions, change model selection
- **architect:** Adjust repo-to-concern mappings, contract dimensions to check, epistemic classification thresholds, and Gherkin draft contract format
- **implementer:** Adjust TDD constraints, add language-specific guidance
- **code-reviewer:** Adjust review dimensions, change what counts as [BLOCKING] vs [SUGGESTION]
- **maintainer:** Adjust evaluation dimensions, blocking criteria, deprecation policy references, and post-decision actions
- **migration-author:** Adjust project structure discovery (DbContext, migrations directory) and expand/contract safety rules
- **triage-agent:** Adjust classification rules, integration sources
- **archivist:** Adjust what triggers ADR promotion, sync targets

### Adding a new skill

Create `.claude/skills/{skill-name}/SKILL.md` with the standard frontmatter:

```yaml
---
name: skill-name
description: What the skill does
argument-hint: "[expected arguments]"
arguments: [arg1, arg2]
allowed-tools: Read Write Edit Glob Grep Bash
---
```

Then add the task steps below the frontmatter.

> **What `arguments:` does and does not give you.** The key declares argument
> **names** for documentation and hint purposes and confers **no binding
> guarantee**: a `$name` token in the body is advisory prose, not a substitution
> primitive. A command **must not rely on** such a placeholder to carry a value
> that is not a single bare token; where a command needs free text, take it off
> the argument channel and pass a bare path instead. The canonical statement is
> `artifacts/SCHEMA.md`, *What `arguments:` is, and what it is not* (BTG-281).
