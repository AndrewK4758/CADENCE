---
name: claire-sync-jira
description: Sync spec metadata and status to a Jira Server / Data Center instance over direct REST v2 -- a thin orchestrator that sequences co-located single-operation shell scripts, authenticated with a Personal Access Token held only in the operator environment
argument-hint: 
arguments: [target]
allowed-tools: Read Glob Grep Bash
model: gemini-3.8-flash-high
---


## Task

Synchronize repository spec artifacts to **Jira Server / Data Center** (on-prem) for the target
`$target`. Every Jira operation is a **direct REST v2 call issued by a co-located, single-operation
shell script**; this file is a thin **orchestrator** that sequences those scripts, supplies the content
they consume, and applies the one `metadata.yaml` write at the end. It performs no Jira call itself and
carries no field-mapping or validation logic -- that lives in the scripts, where it is mechanically
testable rather than re-derived by inference on every run.

> This skill targets Jira **Server/DC**, which differs from Jira **Cloud**:
> - Server/DC uses **PAT bearer** auth against REST **v2**; Cloud uses Basic email:api-token against v3.
>   (This framework ships no Cloud sync adapter -- BTG-299 removed it outright, on a first-party
>   maintainer attestation that its consumer set was empty. See
>   `docs/migrations/sync-jira-removal.md` for the manual path off it.)
> - Issue descriptions use **wiki markup** (Cloud uses ADF/JSON), which REST v2 renders natively -- so
>   the templates here are wiki markup and are never routed through a Markdown-converting path.
>
> **Transport:** `curl` with a Bearer PAT supplied on curl's `-K-` stdin config channel. A call that
> cannot reach the instance fails loud with **`syncjs.transport.rest_unreachable`** (exit 3), distinct
> from a ticket-resolution failure; a non-2xx fails loud with the operation's own named condition. No
> failure is ever swallowed and no fallback is ever silent.

### Where things live

| Read this | When |
|---|---|
| **this file** | sequencing a ticket, deciding a halt, reading the step table |
| `.claude/skills/claire-sync-jira/jira-server-scripts.md` | changing or calling any one operation script (its inputs, stdout keys, exit codes, re-run semantics) |
| `.claude/skills/claire-sync-jira/jira-server-orchestration.md` | changing how the orchestrator sequences, halts, reports, renders the description temp file, or writes `metadata.yaml` back |
| `.claude/skills/claire-sync-jira/jira-server-conditions.md` | interpreting or extending a `syncjs.*` reported condition |
| `.claude/skills/claire-sync-jira/jira-server-scripts-umbrella.md` / `.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md` | changing the umbrella replacement flow (`jira-epic.sh` + `jira-umbrella-lib.sh`) or its conditions -- the relocated halves of the two indexes above |

Read this file plus **one** of the rows, never the whole set. The `-umbrella` row is the relocated half
of the two indexes above it -- split, never truncated, under the 400-line DX ceiling -- so it is read
*instead of* its parent when the umbrella replacement flow is what you are changing, not in addition.

## Direction

This sync is **one-directional: repo -> Jira.** The repository is the source of truth. Jira is the
projection layer for product management, roadmapping, and software capitalization accounting.

The outbound path **never creates or updates Jira attachments** — a documented non-goal (see the
*Non-goal* recorded in `.claude/skills/claire-sync-jira/jira-server-scripts.md` -- `jira-write-issue.sh`
has no attachment path at all). Attachment flow is inbound-only, at the `import` intake operation
(`jira-import.sh`).

## Prerequisites

### 1. Environment

Every Jira call is a direct REST v2 request made by a co-located script. There is no intermediary
server and no container runtime to install -- a plain shell with `curl`, `jq` and `python3` is the whole
substrate.

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | Instance root, e.g. `https://jira.example.com` |
| `JIRA_PAT` | Personal Access Token (Server/DC bearer auth) |
| `JIRA_PROJECT_KEY` | Target project key. **DEPRECATED as the project-key source** (BTG-179): resolution is (1) the ticket prefix's `CLAIRE_ORG.md` §9 row -> (2) §9's scalar `**Project key(s):**` line -> (3) this variable, which sunsets after ONE release cycle. Declare the key in §9 instead: `docs/migrations/multi-tracker-binding.md` |
| `JIRA_SELF` | *Optional.* Pins the assignment identity; when set it always wins |

