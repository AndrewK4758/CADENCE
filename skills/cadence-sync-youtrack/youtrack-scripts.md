# `/cadence-sync-youtrack` — script contracts

Bounded context: Tracker projection / YouTrack Server adapter.
External invariant relied upon: the git repository (`metadata.yaml` + `problem.md`) is the sole source of truth; YouTrack is the downstream projection surface. This document serves as the **canonical interface index** for the skill: `.agents/skills/cadence-sync-youtrack/SKILL.md` is a lightweight **orchestrator** sequencing the standalone single-operation shell scripts contracted below, where each script performs one cohesive YouTrack REST operation (ADR_CADENCE-0025; `archive/BTG-176/spec.md` AC-2).

Its companion index segments are `.agents/skills/cadence-sync-youtrack/youtrack-scripts-projectkey.md` (BTG-179 DEC-019) and `.agents/skills/cadence-sync-youtrack/youtrack-scripts-libs.md` (BTG-247) — split for `<400`-line readability, never truncated.
When modifying a single operation, read this file plus the one script being changed — never every script in the directory. Specifically, an agent updating one operation reads at most 5 files: (1) this index, (2) `.agents/skills/cadence-sync-youtrack/yt-lib.sh`, (3) the target operation script, (4) `.agents/skills/cadence-sync-youtrack/youtrack-server-config.json`, and (5) `SKILL.md`.

**Every REST request and response shape contracted below was live-verified** against YouTrack Server `v2026.1.13162` and recorded in `archive/BTG-176/spec-2-live-rest-observations.md`. Zero shapes are guessed or extrapolated from Jira.

---

## 1. The three-channel return contract

Every script communicates strictly across three channels. The orchestrator never parses free-form prose.

| Channel | Carries | Consumed by |
|---|---|---|
| **stdout** | Machine-readable `key=value` pairs **exclusively**, drawn from that script's contracted output keys (`issue_id=2-13461`, `youtrack_url=…`, `worklog_watermark_advance=<iso8601>`, `assign_result=applied`). Zero prose. Scripts with no output keys emit nothing on stdout. | The orchestrator, which accumulates stdout lines across steps and computes the single end-of-operation `metadata.yaml` write-back |
| **stderr** | Structured `syncyt.*` audit condition lines and diagnostic messages. Never parsed for orchestrator control flow (when verbose non-zero stderr output exceeds 30 lines, the orchestrator routes it through `offload_log_triage` on `:11434` while saving raw output to `/tmp/agy-last-triage.log`). | The human operator and session transcript |
| **exit code** | Numeric status code (table below). | The orchestrator's halt gate (`yt_run_step`) |

### Exit codes

| Code | Meaning | Orchestrator behavior |
|---|---|---|
| `0` | Operation succeeded, or a best-effort step recorded a sanctioned refusal via a `*_result=` stdout key | Continue sequence |
| `1` | Fail-loud operational rejection; the specific `syncyt.*` condition has been emitted on stderr | **Halt** this ticket |
| `2` | CLI usage or setup error (missing required flag, unset required environment variable) | **Halt** this ticket |
| `3` | Network transport unreachable (`syncyt.transport.rest_unreachable`) — kept distinct from issue-lookup failures | **Halt** this ticket |
| `4` | Configuration sidecar missing or malformed — a fail-loud config key could not be resolved | **Halt** this ticket |

**`yt_run_step` decides whether to halt from the exit code ALONE.** A step's *class* (`blocking` vs. `best-effort`) governs only whether a script may report a tracker-level refusal as a completed exit `0` run: a best-effort step unable to apply its update exits **0** with `<step>_result=rejected` on stdout so the ticket continues. Any non-zero exit code from any script halts the ticket immediately regardless of class — because a best-effort script exiting non-zero has *faulted*, not refused, and faults are never ignored.

Upon a halt, the orchestrator never rolls back, compensates, or auto-resumes; it emits a partial-completion report (`yt_emit_partial_report`) and leaves already-applied YouTrack changes intact. Recovery is an operator re-run, which is safe because every script is idempotent (§5).

