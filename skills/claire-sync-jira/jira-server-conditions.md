# `/claire-sync-jira` — reported conditions and error handling

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, ADR_CLAIRE-0025).
Invariant relied on from outside this boundary: every script writes its result to **stdout** as
`key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines
(`.claude/skills/claire-sync-jira/jira-server-scripts.md`, *the three-channel return contract*). Nothing
here is a second implementation — each condition below is emitted by the named script, and this file is
the operator-facing catalogue of what each one means.

**Every name in this file is verified against the emitting line in the script.** A condition that is
documented but never emitted, or emitted but described as something else, is the defect class BTG-075's
re-reviews kept finding; `ci-templates/scripts/tests/btg-075-*.test.sh` execute the scripts and assert
on the names.

> **The catalogue is seven files.** `jira-link.sh`'s link family and the `jira-transition.sh` hop
> condition that travels with it live in `.claude/skills/claire-sync-jira/jira-server-conditions-links.md`;
> the whole `syncjs.umbrella.*` family lives in
> `.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md`; the two **untyped-ticket**
> conditions — `syncjs.write.type_unasserted` and `syncjs.reserve.type_placeholder` — live in
> `.claude/skills/claire-sync-jira/jira-server-conditions-type.md`; the screen-availability family lives in `.claude/skills/claire-sync-jira/jira-server-conditions-screens.md`; and the deterministic markup-rendering conditions live in `.claude/skills/claire-sync-jira/jira-server-conditions-render.md`; and the scratch-staging and import-seed conditions live in `.claude/skills/claire-sync-jira/jira-server-conditions-scratch.md`. BTG-102 split the first off when
> three more conditions on the projection write pushed the single file past the 400-line DX ceiling,
> BTG-105 split the second off when replacing the umbrella re-type retired five names and added
> eighteen, BTG-173 split the third off with **7** lines of headroom left, BTG-168 split off the fourth, BTG-205 the fifth with **one** line left in this file, and BTG-247 the sixth. Each time
> the record is **split, never truncated** (facet conflict C-3 — Operability outranks DX on content,
> and DX is served by placement instead). Everything else is here.

---

## Transport and HTTP

- **Transport unreachable.** When a REST call cannot reach the instance at all, the script exits **3**
  with **`syncjs.transport.rest_unreachable`** — an actionable "instance not reachable" message,
  **distinct** from a ticket-resolution failure. Never silently no-op.
- Treat any **non-2xx** as a failure: the script surfaces the HTTP status and the Jira `errorMessages` /
  `errors` from the response body under the operation's own `syncjs.*` condition. Do not silently
  continue on create/update failures.
- An **auth/permission** failure (`401`/`403`) almost always means the PAT is missing, expired, or lacks
  project permission — re-run `jira-connect.sh`, which reports `syncjs.connect.rest_rejected` with the
  status.
- A **field/screen** failure (`400`) usually means a required field is missing for that issue type, or a
  field id is wrong or not on the issue's edit/create screen — check the field names/ids against the
  project's Jira configuration and the mappings in the config sidecar.
- A **field/screen** failure on the **assignee** write (step 7, `jira-assign.sh`) usually means the
  target user is not assignable for that project/issue type, or the `assignee` field is not on the
  issue's edit screen — report `syncjs.assign.rejected` and **continue** (assignment is non-blocking;
  the rest of the sync still runs).

## Self-identity resolution (`jira-connect.sh`)

Resolving "self" when `$JIRA_SELF` is unset raises its own `syncjs.self.*` reported conditions, all
**non-blocking**: `syncjs.self.resolved` (success, carrying `source=cache` or `source=rest`); the three
distinguishable resolution failures `syncjs.transport.rest_unreachable` /
`syncjs.connect.rest_rejected` (status) / `syncjs.self.shape_unrecognized` (2xx but no usable `.name`);
and, reported **distinctly** from a resolution failure, the cache signals
`syncjs.self.cache_invalidated` (fingerprint mismatch, the safety mechanism firing) /
`syncjs.self.cache_unreadable` / `syncjs.self.cache_write_failed`. A cache **miss is not a failure** and
is never reported as one. A failed resolution leaves "self" **unresolved** (never a guess) and **never
writes a cache entry**, so a failure cannot poison the cache; each consumer then takes its existing
degradation.

## Worklogs (`jira-worklog.sh`)

A disabled **`worklog_creation_enabled`** toggle (the config sidecar) suppresses worklog creation
entirely — the sync makes no worklog read and no worklog post, and reports `syncjs.worklog.disabled`.
This is a policy opt-out, **not an error**: every other step (fields, issue write, status, assignment,
links, `jira_url` write-back) still runs unchanged.

The **worklog immutability + post-add verification** contract (step 6.5, BTG-064) raises its own
`syncjs.worklog.*` reported conditions. Exactly one fires per worklog outcome, so **no post is ever
silent**:

- **`syncjs.worklog.watermark_seeded`** (Info) — `worklog_watermark_at` was absent, so it was seeded to
  `max(stage_effort[].at)` and **nothing** was posted this run (bootstrap; never a backfill).
- **`syncjs.worklog.postcheck_failed`** (Critical) — the post-add re-read shows the tracker did not
  absorb the worklog. Reported with the issue key, worklog id, baseline, observed value, and expected
  delta; the watermark is **not** advanced, and the worklog is left **untouched** for the operator.
- **`syncjs.worklog.postcheck_indeterminate`** (Warning) — the re-read timed out or was unparseable.
  Never treated as a pass; the watermark is not advanced.
- **`syncjs.worklog.postcheck_skipped_floor`** / **`syncjs.worklog.postcheck_skipped_no_estimate`**
  (Info) — sanctioned skips: the pre-add baseline was below the posted duration (floor-at-zero), or the
  issue carries no estimate at all. Both **advance** the watermark. The second is reachable only
  because the baseline READ and the baseline VALUE are now separate questions: a failed read is
  `postcheck_failed`, an issue that genuinely was never estimated is this Info skip. Conflated, every
  unestimated ticket took a false Critical whose watermark never advanced, so it retried on every
  subsequent run — and `estimated_effort: ""` is the shipped template default.
- **`syncjs.worklog.skipped_epic`** (Info) — the ticket is `type: epic`. An Epic tracks no realized
  effort of its own (its children do), so the step is skipped **before any call**.
- **`syncjs.worklog.postcheck_unsupported`** (Info) — the declared capability is `none`; the worklog is
  still posted and the sync still succeeds.
- **`syncjs.worklog.capability_marker_absent`** (Critical) — the `worklog-postcheck-capability` marker
  is absent, malformed, or outside the allowlist. **HALT** — it never silently resolves to `none`.
- **`syncjs.worklog.skipped_zero`** (Info) — the entry's `effort` is `0m`, so the stage records no time
  and there is nothing to project: **no worklog is posted**, and the watermark **advances** past the
  entry (BTG-112 DEC-007). The skip is never a bare `continue` — it fires this condition, because the
  invariant above is that exactly one `syncjs.worklog.*` condition fires per outcome.

  The advance is the point worth reading twice, because it is the **opposite** of the malformed
  branch's ruling and the two look superficially alike. A malformed entry withholds the advance since
  it may still owe a projection once someone repairs it; a `0m` entry can never owe one, because
  `stage_effort` is append-only and an entry's `effort` is immutable — there is no future state in
  which this skip becomes wrong. Withholding it instead would leave a **trailing** `0m` entry selected
  on every subsequent run: each run would re-perform the marker scan, re-report the skip, and never
  report `up_to_date`, firing a condition forever over a state that can never change.

  A `0m` entry is reachable only through a per-operator multiplier override of zero
  (`CLAIRE_ORG.md` §12); the shipped defaults never produce one (BTG-112 DEC-010).

### Split mode (`jira-worklog-agent.sh`, BTG-315)

Active only when the ticket's prefix resolves an agent-time user in `CLAIRE_ORG.md` §9's fifth column
(`jira-worklog.sh` dispatches every candidate to `jira-worklog-agent.sh` instead of the unsplit path
above -- `js_worklog_process_split_candidate`, review cycle-2 B7). Eight `syncjs.worklog.*` conditions
join the family, each firing at most once per candidate per condition:

- **`syncjs.worklog.split_resolved`** (Info) — the split computation (`worklog-split.sh`) resolved
  operator/agent minutes for this candidate. Emitted **before either leg is posted**
  (record-before-contact, OS-1.4), naming only the resolved durations and the configured identity --
  never the factor itself (R6).
- **`syncjs.worklog.split_unavailable`** (Critical, HALT exit 4) — an agent-time user is configured but
  `worklog-split.sh` is missing or exited non-zero. Nothing is posted for the candidate; the watermark
  stays put.
- **`syncjs.worklog.leg_zero_skipped`** (Info) — one leg (operator or agent) computed to `0m`. That leg
  issues no request of any kind; the non-zero leg still posts normally.
- **`syncjs.worklog.agent_leg_posted`** (Info) — the agent leg posted and the confirming re-read names
  the configured identity as author. Mirrors the unsplit path's own `posted`, one level down (per leg).
- **`syncjs.worklog.agent_leg_rejected`** (Warning, non-halting) — the attribution endpoint answered a
  **permanent** rejection (BTG-319): a 4xx other than `408`/`429`, or an HTTP `500` whose JSON
  `.message` (trailing whitespace removed) equals the literal `Invalid user "<configured agent
  user>".` — string equality, never a regex/glob/substring/case-folded match. The operator's own leg
  is never withheld (OQ-3); the agent share is **forfeited**, never retried, and the watermark still
  advances past the candidate (S-5.3/S-5.4, not sticky).
