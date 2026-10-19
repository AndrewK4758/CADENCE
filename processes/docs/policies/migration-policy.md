# Database Migration Policy

This document defines the mandatory requirements for all database migrations, regardless of framework or tooling. Every migration must be **idempotent** and **reversible**. These requirements are enforced by the implementer (at authoring time), code-reviewer (at review time), and maintainer (at acceptance time).

This policy is framework-agnostic. For tool-specific guidance, see companion examples (e.g., `docs/guides/ef-migration-examples.md`).

## Core Principles

1. **Reversibility** — Every migration must be rollback-safe. A deployment can be reverted to the previous migration without manual intervention or data loss.
2. **Idempotency** — Running a migration against a database where it has already been (partially) applied must not fail. This protects against interrupted deployments and retry scenarios.
3. **Separation of concerns** — Schema changes and data migrations are separate migration files. Never seed, transform, or backfill data in a schema migration.

## Requirements

### 1. Every Forward Migration Must Have a Complete Reverse Migration

Every operation in the forward (apply) direction must have a corresponding reversal in the rollback direction:

| Forward operation | Required reverse operation |
|---|---|
| Create table | Drop table |
| Add column | Drop column |
| Create index | Drop index |
| Add constraint (FK, unique, check) | Drop constraint |
| Rename column/table | Rename back to original |
| Alter column (type, nullability) | Alter back to original |
| Custom SQL | Reversal SQL |

**Empty or stub reverse migrations are never acceptable.** If a migration genuinely cannot be reversed (e.g., dropping a column containing data), this must be documented in the spec's `decisions.md` with explicit human approval and a data recovery plan.

### 2. Idempotency Guards

All migrations must tolerate re-execution. This protects against interrupted deployments where a migration partially applied before failing.

**For migration tools with built-in tracking** (e.g., a migration history or version table): the tool prevents full re-execution at the migration level. However, any custom/raw SQL embedded within a migration must still be independently guarded.

**For raw SQL or custom scripts:** Every DDL statement must use conditional guards:

```sql
-- Column addition with existence guard
IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'campaigns' AND column_name = 'new_column'
)
BEGIN
    ALTER TABLE campaigns ADD new_column VARCHAR(100) NULL;
END

-- Index creation with existence guard
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_campaigns_new_column'
)
BEGIN
    CREATE INDEX IX_campaigns_new_column ON campaigns (new_column);
END
```

The test for idempotency: if you run the migration twice against the same database, the second run must either no-op or succeed identically — never error.

### 3. Separation: Schema vs. Data

| Migration type | Allowed operations | Forbidden operations |
|---|---|---|
| **Schema migration** | DDL: create/alter/drop tables, columns, indexes, constraints | DML: INSERT, UPDATE, DELETE of application data |
| **Data migration** | DML: backfill, transform, seed | DDL: structural changes |

If a feature requires both schema and data changes, create separate migrations in the correct order:
1. Schema migration (additive — adds new columns/tables)
2. Data migration (populates new columns from existing data)
3. Schema migration (removes old columns/tables, if applicable, in a later release after consumers have migrated)

This separation ensures each migration can be independently rolled back and that schema rollback does not destroy backfilled data unexpectedly.

For the recommended expand/contract deployment pattern that operationalizes this principle, see `docs/agentic-sdlc/migration-workflow.md`.

### 4. Large Table Safety

For tables exceeding 1M rows (or any table identified as high-traffic):

- **No extended locks:** Avoid operations that hold exclusive table locks for extended periods. Use online/concurrent operations where the database supports them (e.g., `CREATE INDEX CONCURRENTLY` in PostgreSQL, `ONLINE = ON` in SQL Server).
- **Batch data migrations:** Process rows in batches (1,000–10,000) with explicit transaction scoping. Never update an entire large table in a single transaction.
- **Timeout budgets:** Document expected execution time in the spec. Any migration expected to exceed 30 seconds must be flagged during spec review.
- **Non-nullable columns:** Adding a NOT NULL column to a populated table requires a default value. Never add a non-nullable column without a default to a table that contains rows.
- **Column removal:** Dropping columns from large tables should happen in off-peak windows. Consider marking the column as deprecated first, then removing in a subsequent release.

### 5. Rollback Verification

The implementer must verify rollback works before marking implementation complete. The procedure, using whatever migration CLI the project uses:

```
1. Apply the migration forward        → database at version N
2. Roll back to the previous version   → database at version N-1
3. Re-apply the migration forward      → database at version N (again)
```

All three steps must succeed without errors. If the project has a test database managed by integration tests, this apply-rollback-reapply cycle should be codified as an explicit test case.

Evidence of this verification must be present in the MR — either via:
- A commit message tag: `[reversible, idempotent]`
- An integration test that exercises the cycle
- Explicit documentation in the MR description

### 6. Migration Naming and Ordering

Migrations must be named to clearly communicate their purpose and ordering:

- Include a timestamp or sequence number for deterministic ordering
- Include the ticket/issue ID for traceability
- Include a human-readable description of what the migration does
- Separate schema and data migrations must be independently identifiable

For frameworks with built-in ordering (e.g., EF Core timestamps in generated metadata), the filename ordering requirement is satisfied by the framework. The naming pattern may omit the timestamp prefix if the framework guarantees execution order.

Example pattern: `{timestamp}_{ticket}_{description}.{ext}`

## Anti-Patterns

| Anti-pattern | Why it fails | Correct approach |
|---|---|---|
| Empty/stub reverse migration | Cannot roll back deployment | Implement full reversal |
| Data manipulation in schema migration | Couples schema and data lifecycle; can't roll back independently | Separate data migration file |
| Dropping column/table without backup plan | Irreversible data loss | Deprecate first, drop in later release |
| Unconditional DDL in custom SQL | Fails on retry if partially applied | Add conditional existence guards |
| Adding non-nullable column without default | Fails on populated tables | Add with default, or: add nullable → backfill → alter to non-null |
| Single migration for add + backfill + remove | Cannot partially roll back | Three separate migrations |
| Mixing multiple unrelated changes | Partial failure leaves ambiguous state | One logical change per migration |

## Exceptions

If a migration genuinely cannot meet these requirements (e.g., a destructive schema change mandated by compliance, a one-way encryption migration), the following process applies:

1. Document the exception in `specs/{ticket-id}/decisions.md` with rationale
2. Include a data recovery plan (backup procedure, point-in-time restore steps, or export script)
3. Get explicit human approval before implementation
4. The code-reviewer and maintainer must both acknowledge the exception in their reviews

Exceptions are tracked — they are never silent omissions.
