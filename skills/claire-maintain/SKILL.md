---
name: claire-maintain
description: Evaluate an approved MR for project-level acceptance -- backwards compatibility, architectural integrity, mission alignment, and release readiness
argument-hint: "[MR number or branch name]"
arguments: [mr_ref]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Evaluate the change proposal `$mr_ref` (a GitLab MR, GitHub PR, or SourceHut patchset) for project-level acceptance. Use the `claire-maintainer` subagent for the analysis. The maintainer's primary inputs are forge-neutral: `git diff` and `specs/{ticket-id}/submission.md` (the canonical change-proposal record) -- no forge API access is required. See `docs/guides/submitting-changes.md`. This skill is interactive -- it presents a structured assessment and collects the human's accept/postpone/reject decision.

## Prerequisites

Before delegating to the maintainer agent, verify:

1. **Code review is complete.** Check that the code-reviewer has approved this change proposal. Look for a code-reviewer summary comment on the change proposal (the forge thread) or in `submission.md`'s `## Discussion`, or a review verdict in the spec artifacts. If code review has not been completed, stop and tell the user to run `/claire-review $mr_ref` first.

2. **Spec exists.** Check that `specs/{ticket-id}/spec.md` exists and that `metadata.yaml` shows a status of `spec-approved` or later. If no spec exists, warn the user but proceed with a general evaluation. **First resolve `metadata.yaml`'s `tier:` (case-insensitively, trimmed), and at Medium/High read `specs/{ticket-id}/decisions.md` for an entry escalating the tier after implementation began.** Per `docs/policies/change-tiers.md#escalation`, such a ticket may have promoted existing `decisions.md` entries in lieu of backfilling: where the escalating entry names each promoted entry and states why each predates and drove the implementation, the absent `spec.md` is **compliant by ruling** -- do not warn -- and those named entries are what this gate evaluates in place of `spec.md`. An **unqualified** promotion -- no named entries, or no stated reason each qualifies -- is itself a finding to put before the human.

## Steps

1. **Resolve the change-proposal reference:**
   - If `$mr_ref` is a number, it is the forge thread number (GitLab MR / GitHub PR / SourceHut patchset). Resolve it to a branch and ticket locally -- via the `merge_request:` field in `specs/{ticket-id}/metadata.yaml` or the `Thread URL` in `submission.md`'s `## Forge metadata`. If it cannot be resolved from the repo, ask the user for the branch name. (No forge API call is needed; the system of record is in the repo.)
   - If `$mr_ref` is a branch name, use it directly.
   - Extract the ticket ID from the branch name — the final `/`-delimited segment, per the branch-naming convention resolved from `CLAIRE_ORG.md#branch-strategy-binding` (`branch-naming-convention`; full narrative in the bound strategy doc under `docs/policies/branch-strategy/`)

2. **Verify prerequisites:**
   - Confirm code-reviewer approval
   - Confirm spec exists and is approved

