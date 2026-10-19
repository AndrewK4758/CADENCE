---
name: claire-migrate
description: Author EF Core database migrations following the expand/contract pattern
argument-hint: "[ticket-id] [--contract]"
arguments: [ticket_id, flags]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Author database migrations for `$ticket_id` using the expand/contract pattern. Delegate to the `claire-migration-author` agent for discovery, generation, and verification.

## Prerequisites

Verify before starting:

1. A spec exists at `specs/$ticket_id/spec.md` with schema changes described, OR entity classes on the current branch differ from the base branch
2. At least one .NET project in the solution contains a `DbContext`
3. The `dotnet ef` CLI is available (`dotnet ef --version` succeeds)

If no spec exists and no entity changes are detected, ask the user to describe the schema changes needed.

## Steps

1. **Parse arguments:**
   - Extract `ticket_id` (required)
   - Detect `--contract` flag — if present, mode is `contract`; otherwise mode is `expand`

2. **Validate environment:**
   - Run `dotnet ef --version` to confirm EF tooling is installed
   - If missing, instruct user to install: `dotnet tool install --global dotnet-ef`

3. **Delegate to the migration-author agent.** Pass:
   - Ticket ID: `$ticket_id`
   - Mode: `expand` or `contract`
   - The agent will:
     - Discover the project structure (DbContext, migrations directory, startup project, DB provider)
     - Determine schema changes from spec, entity diffs, or user input
     - Generate migrations following the expand/contract pattern
     - Verify backwards compatibility (expand mode)
     - Run apply/rollback/reapply verification cycle
     - Document contraction follow-up when applicable

4. **Verify output:**
   - Migration files exist in the discovered migrations directory
   - Solution compiles cleanly (`dotnet build`)
   - Apply/rollback/reapply cycle passed (confirmed by agent)

5. **Report to user:**
   - Migration files created (paths and descriptions)
   - Backwards compatibility assessment
   - Contraction work deferred (if any) with link to decisions.md entry
   - Suggested next step (commit, run tests, or create MR)

## Example

```
/claire-migrate TT-6547              # Author expansion migrations for a feature
/claire-migrate TT-6547 --contract   # Author contraction migrations as follow-up
```
