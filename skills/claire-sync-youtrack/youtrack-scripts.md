# `/claire-sync-youtrack` — script contracts

Bounded context: Tracker projection / YouTrack Server adapter.
Invariant relied on from outside this boundary: the repository (`metadata.yaml` + `problem.md`) is the
source of truth; YouTrack is the projection layer. This document is the **interface index** for the
skill: `.claude/skills/claire-sync-youtrack/SKILL.md` is a thin **orchestrator** that sequences the standalone
single-operation scripts contracted below, and each script performs exactly one mechanical YouTrack REST
operation (ADR_CLAIRE-0025; `archive/BTG-176/spec.md` AC-2).

Its second part is `.claude/skills/claire-sync-youtrack/youtrack-scripts-projectkey.md` (BTG-179 DEC-019) — split, never truncated.
Read this document plus the one script you are changing — never all of them. That is the whole point of
the contract: an agent modifying one operation reads (1) this file, (2)
`.claude/skills/claire-sync-youtrack/yt-lib.sh`, (3) the operation script, (4)
`.claude/skills/claire-sync-youtrack/youtrack-server-config.json`, (5) the skill body.

**Every REST shape asserted here was OBSERVED live** against the instance the version floor names
(v2026.1 build 13162) and is recorded, with its response, in
`archive/BTG-176/spec-2-live-rest-observations.md`. Nothing below is inferred from the sibling adapter.

---

## 1. The three-channel return contract

Every script communicates on exactly three channels. Nothing else is a return value; the orchestrator
never scrapes prose.

| Channel | Carries | Consumed by |
|---|---|---|
| **stdout** | Machine-readable result **only**: zero or more `key=value` lines drawn from that script's documented vocabulary (`issue_id=2-13461`, `youtrack_url=…`, `worklog_watermark_advance=<iso8601>`, `assign_result=applied`). No prose, ever. A script with nothing to return writes nothing. | The orchestrator, which accumulates the lines and computes the single end-of-operation `metadata.yaml` write |
| **stderr** | The human-readable `syncyt.*` reported-condition audit stream plus diagnostics. Never parsed for control flow. | The operator / the transcript |
| **exit code** | Status (below). | The orchestrator's halt decision |

### Exit codes

| Code | Meaning | Orchestrator behaviour |
|---|---|---|
| `0` | Success, or a sanctioned best-effort refusal reported as a `*_result=` payload | Continue |
| `1` | Fail-loud; the named `syncyt.*` condition is already on stderr | **Halt** this ticket |
| `2` | Usage / setup failure (missing argument, missing environment variable) | **Halt** this ticket |
| `3` | Transport unreachable (`syncyt.transport.rest_unreachable`) — distinct from a ticket-resolution failure | **Halt** this ticket |
| `4` | Config absent or malformed — a fail-loud key could not be resolved | **Halt** this ticket |

**The halt decision reads the exit code ALONE.** A step's *class* (`blocking` / `best-effort`) decides
only which refusals a script may report as a completed run: a best-effort step that cannot do its job
exits **0** carrying `<something>_result=rejected`, and the ticket continues. A non-zero exit from any
step halts the ticket whatever its class — a best-effort script that exits non-zero has not refused, it
has *broken*, and breakage is never swallowed.

On a halt the orchestrator neither rolls back nor compensates nor auto-resumes; it emits a
partial-completion report and leaves the already-applied YouTrack effects in place. Recovery is an
operator re-run, which is safe because every script is idempotent (§5).

---

## 2. Invocation conventions

- **Arguments** are long-form (`--ticket BTG-176`, `--issue 2-13461`, `--description-file <path>`). A
  missing required argument is a usage failure (exit `2`), never a default.
- **Two id forms exist and they are not interchangeable.** The *readable* id (`<KEY>-<n>`) and the *internal*
  id (`2-13461`) both work in a URL path, but a link body's `id` key requires the **internal** one — a
  readable id there answers HTTP 400 quoting back only its alphabetic prefix, which names nothing an
  operator could act on. Every step after the write is therefore addressed by the internal id the write
  step emitted.
- **Environment** supplies the transport and the credential: `YOUTRACK_BASE_URL`, `YOUTRACK_TOKEN`, and the optional adopter override `YOUTRACK_SELF`. The env-var *names* are themselves config (the `env` block of the config sidecar); the *values* are never written anywhere.
- **The PROJECT KEY no longer comes from the environment.** `YOUTRACK_PROJECT_KEY` is **DEPRECATED as the project-key source** (BTG-179), sunsets after ONE release cycle, and the route off it is `docs/migrations/multi-tracker-binding.md`.
  It is still READ, as level (3) of: (1) the ticket prefix's `CLAIRE_ORG.md` §9 row -> (2) §9's scalar `**Project key(s):**` line -> (3) the variable. A read at level (3) reports `syncyt.config.project_key_from_env`. Migration: `docs/migrations/multi-tracker-binding.md`.
