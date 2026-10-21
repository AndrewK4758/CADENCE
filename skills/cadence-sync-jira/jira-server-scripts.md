# `/cadence-sync-jira` — script contracts

Bounded context: Tracker projection / Jira Server-DC adapter.
Boundary invariant: the repository (`metadata.yaml` + `problem.md`) is the
source of truth; Jira is the projection layer. This document is the **interface index** for the skill:
`.agents/skills/cadence-sync-jira/SKILL.md` is a thin **orchestrator** that sequences the standalone
single-operation scripts contracted below, and each script performs one mechanical Jira REST v2
operation (ADR_CADENCE-0025; `archive/BTG-075/spec.md` AC-2/AC-9).

Read this document plus the single script you are modifying — never all of them. That is the core purpose of
the contract: an agent modifying one operation reads (1) this file, (2)
`.agents/skills/cadence-sync-jira/jira-lib.sh`, (3) the operation script, (4)
`.agents/skills/cadence-sync-jira/jira-server-config.json`, and (5) the skill body.

---

## 1. The three-channel return contract (DEC-001)

Every script communicates on three channels. Nothing else is a return value; the orchestrator
never scrapes prose.

| Channel | Carries | Consumed by |
|---|---|---|
| **stdout** | Machine-readable result **only**: zero or more `key=value` lines drawn from that script's documented vocabulary (e.g. `issue_key=CTS-123`, `jira_url=…`, `worklog_watermark_advance=<iso8601>`, `assign_result=self`). No prose, ever. A script with nothing to return writes nothing. | The orchestrator, which accumulates the lines and drives `jira-metadata-write.sh` (BTG-125) — the dedicated writer, up to three times per ticket, and always at end-of-operation — never any operation script itself |
| **stderr** | The human-readable `syncjs.*` reported-condition audit stream plus diagnostics. Never parsed for control flow. | The operator / the transcript (and `offload_log_triage` on non-zero exits with verbose REST error payloads) |
| **exit code** | Status (below). | The orchestrator's halt decision |

### Exit codes

| Code | Meaning | Orchestrator behaviour |
|---|---|---|
| `0` | Success (or a sanctioned best-effort skip, reported as a `*_result=` payload) | Continue |
| `1` | Generic fail-loud; the named `syncjs.*` condition is already on stderr | **Halt** this ticket |
| `2` | Usage / setup failure (missing argument, missing environment variable) | **Halt** this ticket |
| `3` | Transport unreachable (`syncjs.transport.rest_unreachable`) — distinct from a ticket-resolution failure | **Halt** this ticket |
| `4` | Config marker absent or malformed — a fail-loud config key could not be resolved (`syncjs.config.marker_unresolved`) | **Halt** this ticket |

Any non-zero exit halts the orchestrator **for that ticket** (`AGENTS.md` Behavior 5). When a script exits non-zero with verbose Jira REST/HTML error payloads or stack diagnostics on stderr (`> 30` lines), route the diagnostic stream through `offload_log_triage` (`local-fast-cpu` on `:11434`) to extract the verbatim `syncjs.*` condition and HTTP status while preserving the unedited response in `/tmp/agy-last-triage.log`. Explicitly
**best-effort** operations (assignment, acceptance-criteria write, linking, self-identity) exit `0` and
report a skip or rejection as a stdout `*_result=` payload plus a stderr condition, allowing the orchestrator
to continue.

On a halt, the orchestrator neither rolls back nor compensates nor auto-resumes; it emits a
partial-completion report and leaves the already-applied Jira effects in place for the operator
(DEC-008). Recovery is an operator re-run, which is safe because every script is idempotent (DEC-009).

---

## 2. Invocation conventions

- **Arguments** are long-form (`--ticket BTG-075`, `--issue-key CTS-123`, `--description-file <path>`).
  A missing required argument is a usage failure (exit `2`), never a default.
- **Environment** supplies the transport and credential: `JIRA_BASE_URL`, `JIRA_PAT`, and the optional adopter override `JIRA_SELF`. The env-var *names* are themselves config (`env` block of the config sidecar); the *values* are never written anywhere.
- **The PROJECT KEY no longer comes from the environment.** `JIRA_PROJECT_KEY` is **DEPRECATED as the project-key source** (BTG-179), sunsets after ONE release cycle, and the migration path off it is `docs/migrations/multi-tracker-binding.md`.
  It is still READ as level (3) of: (1) the ticket prefix's `CADENCE_ORG.md` §9 row -> (2) §9's scalar `**Project key(s):**` line -> (3) the variable. A read at level (3) reports `syncjs.config.project_key_from_env`.
- **The repository root** is `$CADENCE_REPO_ROOT` when set, else the current working directory. Ticket
  artifacts resolve to `specs/<id>/metadata.yaml`, falling back to `archive/<id>/metadata.yaml`.
- **The config sidecar** is `$JIRA_SERVER_CONFIG` when set, else `jira-server-config.json` co-located
  with the script.
- **The shared library** `.agents/skills/cadence-sync-jira/jira-lib.sh` is sourced by every operation script.
  It centralizes the REST helpers, config resolution (including every key's fail-loud/default
  polarity), the `metadata.yaml` reader, the stdout emitter, and the `syncjs.*` reporter — so no script
  re-implements a polarity or transport detail.

### Credential handling (Pillar 7)

The Jira Personal Access Token is read from the environment at call time and passed to `curl` through a
`-K-` stdin config block. It is **never** a positional argument, and **never** written to a temp file, log
line, artifact, or `metadata.yaml`. The self-identity cache stores only an irreversible credential
fingerprint, never the token.

---

## 3. Owned-data discipline (AC-6)

