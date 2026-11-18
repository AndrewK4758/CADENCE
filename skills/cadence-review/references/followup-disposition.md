# Shared Non-Blocking Follow-Up Disposition Protocol

Used across all three human quality gates (`/cadence-review`, `/cadence-maintain`, and `/cadence-archive`) to ensure non-blocking defects discovered during any gate — across every verdict (`Approve`/`Request Changes`/`Needs Discussion`, `Accept`/`Postpone`/`Reject`, and Archival) — receive an explicit, idempotent disposition in `submission.md`.

**Gate parameters supplied by caller:**
- `<gate>`: `/cadence-review`, `/cadence-maintain`, or `/cadence-archive`
- `<draft-pattern>`: `specs/drafts/{ticket-id}-{review|maintain|archive}-<UTC>-<N>.md` (single whitespace-free path under `specs/drafts/`, created if absent; `<UTC>` captured **once per gate run** via `date -u +%Y%m%dT%H%M%SZ`; `<N>` = 1-based candidate ordinal).
- `<label-context>`: `after final code review` (Low-tier `/cadence-build` gate) or `<gate>`.

---

## Sub-steps (Execute in Strict Order)

### a. Enumerate and Verify Finding Classes
Validate every non-blocking finding against `docs/policies/finding-classes.md`:
1. Any non-blocking entry lacking **both** an existing disposition in `## Resolution` -> `Follow-ups created` and a valid class token **halts enumeration immediately** (historical entries already listed in `Follow-ups created` are exempt).
2. Emit `finding.class.unlabelled` citing `<gate>`, authoring role, and finding text; prompt the human operator for a valid class label. Re-prompt at most once on an empty/unrecognized reply; on a second miss (or with no interactive confirmation channel), record the item as `Deferred` citing `finding.class.unlabelled` (or absent confirmation channel) — never assign a default class.
3. When the human supplies a valid class token, record the classification note beside the entry in `submission.md`'s `## Discussion` per `docs/policies/finding-classes.md` Routing step 1 citing `<gate>`. (At `/cadence-archive` Step 2e.a, a newly labelled `adr-owed` entry is recorded `Deferred` with that rationale and added to candidates.)
4. Collect every un-dispositioned filing candidate lacking a disposition in `## Resolution` -> `Follow-ups created`:
   - At `/cadence-review` and `/cadence-maintain`: all `out-of-scope-defect` items (entries classed `nit`, `hygiene`, `observation`, or `adr-owed` stay in `## Discussion` untouched, with `adr-owed` counted in the tally and resolved at `/cadence-archive`).
   - At `/cadence-archive`: all `out-of-scope-defect` items plus all deferred `adr-owed` items.
   - If `submission.md` is absent (for example at `/cadence-maintain` without a change-proposal record, or a `Trivial`-tier ticket at `/cadence-archive`), halt without allocating IDs (or note "nothing owed" for `Trivial` tickets at `/cadence-archive`).
5. **When zero candidates remain**, record the canonical `none owed` disposition with the per-class tally clause (`docs/policies/finding-classes.md`, Routing step 3) and advance.

### b. Verify Runtime Capability Floor
Filing requires both (i) command-composition support to invoke `/cadence-triage --file-only` and (ii) an interactive human confirmation channel. When either capability is absent:
- Take the **degraded deferral path**: write each candidate's verbatim description to its `<draft-path>` and **leave `<draft-path>` on disk**; invoke **no** callee, allocate **no** id, and never simulate `/cadence-triage`.
- Emit `followup.filing.composition_unavailable` or `followup.filing.confirmation_channel_unavailable`, record each candidate's one-line summary and exact `/cadence-triage --file-only <draft-path>` command in `## Discussion`, and set `Follow-ups created` to the deferred disposition naming that token. Notice emission and deferral recording are atomic; skip both when zero candidates exist.

### c. Prior-Work Deduplication, Presentation, and Human Confirmation
1. Before presenting candidates, search `specs/` and `archive/` (using `local_semantic_embed` / `repo-scout` plus targeted reads) and tag every candidate `new`, `duplicate of <id>`, or `fold into <id>` (citing `<id>`; archived-only matches are cited as related context and tagged `new`).
2. If `specs/` or `archive/` cannot be read, **halt** with `followup.dedupe.check_unavailable` naming the unreadable directory — never default candidates to `new`.
3. Present the numbered list of verdicted candidates (one line per candidate) and prompt the human operator which items to file. Re-prompt at most once on an empty/unrecognized reply; on a second miss, record remaining candidates as `Deferred` citing the invalid/unanswered confirmation — never treat an invalid reply as implicit file or implicit decline. Note: read-only subagents (`cadence-reviewer`, `cadence-maintainer`) only **label** findings; this top-level skill step owns dispositioning.

### d. Execute Confirmed Filings and Folds
- **Confirmed `new`:** write verbatim description to `<draft-path>` first, then invoke `/cadence-triage --file-only <draft-path>` within the same operation (never call `mint-id.sh` or hand-write `specs/<id>/`, and never fall back to directory scanning).
  - Exit `0`: remove `<draft-path>` (emit `followup.filing.draft_cleanup_failed` if cleanup fails without undoing the filing).
  - Non-zero exit: **halt** immediately, surface the callee error verbatim, preserve `<draft-path>` as evidence, keep any previously completed filings intact, and record remaining candidates as `Deferred` citing that error.
- **Confirmed `duplicate of <id>`:** allocate nothing; record duplicate disposition citing `<id>`.
- **Confirmed `fold into <id>`:** re-verify at write time that `<id>` is still `draft` or `triaged` (`docs/policies/finding-classes.md`, Routing step 4). If `<id>` progressed past `triaged`, re-present as `new` citing `<id>`; otherwise append a dated cross-reference line naming this ticket and `<gate>` to `specs/<id>/problem.md` under `## Notes`, record `Folded`, and run the bound tracker sync for `<id>` (surface any sync error; if `problem.md` write fails, record `Deferred`).
- **Declined:** allocate zero IDs and record the human's stated rationale.

### e. Record Final Dispositions
Populate `submission.md`'s `## Resolution` -> `Follow-ups created` using the six canonical template forms (`filed`, `duplicate`, `folded`, `none owed`, `declined`, `deferred`), plus the per-class tally clause whenever `>=1` non-blocking finding was logged. Never leave `Follow-ups created` blank or write an unformatted bare `none`.
