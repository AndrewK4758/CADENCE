---
name: cadence-build
description: Drive a CADENCE ticket through implementation (including schema migrations when declared) and code-review cycles and stop — pick up after the approved spec landed on the integration branch (or at triaged for Trivial/Low), iterate /cadence-implement (plus /cadence-migrate when schema changes exist) and /cadence-review until blocking issues reach zero, open the implementation MR, record it in metadata.yaml, and publish it ready for review. Never invokes /cadence-maintain, monitors merge, or runs /cadence-archive.
argument-hint: "<ticket-id> [--with-migrations]"
arguments: [ticket_id]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-build

Drive one established ticket from **approved spec landed on `<integration-branch>`** (or `triaged` at Low/Trivial) up to **having its implementation MR open, recorded in `merge_request`, and published ready for review**, then stop.

This orchestrator sits strictly between `/cadence-define` and `/cadence-maintain` / `/cadence-close`. Never invoke `/cadence-triage`, `/cadence-maintain`, `/cadence-close`, or `/cadence-archive`, never accept a free-text problem statement, and never monitor or self-merge the MR after `ready_mr.sh` confirms it is ready.

> **Shared Worktree, State Reader, Progress-Guard & Ledger Contract:** Read `.agents/skills/cadence-build/references/worktree-and-ledger.md` before executing Step 3. Preserve the literal shared HTML comment marker prefix **`cadence-run:cycle`** in `submission.md` so `read_state.py` counts cycles identically across orchestrators; never repurpose `spec_mr` or `merge_request`.

## Reading State & Preflight

```bash
python3 .agents/skills/cadence-build/scripts/read_state.py <TICKET-ID> \
  || python3 skills/cadence-build/scripts/read_state.py <TICKET-ID>
```

Never parse `metadata.yaml` or cycle counts manually. `read_state.py` validates `CADENCE_ORG.md` and `#branch-strategy-binding` markers (`integration-branch` and `branch-naming-convention`) and halts on ticket-ID case mismatches or absent `read_state.py` (`read_state_unavailable`).

## Step 0 — Optional Local Offload (:11434, Cloud-Only Fallback)

1. **Test/Build Log Compaction (`offload_log_triage`):** When `:11434` is reachable, pipe test, build, linter, or gate output exceeding 30 lines through `offload_log_triage` (`:11434`, raw log saved to `/tmp/agy-last-triage.log`; else inspect directly).
2. **Pre-Review Mechanical Diff Scan (`offload_deep_review`):** When `:11434` is reachable, before creating/updating the implementation MR and at Step 0 of each `/cadence-review` cycle, invoke `offload_deep_review` (`diff_range="<integration-branch>...HEAD"`, `cwd`) to pre-check the `<400`-line file ceiling, comment discipline, and CHORD seams (degrading cleanly to direct review if unavailable).

## Step 1 — Resolve the Argument

- **Ticket-id shaped + `specs/<id>/` exists** → proceed to Step 2.
- **Ticket-id shaped + `archive/<id>/` exists** → clean exit (`nothing to do`).
- **Ticket-id shaped + neither directory exists** → **halt** (`ticket_not_established`); direct operator to `/cadence-triage` or `/cadence-define`.
- **Not ticket-id shaped** → **halt** (`not_a_ticket_id`), quoting input verbatim.

## Step 2 — Admission Gate

Run `read_state.py` and evaluate `status` jointly with `tier`:

| `status` | Admitted? |
|---|---|
| `triaged` | **ONLY if `tier` ∈ {`Trivial`, `Low`}** (`Medium`/`High` -> *not yet* in window; direct to `/cadence-define`) |
| `spec-approved` | **ONLY after verifying `spec.md` landed on `origin/<integration-branch>`** (for `Medium`/`High`) |
| `in-progress` | yes |
| `in-review` | **ONLY while implementation MR is not yet both recorded and published ready** (Trivial skips cycle check) |
| `draft`, `spec-in-review` | no — *not yet* in window; direct to `/cadence-define` |
| `merged`, `archived` | no — *already past* window (`nothing to do`); direct to `/cadence-archive` or report done |
| unreadable, empty, or unknown | **halt**, quoting raw `status` / `tier` verbatim (never default unknown tier to `Low`) |

- **Gate at `spec-approved` (Medium/High):** Run `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/` (corroborating `SPEC_MR` when online). Because `/cadence-define` writes `status: spec-approved` into the spec branch commit before merging, `spec.md` absent from `origin/<integration-branch>` means **not yet** admitted — direct operator to merge the spec MR via `/cadence-define` first, never cut an implementation branch against an unmerged spec.
- **Gate at `in-review`:** If `merge_request` is populated, check `gh pr view "$MERGE_REQUEST" --json state,isDraft,url` (or `glab mr view "$MERGE_REQUEST" --output json` on GitLab): `OPEN` + `isDraft: false` -> run the *Optional Watch Handoff Prompt* below and exit cleanly directing to `/cadence-close` (or `/cadence-maintain`); `MERGED` -> clean exit noting stale `status` ready for `/cadence-archive`; `CLOSED` -> **halt**; offline -> inspect local `ledger_cycles_completed` & `submission.md` and avoid redundant cycles if latest blocking count is `0`.