---

## 2. Invocation conventions

- **CLI arguments** use explicit long flags (`--ticket BTG-176`, `--issue 2-13461`, `--description-file <path>`). Omitting a required flag triggers an immediate usage halt (exit `2`), never a guessed default.
- **Readable vs. internal issue IDs are not interchangeable.** While both the *readable* key (`<KEY>-<n>`) and the *internal* database ID (`2-13461`) work in URL paths, YouTrack's link creation payload requires the **internal** ID in its `id` field — passing a readable key inside a link body fails with HTTP 400 quoting only the alphabetic prefix. Consequently, every step after Step 4 addresses the issue using the internal `issue_id` emitted by `yt-write-issue.sh`.
- **Environment variables** provide transport and credentials: `YOUTRACK_BASE_URL`, `YOUTRACK_TOKEN`, and optional `YOUTRACK_SELF`. While the variable *names* are configurable via the `env` block of `youtrack-server-config.json`, their secret *values* are never written to disk.
- **Project key resolution.** `YOUTRACK_PROJECT_KEY` is **DEPRECATED as a project-key source** (BTG-179) and sunsets after ONE release cycle (`docs/migrations/multi-tracker-binding.md`). Resolution follows a strict 3-level hierarchy: (1) the ticket prefix's `CADENCE_ORG.md` §9 table row -> (2) §9's scalar `**Project key(s):**` line -> (3) the deprecated environment variable (which emits `syncyt.config.project_key_from_env` when used).
- **Repository root** defaults to `$CADENCE_REPO_ROOT` when set, else the current working directory (`.`). Ticket metadata resolves from `specs/<id>/metadata.yaml` first, then `archive/<id>/metadata.yaml`.
- **Config sidecar path** defaults to `$YOUTRACK_SERVER_CONFIG`, or `youtrack-server-config.json` in the script's directory.
- **Shared library:** `.agents/skills/cadence-sync-youtrack/yt-lib.sh` is sourced by every operation script, centralizing config resolution, fail-loud/default polarities, REST helpers, `metadata.yaml` parsing, stdout `key=value` emission, and `syncyt.*` stderr reporting.

### Credential handling (Engineering Pillar: Security Posture)

`YOUTRACK_TOKEN` is read from the environment at call time and piped to `curl` via a `-K-` stdin configuration block. It is **never** passed on the command line (where `ps` could expose it) and never written to temporary files, logs, artifacts, or `metadata.yaml`. The operator self-identity cache stores only a one-way cryptographic hash of the credential and resides **outside** the git repository tree.

**Every YouTrack attachment `url` is also treated as a live credential.** On YouTrack Server, attachment URLs carry a pre-signed `sign=` query parameter that serves the attachment bytes **without** requiring an `Authorization` header. Therefore, signed attachment URLs must never appear in stderr diagnostics, logs, or repository artifacts: diagnostics log only the attachment **id** and HTTP status code, and `yt-import.sh`'s manifest records a disposition (`downloaded` / `referenced`) rather than the URL. Emitting a signed URL anywhere triggers `syncyt.attachment.signed_url_disclosed`.

---

## 3. Owned-data discipline

Operation scripts **read** `metadata.yaml` and **never write** to `metadata.yaml` or any other repository-owned artifact. Instead, each script emits its state delta on stdout, and the **orchestrator alone** writes `metadata.yaml` once at the very end of a successful ticket sequence (`yt_apply_metadata_writes`). Any mid-sequence halt leaves `metadata.yaml` completely untouched.

If `metadata.yaml` is empty, malformed, or fails subset parsing, `yt_metadata_load` halts loud (exit `1`) rather than proceeding with an empty dictionary.

---

## 4. Configuration and its polarity

All repository-specific and instance-specific mappings reside in `.agents/skills/cadence-sync-youtrack/youtrack-server-config.json`. `yt-lib.sh` is the single resolver, enforcing each setting's missing/malformed polarity in one place:

