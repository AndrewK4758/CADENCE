---
name: cadence-eject
description: Export a CADENCE-stripped deliverable copy of a repository (or validate the committed eject footprint descriptor) by wrapping the canonical cadence-eject.sh engine safely.
argument-hint: "<source-repo-root> <destination-dir> | --check-footprint"
arguments: [source_or_flag, destination]
allowed-tools: Read Bash
---

## Task

Check the repository's CADENCE eject footprint descriptor (`--check-footprint`) or produce a clean, CADENCE-stripped deliverable export (`<source-repo-root>` -> `<destination-dir>`) by wrapping the authoritative eject script (`ci-templates/scripts/cadence-eject.sh` in adopting repositories, or `processes/ci-templates/scripts/cadence-eject.sh` in CADENCE framework checkouts).

This skill intentionally omits `Edit` and `Write` in `allowed-tools` and never reimplements strip rules, footprint derivation, or co-owned JSON transforms in prose.

## Prerequisites & Safety Refusals

1. **Locate canonical script (`> 0` bytes):** resolve `ci-templates/scripts/cadence-eject.sh` (adopter) or `processes/ci-templates/scripts/cadence-eject.sh` (framework-dev). Halt loudly if absent or zero bytes.
2. **Validate mode & arguments before doing any work:**
   - **Check mode:** `--check-footprint` takes zero additional path arguments, performs zero filesystem writes, and prints the descriptor verification verdict directly.
   - **Export mode:** requires **two** local filesystem directory/target paths: `<source-repo-root>` and `<destination-dir>`.
   - **Refuse immediately:**
     - missing `<source-repo-root>` or `<destination-dir>`
     - remote URLs (`://` or `git@`)
     - `<source-repo-root>` resolving via `realpath` / `pwd -P` to the same path as `<destination-dir>`, or `<destination-dir>` nested inside `<source-repo-root>` (which would export recursively)
     - `<source-repo-root>` lacking CADENCE markers (`cadence-eject.sh` itself refuses non-CADENCE sources fail-closed).

## Steps

### 1. Handle `--check-footprint` (read-only mode)

Run:

```bash
bash <eject-script> --check-footprint
```

Stream the verdict verbatim (`OK: committed footprint descriptor is in sync with derive(sources).` or the exact `DELTA_AUDIT_GAP` / `UNSOUND_CONDITION` mismatch lines, compacting via `offload_log_triage` on `:11434` if >30 lines) and exit without modifying any file.

### 2. Inspect strip boundary & preview before exporting

Prior to invoking `<eject-script> <src> <dest>`:

1. Canonicalize `<src>` (`cd <src> && pwd -P`) and resolve target `<dest>`.
2. Run `--check-footprint` in read-only mode to confirm the committed boundary descriptor is healthy (if drifted in framework-dev, warn clearly before continuing; if unreadable, halt fail-closed).
3. Inspect the active descriptor (`processes/artifacts/footprint.generated`, `artifacts/footprint.generated`, or `--derive-adopter-footprint`) to show the operator:
   - Mode detected: `framework-dev` (strips `framework_dev`, `tree_root`, `installed`, `seed`) vs `adopter` (strips only `tree_root`, `installed`, `seed`, leaving project code untouched; transforms co-owned `.claude/settings.json` / `.mcp.json` / `opencode.json` if present)
   - Audit record output location: `${EJECT_AUDIT:-<dest>.eject-audit.txt}` (outside `<dest>` so the audit file itself is not shipped as deliverable content)
   - Existing destination status: if `<dest>` already exists and is non-empty, warn prominently.
   - Explicit limitation note: **BL-003 — `cadence-eject.sh` omits `.git/` from `<dest>` cleanly, and does NOT rewrite git history** in `<src>`.
4. Ask explicit confirmation before writing:
   **"Export CADENCE-stripped deliverable from `<canonical_src>` to `<canonical_dest>`? (yes/no)"**
   Wait for exact affirmative confirmation; halt with zero writes on any other reply.

### 3. Execute export and independently verify `<dest>`

Run:

```bash
bash <eject-script> "<canonical_src>" "<canonical_dest>"
```

If output exceeds 30 lines or the script exits non-zero, compact the log via `offload_log_triage` (`:11434`, saving raw log to `/tmp/agy-last-triage.log`) and surface the exact seam/failure verbatim without claiming success.

After exit `0`, independently verify on disk at `<canonical_dest>`:
- none of `.agents`, `.gemini`, `CADENCE_DIRECTIVES.md`, or `ci-templates` exist under `<canonical_dest>`
- the audit file (`${EJECT_AUDIT:-<canonical_dest>.eject-audit.txt}`) exists and is non-empty
- summarize `N stripped, M shipped` counts verbatim from script output plus the audit file path.

## Constraints

- **Wrap, never reimplement.** Never copy or delete files manually with `cp`, `rm`, or Write/Edit tools; all stripping and co-owned config transforms belong strictly to `cadence-eject.sh`.
- **Refuse in-place or nested destination.** Never overwrite `<src>` or write inside `<src>`.
- **Preserve audit boundary.** Keep the audit file outside `<dest>` per DEC-008.

## Examples

```text
/cadence-eject --check-footprint
/cadence-eject /path/to/my-repo /tmp/my-repo-client-handoff
```

## Local Model Offload Integration (:11434)
- Verbose eject failure logs or footprint diffs exceeding 30 lines route through `offload_log_triage` (`:11434`), keeping raw logs at `/tmp/agy-last-triage.log`.
