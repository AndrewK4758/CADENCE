# Database Migration Policy

This policy establishes the mandatory engineering rules for all database migrations across CADENCE repositories, regardless of language, ORM, or migration runner. Every migration must be both **idempotent** and **reversible**. These guarantees are enforced at three points: by `cadence-implementer` / `cadence-migration-author` during authoring, by `cadence-reviewer` during Gate 2 Code Review, and by `cadence-maintainer` during Gate 3 Maintainer Acceptance.

This policy is stack-agnostic. For framework-specific implementation patterns, consult companion guides such as `docs/guides/ef-migration-examples.md`.

## Core Principles

1. **Reversibility** — Every migration must support clean rollback. Any deployment must be revertible to the prior schema version without manual database surgery or silent data loss.
2. **Idempotency** — Executing a migration against a database where it has already been partially or fully applied must succeed cleanly without error. This guards against interrupted deployments and automated retry loops.
3. **Separation of concerns** — Structural schema changes (DDL) and data transformations (DML) must live in separate migration files. Never seed, transform, or backfill application rows inside a structural schema migration.

## Requirements

### 1. Every Forward Migration Must Have a Complete Reverse Migration

Every structural operation in the forward (`apply` / `Up`) path requires an exact inverse operation in the rollback (`revert` / `Down`) path:

| Forward operation | Required reverse operation |
|---|---|
| Create table | Drop table |
| Add column | Drop column |
| Create index | Drop index |
| Add constraint (FK, unique, check) | Drop constraint |
| Rename column/table | Rename back to original |
| Alter column (type, nullability) | Alter back to original |
| Custom SQL | Reversal SQL |

**Empty or no-op reverse migrations are strictly forbidden.** If a migration is genuinely irreversible by nature (for example, a contraction step that drops a legacy column containing historical data), the exception must be recorded in `specs/{ticket-id}/decisions.md` with explicit human sign-off and a verified backup/restore procedure.

### 2. Idempotency Guards

Every migration must tolerate repeated execution so that a deployment interrupted mid-flight can be safely re-run.

**For migration runners with built-in version tracking** (such as a migration history table): the tool prevents re-running a migration that completed in full. However, any raw or custom SQL block embedded inside a migration must still carry its own conditional existence guards in case an earlier run failed mid-script before recording completion.

**For raw SQL or custom migration scripts:** Every DDL statement must be wrapped in an explicit existence check:

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

The practical test for idempotency: executing the forward migration twice in succession against the same database instance must either no-op cleanly or produce the exact same schema state — never throw a duplicate-object error.

### 3. Separation: Schema vs. Data

| Migration type | Allowed operations | Forbidden operations |
|---|---|---|
| **Schema migration** | DDL: create/alter/drop tables, columns, indexes, constraints | DML: INSERT, UPDATE, DELETE of application data |
| **Data migration** | DML: backfill, transform, seed | DDL: structural changes |

Whenever a feature requires both structural schema changes and data population, author separate, sequentially ordered migrations:
1. **Schema migration (expand)** — additive DDL adding nullable columns or new tables.
2. **Data migration (backfill)** — DML populating the new columns/tables from existing records.
3. **Schema migration (contract)** — restrictive DDL removing deprecated columns/tables in a subsequent release after all consumers have transitioned.

Separating DDL from DML ensures each step can be rolled back independently and prevents a schema rollback from inadvertently destroying backfilled production data.

For the full multi-release expand/contract deployment workflow that operationalizes this rule, see `docs/agentic-sdlc/migration-workflow.md`.

### 4. Large Table Safety

When migrating tables exceeding 1 million rows (or any table on a high-throughput critical path):

- **No extended table locks:** Avoid DDL statements that acquire long-lived exclusive table locks. Always use online or concurrent index/constraint operations supported by the database engine (e.g., `CREATE INDEX CONCURRENTLY` in PostgreSQL, `WITH (ONLINE = ON)` in SQL Server).
- **Batched data migrations:** Execute backfills and updates in bounded batches (1,000–10,000 rows per transaction) rather than locking the entire table in a single monolithic transaction.
- **Execution time budgets:** Record expected migration runtime in `spec.md`. Any migration projected to run longer than 30 seconds must be flagged explicitly for Gate 1 Spec Approval.
- **Non-nullable additions:** Adding a `NOT NULL` column to a populated table requires either a metadata-only default value or a three-step expand/backfill/alter sequence. Never add an un-defaulted `NOT NULL` column directly to a table containing existing rows.
- **Column removal:** Schedule column drops on large tables during low-traffic windows, and always deprecate and stop reading/writing the column in application code at least one release prior to dropping it.

### 5. Rollback Verification

Before marking implementation complete, `cadence-implementer` (or `cadence-migration-author`) must empirically verify the full round-trip migration cycle using the repository's migration CLI (triaging the command output via `offload_log_triage` / `log-triage` to preserve exact verification evidence):

```
1. Apply the migration forward        → database reaches version N
2. Roll back to the previous version   → database returns cleanly to version N-1
3. Re-apply the migration forward      → database reaches version N again without error
```

All three steps must exit zero without errors. When the repository runs automated integration tests against a containerized or ephemeral test database, codify this `apply → rollback → reapply` sequence as an automated test case.

Concrete evidence of rollback verification must accompany the MR via at least one of:
- A commit message tag: `[reversible, idempotent]`
- An automated integration test exercising the apply-rollback-reapply cycle
- Verbatim CLI verification output recorded in `submission.md`

### 6. Migration Naming and Ordering

Migration filenames must communicate both execution order and ticket lineage clearly:

- Prefix with a chronological timestamp or monotonic sequence number for deterministic ordering.
- Embed the ticket ID for direct traceability back to `specs/` or `archive/`.
- Include a concise, human-readable slug describing the operation.
- Make schema migrations and data migrations distinguishable by name.

In frameworks that manage ordering metadata automatically (such as EF Core's `.Designer.cs` timestamp attributes), the filename pattern may follow the framework's native generator convention provided execution order remains deterministic.

Standard naming pattern: `{timestamp}_{ticket}_{description}.{ext}`

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

When a migration genuinely cannot satisfy reversibility (for example, a regulatory data-erasure mandate or a one-way cryptographic hash migration), follow this explicit exception protocol:

1. Record the exception and technical rationale in `specs/{ticket-id}/decisions.md`.
2. Author a concrete data recovery plan (pre-migration snapshot procedure, point-in-time restore runbook, or reversible export script).
3. Obtain explicit human sign-off at Gate 1 (Spec Approval) before writing migration code.
4. Both `cadence-reviewer` (Gate 2) and `cadence-maintainer` (Gate 3) must explicitly verify and acknowledge the documented exception in their review assessments.

Migration exceptions are governed, auditable decisions — never silent omissions.