| Key | Absent / malformed resolves to | Rationale |
|---|---|---|
| `youtrack-server-config.json` file | **HALT**, `syncyt.config.absent` (exit `4`) | Without instance mappings, no valid projection can occur — checking config before environment variables ensures config errors are never misdiagnosed as auth failures |
| `worklog_postcheck_capability` | **HALT**, `syncyt.worklog.capability_marker_absent` (exit `4`) — never silent `none` | Silently defaulting to `none` would disable post-add absorption verification without notice |
| `attachment_size_ceiling_mib` | **fail closed**: reference all attachments, download zero | Downloading unbounded binary files into git history is irreversible; failing closed is safe |
| `worklog_creation_enabled`, `link_creation_enabled` | **enabled** (opt-out toggles) | Effort logging and issue linking are core projection steps and safe by default |
| `assignment_reconciliation_enabled` | **disabled** (opt-in toggle) | Reassigning issues affects human workflow ownership and requires explicit opt-in |
| `sprint_query` | `inconclusive` verdict, `syncyt.sprintcheck.query_unconfigured` | YouTrack Server lacks a built-in `openSprints()` function; returning `inconclusive` lets `/cadence-implement`'s sprint guard apply its documented fallback rather than blocking all work |
| `issue_type_map`, `priority_map`, `status_state_map`, `assignment_map`, `link_relations`, `type_conditional_fields`, `custom_field_map` | **HALT** on unmapped lookup, `syncyt.config.marker_unresolved` | Guessing a Type, Priority, or State is both an ungoverned decision and an immediate HTTP 400 on YouTrack Server |
| `page_top_bound` | **HALT** | An unbounded work-item query cannot detect pagination truncation, which would disarm duplicate-worklog suppression |

Whenever an optional toggle is omitted from the config file, `yt-lib.sh` emits `syncyt.config.default_polarity_applied` on stderr so the audit trail distinguishes explicit configuration from default polarity.

`page_top_bound` applies specifically to the **work-item crash-recovery marker scan**; by contrast, link-direction read-backs (`yt-link.sh`, `yt-epic.sh`) and attachment listings (`yt-import.sh`) pass `$top=-1` by explicit design (DEC-048) so link verification and attachment manifests never suffer false truncation.

---

## 4a. HTTP 2xx IS NOT PROOF OF APPLICATION — the dual guards

Because YouTrack Server responds **HTTP 200** when a create/update request includes a custom field that the issue's Type does not support — **silently discarding the field value** — this adapter enforces two complementary guards:

- **Pre-flight refusal (`syncyt.write.preflight_refused`).** Before sending any HTTP request, `yt-write-issue.sh` consults `type_conditional_fields` in the config sidecar; if a non-empty field is disallowed for the resolved Type, it refuses pre-flight without issuing a network call.
- **Post-write read-back (`syncyt.write.field_applied` / `syncyt.write.field_not_applied`).** Immediately after every field write, the script fetches the issue back and verifies every intended `(field, value)` pair against **the script's own intended state**, halting if any value was silently dropped. Conditionally inapplicable fields legitimately omitted by pre-flight emit `syncyt.write.conditional_field_skipped`.

Each write script emits `fields_verified=<n>` on stdout recording the exact count of fields confirmed via read-back.

---

## 5. Idempotency — sequential re-run convergence

Because operator re-run is the standard recovery path after any halt, **every** script is designed to converge cleanly on sequential re-runs without duplicating side effects. Each script contract below states its **Re-run (idempotency)** guarantee. Note that **concurrent execution against the same ticket is a non-goal**; idempotency guarantees sequential re-runs.

---

## 6. Script contracts

