---
name: cadence-review
description: Audit a change proposal (MR/PR/patchset) against its tier contract -- the approved spec at Medium/High, problem.md's acceptance criteria at Low -- verifying behavioral conformance, test coverage, CHORD seams, security boundary posture, and Engineering Pillars
argument-hint: "[MR number or branch name]"
arguments: [mr_ref]
allowed-tools: Read Glob Grep Bash Write Skill
---

## Task

Audit the change proposal `$mr_ref` (whether a GitLab MR, GitHub PR, or SourceHut patchset) against its governing tier contract -- the approved specification (`spec.md` + `test-plan.md`) at Medium/High tier, or `problem.md`'s Acceptance Criteria checklist at Low tier (resolving `tier` from `metadata.yaml` in Step 2). Run the mandatory Step 0 mechanical pre-scan via `offload_deep_review`, run `verify-facts.sh --trace` and `security-trigger.sh`, and delegate deep adversarial review to `cadence-reviewer` (plus `cadence-security-auditor` whenever `security-trigger.sh` returns `decision=TRIGGER`). Review inputs are completely forge-neutral: `git diff` and `specs/{ticket-id}/submission.md` (the repository's canonical change-proposal record), requiring no forge API connectivity to perform the review itself (`docs/guides/submitting-changes.md`).

## Steps

0. **Mandatory Automatic Mechanical Pre-Scan (`offload_deep_review`).** Once the target branch and integration branch diff are resolved in Steps 1–3, automatically invoke `offload_deep_review(prompt=..., diff_range="<integration-branch>...{branch-name}", cwd="<repo-root>", context_files=[...])` **before** delegating to `cadence-reviewer`. The coprocessor inspects the actual unified diff hunks plus deterministic metrics (`<400`-line ceiling, comment discipline, CHORD seams, security boundary patterns). Pass this report to `cadence-reviewer` (`Deep-reasoning` tier, `xhigh` effort) in Step 4; `/cadence-review` (not the read-only subagent) persists the final review report into `specs/{ticket-id}/submission.md` in Step 5.

1. **Resolve the change-proposal reference:**
   - When `$mr_ref` is an integer, treat it as the forge thread identifier (GitLab MR IID, GitHub PR number, or SourceHut patchset ID). Map it locally to its branch and ticket ID by inspecting `merge_request:` in `specs/{ticket-id}/metadata.yaml` or `Thread URL` under `## Forge metadata` in `specs/{ticket-id}/submission.md`. If local metadata cannot resolve the number, prompt the operator for the branch name (no forge network call is required to resolve the local system of record).
   - When `$mr_ref` is a branch name, use that branch name directly.
   - Parse `{ticket-id}` from the final `/`-delimited segment of the branch name, following the `branch-naming-convention` configured in `CADENCE_ORG.md#branch-strategy-binding` (with full strategy narrative under `docs/policies/branch-strategy/`).

2. **Resolve the ticket's tier and establish the review contract:**
   - Inspect `specs/{ticket-id}/metadata.yaml` and normalize `tier:` (case-insensitively, stripped of surrounding whitespace) **PRIOR to** checking whether `spec.md` exists. The normalized tier determines which artifacts form the review contract.
   - **tier: Low** -> the governing review contract is `problem.md`'s Acceptance Criteria checklist (together with `decisions.md` when present). Never require `spec.md` or `test-plan.md` at Low tier, and never flag their absence as a defect — `docs/policies/change-tiers.md` omits both files at Low tier by design.
   - **tier: Medium or tier: High** -> verify that `specs/{ticket-id}/spec.md` exists and carries approved status. When `spec.md` is absent, flag the missing spec as a process violation while still performing a full code review — **except** when `specs/{ticket-id}/decisions.md` records a mid-implementation tier escalation (`docs/policies/change-tiers.md#escalation`). Before raising a missing-spec violation, inspect `decisions.md` for an escalation entry: if that entry explicitly lists each promoted decision record and explains why each predated and governed the implementation, the absence of `spec.md` is **compliant by escalation ruling** rather than a violation, and those named `decisions.md` entries serve as the review contract. Conversely, an **unqualified** escalation (failing to name the promoted entries or failing to state why each qualifies) is a blocking review finding.
   - **tier absent, empty, or unrecognized** -> NEVER default to Low. Enforce the Medium/High verification rules above and explicitly note in the review report that `tier:` in `metadata.yaml` could not be resolved. Never treat an empty or invalid tier as Low-tier-compliant.

