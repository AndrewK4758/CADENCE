---
name: claire-sync-youtrack
description: Sync spec metadata and status to a self-hosted YouTrack Server instance over direct REST -- a thin orchestrator that sequences co-located single-operation shell scripts, authenticated with a permanent token held only in the operator environment
argument-hint: 
arguments: [target]
allowed-tools: Read Glob Grep Bash
model: gemini-3.8-flash-high
---


## Task

Synchronize repository spec artifacts to **self-hosted YouTrack Server** (not YouTrack Cloud) for the
target `$target`. Every YouTrack operation is a **direct REST call issued by a co-located, single-operation
shell script**; this file is a thin **orchestrator** that sequences those scripts, supplies the content
they consume, and applies the one `metadata.yaml` write at the end. It performs no YouTrack call itself
and carries no field-mapping or validation logic -- that lives in the scripts, where it is mechanically
testable rather than re-derived by inference on every run.

> **Bounded context: Tracker Binding / YouTrack projection flow (CLAIRE_ORG.md#tracker-binding, TS-1).**
> Invariant relied on from outside this boundary: the repository is the sole system of record; YouTrack is
> a one-directional projection target resolved from §9. This skill runs only when an adopter binds
> `#tracker-binding: youtrack`; where §9 resolves to `None` or to a different tracker, every trigger is a
> declared SKIP.
> Spec: archive/BTG-176/spec.md (Proposed Design).

> This skill targets YouTrack **Server** (self-hosted), which differs from Jira and from YouTrack Cloud in
> four ways that shape the whole adapter:
> - **Type-agnostic issue links.** The `Subtask` link (`parent for` / `subtask of`) carries no per-Type
>   restriction, so an epic can parent another epic. There is **no** umbrella / hierarchy-flatten special
>   case (unlike `/claire-sync-jira`).
> - **No dedicated Acceptance-Criteria field.** Acceptance criteria are projected **only into the issue
>   description** (via `ticket_TEMPLATE.md`), and never read back on a seed-read import.
> - **The state field is a plain field** over one project-wide bundle, not a workflow transition graph.
> - **Descriptions render Markdown**, natively. Nothing converts markup on the way in.
>
> **Transport:** `curl` with a Bearer permanent token supplied on curl's `-K-` stdin config channel. A call
> that cannot reach the instance fails loud with **`syncyt.transport.rest_unreachable`** (exit 3), distinct
> from a ticket-resolution failure; a non-2xx fails loud with the operation's own named condition. **A 2xx
> is not evidence a field landed** -- this instance answers a write carrying a field the issue's type
> cannot hold with 200 and silently discards the value -- so every field write is read back. No failure is
> ever swallowed and no fallback is ever silent.

### Where things live

| Read this | When |
|---|---|
| **this file** | sequencing a ticket, deciding a halt, reading the step table |
| `.claude/skills/claire-sync-youtrack/youtrack-scripts.md` | changing or calling any one operation script (its inputs, stdout keys, exit codes, re-run semantics), or reading the documented divergences from `/claire-sync-jira` |
| `.claude/skills/claire-sync-youtrack/youtrack-orchestration.md` | changing how the orchestrator sequences, halts, reports, renders the description temp file, or writes `metadata.yaml` back |
| `.claude/skills/claire-sync-youtrack/youtrack-server-config.json` | changing anything that varies per repository or per YouTrack instance |

Read this file plus **one** of the rows, never the whole set.

## Direction

This sync is **one-directional: repo -> YouTrack.** The repository is the source of truth. YouTrack is the
projection layer for product management, roadmapping, and software capitalization accounting.

The outbound path **never creates or updates YouTrack attachments** -- a documented non-goal. Attachment
flow is inbound-only, at the `import` intake operation (`yt-import.sh`), and an attachment's download URL
is treated as a credential there.

## Prerequisites

### 1. Environment

Every YouTrack call is a direct REST request made by a co-located script. There is no intermediary server
and no container runtime to install -- a plain shell with `curl`, `jq` and `python3` is the whole
substrate.

| Variable | Purpose |
|---|---|
| `YOUTRACK_BASE_URL` | Instance root, e.g. `https://youtrack.example.com` |
| `YOUTRACK_TOKEN` | Permanent token (Bearer auth) |
| `YOUTRACK_PROJECT_KEY` | Target project short name. **DEPRECATED as the project-key source** (BTG-179): resolution is (1) the ticket prefix's `CLAIRE_ORG.md` §9 row -> (2) §9's scalar `**Project key(s):**` line -> (3) this variable, which sunsets after ONE release cycle. Declare the key in §9 instead: `docs/migrations/multi-tracker-binding.md` |
| `YOUTRACK_SELF` | *Optional.* Pins the assignment identity; when set it always wins |

The variable NAMES are themselves configuration (the `env` block of
`.claude/skills/claire-sync-youtrack/youtrack-server-config.json`), so an adopter can rebind a name without editing a
script. The token is read from the environment at call time and handed to `curl` through a `-K-` stdin
config block: it is never a positional argument, never written to a temp file, an artifact or
`metadata.yaml`, and never echoed to any output channel.

**Version floor (precondition): YouTrack Server `v2026.1.13162`.** That is the build every REST shape this
adapter depends on was verified against, and it is a **support boundary** rather than a claim that older
instances fail: nothing here asserts anything about what an older build does. The version endpoint answers
without an `Authorization` header, so a version precondition can be checked *before* a credential is
proven -- an instance below the floor stays distinguishable from a bad token instead of collapsing into
one "something is wrong" failure.

**Permissions.** The issue operations this adapter performs -- read/create/update, link, comment, and,
for the effort worklog, the time-tracking permission -- are within reach of a project-member token on
the bound project. **One step is not, and it is stated here rather than glossed: resolving the
configured project key to the internal project id reads `GET /api/admin/projects`.** That happens on
every ticket sync, before any write, and it is the only route to that id -- `/api/issues` filtered by
project returns an empty array for a project that holds no issues, so it cannot resolve an id at all,
and `/api/agiles` reaches only board-attached projects. **A token that cannot read that endpoint cannot
resolve the project**, and the sync halts (`syncyt.config.project_unresolved`) having written nothing.

What is *not* claimed: that the endpoint requires an administrative role. It sits under `/api/admin/`,
which is suggestive, but that has not been checked against a second, non-administrative credential, and
this adapter does not assert what it has not observed.

No schema is *discovered*: field types and permitted values are never enumerated. The adapter writes
from its own intent, reads the value back, and reports the instance's rejection -- so project resolution
is the whole of its administrative surface, and `youtrack-transport.test.sh` S-2.2 fails the build on
any other `/api/admin/` path appearing in a shipped script.

### 2. Everything instance-specific lives in the config sidecar

The issue-type, priority and state maps, the per-type conditional-field map, the assignment map, the link
relations, the three feature toggles, the attachment ceiling, the sprint query, the page bound and the
worklog post-check capability are all read from
`.claude/skills/claire-sync-youtrack/youtrack-server-config.json`. Each key's absent/malformed polarity is defined
once, in `.claude/skills/claire-sync-youtrack/yt-lib.sh`, and documented in
`.claude/skills/claire-sync-youtrack/youtrack-scripts.md` -- no script re-derives one.

### 3. Verify connectivity before syncing

Run `yt-connect.sh`. It resolves the effective self identity (adopter override, then a
credential-fingerprinted cache outside the repo tree, then the current-user read) and fails loud on an
unreachable transport (exit 3) or a rejected credential (exit 1). Every later step assumes it passed.

## Orchestration — the script sequence and the single metadata write

This skill is a **thin orchestrator**: every mechanical YouTrack operation is performed by a standalone,
single-operation script co-located with this file, and every script's interface (inputs, stdout
`key=value` outputs, exit codes, re-run semantics) is contracted in
`.claude/skills/claire-sync-youtrack/youtrack-scripts.md`. The skill sequences those scripts, supplies the rendered
content they consume, and applies the `metadata.yaml` update. It performs no YouTrack call itself.

