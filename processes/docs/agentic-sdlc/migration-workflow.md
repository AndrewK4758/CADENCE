# Database Migration Workflow

This document describes the developer workflow for authoring database migrations using the expand/contract pattern. Migrations are authored by the `claire-migration-author` agent (invoked via `/claire-migrate` or automatically by the implementer agent) and executed automatically by the CI/CD pipeline.

## Overview

The expand/contract pattern splits schema changes into two releases:

1. **Expansion** — Additive, backwards-compatible changes ship with the feature. Both the old and new application versions work against the expanded schema simultaneously.
2. **Contraction** — Destructive cleanup ships in a follow-up release after production verification confirms the deprecated schema elements are unused.

This eliminates downtime, enables safe rollback, and removes the need for coordinated "big bang" deployments.

## Workflow 1: Authoring Expansion Migrations with a Feature

### When This Happens

Any time a feature requires schema changes (new tables, new columns, new indexes, new relationships).

### Deployment Strategies

The spec-author determines which strategy applies during specification (the Deployment Compatibility Analysis):

#### Strategy A: Simple Expansion (most common)

Old code naturally tolerates the expanded schema. The migration and feature code deploy together.

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

Old code or new code cannot safely handle both schema states. An interim compatibility release deploys first to make the application tolerant of both states.

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

**When is Prep-Required?**
- Old code INSERTs rows without populating a new column that new code expects to be non-null
- New code READs from columns that don't exist yet (race condition in blue/green cutover)
- Both versions write to the same entity with semantically different values
- A dual-write pattern is needed during transition (write to both old and new columns)

### Process (Simple Expansion)

1. **Spec describes schema changes.** The spec's proposed design (in `spec.md`) identifies what entities are new or modified, what columns are being added, and what data migrations are needed. The Deployment Compatibility section classifies this as "Simple."

2. **Implementer modifies entity classes.** During TDD implementation, the implementer agent adds new entity properties, updates DbContext configuration, and adds DbSet registrations as the code requires.

