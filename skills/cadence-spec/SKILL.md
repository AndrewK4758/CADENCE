---
name: cadence-spec
description: Author a complete architectural specification and test plan from a triaged ticket using the Contextual Grounding Matrix (6W×4L) and CHORD decomposition
argument-hint: "[ticket-id]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Author a complete engineering specification and Gherkin test plan for the triaged issue `$ticket_id`. Delegate divergent design exploration to `cadence-explorer`, structural/architectural pre-flight review (`tier: High` mandatory, `tier: Medium` opt-in) to `cadence-architect`, and specification authoring to the `cadence-spec-author` subagent.

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

1. **Read the intake artifacts and run optional local codebase discovery:**
   - Read `specs/$ticket_id/problem.md` and `specs/$ticket_id/metadata.yaml`.
   - **Optional Local Discovery Pre-Pass (`local_semantic_embed` / `repo-scout`, Cloud-Only Fallback).** Prior to broad repository file reads, when local offload (`:11434`) is reachable, invoke `local_semantic_embed` (`top_k=6` on `:11434`) and/or `repo-scout` to map affected codebase symbols, cross-boundary contracts, CHORD seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`), and prior architecture records (`docs/ADR/`, `docs/agentic-sdlc/intent-insights.md`), falling back cleanly to cloud-only `Grep`/`Glob` if unavailable. Forward the resulting symbol map and exact `file:line` references to `cadence-explorer` (Step 2) and `cadence-spec-author` (Step 3).

2. **Explore the design space (mandatory independent pre-step).** Invoke the `cadence-explorer` subagent (`Deep-reasoning` tier, `xhigh` effort), which will:
   - Inspect `specs/$ticket_id/problem.md`, `specs/$ticket_id/metadata.yaml`, and the affected source files identified in Step 1
   - Write `specs/$ticket_id/design-options.md` containing two or three structurally distinct, steelmanned architectural options — at least one diverging from established repository conventions with its unresolved failure modes marked `UNKNOWN` — and containing **ZERO rankings and ZERO recommendations**

   `design-options.md` is a **committed** specification artifact with the same governance standing as `spec.md` and `test-plan.md`: it moves into `archive/$ticket_id/` during `/cadence-archive`, and its presence on disk is what triggers `verify-spec.sh` to enforce the `## Design Exploration` section in `spec.md`. Authoring `design-options.md` without committing it would silently downgrade the ticket into one that appears not to have run design exploration — causing the linter to emit a mere warning and pass. Always stage and commit `design-options.md` alongside `spec.md` and `test-plan.md`.

   This exploration step is **owned directly by `/cadence-spec`**, and **must never be invoked internally by `cadence-spec-author`**. Structural separation between option generation and option selection is the core invariant: a single agent generating and judging its own alternatives can subtly rig the comparison.

   Tier gating is **already enforced by Step 0**: because Low and Trivial tickets halt at Step 0 prior to any file checks, Step 2 is unreachable for those tiers and never writes `design-options.md` for them.

   If `cadence-explorer` fails or is unavailable, **surface the failure** to the operator and **ask explicitly whether to proceed** without divergent exploration. Only if the operator confirms proceeding may `cadence-spec-author` record the explicit **not-performed marker** disclosing the skipped exploration in `spec.md`. **Never bypass Step 2 silently** — an undisclosed skip masquerades as a fully explored design.

2.5. **Architectural pre-flight review (`cadence-architect` -- mandatory at `tier: High`, opt-in at `tier: Medium` per `docs/policies/change-tiers.md`).** Dispatch `cadence-architect` (`Deep-reasoning` tier, `xhigh` effort) after Step 2 exploration to check cross-boundary dependencies, contract compatibility, and failure modes before authoring converges. Pass all returned findings, Draft Contracts, and Open Questions into `cadence-spec-author` in Step 3; because `cadence-architect` is strictly headless, resolve any clarification questions it returns interactively with the operator here in `/cadence-spec` before final Gate 1 sign-off.

3. **Delegate to `cadence-spec-author` (`Deep-reasoning` tier, `xhigh` effort).** Pass `specs/$ticket_id/problem.md`, `design-options.md`, and any Step 2.5 `cadence-architect` outputs. The subagent will:
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

   - **Optional Failure Triage (`offload_log_triage`).** Whenever `verify-spec.sh` exits **non-zero** (or emits multi-line failure output exceeding 30 lines) and local offload (`:11434`) is reachable, pass its output through `offload_log_triage` (`cwd="<repo-root>"`, preserving raw numbered lines in `/tmp/agy-last-triage.log`; otherwise inspect directly) to extract the verbatim failing check assertions and exact `file:line` coordinates. Return those failures to `cadence-spec-author`, then **re-run `verify-spec.sh` until exit 0.**
   - **`design-options.md` neutrality & completeness:** When `design-options.md` is present, `verify-spec.sh` also validates `Axis of variation`, all 6 required per-option bullets, non-empty `UNKNOWN` modes, and zero ranking leakage.
   - `WARN` diagnostics must be surfaced to the operator in Step 7 so Gate 1 verifies nothing was dropped.

   **Run the mechanical citation and fact verifier (`verify-facts.sh`) under the same loop-until-green discipline:**

   ```bash
   .agents/skills/cadence-spec/verify-facts.sh $ticket_id
   ```

   This script validates `Files Affected` entries, every backticked `path:N` / markdown `#LN` citation across `spec.md`, `problem.md`, `design-options.md`, and `decisions.md`, plus identifier-proximity near cited lines. Whenever `verify-facts.sh` exits non-zero, route through `offload_log_triage` and return `FAIL` lines to `cadence-spec-author` until clean.

   **Run the hybrid certainty gate (`certainty-gate.sh`) after `verify-facts.sh`:**

   ```bash
   ( .agents/skills/cadence-certainty/certainty-gate.sh --stage spec [--strictness halt|escalate] $ticket_id \
     || skills/cadence-certainty/certainty-gate.sh --stage spec [--strictness halt|escalate] $ticket_id )
   ```
   Pass `--strictness halt` or `--strictness escalate` only if the operator explicitly overrides repo-level strictness in the command; otherwise `certainty-gate.sh` resolves it from `CADENCE_ORG.md#completeness-strictness-binding` (or root `AGENTS.md`/`GEMINI.md`/`CLAUDE.md`).

   - **Exit `1` (`decision=HALT`):** Return falsified `proof.ref` / `anchor_substring` / `absence` / DAG findings or strict-mode completeness gaps (`unruled_known_risk`, `pillar_precedence_inversion`, `missing_shared_invariant_absence_proof`) directly to `cadence-spec-author` until fixed.
   - **Exit `2` (`decision=ESCALATE_HUMAN`):** If `completeness_strictness_unconfigured` fired, **prompt the operator** to choose `halt` (team >1 enforcing review) vs `escalate` (solo/advisory) for this run (and offer to persist the markers in `CADENCE_ORG.md` / `AGENTS.md`). Surface all `ESCALATE` triggers (`unanswered_probes`, `unmapped_unknowns`, `unruled_known_risk`, `pillar_precedence_inversion`, `missing_shared_invariant_absence_proof`, `inference_depth_exceeded`, `unruled_unknown`) explicitly in Step 7 and `## Open Questions` for Gate 1 human ruling.

