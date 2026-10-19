# EF Core Migration Examples

This document provides Entity Framework Core-specific guidance for implementing the requirements in `docs/policies/migration-policy.md`. Reference both documents when working with EF Core migrations.

## Mapping Policy Concepts to EF Core

| Policy term | EF Core equivalent |
|---|---|
| Forward migration | `Up()` method |
| Reverse migration | `Down()` method |
| Migration tool CLI | `dotnet ef` |
| Apply migration | `dotnet ef database update` |
| Roll back to previous | `dotnet ef database update {PreviousMigrationName}` |
| Migration history/tracking | `__EFMigrationsHistory` table |

## Reversibility: Up() and Down()

Every operation in `Up()` must have a corresponding reversal in `Down()`:

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.CreateTable(
        name: "Campaigns",
        columns: table => new
        {
            Id = table.Column<int>(nullable: false)
                .Annotation("SqlServer:Identity", "1, 1"),
            Name = table.Column<string>(maxLength: 200, nullable: false),
            Status = table.Column<string>(maxLength: 50, nullable: false)
        },
        constraints: table => table.PrimaryKey("PK_Campaigns", x => x.Id));

    migrationBuilder.CreateIndex(
        name: "IX_Campaigns_Status",
        table: "Campaigns",
        column: "Status");
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.DropIndex(
        name: "IX_Campaigns_Status",
        table: "Campaigns");

    migrationBuilder.DropTable(name: "Campaigns");
}
```

### Operation Reversal Reference

| Up() operation | Down() reversal |
|---|---|
| `migrationBuilder.CreateTable(...)` | `migrationBuilder.DropTable(...)` |
| `migrationBuilder.AddColumn(...)` | `migrationBuilder.DropColumn(...)` |
| `migrationBuilder.CreateIndex(...)` | `migrationBuilder.DropIndex(...)` |
| `migrationBuilder.AddForeignKey(...)` | `migrationBuilder.DropForeignKey(...)` |
| `migrationBuilder.RenameColumn(...)` | `migrationBuilder.RenameColumn(...)` (reversed args) |
| `migrationBuilder.RenameTable(...)` | `migrationBuilder.RenameTable(...)` (reversed args) |
| `migrationBuilder.AlterColumn(...)` | `migrationBuilder.AlterColumn(...)` (original type) |
| `migrationBuilder.Sql(...)` | `migrationBuilder.Sql(...)` (reversal SQL) |

## Idempotency

EF Core's `__EFMigrationsHistory` table provides migration-level idempotency — if the migration is recorded as applied, EF will skip it. However, **custom `Sql()` blocks must be independently guarded** because a migration can be partially applied if interrupted between the SQL execution and the history table insert.

```csharp
// Guarded column addition
migrationBuilder.Sql(@"
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('dbo.Campaigns') AND name = 'NewColumn'
    )
    BEGIN
        ALTER TABLE dbo.Campaigns ADD NewColumn NVARCHAR(100) NULL;
    END
");

// Guarded index creation
migrationBuilder.Sql(@"
    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes WHERE name = 'IX_Campaigns_NewColumn'
    )
    BEGIN
        CREATE INDEX IX_Campaigns_NewColumn ON dbo.Campaigns (NewColumn);
    END
");

// Guarded data backfill (in a separate data migration)
migrationBuilder.Sql(@"
    UPDATE dbo.Campaigns
    SET NewColumn = 'DefaultValue'
    WHERE NewColumn IS NULL;
");
```

**When are guards required?**
- Always required: any `migrationBuilder.Sql(...)` block with DDL
- Not required: fluent `MigrationBuilder` methods (EF handles idempotency via the history table)
- Recommended: `Sql()` blocks with DML that should not run twice (e.g., data transforms)

## Rollback Verification

Use the `dotnet ef` CLI to perform the apply-rollback-reapply cycle:

```bash
# Apply the new migration
dotnet ef database update --project {project}

# Verify rollback to the previous migration
dotnet ef database update {PreviousMigrationName} --project {project}

# Re-apply to confirm idempotent behavior
dotnet ef database update --project {project}
```

All three commands must succeed. If using a test database in integration tests, automate this cycle:

```csharp
[Fact]
public async Task Migration_CanBeAppliedRolledBackAndReapplied()
{
    // Apply
    await _context.Database.MigrateAsync();

    // Rollback (requires custom tooling or raw SQL to remove from history)
    // Implementation depends on test infrastructure

    // Reapply
    await _context.Database.MigrateAsync();
}
```

## Naming Convention

Follow the pattern: `{Timestamp}_{TicketId}_{Description}.cs`

```
20260504120000_PROJ1234_AddOrderStatusColumn.cs
20260504120001_PROJ1234_BackfillOrderStatusFromLegacy.cs
20260504120002_PROJ1234_DropLegacyOrderStatusFlag.cs
```

Generate migrations using:
```bash
dotnet ef migrations add {TicketId}_{Description} --project {project} --output-dir Migrations
```

## Separation Example

Feature: Add a `Status` column to `Campaigns`, backfill from a legacy `IsActive` flag, then drop the flag.

**Migration 1 — Schema (additive):**
```csharp
// 20260504120000_PROJ1234_AddOrderStatusColumn.cs
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.AddColumn<string>(
        name: "Status",
        table: "Campaigns",
        maxLength: 50,
        nullable: true);  // Nullable initially for backfill
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.DropColumn(name: "Status", table: "Campaigns");
}
```

**Migration 2 — Data:**
```csharp
// 20260504120001_PROJ1234_BackfillOrderStatus.cs
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.Sql(@"
        UPDATE dbo.Campaigns
        SET Status = CASE WHEN IsActive = 1 THEN 'Active' ELSE 'Inactive' END
        WHERE Status IS NULL;
    ");
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.Sql(@"
        UPDATE dbo.Campaigns SET Status = NULL;
    ");
}
```

**Migration 3 — Schema (restrictive, later release):**
```csharp
// 20260601120000_PROJ1234_MakeStatusNonNullableDropIsActive.cs
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.AlterColumn<string>(
        name: "Status",
        table: "Campaigns",
        maxLength: 50,
        nullable: false,
        defaultValue: "Inactive");

    migrationBuilder.DropColumn(name: "IsActive", table: "Campaigns");
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.AddColumn<bool>(
        name: "IsActive",
        table: "Campaigns",
        nullable: false,
        defaultValue: false);

    migrationBuilder.AlterColumn<string>(
        name: "Status",
        table: "Campaigns",
        maxLength: 50,
        nullable: true);
}
```

## Large Table Safety in EF Core

```csharp
// Online index creation (SQL Server)
migrationBuilder.Sql(@"
    CREATE INDEX IX_Campaigns_Status
    ON dbo.Campaigns (Status)
    WITH (ONLINE = ON);
");

// Batched data migration
migrationBuilder.Sql(@"
    DECLARE @BatchSize INT = 5000;
    DECLARE @RowsAffected INT = 1;

    WHILE @RowsAffected > 0
    BEGIN
        UPDATE TOP (@BatchSize) dbo.Campaigns
        SET Status = 'Active'
        WHERE Status IS NULL AND IsActive = 1;

        SET @RowsAffected = @@ROWCOUNT;
    END
");

// Non-nullable column with default (safe for populated tables)
migrationBuilder.AddColumn<string>(
    name: "Status",
    table: "Campaigns",
    maxLength: 50,
    nullable: false,
    defaultValue: "Draft");
```
