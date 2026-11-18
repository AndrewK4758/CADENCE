---
name: cadence-propose
description: Mechanize Workflow Step 00 (Problem) -- validate intent fit against PROJECT_INTENT.md, scan for semantic duplicates/prior insights via local offload, draft a concise 4-part outcome proposal into specs/drafts/<slug>.md, and hand off cleanly to /cadence-triage.
argument-hint: "<short problem summary or slug>"
arguments: [summary]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Execute **Workflow Step 00 (Problem)** (`docs/guides/workflow/00-problem.md`): help a requester turn an idea, defect symptom, or operational gap into a concrete, charter-checked **4-part intent proposal** (`Problem`, `Proposed approach`, `Surfaces affected`, `Ask`) stored safely in `specs/drafts/<slug>.md`, then hand off cleanly to `/cadence-triage --file-only specs/drafts/<slug>.md` (or full `/cadence-triage` when ready to classify immediately).

This skill runs interactively (`Fast-mechanical` / primary turn) with mandatory `local_semantic_embed` (`:11434`) discovery, and **never mints ticket IDs or creates `specs/<id>/` folders itself** (allocation belongs exclusively to `/cadence-mint` and `/cadence-triage`).

## Prerequisites & Scope Checks

1. Verify `summary` is supplied (if blank, ask the requester for the observable symptom or desired outcome first).
2. Read `PROJECT_INTENT.md` (at repo root, or `docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md` notice if unadopted) checking **Mission**, **In Scope / Out of Scope**, **Adjacent Projects**, **Non-Goals**, and **Quality Stance**.
   - If the proposal falls clearly under a documented **Non-Goal** or belongs to an **Adjacent Project**, stop before drafting a ticket and present the constructive dispositions from `00-problem.md` (`Redirect` to owning repo, `Amend first` via `PROJECT_INTENT.md` §10, or `Decline`).
3. Consult both surface registries (`docs/policies/surface-registry.md` if present, and `docs/policies/cadence-surfaces.md`) so the proposal accurately identifies affected registered surfaces (or explicitly writes `"no public surfaces"`).

## Steps

### 1. Semantic duplicate & insight check (`local_semantic_embed` / `repo-scout`)

Before writing any draft file, invoke `local_semantic_embed` (`:11434`) and/or `repo-scout` over:
- active `specs/*/problem.md` and archived `archive/*/problem.md` (to detect duplicate or overlapping tickets),
- `docs/agentic-sdlc/production-insights.md` and `docs/agentic-sdlc/intent-insights.md` (to connect prior `PROD-*` / `II-*` lessons),
- candidate code modules relevant to the symptom.

Surface any near-duplicate open/archived tickets or `PROD-*` matches immediately to the requester before proceeding.

### 2. Draft the concise 4-part intent proposal (3–5 sentences total)

Help refine the proposal into outcome terms (`"actors can Y without encountering Z"` rather than pre-locking class names, schemas, or UI mockups — architectural options belong downstream in `/cadence-spec`):

- **Title (outcome-framed):** concise one-line summary (used for tracker/ticket title).
- **Problem (1–2 sentences):** observable symptom, metric, user friction, or failure mode.
- **Proposed approach (2–3 sentences):** directional sketch, not a full design or 6W×4L table.
- **Surfaces affected:** exact endpoints/events/configs/CLI commands from the surface registries, or `"no public surfaces"`.
- **Ask:** what maintainer ruling is needed (`Proceed`, architectural guidance, or scope confirmation).

Remind the requester when filing directly in an external tracker (Route A) that intent issues file as issue type **`Issue`** in the **backlog only** (never straight into an active sprint).

### 3. Write safely to `specs/drafts/<slug>.md` (File-First Discipline)

Because multi-word inline skill arguments can truncate across runtimes (BTG-281), persist the draft cleanly to disk:
1. Ensure `specs/drafts/` exists and contains `specs/drafts/.gitignore` (`*\n!.gitignore\n` if missing) so scratch drafts never pollute git history.
2. Derive a short kebab-case `<slug>` and confirm the draft text with the requester, writing `specs/drafts/<slug>.md` cleanly (never guessing or calling `mint-id.sh` here).

### 4. Choose intake next step

Offer three clean routes matching `CADENCE_ORG.md` §9/§10 and `00-problem.md`:
1. **File raw stub now (Recommended for backlog / multi-step intake):** invoke `/cadence-triage --file-only specs/drafts/<slug>.md` (passing `--prefix <PREFIX>` when `CADENCE_ORG.md` §9 has `>=2` prefix rows or running non-interactively).
2. **Triage & classify immediately (Route B):** invoke `/cadence-triage specs/drafts/<slug>.md` (or pass its content directly) to allocate + run `cadence-triage-agent` right away.
3. **Keep draft for tracker-first Route A / maintainer discussion:** leave `specs/drafts/<slug>.md` on disk and display its exact text ready to paste as tracker type `Issue` in the backlog.

## Constraints

- **No speculative design or spec artifacts.** Never generate `specs/<id>/`, `spec.md`, `test-plan.md`, CHORD tables, or `metadata.yaml` in `/cadence-propose`.
- **No manual ID guessing or `--reserve`.** Identifier allocation happens strictly in `/cadence-triage` or `/cadence-mint`.
- **Observed facts only.** Only cite file paths, surfaces, or `PROD-*` entries directly observed in repository files or search output.

## Examples

```text
/cadence-propose "Export audit fails silently when output directory is read-only"
```

## Local Model Offload Integration (:11434)
- Step 1 automatically calls `local_semantic_embed` (`:11434`) across `specs/`, `archive/`, `production-insights.md`, and `intent-insights.md` to catch duplicate proposals and prior incident context early.