## Step 3 — State Loop

Per `.agents/skills/cadence-build/references/worktree-and-ledger.md`, verify runtime-neutral worktree isolation + `guard_tuple=` staleness, read state via `read_state.py`, and enforce the **loop progress guard** every iteration.

### The Trivial Path
`/cadence-implement` refuses `tier: Trivial`. Execute directly in this run without handing back a to-do list:
1. Cut branch per `#branch-strategy-binding` from `origin/<integration-branch>`, apply the Trivial edit, and log the ad-hoc path in `specs/<TICKET-ID>/decisions.md`.
2. Push, open draft PR/MR targeting `<integration-branch>` (`gh pr create --draft` or `glab mr create --draft`), record `merge_request` and `status: in-review` in `metadata.yaml`, commit, and push.
3. Publish via *Finishing the Implementation MR* (run zero `/cadence-review` cycles and zero `cadence-run:cycle` ledger entries).

### Once-Per-Run Sprint Confirmation (Low / Medium / High)
Resolve `#sprint-enforcement-binding` once before Cycle 1 (keeping `#integration-branch-enforcement` synchronized with `/cadence-implement`) so the operator is never prompted repeatedly across cycles:
```bash
( [ -x ci-templates/scripts/org-binding-resolve.sh ] \
  && bash ci-templates/scripts/org-binding-resolve.sh --sprint <PREFIX> \
  || bash processes/ci-templates/scripts/org-binding-resolve.sh --sprint <PREFIX> )
```
Halt fail-closed on missing/unreadable `org-binding-resolve.sh` or any non-zero exit (including `sprint.binding.form_removed` / `sprint.binding.enabled_without_tracker`).
- `enabled=no` → prompt operator once (`Confirm`).
- `enabled=yes` → run resolved `<skill> sprint-check <TICKET-ID>` once (`in-sprint` → `Proceed`; `not-in-sprint` → **halt**; `inconclusive` → `Block` **halt** or `Confirm` prompt once).
- On `Confirm`: explicit `yes` required (no/empty/unattended -> **halt**); write dated confirmation + resolved git/OS operator identity to `specs/<TICKET-ID>/decisions.md` **before Cycle 1**, then relay `yes` citing that entry during each cycle unless verdict shifts to `Block` (`not-in-sprint`).

### Implement / Review Cycle Loop (Cap = 4)
1. **Starting cycle count:** read `ledger_cycles_completed` from `read_state.py` (never count `stage_effort`; fall back to counting verdict blocks in `submission.md` only if legacy ticket has `0` markers). Check consistency between marker count and verdict block count — **halt** if they diverge.
2. **Each iteration:**
   - Invoke `/cadence-implement <TICKET-ID>` (relaying the run-level sprint confirmation if `Confirm`).
   - **Schema migration check (`spec.md` or `--with-migrations`):** Whenever `--with-migrations` is supplied or `specs/<TICKET-ID>/spec.md` declares database/schema migrations (`expand`/`contract`), invoke `/cadence-migrate <TICKET-ID>` (`cadence-migration-author`) immediately after `/cadence-implement` produces domain/entity changes so reversible expand migrations and apply/rollback/reapply verification land cleanly before code review.
   - If `merge_request` is still empty, immediately push and open the implementation PR/MR **as a draft** targeting `<integration-branch>` (`gh pr create --draft` / `glab mr create --draft`), record `merge_request` in `metadata.yaml`, commit, and push (keeps draft until blocking == 0).
   - Invoke `/cadence-review <TICKET-ID>` (which runs `verify-facts.sh --trace`, evaluates `security-trigger.sh` and `breaker-trigger.sh`, and dispatches `cadence-security-auditor` and strictly zero-spec `cadence-breaker` alongside `cadence-reviewer` whenever triggered -- honoring Pre-Gate-1 `cadence-spec-challenger` rulings on escalated spec fixes when invoked via `/cadence-spec`), **holding** non-blocking follow-up candidates during the loop (see below).
   - Append `<!-- cadence-run:cycle n=<N> phase=code-review blocking=<B> nonblocking=<NB> at=<UTC> -->` to `submission.md` `## Discussion`, commit, push, and verify `read_state.py` `ledger_cycles_completed` incremented by `1`.
   - **If `blocking == 0`:** exit loop -> for **Low** tier, reconcile & decide held follow-ups first -> run *Finishing the Implementation MR*.
   - **If `blocking > 0`:** do **not** touch non-blocking suggestions; check cap (`4` total cycles). If `>= 4` with `blocking > 0`, **pause and prompt operator** with cycle count + latest blocking findings to either authorize `K` extra cycles (logging verbatim prompt + reply + `K` in `decisions.md` scoped to this run only) or stop (unattended -> stop cleanly, never self-authorize a 5th cycle).

