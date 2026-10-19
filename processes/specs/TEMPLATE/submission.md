# Submission: {TICKET-ID} -- {Title}

> **Author:** populate this artifact prior to submitting your change proposal. Its `## Description` section serves as the canonical change-proposal body: copy it into your GitLab MR or GitHub PR description, or use it as the cover letter for a SourceHut `git send-email` patchset. Its `## Discussion` section is the canonical review ledger: append review threads and responses here as they occur. Upon merge, `/cadence-archive` enshrines this file alongside the companion specification artifacts as the permanent, self-contained record of what was proposed, debated, and approved.
>
> **Reviewers:** the `cadence-reviewer` and `cadence-maintainer` agents read this file as "the MR description." Leave review comments on your forge as usual; the author (or reviewer) mirrors the substance into `## Discussion` so the repository archive preserves the full rationale independently of the forge. See [`docs/guides/submitting-changes.md`](../../docs/guides/submitting-changes.md) for per-forge instructions.

## Status

Draft | Submitted | Under Review | Approved | Merged | Rejected | Withdrawn

> **The review state of this change proposal**, distinct from the ticket's lifecycle state.
> `metadata.yaml`'s `status:` field is authoritative for the ticket; this line tracks how far *this
> proposal* has progressed. The two vocabularies are intentionally separate, and neither mirrors the
> other -- `Withdrawn` and `Rejected` are terminal proposal outcomes with no counterpart in the ticket
> lifecycle.

## Description

### Tracker

