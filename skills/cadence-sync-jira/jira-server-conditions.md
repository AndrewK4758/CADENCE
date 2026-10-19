# `/cadence-sync-jira` — reported conditions and error handling

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, ADR_CADENCE-0025).
External invariant relied upon: every operation script emits machine-readable results on **stdout** as `key=value` lines and audit conditions on **stderr** as `syncjs.<family>.<condition>` lines (`.agents/skills/cadence-sync-jira/jira-server-scripts.md`, *the three-channel return contract*). Every condition cataloged below corresponds 1:1 to an emitting script line and is verified by `ci-templates/scripts/tests/btg-075-*.test.sh`.

> **This condition catalog spans seven modular files to stay below the `<400`-line Developer Experience ceiling (Operability Pillar outranking single-file consolidation per C-3 — split, never truncated):**
> 1. **This primary file (`jira-server-conditions.md`)**: transport/HTTP, self-identity, worklogs (including BTG-315 split mode), Acceptance Criteria field, preservation comment, estimate projection, issue-type re-type guard, `*_body_unbuildable` family, `type: epic` fork, and reservation pairing.
> 2. `.agents/skills/cadence-sync-jira/jira-server-conditions-links.md`: `jira-link.sh` link conditions and `jira-transition.sh`'s intermediate hop condition (BTG-102).
> 3. `.agents/skills/cadence-sync-jira/jira-server-conditions-umbrella.md`: the `syncjs.umbrella.*` replacement flow family (BTG-105).
> 4. `.agents/skills/cadence-sync-jira/jira-server-conditions-type.md`: the untyped-ticket conditions `syncjs.write.type_unasserted` and `syncjs.reserve.type_placeholder` (BTG-173).
> 5. `.agents/skills/cadence-sync-jira/jira-server-conditions-screens.md`: the screen-availability probe and follow-up family (BTG-168).
> 6. `.agents/skills/cadence-sync-jira/jira-server-conditions-render.md`: deterministic markup conversion (`jira-md2wiki.sh`) and wholesale-overwrite delta conditions (BTG-205).
> 7. `.agents/skills/cadence-sync-jira/jira-server-conditions-scratch.md`: scratch-file staging (`syncjs.<scope>.scratch_unavailable`) and import-seed conditions (BTG-247).

---

## Transport and HTTP

- **Transport unreachable (`syncjs.transport.rest_unreachable`).** When an HTTP call cannot reach the Jira Server/DC instance at all, the script exits **3** with **`syncjs.transport.rest_unreachable`** — kept strictly distinct from a ticket-lookup failure. Never silently no-op.
- **Non-2xx HTTP status.** Every non-2xx response is treated as a failure: the script surfaces the HTTP status code and Jira's `errorMessages` / `errors` payload under the operation's `syncjs.*` condition (and when stderr exceeds 30 lines, the orchestrator routes the output through `offload_log_triage` on `:9379` while preserving raw logs in `/tmp/agy-last-triage.log`).
- **Authentication / permission failure (`401`/`403`).** Indicates `JIRA_PAT` is unset, expired, or lacks project permissions — re-run `jira-connect.sh`, which emits `syncjs.connect.rest_rejected` with the status code.
- **Field / screen rejection (`400`).** Typically indicates a required field is missing for that issue type, or a field ID is absent from the create/edit screen — verify field mappings in `jira-server-config.json`.
- **Assignee screen / permission failure (`400` in Step 7, `jira-assign.sh`).** Indicates the target user is not assignable in that project or `assignee` is absent from the edit screen — emits `syncjs.assign.rejected` and **continues** (assignee reconciliation is best-effort).

## Self-identity resolution (`jira-connect.sh`)

When `$JIRA_SELF` is unset, resolving the operator's username emits non-blocking `syncjs.self.*` conditions: `syncjs.self.resolved` (with `source=cache` or `source=rest`); the three resolution failure conditions `syncjs.transport.rest_unreachable`, `syncjs.connect.rest_rejected` (HTTP status), and `syncjs.self.shape_unrecognized` (2xx response lacking a usable `.name`); plus the distinct cache lifecycle notices `syncjs.self.cache_invalidated` (token/URL fingerprint changed), `syncjs.self.cache_unreadable`, and `syncjs.self.cache_write_failed`. A normal cache miss is never reported as an error, and a failed resolution leaves `self` empty without poisoning the cache.

## Worklogs (`jira-worklog.sh`)

Setting **`worklog_creation_enabled: false`** in `jira-server-config.json` disables worklog projection cleanly — `jira-worklog.sh` performs zero worklog reads or posts and emits `syncjs.worklog.disabled` (a policy opt-out rather than an error; all other sync steps proceed normally).

The **worklog immutability and post-add verification** contract (BTG-064) emits exactly one `syncjs.worklog.*` condition per outcome so **zero worklog posts happen silently**:

- **`syncjs.worklog.watermark_seeded`** (Info) — `worklog_watermark_at` was absent on a ticket carrying existing `stage_effort` entries, so the watermark was seeded forward to `max(stage_effort[].at)` and **zero** historical worklogs were backfilled.
- **`syncjs.worklog.postcheck_failed`** (Critical) — the post-add re-read showed Jira did not absorb the worklog delta. Emits the issue key, worklog ID, pre-add baseline, observed value, and expected delta; leaves `worklog_watermark_at` **unadvanced** and leaves the posted worklog **untouched** (worklogs are never mutated or deleted).
- **`syncjs.worklog.postcheck_indeterminate`** (Warning) — the post-add re-read timed out or returned unparseable JSON; leaves the watermark unadvanced.
- **`syncjs.worklog.postcheck_skipped_floor`** / **`syncjs.worklog.postcheck_skipped_no_estimate`** (Info) — sanctioned verification skips when the pre-add Remaining Estimate was smaller than the logged duration (floor-at-zero) or when the issue carries no estimate (`estimated_effort: ""`). Both **advance** the watermark. Separating a failed baseline read (`postcheck_failed`) from a genuinely unestimated issue (`postcheck_skipped_no_estimate`) prevents unestimated tickets from failing post-check on every run.
- **`syncjs.worklog.skipped_epic`** (Info) — the ticket has `type: epic`. Because Epics accrue effort on child issues rather than directly, worklog projection skips before issuing any HTTP call.
- **`syncjs.worklog.postcheck_unsupported`** (Info) — `worklog_postcheck_capability` is configured as `none`; worklogs are posted without post-add absorption verification.
- **`syncjs.worklog.capability_marker_absent`** (Critical) — `worklog_postcheck_capability` is missing, malformed, or outside the allowed enum. **HALTs** (exit 4) rather than silently defaulting to `none`.
- **`syncjs.worklog.skipped_zero`** (Info) — a `stage_effort` entry has `effort: 0m` (reachable when an operator configures a zero stage multiplier in `CADENCE_ORG.md` §12, BTG-112 DEC-007/DEC-010): **zero worklogs are posted**, this Info condition is emitted, and `worklog_watermark_at` **advances** past the `0m` entry (unlike a malformed entry, which holds the watermark back until repaired, a valid `0m` entry is immutable and never owes a post, so advancing prevents infinite re-scans on subsequent runs).

### Split mode (`jira-worklog-agent.sh`, BTG-315)

Activated when the ticket prefix's `CADENCE_ORG.md` §9 row specifies a non-empty fifth column (`Agent-time user`), routing each candidate through `jira-worklog-agent.sh`'s `js_worklog_process_split_candidate` (review cycle-2 B7). Eight `syncjs.worklog.*` conditions govern split mode:

- **`syncjs.worklog.split_resolved`** (Info) — `worklog-split.sh` computed the operator and agent durations for the candidate. Emitted **prior to posting either leg** (record-before-contact, OS-1.4), logging only the resolved minute durations and configured agent username (never the raw split factor, R6).
- **`syncjs.worklog.split_unavailable`** (Critical, HALT exit 4) — an agent-time user is configured in §9, but `worklog-split.sh` is missing or returned non-zero. Nothing is posted and the watermark does not advance.
- **`syncjs.worklog.leg_zero_skipped`** (Info) — either the operator leg or the agent leg rounded to `0m`; that leg makes no HTTP call while the non-zero leg posts normally.
- **`syncjs.worklog.agent_leg_posted`** (Info) — the agent leg was posted and the confirming re-read verified `author.name` matches the configured agent identity.
- **`syncjs.worklog.agent_leg_rejected`** (Warning, non-halting) — the worklog attribution endpoint returned a **definitive permanent rejection** (BTG-319): any 4xx status other than `408`/`429`, or an HTTP `500` whose JSON `.message` (trimmed of trailing whitespace) equals the exact literal string `Invalid user "<configured agent user>".`. The operator leg stands (OQ-3), the agent leg is **forfeited** without retry, and the watermark advances past the candidate (S-5.3/S-5.4).
- **`syncjs.worklog.agent_leg_status_ambiguous`** (Critical, HALT exit `1`) — the attribution endpoint returned a non-2xx response that does **not** match the permanent rejection predicate above (BTG-319): any other `5xx`, `408`, `429`, or `1xx`/`3xx`. Nothing is forfeited and the watermark is **held**, allowing a subsequent re-run to retry only the missing agent leg. Logs `status=` and a 200-byte single-line `body=` excerpt.
- **`syncjs.worklog.agent_leg_misattributed`** (Critical, non-halting) — the agent leg returned 2xx, but the confirming re-read's `author.name` did not match the configured agent username case-insensitively. Because posted worklogs are immutable (BTG-064), it is never re-posted and the watermark advances.
- **`syncjs.worklog.agent_leg_unconfirmed`** (Critical, HALT) — the agent leg posted, but the confirming re-read failed, timed out, or could not be parsed; the watermark is **not** advanced.

