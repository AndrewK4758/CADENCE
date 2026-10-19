---
name: cadence-sync-jira
description: Project specification metadata and lifecycle status to a Jira Server / Data Center instance via direct REST v2 -- a lightweight orchestrator sequencing co-located single-operation shell scripts, authenticated with a Personal Access Token held strictly in the operator environment.
argument-hint: 
arguments: [target]
allowed-tools: Read Glob Grep Bash
model: gemini-3.8-flash-high
---


## Task

Project repository specification artifacts to an on-premises **Jira Server / Data Center** instance for `$target`. Every Jira operation executes as a **direct REST v2 call inside a co-located, single-operation shell script**; this skill acts as a thin **orchestrator** that sequences those scripts, renders the description temp file they consume, routes verbose non-zero REST error payloads through `offload_log_triage`, and invokes the dedicated `jira-metadata-write.sh` writer to update `metadata.yaml`. It issues no direct Jira HTTP calls itself and embeds no custom field-mapping or validation logic -- all mapping and transport rules live inside the scripts where they are deterministically tested rather than inferred on each run.

> This adapter targets Jira **Server / Data Center**, which differs from Jira **Cloud** in two fundamental ways:
> - Server/DC authenticates with a **Bearer Personal Access Token (PAT)** against REST **v2**, whereas Cloud uses Basic `email:api-token` against REST v3. (CADENCE ships no Jira Cloud adapter -- BTG-299 retired it; see `docs/migrations/sync-jira-removal.md`.)
> - Issue descriptions in REST v2 use **Jira wiki markup** natively (whereas Cloud uses ADF JSON) -- so the templates in this directory are authored in wiki markup and Markdown prose fragments are piped through the deterministic `jira-md2wiki.sh` filter.
>
> **Transport:** `curl` authenticated with a Bearer PAT supplied on `curl`'s `-K-` stdin configuration channel. Any request that fails to reach the server halts loud with **`syncjs.transport.rest_unreachable`** (exit 3), kept distinct from ticket-lookup failures; any non-2xx HTTP status halts loud with the operation's specific `syncjs.*` condition. Zero errors are swallowed and zero fallbacks happen silently.

### Where things live

| Read this | When |
|---|---|
| **this file** | sequencing a ticket sync, handling a halt, or consulting the step table |
| `.agents/skills/cadence-sync-jira/jira-server-scripts.md` | modifying or invoking any single-operation script (inputs, stdout keys, exit codes, idempotency) |
| `.agents/skills/cadence-sync-jira/jira-server-orchestration.md` | modifying how the orchestrator sequences steps, halts, emits partial/completion reports, renders the description temp file, or invokes `jira-metadata-write.sh` |
| `.agents/skills/cadence-sync-jira/jira-server-conditions.md` | interpreting or adding a `syncjs.*` stderr audit condition |
| `.agents/skills/cadence-sync-jira/jira-server-scripts-umbrella.md` / `.agents/skills/cadence-sync-jira/jira-server-conditions-umbrella.md` | modifying the umbrella replacement flow (`jira-epic.sh` + `jira-umbrella-lib.sh`) or its conditions -- the modular companion segments of the two indexes above |

Read this file plus **at most one** companion document above, never the entire directory at once. The `-umbrella` files are modular segments split off under the `<400`-line Developer Experience ceiling -- read them *instead of* their parent index when working on the umbrella replacement flow.

## Direction

Synchronization is strictly **one-directional: repository -> Jira.** The git repository is the authoritative source of truth; Jira serves as the downstream projection surface for product management, roadmapping, and software capitalization accounting.

The outbound projection path **never uploads or modifies Jira attachments** — an explicit non-goal (`jira-write-issue.sh` contains no attachment code path; see `.agents/skills/cadence-sync-jira/jira-server-scripts.md`). Attachment flow occurs exclusively on the inbound `import` intake path (`jira-import.sh`).

## Prerequisites

### 1. Environment

Every Jira request is a direct REST v2 call executed by a co-located shell script. No intermediate server or container runtime is required -- only a POSIX shell with `curl`, `jq`, and `python3`.

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | Root URL of the Jira Server/DC instance, e.g. `https://jira.example.com` |
| `JIRA_PAT` | Personal Access Token (Server/DC Bearer auth) |
| `JIRA_PROJECT_KEY` | Target project key. **DEPRECATED as a project-key source** (BTG-179): resolution order is (1) the ticket prefix's `CADENCE_ORG.md` §9 table row -> (2) §9's scalar `**Project key(s):**` entry -> (3) this environment variable, which sunsets after ONE release cycle. Configure the project key in §9 instead: `docs/migrations/multi-tracker-binding.md` |
| `JIRA_SELF` | *Optional.* Explicitly overrides the resolved operator username for assignee reconciliation; always takes precedence when set |

