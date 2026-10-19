---
name: claire-mint
description: Reserve or peek the next collision-safe id for a prefix (PI/ADR/II/PROD/any) against the shared, flock-atomic reserve ledger. Wraps the canonical allocator sidecar; the ledger is shared by all linked worktrees of one clone so concurrent mints never collide.
argument-hint: "--peek|--reserve|--seed [PREFIX] [note]"
arguments: [action, prefix, note]
allowed-tools: Read Bash
---

## Task

Allocate an id for `$prefix` (default `PI`) by delegating to the canonical allocator at `.claude/skills/claire-mint/mint-id.sh`. The skill does not implement the allocation logic itself — the bash script is the single source of truth for the flock-atomic reserve, the per-prefix zero-pad width, the git-common-dir ledger resolution, and the §10 binding predicate.

This command is the direct, adopter-facing surface of the allocator that `/claire-triage`, `/claire-archive` (archivist), the triage-agent, `/claire-adopt`, and `/claire-upgrade` all use internally. Adopters may call it directly to reserve or inspect ids.

## Actions

- `.claude/skills/claire-mint/mint-id.sh --peek [PREFIX]` — print the next id, reserve nothing.
- `.claude/skills/claire-mint/mint-id.sh --reserve [PREFIX] [note]` — atomically reserve and print the next id (appends one auditable ledger row under a single flock).
- `.claude/skills/claire-mint/mint-id.sh --list [PREFIX]` — show the reserve ledger.
- `.claude/skills/claire-mint/mint-id.sh --seed PREFIX N [note]` — one-time: baseline a prefix's high-water to `N` (refuses an already-seeded prefix).
- `.claude/skills/claire-mint/mint-id.sh --binding [CLAIRE_ORG.md]` — echo `bound`/`unbound` for §10 (the seed-gating predicate).

## Contract

- `--reserve` is flock-atomic and monotonic: two concurrent calls on a prefix return **distinct** ids (`next = highest_for(PREFIX)+1`); gaps are never reused.
- The ledger path is resolved at runtime via `git rev-parse --git-common-dir` (shared by all linked worktrees), never relative to the script's install location; a non-git repo falls back to a committed working-tree file; `CLAIRE_LEDGER` overrides both.
- On a flock-absent host or an unresolvable ledger, the script **fails loud** (non-zero exit, no id printed) and emits a structured seam. The caller MUST halt with the error — **never** fall back to scanning `specs/`/`archive/`/`docs/ADR/`, which reintroduces the id-collision race this allocator removes.

## Example

```
/claire-mint --reserve PI "ship the widget"
/claire-mint --peek ADR
```