All standard `syncjs.worklog.scratch_unavailable`, `body_unbuildable`, and `postcheck_*` checks apply **independently to each leg** in split mode (`_js_worklog_absorb_verify` in `jira-worklog-agent-absorb.sh`, review cycle-2 B2/B3). In bulk runs, `agent_legs_rejected` (emitted on stdout in split mode only; omitted when unconfigured) is reported per ticket at end-of-sync by `bulk_sync_tickets` in `jira-server-orchestration.md`.

## Acceptance Criteria field (`jira-write-issue.sh` / `jira-import.sh`)

Controlled by `acceptance_criteria_sync_enabled` in `jira-server-config.json` (resolved before the issue create/update request so a malformed toggle halts before mutating Jira). All `syncjs.ac.*` operational conditions are **non-blocking**:

- **`syncjs.ac.disabled`** — toggle is `false`; skips dedicated AC custom-field calls in both directions (the `## Acceptance Criteria` section inside `ticket_TEMPLATE.md` still renders into the description).
- **`syncjs.ac.field_absent`** — no custom field named `"Acceptance Criteria"` exists on the instance; skipped.
- **`syncjs.ac.field_ambiguous`** — multiple custom fields match `"Acceptance Criteria"` by exact name; skipped without guessing (II-021 / DEC-005).
- **`syncjs.ac.field_unsupported_type`** — pre-check against `editmeta`/`createmeta` shows the AC field is absent from this issue type's screen; skipped without provoking an HTTP 400.
- **`syncjs.ac.write_rejected`** — the AC custom-field `PUT` failed despite passing pre-check; logs the Jira error and continues.
- **`syncjs.ac.field_discovery_failed`** — fetching `/rest/api/2/field` failed; skips AC field sync without aborting the ticket.
- **`syncjs.ac.source_unreadable`** / **`syncjs.ac.section_absent`** / **`syncjs.ac.items_unrecognized`** — `problem.md` could not be read, lacks `## Acceptance Criteria`, or contains non-empty text with zero recognizable `- [ ]` / `- [x]` items. All three leave the live Jira AC field **untouched** rather than clearing it; only an explicitly present, completely empty section clears the field (DEC-052).
- **`syncjs.ac.scratch_unavailable`** — `mktemp` failed when staging the AC request payload; refuses the write so a bodyless `PUT` cannot accidentally clear the field (DEC-057).
- Inbound/outbound status conditions: `syncjs.ac.imported`, `syncjs.ac.field_empty`, `syncjs.ac.projected`, and `syncjs.ac.skipped_epic`.

## Preservation comment (`jira-preserve.sh`, executed immediately prior to Step 4 on updates)

Reads the existing Jira issue's summary, description, and mapped fields (in raw wiki markup) and, unless the live description already carries the `Repo-managed` panel sentinel, populates `.agents/skills/cadence-sync-jira/originalcontent_TEMPLATE.txt` deterministically in script and posts it as a comment (`preserved=true` / `syncjs.comment.preserved`, or `preserved=skipped` / `syncjs.comment.skipped_repo_managed`). **Every error in Step 3 is BLOCKING** — `syncjs.transport.rest_unreachable`, `syncjs.comment.rest_read_rejected`, or `syncjs.comment.rest_post_rejected` halts the sequence before Step 4 can overwrite the original description.

## Umbrella projection (`jira-epic.sh` + `jira-umbrella-lib.sh`, Epic-on-Epic replacement)

Routed strictly by whether the Epic ticket itself carries a populated live Epic Link (`E`): when empty/absent, runs single-level Epic projection (`syncjs.epic.single_level`); when populated, runs the best-effort umbrella replacement flow (DEC-033, DEC-034). **The complete `syncjs.umbrella.*` condition catalog resides in `.agents/skills/cadence-sync-jira/jira-server-conditions-umbrella.md`** (BTG-105).

## Estimate projection (`jira-write-issue.sh`)

Because `estimated_effort` in `metadata.yaml` is free-form planning text whereas Jira's `originalEstimate` requires a valid Jira duration literal (rejecting non-durations with HTTP 400 at a blocking step), `jira-write-issue.sh` parses and normalizes it first (while screen availability for `timetracking`, `priority`, `labels`, and `description` is cataloged in `.agents/skills/cadence-sync-jira/jira-server-conditions-screens.md` per BTG-168 / PROD_CADENCE-024):

