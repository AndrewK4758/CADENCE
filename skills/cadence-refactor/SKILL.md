---
name: cadence-refactor
description: Execute wide, deterministic, behavior-preserving refactors (renames, argument/flag migrations, uniform lint/type sweeps) using exhaustive manifests, Fast-mechanical high-effort execution, log triage, and Deep-reasoning post-sweep checks.
argument-hint: "<refactor description or before -> after rule> [scope-glob]"
arguments: [transform_spec, scope]
allowed-tools: Read Write Edit Glob Grep Bash
---

## Task

Perform a wide-breadth, low-ambiguity, **strictly behavior-preserving** codebase sweep (`$transform_spec` across `$scope`) — such as renaming a variable/internal helper, adding/reordering a deterministic function argument across call sites, updating repetitive import paths, or applying uniform lint/type fixes — cleanly and completely without missing call sites, sibling scripts, tests, or documentation.

Following CADENCE tier discipline, mechanical execution uses **`Fast-mechanical` (`high` effort)** against an exhaustive pre-computed manifest and strict before/after transform rules, while **any architectural, schema, or public-contract fork halts and escalates to `Deep-reasoning` (`xhigh` effort) via `/cadence-spec`**.

## Prerequisites & Fail-Closed Escalation Guard (Mandatory Before Any Edit)

Check all four conditions BEFORE touching any source file:

1. **Dedicated worktree check:** Confirm edits execute inside a dedicated `git worktree` on a feature branch (never directly on a protected integration branch such as `develop` or `main`). Halt and prompt to cut a worktree if sitting directly on the integration branch.
2. **Surface & schema gate (Fail-Closed):** Consult `docs/policies/surface-registry.md` (if present) and `docs/policies/cadence-surfaces.md`, plus check database migrations/schemas.
   - **HALT and escalate to `/cadence-spec` (`Deep-reasoning`, `xhigh`)** — or `/cadence-migrate` for database schemas — if the proposed refactor:
     - alters any **Stable** or **Beta** public API, event schema, CLI flag, or configuration contract (compatibility/deprecation rules apply);
     - changes runtime behavior, error semantics, security/auth checks, concurrency/locking, or multi-step persistence order;
     - offers competing structural architectures where trade-offs exist.
3. **Explicit transform specification:** Confirm `$transform_spec` defines an unambiguous before -> after transformation, invariants preserved, and explicit exclusions (e.g., frozen `archive/` records, generated vendor files, or historical release notes).

## Steps

### 1. Build the exhaustive transform manifest (`local_semantic_embed` + deterministic grep/AST)

Do NOT start editing file-by-file ad hoc:
1. Run `local_semantic_embed` (`:11434`) to surface conceptually related files, configs, and sibling modules, then run exhaustive deterministic `rg` / symbol searches across:
   - Source files and tests (`rg -n <identifier>`)
   - Sibling scripts, config templates, golden fixtures, and CI/gate scripts
   - Repository documentation with **dual independent searches** (identifier matches AND prose/label claims describing the renamed element, excluding frozen `archive/` and historical release logs).
2. Check modified-file line counts against the `<400`-line Agentic Ergonomics ceiling (split helper modules cleanly if a planned mechanical addition would cross 400 lines).
3. Present the exact **Manifest & Transform Plan** (file count, targeted paths, exclusions, verification command) and confirm with the operator before applying edits.

### 2. Execute mechanical sweep (`Fast-mechanical`, `high` effort)

Apply the verified before -> after transform deterministically across every target in the manifest:
- Preserve all unrelated comments, docstrings, and formatting (`whitespace`/comment integrity).
- Never hand-wave partial sweeps ("and similar files...") — update 100% of manifest targets sequentially or in disjoint directory shards, tracking completion against the manifest checklist.
- Never alter frozen `archive/` historical files or create unrequested abstractions.

### 3. Exhaustive post-sweep verification & offload review

1. **Stale-reference zero-check:** Re-run `rg` across the entire in-scope codebase, configs, tests, and `docs/` confirming **0 unintended remaining occurrences** of the old pattern (explicitly accounting for any intentional exemptions/historical entries).
2. **Canonical verification suite:** Run the repository's canonical build, linter, typechecker, and test runner. Automatically pipe any output `>30` lines or non-zero exit through `offload_log_triage` (`:11434`, saving raw log to `/tmp/agy-last-triage.log`). Fix any failures cleanly or halt loudly.
3. **Mandatory local deep review (`offload_deep_review`):** Invoke `offload_deep_review(diff_range="<integration-branch>...HEAD", cwd="<repo-root>")` across all changed files. Verify every finding directly against code.
4. **Escalation backstop:** If verification uncovers unexpected semantic divergence, broken cross-boundary contracts, or >5 subtly coupled files, recommend running `/cadence-review` (`Deep-reasoning`, `xhigh` effort) before merging.

### 4. Report outcome

Summarize:
- Transform rule applied and manifest coverage (`X / X` target files updated, exact exclusions skipped)
- Zero-stale-reference search confirmation (`docs/` + code + tests)
- Exact test/build/typecheck commands run and observed pass counts
- `offload_deep_review` verdict and recommended next step (commit / `/cadence-review`).

## Constraints

- **Strictly behavior-preserving.** Never sneak feature changes, bug fixes unrelated to the transform, or public-surface breaks into `/cadence-refactor`.
- **Fail closed on public contracts.** Any change touching registered surfaces, schemas, or competing architectures routes to `/cadence-spec` or `/cadence-migrate`.
- **Zero partial sweeps.** Every file in the manifest is verified before claiming completion.

## Examples

```text
/cadence-refactor "Rename config key timeout_sec -> request_timeout_secs" "src/ config/ tests/"
/cadence-refactor "Update log_event(msg, lvl) -> log_event(lvl, msg) call sites" "pkg/"
```

## Local Model Offload Integration (:11434)
- Step 1 calls `local_semantic_embed` (`:11434`) to discover sibling configs, docs, and wrappers alongside `rg`.
- Step 3 routes build/test/typecheck outputs `>30` lines or non-zero exits through `offload_log_triage` (`:11434`) and runs `offload_deep_review` (`:11434`) on the full sweep diff.
