# Jira Server/DC Ticket Description Template

This document specifies the **canonical layout of the Jira issue description** rendered by the `cadence-sync-jira` skill. Rather than uploading `problem.md` raw, the orchestrator populates the template below from repository specification artifacts and projects the rendered result as the Jira issue's `description`.

> **Format:** Jira **Server/DC wiki markup** (Jira REST API v2 renders descriptions directly from wiki markup rather than ADF JSON). The template body below is authored in Jira wiki markup; rendering substitutes the `{{token}}` placeholders after converting extracted Markdown fragments via `jira-md2wiki.sh`. Do **not** wrap the rendered body in outer code fences when sending it to Jira.

## Token sources

Every `{{token}}` placeholder is populated from an authoritative repository artifact (`repo -> Jira` one-way projection). Whenever an optional source section is absent — or fails to meet the stated content rule for that token — apply the corresponding **If missing** disposition.

| Token | Source | If missing |
|---|---|---|
| `{{id}}` | `metadata.yaml` `id` | required — abort rendering if absent |
| `{{title}}` | `metadata.yaml` `title` | required — abort rendering if absent |
| `{{type}}` | `metadata.yaml` `type` | omit the bullet line |
| `{{priority}}` | `metadata.yaml` `priority` | omit the bullet line |
| `{{tier}}` | `metadata.yaml` `tier` | omit the bullet line |
| `{{status}}` | `metadata.yaml` `status` | omit the bullet line |
| `{{business_context}}` | `problem.md` → *Business Context* (prose only) | render `_Not yet documented._` |
| `{{problem_description}}` | `problem.md` → *Problem Description* (prose only) | render `_Not yet documented._` |
| `{{desired_outcome}}` | `problem.md` → *Desired Outcome* (prose only) | render `_Not yet documented._` |
| `{{acceptance_criteria}}` | `problem.md` → *Acceptance Criteria* checklist items | drop the entire `h2.` section |
| `{{functional_validation}}` | `problem.md` → *Functional Validation* (checklist items, or the explicit no-change declaration) | render the NOT SPECIFIED notice: _Functional validation NOT SPECIFIED -- this ticket has not stated whether it changes end-user-observable behaviour; do not read this as "no change"._ Never omit the section and never substitute the no-change declaration. Apply this exact same rule when the section heading exists in `problem.md` but, after stripping HTML comments, contains neither a non-placeholder checklist item nor the canonical no-change line -- an unfilled template section is never treated as "no change". |
| `{{out_of_scope}}` | `problem.md` → *Out of Scope* bullets | drop the entire `h2.` section |
| `{{spec_link}}` | repository path `specs/{{id}}/spec.md` (or `archive/{{id}}/spec.md`) | omit the table row |
| `{{merge_request_link}}` | `metadata.yaml` `merge_request` | omit the table row |
| `{{spec_mr_link}}` | `metadata.yaml` `spec_mr` | omit the table row |
| `{{tags}}` | `metadata.yaml` `tags` (comma-joined) | omit the footer line |
| `{{elicited_intent}}` | `problem.md` → *Elicited Intent* (the section appended by `/cadence-elicit`: a provenance blockquote followed by one `### <section name>` sub-heading per probed section, each containing `**Source:**`/`**Probe:**`/`**Answer:**` blocks) | drop the entire `h2.` section |

## Rendering rules

- **Always use the shipped deterministic converter rather than hand-converting markup.** The mechanical Markdown-to-wiki conversion of every rule below is implemented by `jira-md2wiki.sh`, a pure deterministic filter co-located in `.agents/skills/cadence-sync-jira/` (contracted in `jira-server-scripts-render.md`). Pipe every extracted Markdown section fragment through `jira-md2wiki.sh` rather than translating syntax manually: manual conversion caused the seven recurring markup defects resolved by BTG-205. The rules below document what the filter performs and remain authoritative for extracting the right source sections (BTG-205 DEC-001, superseding BTG-150 on markup conversion).
- **Prose extraction:** strip all `> **Probe:** …` blockquotes and their paired `_Answer:_` placeholder lines from `problem.md` sections — those belong to elicitation scaffolding rather than projected ticket content.
- **Markdown → Jira wiki markup:** `**bold**` → `*bold*`, `` `code` `` → `{{…}}` (monospace), `- item` → `* item`, fenced code blocks → `{code}…{code}`, `#`/`##` → `h1.`/`h2.`.
- **Checklist items:** render `- [ ]` and `- [x]` checklist lines from *Acceptance Criteria* and *Functional Validation* as standard `* ` wiki bullets (Jira wiki markup has no interactive checkbox syntax in descriptions).
- **HTML comments:** strip all `<!-- ... -->` comment blocks from `problem.md` sections — template authoring comments are scaffolding and must not appear in projected descriptions (such as the inline guidance comment inside *Functional Validation*).
- **Spacing and escaping:** Jira wiki markup is sensitive to line breaks around headings and lists — maintain a blank line between each heading and its following paragraph or list.
- **Elicited Intent sub-structure:** convert each `### <section name>` sub-heading to `h3. <section name>`; convert `**Source:**`/`**Probe:**`/`**Answer:**` labels under the standard bold rule; wrap the section's leading provenance blockquote in `{quote}…{quote}`. Answer content is **strictly content-preserving** — never paraphrased, condensed, truncated, or re-ordered — while its Markdown formatting is converted to wiki markup via `jira-md2wiki.sh` with internal blank lines preserved. Note that the *Prose extraction* strip rule (`_Answer:_` italic placeholders) does **not** strip the bold `**Answer:**` bundles inside *Elicited Intent*.

## Template body (wiki markup)

```
{panel:title=Repo-managed — do not edit in Jira|borderStyle=solid|titleBGColor=#f4f5f7|bgColor=#fafbfc}
This description is generated from the repository spec artifacts and overwritten on each sync.
The repository is the source of truth ({{id}}). Edits made in Jira will be lost.
{panel}

h2. Summary

*{{id}}* — {{title}}
* Type: {{type}}
* Priority: {{priority}}
* Tier: {{tier}}
* Repo status: {{status}}

h2. Business Context

{{business_context}}

h2. Problem

{{problem_description}}

h2. Desired Outcome

{{desired_outcome}}

h2. Acceptance Criteria

{{acceptance_criteria}}

h2. Functional Validation

{{functional_validation}}

h2. Out of Scope

{{out_of_scope}}

h2. Elicited Intent

{{elicited_intent}}

h2. Traceability

|| Artifact || Reference ||
| Spec | {{spec_link}} |
| Spec MR | {{spec_mr_link}} |
| Implementation MR | {{merge_request_link}} |

----
Labels: {{tags}}
```
