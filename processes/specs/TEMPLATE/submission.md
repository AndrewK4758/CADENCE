# Submission: {TICKET-ID} -- {Title}

> **Author:** write this file before submitting your change. Its `## Description` section is the canonical change-proposal description: paste it into your MR/PR body on GitLab/GitHub, or use it as the cover letter on a SourceHut `git send-email` patchset. Its `## Discussion` section is the canonical review record: append review comments here as they happen. After merge, this file is archived alongside the other spec artifacts and becomes the immutable record of what was proposed, debated, and decided.
>
> **Reviewers:** this is what the code-reviewer and maintainer agents read as "the MR description." Comment on the forge as usual; the author (or you, on append) mirrors the substance back here so the archive carries the record. See [`docs/guides/submitting-changes.md`](../../docs/guides/submitting-changes.md) for the per-forge workflow.

## Status

Draft | Submitted | Under Review | Approved | Merged | Rejected | Withdrawn

> **The review state of this document** -- the change proposal -- not the ticket's lifecycle state.
> `metadata.yaml`'s `status:` field is authoritative for the ticket; this line tracks how far *this
> proposal* has got. They are different vocabularies by design, and neither is a copy of the other --
> `Withdrawn` and `Rejected` above are outcomes of a proposal, and have no counterpart in the ticket
> lifecycle.

## Description

### Tracker