**Capture the payload.** Each script writes its result to stdout as `key=value` lines and its audit
conditions to stderr. The orchestrator **accumulates the stdout lines of every script run for the ticket**
into one payload and parses that payload — never prose, never stderr — for the metadata delta. The helper
that does this is **`yt_run_step`** in `.claude/skills/claire-sync-youtrack/youtrack-orchestration.md`.

**Every step is one of exactly two classes.** The class is a property of the *step*, not of the failure:

| Class | Steps | On a non-zero exit |
|---|---|---|
| **blocking** | `yt-connect`, `yt-resolve`, `yt-preserve`, `yt-write-issue`, `yt-transition` | **Halt this ticket** at that step |
| **best-effort** | `yt-worklog`, `yt-assign`, `yt-link`, `yt-epic` | Still **halt** — see below |

A best-effort step signals a *sanctioned refusal* by exiting **0** with a named `*_result=` payload
(`assign_result=rejected`, `link_result=skipped`, `epic_result=skipped`, …) plus its stderr condition; the
sequence continues and the refusal is carried in the payload so the run report names it. The class grants a
sanctioned refusal, **not blanket immunity**: a best-effort script that exits non-zero has not refused, it
has *broken* (a crash, a missing file, a failed usage check), and breakage is never swallowed. That is why
the halt decision reads the exit code alone and the class only decides which script is *allowed* to report
a refusal at all.

