---
name: cadence-elicit
description: Interactively guide a requester through unanswered probe questions in problem.md, recording verbatim responses in a structured "Elicited Intent" section.
argument-hint: "<ticket-id>"
arguments: [ticket_id]
allowed-tools: Read Edit Bash Skill
---

## Task

Guide the human requester through every unanswered probe question in `specs/$ticket_id/problem.md` and append their exact, unedited responses as a structured `## Elicited Intent` section.

This skill conducts the interactive session directly within the calling turn — it never delegates the conversation to a subagent, and the entire flow completes in a single turn.

## Prerequisites

Prior to presenting any prompt to the requester, verify all four preconditions in order:

1. `$ticket_id` is supplied. When omitted, halt and inform the user: `"Usage: /cadence-elicit <ticket-id>. The ticket-id is the directory name under specs/."`
2. `specs/$ticket_id/` exists on disk. When absent, halt with: `"No spec directory at specs/$ticket_id/. Run /cadence-triage $ticket_id first."`
3. `specs/$ticket_id/problem.md` exists on disk. When absent, halt with: `"No problem.md at specs/$ticket_id/problem.md."`
4. `specs/$ticket_id/metadata.yaml` exists on disk. When absent, halt with: `"metadata.yaml missing — cannot determine tier."`

## Steps

### 0. Automatic Local Discovery Pre-Pass (`local_semantic_embed` / `local-moe-hybrid`)

Before drafting candidate probe answers in step 3a or evaluating decomposition boundaries in step 4c, automatically invoke `local_semantic_embed` (`local-embed-cpu` on `:11434`, 0 MB VRAM) and/or `local-moe-hybrid` (`local-moe-hybrid` on `:11434`) once to retrieve relevant codebase symbols, adjacent system contracts, and prior insights from `docs/agentic-sdlc/intent-insights.md` and `specs/`/`archive/` without performing broad manual file reads in the primary context window. When grounding a candidate answer as `Observed` in step 3a, explicitly read the specific file coordinate surfaced by `local-moe-hybrid` in this turn.

### 1. Tier gate

Read `specs/$ticket_id/metadata.yaml` and extract the `tier:` attribute. Normalize its value by stripping surrounding quotes and whitespace and converting to lowercase, then match against the canonical tier set `{trivial, low, medium, high}`.