{Include this subsection **only** when `CADENCE_ORG.md` §9 (Tracker Binding) binds an external tracker **and** the ticket's `metadata.yaml` records a tracker URL (for example `jira_url:`). Render it as a single hyperlink line at the top of the description — e.g. **Tracker:** [{TICKET-ID}]({tracker-url}) — so any reviewer opening the MR/PR can jump directly to the originating tracker issue without scrolling. When no tracker is bound, or `metadata.yaml` carries no tracker URL, **omit this entire subsection (heading included)** — leave no placeholder text.}

### Summary

{One sentence naming the bounded context(s) and business flow(s) touched by this change. Example: "Add idempotency-key enforcement to the `payments` context's `charge` flow."}

### What this change does

{One concise paragraph explaining the change in plain terms: what was broken or missing, what this change introduces, and why it resolves the problem. Link to `spec.md` for full architectural detail; this paragraph gives reviewers clear orientation before they inspect the diff.}

### Spec reference

- **Spec:** [`spec.md`](spec.md)
- **Test plan:** [`test-plan.md`](test-plan.md)
- **Decisions:** [`decisions.md`](decisions.md)

For lightweight-track contributions, replace the links above with an inline abbreviated specification — see [`docs/guides/contributor_experience_guide.md`](../../docs/guides/contributor_experience_guide.md) for the required fields.

### Functional Validation

{QA hand-off. Carry this forward from `problem.md`'s `## Functional Validation` section and refine it against what was actually built -- never a fresh empty checklist, and never a silently dropped section. Use EXACTLY ONE of two forms: (a) one or more `- [ ]` items, each an end-user-observable behaviour change a QA engineer can check by hand at the UI/API boundary; or (b) the single line: No behavioral changes expected -- regression testing only. Leaving this subsection unfilled is NOT form (b) -- it projects to the tracker as "NOT SPECIFIED", which is a visible gap, not an assurance.}

- [ ] {Observable change -- what the QA engineer does, and what they should then see}

### Bounded context(s) and flow(s)

- **Context(s):** {list, e.g., `payments`, `notifications`}
- **Flow(s):** {list of business flows touched, linking to `docs/flows/{flow-name}.md` where present}

### Doc impact

One of:

- **Doc impact: updates** — links to the updated `docs/flows/*.md` or `docs/SYSTEM_OVERVIEW.md` sections.
- **Doc impact: new flow** — links to the newly authored `docs/flows/{flow-name}.md` introduced by this change.
- **Doc impact: none** — explicit statement that the change is internal to {context} and does not alter any documented flow.

### Compatibility impact

One of:

- **Compatibility impact: none** — change modifies no registered surface and introduces no new public surface. Resolve "registered surface" per `docs/policies/change-tiers.md`'s rule across **every** registry present (`docs/policies/surface-registry.md`, adopter-owned; `docs/policies/cadence-surfaces.md`, core-owned) -- citing only one registry makes this claim vacuously true in a repository where that single registry is empty.
- **Compatibility impact: additive** — new public surfaces introduced; zero existing consumers impacted. Surface registry entries added: {list}.
- **Compatibility impact: modification** — existing surface semantics altered. Deprecation plan: {link to plan in `spec.md`}. Runtime signals shipped: {Deprecation/Sunset headers, structured log warnings, `deprecated_surface_calls_total` metric}.
- **Compatibility impact: removal** — stable surface retired. Sunset date: {YYYY-MM-DD}. Consumer migration guide: {link in `docs/migrations/`}.

### Migrations

If the change includes database migrations:

- **Type:** expand | contract | expand+prep | data-only
- **Reversibility verified:** apply → rollback → reapply verification result {paste output or link to CI job}
- **Tag:** `[reversible, idempotent]` on the migration commit
- **Deployment ordering:** {simple expansion | prep-required (interim compatibility code first) | contraction follow-up}

If no database migrations are included, write "None."

---

## Forge metadata

- **Forge:** gitlab | github | sourcehut
- **Thread URL:** {MR URL / PR URL / `lists.sr.ht` patchset thread URL — populate upon submission}
- **Branch:** {branch name}
- **Target branch:** {main | trunk | develop}
- **Submitted:** {YYYY-MM-DD HH:MM TZ}
- **Patchset versions** (SourceHut only): v1 — {date}, v2 — {date}, …

---

## Discussion

Append-only review ledger. Authors and reviewers append new entries chronologically; prior entries are never rewritten. On SourceHut this is the primary permanent record (since `lists.sr.ht` threads can move or expire). On GitLab and GitHub this mirrors the forge review thread so `archive/{ticket-id}/` retains the full discussion when the specification freezes.

Each entry follows this structure:

```markdown
### {author handle} — {YYYY-MM-DD HH:MM TZ} — {blocking | suggestion | question | resolution}

> {quoted text, file:line coordinate, or summary of the point being addressed}

{Response. Prefix with `[blocking]` or `[suggestion]` per the review etiquette in
docs/guides/contributor_experience_guide.md § Review etiquette.}
```

### Initial submission — {YYYY-MM-DD HH:MM TZ}

Author submitted the change proposal. Review begins below.

---

## Resolution

Populated by `cadence-archivist` (or `cadence-maintainer` at merge time) after the final human gate -- **except
`Follow-ups created`**, which is recorded at whichever gate dispositions a candidate, and therefore
may be written **prior to** the final gate: `/cadence-review` step 6 (the sole human gate for a Low-tier
ticket), `/cadence-maintain` step 6b, or `/cadence-archive` step 2e.

- **Verdict:** accept | postpone | reject | withdrawn
- **Decided by:** {maintainer name}
- **Decided at:** {YYYY-MM-DD HH:MM TZ}
- **Merge commit:** {SHA, or "N/A — not merged"}
- **Merged into:** {branch name}
- **Merged at:** {YYYY-MM-DD HH:MM TZ}
- **Follow-ups created:** carries exactly one of the six canonical forms below, and every
  follow-up candidate raised at any gate -- including a deferred `adr-owed` item -- is accounted for
  exactly once under one of them. This field is
  **never left blank** and **never a bare** `None` / `none` / `n/a` / `(pending)` / un-substituted
  placeholder: an unpopulated field and a deliberately empty disposition must be mechanically distinguishable.
  `Filed`, `Duplicate`, `Folded`, `Declined`, and `Deferred` may be combined (each listed once per applicable
  candidate); `None owed` stands alone. Whenever one or more non-blocking findings have been logged
  (see `docs/policies/finding-classes.md`), every form also appends the per-class tally clause, omitting
  zero-count classes.
  - **Filed** -- one line per follow-up ticket, recording the allocated id, a one-line summary, the gate phase
    that filed it, the date, and its `specs/{ticket-id}/` path. Example:
    `ABC-42 -- backfill the dangling records; filed at maintainer, 2026-01-31, specs/ABC-42/`
  - **Duplicate of \<id>** -- a confirmed candidate already covered by an existing open ticket; no new id is
    allocated. Example:
    `Duplicate of BTG-900 -- jira-reserve.sh drops jira_url on reserve; confirmed at code review.`
  - **Folded into \<id>** -- a confirmed candidate appended into an open, fold-eligible ticket's
    `## Notes` section, recorded only after that edit lands; no new id is allocated. Example:
    `Folded into BTG-901 -- jira-reserve.sh hardening; confirmed at code review.`
  - **None owed** -- an explicit declaration that zero follow-up candidates were raised at any gate, plus the
    per-class non-blocking tally when findings were logged. Examples:
    `None owed -- no follow-up was named at code review, at the maintainer gate, or at archive.`
    `None owed -- 0 candidates; 23 non-blocking findings logged (nit 9, hygiene 11, observation 3).`
  - **Declined** -- an explicit declaration stating the candidate count, the gate phase, and the rejection rationale per
    candidate. Example: `Declined -- 1 candidate at the maintainer gate: cosmetic, no defect.`
  - **Deferred** -- an explicit declaration naming the blocking cause and confirming that the candidates and
    their exact filing commands are preserved in `## Discussion`. Example:
    `Deferred -- no channel was available to collect the confirmation; candidates and their exact
    filing commands are in ## Discussion.`
