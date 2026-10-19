# Database Migration Workflow

This guide defines the engineering workflow for authoring database schema and data migrations using the **expand/contract** pattern. Migrations are authored by the `cadence-migration-author` agent (invoked directly via `/cadence-migrate` or delegated automatically by `cadence-implementer`) and applied unattended by the CI/CD deployment pipeline.

## Overview

The expand/contract pattern decouples schema evolution across two distinct releases:

1. **Expansion** — Additive, backwards-compatible schema changes ship alongside the feature implementation. Both the prior application version and the new application version operate safely against the expanded schema during rollout.
2. **Contraction** — Destructive cleanup (dropping retired columns, tightening nullability, removing legacy tables/indexes) ships in a subsequent release only after production telemetry confirms the deprecated elements have zero active reads or writes.

This two-phase discipline eliminates deployment downtime, preserves instant application-level rollback, and removes fragile "stop-the-world" database cutovers.

## Workflow 1: Authoring Expansion Migrations with a Feature

### When This Happens

Whenever a ticket's specification introduces schema changes (new tables, new columns, new indexes, or new foreign-key relationships).

### Deployment Strategies

During `/cadence-spec`, `cadence-spec-author` classifies the required migration rollout strategy inside the Deployment Compatibility Analysis:

#### Strategy A: Simple Expansion (most common)

The currently deployed application version naturally tolerates the expanded schema. The expansion migration and the feature code ship and deploy together in a single MR.

```
┌─────────────────────────────────────────────────────────┐
│  Single MR: feature code + expansion migration          │
│                                                         │
│  Deploy: migration runs → new code activates            │
│  Old pods: ignore new columns (nullable/defaulted)      │
│  New pods: use new columns                              │
└─────────────────────────────────────────────────────────┘
```

#### Strategy B: Prep-Required Expansion (three-phase deployment)

Either the existing production code or the new feature code cannot safely operate across both schema states simultaneously. An interim compatibility release is deployed first so all running instances tolerate both the pre-migration and post-migration schemas.

```
┌──────────────┐     ┌──────────────────────┐     ┌──────────────────────┐
│  Phase 1     │     │  Phase 2             │     │  Phase 3             │
│  Prep Release│────►│  Migration + Feature │────►│  Contraction         │
│              │     │                      │     │  (follow-up release) │
└──────────────┘     └──────────────────────┘     └──────────────────────┘

Phase 1: Deploy interim code that handles both pre- and post-migration schema
Phase 2: Run expansion migration + deploy feature code (safe because Phase 1 is running)
Phase 3: Drop deprecated columns after production verification (1-2 sprints later)
```

**When is Prep-Required triggered?**
- Currently running pods `INSERT` rows without populating a newly added column that new feature pods expect to be populated
- New feature pods `SELECT` from columns that do not yet exist during a rolling or blue/green deployment window
- Old and new application instances write semantically different representations to the same entity
- A dual-write bridge is required during cutover (writing to both legacy and replacement columns)

### Process (Simple Expansion)

1. **`spec.md` defines the schema changes.** The Proposed Design section in `spec.md` specifies which entities are added or modified, which columns or indexes are introduced, and whether a data backfill is needed. The Deployment Compatibility section classifies the rollout as "Simple."

2. **`cadence-implementer` updates domain/ORM entities.** During red-green-refactor TDD cycles, the implementer adds entity properties, updates `DbContext` mappings, and registers `DbSet` properties required by the scenarios.

3. **`cadence-migration-author` generates expansion migrations.** Triggered automatically during `cadence-implementer` Phase 2.5 or explicitly via `/cadence-migrate {ticket-id}`, the migration-author agent:
   - Discovers the repository's ORM layout (`DbContext`, migrations directory, startup project, database provider)
   - Runs `dotnet ef migrations add` to scaffold the migration from the entity model diff
   - Verifies that every DDL operation is strictly additive and backwards-compatible
   - Wraps custom SQL statements in idempotency guards
   - Splits schema (DDL) and data backfill (DML) operations into separate migration files
   - Executes the local `apply → rollback → reapply` verification cycle

4. **Expansion migration ships in the feature MR.** The migration files are committed in their own atomic commit on the feature branch and reviewed alongside the application code in the same MR.

5. **CI/CD applies the migration automatically.** During deployment, the pipeline runs `dotnet ef database update` (or the service invokes `context.Database.Migrate()` on startup) with zero manual intervention.

