---
name: cadence-archive
description: Archive a completed or cancelled ticket -- relocate spec artifacts to archive/, generate summary.md, update CHANGELOG.md, promote ADRs and intent insights, sweep dead citations, and sync the repo's bound tracker (CADENCE_ORG.md#tracker-binding)
argument-hint: "[ticket-id]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Archive the completed (or cancelled) ticket `$ticket_id`. Delegate core archival file moves, summary generation, and promotions to the `cadence-archivist` subagent, and enforce the inbound dead-citation sweeps, insight-register gates, and follow-up backstop dispositions.

## Prerequisites

Verify before starting:
- `specs/$ticket_id/` exists on disk containing the ticket's artifacts
- The ticket satisfies **one of two** valid entry states, and **the matching entry state governs which archival path runs**:
  - **(a) Merged.** The ticket's change proposal has merged: `specs/$ticket_id/metadata.yaml` carries `status: merged`, or the merge commit is an ancestor of the integration branch tip (resolving `<integration-branch>` dynamically from the `integration-branch` marker in `CADENCE_ORG.md#branch-strategy-binding` per `ADR_CADENCE-0020`; never hardcode a branch name). Follow the standard merged archival path.
  - **(b) Terminated without merging.** `specs/$ticket_id/metadata.yaml` carries `status: cancelled` — the canonical terminal status for work closed without merging. Follow the **close-out path** defined below. **Entry state (b) TAKES PRECEDENCE over (a)** even if a merge commit happens to be reachable on a branch: a ticket explicitly marked `status: cancelled` in its metadata is cancelled, regardless of any stray branch ref.

When the ticket satisfies **neither** (a) nor (b), stop and inform the operator that archival requires a completed merge (run `/cadence-maintain` and merge first) — or, for abandoned work, require setting `status: cancelled` together with a `resolution:` explanation in `metadata.yaml` rather than archiving an active ticket. If `specs/$ticket_id/` is absent and `archive/$ticket_id/` already exists on disk, inform the operator that `$ticket_id` is already archived.

**The close-out path (entry state (b)).** Because a cancelled ticket has no merge commit, never fabricate merge data:
- **HALT when no cancellation reason is recorded.** Whenever `merged_at` is empty **and** `resolution:` is missing, empty, or whitespace-only, **halt immediately**. Emit `archive.close_out_reason_absent` citing `$ticket_id` and the unpopulated `resolution:` attribute. Perform no file moves, create no `summary.md`, add no `CHANGELOG.md` entry, and run no tracker sync — halting cleanly leaves zero partial state behind. Instruct the operator to populate `resolution:` in `specs/$ticket_id/metadata.yaml` (following the normative schema comment in `specs/TEMPLATE/metadata.yaml`) and re-invoke `/cadence-archive $ticket_id`.
- **This halt applies EXCLUSIVELY to entry state (b) and never triggers on entry state (a).** Because nothing in the standard merge flow populates `merged_at`, genuinely merged tickets routinely arrive at `/cadence-archive` with both `merged_at` and `resolution:` empty (e.g., `archive/BTG-113` and `archive/PI-003`). Tickets entering via branch (a) bypass this check completely.
- **CARVE-OUT -- terminal disposition already RATIFIED and already ASSERTED by a live test. Evaluate this before any other check on the close-out path.** Whenever `$ticket_id`'s terminal disposition is already documented inside a **ratified decision record** belonging to another ticket **and** is actively guarded by a **live automated assertion** inspecting `$ticket_id`'s files, the close-out **may proceed under three strict conditions**. Emit `archive.closeout.disposition_already_asserted`, citing the ratifying decision entry, every asserting test script discovered, and the exact repointing applied to each. All three conditions below are mandatory:

  1. **Carry the ratified disposition forward verbatim without re-adjudicating it.** Archival relocates the directory and sets terminal `status: archived`; it never re-evaluates or rewords a disposition already ratified by another ticket's gate. Set `resolution:` to the exact disposition token used by that ratified decision.

  2. **Repoint every assertion referencing `$ticket_id`'s paths within the SAME commit so the test retains its enforcement teeth.** Never defer repointing to a follow-up commit. Any test assertion that would trivially pass after `specs/$ticket_id/` moves *merely because the old path no longer exists* has been silently neutered rather than repointed — **a vacuous green test is more dangerous than a failing red test** because it reports coverage while checking nothing.

  3. **If any assertion cannot be repointed without going vacuous, HALT.** Emit `archive.closeout.assertion_would_go_vacuous`, cite the un-repointable test assertion, and modify no files. Preserving an active regression guard takes priority over moving the directory.

  **BOTH the ratified decision and the live assertion must exist; neither suffices alone.** A prose decision without a mechanical test, or a test without a ratified decision record, follows the standard close-out rules above.

  Never edit the ratified text inside the artifact to match the new directory path. Where a standard close-out would modify `problem.md`'s `## Status` section in place, any file guarded by a byte-comparison test receives an appended note instead (or keeps its pinned bytes intact while the test's path reference is updated to `archive/$ticket_id/`).

  Canonical precedent for this carve-out: **BTG-093**, whose `SUPERSEDED` disposition was ratified by `archive/BTG-132/decisions.md` DEC-002 cl.2 and guarded by `ci-templates/scripts/tests/btg-132-registered-surface-fixes.test.sh` S-3.1 (byte-comparison against a merge base) and S-3.2 (asserting the directory contains `problem.md` only, with no `metadata.yaml` and no `tier:`/`status:` fields). Moving `BTG-093` on 2026-09-15 without updating S-3.1 and S-3.2 broke S-3.1 and rendered S-3.2 vacuous; that move was reverted, this rule was codified, and the move was re-executed with both assertions repointed.

  **This fulfills DEC-002's intent rather than overriding it.** DEC-002 cl.2 forbade adding `metadata.yaml` under `specs/BTG-093/` because doing so *"would insert a SUPERSEDED ticket into the implementation pipeline"*. Relocating the ticket into `archive/` removes it from the active implementation pipeline permanently, and a close-out `metadata.yaml` records only the terminal disposition without a `tier` or classification.