Each `###` entry below specifies **Operation/step**, **What it does**, **Inputs**, **Outputs (stdout)**, **Exit codes**, and **Re-run (idempotency)**. `ci-templates/scripts/tests/btg-176-rest-foundation.test.sh` (scenario E-8) enforces a bidirectional 1:1 match between scripts in the directory and entries across `youtrack-scripts*.md` (`syncyt.contract.script_undocumented`).

### yt-connect.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 1, blocking — verify server reachability and resolve operator self identity |
| **What it does** | Confirms base URL and token environment variables are set, then resolves the operator's YouTrack login: if `YOUTRACK_SELF` is non-empty, it wins immediately (zero cache I/O, zero network calls); otherwise checks a credential-fingerprinted cache file **outside** the repository tree, and on a cache miss queries `GET /api/users/me` for `.login` (never falling back to `fullName` or `email`, which YouTrack rejects on `Assignee` writes with HTTP 400). Token rotation or URL changes automatically invalidate the fingerprint cache |
| **Inputs** | Environment: base URL and token (required), optional `YOUTRACK_SELF`, `XDG_CACHE_HOME` / `HOME`. Zero CLI flags |
| **Outputs (stdout)** | `self=<login>`, `self_source=env\|cache\|rest`, `self_id=<1-NNN>` on full resolution; `self_result=unresolved` if reachable but `.login` is absent |
| **Exit codes** | `0` connected; `2` required env var unset (no network call made); `3` `syncyt.transport.rest_unreachable`; `1` `syncyt.connect.auth_rejected` (server reached and rejected the token) |
| **Re-run (idempotency)** | Read-only check; cache updates overwrite in place and failed checks write nothing |

### yt-resolve.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 2, blocking — resolve internal project ID and determine `create` vs. `update` mode |
| **What it does** | Queries `GET /api/admin/projects?query=` and matches `shortName` **exactly** (preventing substring matches against other projects), refuses archived projects, and determines `create` vs. `update` strictly from whether `youtrack_url` is present in `metadata.yaml` (performing no fuzzy summary search) |
| **Inputs** | `--ticket <id>` (required). Environment: base URL, token, optional fallback project key. Files: `metadata.yaml` (read-only), `CADENCE_ORG.md`, config sidecar |
| **Outputs (stdout)** | `project_key=<KEY>`, `project_id=<0-NNN>`, `mode=create\|update`, plus `issue=<id>` when `mode=update` |
| **Exit codes** | `0` resolved; `1` `syncyt.config.project_unresolved` (including HTTP 200 with `[]`) or `syncyt.config.project_read_refused` on HTTP 401/403 from `/api/admin/projects` (BTG-176 DEC-076); `2` usage / missing key; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | Pure read. Once `youtrack_url` is written to `metadata.yaml`, every subsequent run resolves `mode=update`; halting after Step 4 creates an issue but before `yt_apply_metadata_writes` records `youtrack_url` is the sole non-convergent window |

### yt-preserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 3, blocking, **update path only** — preserve the pre-sync original issue content as a comment before Step 4 overwrites the description |
| **What it does** | Fetches the issue's current summary, description, and mapped custom fields; if the description does not yet start with the `Repo-managed` sentinel, populates `.agents/skills/cadence-sync-youtrack/originalcontent_TEMPLATE.txt` deterministically in script and posts it as an issue comment. Original values are copied **verbatim** in Markdown |
| **Inputs** | `--issue <id>` (required). Files: config sidecar, `originalcontent_TEMPLATE.txt` |
| **Outputs (stdout)** | `preserved=true` (comment created) or `preserved=skipped` (sentinel already present) |
| **Exit codes** | `0` preserved or skipped; `1` read/render/comment-post failure; `2` usage / missing template; `3` transport; `4` config HALT. **Any non-zero exit halts the ticket prior to Step 4's overwrite** |
| **Re-run (idempotency)** | Once Step 4 writes the `Repo-managed` sentinel into the description, all future runs detect the sentinel and emit `preserved=skipped` |

