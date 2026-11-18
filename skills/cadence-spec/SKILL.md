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
   - **Automatic Local Discovery Pre-Pass (`local_semantic_embed` / `repo-scout`).** Prior to broad repository file reads, automatically invoke `local_semantic_embed` (`top_k=6` on `:11434`) and/or `repo-scout` to map affected codebase symbols, cross-boundary contracts, CHORD seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`), and prior architecture records (`docs/ADR/`, `docs/agentic-sdlc/intent-insights.md`). Forward the resulting symbol map and exact `file:line` references to `cadence-explorer` (Step 2) and `cadence-spec-author` (Step 3).

2. **Explore the design space (mandatory independent pre-step).** Invoke the `cadence-explorer` subagent (`Model="pro"` in Antigravity), which will:
   - Inspect `specs/$ticket_id/problem.md`, `specs/$ticket_id/metadata.yaml`, and the affected source files identified in Step 1
   - Write `specs/$ticket_id/design-options.md` containing two or three structurally distinct, steelmanned architectural options — at least one diverging from established repository conventions with its unresolved failure modes marked `UNKNOWN` — and containing **ZERO rankings and ZERO recommendations**

   `design-options.md` is a **committed** specification artifact with the same governance standing as `spec.md` and `test-plan.md`: it moves into `archive/$ticket_id/` during `/cadence-archive`, and its presence on disk is what triggers `verify-spec.sh` to enforce the `## Design Exploration` section in `spec.md`. Authoring `design-options.md` without committing it would silently downgrade the ticket into one that appears not to have run design exploration — causing the linter to emit a mere warning and pass. Always stage and commit `design-options.md` alongside `spec.md` and `test-plan.md`.

   This exploration step is **owned directly by `/cadence-spec`**, and **must never be invoked internally by `cadence-spec-author`**. Structural separation between option generation and option selection is the core invariant: a single agent generating and judging its own alternatives can subtly rig the comparison.

   Tier gating is **already enforced by Step 0**: because Low and Trivial tickets halt at Step 0 prior to any file checks, Step 2 is unreachable for those tiers and never writes `design-options.md` for them.

   If `cadence-explorer` fails or is unavailable, **surface the failure** to the operator and **ask explicitly whether to proceed** without divergent exploration. Only if the operator confirms proceeding may `cadence-spec-author` record the explicit **not-performed marker** disclosing the skipped exploration in `spec.md`. **Never bypass Step 2 silently** — an undisclosed skip masquerades as a fully explored design.

3. **Delegate to `cadence-spec-author` (`Model="pro"`).** The subagent will:
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

   - **Automatic Failure Triage (`offload_log_triage`).** Whenever `verify-spec.sh` exits **non-zero** (or emits multi-line failure output), automatically pass its output through `offload_log_triage` (`cwd="<repo-root>"`, preserving raw numbered lines in `/tmp/agy-last-triage.log`) to extract the verbatim failing check assertions and exact `file:line` coordinates. Return those failures to `cadence-spec-author`, then **re-run `verify-spec.sh` until exit 0.**
   - **`design-options.md` neutrality & completeness:** When `design-options.md` is present, `verify-spec.sh` also validates `Axis of variation`, all 6 required per-option bullets, non-empty `UNKNOWN` modes, and zero ranking leakage.
   - `WARN` diagnostics must be surfaced to the operator in Step 7 so Gate 1 verifies nothing was dropped.

   **Run the mechanical citation and fact verifier (`verify-facts.sh`) under the same loop-until-green discipline:**

   ```bash
   .agents/skills/cadence-spec/verify-facts.sh $ticket_id
   ```

   This script validates `Files Affected` entries, every backticked `path:N` / markdown `#LN` citation across `spec.md`, `problem.md`, `design-options.md`, and `decisions.md`, plus identifier-proximity near cited lines. Whenever `verify-facts.sh` exits non-zero, route through `offload_log_triage` and return `FAIL` lines to `cadence-spec-author` until clean.

4.5. **Adversarial Spec Challenge (Pre-Gate-1 Red-Team, Medium/High).** Once mechanical checks exit `0`, dispatch a read-only challenger (`cadence-reviewer` or `cadence-architect` with `Model="pro"`) supplied ONLY with `problem.md`, `design-options.md`, `spec.md`, `test-plan.md`, and repository source access (zero authoring-session reasoning) to:
   - Attempt to construct a concrete counterexample violating each CHORD `Condition`, `Rule`, or `Delta` that lacks a negative/concurrency/timeout scenario in `test-plan.md`;
   - Verify any `# STATUS: Verified` boundary claims or `Files Affected` signatures against real callee implementations and callers;
   - Flag any existing target file approaching `<400` lines that lacks a split plan, or any unstated failure mode missing from `## Open Questions` (`OQ-N`).
   Feed concrete findings back into `cadence-spec-author` (re-running Step 4 gates after any edit) before advancing.

5. **Verify engineering completeness (judgment review).** Confirm every AC maps cleanly to design signatures and Gherkin scenarios, the 6W×4L matrix is substantively populated, `## Design Exploration` documents the flip condition and steelman counter-argument, and risks + `OQ-N` capture every unresolved challenge.

6. **Update ticket metadata and project to tracker:**
   - Set `status: spec-in-review` in `specs/$ticket_id/metadata.yaml`
   - **Record the spec stage effort** (`CADENCE_ORG.md` §12): invoke `(test -x ci-templates/scripts/stage-effort.sh && ci-templates/scripts/stage-effort.sh || processes/ci-templates/scripts/stage-effort.sh) --stage spec --observed <minutes>`, verify `0m` or a 15-minute multiple, and append to `stage_effort` + `actual_effort` using `date -u +%Y-%m-%dT%H:%M:%SZ`.
   - Execute the repository's designated tracker sync skill (`CADENCE_ORG.md` §9) for `$ticket_id`.

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

## Local Model Offload Integration (Antigravity + llama-swap)
- Step 1 automatically invokes `local_semantic_embed` (`top_k=6` on `:11434`) to gather type signatures, cross-boundary contracts, and prior insights without polluting the primary context window.
- Step 4 automatically pipes any `verify-spec.sh` or `verify-facts.sh` failure output through `offload_log_triage` (`cwd="<repo-root>"` on `:11434`) to extract verbatim `FAIL` assertions and `file:line` coordinates.
- Specification authoring, convergent judgment, and the Step 4.5 Adversarial Spec Challenge remain 100% owned by Deep-reasoning models (`Model="pro"`).
