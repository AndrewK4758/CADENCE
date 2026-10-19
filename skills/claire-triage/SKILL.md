---
name: claire-triage
description: Triage an incoming issue -- classify, assess impact, check for duplicates, and create spec stub
argument-hint: "[--file-only] [--prefix <PREFIX>] [ticket-id | draft-path | problem description]"
arguments: [file_only, prefix, ticket_id]
allowed-tools: Read Glob Grep Bash Write Edit Skill
---

## Task

Triage the issue identified by `$ticket_id`. Use the `claire-triage-agent` subagent for the analysis. After the agent returns, for Medium/High tier issues with unanswered probes, offer to walk the requester through them by invoking the `claire-elicit` skill.

**Handoff mode.** `/claire-elicit` may invoke this skill to create a decomposition child (step 4d of `claire-elicit`). When the invocation carries a handoff payload (it contains `parent_ticket_id` and `suppress_elicit_offer`), follow the handoff rules in step 3 and step 5 below and return the handoff response shape documented in **## Handoff mode (decomposition children)**. A normal `/claire-triage <id-or-description>` invocation carries no such payload and behaves exactly as before.

## Steps

1. **Resolve the id-allocation binding** from `CLAIRE_ORG.md#id-allocation-binding` (§10) and the bound tracker from `#tracker-binding` (§9 — resolve it **vendor-neutrally**, never hardcode a tracker name). The §10 binding state selects the origination path:

   a. **If `specs/$ticket_id/` already exists => WARN and SKIP the seed-read** (reuse the duplicate-detection contract in step 3 — do not fork it). Emit a skip notice: "already triaged; **seed-read skipped (one-time, ADR_CLAIRE-0011 cl.2)**" and do **not** overwrite `problem.md`. The skip is auditable via the existing `originated_from_tracker:` field in `metadata.yaml`. **No `--reserve` is called** on this path — the id already exists, so no ledger id is minted. Then proceed to classification only (steps 3+), never re-seeding.

      **"Do not overwrite" means "never re-seed from the tracker"** (BTG-327) — it does not forbid the triage-agent's own classification writes: Outputs step 1's Acceptance Criteria drafting/flagging obligation (`claire-triage-agent` Outputs step 1) still fires on this path, completing whatever an earlier `--file-only` filing left as template placeholders.

   b. **Else if a real allocator is bound AND `$ticket_id` matches `id_scheme` AND `specs/$ticket_id/` does not exist => GOVERNED ONE-TIME SEED-READ** (ADR_CLAIRE-0011 cl.2):
      - **Record the selection** (resolved allocator + the id + the binding source) **before contacting the tracker** — the §9 record-before-contact precedent, so the seed-read is traceable up front.
      - Resolve the bound tracker from `#tracker-binding` vendor-neutrally and read its summary **once**.
      - Seed `problem.md`: the tracker **summary → the Problem Statement title**; the **description body → Business Context, fenced as a seed**. The field map is **minimal**. **Attachments** on a seed-read issue **are** an allowed inbound content class — the bound tracker's Import operation downloads them to `specs/{id}/attachments/` and references each from `problem.md` as Supporting Evidence (BTG-043 / OQ-1 → (a): a documented field-map extension, not a charter widening). **No acceptance criteria are mapped inbound** — a separate future ticket maps them, content-class by content-class — because mapping them now would widen the one sanctioned inbound flow past ADR_CLAIRE-0011 cl.2.
      - Write the provenance markers: a `## Source: tracker seed-read $ticket_id (non-authoritative after triage)` block in `problem.md`, and `originated_from_tracker: $ticket_id` + `seed_read_at: <ISO-8601>` in `metadata.yaml`. Set `seed_read_at` to the **exact** current wall-clock UTC time from `date -u +%Y-%m-%dT%H:%M:%SZ` (a full second-precision `YYYY-MM-DDTHH:MM:SSZ` value; never rounded, midnight, or date-only). The seed-read is **one-time and non-authoritative** — later tracker edits never flow back (AC-2).
      - **SUSPECTED UNPAIRED RESERVATION.** If the seed-read returns a summary but **no description body** (the triage-agent reports this as `idalloc.reserve.orphan_suspected`), that is the signature a reservation-created issue leaves — a `reserve` call has only a summary to give it. Surface it to the requester: name the id, state plainly that the seed will be title-only, and **ASK** whether to paste a description or proceed with the degraded seed. This is a **HEURISTIC signal, not proof** — a human can legitimately file a summary-only ticket — so it **never refuses**, **never auto-repairs**, and never alters the provenance-marker rules above. It **reads no field the seed-read does not already read**, so it **adds NO inbound flow** (**ADR_CLAIRE-0011 cl.2** is untouched; a proactive orphan audit against the tracker *would* be a second inbound flow and is out of scope).
      - **If the tracker MCP is unavailable:** fall back to asking the user to paste the description, and **write NO provenance** marker (no `## Source:` block, no `originated_from_tracker`/`seed_read_at` field). The fallback is at the *write* path, so a later retry seed-reads cleanly (F4/DEC-011) — a failed fetch is not a seed-read.

   c. **Unbound / un-substituted placeholder / `None — closed default`: MINT BY CONVENTION**, exactly as today. This is the **EXPLICIT INVERSE of §9's fail-loud** — a missing *allocator* binding is **not** an error, it is the byte-identical legacy behavior. If `$ticket_id` resembles a tracker id you MAY fetch it from the repo's bound tracker **for context only**, writing **NO provenance** (no `## Source:` block, no `metadata.yaml` provenance field). If the tracker is unreachable, ask the user to paste the description. A `$ticket_id` that does not match `id_scheme` is treated as unbound free text (OQ-2: this repo's `BL-*`/`II-*`/`SO-*` convention ids keep minting normally).

      **Minting mechanism (mint-by-convention = reserve, never scan):** when this path needs a *fresh* id (a description-first `/claire-triage`, step 2, or a decomposition child, step 3), obtain it from `.claude/skills/claire-mint/mint-id.sh --reserve <ticket-prefix>` (the prefix from §10's `id_scheme`, e.g. `PI`). The minted-id shape is byte-identical to the legacy scan output (`PI-NNN`) and **no** tracker provenance is written. Do **not** scan `specs/`+`archive/` for the highest id — that scan is the PI-031/032 race this allocator removes. **On a non-zero allocator exit (e.g. `flock` unavailable), HALT with the error verbatim; NEVER fall back to scanning** `specs/`/`archive/`/`docs/ADR/` (a silent scan fallback is a `SEAM_VIOLATION` — `idalloc.caller.silent_scan_fallback` — that reintroduces the exact race, L-1/AC-8).

2. **If `$ticket_id` is a description**, treat it as the problem statement directly. On the **unbound** path this **mints the id via `.claude/skills/claire-mint/mint-id.sh --reserve <ticket-prefix>`** (step 1c) — never by scanning; halt loud on a non-zero allocator exit (never scan-fall-back, AC-8). On a **tracker-bound** repo (§9 declares a real tracker), description-first triage still **mints the id** and generates the tracker ticket as an **outbound tracker-create projection** (ADR_CLAIRE-0011 cl.3 — tracker-first is an *additional* entry path, not a replacement); the newly-owned item carries its per-item audit line `(item id, owned?=true, action=create)`. Early visibility is **explicit** (Q4/DEC-010): the recommended next step (step 4) *suggests* `/sync-<bound-tracker>`; the human invokes it — triage never auto-fires a sync.

   **FILE-ONLY MODE (`--file-only`).** When the invocation carries `--file-only`, take this branch **instead of** steps 3-5, right here — after step 1's binding resolution and before any delegation. This mode **FILES** a ticket; it does **NOT** triage one. It never reaches step 3's triage-agent delegation, step 4's triage summary, or step 5's probe-interview offer. With the flag **absent**, nothing in this block runs and every existing `/claire-triage` path is byte-identical to before.

   - **F0. RESOLVE THE ARGUMENT, BEFORE F1 AND BEFORE ANY ALLOCATION.** On `--file-only`, if the argument is a SINGLE WHITESPACE-FREE TOKEN it MUST resolve to a readable, non-empty file, and that file's contents are recorded **VERBATIM** by F3 as the Problem Description. Write the draft first (recommended: `specs/drafts/`), then invoke `/claire-triage --file-only <draft-path>`.
     - **OTHERWISE HALT** (`claire_triage.fileonly.argument_unresolved`), naming the unresolved token and BOTH accepted forms. **NO allocator call, NO tracker contact, NO projection**, and **NO `specs/<id>/` directory** on that halt. This is F1's refuse-before-allocating polarity applied to the argument itself: the token a caller never sent cannot be told from one they did, so a token that does not open a file is refused rather than filed.
     - **ON `--file-only`, NO EARLIER STEP IS TAKEN AND THIS MODE ALLOCATES AT F2 AND NOWHERE ELSE: steps 1b and 1c are NOT TAKEN, and step 2's description-first mint and its outbound tracker-create projection are NOT TAKEN, so this mode never seed-reads and never mints outside F2.** Step 1 resolves the BINDING and nothing else on this path, and although this paragraph is nested under step 2 and follows it on the page, the branch is taken **INSTEAD OF** step 2's description handling, never after it. Stated because the guarantee above would otherwise be FALSE on a tracker-bound repository and TRUE on this one, in three places: with a bound allocator, an argument mangled into an id-shaped token naming no existing directory matches `id_scheme`, so **step 1b** would contact the tracker and write `specs/<token>/problem.md` with its provenance markers BEFORE F0 ever ran; **step 1c**'s context-only fetch contacts a tracker on the same reading; and because a `--file-only` argument **IS** a description by construction, a mangled stray word reads as one, so a linear reader could run **step 2**'s mint and create an external tracker issue titled after that stray word. F0 would then report that none of it happened. The positive rule is the one to check a future step against: **allocation happens at F2, after F1, and nowhere else.** A filing invocation has a description already; seeding one from a tracker issue the caller never named is not a degraded filing, it is a different operation.
     - **THE TEST IS A RESOLUTION TEST, NEVER A SHAPE HEURISTIC.** The refusal condition is a **FAILURE TO RESOLVE** to a readable, non-empty file, and nothing else. Nothing here refuses an argument for being SHORT, and nothing here refuses an argument for LACKING WHITESPACE ALONE: a bare token that *does* resolve is accepted, whatever its length. This is an ALLOWLIST (it must open) and never a denylist of suspicious shapes, so it cannot misfire on a legitimately short description.
     - **SCOPED TO `--file-only`.** The resolution requirement above applies ONLY when the file-only flag is present, which is the one place a single bare token is never a legitimate *description*. With the flag absent it does not run at all: `/claire-triage <id>` classification keeps step 1a's existing-`specs/$ticket_id/` resolution, which carries **NO** single-token resolution requirement, and a bare ticket id, the normal correct argument for every phase skill after triage, is never refused.
     - **A MULTI-TOKEN argument is inline prose** and FALLS THROUGH to the clauses below UNCHANGED. Emit a **DEPRECATION NOTICE** on that path: the inline free-text description on `--file-only` sunsets in **2 release cycles**, and the migration is `docs/migrations/triage-file-only-draft-path.md`. Deprecated, not removed: a multi-token value that was mangled would still pass this test, and that residual is recorded rather than argued away.
     - **EVALUATED BEFORE EVERY CLAUSE BELOW**, so **NO clause below** is ever asked a question about an argument that failed to resolve. That ordering is the safety property, not a formatting choice: F1's existing-`specs/<id>/` clause exists to protect a governed trail, and answering it about a token nobody supplied is worse than not asking it. An ID-SHAPED stray token is the case this covers: a **DIRECTORY is not a readable file**, so a bare ticket id halts HERE even where a `specs/<id>/` directory of that name exists, and the existing-trail clause is never reached.
     - **THE DEFECT STATE this clause exists to make visible** is `triage.fileonly.allocation_before_validation`: an allocation with **no recorded F0 resolution outcome** preceding it. That is what an auditor looks for after the fact, in a tree where the halt did not fire and an id exists anyway. **RECORD the F0 outcome** (accepted draft path, accepted inline prose, or the halt) **before F1.5 runs**, which is §10's record-before-contact rule applied to the argument.
   - **F1. REFUSE BEFORE ALLOCATING** — never burn an id on an input error:
     - no description supplied => **HALT** with the usage, naming `--file-only`;
     - the argument resolves to an existing `specs/<id>/` => **HALT** naming that path — the operator wants `/claire-triage <id>` (classification), not a re-file, and filing would overwrite a governed trail;
     - a handoff payload is present (`parent_ticket_id` / `idempotency_key`) => **HALT**: handoff mode owns its own allocation and duplicate-detection contract, and the two origination contracts never interleave.
   - **F1.5. SELECT THE PREFIX — BEFORE ANY ALLOCATION.** Resolve the configured prefixes from `CLAIRE_ORG.md` §9 via `ci-templates/scripts/org-binding-resolve.sh --prefixes`. Each line is `<prefix>\t<project key>\t<tracker>\t<sync skill>`. Let **N** be the number of those lines that are **not** the wildcard row — a `*` row names no prefix, so it **contributes 0 to N** (it is still emitted, last, so the menu can render it).
     - **`--prefix <PREFIX>` supplied => USE IT; no menu.** A value with no §9 row => **HALT** (`triage.fileonly.prefix_unconfigured`) naming the configured set. This is the non-interactive channel; it is never inferred.
     - **N <= 1 (INCLUDING "no per-prefix table") => NO MENU.** Byte-identical to today: the prefix is §10's `id_scheme` prefix, else the allocator sidecar's default. **Which arm you are on is resolved from YOUR §9, never assumed** — a repo that has configured no per-prefix table lands here; a repo with two or more prefix rows does not, whatever any example elsewhere in this file happens to show. A menu of one is not a choice.
     - **N >= 2 => PRESENT THE MENU**, one numbered row per configured prefix, rendered `<prefix> — <project key(s)> — <tracker> (<sync skill>)`, plus a final `<any prefix> — (no project key) — inner-source` row when a wildcard row is declared. **NO DEFAULT.** An unrecognised or empty answer **RE-PROMPTS ONCE**, then **HALTS WITH NO ID ALLOCATED** — F1's refuse-before-allocating polarity, applied to the operator's own typo.
     - **NON-INTERACTIVE CONTEXT with N >= 2 and no `--prefix` => HALT**, naming the configured set and the `--prefix` form. A delegated subagent cannot issue a menu, and inferring a selection is an ungoverned allocation.
     - **WHAT THE SELECTION BINDS.** The selected prefix is the `<ticket-prefix>` **F2** allocates under, and the binding F2 consults is **that prefix's** §10 row (`.claude/skills/claire-mint/mint-id.sh --binding-for <PREFIX>`), never a repo-wide read; **F5** projects through **that same selected prefix's** §9 row. Stated here rather than in F2 and F5 so their pre-change text is untouched -- on a repo with no per-prefix table there is nothing to select and both steps behave exactly as they always have.
     - **RECORD the selection** (prefix, project key, tracker, allocation mechanism) **BEFORE F2 runs** — §10's record-before-contact rule applied to the selection. An allocation with no recorded selection on an N >= 2 repo is `triage.fileonly.menu_bypassed`.
   - **F2. ALLOCATE** via the **existing** mechanism resolved in step 1 — the bound adapter's `reserve` on a reserve-from-tracker binding, else `.claude/skills/claire-mint/mint-id.sh --reserve <ticket-prefix>`. **FORWARD F1.5's SELECTED PREFIX to whichever allocator that resolves to**, on both limbs: as `--prefix <PREFIX>` to the adapter's `reserve` (`.claude/skills/claire-sync-jira/jira-reserve.sh --summary "<text>" --prefix <PREFIX>`, and the same argument on any other reserve-from-tracker adapter), and as the `<ticket-prefix>` argument to the mint. On a reserve-from-tracker binding whose §9 declares a PER-PREFIX table this is not optional: a reserve invoked with no prefix cannot consult the binding and HALTS on `syncjs.config.project_key_precondition_unmet`, so an unforwarded selection would fail every reservation on such a repo. Where F1.5 selected nothing to forward (its `N <= 1` arm, which includes every repo with no per-prefix table), this invocation is byte-identical to its pre-change form. **On a non-zero allocator exit, HALT with the error verbatim; NEVER fall back to scanning** `specs/`/`archive/`/`docs/ADR/` (the same `idalloc.caller.silent_scan_fallback` rule step 1c carries).
   - **F3. ALWAYS WRITE THE TRAIL**, in this same operation:
     - `specs/<id>/problem.md` from `specs/TEMPLATE/problem.md` — the description recorded **VERBATIM** as the Problem Statement/Description, the title derived from it, **Status = Draft**, and **every template probe LEFT UNANSWERED** so the later classify pass reads the true unanswered count and can offer the interview;
     - `specs/<id>/metadata.yaml` from `specs/TEMPLATE/metadata.yaml` — `id`, `title`, `status: draft` (an **existing** lifecycle value; never invent a `filed` status), `created_at` at exact second precision from `date -u +%Y-%m-%dT%H:%M:%SZ`, and `tier: ""` with a comment stating the ticket was **FILED, not triaged**. Write **no** `triaged_at`, **no** type/priority/scope/domain/observability classification value, and **no** `stage_effort` entry — filing is not the triage stage, so the triage stage's effort is recorded by the later `/claire-triage <id>` that actually classifies (the same carve-out handoff mode already carries).
   - **F4. DISCHARGE** the pairing exactly as step 3 does: assert **both** files exist; on either absent **HALT LOUD** naming `idalloc.reserve.unpaired_artifact_creation` and the allocated id. On this path the pairing holds **BY CONSTRUCTION** — the operation that allocated is the operation that wrote — and the assertion is the proof, not the mechanism.

     **RECORD THE IDENTITY MAPPING, in this same discharge.** When F2 allocated through a **tracker reserve** whose stdout payload carried a tracker-URL value (`jira_url=<url>` from `.claude/skills/claire-sync-jira/jira-reserve.sh`, and the same shape from any other reserve-from-tracker adapter), set that value into the `metadata.yaml` **F3 just wrote**, under the key the payload names. The reserve writes nothing to the repository by contract, and `CLAIRE_ORG.md#id-allocation-binding` (*Reservation pairing*) makes the pairing the **caller's** obligation — so this step is the one place that both holds the value and is already writing the file it belongs in. It matters because the recorded URL is that adapter's **sole** ticket-to-issue identity mapping: its resolve step performs **no recovery lookup by design**, so a ticket filed without it takes the **CREATE** path on its very first sync and mints a **second** issue for the ticket the reservation already created.
     - **On failure to record it, HALT LOUD** naming `syncjs.reserve.identity_unrecorded` **and the reserved issue key**, so the operator is told exactly which tracker object now exists with no repository-side mapping. Reporting success here would leave an orphan nobody knows about — the one state this whole step exists to prevent.
     - **On a MINT-BY-CONVENTION allocation there is no such value in the payload, and this is a declared NO-OP, never a halt.** An unbound or conventionally-minted repo has no identity mapping to record, so it records none and says so; the absence of a URL is the expected shape there, not a failure.
   - **F5. PROJECT:** run the designated tracker sync skill resolved from `CLAIRE_ORG.md` §9 (Tracker Binding) **once** for `<id>`, and only **after** both artifacts exist (the existing end-of-operation trigger). Where **your** §9 resolves to `None`, this is a **DECLARED NO-OP**: report the skip and its reason. Where it **resolves to a bound tracker**, the projection is **genuinely owed** and must run — resolve §9 rather than assuming the no-op. Never report a projection that did not run, and never omit the line. If a projection is attempted and **fails**, report the failure and leave the filed trail standing — never delete `problem.md`/`metadata.yaml` to "undo" it; the artifacts already exist, so the pairing holds.
   - **F6. REPORT:** the filed id, both artifact paths, `status: draft`, that **no tier was assigned because nothing was classified**, whether the projection ran or was skipped and why, and the recommended next step — `/claire-triage <id>` to classify.

   **What this mode deliberately does NOT do.** No **classification** of any kind: the **triage-agent is never delegated to** on this path, **no search of `specs/` or `archive/` for prior work occurs**, and no type, priority, scope or tier is assigned. Duplicates are found by the **later classification pass**, not at filing -- **unless** this filing was itself composed by a gate's disposition step (`docs/policies/finding-classes.md`, Routing step 4): a gate-composed filing was already prior-work-checked by the composing step before it invoked `--file-only`, so that check is not repeated here. No **new tier guard** is added here either — a filed ticket is untiered, and the downstream skills already halt fail-closed on an absent or empty `tier:` (`/claire-implement`'s Prerequisites Step 1 states the tier **cannot be resolved** and never defaults to Low; `/claire-spec`'s Step 0 and `/claire-review`'s step 2 do the same). Adding one here would be a second mechanism for a job an existing one already does. A filed ticket picked up later takes the **existing step-1a branch**: warn, skip the seed-read, do not overwrite `problem.md`, classify from there.

   **(BTG-327):** "do not overwrite `problem.md`" on that step-1a branch means never re-seed from the tracker -- classifying from there includes drafting or flagging that stub's Acceptance Criteria section, which is not an overwrite.

3. **Delegate to the triage-agent.** Pass the issue details and let the triage-agent:
   - Search the codebase for related code
   - Check `specs/` and `archive/` for prior work
   - Classify the issue
   - Create `specs/{ticket-id}/problem.md` and `specs/{ticket-id}/metadata.yaml` — when the stub is created, set `created_at` and `triaged_at` to the **exact** current wall-clock UTC time from `date -u +%Y-%m-%dT%H:%M:%SZ` (a full `YYYY-MM-DDTHH:MM:SSZ` value, never date-only, never rounded or midnight)

   **In handoff mode**, before creating anything, run **duplicate detection**: if a `specs/<id>/` already exists whose `metadata.yaml` has `decomposed_from: {parent_ticket_id}` AND a matching `idempotency_key:`, do not write anything — return `{child_ticket_id: <that id>, status: duplicate, idempotency_echo: <key>}`. This makes a re-run after a crash safe.

   **`--reserve` fires strictly AFTER duplicate detection resolves to "create" (H-2/AC-4).** The duplicate branch above returns `{status: duplicate}` **without** calling `.claude/skills/claire-mint/mint-id.sh --reserve` — so a crash-and-retry of a decomposition **never burns a ledger id** on the retry. Only the create branch below reserves the child id, via `.claude/skills/claire-mint/mint-id.sh --reserve <ticket-prefix>`, **exactly once**. Calling `--reserve` before the dedup check resolves is a `LOGIC_FAULT` (`idalloc.triage.reserve_before_dupcheck`). On a non-zero allocator exit, halt loud — never scan-fall-back (AC-8).

   Otherwise (the create branch) the child id is reserved via `--reserve` (above) and the triage-agent creates its stub, and additionally:
   - writes the child's `problem.md` with the `propagated_answers` copied **verbatim** as a `## Elicited Intent` block whose entries carry `**Source:** propagated-from-parent` (never paraphrased);
   - writes `decomposed_from: {parent_ticket_id}` and the verbatim `idempotency_key:` into the child `metadata.yaml`;
   - uses `proposed_tier_hint` as the starting tier but may re-classify from the child's own evidence (the chosen id and tier are returned to `claire-elicit`).

   **Record the triage stage effort.** After the triage-agent returns (and only when it wrote artifacts —
   skip on a handoff-mode duplicate that wrote nothing), record this stage's effort in
   `specs/{ticket-id}/metadata.yaml` per `docs/agentic-sdlc/CLAIRE_ORG.md` "Actual Effort Accumulation":
   append a `stage_effort` entry (`stage: triage`, `at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose `effort` is computed exactly as that
   directive prescribes: take your observed working time, run `ci-templates/scripts/stage-effort.sh --stage triage --observed <minutes>`
   and record the duration it prints — it resolves the per-stage review multiplier (including any
   per-operator override), multiplies, and rounds, so never restate a multiplier value or do the
   arithmetic here (floor `15m` for any non-zero computed time; a resolved multiplier of `0` records a real `0m`). **Self-check before you write**
   the entry: the rounded `effort` MUST be either `0m` or a whole multiple of 15 minutes — if it is not, the
   multiply-then-round step was skipped or mis-executed, so surface a visible diagnostic naming the
   offending value, recompute, and continue; do **NOT** halt the operation. **And** add the increment to the accumulated `actual_effort`. Do this in the same
   `metadata.yaml` edit so the end-of-operation sync below projects the new entry as its per-stage worklog.
   **In handoff mode, do not record a child's triage effort here** — an automated decomposition child's
   triage is part of the parent's `/claire-elicit` operation, not a separately-billed stage.

   **DISCHARGE THE ALLOCATION PAIRING** (`CLAIRE_ORG.md` `#id-allocation-binding`, *Reservation
   pairing* — the canonical rule; this step cites it, it does not restate it). When **this** invocation
   ALLOCATED an id — a tracker `reserve` (step 2, bound path) or `.claude/skills/claire-mint/mint-id.sh --reserve`
   (step 1c) — assert that **both** `specs/<id>/problem.md` and `specs/<id>/metadata.yaml` now exist. If
   either is absent, **HALT LOUD** naming `idalloc.reserve.unpaired_artifact_creation` and the allocated id,
   and state the two recovery options: **complete the artifacts**, or **close/abandon the reservation**.
   **NEVER continue to the sync step** — projecting a half-state leaves the tracker carrying an item the
   repo cannot govern, which is worse than stopping. This assertion **does NOT run on the handoff-mode
   duplicate branch**, which allocates nothing by design.

   **End-of-operation sync.** After the triage-agent returns with `problem.md` and `metadata.yaml`
   written, run the repo's **designated tracker sync skill** (resolved from `CLAIRE_ORG.md` §9 (Tracker Binding)) once for `{ticket-id}` to project the new ticket
   (end-of-operation trigger per `CLAIRE_ORG.md` §9, Projection triggers & sync discipline). Skip the sync when nothing was
   written (handoff-mode duplicate detection that returned an existing child without writing). **In
   handoff mode, do not sync the child here** — `/claire-elicit` owns the all-or-nothing decomposition
   transaction and projects each committed child after it commits (see `claire-elicit` step 7); syncing
   mid-handoff could project a child that a later sibling failure rolls back.
   A classifying run (not `--file-only`) also yields the `Phase: Triage` entry in
   `specs/{ticket-id}/decisions.md` — an output the triage-agent role owns (see
   `claire-triage-agent` Outputs step 3), not a write this skill performs.

4. **Report the triage summary** to the user:
   - Type, priority, scope
   - Affected code areas
   - Related prior work
   - Recommended next step
   - `Acceptance Criteria:` line (BTG-327), carried verbatim from the triage-agent's Outputs step 4 -- `drafted N` or `no ACs derivable` with its reason -- so the disposition is visible here without opening `problem.md`.

5. **Offer the probe interview (Medium/High tier only).** The triage-agent is a subagent and cannot interview the requester, so the interview happens here, in the main turn, after the agent returns. Decide whether to offer it:

   - **Handoff-mode gate (first):** if the invocation payload has `suppress_elicit_offer: true`, **skip this step entirely** — print `"Created child <id> from decomposition of <parent_ticket_id>; elicit offer suppressed."` and return the handoff response. This prevents a freshly-created decomposition child from immediately re-triggering `/claire-elicit` (infinite re-elicitation). Then stop.
   - Read the `tier:` field from `specs/$ticket_id/metadata.yaml`. Normalize it: strip surrounding quotes and whitespace, then lowercase.
   - Count the unanswered probes:
     ```bash
     grep -cF '_Answer:_ _(not yet answered)_' specs/$ticket_id/problem.md
     ```
   - **If the normalized tier is `medium` or `high` AND the unanswered count is greater than 0:** ask the requester exactly — "N probe(s) are unanswered. Walk through them now? (yes/no)" (substitute the real count for N).
     - On `yes` (case-insensitive): invoke the `claire-elicit` skill for this ticket (equivalent to `/claire-elicit $ticket_id`). The interview runs in this same turn. Do not reimplement the interview here — `claire-elicit` owns the tier gate, the idempotency check, the verbatim-capture rules, and the 5-probe cap.
     - On anything else (including `no` or empty input): skip the interview. Leave the agent's existing recommendation ("Run `/claire-elicit $ticket_id`" later) in place.
   - **If the normalized tier is `trivial` or `low`, the count is 0, or the `tier:` field is missing/unrecognized:** do not offer the interview. This matches `claire-elicit`'s own tier gate in `docs/policies/change-tiers.md` and avoids surfacing the elicit refusal message on every low-tier triage.

## Notes

- **Reuse, do not duplicate.** The interview is delegated to the `claire-elicit` skill. The triage skill only decides *whether to offer* it (Medium/High tier with unanswered probes); `claire-elicit` enforces the gating and capture rules. Keeping the offer condition here in sync with `claire-elicit`'s tier gate is deliberate — both reference `docs/policies/change-tiers.md`.
- **Why here and not in the agent.** Interviewing requires a live back-and-forth with the requester. Subagents run autonomously and cannot pause for input, so the interview must live in the skill body (main turn), not in `claire-triage-agent`.
- **The numbering authority is the binding's, not this skill's.** For description-sourced issues step 2 assigns the ticket id *before* the agent runs (see the operational steps above): reserved from the tracker while an allocator is bound, or minted from the local sequence if none is bound. The governing rule — mint-by-convention vs. reserve-from-tracker, its contingency on a declared allocator, and the triage-agent's use-verbatim / never-mint contract — is defined in `CLAIRE_ORG.md` §10 *Id Allocation Binding* (the vendor-specific key-reservation mechanics live in the bound tracker's `/sync-*` skill intake section).

