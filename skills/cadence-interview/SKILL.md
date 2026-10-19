---
name: cadence-interview
description: Guide an adopter interactively through populating <placeholder> cells in CADENCE_ORG.md's Contextual Grounding Matrix (6W×4L) Where/Who/Why tables -- offering 3 repository-evidenced candidates plus N/A and free-text entry per row, with --re-interview to re-open all rows.
argument-hint: "[--re-interview]"
arguments: [mode_flag]
allowed-tools: Read Edit Bash
---

## Task

Walk the adopter interactively through populating `<placeholder>` value cells in their live `docs/agentic-sdlc/CADENCE_ORG.md` **Contextual Grounding Matrix (6W×4L) Where/Who/Why tables**, presenting 3 evidence-backed candidate values alongside `N/A` and a custom free-text option for each row, and applying all selected values in a single atomic edit. Supplying `--re-interview` re-opens **every** row in those three tables rather than only unfilled placeholders.

This skill conducts the interactive session directly within the invoking turn without subagent delegation for the conversation itself, completing in a single turn (matching `/cadence-elicit`). Its write scope is strictly restricted to the Where/Who/Why value cells; it never modifies the operational binding sections (§7–§15) and never touches `CADENCE_ORG_TEMPLATE.md` (which remains an upstream-owned reference template).

## Prerequisites

Before presenting any prompts, verify:

1. `docs/agentic-sdlc/CADENCE_ORG.md` **exists on disk**. If the live file is **missing**, **halt immediately** with a clear message naming `docs/agentic-sdlc/CADENCE_ORG.md` and directing the adopter to run adoption first — **never synthesize or fabricate the file** (creating the live org document is the adopter's responsibility, matching org-fold DEC-010).
2. The live file contains a `## ...Pre-Filled Contextual Grounding Constants` H2 heading with H3 tables titled **Where**, **Who**, and **Why**. If that section is absent, halt and report that there are no Contextual Grounding tables in scope to populate.

## Steps

### 1. Resolve the mode from the argument

- No argument supplied → **default mode** (inspect and prompt only for rows whose value cell is a `<placeholder>`).
- `--re-interview` → **re-interview mode** (re-open every data row across Where/Who/Why; see Step 5).
- **Any other argument token** (such as a misspelled flag like `--reinterview`) → **halt immediately** with an **unrecognized-argument** error naming the invalid token. **Never** fall back silently to default mode and **never** perform any file writes (Fail Loud / no silent fallback).

### 2. Scan the Where/Who/Why tables

Read `docs/agentic-sdlc/CADENCE_ORG.md`. Locate the single `## ...Pre-Filled Contextual Grounding Constants` H2 section and, beneath it, the three H3 tables whose headings start with **Where**, **Who**, and **Why**. Those three tables constitute the **entire** target scope. Any `<...>` angle-bracket token appearing **anywhere else** in the document — whether inside a binding section (§7–§15) or another table — is **never prompted and never modified**; all other sections remain byte-identical.

Within each data row, the **key** is the first table column (whitespace-trimmed, case-sensitive) and the **value** is the second table column; the Where table's third **Notes** column is preserved intact. A **placeholder** is defined as a value cell whose trimmed content matches an `<...>` angle-bracket token (following the `CADENCE_ORG_TEMPLATE.md` convention shared with the BTG-048 org-fold normalizer).

In **default mode**, select only rows whose value cell currently holds a placeholder. When **zero** rows contain a placeholder, default mode acts as an **idempotent no-op**: display no interactive prompts, perform no writes, and output **"nothing to fill"** (re-running after all placeholders are populated cleanly exits without prompting, mirroring `/cadence-elicit` when all probes are resolved).

### 3. Gather repository evidence via local offload and offer candidates per selected row

Before formulating candidates for the selected rows, **automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) / `local-moe-hybrid` (`:9380`)** to gather concrete repository evidence (scanning CI/CD workflows, deployment manifests, VCS/remote configuration, authentication/IdP references, branch protection rules, and already-populated cells in `CADENCE_ORG.md` and `PROJECT_INTENT.md`).

Using that gathered evidence, derive **3** candidate answers per selected row, explicitly tagging each candidate as **Observed**, **Inferred**, or **Unknown** (following the architect evidence discipline — never invent false-confident citations). Present the following options for each selected row:

