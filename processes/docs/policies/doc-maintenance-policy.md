# Documentation Maintenance Policy

This policy defines when and how system-level architecture and flow documentation must be updated alongside code changes. Its purpose is to prevent architectural drift and preserve human comprehension as the codebase evolves.

## When Documentation Updates Are Required

Every MR **must** update system documentation (or explicitly record a verified no-impact statement) whenever it introduces any of the following:

- A new API endpoint (REST, gRPC, or internal RPC)
- A new event or message schema published to a broker or queue
- A new service or bounded context
- A new major capability exposed to users or automation (CLI command, slash command, scheduled job, or other invocable surface — applicable even when no HTTP endpoint or queue event is added)
- A new integration with an external third-party or internal system
- A modification to an existing business flow's sequence (adding steps, removing steps, or reordering execution)
- A change in data ownership (altering which bounded context writes to which tables or stores)
- A change to system boundaries as recorded in `docs/SYSTEM_OVERVIEW.md` (newly owned entities, retired ownership, or a new authoritative source of record for an entity previously managed elsewhere)

## What Constitutes Acknowledgment

Every MR must include one of the following two artifacts:

1. **Doc update committed:** The affected `docs/flows/{flow-name}.md` and/or `docs/SYSTEM_OVERVIEW.md` files are updated directly within the MR.
2. **Explicit no-impact statement:** The MR description (`submission.md`) carries an explicit declaration:
   > Doc impact: none — this change is internal to {context} and does not alter any documented flow.

Omitting both is flagged during code review.

## MR Description Requirements

Every MR description (`submission.md`) must explicitly identify:

- **Bounded context:** Which bounded context(s) the change modifies
- **Flow:** Which business flow(s) the change participates in (referencing `docs/flows/` documents by name)

Stating both up front allows human reviewers to orient themselves in the system architecture before reading a single line of the diff.

## Dependency Graph Maintenance

Repositories adopting CADENCE should use stack-appropriate tooling to generate service and module dependency graphs automatically:

- The generated graph should be embedded in or linked from `docs/SYSTEM_OVERVIEW.md`.
- Graphs should be regenerated whenever service or module topology changes (new services, new cross-context dependencies).
- Specific graphing tools remain stack-specific, but the governance expectation is that the dependency map exists and stays current.

## Human Review for System-Level Docs

Agent-authored modifications to the following architectural documents **always require explicit human approval** at the Maintainer gate:

- `docs/SYSTEM_OVERVIEW.md`
- Any flow document under `docs/flows/`

While agents may draft proposed updates (for example, `cadence-archivist` proposing a flow update after archiving a ticket that added an endpoint), accountable humans decide whether the proposed narrative accurately reflects the live system.

## Reconciliation Sweep Method

`AGENTS.md` Behavior 6 establishes the core *obligation* — "a fact changed anywhere is reconciled everywhere". This section defines the **operational method** for discharging that obligation and serves as its **single authoritative home**: `AGENTS.md` and the `cadence-spec-author` / `cadence-reviewer` role definitions state the obligation and point here without restating the method, because duplicating a multi-step procedure across four files creates four surfaces that can drift apart — the exact failure mode Behavior 6 exists to prevent.

### Two independent searches

Every reconciliation sweep — required whenever a change falsifies a claim the repository makes about itself — executes **two independent searches**:

1. **The identifier search.** Search for the exact code or configuration identifiers being **moved, renamed, or removed**: the condition token, function name, file path, variable, or schema field whose semantics the change alters. This is the mechanical search most sweeps naturally run first.
2. **The claim search.** Search for the **claim's distinctive prose phrasing** — the natural-language terms a narrative document would use to state the property that is now false — selected **independently** of any identifier used in the first search.

The second search must not be a mere casing or punctuation variant of the first. If its search terms are derived from the code identifier, it inherits the identifier search's blind spot and contributes zero additional coverage; derive the query terms from the *conceptual claim*, and verify that those terms would not have been matched by search 1 alone.

**Both search queries and both resulting hit sets must be recorded** in the ticket's `decisions.md` or MR description (`submission.md`): document the exact search executed and the list of files returned by each. An empty hit set is a concrete finding and must be recorded explicitly — it distinguishes "no other document asserts this claim" from "nobody checked."

