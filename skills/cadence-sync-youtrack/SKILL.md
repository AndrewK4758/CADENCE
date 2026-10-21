---
name: cadence-sync-youtrack
description: Project specification metadata and lifecycle status to a self-hosted YouTrack Server instance via direct REST -- a lightweight orchestrator sequencing co-located single-operation shell scripts, authenticated with a permanent token held strictly in the operator environment.
argument-hint: 
arguments: [target]
allowed-tools: Read Glob Grep Bash
model: gemini-3.8-flash-high
---


## Task

Project repository specification artifacts to a **self-hosted YouTrack Server** instance (not YouTrack Cloud) for `$target`. Every YouTrack interaction executes as a **direct REST call inside a co-located, single-operation shell script**; this skill acts as a thin **orchestrator** that sequences those scripts, renders the description temp file they consume, routes verbose non-zero REST error payloads through `offload_log_triage`, and performs the single `metadata.yaml` write-back at the end of the sequence. It issues no direct YouTrack HTTP calls itself and embeds no custom field-mapping or validation logic -- all mapping and transport rules live inside the scripts where they are deterministically tested rather than inferred on each run.

> **Bounded context: Tracker Binding / YouTrack projection flow (CADENCE_ORG.md#tracker-binding, TS-1).**
> External invariant relied upon: the git repository is the sole system of record; YouTrack is a one-way projection target resolved via §9. This skill executes only when an adopter binds `#tracker-binding: youtrack`; whenever §9 resolves to `None` or to another tracker, every trigger executes a declared SKIP.
> Spec: archive/BTG-176/spec.md (Proposed Design).

> This adapter targets self-hosted YouTrack **Server**, which diverges from Jira Server and YouTrack Cloud in four architectural ways:
> - **Type-agnostic issue linking.** The `Subtask` link relation (`parent for` / `subtask of`) enforces no per-Type restriction, allowing an epic to parent another epic directly. Consequently, there is **no** umbrella or hierarchy-flattening replacement flow (unlike `/cadence-sync-jira`).
> - **No dedicated Acceptance-Criteria custom field.** Acceptance criteria are rendered **exclusively inside the issue description** (via `ticket_TEMPLATE.md`) and are never read back from a custom field during intake import.
> - **Plain single-field state model.** The `State` field operates over a single project-wide value bundle rather than a multi-hop workflow transition graph.
> - **Native Markdown descriptions.** Issue descriptions and comments render Markdown natively, requiring zero wiki-markup conversion on outbound or inbound paths.
>
> **Transport:** `curl` authenticated with a Bearer permanent token piped via `curl`'s `-K-` stdin configuration channel. Any request that fails to reach the server halts loud with **`syncyt.transport.rest_unreachable`** (exit 3), kept distinct from ticket-lookup failures; any non-2xx response halts loud with the operation's specific `syncyt.*` condition. **An HTTP 2xx status alone is never proof that a custom field update took effect** -- YouTrack Server responds 200 to a payload containing a field disallowed for the issue's Type while silently dropping the value -- so every field write is verified via an immediate read-back. Zero errors are swallowed and zero fallbacks happen silently.

### Where things live

| Read this | When |
|---|---|
| **this file** | sequencing a ticket sync, handling a halt, or consulting the step table |
| `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md` | modifying or invoking any single-operation script (inputs, stdout keys, exit codes, idempotency), or reviewing documented divergences from `/cadence-sync-jira` |
| `.agents/skills/cadence-sync-youtrack/youtrack-orchestration.md` | modifying how the orchestrator sequences steps, halts, emits completion/partial reports, renders the description temp file, or writes `metadata.yaml` |
| `.agents/skills/cadence-sync-youtrack/youtrack-server-config.json` | configuring settings that vary per repository or per YouTrack Server instance |

Read this file plus **at most one** companion document above, never all of them at once.

## Direction

Synchronization is strictly **one-directional: repository -> YouTrack.** The git repository is the authoritative source of truth; YouTrack serves as the downstream projection surface for product tracking, roadmapping, and capitalization accounting.

The outbound projection path **never uploads or modifies YouTrack attachments** -- an explicit non-goal. Attachment handling occurs strictly on the inbound `import` intake path (`yt-import.sh`), where an attachment's signed download URL is treated as a sensitive credential.

## Prerequisites

### 1. Environment

All YouTrack requests are direct REST calls executed by the co-located shell scripts. No intermediate daemon or container runtime is required -- only a POSIX shell with `curl`, `jq`, and `python3`.

| Variable | Purpose |
|---|---|
| `YOUTRACK_BASE_URL` | Root URL of the YouTrack Server instance, e.g. `https://youtrack.example.com` |
| `YOUTRACK_TOKEN` | Permanent authentication token (Bearer auth) |
| `YOUTRACK_PROJECT_KEY` | Target project shortName. **DEPRECATED as a project-key source** (BTG-179): resolution order is (1) the ticket prefix's `CADENCE_ORG.md` §9 table row -> (2) §9's scalar `**Project key(s):**` entry -> (3) this environment variable, which sunsets after ONE release cycle. Configure the project key in §9 instead: `docs/migrations/multi-tracker-binding.md` |
| `YOUTRACK_SELF` | *Optional.* Explicitly overrides the resolved operator login for assignee reconciliation; always takes precedence when set |

The environment variable *names* are configurable inside the `env` block of `.agents/skills/cadence-sync-youtrack/youtrack-server-config.json`, allowing adopters to remap variable names without editing scripts. The bearer token is read from the environment at request time and passed to `curl` over `-K-` stdin: it is never passed on argv, never written to a temporary file, artifact, or `metadata.yaml`, and never printed to stdout or stderr.

**Version floor (precondition): YouTrack Server `v2026.1.13162`.** Every REST request and response contract in this adapter was live-verified against that build; it defines our **verified support boundary** rather than asserting that earlier versions fail. Because the version endpoint responds without an `Authorization` header, the version precondition can be checked *prior* to authenticating -- keeping an unsupported server version distinct from a rejected token.

**Permissions.** Standard issue operations performed by this adapter -- issue read/create/update, issue linking, commenting, and posting effort work items (which requires time-tracking permission) -- work with a standard project-member token on the target project. **One step requires an additional read path, stated explicitly here: resolving the configured project `shortName` to YouTrack's internal project ID queries `GET /api/admin/projects`.** That lookup runs on every ticket sync prior to any write, because `/api/issues` filtered by project returns `[]` on an empty project (making ID resolution impossible) and `/api/agiles` covers only board-attached projects. **If the token lacks permission to read `GET /api/admin/projects`, project resolution fails** and the sync halts (`syncyt.config.project_unresolved` / `syncyt.config.project_read_refused`) before writing anything.

Note what is *not* asserted: we do not claim that `/api/admin/projects` requires a global system-admin role. While its URL path sits under `/api/admin/`, this adapter only reports what it observes (`401`/`403` vs `200`).

No dynamic schema discovery is performed: custom field types and enum bundles are never crawled. Instead, the adapter writes its intended value, reads the issue back, and reports any rejection or silent drop -- making `GET /api/admin/projects` the sole `/api/admin/` endpoint in the entire adapter (enforced by `youtrack-transport.test.sh` S-2.2).

### 2. Instance-specific settings live in the config sidecar

Issue-type, priority, and per-Type state mappings, conditional-field rules, assignment rules, link relation types, the three feature toggles, the attachment download ceiling, the sprint membership query, the pagination bound, and the worklog post-check capability marker all reside in `.agents/skills/cadence-sync-youtrack/youtrack-server-config.json`. Every key's missing/malformed fail-loud or default polarity is implemented once inside `.agents/skills/cadence-sync-youtrack/yt-lib.sh` and documented in `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md`.

### 3. Verify connectivity before syncing

Invoke `yt-connect.sh` first. It resolves the active operator identity (checking `YOUTRACK_SELF`, then a credential-fingerprinted cache outside the repository, and finally `GET /api/users/me`) and halts loud on an unreachable endpoint (exit 3) or rejected token (exit 1). All subsequent steps rely on Step 1 having succeeded.

## Orchestration — script sequencing, automatic log triage, and the single metadata write

This skill is a **lightweight orchestrator**: every YouTrack REST operation is encapsulated in an executable single-operation script in `.agents/skills/cadence-sync-youtrack/`, whose contract (CLI flags, stdout `key=value` lines, stderr `syncyt.*` audit conditions, exit codes, and idempotency) is specified in `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md`. The orchestrator runs those scripts in sequence, supplies the rendered description temp file, and performs the single `metadata.yaml` update at completion.

**Automatic local offload on verbose REST/script errors.** Whenever any `yt-*.sh` script exits non-zero or emits verbose REST error bodies / diagnostic output exceeding 30 lines on stderr, **automatically route the error output through `offload_log_triage` (`local-fast-cpu` on `:11434`)** to compact the noisy HTTP/JSON payload into verbatim `syncyt.*` conditions, HTTP status codes, and failing step coordinates while preserving the full unedited output in `/tmp/agy-last-triage.log` (never passing `YOUTRACK_TOKEN` or signed attachment URLs into any log).

**Capture the stdout payload.** Every script emits machine-readable results on stdout as `key=value` lines and human-readable `syncyt.*` audit lines on stderr. The orchestrator **accumulates all stdout `key=value` lines across the ticket's script sequence** into a single payload (`$YT_SYNC_PAYLOAD`) and derives the `metadata.yaml` delta strictly from that structured payload — never by scraping prose or stderr. The step runner **`yt_run_step`** is defined in `.agents/skills/cadence-sync-youtrack/youtrack-orchestration.md`.

**Every step belongs to one of two classes.** Step class is an attribute of the *step*, not of the exit code:

| Class | Steps | Behavior on non-zero exit |
|---|---|---|
| **blocking** | `yt-connect`, `yt-resolve`, `yt-preserve`, `yt-write-issue`, `yt-transition` | **Halt this ticket** immediately at the failing step |
| **best-effort** | `yt-worklog`, `yt-assign`, `yt-link`, `yt-epic` | Still **halt** on non-zero exit — see below |

A best-effort script indicates a *sanctioned refusal* by exiting **0** while emitting a structured `*_result=` key on stdout (`assign_result=rejected`, `link_result=skipped`, `epic_result=skipped`, etc.) alongside its `syncyt.*` warning on stderr; the ticket sequence continues and records the refusal in the final completion report. Being best-effort permits a sanctioned refusal on exit `0`, **never immunity for script failures**: if a best-effort script exits non-zero (due to a transport outage, malformed config, missing CLI flag, or crash), it has *faulted* rather than refused, and the orchestrator halts the ticket immediately. Thus, `yt_run_step` keys its halt decision strictly off a non-zero exit code regardless of class.

**Halts are loud and leave already-applied tracker state intact and visible.** When a ticket halts mid-sequence, the orchestrator **never** rolls back prior steps, **never** issues compensating deletes/updates, and **never** auto-retries — effects already applied by earlier steps remain in YouTrack (indeed, a newly created issue is the ticket's identity and a posted work item is immutable). Instead, the orchestrator emits a structured **partial-completion report** (`yt_emit_partial_report`, enforced by `yt_assert_partial_report_emitted`) detailing: which steps finished and their exact `key=value` effects, which step halted along with its exit code and `syncyt.*` condition, and which remaining steps were not executed. Because operator re-run is the recovery mechanism, failing to emit a partial-completion report on a halt is itself a critical defect (`syncyt.orchestrator.partial_report_absent`).

**The orchestrator is the exclusive writer of `metadata.yaml`.** Individual `yt-*.sh` scripts **never modify** `metadata.yaml` or any other repository artifact; they only read it. The orchestrator updates `metadata.yaml` **once, at the conclusion of the ticket sequence** (`yt_apply_metadata_writes`), only after all steps succeed — meaning any mid-sequence halt leaves `metadata.yaml` byte-untouched so a subsequent operator re-run re-derives state cleanly. Because `yt_apply_metadata_writes` sets each scalar key idempotently (set-or-append, never duplicating keys), re-running after a halt converges cleanly.

> **One non-convergent window is explicitly called out.** Because `youtrack_url` in `metadata.yaml` is the sole mapping from a repo ticket to its YouTrack issue (with no fuzzy summary search fallback), if an initial sync creates a brand-new YouTrack issue in Step 4 and then halts in Steps 5–9 **before** `yt_apply_metadata_writes` records `youtrack_url`, `metadata.yaml` still has no `youtrack_url`. Re-running blindly would create a **duplicate issue** in YouTrack. Always check the YouTrack project (or record the created `youtrack_url=` reported in `yt_emit_partial_report`'s `effect:` lines) before re-running an initial create sync that halted mid-sequence.

All orchestration functions -- `yt_run_step`, `yt_emit_partial_report` / `yt_assert_partial_report_emitted`, `yt_emit_completion_report`, `yt_apply_metadata_writes`, and `yt_sync_one_ticket` -- are defined in `.agents/skills/cadence-sync-youtrack/youtrack-orchestration.md` and `.agents/skills/cadence-sync-youtrack/youtrack-orchestration-sequence.md`.

## Steps

### Single Ticket Sync (`$target` = ticket ID)

Execute each step through `yt_run_step`, accumulating stdout `key=value` pairs into `$YT_SYNC_PAYLOAD` and checking for halts. Full per-script contracts live in `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md`. Every script is executable and invoked directly.

The canonical step invocation lives in `yt_sync_one_ticket` inside `.agents/skills/cadence-sync-youtrack/youtrack-orchestration-sequence.md`. The table below summarizes the 9-step pipeline; always quote shell variables (`"$ISSUE"`, `"$ID"`, `"$TMP"`, `"$PID"`, `"$SELF"`) so an empty variable never shifts positional flags.

| # | Step | Script | Class |
|---|---|---|---|
| 1 | Connectivity + operator self identity | `yt-connect.sh` | blocking |
| 2 | Project resolution + create-vs-update | `yt-resolve.sh --ticket "$ID"` | blocking |
| 3 | Preserve as-filed original comment (**update path only**) | `yt-preserve.sh --issue "$ISSUE"` | blocking |
| 4 | Render description temp file, then create/update issue | `yt-write-issue.sh --ticket "$ID" --description-file "$TMP" [--project "$PID" \| --issue "$ISSUE"]` | blocking |
| 5 | State projection | `yt-transition.sh --ticket "$ID" --issue "$ISSUE"` | blocking |
| 6 | Per-stage effort work items | `yt-worklog.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |
| 7 | Assignee reconciliation | `yt-assign.sh --ticket "$ID" --issue "$ISSUE" --self "$SELF"` | best-effort |
| 8 | Related-ticket issue links | `yt-link.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |
| 9 | Epic parent link (type-agnostic; **no** re-type, Move, or flatten) | `yt-epic.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |

Four argument rules are critical:
1. `yt-preserve.sh` accepts **`--issue` only** and runs **exclusively on the `update` branch** (on `create`, no issue exists yet). It snapshots the as-filed summary, description, and fields into a preservation comment *before* Step 4 overwrites the description, halting immediately if preservation fails so original content is never lost.
2. Step 4 passes `--project "$PID"` when `mode=create` and `--issue "$ISSUE"` when `mode=update`.
3. `$SELF` is the login emitted by Step 1 (`yt-connect.sh`); if `$SELF` is empty, any status mapped to `self` in `assignment_map` is refused.
4. Every step from Step 5 onward passes the **internal** issue ID (`issue_id=2-NNNN`) emitted by Step 4, never the readable key (`KEY-N`), because YouTrack's link endpoint rejects readable IDs inside request bodies with HTTP 400.

**Per-stage effort projection (Step 6)** posts each new `stage_effort` entry from `metadata.yaml` as an **individual** YouTrack work item (never posting or reconciling the cumulative `actual_effort` scalar), applying the repository's §12 effort-rounding rule by reference without hardcoding multiplier constants. Candidate selection relies exclusively on the repo-owned `worklog_watermark_at` timestamp (`entry.at > worklog_watermark_at`), **never** by diffing against existing tracker work items, ensuring manual operator adjustments in YouTrack are never overwritten. Posted work items are **strictly immutable (never updated or deleted)**. Watch the stderr audit stream for three key conditions: `syncyt.worklog.watermark_seeded` (a legacy ticket with effort entries but no prior watermark seeds the watermark forward without backfilling historical items), `syncyt.worklog.postcheck_failed` (the post-add read-back did not confirm absorption, leaving the watermark unadvanced), and `syncyt.worklog.marker_scan_rejected` (the bounded crash-recovery marker scan failed, halting worklog posting for the batch rather than risking duplicate items).

**Operator / agent worklog split (opt-in, BTG-315).** By default, `yt-worklog.sh` attributes 100% of each stage's effort to the operator. When the ticket prefix's row in `CADENCE_ORG.md` §9 specifies a login in its fifth column (`Agent-time user`), each candidate `stage_effort` entry is split into two work items -- an operator leg and an agent leg carrying that configured login in the work item's native `author` field -- using the per-stage split ratio defined in `CADENCE_ORG.md` §19 (or overridden per operator via `CADENCE_WORKLOG_FACTOR_<STAGE>`). Leaving the fifth column blank preserves byte-identical single-item behavior. See `docs/migrations/worklog-agent-attribution.md` for configuration details and `syncyt.worklog.agent_leg_rejected` for the non-halting warning emitted when the operator token lacks `JetBrains.YouTrack.CREATE_NOT_OWN_WORK_ITEM` permission.

### Step 4 — rendering the per-projection description temp file

**Render the issue description into a brand-new temporary file.** Because description assembly synthesizes prose from `problem.md` and fields from `metadata.yaml`, the orchestrator renders this file and passes its path to `yt-write-issue.sh`:

- Populate every `{{token}}` in **`ticket_TEMPLATE.md`** using the repository artifacts specified in its *Token sources* table (`specs/{target}/problem.md` or `archive/{target}/problem.md`, plus `metadata.yaml`), following all *Rendering rules* (stripping `> **Probe:**` blockquotes, `_Answer:_` lines, and `<!-- ... -->` HTML comments). Never post `problem.md` raw. Because YouTrack Server renders Markdown natively and `ticket_TEMPLATE.md` is authored in Markdown, no markup translation occurs.
- Include the rendered **`## Acceptance Criteria` section** inside the description body: because YouTrack Server has no separate Acceptance Criteria custom field, the description is the sole surface where acceptance criteria are projected.
- Set the issue summary to the ticket's `title` **verbatim** without prepending the ticket ID.
- Write the completed Markdown body — including the Traceability table rows for `spec_link`, `spec_mr_link`, and `merge_request_link` — to a **freshly allocated** `mktemp` file (`render_description_tempfile`), and pass that file path via `--description-file`.
- **Allocate a fresh `mktemp` file for every single projection, never reusing paths** across retries or across tickets in a bulk sync. `yt-write-issue.sh` unlinks the temp file on every exit path, guaranteeing stale prose from a prior ticket can never leak into a subsequent ticket.
- **Never** write `YOUTRACK_TOKEN` into the description temp file.

See `render_description_tempfile` in `.agents/skills/cadence-sync-youtrack/youtrack-orchestration.md` for the reference implementation.

Once Step 9 finishes cleanly, invoke `yt_apply_metadata_writes` once to atomically update `metadata.yaml`.

### Bulk Sync (`$target` = "all")

1. **Discover tickets:** locate all `metadata.yaml` files across `specs/*/` and `archive/*/`.
2. **Execute the per-ticket pipeline independently for each ticket:** reset per-ticket accumulator variables, generate a **fresh `mktemp` description file inside the loop** (`render_description_tempfile "$id"`), and run `yt_sync_one_ticket`.
3. **Isolate per-ticket halts:** if one ticket halts, emit its partial-completion report (`yt_emit_partial_report`), leave its `metadata.yaml` untouched, record it in the halted list, and **advance to the next ticket**. One ticket's failure must never block independent sibling tickets from syncing. See `bulk_sync_tickets` in `.agents/skills/cadence-sync-youtrack/youtrack-orchestration-sequence.md`.
4. **Emit the comprehensive batch summary:** report per-ticket and aggregate counts for issues created, issues updated, states applied, work items posted/suppressed/disabled, **agent legs rejected** (`agent_legs_rejected` in split mode only -- BTG-315; omitted when unconfigured), assignments applied/skipped/rejected, issue links created/skipped, epic parent links applied/skipped, and an **explicit itemized list of every halted ticket** naming its failed step, `syncyt.*` condition, and exit code.

## Intake operations (inbound)

Inbound operations used by `/cadence-triage` and `/cadence-implement` are likewise standalone executable scripts in `.agents/skills/cadence-sync-youtrack/`, operating strictly read-only against repository files (never modifying `metadata.yaml`):

| Operation | Script | Stdout return keys |
|---|---|---|
| `reserve` (`$target` = "reserve") | `yt-reserve.sh --summary "<text>" [--type <repo-type>]` | `issue_id=` / `issue_readable=` / `youtrack_url=` -- the authoritative ID allocated by **YouTrack**; halts loud on failure rather than guessing an ID |
| `import` (`$target` = "import") | `yt-import.sh --issue <KEY-N> [--ticket <id>]` | `seed_dir=` / `summary_file=` / `description_file=` / `manifest_file=` / `attachments_downloaded=` / `attachments_referenced=` / `type_hint=` -- seed files used to author `problem.md` |
| `sprint-check` (`$target` = "sprint-check {ticket-id}") | `yt-sprint-check.sh --ticket <id>` | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive` |

`reserve` **emits its pairing obligation audit record prior to contacting YouTrack**: any tracker ID reserved by this call must be paired in the same governed workflow with `specs/<id>/problem.md` and `specs/<id>/metadata.yaml`, and leaving an orphan issue without repo artifacts violates `idalloc.reserve.unpaired_artifact_creation` per `CADENCE_ORG.md` `#id-allocation-binding` (Reservation pairing). Emitting the obligation before the network request ensures an aborted call is auditable. When the repository's allocation binding is `mint-by-convention`, `reserve` makes **zero** YouTrack requests and emits no tracker-reservation audit line, though the locally minted ID remains bound by the exact same artifact-pairing invariant (`idalloc.reserve.unpaired_artifact_creation`).

`import` writes fetched issue fields into a single temporary `seed_dir=` directory. The caller is responsible for removing `seed_dir` after authoring `problem.md` (if `yt-import.sh` itself fails, it cleans up `seed_dir` before exiting). Because YouTrack Server has **no dedicated acceptance-criteria custom field**, `import` never populates acceptance criteria from a custom field. Attachments are downloaded only up to `attachment_size_ceiling_mib`, **failing closed** (referencing all attachments and downloading none) if the ceiling setting is missing or invalid. **Crucially, YouTrack Server attachment download URLs contain a pre-signed `sign=` query token that serves file bytes without an `Authorization` header** -- therefore attachment URLs are treated as credentials and are never written to logs, error messages, or repository artifacts (diagnostics record only the attachment ID and HTTP status code).

`sprint-check` executes the single configured `sprint_query` and emits one of three distinct verdicts: `in-sprint`, `not-in-sprint` (issue exists on the server but does not match the sprint query), or `inconclusive` (issue ID does not exist, query is unconfigured, or server is unreachable). An HTTP `400` response is **always mapped to `inconclusive`, never `not-in-sprint`**, and issue lookup is strictly verbatim (never falling back to a fuzzy summary search).

**Definition of "synced":** because the git repository is the system of record and YouTrack is a downstream projection, a ticket is synced only when a complete run of this skill has projected its latest repository state -- never merely because tracker fields appear superficially similar.

## §9 binding resolution (vendor-neutral)

Prior to issuing any external tracker write, resolve the repository's tracker binding from `CADENCE_ORG.md#tracker-binding` and emit the **`syncyt.resolve.tracker`** audit line (recording resolved tracker, binding source, and mapped skill) **before** contacting YouTrack. On scoped-projection runs, emit a **per-item fail-closed audit record** (`item-id`, `owned-flag`, `action`) prior to each board write (PI-030); foreign issues lacking a repository `specs/<id>/` directory are skipped with an audit notice and zero tracker writes. Whenever the ticket prefix's §9 row (or covering `*` wildcard row) resolves to `None -- inner-source`, every trigger logs `"no external tracker bound (inner-source); skipped"` and performs **zero external tracker calls** (BTG-242).

## Error handling

All error and audit conditions are emitted as structured `syncyt.<family>.<condition>` lines on stderr, and **no error is ever silently ignored**. If a script exits non-zero with verbose output (`>30` lines), automatically invoke `offload_log_triage` (`local-fast-cpu` on `:11434`) to extract the exact `syncyt.*` condition and HTTP status while saving the full log to `/tmp/agy-last-triage.log`. Five core rules govern all scripts (full catalog in `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md`):

1. **Unreachable transport** exits **3** with `syncyt.transport.rest_unreachable`, kept distinct from issue-lookup failures, and includes `curl`'s transport error detail so DNS, TLS, and proxy failures remain distinguishable.
2. **Rejected credentials are authentication failures, not transport failures.** When the server responds with `401`/`403`, `syncyt.connect.auth_rejected` (exit 1) names the token variable and relays the server's message.
3. **Every non-2xx HTTP status is a failure** reported with its status code under the step's condition — and **even a 2xx status requires read-back confirmation** (`syncyt.write.field_not_applied`) before a field write is considered applied.
4. **Disabled feature toggles are intentional policy opt-outs, not errors** (`syncyt.worklog.disabled`, `syncyt.link.disabled`, `syncyt.assign.disabled`); however, a **malformed** toggle or missing capability marker triggers an immediate config **HALT** (exit 4) rather than silently defaulting to disabled.
5. **Best-effort steps halt only their own feature branch on tracker refusal, never the entire ticket** — emitting their `syncyt.*` condition on stderr and exiting **0** with `*_result=rejected` or `*_result=skipped` on stdout.

## Example

```
/cadence-sync-youtrack BTG-6
/cadence-sync-youtrack all
```