- the **3** repository-evidenced candidates (tagged Observed / Inferred / Unknown),
- **`N/A`**,
- **`Type my own`** (custom free text) — whatever string the operator enters is written into the value cell **verbatim** (with zero paraphrasing or normalization).

Capture the operator's exact selection for each row. Preserve the row's first-column **key** and any trailing **Notes** column byte-for-byte; only the second-column **value cell** is updated.

If a **malformed row** is encountered (a table line lacking a second data column, leaving no targetable value cell), **skip and report** that row in the final summary — leaving its bytes **completely untouched** rather than risking column corruption on a non-standard row shape.

### 4. N/A is non-destructive (both modes)

`N/A` is a **first-class, non-destructive** selection. Choosing `N/A` — in **either default or `--re-interview` mode** — writes the **literal string `N/A`** into the value cell while **retaining the row** (never deleting or stripping the table row) and preserving the first-column key and any Notes column intact. This enforces the strict row-count invariant: none of the Where/Who/Why tables ever gains or loses rows during an interview run, even when `N/A` is chosen. When a row previously set to `N/A` is re-opened under `--re-interview`, `N/A` appears as its current value alongside the standard options, and re-selecting `N/A` results in a clean no-op for that cell.

### 5. Re-interview mode (`--re-interview`)

When invoked with `--re-interview`, the table scan in Step 2 selects **every data row** across the Where, Who, and Why tables — regardless of whether a row currently holds a concrete value or a placeholder — and prompts the operator for each one. For each row in re-interview mode, present:

- the **current value** as an explicit option — included **only** when the current value is **not a `<placeholder>`**;
- **2** repository-evidenced candidates (via `local_semantic_embed` / `local-moe-hybrid`) when the current value is offered, or **3** repository-evidenced candidates when the current value **is a placeholder** (and therefore omitted as a keep option) — keeping the total choices per row consistent at ~5;
- **`N/A`**;
- **`Type my own`**.

Table scope, key and Notes column preservation, and value-cell-only editing work identically to default mode. Although `--re-interview` is intentionally non-idempotent with respect to prompting (since its purpose is to re-review all rows), every mutation remains gated on explicit human selection: if the operator **retains the existing value for every single row**, no file write occurs and the summary reports **0 rows changed**.

### 6. Compose and write

Accumulate all operator selections in memory across the interview, then apply **one atomic edit** at the conclusion of the turn, updating only the targeted **value cells** in place. Output a concise **summary** stating: rows populated, rows left as placeholder, and total `N/A` selections. If zero rows were selected or modified, perform no file write. An **empty response** on a row leaves its existing placeholder untouched and notes it in the summary; **aborting** the session prior to Step 6 leaves `docs/agentic-sdlc/CADENCE_ORG.md` byte-identical.

### 7. Post-write self-check (AC-7)

Immediately after applying the atomic edit, **re-read `docs/agentic-sdlc/CADENCE_ORG.md` directly from disk** to perform an independent verification (never relying on in-memory state). Verify three strict invariants and print the self-check verification report:

- **Residual-placeholder invariant** — every value cell that the operator **chose to populate** contains **zero** `<...>` angle-bracket markers (residual placeholder count = 0 across filled cells). Any cell the operator **intentionally skipped** (leaving it as a placeholder) is **explicitly listed by name** as left-as-placeholder — treated as an intentional skip rather than structural corruption.
- **Row-count invariant** — the total row count of each of the Where, Who, and Why tables is **identical before and after the edit**.
- **Scope-containment invariant** — only second-column value cells in Where/Who/Why changed; every single byte of the operational binding sections (§7–§15) remains **completely unchanged**.

When all three invariants hold, print the completion summary: rows filled, rows intentionally left as placeholder (named), `N/A` count, and explicit confirmation that "row counts preserved" and "binding sections unchanged".

If **structural damage** is detected — such as a table row **added or removed**, a value written into the **wrong column**, or **any** byte modification inside §7–§15 — **halt loud** (`UNSOUND_CONDITION`): report the exact invariant violated and the affected table/row, and instruct the operator to run `git checkout -- docs/agentic-sdlc/CADENCE_ORG.md` to restore the tracked file from git. Never report success when the post-write self-check fails.