### Why the second search exists

An identifier-keyed search **cannot reach** a narrative document that states the now-false property **in prose** without mentioning any code identifier modified by the diff. Flow documents under `docs/flows/` are the prime example: they explain end-to-end behavior for human readers and frequently omit low-level condition tokens or function names.

The motivating failure occurred in this repository: BTG-105's reconciliation sweep searched exclusively for `syncjs.*` condition identifiers and therefore never surfaced `docs/flows/jira-server-projection.md`, which narrated the exact same behavior in plain English without citing a single `syncjs.*` token. That flow document was not missed due to negligence — it was **structurally unreachable by the identifier query**. No amount of care applied to search 1 could have located it; only a second search keyed on the prose claim could.

### An unrecorded sweep did not happen

A change that **asserts a reconciliation sweep was performed** while recording **neither the search queries nor their hit sets** is **not accepted as evidence** that the sweep ran. Reviewers treat an unrecorded sweep identically to a sweep that **was never executed**, requiring the author to run and record it — because from the outside, an unrecorded sweep and a skipped sweep are indistinguishable.

The written record is the evidence; a bare assertion is not.

**Claiming that no document under `docs/flows/` covers a journey is itself a hit-set assertion** — it states the outcome of a claim search. The exact same rule governs it: an absence claim recorded without the search query and return that produced it is an unrecorded sweep and is rejected at review, whether the search was skipped or merely left undocumented (`BTG-293`).

### What a reviewer examines

When inspecting a recorded reconciliation sweep, the reviewer verifies that **both searches appear** — the identifier search and the independent claim search — each paired with its own hit set, and that the two are **clearly distinguishable**: a reader must be able to tell which query produced which hit set. A record containing **only a single search** is a one-legged sweep regardless of how it is labeled, and leaves open the exact prose blind spot this method closes.

This requirement is a **normative prose obligation** enforced by human reviewers at the **Code Review and Maintainer gates** alongside the rest of this policy. It is **deliberately not mechanized as a regex gate**: a script attempting to judge whether free-form prose "adequately recorded two independent hit sets" would act as a shallow content **classifier** that is fail-open by construction — and a brittle automated check over a substantive engineering duty is worse than human review alone because it turns an unfulfilled obligation into a green checkmark. Should future recurrences ever demonstrate that gate review is insufficient, that evidence will ground a dedicated ticket to revisit enforcement rather than a silent heuristic script.

### Ruling (BTG-293)

**Verdict.** The prose obligation specified above is **sound as a governance duty** and **insufficient when recorded only as a bare conclusion**. The historical misses were defects in how sweeps were recorded rather than in the two-search duty itself: this ruling tightens the recording standard in prose and narrows one downstream reviewer check without introducing new automated scripts.

**Evidence.** Re-measured across the archived ticket corpus at commit `8085a5ee`: the confirmed false-absence class against `docs/flows/jira-server-projection.md` totals **seven instances** — a **verified floor**, not claimed as exhaustive — **revised upward from** the **four** instances initially cited at ticket intake. Detection breakdown across those seven instances: **0 of 7** caught at the Code Review gate, **5 of 7** caught at the Maintainer gate, **1 of 7** caught in-ticket during authoring, and **1 of 7** caught post-merge during Archive. Complete measurement commands, corpus scope, and per-ticket breakdowns are preserved in `archive/BTG-293/spec.md` under `## Measurement`. All figures characterize **this framework repository** at commit `8085a5ee`; an adopting repository's historical distribution may differ.

**Reasoning.** Three candidate mechanical gates were evaluated and rejected on empirical grounds rather than personal preference:

- **Directory non-emptiness gate** (rejecting any flow-doc absence claim whenever `docs/flows/` is non-empty) was rejected on measured grounds: it triggers on 158 of 307 archived tickets, roughly 151 of which state flow-doc absence truthfully — yielding a ~96% false-positive rate.
- **Resolvable citation checked by a shape-only linter** was rejected on measured grounds: it catches 0 of 7 historical misses because every one of the seven could have emitted the "no flow coverage" token syntactically, while breaking the Stable, 2-release-cycle `specs/TEMPLATE/*` surface contract.
- **Derived path-coverage declarations** were rejected on measured grounds: the very first coverage declaration drafted for this repository referenced a file path that has never existed at any commit, meaning automated derivation would have resolved coverage to false for the exact journey it was meant to protect.