The variable NAMES are themselves configuration (the `env` block of
`.claude/skills/claire-sync-jira/jira-server-config.json`), so an adopter can rebind a name without editing
a script. The token is read from the environment at call time and handed to `curl` through a `-K-` stdin
config block: it is never a positional argument, never written to a temp file, an artifact or
`metadata.yaml`, and never echoed to any output channel.

### 2. Everything instance-specific lives in the config sidecar

Issue-type and priority maps, per-type workflow transitions, the assignment map, link relation types,
the acceptance-criteria field name, the three feature toggles, the run-mode binding, the worklog
post-check capability and the attachment ceiling are all read from
`.claude/skills/claire-sync-jira/jira-server-config.json`. Each key's absent/malformed polarity is defined
once, in `.claude/skills/claire-sync-jira/jira-lib.sh`, and documented in
`.claude/skills/claire-sync-jira/jira-server-scripts.md` -- no script re-derives one.

### 3. Verify connectivity before syncing

Run `jira-connect.sh`. It resolves the effective self identity (adopter override, then a
credential-fingerprinted cache outside the repo tree, then `GET /rest/api/2/myself`) and fails loud on an
unreachable transport (exit 3) or a rejected credential (exit 1). Every later step assumes it passed.


## Orchestration — the script sequence and the single metadata write

This skill is a **thin orchestrator**: every mechanical Jira operation is performed by a standalone,
single-operation script co-located with this file, and every script's interface (inputs, stdout
`key=value` outputs, exit codes, re-run semantics) is contracted in
`.claude/skills/claire-sync-jira/jira-server-scripts.md`. The skill sequences those scripts, supplies the
rendered content they consume, and applies the `metadata.yaml` update. It performs no Jira call itself.

**Capture the payload.** Each script writes its result to stdout as `key=value` lines and its audit
conditions to stderr. The orchestrator **accumulates the stdout lines of every script run for the
ticket** into one payload and parses that payload — never prose, never stderr — for the metadata delta.
The helper that does this is **`run_step`** in
`.claude/skills/claire-sync-jira/jira-server-orchestration.md`.

**Every step is one of exactly two classes.** The class is a property of the *step*, not of the failure:

| Class | Steps | On a non-zero exit |
|---|---|---|
| **blocking** | `jira-connect`, `jira-resolve`, `jira-preserve`, `jira-write-issue`, `jira-transition`, `jira-worklog` | **Halt this ticket** at that step (DEC-008) |
| **best-effort** | `jira-assign`, the acceptance-criteria write, `jira-link`, `jira-epic` | Still **halt** — see below |

A best-effort step signals a *sanctioned refusal* by exiting **0** with a named `*_result=` payload
(`assign_result=rejected`, `link_result=skipped`, …) plus its stderr condition; the sequence continues
and the refusal is carried in the payload so the run report names it. The class grants a sanctioned
refusal, **not blanket immunity**: a best-effort script that exits non-zero has not refused, it has
*broken* (a crash, a missing file, a failed usage check), and breakage is never swallowed. That is why
the halt decision reads the exit code alone and the class only decides which script is *allowed*
to report a refusal at all.

**A halt is loud, and it leaves partial work intact and VISIBLE (DEC-008).** On a halt the orchestrator
does **not** roll back, does **not** issue a compensating call, and does **not** auto-retry or
auto-resume — the effects the completed steps already applied stay in Jira. What it owes the operator
instead is a **partial-completion report** (`emit_partial_report`, guarded by
`assert_partial_report_emitted`): which steps completed and what effect each applied, which step failed
with its `syncjs.*` condition and exit code, and which steps remain un-run. Recovery is an operator
re-run, which the operator cannot judge without exactly that picture — so a halt that emitted no report
is itself a defect (`syncjs.orchestrator.partial_report_absent`).

