# YouTrack Issue Description Template

This document specifies the **canonical layout of the YouTrack issue description** rendered by the `cadence-sync-youtrack` skill. Rather than uploading `problem.md` raw, the orchestrator populates the template below from repository specification artifacts and projects the rendered Markdown as the YouTrack issue's `description`.

> **Format:** Native YouTrack **Markdown** (self-hosted YouTrack Server renders issue descriptions and comments directly as Markdown).
> Whereas `/cadence-sync-jira` converts descriptions into Jira **wiki** markup for Jira REST v2, nothing in the YouTrack pipeline converts markup in either direction — applying wiki markup conversion here would corrupt every projected YouTrack description (AC-6 divergence 3).
> The template body below is authored directly in Markdown; rendering simply substitutes the `{{token}}` placeholders.

> **Acceptance Criteria are projected inside the description body (AC-4b, CONFIRMED).** Because `cadence-sync-youtrack` never writes to a dedicated Acceptance-Criteria custom field, the `## Acceptance Criteria` section in this template is the **sole** surface where acceptance criteria appear in YouTrack. Since no separate custom-field write branch exists, no audit condition is emitted for projecting ACs into the description (an audit event that fires unconditionally on every single run carries zero diagnostic signal). See `youtrack-scripts.md` §8 (AC-6 divergence 2).

## Token sources

Every `{{token}}` placeholder is populated from an authoritative repository artifact (`repo -> YouTrack` one-way projection). Whenever an optional source section is absent — or fails to meet the stated content rule for that token — apply the corresponding **If missing** disposition.

| Token | Source | If missing |
|---|---|---|
| `{{id}}` | `metadata.yaml` `id` | required -- abort rendering if absent |
| `{{title}}` | `metadata.yaml` `title` | required -- abort rendering if absent |
| `{{type}}` | `metadata.yaml` `type` | omit the bullet line |
| `{{priority}}` | `metadata.yaml` `priority` | omit the bullet line |
| `{{tier}}` | `metadata.yaml` `tier` | omit the bullet line |
| `{{status}}` | `metadata.yaml` `status` | omit the bullet line |
| `{{business_context}}` | `problem.md` -> *Business Context* (prose only) | render `_Not yet documented._` |
| `{{problem_description}}` | `problem.md` -> *Problem Description* (prose only) | render `_Not yet documented._` |
| `{{desired_outcome}}` | `problem.md` -> *Desired Outcome* (prose only) | render `_Not yet documented._` |
| `{{acceptance_criteria}}` | `problem.md` -> *Acceptance Criteria* checklist items | drop the entire section |
| `{{functional_validation}}` | `problem.md` -> *Functional Validation* (checklist items, or the explicit no-change declaration) | render the NOT SPECIFIED notice: _Functional validation NOT SPECIFIED -- this ticket has not stated whether it changes end-user-observable behaviour; do not read this as "no change"._ Never omit the section and never substitute the no-change declaration. Apply this exact same rule when the section heading exists in `problem.md` but, after stripping HTML comments, contains neither a non-placeholder checklist item nor the canonical no-change line -- an unfilled template section is never treated as "no change". |
| `{{out_of_scope}}` | `problem.md` -> *Out of Scope* bullets | drop the entire section |
| `{{spec_link}}` | repository path `specs/{{id}}/spec.md` (or `archive/{{id}}/spec.md`) | omit the table row |
| `{{merge_request_link}}` | `metadata.yaml` `merge_request` | omit the table row |
| `{{spec_mr_link}}` | `metadata.yaml` `spec_mr` | omit the table row |
| `{{tags}}` | `metadata.yaml` `tags` (comma-joined) | omit the footer line |
| `{{elicited_intent}}` | `problem.md` -> *Elicited Intent* (provenance blockquote + one `### <section name>` sub-heading per probed section, each containing `**Source:**`/`**Probe:**`/`**Answer:**` blocks) | drop the entire section |

## Rendering rules

- **Prose extraction:** strip all `> **Probe:** ...` blockquotes and their paired `_Answer:_` lines from `problem.md` sections -- those belong to elicitation scaffolding rather than projected issue prose.
- **Checklist items:** format `- [ ]` and `- [x]` checklist lines from *Acceptance Criteria* and *Functional Validation* as standard Markdown bullet items (`- ...`).
- **HTML comments:** strip all `<!-- ... -->` comment blocks from `problem.md` sections -- template authoring comments are scaffolding and must not appear in projected descriptions (such as the inline guidance comment inside *Functional Validation*).
- Maintain a blank line between each section heading and its following paragraph or list.

## Template body (Markdown)

```
> Repo-managed -- do not edit in YouTrack. This description is generated from the repository spec artifacts
> and overwritten on each sync. The repository is the source of truth ({{id}}). Edits made in YouTrack will be lost.

## Summary

**{{id}}** -- {{title}}
- Type: {{type}}
- Priority: {{priority}}
- Tier: {{tier}}
- Repo status: {{status}}

## Business Context

{{business_context}}

## Problem

{{problem_description}}

## Desired Outcome

{{desired_outcome}}

## Acceptance Criteria

{{acceptance_criteria}}

## Functional Validation

{{functional_validation}}

## Out of Scope

{{out_of_scope}}

## Elicited Intent

{{elicited_intent}}

## Traceability

| Artifact | Reference |
|---|---|
| Spec | {{spec_link}} |
| Spec MR | {{spec_mr_link}} |
| Implementation MR | {{merge_request_link}} |

---
Tags: {{tags}}
```
