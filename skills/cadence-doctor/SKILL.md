---
name: cadence-doctor
description: Run a strictly read-only CADENCE governance, binding, footprint, gate, and ticket health audit using the canonical doctor script and report actionable remediations.
argument-hint: "[--ticket <id>] [--check-offload] [--full]"
arguments: [options]
allowed-tools: Read Glob Grep Bash
---

## Task

Execute a strictly **read-only** diagnostic audit of the current CADENCE repository (either an adopting repository or a CADENCE core framework checkout) by wrapping `.agents/skills/cadence-doctor/doctor.sh`. This skill inspects installation linkage, organization bindings (`CADENCE_ORG.md`), authoring `<400`-line compliance, eject footprint freshness, allocator reachability, and installed governance gate scripts — surfacing exact failures and remediations without modifying any repository file.

Its `allowed-tools` intentionally omits `Write` and `Edit`: `/cadence-doctor` diagnoses issues and never mutates code, specs, or ledgers silently.

## Steps

### 1. Resolve options and locate the script

Parse `$options`:
- Pass through `--ticket <id>` when auditing a specific ticket's tier artifacts (`verify-spec.sh`, `verify-facts.sh` including `--rulings` and post-implementation `--trace`, or `ac-classify.sh` for Low tier).
- Pass through `--check-offload` when the operator asks to verify the local hardware coprocessor endpoint (`127.0.0.1:11434`).
- Pass through `--full` only in a CADENCE framework-dev checkout to include `tests/run-cadence-tests.sh`.
- Reject any unknown flag cleanly rather than guessing.

Resolve the repository root via `git rev-parse --show-toplevel` (falling back to `$PWD`) and confirm the canonical script exists and is non-empty:
- `.agents/skills/cadence-doctor/doctor.sh` (or `skills/cadence-doctor/doctor.sh` inside core development checkouts).
- Treat an absent or 0-byte script as a hard failure (`UNSOUND_CONDITION`), never a silent pass.

### 2. Execute the read-only health audit

Run:

```bash
bash .agents/skills/cadence-doctor/doctor.sh $options
```

**Automatic local offload compaction (`offload_log_triage`):** Whenever `doctor.sh` (especially with `--full`) exits non-zero or produces output exceeding 30 lines, route the output through `offload_log_triage` (`local-coprocessor` on `:11434`, saving the full raw log to `/tmp/agy-last-triage.log`) before summarizing.

### 3. Interpret outcomes and present actionable remediations

Summarize every `PASS`, `WARN`, `FAIL`, and explicit `SKIP` line accurately (never collapsing `SKIP` into `PASS`, and never hiding warnings):

- **`broken runtime symlink` / `directives missing`:** instruct the operator to re-link or run `/cadence-upgrade --repair`.
- **`CADENCE_ORG.md` placeholders (`WARN`):** recommend running `/cadence-interview` to populate `<placeholder>` cells in `Where`/`Who`/`Why`.
- **`marker ... missing or placeholder` / `org-binding-resolve` failure:** point to the exact `#*-binding` section in `docs/agentic-sdlc/CADENCE_ORG.md`.
- **`line ceiling >=400L`:** identify the exact file and line count under Pillar 3 (`Agentic Ergonomics`) so modules can be split cleanly.
- **`cadence-eject --check-footprint` drift:** explain which committed footprint row diverged from sources (never suggest editing `footprint.generated` by hand).
- **`authored-doc-gate` / `dead-citation-gate` / `chaos-citation-gate` failure:** list exact `file:line` findings and whether remediation belongs to `/cadence-archive` disposition (`REPOINT`/`EXEMPT`) or draft editing.
- **0-byte gate script failure:** flag immediately as a truncated/corrupted gate file (`exit 1`) requiring restoration.
- **`--ticket <id>` failures:** route to `/cadence-triage <id>` (if `tier` unset), `/cadence-spec <id>` (if `spec.md`/`verify-spec` fails), or `verify-facts.sh` citations.
- **`local-offload` unreachable (`--check-offload`):** instruct checking `systemctl --user status local-ai-offload.service` on `:11434`.

## Constraints

- **Strictly read-only.** Never modify files, run `--reserve`, modify ledgers, or auto-fix failing checks during `/cadence-doctor`.
- **Zero silent skips.** Any gate not runnable (e.g., `dead-citation-gate` without `archive/`, or absent optional script) stays labeled `SKIP` with its reason; a 0-byte gate script is always `FAIL`.
- **Provider-neutral & single source of truth.** Never duplicate gate logic inside this markdown file; `doctor.sh` wraps existing repository gate scripts directly.

## Examples

```text
/cadence-doctor
/cadence-doctor --ticket BTG-142
/cadence-doctor --check-offload
/cadence-doctor --full
```

## Local Model Offload Integration (:11434)
- Output exceeding 30 lines or any non-zero gate exit routes automatically through `offload_log_triage` (`:11434`), keeping raw diagnostics at `/tmp/agy-last-triage.log`.
- `--check-offload` verifies `127.0.0.1:11434/health` without mutating service configuration.