**One dedicated writer script, invoked by the orchestrator, is the sole writer of `metadata.yaml`.** A
script **never writes** `metadata.yaml` (or any other owned artifact); it only reads it.
`jira-metadata-write.sh` (BTG-125) applies the update **at end-of-operation**, after the sequence has
completed — so a halt **before** any write in a run leaves `metadata.yaml` unchanged and the
already-applied Jira effects are re-derived from repo state on the operator's re-run (DEC-008/DEC-009) —
plus, on the create path and on an umbrella replacement, two EARLY calls that record `jira_url` /
`umbrella_epic_url` the moment each is known, so a later halt cannot cause a re-run to mint a duplicate.
Re-applying the same value converges byte-identically (each field is set to the desired value, not
appended), so an operator re-run after a halt is safe.

All the orchestrator's own helpers -- `run_step`, `emit_partial_report` / `assert_partial_report_emitted`,
the three `jira-metadata-write.sh` call sites, and `render_description_tempfile` -- are specified, with
their reference implementations (or, for the dedicated writer, its contract and call sites), in
`.claude/skills/claire-sync-jira/jira-server-orchestration.md`.

## Steps

### Single Ticket Sync (`$target` = ticket ID)

Each step is one script invocation through `run_step`, which accumulates its stdout into
`$SYNC_PAYLOAD` and decides the halt. The full contract of every script -- inputs, stdout keys, exit
codes, re-run semantics -- is in `.claude/skills/claire-sync-jira/jira-server-scripts.md`; read that plus the
one script you are changing, never all of them. Every script below is **executable and invoked bare**.

The sequence has a **reference implementation** — `sync_one_ticket` in
`.claude/skills/claire-sync-jira/jira-server-orchestration.md` — and that is where the argv lives. The
table below names each step; it is a reading aid, not a second copy to keep in step. Every variable is
passed **quoted**: an unquoted empty `$KEY` leaves a dangling `--issue-key` flag, which is a usage
halt, not a shrug.

| # | Step | Script | Class |
|---|---|---|---|
| 1 | Connectivity + self identity | `jira-connect.sh` | blocking |
| 2 | Create-vs-update resolution | `jira-resolve.sh --ticket "$ID"` | blocking |
| 3 | Preserve the as-filed original (**update path only**) | `jira-preserve.sh --issue-key "$KEY"` | blocking |
| 4 | Render the description, then project the issue | `jira-write-issue.sh --ticket "$ID" --mode "$MODE" [--issue-key "$KEY"] [--description-file "$TMP"]` | blocking |
| 5 | Status transition | `jira-transition.sh --ticket "$ID" --issue-key "$KEY"` | blocking |
| 6 | Per-stage worklogs | `jira-worklog.sh --ticket "$ID" --issue-key "$KEY"` | blocking |
| 7 | Assignee reconciliation | `jira-assign.sh --ticket "$ID" --issue-key "$KEY" --self "$SELF"` | best-effort |
| 8 | Related-ticket links | `jira-link.sh --ticket "$ID" --issue-key "$KEY"` | best-effort |
| 9 | Epic association (and, for an umbrella, its **replacement**: create the new umbrella issue at the configured type, move the children's ordered links onto it, close the superseded original, and emit `umbrella_epic_url=` -- plus `jira_url=` on completion) | `jira-epic.sh --ticket "$ID" --issue-key "$KEY"` | best-effort |

Three of those arguments are load-bearing and were each missing at some point in this skill's life:
`jira-preserve.sh` takes **`--issue-key` and nothing else** (a `--ticket` is a usage halt at a blocking
step, so no ticket is ever projected); step 3 is skipped entirely on the **create** path, where no
issue exists yet; and `$SELF` is the identity step 1 resolved from the credential — without it every
status the config maps to `self` is refused.

**Step 6 — the operator/agent worklog split (opt-in, BTG-315).** `jira-worklog.sh` posts every
per-stage entry to the operator as before, unless the ticket prefix's `CLAIRE_ORG.md` §9 row carries a
value in its fifth column, `Agent-time user`. When it does, each entry is split into two worklogs
instead of one -- an operator leg and an agent leg attributed to that configured identity -- using the
per-stage share the adopter's own §19 table (and, per-operator, the `CLAIRE_WORKLOG_FACTOR_<STAGE>`
override family) declares; this skill never restates or defaults that share itself. Leaving the fifth
column empty is byte-identical to before this ticket. See `docs/migrations/worklog-agent-attribution.md`
for the full opt-in walkthrough and `syncjs.worklog.agent_leg_rejected` / `syncjs.worklog.agent_leg_status_ambiguous`
(BTG-319) for the two conditions an adopter watches for on the agent leg -- the first when the
configured identity is not one the plugin will honor (forfeited, non-halting), the second when the
plugin's response is not positively identified as either (halts the ticket's sync; a re-run retries
only the missing agent leg).