- **Preserve actual records without fabrication.** Copy `resolution:` and the cancellation explanation into `archive/$ticket_id/` verbatim, keep `merged_at` empty, do not synthesize `submission.md` fields from a nonexistent merge commit, and do not invent diff statistics for unmerged work. Set `status: archived` upon relocation so all downstream tools checking for the single terminal status continue working uniformly (precedent: `archive/BTG-045` and `archive/BTG-061`).

## Steps

1. **Read the ticket's archival inputs and match affected flow docs via `local_semantic_embed`:**
   - Read `specs/$ticket_id/metadata.yaml` (lifecycle status, URLs, timestamps, effort ledger)
   - Read `specs/$ticket_id/submission.md` (resolution summary and review/maintainer discussion record, if present)
   - **Automatic Semantic Flow Matching (`local_semantic_embed`).** Automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) to compare the ticket's specification/summary against `docs/flows/*.md`, `docs/ADR/*.md`, and `docs/agentic-sdlc/intent-insights.md`. Pass the matched flow documents and related ADRs to `cadence-archivist` in Step 2 so flow-documentation update proposals and ADR cross-references are grounded without brute-force reading of unrelated docs.

1b. **Disposition recorded `adr-owed` findings** prior to delegating to `cadence-archivist` (`PROD_CADENCE-015`). First, enforce `docs/policies/finding-classes.md` Routing step 1's unlabelled-entry check across all undispositioned Non-Blocking items in `submission.md`'s `## Discussion`, ensuring any human-supplied class label (including `adr-owed`) is written as a Routing step 1 note before `adr-owed` items are gathered. Next, extract every `[adr-owed]` item from `## Discussion` (live path) — including items tagged `adr-owed` via a Routing step 1 note ("read it exactly as if" rule) — and display each item alongside its recorded trigger precondition and current evidence (`docs/policies/finding-classes.md`, *adr-owed at archive*). The human operator selects either **promote** (author the ADR now) or **defer-with-reason** (never re-litigating whether the ADR was owed in the first place). Write each ruling as a single line in `## Discussion` prior to Step 2:
   - Items chosen for **promotion** are passed directly to `cadence-archivist` (Step 2) as mandatory ADR inputs (never re-evaluated or duplicated from `decisions.md`).
   - Items chosen for **deferral** flow into Step 2e's follow-up candidate pool.
   - When no interactive confirmation channel is available, record every `[adr-owed]` item as `Deferred` citing `followup.filing.confirmation_channel_unavailable` and route them to Step 2e.
   - When zero `[adr-owed]` items exist, proceed directly to Step 2.
   Any `[adr-owed]` item that reaches Step 3's exit check neither promoted into a concrete `docs/ADR/` file nor dispositioned under `Follow-ups created` fails archival verification with `archive.adr_owed.undispositioned`.