- When the normalized tier is `medium` or `high`: continue to step 2.
- When the normalized tier is `trivial` or `low`: halt immediately with this exact message (substituting the ticket's title-cased tier name for `{Tier}`):

  ```
  /cadence-elicit is gated to Medium and High tier changes per docs/policies/change-tiers.md.
  Ticket $ticket_id is tier {Tier}.
  If the tier is wrong, run /cadence-triage $ticket_id to re-classify, or edit metadata.yaml manually and re-run /cadence-elicit.
  ```

  Terminate without modifying any file.

- When the `tier:` attribute is absent from `metadata.yaml`, or normalizes to anything outside the four canonical values, halt immediately with:

  ```
  tier field missing or unrecognized in specs/$ticket_id/metadata.yaml.
  Expected one of: Trivial, Low, Medium, High.
  Re-run /cadence-triage $ticket_id to re-classify, or fill the tier field manually before re-running /cadence-elicit.
  ```

  Terminate without modifying any file.

### 2. Detect unfilled probes

Execute against the ticket's `problem.md`:

```bash
grep -nF '_Answer:_ _(not yet answered)_' specs/$ticket_id/problem.md
```

Record the matching line numbers and, for each match, locate:

- The closest preceding `## ...` markdown heading in `problem.md` (identifying which template section owns the probe).
- The immediately preceding `> **Probe:** ...` line (capturing the verbatim probe question text). If the `> **Probe:**` line is absent, fall back to using the section heading plus the line number as the prompt label for traceability.

When the match count is `0`, halt with: `"All probes already answered for $ticket_id. Nothing to elicit."` Terminate without modifying any file.

### 3. Idempotency check

Execute:

```bash
grep -cE '^## Elicited Intent\s*$' specs/$ticket_id/problem.md
```

Use an **anchored** pattern (`^...\s*$`) so only a genuine `## Elicited Intent` section heading is counted, ignoring inline backticked or prose references to that heading string (unanchored substring matching causes false positives — see PI-008-FA).

When the count is greater than `0`, an `## Elicited Intent` section is already present:

1. Inspect the existing `## Elicited Intent` block and compose a concise 1–2 line summary (recording date if present, number of probes answered, and number of probes skipped).
2. Display that summary, then ask the exact question: `"Overwrite the existing Elicited Intent section? (yes/no)"`
3. Await the requester's reply.
4. If the reply is `yes` (case-insensitive exact match), continue; step 5 will **replace the existing section in place**.
5. For any other reply (including `no`, empty input, or any other string), halt with: `"No changes made."` Terminate without modifying any file.

### 3a. Compose candidate answers (per unfilled probe)

For each unanswered probe identified in step 2, **prior to** displaying that probe to the requester:

1. Compose **at most 3** candidate responses for the probe, grounded in `specs/$ticket_id/problem.md` and in the actual codebase state of **the repository where this skill is executing** (informed by Step 0's `local-moe-hybrid` / `local_semantic_embed` lookup plus targeted `Read` calls). Tag each draft's grounding as `Observed` or `Inferred`. **Never tag a draft `Observed` unless** the supporting fact appears in a file explicitly read during this turn.
2. Evaluate each draft **independently** against the **step-4a sufficiency rubric row corresponding to that probe's section**. A candidate draft is **admitted if and only if** it explicitly names at least one concrete element from **each** of that row's two required bullets. This reuses the exact step-4a rubric at pre-display time — never a separate standard.
3. **Discard** any draft that fails either bullet. Never soften, generalize, or rewrite a failing draft to help it pass — **a candidate rewritten to clear a rubric bullet did not pass**.
4. When a probe's section has **no corresponding rubric row, admit zero candidates**: without an admission test, no candidate can be admitted.
5. The resulting admitted list **may contain 3, 2, 1, or 0 candidates**. Every one of those counts is valid. Never invent filler candidates to pad the list to 3.
6. **Runtime description ceiling guard.** Whenever a candidate's text **exceeds the measured `description` byte/character limit** of the active question control, **discard** that candidate outright — **never truncate, abbreviate, or paraphrase it to fit**. **Trimming a candidate to fit a UI ceiling fabricates a candidate**, just like rewriting one to pass a rubric bullet. Having fewer admitted candidates as a result is a valid outcome.
7. **Pre-declare pairwise mutual exclusions across the admitted set.** For every unordered pair `(i, j)` of admitted candidates, determine whether choosing both simultaneously would be self-contradictory. Store those conflicting ordinal pairs as a fixed declaration **in memory for this turn**, computed once here and never re-evaluated after the user responds. Whenever `k < 2`, the conflict set is empty and the post-selection conflict check is vacuous.

Each candidate expresses the requester's **intent** and **may anchor itself in concrete repository facts** — existing behaviors, file paths, or symbol identifiers — whenever those specifics make the option actionable. Keep in mind that any selected candidate is written byte-for-byte into `problem.md`, committed to git, and **projected to the repository's bound issue tracker**: **every repository detail embedded in a candidate travels with it**.

### 4. Elicit answers one probe at a time

**Global question ceiling: 7 total questions per invocation** — comprising the 5 template probes plus at most 2 adaptive follow-up questions (step 4a) across the entire run. This enforces the PI-003-F4 DEC-001 budget. Present the unanswered template probes in ascending line-number order, generating follow-ups strictly as governed by step 4a.

For each unanswered probe in template order:

**4.1 — when `k = 0`, bypass the multi-select menu control.** Because the enumerated option array requires 2 to 4 entries and `k = 0` yields only the single `No response` entry, **fall back to the standard free-text prompt** for that probe. Thus `k` may be `0, 1, 2, or 3`; all four are valid, and **falling back to free-text at `k = 0` is the intended behavior**. **Never comment on the candidate count**, and **never apologize for having zero or few candidates**.

**4.2 — when `k >= 1`, present ONE multi-select question** via the runtime's interactive question tool:

- **Question prompt**: the verbatim probe text from `> **Probe:**`, followed — only when step 3a's conflict set is non-empty — by a closing note **listing the mutually exclusive ordinal pairs**. That closing note is **skill-generated guidance, not part of the recorded probe text**.
- **Candidate options**, **one per admitted candidate** for `n` in `1..k`: set the option `label` to the positional handle `Candidate n` (**containing zero text from the candidate itself**), and place the candidate's **verbatim text** in the option's `description` field — **those exact `description` bytes are what get written to disk if selected**. Capacity is governed by step 3a's length guard.
- **Skip option**: append one option with `label` set to `No response` and a **fixed, candidate-independent** `description` string that is never written as an answer.
- The **enumerated option list** thus contains `k + 1` items, **at most four**.
- **Never attach a preview pane.** Preview panes are unsupported in multi-select mode, making `description` the sole rendered surface carrying candidate text.

Construct the option list by starting with `No response` and appending each admitted candidate `Candidate 1..k`, guaranteeing `No response` is present in every menu invocation **by construction**. The question control's built-in free-text write-in field provides the typed-answer path without occupying an enumerated array slot.

**4.5 — option label uniqueness.** **Every option label within a question call must be distinct.** Because the UI control **returns selected options solely by their `label` string**, duplicate labels would make selection lookup ambiguous. Using `Candidate 1..k` plus `No response` guarantees uniqueness by construction. If a returned label **fails to match exactly one option** sent in the prompt payload, **halt and cite the offending label** — **never guess by array index**. Although multi-select labels may arrive **in click order rather than ordinal order**, key lookup is order-independent, and **Step 5 always writes resolved options in ascending ordinal order (`Candidate 1`, `Candidate 2`, ...)**.

**Presenting a template probe consumes exactly 1 question** from the global budget of 7, regardless of whether it was shown as a menu or a free-text prompt.

Await the requester's response.

**4.3 — validate the returned selection set**, in this exact sequence — ensuring **every ambiguity rejection names the specific rule that fired**:

- **`No response` is mutually exclusive with all other choices.** **If `No response` is selected alongside any other option** — whether a `Candidate n` option or a free-text write-in — the reply is **ambiguous and invalid**: **record nothing for this probe**, and **do not write `_(skipped by requester)_`**, because converting an ambiguous click into a skip violates the non-coercion rule.
- **Simultaneous selection of any pair `(i, j)` declared conflicting in step 3a** — **ambiguous and invalid**. **Cite the conflicting ordinals in the rejection**, and **record nothing for this probe**. **Only pairs pre-declared in step 3a count as conflicts**: **never perform post-hoc semantic contradiction checks after the user responds**. Accepting an undeclared tension is the deliberate price of deterministic, non-inferred validation.

Any selection set that excludes `No response` and triggers **no pre-declared step-3a conflict pair** is **valid**, regardless of how many candidates were checked, and **every selected candidate is recorded**.

**4.4 — route the validated response.** Because the question control **returns only the selected `label` strings**, **resolve each returned label against the exact payload sent in 4.2**, then take the matching branch:

- A free-text response that **equals `__elicit_done__` after trimming leading/trailing whitespace only** — triggers early completion. Match **only the entire trimmed string, never a substring**, and use trimming **solely for routing, never altering recorded answer bytes**. Cease presenting remaining probes and proceed directly to step 5 with all answers collected so far intact. Previously resolved probes retain their entries; unpresented probes are omitted from `## Elicited Intent`.
- The `No response` **option selected by itself**, or a free-text reply whose **entire whitespace-trimmed value is `skip`** (case-insensitive), or an empty free-text reply — all three route to a single skip outcome: record `_(skipped by requester)_` for this probe. **`skip` matches only the whole trimmed string** — **never a prefix or substring**. Any free-text reply that **merely contains the word `skip` within longer prose** is a **typed answer**, recorded verbatim and untrimmed. Do **not** evaluate step 4a's rubric on a skipped probe, and generate **no follow-up questions**. Advance to the next probe.
- One or more resolved `Candidate n` options — **record each selected option's exact `description` bytes, byte-for-byte as displayed**. Never rewrap, summarize, truncate, or annotate the text. Tag the block with `**Source:** template-probe-menu`. **Do not re-run step 4a's rubric**, and generate no follow-up questions for this probe: those candidates already passed the identical rubric in step 3a.
- Any other free-text input — **a typed answer entered via the write-in field**. Record it **verbatim** (preserving all line breaks, markdown formatting, and punctuation without paraphrasing or echoing back), tag it with `**Source:** template-probe`, and **evaluate step 4a's sufficiency rubric against it**. A longer prose response that happens to contain the substring `__elicit_done__` lands here: record it verbatim and do **not** terminate early.
- An ambiguous or unresolvable selection — **re-present the probe once** per 4.6. **Never coerce an ambiguous reply into a default option or skip**.

**4.6 — single re-presentation on ambiguity.** When 4.3 flags an ambiguous response, **re-present the question exactly once within the same probe turn**. Prepend a note to the **question text naming the violated rule and the offending ordinals** — providing actionable feedback rather than a silent repeat. **Keep the option array byte-identical to the first display**, and **never re-draft or alter candidates between the first and second display**. This retry **consumes zero additional questions** against the global budget of 7. If the **second response is also ambiguous, terminate that probe without writing any entry** — record neither an answer nor `_(skipped by requester)_`, leaving `_Answer:_ _(not yet answered)_` untouched in `problem.md` so a subsequent `/cadence-elicit` run detects it again in step 2.

### 4a. Rubric-driven adaptive follow-up

Whenever step 4 captures a verbatim typed answer (`**Source:** template-probe`, non-skipped, non-empty), test it against the **sufficiency rubric** for that probe's template section. This check is strictly mechanical — ask a follow-up **if and only if** the response omits >=1 required element below that would otherwise force the spec author to guess *what to build* or *how to verify it*. Never trigger follow-ups over stylistic brevity.

This single rubric table governs **both evaluation sites**:

- **PRE-DISPLAY (step 3a)** — filters candidate drafts before presentation; failing drafts are discarded.
- **POST-CAPTURE (step 4, typed-answer branch)** — evaluates free-text user replies and is the **sole site permitted to spawn a follow-up question**.

Menu-selected answers (`template-probe-menu`) are **never** re-tested here because they already cleared this rubric during step 3a admission.

To pass, an answer must name >=1 concrete item for **each** bullet `(i)` and `(ii)` in its section's row:

| Probe section | Rubric bullets |
|---|---|
| Problem Description (observable failure mode) | (i) an observable surface where the failure manifests (log / metric / UI / ticket / dashboard); (ii) a concrete discriminator separating "broken" from "working" |
| Desired Outcome (adjacent assumptions) | (i) a specific adjacent service/system/team OR an explicit `"no dependencies"`; (ii) the exact state, contract, or behavior being relied upon |
| Acceptance Criteria (NFR) | (i) a non-functional dimension (latency / durability / observability / audit / accessibility / security); (ii) a concrete violation signal the requester would notice |
| Constraints (rejected edge cases) | (i) a specific rejected edge case OR an explicit `"none considered yet"`; (ii) the rationale for rejecting it |
| Out of Scope (what would change your mind) | (i) a concrete out-of-scope item; (ii) a specific trigger condition that would pull it in-scope OR an explicit `"no trigger"` |

When a typed answer fails one or both bullets:

- Compose **at most 2** targeted follow-up QUESTIONS addressing the missing bullet(s). Display each question prefixed with `Follow-up:`, await the user's reply, and record the response verbatim under `**Source:** agent-followup`. **Always present follow-ups as free-form questions, never as candidate menus** — step 3a composes menus exclusively for template probes.
- **Maximum depth of 1.** Never evaluate the rubric against a follow-up response — a follow-up question can never spawn a second-level follow-up.
- **Enforce the global ceiling of 7 questions.** Once the combined count of presented template probes plus follow-up questions hits 7, ask no further follow-ups and mark any remaining rubric gap via step 4b.
- If more than 2 rubric bullets fail across the session, convert only the first 2 into follow-up questions and attach the residual-gap flag (step 4b) to any remaining underspecified answers.
- **Never fabricate or infer an answer.** A follow-up is strictly a QUESTION, and its recorded answer must be the requester's verbatim reply.
- Any probe belonging to a custom section with no row in the rubric table above automatically passes without follow-ups and receives the step-4b flag so reviewers see the unrubricated section.

### 4b. Flag residual gaps

Whenever a probe response still fails its section's rubric after the depth-1 follow-up (or after hitting the 7-question ceiling), append the exact literal suffix `_(remains underspecified -- agent flagged)_` at the end of that probe's `**Answer:**` line — **following** the verbatim answer text, never replacing it. This marker is non-blocking and signals the gap to the human reviewer at the spec-approval gate.

### 4c. Detect plurality and build a split proposal

Underspecification (steps 4a/4b) and **concern plurality** require different remedies. When the elicited responses describe multiple independent problems bundled into a single ticket, asking more follow-ups will not make them converge — the right remedy is proposing a ticket split.

Evaluate the **bidirectional split test** across candidate clusters (grouping the elicited Q&A blocks alongside `## Acceptance Criteria` items in `problem.md`), using context from Step 0's `local_semantic_embed` / `local-moe-hybrid` pass to check whether candidate clusters touch overlapping code paths:

- **Propose a decomposition split if and only if** the candidate halves share **zero acceptance criteria AND zero mutation targets** (no shared file or surface modified by both).
- **Keep unified whenever** the halves share **any precondition OR any mutation target.** This deliberate asymmetry (splitting requires both absent; keeping unified requires either present) biases strongly against premature decomposition.

Decomposition guards:

- **Anti-fragmentation cap.** Propose at most **N <= 3** child tickets and discard weak boundaries. Never split coupled concerns. When considering `N = 3` children, run the bidirectional test **pairwise** across all three pairs *prior* to presenting the proposal; if any pair shares a precondition or mutation surface, merge that pair back together.
- **Size/sequencing carve-out.** Large, strictly sequential workstreams may be proposed as separate child tickets *even if they touch a shared file surface*, provided each child delivers standalone testable value and one child's output feeds the next. The canonical precedent is PI-008: FA (adaptive follow-ups) and FB (plurality decomposition) both edit `## Elicited Intent` yet were split because FA's convergence signal triggers FB's split detector. Invoke this carve-out sparingly and populate `sequencing_rationale` in the step-4d handoff payload whenever used.
- **Deterministic idempotency key.** Calculate `key = sha256(canonical(parent prose) + "|" + canonical(proposal struct)) | head -c 12` (12-char lowercase hex), where `canonical()` strips whitespace **and strips any existing `## Elicited Intent` block** — ensuring that re-running elicitation produces the identical `key` for the same parent prose and split proposal.
- **Prior rejection check.** Run `grep -E '^<!-- decomposition-rejected: '$key specs/$ticket_id/problem.md`; if it matches, the requester previously declined this exact split — skip silently to step 5.
- **Prior decomposition check.** If `specs/$ticket_id/metadata.yaml` already contains `decomposed_into:` covering these children, skip directly to step 5.

When the split test favors keeping the ticket unified (or finds no plurality), **proceed directly to step 5.**

### 4d. Propose, confirm, and hand off to triage

Execute this step only when step 4c produced a valid split proposal that has neither been previously rejected nor already executed.

1. **Display the split proposal:** render a numbered list of the `N` proposed children, showing for each child its `Title`, `Boundary`, `Standalone success criterion`, and `Inherited probe answers` (which verbatim parent Q&A entries propagate to that child).
2. **Prompt with the exact string:** `"Confirm decomposition into N child tickets? (yes / no / edit)"` (substituting the integer `N`).
   - `yes` (case-insensitive exact match) → proceed to sub-step 4 (handoff execution).
   - `edit` → allow one inline boundary adjustment from the requester, re-display the updated proposal once, and re-prompt; **on that second prompt, honor only `yes` or `no`** (treating a second `edit` as `no`).
   - Any other reply (including `no` or empty input) → proceed to sub-step 3 (record rejection).
3. **On `no`:** persist the rejection so future runs do not re-propose the same split. Under an invisible HTML comment heading `<!-- decomposition rejections -->` near the bottom of `problem.md` (creating that comment header once if absent), append `<!-- decomposition-rejected: {key} {YYYY-MM-DD} -- {one-line rationale} -->`. Proceed to step 5 without creating any child tickets.
4. **On `yes`:** first confirm that the `Skill` tool is available in this runtime; **if unavailable, abort with an explicit error prior to any triage call**, leaving the parent ticket untouched and reporting the split proposal as preserved-but-unexecuted. When `Skill` is available, invoke `cadence-triage` in **handoff mode** sequentially for each proposed child with this payload:
   - `problem_description` — the child's boundary text and standalone success criterion
   - `parent_ticket_id` — `$ticket_id` (written to the child's `decomposed_from`)
   - `proposed_tier_hint` — the parent ticket's tier (which triage may refine)
   - `suppress_elicit_offer: true` — prevents the child from recursively offering `/cadence-elicit` in triage step 5
   - `propagated_answers` — verbatim parent Q&A blocks applicable to this child (written into the child with `**Source:** propagated-from-parent`, never paraphrased)
   - `idempotency_key` — `{key}` (used by triage's crash-recovery duplicate detector)
   - `sequencing_rationale` — populated only when the size/sequencing carve-out was used
   Capture each child return object (`child_ticket_id`, `status: created | duplicate | refused`, `scope_check_result`, `idempotency_echo` — verifying `idempotency_echo == {key}`). Treat any missing or malformed return object as a failure for that child (triggering sub-step 5).
5. **All-or-nothing rollback.** If any child invocation returns `refused`, throws an error, or returns a malformed payload: **HALT** — do not invoke triage for any remaining children. **Roll back:** remove `specs/<child>/` for every child whose return status in this run was `created` (never delete pre-existing `duplicate`-status children). Leave the parent ticket's `metadata.yaml` unmodified. Report the structured failure summary `{successful, rolled_back, failed: [{child, reason}], rollback_failed?}`; if removing a `created` child directory fails, list that orphan id under `rollback_failed` and exit non-zero (DEC-002).
6. **On complete success (all children returned `created` or `duplicate`):** write `decomposed_into: [{ids}]` into the parent's `specs/$ticket_id/metadata.yaml` in a single atomic Edit.
7. Proceed to step 5 so the parent ticket also receives its complete `## Elicited Intent` section.

### 5. Compose and append the Elicited Intent section

Assemble the `## Elicited Intent` block in memory conforming to this **exact** markdown schema:

```markdown
## Elicited Intent

> Answers are recorded exactly as given — typed verbatim by the requester, or selected by the requester
> from agent-composed candidates. The `**Source:**` value on each entry says which. The skill
> never records an answer the requester did not choose.
> Ticket: $ticket_id | Date: {YYYY-MM-DD} | Skill version: v2.3

### {Source section name 1}

**Source:** template-probe
**Probe:** {verbatim probe question}
**Answer:** {verbatim requester answer} _(remains underspecified -- agent flagged)_

**Source:** agent-followup
**Probe:** {agent-generated follow-up question}
**Answer:** {verbatim requester answer}

### {Source section name 2}

**Source:** template-probe
**Probe:** {verbatim probe question}
**Answer:** {verbatim requester answer or _(skipped by requester)_}

### {Source section name 3}

**Source:** template-probe-menu
**Probe:** {verbatim probe question}
**Answer:** {the exact description text of the first candidate the requester selected}
**Answer:** {the exact description text of the next candidate the requester selected}
```

Formatting and provenance rules:

- Emit one `### {Source section name}` sub-heading **for each probe that was presented and resolved** during step 4 (whether answered, skipped, or completed early via `__elicit_done__`). Any probe **aborted after a second ambiguous reply** was presented but never resolved, so it receives **no sub-heading or block**. Probes that were already answered before this run (excluded in step 2) are omitted.
- Beneath each `### {Source section name}` heading, write one Q&A block per question. Tag the template probe with `**Source:** template-probe` when the user **typed** a free-text reply, or `**Source:** template-probe-menu` when the user **checked** one or more candidate options from the step-4 menu. Tag each adaptive follow-up question (step 4a) with `**Source:** agent-followup`, ordered chronologically beneath its parent probe. A fourth provenance tag, `**Source:** propagated-from-parent`, is written **exclusively by `/cadence-triage`** when initializing a decomposition child from a step-4d handoff; `/cadence-elicit` never writes that tag directly to the parent.
- When the user selects multiple menu candidates on a single probe, emit **one `**Answer:**` line per selected candidate** within the same Q&A block, ordered by **ascending candidate ordinal (`Candidate 1`, `Candidate 2`, ...)** — completely deterministic and **independent of the order in which the user clicked the checkboxes**. Each `**Answer:**` line must be **byte-identical to that option's `description` payload**, never merged or truncated.
- Append the residual-gap suffix `_(remains underspecified -- agent flagged)_` (step 4b) at the end of the `**Answer:**` line when the rubric remained unsatisfied; omit it whenever the rubric passed.
- Set `{YYYY-MM-DD}` to the current UTC date.
- Keep `Skill version: v2.3` as the monotonic schema version identifier. Version `v2.3` is backwards-compatible with `v2.2`, `v2.1`, `v2`, and `v1` (`v2` introduced `**Source:**` and the residual-gap marker; `v2.1` added `propagated-from-parent`; `v2.2` added `template-probe-menu` and updated the header blockquote; `v2.3` added multiple `**Answer:**` lines per block for multi-select and the presented-and-resolved heading rule); historical sections tagged `v1` through `v2.2` remain valid without migration.
- Write the assembled block to `specs/$ticket_id/problem.md` in a single atomic Edit:
  - When no `## Elicited Intent` heading existed prior to this run, append the block at the end of `specs/$ticket_id/problem.md` (preceded by a single blank line).
  - When an `## Elicited Intent` heading existed and the requester confirmed overwrite in step 3, replace the entire existing section — from `## Elicited Intent` up to the next `## ` heading or EOF — with the newly assembled block.
- Never interleave `## Elicited Intent` entries into the upper template sections of `problem.md`.

If the atomic Edit fails, surface the error and exit without partial modifications. If the user aborts prior to step 5, `problem.md` remains untouched.

### 6. Report outcome

Output this concise completion summary:

```
Appended Elicited Intent section to specs/$ticket_id/problem.md.
Probes recorded: {N}
Probes skipped: {M}
Probes unresolved: {U}
```

Where `{U}` is the count of probes terminated after two consecutive ambiguous responses — left untouched in `problem.md` so a future run can re-elicit them.

### 7. Record effort and project to the tracker (end-of-operation)

Execute this step **only when this run modified repository files** — writing `## Elicited Intent` (step 5), appending a decomposition-rejection comment (step 4d.3), or recording `decomposed_into` on the parent (step 4d.6). Bypass this step completely (no effort entry, no tracker sync) whenever the run exited without writes (step 1 tier-gate refusal, step 3 overwrite declined, or mid-run abort).

**Log elicitation effort.** Update `specs/$ticket_id/metadata.yaml` in accordance with `docs/agentic-sdlc/CADENCE_ORG.md` "Actual Effort Accumulation": append a `stage_effort` item tagged **`stage: triage`** (`at` = exact UTC completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded, midnight, or date-only) with `effort` computed via `ci-templates/scripts/stage-effort.sh --stage triage --observed <minutes>` — the script resolves the configured stage multiplier (including per-operator overrides), multiplies, and rounds up to a 15-minute increment (minimum `15m` for non-zero work; `0m` when the multiplier is `0`). **Verify before writing:** the rounded `effort` string MUST be `0m` or an exact multiple of 15 minutes; if not, emit a diagnostic naming the bad value, recompute, and continue without halting. Add the increment to `actual_effort`. Because requirement elicitation is part of intake elaboration under the `cadence-triage` lifecycle stage, its effort entry uses `stage: triage`; `/cadence-triage` logs its classification entry in step 3 *prior* to offering `/cadence-elicit`, so this elicitation entry is *additive* and `stage: triage` legitimately holds multiple entries. Log this effort strictly on the **parent** `$ticket_id` — decomposition children receive no separate elicitation effort entry.

**Project to the bound tracker.** Invoke the repository's **designated tracker sync skill** (resolved from `CADENCE_ORG.md` §9, Tracker Binding) once for `$ticket_id` at the conclusion of the operation to project the updated `problem.md`/`metadata.yaml` and post the new `stage_effort` worklog (`CADENCE_ORG.md` §9, Projection triggers & sync discipline).

Whenever a decomposition transaction committed in step 4d (all children `created` or `duplicate`), invoke that same tracker sync skill once for each committed `{child_ticket_id}`, projecting the newly created children now that the atomic transaction has succeeded.

## Constraints

- **Strictly verbatim capture.** Record the requester's exact words without paraphrasing, summarizing, normalizing, or polishing. While the skill drafts candidate options in step 3a, it **never records** any text that the requester did not explicitly type or select from the menu.
- **Zero fabricated candidates.** Admitting 2, 1, or 0 candidates is a valid result. Rewriting a draft to squeeze past a rubric bullet or length limit **fabricates a candidate** and is forbidden.
- **Byte-for-byte fidelity between menu display and disk.** Every selected menu candidate is written to `problem.md` **byte-for-byte as rendered in its option `description`**.
- **One `**Answer:**` line per selected candidate.** Multi-select responses write one separate `**Answer:**` line per chosen option in ascending ordinal order, never concatenating two candidates onto one line.
- **Hard ceiling of 7 questions.** At most 5 template probes plus at most 2 adaptive follow-ups (step 4a) per invocation (PI-003-F4 DEC-001).
- **Mechanical rubric-driven follow-ups only.** Follow-ups fire solely when triggered by the step-4a rubric table, at maximum depth 1, within the 7-question ceiling (II-006 / II-001).
- **Single-turn execution.** Prechecks, idempotency check, probe presentation, atomic file edit, and tracker sync all finish within one invocation turn.
- **Atomic file mutation.** Build `## Elicited Intent` in memory and write it in a single Edit call at step 5.
- **Medium/High tier gate.** Refuse Trivial and Low tier tickets without mutating `metadata.yaml` or `problem.md`.

## Example

```
/cadence-elicit PI-005
```

Guides the requester through unanswered probes in `specs/PI-005/problem.md` (when `PI-005` is Medium or High tier) and writes the verbatim responses into `## Elicited Intent`.

```
/cadence-elicit PI-006
```

When `PI-006` is Trivial or Low tier, halts immediately citing the tier and `docs/policies/change-tiers.md` without modifying any files.

```
/cadence-elicit PI-007
```

When `specs/PI-007/problem.md` already contains `## Elicited Intent`, displays a 1–2 line summary of the existing section and prompts for confirmation before overwriting.

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 0 automatically calls `local_semantic_embed` (`local-embed-cpu` on `:11434`, 0 MB VRAM) and/or `local-moe-hybrid` (`local-moe-hybrid` on `:11434`) to gather codebase context and prior insights before candidate composition (step 3a) and plurality split analysis (step 4c).
- Candidate rubric filtering, interactive elicitation, and verbatim capture remain 100% owned by Gemini.