### Step 4 — the per-projection description temp file (AC-4)

**Render the description into a FRESH temp file** (**skip entirely for `type: epic`** — an Epic's
Description stays empty). This is content the skill *supplies*; it is the one thing the orchestrator
renders rather than delegating.

- Fill each placeholder in **`ticket_TEMPLATE.md`**'s wiki body from the repo artifacts per its
  *Token sources* table (prose from `specs/{target}/problem.md` or `archive/...`, fields from
  `metadata.yaml`), applying its *Rendering rules* — convert Markdown to **Jira wiki markup** and
  strip the `> **Probe:**` authoring blockquotes. Do **not** post `problem.md` verbatim. Jira
  Server/DC's REST v2 `description` field renders wiki markup natively; nothing converts Markdown on
  the way in, so the body is sent as wiki.
- Write the rendered result — including the traceability table for `merge_request` and `spec_mr` —
  into a **new** `mktemp` file, and pass that path to `jira-write-issue.sh --description-file`.
- **One fresh file per projection, never reused** — not across syncs and not across tickets in a bulk
  run. The consuming script owns the file's end of life and unlinks it on every exit path (success or
  halt), so no rendered content is ever left behind or re-sent.
- The PAT is **never** written into the temp file (it belongs to the environment alone).

`render_description_tempfile` in `.claude/skills/claire-sync-jira/jira-server-orchestration.md` is the
reference implementation, and the reason `mktemp` (not a ticket-derived path) is what makes the
freshness structural.

An Epic is the one sanctioned exception to step 4: it carries no description and no Original Estimate.

After the sequence completes, the orchestrator invokes `jira-metadata-write.sh` once more, carrying every
key the run accumulated (BTG-125); on the create path `jira_url` was already recorded right after this
step returned, and the two calls converge byte-identically.


### Bulk Sync (`$target` = "all")

1. **Scan `specs/` and `archive/`** for all `metadata.yaml` files.
2. **For each ticket, run the single-ticket sequence** above — **independently**. Each ticket gets its
   own script sequence, its own accumulated stdout payload, and its **own fresh description temp file**:
   `render_description_tempfile` is called **inside** the per-ticket loop, never hoisted above it, so no
   rendered body is ever shared between two tickets (AC-4).
3. **A per-ticket halt does not stop the run.** When a ticket's sequence halts (a blocking script exited
   non-zero), emit that ticket's partial-completion report, leave its `metadata.yaml` unwritten, and
   **continue to the next ticket** — the tickets are independent, so one ticket's failure is never
   allowed to suppress another's due projection. A halt is **never** silent: every halted ticket appears
   in the run summary. `bulk_sync_tickets` in
   `.claude/skills/claire-sync-jira/jira-server-orchestration.md` is the reference loop.