A script **reads** `metadata.yaml`; a script **never writes** `metadata.yaml`, and never creates or edits
any other owned artifact. Each script instead returns its metadata-relevant delta on stdout, and **one
dedicated writer script, invoked by the orchestrator** — `jira-metadata-write.sh`, BTG-125 — is the
**sole writer**. It is called at end-of-operation and, on the create path and on an umbrella
replacement, twice EARLY — the moment `jira_url` / `umbrella_epic_url` is known — so that a mid-sequence
halt after either early call leaves the corresponding key already recorded. A halt **before** any write
in a run leaves `metadata.yaml` untouched.

A degenerate parse of `metadata.yaml` (empty, malformed, or not a JSON object once converted) is a
fail-loud HALT with `syncjs.metadata.degenerate` — never a silent proceed on an empty object (BTG-068).

---

## 4. Configuration and its polarity (AC-7)

Everything that varies per repository or per Jira instance lives in
`.agents/skills/cadence-sync-jira/jira-server-config.json`; nothing instance-varying is hardcoded in a script
or in skill prose. `jira-lib.sh` is the single resolver, defining each key's polarity once.

| Key | Absent / malformed resolves to | Rationale |
|---|---|---|
| the config file itself | **HALT**, `syncjs.config.absent` (exit `4`) | No instance mapping means no valid projection |
| `worklog_postcheck_capability` | **HALT**, `syncjs.config.marker_unresolved` (exit `4`) — never a silent `none` | A silent `none` would disable the BTG-064 post-add verification invisibly |
| `attachment_size_ceiling_mib` | **fail closed**: reference every attachment by URL, download none | An unbounded download is the unsafe direction (BTG-043) |
| `worklog_creation_enabled` | **enabled** (opt-out toggle) | Preserves the BTG-064 default |
| `acceptance_criteria_sync_enabled` | **enabled** (opt-out toggle) | Preserves the BTG-046 default. Only an explicit `false` disables it; when disabled, the sync makes **no** acceptance-criteria field call in either direction and reports `syncjs.ac.disabled` |
| `assignment_reconciliation_enabled` | **disabled** (opt-in toggle) | Preserves the BTG-014 opt-in polarity |
| `issue_type_map`, `priority_map`, `status_workflow_map`, `assignment_map`, `link_relations`, `acceptance_criteria.field_name`, `run_mode` | **HALT** on an unresolvable lookup, `syncjs.config.marker_unresolved` | A guessed issue type or transition is an ungoverned decision |

---

## 4a. Effort and estimates — the two standing guarantees (PROD_CADENCE-006 / BTG-037, BTG-064)

Both guarantees are enforced inside the scripts (AC-8) and asserted by
`sync-jira-server-estimate-gate.sh`, which anchors on this section:

- **Writing Original Estimate NEVER resets Remaining Estimate.** In Jira Server/DC the `timetracking`
  fields are coupled, so `jira-write-issue.sh` reads the issue's **current** Remaining as an explicit
  prerequisite of the update and co-sends it with `originalEstimate`. A failed read refuses the `PUT`
  rather than degrading to Original-alone; a genuinely never-estimated issue omits `remainingEstimate`
  entirely.
- **The post-add verification capability is declared, allowlisted, and fail-loud.** The config key
  `worklog_postcheck_capability` (the Jira spelling of the shared `worklog-postcheck-capability`
  declaration) accepts `remaining-estimate-decrement` | `none` on THIS adapter —
  `spent-time-increment` is the `/cadence-sync-youtrack` adapter's verification (its Spent time only grows) and
  has no Jira branch, so it is deliberately not accepted here rather than allowlisted and unimplemented. Its
  absent-value polarity is the **INVERSE** of the `worklog_creation_enabled` opt-out: absent, malformed,
  or non-allowlisted **HALTs** and reports the offending value verbatim, and must
  never silently resolve to `none`. Only an explicit `none` sanctions non-enforcement (the worklog is
  still posted and the run still succeeds, reported as `postcheck_unsupported`).
- **Worklog idempotency is repo-owned.** An entry is already-synced iff its `at` is at or below the
  repo-owned `worklog_watermark_at` scalar in `metadata.yaml` — the decision is
  never a live tracker read, so an operator who edits or deletes a worklog is never overridden by a
  backfill. The marker scan is SUPPRESS-ONLY and can only remove an entry the watermark already
  selected; an absent key bootstraps (seeds forward, posts nothing), while a present-but-empty value indicates
  a new ticket that posts from its first sync.
- **The worklog lets Jira decrement Remaining, and never sets it explicitly.** `jira-worklog.sh` posts
  each entry with `adjustEstimate=auto` and passes **no** Remaining-override argument, then verifies that the
  tracker absorbed the entry by RE-READING the issue — never by trusting the add response's own
  flags. A posted worklog is immutable: it is never updated and never deleted.

---

## 5. Idempotency — every entry states its re-run semantics (DEC-009)

Idempotency is a first-class requirement: recovery from a halt is an
operator re-run, so **every** step must converge to the same Jira state and never double-apply an
effect. Each contract entry below carries a **Re-run (idempotency)** field stating how that script
converges. (This is a *sequential re-run* property. Concurrent syncs against the same ticket are an
explicitly rejected edge case — DEC-010 — so no locking, lease, or optimistic-concurrency retry exists.)

---

## 6. Script contracts

