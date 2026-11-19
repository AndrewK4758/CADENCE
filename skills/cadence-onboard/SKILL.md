---
name: cadence-onboard
description: Consolidated repository onboarding workflow -- install or link CADENCE governance artifacts (adopt-cadence.sh, optional --linked via link-sdlc.sh --replace), populate Where/Who/Why constants via /cadence-interview plus Step 3b operator-confirmed CADENCE_ORG.md bindings, and run /cadence-doctor --check-offload. Activate when setting up CADENCE in a new or copied repository.
argument-hint: "<target-repo-root> [--linked] [--gitignore-machinery] [--claude] [--opencode] [--blitz] [--skip-interview]"
arguments: [target_and_flags]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-onboard

Onboard a repository to CADENCE end-to-end in a single command (`adopt` -> optional `--linked` framework symlinks -> `/cadence-interview` + Step 3b bindings -> `/cadence-doctor --check-offload`).

## Prerequisites & Safety Refusals

1. Parse `<target-repo-root>` (defaults to `git rev-parse --show-toplevel` only if omitted and operator explicitly confirms onboarding the current checkout). Reject remote URLs (`://` or `git@`) — clone locally first.
2. Locate `<cadence-root>` (the directory containing `skills/cadence-adopt/adopt-cadence.sh` and `import/link-sdlc.sh`). Resolve `<canonical_target>` with `realpath` / `pwd -P` and verify it is an existing directory distinct from `<cadence-root>` (`adopt-cadence.sh` refuses self-target).

## Steps

### 1. Provision adopter skeleton (`cadence-adopt`)

Execute the canonical adoption script (forwarding `--gitignore-machinery` only when supplied):

```bash
bash "<cadence-root>/skills/cadence-adopt/adopt-cadence.sh" "<canonical_target>" [--gitignore-machinery]
```

Verify core landing files (`specs/CADENCE.md`, `specs/TEMPLATE/`, `.agents/skills/`) and preserve verbatim `copied:` / `skip (exists):` output. Route >30 lines or any non-zero output through `offload_log_triage` (`:11434`).

### 2. Optional linked framework posture (`--linked`)

When `--linked` is supplied (recommended for first-party repos referencing the canonical CADENCE checkout instead of keeping static copies of agents/skills/hooks):

1. Invoke `link-sdlc.sh` with `--replace` (forwarding any requested `--claude`, `--opencode`, or `--blitz` flags):
   ```bash
   bash "<cadence-root>/import/link-sdlc.sh" "<canonical_target>" --replace [--claude] [--opencode] [--blitz]
   ```
2. Verify `.agents/agents`, `.agents/skills`, `.agents/hooks`, and `.gemini/` resolve cleanly with zero broken symlinks, while keeping repo-owned files (`AGENTS.md`, `docs/agentic-sdlc/CADENCE_ORG.md`, `docs/policies/surface-registry.md`, `specs/`, `archive/`, `CHANGELOG.md`) untouched.

### 3. Populate identity constants (`/cadence-interview`) and operational bindings

Check `docs/agentic-sdlc/CADENCE_ORG.md` for unfilled `<placeholder>` markers or table cells.
- **Step 3a (Where / Who / Why constants):** Unless `--skip-interview` was passed, run `/cadence-interview` interactively to populate repository identity constants (`Where`, `Who`, `Why`, test/surface commands).
- **Step 3b (Operator-confirmed operational bindings):** Still inside `/cadence-onboard` (unless `--skip-interview` is set or running non-interactively), interactively confirm `#branch-strategy-binding`, `#version-scheme-binding`, `#tracker-binding`, and `#id-allocation-binding`, then validate the populated file via `org-binding-resolve.sh`.
- If non-interactive or `--skip-interview` is set, leave `<placeholder>` entries intact and list the remaining markers explicitly so the operator can finish `/cadence-interview` and binding configuration before `/cadence-define`.

### 4. Health & offload verification (`/cadence-doctor --check-offload`)

Run the read-only health check against `<canonical_target>`:

```bash
bash "<cadence-root>/skills/cadence-doctor/doctor.sh" --root "<canonical_target>" --check-offload
```

Compact >30 lines or failures via `offload_log_triage` (`:11434`, raw log at `/tmp/agy-last-triage.log`) and summarize all `PASS`, `WARN`, `FAIL`, and `SKIP` counts plus the exact next command (`/cadence-define` once any remaining interview placeholders are resolved).