## Handoff mode (decomposition children)

This is the framework's first cross-skill coordination contract. `/claire-elicit` step 4d invokes `/claire-triage` once per decomposition child, with this payload:

| Field | Req | Meaning |
|---|---|---|
| `problem_description` | yes | The child's boundary text + standalone success criterion |
| `parent_ticket_id` | yes | Written to the child's `decomposed_from:` |
| `proposed_tier_hint` | no | Starting tier; triage may re-classify from the child's own evidence |
| `suppress_elicit_offer` | yes | `true` — gates step 5 so the child does not re-trigger `/claire-elicit` |
| `propagated_answers` | no | Parent Q&A copied **verbatim** into the child as `**Source:** propagated-from-parent` |
| `idempotency_key` | yes | Opaque 12-hex; stored on the child and used for duplicate detection on re-run |
| `sequencing_rationale` | no | Present only when the size/sequencing split-test exception applies |

Return shape (one per child, back to `claire-elicit`):

| Field | Meaning |
|---|---|
| `child_ticket_id` | The allocated (or pre-existing, on duplicate) child id |
| `status` | `created` \| `duplicate` \| `refused` (e.g. a `PROJECT_INTENT` scope-check rejection) |
| `scope_check_result` | The intent scope-check outcome for the child |
| `idempotency_echo` | The `idempotency_key` echoed back, so `claire-elicit` can verify no unintended duplicate-create |

`claire-elicit` enforces **all-or-nothing**: on any `refused`/error it rolls back the `created` children and does not write the parent's `decomposed_into:`. Triage itself only creates (or detects-duplicate) one child per call; it does not write parent lineage.

## Example

```
/claire-triage TT-6547
```

Triages the issue. If it lands at Medium or High tier with unanswered probes, triage then asks whether to walk through them now; on `yes`, it runs the `claire-elicit` interview in the same turn and appends an `## Elicited Intent` section to `problem.md`.

```
/claire-triage "checkout total ignores expired coupons"
```

Triages a free-text problem statement directly. Trivial/Low tier results skip the interview offer entirely.


## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- During duplicate detection, component discovery, and insight lookups, delegate broad search to `repo-scout` or `local_semantic_embed` (`local-embed-cpu` / `nomic-embed-text` on CPU, 0 VRAM).
- Classification, scope assessment, and artifact authoring remain 100% owned by Gemini (`claire-triage-agent` on `gemini-3.8-flash-high` / Argon).