- **`syncjs.worklog.agent_leg_status_ambiguous`** (Critical, HALT exit `1`) — the attribution endpoint
  answered a non-2xx that is **not** positively identified as the permanent rejection above (BTG-319):
  every other `5xx`, `408`, `429`, and any `1xx`/`3xx`. Nothing is forfeited and the watermark is
  **not** advanced for this candidate — a re-run retries only the missing agent leg. Names `status=`
  and a 200-byte `body=` excerpt with CR/LF flattened to spaces, so an operator can tell it apart from
  a genuine rejection without re-running.
- **`syncjs.worklog.agent_leg_misattributed`** (Critical, non-halting) — the agent leg posted (2xx), but
  the confirming re-read's `author.name` does not match the configured identity case-insensitively.
  Never re-posted (worklogs are immutable, BTG-064); the watermark still advances, since the leg IS on
  the tracker, just not attributed as intended.
- **`syncjs.worklog.agent_leg_unconfirmed`** (Critical, HALT) — the agent leg posted, but the confirming
  re-read was unreachable, rejected, or unparseable. Never treated as a pass; the watermark is **not**
  advanced for this candidate.

The existing `syncjs.worklog.scratch_unavailable` / `body_unbuildable` / `postcheck_*` conditions above
apply **identically per leg** in split mode (review cycle-2 B2/B3): a local staging failure on either
leg halts exactly as the unsplit path does, and each leg now gets its own absorption check
(`_js_worklog_absorb_verify`, `jira-worklog-agent-absorb.sh`), never only the operator's.

