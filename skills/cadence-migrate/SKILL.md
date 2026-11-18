---
name: cadence-migrate
description: Author reversible database schema and data migrations using the expand/contract pattern (EF Core, Alembic, Prisma/Drizzle, Room, or SQL scripts) with automatic log triage and pre-review diff verification
argument-hint: "[ticket-id] [--contract]"
arguments: [ticket_id, flags]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Author reversible database schema migrations for `$ticket_id` adhering to the expand/contract pattern. Delegate stack/topology discovery, migration generation, and apply/rollback/reapply verification to the `cadence-migration-author` subagent (`Deep-reasoning` tier, `xhigh` effort), with automatic `offload_log_triage` compaction on build/migration logs and diff-aware `offload_deep_review` pre-scanning prior to MR creation.

## Prerequisites

Confirm all three preconditions before starting:

1. Either `specs/$ticket_id/spec.md` exists and specifies schema changes, OR entity/schema model files on the active branch differ from the integration branch
2. A persistence migration stack is identifiable in the repository (`*.sln`/EF Core, `alembic.ini`, `prisma/schema.prisma`/`drizzle.config.*`, Android Room `@Database`, or SQL migration scripts)
3. The stack's migration/test tooling is executable in the workspace environment

When neither a specification nor schema diffs exist, prompt the operator to describe the required schema changes before proceeding.

## Steps

1. **Parse invocation arguments:**
   - Extract `ticket_id` (mandatory)
   - Check for the `--contract` flag — when `--contract` is supplied, set migration mode to `contract`; otherwise default to `expand` mode

2. **Detect stack and verify tooling environment:**
   - Identify which database migration stack applies and verify its CLI/test harness responds cleanly before scaffolding.

3. **Delegate to `cadence-migration-author` (`Deep-reasoning` tier, `xhigh` effort, with `offload_log_triage`).** Supply ticket ID `$ticket_id` and mode `expand` or `contract`. The subagent discovers project topology, derives schema deltas, generates stack-idiomatic expand/contract migrations (DDL separate from DML, complete rollback path, idempotency guards), runs the apply -> rollback -> reapply cycle (compacting `>30`-line or failing outputs via `offload_log_triage`), and records deferred `--contract` entries in `specs/$ticket_id/decisions.md`.

4. **Verify migration outputs and run automatic pre-MR scan (`offload_deep_review`):**
   - Confirm generated migration/snapshot artifacts exist and clean build + tests pass (compacting logs `>30` lines via `offload_log_triage`).
   - Run `offload_deep_review` (`diff_range="<integration-branch>...HEAD"`, `cwd="<repo-root>"`, `context_files=[...]`) to verify expand/contract safety, absence of unguarded destructive DDL in expand mode, `<400`-line ceiling compliance, and CHORD seams (`BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).

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

## Local Model Offload Integration (:11434)
- Step 3 and Step 4 automatically pipe any build or migration verification output exceeding 30 lines through `offload_log_triage` (`inference` on `:11434`), saving raw numbered logs to `/tmp/agy-last-triage.log`.
- Step 4 automatically runs `offload_deep_review` (`inference` on `:11434`) on the generated migration diff before MR creation/update.
- All migration authoring and schema verification decisions remain 100% owned by the `Deep-reasoning` tier (`effort: xhigh`, routed by `CADENCE_ORG.md#model-tier-mapping`).
