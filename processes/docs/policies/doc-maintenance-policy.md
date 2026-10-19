# Documentation Maintenance Policy

This policy defines when and how system-level documentation must be updated alongside code changes. The goal is to prevent erosion of human understanding as the system evolves.

## When Documentation Updates Are Required

An MR **must** update documentation (or explicitly acknowledge no update is needed) when it introduces any of the following:

- A new API endpoint (REST, gRPC, or internal)
- A new event or message type published to a queue
- A new service or bounded context
- A new major capability surfaced to consumers (CLI command, slash command, scheduled job, or other invocable surface — applies even when no HTTP endpoint or queue event is added)
- A new integration with an external system
- A change to an existing flow's sequence (new steps, removed steps, reordering)
- A change to data ownership (which context writes to which tables)
- A change to system boundaries as documented in `docs/SYSTEM_OVERVIEW.md` (newly-owned data, removed ownership, or a new authoritative source for an entity previously owned elsewhere)

## What Constitutes Acknowledgment

One of the following must be present in the MR:

1. **Doc update committed:** The relevant `docs/flows/{flow-name}.md` and/or `docs/SYSTEM_OVERVIEW.md` are updated in the MR.
2. **Explicit no-impact statement:** The MR description includes:
   > Doc impact: none — this change is internal to {context} and does not alter any documented flow.

The absence of both is flagged during code review.

## MR Description Requirements

Every MR description must state:

- **Bounded context:** Which context(s) this change lives in
- **Flow:** Which business flow(s) this change participates in (reference `docs/flows/` by name)

This enables reviewers to orient themselves in the system before examining the diff.

## Dependency Graph Maintenance

Projects adopting this framework should use language-appropriate tooling to auto-generate service/module dependency graphs:

- The generated output should be referenced from (or embedded in) `docs/SYSTEM_OVERVIEW.md`
- Regeneration should occur when service topology changes (new services, new inter-service dependencies)
- The choice of tooling is project-specific; the convention is that the graph exists and is current

## Human Review for System-Level Docs

Agent-proposed changes to the following files **always require human approval** at the maintainer gate:

- `docs/SYSTEM_OVERVIEW.md`
- Any file under `docs/flows/`

Agents may propose updates (e.g., the archivist after archiving a spec that introduced a new endpoint), but humans decide whether the proposed change accurately represents the system.

## Reconciliation Sweep Method

`CLAUDE.md` Behavior 6 states the *obligation* — "a fact changed anywhere is reconciled everywhere". This section states the **method**, and is its **only home**: `CLAUDE.md` and the `claire-spec-author` / `claire-reviewer` role prose continue to state the obligation and never restate the method, because a method copied into four places is four copies to drift — the same failure the obligation exists to prevent.

### Two independent searches

A reconciliation sweep — run for any change that falsifies a claim the repository makes about itself — performs **two independent searches**:

1. **The identifier search.** The identifiers being **moved, renamed, or removed**: the condition name, function, path, variable, or field whose meaning the change alters. This is the search a sweep already runs.
2. **The claim search.** The **claim's distinctive phrasing** — the words a document would use to assert the property that is now false — chosen **independently** of any identifier in the first search.

The second search is not a spelling variant of the first. If its terms are derived from the identifier, it inherits the identifier search's blind spot and adds nothing; pick the phrasing from the *claim*, then check that it would not have been found by search 1.

**Both searches and both hit sets are recorded** in the change's decision log or MR description: each search as it was actually run, and the set of files it returned. An empty hit set is a result and is recorded as one — it is the difference between "nothing else asserts this" and "nobody looked."

### Why the second search exists

An identifier-keyed sweep **cannot reach** a document that asserts the now-false property **in prose** while **naming no** identifier the change touched. Flow documents are the canonical members of that class: they narrate a flow for a human reader and may contain not one of the names the change moved.

The motivating instance is real and in this repository. BTG-105's reconciliation sweep searched for `syncjs.*` condition names, and so never reached `docs/flows/jira-server-projection.md`, which describes the same flow in prose and contains no condition name to match. That document was not overlooked through carelessness — it was **unreachable by the search that was run**. No amount of diligence applied to search 1 would have found it; only a second search keyed on the claim would.

### An unrecorded sweep did not happen

A change that **claims a sweep** was performed while recording **no search and no hit set** is **not accepted as evidence** the sweep occurred. A reviewer treats it as a sweep that **did not run**, and asks for it — the same disposition, whether the omission was an oversight or the sweep was genuinely skipped, because from outside the two are indistinguishable.

The record is the evidence. The claim is not.

**An assertion that no document under `docs/flows/` covers this journey is itself a hit set** — it is the claim search's result. The rule above applies to it unchanged: an absence recorded without the search that produced it is an unrecorded sweep, and is treated as one, whether the search was skipped or simply never written down (`BTG-293`).

### What a reviewer examines

When a recorded sweep is examined, the record must show **both searches** — the identifier search and the claim search — each with its own hit set, and the two must be **distinguishable**: a reviewer has to be able to see which search produced which hit set. A record showing **only one search** is a one-search sweep, whatever it is labelled, and carries the blind spot this method exists to close.

This rule is a **prose obligation**, checked by a human at the **code-review and maintainer gates** like the rest of this policy. It is **deliberately not mechanized**: a gate that tried to decide whether some free text "recorded both hit sets" would be a content **classifier**, fail-open by construction — and a weak gate over a real obligation is worse than the obligation alone, because it converts an unmet duty into a green check. If a recurrence ever shows the prose obligation is insufficient, that is the trigger to revisit this, in a ticket that argues it — not a gap to quietly fill.

### Ruling (BTG-293)