One `###` section per script, keyed by file name. Every section states, at minimum:
**Operation/step**, **What it does**, **Inputs**, **Outputs (stdout)**, **Exit codes**, and
**Re-run (idempotency)**. A script in the tree with no complete entry here — or an entry naming a script
that is not in the tree — is a structural defect (`syncjs.contract.script_undocumented`).
Each **Outputs (stdout)** row below spells out, per key, either a **closed** enumeration of literals or an
**open** `<placeholder>` for a value that is instance data. A value a script can emit that a closed
enumeration does not spell out is the same class of defect (`syncjs.contract.value_undeclared`). A row
that is neither — a key the script emits with no value spelled out beside it, or one mixing a
`<placeholder>` with literal alternatives — cannot be evaluated at all and is a defect in its own right
(`syncjs.contract.enumeration_unparseable`), never a skip: a row the gate silently declines to read is how
a closed enumeration gets disarmed by an ordinary markdown edit. A section carrying no
**Outputs (stdout)** row at all is refused for that same reason (`syncjs.contract.outputs_row_absent`), and
a row separating alternatives with anything other than `\|` is refused rather than read short
(`syncjs.contract.separator_unrecognized`) — a comma would otherwise truncate the declared set and
blame the script for the values it dropped.

**What is machine-asserted, stated as a rule.** `ci-templates/scripts/tests/btg-075-script-contract.test.sh`
reads the values out of the shipped scripts rather than trusting this prose. What it enforces varies per
row, and the row itself indicates which case applies:

- A row spelling out **literal** alternatives **is** value-asserted: every value the gate can statically see
  the script emit for that key must appear in it.
- A row spelling out a `<placeholder>` is an **open** enumeration and is **not** value-asserted — only
  its evaluability is checked. An open row binds itself to nothing, by design.

**The check is a SUBSET assertion, never an equality.** It verifies that every value it can *see* is
declared; it may under-report, and it never fabricates. A declared enumeration is therefore an upper bound
that the author asserts, machine-checked against the statically visible producers only.

**The extraction floor, named.** These are unreachable by construction and are *not* enforced:
command substitution (`VAR="$(...)"`), the `${VAR}` brace form and indirect expansion, variable-from-variable
(`VAR=$OTHER`), and any value written to stdout by something other than `js_emit` — a bare `printf`.
One enumeration in this document has a producer behind that floor: `jira-assign.sh`'s `assign_result`, whose
entry names it rather than leaving it to this general concession.

**How much of the surface is enforced is deliberately not a static number here.** A figure written into this
document would rot, and a reader cannot tell a stale number from a current one. The gate computes it on every
run and prints it as `syncjs.contract.coverage_report`, keeping the current value one CI log away.

<!-- Entries are added as each operation script lands (BTG-075 Implementation Order). -->

### jira-connect.sh

| Field | Value |
|---|---|
| **Operation/step** | Prerequisite — connectivity check + self-identity resolution, run once at the head of every operation |
| **What it does** | Verifies the environment carries a base URL and a PAT, then resolves the effective self identity: a non-empty `JIRA_SELF` always wins (no cache read, no cache write, no network call); otherwise a credential-fingerprinted user-level cache **outside** the repository tree is consulted, and on a miss `GET /rest/api/2/myself` is read for its `.name` and written back atomically. A rotated PAT or a re-pointed instance structurally invalidates the entry, so a stale identity can never be served (BTG-066). The identity never reaches the repository |
| **Inputs** | Environment: `JIRA_BASE_URL`, `JIRA_PAT` (required); `JIRA_SELF` (optional adopter override); `XDG_CACHE_HOME` / `HOME` (cache location). No arguments |
| **Outputs (stdout)** | `self=<username>` + `self_source=env\|cache\|rest` on success; `self_result=unresolved` when connectivity succeeded but no usable `.name` was returned |
| **Exit codes** | `0` resolved (or connectivity proven with the identity unresolved — non-blocking); `2` a required environment variable is unset; `3` `syncjs.transport.rest_unreachable`; `1` `syncjs.connect.rest_rejected` (non-2xx: the PAT is missing, expired, or unauthorized) |
| **Re-run (idempotency)** | A pure read. A re-run returns the same identity (from the cache, with no network call) and mutates no Jira state; the cache write is an overwrite in place, so no entry is ever orphaned or duplicated |

### jira-preserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Projection — preserve the as-filed original intake as a comment, immediately **before** the projection write |
| **What it does** | Reads the issue's current fields over REST v2 (**raw wiki**), and, unless the description already carries the format-invariant `Repo-managed` sentinel, substitutes the tokens of the co-located `.agents/skills/cadence-sync-jira/originalcontent_TEMPLATE.txt` **entirely in script** (zero inference — DEC-005) and posts the result as a comment. The as-filed values are copied **verbatim**: never reformatted, re-wrapped, summarized, or converted. The acceptance-criteria line is toggle-gated and renders **state-preserving** (`(x)`/`( )` — the as-filed record, unlike the always-unchecked outbound projection); its plugin-provided field is discovered by **exact name**, and zero or ambiguous matches render `_(none)_` rather than guessing a field |
| **Inputs** | `--issue-key <KEY>` (required). Environment: the base URL and PAT named by the config's `env` block. Files: the config sidecar, `originalcontent_TEMPLATE.txt` |
| **Outputs (stdout)** | `preserved=true` (comment posted) or `preserved=skipped` (already repo-managed) |
| **Exit codes** | `0` preserved or sanctioned skip; `1` the as-filed read was rejected/unparseable (`syncjs.comment.rest_read_rejected`), the comment POST was rejected (`syncjs.comment.rest_post_rejected`), or the render failed; `2` usage / missing environment / missing template; `3` transport unreachable; `4` config HALT. **Every non-zero halts the sequence before the projection write** — the next step overwrites the summary/description, so a swallowed failure here would cause data loss rather than a degraded run |
| **Re-run (idempotency)** | Guarded by the `Repo-managed` sentinel: the comment is posted only on the first sync of an unmanaged ticket. A re-run reads the now repo-managed description and **skips** (`preserved=skipped`), ensuring the comment is never double-posted |

### jira-write-issue.sh