**A halt is loud, and it leaves partial work intact and VISIBLE.** On a halt the orchestrator does **not**
roll back, does **not** issue a compensating call, and does **not** auto-retry or auto-resume — the effects
the completed steps already applied stay in YouTrack, and two of them cannot be undone by a later run in
any case: a created issue is the ticket's only identity, and a posted work item is immutable by
construction. What it owes the operator instead is a **partial-completion report**
(`yt_emit_partial_report`, guarded by `yt_assert_partial_report_emitted`): which steps completed and what
effect each applied, which step failed with its `syncyt.*` condition and exit code, and which steps remain
un-run. Recovery is an operator re-run, which the operator cannot judge without exactly that picture — so a
halt that emitted no report is itself a defect (`syncyt.orchestrator.partial_report_absent`).

**The orchestrator is the sole writer of `metadata.yaml`.** A script **never writes** `metadata.yaml` (or
any other owned artifact); it only reads it. The update is applied **once, at end-of-operation**
(`yt_apply_metadata_writes`), after the sequence has completed — so a mid-sequence halt leaves
`metadata.yaml` unchanged and the already-applied YouTrack effects are re-derived from repo state on the
operator's re-run. Re-applying the same payload converges byte-identically (each field is set to the
desired value, not appended), so an operator re-run after a halt is safe.

> **One window is NOT convergent, and it is named rather than hidden.** `youtrack_url` is the only
> ticket-to-issue mapping this adapter has, and there is no recovery search to fall back on. A first sync
> that creates the issue and then halts **before** the end-of-operation write leaves no record anywhere,
> and a re-run mints a **duplicate issue** that must be cleaned up by hand. Check the project before
> re-running a sync that halted mid-sequence.

All the helpers -- `yt_run_step`, `yt_emit_partial_report` / `yt_assert_partial_report_emitted`,
`yt_emit_completion_report`, `yt_apply_metadata_writes` and `yt_sync_one_ticket` -- are specified, with
their reference implementations, in `.claude/skills/claire-sync-youtrack/youtrack-orchestration.md`.

## Steps

### Single Ticket Sync (`$target` = ticket ID)

Each step is one script invocation through `yt_run_step`, which accumulates its stdout into
`$YT_SYNC_PAYLOAD` and decides the halt. The full contract of every script -- inputs, stdout keys, exit
codes, re-run semantics -- is in `.claude/skills/claire-sync-youtrack/youtrack-scripts.md`; read that plus the one
script you are changing, never all of them. Every script below is **executable and invoked bare**.

The sequence has a **reference implementation** — `yt_sync_one_ticket` in
`.claude/skills/claire-sync-youtrack/youtrack-orchestration.md` — and that is where the argv lives. The table below
names each step; it is a reading aid, not a second copy to keep in step. Every variable is passed
**quoted**: an unquoted empty `$ISSUE` leaves a dangling `--issue` flag, which is a usage halt, not a shrug.

