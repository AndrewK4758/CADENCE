---
name: claire-review
description: Review an MR against its tier contract -- the approved spec at Medium/High, problem.md's acceptance criteria at Low -- checking acceptance criteria, test coverage, security, and code quality
argument-hint: "[MR number or branch name]"
arguments: [mr_ref]
allowed-tools: Read Glob Grep Bash Write Skill
---

## Task

Review the change proposal `$mr_ref` (a GitLab MR, GitHub PR, or SourceHut patchset) against its tier contract -- the approved specification at Medium/High tier, or `problem.md`'s acceptance criteria at Low tier (the tier is resolved from `metadata.yaml` in step 2). Use the `claire-reviewer` subagent for the analysis. The reviewer's primary inputs are forge-neutral: `git diff` and `specs/{ticket-id}/submission.md` (the canonical change-proposal record) -- no forge API access is required. See `docs/guides/submitting-changes.md`.

## Steps

1. **Resolve the change-proposal reference:**
   - If `$mr_ref` is a number, it is the forge thread number (GitLab MR / GitHub PR / SourceHut patchset). Resolve it to a branch and ticket locally -- via the `merge_request:` field in `specs/{ticket-id}/metadata.yaml` or the `Thread URL` in `submission.md`'s `## Forge metadata`. If it cannot be resolved from the repo, ask the user for the branch name. (No forge API call is needed; the system of record is in the repo.)
   - If `$mr_ref` is a branch name, use it directly.
   - Extract the ticket ID from the branch name — the final `/`-delimited segment, per the branch-naming convention resolved from `CLAIRE_ORG.md#branch-strategy-binding` (`branch-naming-convention`; full narrative in the bound strategy doc under `docs/policies/branch-strategy/`)

2. **Read the tier, then verify the review contract:**
   - Read `specs/{ticket-id}/metadata.yaml` and resolve `tier:` (case-insensitively, trimmed) BEFORE checking for `spec.md`. The tier selects the review contract.
   - **tier: Low** -> the review contract is `problem.md`'s Acceptance Criteria checklist (plus `decisions.md` if present). Do NOT check for `spec.md`/`test-plan.md` and do NOT flag their absence -- at Low tier they are not produced by policy (`docs/policies/change-tiers.md`), so their absence is compliant, not a process violation.
   - **tier: Medium or tier: High** -> Check `specs/{ticket-id}/spec.md` exists and is approved. If no spec exists, note this as a process violation but proceed with general review. **Before flagging that absence, read `specs/{ticket-id}/decisions.md` for an entry escalating the tier after implementation began.** Per `docs/policies/change-tiers.md#escalation` such a ticket may take the promotion path instead of backfilling: where the escalating entry names each promoted entry and states why each predates and drove the implementation, the missing `spec.md` is **compliant, not a process violation**, and those named entries are the contract you review conformance against. An **unqualified** promotion -- no named entries, or no stated reason each qualifies -- is a blocking finding.
   - **tier absent, empty, or unrecognized** -> do NOT assume Low. Apply the Medium/High check above and note in the review that the tier could not be resolved from `metadata.yaml`. Never treat a missing or unrecognized tier as Low-tier-compliant.