3. **Get the diff** against the integration branch (resolve `<integration-branch>` from `CLAIRE_ORG.md#branch-strategy-binding`'s `integration-branch` field — ADR_CLAIRE-0020; never hardcode a branch name):
   ```bash
   git diff <integration-branch>...{branch-name}
   ```

4. **Delegate to the maintainer agent.** The agent will evaluate across eight dimensions:
   - Backwards compatibility and API stability
   - Architectural integrity against ADRs and established patterns
   - Project goal alignment (mission fitness vs. scope creep)
   - Maintenance cost and complexity budget
   - Security impact and threat surface changes
   - Release readiness (changelog, deprecation, migration docs)
   - Dependency and supply chain health
   - Documentation currency (flow docs and SYSTEM_OVERVIEW.md still accurate)

5. **Present the Maintainer Assessment** to the user with the structured report and recommendation.

6. **Collect the human's decision:**
   - **Accept** -- approve for merge
   - **Postpone** -- defer with stated reason
   - **Reject** -- do not merge with guidance for the author

6b. **Disposition the owed follow-ups.** Runs on **every** verdict path -- Accept, Postpone and Reject alike -- exactly as step 7's effort recording does: a rejected proposal's non-blocking findings are still owed. A `new` candidate's draft path is `specs/drafts/{ticket-id}-maintain-<UTC>-<N>.md` -- a single whitespace-free token rooted at `specs/drafts/` (created if absent), where `<UTC>` is `date -u +%Y%m%dT%H%M%SZ` read **once per gate run** and shared by all that run's candidates (DEC-014), and `<N>` is the candidate's ordinal in sub-step a's enumeration.

   a. **Enumerate.** Classify per `docs/policies/finding-classes.md`: a Non-Blocking Observation with **no disposition yet** and no valid class token halts this step before enumeration -- an entry that already carries a disposition in `## Resolution`'s `Follow-ups created` is a legacy record and is exempt from this halt, classed or not. Emit `finding.class.unlabelled` naming the entry (gate, authoring role, text) and request a label from the human; an empty or unrecognized answer re-prompts exactly once, and a second miss records it Deferred naming `finding.class.unlabelled`, never classed by default. A valid supplied label is recorded per `docs/policies/finding-classes.md` Routing step 1 (entry format, operator-identity resolution, and downstream read semantics), naming this gate (`/claire-maintain`). With no confirmation channel at all, record it Deferred naming that cause. Once every entry is classed, from this phase's own findings (the assessment's `### Non-Blocking Observations`) and from `submission.md`'s `## Discussion`, list every candidate -- entries classed `out-of-scope-defect` -- that carries **no** disposition yet in `## Resolution`'s `Follow-ups created`. A candidate that already carries one is **never re-presented** -- the recorded line is the idempotency key. `nit`, `hygiene`, `observation` and `adr-owed` entries are never candidates; they stay recorded in `## Discussion` unchanged, and `adr-owed` is counted in the tally but disposed of only at `/claire-archive` step 1b. **Zero candidates** => record the none-owed disposition, with the per-class tally clause (`docs/policies/finding-classes.md`, Routing step 3), and go to step 7. If `submission.md` **is missing**, report the absent record and **halt this step**: a filed id would have nowhere to record it, which recreates the unpaired record this step exists to prevent. Allocate nothing.

   b. **Check the capability floor.** This step needs (i) a host runtime that can compose one command from another and (ii) a channel to collect the human's confirmation. **If either is unavailable**, take the degraded path: write the candidate's description to its draft path (declared above) and **keep** it there -- no callee runs on this path, so nothing is deleted -- then file **nothing**, allocate **nothing**, and **never simulate the callee**. Emit the named notice for the cause that fired -- `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable` -- record in `## Discussion`, per candidate, its one-line description **and the exact `/claire-triage --file-only <draft-path>` command**, which runs as written in this worktree (a human running it elsewhere writes the description to that path first), and set the field to the **deferred disposition naming** that cause. Notice and record happen together or not at all: a notice beside a clean field reads as no finding. With zero candidates there is **nothing to defer**, so record the none-owed disposition and emit no notice. When both (i) and (ii) are available this path is not taken -- it is **never a route around** the confirmation in the present-and-confirm step.

   c. **Present and confirm.** Before presenting, give each candidate its prior-work verdict (`docs/policies/finding-classes.md`, Routing step 4): search `specs/` and `archive/` for matching prior work and present exactly one of `new`, `duplicate of <id>`, or `fold into <id>`, citing the matched id; an archived-only match is cited as related context and is presented as `new`. A candidate with no verdict is never shown. If the search cannot run, halt and emit `followup.dedupe.check_unavailable` naming the unreadable root -- never present a candidate as `new` by default. Show the verdicted candidates as a numbered list, one line each, and ask the human which to file. The agent **proposes**; the human **decides**. Nothing is filed without an explicit per-candidate confirmation. An empty or unrecognized answer **re-prompts exactly once**; if the second answer is also empty or unrecognized, record the remaining candidates as **deferred with that reason** -- never as an implicit decline and never as an implicit file.

   d. **File.** For each confirmed `new` candidate, invoke `/claire-triage --file-only <draft-path>` in this same operation, having FIRST written the candidate's description to `<draft-path>` verbatim, replacing any file already there -- never invoke before that write lands. **Never** call the id allocator directly and **never** hand-write a ticket's artifacts: that path's own reserve-and-write pairing is what makes the filed id auditable, and a bare reservation with nothing paired to it is the exact defect this step exists to avoid. On a **zero exit**, delete that draft (the exact path just written, nothing else). On a **non-zero exit**, halt, report the callee's error **verbatim**, keep that draft as evidence, and record the remaining candidates as deferred with that reason. A delete that fails is reported as `followup.filing.draft_cleanup_failed` and never undoes the filing. **Never fall back to scanning** the tree for a free id and never issue a bare reservation. An id already filed when a later one fails **stays filed and stays recorded** -- never delete a filed trail to undo a partial run. For each confirmed `duplicate of <id>`, file nothing and record it. For each confirmed `fold into <id>`: re-check the target's fold eligibility (open, at `draft` or `triaged`, per `docs/policies/finding-classes.md` Routing step 4) at write time -- a target that has moved on is re-presented as `new` with the target cited as related; otherwise append one dated line naming this ticket and gate to the target's `problem.md` `## Notes`, and only once that write lands record the fold, then run the tracker sync for `<id>` per Routing step 5 -- a failed projection is reported, never silently skipped. A failed target write is recorded Deferred with that failure as the reason -- never recorded as Folded without the write landing. Declining a presented `fold into <id>` or `duplicate of <id>` writes nothing to the target.

   e. **Record.** Write every candidate's disposition into `## Resolution`'s `Follow-ups created`, in one of the six forms the template defines (filed / duplicate / folded / none owed / declined / deferred), plus the per-class tally clause whenever at least one non-blocking finding has been logged. A **declined candidate is recorded with the human's stated reason**, and **no id is allocated for** it -- a decline is a disposition, not an omission. The field is never left empty and never carries a bare none-shaped token.

7. **Execute post-decision actions** based on the human's choice:
   - **Record the maintainer stage effort (all decisions).** The maintainer evaluation consumed effort
     regardless of the verdict, so on every path — Accept, Postpone, or Reject — record it per
     `docs/agentic-sdlc/CLAIRE_ORG.md` "Actual Effort Accumulation": append a `stage_effort` entry to
     `specs/{ticket-id}/metadata.yaml` (`stage: maintainer`, `at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose `effort` is computed exactly
     as that directive prescribes: take your observed working time, then run
     `ci-templates/scripts/stage-effort.sh --stage maintainer --observed <minutes>` and record the
     duration it prints — it resolves the per-stage review multiplier (including any per-operator
     override), applies it, and rounds, so never restate a multiplier value or perform the arithmetic
     here (floor `15m` for any non-zero computed time; a resolved multiplier of `0` records a real `0m`). **Self-check before you
     write** the entry: the rounded `effort` MUST be either `0m` or a whole multiple of 15 minutes — if it is
     not, the multiply-then-round step was skipped or mis-executed, so surface a visible diagnostic naming
     the offending value, recompute, and continue; do **NOT** halt the operation. Add the increment to the
     accumulated `actual_effort`, in the same metadata edit as the decision fields below.
   - Accept: update metadata with `maintainer_approved_at` set to the **exact** current wall-clock UTC time from `date -u +%Y-%m-%dT%H:%M:%SZ` (second precision; never rounded, midnight, or date-only), commit any drafted documentation
   - Postpone: log reason in decisions.md, update metadata
   - Reject: log reason in decisions.md, update metadata
   - **Then sync.** After writing metadata, run the repo's designated tracker sync skill (resolved from `CLAIRE_ORG.md` §9 (Tracker Binding)) for `{ticket-id}` to project the change and post the new
     `stage_effort` entry as its per-stage worklog.

8. **Report outcome** to the user with a summary of actions taken.

## Example

```
/claire-maintain 142
/claire-maintain feature/26.5.TT/TT-6547
```
