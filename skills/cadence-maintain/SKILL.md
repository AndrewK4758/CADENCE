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

0. **Mandatory Automatic Mechanical Pre-Scan (`offload_deep_review`).** Once the branch reference and integration branch diff (`git diff <integration-branch>...{branch-name}`) are resolved in Steps 1–3, automatically invoke `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:9380`) on the diff **before** delegating to `cadence-maintainer`. The local coprocessor performs an advisory pre-scan verifying:
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

4. **Delegate to `cadence-maintainer`.** Pass the diff, the spec/decision artifacts, and Step 0's `offload_deep_review` pre-scan so the subagent evaluates all eight maintainer dimensions:
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

6b. **Disposition owed follow-up findings.** Execute this step across **all three** verdict branches — `Accept`, `Postpone`, and `Reject` alike — matching Step 7's unconditional effort logging, because out-of-scope defects uncovered on a postponed or rejected proposal still require disposition. Format each `new` candidate's scratch file path as `specs/drafts/{ticket-id}-maintain-<UTC>-<N>.md` — a single whitespace-free path inside `specs/drafts/` (creating the directory if absent), where `<UTC>` is read **once per maintainer gate run** via `date -u +%Y%m%dT%H%M%SZ` and shared across all candidates in this run (DEC-014), and `<N>` is the candidate's 1-based ordinal from sub-step `a`.

   a. **Enumerate and verify finding classes.** Validate every non-blocking observation against `docs/policies/finding-classes.md`: any Non-Blocking Observation lacking both an existing disposition in `## Resolution` -> `Follow-ups created` and a valid class token **halts enumeration immediately** (entries already carrying a disposition in `Follow-ups created` are historical records and exempt from this halt). Emit `finding.class.unlabelled` citing the gate (`/cadence-maintain`), authoring role, and observation text, and ask the human maintainer for a valid class label; re-prompt at most once on an empty or unrecognized reply, and on a second invalid reply record the item as `Deferred` citing `finding.class.unlabelled` (never assigning a default class). When the human supplies a valid class token, record the classification note beside the entry in `submission.md`'s `## Discussion` per `docs/policies/finding-classes.md` Routing step 1 (naming gate `/cadence-maintain`). If no interactive confirmation channel exists, record the item as `Deferred` citing that cause. Once every item carries a valid class (or deferral), gather all `out-of-scope-defect` items from the maintainer assessment's `### Non-Blocking Observations` and from `submission.md`'s `## Discussion` that do **not** yet have a disposition in `## Resolution` -> `Follow-ups created` (the recorded disposition line serves as the idempotency key, so already-dispositioned items are **never re-presented**). Entries classed `nit`, `hygiene`, `observation`, or `adr-owed` are never filing candidates here; they remain in `## Discussion` unchanged, with `adr-owed` counted in the per-class tally and dispositioned later at `/cadence-archive` step 1b. **When zero candidates remain**, record the none-owed disposition with the per-class tally clause (`docs/policies/finding-classes.md`, Routing step 3) and proceed to Step 7. If `submission.md` **is absent**, report the missing change-proposal record and **halt Step 6b without allocating any id**: filing a ticket without `submission.md` to record its disposition would create an unpaired trail.

   b. **Verify runtime capability floor.** Filing requires both (i) command-composition support to invoke `/cadence-triage --file-only` and (ii) an interactive channel to collect human confirmation. **When either capability is unavailable**, take the degraded deferral path: write each candidate's description verbatim to its `<draft-path>` (`specs/drafts/{ticket-id}-maintain-<UTC>-<N>.md`) and **retain that file on disk** — invoke **no** callee, allocate **no** id, and **never simulate `/cadence-triage`**. Emit the corresponding diagnostic token — `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable` — log each candidate's one-line summary and exact `/cadence-triage --file-only <draft-path>` command inside `## Discussion`, and set `Follow-ups created` to the **deferred disposition naming** that cause. Notice emission and deferral recording must occur together. When zero candidates exist, nothing is deferred and no notice is emitted. When both capabilities (i) and (ii) are available, never take this branch.

   c. **Prior-work deduplication, presentation, and human confirmation.** Before presenting candidates, assign each candidate its prior-work verdict (`docs/policies/finding-classes.md`, Routing step 4) by searching `specs/` and `archive/` (using `local_semantic_embed` / `local-moe-hybrid` plus targeted reads) and tagging each item as `new`, `duplicate of <id>`, or `fold into <id>` (citing `<id>`; an archived-only match is cited as related context and tagged `new`). Never present a candidate lacking a verdict. If `specs/` or `archive/` is unreadable, halt and emit `followup.dedupe.check_unavailable` naming the unreadable root — never default a candidate to `new`. Display the numbered list of verdicted candidates (one line per item) and ask the human maintainer which items to file. The agent **proposes**; the human **decides** — nothing is filed without explicit per-candidate confirmation. On an empty or unrecognized reply, **re-prompt once**; if the second reply is also empty or unrecognized, record the remaining candidates as **deferred with that reason** — never treating an invalid reply as an implicit decline or implicit file.

   d. **Execute confirmed filings and folds.** For each confirmed `new` candidate, first write its verbatim description to `<draft-path>` (replacing any prior file at that path), and only after that write completes invoke `/cadence-triage --file-only <draft-path>` within the same operation. **Never** call the id allocator directly and **never** hand-author `specs/<id>/` files, as `--file-only` enforces atomic reserve-and-write pairing. On a **zero exit**, delete `<draft-path>` (and nothing else); if deleting the scratch file fails, emit `followup.filing.draft_cleanup_failed` without undoing the filing. On a **non-zero exit**, halt immediately, report the callee's error **verbatim**, preserve `<draft-path>` on disk as diagnostic evidence, and record remaining candidates as `Deferred` citing that error. **Never fall back to directory scanning** for a free id. Any candidate already filed before a later failure **remains filed and recorded** — never delete a filed `specs/<id>/` directory. For each confirmed `duplicate of <id>`, allocate nothing and record the duplicate disposition. For each confirmed `fold into <id>`, re-verify at write time that target `<id>` remains open at `draft` or `triaged` (`docs/policies/finding-classes.md`, Routing step 4): if `<id>` has progressed past `triaged`, re-present the candidate as `new` citing `<id>` as related context; otherwise append one dated line naming this ticket and `/cadence-maintain` to `specs/<id>/problem.md` under `## Notes`, record the `folded` disposition only after that write succeeds, and run the bound tracker sync for `<id>` per Routing step 5 (reporting any sync failure; if writing to the target's `problem.md` fails, record the candidate as `Deferred` rather than `Folded`). Declining a `fold into <id>` or `duplicate of <id>` candidate leaves the target ticket untouched.

   e. **Record final dispositions.** Write every candidate's disposition into `submission.md`'s `## Resolution` -> `Follow-ups created` using one of the six canonical template forms (`filed`, `duplicate`, `folded`, `none owed`, `declined`, `deferred`), plus the per-class tally clause whenever >=1 non-blocking observation was logged. Record any **declined candidate with the human maintainer's stated reason** and allocate **zero ids** for it. Never leave `Follow-ups created` empty or populated with a bare `none` token.

