# `/claire-sync-youtrack` — script contracts: shared libraries

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176, BTG-247).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-youtrack/youtrack-scripts.md` and the other `youtrack-scripts-*.md`
parts — the repository (`metadata.yaml` + `problem.md`) is the source of truth; YouTrack is the
projection layer, and every script communicates on exactly three channels (stdout `key=value`,
stderr `syncyt.*`, exit code).

**This file is a further part of one index, not another index.** It was split off by BTG-247, when
the primary stood at 399 lines against a re-derived headroom threshold and the shared-library
contract entries (`yt-lib.sh`, `yt-rest.sh`, `yt-meta.sh`, `yt-worklog-lib.sh` and
`yt-link-targets.sh`) had nowhere to land in place. The record is **split, never truncated** — the
same facet-conflict resolution BTG-102, BTG-105, BTG-168, BTG-173 and this ticket's own
`jira-server-scripts-libs.md` sibling already applied. The seam is "shared library, not an
operation entry point" — every entry below is sourced by at least one operation script (confirmed
by `grep -rl` across `artifacts/commands/claire-sync-youtrack/*.sh`, not assumed from the file name) and
is never invoked on its own.

`btg176_index_view` (`ci-templates/scripts/tests/btg-176-lib/contract-doc.sh`) merges every
`youtrack-scripts-*.md` into the primary before each lookup, so a split cannot hide a missing
contract entry.

---

### yt-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library — **sourced** by every operation script; not an entry point and runs nothing on load. It sources its own two halves (`yt-rest.sh`, `yt-meta.sh`) |
| **What it does** | Owns the channels (`yt_emit`, `yt_report`, `yt_halt`), the exit-code vocabulary, and config resolution: `yt_config_path`, `yt_config_get`, `yt_config_map`, `yt_config_map2` (the two-level `status_state_map` lookup — HALTs on a missing `(Type, status)` pair, naming both keys; never a flat fallback), `yt_config_require`, `yt_env_value`, `yt_config_capability`, `yt_config_toggle` (the ONLY place a default polarity is defined), `yt_config_field_map`, `yt_field_attachment`, `yt_config_page_bound`, `yt_conditional_map_usable` |
| **Inputs** | The config sidecar; the environment variables the config's `env` block names |
| **Outputs (stdout)** | None of its own — it provides `yt_emit` to its callers |
| **Exit codes** | `yt_halt` exits with the code its caller supplies; the resolvers return non-zero without exiting so the caller decides the polarity |
| **Re-run (idempotency)** | Pure resolution over files and environment; no state |

### yt-rest.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, transport half — **sourced** by `yt-lib.sh` |
| **What it does** | `yt_rest <method> <path> [body-file]` (sets `YT_HTTP_STATUS` / `YT_HTTP_BODY` / `YT_TRANSPORT_ERROR`), `yt_http_ok`, `yt_rest_download <path> <dest>` (streams to disk; never through a shell variable, which drops NUL bytes), `yt_build_body` (the ONE checked builder — it asks both wire questions: did `jq` exit 0, and did it produce content), `yt_readback`, `yt_classify_rejection`. Note the observed statuses callers must not guess: a create answers **200**, not 201; a missing issue answers **404** while a missing **project** answers 200 with `[]` |
| **Inputs** | The base URL and token resolved through the config's `env` block |
| **Outputs (stdout)** | None — it sets variables for its caller |
| **Exit codes** | `yt_rest` returns `3` when the exchange could not happen at all, `0` on any completed exchange whatever its status; `yt_build_body` returns 1 having emitted exactly one condition, and the CALLER decides whether that is a skip or a halt |
| **Re-run (idempotency)** | Stateless; each call is one exchange |

### yt-meta.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, owned-data half — **sourced** by `yt-lib.sh` |
| **What it does** | Owns the `metadata.yaml` reader and nothing else: `yt_metadata_load <ticket-id>` (a python3 **stdlib** subset parser that HALTs `syncyt.metadata.unreadable` on a degenerate parse rather than letting a caller no-op a projection). It READS owned data and never writes it. The parser program is byte-identical to the sibling adapter's, deliberately: what the two share is the OWNED DATA FORMAT — one repository, one grammar — not a tracker, and re-deriving a second reader would be the drift surface rather than the safeguard. `yt_metadata_path` and `yt_metadata_get` relocated to the colocated `yt-meta-path.sh` (BTG-114, the AC-12 analog of `jira-meta.sh`'s DEC-004) for DX-ceiling headroom |
| **Grammar (the accepted YAML subset)** | The parser is a SUBSET reader, not a spec-compliant one, so `yaml.safe_load` accepting a file is **no evidence** the sync can read it — that mismatch IS **PROD_CLAIRE-013**, in which a spec-legal wrapped scalar halted a blocking step while the operator's standard pre-check reported clean. **Accepted:** block sequences; inline (flow) sequences `["A", "B"]` on one line; one level of map nesting; the quote-doubling escape (`''`); a quoted scalar **wrapped across physical lines**, folded on exactly one space per break in all three value positions (`k: "…"`, `- "…"`, `- k: "…"`) so this reader and a spec-compliant parser agree on the value; and, in a DOUBLE-quoted scalar, a **BACKSLASH escape** that consumes the next character — `\"`/`\\`/`\n`/`\t`/`\r`/`\0`/`\a`/`\b`/`\f`/`\v`/`\e` translate, anything else falls through literally (BTG-114 G3; a SINGLE-quoted backslash stays literal, G2) — **byte-identical to `jira-meta.sh`'s grammar, including this addition** (spec.md F-3, AC-12). **Refused, each naming the file, the OPENING line and the last key read rather than being half-read:** the NUMERIC escapes `\x`/`\u`/`\U` (BTG-114 G4, never guessed); a flow sequence spanning lines; a block scalar (`\|`, `>`) in a mapping value; anchors/aliases; multi-document streams; map nesting past one level; a wrapped UNQUOTED scalar; and text after a closed quoted scalar, on **every** line and not only a folded one (BTG-114 drops the former FOLDED-only gate). The canonical statement for AUTHORS is the note at the top of `specs/TEMPLATE/metadata.yaml`; this row is its script-side counterpart and the two move together |
| **Inputs** | `CLAIRE_REPO_ROOT` (optional); `specs/<id>/metadata.yaml` or the archived copy |
| **Outputs (stdout)** | None — it sets `YT_METADATA_PATH` / `YT_METADATA_JSON` for its caller |
| **Exit codes** | `yt_metadata_load` HALTS (exit `1`) on a degenerate parse; the other helpers return non-zero without exiting |
| **Re-run (idempotency)** | Read-only over repo state |

### yt-meta-path.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, the metadata LOCATOR and one-value GETTER — **sourced by `yt-meta.sh`**, unconditionally, at its own tail; never on its own and never invoked |
| **What it does** | Owns `yt_metadata_path <id>` (specs/ then archive/) and `yt_metadata_get <jq-filter>` (reads one value from `$YT_METADATA_JSON`, `// empty` so an absent key never writes the literal `null` to the instance). Relocated here from `yt-meta.sh` (BTG-114) to buy DX-ceiling headroom for the G2/G3/G4/G5 quote-escape grammar addition — `yt-meta.sh` was at 391/400 with only 9 lines free, not enough for the +11-ish the grammar costs. `yt-lib.sh`'s existing `. yt-meta.sh` chain resolves both functions exactly as before the move — no call site changed (`yt-epic.sh` and `yt-sprint-check.sh` call `yt_metadata_path` through that chain, never sourcing this file directly) |
| **Inputs** | `yt_metadata_path`: `CLAIRE_REPO_ROOT` (optional). `yt_metadata_get`: `$YT_METADATA_JSON` (set by a prior `yt_metadata_load`) |
| **Outputs (stdout)** | `yt_metadata_path`: the resolved file path. `yt_metadata_get`: the requested value, or nothing |
| **Exit codes** | Both return (never exit): `0` on success, `1` when the id resolves to neither location (`yt_metadata_path`) |
| **Re-run (idempotency)** | Pure: no state of their own |

### yt-worklog-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, worklog half — **sourced** by `yt-worklog.sh`; the DX-ceiling split of one script into a driver and its mechanics |
| **What it does** | `yt_worklog_spent_minutes` (the spent-time baseline read), `yt_worklog_report_truncation` (`syncyt.transport.page_truncated` — a page at its explicit bound is ANNOUNCED, never inferred), `yt_worklog_scan_markers` (SUPPRESS-ONLY: the scan can suppress a post, never cause one), `yt_worklog_post_candidates`, `yt_worklog_post_one`, `yt_worklog_verify_one` (the post-add absorption check) |
| **Inputs** | Called with the issue id and the resolved capability; reads the config through `yt-lib.sh` |
| **Outputs (stdout)** | None — it sets `POSTED` / `SUPPRESSED` / `POSTCHECK` / `ADVANCE` for `yt-worklog.sh`, which emits them |
| **Exit codes** | Returns non-zero to its caller; it never exits the process |
| **Re-run (idempotency)** | Read/append only; it never issues a work-item update or delete, which is enforced structurally rather than trusted |

**BTG-315 (additive):** `yt_worklog_post_candidates`'s per-candidate suppress check also recognizes
a stray split-mode marker (`stage=S op-at=A` / `stage=S agent-at=A`) as already-projected, and
dispatches to `yt-worklog-agent.sh` entirely when `$AGENT_USER` is non-empty. Neither change alters
the unsplit path's own byte-for-byte behavior (AC-4).

### yt-worklog-agent.sh

| Field | Value |
|---|---|
| **Operation/step** | Split-mode projection (BTG-315) — **sourced** by `yt-worklog.sh` alone; its functions are only ever CALLED when `$AGENT_USER` is non-empty, so an unconfigured run never reaches them |
| **What it does** | `yt_worklog_process_split_candidate <stage> <effort> <at>` is the whole split-mode handling for one candidate: resolves the operator-share split via `worklog-split.sh` (`yt_worklog_split`), emits the `split_resolved` audit line BEFORE either leg is contacted, posts the operator leg by CALLING the existing, untouched `yt_worklog_post_one` / `yt_worklog_verify_one` with the `op-at` marker, then posts the agent leg to the SAME work-item endpoint with an `author: {login:}` field (`yt_worklog_post_agent_one`) and confirms attribution with a fresh re-read of the created item (`yt_worklog_confirm_agent_author`) — `creator` is never consulted, it stays the operator by construction. A leg computing to `0m` posts nothing for that party |
| **Inputs** | `$AGENT_USER`, `$WLS_PATH`, `$ISSUE`, `$CAPABILITY`, `$TICKET`, `$YT_WORKLOG_MARKERS` — all already resolved by the caller, read directly (no `local`) |
| **Outputs (stdout)** | None directly — writes the caller's own `POSTED` / `ADVANCE` / `RESULT` / `AGENT_LEGS_REJECTED`, which `yt-worklog.sh`'s `yt_worklog_finish` emits |
| **Exit codes** | May call the caller's own `yt_worklog_finish` (postcheck-failed / postcheck-indeterminate / unconfirmed attribution) or `yt_halt` directly: `3` transport unreachable, `4` the splitter is missing or errored (`syncyt.worklog.split_unavailable`) |
| **Re-run (idempotency)** | Per-leg, via the three-marker scan: a leg already logged is never re-posted; a rejected agent leg is NEVER retried automatically (OQ-3/OQ-4) |

### yt-link-targets.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, link-target traversal — **sourced** by `yt-link.sh`; no REST call, no write, nothing on stdout |
| **What it does** | `yt_link_targets` reads every shape `related_tickets` legitimately takes — a flat list, a mapping of sub-keys each holding a list or a single id — plus the top-level ordering keys, and reports anything else rather than reading it as an empty list. "No relations declared" and "the declaration could not be read" are opposite facts and only one of them is safe to project silently |
| **Inputs** | The loaded metadata JSON |
| **Outputs (stdout)** | None — it sets `YT_LINK_TARGETS` and `YT_LINK_TARGETS_UNREADABLE` for its caller, and is called DIRECTLY rather than through a `$( )` subshell, which would discard the counter |
| **Exit codes** | None — it returns to its caller |
| **Re-run (idempotency)** | Pure computation over owned data |

