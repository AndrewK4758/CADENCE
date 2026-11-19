---
name: cadence-retro
description: Synthesize cross-ticket metrics, recurring review rework, deferred follow-ups, and systemic lessons across archive/*/ records — strictly read-only by default, with confirmation-gated promotion of II-NNN/PROD-NNN insights or draft follow-up tickets
argument-hint: "[--since <N|YYYY-MM-DD>] [--include-active] [--promote]"
arguments: [options]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

## Task

Execute a cross-ticket engineering retrospective across archived CADENCE work (`archive/*/`, plus `specs/*/` when `--include-active` is supplied). Aggregate rework cycles, effort variance, unfiled `Deferred` follow-ups, and recurring failure patterns, deduplicate against `docs/agentic-sdlc/intent-insights.md` (`II-NNN`) and `production-insights.md` (`PROD-NNN`), and promote durable insights or new follow-up drafts **only** upon explicit operator confirmation.

## Steps

0. **Read-Only Telemetry Scan & Semantic Clustering (`retro_scan.py` + `local_semantic_embed`):**
   - Resolve repository root (`git rev-parse --show-toplevel` or `$PWD`) and execute:
     ```bash
     python3 .agents/skills/cadence-retro/retro_scan.py $options
     ```
     (falling back to `skills/cadence-retro/retro_scan.py` in framework-dev checkouts; piping output `>30` lines or failures via `offload_log_triage` on `:11434` when reachable, else inspecting directly).
   - Fail loudly (`exit 1`) on invalid `--since` or unreadable repository paths. When `status=empty_archive` and `--include-active` is absent, report cleanly (`0 archived tickets; nothing to synthesize`) and exit without writing any file.
   - When archived records exist and `:11434` is reachable, optionally invoke `local_semantic_embed` (`embedding` on `:11434`, `top_k=6`) across `archive/*/summary.md`, `archive/*/decisions.md`, `docs/agentic-sdlc/intent-insights.md`, and `docs/agentic-sdlc/production-insights.md` to surface multi-ticket clusters (rework themes, recurring CHORD seams, spec-to-implementation gaps; cloud-only `Grep`/`Glob` fallback when offline).

1. **Synthesize the Cross-Ticket Retrospective Report (Strictly Read-Only Default):**
   - Present a structured synthesis covering:
     1. **Tier & Stage Effort Ledger:** Ticket counts per `tier` (preserving unresolved tiers verbatim — never defaulting empty tiers to `Low`), recorded `stage_effort` sums vs `estimated_effort` (`actual_effort` variance computed strictly from recorded `metadata.yaml` ledgers, never recomputed from git commit timestamps).
     2. **Code-Review Rework & Traceability Hotspots:** Tickets requiring `>=2` `cadence-run:cycle` iterations, recurring blocking findings, or `unguarded_citation_sweeps` (`DEAD-CITATION-SWEEP: SKIPPED|MANUAL`).
     3. **Unresolved Follow-Up Debt:** `Deferred` follow-ups (`## Resolution -> Follow-ups created`) still unfiled across closed work.
     4. **Candidate Systemic Insights (Deduplicated):** Distinct multi-ticket patterns qualifying for `II-NNN` (`intent-insights.md`) or `PROD-NNN` (`production-insights.md`, honoring `field-observed` / `execution-reproduced` / `categorically-reachable` entry criteria), excluding already-recorded `Source Ticket` entries.
   - Without `--promote` (or explicit operator confirmation), **STOP cleanly after presenting the synthesis — modify ZERO files and reserve ZERO IDs.**

2. **Confirmation-Gated Promotion (Only With Explicit Human Confirmation):**
   - Present each candidate promotion (`II-NNN`, `PROD-NNN`, or follow-up draft) for explicit operator selection before writing anything.
   - **Never mutate archived ticket files** under `archive/<id>/` (`problem.md`, `spec.md`, `test-plan.md`, `decisions.md`, `summary.md` stay untouched).
   - Reserve every new insight identifier atomically via `.agents/skills/cadence-mint/mint-id.sh --reserve II` or `--reserve PROD` (`halt` if `flock`/allocator fails — never fall back to directory scanning).
   - For confirmed systemic work items, write each draft to `specs/drafts/retro-<UTC>-<N>.md` and file via `/cadence-triage --file-only <draft-path>` (never calling `mint-id.sh --reserve` directly for ticket prefixes).
   - After editing `intent-insights.md` or `production-insights.md`, verify installed governance gates when present and non-empty:
     ```bash
     ([ -s ci-templates/scripts/authored-doc-gate.sh ] && bash ci-templates/scripts/authored-doc-gate.sh)
     ([ -s ci-templates/scripts/dead-citation-gate.sh ] && bash ci-templates/scripts/dead-citation-gate.sh)
     ```

## Constraints

- Default execution is **strictly read-only**: write no files, mint no IDs, and make no tracker API calls unless the operator explicitly confirms promotions.
- Never alter immutable files inside `archive/<id>/`.
- Never recompute `actual_effort` from git history timestamps.

## Examples

```text
/cadence-retro
/cadence-retro --since 10
/cadence-retro --since 2026-09-01 --include-active
/cadence-retro --promote
```

## Local Model Offload Integration (:11434, Optional Cloud-Only Fallback)
- When `:11434` is reachable, Step 0 uses `local_semantic_embed` (`embedding` on `:11434`) to cluster recurring multi-ticket patterns across `archive/` and existing insight ledgers, and routes verbose scanner output (`>30` lines) via `offload_log_triage` (degrading cleanly to direct inspection / `Grep` when offline).
- Local coprocessors act strictly read-only (`enable_write_tools: false`).