| # | Step | Script | Class |
|---|---|---|---|
| 1 | Connectivity + self identity | `yt-connect.sh` | blocking |
| 2 | Project resolution + create-vs-update | `yt-resolve.sh --ticket "$ID"` | blocking |
| 3 | Preserve the as-filed original (**update path only**) | `yt-preserve.sh --issue "$ISSUE"` | blocking |
| 4 | Render the description, then project the issue | `yt-write-issue.sh --ticket "$ID" --description-file "$TMP" [--project "$PID" \| --issue "$ISSUE"]` | blocking |
| 5 | State | `yt-transition.sh --ticket "$ID" --issue "$ISSUE"` | blocking |
| 6 | Per-stage effort work items | `yt-worklog.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |
| 7 | Assignee reconciliation | `yt-assign.sh --ticket "$ID" --issue "$ISSUE" --self "$SELF"` | best-effort |
| 8 | Related-ticket links | `yt-link.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |
| 9 | Epic parent link (type-agnostic; **no** re-type, Move or flatten) | `yt-epic.sh --ticket "$ID" --issue "$ISSUE"` | best-effort |

Four of those arguments are load-bearing. `yt-preserve.sh` takes **`--issue` and nothing else**, and step 3
is skipped entirely on the **create** path, where no issue exists yet -- it captures the as-filed original
*before* step 4 overwrites the description, so any failure there halts rather than letting the overwrite
proceed. Step 4 takes `--project` on the create path and `--issue` on the update path. `$SELF` is the
identity step 1 resolved from the credential — without it every status the config maps to `self` is
refused. And every step after step 4 is addressed by the **internal** issue id that step returned, never
the readable one: a readable id in a link body is rejected with a message quoting back only its alphabetic
prefix.

**Per-stage effort (step 6)** projects each `metadata.yaml` `stage_effort` entry as its **own** work item,
never the accumulated `actual_effort` total, using the shared §12 effort-rounding rule **by name** — no
vendor multiplier value is restated anywhere in this skill. "Already synced" is decided by the repo-owned
`worklog_watermark_at` scalar alone, **never** by reading the tracker's current work items, so an operator
who edits or deletes a work item is never overridden by a backfill. A posted work item is **never updated
and never deleted**. Three outcomes of that step are named here because an operator reads the audit stream
for them: `syncyt.worklog.watermark_seeded` (a ticket carried over from before the watermark existed seeds
forward and posts nothing), `syncyt.worklog.postcheck_failed` (the instance did not absorb a posted work
item — the watermark is NOT advanced and the work item is left exactly as it is), and
`syncyt.worklog.marker_scan_rejected` (the crash-recovery scan could not be performed, so the batch posts
NOTHING rather than risk a duplicate this adapter can never delete).

**The operator/agent worklog split (opt-in, BTG-315).** `yt-worklog.sh` posts every per-stage entry to
the operator as before, unless the ticket prefix's `CLAIRE_ORG.md` §9 row carries a value in its fifth
column, `Agent-time user`. When it does, each entry is split into two work items instead of one -- an
operator leg and an agent leg carrying that configured login in the item's native `author` field -- using
the per-stage share the adopter's own §19 table (and, per-operator, the `CLAIRE_WORKLOG_FACTOR_<STAGE>`
override family) declares; this skill never restates or defaults that share itself. Leaving the fifth
column empty is byte-identical to before this ticket. See `docs/migrations/worklog-agent-attribution.md`
for the full opt-in walkthrough and `syncyt.worklog.agent_leg_rejected` for the sanctioned-refusal
condition an adopter watches for when the configured identity lacks the
`JetBrains.YouTrack.CREATE_NOT_OWN_WORK_ITEM` permission.

### Step 4 — the per-projection description temp file

**Render the description into a FRESH temp file.** This is content the skill *supplies*; it is the one
thing the orchestrator renders rather than delegating.

- Fill each placeholder in **`ticket_TEMPLATE.md`**'s body from the repo artifacts per its *Token sources*
  table (prose from `specs/{target}/problem.md` or `archive/...`, fields from `metadata.yaml`), applying
  its *Rendering rules*. Do **not** post `problem.md` verbatim. YouTrack renders the description as
  Markdown and the template is already Markdown, so the body is sent as authored — nothing converts it.