### yt-write-issue.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 4, blocking — create or update the YouTrack issue and verify all fields via read-back |
| **What it does** | Writes the issue `summary` (ticket `title` verbatim without ID prefix), `description` (from `--description-file`), and mapped `customFields` in a single atomic POST, enforcing both pre-flight conditional-field validation and post-write read-back verification (§4a). Always **unlinks `--description-file` on every exit path** |
| **Inputs** | `--ticket <id>` (required), `--description-file <path>`, and either `--project <id>` (`create`) or `--issue <id>` (`update`). Files: `metadata.yaml` (read-only), config sidecar |
| **Outputs (stdout)** | `issue_id=<2-NNNN>`, `issue_readable=<KEY-N>`, `youtrack_url=<base>/issue/<KEY-N>`, `write_result=created\|updated`, `fields_verified=<n>` |
| **Exit codes** | `0` written and read-back verified; `1` request rejected, payload unbuildable, or read-back mismatch (`syncyt.write.field_not_applied`); `2` usage; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | Idempotent set-to-desired state on the update path |

### yt-transition.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 5, blocking — project the ticket's repository `status` onto YouTrack's `State` field |
| **What it does** | Sets `State` directly as a single-value custom field without walking intermediate workflow transitions. Resolves the target state via the two-level `status_state_map` keyed by `(Type, status)` (BTG-176 DEC-077), then verifies the state via read-back |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), config sidecar (`status_state_map`) |
| **Outputs (stdout)** | `state_result=applied`, `fields_verified=<n>` |
| **Exit codes** | `0` applied and verified; `1` rejected or read-back mismatch; `2` usage; `3` transport; `4` config HALT on an unmapped `type` or `(Type, status)` pair (naming both keys without guessing) |
| **Re-run (idempotency)** | Set-to-desired state; re-running with unchanged status is a no-op |

### yt-worklog.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 6, best-effort — project each new `stage_effort` entry as an immutable YouTrack work item |
| **What it does** | Filters `stage_effort` entries strictly by `entry.at > worklog_watermark_at`, runs the bounded suppress-only marker scan, captures the pre-post spent-time baseline, posts one work item per new entry tagged with `(stage, at)`, and verifies absorption via a fresh re-read. Posted work items are **never updated or deleted** |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), config sidecar (`worklog_creation_enabled`, `worklog_postcheck_capability`, `duration_units`, `work_item_type`, `page_top_bound`) |
| **Outputs (stdout)** | `worklog_posted=<n>`, `worklog_suppressed=<n>`, `worklog_result=posted\|seeded\|skipped-epic\|disabled\|none\|halted-malformed\|posted-then-halted-malformed\|rejected\|postcheck-failed\|postcheck-indeterminate` (BTG-320: `rejected` unifies marker-scan, scratch-file, body-build, and POST rejections, PROD_CADENCE-054), `postcheck=passed\|failed\|indeterminate\|unsupported` (when posted), `worklog_watermark_advance=<iso8601>`, and `agent_legs_rejected=<n>` (BTG-315, split mode only) |
| **Exit codes** | `0` for all verdicts above (including batch-scoped halts via `yt_worklog_finish`); `1` malformed `worklog_watermark_at` (`syncyt.worklog.watermark_malformed`); `2` usage; `3` transport; `4` config HALT (`capability_marker_absent` or `syncyt.worklog.split_unavailable`) |
| **Re-run (idempotency)** | Watermark advances only at end-of-sequence; the suppress-only marker scan prevents duplicate posts if a prior run halted after posting work items |

**BTG-315 (additive):** when the ticket prefix's `CADENCE_ORG.md` §9 row configures an `Agent-time user` (`$AGENT_USER` non-empty), candidate processing delegates to `yt-worklog-agent.sh`'s `yt_worklog_process_split_candidate` (see `.agents/skills/cadence-sync-youtrack/youtrack-scripts-libs.md`). The operator leg reuses `yt_worklog_post_one` / `yt_worklog_verify_one`, while the agent leg posts to the same endpoint with `author: {login:}` and confirms attribution via a fresh re-read. Unsplit mode is byte-identical.

