---
name: cadence-mint
description: Reserve or peek the next collision-free identifier for a prefix (PI/ADR/II/PROD/custom) using the shared, flock-atomic reserve ledger. Wraps the canonical allocator script; the ledger lives in git-common-dir so concurrent mints across linked worktrees never collide.
argument-hint: "--peek|--reserve|--seed [PREFIX] [note]"
arguments: [action, prefix, note]
allowed-tools: Read Bash
---

## Task

Allocate or inspect the next sequential identifier for `$prefix` (defaulting to `PI`) by delegating to the canonical allocator script at `.agents/skills/cadence-mint/mint-id.sh` (with `.gemini/` as the canonical Gemini/Antigravity runtime directory and `.claude/` or other CLI runtime directories projected off `.agents/` per `docs/policies/cli-runtime-adoption-policy.md`). This skill never implements counter or locking logic itself — the bash script is the single authoritative source for flock-atomic reservation, per-prefix zero-padding width, `git-common-dir` ledger path resolution, and the §10 tracker-binding check.

This skill exposes the direct, operator-facing command surface for the same underlying allocator invoked internally by `/cadence-triage`, `/cadence-archive` (`cadence-archivist`), `cadence-triage-agent`, `/cadence-adopt`, and `/cadence-upgrade`. Adopters and agents can invoke `/cadence-mint` directly whenever they need to reserve or inspect an identifier.

## Actions

- `.agents/skills/cadence-mint/mint-id.sh --peek [PREFIX]` — compute and print the next sequential identifier without modifying the ledger.
- `.agents/skills/cadence-mint/mint-id.sh --reserve [PREFIX] [note]` — atomically reserve and output the next sequential identifier (appending one auditable ledger record under an exclusive `flock`).
- `.agents/skills/cadence-mint/mint-id.sh --list [PREFIX]` — display the current reserve ledger rows (optionally filtered to `PREFIX`).
- `.agents/skills/cadence-mint/mint-id.sh --seed PREFIX N [note]` — one-time bootstrap: initialize `PREFIX`'s high-water mark to `N` (refuses if `PREFIX` already has ledger entries).
- `.agents/skills/cadence-mint/mint-id.sh --binding [CADENCE_ORG.md]` — print `bound` or `unbound` reflecting §10 External Issue Tracker Binding (used as the seed-gating predicate).

## Contract

- `--reserve` is strictly `flock`-atomic and monotonically increasing: two simultaneous invocations for the same prefix across different worktrees are guaranteed to receive **distinct** identifiers (`next = highest_for(PREFIX) + 1`), and numerical gaps are never backfilled or reused.
- The ledger file location is resolved dynamically at runtime via `git rev-parse --git-common-dir` (ensuring all linked git worktrees of a repository share one canonical ledger), never relative to the script's installation directory; in a non-git directory it falls back to a committed `.cadence/` working-tree file, and `CADENCE_LEDGER` overrides both when set.
- If `flock` is unavailable on the host or the ledger path cannot be resolved or locked, the script **fails loud** (exiting non-zero without printing an identifier) and emits a structured observability seam (`DELTA_AUDIT_GAP` / `UNSOUND_CONDITION`). When `mint-id.sh` diagnostic or `--list` output exceeds 30 lines, automatically compact it via `offload_log_triage` (`local-fast-cpu` on `:9379`, preserving raw output in `/tmp/agy-last-triage.log`). The caller MUST halt immediately on any non-zero exit and surface the error — **never** fall back to scanning `specs/`, `archive/`, or `docs/ADR/` to guess the next number, as directory scanning reintroduces the exact parallel worktree collision race this allocator eliminates.

## Example

```
/cadence-mint --reserve PI "ship the widget"
/cadence-mint --peek ADR
```
