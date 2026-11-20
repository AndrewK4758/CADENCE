---
name: cadence-certainty
description: Run the deterministic empirical certainty and human-escalation gate (certainty-gate.sh) on a ticket — falsifying codebase proofs, absence regexes, inference chains, scope drift, dormant pillar contradictions, and HEAD-SHA test receipts without AI self-grading
argument-hint: "<ticket-id> [--stage auto|spec|implement|review] [--base <ref>] [--strictness auto|halt|escalate] [--require-evidence]"
arguments: [ticket_id]
allowed-tools: Read Edit Bash
---

## Task

Run the read-only deterministic certainty evaluator (`certainty-gate.sh`) against `specs/$ticket_id/` (or `archive/$ticket_id/`), enforcing empirical verification and halting for a human ruling whenever epistemic uncertainty, unmapped unknowns, unanswered probes, scope drift, or review oscillation triggers.

**Never self-rate certainty in prose.** Certainty is computed strictly by `certainty-gate.sh` from repository ground truth (`git`, `problem.md`, `design-options.md`, `spec.md`, `decisions.md`, `submission.md`, and `evidence.yaml`).

## Steps

1. **Resolve and execute `certainty-gate.sh`:**
   ```bash
   ( .agents/skills/cadence-certainty/certainty-gate.sh $ticket_id \
     || skills/cadence-certainty/certainty-gate.sh $ticket_id )
   ```
   Pass `--stage spec|implement|review`, `--base <integration-branch>`, `--code-root <dir>` (repeatable for satellite code repositories), `--strictness auto|halt|escalate` (when the user explicitly overrides repo strictness in the command), or `--require-evidence` when supplied by the caller or workflow stage. When output exceeds 30 lines and local offload (`:11434`) is reachable, pipe it through `offload_log_triage` (`cwd="<repo-root>"`, raw escape hatch at `/tmp/agy-last-triage.log`; fall back to direct inspection if unavailable).

   **Repo-level strictness resolution (`docs/policies/completeness-invariants.md` §5):** By default (`--strictness auto`), `certainty-gate.sh` reads `team-size` / `enforce-review` / `completeness-strictness` from `docs/agentic-sdlc/CADENCE_ORG.md#completeness-strictness-binding` (falling back to root `AGENTS.md`, `GEMINI.md`, or `CLAUDE.md`): multi-person reviewed repos (`team-size > 1` + `enforce-review: yes`) resolve to `halt` (`exit 1`); solo or non-reviewed repos resolve to `escalate` (`exit 2`). If the user explicitly requests strict or advisory enforcement in the command, pass `--strictness halt` or `--strictness escalate`. If the repo-level rule is not in place, `certainty-gate.sh` emits `ESCALATE completeness_strictness_unconfigured` (`exit 2`) — **prompt the user** to choose `halt` vs `escalate` for this run (and offer to record the markers in `CADENCE_ORG.md` / `AGENTS.md`) rather than guessing silently.

2. **Act strictly on the deterministic exit code:**
   - **Exit `0` (`decision=PROCEED`):** All Layer 1 (and Layer 2 when `evidence.yaml` exists) checks passed. Report the final `decision=PROCEED ...` summary line and continue the calling workflow.
   - **Exit `1` (`decision=HALT`, `grade=INSUFFICIENT`):** Mechanical falsification or strict-mode completeness failure detected (`hallucinated_ref`, `ref_out_of_bounds`, `missing_symbol`, `anchor_mismatch`, `falsified_absence`, `cyclic_inference`, `dormant_security_contradicted`, `stale_test_receipt`, `failing_test_receipt`, `receipt_log_hash_mismatch`, `verify_facts_failed`, `blocking_anomaly_in_approve`, or strict-mode `unruled_known_risk` / `pillar_precedence_inversion` / `missing_shared_invariant_absence_proof` / `unruled_review_waiver` / `unproven_safe_anomaly` / `reviewer_rationalized_defect` / `out_of_scope_shared_surface`). **Do NOT escalate a broken AI proof to a human** — fix the code, spec, test run, or `evidence.yaml` manifest directly and re-run `certainty-gate.sh`.
   - **Exit `2` (`decision=ESCALATE_HUMAN`, `grade=CONDITIONAL`):** Genuine uncertainty, unconfigured repo strictness (`completeness_strictness_unconfigured`), or advisory-mode completeness trigger requiring human judgment (`unanswered_probes`, `unmapped_unknowns`, `unruled_known_risk`, `pillar_precedence_inversion`, `missing_shared_invariant_absence_proof`, `out_of_scope_shared_surface`, `unpromoted_draft_contract`, `undeclared_blast_radius`, `inferred_on_unknown`, `inference_depth_exceeded`, `load_bearing_inferred_sensitive`, `unruled_unknown`, `high_unverifiable_ratio`, `cycle_oscillation`, `unruled_review_waiver`, `unproven_safe_anomaly`, or `reviewer_rationalized_defect`). **Pause autonomous progression immediately** before advancing phases or calling `ready_mr.sh`.

3. **Present the Human Escalation Packet (when Exit `2`):**
   - Quote the `ESCALATE` lines and final `decision=ESCALATE_HUMAN ... triggers=...` line verbatim.
   - If `completeness_strictness_unconfigured` fired, ask the operator to select `halt` (team >1 with enforced review) or `escalate` (solo/advisory) for this run (re-running with `--strictness <choice>`) and offer to persist the markers in `CADENCE_ORG.md` / `AGENTS.md`.
   - Group remaining failing triggers into concrete choices (e.g., resolve unanswered probe in `problem.md`, map `OQ-N`, promote or reject `# STATUS: Draft`, approve scope change, add shared-sink `absence` proof, or decide a `CLM-N` assumption).
   - Append each confirmed human decision to `specs/$ticket_id/decisions.md` using `Gate <1-3> ruling: <item> -- <agree|amend|override> -- <why>` (where `<item>` is `OQ-N`, `CLM-N`, `unknowns`, `known_risks`, `absence_waiver`, `anomaly_waiver`, `rationalization_waiver`, `scope_exclusion`, `completeness_strictness`, `probes`, `scope`, `draft`, `citations`, or `oscillation`), then re-run `certainty-gate.sh` to confirm exit `0` (`decision=PROCEED`).

## Example

```bash
/cadence-certainty ACME-201
certainty-gate.sh --stage review --base develop PLAT-644
```