3. **Run diff pre-scan, mechanical traceability check, security trigger, and compute the branch diff** against the repository's integration branch (resolving `<integration-branch>` dynamically from `CADENCE_ORG.md#branch-strategy-binding` per `ADR_CADENCE-0020`; never hardcode a branch name):
   - Call `offload_deep_review` with `diff_range="<integration-branch>...{branch-name}"`, `cwd="<repo-root>"`, and `context_files` pointing to touched specs/files before Step 4.
   - Run `(.agents/skills/cadence-spec/verify-facts.sh --trace {ticket-id} --base <integration-branch> || skills/cadence-spec/verify-facts.sh --trace {ticket-id} --base <integration-branch>)` (routing `>30`-line failure output through `offload_log_triage`) and pass its `PASS`/`FAIL`/`WARN` traceability report directly into Step 4 for `cadence-reviewer` (treating missing scenarios, untraced Low-tier ACs, or omitted CHORD seams as blocking evidence unless explained in `decisions.md`).
   - Run `(.agents/skills/cadence-review/security-trigger.sh --base <integration-branch> {ticket-id} || skills/cadence-review/security-trigger.sh --base <integration-branch> {ticket-id})` to determine whether `cadence-security-auditor` is dispatched alongside `cadence-reviewer` (`High` tier always `TRIGGER`; `Low`/`Medium` diffs `TRIGGER` on auth, secrets/crypto, SQL/migrations, concurrency/locks, or untrusted exec signals; `Trivial` `SKIP`). Capture the `decision=TRIGGER|SKIP` output cleanly.