Bulk-run summary: `agent_legs_rejected` (stdout, split mode only, absent -- never `0` -- when
unconfigured) is surfaced per ticket at end-of-sync by
`.claude/skills/claire-sync-jira/jira-server-orchestration.md`'s `bulk_sync_tickets`, the same
never-summed, named-by-id shape as the reference-account line above it.

## Acceptance Criteria field (`jira-write-issue.sh` / `jira-import.sh`)

Gated by the `acceptance_criteria_sync_enabled` toggle in the config sidecar, which
`jira-write-issue.sh` **resolves before its create/update call** so a config HALT never abandons a
freshly-created issue. All `syncjs.ac.*` conditions are **non-blocking** — the rest of the sync always
completes:

- **`syncjs.ac.disabled`** — the toggle is `false`; no AC-field API call is made in either direction (a
  policy opt-out, **not an error**; the description-embed acceptance-criteria token in
  `ticket_TEMPLATE.md` is unaffected).
- **`syncjs.ac.field_absent`** — no field named exactly "Acceptance Criteria" on the instance; AC is
  skipped (actionable: set the toggle to `false` if the instance has no AC plugin).
- **`syncjs.ac.field_ambiguous`** — more than one exact-name match; AC is skipped and the field is
  **never guessed** (II-021 / DEC-005).