{Include this field **only** when `CLAIRE_ORG.md` §9 (Tracker Binding) binds a tracker **and** the ticket's `metadata.yaml` carries a tracker URL (e.g. `jira_url:`). Render it as a single link line at the very top of the description — e.g. **Tracker:** [{TICKET-ID}]({tracker-url}) — so a reviewer reading the MR/PR sees the link back to the originating issue without scrolling. When no tracker is designated, or `metadata.yaml` carries no tracker URL, **omit this entire field (heading included)** — leave no empty placeholder.}

### Summary

{One line. Name the bounded context(s) and flow(s) the change belongs to. Example: "Add idempotency-key support to the `payments` context's `charge` flow."}

### What this change does

{One paragraph. The change in plain language. What was wrong / missing, what this introduces, why it solves the problem. Link to `spec.md` for the full design; this paragraph is the orientation a reviewer needs before opening the diff.}

### Spec reference

- **Spec:** [`spec.md`](spec.md)
- **Test plan:** [`test-plan.md`](test-plan.md)
- **Decisions:** [`decisions.md`](decisions.md)

For lightweight-track contributions, replace the link above with the abbreviated specification inline — see [`docs/guides/contributor_experience_guide.md`](../../docs/guides/contributor_experience_guide.md) for the required fields.

### Functional Validation

{QA hand-off. Carry this forward from `problem.md`'s `## Functional Validation` section and refine it against what was actually built -- never a fresh empty checklist, and never a silently dropped section. Use EXACTLY ONE of two forms: (a) one or more `- [ ]` items, each an end-user-observable behaviour change a QA engineer can check by hand at the UI/API boundary; or (b) the single line: No behavioral changes expected -- regression testing only. Leaving this subsection unfilled is NOT form (b) -- it projects to the tracker as "NOT SPECIFIED", which is a visible gap, not an assurance.}

- [ ] {Observable change -- what the QA engineer does, and what they should then see}

### Bounded context(s) and flow(s)

- **Context(s):** {list, e.g., `payments`, `notifications`}
- **Flow(s):** {list of flows touched, with links to `docs/flows/{flow-name}.md` if they exist}

### Doc impact

One of:

- **Doc impact: updates** — links to the updated `docs/flows/*.md` or `docs/SYSTEM_OVERVIEW.md` entries.
- **Doc impact: new flow** — links to the new `docs/flows/{flow-name}.md` created for this change.
- **Doc impact: none** — explicit acknowledgment that the change is internal to {context} and does not alter any documented flow.

### Compatibility impact

One of:

- **Compatibility impact: none** — change touches no registered surface and introduces no new public surface. Resolve "registered surface" per `docs/policies/change-tiers.md`'s rule, across **every** registry present (`docs/policies/surface-registry.md`, adopter-owned; `docs/policies/claire-surfaces.md`, core-owned) -- naming one registry makes this line vacuously true in a repo where that registry happens to be empty, which asserts nothing.
- **Compatibility impact: additive** — new surfaces added; no existing consumers affected. Surface registry entries: {list}.
- **Compatibility impact: modification** — existing surface semantics changed. Deprecation plan: {link to plan in spec.md}. Signals shipped: {Deprecation/Sunset headers, structured log warnings, `deprecated_surface_calls_total` metric}.
- **Compatibility impact: removal** — stable surface removed. Sunset date: {YYYY-MM-DD}. Consumer migration guide: {link in `docs/migrations/`}.

### Migrations

If the change includes database migrations:

- **Type:** expand | contract | expand+prep | data-only
- **Reversibility verified:** apply → rollback → reapply test result {paste output or link to CI run}
- **Tag:** `[reversible, idempotent]` on the migration commit
- **Deployment ordering:** {simple expansion | prep-required (interim code first) | contraction follow-up}

If no migrations, write "None."

---

## Forge metadata

- **Forge:** gitlab | github | sourcehut
- **Thread URL:** {MR URL / PR URL / `lists.sr.ht` patchset thread URL — fill on submission}
- **Branch:** {branch name}
- **Target branch:** {main | trunk | develop}
- **Submitted:** {YYYY-MM-DD HH:MM TZ}
- **Patchset versions** (SourceHut only): v1 — {date}, v2 — {date}, …

---

## Discussion

Append-only review log. Authors and reviewers add entries; nothing is rewritten. For SourceHut this is the canonical record (the `lists.sr.ht` thread may move or rot). For GitLab/GitHub this mirrors the forge thread so the archive carries the discussion when the spec freezes.

Each entry follows this shape:

```markdown
### {author handle} — {YYYY-MM-DD HH:MM TZ} — {blocking | suggestion | question | resolution}

> {quoted text, file:line reference, or summary of what is being responded to}

{Reply. Prefix with `[blocking]` or `[suggestion]` per review etiquette in
docs/guides/contributor_experience_guide.md § Review etiquette.}
```

### Initial submission — {YYYY-MM-DD HH:MM TZ}

Author submitted the change proposal. Reviewers begin here.

---

## Resolution

Filled by the archivist (or the maintainer at merge time) after the final gate -- **except
`Follow-ups created`**, which is written at whichever gate dispositions the candidate, and so
may be written **before** the final gate: `/claire-review` step 6 (the only gate a Low-tier
ticket reaches), `/claire-maintain` step 6b, or `/claire-archive` step 2e.

- **Verdict:** accept | postpone | reject | withdrawn
- **Decided by:** {maintainer name}
- **Decided at:** {YYYY-MM-DD HH:MM TZ}
- **Merge commit:** {SHA, or "N/A — not merged"}
- **Merged into:** {branch name}
- **Merged at:** {YYYY-MM-DD HH:MM TZ}
- **Follow-ups created:** carries exactly one of the six forms below, and every
  follow-up candidate raised at any gate -- including a deferred `adr-owed` item -- appears
  exactly once under one of them. The field is
  **never left empty** and **never a bare** `None` / `none` / `n/a` / `(pending)` / an unfilled
  placeholder: an empty field and a deliberately-empty field must be distinguishable, which is
  the whole point of the contract. Filed, Duplicate, Folded, Declined and Deferred may combine,
  each named once per applicable candidate; None owed stands alone. Whenever at least one
  non-blocking finding has been logged (see `docs/policies/finding-classes.md`), every form also
  carries the per-class tally clause, omitting any zero-count class.
  - **Filed** -- one line per follow-up, naming the id, a one-line description, the phase that
    filed it, the date, and its `specs/{ticket-id}/` path. Example:
    `ABC-42 -- backfill the dangling records; filed at maintainer, 2026-01-31, specs/ABC-42/`
  - **Duplicate of \<id>** -- a confirmed candidate that an open ticket already covers; no id is
    allocated. Example:
    `Duplicate of BTG-900 -- jira-reserve.sh drops jira_url on reserve; confirmed at code review.`
  - **Folded into \<id>** -- a confirmed candidate appended into an open, fold-eligible ticket's
    `## Notes`, recorded only after that write lands; no id is allocated. Example:
    `Folded into BTG-901 -- jira-reserve.sh hardening; confirmed at code review.`
  - **None owed** -- an explicit statement that no follow-up was named at any gate, with the
    per-class tally when at least one finding was logged. Examples:
    `None owed -- no follow-up was named at code review, at the maintainer gate, or at archive.`
    `None owed -- 0 candidates; 23 non-blocking findings logged (nit 9, hygiene 11, observation 3).`
  - **Declined** -- an explicit statement naming the candidate count, the phase, and a reason per
    candidate. Example: `Declined -- 1 candidate at the maintainer gate: cosmetic, no defect.`
  - **Deferred** -- an explicit statement naming the cause and stating that the candidates and
    their exact filing commands are recorded in `## Discussion`. Example:
    `Deferred -- no channel was available to collect the confirmation; candidates and their exact
    filing commands are in ## Discussion.`