4.5. **Adversarial Spec Challenge (Pre-Gate-1 Red-Team, Medium/High).** Once Step 4 mechanical checks (`verify-spec.sh`, `verify-facts.sh`, `certainty-gate.sh`) exit `0`, dispatch dedicated read-only `cadence-spec-challenger` (`Deep-reasoning` tier, `xhigh` effort) supplied ONLY with `problem.md`, `design-options.md`, `spec.md`, `test-plan.md`, and repository source access (zero authoring-session reasoning) to:
   - Probe all 7 falsification checks (`docs/policies/completeness-invariants.md`): upgrade/sibling default drift, exception hierarchy & external authority/TTL reality vs `# STATUS: Verified`, multi-suspension/post-lock re-validation/stream completeness, grammar/lexer/math bounds, sibling surface parity + unsafe `Out of Scope` carve-outs + `<400`-line split plans, anti-mock/coupled-invariant/chaos (`CP-12`–`CP-14`) `test-plan.md` coverage, and Pillar Precedence non-inversion / unmitigated `KNOWN` safety holes;
   - Feed any `[HIGH]`/`[MEDIUM]` findings from `Verdict: CHALLENGE_ISSUES` back into `cadence-spec-author` (re-running Step 4 mechanical gates + `cadence-spec-challenger` until `Verdict: PASS`) before advancing.

5. **Verify engineering completeness (judgment review).** Confirm every AC maps cleanly to design signatures and Gherkin scenarios, the 6W×4L matrix is substantively populated, `## Design Exploration` documents the flip condition and steelman counter-argument, and risks + `OQ-N` capture every unresolved challenge.

6. **Update ticket metadata and project to tracker:**
   - Set `status: spec-in-review` in `specs/$ticket_id/metadata.yaml`
   - **Record the spec stage effort** (`CADENCE_ORG.md#actual-effort-accumulation`): invoke `(test -x ci-templates/scripts/stage-effort.sh && ci-templates/scripts/stage-effort.sh || processes/ci-templates/scripts/stage-effort.sh) --stage spec --observed <minutes>`, verify `0m` or a 15-minute multiple, and append to `stage_effort` + `actual_effort` using `date -u +%Y-%m-%dT%H:%M:%SZ`.
   - Execute the repository's designated tracker sync skill (`CADENCE_ORG.md#tracker-binding`) for `$ticket_id`.

7. **Report to the operator:**
   - Concise overview of the proposed architecture and CHORD decomposition
   - Key engineering decisions logged in `decisions.md`
   - Open questions requiring human Gate 1 rulings
   - Any non-blocking `WARN` or `UNVERIFIABLE` lines emitted by `verify-spec.sh` or `verify-facts.sh`
   - Recommendation to review the specification artifacts and open the spec-approval MR
   - **Standalone Watch Handoff Prompt:** Only when `/cadence-spec` was invoked directly (skip when invoked inside `/cadence-define` or `/cadence-parallel`, or when non-interactive) and `spec_mr` is populated (or once the spec-approval MR is opened), ask whether to invoke `/cadence-watch $ticket_id` (`watch` = `--watch` live poll / `once` = `--once` single check / `no` = stop here), invoking `/cadence-watch` only on explicit confirmation and never auto-polling silently.

## Example

```
/cadence-spec TT-6547
```

## Local Model Offload Integration (:11434)
- When `:11434` is reachable, Step 1 optionally invokes `local_semantic_embed` (`top_k=6` on `:11434`) to gather type signatures, cross-boundary contracts, and prior insights without polluting the primary context window (cloud `Grep`/`Glob` fallback when absent).
- When `:11434` is reachable, Step 4 optionally pipes `verify-spec.sh` or `verify-facts.sh` failure output through `offload_log_triage` (`cwd="<repo-root>"` on `:11434`) to extract verbatim `FAIL` assertions and `file:line` coordinates.
- Specification authoring, convergent judgment, and the Step 4.5 Adversarial Spec Challenge remain 100% owned by `Deep-reasoning` models (`effort: xhigh`, routed by `CADENCE_ORG.md#model-tier-mapping`).