- **`syncjs.ac.field_unsupported_type`** — the field is not on the target issue type's edit/create
  screen (pre-checked via `editmeta`/`createmeta`); the AC write is skipped (a reported skip, **not a
  400**).
- **`syncjs.ac.write_rejected`** — the AC field write failed despite the pre-check; reported with the
  tool's Jira error, then the sync continues (mirrors `syncjs.assign.rejected`).
- **`syncjs.ac.field_discovery_failed`** — the instance field-list discovery errored; AC is skipped and
  the rest of the seed/sync is never lost.
- **`syncjs.ac.source_unreadable`** / **`syncjs.ac.section_absent`** / **`syncjs.ac.items_unrecognized`**
  — the repo `problem.md` could not be read, carries no `## Acceptance Criteria` section, or carries a
  section with content the item recognizer found no `- [ ]` / `- [x]` item in. All three are **read or
  parse failures**, never an empty section: the field is left **untouched** rather than cleared. Only a
  section present and carrying **no content at all** is the sanctioned clear (DEC-052).
- **`syncjs.ac.scratch_unavailable`** — the scratch file for the request body could not be created
  (a full `/tmp`, a bad `$TMPDIR`, a quota). Reported and the write **refused**: an unstaged body
  degrades the `PUT` into a **bodyless** one, which a permissive server accepts, clearing the field
  while the run reports success. Non-blocking like every other `syncjs.ac.*` condition (DEC-057).
- Import additionally reports `syncjs.ac.imported` / `syncjs.ac.field_empty`; a successful write reports
  `syncjs.ac.projected`, and an Epic reports `syncjs.ac.skipped_epic`.

## Preservation comment (`jira-preserve.sh`, run immediately before the projection write)

The script decides for itself whether to act: it reads the issue's as-filed fields (raw wiki) and,
unless the description already carries the `Repo-managed` sentinel, builds the comment **entirely in
script** from `.claude/skills/claire-sync-jira/originalcontent_TEMPLATE.txt` and posts it. It returns
`preserved=true` or `preserved=skipped` (`syncjs.comment.skipped_repo_managed`). **Every failure is
BLOCKING** — `syncjs.transport.rest_unreachable`, `syncjs.comment.rest_read_rejected` (as-filed GET
non-2xx or unparseable), or `syncjs.comment.rest_post_rejected` (comment POST non-2xx). The orchestrator
must **halt before the projection write** on any of them: the write overwrites the
summary/description, so a swallowed failure here loses the as-filed original permanently. A successful
post reports **`syncjs.comment.preserved`**.

## Umbrella projection (`jira-epic.sh` + `jira-umbrella-lib.sh`, the Epic-on-Epic case)

The fork is gated **solely** on the ticket’s own live Epic Link (`E`): empty/absent ⇒ the single-level
Epic projection (`syncjs.epic.single_level`, zero links and zero writes); populated ⇒ the umbrella
branch (DEC-034). All of these are **best-effort**: the branch halts, reports, and exits **0**, because
a non-zero exit from a best-effort script makes the orchestrator halt the whole ticket (DEC-033).

**The whole `syncjs.umbrella.*` family lives in
`.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md`** — the third part of this one
catalogue, split off by BTG-105 when the umbrella re-type was replaced by a create-and-close flow
(five names retired, eighteen added, against a file already at the 400-line DX ceiling). The record is
**split, never truncated**, on the same facet-conflict resolution BTG-102 applied to the links half.

## Estimate projection (`jira-write-issue.sh`)

`estimated_effort` is human-authored planning prose, not a typed field, so it is **projected** onto a
Jira duration rather than forwarded. The write is a **blocking** step and Jira answers a non-duration
with a 400, so forwarding one strands the whole ticket — its status, worklogs and links never project
either. **A projectable estimate can still be unwritable**, for a different reason with a different
remedy: the target screen may not carry Time Tracking at all. That case, and the same hazard on
`priority`, `labels` and `description`, is catalogued in the fifth part of this one catalogue —
`.claude/skills/claire-sync-jira/jira-server-conditions-screens.md` (BTG-168 / PROD_CLAIRE-024).

