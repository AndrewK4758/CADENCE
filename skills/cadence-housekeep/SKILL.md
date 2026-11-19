---
name: cadence-housekeep
description: Consolidated repository hygiene & maintenance workflow — run read-only /cadence-doctor (--check-offload, optional --full), run read-only /cadence-retro cross-ticket synthesis (confirmation-gated --promote), and optionally run confirmation-gated /cadence-release when --with-release is passed and doctor passes cleanly. Activate for periodic repo health checks, retrospectives, or release readiness.
argument-hint: "[--since <N>] [--include-active] [--full] [--promote] [--with-release [major|minor|patch]]"
arguments: [options]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-housekeep

Run periodic CADENCE repository maintenance in one command: **Health Audit (`/cadence-doctor`) -> Cross-Ticket Retrospective (`/cadence-retro`) -> Optional Confirmation-Gated Release (`/cadence-release`)**.

Defaults strictly to **read-only diagnostics and synthesis**. No insights are promoted, no IDs are reserved, and no release is cut without explicit operator flags and interactive confirmations.

## Steps

### 1. Governance, Gate & Offload Health (`/cadence-doctor`)

Execute the canonical read-only diagnostic wrapper (`--full` only inside a CADENCE framework checkout):

```bash
bash .agents/skills/cadence-doctor/doctor.sh --check-offload [--full] \
  || bash skills/cadence-doctor/doctor.sh --check-offload [--full]
```

When `:11434` is reachable, route >30 lines or non-zero exits through `offload_log_triage` (`:11434`, raw log in `/tmp/agy-last-triage.log`; else inspect directly). Preserve all `PASS`, `WARN`, `FAIL`, and `SKIP` counts accurately.

### 2. Cross-Ticket Retrospective (`/cadence-retro`)

Run read-only quantitative scan + optional semantic pattern clustering (`local_semantic_embed` on `:11434` when reachable, else direct text clustering):

```bash
python3 .agents/skills/cadence-retro/retro_scan.py [--since <N>] [--include-active] \
  || python3 skills/cadence-retro/retro_scan.py [--since <N>] [--include-active]
```

Report review rework hotspots, stage effort variance vs estimates, `Deferred` follow-ups, `DEAD-CITATION-SWEEP: SKIPPED` gaps, and deduplicated insight candidates against `II-*`/`PROD-*` registers.
- Never reserve IDs (`mint-id.sh --reserve`) or mutate `intent-insights.md` / `production-insights.md` unless `--promote` was passed **and** the operator explicitly confirms the exact candidate list. Never mutate immutable `archive/<id>/` files.

### 3. Optional Release Gate (`--with-release [major|minor|patch]`)

Only when `--with-release` is passed:
1. Require **zero** `FAIL` verdicts from Step 1 (`/cadence-doctor`). If Step 1 exited non-zero, **halt** before invoking `/cadence-release` and list blocking failures.
2. Check `CHANGELOG.md` `## [Unreleased]` is non-empty; if empty, report `nothing to release` cleanly without mutating files.
3. Delegate to `/cadence-release [major|minor|patch]` (preserving both interactive operator confirmation checkpoints before modifying files and before pushing tags/commits).