2. **Delegate to `cadence-archivist`.** Supply the ticket artifacts, Step 1's `local_semantic_embed` flow matches, and Step 1b's promoted `adr-owed` rulings so the subagent will:
   - Finalize `submission.md` (recording final status, discussion, and merge commit resolution on entry path (a))
   - Relocate `specs/$ticket_id/` to `archive/$ticket_id/`
   - Author `archive/$ticket_id/summary.md` incorporating git history metrics
   - **Record the archive stage effort** — following `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation", append an `archive` entry to `stage_effort` (`at` = exact UTC completion timestamp from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded, midnight, or date-only) with `effort` computed via `ci-templates/scripts/stage-effort.sh --stage archive --observed <minutes>` (applying the configured stage multiplier to observed archival minutes and rounding up to a 15-minute multiple), and add that increment to `actual_effort` inside `archive/$ticket_id/metadata.yaml` (never recomputing `actual_effort` from git log timestamps). The tracker sync below projects this entry as the archive stage worklog.
   - Update `CHANGELOG.md` (following Keep a Changelog structure)
   - Promote qualifying architectural decisions to `docs/ADR/` and reusable intent insights to `docs/agentic-sdlc/intent-insights.md`
   - Project the archival state to the repository's bound tracker (resolved from `CADENCE_ORG.md#tracker-binding`; halt loudly if unbound when a tracker sync is required) using **owned-items-only scoped projection** (touching only items owned by this repository)
   - Draft proposed updates for any matched `docs/flows/*.md` files surfaced in Step 1 (flagged for human review)
   - Delete or clean up the merged feature branch