- **`syncjs.estimate.range_projected`** (Info) — the value is a range (`2-4h`, or `1–2d` with an
  en-dash), so its **upper bound** is projected: the upper bound is the commitment the estimate is read
  as. An en/em dash is normalized first — a projection that turned on which dash key an author hit
  would be a defect wearing a typography disguise.
- **`syncjs.estimate.unprojectable`** (Warning) — the value is not a duration and not a range this
  adapter can collapse (`hours`, `<1h`, `half-day to 1d`, a whole sentence — 13 of this repo's 149
  files carry such a value). The Original Estimate is **omitted**, the live value is left untouched,
  and the rest of the projection applies. Payload: `estimate_result=unprojectable`.
- **`syncjs.write.labels_unusable`** (Warning) — `tags:` is not a list, so **no labels** are projected
  rather than a malformed body being sent. A scalar `tags:` used to empty the label array, which failed
  the whole body build and sent an EMPTY request — surfacing as an opaque Jira 400 rather than as
  anything this adapter can name.
- **`syncjs.write.body_unbuildable`** (Critical) — the request body could not be built, or built empty.
  **HALT**; nothing is sent.
- **`syncjs.write.title_absent`** (Critical, BTG-124) — the ticket's `title` is empty or whitespace-only,
  so `fields.summary` would go out as `""`. **HALT before any REST call**; nothing is created and nothing
  is updated. This became reachable when BTG-124 dropped the `<id>: ` prefix: until then an absent title
  still produced the degenerate-but-non-empty `"<id>: "`, which Jira accepts, so the state existed but
  never surfaced. Without the guard it would arrive as a 400 reported under `syncjs.write.rest_rejected`
  — this adapter's own malformed body, blamed on the instance. Whitespace-only counts as empty, matching
  `syncjs.umbrella.title_absent`'s existing treatment on the sibling writer.

## Issue-type re-type guard (`jira-write-issue.sh`, update path — BTG-102)

Jira's update `PUT` does **not** enforce the issue types its own edit screen offers. Observed, not
assumed: a `Story` whose `editmeta.fields.issuetype.allowedValues` was exactly `["Story"]` accepted
`issuetype: Issue` with HTTP **204**, was left sitting on a status its new workflow does not contain,
and its offered transitions collapsed from six to two — with **no `Workflow` changelog item**, which
only Jira's UI **Move** writes. So the instance is **asked first**, exactly as `jira-transition.sh` asks
`GET /transitions` before a status hop. The contract relied on is the weaker, robust one:
`allowedValues` is *the set of types Jira will accept without a Move* — the workflow correlation is the
explanation offered to the operator, not the thing depended on.

The verdict read is `GET /rest/api/2/issue/{key}/editmeta`, **strictly conditional**: only on the **update**
path, and only when the live issue type actually differs from the target — it adds **no** call of its own to
a create or reservation; BTG-168's screen probe does. The **live** type comes from the current-Remaining
prerequisite read's body when that read ran (it already asks for `issuetype`), otherwise from the guard's own
narrow `GET /rest/api/2/issue/{key}?fields=issuetype`: the guard's precondition is the update path and
nothing else, so an update with no projectable estimate — and a **`type: epic`** update, which that
prerequisite read skips — is guarded like any other, and on a `type: epic` update the **Epic Name** field is
withheld with the type (an Epic-only field written to an issue that is not becoming an Epic is rejected
`400`, stranding every other field). The verdict is always reported, and `issuetype_projected=yes|no` reaches
stdout so the decision is auditable from the transcript. **`jira-epic.sh`'s umbrella re-type is deliberately NOT guarded** — a human gate ruling
(spec BTG-102 OQ-7 / RISK-2 / DEC-021), superseded by the follow-up that replaces that flow outright;
until then it keeps re-typing unguarded and its `syncjs.umbrella.*` conditions are unchanged.

