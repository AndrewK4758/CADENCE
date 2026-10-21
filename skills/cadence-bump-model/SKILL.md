---
name: cadence-bump-model
description: Update the concrete model identifier for a capability tier across adapter scripts and CADENCE_ORG.md, then recompile agent frontmatter after operator confirmation of the diff.
argument-hint: "<from-model> <to-model>"
arguments: [from_model, to_model]
allowed-tools: Read Edit Glob Grep Bash
---

## Task

Update a single capability tier's concrete model identifier from `$from_model` to `$to_model` across every authoritative source representation atomically in one run. Concrete model identifiers are **authored** in exactly two places — the tier-resolution `case` arm inside the runtime adapter scripts under `ci-templates/scripts/adapters/*.sh`, and the concrete-model cell of the corresponding tier row in `docs/agentic-sdlc/CADENCE_ORG.md#model-tier-mapping` — and are **propagated** into the compiled agent frontmatter (`.agents/agents/*/AGENT.md` `model:` lines, as well as `.gemini/` or any projected CLI runtime directories per `docs/policies/cli-runtime-adoption-policy.md`) by running `cadence-compile.sh`. The adapter script serves as the machine source of truth; the compiled agent tree is a generated build artifact updated exclusively via `cadence-compile.sh` and never edited by hand (manual edits to compiled agent files are overwritten on the next compile pass).

CADENCE defines two primary capability tiers (`Deep-reasoning` and `Fast-mechanical`) in `CADENCE_ORG.md#model-tier-mapping`, alongside read-only local hardware coprocessor tiers (`local-fast-cpu`, `local-embed-cpu`, `local-12b-gpu`, `local-moe-hybrid`). Each capability tier maps to a single concrete model identifier for the active runtime. This skill updates the concrete model identifier for **one tier per invocation** — requiring explicit `from` and `to` model arguments so tier boundaries stay explicit and accidental cross-tier reassignments are prevented.

## Prerequisites

- Both `$from_model` and `$to_model` must be supplied. If either argument is missing, halt and display the required syntax: `/cadence-bump-model <from-model> <to-model>`.
- Both model strings must conform to the naming pattern documented in `CADENCE_ORG.md#model-tier-mapping` for the repository's bound runtime. If either string deviates from the expected naming pattern in the mapping table, warn the operator — model naming conventions occasionally change across vendor generations, but an unexpected format is usually a typo. Continue only after explicit operator confirmation.
- The `#model-tier-mapping` section must be present in `docs/agentic-sdlc/CADENCE_ORG.md`. If the section is missing (for instance, in an older adopter repository), halt and warn the operator without modifying any files.

## Steps

### 1. Validate arguments

Verify that both `$from_model` and `$to_model` are non-empty and match the model naming convention in `CADENCE_ORG.md#model-tier-mapping`.

If `$from_model` and `$to_model` belong to **different capability tiers** in the mapping table, **halt and refuse**. Reassigning a tier to a different model family/tier is an architectural change affecting reasoning depth, latency, and cost rather than a version bump — it requires an intent ticket and specification rather than `/cadence-bump-model`. Inform the operator clearly that this skill only updates the concrete model version within a single capability tier.

When `$to_model` does not yet appear anywhere in the mapping table (the standard case when adopting a newly released model version), resolve `$from_model`'s tier from the table and treat the operation as an in-tier upgrade for that tier. Refuse only when `$to_model` is already assigned to a *different* tier's row, or when the runtime's model-family naming convention makes a cross-tier mismatch unmistakable (see Worked Example below).

### 2. Find all authored references

Locate both **authored** representations before presenting a diff. Because compiled agent definitions (`.agents/agents/*/AGENT.md` `model:` fields and projected runtime copies) are **derived** build outputs, do NOT search or hand-edit them in this step — Step 5 regenerates them via `cadence-compile.sh`.

**Adapter tier-resolution case arm(s):** search `ci-templates/scripts/adapters/*.sh` for the tier-resolution `case` arm whose concrete model literal matches `$from_model`. Account for an optional `<provider>/` namespace prefix (used by runtimes that prefix vendor names onto model IDs) so that `$from_model` matches both bare and `<provider>/`-prefixed literals:

```bash
grep -rn "$from_model" ci-templates/scripts/adapters/
```

**Org mapping table row:** locate the row inside the `### Tier → Concrete Model` table under `docs/agentic-sdlc/CADENCE_ORG.md#model-tier-mapping` whose concrete-model column currently contains `$from_model`.

If neither authored target matches `$from_model`, halt and report that no adapter `case` arm or `CADENCE_ORG.md` mapping row references `$from_model` (indicating a typo, an already-completed bump, or a model never configured in this repository).

If only one of the two authored targets matches (for example, the `CADENCE_ORG.md` row matches while no adapter script does, or vice versa), surface the discrepancy and ask the operator whether to proceed with the single matched target. Modify files only if the operator explicitly confirms the partial update.

### 3. Show the user a diff (both authored targets)

For every matching adapter `case` arm, display:

```
<adapter file> (tier-resolution case arm, tier <tier-name>):
  - <from_model>
  + <to_model>
```

For the matching `CADENCE_ORG.md` row, display:

```
docs/agentic-sdlc/CADENCE_ORG.md (Tier → Concrete Model, row <tier-name>):
  - <from_model>
  + <to_model>
```

Show the complete list of authored files that will be modified. Do NOT list or hand-edit compiled `.agents/agents` files — those are regenerated automatically in Step 5. Perform no file edits prior to confirmation.

### 4. Confirm with the user

Prompt the operator explicitly: *"Apply M adapter case arm(s) + 1 mapping row, then recompile?"* (where `M` is the number of matched adapter `case` arms found in Step 2). Wait for explicit operator approval before making any changes.