4. **Report** per ticket, and in the run summary: tickets created, tickets updated, transitions applied,
   worklogs posted/skipped/**disabled**, **agent legs rejected** (`agent_legs_rejected`, split mode only
   -- BTG-315; absent, never zero, when the ticket's prefix carries no agent-time user), assignments
   applied/skipped/disabled/rejected, AC field
   imported/projected/disabled/skipped (the `syncjs.ac.*` family), issue links created, and their
   reference account -- `references_unreadable` / `references_unresolved` / `references_skipped`
   (BTG-107 AC-2). Name each counter that is non-zero. A CLEAN account (all three zero) is stated
   **affirmatively** -- "no reference was unreadable, unresolved or skipped" -- never left to silence,
   because a run that says nothing about the account is indistinguishable from one that forgot to check.
   A counter the payload did **not return** is reported as **not returned**, never read as zero -- an
   absent key and a zero value are different facts. And — listed explicitly, never folded into a count —
   **each halted ticket** with its failing step, that step's `syncjs.*` condition, and its exit code; and,
   on a bulk run, **each ticket whose reference account is non-zero**, named **by id**, never summed into
   a cross-ticket total (`bulk_sync_tickets` resets the payload per ticket, so no such total exists to
   fold into).

## Intake operations (inbound)

The inbound operations `/claire-triage` relies on are scripts too, each executable and invoked bare, and each
read-only against the repository (none writes `metadata.yaml`):

| Operation | Script | What it returns |
|---|---|---|
| `reserve` (`$target` = "reserve") | `jira-reserve.sh --summary "<text>" [--type <repo-type>] [--prefix <PREFIX>]` | `issue_key=` / `jira_url=` -- the key **Jira** assigned; a failed reservation stops rather than guessing a number. `--prefix` is optional in general but **REQUIRED** where §9 declares a PER-PREFIX table: without it the binding cannot be consulted, and the reservation halts `4` on `syncjs.config.project_key_precondition_unmet` rather than reserving into whatever project the deprecated environment variable names |
| `import` (`$target` = "import") | `jira-import.sh --issue-key <KEY> [--ticket <id>]` | `summary_file=` / `ac_items_file=` / `attachments_downloaded=` / `attachments_referenced=` -- the seed files `problem.md` is written from |
| `sprint-check` (`$target` = "sprint-check {ticket-id}") | `jira-sprint-check.sh --ticket <id>` | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive` |

`import` returns its seed files inside ONE `seed_dir=` temp directory. The caller
owns that directory's end of life: remove it once `problem.md` has been written.
A FAILED import unlinks it itself, so only a successful one leaves anything behind
— the same one-owner, one-unlink discipline the description temp file follows (AC-4).

`sprint-check` runs a single `key=<KEY> AND sprint in openSprints()` query. It is **read-only** and its
three verdicts are not interchangeable: *exists but in no open sprint* is `not-in-sprint`, while *no such
key* (or any unresolved key) is `inconclusive`. A `400` is **never** reported as `not-in-sprint`, and the
key is resolved **verbatim** -- there is no summary-search fallback, because a fuzzy match is unsafe for a
gate decision.

**What "synced" means** for this skill: the repo is the source of truth and Jira is the projection, so a
ticket is synced when the last successful run projected its current repo state -- never when Jira and the
repo merely look similar. `import` downloads attachments only within the configured per-file ceiling and
**fails closed** when that ceiling is absent or malformed: every attachment is referenced by URL and none
is downloaded, because persisting one is an irreversible git-history write.


## Error handling

Every failure surfaces as a named `syncjs.<family>.<condition>` line on stderr, and **no failure is ever
swallowed**. The full operator-facing catalogue — transport and HTTP, self-identity, worklogs, the
Acceptance Criteria field, the preservation comment, related-ticket links and the Epic-on-Epic umbrella
projection — is `.claude/skills/claire-sync-jira/jira-server-conditions.md`. The four rules that govern all
of them:

1. **Transport unreachable** exits **3** with `syncjs.transport.rest_unreachable`, distinct from a
   ticket-resolution failure. Never a silent no-op.
2. **Any non-2xx is a failure**, surfaced with its HTTP status and the Jira `errorMessages` / `errors`
   under the operation's own condition.
3. **A disabled toggle is a policy opt-out, not an error** (`syncjs.worklog.disabled`,
   `syncjs.ac.disabled`); a **malformed** toggle or capability marker is a config **HALT** (exit 4) and
   never silently resolves to "off".
4. **A best-effort step halts its own branch, never the ticket** — it reports its condition and exits
   **0** with a named `*_result=` payload (DEC-033).

## Example

```
/claire-sync-jira ORD-6
/claire-sync-jira all
```