6. **Old and new application instances coexist safely.** Throughout a rolling deployment, prior-version pods ignore the newly added nullable/defaulted columns while new-version pods read and write them normally.

### Process (Prep-Required Expansion)

1. **`spec.md` specifies both the schema expansion and the interim compatibility code.** The Deployment Compatibility section classifies the change as "Prep-required" and details the required bridge logic (null-safe fallbacks, dual-writes, or application-level default synthesis).

2. **`cadence-implementer` authors interim compatibility code (Phase 2.25).** This bridge code:
   - Makes the running application tolerant of both pre-migration and post-migration schema states
   - Implements null-safe reads, dual-writes, or conditional column handling
   - Is verified by automated tests against both schema states
   - Is committed as a standalone deployable commit tagged `[prep-release]`

3. **Prep release deploys to 100% of production pods first.** Every production instance must be running the prep release before the expansion migration executes, guaranteeing that no running pod encounters an incompatible schema state during cutover.

4. **`cadence-migration-author` generates the expansion migration (Phase 2.5).** Follows the same verification rules as Simple Expansion while additionally confirming that:
   - The `[prep-release]` compatibility commit is present
   - The DDL/DML migration aligns cleanly with any active dual-write logic
   - Deployment sequencing is documented in `submission.md`

5. **Expansion migration + full feature code deploy together (Phase 2).** Once the prep release is active across production, the expansion migration and feature implementation roll out:
   - Prep-release pods continue operating safely via their compatibility bridge
   - Feature-release pods use the expanded schema natively
   - Cutover finishes once all pods run the feature release

6. **Retire interim bridge code.** Once the feature release is fully deployed, the temporary dual-write/fallback bridge can be removed either in a follow-up MR (recommended, preserving clean rollback to the prep release) or at the end of the rollout.

### What Gets Deferred to Contraction

Whenever a feature logically retires legacy columns, renames fields, or tightens column nullability, those destructive operations are **excluded** from the expansion migration. Instead:
- `cadence-migration-author` records the deferred destructive operations in `specs/{ticket-id}/decisions.md`
- `specs/{ticket-id}/metadata.yaml` is tagged with `contraction-pending`
- The specification's follow-up checklist defines the production verification criteria required before contraction can run

### Naming Convention

EF Core orders migration execution via the timestamp prefix in each migration's `.Designer.cs` file, while the ticket-prefixed migration name provides end-to-end traceability (see `docs/policies/migration-policy.md` §6):

```
{TicketId}_Expand_{PascalCaseDescription}    -- schema (DDL)
{TicketId}_Data_{PascalCaseDescription}      -- data (DML)
```

Examples:
```
TT6547_Expand_AddCampaignStatusColumn
TT6547_Data_BackfillCampaignStatusFromLegacy
```

### Commit Convention

```
{ticket-id}: migration(expand): {description} [reversible, idempotent]
```

---

## Workflow 2: Authoring Contraction Migrations

### When This Happens

After the expansion migration has run in production for at least 1 full sprint and every item on the production verification checklist has been confirmed.

### Prerequisites

Before invoking `/cadence-migrate {ticket-id} --contract`, verify:

- [ ] Expansion migration has been running in production for `>= 1` sprint
- [ ] Database query telemetry confirms zero reads or writes against the deprecated columns/tables for `>= 1` week
- [ ] No rollback to the pre-expansion application version is planned
- [ ] Application source code contains zero references to the deprecated schema elements
- [ ] The `contraction-pending` tag is present in `specs/{ticket-id}/metadata.yaml` (or `archive/{ticket-id}/metadata.yaml`)

### Process

1. **Invoke `/cadence-migrate {ticket-id} --contract`.** Launches `cadence-migration-author` in contraction mode.

2. **Agent loads deferred contraction scope.** Reads `decisions.md` for the ticket to locate the recorded list of deprecated columns, constraints, or tables slated for removal.

3. **Agent verifies readiness.** Prompts the operator to confirm that all production verification prerequisites above are satisfied.

4. **Agent scaffolds the contraction migration.** Generates the cleanup migration (dropping retired columns/indexes or tightening nullability) along with a complete `Down()` method capable of restoring the expanded schema structure.

5. **Agent runs `apply → rollback → reapply`.** Executes the full reversibility and idempotency verification cycle against the local verification database.