| Field | Value |
|---|---|
| **Operation/step** | Projection — write the repository's ticket state onto the Jira issue |
| **What it does** | Projects summary, issue type, priority, and labels (an **Epic** deliberately carries none of those: BTG-040 keeps it minimal, though its create DOES carry the instance's Epic Name field, without which an Agile instance rejects the create with 400). **The projected `Summary` is the ticket's `title` ALONE** — `SUMMARY="$TITLE"`. It carried a `"<TICKET>: "` prefix until BTG-124 removed it so the board reads as human titles; an empty or whitespace-only `title` is now refused **before any REST call** (`syncjs.write.title_absent`), because without the prefix a degenerate title would reach the wire as `""` and trigger a 400 at this blocking step. **That single `$SUMMARY` scalar feeds TWO Jira fields, not one:** `fields.summary` on every write, **and** the discovered **Epic Name** custom field on a single-level `type: epic` create. Thus an edit to summary construction changes the agile board's epic swimlane label too — BTG-124 DEC-008 ratified that coupling deliberately (OQ-2 option 2a: Epic Name follows Summary and drops the prefix as well), noted here because it is the kind of second-field coupling PROD_CADENCE-006 shows is easy to miss when reading the field list alone. It is the **sole writer of `issuetype` and `summary`**, so for `type: epic` it resolves the BTG-036 fork FIRST through `.agents/skills/cadence-sync-jira/jira-epic-lib.sh`: a **single-level** epic is typed `Epic` with its Epic Name, while an **umbrella** (one already carrying a live Epic Link, which Jira forbids an Epic to hold) is typed the configured plain type with a `[UMBRELLA] {title}` summary and no Epic Name. On CREATE there is no live issue and therefore no Epic Link, so the branch is single-level by construction and costs no call; on UPDATE a fork that cannot be READ HALTS before any write, because every field this script writes for an epic depends on the answer and promoting on a failed read writes the state Jira forbids. The repository `estimated_effort` is **projected**, not forwarded: a range gives its upper bound (`2-4h` → `4h`) and a value that is not a Jira duration at all is OMITTED and reported (`estimate_result=unprojectable`) rather than sent to take a 400 at this blocking step and strand the ticket. On `--mode create` it `POST`s and reads the new key from top-level `.key`; on `--mode update` (the default) it reads the issue's **current** Remaining Estimate as an explicit prerequisite and issues the update `PUT` with a `timetracking` object that co-sends `originalEstimate` **and** `remainingEstimate` — because in Jira Server/DC writing Original alone RESETS Remaining (PROD_CADENCE-006/BTG-037). A read failure never degrades to Original-alone; a genuinely never-estimated issue omits `remainingEstimate` entirely (never `""`, never `null`). When a rendered description temp file is supplied, it is folded into the same `PUT` as raw bytes (`jq` performs JSON encoding, so the wiki markup reaches Jira as rendered) and the file is **unlinked on every exit path**. **Before the body is built, it ASKS THE INSTANCE which of four fields the target screen carries** — `timetracking`, `priority`, `labels`, and `description` — through the shared predicate in `.agents/skills/cadence-sync-jira/jira-screen-lib.sh`, whose contract is the fifth part of this index (`.agents/skills/cadence-sync-jira/jira-server-scripts-screens.md`) and whose eight conditions are catalogued in `.agents/skills/cadence-sync-jira/jira-server-conditions-screens.md`. A field the screen does not carry is **OMITTED with a named condition** instead of taking a 400 that aborts the WHOLE projection (BTG-168 / PROD_CADENCE-024, observed live: a Bug create screen without Time Tracking made every bug-type ticket carrying an estimate unprojectable). **Only an affirmative absence suppresses** — an unreachable or unparseable metadata read sends all four as normal — and a create that suppressed any field is completed by **exactly one** follow-up `PUT` carrying every suppressed field that the issue's EDIT screen accepts |
| **Inputs** | `--ticket <id>` (required), `--mode create\|update` (optional, default `update`), `--issue-key <KEY>` (required on the **update** path only — a create has no key yet), `--description-file <path>` (optional — a **fresh** temp file the orchestrator rendered for **this** projection; consumed and deleted here, never reused, AC-4; a named-but-unreadable path is a usage failure, never an empty-description projection). Environment: the base URL and PAT named by the config's `env` block. Files: `metadata.yaml` (read-only), the config sidecar |
| **Outputs (stdout)** | `issue_key=<KEY>` (the key Jira assigned, on create), `jira_url=<base>/browse/<KEY>`, `estimate_result=cosent\|original-only\|unprojectable\|none\|field-unsupported\|followup-written` (the last two added by BTG-168: `field-unsupported` means there WAS an estimate and the target screen would not take it — never `none`, which means there was none to project — and `followup-written` means the create-completion write landed it), `issuetype_projected=yes\|no` (BTG-102 — `no` when the pre-flight guard withheld the issue type, keeping the decision auditable from the transcript), `epic_branch=single-level\|umbrella` (on `type: epic` only), `ac_result=projected\|skipped\|skipped-epic\|disabled\|rejected\|source-unreadable\|section-absent\|items-unrecognized\|scratch-unavailable\|body-unbuildable` (the projection itself lives in `.agents/skills/cadence-sync-jira/jira-ac-lib.sh`; this script remains its only caller and the only `js_emit ac_result` site) |
| **Exit codes** | `0` written; `1` the ticket's `title` is empty or whitespace-only so `fields.summary` would be sent as `""` (`syncjs.write.title_absent` — BTG-124, refused **before** any REST call), the current-Remaining read was rejected/unparseable (`syncjs.estimate.current_remaining_unreadable`), the write was rejected (`syncjs.write.rest_rejected`), the rendered description was empty (`syncjs.description.empty_render`), an Epic create could not resolve the Epic Name field (`syncjs.epic.name_field_unresolved`), a `type: epic` ticket's live Epic Link could not be read so the fork is unresolved (`syncjs.umbrella.epic_link_unreadable`), or the request body could not be built (`syncjs.write.body_unbuildable` — an unchecked build leaves the file empty and sends a write with no fields, which Jira rejects with an opaque 400); `2` usage, including an update with no rendered description (`syncjs.description.update_reproject_absent` — BTG-062: a dropped description is a refusal, not a quiet field drop); `3` transport unreachable; `4` config HALT. **Every config value this script needs — including `acceptance_criteria_sync_enabled`, which is consumed only after the write — is RESOLVED before the create/update call**, so a config HALT costs nothing: resolving that toggle afterwards meant a `--mode create` run could exit `4` after already creating the issue and emitting no `issue_key=` |
| **Re-run (idempotency)** | Set-to-desired: the `PUT` sets fields to the repository's current projection, so re-running with unchanged repository state yields the same issue and creates nothing. The estimate co-send preserves Remaining at its worked-down value, so a re-run never resets burndown |

### jira-metadata-write.sh

| Field | Value |
|---|---|
| **Operation/step** | Not a Jira operation — the orchestrator's dedicated, sole writer of the repo-owned `metadata.yaml`. Extracted from `jira-server-orchestration.md`'s fenced reference implementation (DEC-014, Option C), so the single-writer guarantee is an executable script that a harness can run and the metadata-write seam enumerates, rather than prose an agent is trusted to execute. Every OTHER script in this index reads `metadata.yaml` and never writes it (AC-6); this script is the sole writer |
| **What it does** | Applies each `--set key=value` pair whose value is non-empty: substitutes the key's existing line in place (commented or not, preserving its trailing comment) or appends it as a new top-level line. Builds the complete new image in a temp file, VERIFIES that every requested key landed, then replaces the owned file with a single atomic `mv -f` — one write per invocation, so a reader never observes a partial image. Called by the orchestrator up to **three** times per ticket: early after step 4 (`jira_url`, `mode = create` only), early after step 9 (`umbrella_epic_url`, guarded on a non-empty emitted value), and once at end-of-operation carrying every key accumulated during the run |
| **Inputs** | `--ticket <id>` (required), `--set <key>=<value>` (repeatable, at least one required — narrow and explicit, never the raw accumulated payload). Files: the ticket's `metadata.yaml` under `specs/<id>/` or `archive/<id>/` (the only file this script writes) |
| **Outputs (stdout)** | Nothing |
| **Exit codes** | `0` written, or a declared no-delta (every `--set` value was empty); `1` fail-loud (`metadata.yaml` absent, or a temp-file allocation / post-write verification failed — refusing rather than reporting a no-op as success); `2` usage (missing `--ticket`, missing `--set`, or a dangling flag); `4` config HALT (unreachable in practice: this script makes no REST call and reads no config) |
| **Re-run (idempotency)** | Re-applying the same value converges byte-identically (each key is SET to the desired value, never appended twice), so the early writes and the end-of-operation call — all carrying values derived from the same run — never clobber one another and a re-run after a halt is safe |

### jira-worklog.sh

| Field | Value |
|---|---|
| **Operation/step** | Projection — post each NEW `stage_effort` entry as its own Jira worklog, after the status transition |
| **What it does** | Selects candidates from the repo-owned `worklog_watermark_at` alone (an entry is **already-synced iff** `entry.at <= worklog_watermark_at`; tracker state is never an input), runs the **SUPPRESS-ONLY** crash-recovery marker scan (bracket-agnostic on the `stage=<stage> at=<at>` core — Jira strips the brackets on read-back), reads the pre-add **baseline**, posts one `adjustEstimate=auto` worklog carrying only `timeSpent` + the marker comment, then verifies absorption from a **fresh re-read**. A posted worklog is **never updated and never deleted**, and tracker totals are never compared to `actual_effort` (BTG-064) |
| **Inputs** | `--ticket <id>` (required), `--issue-key <KEY>` (required). Environment: the base URL and PAT named by the config's `env` block. Files: `metadata.yaml` (read-only), the config sidecar (`toggles.worklog_creation_enabled`, `worklog_postcheck_capability`, `duration_units`) |
| **Outputs (stdout)** | `worklogs_posted=<n>`, `worklog_result=posted\|disabled\|skipped-epic\|seeded\|halted-malformed\|posted-then-halted-malformed\|postcheck-failed\|postcheck-indeterminate\|none`, `worklog_watermark_advance=<iso8601>` **only** when the watermark legitimately advances, and `agent_legs_rejected=<n>` (BTG-315) **only** in split mode |
| **Exit codes** | `0` posted, sanctioned skip, disabled, seeded, or a scoped batch halt (a malformed entry or a failed post-check stops the batch without aborting the sync); `1` the crash-recovery scan was rejected/unparseable (`syncjs.worklog.marker_scan_rejected`), the post was rejected (`syncjs.worklog.post_rejected`), or — split mode only (BTG-319) — the agent leg's response was not positively identified as a permanent rejection (`syncjs.worklog.agent_leg_status_ambiguous`; a re-run retries only the missing agent leg); `2` usage; `3` transport unreachable; `4` config HALT (`worklog_postcheck_capability` absent/unrecognized — never a silent `none`) |
| **Re-run (idempotency)** | Decided **only** from `worklog_watermark_at`, which the orchestrator advances solely on a full-sequence success — so a halt leaves it unadvanced and the next re-run re-derives the identical batch. An entry at or below the watermark is never re-posted; the suppress-only scan closes the crash window where a post landed but the watermark write did not, and a suppressed entry still advances the watermark to observed reality. This is the BTG-064 treatment |

**BTG-315 (additive):** when the ticket's §9 row names an agent-time user (`$AGENT_USER`
non-empty, resolved once by `jira-worklog-prepare.sh`), each candidate is instead handled
by `jira-worklog-agent.sh`'s `js_worklog_process_split_candidate` — see
`.agents/skills/cadence-sync-jira/jira-server-scripts-libs.md`. Split mode adds a stdout key,
`agent_legs_rejected=<n>`, emitted **only** when `$AGENT_USER` is non-empty; an unconfigured run's
stdout key set is byte-unchanged. Exit codes gain `4` for `syncjs.worklog.split_unavailable` (an
agent-time user is configured but `worklog-split.sh` is missing or errored) — unreachable in
unsplit mode.