If the operator declines, halt immediately and confirm that zero files were modified.

### 5. Apply edits + recompile

For each matched adapter `case` arm, use the Edit tool to update the concrete model string from `$from_model` to `$to_model` (preserving any leading `<provider>/` prefix). Because each tier's model literal appears once in an adapter's resolution function, a targeted replacement per file is deterministic.

In `docs/agentic-sdlc/CADENCE_ORG.md`, use the Edit tool to update `$from_model` to `$to_model` within the matched cell of the `### Tier → Concrete Model` table.

Next, recompile the agent and skill trees from the neutral source:

```bash
bash ci-templates/scripts/cadence-compile.sh
```

Never manually edit `model:` lines inside compiled `.agents/agents` (or `.gemini/` / `.claude/agents`) files — they are build outputs, and running `cadence-compile.sh` is the sole sanctioned mechanism to propagate the updated model identifier across all agent definitions.

### 6. Verify propagation

Run the compiler in verification mode to confirm every representation is synchronized:

```bash
bash ci-templates/scripts/cadence-compile.sh --check
```

Verify BOTH post-conditions:

- `cadence-compile.sh --check` exits 0 (confirming every compiled agent `model:` line matches the adapter's fresh tier resolution).
- The `### Tier → Concrete Model` cell in `docs/agentic-sdlc/CADENCE_ORG.md` now contains `$to_model`.

If `cadence-compile.sh --check` exits non-zero, propagation is incomplete (`bump-model.reference_search.incomplete_representation_set`): if the compiler diagnostic output exceeds 30 lines, automatically pass the output through `offload_log_triage` (`local-fast-cpu` on `:11434`, preserving the full raw log in `/tmp/agy-last-triage.log`), then halt loud, report the diverging files, and instruct the operator to inspect `git diff` and revert manually — never attempt silent workarounds. This `--check` gate prevents any recurrence of representation drift (such as updating `CADENCE_ORG.md` or compiled files without updating the adapter script).

### 7. Report outcome

Provide a clear completion summary covering:

- The number of updated adapter `case` arms (`M`) plus the org mapping row (`1`), stated as `"M adapter case arm(s) + 1 mapping row updated, compiled tree regenerated"`.
- The exact file paths of the modified adapter script(s).
- Confirmation that all compiled agent `model:` fields under `.agents/agents/` were regenerated via `cadence-compile.sh` and verified clean via `--check`.
- A reminder that changes remain uncommitted in the working tree, inviting the operator to review `git diff ci-templates/scripts/adapters/ docs/agentic-sdlc/CADENCE_ORG.md .agents/agents` and commit with a message such as `Bump <tier> tier from <from> to <to>`.
- Explicit notice of surfaces intentionally left untouched by this skill:
  - Neutral-source denylist patterns in lint/check scripts — those are static guard patterns rather than live tier bindings (and `cadence-compile.sh --check` enforces round-trip consistency).
  - Narrative documentation mentioning historical model versions (release notes, ADRs, examples) — those require human editorial context.
  - External CI workflows, API gateways, or model-routing proxies outside the repository.
  - Other capability tiers (to update a second tier, invoke `/cadence-bump-model` separately for that tier).

## Out of Scope

- **Narrative documentation.** Prose references to model versions inside release notes, architecture discussions, or examples carry historical context and are never bulk-rewritten by this skill.
- **CI pipeline manifests.** External or repository CI workflow files that hardcode model names outside `ci-templates/scripts/adapters/` are not modified here.
- **External gateway routing.** API proxies, Portkey configurations, or local llama-server systemd units (`:11434`) are managed outside this skill.
- **Cross-tier reassignments.** Swapping a tier from one model family to another is an architectural change requiring a specification, not a version bump.
- **Multi-tier batching.** Each invocation updates exactly one tier so diffs and commit histories remain unambiguous.

---

## Worked Example (Gemini / Antigravity & Claude Runtimes)

In a repository configured for Gemini (`gemini-4-argon-high` for `Deep-reasoning`, `gemini-3.8-flash-high` for `Fast-mechanical`) or Claude (`claude-opus-N-M` for `Deep-reasoning`, `claude-sonnet-N-M` for `Fast-mechanical`), `CADENCE_ORG.md#model-tier-mapping` binds each tier to its family convention.

### Cross-family refusal (runtime-specific instance of the cross-tier rule)

If `$from_model` belongs to one capability family (e.g., `gemini-*-argon-*` or `claude-opus-*`) and `$to_model` belongs to another (e.g., `gemini-*-flash-*` or `claude-sonnet-*`), the skill refuses the operation — because model families map 1:1 to capability tiers (`Deep-reasoning` vs. `Fast-mechanical`), a cross-family replacement is a cross-tier change rather than a version bump.

### Invocations

```
/cadence-bump-model gemini-4-argon-preview gemini-4-argon-high
```

Updates the `Deep-reasoning` tier's concrete model identifier (and recompiles every `Deep-reasoning` agent to `gemini-4-argon-high`), leaving the `Fast-mechanical` tier untouched.

```
/cadence-bump-model gemini-3.7-flash-high gemini-3.8-flash-high
```

Updates the `Fast-mechanical` tier's concrete model identifier (and recompiles every `Fast-mechanical` agent to `gemini-3.8-flash-high`).

```
/cadence-bump-model gemini-4-argon-high gemini-3.8-flash-high
```

**Refused.** Moving from Argon (`Deep-reasoning`) to Flash (`Fast-mechanical`) crosses capability tiers. The skill halts and instructs the operator to open an intent ticket if a tier reassignment is desired.
