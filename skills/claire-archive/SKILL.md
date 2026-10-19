---
name: claire-archive
description: Archive a merged ticket -- move spec artifacts to archive/, generate summary, update CHANGELOG, promote ADRs and intent insights, sync the repo's bound tracker (CLAIRE_ORG.md#tracker-binding)
argument-hint: "[ticket-id]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Archive the completed ticket `$ticket_id`. Use the `claire-archivist` subagent for the archival work.

## Prerequisites

Verify before starting:
- `specs/$ticket_id/` exists with its spec artifacts
- The ticket is in one of **exactly two** accepted entry states, and **which one admitted it decides the path**:
  - **(a) Merged.** The change proposal has been merged: `specs/$ticket_id/metadata.yaml` shows `status: merged`, or the merge commit is reachable on the integration branch (resolve `<integration-branch>` from `CLAIRE_ORG.md#branch-strategy-binding`'s `integration-branch` field — ADR_CLAIRE-0020; never hardcode a branch name). Take the normal path.
  - **(b) Terminated without merging.** `specs/$ticket_id/metadata.yaml` shows `status: cancelled` — the declared terminal-without-merge value. Take the **close-out path** described below. **This branch WINS** when a merge commit also happens to be reachable: a ticket whose record says it was cancelled is cancelled, whatever a stray branch tip says.

If the ticket is in **neither** state, stop and tell the user archival happens after merge (run `/claire-maintain` and complete the merge first) — or, if the work was abandoned, that the governed way to record that is `status: cancelled` plus a `resolution:`, not archiving an open ticket. If `specs/$ticket_id/` does not exist but `archive/$ticket_id/` does, report that the ticket is already archived.

**The close-out path (entry state (b)).** A cancelled ticket has no merge to describe, so nothing is synthesised from one:
- **HALT if no reason is recorded.** If `merged_at` is empty **and** `resolution:` is empty, absent or whitespace-only, **stop**. Report `archive.close_out_reason_absent`, naming the ticket and the missing `resolution:` field. Move nothing, generate no `summary.md`, write no CHANGELOG entry and perform no tracker projection — a refusal is louder than a warning precisely because it leaves no partial artifact behind. A ticket may not be closed out without saying why. Tell the user to record the disposition in `resolution:` (see the key's own comment in `specs/TEMPLATE/metadata.yaml`, which is the normative statement of where a cancellation reason lives) and re-run.
- **This halt is SCOPED to entry state (b) and never fires on (a).** Nothing in this repository writes `merged_at`, so genuinely merged tickets do reach `/claire-archive` with it empty and carrying no `resolution:` — `archive/BTG-113` and `archive/PI-003` are exactly that shape. A ticket admitted by (a) is never subjected to this check.
- **EXCEPTION -- a disposition already RATIFIED and already ASSERTED. Check this before doing anything else on this path.** Where the ticket's terminal disposition is already recorded in a **ratified decision entry** owned by another ticket **and** already enforced by a **live assertion** over this ticket's artifacts, the close-out **may proceed, but not on its ordinary terms**. Report `archive.closeout.disposition_already_asserted`, naming the decision entry, every asserting harness found, and what was done about each. Three conditions bind it, and all three must hold:

  1. **The ratified disposition is carried forward verbatim, never re-decided.** The close-out records a change of LOCATION and a terminal `status`; it does not restate, re-derive or re-adjudicate the verdict another ticket's gate already reached. `resolution:` takes the word that decision already used.

  2. **Every assertion that binds this ticket's artifacts is repointed in the SAME change, and keeps its teeth.** Not repointed afterwards, not left to the next run to discover. An assertion that would still pass after the move *because the artifacts it reads are gone* has not been repointed -- it has been silenced, and **a vacuous assertion is a worse outcome than the red it replaced**, because it reports green while guarding nothing.

  3. **If an assertion cannot be repointed without losing its teeth, HALT.** Report `archive.closeout.assertion_would_go_vacuous`, name the assertion, and write nothing. The close-out is not worth buying at the price of a guard that no longer guards. This is the fail-closed arm: the exception permits a move, never a silencing.

  **BOTH records must be found, and the exception fires on neither alone.** A ratified decision with no live assertion, or a live assertion with no ratified decision, takes the ordinary close-out above. One record alone is a prose promise, and this repository has the receipts for what those are worth -- the whole point of the second record is that something mechanical will notice if the first stops being true.

  The original text that the decision ratified is **never** edited to fit the new location. Where the close-out would ordinarily rewrite `problem.md`'s `## Status` block, an artifact pinned by a byte-comparison assertion takes an appended note instead, so the pinned text survives byte-for-byte and the assertion's own comparison is repointed at the new path rather than defeated.

  Worked example, and the case this clause was written from: **BTG-093**, ratified by `archive/BTG-132/decisions.md` DEC-002 cl.2 and asserted by `ci-templates/scripts/tests/btg-132-registered-surface-fixes.test.sh` S-3.1 (a byte-comparison against a pinned merge base) and S-3.2 (the directory holds `problem.md` only, with no `metadata.yaml` and no machine-readable `tier:`/`status:` field). A first attempt on 2026-09-15 moved the ticket without repointing either, which broke S-3.1 and would have made S-3.2 pass having tested nothing. That attempt was reverted, this clause written, and the move then done under it.

  **DEC-002's intent is served, not overridden.** Its clause 2 refuses a `metadata.yaml` in `specs/` because that "would insert a SUPERSEDED ticket into the implementation pipeline". Archiving removes the ticket from the pipeline *entirely*, which is that intent carried further rather than set aside -- and the close-out's `metadata.yaml` carries a terminal disposition only, never a tier or a classification, so nothing reads it as live work.

- **Preserve, do not fabricate.** Carry `resolution:` and the prose reason through to `archive/$ticket_id/` unchanged, leave `merged_at` empty, finalize no `submission.md` from a merge commit that does not exist, and synthesise no diff metrics for a diff that never happened. `status` still becomes `archived` on the move — `archived` remains the single terminal status, so no consumer that tests for it changes. Precedent: `archive/BTG-045` and `archive/BTG-061`.

## Steps

1. **Read the spec artifacts:**
   - `specs/$ticket_id/metadata.yaml` (status, links, timestamps)
   - `specs/$ticket_id/submission.md` (resolution and discussion record)

1b. **Disposition the recorded `adr-owed` items**, before the archivist delegation (PROD_CLAIRE-015). First, apply `docs/policies/finding-classes.md` Routing step 1's unlabelled halt over every undispositioned Non-Blocking entry in `## Discussion`, so a human label supplied here (including `adr-owed`) lands as a Routing step 1 note before anything below is presented. Then, from `## Discussion` (live path), present each `[adr-owed]` item with its recorded precondition and the current evidence on it (`docs/policies/finding-classes.md`, *adr-owed at archive*) -- this includes an entry classed `adr-owed` by a Routing step 1 note rather than by its own bracket token, per that step's "read it exactly as if" rule; the human chooses promote or defer-with-reason, never re-judging whether one is owed. Record each outcome as one `## Discussion` line, before step 2 runs: promotions pass to archivist step 6 as given input (never re-judged, never promoted a second time from `decisions.md`); deferrals join step 2e's candidates under the ordinary filter. No confirmation channel => every item recorded Deferred naming `followup.filing.confirmation_channel_unavailable`, carried to 2e. Zero items => nothing to do. An item ending the archive neither promoted (named by an authored ADR) nor dispositioned in `Follow-ups created` fails the exit criteria below, naming it and emitting `archive.adr_owed.undispositioned`.

2. **Delegate to the archivist agent.** The agent will:
   - Finalize `submission.md` (status, discussion, resolution from the merge commit)
   - Move `specs/$ticket_id/` to `archive/$ticket_id/`
   - Generate `archive/$ticket_id/summary.md` with metrics from git history
   - **Record the archive stage effort** — per `docs/agentic-sdlc/CLAIRE_ORG.md` "Actual Effort
     Accumulation", append an `archive` entry to `stage_effort` (`at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose `effort` is computed exactly as that
     directive prescribes (the per-stage review multiplier applied to the agent-observed archival time,
     then rounded up), and add it to the accumulated `actual_effort`. The archivist writes this as it finalizes the archived
     `metadata.yaml`; it does **not** compute `actual_effort` from git history. The sync below projects the
     new entry as its per-stage worklog.
   - Update CHANGELOG.md (Keep a Changelog format)
   - Promote ADR-worthy decisions to `docs/ADR/` and qualifying intent discoveries to `docs/agentic-sdlc/intent-insights.md`
   - Sync to the repo's bound tracker (resolved from `CLAIRE_ORG.md#tracker-binding`; fail loud if none is bound) via the **owned-items-only scoped projection** — write only items with a `specs/<id>/` (ownership ⟺ that directory exists)
   - Propose flow documentation updates (flagged for human review)
   - Clean up the feature branch

2b. **Sweep inbound citations (PROD_CLAIRE-009) — blocking when the classifier is installed.**

    The move in step 2 relocates `specs/$ticket_id/` to `archive/$ticket_id/`, which turns every
    external reference to the old path into a dead pointer. Nothing else in the lifecycle looks for
    those references, and the class has recurred three times — each time after being recorded as a
    lesson rather than embedded in tooling, which is why it recurred. That is the whole reason this
    step exists, and you can act on it without resolving any identifier.

    (Framework-repo provenance: the class is recorded as **PROD_CLAIRE-009** in
    `docs/agentic-sdlc/production-insights.md`. That register is an **adopter-owned seed** — copied
    once at adopt time and excluded from every `/claire-upgrade` merge by design — so in a repo that
    adopted before the entry was written, `PROD_CLAIRE-009` **may be absent** locally, permanently. The id is
    provenance; this step's authority does not depend on the lookup.)

    **First, test whether the classifier is installed AND non-empty:**
    `ci-templates/scripts/dead-citation-gate.sh` must exist **and** have a non-zero size —

    ```
    [ -s ci-templates/scripts/dead-citation-gate.sh ]
    ```

    An existence-only test (`[ -f ]`) is **not sufficient**: a zero-byte file is a valid shell script
    that exits 0, so step 2b would run a truncated classifier, read exit 0, and record a clean sweep
    that never happened. A classifier that is **absent, or present but zero bytes**, is one and the
    same condition: it takes the not-installed path below, and it is **never invoked**.

    **If the classifier is installed and non-empty**, run the citation check scoped to this ticket:

    ```
    bash ci-templates/scripts/dead-citation-gate.sh --id $ticket_id
    ```

    This is the **same script** the `dead-citation` CI gate row runs and the **same script** step 2c
    runs below — one classifier, three callers, never a second implementation. (The CI-row caller
    holds only where `run-gates.sh` has been copied in: it is a Beta surface adopters copy manually,
    not something adoption installs, so a repo without it has **only this caller and 2c's** — and a
    repo without the classifier has none.) It **detects, classifies and blocks; it never rewrites.**

    Read its exit status and treat 0, 1 and 2 as **three different outcomes** — the classifier's own
    documented contract (`0 clean ; 1 on a violation ; 2 on setup failure`): **0** continue, **1**
    disposition its hits below, **2** halt below.
    Any other non-zero status is handled as a setup failure rather than interpreted.

    For **each** hit, choose exactly one disposition:

    - **REPOINT** (the default) — rewrite `specs/$ticket_id/` to `archive/$ticket_id/` in place.
    - **EXEMPT** — add an entry to `ci-templates/scripts/dead-citation-exemptions.txt` naming the
      disposition class and the reason. Exemption is for a citation that *records a past state*
      (Class C historical narrative) or whose subject *is* the path (Class D), never for one that is
      merely inconvenient to fix.

    A hit reported as `NOT-A-COMMENT` is **code** — a filter argument, a variable binding, or a path
    addressed against a historical git ref. Read it and disposition it **individually**; **never**
    blanket-repoint it. A `git show <ref>:specs/<id>/...` path is *correct as written*, because it
    addresses a tree state in which that directory existed, and repointing it breaks working code.

    **Never auto-rewrite**, and never silently skip. Record every hit and its disposition in
    `archive/$ticket_id/summary.md`. **Archive does not complete while any hit is undispositioned** —
    fail loud, naming each one. A newly archived id must never be added to
    `dead-citation-baseline.txt`: that ledger is closed, shrink-only residual debt, and the gate
    rejects its growth.

    **If the classifier is installed and non-empty but exits 2 — HALT.** A setup failure is a real
    failure, not an absence: the operator asked for the gate, installed it, and it could not run.

    ```
    seam_type=SEAM_VIOLATION event_name=archive.dead_citation.classifier_setup_failed subject=ci-templates/scripts/dead-citation-gate.sh
    /claire-archive step 2b cannot complete: the dead-citation classifier is installed but could not run
    (exit <n> -- its documented setup-failure status).
    ```

    Follow the halt with the classifier's own reported cause, verbatim, and — for the commonest case,
    an absent baseline — its one-line remedy: `bash ci-templates/scripts/dead-citation-gate.sh
    --emit-baseline > ci-templates/scripts/dead-citation-baseline.txt`.

    The ticket's artifacts have already moved to `archive/$ticket_id/`; **the ticket is NOT archived**.
    Say so, and name the recovery: re-running `/claire-archive $ticket_id` **will not resume** the sweep —
    its Prerequisites report the ticket already archived once `specs/$ticket_id/` is gone and
    `archive/$ticket_id/` exists. After remediating, either restore the pre-move state with
    `mv archive/$ticket_id/ specs/$ticket_id/` and re-run `/claire-archive $ticket_id` from the top, or run
    the classifier directly, disposition its hits, and finish the remaining archival steps by hand.

    **If the classifier is absent or zero bytes — do NOT halt, do NOT silently skip, and do NOT
    invoke it.** Emit this notice, record the outcome in `archive/$ticket_id/summary.md`'s
    `## Citation Dispositions` section, and continue with the archive:

    ```
    seam_type=LINEAGE_GAP event_name=archive.dead_citation.sweep_skipped subject=ci-templates/scripts/dead-citation-gate.sh
    /claire-archive step 2b SKIPPED: the dead-citation classifier is not installed in this repository
    (ci-templates/scripts/dead-citation-gate.sh is absent or empty).

      ==> Inbound-citation rot (PROD_CLAIRE-009) is UNGUARDED for this archival. Moving specs/<id>/ to
          archive/<id>/ has just turned every external reference to the old path into a dead
          pointer, and nothing has checked for them.

    To enable the gate for future archivals, copy these three files from a CLAIRE core checkout
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

    The `-- ':!archive/'` pathspec is **load-bearing, not decoration**: step 2 has just moved this
    ticket's own artifacts into `archive/$ticket_id/`, so without it the operator's results are
    dominated by false positives — the ticket's own just-moved artifacts. It mirrors the governed
    classifier's own scope rule. **Offer** the fallback; **never run it automatically** — running it
    on the operator's behalf would make the framework perform the ungoverned sweep itself, the
    opposite of a labelled choice, and would make the declined-offer state unreachable.

    Name those three files individually, and **never** shorten the instruction to a `dead-citation-*`
    wildcard: that glob also matches core's `dead-citation-baseline.txt`, core's own residual debt
    naming core's files — installing it silences the adopter's real findings and produces a green gate
    over unswept rot. Emit the notice on **every** archival that takes this path — one notice and one
    record per ticket, never suppressed as "already warned".

    **The `## Citation Dispositions` record is one of four states, and the two non-governed ones lead
    with a fixed token.** Write the token on a **line of its own**, as the first line of the section
    body, with **nothing else on it** — no trailing parenthetical, no punctuation, no indentation.
    Exactly two lines are admissible, uppercase throughout, one ASCII space after the colon:

    ```
    DEAD-CITATION-SWEEP: SKIPPED
    DEAD-CITATION-SWEEP: MANUAL
    ```

    The human-readable expansion — including the word *ungoverned* — goes on the **next** line. Keeping
    the token line clean is what makes
    `grep -rlE '^DEAD-CITATION-SWEEP: [A-Za-z]+$' archive/*/summary.md` answer
    *"which archivals ran unguarded?"* across the whole repo. Two properties of that query are
    deliberate. It is **anchored to a whole line**, matching the rule above: an unanchored substring
    match also returns any summary whose *prose* merely mentions the token, so a fully governed archival
    that happens to discuss this mechanism is reported as unguarded. And it deliberately does **not**
    enumerate `SKIPPED|MANUAL`: matching any single alphabetic value keeps a misspelled or re-cased
    value — and any future state added under this reserved prefix — inside the answer rather than
    silently outside it. A reworded or re-cased token silently drops that archival from the answer, and
    an under-reporting audit reads as a clean fleet — which is worse than no audit. The two governed
    states deliberately carry no token; the archivist's summary template defines all four.

2c. **Sweep for citations of OTHER archived tickets (PROD_CLAIRE-015) — blocking, same condition as 2b.**

    Step 2 wrote **new files** into this tree: the ADR promotion and the intent-insight promotion.
    Those files may cite a **different**, already-archived ticket's `specs/<id>/` path — a normal,
    even encouraged, thing for a promoted decision record to do (illustrative snippets,
    cross-referenced precedent). Step 2b cannot see them: it greps for `specs/$ticket_id/` and
    nothing else, so a citation of some *other* archived id is structurally invisible to it. This
    step is that complement. It exists because the gap was not hypothetical — an archival shipped a
    promoted ADR carrying two such citations, the archive MR merged, and the integration branch went
    red for every other contributor until a follow-up fixup landed.

    Run it **only after step 2b has exited 0**, and only when the classifier is installed and
    non-empty — the **same** test step 2b uses:

    ```
    [ -s ci-templates/scripts/dead-citation-gate.sh ]
    ```

    An existence-only test (`[ -f ]`) is **not sufficient** here for the same reason it is not
    sufficient in 2b: a zero-byte file is a valid shell script that exits 0, so step 2c would read a
    clean complement sweep that never happened. A classifier that is **absent, or present but zero
    bytes**, takes the not-installed path below and is **never invoked**.

    **If the classifier is installed and non-empty:**

    ```
    bash ci-templates/scripts/dead-citation-gate.sh --except-id $ticket_id
    ```

    Same classifier, **third caller** — not a second implementation. `--except-id` is a scope
    modifier on the repo-wide ratchet: it scans every archived id **except** this one. Step 2b keeps
    sole responsibility for this ticket's own id under its own disposition contract; step 2c takes
    every other archived id under the ratchet contract. The union is total and the intersection is
    empty, so nothing is swept twice and nothing falls between them — with one recorded residual: a
    file carrying a **blanket exemption** in `dead-citation-exemptions.txt` is outside **both** calls,
    and `docs/agentic-sdlc/intent-insights.md` (written by the intent-insight promotion) is one of
    them. That exemption predates this step and is defensible for an append-only ledger; it is named
    here so the totality claim is read with its one hole visible (BTG-133 DEC-033).

    Read its exit status as the **same three outcomes** step 2b reads (`0 clean ; 1 on a violation ;
    2 on setup failure`): **0** continue, **1** disposition its hits below, **2** halt. Any other
    non-zero status is handled as a setup failure rather than interpreted.

    For **each** hit, choose exactly one disposition. Note the REPOINT target: it is the **other**
    ticket's archive directory, **not** this one's.

    - **REPOINT** (the default) — rewrite `specs/<other-id>/` to `archive/<other-id>/` in place.
    - **EXEMPT** — add an entry to `ci-templates/scripts/dead-citation-exemptions.txt` naming the
      disposition class and the reason, exactly as in 2b.

    **NEVER reach for `--emit-baseline` to clear a hit here.** The baseline is closed, shrink-only
    residual debt; regenerating it to absorb a fresh violation is precisely the growth the ratchet
    rejects, and the gate will reject it. The only two dispositions are the two above.

    Record every hit and its disposition in `archive/$ticket_id/summary.md`, in the **same**
    `## Citation Dispositions` section step 2b writes — step 2c introduces **no new audit token**.
    Attribute each row to the step that found it so a reader can tell 2b's hits from 2c's.
    **Archive does not complete while any hit is undispositioned** — fail loud, naming each one:

    ```
    seam_type=LINEAGE_GAP event_name=archive.citation_sweep.complement_undispositioned subject=<file>:<line>
    ```

    **If the classifier is installed and non-empty but exits 2 — HALT**, exactly as in 2b, under
    `archive.dead_citation.classifier_setup_failed`, and follow the halt with the classifier's own
    reported cause verbatim. A setup failure is a real failure, not an absence.

    Note that step 2c is **repo-wide**, so it can report pre-existing dead-citation debt this
    archival did not create. That is accepted deliberately: the alternative — warning without
    blocking — weakens this step from *catches* to *mentions*, which is the posture that let the
    class recur in the first place. Disposition what it finds.

    **If the classifier is absent or zero bytes — do NOT halt, do NOT silently skip, and do NOT
    invoke it.** Emit this notice, record the outcome in the same `## Citation Dispositions`
    section, and continue with the archive:

    ```
    seam_type=LINEAGE_GAP event_name=archive.dead_citation.complement_skipped subject=ci-templates/scripts/dead-citation-gate.sh
    /claire-archive step 2c SKIPPED: the dead-citation classifier is not installed in this repository
    (ci-templates/scripts/dead-citation-gate.sh is absent or empty).

      ==> Citations of OTHER archived tickets, written into this tree by this run's own ADR and
          intent-insight promotion, are UNGUARDED for this archival.
    ```

    Step 2b's not-installed notice already tells the operator how to install the gate; do not repeat
    those instructions here. One notice and one record per archival, never suppressed as "already
    warned".

2d. **Check the insights registers this archival WRITES (BTG-191) — blocking, same condition as 2b.**

    Step 2's promotion writes narrative into `docs/agentic-sdlc/intent-insights.md`, and this archival
    also appends a **`Closed by:` narrative** to the ticket's `PROD-NNN` entry in
    `docs/agentic-sdlc/production-insights.md` when one exists — recording what closed it, and against
    what it was verified. **That second write is documented here as a step for the first time, and
    documenting it is half of why this sub-step exists.** It was measured being performed at archival
    time while being described nowhere, and a write that no step describes is a write no step-scoped
    check can cover — PROD_CLAIRE-015's exact class, on the same component family that already carries four
    findings. The other half is the gate's repo-wide sweep, which is scope-independent by construction
    and is the compensating control for any writer still undescribed.

    Both registers are shipping paths — `production-insights.md` is `kind=seed` and reaches every
    adopting repository — and a single org-specific literal in either is the largest single defect
    class the 2026-09-01 baseline sweep measured.

    **First, test whether the gate is installed AND non-empty:**

    ```
    [ -s ci-templates/scripts/authored-doc-gate.sh ]
    ```

    An `[ -f ]` test is **not sufficient**, for the same reason step 2b gives: a zero-byte file is a
    valid shell script that exits 0, so this step would read a clean result from a gate that never ran.
    **Absent, or present but zero bytes, is one and the same condition** — take the not-installed path,
    record the skip in `summary.md` exactly as 2b and 2c do, and never infer a clean result from it.

    **If it is installed and non-empty**, run it against each register this archival wrote:

    ```
    bash ci-templates/scripts/authored-doc-gate.sh --path docs/agentic-sdlc/intent-insights.md
    bash ci-templates/scripts/authored-doc-gate.sh --path docs/agentic-sdlc/production-insights.md
    ```

    The **same script** the `authored-doc` CI row, `/claire-release` step 4b and the triage agent's
    PROD-entry append all run — one classifier, several callers, never a second implementation. Read
    0 / 1 / 2 as **three different outcomes**: **0** continue; **1** disposition each hit — genericise
    the offending clause, or add an anchored row to `ci-templates/scripts/authored-doc-ledgers.sh`
    anchored on that **sentence** and never on the file; **2** halt, the gate certifies nothing.

    **Never rewrite an archived entry to clear a hit.** An archived `PROD-NNN` entry is an immutable
    record; the sanctioned disposition is the ledger row. Record every hit and its disposition in
    `archive/$ticket_id/summary.md` beside 2b's and 2c's.

2e. **Disposition the owed follow-ups -- the completeness backstop.** This is the LAST phase, so it is both a filing point and the check that no earlier gate's candidate was dropped. It runs after the sweeps above and before the exit criteria below, and the `submission.md` it reads is resolved **live path first, archived path second**, because step 2's move may already have run. The sub-steps below are one line each, matching the same contract's instances in `/claire-maintain` and `/claire-review`. A `new` candidate's draft path is `specs/drafts/$ticket_id-archive-<UTC>-<N>.md` -- a single whitespace-free token rooted at `specs/drafts/` (created if absent), where `<UTC>` is `date -u +%Y%m%dT%H%M%SZ` read **once per gate run** and shared by all that run's candidates (DEC-014), and `<N>` is the candidate's ordinal in sub-step a's enumeration.

   a. **Enumerate.** Classify per `docs/policies/finding-classes.md`: a Non-Blocking entry with **no disposition yet** and no valid class token halts this step before enumeration -- an entry that already carries a disposition in `## Resolution`'s `Follow-ups created` is a legacy record and is exempt from this halt, classed or not. Emit `finding.class.unlabelled` naming the entry and request a label; an empty or unrecognized answer re-prompts exactly once, and a second miss records it Deferred naming `finding.class.unlabelled`, never classed by default. A valid supplied label is recorded per `docs/policies/finding-classes.md` Routing step 1 (entry format, operator-identity resolution, and downstream read semantics), naming this gate (`/claire-archive`). A supplied label of `adr-owed` here -- written after step 1b already ran -- is handled per `docs/policies/finding-classes.md`'s *adr-owed at archive* section: recorded Deferred naming the reason, and admitted to this step's candidates exactly as a step 1b deferral is. With no confirmation channel at all, record it Deferred naming that cause. From `## Discussion`, list every candidate -- entries classed `out-of-scope-defect`, raised at **any** earlier gate, plus every `adr-owed` item step 1b deferred -- that carries no disposition yet in `## Resolution`'s `Follow-ups created`. A candidate that already carries one is **never re-presented**, so no duplicate id is ever allocated for it. `nit`, `hygiene` and `observation` entries are never candidates. **Zero candidates** => record the none-owed disposition, with the per-class tally clause, and go on. A ticket with **no `submission.md` at all** owes nothing and is not checked: `docs/policies/change-tiers.md` gives a Trivial ticket no change-proposal record except a release cut. Record that nothing was owed and proceed.

   b. **Check the capability floor.** This step needs (i) a host runtime that can compose one command from another and (ii) a channel to collect the human's confirmation. **If either is unavailable**, take the degraded path: write the candidate's description to its draft path (declared above) and **keep** it there -- no callee runs on this path, so nothing is deleted -- then file **nothing**, allocate **nothing**, and **never simulate the callee**. Emit the named notice for the cause that fired -- `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable` -- record in `## Discussion`, per candidate, its one-line description **and the exact `/claire-triage --file-only <draft-path>` command**, which runs as written in this worktree (a human running it elsewhere writes the description to that path first), and set the field to the **deferred disposition naming** that cause. Notice and record happen together or not at all: a notice beside a clean field reads as no finding. With zero candidates there is **nothing to defer**, so record the none-owed disposition and emit no notice. When both (i) and (ii) are available this path is not taken -- it is **never a route around** the confirmation in the present-and-confirm step.

   c. **Present and confirm.** Before presenting, give each candidate its prior-work verdict (`docs/policies/finding-classes.md`, Routing step 4): search `specs/` and `archive/` for matching prior work and present exactly one of `new`, `duplicate of <id>`, or `fold into <id>`, citing the matched id; an archived-only match is cited as related context and presented as `new`. A candidate with no verdict is never shown. If the search cannot run, halt and emit `followup.dedupe.check_unavailable` naming the unreadable root -- never present a candidate as `new` by default. Show the verdicted candidates as a numbered list, one line each, and ask the human which to file. The agent **proposes**; the human **decides**. Nothing is filed without an explicit per-candidate confirmation. An empty or unrecognized answer **re-prompts exactly once**; if the second answer is also empty or unrecognized, record the remaining candidates as **deferred with that reason** -- never as an implicit decline and never as an implicit file.

   d. **File.** For each confirmed `new` candidate, invoke `/claire-triage --file-only <draft-path>` in this same operation, having FIRST written the candidate's description to `<draft-path>` verbatim, replacing any file already there -- never invoke before that write lands. **Never** call the id allocator directly and **never** hand-write a ticket's artifacts. On a **zero exit**, delete that draft (the exact path just written, nothing else). On a **non-zero exit**, halt, report the callee's error **verbatim**, keep that draft as evidence, and record the remaining candidates as deferred with that reason. A delete that fails is reported as `followup.filing.draft_cleanup_failed` and never undoes the filing. **Never fall back to scanning** the tree for a free id and never issue a bare reservation. An id already filed when a later one fails **stays filed and stays recorded** -- never delete a filed trail to undo a partial run. For each confirmed `duplicate of <id>`, file nothing. For each confirmed `fold into <id>`: re-check the target's fold eligibility (open, at `draft` or `triaged` -- `docs/policies/finding-classes.md`, Routing step 4) at write time -- a target that has moved on is re-presented as `new` with the target cited as related; otherwise append one dated line naming this ticket and gate to the target's `problem.md` `## Notes`, and only once that write lands record the fold, then run the tracker sync for `<id>` per Routing step 5 -- a failed projection is reported, never silently skipped; a failed target write is recorded Deferred, never Folded. Each newly created `specs/<new-id>/` is **live, not archived**, so it is not a dead citation and the sweeps above have nothing to flag -- but it is created after those sweeps ran, so nothing written here may be assumed covered by them.

   e. **Record.** Write every candidate's disposition into `## Resolution`'s `Follow-ups created`, in one of the six forms the template defines (filed / duplicate / folded / none owed / declined / deferred), plus the per-class tally clause whenever at least one non-blocking finding has been logged. A **declined candidate is recorded with the human's stated reason**, and **no id is allocated for** it. The field is never left empty and never carries a bare none-shaped token.

3. **Verify exit criteria:**
   - All artifacts live under `archive/$ticket_id/` and `summary.md` exists
   - `summary.md`'s `## Citation Dispositions` section records **exactly one** of the four states:
     the classifier ran and `dead-citation-gate.sh --id $ticket_id` exited 0, with every inbound
     `specs/$ticket_id/` citation dispositioned and the disposition table (or the explicit none-found
     line) present — if citations existed and no disposition table is present, report the omission
     rather than completing; **or** the classifier was not installed and the outcome is recorded
     under `DEAD-CITATION-SWEEP: SKIPPED`; **or** it was not installed, the ungoverned fallback was
     taken, and the outcome is recorded under `DEAD-CITATION-SWEEP: MANUAL` with its hand-built
     table. A **halt is never a satisfied criterion**, and a section carrying **none of the four**
     is an incomplete archive, not a passing one
   - Step 2c ran after step 2b exited 0 (or took the same not-installed path, recorded in the same
     section), and **every** hit it reported is dispositioned. A 2c hit left undispositioned is an
     incomplete archive, exactly as a 2b hit is; a 2c halt is never a satisfied criterion
   - Step 2e ran and `submission.md`'s `Follow-ups created` carries one of its six forms, with **every** candidate raised at any gate -- including a deferred `adr-owed` item -- appearing exactly once under one of them. A candidate left **undispositioned** is an incomplete archive: report the ticket as **NOT archived**, naming that candidate, rather than completing. A halt is never a satisfied criterion, exactly as for an undispositioned citation hit
   - Every `[adr-owed]` item recorded at any gate is, by archive exit, named by exactly one authored ADR or dispositioned in `Follow-ups created` -- never neither, and this includes one classed `adr-owed` only by a Routing step 1 note, which this criterion reads exactly as if it carried that bracket token. One that is neither fails the archive, naming it and emitting `archive.adr_owed.undispositioned`; this is never a satisfied criterion
   - CHANGELOG.md updated; `metadata.yaml` shows `status: archived` with `archived_at` set
   - The `archive` `stage_effort` entry is recorded and `actual_effort` reflects it (accumulated, not
     recomputed from git history)
   - External systems updated (or noted as unavailable)

4. **Report to user:**
   - Archive location and summary highlights
   - Any ADRs or intent insights promoted
   - Flow doc proposals awaiting human review, if any

## Example

```
/claire-archive TT-6547
```