### jira-assign.sh

| Field | Value |
|---|---|
| **Operation/step** | Reconciliation — set the Jira assignee from the repository `status`, immediately **after** the status transition (**best-effort**) |
| **What it does** | Resolves the status-mapped action from the config's `assignment_map` (`self` / `unassigned` / `no-change`) and writes the assignee. A status outside the map is **reported, never guessed**. The `self` identity is the credential's own, resolved by `jira-connect.sh` and passed in with `--self` — never read from artifact content and never hardcoded; an unresolved identity skips and reports rather than approximating a name. Running after the transition makes this write the final word, preventing a workflow automation firing during the transition from overwriting it |
| **Inputs** | `--ticket <id>` (required), `--issue-key <KEY>` (required), `--self <username>` (optional — required only for the `self` action). Environment: the base URL and PAT named by the config's `env` block. Files: `metadata.yaml` (read-only), the config sidecar (`toggles.assignment_reconciliation_enabled`, `assignment_map`) |
| **Outputs (stdout)** | `assign_result=self\|unassigned\|no-change\|skipped-epic\|unknown-status\|disabled\|rejected`. **Partially machine-asserted — the single named exception to §6's rule.** The value is emitted through `$ACTION`, which arrives via command substitution (`ACTION="$(js_config_map …)"`) and is therefore **not statically visible** to the contract gate. The five values written as bare literals in the script — `no-change`, `skipped-epic`, `unknown-status`, `disabled`, `rejected` — are extracted and checked. `self` and `unassigned` reach stdout **only** through that producer, so they are bounded by this script's own catch-all `*)` case arm, which reports an unmapped action rather than inventing one. A new `case` arm shipping an undeclared value would not be caught statically here |
| **Exit codes** | `0` for **every** outcome including a rejection — assignment is best-effort and never a gate on the surrounding sync (BTG-014). Only breakage exits non-zero: `2` usage / missing environment, `4` config HALT. The toggle is **opt-in**: absent ⇒ DISABLED, so a repository predating the feature is never silently opted into overwriting a manually set assignee |
| **Re-run (idempotency)** | Set-to-desired: the assignee is written **to** the status-mapped target, so a re-run writes the same value. Nothing accumulates and nothing is appended |