- **`syncjs.estimate.range_projected`** (Info) — normalizes en/em dashes and projects the **upper bound** of a duration range (`2-4h` or `1–2d` -> `4h` or `2d`).
- **`syncjs.estimate.unprojectable`** (Warning) — the text cannot be parsed as a duration or range (`<1h`, `half-day to 1d`, etc.); omits `originalEstimate`, preserves any live estimate in Jira, and emits `estimate_result=unprojectable`.
- **`syncjs.write.labels_unusable`** (Warning) — `tags:` in `metadata.yaml` is not a list; omits `labels` rather than failing payload construction.
- **`syncjs.write.body_unbuildable`** (Critical) — `jq` failed or produced an empty request payload; **HALTs** before sending any request.
- **`syncjs.write.title_absent`** (Critical, BTG-124) — `title` in `metadata.yaml` is empty or whitespace-only; **HALTs before any REST call** so an empty `summary` is never sent.

## Issue-type re-type guard (`jira-write-issue.sh`, update path — BTG-102)

Because Jira's update `PUT` accepts an `issuetype` change with HTTP 204 even when the target type uses a different workflow — stranding the issue in an invalid workflow status without running a Jira UI **Move** — `jira-write-issue.sh` queries `GET /rest/api/2/issue/{key}/editmeta` on the **update** path whenever the live issue type differs from the mapped target type (and on `type: epic` updates, withholds `Epic Name` whenever the re-type is withheld). Emits `issuetype_projected=yes|no` on stdout:

- **`syncjs.write.issuetype_retyped`** (Info) — target issue type is present in `editmeta.fields.issuetype.allowedValues` and was written.
- **`syncjs.write.issuetype_move_required`** (Warning) — target issue type is **absent** from a non-empty `allowedValues` list. Withholds `issuetype` (and `Epic Name` if target is Epic), projects all other fields normally, and exits **0**. **Operator action:** use Jira UI `More -> Move` on the issue URL, then re-run sync. Repeats on every sync until moved.
- **`syncjs.write.issuetype_undeterminable`** (Critical, non-halting) — live `issuetype` or `editmeta` response was unreadable, non-2xx, or had an missing/empty `allowedValues` list. Fails **closed on `issuetype` only** (withholding the type change while projecting all other fields and exiting **0**). Note: if the `editmeta` request itself suffered a transport outage, `syncjs.transport.rest_unreachable` exits **3** before any `PUT`.

## The `*_body_unbuildable` family (BTG-084)

Every JSON payload is built through `js_build_body` in `jira-rest.sh`, which verifies both that `jq` exited `0` and produced non-empty bytes (preventing a mid-write `jq` crash from sending a truncated file). Enforced across all `*.sh` scripts by `btg-084-jq-build-guard.test.sh` (with `jira-assign.sh` guarded inline, DEC-018). Active script-specific conditions include `syncjs.umbrella.issue_body_unbuildable` (BTG-105), `syncjs.umbrella.child_epic_link_body_unbuildable`, `syncjs.transition.body_unbuildable`, `syncjs.comment.body_unbuildable`, `syncjs.reserve.body_unbuildable`, `syncjs.worklog.body_unbuildable`, and `syncjs.assign.body_unbuildable`, alongside the existing `ac`, `write`, `epic`, and `link` body guards.

## The `type: epic` fork (`jira-epic-lib.sh`)

- **`syncjs.umbrella.write_deferred`** (Info) — the Epic carries a populated live Epic Link, so Step 4 defers all writes to Step 9 (`jira-epic.sh`) to avoid type oscillation (BTG-036 / DEC-045).
- **`syncjs.epic.link_field_absent`** (Info) — the Jira instance has no *Epic Link* custom field, confirming single-level Epic projection (distinct from `syncjs.umbrella.epic_link_unreadable`, which halts when field discovery fails, DEC-046).
- **`syncjs.assign.skipped_epic`** (Info) — Epic assignees are human-managed and skipped before any call.
- **`syncjs.epic.scratch_unavailable`** / **`syncjs.epic.body_unbuildable`** (Warning, BTG-079 AC-1) — child Epic Link payload could not be staged or built; refuses the `PUT` and emits `epic_result=rejected` at exit `0` (DEC-033).

## Scratch staging and import seed (relocated)

Cataloged in `.agents/skills/cadence-sync-jira/jira-server-conditions-scratch.md` (BTG-247).

## Reservation pairing (`jira-reserve.sh`)

- **`syncjs.reserve.pairing_obligation`** (Info) — emitted **prior** to the reservation `POST` (record-before-contact), declaring that the reserved Jira key must be paired in the same governed operation with `specs/<id>/problem.md` and `specs/<id>/metadata.yaml` per `CADENCE_ORG.md` `#id-allocation-binding` (`idalloc.reserve.unpaired_artifact_creation`).
- **`syncjs.reserve.reserved`** (Info) — emitted upon reservation success, naming the exact `specs/<KEY>/problem.md` and `specs/<KEY>/metadata.yaml` paths required to complete pairing.
