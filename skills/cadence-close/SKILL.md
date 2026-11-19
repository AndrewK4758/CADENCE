---
name: cadence-close
description: Consolidated ticket close-out workflow — read metadata state via read_state.py, run tier-gated Gate 3 /cadence-maintain (Medium/High when maintainer_approved_at is unset; skipped at Low/Trivial), land via /cadence-merge (with tracker sync), and finalize via /cadence-archive unless --no-archive is passed. Activate when implementation and Gate 2 code review have passed and the ticket is ready to land and archive.
argument-hint: "<ticket-id> [--no-archive]"
arguments: [ticket_and_flags]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-close

Advance a code-reviewed ticket through **Gate 3 Maintainer Acceptance (tier-conditional) -> Merge & Tracker Sync -> Archive** in one command.

> **Shared State Reader Contract:** Always inspect ticket state using `read_state.py` rather than parsing `metadata.yaml` by hand. Never invoke `--no-verify` during merge, and never run this workflow before `/cadence-build` has closed Gate 2 cleanly (except `status: cancelled` close-out archival).

## Steps

### 1. Read State & Validate Entry Gate

```bash
python3 .agents/skills/cadence-build/scripts/read_state.py <TICKET-ID> \
  || python3 skills/cadence-build/scripts/read_state.py <TICKET-ID>
```

Inspect `tier`, `status`, `merge_request`, `maintainer_approved_at`, and `ledger_last` (`blocking=`):
- If `status == archived` or `specs/<TICKET-ID>/` is already absent while `archive/<TICKET-ID>/` exists → report `nothing to do (already archived)` and exit cleanly.
- If `status == cancelled` → skip Gate 3 and merge; verify `resolution:` is populated and delegate directly to Step 4 (`/cadence-archive <TICKET-ID>`).
- If `tier` is empty or unrecognized → **halt fail-closed** (never default to Low).
- If `status == in-progress` or `ledger_last` reports `blocking>0` → **halt**, directing the operator back to `/cadence-build <TICKET-ID>`.
- Unless `status == merged`:
  - At `Medium` or `High` with `status == in-review` and `ledger_last` reporting `blocking=0` -> proceed to Step 2.
  - At `Low` or `Trivial` -> skip Step 2 (Gate 3 exempt) and proceed to Step 3.

### 2. Gate 3 Maintainer Acceptance (`Medium` / `High` only)

When normalized `tier` is `Medium` or `High` and `maintainer_approved_at` is empty:
1. Run `/cadence-maintain <MR-ref-or-TICKET-ID>` (evaluates all 8 acceptance dimensions via `cadence-maintainer` and presents the interactive decision prompt; `/cadence-close` owns any follow-up watch prompt rather than letting inner `/cadence-maintain` prompt independently).
2. Require explicit human acceptance recording `maintainer_approved_at` and updating `submission.md` before continuing.
3. On `Postpone` or `Reject` (or missing human confirmation), **stop immediately** with zero merge writes. If `merge_request` remains open and an interactive operator is present, ask whether to invoke `/cadence-watch <TICKET-ID>` (`watch` = `--watch` live poll / `once` = `--once` single check / `no` = stop here) to watch for follow-up updates on the open PR (never prompt after a successful merge/archive; never auto-poll silently).

When `Low` or `Trivial`, log `gate3=SKIPPED (tier exempt)` and continue.

### 3. Merge, Post-Rebase Verification & Tracker Sync (`/cadence-merge`)

Unless `status == merged` already:
1. Invoke `/cadence-merge <TICKET-ID> --no-archive`:
   - Resolves `#branch-strategy-binding` dynamically (`integration-branch`, never hardcoded `main`/`develop`).
   - Rebases cleanly if needed, re-runs tests (routing >30 lines or errors through `offload_log_triage` on `:11434`), and runs `offload_deep_review` when resolving non-trivial conflicts.
   - Merges cleanly without `--no-verify`, fast-forwards local `<integration-branch>` (`--ff-only`) without pushing direct commits onto protected `<integration-branch>`, projects `merged` status to the bound tracker (`CADENCE_ORG.md#tracker-binding`), and cleans up temporary worktree state (`/cadence-archive` persists `merged_at` if unset alongside `status: archived`).

### 4. Archival & Inbound Citation Sweep (`/cadence-archive`)

- If `--no-archive` was passed, stop after Step 3 and report `status=merged (archival deferred; run /cadence-archive <TICKET-ID>)`.
- Otherwise invoke `/cadence-archive <TICKET-ID>` to relocate `specs/<TICKET-ID>/` -> `archive/<TICKET-ID>/`, run `dead-citation-gate.sh`, author `summary.md`, update `CHANGELOG.md`, disposition `[adr-owed]` findings, sync final tracker state, and clean up the merged branch.

### 5. Local Verification Post-Close

Run `bash .agents/skills/cadence-doctor/doctor.sh --ticket <TICKET-ID> || bash skills/cadence-doctor/doctor.sh --ticket <TICKET-ID>` to confirm post-archival ticket and repository hygiene (`0` failures).
