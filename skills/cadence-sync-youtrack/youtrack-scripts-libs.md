# `/cadence-sync-youtrack` — script contracts: shared libraries

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176, BTG-247).
External invariant relied upon: identical to `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md` and `.agents/skills/cadence-sync-youtrack/youtrack-scripts-projectkey.md` — the git repository (`metadata.yaml` + `problem.md`) is the sole source of truth; YouTrack is the projection surface, and every script communicates strictly across three channels (stdout `key=value`, stderr `syncyt.*`, exit code).

**This file is a modular continuation of the single script-contract index, split rather than truncated.** BTG-247 factored out the shared library entries (`yt-lib.sh`, `yt-rest.sh`, `yt-meta.sh`, `yt-meta-path.sh`, `yt-worklog-lib.sh`, `yt-worklog-agent.sh`, and `yt-link-targets.sh`) so that `youtrack-scripts.md` remains under the `<400`-line Developer Experience ceiling, matching `jira-server-scripts-libs.md`. Every file documented below is a **sourced library rather than a standalone CLI entry point** (verified across `artifacts/commands/cadence-sync-youtrack/*.sh`).

`btg176_index_view` (`ci-templates/scripts/tests/btg-176-lib/contract-doc.sh`) concatenates all `youtrack-scripts-*.md` files with `youtrack-scripts.md` prior to each contract lookup, ensuring the split is completely transparent to contract verification tests.

---

### yt-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library — **sourced** by every operation script; never executed directly and performs no side effects on load. Sources `yt-rest.sh` and `yt-meta.sh` |
| **What it does** | Provides the three-channel output primitives (`yt_emit`, `yt_report`, `yt_halt`), exit-code constants, and configuration resolvers: `yt_config_path`, `yt_config_get`, `yt_config_map`, `yt_config_map2` (the two-level `status_state_map` resolver — HALTs on an unmapped `(Type, status)` pair, naming both keys without falling back to a flat lookup), `yt_config_require`, `yt_env_value`, `yt_config_capability`, `yt_config_toggle` (the SOLE place default toggle polarities are defined), `yt_config_field_map`, `yt_field_attachment`, `yt_config_page_bound`, `yt_conditional_map_usable` |
| **Inputs** | `youtrack-server-config.json` sidecar; environment variables named in the sidecar's `env` block |
| **Outputs (stdout)** | None directly — exposes `yt_emit` to sourcing scripts |
| **Exit codes** | `yt_halt` terminates with the caller-supplied exit code; config resolvers return non-zero without exiting so the caller controls halt vs. refusal polarity |
| **Re-run (idempotency)** | Stateless resolution over config and environment |

### yt-rest.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, HTTP transport layer — **sourced** by `yt-lib.sh` |
| **What it does** | Provides `yt_rest <method> <path> [body-file]` (populating `YT_HTTP_STATUS`, `YT_HTTP_BODY`, and `YT_TRANSPORT_ERROR`), `yt_http_ok`, `yt_rest_download <path> <dest>` (streaming response bytes directly to disk rather than through shell variables that strip NUL bytes), `yt_build_body` (the single checked JSON payload builder verifying both that `jq` exited 0 and produced non-empty output), `yt_readback`, and `yt_classify_rejection`. Callers rely on observed YouTrack Server status codes: issue creation returns **200** (not 201); a missing issue returns **404**, whereas a missing **project** filter returns **200** with `[]` |
| **Inputs** | Base URL and Bearer token resolved via the config sidecar's `env` block |
| **Outputs (stdout)** | None — populates shell variables for the caller |
| **Exit codes** | `yt_rest` returns `3` when the HTTP exchange could not complete at the transport layer, and `0` whenever an HTTP status code was received; `yt_build_body` returns `1` after emitting one `syncyt.*` condition, leaving the halt/skip decision to the caller |
| **Re-run (idempotency)** | Stateless; each invocation performs a single HTTP exchange |

