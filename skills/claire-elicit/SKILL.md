---
name: claire-elicit
description: Walk a requester through the unfilled probe questions in their problem.md interactively, appending answers as a structured "Elicited Intent" section.
argument-hint: "<ticket-id>"
arguments: [ticket_id]
allowed-tools: Read Edit Bash Skill
---

## Task

Walk the human requester through any unfilled probe questions in `specs/$ticket_id/problem.md` and append their verbatim answers as a structured `## Elicited Intent` section.

This skill runs the conversation directly in the invoking turn — there is no subagent delegation. The conversation must complete in one turn.

## Prerequisites

Before prompting the requester, verify:

1. `$ticket_id` is provided. If missing, stop and tell the user: "Usage: `/claire-elicit <ticket-id>`. The ticket-id is the directory name under `specs/`."
2. `specs/$ticket_id/` exists. If not, stop with: "No spec directory at `specs/$ticket_id/`. Run `/claire-triage $ticket_id` first."
3. `specs/$ticket_id/problem.md` exists. If not, stop with: "No problem.md at `specs/$ticket_id/problem.md`."
4. `specs/$ticket_id/metadata.yaml` exists. If not, stop with: "metadata.yaml missing — cannot determine tier."

## Steps

### 1. Tier gate

Read `specs/$ticket_id/metadata.yaml`. Locate the `tier:` field. Normalize the value by stripping surrounding quotes and whitespace, then lowercasing. Compare against the canonical set `{trivial, low, medium, high}`.

- If the normalized tier is `medium` or `high`: proceed to step 2.
- If the normalized tier is `trivial` or `low`: stop with this exact message (substitute the actual tier name in title case):

  ```
  /claire-elicit is gated to Medium and High tier changes per docs/policies/change-tiers.md.
  Ticket $ticket_id is tier {Tier}.
  If the tier is wrong, run /claire-triage $ticket_id to re-classify, or edit metadata.yaml manually and re-run /claire-elicit.
  ```

  Exit without writes.

- If the `tier:` field is missing from metadata.yaml, or its value does not normalize to one of the four canonical values, stop with:

  ```
  tier field missing or unrecognized in specs/$ticket_id/metadata.yaml.
  Expected one of: Trivial, Low, Medium, High.
  Re-run /claire-triage $ticket_id to re-classify, or fill the tier field manually before re-running /claire-elicit.
  ```

  Exit without writes.

### 2. Detect unfilled probes

Run, against the per-ticket problem.md:

```bash
grep -nF '_Answer:_ _(not yet answered)_' specs/$ticket_id/problem.md
```

Collect the line numbers and, for each match, determine:

- The nearest preceding `## ...` heading in problem.md (the section the probe lives in).
- The immediately-preceding `> **Probe:** ...` line (the verbatim probe question text). If that line is missing for some reason, use the section heading alone as the probe label and include the line number in the prompt for traceability.

If the match count is 0, stop with: "All probes already answered for $ticket_id. Nothing to elicit." Exit without writes.

### 3. Idempotency check

Run:

```bash
grep -cE '^## Elicited Intent\s*$' specs/$ticket_id/problem.md
```

This match is **anchored** (`^...\s*$`) so it counts only a real `## Elicited Intent` heading, not inline prose mentions of the string (e.g. a problem.md that discusses the schema in backticks). A bare substring match here is a known false-positive — see PI-008-FA.

If the count is greater than 0, an Elicited Intent section already exists:

1. Read the existing section and produce a brief 1-2 line summary (date if present, count of probes recorded, count skipped).
2. Print the summary, then ask exactly: "Overwrite the existing Elicited Intent section? (yes/no)"
3. Wait for the requester's response.
4. If the response is exactly `yes` (case-insensitive), proceed. The existing section will be **replaced in place** in step 5.
5. If the response is anything else (including `no`, empty input, or any other token), stop with: "No changes made." Exit without writes.

### 3a. Compose candidate answers (per unfilled probe)

For each unfilled probe detected in step 2, **before** that probe is presented:

1. Draft **at most 3** candidate answers to that probe, grounded in this ticket's problem.md prose and in the state of **the repository this skill is running in**. Label each candidate's grounding Observed / Inferred. **Never label a draft Observed unless** the fact is present in a file that was read in this turn.
2. Apply the **step-4a rubric row for that probe's own section** to each draft **independently**. A draft is **admitted if and only if** it names at least one item from **each** of that row's two bullets. This is the same rubric, applied earlier — never a second one.
3. **Discard** every draft that fails. Never reword, soften, or generalize a draft in order to clear a bullet — a candidate that **had to be rewritten to pass did not pass**.
4. If the probe's section has **no rubric row, admit nothing**: with no admission test there is no admitted candidate.
5. The admitted set **may hold 3, 2, 1 or 0 candidates**. All four are correct outcomes. Never fabricate a candidate to reach 3.
6. **Length guard.** If a candidate's text **exceeds the measured `description` ceiling** for the running runtime, **discard** it — **never shorten, truncate or re-word it to fit**. A candidate **trimmed to clear a ceiling is a fabricated candidate**, exactly as one reworded to clear a rubric bullet is. The admitted set **may therefore hold fewer candidates, which is a correct outcome**.
7. **Declare pairwise conflicts over the admitted set.** For each unordered pair `(i, j)` of admitted candidates, record whether selecting both would be self-contradictory. The declaration is a set of ordinal pairs **held in the turn**, composed here and never re-derived later. When `k` is below 2 the declaration is empty and the later check is vacuous.

A candidate states the requester's **intent**, and **may ground itself in the current state of the repository** — an existing behavior, a path, an identifier — where that grounding is what makes the candidate concrete enough to choose between. Be aware that a selected candidate is written verbatim into problem.md, which is committed and **projected to the repository's bound tracker**: **whatever grounds the candidate travels with it**.

### 4. Elicit answers one probe at a time

**Global question budget: 7 total questions per invocation** — the 5 template probes plus up to 2 adaptive follow-ups (step 4a) across the whole session. This is the PI-003-F4 DEC-001 ceiling; it is not a new constant. Ask the verbatim template probes detected in step 2; generate follow-ups only as governed by step 4a.

For each unfilled probe in template (line-number) order:

**4.1 — when `k = 0`, do not present the control.** The enumerated option array admits 2 to 4 entries, and at `k = 0` it would hold one, below that minimum: **fall through to the pre-existing free-form prompt** for that probe. `k` is therefore 0, 1, 2 or 3; all four are correct outcomes, and a **fall-through at `k = 0` is a correct presentation**. **Do not comment on how many candidates were found**, and **do not apologize for a short list**.

**4.2 — otherwise present ONE multi-select question** through the runtime's native question control:

- Question text: the verbatim probe text from the `> **Probe:**` line, plus — only when step 3a's declaration is non-empty — a closing note **naming the conflicting ordinals**. That note is **skill-authored and is not part of the probe**.
- Options, **one per admitted candidate**, for `n` in `1..k`: the `label` is the positional handle `Candidate n` and **carries no text derived from the candidate**; each option's `description` carries that candidate's **verbatim text**, and **that field's bytes are what is recorded**. That field's capacity is **established by measurement, never assumed** — see step 3a's length guard.
- Plus one option labelled `No response`, whose `description` is a **fixed, candidate-independent** string that is never recorded as an answer.
- The **enumerated option array** therefore carries `k + 1` entries, **at most four**.
- **No branch supplies a preview.** A **preview pane is unavailable under multi-select**, so `description` is the only rendered field carrying candidate text.

The enumerated array **is** the single option `No response`; each admitted candidate option is **appended** to it, so `No response` is present in every presented case **by construction** — not by remembering to add it. The control's own appended free-text choice carries the typed-answer route and is **not** an enumerated array entry.

**4.5 — label uniqueness.** **Every option label in one call must be unique.** The **return identifies a selection only by its label**, so a duplicated label makes the lookup ambiguous and the skill cannot know which candidate was chosen. `Candidate 1..k` plus `No response` satisfies this by construction. If a returned label **does not resolve to exactly one option** in the payload, **halt and name it** — **never guess by position**. The selected labels arrive **in click order, not the declared order**, but resolution is a unique-key lookup and so **does not depend on the order the selections were returned in**; **each resolved option records its own `description` bytes**.

