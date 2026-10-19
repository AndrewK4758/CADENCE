# EF Core Migration Examples

This guide provides Entity Framework Core reference patterns that implement the mandatory database migration rules defined in `docs/policies/migration-policy.md`. Consult both documents whenever authoring or reviewing EF Core schema and data migrations under CADENCE.

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

Every schema operation declared in `Up()` must have an exact inverse operation in `Down()`:

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

EF Core's `__EFMigrationsHistory` table provides migration-level idempotency once a migration finishes — if a migration ID is already present in the history table, EF Core skips it on subsequent runs. However, **raw `migrationBuilder.Sql(...)` statements must still carry explicit existence guards** because an interrupted deployment can fail after executing custom SQL but before inserting the completion row into `__EFMigrationsHistory`.

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

**When are explicit SQL guards required?**
- Always required: any `migrationBuilder.Sql(...)` call executing DDL (`CREATE`, `ALTER`, `DROP`)
- Not required: typed fluent `MigrationBuilder` API calls (EF Core wraps and tracks these via `__EFMigrationsHistory`)
- Strongly recommended: `migrationBuilder.Sql(...)` blocks executing DML (`UPDATE`, `INSERT`, `DELETE`) so re-runs do not corrupt or duplicate rows

## Rollback Verification

Execute the three-step `apply → rollback → reapply` verification cycle using the `dotnet ef` CLI (when `cadence-implementer` or `cadence-migration-author` runs this verification, CLI logs are routed through `offload_log_triage` / `log-triage` to preserve verbatim command evidence):

```bash
# Apply the new migration
dotnet ef database update --project {project}

# Verify rollback to the previous migration
dotnet ef database update {PreviousMigrationName} --project {project}

# Re-apply to confirm idempotent behavior
dotnet ef database update --project {project}
```

All three invocations must exit zero. When your repository uses an integration test database, codify this round-trip check as an automated test:

```csharp
[Fact]
public async Task Migration_CanBeAppliedRolledBackAndReapplied()
{
    // Apply
    await _context.Database.MigrateAsync();

    // Rollback (via IMigrator.MigrateAsync("{PreviousMigrationName}"))
    // Implementation depends on test infrastructure

    // Reapply
    await _context.Database.MigrateAsync();
}
```

## Naming Convention

Name migration files using the pattern: `{Timestamp}_{TicketId}_{Description}.cs`

```
20260504120000_PROJ1234_AddOrderStatusColumn.cs
20260504120001_PROJ1234_BackfillOrderStatusFromLegacy.cs
20260504120002_PROJ1234_DropLegacyOrderStatusFlag.cs
```

Scaffold a new migration via:
```bash
dotnet ef migrations add {TicketId}_{Description} --project {project} --output-dir Migrations
```

## Separation Example

Scenario: Add a `Status` column to `Campaigns`, backfill values from the legacy `IsActive` boolean column, and later drop `IsActive` in a contraction release.

**Migration 1 — Schema (expand / additive):**
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

**Migration 2 — Data (backfill):**
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

**Migration 3 — Schema (contract / restrictive, shipped in a subsequent release):**
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