**Split-mode conditions (review cycle-2 B7):** seven `syncyt.worklog.*` conditions cover split mode:

- **`syncyt.worklog.split_resolved`** (Info) — emitted **before either leg is posted** (OS-1.4), logging resolved operator/agent minutes and agent login (never the raw factor, R6).
- **`syncyt.worklog.split_unavailable`** (Critical, HALT exit 4) — `$AGENT_USER` is set but `worklog-split.sh` is missing or failed.
- **`syncyt.worklog.leg_zero_skipped`** (Info) — a leg rounded to `0m` and issued no HTTP request.
- **`syncyt.worklog.agent_leg_posted`** (Info) — agent leg posted and re-read confirmed `author.login`.
- **`syncyt.worklog.agent_leg_rejected`** (Warning, non-halting) — tracker returned non-2xx on the agent leg; operator leg stands, agent share is forfeited without retry, and watermark advances.
- **`syncyt.worklog.agent_leg_misattributed`** (Critical, non-halting) — agent leg returned 2xx but re-read `author.login` differed from `$AGENT_USER`; never re-posted (immutability, BTG-064) and watermark advances.
- **`syncyt.worklog.agent_leg_unconfirmed`** (Critical, HALT via `yt_worklog_finish`) — agent leg posted but confirming re-read failed; watermark does **not** advance.

Local staging faults (`syncyt.worklog.scratch_unavailable` / `body_unbuildable`) on either leg halt via `yt_worklog_finish` without incrementing `agent_legs_rejected` (which counts only genuine tracker rejections and is surfaced at batch end by `bulk_sync_tickets` in `youtrack-orchestration-sequence.md`).

### yt-assign.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 7, best-effort — reconcile `Assignee` to repository `status` after Step 5's state update |
| **What it does** | Updates `Assignee` (`value.login`, or `null` to unassign) and verifies via read-back. If the user is not in the project's Assignee bundle (HTTP 400 `Value is not allowed`), emits `syncyt.assignee.unresolved` naming both field and login without issuing a compensating clear |
| **Inputs** | `--ticket <id>`, `--issue <id>`, `--self <login>`. Files: `metadata.yaml` (read-only), config sidecar (`assignment_reconciliation_enabled`, `assignment_map`) |
| **Outputs (stdout)** | `assign_result=applied\|no-change\|unknown-status\|skipped-epic\|disabled\|rejected` |
| **Exit codes** | `0` on all applied/skipped/rejected outcomes; `2` usage; `4` config HALT |
| **Re-run (idempotency)** | Set-to-desired with read-back confirmation |

### yt-link.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 8, best-effort — project `related_tickets` and ordering keys as directed YouTrack issue links |
| **What it does** | Strictly additive over existing issues: unresolved targets are skipped with an audit notice, existing links are never deleted, and each created link's slot direction is verified via read-back |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: `metadata.yaml` (read-only), config sidecar (`link_creation_enabled`, `link_relations`) |
| **Outputs (stdout)** | `links_created=<n>`, `links_skipped=<n>`, `link_result=applied\|skipped\|rejected` |
| **Exit codes** | `0` on applied/skipped/rejected; `2` usage; `3` transport; `4` config HALT on an unmapped relation |
| **Re-run (idempotency)** | Link creation is idempotent on YouTrack Server (re-POSTing returns 200 with a single link in the slot) |

### yt-epic.sh