### jira-transition.sh

| Field | Value |
|---|---|
| **Operation/step** | Reconciliation — apply the repository `status` as a workflow **transition** (Jira does not allow setting status directly) |
| **What it does** | Reads the issue's **live** status and issue type (the workflow scheme follows the type Jira holds, not the one the repository prefers), resolves the target from `status_workflow_map[<issue type>][<status>]`, and applies the offered transition whose `to.name` is that target — or the instance-declared `global_transitions` id when the target is not directly offered. After **every** hop it RE-READS where the issue landed, because a Jira post-function can route it somewhere other than the transition's declared `to`. An Epic is skipped before any call (BTG-040: Epic status is human-managed) |
| **Inputs** | `--ticket <id>` (required), `--issue-key <KEY>` (required). Environment: the base URL and PAT named by the config's `env` block. Files: `metadata.yaml` (read-only), the config sidecar (`status_workflow_map`) |
| **Outputs (stdout)** | `transitions_applied=<n>`, `transition_result=applied\|at-target\|skipped-epic\|skipped-unmapped` |
| **Exit codes** | `0` applied, already at target, Epic-skipped, or unmapped-and-reported; `1` the read or transition POST was rejected (`syncjs.transition.rest_rejected`), or the target is not reachable and no global id is declared (`syncjs.transition.unreachable`) — an intermediate hop is **never guessed**, because picking whichever transition happens to be offered is an ungoverned state change on a real board; `2` usage; `3` transport unreachable; `4` config HALT. **Blocking**: status is the field every other CADENCE surface reads back |
| **Re-run (idempotency)** | Transitions **to the target**. A re-run of an issue already at the target reads its status, matches, and applies nothing (`transitions_applied=0`) — a completed path is never re-walked |

### jira-resolve.sh

