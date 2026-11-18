---
name: cadence-maintain
description: Evaluate a code-reviewed change proposal (MR/PR/patchset) for maintainer-level acceptance -- surface compatibility, architectural integrity, mission alignment, operational resilience, and release readiness
argument-hint: "[MR number or branch name]"
arguments: [mr_ref]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Assess the change proposal `$mr_ref` (whether a GitLab MR, GitHub PR, or SourceHut patchset) for maintainer-level project acceptance. Run the mandatory Step 0 mechanical pre-scan via `offload_deep_review` and delegate the eight-dimension maintainer analysis to the `cadence-maintainer` subagent. Evaluation inputs are forge-neutral: `git diff` and `specs/{ticket-id}/submission.md` (the repository's canonical change-proposal record), requiring no external forge API calls (`docs/guides/submitting-changes.md`). Because maintainer acceptance is a human governance gate, this skill runs interactively — presenting the structured assessment and capturing the human maintainer's `Accept`, `Postpone`, or `Reject` ruling.

## Prerequisites

Prior to invoking `cadence-maintainer`, verify both preconditions:

1. **Code review approval is recorded.** Confirm that `cadence-reviewer` has approved this change proposal by checking `submission.md`'s `## Discussion`, the forge thread comments, or the review record in the ticket's spec directory. If code review has not yet approved the proposal, stop and instruct the operator to run `/cadence-review $mr_ref` first.

2. **Specification contract is satisfied.** Confirm that `specs/{ticket-id}/spec.md` exists and `metadata.yaml` carries a status of `spec-approved` or later. When `spec.md` is absent, warn the operator and proceed with a general maintainer evaluation — **except** when a valid tier escalation ruling applies. **Always resolve `tier:` from `metadata.yaml` first (case-insensitively, stripped of surrounding whitespace), and for Medium/High tickets inspect `specs/{ticket-id}/decisions.md` for a post-implementation tier-escalation entry (`docs/policies/change-tiers.md#escalation`).** Whenever such an escalation entry explicitly names each promoted `decisions.md` entry and explains why each predated and governed the implementation, the missing `spec.md` is **compliant by ruling** — emit no warning — and evaluate the change against those promoted decision entries instead. Conversely, an **unqualified** escalation (omitting the promoted entry identifiers or the rationale for why each qualifies) is surfaced directly to the human maintainer as a finding.

## Steps

0. **Mandatory Automatic Mechanical Pre-Scan (`offload_deep_review`).** Once the branch reference and integration branch diff (`git diff <integration-branch>...{branch-name}`) are resolved in Steps 1–3, automatically invoke `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:11434`) on the diff **before** delegating to `cadence-maintainer`. The local coprocessor performs an advisory pre-scan verifying:
   - Single-pass readability ceiling (`<400` lines per modified/added file under the Agentic Ergonomics pillar)
   - Comment and docstring preservation discipline
   - CHORD observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) and public Surface Compatibility markers
   Forward the pre-scan output to `cadence-maintainer` in Step 4 so `gemini-4-argon-high` verifies any mechanical flags alongside the eight maintainer dimensions.

1. **Resolve the change-proposal reference:**
   - When `$mr_ref` is an integer, treat it as the forge thread number (GitLab MR IID, GitHub PR number, or SourceHut patchset ID). Resolve it locally to its branch and ticket ID by reading `merge_request:` in `specs/{ticket-id}/metadata.yaml` or `Thread URL` under `## Forge metadata` in `specs/{ticket-id}/submission.md`. If local metadata cannot map the number, ask the operator for the branch name (no forge API call is required).
   - When `$mr_ref` is a branch name, use it directly.
   - Extract `{ticket-id}` from the final `/`-delimited segment of the branch name per the `branch-naming-convention` declared in `CADENCE_ORG.md#branch-strategy-binding` (with full strategy narrative under `docs/policies/branch-strategy/`).

2. **Confirm prerequisites:**
   - Verify code-reviewer approval is on record
   - Verify the specification (or qualified escalation ruling) is present and approved

3. **Compute the branch diff** against the repository's integration branch (resolving `<integration-branch>` dynamically from the `integration-branch` marker in `CADENCE_ORG.md#branch-strategy-binding` per `ADR_CADENCE-0020`; never hardcode a branch name):
   ```bash
   git diff <integration-branch>...{branch-name}
   ```
   Run Step 0's automatic `offload_deep_review` pre-scan on this diff prior to Step 4.