- **The repository root** is `$CLAIRE_REPO_ROOT` when set, else the current working directory. Ticket
  artifacts resolve to `specs/<id>/metadata.yaml`, falling back to `archive/<id>/metadata.yaml`.
- **The config sidecar** is `$YOUTRACK_SERVER_CONFIG` when set, else `youtrack-server-config.json`
  co-located with the script.
- **The shared library** `.claude/skills/claire-sync-youtrack/yt-lib.sh` is sourced by every operation script. It
  centralises config resolution (including every key's fail-loud/default polarity), the REST helpers, the
  `metadata.yaml` reader, the stdout emitter and the `syncyt.*` reporter — so no script re-implements a
  polarity or a transport detail.

### Credential handling (Facet 7)

The YouTrack permanent token is read from the environment at call time and passed to `curl` through a
`-K-` stdin config block. It is **never** a positional argument (argv is visible to `ps`), never written
to a temp file, a log line, an artifact or `metadata.yaml`. The self-identity cache stores only an
irreversible credential fingerprint, never the token, and lives **outside** the repository tree.

**An attachment's `url` is itself a credential.** It carries a `sign=` parameter and was live-observed
returning the file's bytes with **no** `Authorization` header — anyone holding it can read the file. It
must never reach a log, an artifact or an error message: every diagnostic names the attachment **id** and
the HTTP status, and `yt-import.sh`'s manifest records a *disposition* rather than a location. A signed
url that reaches any of those is `syncyt.attachment.signed_url_disclosed`. This is a real divergence from
the sibling adapter, whose content URL is useless without a credential and is therefore recorded.

---

## 3. Owned-data discipline

A script **reads** `metadata.yaml`; a script **never writes** `metadata.yaml`, and never creates or edits
any other owned artifact. Each script instead returns its metadata-relevant delta on stdout, and the
**orchestrator alone** applies the update — once, at end-of-operation. A mid-sequence halt therefore
leaves `metadata.yaml` untouched.

A degenerate parse of `metadata.yaml` (empty, malformed, or not a JSON object once converted) is a
fail-loud HALT — never a silent proceed on an empty object.

---

## 4. Configuration and its polarity

Everything that varies per repository or per YouTrack instance lives in
`.claude/skills/claire-sync-youtrack/youtrack-server-config.json`; nothing instance-varying is hardcoded in a script
or in skill prose. `yt-lib.sh` is the single resolver, so a key's polarity is defined exactly once.

| Key | Absent / malformed resolves to | Rationale |
|---|---|---|
| the config file itself | **HALT**, `syncyt.config.absent` (exit `4`) | No instance mapping means no correct projection — and, resolved *before* the environment is read, a config problem is never reported as a credential one |
| `worklog_postcheck_capability` | **HALT**, `syncyt.worklog.capability_marker_absent` (exit `4`) — never a silent `none` | A silent `none` would disarm the post-add verification invisibly while the adapter kept posting and reporting success |
| `attachment_size_ceiling_mib` | **fail closed**: reference every attachment, download none | An unbounded download is the unsafe direction, and persisting a file is an irreversible git-history write |
| `worklog_creation_enabled`, `link_creation_enabled` | **enabled** (opt-out toggles) | Effort projection is the adapter's point; linking is additive and hand-reversible |
| `assignment_reconciliation_enabled` | **disabled** (opt-in toggle) | It reassigns issues that may belong to other people |
| `sprint_query` | the `inconclusive` verdict, `syncyt.sprintcheck.query_unconfigured` | This instance has no `openSprints()` analog, so the membership predicate is adopter-specific. Blocking every ticket on an unconfigured query is worse than routing the guard to its fallback |
| `issue_type_map`, `priority_map`, `status_state_map`, `assignment_map`, `link_relations`, `type_conditional_fields`, `custom_field_map` | **HALT** on an unresolvable lookup, `syncyt.config.marker_unresolved` | A guessed Type, Priority or State is an ungoverned decision — and on this instance it is also a guaranteed HTTP 400 |
| `page_top_bound` | **HALT** | An unbounded read cannot report truncation, so a missing bound silently disarms the truncation signal |

An absent toggle is **announced** (`syncyt.config.default_polarity_applied`), never applied in silence: an
operator reading the audit stream must be able to tell a configured polarity from an assumed one.

`page_top_bound` governs the **work-item crash-recovery scan** and nothing else; the link direction
read-backs (`yt-link.sh`, `yt-epic.sh`) and the attachment list (`yt-import.sh`) carry an explicit
`$top=-1` by **ruling, not oversight** (DEC-048) — it declares the size rather than inheriting the
server's default, and cannot truncate. The bound is applied where truncation would make the adapter
**write** something wrong (the scan is suppress-only, so an unseen marker means an unwithdrawable duplicate
work item) and withheld where it would only make it **report** something wrong: a false
`direction_unverified` for a link that landed, or an attachment silently absent from a seed. Each site
carries that reason; "tidying" one into a bounded read re-introduces the failure it names.

---

## 4a. A 2xx IS NOT EVIDENCE — the two guards

This instance answers a create carrying a custom field that the resulting issue's Type cannot hold with
**HTTP 200**, and then **silently discards the value**. Both guards below exist because of that one
observation, they fail in different directions, and neither subsumes the other:

- **Pre-flight refusal.** A field whose value the config's `type_conditional_fields` map says cannot
  attach under the resolved Type is refused **before any request is issued**
  (`syncyt.write.preflight_refused`). The refusal is asserted by the ABSENCE of a call, which is the only
  thing that distinguishes it from a rejection.
- **Read-back.** Every field write is followed by a re-read that compares each intended `(name, value)`
  from **the step's own intent**, never from the instance's reply
  (`syncyt.write.field_applied` / `syncyt.write.field_not_applied`). A field the pre-flight legitimately
  skipped is `syncyt.write.conditional_field_skipped`, which is a different fact from a value that was
  accepted and dropped.

`fields_verified=<n>` on stdout is how many intended fields a step confirmed by reading them back.

---

## 5. Idempotency — every entry states its re-run semantics

Recovery from a halt is an operator re-run, so **every** step must converge to the same YouTrack state and
must never double-apply an effect. Each contract entry carries a **Re-run (idempotency)** field stating
how that script converges. This is a *sequential* re-run property: **concurrency is an explicit
non-goal**, so no locking, lease or compare-and-set exists anywhere in this adapter. Link creation was
observed to be idempotent on this instance; that observation explains why an operator re-run is safe and
must never be cited as evidence that concurrent invocations are.

---

## 6. Script contracts

One `###` section per script, keyed by file name. Every section states **Operation/step**, **What it
does**, **Inputs**, **Outputs (stdout)**, **Exit codes** and **Re-run (idempotency)**. A script in the
tree with no complete entry here — or an entry naming a script that is not in the tree — is a structural
defect (`syncyt.contract.script_undocumented`), asserted in both directions by
`ci-templates/scripts/tests/btg-176-rest-foundation.test.sh` scenario E-8.

### yt-connect.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 1, blocking — connectivity check and self-identity resolution |
| **What it does** | Verifies the environment carries a base URL and a token, then resolves the effective identity: a non-empty adopter override always wins (no cache read, no cache write, no network call); otherwise a credential-fingerprinted cache **outside** the repository tree is consulted, and on a miss `GET /api/users/me` is read for its `.login`. The identity comes from EXACTLY ONE field — never a fallback to `fullName` or `email`, because `Assignee` accepts a login or an internal id but not a display name, so a fallback would produce a value that 400s later, far from here. A rotated token or a re-pointed instance structurally invalidates the cache entry |
| **Inputs** | Environment: base URL and token (required), the optional self override; `XDG_CACHE_HOME` / `HOME`. No arguments |
| **Outputs (stdout)** | `self=<login>` + `self_source=env\|cache\|rest` + `self_id=<1-NNN>` on success; `self_result=unresolved` when connectivity succeeded but no usable `.login` came back |
| **Exit codes** | `0` resolved (or connectivity proven with the identity unresolved — non-blocking); `2` a required environment variable is unset, with **no** network call made; `3` `syncyt.transport.rest_unreachable`; `1` `syncyt.connect.auth_rejected` (the instance was reached and REFUSED the credential — never a transport failure) |
| **Re-run (idempotency)** | A pure read; the cache write is an overwrite in place, and a FAILED resolution writes nothing |

### yt-resolve.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 2, blocking — project resolution and the create-vs-update decision |
| **What it does** | Resolves the project key to its internal id by matching `shortName` **exactly** in the `GET /api/admin/projects?query=` result (a `query=` is a SEARCH, so a substring hit on another project's name would project into the wrong project and report success), refuses an ARCHIVED project, and then decides create-vs-update from the repo's recorded `youtrack_url` alone. There is **no recovery search**: a non-existent readable key answers 400 `invalid_query` and an unknown field name answers 200 with `[]`, so a fuzzy fallback is not available and is not invented |
| **Inputs** | `--ticket <id>` (required). Environment: base URL, token, project key. Files: `metadata.yaml` (read-only), the config sidecar |
| **Outputs (stdout)** | `project_key=<KEY>`, `project_id=<0-NNN>`, `mode=create\|update`, and `issue=<id>` on the update path |
| **Exit codes** | `0` resolved; `1` `syncyt.config.project_unresolved` (including the observed 200-with-`[]`, which is a NOT-FOUND and never an empty success) or `syncyt.config.project_read_refused` on a 401/403 from the project read — a REFUSAL of the credential, reported separately so a permission fault does not wear a bad-project-key's name, and naming the token's read of `/api/admin/projects` as a candidate without asserting the endpoint is admin-only (unverified; BTG-176 DEC-076); `2` usage / unset project-key variable; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | Read-only. Once `youtrack_url` is recorded the same run resolves `update` forever; before it is, a re-run after a halted first sync creates a DUPLICATE — the one non-convergent window in the sequence, and it is named rather than hidden |

### yt-preserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 3, blocking, **update path only** — preserve the as-filed original as a comment, immediately before the projection write |
| **What it does** | Reads the issue's current summary, description and mapped fields and, unless the description already carries the format-invariant `Repo-managed` sentinel, substitutes the tokens of `.claude/skills/claire-sync-youtrack/originalcontent_TEMPLATE.txt` **entirely in script** (zero inference) and posts the result as a comment. The as-filed values are copied **verbatim** — never reformatted, re-wrapped, summarized or converted; YouTrack renders both a description and a comment as Markdown, so nothing converts on this path. A field the issue does not carry renders the template's own missing value |
| **Inputs** | `--issue <id>` (required — this step never creates an issue). Files: the config sidecar, `originalcontent_TEMPLATE.txt` |
| **Outputs (stdout)** | `preserved=true` (comment posted) or `preserved=skipped` (already repo-managed) |
| **Exit codes** | `0` preserved or sanctioned skip; `1` the as-filed read was rejected or unparseable, the comment POST was rejected, or the render failed; `2` usage / missing template; `3` transport; `4` config HALT. **Every non-zero halts the sequence before the projection write** — the next step overwrites the description, so a swallowed failure here is data loss, not a degraded run |
| **Re-run (idempotency)** | Guarded by the sentinel the NEXT step writes: the comment is posted only on the first sync of an un-managed issue, and every later run reads the repo-managed description and skips |

### yt-write-issue.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 4, blocking — create or update the issue and verify what landed |
| **What it does** | Projects the summary (the ticket's `title` **verbatim**, with no id prefix), the rendered description from the supplied temp file, and the mapped custom fields, through ONE atomic `customFields` write — one bad member rejects the whole body, so there is no partial write to compensate for. It applies the pre-flight refusal and then the read-back (§4a). The description temp file is consumed and **unlinked on every exit path** |
| **Inputs** | `--ticket <id>` (required), `--description-file <path>`, and exactly one of `--project <id>` (create) or `--issue <id>` (update). Files: `metadata.yaml` (read-only), the config sidecar |
| **Outputs (stdout)** | `issue_id=<2-NNNN>`, `issue_readable=<KEY-N>`, `youtrack_url=<base>/issue/<KEY-N>`, `write_result=created\|updated`, `fields_verified=<n>` |
| **Exit codes** | `0` written and verified; `1` the write was rejected, the body could not be built, or a read-back showed an intended field absent (`syncyt.write.field_not_applied`); `2` usage; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | Set-to-desired: every field is set to the repo's current projection, so an unchanged repo yields the same issue and creates nothing on the update path |

### yt-transition.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 5, blocking — project the repo `status` onto the issue's state field |
| **What it does** | Writes the state as an ordinary single-value custom field. There is **no transition graph and no intermediate hop**: any declared value is set directly, so the sibling's `global_transitions` (the transition ids a hop is authorised by) has no analog. **The per-Type map DOES have one**: the value is resolved by the `(Type, status)` pair, so `status_state_map` is TWO levels exactly like `status_workflow_map`, and a new repo status is added under **every Type** -- a key added at the top level is never consulted and every ticket at that status halts (BTG-176 DEC-077). A value the bundle does not carry is HTTP 400, and the rejection is attributed from the step's own intent |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), the config sidecar (`status_state_map`) |
| **Outputs (stdout)** | `state_result=applied`, `fields_verified=<n>` |
| **Exit codes** | `0` applied and verified; `1` rejected, unbuildable, or the read-back showed the value absent; `2` usage; `3` transport; `4` config HALT — an unmapped `type`, or a `(Type, status)` pair `status_state_map` does not carry. The pair is reported with BOTH keys and **nothing is guessed**: no flat fallback, no default Type, no default State. Louder than the sibling, which reports `syncjs.transition.unmapped` and skips at exit `0` because Jira's workflow may legitimately not define a state; there is no workflow here to decline, so an unmapped pair is a projection this adapter cannot make (DEC-077) |
| **Re-run (idempotency)** | Set-to-desired; re-running with the same repo status is a no-op on the instance |

### yt-worklog.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 6, best-effort — post each NEW `stage_effort` entry as its own work item |
| **What it does** | Selects candidates from the repo-owned `worklog_watermark_at` **alone** (an entry is already-synced iff `entry.at <= worklog_watermark_at`; tracker state is never an input, so an operator who edits or deletes a work item is never overridden by a backfill), runs the SUPPRESS-ONLY marker scan under an explicit page bound, reads the pre-add baseline, posts one work item per entry carrying the `(stage, at)` marker, and verifies absorption from a fresh re-read. A posted work item is **never updated and never deleted**, and tracker totals are never reconciled against `actual_effort` |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), the config sidecar (`worklog_creation_enabled`, `worklog_postcheck_capability`, `duration_units`, `work_item_type`, `page_top_bound`) |
| **Outputs (stdout)** | `worklog_posted=<n>`, `worklog_suppressed=<n>`, `worklog_result=posted\|seeded\|skipped-epic\|disabled\|none\|halted-malformed\|posted-then-halted-malformed\|rejected\|postcheck-failed\|postcheck-indeterminate` (BTG-320: `rejected` covers the marker scan, the scratch file (any leg), the work-item body (any leg) or the POST failing -- stderr names which; the split-only `halted-body-unbuildable` and `halted-scratch-unavailable` are retired, converged onto this same `rejected`, PROD_CLAIRE-054), `postcheck=passed\|failed\|indeterminate\|unsupported` (only when a post happened), `worklog_watermark_advance=<iso8601>` (only when the watermark legitimately advances), and `agent_legs_rejected=<n>` (BTG-315) **only** in split mode |
| **Exit codes** | `0` every verdict above, including a scoped batch halt (BTG-320, OQ-2 resolved (a): a rejection HALTS the batch via `yt_worklog_finish`, which always exits 0 -- verified by reading the code, not a behavior change); `1` `worklog_watermark_at` is not ISO-8601 (`syncyt.worklog.watermark_malformed`); `2` usage; `3` transport; `4` config HALT (the capability marker absent or unrecognized — never a silent `none`; BTG-315 also reaches `4` for `syncyt.worklog.split_unavailable`, unreachable in unsplit mode) |
| **Re-run (idempotency)** | Decided only from the watermark, which the orchestrator advances solely on a full-sequence success — so a halt leaves it unadvanced and the next run re-derives the identical batch. The suppress-only scan closes the crash window where a post landed but the watermark write did not |

**BTG-315 (additive):** when the ticket's §9 row names an agent-time user (`$AGENT_USER` non-empty,
resolved once here before candidate selection), each candidate is instead handled entirely by
`yt-worklog-agent.sh`'s `yt_worklog_process_split_candidate` — see
`.claude/skills/claire-sync-youtrack/youtrack-scripts-libs.md`. The operator leg reuses the UNTOUCHED
`yt_worklog_post_one` / `yt_worklog_verify_one` (a parallel caller, not a refactor -- and, per review
cycle-2 B3, `yt_worklog_verify_one` is reused for the AGENT leg's own absorption check too, since it
was already leg-agnostic); the agent leg posts to the SAME work-item endpoint with an `author` field
(native attribution, unlike the Jira adapter's third-party plugin) and is confirmed by a fresh re-read
of the created item, never the create response. Unsplit mode is byte-identical.

**Split-mode conditions (review cycle-2 B7):** seven `syncyt.worklog.*` conditions join the family
above, each firing at most once per candidate per condition:

- **`syncyt.worklog.split_resolved`** (Info) — the split computation resolved operator/agent minutes.
  Emitted **before either leg is posted** (record-before-contact, OS-1.4), naming only the resolved
  durations and the configured identity — never the factor (R6).
- **`syncyt.worklog.split_unavailable`** (Critical, HALT exit 4) — an agent-time user is configured but
  `worklog-split.sh` is missing or exited non-zero. Nothing is posted for the candidate.
- **`syncyt.worklog.leg_zero_skipped`** (Info) — one leg computed to `0m`; that leg issues no request.
- **`syncyt.worklog.agent_leg_posted`** (Info) — the agent leg posted and the confirming re-read names
  the configured identity as `author.login`.
- **`syncyt.worklog.agent_leg_rejected`** (Warning, non-halting) — the tracker answered a non-2xx.
  The operator's own leg is never withheld; the agent share is **forfeited**, never retried, and the
  watermark still advances past the candidate.
- **`syncyt.worklog.agent_leg_misattributed`** (Critical, non-halting) — the agent leg posted (2xx),
  but the re-read's `author.login` does not match the configured identity case-insensitively. Never
  re-posted (work items are immutable, BTG-064); the watermark still advances.
- **`syncyt.worklog.agent_leg_unconfirmed`** (Critical, HALT via `yt_worklog_finish`) — the agent leg
  posted, but the confirming re-read was unreachable, rejected, or unparseable. The watermark is
  **not** advanced for this candidate.

A local staging failure (`syncyt.worklog.scratch_unavailable` / `body_unbuildable`) on EITHER leg halts
via `yt_worklog_finish` exactly as the unsplit path's own scratch failure does (review cycle-2 B2),
and is never counted in `agent_legs_rejected` -- that counter is reserved for genuine tracker
rejections. `agent_legs_rejected` (stdout, split mode only, absent -- never `0` -- when unconfigured)
is surfaced per ticket at end-of-sync by
`.claude/skills/claire-sync-youtrack/youtrack-orchestration-sequence.md`'s `bulk_sync_tickets`.

### yt-assign.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 7, best-effort — reconcile the assignee to the repo `status`, after the state write so a workflow reacting to the state cannot overwrite it |
| **What it does** | Writes `Assignee` as an ordinary user-typed custom field (`value.login`, or a jq `null` to clear). The failure it guards is **MEMBERSHIP, not lookup**: a user who exists in the directory but is not in the project's Assignee bundle is refused HTTP 400 `Value is not allowed`, a body naming neither the field nor the value — so `syncyt.assignee.unresolved` names both from the step's OWN intent. Nothing is compensated after a refusal: a clearing write would turn a refused assignment into an unassignment nobody asked for |
| **Inputs** | `--ticket <id>`, `--issue <id>`, `--self <login>` (the identity step 1 resolved from the credential — without it every status the config maps to `self` is refused). Files: `metadata.yaml` (read-only), the config sidecar (`assignment_reconciliation_enabled`, `assignment_map`) |
| **Outputs (stdout)** | `assign_result=applied\|no-change\|unknown-status\|skipped-epic\|disabled\|rejected` |
| **Exit codes** | `0` always — every refusal is a sanctioned one and is carried on stdout — EXCEPT `2` usage and `4` config HALT, which are breakage rather than refusal and are never swallowed |
| **Re-run (idempotency)** | Set-to-desired: the same repo status writes the same assignee, and the read-back confirms it landed rather than inferring it from the write's own 200 |

### yt-link.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 8, best-effort — project `related_tickets` and the ordering keys as issue links |
| **What it does** | ADDITIVE-ONLY over issues that already exist: a target that does not resolve is skipped with an audit line and never fabricated, and no existing link is ever removed. Each link is created at the configured type and direction, and the direction is **read back and compared** — on this instance the slot id IS the direction, and every slot the project defines comes back including the empty ones, so the assertion is the target's presence in the slot the mapping intends. A config whose labels no longer match the instance's own is reported as drift |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), the config sidecar (`link_creation_enabled`, `link_relations`) |
| **Outputs (stdout)** | `links_created=<n>`, `links_skipped=<n>`, `link_result=applied\|skipped\|rejected` |
| **Exit codes** | `0` always, except `2` usage, `3` transport and `4` config HALT (an unmapped relation — never a silent fallback to the undirected default, which would project a directed relation as an undirected one and report success) |
| **Re-run (idempotency)** | Link creation was OBSERVED to be idempotent: re-POSTing an identical link answers 200 and the read-back still shows one target |