2b. **Sweep inbound citations to `$ticket_id` (`PROD_CADENCE-009`) — blocking whenever the classifier script is installed.**

    Relocating `specs/$ticket_id/` to `archive/$ticket_id/` in Step 2 turns every surviving repository reference to `specs/$ticket_id/` into a broken path. Because no later lifecycle phase scans for stale inbound pointers — and because this defect class recurred three separate times before being mechanized — Step 2b enforces the sweep directly.

    (Provenance note: this defect class is cataloged as **PROD_CADENCE-009** in `docs/agentic-sdlc/production-insights.md`. Because `production-insights.md` is an **adopter-seeded file** copied once during initial adoption and untouched by `/cadence-upgrade`, repositories adopted prior to `PROD_CADENCE-009` may not contain that ID locally; Step 2b's enforcement authority is self-contained and never depends on looking up that ID.)

    **First, verify that the classifier script exists AND is non-empty:**
    `ci-templates/scripts/dead-citation-gate.sh` must exist on disk **with size > 0 bytes** —

    ```
    [ -s ci-templates/scripts/dead-citation-gate.sh ]
    ```

    Testing `[ -f ]` alone is **insufficient**: a truncated 0-byte file is a valid shell script that exits `0`, which would trick Step 2b into recording a clean citation sweep when zero lines were checked. Treat an **absent file and a 0-byte file identically**: route both to the not-installed branch below and **never execute the script**.

    **When the classifier exists and is non-empty**, execute the ticket-scoped citation sweep:

    ```
    bash ci-templates/scripts/dead-citation-gate.sh --id $ticket_id
    ```

    **Automatic Output Triage (`offload_log_triage`).** Whenever `dead-citation-gate.sh` exits non-zero or emits violation hits exceeding 30 lines, automatically pass its output through `offload_log_triage` (`local-fast-cpu` on `:9379`, saving the complete numbered raw output to `/tmp/agy-last-triage.log`) to extract every verbatim hit, classification tag (`NOT-A-COMMENT`, etc.), and exact `file:line` coordinate.

    This invokes the **exact same script** used by the `dead-citation` CI gate row and by Step 2c below — one shared classifier across all three call sites. (In adopter repositories that have not copied the optional Beta `run-gates.sh` harness, Step 2b and Step 2c are the sole callers.) The classifier **detects, classifies, and blocks; it never auto-edits files.**

    Interpret the script's exit code across **three distinct branches** (`0 clean ; 1 on a violation ; 2 on setup failure`):
    - **Exit 0:** clean sweep; proceed to Step 2c.
    - **Exit 1:** one or more dead citations found; disposition every hit below.
    - **Exit 2 (or any other non-zero exit code):** setup failure; halt immediately per the Exit 2 block below.

    For **each** violation hit on Exit 1, apply **exactly one** sanctioned disposition:

    - **REPOINT** (default) — update the reference in place from `specs/$ticket_id/` to `archive/$ticket_id/`.
    - **EXEMPT** — append a documented exemption row to `ci-templates/scripts/dead-citation-exemptions.txt` specifying the exemption class (`Class C` historical narrative recording a past state, or `Class D` where the literal `specs/` path itself is the subject under test) and rationale. Never exempt a citation merely to avoid editing it.

    Any hit tagged `NOT-A-COMMENT` occurs inside **executable code** — such as a path filter, shell variable, or `git show <ref>:specs/<id>/...` command inspecting a historical commit where `specs/<id>/` existed at `<ref>`. Inspect and disposition every `NOT-A-COMMENT` hit **individually**; **never** bulk-replace it, as rewriting a historical `<ref>:specs/<id>/` lookup breaks working code.

    **Never auto-rewrite without inspection**, and never ignore a hit. Log every hit and its chosen disposition (`REPOINT` or `EXEMPT`) inside `archive/$ticket_id/summary.md` under `## Citation Dispositions`. **Archival cannot complete while any hit remains undispositioned** — re-run `dead-citation-gate.sh --id $ticket_id` until it exits `0`. Never add a newly archived ticket to `dead-citation-baseline.txt`; that baseline ledger is strictly shrink-only legacy debt.

    **When the classifier is installed and non-empty but exits 2 — HALT IMMEDIATELY.** A setup error means an installed gate failed to execute:

    ```
    seam_type=BOUNDARY_FAULT event_name=archive.dead_citation.classifier_setup_failed subject=ci-templates/scripts/dead-citation-gate.sh
    /cadence-archive step 2b cannot complete: the dead-citation classifier is installed but could not run
    (exit <n> -- its documented setup-failure status).
    ```

    Display the script's verbatim error message and — when the cause is a missing baseline file — display the one-line remediation command:
    `bash ci-templates/scripts/dead-citation-gate.sh --emit-baseline > ci-templates/scripts/dead-citation-baseline.txt`.

    Because Step 2 already moved the directory to `archive/$ticket_id/`, **explicitly inform the operator that the ticket is NOT yet fully archived**, and state the recovery procedure: simply re-running `/cadence-archive $ticket_id` **will not resume Step 2b** because Prerequisites will see `archive/$ticket_id/` and report the ticket already archived. Instead, after fixing the setup error, the operator must either move the directory back (`mv archive/$ticket_id/ specs/$ticket_id/`) and re-run `/cadence-archive $ticket_id`, or run `dead-citation-gate.sh` manually, disposition all hits, and complete Steps 2c–4.

    **When the classifier script is absent or 0 bytes — do NOT halt, do NOT silently skip, and do NOT execute the file.** Output this exact notice, record the corresponding token in `archive/$ticket_id/summary.md`'s `## Citation Dispositions` section, and proceed to Step 2c:

    ```
    seam_type=DELTA_AUDIT_GAP event_name=archive.dead_citation.sweep_skipped subject=ci-templates/scripts/dead-citation-gate.sh
    /cadence-archive step 2b SKIPPED: the dead-citation classifier is not installed in this repository
    (ci-templates/scripts/dead-citation-gate.sh is absent or empty).

      ==> Inbound-citation rot (PROD_CADENCE-009) is UNGUARDED for this archival. Moving specs/<id>/ to
          archive/<id>/ has just turned every external reference to the old path into a dead
          pointer, and nothing has checked for them.

    To enable the gate for future archivals, copy these three files from a CADENCE core checkout
    into ci-templates/scripts/ :
        dead-citation-gate.sh
        dead-citation-ledgers.sh
        dead-citation-exemptions.txt
    then GENERATE this repository's own baseline (do NOT copy core's dead-citation-baseline.txt --
    it is core's debt, naming core's files, and installing it would silence your real findings):
        bash ci-templates/scripts/dead-citation-gate.sh --emit-baseline \
          > ci-templates/scripts/dead-citation-baseline.txt

    If you want a one-off sweep for THIS archival without installing the gate, you can run an
    UNGOVERNED manual check and disposition the hits by hand:

        git grep -n "specs/<id>/" -- ':!archive/'

    This is NOT equivalent to the gate. It has no shared exemption ledger (so nothing carries your
    decisions forward), no CI regression cover (so nothing catches a re-introduction), and it is
    re-derived from scratch every archival. Taking it is better than nothing; it is not the sweep.
    If you take it, record it as DEAD-CITATION-SWEEP: MANUAL. Declining it is a legitimate choice
    and is recorded as DEAD-CITATION-SWEEP: SKIPPED.
    ```

    Note that `-- ':!archive/'` in the manual `git grep` command is **essential**: because Step 2 just relocated `$ticket_id` into `archive/$ticket_id/`, omitting that pathspec exclusion floods the output with false-positive matches inside `archive/`. **Present** the manual fallback command to the operator, but **never execute it automatically** — running an ungoverned grep automatically would erase the distinction between governed enforcement and operator-elected manual inspection.

    Always list the three script files explicitly rather than using a `dead-citation-*` glob, because a glob would also copy core's `dead-citation-baseline.txt` and mask local findings. Emit this notice on **every** unguarded archival run without suppression.

    **Formatting rule for `## Citation Dispositions`:** the section records one of four canonical outcomes, and the two unguarded outcomes MUST begin with a standalone token on the **very first line** of the section body — containing **zero leading spaces, zero trailing comments, and zero punctuation**:

    ```
    DEAD-CITATION-SWEEP: SKIPPED
    DEAD-CITATION-SWEEP: MANUAL
    ```

    Place any explanatory prose (including the word *ungoverned*) on the **following** line. Keeping line 1 strictly anchored enables `grep -rlE '^DEAD-CITATION-SWEEP: [A-Za-z]+$' archive/*/summary.md` to audit every unguarded archival across the repository without false positives from prose mentions or missed records from casing/spelling drift.

2c. **Sweep for dead citations targeting OTHER archived tickets (`PROD_CADENCE-015`) — blocking under the same installation check as 2b.**

    During Step 2, `cadence-archivist` authored **new content** in `docs/ADR/` and `docs/agentic-sdlc/intent-insights.md`. Those newly promoted records frequently cite *other*, previously archived tickets using stale `specs/<other-id>/` paths — which Step 2b (`--id $ticket_id`) cannot detect because it searches only for `$ticket_id`. Step 2c closes that exact gap so a newly promoted ADR never breaks the integration branch's repo-wide dead-citation ratchet.

    Execute Step 2c **strictly after Step 2b exits 0**, using the **identical** non-empty script check:

    ```
    [ -s ci-templates/scripts/dead-citation-gate.sh ]
    ```

    **When the classifier exists and is non-empty:**

    ```
    bash ci-templates/scripts/dead-citation-gate.sh --except-id $ticket_id
    ```

    Whenever the output exceeds 30 lines, automatically pass it through `offload_log_triage` (`local-fast-cpu` on `:9379`, saving raw numbered output to `/tmp/agy-last-triage.log`).

    `--except-id $ticket_id` scans every archived ticket ID in the repository **except** `$ticket_id`. Together, Step 2b (`--id $ticket_id`) and Step 2c (`--except-id $ticket_id`) partition the entire `archive/` set with zero overlap and complete coverage — subject to one documented carve-out: files carrying a **blanket file-level exemption** in `dead-citation-exemptions.txt` (such as the append-only ledger `docs/agentic-sdlc/intent-insights.md`, per BTG-133 DEC-033) are excluded from both passes by design.

    Handle exit codes `0`, `1`, and `2` identically to Step 2b:
    - **Exit 0:** continue to Step 2d.
    - **Exit 1:** disposition every hit using **REPOINT** (rewriting `specs/<other-id>/` to `archive/<other-id>/` — note that the target is `<other-id>`, **not** `$ticket_id`) or **EXEMPT** (adding a justified entry to `ci-templates/scripts/dead-citation-exemptions.txt`). **NEVER run `--emit-baseline` to silence a Step 2c hit**, as growing the legacy baseline violates the shrink-only ratchet. Log each Step 2c disposition in `archive/$ticket_id/summary.md` under the **same** `## Citation Dispositions` heading written by Step 2b, labelling which step (`2b` vs. `2c`) surfaced each row. If any hit remains undispositioned, fail loudly:

      ```
      seam_type=DELTA_AUDIT_GAP event_name=archive.citation_sweep.complement_undispositioned subject=<file>:<line>
      ```

    - **Exit 2:** **HALT** citing `archive.dead_citation.classifier_setup_failed` and quoting the classifier's verbatim error message, exactly as in Step 2b.

    Because Step 2c scans repo-wide (`--except-id`), it will also catch pre-existing dead citations introduced outside this ticket; dispositioning them here is intentional so the integration branch stays green.

    **When the classifier is absent or 0 bytes — do NOT halt, do NOT silently skip, and do NOT execute it.** Output this notice, log the skip in `## Citation Dispositions`, and advance to Step 2d:

    ```
    seam_type=DELTA_AUDIT_GAP event_name=archive.dead_citation.complement_skipped subject=ci-templates/scripts/dead-citation-gate.sh
    /cadence-archive step 2c SKIPPED: the dead-citation classifier is not installed in this repository
    (ci-templates/scripts/dead-citation-gate.sh is absent or empty).

      ==> Citations of OTHER archived tickets, written into this tree by this run's own ADR and
          intent-insight promotion, are UNGUARDED for this archival.
    ```

2d. **Verify the insights registers modified during archival (BTG-191) — blocking under the same non-empty check.**

    Step 2's archivist promotion updates `docs/agentic-sdlc/intent-insights.md`, and archival also writes a **`Closed by:` resolution note** onto the ticket's `PROD-NNN` record inside `docs/agentic-sdlc/production-insights.md` whenever one exists. **Documenting that `production-insights.md` write explicitly here ensures it is covered by a mechanical gate** rather than remaining an uninspected side effect (`PROD_CADENCE-015`). Because both registers ship downstream (`production-insights.md` is `kind=seed`), any organization-specific identifier leaked into either file violates portability.

    **First, check that `authored-doc-gate.sh` exists AND has size > 0 bytes:**

    ```
    [ -s ci-templates/scripts/authored-doc-gate.sh ]
    ```

    As in Step 2b, `[ -f ]` is **insufficient** because a 0-byte file exits `0`. When `authored-doc-gate.sh` is **missing or 0 bytes**, take the not-installed path, record the skip in `archive/$ticket_id/summary.md`, and never claim a clean verification.

    **When installed and non-empty**, execute it against both registers:

    ```
    bash ci-templates/scripts/authored-doc-gate.sh --path docs/agentic-sdlc/intent-insights.md
    bash ci-templates/scripts/authored-doc-gate.sh --path docs/agentic-sdlc/production-insights.md
    ```

    (If output exceeds 30 lines, automatically compact via `offload_log_triage` on `:9379`.) This runs the **same classifier** invoked by the `authored-doc` CI gate, `/cadence-release` step 4b, and triage's `PROD`-entry append:
    - **Exit 0:** proceed to Step 2e.
    - **Exit 1:** remediate each hit by either generalizing the org-specific phrase in the newly written prose or adding a sentence-anchored exemption row in `ci-templates/scripts/authored-doc-ledgers.sh` (anchored strictly to the offending **sentence**, never blanket-exempting the entire file). **Never edit historical archived `PROD-NNN` entries in place**; use a sentence-anchored ledger row for immutable historical records. Record every hit and disposition in `archive/$ticket_id/summary.md`.
    - **Exit 2:** **HALT** immediately on setup failure.

2e. **Disposition owed follow-ups — the final lifecycle completeness backstop.** Because `/cadence-archive` is the terminal phase of the ticket lifecycle, Step 2e acts as the final catch-all ensuring no non-blocking defect raised at any earlier gate (`/cadence-review` or `/cadence-maintain`) or deferred at Step 1b was left behind. Resolve `submission.md` by checking **`specs/$ticket_id/submission.md` first, then `archive/$ticket_id/submission.md` second** (since Step 2 has normally relocated the directory already). Format each `new` candidate's scratch file path as `specs/drafts/$ticket_id-archive-<UTC>-<N>.md` — a single whitespace-free path under `specs/drafts/` (created if absent), with `<UTC>` captured **once per archive run** via `date -u +%Y%m%dT%H%M%SZ` (DEC-014) and `<N>` denoting the candidate's 1-based ordinal from sub-step `a`.

   a. **Enumerate and verify finding classes.** Enforce `docs/policies/finding-classes.md`: any Non-Blocking entry in `## Discussion` lacking both a disposition in `## Resolution` -> `Follow-ups created` and a valid class token **halts enumeration** (entries already listed in `Follow-ups created` are exempt legacy records). Emit `finding.class.unlabelled` naming the entry and prompt the operator for a class label; re-prompt once on an empty or unrecognized reply, and on a second miss record the item as `Deferred` citing `finding.class.unlabelled`. Record any valid supplied label per `docs/policies/finding-classes.md` Routing step 1 naming `/cadence-archive`. If an entry is newly labelled `adr-owed` here in 2e.a (after Step 1b already completed), handle it per `docs/policies/finding-classes.md` (*adr-owed at archive*): record it `Deferred` with that rationale and include it in Step 2e's candidate list alongside Step 1b's deferrals. With no confirmation channel, record unlabelled entries `Deferred` naming that cause. Next, gather from `## Discussion` every candidate — all `out-of-scope-defect` entries from any prior gate plus all `adr-owed` entries deferred in Step 1b (or 2e.a) — that lacks a disposition in `## Resolution` -> `Follow-ups created`. Already-dispositioned items are **never re-presented**. Entries classed `nit`, `hygiene`, or `observation` are never candidates. **Zero candidates** => record the none-owed disposition with the per-class tally clause and advance to Step 3. When a ticket has **no `submission.md` at all** (such as a Trivial ticket under `docs/policies/change-tiers.md`), nothing is owed; note that and proceed to Step 3.

   b. **Verify runtime capability floor.** Step 2e requires (i) command composition to invoke `/cadence-triage --file-only` and (ii) an interactive confirmation channel. **If either is missing**, take the degraded deferral path: write each candidate's verbatim description to its `<draft-path>` and **keep it on disk** — invoke **no** callee, allocate **no** id, and **never simulate `/cadence-triage`**. Emit `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable`, record each candidate's one-line description and exact `/cadence-triage --file-only <draft-path>` command in `## Discussion`, and write the deferred disposition naming that cause in `Follow-ups created`. When both (i) and (ii) are available, never take this degraded branch.

   c. **Prior-work deduplication, presentation, and human confirmation.** Assign each candidate its prior-work verdict (`docs/policies/finding-classes.md`, Routing step 4) by searching `specs/` and `archive/` (using Step 1's `local_semantic_embed` index / `local-moe-hybrid`) and tagging each as `new`, `duplicate of <id>`, or `fold into <id>` (citing `<id>`; archived-only matches are cited as context and tagged `new`). If `specs/` or `archive/` cannot be read, halt with `followup.dedupe.check_unavailable` naming the unreadable root — never default to `new`. Display the numbered list of verdicted candidates and ask the human operator which items to file. Re-prompt once on an empty or unrecognized reply; on a second invalid reply, record remaining candidates as **deferred with that reason**.

   d. **Execute confirmed filings and folds.** For each confirmed `new` candidate, write its verbatim description to `<draft-path>` first, then invoke `/cadence-triage --file-only <draft-path>`. **Never** invoke the id allocator directly or hand-write `specs/<id>/` artifacts. On exit `0`, delete `<draft-path>` (reporting `followup.filing.draft_cleanup_failed` if deletion fails without undoing the filing). On a **non-zero exit**, halt, report the callee's error **verbatim**, keep `<draft-path>` as evidence, and record remaining candidates as `Deferred` citing that error. **Never fall back to directory scanning** for an id, and never delete an already-filed `specs/<id>/` trail on a partial run. For confirmed `duplicate of <id>` items, file nothing. For confirmed `fold into <id>` items, re-verify at write time that `<id>` is still open at `draft` or `triaged` (`docs/policies/finding-classes.md`, Routing step 4): if `<id>` has moved past `triaged`, re-present as `new` citing `<id>`; otherwise append a dated note naming this ticket and `/cadence-archive` to `specs/<id>/problem.md` `## Notes`, record the fold once the write lands, and sync `<id>` per Routing step 5 (reporting any sync error; if the write to `problem.md` fails, record `Deferred`, never `Folded`). Note that any newly filed `specs/<new-id>/` created here is a **live ticket**, not an archived one, so it is not a dead citation.

   e. **Record final dispositions.** Populate `## Resolution` -> `Follow-ups created` using the six canonical template forms (`filed`, `duplicate`, `folded`, `none owed`, `declined`, `deferred`), plus the per-class tally clause whenever >=1 non-blocking entry was logged. Record any declined candidate with the human's stated rationale and allocate no id for it. Never leave `Follow-ups created` blank or holding a bare `none` token.

3. **Verify archival exit criteria:**
   - All ticket artifacts reside under `archive/$ticket_id/` and `archive/$ticket_id/summary.md` exists
   - `archive/$ticket_id/summary.md`'s `## Citation Dispositions` section records **one of the four valid states**:
     (1) `dead-citation-gate.sh --id $ticket_id` ran and exited `0` with zero hits (explicit none-found line recorded);
     (2) `dead-citation-gate.sh --id $ticket_id` ran, every hit was dispositioned (`REPOINT` or `EXEMPT`), the disposition table is present in `summary.md`, and the re-run exited `0`;
     (3) the classifier was absent/empty and `DEAD-CITATION-SWEEP: SKIPPED` appears on line 1 of the section body; or
     (4) the classifier was absent/empty, the operator ran the manual check, and `DEAD-CITATION-SWEEP: MANUAL` appears on line 1 of the section body followed by the manual disposition table.
     Any halt or missing disposition state means archival is **incomplete**
   - Step 2c (`--except-id $ticket_id`) executed after Step 2b exited `0` (or recorded its not-installed skip in the same section), and **every** hit it surfaced is dispositioned. Any undispositioned 2c hit or 2c halt means archival is incomplete
   - Step 2e completed and `submission.md`'s `Follow-ups created` carries one of the six valid template forms accounting for **every** candidate raised at any gate (including deferred `adr-owed` items) exactly once. If any candidate remains undispositioned, report the ticket as **NOT archived** naming that candidate
   - Every `[adr-owed]` item recorded at any gate (including items classed `adr-owed` via a Routing step 1 note) is either named by an authored ADR in `docs/ADR/` or accounted for in `Follow-ups created` — never neither (which fails archival with `archive.adr_owed.undispositioned`)
   - `CHANGELOG.md` is updated (for merged tickets); `archive/$ticket_id/metadata.yaml` carries `status: archived` and `archived_at`
   - The `archive` `stage_effort` entry is recorded and added to `actual_effort` (accumulated via `stage-effort.sh`, never recomputed from git log history)
   - Bound external tracker is synced (or logged as unavailable)

4. **Report to the operator:**
   - Final `archive/$ticket_id/` path and key summary metrics
   - Any ADRs (`docs/ADR/`) or intent insights (`docs/agentic-sdlc/intent-insights.md`) promoted
   - Citation sweep and authored-doc gate outcomes (`2b`, `2c`, `2d`) and follow-up dispositions (`2e`)
   - Any proposed `docs/flows/*.md` updates awaiting human review

## Example

```
/cadence-archive TT-6547
```

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 1 and Step 2e.c automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:9379`, 0 MB VRAM) to match archived ticket changes against `docs/flows/*.md` and deduplicate follow-up candidates against `specs/` and `archive/`.
- Steps 2b, 2c, and 2d automatically pipe `dead-citation-gate.sh` and `authored-doc-gate.sh` output exceeding 30 lines through `offload_log_triage` (`local-fast-cpu` on `:9379`, saving raw numbered output to `/tmp/agy-last-triage.log`).
- Archival summary authoring, ADR/insight promotion, and citation disposition decisions remain 100% owned by Gemini (`cadence-archivist` / Argon).