4. **Delegate to `cadence-maintainer` (`Model="pro"`).** Pass the diff, the spec/decision artifacts, and Step 0's `offload_deep_review(diff_range="<integration-branch>...{branch-name}", cwd="<repo-root>")` pre-scan so the subagent evaluates all eight maintainer dimensions:
   - Surface Compatibility and backwards-compatible API stability
   - Architectural alignment with ratified ADRs and repository conventions
   - Mission alignment against `PROJECT_INTENT.md` (fitness vs. scope creep)
   - Long-term maintenance burden and Structural Simplicity budget
   - Security Boundary Posture and threat-surface shifts
   - Release readiness (CHANGELOG coverage, deprecation notices, migration guides)
   - Dependency hygiene and supply-chain risk
   - Documentation currency (`docs/flows/*.md` and `SYSTEM_OVERVIEW.md` accuracy)

5. **Present the Maintainer Assessment** to the human operator, displaying the eight-dimension evaluation and the subagent's recommendation.

6. **Capture the human maintainer's ruling:**
   - **Accept** -- approve the change proposal to merge into the integration branch
   - **Postpone** -- defer merging with a documented rationale
   - **Reject** -- decline the change proposal with actionable remediation guidance for the author

6b. **Disposition owed follow-up findings** across **all three** verdicts (`Accept`, `Postpone`, `Reject`). Format scratch drafts as `specs/drafts/{ticket-id}-maintain-<UTC>-<N>.md` (`<UTC>` captured once via `date -u +%Y%m%dT%H%M%SZ`; `<N>` = 1-based ordinal).

   Execute **Steps a–e** of [followup-disposition.md](../cadence-review/references/followup-disposition.md) with `<gate>` = `/cadence-maintain`:
   - If `submission.md` **is absent**, report the missing change-proposal record and **halt Step 6b without allocating any id** (never file without `submission.md` to record disposition).
   - Enforce unlabelled halt (`finding.class.unlabelled`), degraded deferral (`followup.filing.composition_unavailable` / `followup.filing.confirmation_channel_unavailable`), semantic dedupe across `specs/` and `archive/` (`followup.dedupe.check_unavailable` on unreadable root), `--file-only` filing/fold (`followup.filing.draft_cleanup_failed` on cleanup miss), and canonical `Follow-ups created` templates (with human rationale for any declined item). Items classed `adr-owed` remain in `## Discussion` for `/cadence-archive` Step 1b.

7. **Execute post-decision updates** corresponding to the maintainer's ruling:
   - **Record the maintainer stage effort (across all decisions).** Always record maintainer effort per `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation": append a `stage_effort` item to `specs/{ticket-id}/metadata.yaml` (`stage: maintainer`, `at` = exact `date -u +%Y-%m-%dT%H:%M:%SZ`) whose `effort` comes from running `([ -x ci-templates/scripts/stage-effort.sh ] && ci-templates/scripts/stage-effort.sh || processes/ci-templates/scripts/stage-effort.sh) --stage maintainer --observed <minutes>`. **Verify** `effort` equals `0m` or an exact 15-minute multiple (recomputing on mismatch without halting) and add to `actual_effort`.
   - **Accept:** set `maintainer_approved_at` in `metadata.yaml` to the **exact** current UTC wall-clock timestamp from `date -u +%Y-%m-%dT%H:%M:%SZ` (full second precision; never date-only, midnight, or rounded) and commit any finalized documentation updates
   - **Postpone:** append the postponement rationale to `specs/{ticket-id}/decisions.md` and update `metadata.yaml`
   - **Reject:** append the rejection rationale and author guidance to `specs/{ticket-id}/decisions.md` and update `metadata.yaml`
   - **Project to tracker.** Once `metadata.yaml` is saved, invoke the repository's designated tracker sync skill (resolved from `CADENCE_ORG.md` §9, Tracker Binding) for `{ticket-id}` to project the maintainer decision and post the new `stage_effort` entry as a per-stage worklog.

8. **Report outcome** to the operator summarizing the recorded decision, follow-up dispositions, and tracker projection status.

## Example

```
/cadence-maintain 142
/cadence-maintain feature/26.5.TT/TT-6547
```

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 0 automatically invokes `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:11434`) to pre-scan the branch diff for `<400`-line ceiling compliance, comment discipline, and CHORD observability seams before delegating to `cadence-maintainer`.
- Step 6b.c uses `local_semantic_embed` (`local-embed-cpu` on `:11434`, 0 MB VRAM) / `local-moe-hybrid` when checking `specs/` and `archive/` for prior-work deduplication.
- Maintainer evaluation across the eight governance dimensions and human decision capture remain 100% owned by `gemini-4-argon-high`.