### yt-epic.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 9, best-effort, last — project the ticket's `decomposed_from` parent as ONE type-agnostic link |
| **What it does** | Resolves the parent through the parent's OWN recorded `youtrack_url` (the only ticket-to-issue mapping this adapter has), confirms the issue still exists, creates one `Subtask` link with the parent as its SOURCE, and reads the direction back. **No re-type, no Move, no flatten, no replacement issue** — see the divergence below. A parent with no metadata, no recorded url or a 404 is SKIPPED with an audit line, never fabricated |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: this ticket's and its parent's `metadata.yaml` (read-only), the config sidecar (`link_relations.decomposed_from`) |
| **Outputs (stdout)** | `epic_result=applied\|skipped\|rejected\|none` (`none` = the ticket declares no parent) |
| **Exit codes** | `0`, except `2` usage, `4` config HALT, and `1` when the parent's owned data cannot be read at all — the last is deliberate and is NOT a sanctioned refusal: unreadable owned data is broken, not absent |
| **Re-run (idempotency)** | The link create is idempotent on this instance, and a re-run re-reads the same parent; a parent projected between two runs simply links on the later one |

### yt-reserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — reserve an id from the instance when the id-allocation binding is reserve-from-tracker |
| **What it does** | Resolves the project, stages the create body, **declares the pairing obligation BEFORE contacting the tracker** (record-before-contact) and then creates the issue. The id the instance assigns is authoritative; a computed or guessed one is never used, so a failed reservation STOPS. **No placeholder type is invented** — see the divergence below |
| **Inputs** | `--summary <text>` (required), `--type <repo-type>` (optional). Environment: base URL, token, project key |
| **Outputs (stdout)** | `issue_id=<2-NNNN>`, `issue_readable=<KEY-N>`, `youtrack_url=<base>/issue/<KEY-N>` |
| **Exit codes** | `0` reserved; `1` the create was rejected, the response carried no readable id, or the project read was REFUSED with 401/403 (`syncyt.config.project_read_refused` — a credential refusal reported apart from a bad project key; see `yt-resolve.sh`); `2` usage / unset environment; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | **NOT idempotent, by design** — a reservation is an allocation, and running it twice reserves two ids. It is called once per governed allocation, and the obligation it declares is what pairs the id with its artifacts |