7. **Execute post-decision updates** corresponding to the maintainer's ruling:
   - **Record the maintainer stage effort (across all decisions).** Because maintainer evaluation consumes effort regardless of whether the proposal is accepted, postponed, or rejected, always record it per `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation": append a `stage_effort` item to `specs/{ticket-id}/metadata.yaml` (`stage: maintainer`, `at` = exact UTC completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded, midnight, or date-only) whose `effort` comes directly from running `ci-templates/scripts/stage-effort.sh --stage maintainer --observed <minutes>` — resolving the stage review multiplier (including any operator override), multiplying, and rounding up to a 15-minute multiple (minimum `15m` for non-zero work; `0m` when the multiplier is `0`). **Verify before saving:** the rounded `effort` string MUST equal `0m` or an exact multiple of 15 minutes; if not, emit a visible diagnostic naming the invalid value, recompute, and continue without halting. Add the increment to `actual_effort` in the same `metadata.yaml` edit as the decision attributes below.
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
- Step 0 automatically invokes `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:9380`) to pre-scan the branch diff for `<400`-line ceiling compliance, comment discipline, and CHORD observability seams before delegating to `cadence-maintainer`.
- Step 6b.c uses `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) / `local-moe-hybrid` when checking `specs/` and `archive/` for prior-work deduplication.
- Maintainer evaluation across the eight governance dimensions and human decision capture remain 100% owned by `gemini-4-argon-high`.