3. **Get the diff** against the integration branch (resolve `<integration-branch>` from `CLAIRE_ORG.md#branch-strategy-binding`'s `integration-branch` field — ADR_CLAIRE-0020; never hardcode a branch name):
   ```bash
   git diff <integration-branch>...{branch-name}
   ```

4. **Delegate to the code-reviewer agent.** The agent will:
   - Check each acceptance criterion against the implementation
   - Verify test coverage against the test plan
   - Check architecture compliance (Clean Architecture layers, service patterns)
   - Check code quality (naming, error handling, performance)
   - Check security (authorization, input validation, data exposure)
   - Check migration safety if applicable
   - **Generative principle for the adversarial lens (AGENT.md §10):** every "this is safe because X" is a claim to verify against the real source of X (real seed numbers, real engine docs, real sibling writers, real prod config, the canonical story file) — never inherit it; and for each finding name whether the failure lives in the diff, in code it consumes, in code that consumes it, or in unchanged code whose contract the diff silently changed. The bullets below are recurring instances of this principle.
   - Apply the **adversarial lens** (AGENT.md §10): after confirming spec conformance, probe how the change can fail *silently* — fallbacks/stubs that mask real defects, broad `except` clauses, assumptions about what consumed code (incl. dependencies merged after this branch) actually does, and test/fake blind spots. Approved decisions are not exempt; silent/partial-failure paths are blocking. Locate every finding by its position relative to the diff — (1) in the diff, (2) in code it consumes, (3) in code that consumes it, (4) in unchanged code whose contract the diff silently changed (the one diff-review misses by construction) — and scale effort to the change: a trivial diff with no shared-state coupling does not warrant a four-position enumeration, so simple changes stay cheap. **Do not accept a spec's "out of scope / known limitation / can't happen at this scale" label at face value** — verify the claim against real numbers (seed-data volume, actual default param values, true input sizes) and recompute the bound; a limitation whose justification is false is a present, blocking bug, not a forward hazard.
   - When the diff configures a third-party engine declaratively (map styles, ORM/query builders, CSS, IaC, GraphQL), the reviewer must consult the **real engine contract** (vendored source / official docs), not just the diff and the fakes — declarative *omissions* evaluated against engine defaults are a primary failure class here.
   - When the diff routes a new field/atom/column into a **shared** surface that enforces a consistency or mutual-exclusivity invariant (a combined/derived query, an encoder/serializer, a reducer, an "exactly one of" constraint), the reviewer must enumerate **every** writer of every field in that invariant — including pre-existing, unchanged sibling writers outside the diff — and verify each still maintains it. A sibling setter that was correct before the coupling but now leaves the invariant broken (e.g. sets one side of a mutually-exclusive pair without clearing the other) is a blocking defect invisible to a diff-only read.
   - When a transition (mount/hydrate/back-forward/reset/object-spread) carries over part of prior state, verify each carried field is still consistent with the fields the transition overwrote — a stale derived field (e.g. a map-derived bbox spread forward while center/zoom are reset) is a blocking defect; and verify load-bearing tests use the same framework config prod ships (`createBrowserRouter`, the real container), not a test-only wiring that masks the bug.

   **Re-review after integration.** If the branch has been rebased onto (or merged with) dependencies that were not present at the last review — e.g. another ticket's branch landed on the integration branch — run `/claire-review` again. The earlier review only saw a single-branch diff; integration bugs (a now-present collaborator that commits, blocks, or raises) are invisible until the dependency is actually on the branch.

5. **Format the review** as structured comments on the change proposal and record it:
   - Summary comment with verdict and AC checklist
   - Inline comments on specific lines for issues and suggestions
   - **Always** mirror the review (verdict, AC checklist, and discussion) into `submission.md`'s `## Discussion` section so the archive carries the record. This write is the system of record and must succeed regardless of forge availability.

   Then post to the forge **only when an MR exists**:

   - **MR-exists guard.** Resolve an MR URL from the `merge_request:` field in `specs/{ticket-id}/metadata.yaml` **or** the `Thread URL` in `submission.md`'s `## Forge metadata` section. If an MR URL is resolvable, the review outcome **MUST** be posted to that forge thread (steps below). If **no** MR URL is resolvable (e.g. a branch review before the MR is created), recording in `submission.md` is sufficient — do **not** attempt a forge post, and do **not** raise an error.

   - **Forge-posting step.** When an MR URL is resolvable, post the review using the mechanism for the forge type recorded in `submission.md`'s `## Forge metadata` (`Forge:` field). Write the mirrored review content to a file first (e.g. the same text appended to `## Discussion`), then:
     - **GitHub:** `gh pr comment <pr-number-or-url> --body "$(cat <review-output>)"`
     - **GitLab:** `glab mr note <mr-iid> --message "$(cat <review-output>)"`
     - **SourceHut:** there is no CLI equivalent — the review is already recorded in `submission.md`'s `## Discussion`; add a note there that a manual email reply to the `lists.sr.ht` patchset thread is needed to post the review upstream.

   - **Failure handling.** If the forge CLI call exits non-zero, **report the failure to the user** with the CLI's error output, and note that the review is recorded in `submission.md`. Do **not** silently continue as though the forge post succeeded — a failed post is a visible outcome, not a swallowed one.

6. **Disposition the owed follow-ups.** Runs on **every** verdict -- Approve, Request Changes and Needs Discussion alike: a rejected proposal's non-blocking findings are still owed. **Tier-independent**: this step adds no tier branch, so an unresolved tier cannot route it to a branch chosen by accident. At **Low** tier this is the only human gate the ticket will ever reach (`docs/policies/change-tiers.md` gives Low no maintainer gate), which is why the filing point lives here and not only downstream. A `new` candidate's draft path is `specs/drafts/{ticket-id}-review-<UTC>-<N>.md` -- a single whitespace-free token rooted at `specs/drafts/` (created if absent), where `<UTC>` is `date -u +%Y%m%dT%H%M%SZ` read **once per gate run** and shared by all that run's candidates (DEC-014), and `<N>` is the candidate's ordinal in sub-step a's enumeration.

   a. **Enumerate.** Classify per `docs/policies/finding-classes.md`: a Non-Blocking entry with **no disposition yet** and no valid class token halts this step before enumeration -- an entry that already carries a disposition in `## Resolution`'s `Follow-ups created` is a legacy record and is exempt from this halt, classed or not. Emit `finding.class.unlabelled` naming the entry (gate, authoring role, text) and request a label from the human; an empty or unrecognized answer re-prompts exactly once, and a second miss records it Deferred naming `finding.class.unlabelled`, never classed by default. A valid supplied label is recorded per `docs/policies/finding-classes.md` Routing step 1 (entry format, operator-identity resolution, and downstream read semantics), naming this gate (`/claire-review`). With no confirmation channel at all, record it Deferred naming that cause. Once every entry is classed, from the reviewer's `#### Non-Blocking` findings and from `submission.md`'s `## Discussion`, list every candidate -- entries classed `out-of-scope-defect` -- that carries **no** disposition yet in `## Resolution`'s `Follow-ups created`. A candidate that already carries one is **never re-presented**. `nit`, `hygiene`, `observation` and `adr-owed` entries are never candidates; they stay recorded in `## Discussion` unchanged. **Zero candidates** => record the none-owed disposition, with the per-class tally clause (`docs/policies/finding-classes.md`, Routing step 3), and go to step 7.

   b. **Check the capability floor.** This step needs (i) a host runtime that can compose one command from another and (ii) a channel to collect the human's confirmation. **If either is unavailable**, take the degraded path: write the candidate's description to its draft path (declared above) and **keep** it there -- no callee runs on this path, so nothing is deleted -- then file **nothing**, allocate **nothing**, and **never simulate the callee**. Emit the named notice for the cause that fired -- `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable` -- record in `## Discussion`, per candidate, its one-line description **and the exact `/claire-triage --file-only <draft-path>` command**, which runs as written in this worktree (a human running it elsewhere writes the description to that path first), and set the field to the **deferred disposition naming** that cause. Notice and record happen together or not at all: a notice beside a clean field reads as no finding. With zero candidates there is **nothing to defer**, so record the none-owed disposition and emit no notice. When both (i) and (ii) are available this path is not taken -- it is **never a route around** the confirmation in the present-and-confirm step.

   c. **Present and confirm.** Before presenting, give each candidate its prior-work verdict (`docs/policies/finding-classes.md`, Routing step 4): search `specs/` and `archive/` for matching prior work and present exactly one of `new`, `duplicate of <id>`, or `fold into <id>`, citing the matched id; a candidate with no verdict is never shown. If the search cannot run, halt and emit `followup.dedupe.check_unavailable` naming the unreadable root -- never present a candidate as `new` by default. Show the verdicted candidates as a numbered list, one line each, and ask the human reviewer which to file. The agent **proposes**; the human **decides**. Nothing is filed without an explicit per-candidate confirmation. The `claire-reviewer` agent itself never files -- it holds neither `write` nor `command-composition`; it **labels** candidates and this step disposes of them.

   d. **File.** For each confirmed `new` candidate, invoke `/claire-triage --file-only <draft-path>` in this same operation, having FIRST written the candidate's description to `<draft-path>` verbatim, replacing any file already there -- never invoke before that write lands. **Never** call the id allocator directly and **never** hand-write a ticket's artifacts: that path's own reserve-and-write pairing is what makes the filed id auditable. On a **zero exit**, delete that draft (the exact path just written, nothing else). On a **non-zero exit**, halt, report the callee's error **verbatim**, keep that draft as evidence, and record the remaining candidates as deferred with that reason. A delete that fails is reported as `followup.filing.draft_cleanup_failed` and never undoes the filing. **Never fall back to scanning** the tree for a free id and never issue a bare reservation. An id already filed when a later one fails **stays filed and stays recorded** -- never delete a filed trail to undo a partial run. For each confirmed `duplicate of <id>`, file nothing. For each confirmed `fold into <id>`: re-check the target's fold eligibility (open, at `draft` or `triaged`, per `docs/policies/finding-classes.md` Routing step 4) at write time -- if it has moved on, re-present the candidate as `new` with the target cited as related; otherwise append one dated line naming this ticket and gate to the target's `problem.md` `## Notes`, and only once that write lands record the fold, then run the tracker sync for `<id>` per Routing step 5 -- a failed projection is reported, never silently skipped. If the target write fails, record the candidate Deferred with that failure as the reason -- never record a fold whose target write did not land.

   e. **Record.** Write every candidate's disposition into `## Resolution`'s `Follow-ups created`, in one of the six forms the template defines (filed / duplicate / folded / none owed / declined / deferred), plus the per-class tally clause whenever at least one non-blocking finding has been logged. The field is never left empty and never carries a bare none-shaped token.

7. **Record the code-review stage effort.** Per `docs/agentic-sdlc/CLAIRE_ORG.md` "Actual Effort
   Accumulation": append a `stage_effort` entry to `specs/{ticket-id}/metadata.yaml` (`stage: code-review`,
   `at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose `effort` is computed exactly as that directive prescribes: take your observed working
   time, then run `ci-templates/scripts/stage-effort.sh --stage code-review --observed <minutes>` and
   record the duration it prints — it resolves the per-stage review multiplier (including any
   per-operator override), applies it, and rounds, so never restate a multiplier value or perform the
   arithmetic here (floor `15m` for any non-zero computed
   time; a resolved multiplier of `0` records a real `0m`). **Self-check before you write** the entry: the rounded `effort` MUST be either `0m` or a
   whole multiple of 15 minutes — if it is not, the multiply-then-round step was skipped or mis-executed, so
   surface a visible diagnostic naming the offending value, recompute, and continue; do **NOT** halt the
   operation. Add the increment to the
   accumulated `actual_effort`. The review stage makes exactly three repo writes and no others — step 5's
   `submission.md` review mirror, step 6's `Follow-ups created` disposition, and this `metadata.yaml`
   bookkeeping — plus a conditional fourth write only when step 6d confirms a `fold into <id>`: the
   dated line appended to that target ticket's own `problem.md` `## Notes` (which also triggers the
   target's own tracker sync per `docs/policies/finding-classes.md` Routing step 5) — and a
   conditional fifth write only when step 6a's unlabelled-entry halt collects a valid label: the
   label note `docs/policies/finding-classes.md` Routing step 1 defines, appended beside the entry
   in `submission.md`'s `## Discussion` -- and a conditional sixth write only when step 6 writes a
   draft for a `new` candidate: the gitignored scratch file at its draft path under `specs/drafts/`,
   which is never committed and is deleted again once that candidate's filing exits 0 (kept after a
   non-zero exit, and kept on the degraded path). The
   `claire-reviewer` agent itself stays read-only; the review verdict is not a status change. Then run the
   repo's designated tracker sync skill (resolved from `CLAIRE_ORG.md` §9 (Tracker Binding)) for
   `{ticket-id}` to project it (posting the new `stage_effort` entry as its per-stage worklog).

8. **Report to user:**
   - Verdict (Approve / Request Changes / Needs Discussion)
   - Blocking issues count
   - Suggestion count
   - Overall assessment

## Example

```
/claire-review 142
/claire-review impl/feature/ORD-40
```


## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Use `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` or `local-12b-gpu`) to run an initial mechanical checklist pass over the diff (checking <400-line ceiling, comment discipline, SCOUT observability seams, and security patterns).
- `gemini-4-argon-high` independently verifies all findings against the approved tier contract (`spec.md` or `problem.md`) before recording the review verdict.