The environment variable *names* are configurable inside the `env` block of `.agents/skills/cadence-sync-jira/jira-server-config.json`, allowing adopters to rebind variable names without editing scripts. The PAT is read from the environment at request time and piped to `curl` over `-K-` stdin: it is never passed on argv, never written to a temporary file, artifact, or `metadata.yaml`, and never echoed to stdout or stderr.

### 2. Instance-specific settings live in the config sidecar

Issue-type and priority mappings, per-type workflow transition graphs, assignment rules, link relation types, the Acceptance Criteria custom field name, the three feature toggles, the run-mode binding, the worklog post-check capability marker, and the attachment size ceiling all reside in `.agents/skills/cadence-sync-jira/jira-server-config.json`. Every key's missing/malformed fail-loud or default polarity is implemented once inside `.agents/skills/cadence-sync-jira/jira-lib.sh` and documented in `.agents/skills/cadence-sync-jira/jira-server-scripts.md`.

### 3. Verify connectivity before syncing

Invoke `jira-connect.sh` first. It resolves the active operator identity (checking `JIRA_SELF`, then a credential-fingerprinted cache outside the repository tree, and finally `GET /rest/api/2/myself`) and halts loud on an unreachable endpoint (exit 3) or rejected credential (exit 1). All subsequent steps rely on Step 1 having succeeded.


## Orchestration — script sequencing, automatic log triage, and the dedicated metadata writer

This skill is a **lightweight orchestrator**: every Jira REST v2 operation is encapsulated in an executable single-operation script in `.agents/skills/cadence-sync-jira/`, whose contract (CLI flags, stdout `key=value` lines, stderr `syncjs.*` audit conditions, exit codes, and idempotency) is specified in `.agents/skills/cadence-sync-jira/jira-server-scripts.md`. The orchestrator runs those scripts in sequence, supplies the rendered wiki-markup description temp file, and invokes `jira-metadata-write.sh` to update `metadata.yaml`.

**Automatic local offload on verbose REST/script errors.** Whenever any `jira-*.sh` script exits non-zero or emits verbose REST error bodies / diagnostic output exceeding 30 lines on stderr, **automatically route the error output through `offload_log_triage` (`local-fast-cpu` on `:9379`)** to compact the noisy HTTP/JSON payload into verbatim `syncjs.*` conditions, HTTP status codes, Jira `errorMessages`/`errors`, and failing step coordinates while preserving the full unedited output in `/tmp/agy-last-triage.log` (never passing `JIRA_PAT` into any log).

**Capture the stdout payload.** Every script emits machine-readable results on stdout as `key=value` lines and human-readable `syncjs.*` audit lines on stderr. The orchestrator **accumulates all stdout `key=value` lines across the ticket's script sequence** into a single payload (`$SYNC_PAYLOAD`) and derives the `metadata.yaml` delta strictly from that structured payload — never by scraping prose or stderr. The step runner **`run_step`** is defined in `.agents/skills/cadence-sync-jira/jira-server-orchestration.md`.

**Every step belongs to one of two classes.** Step class is an attribute of the *step*, not of the exit code:

| Class | Steps | Behavior on non-zero exit |
|---|---|---|
| **blocking** | `jira-connect`, `jira-resolve`, `jira-preserve`, `jira-write-issue`, `jira-transition`, `jira-worklog` | **Halt this ticket** immediately at the failing step (DEC-008) |
| **best-effort** | `jira-assign`, acceptance-criteria write, `jira-link`, `jira-epic` | Still **halt** on non-zero exit — see below |

A best-effort script indicates a *sanctioned refusal* by exiting **0** while emitting a structured `*_result=` key on stdout (`assign_result=rejected`, `link_result=skipped`, etc.) alongside its `syncjs.*` warning on stderr; the ticket sequence continues and records the refusal in the final report. Being best-effort permits a sanctioned refusal on exit `0`, **never immunity for script failures**: if a best-effort script exits non-zero (due to a transport outage, malformed config, missing CLI flag, or crash), it has *faulted* rather than refused, and the orchestrator halts the ticket immediately. Thus, `run_step` keys its halt decision strictly off a non-zero exit code regardless of class.