**Presenting a probe costs exactly one question** against the global budget of 7, exactly as presenting a bare prompt does today. The number of candidates does not change that accounting.

Wait for the requester's answer.

**4.3 — validate the returned selection set**, in this order — and **every ambiguity refusal names which rule fired**:

- **`No response` is exclusive.** **Returned with any other selection** — a candidate option or the free-text choice — the response is **ambiguous and invalid**: **nothing is recorded for that probe**, and **no `_(skipped by requester)_` marker is written**, because recording a skip the operator did not choose is the coercion this skill forbids.
- **Any pair step 3a declared conflicting, both selected** — **ambiguous and invalid**. The **refusal names the offending ordinals**, and **nothing is recorded for that probe**. **A conflict not declared in step 3a is not a conflict**: **never judge at this point whether two selected texts contradict each other**. A semantically opposed pair that was not declared is accepted through, which is the priced cost of refusing to infer.

A selection that omits `No response` and carries **no declared conflicting pair** is **accepted**, however many candidates it holds, and **every selected candidate is recorded**. The refusal is **bounded by the declaration, never by judgement**.

**4.4 — then route.** The control **returns the selected options' `label` text only** — not the `description` bytes and not an index. **Resolve each returned label against the skill's own record of the payload it sent**, then:

- a free-text value that **trims, on surrounding whitespace only, to exactly** `__elicit_done__` — the early finish, unchanged and **accepted through the control's appended free-text choice**. The match is on the **whole value and never on a substring**, and the **trim informs routing only and never the recorded bytes**. Stop presenting further probes and jump to step 5 with the in-memory accumulator intact. Probes already presented keep their answers; not-yet-presented probes are simply not included in the section.
- the `No response` **option selected alone** / `skip` (case-insensitive) / an empty free-text value — one branch, not two: record `_(skipped by requester)_` for this probe. The **`skip` spelling is matched on the whole value**, after trimming surrounding whitespace only, and takes this branch **only when the trimmed value is exactly `skip`** — **never as a substring or a prefix**. A value that **merely contains the word `skip`** inside longer prose is a **typed answer**, recorded verbatim and untrimmed; as with the early-finish sentinel, the trim informs routing only and never the recorded bytes. Do **not** run the rubric (step 4a), and **no follow-up is generated for that probe**. Move to the next probe.
- a resolved candidate option — **record that option's `description` bytes**, **exactly as displayed, byte for byte**. Do not truncate, re-render, re-wrap or annotate it. The entry carries `**Source:** template-probe-menu`. **Do not re-run step 4a against it**, and no follow-up is generated for that probe: it was admitted by the same rubric in step 3a, and running the gate twice is a **second mechanism for one job**.
- any other free-text value — **a typed answer, taken from the control's own appended free-text choice**. Record it **verbatim** (line breaks, Markdown, punctuation preserved; no paraphrase, no summary, no normalization, no echo-back), **then run step 4a against it** exactly as today. A typed answer keeps `**Source:** template-probe`. A value that **merely contains the early-finish literal** inside longer prose is such an answer: it is **recorded verbatim and untrimmed**, and the run **does not finish early**.
- An ambiguous or unresolvable response — **re-present the question once**. **Never coerce an unrecognized or ambiguous response to a default** choice.

**4.6 — the ambiguity remedy.** On an ambiguous response, **re-present exactly once, within the same question**, and no more. The re-presented **question text names the rule that fired and the offending ordinals** — that is **new information, not a repetition**. **Only the question text changes**: the **option payload is byte-identical to the first presentation**, and you **never re-compose candidates between presentations**, because different text under the same ordinals is a mis-binding by another name. The **re-presentation costs no additional question** against the global budget of 7, which is unchanged. A **second ambiguous response terminates the probe with no entry written** — no answer, and **no `_(skipped by requester)_` marker**. That probe's `_Answer:_ _(not yet answered)_` line in problem.md is **left untouched**, so a later run detects it again at step 2.

### 4a. Rubric-driven adaptive follow-up

