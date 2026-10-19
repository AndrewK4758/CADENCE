# `/claire-sync-jira` — reported conditions: screen availability

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-168).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-conditions.md` — every script writes its result to **stdout**
as `key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines.
Nothing here is a second implementation; each condition below is emitted by `jira-screen-lib.sh`.

**This file is a fifth part of one catalogue, not a fifth catalogue.** BTG-168 split it off with 4 lines
of headroom left in the primary. The record is **split, never truncated** — the same facet-conflict
resolution BTG-102, BTG-105 and BTG-173 each applied (C-3: Operability outranks DX on *content*; DX is
served by the placement instead).

---

## The doctrine: a field is sent only when the target screen carries it

**Discovered live, by ablation through the real transport** (BTG-150's `CLAIRE_ORG.md` §16
live-verification run against the reference Jira Server instance, 2026-08-19/20; registered as
**PROD_CLAIRE-024**). A Jira Server/DC project's **create** screen and
**edit** screen are separate configurations, and a `fields` member the target screen does not carry is
rejected outright: `POST /rest/api/2/issue` answers **HTTP 400** and the *whole* projection dies. On that
instance the Bug create screen omits Time Tracking, so **every** `type: bug` ticket carrying an estimate
was unprojectable — a common class of ticket, not an exotic one.

The remedy is **detect-then-send** (DEC-001), never send-then-recover. A 400 is an error-shaped
*inference*, not a field-availability *answer*: it can equally mean a required field is missing, a
priority value was rejected, a duration was invalid, or this adapter sent a malformed body — and this
adapter has a recorded incident of blaming the instance for exactly that. So the instance is **asked**,
once per invocation, and its own metadata is the answer.

Three properties govern every condition below.

- **The predicate is THREE-VALUED** — available, affirmatively absent, or unknown — and **only an
  affirmative absence suppresses**. Collapsing "the instance says this field is absent" into "nobody
  could ask" is the fail-**closed** mistake DEC-007 forbids by name: a transient metadata-endpoint
  failure would silently stop projecting four fields for every adopter at once, which is what
  problem.md's *Constraints* rule out ("silently never projecting an estimate would trade a loud failure
  for a quiet one"). The polarity is precedent-backed, not invented — `jira-ac-lib.sh` suppresses the
  acceptance-criteria write only when its `editmeta` read **succeeded**, returned **2xx**, and the field
  was **absent**.
- **Detection is instance-driven.** No issue-type name and no field name appears in any control-flow
  predicate: the field id is a **parameter**, so one implementation governs every type and every guarded
  field identically and the four cannot drift. An adopter whose Bug screen *does* carry Time Tracking
  still gets the estimate written, byte-identically.
- **The available branch reports NOTHING.** A line there would appear in every adopter's transcript on
  every sync for no decision anyone can act on.

**Four fields are guarded** — `timetracking`, `priority`, `labels` and `description` — because all four
are sent by one writer under the same unchecked assumption. Fixing only the reported one would reproduce
PROD_CLAIRE-024's root cause one ticket later (DEC-014). `summary` and `project` are structural and cannot be
absent; `issuetype` is guarded separately by the BTG-102 re-type guard; the Epic Name field carries the
**inverse** hazard (BTG-040: on an Agile instance it is *required*) and stays out of scope.

---

## The four per-field conditions

- **`syncjs.estimate.field_unsupported_type`** (Warning) — the instance affirmatively reports that
  `timetracking` is **not on the target screen** for this issue type, so `originalEstimate` is
  **omitted** from the request body and the projection continues with every other field written. This is
  PROD_CLAIRE-024's own recommended seam name, adopted verbatim. On the **update** path the live Original and
  Remaining Estimates are left **untouched** — the polarity `syncjs.estimate.unprojectable` already uses
  — and the current-Remaining prerequisite read is **not issued at all**, because there is no write to
  preserve a Remaining for. `estimate_result` reports **`field-unsupported`**, never `none`: `none`
  means "there was no estimate to project", and collapsing the two re-creates PROD_CLAIRE-023's shape verbatim
  (DEC-008). **Operator action:** add Time Tracking to that issue type's screen if the estimate should
  project; otherwise none — the omission is deliberate and reported.
- **`syncjs.priority.field_unsupported_type`** (Warning) — as above, for `priority`. The mapped priority
  is omitted; the repo's `priority:` and the config's `priority_map` are unaffected, and an unmapped
  priority remains a **configuration HALT**, which is a different cause with a different remedy.
- **`syncjs.labels.field_unsupported_type`** (Warning) — as above, for `labels`, and this one carries a
  distinction worth stating: the member is **OMITTED**, never sent as an empty array. `{"labels": []}`
  is not an omission, it is an explicit instruction to Jira to **CLEAR the labels** — materially worse
  than sending them. `labels` is the one guarded field whose body-builder arm has no empty-value
  sentinel, so it is the one arm that gained a condition (DEC-017).
