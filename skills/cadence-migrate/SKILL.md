---
name: cadence-migrate
description: Author EF Core database schema migrations using the expand/contract pattern with automatic log triage and pre-review diff verification
argument-hint: "[ticket-id] [--contract]"
arguments: [ticket_id, flags]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Author reversible database schema migrations for `$ticket_id` adhering to the expand/contract pattern. Delegate project discovery, migration generation, and apply/rollback/reapply verification to the `cadence-migration-author` subagent, with mandatory automatic `offload_log_triage` compaction on build/migration logs and `offload_deep_review` pre-scanning prior to MR creation.

## Prerequisites

Confirm all three preconditions before starting:

1. Either `specs/$ticket_id/spec.md` exists and specifies schema changes, OR entity model classes on the active branch differ from the integration branch
2. At least one .NET project in the solution defines an EF Core `DbContext`
3. The `dotnet ef` CLI tool is installed and operational (`dotnet ef --version` exits 0)

When neither a specification nor entity model diffs exist, prompt the operator to describe the required schema changes before proceeding.

## Steps

1. **Parse invocation arguments:**
   - Extract `ticket_id` (mandatory)
   - Check for the `--contract` flag — when `--contract` is supplied, set migration mode to `contract`; otherwise default to `expand` mode

2. **Verify tooling environment:**
   - Execute `dotnet ef --version` to verify that EF Core CLI tooling is available
   - If unavailable, instruct the operator to install it via: `dotnet tool install --global dotnet-ef`

3. **Delegate to `cadence-migration-author` (with mandatory `offload_log_triage`).** Supply:
   - Ticket ID: `$ticket_id`
   - Mode: `expand` or `contract`
   - The subagent will:
     - Locate the solution's `DbContext`, migrations folder, startup project, and configured database provider
     - Derive the required schema delta from `specs/$ticket_id/spec.md`, entity class diffs, or operator input
     - Generate EF Core migration files adhering strictly to the expand/contract pattern
     - Verify Surface Compatibility and backwards compatibility (in `expand` mode, existing running application code must continue operating cleanly against the expanded schema)
     - Execute the full apply -> rollback -> reapply verification cycle against the target database
     - **Mandatory Automatic Log Offload (`offload_log_triage`).** Whenever `dotnet build`, `dotnet ef migrations add`, or `dotnet ef database update` output exceeds 30 lines, automatically route the command output through `offload_log_triage` (`local-fast-cpu` / `gemma-4-e2b` on `:9379`, 0 MB VRAM, writing the full numbered raw output to `/tmp/agy-last-triage.log`) so verbatim compiler/SQL errors and `file:line` coordinates are extracted cleanly
     - Record any deferred contraction follow-up work in `specs/$ticket_id/decisions.md` when running in `expand` mode

4. **Verify migration outputs and run automatic pre-MR scan (`offload_deep_review`):**
   - Confirm the generated migration and designer/snapshot files exist in the target migrations directory
   - Confirm the solution builds cleanly (`dotnet build`), routing any output >30 lines through `offload_log_triage` (`/tmp/agy-last-triage.log`)
   - Confirm the apply/rollback/reapply verification cycle succeeded
   - **Mandatory Automatic Pre-Review Diff Scan (`offload_deep_review`).** Before recommending or opening/updating an MR, automatically run `offload_deep_review` (`local-moe-hybrid` on `:9380`) on the migration diff to verify expand/contract safety, absence of destructive unguarded DDL in expand mode, `<400`-line ceiling compliance on hand-authored files, and CHORD seam annotations (`BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).

5. **Report to the operator:**
   - Generated migration file paths and a summary of schema operations
   - Backwards-compatibility and zero-downtime deployment assessment (`expand` vs. `contract`)
   - Pre-review scan summary from `offload_deep_review`
   - Deferred `--contract` follow-up details (when applicable) citing the entry in `specs/$ticket_id/decisions.md`
   - Recommended next step (commit migration cycle, run full test suite, or open/update the MR)

## Example

```
/cadence-migrate TT-6547              # Author expansion migrations for a feature
/cadence-migrate TT-6547 --contract   # Author contraction migrations as follow-up
```

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 3 and Step 4 automatically pipe any `dotnet build` or `dotnet ef` verification output exceeding 30 lines through `offload_log_triage` (`local-fast-cpu` on `:9379`, 0 MB VRAM), saving raw numbered logs to `/tmp/agy-last-triage.log`.
- Step 4 automatically runs `offload_deep_review` (`local-moe-hybrid` on `:9380`) on the generated migration diff before MR creation/update.
- All migration authoring and schema verification decisions remain 100% owned by `gemini-4-argon-high`.
