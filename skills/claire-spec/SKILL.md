---
name: claire-spec
description: Generate a complete specification from a triaged issue using the Zachman framework
argument-hint: "[ticket-id]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Generate a complete specification for the triaged issue `$ticket_id`. Use the `claire-spec-author` subagent for the analysis and writing.

## Prerequisites

**Step 0 -- Read the tier BEFORE any file-existence check.** Read `specs/$ticket_id/metadata.yaml` and resolve the `tier:` field (match case-insensitively, trimmed). The tier decides whether the Spec-authoring phase applies; do NOT evaluate the `problem.md`/`metadata.yaml` existence checks below until the tier is known. If `specs/$ticket_id/metadata.yaml` is absent or the `tier:` field cannot be read, treat that as the absent/unrecognized case below.

- **tier: Low** -> STOP. Low-tier work has no Spec-authoring phase (`docs/policies/change-tiers.md`: `problem.md` acceptance criteria only; no `spec.md`/`test-plan.md`). Do not author a spec and do not delegate to the `claire-spec-author` agent; tell the user and stop.
- **tier: Trivial** -> STOP. Not applicable (Trivial has no spec at all). Tell the user and stop.
- **tier: Medium or tier: High** -> proceed to the existing prerequisite checks below.
- **tier absent, empty, or any other value** -> STOP and fail loudly: report the value verbatim and instruct the user to set a valid `tier:` in `metadata.yaml` or run `/claire-triage $ticket_id` first. NEVER default to Low.

Verify before starting:
- `specs/$ticket_id/problem.md` exists (issue has been triaged)
- `specs/$ticket_id/metadata.yaml` exists with triage fields populated

If prerequisites are not met, suggest running `/claire-triage $ticket_id` first.

## Steps

1. **Read the triage artifacts:**
   - `specs/$ticket_id/problem.md`
   - `specs/$ticket_id/metadata.yaml`

2. **Explore the design space (independent pre-step).** Delegate to the `claire-explorer` subagent. It will:
   - Read `specs/$ticket_id/problem.md`, `specs/$ticket_id/metadata.yaml` and the affected source
   - Produce `specs/$ticket_id/design-options.md`: two or three structurally distinct, individually steelmanned options, at least one departing from the repository's established patterns with its unresolved failure modes labelled UNKNOWN, and **NO ranking and no recommendation** of any kind

   `design-options.md` is a **committed** ticket artifact, on the same footing as `spec.md` and `test-plan.md`: it travels with the ticket through `/claire-archive`, and it is what `verify-spec.sh` reads to decide whether this spec owes a Design Exploration section. A run that authors it and then leaves it out of the commit silently converts the ticket into one that "did not explore" -- the linter warns and passes, and nothing reports the gap. Commit it with the ticket's other spec artifacts.

   This is an **independent step of this skill**, and **never a sub-call the spec-author agent makes internally**. Independence is the whole point: an agent that can generate its own options can also launder the appearance of having considered them.

   Tier gating is **inherited, not re-implemented**: Step 0 has already STOPped at Low and at Trivial before any file-existence check, so this step is unreachable at those tiers and no `design-options.md` is produced for them.

   If the explorer cannot run, **report the failure** to the user and **ask whether to proceed** without exploration. If they choose to proceed, the spec-author records the explicit **not-performed marker** and the spec discloses the gap. **Never skip this step silently** -- a silently skipped step produces a spec that looks explored and is not, which is worse than one that says it was not.

3. **Delegate to the spec-author agent.** The agent will:
   - Read all related source code
   - Fill in the Zachman framework grid
   - Design the proposed changes following established project patterns
   - Write the test plan
   - Log initial decisions