**Halts are loud and leave already-applied tracker state intact and visible (DEC-008).** When a ticket halts mid-sequence, the orchestrator **never** rolls back prior steps, **never** issues compensating requests, and **never** auto-retries — effects already applied by earlier steps remain in Jira. Instead, the orchestrator emits a structured **partial-completion report** (`emit_partial_report`, enforced by `assert_partial_report_emitted`) detailing: which steps finished and their exact `key=value` effects, which step halted along with its exit code and `syncjs.*` condition, and which remaining steps were not executed. Because operator re-run is the recovery mechanism, failing to emit a partial-completion report on a halt is itself a critical defect (`syncjs.orchestrator.partial_report_absent`).

**One dedicated writer script (`jira-metadata-write.sh`), invoked exclusively by the orchestrator, is the sole writer of `metadata.yaml`.** Individual operation scripts **never modify** `metadata.yaml` or any other repository artifact; they only read it. `jira-metadata-write.sh` (BTG-125) applies updates **at end-of-operation** after the full sequence completes — plus two targeted **early writes** (recording `jira_url` immediately after Step 4 creates a new issue, and recording `umbrella_epic_url` immediately after Step 9 creates a replacement umbrella issue) so that a subsequent halt cannot cause a re-run to mint a duplicate issue (DEC-008/DEC-009). Re-applying the same scalar value is byte-idempotent (each field is set in place rather than duplicated), making operator re-runs after a halt completely safe.

All orchestration helpers -- `run_step`, `emit_partial_report` / `assert_partial_report_emitted`, the three `jira-metadata-write.sh` call sites, and `render_description_tempfile` -- are defined in `.agents/skills/cadence-sync-jira/jira-server-orchestration.md`.

## Steps

### Single Ticket Sync (`$target` = ticket ID)

Execute each step through `run_step`, accumulating stdout `key=value` pairs into `$SYNC_PAYLOAD` and checking for halts. Full per-script contracts live in `.agents/skills/cadence-sync-jira/jira-server-scripts.md`. Every script is executable and invoked directly.

The canonical step invocation lives in `sync_one_ticket` inside `.agents/skills/cadence-sync-jira/jira-server-orchestration.md`. The table below summarizes the 9-step pipeline; always quote shell variables (`"$KEY"`, `"$ID"`, `"$MODE"`, `"$TMP"`, `"$SELF"`) so an empty variable never shifts positional flags.

| # | Step | Script | Class |
|---|---|---|---|
| 1 | Connectivity + operator self identity | `jira-connect.sh` | blocking |
| 2 | Create-vs-update resolution | `jira-resolve.sh --ticket "$ID"` | blocking |
| 3 | Preserve as-filed original comment (**update path only**, non-Epic) | `jira-preserve.sh --issue-key "$KEY"` | blocking |
| 4 | Render wiki description temp file, then create/update issue | `jira-write-issue.sh --ticket "$ID" --mode "$MODE" [--issue-key "$KEY"] [--description-file "$TMP"]` | blocking |
| 5 | Workflow status transition | `jira-transition.sh --ticket "$ID" --issue-key "$KEY"` | blocking |
| 6 | Per-stage effort worklogs | `jira-worklog.sh --ticket "$ID" --issue-key "$KEY"` | blocking |
| 7 | Assignee reconciliation | `jira-assign.sh --ticket "$ID" --issue-key "$KEY" --self "$SELF"` | best-effort |
| 8 | Related-ticket issue links | `jira-link.sh --ticket "$ID" --issue-key "$KEY"` | best-effort |
| 9 | Epic association (and, for an umbrella Epic, its **replacement**: mint replacement issue at configured type, migrate child links, close superseded original, and emit `umbrella_epic_url=` plus `jira_url=` on completion) | `jira-epic.sh --ticket "$ID" --issue-key "$KEY"` | best-effort |

Three argument rules are critical:
1. `jira-preserve.sh` accepts **`--issue-key` only** (passing `--ticket` causes an exit 2 usage halt at a blocking step); Step 3 is skipped entirely on the **create** path (where no issue exists yet) and for `type: epic` tickets.
2. `$SELF` is the username resolved by Step 1 (`jira-connect.sh`); if `$SELF` is empty, any status mapped to `self` in `assignment_map` is refused.
3. On `mode=create`, `jira-metadata-write.sh` is called immediately after Step 4 to persist `jira_url` before Step 5 runs.