| Field | Value |
|---|---|
| **Operation/step** | Resolution — decide CREATE vs UPDATE and resolve the issue key (the first ticket-scoped step) |
| **What it does** | Answers from repository state, and **only** from repository state: a populated `jira_url` yields the key with **no** network call, and its absence resolves to `create`. **BTG-124 (DEC-007, OQ-1 Option C, ratified at the Spec Review gate) DELETED the halted-run recovery search that previously ran here and did NOT replace it.** That search matched the repository id inside the projected Summary, and BTG-124 removed the id from the Summary; rather than re-pointing it at another signal, the gate accepted the removal. Thus `jira_url` is now the **sole** identity mapping, and this script issues **no REST request on any path**. The consequence is stated explicitly: since BTG-125, `jira_url` is recorded as soon as `jira-write-issue.sh` (step 4) returns, so the residual window that could let a re-run mint a **duplicate** — the one effect nothing downstream can undo — is narrow: a halt **inside** step 4 itself, between the create POST and the script's return. That residual is **REPORTED** on the create branch (the `syncjs.resolve.create` message names the absent lookup, identifies `jira_url` as the sole mapping, states the residual window's bounds, and warns about potential duplication), never taken silently. Read-only: this script mutates nothing |
| **Inputs** | `--ticket <id>` (required). Environment: **none**. Since BTG-124 (DEC-007) this script resolves entirely from repository state and issues no network request, reading no environment variable at all — the project key left with the deleted search's JQL, and the base URL left with the transport halt and `jira_url=` emit that only the recovery path produced. The base URL and PAT remain required at **step 1** (`jira-connect.sh`), which is blocking, enforcing them earlier in the sequence than this script did. Files: `metadata.yaml` (read-only), the config sidecar |
| **Outputs (stdout)** | `mode=update\|create`; `issue_key=<KEY>` when resolved from a recorded `jira_url`. It no longer emits a `jira_url=` delta: that key existed **only** for the deleted recovery path, where the script learned a mapping the repository did not yet hold |
| **Exit codes** | `0` resolved; `1` the recorded `jira_url` does not end in a key (`syncjs.resolve.url_unparseable`); `2` usage — **argv only** (unknown flag, malformed pair, absent `--ticket`); `4` config HALT. **`3` is no longer reachable**, and neither are `syncjs.resolve.search_rejected`, `syncjs.resolve.ambiguous`, or **`syncjs.resolve.env_absent`**. The first three belonged to the deleted search. `env_absent` was removed alongside the base-URL requirement: once no request is issued, demanding the variable would refuse — with a *usage* error — a resolution this script can complete from repository state alone. All four removals are recorded here so an operator searching for them finds the rationale |
| **Re-run (idempotency)** | This script **is** the sync's idempotency hinge, and since BTG-124 its answer derives strictly from the repository's record: a re-run of an already-created ticket resolves to `update` **from `jira_url`**. When a halt left `jira_url` unrecorded, it resolves to `create` and reports that explicitly |

### jira-link.sh

| Field | Value |
|---|---|
| **Operation/step** | Best-effort — project the repository's related-ticket declarations as Jira issue links |
| **What it does** | Derives the relation from the DECLARING KEY when present: `precedes:` / `preceded_by:` → the ordered type with the predecessor in the configured slot (this instance stores it INVERTED, in `inwardIssue`), `duplicates:` → `Duplicate`, `clones:` → `Cloners`, and a **keyed** `related_tickets:` map by its own keys. A **flat** `related_tickets:` list — the shape this repository holds — states its relation in the entry's TRAILING COMMENT, read from the raw file and mapped onto the same declaring keys so one code path serves both shapes; a comment asserting BOTH landing directions degrades to the symmetric default (`syncjs.link.signal_ambiguous`) rather than picking one (DEC-032). The extraction — including the type dispatch that fans a LIST-valued keyed sub-key out to one target per element and refuses any value it cannot read (`.agents/skills/cadence-sync-jira/jira-link-targets.sh`, BTG-106) — belongs to that module; what arrives here is the deduplicated row set and a count of unreadable declarations, which seeds this script's rejection total so an unreadable declaration is never reported as `none`. Targets are DEDUPED by repository id at the STRONGEST signal (ordered > duplicate > clone > symmetric), because the existing-link snapshot is taken once before the loop and a ticket named twice would otherwise be linked twice. The ordered type itself is **discovered from the instance** by `precedes` / `is preceded by` phrasing rather than by the config's declared name (this organization's is `precedes ` — trailing space); an unreadable type list is not an absent type and nothing is guessed (DEC-031). Each referenced ticket is resolved to a Jira key by a **direct key lookup only**, and checked for EXISTENCE first — only a definitive 404 is an absence; a 401/403/500 is a failure to ASK, reported as `syncjs.link.reference_unresolved` and counted so the result is never `up-to-date` (DEC-033). **BTG-124 (DEC-007, OQ-1 Option C) DELETED the summary-search fallback that previously ran on that 404 and did not replace it**: it matched the repository id inside the projected Summary, and BTG-124 removed the id from the Summary. A repo-id target that is not itself a Jira key is therefore now reported as `syncjs.link.referenced_absent` rather than resolved, and `syncjs.link.reference_resolved` is retired and never emitted. The accepted tradeoff is that a cross-reference to a **not-yet-synced** ticket does not link; it degrades cleanly by design — this step is best-effort and exits `0` for every outcome — while still naming and counting the absence. This step never creates the referenced issue. Linking is additive-only, with one exception: an ordered link whose stored slots are reversed records the ordering backwards on the board, so it is recreated the right way round and the reversed one is then removed — in that order, with the delete's result checked, so no single failure can leave the pair unlinked (a refused recreate reports `syncjs.link.heal_abandoned` and deletes nothing; a refused delete reports `syncjs.link.heal_incomplete` and leaves both links). Direction is read with `$ISSUE_KEY` folded back in as the implicit near endpoint, because a per-issue `issuelinks` entry names only the FAR one. Epics are exempt (their children carry the Epic Link field) and `decomposed_into` is a lineage record, not a link source. **BTG-107 AC-1**: every non-linked disposition of a declared reference lands in one of three counters, which PARTITION the rejection total exhaustively and disjointly — `references_unreadable` (the declaration could not be read; zero requests made), `references_unresolved` (the far end could not be established: transport, 401/403/500, or a definitive 404), and `references_skipped` (the reference resolved but its link was not created, completed, or confirmed this run, including an ordered link skipped for an unreadable type). `link_result` is `rejected` whenever their sum is non-zero, never a separately incremented total. On the AC-5 failed-extraction path, `references_unreadable` is a **floor, not a total** — the extraction that would have produced the true count is what failed |
| **Inputs** | `--ticket <id>`, `--issue-key <KEY>`. Reads `precedes` / `preceded_by` / `duplicates` / `clones` / `related_tickets` / `type` from `metadata.yaml`, and `link_relations` from the config sidecar |
| **Outputs (stdout)** | `links_created=<n>`, `references_unreadable=<n>`, `references_unresolved=<n>`, `references_skipped=<n>`, `link_result=created\|up-to-date\|none\|rejected` |
| **Exit codes** | `0` for every outcome including a rejection (best-effort — a link failure never halts the ticket); `2` usage; `4` config HALT |
| **Re-run (idempotency)** | Read-before-write, with a TYPE-AWARE skip: an existing link **of the same type** in the right direction is left untouched, so a re-run creates no duplicate, while an unrelated `Relates` link does not suppress a required ordered link. A reversed ordered link converges to the proper direction rather than accumulating a second link |