- **`syncjs.write.issuetype_retyped`** (Info) — the instance offers the target type for this issue, so
  the re-type is projected exactly as before this guard existed. The positive checkpoint: a permitted
  same-workflow re-type must never be over-blocked.
- **`syncjs.write.issuetype_move_required`** (Warning) — the target type is **absent** from a
  well-formed, non-empty `allowedValues`. The issue type is **not** written; **every other field still
  projects** (summary, description, labels, priority, timetracking), and the run exits **0** — stranding
  the rest of the projection is the defect this closes, not one it introduces. A status is **never**
  transitioned to force the re-type. **Operator action:** perform the Move in the Jira UI (More → Move)
  on the browse URL the condition carries, then re-run the sync. There is no REST Move to automate:
  `/secure/MoveIssue!default.jspa` is a JSPA UI form needing a session and an XSRF token. The condition
  repeats on **every** subsequent sync until a human acts — deliberately, and confirmed at the gate: it
  never decays into silence, and no toggle suppresses it, because a suppression channel would sanction
  the corruption above.
- **`syncjs.write.issuetype_undeterminable`** (Critical) — the answer is unusable. Either the **live issue
  type itself** is unresolvable (a 2xx issue read carrying no `.fields.issuetype` — field-level security, or
  an unexpected shape; the edit metadata is then never asked, there being nothing to compare), or the edit
  metadata was **reached** and unusable: a non-2xx, an unparseable body, no `issuetype` field on the edit
  screen, no `allowedValues` list, or an **empty** one. Fails **closed on the issue type only** — same outcome as
  a refusal, same exit **0**, every other field projected — and the detail names *which* sub-condition
  held, so a non-editable Issue Type field (a legitimate screen configuration, where a Move genuinely is
  the only path) is distinguishable from a malformed response. An **absent** `allowedValues` is never
  read as "every type is allowed" and an **empty** one is never read as "no type is allowed": both are
  *unknown*, and unknown never becomes "go ahead".
- **Not to be confused with a transport failure.** If the edit-metadata exchange could not happen at
  all, the existing **`syncjs.transport.rest_unreachable`** fires and the run exits **3** with **no
  update `PUT` at all** — the question was never asked, so nothing is written. A completed exchange with
  an unusable answer (exit `0`, one field withheld) and an exchange that never happened (exit `3`,
  nothing written) are different conditions with different exit codes, and are never conflated.

## The `*_body_unbuildable` family (BTG-084) — one rule, thirteen sites

Every request body is staged by **one** builder, `js_build_body` in `jira-rest.sh`, whose header carries
the full rationale. It asks **both** questions the wire needs answered — did `jq` **exit 0**, and did it
**produce content** — because a `jq` dying mid-write leaves a **truncated, non-empty** file an emptiness
probe reads as "built". On either failure **nothing is sent** and exactly ONE line is emitted.
**`*_body_unbuildable` is never `*_rejected`:** blaming the instance for a body this adapter built wrong
is an audit line that lies about causation. **No stdout value is invented.**

**Eight new names** at BTG-084. Two of them — the umbrella re-type and summary body-build refusals — were
**retired by BTG-105** with the writes they guarded; the property was **re-homed**, not dropped, onto the
replacement's creation body as `syncjs.umbrella.issue_body_unbuildable`
(`.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md`). The remaining seven:
`syncjs.umbrella.child_epic_link_body_unbuildable` (which also **counts**, so the run reports
`epic_result=umbrella-partial`), `syncjs.transition.body_unbuildable`, `syncjs.comment.body_unbuildable`,
`syncjs.reserve.body_unbuildable`, `syncjs.worklog.body_unbuildable`, `syncjs.assign.body_unbuildable`
(added at code review). **Five reuse** an existing one (`ac`, `write`, `epic`, `<prefix>.link` x2);
skip-or-halt semantics are stated per area, below.

**The class is closed by a CHECK, not by a list** — `btg-084-jq-build-guard.test.sh` asserts the property
over **every** `*.sh` in the compiled tree. Its one blind spot is `jira-assign.sh`, which builds into a
**variable** and matches no `jq … > file` shape (guarded inline; DEC-018). This inventory has been wrong
**five** times: any list of sites is documentation, never the guarantee.