### yt-meta.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, repository metadata reader — **sourced** by `yt-lib.sh` |
| **What it does** | Implements the `metadata.yaml` reader (`yt_metadata_load <ticket-id>`), using a `python3` **stdlib-only** YAML subset parser that HALTs with `syncyt.metadata.unreadable` on any unsupported or malformed syntax rather than silently returning an empty object. Strictly read-only over `metadata.yaml`. The parser implementation is deliberately kept byte-aligned with `jira-meta.sh` because both adapters read the exact same repository `metadata.yaml` format. `yt_metadata_path` and `yt_metadata_get` live in `yt-meta-path.sh` (split in BTG-114 to maintain `<400`-line headroom) |
| **Grammar (the accepted YAML subset)** | Because this parser implements a strict **subset** of YAML without external PyYAML dependencies, `yaml.safe_load` passing in Python is **not sufficient proof** that the sync parser accepts a file — the root cause of **PROD_CADENCE-013**, where a multi-line scalar halted a blocking sync step after passing standard lint. **Supported constructs:** block sequences; single-line flow sequences `["A", "B"]`; single-level map nesting; single-quote doubling (`''`); quoted scalars **wrapped across physical lines**, folded with a single space per line break across all three value contexts (`k: "…"`, `- "…"`, `- k: "…"`); and, inside double-quoted scalars, **backslash escapes** consuming the following character (`\"`, `\\`, `\n`, `\t`, `\r`, `\0`, `\a`, `\b`, `\f`, `\v`, `\e` translate, while other escaped characters pass through literally per BTG-114 G3; backslashes inside single-quoted scalars remain literal per G2) — **byte-identical to `jira-meta.sh`** (spec.md F-3, AC-12). **Rejected constructs (halting loud with file path, opening line number, and last parsed key):** numeric escapes `\x`, `\u`, `\U` (BTG-114 G4); multi-line flow sequences; block scalars (`\|`, `>`) in mapping values; YAML anchors/aliases; multi-document streams; map nesting deeper than one level; wrapped unquoted scalars; and trailing non-comment text after a closing quote on **any** line (BTG-114). Kept synchronized with the header note in `specs/TEMPLATE/metadata.yaml` |
| **Inputs** | `CADENCE_REPO_ROOT` (optional); `specs/<id>/metadata.yaml` or `archive/<id>/metadata.yaml` |
| **Outputs (stdout)** | None — populates `YT_METADATA_PATH` and `YT_METADATA_JSON` for the caller |
| **Exit codes** | `yt_metadata_load` HALTs (exit `1`) on a parse error; helper functions return non-zero without exiting |
| **Re-run (idempotency)** | Pure read over repository files |

### yt-meta-path.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, metadata file locator and field extractor — **sourced unconditionally at the bottom of `yt-meta.sh`**; never invoked standalone |
| **What it does** | Defines `yt_metadata_path <id>` (resolving `specs/<id>/metadata.yaml` then `archive/<id>/metadata.yaml`) and `yt_metadata_get <jq-filter>` (extracting a single value from `$YT_METADATA_JSON` with `// empty` so missing keys never emit literal `null`). Factored out of `yt-meta.sh` in BTG-114 to preserve `<400`-line headroom when adding the G2–G5 quote-escape grammar rules. Because `yt-meta.sh` sources this file automatically, callers (`yt-epic.sh`, `yt-sprint-check.sh`) obtain both functions through `yt-lib.sh` without sourcing `yt-meta-path.sh` directly |
| **Inputs** | `yt_metadata_path`: `CADENCE_REPO_ROOT` (optional). `yt_metadata_get`: `$YT_METADATA_JSON` (populated by `yt_metadata_load`) |
| **Outputs (stdout)** | `yt_metadata_path`: resolved path to `metadata.yaml`. `yt_metadata_get`: extracted field value, or empty |
| **Exit codes** | Both return (never exit): `0` on success, `1` when `<id>` exists in neither `specs/` nor `archive/` |
| **Re-run (idempotency)** | Pure functions with zero state |