4. **Verify structural completeness (mechanical gate).** Run the Layer-1 linter against the freshly authored artifacts:

   ```bash
   .claude/skills/claire-spec/verify-spec.sh $ticket_id
   ```

   This is a deterministic structural check — the spec-side analog of the unfilled-probe grep that anchors `/claire-elicit`. It asserts required sections exist, every mandatory facet is evaluated, SCOUT decompositions and Gherkin scenarios are present, and no template placeholders were left unfilled. Each check traces to a line in the spec-author Quality Criteria.

   - If the linter exits **non-zero**, it prints the failing checks (with `file:line` for unfilled placeholders). Hand the failures back to the `claire-spec-author` agent to fix, then **re-run the linter. Loop until it exits zero.** Do not advance to step 5 while any check fails.
   - `WARN` lines (e.g. an acceptance-criterion count mismatch between problem.md and spec.md) do not block, but surface them to the user in step 7 so the human gate can judge whether a criterion was dropped.

   The linter verifies *structure*, not *soundness*. Whether a filled cell is correct, the edge cases are real, or the design is right remains the job of the human spec-approval gate (and any Layer-2 judgment review). Passing the linter is necessary, not sufficient.

   **Also run the fact checker (BTG-331), same loop-until-green discipline:**

   ```bash
   .claude/skills/claire-spec/verify-facts.sh $ticket_id
   ```

   This resolves every `Files Affected` row's `Add`/`Modify`/`Delete` and every backticked `path:N` citation against the base tree — a reviewer should never have to proofread a fact a machine can check. It applies only to a spec carrying the `**Gate 1 rulings:** required` sentinel in Open Questions: a spec without it gets `WARN` lines only and never blocks. If it exits non-zero, hand the `FAIL` lines back to `claire-spec-author` and loop until clean, same as `verify-spec.sh` above.

5. **Verify design completeness (judgment).** With the structural gate green, confirm:
   - Every acceptance criterion has a design element and test case
   - The Zachman grid is populated where relevant
   - Design Exploration is recorded: the winner, the axis over the named runner-up, a testable flip-condition, and the strongest objection -- or, where `design-options.md` was absent, the explicit not-performed marker
   - Risks are identified

6. **Update metadata:**
   - Set `status: spec-in-review` in metadata.yaml
   - **Record the spec stage effort** per `docs/agentic-sdlc/CLAIRE_ORG.md` "Actual Effort Accumulation":
     in the same metadata.yaml edit, append a `stage_effort` entry (`stage: spec`, `at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose
     `effort` is computed exactly as that directive prescribes: take your observed working time, then run
     `ci-templates/scripts/stage-effort.sh --stage spec --observed <minutes>` and record the duration it
     prints — it resolves the per-stage review multiplier (including any per-operator override), applies
     it, and rounds, so never restate a multiplier value or perform the arithmetic here (floor `15m` for
     any non-zero computed time; a resolved multiplier of `0` records a real
     `0m`). **Self-check before you write** the entry: the rounded `effort` MUST be either `0m` or a
     whole multiple of 15 minutes — if it is not, the multiply-then-round step was skipped or mis-executed, so
     surface a visible diagnostic naming the offending value, recompute, and continue; do **NOT** halt the
     operation. Add the increment to the accumulated `actual_effort`.
   - Run the repo's designated tracker sync skill (resolved from `CLAIRE_ORG.md` §9 (Tracker Binding)) for `{ticket-id}` to project the status change (and post the new `stage_effort` entry as its per-stage worklog)

7. **Report to user:**
   - Summary of the proposed design
   - Key decisions made
   - Open questions that need human input
   - Any `WARN`/`UNVERIFIABLE` lines from `verify-spec.sh` or `verify-facts.sh` (non-blocking, for the human gate's attention)
   - Suggestion to review and then create a spec MR

## Example

```
/claire-spec TT-6547
```


## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- During codebase discovery and fact verification (`verify-facts.sh` / `verify-spec.sh`), use `repo-scout` (`local-embed-cpu` + `local-moe-hybrid`) to gather existing type signatures and contracts without polluting the primary context window.
- Zachman grounding, SCOUT decomposition, design options, and Gherkin scenarios remain 100% owned by `gemini-4-argon-high`.
