---
name: cadence-spec
description: Author a complete architectural specification and test plan from a triaged ticket using the Contextual Grounding Matrix (6W×4L) and CHORD decomposition
argument-hint: "[ticket-id]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Author a complete engineering specification and Gherkin test plan for the triaged issue `$ticket_id`. Delegate divergent design exploration to `cadence-explorer` and specification authoring to the `cadence-spec-author` subagent.

## Prerequisites

**Step 0 -- Resolve the ticket's tier PRIOR to any artifact existence check.** Inspect `specs/$ticket_id/metadata.yaml` and read the `tier:` field (matching case-insensitively after trimming surrounding whitespace). Because the resolved tier determines whether the Specification phase applies at all, do NOT run the `problem.md`/`metadata.yaml` completeness checks below until `tier` is resolved. Whenever `specs/$ticket_id/metadata.yaml` is missing or its `tier:` attribute cannot be parsed, route directly to the absent/unrecognized branch below.

- **tier: Low** -> STOP immediately. Under `docs/policies/change-tiers.md`, Low-tier changes have no Specification phase (`problem.md` acceptance criteria serve as the sole contract; no `spec.md` or `test-plan.md` is authored). Never create a spec and never invoke `cadence-spec-author`; inform the operator and exit cleanly.
- **tier: Trivial** -> STOP immediately. Trivial work requires no specification artifacts at all. Inform the operator and exit cleanly.
- **tier: Medium or tier: High** -> continue to the artifact existence checks below.
- **tier absent, empty, or any unrecognized value** -> STOP and fail loudly: echo the raw value verbatim and instruct the operator to populate a valid `tier:` in `metadata.yaml` or run `/cadence-triage $ticket_id` first. NEVER fall back or default to Low.

Confirm before proceeding:
- `specs/$ticket_id/problem.md` exists on disk (confirming triage has run)
- `specs/$ticket_id/metadata.yaml` exists with classification fields populated

When either prerequisite is missing, advise the operator to run `/cadence-triage $ticket_id` first.

## Steps

1. **Read the intake artifacts and run automatic local codebase discovery:**
   - Read `specs/$ticket_id/problem.md` and `specs/$ticket_id/metadata.yaml`.
   - **Automatic Local Discovery Pre-Pass (`local_semantic_embed` / `local-moe-hybrid`).** Prior to broad repository file reads, automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) and `local-moe-hybrid` (`local-moe-hybrid` on `:9380`) to map affected codebase symbols, cross-boundary contracts, CHORD seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`), and prior architecture records (`docs/ADR/`, `docs/agentic-sdlc/intent-insights.md`). Forward the resulting symbol map and exact `file:line` references to `cadence-explorer` (Step 2) and `cadence-spec-author` (Step 3).

2. **Explore the design space (mandatory independent pre-step).** Invoke the `cadence-explorer` subagent, which will:
   - Inspect `specs/$ticket_id/problem.md`, `specs/$ticket_id/metadata.yaml`, and the affected source files identified in Step 1
   - Write `specs/$ticket_id/design-options.md` containing two or three structurally distinct, steelmanned architectural options — at least one diverging from established repository conventions with its unresolved failure modes marked `UNKNOWN` — and containing **ZERO rankings and ZERO recommendations**

   `design-options.md` is a **committed** specification artifact with the same governance standing as `spec.md` and `test-plan.md`: it moves into `archive/$ticket_id/` during `/cadence-archive`, and its presence on disk is what triggers `verify-spec.sh` to enforce the `## Design Exploration` section in `spec.md`. Authoring `design-options.md` without committing it would silently downgrade the ticket into one that appears not to have run design exploration — causing the linter to emit a mere warning and pass. Always stage and commit `design-options.md` alongside `spec.md` and `test-plan.md`.

   This exploration step is **owned directly by `/cadence-spec`**, and **must never be invoked internally by `cadence-spec-author`**. Structural separation between option generation and option selection is the core invariant: a single agent generating and judging its own alternatives can subtly rig the comparison.

   Tier gating is **already enforced by Step 0**: because Low and Trivial tickets halt at Step 0 prior to any file checks, Step 2 is unreachable for those tiers and never writes `design-options.md` for them.

   If `cadence-explorer` fails or is unavailable, **surface the failure** to the operator and **ask explicitly whether to proceed** without divergent exploration. Only if the operator confirms proceeding may `cadence-spec-author` record the explicit **not-performed marker** disclosing the skipped exploration in `spec.md`. **Never bypass Step 2 silently** — an undisclosed skip masquerades as a fully explored design.

3. **Delegate to `cadence-spec-author`.** The subagent will:
   - Inspect all relevant source files and contracts surfaced in Step 1
   - Populate the Contextual Grounding Matrix (6W×4L) across What, How, Where, Who, When, and Why
   - Evaluate every mandatory Engineering Pillar (Structural Simplicity, Operational Resilience, Agentic Ergonomics, plus triggered Data & Audit Fidelity, Security Boundary Posture, and Surface Compatibility)
   - Decompose acceptance criteria using CHORD (Conditions, Handling/Triggers, Outcomes, Rules, Deltas) per `chord-reference.md` and design the proposed changes
   - Author the Gherkin scenarios and implementation order in `specs/$ticket_id/test-plan.md`
   - Record initial architectural decisions in `specs/$ticket_id/decisions.md`