## The `type: epic` fork (`jira-epic-lib.sh`, consumed by `jira-write-issue.sh` and `jira-epic.sh`)

Jira Server/DC forbids an Epic from carrying an Epic Link, so the fork decides the issue's **type** and
must be resolved **before** the type is written (BTG-036 / DEC-045).

- **`syncjs.umbrella.write_deferred`** (Info) — the ticket carries a live Epic Link, so it is an
  umbrella: step 4 issues **no write at all** and yields the issue to `jira-epic.sh`, which owns its
  type, its `[UMBRELLA] ` summary and its child decomposition as one sequence. Without this the
  umbrella was typed `Epic` at step 4 and back at step 9 — oscillating on every run.
- **`syncjs.epic.link_field_absent`** (Info) — this instance has no *Epic Link* field, so **no issue
  here can carry one**: the single-level Epic projection is a fact about the instance, not a guess, and
  the projection proceeds. Distinct from `syncjs.umbrella.epic_link_unreadable` (Critical), which is
  "I could not look" and **halts** before any write (DEC-046).
- **`syncjs.assign.skipped_epic`** (Info) — an Epic's assignee is human-managed; skipped before any
  call, exactly as `syncjs.transition.skipped_epic` skips its status.
- **`syncjs.epic.scratch_unavailable`** / **`syncjs.epic.body_unbuildable`** (Warning) — the scratch
  file for the child's Epic Link body could not be created, or the build **exited non-zero or produced
  nothing**. The write is **refused** and `epic_result=rejected` is reported: an unstaged or empty body
  degrades the `PUT` into a **bodyless** one, which a permissive server accepts, leaving the Epic Link
  unset while the run reports `associated`. The same hazard `syncjs.ac.scratch_unavailable` names, on
  the same `PUT /rest/api/2/issue/{key}` endpoint. Non-blocking — the epic step is best-effort and
  halts its BRANCH, never the ticket (DEC-033).
  **BTG-079 AC-1:** `body_unbuildable` now fires on `jq`'s **exit status** as well as on an empty file.
  The two are different questions: a build that dies mid-write leaves a TRUNCATED, non-empty file, so
  the emptiness probe alone answered "built" and a **malformed** body was `PUT` under
  `epic_result=associated`. This is also the arm no scenario could previously reach — the `mktemp`
  guard always fired first — and `btg-075-tempfile-lifecycle.test.sh` **S-4.6** now reaches it.

## Scratch staging and import seed (relocated)

The scratch-staging family (`syncjs.<scope>.scratch_unavailable`, every script — BTG-079 AC-4/AC-5) and the import-seed conditions (`jira-import.sh`) moved to `.claude/skills/claire-sync-jira/jira-server-conditions-scratch.md` (BTG-247). Relocated, not removed.

## Reservation pairing (`jira-reserve.sh`)

- **`syncjs.reserve.pairing_obligation`** (Info) — reported **before** the create POST
  (record-before-contact). The key this call is about to reserve must be paired, within the **same
  governed operation**, with `specs/<id>/problem.md` and `specs/<id>/metadata.yaml`; an allocation
  left unpaired is the defect state **`idalloc.reserve.unpaired_artifact_creation`**. It is
  **Info**, not a failure: nothing has gone wrong at the moment it is emitted — it names a duty the
  CALLER now carries, and `/claire-triage` is what asserts the duty was discharged. It is declared first so
  a caller can abort before an orphan exists rather than learn of it once one does. The id is
  produced BY the reservation, so a "refuse unless the artifacts exist" precondition is structurally
  impossible here; declaring the obligation is what is achievable. The governing rule is
  `CLAIRE_ORG.md` `#id-allocation-binding` (Reservation pairing) — cited, never restated.
- **`syncjs.reserve.reserved`** (Info, detail extended) — on success the detail now also names the
  concrete `specs/<KEY>/problem.md` + `specs/<KEY>/metadata.yaml` the caller still owes, and says the
  reservation is UNPAIRED until they exist. No stdout key was added (the `pairing_obligation=` key
  was dropped during authoring — nothing parses it, so it would have been contract surface with no
  consumer); the stderr audit stream carries the whole signal.
