# Problem Statement: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Superseded

> **The review state of this document**, not the ticket's lifecycle state. `metadata.yaml`'s
> `status:` field is authoritative for the ticket; this line tracks how far *this document* has got.
> They are different vocabularies by design, and neither is a copy of the other.

## Requestor

- **Name:** {PM or stakeholder name}
- **Role:** {Product Manager | Architect | Engineering Lead | Support}
- **Date Filed:** {YYYY-MM-DD}

## Business Context

{Why does this problem matter to the business? What user pain, revenue impact, compliance requirement, or operational inefficiency drives this request? Be specific -- "users are confused" is insufficient; "43% of support tickets in Q1 were about X" is actionable.}

## Problem Description

> **Probe:** How would you know this shipped wrong? What is the observable failure mode — in logs, in user behaviour, in a dashboard, in a follow-up support ticket?
> _Answer:_ _(not yet answered)_

{What is happening today that should not be, or what is not happening today that should be? Describe the current state and the gap. Include observable symptoms, not assumed root causes.}

## Affected Users and Systems

- **End users:** {Who experiences the problem? Customers, internal staff, administrators, API consumers?}
- **Systems:** {Which systems or services are involved?}
- **Scale:** {How many users/records/transactions are affected? How often does it occur?}

## Desired Outcome

> **Probe:** What assumptions does this make about adjacent systems, teams, or contexts? Anything you are quietly counting on being true?
> _Answer:_ _(not yet answered)_

{What does success look like from the business perspective? Not "build feature X" but "users can Y without Z." Focus on the outcome, not the solution.}

## Acceptance Criteria

> **Probe:** What non-functional needs (latency, durability, observability, audit, accessibility) does this implicitly assume? Name the ones you would notice if they were violated.
> _Answer:_ _(not yet answered)_

- [ ] {Observable, testable criterion -- e.g., "Given a user with an active subscription, when they view their dashboard, then only current-period data is displayed"}
- [ ] {Each criterion should be independently verifiable}
- [ ] {Include both functional and non-functional requirements}

## Functional Validation

<!-- QA hand-off. List only END-USER-OBSERVABLE behaviour changes: what a QA engineer does at the
     UI/API boundary, and what they should then see. Source-level criteria stay in Acceptance
     Criteria above. This section's CONTENT evolves as the ticket moves through the workflow; its
     structure does not. Use EXACTLY ONE of two forms:
       (a) one or more `- [ ]` items, each independently checkable by hand; or
       (b) the single line: No behavioral changes expected -- regression testing only.
     Leaving this section unfilled is NOT form (b). It projects to the tracker as
     "NOT SPECIFIED", which is a visible gap, not an assurance. -->

- [ ] {Observable change -- what the QA engineer does, and what they should then see}

## Constraints

> **Probe:** What edge cases have you already considered and rejected, and why? Capture the rejections so the spec author does not re-litigate them.
> _Answer:_ _(not yet answered)_

- **Timeline:** {Hard deadlines -- e.g., "must ship before Q3 release cut"}
- **Regulatory:** {Any compliance or legal requirements -- HIPAA, SOC 2, GDPR, PCI-DSS}
- **Dependencies:** {External teams, services, or decisions that block or constrain this work}
- **Budget:** {If applicable -- infrastructure cost limits, licensing constraints}

## Out of Scope

> **Probe:** What is deliberately out of scope today, and what would change your mind? Name the trigger that would move an item from 'no' to 'yes'.
> _Answer:_ _(not yet answered)_

{Explicitly list what this problem statement does NOT cover. Prevents scope creep during spec authoring.}

- {Item 1}
- {Item 2}

## Supporting Evidence

- {Link to support tickets, dashboards, user research, or prior incidents}
- {Screenshots, error logs, or data exports if applicable}

<!-- Imported tracker attachments (BTG-043): when problem.md is seeded from a tracker-first Import, each
     attachment on the source issue is recorded here as ONE bullet — a stored file is referenced by its
     local path `specs/{id}/attachments/{attachmentId}-{filename}`; an over-ceiling or failed-to-download
     file is referenced by its Jira `content` URL with a short note. Every bullet records provenance
     (source issue key, attachment id, filename, size, mimeType). Reference-by-path and reference-by-URL
     are both first-class here. -->
- {Imported attachment — e.g. `specs/ABC-123/attachments/501-screenshot.png` (from ABC-123, id 501, image/png, 40 KB)}

## Notes

{Any additional context that does not fit the sections above.}

When a ticket is decomposed (via `/claire-elicit`), record lineage in `metadata.yaml`: each child gets `decomposed_from:` and the parent gets `decomposed_into:`. See `archive/PI-008-FB/` for the canonical example.