4. **Verify structural completeness (deterministic mechanical gate).** Execute the Layer-1 specification linter against the authored files:

   ```bash
   .agents/skills/cadence-spec/verify-spec.sh $ticket_id
   ```

   This deterministic structural gate — the specification counterpart to `/cadence-elicit`'s unfilled-probe grep — verifies that all required headings are present, every mandatory Engineering Pillar is evaluated, CHORD decompositions (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) and Gherkin scenarios exist, and zero template placeholders remain unfilled.

   - **Automatic Failure Triage (`offload_log_triage`).** Whenever `verify-spec.sh` exits **non-zero** (or emits multi-line failure output), automatically pass its output through `offload_log_triage` (`local-fast-cpu` on `:9379`, preserving raw numbered lines in `/tmp/agy-last-triage.log`) to extract the verbatim failing check assertions and exact `file:line` coordinates of unfilled placeholders. Return those exact failures to `cadence-spec-author` for remediation, then **re-run `verify-spec.sh`. Repeat this loop until the script exits 0.** Never advance to Step 5 while any structural check fails.
   - `WARN` diagnostics (such as an acceptance-criterion count difference between `problem.md` and `spec.md`) do not block execution, but must be surfaced to the operator in Step 7 so the human spec-approval gate can verify no criterion was inadvertently dropped.

   Remember that `verify-spec.sh` checks *structural completeness*, not *engineering soundness*. Judging whether the Contextual Grounding Matrix (6W×4L) cells are accurate, whether the CHORD edge cases are realistic, and whether the chosen architecture is sound belongs to Step 5 and the human spec-approval gate.

   **Run the mechanical citation and fact verifier (BTG-331) under the same loop-until-green discipline:**

   ```bash
   .agents/skills/cadence-spec/verify-facts.sh $ticket_id
   ```

   This script validates every `Files Affected` entry (`Add`/`Modify`/`Delete`) and every backticked `path:N` line citation against the actual repository tree — eliminating manual proofreading of mechanical file facts. It blocks only when `spec.md` carries the `**Gate 1 rulings:** required` sentinel under Open Questions (specs without that sentinel emit `WARN` lines only and exit 0). Whenever `verify-facts.sh` exits non-zero, automatically pass the output through `offload_log_triage` (`local-fast-cpu` on `:9379`), hand the verbatim `FAIL` lines back to `cadence-spec-author`, and re-run until clean.

5. **Verify engineering completeness (judgment review).** Once both mechanical gates exit 0, verify:
   - Every acceptance criterion in `problem.md` maps to a concrete design element in `spec.md` and a Gherkin scenario in `test-plan.md`
   - Relevant cells of the Contextual Grounding Matrix (6W×4L) are substantively populated
   - `## Design Exploration` documents the selected option, the decisive tradeoff axis over the named runner-up, a concrete falsifiable flip-condition, and the strongest counter-argument -- or, if `design-options.md` was skipped with operator permission, the explicit not-performed marker
   - Operational and architectural risks are documented

6. **Update ticket metadata and project to tracker:**
   - Set `status: spec-in-review` in `specs/$ticket_id/metadata.yaml`
   - **Record the spec stage effort** in accordance with `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation": within the same `metadata.yaml` edit, append a `stage_effort` item (`stage: spec`, `at` = exact UTC completion timestamp from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded, midnight, or date-only) whose `effort` value comes directly from running `ci-templates/scripts/stage-effort.sh --stage spec --observed <minutes>` — the script resolves the stage review multiplier (including any operator-specific override), multiplies, and rounds up to a 15-minute increment (minimum `15m` for non-zero work; `0m` when the multiplier is `0`). **Verify before saving:** the rounded `effort` string MUST equal `0m` or an exact multiple of 15 minutes; if not, surface a visible diagnostic naming the invalid value, recompute, and continue without halting. Add the increment to `actual_effort`.
   - Execute the repository's designated tracker sync skill (resolved from `CADENCE_ORG.md` §9, Tracker Binding) for `{ticket-id}` to project the `spec-in-review` status and log the new `stage_effort` entry as a per-stage worklog.

7. **Report to the operator:**
   - Concise overview of the proposed architecture and CHORD decomposition
   - Key engineering decisions logged in `decisions.md`
   - Open questions requiring human Gate 1 rulings
   - Any non-blocking `WARN` or `UNVERIFIABLE` lines emitted by `verify-spec.sh` or `verify-facts.sh`
   - Recommendation to review the specification artifacts and open the spec-approval MR

## Example

```
/cadence-spec TT-6547
```

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 1 automatically invokes `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) and `local-moe-hybrid` (`local-moe-hybrid` on `:9380`) to gather type signatures, cross-boundary contracts, and prior insights without polluting the primary context window.
- Step 4 automatically pipes any `verify-spec.sh` or `verify-facts.sh` failure output through `offload_log_triage` (`local-fast-cpu` on `:9379`) to extract verbatim `FAIL` assertions and `file:line` coordinates.
- Contextual Grounding Matrix (6W×4L) analysis, CHORD decomposition, divergent design options, and Gherkin test plans remain 100% authored by `gemini-4-argon-high`.