### yt-import.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — seed-read an existing issue for a ticket a business user filed in the tracker |
| **What it does** | Reads the seed fields into ONE temp directory the caller then owns, computes a reverse `type:` HINT from the config's own map **only where the inverse is unique** (an ambiguous preimage yields no hint rather than a best guess), and downloads attachments within the configured ceiling under `{attachmentId}-{sanitizedFilename}` — this instance permits two attachments with the same filename on one issue, so a bare basename would silently overwrite one. A short transfer is removed and referenced instead. **No dedicated acceptance-criteria field is read** — see the divergence below. A FAILED import unlinks its own seed directory |
| **Inputs** | `--issue <KEY-N>` (required), `--ticket <id>` (optional — it names the attachment directory; without it nothing is downloaded, because nowhere has been claimed to put it). Files: the config sidecar (`attachment_size_ceiling_mib`, `issue_type_map`) |
| **Outputs (stdout)** | `issue_readable=`, `issue_id=`, `seed_dir=`, `summary_file=`, `description_file=`, `manifest_file=`, `attachments_downloaded=<n>`, `attachments_referenced=<n>`, `type_hint=<repo-type>` |
| **Exit codes** | `0` seeded; `1` the issue read was rejected or unparseable; `2` usage; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | A read; a re-run re-seeds into a NEW temp directory and re-downloads under the same collision-free names, overwriting its own previous bytes and nothing else |