**Step 6 — operator / agent worklog split (opt-in, BTG-315).** By default, `jira-worklog.sh` attributes 100% of each stage's effort to the operator. When the ticket prefix's row in `CADENCE_ORG.md` §9 specifies a username in its fifth column (`Agent-time user`), each candidate `stage_effort` entry is split into two worklogs -- an operator leg and an agent leg attributed to that configured user -- using the per-stage split ratio defined in `CADENCE_ORG.md` §19 (or overridden per operator via `CADENCE_WORKLOG_FACTOR_<STAGE>`). Leaving the fifth column blank preserves byte-identical single-worklog behavior. See `docs/migrations/worklog-agent-attribution.md` for configuration details and `syncjs.worklog.agent_leg_rejected` / `syncjs.worklog.agent_leg_status_ambiguous` (BTG-319) for the two agent-leg conditions -- the former when the plugin permanently rejects the configured user (forfeiting the agent leg without halting), and the latter when the plugin returns an ambiguous non-2xx status (halting the ticket so a re-run retries only the missing agent leg).

### Step 4 — rendering the per-projection description temp file (AC-4)

**Render the issue description into a brand-new temporary file** (**skipping entirely for `type: epic`** — an Epic's Description remains empty). Because description assembly synthesizes prose from `problem.md` and fields from `metadata.yaml`, the orchestrator renders this file and passes its path to `jira-write-issue.sh`:

- Populate every `{{token}}` in **`ticket_TEMPLATE.md`**'s wiki-markup body from the repository artifacts specified in its *Token sources* table (`specs/{target}/problem.md` or `archive/{target}/problem.md`, plus `metadata.yaml`), following all *Rendering rules* — piping each extracted Markdown fragment through **`jira-md2wiki.sh`** (and `{{functional_validation}}` with `--functional-validation`) to convert Markdown into **Jira wiki markup** while stripping `> **Probe:**` blockquotes, `_Answer:_` lines, and HTML comments. Never post `problem.md` raw. Because Jira Server/DC REST v2 renders wiki markup natively, the body is sent as wiki markup.
- Write the completed wiki-markup description — including the Traceability table rows for `spec_link`, `spec_mr_link`, and `merge_request_link` — to a **freshly allocated** `mktemp` file (`render_description_tempfile`), and pass that path via `--description-file`.
- **Allocate a fresh `mktemp` file for every single projection, never reusing paths** across retries or across tickets in a bulk sync. `jira-write-issue.sh` unlinks the temp file on every exit path (success or halt), guaranteeing stale prose from a prior ticket can never leak into a subsequent ticket.
- **Never** write `JIRA_PAT` into the description temp file.

See `render_description_tempfile` in `.agents/skills/cadence-sync-jira/jira-server-orchestration.md` for the reference implementation.

`type: epic` is the sole sanctioned exception to Step 4: an Epic carries neither a rendered description nor an Original Estimate.

Once Step 9 finishes cleanly, the orchestrator invokes `jira-metadata-write.sh` one final time carrying all accumulated keys (`jira_url`, `worklog_watermark_at`, `umbrella_epic_url`), converging byte-identically with any early writes (BTG-125).


### Bulk Sync (`$target` = "all")

1. **Discover tickets:** locate all `metadata.yaml` files across `specs/*/` and `archive/*/`.
2. **Execute the per-ticket pipeline independently for each ticket:** reset per-ticket accumulator variables, generate a **fresh `mktemp` description file inside the loop** (`render_description_tempfile "$id"`), and run `sync_one_ticket` (AC-4).
3. **Isolate per-ticket halts:** if one ticket halts (a blocking script exited non-zero), emit its partial-completion report (`emit_partial_report`), leave its remaining `metadata.yaml` delta unwritten, record it in the halted list, and **advance to the next ticket**. One ticket's failure must never block independent sibling tickets from syncing. See `bulk_sync_tickets` in `.agents/skills/cadence-sync-jira/jira-server-orchestration.md`.
4. **Emit the comprehensive batch summary:** report per-ticket and aggregate counts for issues created, issues updated, transitions applied, worklogs posted/skipped/**disabled**, **agent legs rejected** (`agent_legs_rejected`, split mode only -- BTG-315; omitted, never zero, when unconfigured), assignments applied/skipped/disabled/rejected, Acceptance Criteria field imported/projected/disabled/skipped (`syncjs.ac.*`), issue links created, and the three link reference counters -- `references_unreadable` / `references_unresolved` / `references_skipped` (BTG-107 AC-2). Name each non-zero counter explicitly. When all three reference counters are `0`, state that clean outcome **affirmatively** -- `"no reference was unreadable, unresolved or skipped"` -- never omitting the statement. If any counter was **not returned** in the stdout payload, report it as **not returned** rather than `0`. Finally, list **each halted ticket** explicitly with its failing step, `syncjs.*` condition, and exit code, and list **each ticket with a non-zero reference account or agent-leg rejection by ticket ID** rather than folding them into a cross-ticket sum.

## Intake operations (inbound)

Inbound operations used by `/cadence-triage` and `/cadence-implement` are likewise standalone executable scripts in `.agents/skills/cadence-sync-jira/`, operating strictly read-only against repository files (never modifying `metadata.yaml`):

| Operation | Script | Stdout return keys |
|---|---|---|
| `reserve` (`$target` = "reserve") | `jira-reserve.sh --summary "<text>" [--type <repo-type>] [--prefix <PREFIX>]` | `issue_key=` / `jira_url=` -- the authoritative key allocated by **Jira**; halts loud on failure rather than guessing a key. `--prefix` is optional for single-project bindings but **REQUIRED** whenever `CADENCE_ORG.md` §9 declares a per-prefix table (halting with exit `4` `syncjs.config.project_key_precondition_unmet` if omitted) |
| `import` (`$target` = "import") | `jira-import.sh --issue-key <KEY> [--ticket <id>]` | `summary_file=` / `ac_items_file=` / `attachments_downloaded=` / `attachments_referenced=` -- seed files used to author `problem.md` |
| `sprint-check` (`$target` = "sprint-check {ticket-id}") | `jira-sprint-check.sh --ticket <id>` | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive` |

`import` writes fetched issue fields into a single temporary `seed_dir=` directory. The caller owns removing `seed_dir` after authoring `problem.md` (if `jira-import.sh` itself fails, it unlinks `seed_dir` before exiting, following the AC-4 temp-file lifecycle rule).

`sprint-check` runs a single `key=<KEY> AND sprint in openSprints()` JQL query. It is strictly **read-only** and emits one of three distinct verdicts: `in-sprint`, `not-in-sprint` (issue exists on the server but belongs to no open sprint), or `inconclusive` (issue key does not exist or cannot be resolved). An HTTP `400` response is **always mapped to `inconclusive`, never `not-in-sprint`**, and issue lookup is strictly verbatim without any fuzzy summary-search fallback.

**Definition of "synced":** because the git repository is the system of record and Jira is a downstream projection, a ticket is synced only when a complete run of this skill has projected its latest repository state -- never merely because Jira and repository fields appear superficially similar. `import` downloads attachments only within `attachment_size_ceiling_mib` and **fails closed** (referencing all attachments by URL and downloading zero) when the ceiling is absent or malformed.


## Error handling

All error and audit conditions are emitted as structured `syncjs.<family>.<condition>` lines on stderr, and **no error is ever silently ignored**. If a script exits non-zero with verbose output (`>30` lines), automatically invoke `offload_log_triage` (`local-fast-cpu` on `:9379`) to extract the exact `syncjs.*` condition, HTTP status, and Jira `errorMessages`/`errors` while saving the full log to `/tmp/agy-last-triage.log`. Four core rules govern all scripts (full catalog in `.agents/skills/cadence-sync-jira/jira-server-conditions.md`):

1. **Unreachable transport** exits **3** with `syncjs.transport.rest_unreachable`, kept distinct from issue-lookup failures.
2. **Every non-2xx HTTP status is a failure**, surfaced with its HTTP status code and Jira's `errorMessages` / `errors` under the step's condition.
3. **Disabled feature toggles are intentional policy opt-outs, not errors** (`syncjs.worklog.disabled`, `syncjs.ac.disabled`); however, a **malformed** toggle or missing capability marker triggers an immediate config **HALT** (exit 4) rather than silently defaulting to disabled.
4. **Best-effort steps halt only their own feature branch on tracker refusal, never the entire ticket** — emitting their `syncjs.*` condition on stderr and exiting **0** with a named `*_result=` payload on stdout (DEC-033).

## Example

```
/cadence-sync-jira ORD-6
/cadence-sync-jira all
```