6. **Contraction ships in a dedicated MR.** The contraction migration is submitted as its own standalone MR with its own Gate 2 / Gate 3 review cycle, citing the originating ticket ID for lineage.

7. **Clear `contraction-pending`.** Once the contraction MR merges, remove the `contraction-pending` tag from `metadata.yaml`.

### Naming Convention

```
{TicketId}_Contract_{PascalCaseDescription}
```

Example:
```
TT6547_Contract_DropLegacyIsActiveColumn
```

### Commit Convention

```
{ticket-id}: migration(contract): {description} [reversible, idempotent]
```

---

## Workflow 3: CI/CD Pipeline Integration

### What the Deployment Pipeline Executes

The CI/CD deployment pipeline owns migration execution across shared environments. `cadence-migration-author` never runs migrations against staging or production databases — it runs verification exclusively against an isolated local development database.

**Pipeline responsibilities:**
- Executes `dotnet ef database update` using the target environment's connection string injected from the secrets manager
- Applies pending migrations in strict chronological timestamp order
- Records applied migrations in `__EFMigrationsHistory`
- Supports automated schema rollback via `dotnet ef database update {PreviousMigration}` if a deployment step fails

**Pipeline never requires:**
- Ad-hoc console runner scripts
- Manual SQL execution by an operator
- Per-environment migration branches
- Separate manual orchestration between DDL and DML migrations (EF Core timestamp ordering sequences both automatically)

### Guarantees Enforced by `cadence-migration-author`

Every migration authored by the agent is verified safe for unattended CI/CD execution:

1. **Reversible** — Every `Up()` operation has a complete, tested `Down()` counterpart
2. **Idempotent** — Custom SQL statements include conditional existence guards so retries after an interrupted deploy succeed cleanly
3. **Non-interactive** — Zero interactive prompts or manual operator steps
4. **Self-contained** — Zero external runtime dependencies beyond the database connection
5. **Deterministically ordered** — Timestamp-prefixed Designer metadata guarantees reproducible execution order
6. **Cleanly separated** — DDL schema changes and batched DML data backfills live in separate migration files for independent rollback

### Rollback Strategy

When a production deployment must be reverted:

1. **Application rollback:** The deployment controller (e.g., ArgoCD or ECS) rolls back immediately to the prior container image
2. **Schema rollback (only if needed):** The pipeline executes `dotnet ef database update {PreviousMigration}` to revert the database schema
3. **Zero-downtime safety:** Because expansion migrations are strictly additive, rolling back the application container **without** rolling back the database schema is safe by construction — the prior application version simply ignores the newly added nullable/defaulted columns

Application rollback is therefore instantaneous; database schema rollback is required only if a newly added index or trigger itself causes database resource contention.

---

## Quick Reference

| Scenario | Command | Ships In |
|----------|---------|----------|
| Simple schema expansion (new nullable/defaulted columns) | `/cadence-migrate TT-1234` | Same MR as feature |
| Feature requires data backfill | `/cadence-migrate TT-1234` (agent splits DDL & DML automatically) | Same MR as feature |
| Prep-required expansion | `cadence-implementer` Phase 2.25 + Phase 2.5 | Prep MR first, then feature MR |
| Deprecated columns ready for removal | `/cadence-migrate TT-1234 --contract` | Separate follow-up MR |
| Implementer auto-invocation | (automatic during `/cadence-implement` Phase 2.5) | Same MR as feature |

| Migration Type | Allowed Operations | Forbidden Operations |
|----------------|-------------------|---------------------|
| Expand | Add table, add nullable column, add column with default, add index, add nullable FK | Drop, rename, tighten nullability, narrow column type |
| Data | Batched `INSERT`, `UPDATE`, `DELETE` (`1,000–10,000` rows per batch per `docs/policies/migration-policy.md`) | `CREATE`, `ALTER`, `DROP` |
| Contract | Drop column/table/index, tighten nullability, rename retired elements | (all cleanup operations permitted after production verification) |

---

## Finding Pending Contraction Work

To list all tickets with pending contraction migrations awaiting production cleanup:

```bash
grep -rl "contraction-pending" specs/*/metadata.yaml archive/*/metadata.yaml
```

Inspect each ticket's `decisions.md` verification checklist before running `/cadence-migrate {ticket-id} --contract`.