### yt-sprint-check.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — the sprint-membership verdict `/claire-implement`'s sprint guard consumes. READ-ONLY |
| **What it does** | Resolves the id VERBATIM (the recorded `youtrack_url` when there is one, else the ticket id — never a summary search, because a fuzzy match is unsafe for a gate decision), runs the ONE configured query, and returns exactly ONE verdict through a single emitter. A **400 is `inconclusive`, never `not-in-sprint`**: on this instance a query naming an unknown id answers 400 while a nonsense field name answers 200 with `[]`, and reporting the former as `not-in-sprint` would BLOCK on a ticket the tracker simply does not have |
| **Inputs** | `--ticket <id>` (required). Files: `metadata.yaml` (read-only, when present), the config sidecar (`sprint_query`) |
| **Outputs (stdout)** | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive`, `issue_readable=<KEY-N>` |
| **Exit codes** | `0` — a verdict is a RESULT, not a failure, and the guard decides what to do with it. `2` usage, `4` config HALT. Deliberately **not** `3`: an unreachable instance is a known-unknown sprint state, which is exactly `inconclusive`, and halting would deny the guard the fallback it has for this case |
| **Re-run (idempotency)** | Read-only; it writes nothing anywhere |

### Shared libraries (BTG-247)

`yt-lib.sh`, `yt-rest.sh`, `yt-meta.sh`, `yt-worklog-lib.sh` and `yt-link-targets.sh` — relocated, not removed — are in `.claude/skills/claire-sync-youtrack/youtrack-scripts-libs.md` (BTG-247); `yt-projectkey-lib.sh` is in `.claude/skills/claire-sync-youtrack/youtrack-scripts-projectkey.md` (BTG-179) -- each a further part of this one index, the same facet-conflict resolution BTG-102, BTG-105, BTG-168, BTG-173 and BTG-247's own sibling adapter already applied, split, never truncated.

---

## 7. Documented divergences

AC-6's rule is that a `/claire-sync-jira` capability with a YouTrack equivalent is present with the same
observable semantics, and one **without** an equivalent is absent **and documented** — never forced. Each
divergence below is a data-model fact about this instance, observed rather than assumed.

| # | The sibling has | This adapter | Why (the YouTrack data-model reason) |
|---|---|---|---|
| 1 | An umbrella replacement flow: create a replacement issue at another type, move the children's ordered links onto it, close the superseded original | **No umbrella, no hierarchy flatten, no re-type, no Move.** `yt-epic.sh` creates ONE link and nothing else | Jira forbids an Epic to hold an Epic Link, which is what forces the replacement. This instance's `Subtask` link type carries NO per-Type restriction, so any issue may parent any issue — including an epic parenting an epic. The equivalent is one link, and E-3 asserts it by enumerating the entire call log |
| 2 | A dedicated acceptance-criteria field, discovered by exact name, written outbound and read on import | **No dedicated acceptance-criteria field**, in either direction. Criteria project into the description only, and `yt-import.sh` never reads one back | This project has no such field, and writing an unknown custom-field name answers **HTTP 500** `incompatible-issue-custom-field-name-…`. There is nothing to discover and nothing to write |
| 3 | Wiki markup in the description templates, restored deliberately because REST v2 renders wiki | **Markdown**, and no conversion anywhere on the path | YouTrack renders issue descriptions and comments as Markdown natively. Forcing a wiki restoration here would corrupt every projected description — the sibling's own defect, in reverse |
| 4 | A per-issue-type workflow transition graph, walked hop by hop through intermediate states, plus `global_transitions` for the hops that need one | **A per-Type `status_state_map`** (Type -> repo status -> State), written as an ordinary field in ONE request | The divergence is the transition graph, and only the graph. State here is a plain `StateProjectCustomField`: any declared value is set directly, so there is no path to walk, no intermediate hop to authorise and no analog for `global_transitions`. **The per-type map itself is NOT a divergence and this row previously claimed it was** — it read "no per-type variation to map", which was disproved live (BTG-176 DEC-077): `Type` and `State` are independent custom fields and this instance accepts any of the bundle's 16 values under any Type. One project-wide bundle means the Types share a VALUE SET, not a POLICY, and the sibling's map encodes policy. The map is two-level as of that correction |
| 5 | `sprint in openSprints()` as a fixed JQL clause | **A configured `sprint_query`**, with an inconclusive default | This instance has no `openSprints()` function; sprint membership is a board concept, and a naive sprint query in a board-less project matches EVERY issue because the empty-field text is itself a queryable value |
| 6 | A placeholder issue type on `reserve`, declared because Jira requires one on create | **No placeholder type.** An untyped ticket is reserved untyped | A create carrying only the project and the summary answers 200 here. Inventing a type would assert a classification the repo has not made, and `/claire-triage` would have to undo it |
| 7 | An attachment manifest recording each attachment's content URL | **A disposition, never a location** | The attachment url is a signed credential on this instance (§2). Recording it would put a credential in a repo artifact |
| 8 | A `precedes` link type | **`precedes` mapped onto `Depend`**, recorded in the config as a MAPPING DECISION, not an identity | There is no `Precedes` type here. `Depend` is the only directed near-fit, and direction is the property the repo's ordering relation exists to carry — but a reader of the instance sees `is required for` / `depends on` where the repo means `precedes`. The direction is asserted by a test, never assumed |

---

## 8. Retained invariants that no longer have a branch to fire on

Two rules from the MCP-era prose survive the reversal as *invariants* rather than as code paths. They are
recorded here because a rule whose enforcement moved is indistinguishable, to a later reader, from a rule
that was dropped.

| Invariant | Where it lives now | Why it has no branch |
|---|---|---|
| **Writing the estimate field never resets spent time** (the PROD_CLAIRE-006 transplant) | Nowhere in code, deliberately — and the reason is in the config's `custom_field_map` comment | The two fields are live-confirmed **write-decoupled** on this instance: spent time is read-only/computed and accrues only from work items, and a direct write to it is rejected `400 "automatically calculated"`. This adapter also does not project the estimate at all — the repo's `estimated_effort` values are free-form human durations with no unambiguous period analog, so `custom_field_map` ships EMPTY rather than mapping a guess. There is no write, so there is nothing to guard; an adopter who maps the field gets the same read-back every other mapped field gets |
| **A posted work item is never updated and never deleted** | Enforced structurally, not by a runtime branch | There is no work-item update path and no work-item delete path anywhere in the tree, and none may be added. Immutability is a POLICY here, not an API limitation — the instance permits both verbs — so it is enforced by `worklog-immutability-parity-gate.sh`, which fails the build if either adapter's code lines carry an explicit mutating HTTP method against a work item, rather than by a check the code performs on itself. That gate's YouTrack arm is the enforcement site for this whole row |

Three MCP-era **conditions** are retired rather than re-homed, each because it named a branch that no
longer exists: the acceptance-criteria audit line (there is no field to write, so the description-only
"branch" is the only path and a condition that fires on every run names no run); the description
re-projection line (the update path always sends the rendered description, same reasoning); and the
non-admin qualifier on an absent schema value (a 400 does not tell the adapter whether an admin could have
created the value, so the condition asserts only what it can see: the value is absent).