4. **Delegate to `cadence-reviewer` (and `cadence-security-auditor` when `decision=TRIGGER`, both on `Deep-reasoning` tier, `xhigh` effort).** Supply the diff, the tier contract artifacts, Step 3's `--trace` + `security-trigger.sh` output, and Step 0/3's `offload_deep_review` pre-scan so the strictly read-only `cadence-reviewer` executes Pass 1 (Contract, Independent Test/Gate Execution via `offload_log_triage`, Boundaries, Pillars, Migrations) and Pass 2 (Section 10 Adversarial Falsification across Positions 1–4). When `security-trigger.sh` returns `decision=TRIGGER` (or Step 3 failed to run it — fail safe toward auditing on High/sensitive changes), concurrently invoke the read-only `cadence-security-auditor` subagent (`xhigh` effort) to audit authn/authz, secrets/PII, injection/SSRF/traversal, TOCTOU/locking races, transactions/idempotency, and fail-open fallbacks, and merge its blocking and classified non-blocking findings into Step 5's review report:
   - Verify every acceptance criterion against the concrete implementation
   - Audit test coverage and scenario fidelity against `test-plan.md` (or `problem.md` at Low tier)
   - Verify architectural boundaries (Clean Architecture layer direction, service contracts, CHORD seams)
   - Evaluate Engineering Pillars (Structural Simplicity, Operational Resilience, Agentic Ergonomics `<400`-line ceiling, Data & Audit Fidelity, Security Boundary Posture, Surface Compatibility)
   - Verify database migration safety (expand/contract reversibility) where applicable
   - **Core generative principle for the adversarial lens (`AGENTS.md` / `GEMINI.md` §10):** treat every assumption of the form *"this is safe because X"* as an unverified claim that must be checked directly against the authoritative source of X (actual seed-data volumes, vendored engine source/docs, all sibling state writers, production configuration, and canonical story files) — never take the claim at face value; and classify every discovered defect by its structural location relative to the diff: `(1)` inside the diff itself, `(2)` inside upstream code consumed by the diff, `(3)` inside downstream callers consuming the diff, or `(4)` inside untouched sibling code whose invariant the diff silently altered.
   - Apply the **adversarial lens** (`AGENTS.md` / `GEMINI.md` §10): once happy-path spec conformance is confirmed, actively hunt for *silent or partial failure modes* — fallback defaults or stubs that conceal broken state, overly broad exception handlers, unverified assumptions about collaborator behavior (including changes merged to the integration branch after this branch was cut), and test/fake blind spots. Previously approved `decisions.md` entries are not immune to adversarial verification; any silent or partial failure path is a blocking defect. Classify each finding across the four structural positions `(1)`–`(4)` above, scaling depth proportionally to coupling complexity so isolated trivial diffs remain fast. **Never accept a specification's `"out of scope / known limitation / cannot occur at current scale"` disclaimer unverified** — check the actual numbers (seed data counts, default parameter bounds, real payload sizes) and recompute the threshold; any limitation resting on a false numerical premise is an active blocking bug, not future tech debt.
   - Whenever the diff declaratively configures an external engine or framework (map style layers, ORM query builders, CSS layout rules, IaC templates, GraphQL schemas), inspect the **authoritative engine contract** (vendored source or official specification) rather than relying solely on the diff and test doubles — omitted declarative properties interacting with engine defaults are a primary source of production defects.
   - Whenever the diff connects a new field, state atom, or column into a **shared** surface governed by a mutual-exclusivity or consistency invariant (a composite query, serializer/encoder, state reducer, or `"exactly one of"` rule), enumerate **every** writer touching any field in that invariant — including **unchanged sibling writers outside the diff** — and confirm each writer still preserves the invariant. An untouched sibling setter that previously worked in isolation but now leaves the shared invariant violated (e.g., setting one side of a mutually exclusive pair without clearing the newly coupled field) is a blocking defect invisible to narrow diff-only inspection.
   - Whenever a state transition (component mount/hydration, browser back/forward navigation, form reset, or object spread) carries forward a subset of prior state while overwriting other fields, confirm that every retained derived field remains consistent with the overwritten fields (e.g., ensuring a stale map bounding box is not spread forward when center/zoom reset); and confirm that load-bearing integration tests run against the production framework router/container (`createBrowserRouter`, real DI container) rather than a test-only harness that masks the state transition bug.

   **Mandatory re-review after rebasing or merging upstream dependencies.** Whenever the feature branch is rebased onto (or merged with) integration-branch commits that landed after the previous review — such as a collaborator ticket merging upstream — `/cadence-review` must be executed again. A review conducted against an earlier base could not observe interaction bugs introduced when the new upstream collaborator combined with this branch.

5. **Format the review report** as structured change-proposal comments and persist it locally first:
   - Top-level summary containing the overall verdict (`Approve`, `Request Changes`, or `Needs Discussion`) and the per-AC verification checklist
   - File-and-line anchored comments for specific blocking defects and non-blocking observations
   - **Unconditionally** append the complete review record (verdict, AC checklist, and detailed findings) to `specs/{ticket-id}/submission.md` under `## Discussion` so the repository archive preserves the full audit trail regardless of external forge availability.

   Next, publish the review to the external forge **if and only if an MR URL is resolvable**:

   - **MR-existence check.** Look up the MR URL from `merge_request:` in `specs/{ticket-id}/metadata.yaml` **or** `Thread URL` under `## Forge metadata` in `submission.md`. When a URL resolves, posting the review to that forge thread is **MANDATORY**. When **no** MR URL resolves (for example, reviewing a local branch prior to MR creation), the `submission.md` write above is complete — **never** attempt a forge CLI call and **never** treat the absent URL as an error.

   - **Forge publication.** When an MR URL is present, read the `Forge:` type from `submission.md`'s `## Forge metadata`, write the formatted review body to a temporary file, and invoke the matching CLI:
     - **GitHub:** `gh pr comment <pr-number-or-url> --body "$(cat <review-output>)"`
     - **GitLab:** `glab mr note <mr-iid> --message "$(cat <review-output>)"`
     - **SourceHut:** no CLI comment command exists — `submission.md`'s `## Discussion` already holds the canonical record; append a note there instructing the operator to send an email reply to the `lists.sr.ht` patchset thread.

   - **Loud failure reporting.** If `gh` or `glab` exits non-zero, **surface the failure and verbatim CLI error output to the operator**, while confirming that the review was safely persisted in `submission.md`. **Never** swallow a failed forge post silently.