- The rendered description **includes the Acceptance Criteria section**: that is the only place acceptance
  criteria are projected, because this instance has no dedicated field for them.
- The projected issue summary is the ticket's `title` **verbatim**, with no ticket-id prefix.
- Write the rendered result — including the traceability rows for `merge_request` and `spec_mr` — into a
  **new** `mktemp` file, and pass that path to `yt-write-issue.sh --description-file`.
- **One fresh file per projection, never reused** — not across syncs and not across tickets in a bulk run.
  The consuming script owns the file's end of life and unlinks it on every exit path, so no rendered
  content is ever left behind or re-sent.
- The token is **never** written into the temp file (it belongs to the environment alone).

`render_description_tempfile` in `.claude/skills/claire-sync-youtrack/youtrack-orchestration.md` is the reference
implementation, and the reason `mktemp` (not a ticket-derived path) is what makes the freshness structural.

After the sequence completes, and only then, the orchestrator applies `yt_apply_metadata_writes` once.

### Bulk Sync (`$target` = "all")

1. **Scan `specs/` and `archive/`** for all `metadata.yaml` files.
2. **For each ticket, run the single-ticket sequence** above — **independently**. Each ticket gets its own
   script sequence, its own accumulated stdout payload, and its **own fresh description temp file**:
   `render_description_tempfile` is called **inside** the per-ticket loop, never hoisted above it, so no
   rendered body is ever shared between two tickets.
3. **A per-ticket halt does not stop the run.** When a ticket's sequence halts, emit that ticket's
   partial-completion report, leave its `metadata.yaml` unwritten, and **continue to the next ticket** —
   the tickets are independent, so one ticket's failure is never allowed to suppress another's due
   projection. A halt is **never** silent: every halted ticket appears in the run summary.
   `bulk_sync_tickets` in `.claude/skills/claire-sync-youtrack/youtrack-orchestration.md` is the reference loop.