After capturing a verbatim (non-skipped, non-empty) answer in step 4, evaluate it against the **sufficiency rubric** for that probe's section. The rubric is mechanical — fire a follow-up **iff** the answer fails ≥1 bullet that would force the spec author to guess about *what is built* or *how it is verified*. Do not fire on merely stylistic vagueness (that is a rubber-stamp anti-pattern).

This rubric has **two call sites and one definition**:

- **PRE-DISPLAY (step 3a)** — applied to each composed candidate. A failing candidate is discarded and never offered.
- **POST-CAPTURE (step 4, the `[T]` branch)** — applied to a typed answer, as it always has been, and it is the **only call site that can fire a follow-up**.

A menu-selected answer is **not** re-evaluated here; it cleared this same rubric at admission.

A spec-usable answer must name ≥1 item from **each** row:

| Probe section | Rubric bullets |
|---|---|
| Problem Description (observable failure mode) | (i) a surface where failure is observable (log / metric / UI / ticket / dashboard); (ii) a discriminator between "broken" and "working" |
| Desired Outcome (adjacent assumptions) | (i) a named adjacent system/team OR explicit "no dependencies"; (ii) what is being counted on (state, contract, behaviour) |
| Acceptance Criteria (NFR) | (i) an NFR dimension (latency / durability / observability / audit / accessibility / security); (ii) a violation signal the requester would notice |
| Constraints (rejected edge cases) | (i) a named rejected edge case OR explicit "none considered yet"; (ii) the rationale for rejection |
| Out of Scope (what would change your mind) | (i) a named out-of-scope item; (ii) a trigger that would move it in-scope OR explicit "no trigger" |

When the rubric fails:

- Generate **at most 2** follow-up QUESTIONS targeting the failed bullets. Print each like a probe, labelled `Follow-up:`, and wait for the answer. Record it verbatim. A **follow-up is presented as a free-form question, not as a menu** — step 3a composes candidates for template probes only — and its answer carries `**Source:** agent-followup`.
- **Depth 1 only.** Never run the rubric against a follow-up answer — a follow-up never spawns another follow-up.
- **Respect the global budget of 7.** When total questions asked (template + follow-up) reaches 7, stop generating follow-ups; flag any remaining gap per step 4b.
- If >2 rubric bullets fail, turn only the top 2 into questions; fold the rest into the residual-gap flag (step 4b).
- **Never record an answer the requester did not give.** Do not paraphrase, summarize, normalize or infer an answer: a follow-up is a QUESTION, and its answer is the requester's verbatim words. Composing candidates for the step-3a menu is the one place this skill drafts answer text, and such a draft becomes a recorded answer only when the requester selects it from the menu.
- A probe section with no rubric row (e.g. a future probe added to the template without a rubric) auto-passes — no follow-up — and is flagged per step 4b so the gap is visible.

### 4b. Flag residual gaps

If, after the depth-1 budget is spent (or folded per step 4a), a probe's answer still fails its rubric, append the literal marker `_(remains underspecified -- agent flagged)_` to that probe's answer line — **after** the verbatim answer, never replacing it. This does not block: the human spec-approval gate is the consumer of the flag.

### 4c. Detect plurality and build a split proposal

Vagueness (steps 4a/4b) and **plurality** are different failures. When the answers describe several genuinely separate problems, the remedy is not more follow-ups — it is to propose splitting the ticket into smaller strong-signal problems. The signal: a probe whose answer will not converge under follow-ups because it spans two distinct concerns.

Apply the **bidirectional split test** to the candidate halves (cluster the Q&A entries + the `## Acceptance Criteria` bullets in problem.md):

- **Propose a split iff** the two halves share **no acceptance criteria AND no mutations** (no file/surface both would write).
- **Keep together if** they share **a precondition OR a mutation.** The asymmetry (split needs both-absent; keep needs either-present) deliberately biases toward *not* splitting.

Guards:

- **Over-split resistance.** Cap the proposal at **N ≤ 3** children; drop weak boundaries. Coupled concerns are never split — this is the named anti-goal. When N=3, apply the bidirectional test **pairwise** across every pair of candidate children *before* showing the proposal; if any pair shares a precondition or a mutation, drop the coupled pair (merge them back).
- **Size/sequencing exception.** Substantial, sequence-dependent facets may be proposed as separate problems *even when they share a surface*, when each carries independent implementation work and one detects/feeds the other. The canonical example is PI-008 itself: FA (follow-ups) and FB (decomposition) share the `## Elicited Intent` surface yet were specified separately because FA's convergence detector is FB's split trigger. Use this exception sparingly; record the `sequencing_rationale` in the handoff payload when it applies.
- **Idempotency key.** Compute `key = sha256(canonical(parent prose) + "|" + canonical(proposal struct)) | head -c 12` (lowercase hex), where `canonical()` strips whitespace **and the `## Elicited Intent` section** — so FA's re-appended section does not invalidate the key across re-runs. The same parent + same proposal always yields the same key.
- **Prior rejection.** If `grep -E '^<!-- decomposition-rejected: '$key specs/$ticket_id/problem.md` matches, the requester already declined this split — skip silently to step 5.
- **Prior split.** If the parent metadata.yaml already records `decomposed_into:` for these children, skip to step 5.

If the test says keep-together, or no candidate is found, **skip to step 5 unchanged.**

### 4d. Propose, confirm, and hand off to triage

Only reached when step 4c produced a split proposal that is neither previously-rejected nor already-done.