3. **Migration-author generates expansion migrations.** This happens automatically (via the implementer's Phase 2.5) or manually via `/claire-migrate {ticket-id}`. The agent:
   - Discovers the project structure (DbContext, migrations directory, DB provider)
   - Runs `dotnet ef migrations add` to scaffold from the model diff
   - Verifies all operations are additive and backwards-compatible
   - Adds idempotency guards to custom SQL
   - Separates schema and data migrations into distinct files
   - Runs the apply/rollback/reapply verification cycle

4. **Expansion migration ships in the same MR as feature code.** The migration is committed separately from application code but included in the same merge request. This ensures the schema change is reviewed alongside the code that depends on it.

5. **CI/CD applies the migration automatically.** During deployment, the pipeline runs `dotnet ef database update` (or the application calls `context.Database.Migrate()` at startup). No human intervention required.

6. **Both application versions work simultaneously.** During a rolling deployment, old pods (running the previous version) coexist with new pods (running the new version). Because expansion only adds nullable columns or columns with defaults, old code ignores the new columns and continues functioning.

### Process (Prep-Required Expansion)

1. **Spec describes schema changes AND interim code.** The Deployment Compatibility section classifies this as "Prep-required" and specifies what interim code is needed (null-safe reads, dual-writes, application-level defaults).

2. **Implementer produces interim compatibility code (Phase 2.25).** This code:
   - Makes the current application tolerant of both pre-migration and post-migration schema states
   - Uses patterns like null-safe fallbacks, dual-writes, or conditional column access
   - Is tested against both schema states
   - Ships as a separately deployable commit tagged `[prep-release]`

3. **Interim code deploys to production first.** This is the critical ordering requirement. The prep release must be running on ALL pods before the expansion migration executes. This ensures:
   - Old pods (running prep code): handle both old and new schema safely
   - During cutover: no pod is caught with incompatible code against the migrated schema

4. **Migration-author generates expansion migrations (Phase 2.5).** Same as simple expansion, but the agent additionally verifies:
   - Interim compatibility code is committed
   - The migration does not conflict with dual-write patterns
   - Deployment ordering is documented

5. **Migration + feature code deploy together (Phase 2).** Once the prep release is stable in production, the expansion migration and full feature code deploy. At this point:
   - Prep-release pods: handle new schema via their compatibility code (correct but suboptimal)
   - Feature pods: use new schema natively
   - Transition completes when all pods are on the feature release

6. **Remove interim compatibility code.** After full deployment, the dual-write/fallback code is dead weight. It can be removed:
   - In the same feature MR (if the team is confident in rapid full-fleet rollout)
   - In a follow-up MR (safer — allows rollback to prep-release state if issues arise)

### What Gets Deferred

If the feature logically requires removing old columns, renaming columns, or tightening nullability, those operations are NOT included in the expansion. Instead:
- The agent logs them in `specs/{ticket-id}/decisions.md` as deferred contraction work
- The metadata is tagged with `contraction-pending`
- The spec's follow-up checklist tracks when contraction is safe to ship

### Naming Convention

EF Core manages execution order via timestamps in the migration's Designer file. The ticket-based naming prefix satisfies the policy's traceability requirement (see `docs/policies/migration-policy.md` §6).

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

After the expansion has been running in production for at least 1 sprint and the verification checklist is satisfied.

### Prerequisites

Before running `/claire-migrate {ticket-id} --contract`, verify:

- [ ] Expansion migration has been deployed to production for >= 1 sprint
- [ ] Query logs confirm zero reads/writes to deprecated columns for >= 1 week
- [ ] No rollback to the pre-expansion state is planned
- [ ] Application code no longer references the deprecated schema elements
- [ ] The `contraction-pending` tag exists in `specs/{ticket-id}/metadata.yaml`

### Process

1. **Developer runs `/claire-migrate {ticket-id} --contract`.** This invokes the migration-author agent in contract mode.

2. **Agent reads deferred operations.** It reads `specs/{ticket-id}/decisions.md` to find the contraction decision entry listing what to remove.

3. **Agent confirms readiness.** It asks the developer to confirm the verification checklist is satisfied.

4. **Agent generates contraction migration.** It produces the destructive migration (drop columns, tighten nullability, remove indexes) with a complete Down() method that restores the expanded schema state.

5. **Agent runs apply/rollback/reapply.** Same verification cycle as expansion.

6. **Contraction ships in its own MR.** This is a separate merge request from the original feature, with its own code review cycle. The MR references the original ticket for traceability.

7. **Tag is removed.** On successful merge, `contraction-pending` is removed from the metadata.

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

### What the Pipeline Does

The deployment pipeline handles migration execution. The migration-author agent does NOT run migrations against any environment other than a local development database for verification.

**Pipeline responsibilities:**
- Runs `dotnet ef database update` using the environment-specific connection string (provided via secrets management)
- Executes migrations in order (earliest timestamp first)
- Records successful migrations in `__EFMigrationsHistory`
- On failure: the pipeline can roll back via `dotnet ef database update {PreviousMigration}`

**Pipeline does NOT:**
- Require manual console app execution
- Require a human to run SQL scripts
- Need environment-specific migration branches
- Execute data migrations separately from schema migrations (EF Core handles ordering via timestamps)

### What the Migration-Author Guarantees

Every migration produced by the agent is safe for unattended pipeline execution:

1. **Reversible** — Complete Down() method for every Up() operation
2. **Idempotent** — Conditional guards on all custom SQL; safe for retry after interrupted deployment
3. **Non-interactive** — No prompts, no user input, no manual seed data
4. **Self-contained** — No external dependencies beyond the database connection
5. **Ordered** — Timestamp-based naming ensures deterministic execution order
6. **Separated** — Schema and data in distinct files for independent rollback

### Rollback Strategy

If a deployment needs to be reverted:

1. **Application rollback:** ArgoCD (or equivalent) rolls back to the previous container image
2. **Schema rollback:** Pipeline runs `dotnet ef database update {PreviousMigration}` to revert the schema
3. **Safety:** Because expansion migrations are additive, rolling back the application WITHOUT rolling back the schema is also safe (old code simply ignores new columns)

This means application rollback is instantaneous — schema rollback is only needed if the new columns actively cause problems (e.g., trigger size, storage cost).

---

## Quick Reference

| Scenario | Command | Ships In |
|----------|---------|----------|
| Simple expansion (new columns) | `/claire-migrate TT-1234` | Same MR as feature |
| Feature needs data backfill | `/claire-migrate TT-1234` (agent separates automatically) | Same MR as feature |
| Prep-required expansion | Implementer Phase 2.25 + 2.5 | Prep MR first, then feature MR |
| Old columns ready to remove | `/claire-migrate TT-1234 --contract` | Separate follow-up MR |
| Implementer auto-generates | (automatic via Phase 2.5) | Same MR as feature |

| Migration Type | Allowed Operations | Forbidden Operations |
|----------------|-------------------|---------------------|
| Expand | Add table, add nullable column, add column with default, add index, add FK (nullable) | Drop, rename, tighten nullability, narrow type |
| Data | INSERT, UPDATE, DELETE (1,000–10,000 row batches per `docs/policies/migration-policy.md`) | CREATE, ALTER, DROP |
| Contract | Drop column/table/index, tighten nullability, rename | (all allowed — this is the cleanup phase) |

---

## Finding Pending Contraction Work

To find all specs with pending contraction migrations:

```bash
grep -rl "contraction-pending" specs/*/metadata.yaml
```

Review each spec's `decisions.md` for the verification checklist before proceeding.
