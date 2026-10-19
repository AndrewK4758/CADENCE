---
name: claire-interview
description: Walk an adopter through filling <placeholder> cells in CLAIRE_ORG.md's Zachman Where/Who/Why tables -- 3 evidence-based candidates plus N/A and type-my-own per row; a --re-interview flag re-opens every row.
argument-hint: "[--re-interview]"
arguments: [mode_flag]
allowed-tools: Read Edit Bash
---

## Task

Walk the adopter interactively through the `<placeholder>` value cells in their live
`docs/agentic-sdlc/CLAIRE_ORG.md` **Zachman Where/Who/Why tables**, offering evidence-based candidate
answers plus `N/A` and a free-text escape hatch per row, and write each chosen value into that row's value
cell via one atomic edit. A `--re-interview` flag re-opens **every** row, not only the placeholders.

This skill runs the conversation directly in the invoking turn — there is no delegation. The conversation
completes in one turn, mirroring `/claire-elicit`. It touches **only** the Where/Who/Why value cells; it never
edits the binding sections (§7–§15) and never edits `CLAIRE_ORG_TEMPLATE.md` (framework-owned reference).

## Prerequisites

Before prompting, verify:

1. `docs/agentic-sdlc/CLAIRE_ORG.md` **exists**. If the live file is **absent**, **stop** with an
   actionable message naming the missing file (`docs/agentic-sdlc/CLAIRE_ORG.md`) and pointing the adopter
   at adoption — **never fabricate the file** (the adopter owns its creation; mirrors org-fold DEC-010). Do
   not create it.
2. The live file contains a `## ...Pre-Filled Zachman Constants` H2 with H3 tables headed Where/Who/Why.
   If that section is missing, stop and say so — there is nothing in scope to fill.

## Steps

### 1. Resolve the mode from the argument

- No argument → **default mode** (fill placeholder rows only).
- `--re-interview` → **re-interview mode** (re-open every row; step 5).
- **Any other token** (e.g. a typo like `--reinterview`) → **stop** with an **unrecognized-argument**
  message naming the token. **Never** silently fall back to default mode and **never** write (Behavior 5:
  no silent fallback).

### 2. Scan the Where/Who/Why tables

Read `docs/agentic-sdlc/CLAIRE_ORG.md`. Locate the single `## ...Pre-Filled Zachman Constants` H2 and,
under it, the three H3 tables whose headings begin **Where**, **Who**, and **Why**. This H2's three tables
are the **entire** scope. An `<...>` marker anywhere **else** in the file — in a binding section (§7–§15)
or any other table — is **never offered and never written**; those sections stay byte-unchanged.

For each data row, the **key** is the first data column (trimmed, case-sensitive) and the **value** is the
second data column; the Where table's trailing **Notes** column is preserved. A **placeholder** is a value
cell whose trimmed text matches an `<...>` angle-bracket marker (the `CLAIRE_ORG_TEMPLATE.md` convention,
reused from the BTG-048 org-fold row normalization — do not reinvent it).

**Default mode** selects only the rows whose value cell is a placeholder. If **no** value cell is a
placeholder, default mode is an **idempotent no-op**: show no prompt, write nothing, and report
**"nothing to fill"** (a re-run after every placeholder is filled offers nothing — mirrors `/claire-elicit`
no-op'ing when all probes are answered).

### 3. Offer candidates per selected row

For each selected row, derive **3** candidate answers grounded in evidence discovered in the repo
(VCS/CI config, IdP references, branch config, the shape of already-filled cells), labelled
Observed / Inferred / Unknown (the architect precedent — never fabricate false-confident evidence). Present,
per row:

- the **3** evidence-based candidates,
- **`N/A`**,
- **`Type my own`** (free text) — the entered text is written into the value cell **verbatim** (no
  paraphrase, no normalization).

Record the operator's verbatim choice for that row. The row's first-column **key** and any **Notes** column
are preserved byte-for-byte; only the **value cell** is rewritten.

A **malformed row** (a table line with **no second data column**, so there is no value cell to target) is
**skipped and reported** in the summary — it is left **byte-unchanged** and **never mangled** (positional
value-cell targeting can misfire on a reshaped table, so a row that does not fit the shape is skipped, not
guessed at).

### 4. N/A is non-destructive (both modes)

`N/A` is a **first-class, non-destructive** answer. Selecting it — in **either mode** — sets the value cell
to the **literal text `N/A`**; the **row is retained** and is **never deleted or removed**, and the
first-column key (and any Notes column) is preserved. This holds the row-count invariant: a Where/Who/Why
table never gains or loses a row across a run, including an `N/A` selection. A row already set to `N/A`,
re-opened under `--re-interview`, shows `N/A` as its current value and is offered again — re-selecting it is
a no-op write.

### 5. Re-interview mode (`--re-interview`)

In re-interview mode the scan (step 2) selects **every row** in the Where/Who/Why tables — not only
placeholders — and re-opens each one. Per row, the choices are:

- the **current value** as a choice — offered **only** when it is **not itself a placeholder**;
- **2** evidence-based candidates when the current value was offered, or **3** candidates when the current
  value **is a placeholder** (and thus not offered) — so the option count stays stable at ~5;
- **`N/A`**;
- **`Type my own`**.

Scope, key/Notes preservation, and the value-cell-only rewrite are identical to default mode. Re-interview
is intentionally non-idempotent (re-opening every row is its purpose), but every write is still a per-row
human choice: if the operator **keeps the current value for every row**, the file is **not written** and the
summary reports **0 rows changed**.

### 6. Compose and write

Compose every chosen value in memory, then apply **one atomic edit** at the end of the turn, rewriting each
selected row's **value cell** in place. Print a **summary** reporting rows filled / rows left as placeholder
/ `N/A` count. If a run selects no rows, write nothing. An **empty answer** leaves that row as-is (still a
placeholder), reported in the summary; an **abort** before the write leaves the file byte-unchanged.

### 7. Post-write self-check (AC-7)

After the atomic edit, **re-read `docs/agentic-sdlc/CLAIRE_ORG.md` from disk** — independent verification;
never trust the in-memory model of what was written. Assert three invariants and print a self-check report:

- **Residual-placeholder** — every offered value cell the operator **filled** contains **no** `<...>` marker
  (residual count 0 for filled cells). A cell the operator **deliberately left as a placeholder** (an empty
  answer) is **named explicitly** as left-as-placeholder — it is a clean skip, **not** damage.
- **Row-count** — each Where/Who/Why table's **row count is unchanged** (before == after).
- **Scope-containment** — only value cells changed; every byte of the binding sections (§7–§15) is
  **unchanged**.

On a clean result, report success: rows filled / rows left-as-placeholder (named) / `N/A` count, plus
"row counts preserved" and "binding sections unchanged".

On **structural damage** — a row **added or deleted**, a value written to the **wrong column**, or **any**
byte change in §7–§15 — **halt loud**: name exactly what was found (which invariant, which table/row), and
point the operator at `git checkout -- docs/agentic-sdlc/CLAIRE_ORG.md` to restore the git-tracked file.
It does not report success over a corrupted file. Structural damage is an impossible state for a correct run; the self-check
catches a latent bug rather than shipping a silently-corrupted file (Behaviors 4 and 5).