1. **Print the proposal:** a numbered list; for each of the N children print `Title`, `Boundary`, `Standalone success criterion`, and `Inherited probe answers` (which verbatim parent answers would propagate to it).
2. **Prompt exactly:** "Confirm decomposition into N child tickets? (yes / no / edit)" (substitute the real N). `yes` (case-insensitive exact) → item 4 below (hand off). `edit` → re-show once after the requester's inline boundary adjustment, then re-prompt; **on that second prompt only `yes`/`no` are honored** (a second `edit` is treated as `no`). Anything else (including `no` or empty) → item 3 below (record rejection; conservative bias).
3. **On `no`:** record the rejection so a re-run does not re-propose. Append, under a fixed accumulator heading `<!-- decomposition rejections -->` (an HTML comment, created once near the bottom of problem.md if absent — kept invisible so it adds no visual noise), the line `<!-- decomposition-rejected: {key} {YYYY-MM-DD} -- {one-line rationale} -->`. Then continue to step 5. **Do not** create any tickets.
4. **On `yes`:** first verify the `Skill` tool is available; **if it is not, exit with an explicit error before any triage call** — the parent is NOT mutated and the proposal is reported as preserved-but-not-executed. Otherwise, for each child, invoke the `Skill` tool (`claire-triage`) in **handoff mode**, passing the payload:
   - `problem_description` — the child's boundary text and success criterion
   - `parent_ticket_id` — `$ticket_id` (becomes the child's `decomposed_from`)
   - `proposed_tier_hint` — the parent's tier (triage may re-classify)
   - `suppress_elicit_offer: true` — the child must NOT re-trigger triage's step-5 elicit offer
   - `propagated_answers` — the verbatim parent Q&A relevant to this child (written into the child as a `**Source:** propagated-from-parent` block — never paraphrased)
   - `idempotency_key` — `{key}` (triage's duplicate-detection uses it on re-run)
   - `sequencing_rationale` — only when the size/sequencing exception applies
   Collect each return (`child_ticket_id`, `status: created | duplicate | refused`, `scope_check_result`, `idempotency_echo` — verify the echo matches `{key}`). A malformed/missing return is treated as a failure for that child (step 5).
5. **All-or-nothing.** If any child returns `refused`, errors, or returns a malformed result: **STOP** — do not invoke triage for the remaining children. **Roll back:** delete `specs/<child>/` for every child whose status was `created` this run (`duplicate`-status children are NOT rolled back). Do **not** mutate the parent. Surface the failure list `{successful, rolled_back, failed: [{child, reason}], rollback_failed?}`; if a rollback delete itself fails, name the orphan ticket-id under `rollback_failed` and exit non-zero (loudest-possible failure, per DEC-002).
6. **On all-success (every child `created` or `duplicate`):** append `decomposed_into: [{ids}]` to the parent metadata.yaml in one Edit.
7. Continue to step 5 (the parent still gets its own Elicited Intent section).

### 5. Compose and append the Elicited Intent section

Compose the section text in memory using this **exact** schema:

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

Rules for the section:

- One `### {Source section name}` sub-heading **per probe that was presented and resolved** in step 4 (answered, skipped, or escaped via `__elicit_done__`). A probe **terminated on ambiguity** was presented but resolved by none of those three, so it gets **no block**. Probes that were already answered in the template (not in the unfilled set detected in step 2) are not included in the section.
- Under each section heading, emit one Q&A block per question. The template probe carries `**Source:** template-probe` when the requester **typed** the answer and `**Source:** template-probe-menu` when the requester **selected** an agent-composed candidate from the step-4 menu. Each adaptive follow-up (step 4a) carries `**Source:** agent-followup`, in the order asked, beneath its parent probe. A fourth value, `**Source:** propagated-from-parent`, is written **only by triage** when it copies a parent's verbatim answers into a decomposition child (step 4d handoff); `/claire-elicit` itself does not emit it.
- A multi-select response records **one `**Answer:**` line per selected candidate**, inside one Q&A block, in **ascending option-ordinal order** — deterministic and **independent of the operator's click order**. Each line is **byte-identical to the `description` payload supplied for its own option**; lines are **never merged into one another and never truncated**.
- The residual-gap marker `_(remains underspecified -- agent flagged)_` (step 4b) is appended to the verbatim answer line; it never replaces the answer. Omit it when the rubric passed.
- `{YYYY-MM-DD}` is today's date.
- `Skill version: v2.3` is the monotonic version of this skill's schema. It is additive over v2.2/v2.1/v2/v1 (v2 added the `**Source:**` line per Q&A and the residual-gap marker; v2.1 documents the `propagated-from-parent` source value; v2.2 adds `template-probe-menu` and rewords the provenance blockquote, which under v2.1 and earlier asserted that no answer was agent-composed; v2.3 adds more than one `**Answer:**` line per Q&A block, for a multi-select response, and the presented-and-resolved block rule); sections written as `Skill version: v1`, `v2`, `v2.1` or `v2.2` remain valid records and are never rewritten by migration. Bumping the version is a deliberate schema change.
- Append the section atomically using a single Edit:
  - If no `## Elicited Intent` section existed before this run, append the new section at the end of `specs/$ticket_id/problem.md` (preceded by one blank line for separation).
  - If an `## Elicited Intent` section existed and the requester confirmed overwrite in step 3, replace the entire existing block — from the `## Elicited Intent` heading through the next `##` heading or EOF — with the new section.
- Do not interleave Elicited Intent content with existing problem.md content. The section is a contiguous block.

The Edit is atomic. If it fails, report the error and exit without partial writes. If the requester aborts mid-conversation (before step 5), problem.md is unchanged.

### 6. Report outcome

Print a short summary:

```
Appended Elicited Intent section to specs/$ticket_id/problem.md.
Probes recorded: {N}
Probes skipped: {M}
Probes unresolved: {U}
```

`{U}` counts probes terminated on a second ambiguous response — presented, resolved by nothing, and left re-elicitable.

### 7. Record effort and project to the tracker (end-of-operation)

This step runs only when the invocation **made writes** — an Elicited Intent section (step 5), a
decomposition-rejection marker (step 4d.3), or a parent `decomposed_into` (step 4d.6). Skip it entirely
(no recording, no sync) when the run made no writes — a tier-gate refusal (step 1), overwrite declined
(step 3), or an abort before step 5 — there is nothing to record or project.

**Record the elicit effort.** On `specs/$ticket_id/metadata.yaml`, per `docs/agentic-sdlc/CLAIRE_ORG.md`
"Actual Effort Accumulation": append a `stage_effort` entry labelled **`stage: triage`** (`at` = the exact stage-completion time from `date -u +%Y-%m-%dT%H:%M:%SZ`, never rounded/midnight/date-only) whose
`effort` is computed exactly as that directive prescribes: take your observed working time for this
elicitation, then run `ci-templates/scripts/stage-effort.sh --stage triage --observed <minutes>` and
record the duration it prints — it resolves the per-stage review multiplier (including any per-operator
override), applies it, and rounds, so never restate a multiplier value or perform the arithmetic here
(floor `15m` for any non-zero computed time; a resolved multiplier of `0` records a real
`0m`). **Self-check before you write** the entry: the rounded `effort` MUST be either `0m` or a
whole multiple of 15 minutes — if it is not, the multiply-then-round step was skipped or mis-executed, so
surface a visible diagnostic naming the offending value, recompute, and continue; do **NOT** halt the
operation. Add the increment to the accumulated `actual_effort`. Elicitation is intake elaboration under the `claire-triage` stage, so it is labelled `claire-triage`;
`/claire-triage` records its own classification increment in its step 3 — **before** it offers `/claire-elicit` — so this
interview increment is *additive*, and the `claire-triage` stage legitimately carries more than one entry (see the
directive). This applies whether `/claire-elicit` was offered by `/claire-triage` or invoked directly (`/claire-elicit <id>`).
Record it on the **parent** `$ticket_id` only — decomposition children get no elicit increment (their
triage is handoff-suppressed).

**Then sync.** Run the repo's **designated tracker sync skill** (resolved from `CLAIRE_ORG.md` §9 (Tracker Binding)) once for `$ticket_id` now — at the end of the operation — to
project the change and post the new `stage_effort` entry as its per-stage worklog (end-of-operation trigger per `CLAIRE_ORG.md` §9, Projection triggers & sync discipline).

If a decomposition committed in step 4d (every child `created`/`duplicate`), also run that sync skill
for each committed child `{child_ticket_id}`, so the newly-created child tickets
are projected once the all-or-nothing transaction has committed (triage deliberately does not sync them
mid-handoff).

## Constraints

- **Verbatim answers only.** Capture the requester's words exactly. Do not paraphrase, summarize, normalize, or "improve" answers. This applies to template-probe answers, menu selections and follow-up answers alike: the skill may **offer** candidate answers it drafted (step 3a), but it **never records** an answer the requester did not type or select.
- **Never fabricate a candidate.** Fewer than three candidates, including none, is a correct outcome. A candidate **reworded until it clears a rubric bullet is a fabricated candidate**.
- **Displayed text is recorded text.** A selected candidate is **recorded byte for byte as it was displayed**. Any divergence between what the operator saw and what problem.md records **is a defect, not a formatting choice**.
- **One answer line per selected candidate.** A multi-select response records **one answer line per selected candidate**, each **byte-identical to the `description` payload supplied for that option**. The guarantee applies to every selected candidate individually; two are never merged into one.
- **Global budget of 7 questions.** The 5 template probes plus up to 2 adaptive follow-ups (step 4a), total, per invocation. This is the PI-003-F4 DEC-001 ceiling; changing it requires a deliberate edit and a version bump.
- **Rubric-driven follow-ups only.** Adaptive follow-ups are generated solely by the step-4a rubric, at depth 1, within the global budget. Do not generate free-form or open-ended "dig deeper" questions. (This reverses the original "no follow-up questions" rule; see II-006, which partially supersedes II-001 — the "auto-suggested, not auto-invoked" half of II-001 remains in force.)
- **One turn.** Validation, idempotency check, prompts, write, and summary all complete in one invocation.
- **Atomic write.** Compose the Elicited Intent section in memory; write it with one Edit at the end. If the requester aborts mid-conversation, problem.md is not modified.
- **Tier-gated.** Refuse Trivial and Low tier tickets. The tier field is read from metadata.yaml; it is not modified by this skill.

## Example

```
/claire-elicit PI-005
```

Walks the requester through any unfilled probes in `specs/PI-005/problem.md` (provided PI-005 is Medium or High tier), then appends an `## Elicited Intent` section recording the answers verbatim.

```
/claire-elicit PI-006
```

If PI-006 is Trivial or Low tier, refuses with a message naming the tier and citing `docs/policies/change-tiers.md`. No file changes.

```
/claire-elicit PI-007
```

If `## Elicited Intent` already exists for PI-007, summarizes the existing contents and asks whether to overwrite. Only proceeds on explicit `yes`.