| Field | Value |
|---|---|
| **Operation/step** | Step 9, best-effort, final step — link the ticket's `decomposed_from` parent via a single type-agnostic `Subtask` link |
| **What it does** | Looks up the parent ticket's `youtrack_url` from the parent's `metadata.yaml`, verifies the parent issue exists, creates one `Subtask` link with the parent as source, and verifies direction via read-back. **Performs zero re-typing, Move, hierarchy flattening, or umbrella replacement** |
| **Inputs** | `--ticket <id>`, `--issue <id>` (both required). Files: child and parent `metadata.yaml` (read-only), config sidecar (`link_relations.decomposed_from`) |
| **Outputs (stdout)** | `epic_result=applied\|skipped\|rejected\|none` |
| **Exit codes** | `0` on applied/skipped/rejected/none; `2` usage; `4` config HALT; `1` if the parent's `metadata.yaml` exists but fails subset parsing |
| **Re-run (idempotency)** | Idempotent link creation; if a parent was not yet projected on run 1, run 2 links it once the parent has a `youtrack_url` |

### yt-reserve.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — allocate a new issue ID from YouTrack when §10 binds `reserve-from-tracker` |
| **What it does** | Resolves the project, constructs the create payload, **emits the pairing obligation audit line BEFORE contacting YouTrack**, and creates the stub issue (with no invented placeholder Type) |
| **Inputs** | `--summary <text>` (required), `--type <repo-type>` (optional). Environment: base URL, token, optional project key |
| **Outputs (stdout)** | `issue_id=<2-NNNN>`, `issue_readable=<KEY-N>`, `youtrack_url=<base>/issue/<KEY-N>` |
| **Exit codes** | `0` reserved; `1` create rejected, readable ID missing, or `/api/admin/projects` returned 401/403 (`syncyt.config.project_read_refused`); `2` usage; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | **Intentionally non-idempotent** — each invocation allocates a distinct issue ID and must be paired with `specs/<id>/` artifacts |

### yt-import.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — seed-read an existing YouTrack issue into a temporary directory for `/cadence-triage` |
| **What it does** | Fetches summary and description into a single `seed_dir=` temp directory, derives an inverse `type_hint` only when `issue_type_map` is 1:1 invertible for that value, and downloads attachments within `attachment_size_ceiling_mib` under collision-proof `{attachmentId}-{sanitizedFilename}` names without ever logging signed attachment URLs. Unlinks `seed_dir` on failure |
| **Inputs** | `--issue <KEY-N>` (required), `--ticket <id>` (optional attachment destination key). Files: config sidecar (`attachment_size_ceiling_mib`, `issue_type_map`) |
| **Outputs (stdout)** | `issue_readable=`, `issue_id=`, `seed_dir=`, `summary_file=`, `description_file=`, `manifest_file=`, `attachments_downloaded=<n>`, `attachments_referenced=<n>`, `type_hint=<repo-type>` |
| **Exit codes** | `0` seeded; `1` read rejected/unparseable; `2` usage; `3` transport; `4` config HALT |
| **Re-run (idempotency)** | Pure read into a fresh temp directory; overwrites only matching `{attachmentId}-{sanitizedFilename}` files |

### yt-sprint-check.sh

| Field | Value |
|---|---|
| **Operation/step** | Intake — read-only sprint membership check consumed by `/cadence-implement` |
| **What it does** | Resolves the issue ID verbatim (from `youtrack_url` or `<id>`, never via summary search), runs the configured `sprint_query`, and outputs one verdict (`in-sprint`, `not-in-sprint`, or `inconclusive`). Maps HTTP 400 (`invalid_query` on unknown ID) and unreachable transport to `inconclusive`, never `not-in-sprint` |
| **Inputs** | `--ticket <id>` (required). Files: `metadata.yaml` (read-only, if present), config sidecar (`sprint_query`) |
| **Outputs (stdout)** | `sprint_verdict=in-sprint\|not-in-sprint\|inconclusive`, `issue_readable=<KEY-N>` |
| **Exit codes** | `0` for all verdicts; `2` usage; `4` config HALT |
| **Re-run (idempotency)** | Strictly read-only |

### Shared libraries (BTG-247)

`yt-lib.sh`, `yt-rest.sh`, `yt-meta.sh`, `yt-meta-path.sh`, `yt-worklog-lib.sh`, `yt-worklog-agent.sh`, and `yt-link-targets.sh` are contracted in `.agents/skills/cadence-sync-youtrack/youtrack-scripts-libs.md` (BTG-247); `yt-projectkey-lib.sh` is contracted in `.agents/skills/cadence-sync-youtrack/youtrack-scripts-projectkey.md` (BTG-179).