6. **Disposition owed follow-up findings** across **every** review verdict (`Approve`, `Request Changes`, `Needs Discussion`) independently of `tier` or `status` (at **Low** tier this is the sole human follow-up gate). Format candidate scratch drafts as `specs/drafts/{ticket-id}-review-<UTC>-<N>.md` (capture `<UTC>` once via `date -u +%Y%m%dT%H%M%SZ`; `<N>` = 1-based ordinal).

   Execute **Steps a–e** defined in [followup-disposition.md](references/followup-disposition.md) with `<gate>` = `/cadence-review`:
   - **(a) Enumerate & verify classes:** halt on any unlabelled undispositioned non-blocking item (`finding.class.unlabelled`); gather undispositioned `out-of-scope-defect` entries (`nit`, `hygiene`, `observation`, `adr-owed` stay in `## Discussion`; if 0 candidates remain, write `none owed` + per-class tally).
   - **(b) Capability floor:** require command composition + interactive confirmation, else take degraded deferral writing drafts to disk and emitting `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable`.
   - **(c) Dedupe & confirm:** search `specs/` and `archive/` via `local_semantic_embed` / `repo-scout` (`local-coprocessor` tier) for `new`, `duplicate of <id>`, or `fold into <id>` (halt on unreadable root with `followup.dedupe.check_unavailable`); `cadence-reviewer` only labels findings — this step asks the human.
   - **(d) File/fold confirmed candidates:** run `/cadence-triage --file-only <draft-path>` (never call `mint-id.sh` directly or directory-scan; emit `followup.filing.draft_cleanup_failed` only on cleanup failure); verify `<id>` is `draft` or `triaged` before folding into `## Notes`.
   - **(e) Record dispositions:** update `## Resolution` -> `Follow-ups created` using canonical forms (`filed`, `duplicate`, `folded`, `none owed`, `declined`, `deferred`) + per-class tally.

7. **Log code-review stage effort and project to tracker.** In accordance with `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation", append a `stage_effort` entry to `specs/{ticket-id}/metadata.yaml` (`stage: code-review`, `at` = exact UTC completion timestamp from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded, midnight, or date-only) whose `effort` value comes from running `(test -x ci-templates/scripts/stage-effort.sh && ci-templates/scripts/stage-effort.sh || processes/ci-templates/scripts/stage-effort.sh) --stage code-review --observed <minutes>` — verify `0m` or an exact 15-minute multiple, add to `actual_effort`, and invoke the bound tracker sync skill (`CADENCE_ORG.md` §9). Across its entire execution, `/cadence-review` executes Steps 5–7 writes while `cadence-reviewer` remains strictly read-only.

8. **Report to the operator:**
   - Review verdict (`Approve` / `Request Changes` / `Needs Discussion`)
   - Count of blocking defects
   - Count of non-blocking findings and their follow-up dispositions
   - Concise synthesis of architectural and adversarial review findings

## Example

```
/cadence-review 142
/cadence-review impl/feature/ORD-40
```

## Local Model Offload Integration (:11434)
- Step 0 automatically invokes `offload_deep_review` (`inference` on `:11434`) to execute an advisory mechanical pre-scan over the branch diff (verifying the `<400`-line Agentic Ergonomics ceiling, comment preservation discipline, CHORD observability seams, and security boundary patterns).
- Step 6c uses `local_semantic_embed` (`embedding` on `:11434`) / `repo-scout` when checking `specs/` and `archive/` for prior-work deduplication.
- The `Deep-reasoning` tier (`effort: xhigh`, routed by `CADENCE_ORG.md#model-tier-mapping`) independently verifies all mechanical flags and conducts the four-position adversarial review against the approved tier contract (`spec.md` or `problem.md`) before issuing the verdict.
