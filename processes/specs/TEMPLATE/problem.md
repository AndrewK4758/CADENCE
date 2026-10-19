# Problem Statement: {TICKET-ID} -- {Title}

## Status

Draft | In Review | Approved | Superseded

> **Document review status**, distinct from the ticket's overall lifecycle state. The `status:`
> field in `metadata.yaml` is the single source of truth for the ticket's workflow stage; this line
> records the review progression of *this document*. The two vocabularies are intentionally separate,
> and neither mirrors the other.

## Requestor

- **Name:** {PM or stakeholder name}
- **Role:** {Product Manager | Architect | Engineering Lead | Support}
- **Date Filed:** {YYYY-MM-DD}

## Business Context

{Why does this problem matter to the organization? What user friction, revenue exposure, compliance mandate, or operational bottleneck motivates this request? Be concrete -- "users find the screen confusing" is not actionable; "43% of Q1 support escalations stemmed from X" gives clear grounding.}

## Problem Description

> **Probe:** How would you know this shipped wrong? What is the observable failure mode — in logs, in user behaviour, in a dashboard, in a follow-up support ticket?
> _Answer:_ _(not yet answered)_

{What is occurring today that should not happen, or what capability is missing that must exist? Contrast the current behavior with the required state. Focus on observable symptoms rather than unverified root-cause assumptions.}

## Affected Users and Systems

- **End users:** {Who directly encounters the issue? External customers, internal operators, administrators, or API integrators?}
- **Systems:** {Which bounded contexts, services, or components are involved?}
- **Scale:** {How many users, records, or requests are impacted, and at what frequency?}

## Desired Outcome

> **Probe:** What assumptions does this make about adjacent systems, teams, or contexts? Anything you are quietly counting on being true?
> _Answer:_ _(not yet answered)_

{What does success look like from a domain and user perspective? Frame this as "actors can achieve Y without encountering Z" rather than "build component X." Describe the target outcome, not a pre-selected implementation.}

## Acceptance Criteria

> **Probe:** What non-functional needs (latency, durability, observability, audit, accessibility) does this implicitly assume? Name the ones you would notice if they were violated.
> _Answer:_ _(not yet answered)_

- [ ] {Observable, verifiable criterion -- e.g., "Given an account with an active subscription, when the user opens the billing dashboard, then only current-period charges are rendered"}
- [ ] {Each criterion must be independently testable and decomposed via CHORD in spec.md}
- [ ] {Include both functional behaviors and required non-functional guarantees}

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

- **Timeline:** {Hard delivery dates -- e.g., "must ship prior to Q3 release cut"}
- **Regulatory:** {Applicable compliance or legal mandates -- HIPAA, SOC 2, GDPR, PCI-DSS}
- **Dependencies:** {Upstream teams, external APIs, or architectural rulings that bound or block this work}
- **Budget:** {If applicable -- cloud spend ceilings, third-party licensing limits}

## Out of Scope

> **Probe:** What is deliberately out of scope today, and what would change your mind? Name the trigger that would move an item from 'no' to 'yes'.
> _Answer:_ _(not yet answered)_

{Explicitly enumerate adjacent work that this problem statement does NOT address. Clear non-goals prevent scope drift during `/cadence-spec`.}

- {Item 1}
- {Item 2}

## Supporting Evidence

- {Links to issue tracker tickets, telemetry dashboards, user research notes, or incident postmortems}
- {Screenshots, structured error logs, or query exports where applicable}

<!-- Imported tracker attachments (BTG-043): when problem.md is seeded from a tracker-first Import, each
     attachment on the source issue is recorded here as ONE bullet — a stored file is referenced by its
     local path `specs/{id}/attachments/{attachmentId}-{filename}`; an over-ceiling or failed-to-download
     file is referenced by its Jira `content` URL with a short note. Every bullet records provenance
     (source issue key, attachment id, filename, size, mimeType). Reference-by-path and reference-by-URL
     are both first-class here. -->
- {Imported attachment — e.g. `specs/ABC-123/attachments/501-screenshot.png` (from ABC-123, id 501, image/png, 40 KB)}

## Notes

{Any supplementary context that does not belong in the sections above.}

When a ticket is decomposed into a child track (via `/cadence-elicit`), record the parent/child lineage in `metadata.yaml`: each child ticket sets `decomposed_from:` and the parent ticket sets `decomposed_into:`. See `archive/PI-008-FB/` for the canonical example.