4. **Report** per ticket, and in the run summary: issues created, issues updated, states applied, work
   items posted/suppressed/disabled, **agent legs rejected** (`agent_legs_rejected`, split mode only --
   BTG-315; absent, never zero, when the ticket's prefix carries no agent-time user), assignments
   applied/skipped/rejected, links created/skipped, epic
   parents linked/skipped, and — listed explicitly, never folded into a count — **each halted ticket** with
   its failing step, that step's `syncyt.*` condition, and its exit code.

## Intake operations (inbound)

The inbound operations `/claire-triage` relies on are scripts too, each executable and invoked bare, and each
read-only against the repository (none writes `metadata.yaml`):

| Operation | Script | What it returns |
|---|---|---|
| `reserve` (`$target` = "reserve") | `yt-reserve.sh --summary "<text>" [--type <repo-type>]` | `issue_id=` / `issue_readable=` / `youtrack_url=` -- the id **YouTrack** assigned; a failed reservation stops rather than guessing one |
| `import` (`$target` = "import") | `yt-import.sh --issue <KEY-N> [--ticket <id>]` | `seed_dir=` / `summary_file=` / `description_file=` / `manifest_file=` / `attachments_downloaded=` / `attachments_referenced=` / `type_hint=` -- the seed files `problem.md` is written from |
| `sprint-check` (`$target` = "sprint-check {ticket-id}") | `yt-sprint-check.sh --ticket <id>` | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive` |

`reserve` **declares its pairing obligation before it contacts the tracker**: the id it is about to
allocate must be paired, in this same governed operation, with the `problem.md` and `metadata.yaml`
artifacts that id owns, and an unpaired allocation is `idalloc.reserve.unpaired_artifact_creation`. The
governing rule is `CLAIRE_ORG.md` `#id-allocation-binding` (Reservation pairing) -- cited, never
restated. Declaring it first is what lets a caller abort before an orphan exists. Where the binding is
mint-by-convention, `reserve` performs **no** YouTrack write at all and therefore
declares **no** tracker-side obligation -- announcing one for a write that never happens would be a false
audit line. That locally-minted id is **still governed by** the same pairing clause: nothing about minting
by convention loosens it, and an id allocated with no `specs/<id>/` artifacts behind it is the same
`idalloc.reserve.unpaired_artifact_creation` it would be on any binding.

`import` returns its seed files inside ONE `seed_dir=` temp directory. The caller owns that directory's
end of life: remove it once `problem.md` has been written. A FAILED import unlinks it itself, so only a
successful one leaves anything behind. It **reads no dedicated acceptance-criteria field** (there is none),
so acceptance criteria are never populated into `problem.md` from a tracker field. It downloads
attachments only within the configured per-file ceiling and **fails closed** when that ceiling is absent or
malformed: every attachment is referenced and none is downloaded, because persisting one is an irreversible
git-history write. **An attachment's download URL is a signed credential on this instance** -- it serves the
file with no `Authorization` header -- so it is never logged, never written into an artifact and never
included in an error message; diagnostics name the attachment id and the HTTP status.

`sprint-check` runs a **single** query and returns exactly **one** verdict. It is read-only and its three
verdicts are not interchangeable: *exists but in no sprint the query names* is `not-in-sprint`, while *no
such id* (or any unresolved query) is `inconclusive`. A `400` is **never** reported as `not-in-sprint`, and
the id is resolved **verbatim** -- there is no summary-search fallback, because a fuzzy match is unsafe for
a gate decision. The query itself is configuration: this instance has no open-sprint query function, and a
naive sprint query in a project with no board matches every issue.

**What "synced" means** for this skill: the repo is the source of truth and YouTrack is the projection, so
a ticket is synced when the last successful run projected its current repo state -- never when YouTrack and
the repo merely look similar.

## §9 binding resolution (vendor-neutral)

Before any external write, resolve the bound tracker from `CLAIRE_ORG.md#tracker-binding` and record the
**`syncyt.resolve.tracker`** AUDIT line (resolved tracker + binding source + mapped skill) **before**
contacting YouTrack (the wrong-tracker guard). For a scoped-projection run, a **per-item fail-closed audit
line** (item-id, owned-flag, action) is written **before** each board write (PI-030); a foreign item (no
`specs/<id>/`) is skipped with an audit line and no board write. When the ticket prefix's §9 row --
or the `*` wildcard row that covers it -- resolves to `None -- inner-source`, every trigger records
"no external tracker bound (inner-source); skipped" and performs **no external write**:
only repo-owned state is touched. (BTG-242: the repo-wide `**Bound tracker(s):**` line that used
to carry this declaration was removed; the row is the declaration.)

## Error handling

Every failure surfaces as a named `syncyt.<family>.<condition>` line on stderr, and **no failure is ever
swallowed**. The full per-script catalogue -- which conditions each operation can raise, and what each one
means -- is in `.claude/skills/claire-sync-youtrack/youtrack-scripts.md`. The five rules that govern all of them:

1. **Transport unreachable** exits **3** with `syncyt.transport.rest_unreachable`, distinct from a
   ticket-resolution failure, and relays curl's own diagnostic so a DNS failure stays distinguishable from
   a TLS or proxy one. Never a silent no-op.
2. **A rejected credential is not a transport failure.** The instance answered; `syncyt.connect.auth_rejected`
   (exit 1) names the environment variable to fix and relays the instance's own description, because a
   rejected token and an absent header are different remedies.
3. **Any non-2xx is a failure**, surfaced with its HTTP status under the operation's own condition — and a
   **2xx is not a success** either until the read-back confirms it (`syncyt.write.field_not_applied`).
4. **A disabled toggle is a policy opt-out, not an error** (`syncyt.worklog.disabled`,
   `syncyt.link.disabled`, `syncyt.assign.disabled`); a **malformed** toggle or capability marker is a
   config **HALT** (exit 4) and never silently resolves to "off".
5. **A best-effort step halts its own branch, never the ticket** — it reports its condition and exits **0**
   with a named `*_result=` payload.

## Example

```
/claire-sync-youtrack BTG-6
/claire-sync-youtrack all
```
