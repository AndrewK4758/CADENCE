# `/cadence-sync-jira` — reported conditions: scratch staging and import seed

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-247).
External invariant relied upon: identical to `.agents/skills/cadence-sync-jira/jira-server-conditions.md` — every script emits machine-readable results on **stdout** and audit conditions on **stderr** as `syncjs.<family>.<condition>` lines. Each condition below is emitted by the named script and verified by test harnesses.

**This file is a modular segment of the single condition catalog, split rather than truncated.** BTG-247 factored out the scratch-staging and import-seed sections so `jira-server-conditions.md` stays beneath the `<400`-line Developer Experience ceiling, matching the modular split pattern of BTG-102, BTG-105, BTG-168, BTG-173, and BTG-205.

---

## Scratch staging (`syncjs.<scope>.scratch_unavailable`, every script — BTG-079 AC-4/AC-5)

Every script that constructs a JSON request payload stages it in a temporary file via `mktemp`. If `mktemp` fails (due to a full or read-only `$TMPDIR`, disk quota exhaustion, or `ENOSPC`) and a script does not guard the call, two severe failures occur simultaneously:

1. **Broken output channel contract.** `mktemp` prints a raw OS error to stderr and returns an empty path, causing the subsequent `> "$path"` redirect to emit a raw bash error (`No such file or directory`) instead of a structured `syncjs.*` condition (violating DEC-001).
2. **Silent bodyless request degradation.** Because `js_rest` omits `--data-binary` and `Content-Type` when passed an empty body path, an unguarded `mktemp` failure sends a **bodyless** HTTP request — which a permissive endpoint can accept as a field clear while the script reports success (DEC-057, DEC-060, DEC-061).

BTG-079 eliminates this entire defect class structurally: every `mktemp` invocation across the adapter silences raw OS stderr and checks its exit status immediately, enforced across all compiled `*.sh` files by `btg-075-structural-seams.test.sh` **OS-1.7** (`syncjs.script.unguarded_mktemp`, `BOUNDARY_FAULT`). Each script emits its own scoped condition while respecting its blocking vs. best-effort polarity:

- **`syncjs.write.scratch_unavailable`** (Critical) — the primary issue create/update request payload could not be staged. **HALTs** before sending any request (sibling of `syncjs.write.body_unbuildable`).
- **`syncjs.ac.body_unbuildable`** (Warning) — the Acceptance Criteria payload built as zero bytes (distinct from `syncjs.ac.scratch_unavailable`, where `mktemp` itself failed). Refuses the `PUT` with `ac_result=body-unbuildable` and continues the sync, preventing `--data-binary "@<empty-file>"` from clearing the AC field in Jira.
- **`syncjs.worklog.scratch_unavailable`** (Critical) — **HALTs** without posting any worklog.
- **`syncjs.comment.scratch_unavailable`** (Critical) — **HALTs** Step 3 (`jira-preserve.sh`) before Step 4 can overwrite the unpreserved original issue description.
- **`syncjs.transition.scratch_unavailable`** (Critical) — **HALTs** Step 5 (`jira-transition.sh`) before sending a bodyless transition `POST`.
- **`syncjs.reserve.scratch_unavailable`** (Critical) — **HALTs** `jira-reserve.sh` without reserving or guessing an issue key.
- **`syncjs.import.scratch_unavailable`** (Critical) — **HALTs** `jira-import.sh` with nothing seeded so a partial seed directory is never mistaken for a complete import.
- **`syncjs.link.scratch_unavailable`** (Warning) — skips link creation with `links_created=0` and `link_result=rejected` at exit `0` (best-effort branch halt). `jira-link-lib.sh` emits this condition under `$JS_LINK_REPORT_PREFIX` and returns non-zero for that single link pair.
- **`syncjs.umbrella.scratch_unavailable`** (Warning) — skips child Epic Link updates and emits `epic_result=rejected` at exit `0` (DEC-033).
- **`syncjs.assign.rejected`** (Warning) — when staging the assignee payload fails, `jira-assign.sh` makes no HTTP request and emits `assign_result=rejected` at exit `0`.
- **`syncjs.assign.body_unbuildable`** (Warning, BTG-084) — `jq` failed or produced zero bytes when building the assignee payload; emits `assign_result=rejected` at exit `0` without sending a 0-byte body over the wire.

**One deliberate exception: the transport diagnostic capture file degrades gracefully rather than halting** (AC-5). Inside `js_rest` and `js_rest_download`, `mktemp` is used solely to capture `curl`'s `-sS` stderr diagnostic stream. Because that capture file is a diagnostic aid rather than a request payload — and is the very first `mktemp` executed in any script — halting there on an unusable `$TMPDIR` previously misreported a local `/tmp` fault as `syncjs.transport.rest_unreachable` before any network call was attempted. Instead, if the diagnostic capture file cannot be created, `JS_TRANSPORT_ERROR` notes that curl stderr capture was unavailable and the HTTP exchange proceeds normally, allowing the first load-bearing request-body `mktemp` to halt with the accurate `syncjs.<scope>.scratch_unavailable` condition.

## Import seed (`jira-import.sh`)

- **`syncjs.import.no_reverse_map`** (Info) — the live Jira issue type does not have a **unique** inverse key in `issue_type_map` (for example, when both `bug` and `security` map to Jira's `Bug` type), so **no `type:` hint is emitted** and the imported ticket remains untyped for `/cadence-triage` to classify (preventing security tickets from being silently misclassified as ordinary bugs). The inverse lookup is computed dynamically from `issue_type_map` in `jira-server-config.json` so it can never drift from the forward map.
- **Attachment manifest (`manifest_file=`)** — records one structured line per attachment containing source issue key, attachment ID, sanitized filename, byte size, `mimeType`, and disposition (`path:` when downloaded locally, `url:` when referenced above the size ceiling, or `failed:` when download failed). `/cadence-triage` renders one `## Supporting Evidence` bullet per manifest line so every attachment is accounted for (BTG-043).