- **`syncjs.description.field_unsupported_type`** (Warning) — as above, for `description`. It is
  evaluated **after** BTG-062's absent/blank-render guards, never before: an update with no rendered
  description is an **upstream defect** and stays a loud refusal to PUT, and must never be masked by
  "the screen would not have taken it anyway". On the update path the live description is left
  untouched rather than cleared.

---

## The shared and follow-up conditions

- **`syncjs.screen.availability_unknown`** (Warning) — the availability question could **not be
  resolved**: the metadata read was unreachable, returned a non-2xx, returned a 2xx carrying no
  recognizable field map, returned a 2xx carrying an **empty** field map (BTG-184 AC-1: a zero-key map
  answers nothing about these fields — it is an unanswered question, never four affirmative absences),
  or — on the **create** scope only — returned a 2xx whose pagination envelope affirmatively reports the
  page is **truncated** (BTG-184 AC-2: `isLast` present and false, or a present numeric `total` exceeding
  the returned `values` length; an *absent* envelope is never evidence of truncation, per DEC-003). **All
  four fields are sent exactly as they are today**, so behaviour is strictly no worse than before this
  guard existed. Its name is deliberately **distinct** from `field_unsupported_type`: reporting the latter
  here would assert a fact about the instance's screen that nobody observed. It is emitted **once per run,
  never once per field** — one unanswered question is one condition. **Operator action:** if it persists,
  the metadata endpoint is restricted or absent on this Jira version and the guard is inert there; the
  writes behave as they did before. The **create**-screen read is the one to check first, and it is
  version-sensitive: Jira 9 removed the classic single-shot
  `createmeta?projectKeys=…&expand=projects.issuetypes.fields`, which answers **HTTP 404 "Issue Does Not
  Exist"** there, so the adapter uses the two-step `createmeta/{project}/issuetypes[/{issueTypeId}]` form
  instead. On a Jira **older than 8.4** neither step exists, this condition fires on every create, and the
  create path is exactly as unguarded as it was before BTG-168 — reported, never silent (DEC-026, observed
  live on Jira Server 9.3.1). **When this condition fires during the create-completion follow-up** (the
  edit-screen re-ask after a create suppressed one or more fields), no follow-up write was issued, the
  create's omissions reported above **stand**, and the operator action is to check the metadata endpoint or
  credential — **never** to reconfigure screens that were never inspected; see `followup_unavailable`
  below for the case that fires instead when the edit screen genuinely *was* read.
- **`syncjs.screen.followup_written`** (Info) — a **create-completion** write. After a create that
  suppressed one or more fields, the new issue's **edit** screen was asked and carries some of them, so
  **exactly one** follow-up `PUT` wrote every recovered field and this line names them. Both facts are
  true and both are recorded — the field *was* unavailable at create *and* *was* recovered — because
  collapsing them hides why a second write happened at all. `estimate_result` becomes
  **`followup-written`** when the estimate is among them. Its `timetracking` carries `originalEstimate`
  **alone**, and that is correct rather than a PROD_CLAIRE-006 violation *only* because the issue was created
  moments earlier with the estimate suppressed and therefore has **no Remaining Estimate** — today's
  ordinary create semantics, where Jira initialises Remaining from Original. That justification is
  enforced structurally by `sync-jira-server-screen-availability-gate.sh`, not left as prose (DEC-013).
- **`syncjs.screen.followup_rejected`** (Warning) — the follow-up write was attempted and the instance
  refused it, or its body could not be staged. **NON-BLOCKING**: the issue exists, was already reported
  created, and the run exits **0**. Turning a successful create into a failed run would re-introduce the
  exact defect BTG-168 removes. `estimate_result` stays **`field-unsupported`**, because nothing landed.
  **Operator action:** re-run the sync, or write the fields in Jira.
- **`syncjs.screen.followup_unavailable`** (Warning) — a create suppressed one or more fields, the issue's
  **edit** screen **was actually read** (state `ok`), and it carries **none of them either**, so **no
  follow-up write was issued** and the omissions reported above **stand**. This line exists because its
  absence would be ambiguous: a reader seeing four suppressions and no follow-up line cannot otherwise
  tell *"the edit screen could not take them either"* (correct) from *"the completion never ran"* (a
  defect). **It fires only on an observed screen** (BTG-184 AC-3): when the edit-screen read instead
  failed, returned non-2xx, or resolved to an empty or unrecognizable map, `availability_unknown` has
  already fired above and is the correct and sufficient line — asserting *this* condition in that case
  would claim a screen fact nobody observed (DEC-025's collapse, one level in). Recorded as DEC-025, which
  extends DEC-019's set from seven conditions to eight; the gate derives the set from the library and
  pins no count, exactly so it can grow this way. **Operator action:** add the fields to that issue
  type's screens, or accept the omission — this action applies only to the observed-and-empty case above,
  never to the could-not-be-read case, which is `availability_unknown`'s to diagnose.

**No condition here is ever fatal.** Every probe outcome and every follow-up outcome exits `0` if
nothing else fails. A guard that can halt the projection is not a guard — it is a second copy of the
defect it was built to remove.