### jira-epic.sh / jira-umbrella-lib.sh

**Relocated, not removed.** Both contract entries live in
`.agents/skills/cadence-sync-jira/jira-server-scripts-umbrella.md` — the second part of this unified index,
split off by BTG-105 when the umbrella replacement flow's two entries pushed this file past the
400-line Agentic DX ceiling. The record is **split, never truncated**, using the same pillar-tension resolution
BTG-102 applied to the condition catalogue (C-3 — Operability outranks DX on *content*).

### jira-reserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — reserve a ticket key when the tracker is the numbering authority |
| **What it does** | Creates the reservation issue and returns the key **Jira** assigned. A failed reservation stops rather than guessing a number, and a locally computed key is never assumed. **Before** the create, it reports `syncjs.reserve.pairing_obligation`: the key it is about to reserve must be paired, within this same governed operation, with `specs/<id>/problem.md` and `specs/<id>/metadata.yaml`, per `CADENCE_ORG.md` `#id-allocation-binding` (Reservation pairing). It writes neither file itself — it declares the obligation and the caller discharges it — and an allocation left unpaired is reported as `idalloc.reserve.unpaired_artifact_creation` |
| **Inputs** | `--summary <text>` (required), `--type <repo-type>` (optional, default `tech-debt`), `--prefix <PREFIX>` (the ticket-id prefix; optional in general, **REQUIRED** on a repository whose `CADENCE_ORG.md` §9 declares a PER-PREFIX table, where omitting it halts `4` on `syncjs.config.project_key_precondition_unmet` rather than falling back to the deprecated environment variable). Environment: base URL, PAT, project key |
| **Outputs (stdout)** | `issue_key=<KEY>`, `jira_url=<url>` |
| **Exit codes** | `0` reserved; `1` the create was rejected or carried no key; `2` usage; `3` transport unreachable; `4` config HALT |
| **Re-run (idempotency)** | **Not** idempotent by construction, and deliberately so: each call reserves a NEW key. It is called once per origination, by `/cadence-triage`, before any artifact exists — a re-run means a second ticket is being originated, and therefore a second pairing is owed. Because the id does not exist until the create returns, a "refuse unless `specs/<id>/` exists" precondition is structurally impossible here; the obligation is declared instead, and `/cadence-triage` verifies that it was discharged |

### jira-import.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — seed-read an existing issue (ticket-first triage) |
| **What it does** | Reads the issue's core fields into a seed file, reads the dedicated acceptance-criteria field into unchecked `- [ ]` items, and downloads attachments within the configured ceiling, each under BTG-043's collision-free `{attachmentId}-{sanitizedFilename}` name (Jira permits multiple attachments with the same filename on one issue, so a bare basename would silently overwrite). Writes **nothing** to Jira |
| **Inputs** | `--issue-key <KEY>` (required), `--ticket <id>` (optional; sets the attachment directory) |
| **Outputs (stdout)** | `issue_key=<KEY>`, `seed_dir=<path>`, `summary_file=<path>`, `ac_items_file=<path>`, `manifest_file=<path>`, `attachments_downloaded=<n>`, `attachments_referenced=<n>`, `type_hint=<repo-type>` (empty when the instance type maps to none). Every value is instance data, making this row an OPEN enumeration by construction. The seed files live inside `seed_dir`, which the CALLER removes once `problem.md` is written; a failed import unlinks it directly |
| **Exit codes** | `0` seeded; `1` the read was rejected or unparseable; `2` usage; `3` transport unreachable; `4` config HALT |
| **Re-run (idempotency)** | A pure read against Jira. A re-run re-reads the same issue and rewrites its own temp seed files; attachment ingestion is one-time and non-authoritative afterwards, and an absent or malformed ceiling fails CLOSED (reference all, download none) |

### jira-sprint-check.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — check whether the ticket is in an open sprint (input to `/cadence-implement`'s sprint guard) |
| **What it does** | Runs a single `key=<KEY> AND sprint in openSprints()` query and maps it to one verdict. The key is resolved **verbatim** (no summary-search fallback). A `400` means no such key and maps to `inconclusive`, **never** `not-in-sprint` |
| **Inputs** | `--ticket <id>`. Reads `metadata.yaml` `jira_url` when present |
| **Outputs (stdout)** | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive`, `issue_key=<KEY>` |
| **Exit codes** | `0` — a verdict is a RESULT, not a failure; the guard decides how to handle it. `2` usage; `4` config HALT. A transport failure is reported and returned as `inconclusive`, never assumed |
| **Re-run (idempotency)** | Read-only: writes nothing to Jira and nothing to the repository, making it trivially re-runnable |

### Shared libraries (BTG-247)

`jira-rest.sh`, `jira-meta.sh`, `jira-link-lib.sh`, `jira-link-targets.sh`, `jira-ac-lib.sh`, `jira-epic-lib.sh`, and `jira-lib.sh` — relocated, not removed — are documented in `.agents/skills/cadence-sync-jira/jira-server-scripts-libs.md` (BTG-247); `jira-projectkey-lib.sh` is in `.agents/skills/cadence-sync-jira/jira-server-scripts-projectkey.md` (BTG-179); `jira-md2wiki.sh` and `jira-md2wiki-lib.sh` are in `.agents/skills/cadence-sync-jira/jira-server-scripts-render.md` (BTG-205) — each a further part of this single index, applying the same pillar-tension resolution as BTG-102, BTG-105, BTG-168, and BTG-173: split, never truncated.
