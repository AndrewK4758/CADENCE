# Runtime-Neutral Worktree Isolation, State Reader & Cycle Ledger

Shared execution contract for multi-phase orchestrators (`/cadence-prep` and `/cadence-cycle`). Preserves identical on-disk state semantics across Antigravity (`agy`), Blitz, Gemini CLI, and headless worker agents without relying on runtime-specific CLI binaries.

---

## 1. Reading Machine State (`read_state.py`)

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Never parse `metadata.yaml` or `submission.md` cycle counts manually: agents wrap multi-line YAML scalars unexpectedly, and `read_state.py` detects ticket-ID case mismatches instead of misreporting `location=absent`. If `read_state.py` is missing or exits non-zero (`not_a_cadence_repo`, `binding_absent`, `binding_unset`, `ticket_id_case_mismatch`, `status_unreadable`), **halt** immediately citing its exact stderr line.

`read_state.py` copies in `skills/cadence-prep/scripts/` and `skills/cadence-cycle/scripts/` are maintained byte-identical (verify with `md5sum`).

---

## 2. Preflight Abort Conditions

1. **`docs/agentic-sdlc/CADENCE_ORG.md` exists** in the repo root (or ancestor). If absent, abort cleanly — not a CADENCE-governed repository.
2. **`§15 Branch-Strategy Binding` markers resolve** (`integration-branch` and `branch-naming-convention`). Never assume `main` when §15 binds `develop` or `trunk`.

---

## 3. Runtime-Neutral Worktree Isolation (Autonomous / Concurrent Agents)

Determine two facts **before** running any state mutation:

1. **Checkout topology:** check whether `PWD` is already an isolated linked worktree or the shared primary checkout:
   ```bash
   [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
     && echo "worktree_state=launch-checkout" || echo "worktree_state=in-worktree"
   ```
2. **Isolation trigger & delegation role:**
   - **Already `in-worktree`** → stay here; log the worktree path and continue. Never create nested worktrees from inside a delegated subagent.
   - **Standing in `launch-checkout` as an interactive foreground operator with no concurrent agent conflict** → stay in the current checkout when directly authorized by the user, OR create a dedicated worktree if modifying branches/files under workspace isolation rules.
   - **Standing in `launch-checkout` as an autonomous background/parallel orchestrator (or when repo policy forbids editing directly in the primary checkout)** → isolate into a dedicated linked worktree (`../worktrees/<phase>-<TICKET-ID>`) branched from `origin/<integration-branch>` before mutating files or switching branches:
     - In **Antigravity (`agy`)** when delegating implementation/spec subagents: prefer `invoke_subagent(..., Workspace="branch")` (or `git worktree add ../worktrees/<handle> origin/<integration-branch>` / dedicated branch).
     - In **shell orchestrators**: run:
       ```bash
       git worktree add -b <phase>/<type>/<TICKET-ID> ../worktrees/<handle> origin/<integration-branch>
       ```
       (or attach to the existing ticket branch if one already exists on `origin`).
     - If worktree creation is unavailable or fails when isolation is required, **halt** immediately with cause `worktree_unavailable` — never allow concurrent agents to collide on primary-checkout `HEAD`.
   - **Delegated subagent rule:** if this run was spawned inside an already-isolated workspace by a parent orchestrator, stay inside that assigned workspace; creating a nested worktree strands commits where the parent cannot see them.

Print both observed facts in the run log: `session_topology=<interactive|autonomous|subagent> worktree_state=<in-worktree|launch-checkout -> isolated-path>`.

### Mandatory Worktree Staleness Guard

Immediately before and after switching into a newly created or attached worktree (when the ticket directory exists locally), compare the full `read_state.py` `guard_tuple=` output:

- **Byte-for-byte identical `guard_tuple=`** → proceed.
- **Any field differs in `guard_tuple=`** → **halt** immediately quoting both `guard_tuple=` lines verbatim without guessing which tree is authoritative (uncommitted local artifacts, untracked `specs/drafts/`, or unpushed cycle ledger entries in the launch checkout are invisible in a fresh worktree cut from `origin/<integration-branch>`).

Never strip fields from `guard_tuple=`: it binds `location`, `status`, `spec_mr`, `merge_request`, `maintainer_approved_at`, and `ledger_cycles_completed`.

Leave isolated worktrees standing at run end when an open branch/MR awaits human review, and report the filesystem path and branch name in the run-end checklist.

---

## 4. Loop Progress Guard

Capture `guard_tuple=` before every loop iteration and re-read it immediately after. If `guard_tuple=` is unchanged after an iteration completed without reaching a terminal state → **halt immediately** citing what action was attempted, what blocked progression, and the unchanged `guard_tuple=`. Never report a progress-guard halt as normal completion.

---

## 5. Shared Cycle Ledger Contract (`cadence-run:cycle`)

`/cadence-cycle` appends a machine-readable HTML comment at the end of each review block inside `specs/<TICKET-ID>/submission.md` under `## Discussion`:

```html
<!-- cadence-run:cycle n=2 phase=code-review blocking=1 nonblocking=3 at=2026-08-21T14:02:11Z -->
```

- **Always preserve the literal marker prefix `cadence-run:cycle`** for backwards compatibility with `read_state.py` and existing ticket histories.
- Populate `at=` via `date -u +%Y-%m-%dT%H:%M:%SZ`.
- Append only the live cycle marker line — never paste instructional examples containing `cadence-run:cycle` into `submission.md`, because `read_state.py` greps `submission.md` for `cadence-run:cycle` and would miscount example prose as completed cycles.
- After every review cycle, re-run `read_state.py` and confirm `ledger_cycles_completed` incremented by `1`.