### yt-worklog-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, worklog mechanics — **sourced** by `yt-worklog.sh` to keep each file within the `<400`-line ceiling |
| **What it does** | Implements `yt_worklog_spent_minutes` (pre-post spent-time baseline read), `yt_worklog_report_truncation` (`syncyt.transport.page_truncated` — explicitly announcing when a work-item page hits `page_top_bound`), `yt_worklog_scan_markers` (SUPPRESS-ONLY crash-recovery scan: marker hits suppress duplicate posts, never trigger backfills), `yt_worklog_post_candidates`, `yt_worklog_post_one`, and `yt_worklog_verify_one` (post-add read-back verification) |
| **Inputs** | Internal issue ID and resolved `worklog_postcheck_capability`; reads config via `yt-lib.sh` |
| **Outputs (stdout)** | None directly — populates `POSTED`, `SUPPRESSED`, `POSTCHECK`, and `ADVANCE` variables emitted by `yt-worklog.sh` |
| **Exit codes** | Returns non-zero to `yt-worklog.sh`; never exits the process directly |
| **Re-run (idempotency)** | Append-only after marker and watermark filtering; structurally contains zero work-item update or delete calls |

**BTG-315 (additive):** `yt_worklog_post_candidates`'s per-candidate suppression filter also recognizes split-mode markers (`stage=S op-at=A` / `stage=S agent-at=A`) as already posted, and delegates candidate processing to `yt-worklog-agent.sh` whenever `$AGENT_USER` is non-empty. Unsplit mode remains byte-identical (AC-4).

### yt-worklog-agent.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, split-mode worklog attribution (BTG-315) — **sourced** by `yt-worklog.sh`; its functions are invoked only when `$AGENT_USER` is non-empty |
| **What it does** | Implements `yt_worklog_process_split_candidate <stage> <effort> <at>` to handle split operator/agent worklog projection for one candidate: computes the operator/agent minute split via `worklog-split.sh` (`yt_worklog_split`), emits the `split_resolved` audit line BEFORE contacting YouTrack for either leg, posts the operator leg by calling `yt_worklog_post_one` / `yt_worklog_verify_one` with the `op-at` marker, then posts the agent leg to the same work-item endpoint with `author: {login: <AGENT_USER>}` (`yt_worklog_post_agent_one`) and verifies attribution via a fresh re-read of the created work item (`yt_worklog_confirm_agent_author`) — inspecting `author.login` rather than `creator`. Any leg that rounds to `0m` is skipped cleanly without issuing an HTTP request |
| **Inputs** | `$AGENT_USER`, `$WLS_PATH`, `$ISSUE`, `$CAPABILITY`, `$TICKET`, `$YT_WORKLOG_MARKERS` — pre-resolved by `yt-worklog.sh` |
| **Outputs (stdout)** | None directly — updates `POSTED`, `ADVANCE`, `RESULT`, and `AGENT_LEGS_REJECTED` for `yt-worklog.sh`'s `yt_worklog_finish` emitter |
| **Exit codes** | Invokes `yt_worklog_finish` (on postcheck failure, indeterminate postcheck, or unconfirmed agent attribution) or `yt_halt` directly: `3` on unreachable transport, `4` when `worklog-split.sh` is missing or errors (`syncyt.worklog.split_unavailable`) |
| **Re-run (idempotency)** | Per-leg idempotency via the three-marker scan (`at=`, `op-at=`, `agent-at=`): an already-posted leg is never duplicated, and a rejected agent leg is NEVER retried automatically (OQ-3/OQ-4) |

### yt-link-targets.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, link-target extractor — **sourced** by `yt-link.sh`; performs zero network calls, zero file writes, and zero stdout output |
| **What it does** | Defines `yt_link_targets` to traverse every valid `related_tickets` structure in `metadata.yaml` — whether a flat array of IDs or a nested map of relation sub-keys holding lists or scalar IDs — alongside top-level ordering keys (`blocks`, `blocked_by`, `precedes`, etc.), flagging malformed structures rather than silently treating them as empty |
| **Inputs** | `$YT_METADATA_JSON` loaded by `yt_metadata_load` |
| **Outputs (stdout)** | None — populates `YT_LINK_TARGETS` and `YT_LINK_TARGETS_UNREADABLE` directly in the caller's shell scope (must be invoked directly, never inside a `$(...)` subshell) |
| **Exit codes** | Returns to caller without exiting |
| **Re-run (idempotency)** | Pure in-memory extraction over loaded metadata |