**Verdict.** The prose obligation defined above is **sufficient as an obligation** and **insufficient as recorded**. The defects found are in the record, not in the duty: this ruling corrects the record in prose and narrows one downstream check; no new mechanism is introduced.

**Evidence.** Re-measured against the archived corpus at commit `8085a5ee`: the confirmed false-absence class on `docs/flows/jira-server-projection.md` is **seven** — a **confirmed** count, and **at least** that many, not claimed as exhaustive — **corrected from** the **four** originally cited when this ticket was filed. Catch distribution across the seven: **0 of 7** caught at the code-review gate, **5 of 7** at the maintainer gate, 1 of 7 in-ticket, 1 of 7 post-merge at archive. The full measurement, with the command, corpus and unit behind every figure, is recorded in `archive/BTG-293/spec.md` under `## Measurement`. Every figure in this ruling describes **this repository**, at the commit named above; an adopting repository's own record may differ.

**Reasoning.** Three candidate mechanisms were evaluated and rejected on measured grounds, not preference:

- **Directory non-emptiness** (refuse any absence claim while `docs/flows/` is non-empty) was rejected on measured grounds: it fires on 158 of 307 archived tickets, of which roughly 151 assert absence truly — a ~96% false-positive rate.
- **A resolvable citation validated by a shape-only gate** was rejected on measured grounds: it catches 0 of 7 outright, because every one of the seven could have emitted the "no coverage" token freely, and it breaks the Stable, 2-release-cycle `specs/TEMPLATE/*` surface.
- **Derived coverage declarations** were rejected on measured grounds: the first such declaration ever authored for this repository named a path that has never existed at any commit, so the derivation would have resolved absence to true for the very journey it was meant to cover.

**The selected design's own catch rate**, measured the same way and stated rather than left implicit: the narrowed check adopted below (an absence claim's recorded search must exist, **its recorded return must be recorded, not merely concluded**, and **its recorded scope must cover the claim's scope**) catches **7 of 7** against this same confirmed class (re-derived at the cycle-3 code-review gate, `decisions.md` DEC-016, correcting a **6 of 7** figure first recorded at cycle 2). `BTG-184`, the one candidate miss, recorded a search whose *stated* scope was adequate (a listing of `docs/flows/` itself, matching a repo-wide claim) but whose statement — "confirmed by listing `docs/flows/`" — names what was searched and then records a **conclusion** ("confirmed"), not a **return**. **A recorded conclusion is not a recorded return**: the cycle-2 figure treated "confirmed by listing X" as satisfying the return-recording conjunct, which is the lighter reading and the one that lets a false "confirmed" pass; the gate ruled the other way. This closes the miss **structurally**, by the return-recording conjunct alone, without judging whether the claimed search actually ran — the content-classification `archive/BTG-113` DEC-019 forbids stays unengaged; the check remains scope and form only. Per-ticket recipe in `archive/BTG-293/spec.md` `## Measurement` M-5.

Each option is argued in full in `archive/BTG-293/spec.md` under `## Design Exploration`.

**Re-measurement trigger.** This ruling reverses if, across the next **three** confirmed instances of the class, the code-review gate's catch rate stays at the **0 of 7** baseline and either (a) more than one of the three escapes past every pre-merge human gate, or (b) a second `docs/flows/` document accumulates the same failure. Baselines this is measured against: **0 of 7** caught at code review, **5 of 7** at the maintainer gate, **1 of 7** escaped past every pre-merge gate — all in this repository, at the commit named above. Either limb is checkable by a reader other than this ruling's author, without needing to agree with the author about anything else.

## Enforcement

Documentation freshness is enforced at two gates, plus an observed post-merge backstop:

1. **Code review gate:** The code-reviewer agent checks for doc updates or explicit acknowledgment. Missing documentation is flagged as a non-blocking issue, **with one narrowed exception (BTG-293): an affirmative flow-doc-absence assertion recorded with no search, with a search whose return is recorded only as a conclusion, or with a search scoped narrower than the claim, is blocking** — see `### Ruling (BTG-293)` above and `artifacts/roles/claire-reviewer.md`'s Documentation Freshness check. Every other doc-freshness finding, including a correctly-scoped, return-recording absence claim, stays non-blocking. **Measured record for this repository, at commit `8085a5ee` (BTG-293):** the code-review gate has **not caught** the affirmative flow-doc-absence class — **0 of 7** confirmed instances were caught here.
2. **Maintainer gate:** The maintainer evaluates whether the change impacts documented flows and whether SYSTEM_OVERVIEW.md remains accurate. Systemic neglect of documentation freshness may be escalated to blocking. **Measured record for this repository:** the maintainer gate has caught the **majority** of the confirmed instances — **5 of 7**.
3. **Archive step (observed, not a gate):** `claire-archivist` drafts flow-doc updates post-merge and is the **observed post-merge backstop** that caught the one remaining confirmed instance not caught pre-merge (**1 of 7**).

The figures above describe **this repository**'s measured record only, at the commit named above; an adopting repository's own record may differ. See this section's `### Ruling (BTG-293)` above and `archive/BTG-293/spec.md` `## Measurement` for the full figures and reproduction recipes.

## Flow Documentation Lifecycle

1. **New flow:** When a spec introduces a new end-to-end business flow, create `docs/flows/{flow-name}.md` from the template.
2. **Modified flow:** When a spec modifies an existing flow's sequence, update the relevant flow doc.
3. **Deprecated flow:** When a flow is no longer active, move its doc to `docs/flows/archive/` and remove it from SYSTEM_OVERVIEW.md.
4. **Related specs:** Append a link to the implementing spec in the flow doc's "Related Specs" section after merge.