**The selected design's own catch rate**, measured against the identical seven-ticket class: the tightened reviewer rule below (requiring that any flow-doc absence claim include a recorded search, **that its actual return be recorded rather than summarized as a conclusion**, and **that the search's scope cover the full scope of the absence claim**) catches **7 of 7** confirmed instances (re-verified at cycle-3 code review, `decisions.md` DEC-016, supersedes the **6 of 7** count noted at cycle 2). `BTG-184`, the single borderline case, documented a search whose *stated* scope was sufficient (listing `docs/flows/` for a repo-wide absence claim) but recorded only a **conclusion** ("confirmed by listing `docs/flows/`") rather than the **returned file list**. **A stated conclusion is not a recorded return**: treating "confirmed by listing X" as a valid return would allow an erroneous "confirmed" to pass uninspected. Requiring the actual return closes the gap **structurally** on form and scope alone, without engaging in forbidden content classification (`archive/BTG-113` DEC-019). See `archive/BTG-293/spec.md` `## Measurement` M-5 for the per-ticket verification recipe.

Full design exploration and tradeoff analysis are recorded in `archive/BTG-293/spec.md` under `## Design Exploration`.

**Re-measurement trigger.** This ruling will be reopened if, across the next **three** confirmed occurrences of this class, the Code Review gate's detection rate remains at the **0 of 7** baseline and either (a) more than one of the three escapes past all pre-merge human gates, or (b) a second `docs/flows/` document experiences the same false-absence pattern. Reference baselines in this repository at commit `8085a5ee`: **0 of 7** caught at Code Review, **5 of 7** caught at Maintainer Acceptance, **1 of 7** escaped past all pre-merge gates. Both trigger conditions are objectively verifiable by any reader without relying on subjective interpretation.

## Enforcement

Documentation freshness is enforced across two pre-merge gates and one post-merge archival backstop:

1. **Code review gate:** The `cadence-reviewer` agent checks for required documentation updates or an explicit no-impact acknowledgment. Missing documentation is raised as a non-blocking finding, **with one strict exception (BTG-293): an affirmative claim that no `docs/flows/` document covers the change — when recorded with no search, with a search that states only a conclusion instead of its return, or with a search scoped narrower than the claim — is a BLOCKING finding** (see `### Ruling (BTG-293)` above and `artifacts/roles/cadence-reviewer.md`'s Documentation Freshness check). All other documentation-freshness findings, including a properly scoped, return-recording absence statement, remain non-blocking. **Historical baseline in this repository at commit `8085a5ee` (BTG-293):** the Code Review gate caught **0 of 7** confirmed instances prior to the tightened return-recording check.
2. **Maintainer gate:** The `cadence-maintainer` evaluates whether the change alters documented business flows and whether `docs/SYSTEM_OVERVIEW.md` remains an accurate map of the system. Chronic or systemic neglect of documentation currency may be escalated to a blocking finding. **Historical baseline in this repository:** the Maintainer gate caught **5 of 7** confirmed instances.
3. **Archive step (observed backstop, not a pre-merge gate):** `cadence-archivist` drafts proposed flow-doc updates after merge and served as the **post-merge backstop** that caught the remaining instance not intercepted pre-merge (**1 of 7**).

The historical catch numbers above describe **this repository** at commit `8085a5ee`; an adopting repository's metrics may vary. Consult `### Ruling (BTG-293)` above and `archive/BTG-293/spec.md` `## Measurement` for full reproduction details.

## Flow Documentation Lifecycle

1. **New flow:** Whenever a specification introduces a net-new end-to-end business journey, create `docs/flows/{flow-name}.md` from the flow template.
2. **Modified flow:** Whenever a specification alters the step sequence or boundary contracts of an existing flow, update the corresponding `docs/flows/{flow-name}.md` document in the same change.
3. **Deprecated flow:** When a business flow is retired, move its documentation file to `docs/flows/archive/` and remove its active entry from `docs/SYSTEM_OVERVIEW.md`.
4. **Related specs:** Upon archival, append a reference link to the implementing specification under the flow document's "Related Specs" section.
