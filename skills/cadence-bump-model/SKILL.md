---
name: cadence-bump-model
description: Update the concrete model identifier for a capability tier across adapter scripts, CADENCE_ORG.md, agent definitions (agent.md default_model), and skill delegation routing after operator confirmation of the diff.
argument-hint: "<from-model> <to-model>"
arguments: [from_model, to_model]
allowed-tools: Read Edit Glob Grep Bash
---

## Task

Update a single capability tier's concrete model identifier from `$from_model` to `$to_model` across every authoritative representation atomically in one run: the tier-resolution `case` arm in runtime adapter scripts (`processes/ci-templates/scripts/adapters/*.sh` or `ci-templates/scripts/adapters/*.sh`), the concrete-model cell in `docs/agentic-sdlc/CADENCE_ORG.md#model-tier-mapping`, and `.agents/agents/*/agent.md` (`agents/*/agent.md` in core) `default_model:` lines when applicable. (Project `.gemini/` projections via `adapters/gemini-agy.sh`.)

CADENCE defines two primary capability tiers (`Deep-reasoning` and `Fast-mechanical`) in `CADENCE_ORG.md#model-tier-mapping`, alongside read-only local hardware coprocessor tiers (`local-fast-cpu`, `local-embed-cpu`, `local-12b-gpu`, `local-moe-hybrid`). Each capability tier maps to a single concrete model identifier for the active runtime. This skill updates the concrete model identifier for **one tier per invocation** — requiring explicit `from` and `to` model arguments so tier boundaries stay explicit and accidental cross-tier reassignments are prevented.

## Prerequisites

- Both `$from_model` and `$to_model` must be supplied. If either argument is missing, halt and display the required syntax: `/cadence-bump-model <from-model> <to-model>`.
- Both model strings must conform to the naming pattern documented in `CADENCE_ORG.md#model-tier-mapping` for the repository's bound runtime. If either string deviates from the expected naming pattern in the mapping table, warn the operator — model naming conventions occasionally change across vendor generations, but an unexpected format is usually a typo. Continue only after explicit operator confirmation.
- The `#model-tier-mapping` section must be present in `CADENCE_ORG.md` (`docs/agentic-sdlc/CADENCE_ORG.md` or `processes/docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md` in core). If missing, halt without modifying files.

## Steps

### 1. Validate arguments

Verify that both `$from_model` and `$to_model` are non-empty and match the model naming convention in `CADENCE_ORG.md#model-tier-mapping`.

If `$from_model` and `$to_model` belong to **different capability tiers** in the mapping table, **halt and refuse**. Reassigning a tier to a different model family/tier is an architectural change affecting reasoning depth, latency, and cost rather than a version bump — it requires an intent ticket and specification rather than `/cadence-bump-model`. Inform the operator clearly that this skill only updates the concrete model version within a single capability tier.

When `$to_model` does not yet appear anywhere in the mapping table (the standard case when adopting a newly released model version), resolve `$from_model`'s tier from the table and treat the operation as an in-tier upgrade for that tier. Refuse only when `$to_model` is already assigned to a *different* tier's row, or when the runtime's model-family naming convention makes a cross-tier mismatch unmistakable (see Worked Example below).

### 2. Find all authored references

Locate all concrete model references across adapters, `CADENCE_ORG.md`, and `.agents/agents/*/agent.md` (`default_model:` lines):

```bash
grep -rn "$from_model" ci-templates/scripts/adapters/ processes/ci-templates/scripts/adapters/ agents/ .agents/agents/ 2>/dev/null || true
```

**Org mapping table row:** locate the row inside `### Tier → Concrete Model` under `CADENCE_ORG.md#model-tier-mapping` whose concrete-model column currently contains `$from_model`.

If neither the adapter scripts/`agent.md` nor `CADENCE_ORG.md` matches `$from_model`, halt and report zero matches (indicating a typo, already-completed bump, or unconfigured model). If only one target matches, surface the discrepancy and ask the operator before making partial edits.

### 3. Show the user a diff

Display the exact proposed replacements (`<file>: - <from_model> / + <to_model>`) across adapters, `CADENCE_ORG.md`, and any matching `agent.md` `default_model:` lines. Perform zero edits prior to explicit confirmation.

### 4. Confirm with the user

Prompt the operator explicitly: *"Apply M file updates + 1 mapping row?"* Wait for explicit approval before editing; if declined, halt with zero files modified.

### 5. Apply edits + sync runtime projections

Use Edit to update `$from_model` -> `$to_model` (preserving any `<provider>/` prefix) in matched adapter scripts, `CADENCE_ORG.md`, and matched `.agents/agents/*/agent.md` `default_model:` lines. If `.gemini/` projection exists, run the adapter script (`gemini-agy.sh`) to keep projections in sync.

### 6. Verify consistency

Confirm every `default_model:` in `.agents/agents/*/agent.md`, matched adapter `case` arms, and `CADENCE_ORG.md#model-tier-mapping` agrees on `$to_model`, and confirm zero stale `$from_model` entries remain outside historical prose (`grep -rn "$from_model" ...`). If drift remains (`bump-model.reference_search.incomplete_representation_set`), halt loud naming the diverging files.

### 7. Report outcome

Summarize updated file paths (`adapter(s)`, `CADENCE_ORG.md`, `agent.md`), confirm verification passed, remind the operator to review `git diff`, and note historical prose/ADRs/external proxies were left untouched.

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