### Held Follow-Ups: One Consolidated Decision at the Gate
- **During each cycle:** intercept `/cadence-review` Step 6c before filing/declining, list each candidate under `## Discussion` with `/cadence-triage --file-only specs/drafts/<TICKET-ID>-held-c<n>-<k>.md` (write scratch file only when confirmed), and maintain a single consolidated line in `submission.md` `## Resolution` -> `Follow-ups created`:
  `Deferred -- held for the maintainer gate: <N> candidates from code-review cycles <list>, held because later cycles can change them; candidates and their exact filing commands are in ## Discussion.`
  (Verify `/cadence-review` did not overwrite it with `Declined`/`none owed`.)
- **Medium / High:** leave the `Deferred -- held for the maintainer gate:` line intact for `/cadence-maintain`.
- **Low (when `blocking == 0`):** reconcile every held candidate against `HEAD` + `specs/`/`archive/` (`local_semantic_embed` / `repo-scout`) as *file as written*, *file as rewritten*, *decline, resolved*, or *decline, duplicate*; prompt once -> file confirmed items via `/cadence-triage --file-only`, record final canonical lines (`after final code review`) replacing the held line, commit, and push (leave `Deferred -- held...` untouched if no interactive operator is reachable).

## Finishing the Implementation MR

Before calling `ready_mr.sh` (for Low, Medium, or High), run `(.agents/skills/cadence-certainty/certainty-gate.sh --stage review [--strictness halt|escalate] <TICKET-ID> || skills/cadence-certainty/certainty-gate.sh --stage review [--strictness halt|escalate] <TICKET-ID>)` (passing `--strictness` only when explicitly requested by the operator): `exit 1` -> remediate in cycle; `exit 2` -> pause and prompt the operator (selecting strictness if `completeness_strictness_unconfigured` fired, and recording rulings for any other escalation triggers in `decisions.md`) before publishing ready.

```bash
bash .agents/skills/cadence-build/scripts/ready_mr.sh <pr-url-or-number> \
  || bash skills/cadence-build/scripts/ready_mr.sh <pr-url-or-number>
```
Exit `0`: quote verbatim `ready_mr:` line, verify `metadata.yaml` `merge_request` equals `url=` (commit/push if reconciled), present the Run-End Checklist, run the *Optional Watch Handoff Prompt* below, and **stop immediately** unless explicitly confirmed (never self-merge or auto-monitor merge). Name `/cadence-close <TICKET-ID>` (or `/cadence-maintain <TICKET-ID>`) as the next step. Exit `2`: **halt** citing MR and failure cause.

### Optional Watch Handoff Prompt
`/cadence-build` owns the single watch prompt for this run (inner `/cadence-implement` and `/cadence-review` cycles skip their standalone watch prompts while running inside `/cadence-build`). Whenever the implementation MR is open and ready on the forge and an interactive operator is present, ask:
> `Invoke /cadence-watch <TICKET-ID> now to monitor PR reviews, CI, merge, and bound tracker comments? (watch = --watch live poll / once = --once single check / no = stop here; or use /schedule for recurring --once checks)`
Invoke `/cadence-watch <TICKET-ID> --watch` or `/cadence-watch <TICKET-ID> --once` **only** on explicit confirmation (`watch` / `once`); if declined or non-interactive/unattended, stop immediately with zero polling.

## Run-End Checklist (Every Exit Path)

1. **Terminal outcome:** `implementation MR open, recorded and ready` | `nothing to do` | `cycle cap reached awaiting authorisation` | `halt` (exact state & cause).
2. **Verbatim `ready_mr:` line** + confirmation `merge_request` matches `url=`.
3. **Cycle count summary:** prior cycles, cycles run this invocation, final `blocking`/`nonblocking`.
4. **Session topology & worktree status** (`worktree_state`, left-standing path & branch).
5. **Stopping reason & next actor** (`/cadence-close <TICKET-ID>`, `/cadence-maintain <TICKET-ID>`, opt-in `/cadence-watch <TICKET-ID>` handoff, or unblock action).
6. **Sprint-enforcement record** (`org-binding-resolve.sh --sprint` output, single-run confirmation or `in-sprint`).
7. **Held follow-up disposition summary** (held count at Medium/High, or final Low-tier gate dispositions).