---

## 7. Documented divergences from `/cadence-sync-jira`

Per AC-6, every `/cadence-sync-jira` capability that has a YouTrack Server equivalent is implemented with matching observable semantics, while capabilities **without** a YouTrack Server equivalent are omitted **and explicitly documented below**:

| # | `/cadence-sync-jira` behavior | `/cadence-sync-youtrack` behavior | Underlying YouTrack Server data-model reason |
|---|---|---|---|
| 1 | Umbrella replacement flow: mints a replacement issue at a non-Epic type, migrates child links, and closes the original issue | **No umbrella replacement, no hierarchy flatten, no re-type, no Move.** `yt-epic.sh` creates a single `Subtask` link | Jira forbids an Epic from having an Epic Link parent. YouTrack Server's `Subtask` link relation is type-agnostic, allowing an epic to parent another epic directly |
| 2 | Dedicated Acceptance Criteria custom field discovered by name, written outbound, and read back on import | **No Acceptance Criteria custom field** in either direction; criteria project solely into the Markdown description | The bound YouTrack project has no AC custom field, and sending an unknown customField name returns **HTTP 500** `incompatible-issue-custom-field-name-…` |
| 3 | Jira wiki markup templates required by Jira REST v2 | **Native Markdown templates** with zero markup conversion | YouTrack Server renders Markdown natively in descriptions and comments |
| 4 | Multi-hop workflow transition graph walk with `global_transitions` | **Two-level `status_state_map`** (`Type -> repo status -> State`) applied in a single custom-field write | YouTrack's `State` is a direct `StateProjectCustomField` without transition graph edges, though the policy mapping remains two-level (`(Type, status)`) per BTG-176 DEC-077 |
| 5 | Fixed `sprint in openSprints()` JQL predicate | **Configurable `sprint_query`** defaulting to `inconclusive` when unconfigured | YouTrack Server has no built-in `openSprints()` query function |
| 6 | Placeholder issue type required during `reserve` | **No placeholder type**; reserved stub issues carry only project and summary | YouTrack Server permits creating an issue with only project and summary (HTTP 200) |
| 7 | Attachment manifest records each attachment's download URL | **Manifest records disposition only (`downloaded` / `referenced`), never the URL** | YouTrack Server attachment URLs include a pre-signed `sign=` credential parameter that grants unauthenticated read access (§2) |
| 8 | Dedicated `precedes` link relation | **`precedes` mapped to `Depend`** (`is required for` / `depends on`) in config | YouTrack Server ships `Depend` rather than `Precedes` as its directed dependency link type |

---

## 8. Retained invariants that require no runtime branch

Two governance invariants from earlier revisions remain enforced structurally without needing runtime conditional branches:

| Invariant | How it is enforced | Why no runtime branch exists |
|---|---|---|
| **Updating an estimate never resets spent time** (PROD_CADENCE-006) | Enforced by YouTrack Server's field architecture and `custom_field_map` shipping empty | On YouTrack Server, `Spent time` is read-only/computed from work items (direct writes fail with HTTP 400 `"automatically calculated"`), and `custom_field_map` does not project `estimated_effort` by default |
| **Posted work items are strictly immutable (never updated or deleted)** | Enforced structurally by `worklog-immutability-parity-gate.sh` | Neither `yt-worklog.sh` nor its libraries contain any HTTP update or delete calls against work items, and the CI parity gate fails the build if any mutating HTTP verb targets a work-item path |

Three legacy MCP-era audit conditions remain retired because their conditional branches no longer exist: the description-only AC notice (since description projection is the only path), the description re-projection notice (since updates always project the rendered description), and the non-admin schema-value qualifier (since HTTP 400 reports only that the value is absent from the bundle).
