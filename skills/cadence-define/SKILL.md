---
name: cadence-define
description: Advance a CADENCE ticket (or raw problem with --propose) from intake through specification approval and stop — optionally run /cadence-propose for new ideas, then run /cadence-triage, /cadence-elicit, and /cadence-spec, resolve open specification questions interactively, open the spec-approval MR, record it in metadata.yaml, and publish it ready for review — without monitoring the MR or starting implementation. Activate when the user wants a ticket groomed and specced up to human spec review (or triaged at Low/Trivial). Declines cleanly with zero mutations when a ticket is already past spec approval.
argument-hint: "[--propose] <ticket-id-or-problem>"
arguments: [target]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-define

Advance a single ticket from intake/specification state to **having its spec-approval MR open, recorded in `spec_mr`, and published ready for human review**, then stop. (For Low and Trivial tickets, where policy requires no specification, stop after triage — see *Stopping at Low and Trivial*.)

This orchestrator stops strictly before implementation. If you are ever about to invoke `/cadence-build`, `/cadence-implement`, `/cadence-review`, `/cadence-close`, `/cadence-maintain`, or `/cadence-archive`, halt immediately and report that boundary.

**On-disk artifacts are the program counter.** Reconstruct all state from `metadata.yaml`, `submission.md`, and the forge via `read_state.py` — never cache state only in memory. Marking the spec MR ready for review via `ready_mr.sh` is `/cadence-define`'s terminal act; never poll or monitor the merge afterward.

> **Shared Worktree, State Reader & Progress-Guard Contract:** Read `.agents/skills/cadence-build/references/worktree-and-ledger.md` before executing Step 3 (also handles runtime-neutral worktree isolation, `guard_tuple=` staleness checks, and preflight aborts).

## Reading State & Preflight

```bash
python3 .agents/skills/cadence-define/scripts/read_state.py <TICKET-ID> \
  || python3 skills/cadence-define/scripts/read_state.py <TICKET-ID>
```

Never parse `metadata.yaml` by hand (`read_state.py` joins wrapped scalars and halts on ticket-ID case mismatches). If `read_state.py` is absent, halt citing `read_state_unavailable`. If `docs/agentic-sdlc/CADENCE_ORG.md` or `§15 Branch-Strategy Binding` fails, `read_state.py` exits non-zero with the exact cause — always abort rather than hardcoding `main`.

## Step 0 — Automatic Local Offload (`local_semantic_embed` & `offload_log_triage`)

1. **Pre-Discovery (`local_semantic_embed` / `repo-scout`):** Before broad reads during intake triage (`draft`), probe grounding (`triaged` -> `/cadence-elicit`), or specification authoring (`triaged` -> `/cadence-spec`), run `local_semantic_embed` (`:11434`, 0 MB VRAM) or `repo-scout` (`local-coprocessor` tier) over `specs/`, `archive/`, `docs/agentic-sdlc/*-insights.md`, and candidate symbols.
2. **Gate Failure Compaction (`offload_log_triage`):** Route non-zero output (>30 lines) from `verify-spec.sh` or `verify-facts.sh` through `offload_log_triage` (`:11434`, raw log saved to `/tmp/agy-last-triage.log`).

## Step 1 — Resolve the Argument

- **Ticket-id shaped** (`PREFIX-123`) **with `specs/<id>/` or `archive/<id>/` locally** → proceed to Step 2.
- **Ticket-id shaped with neither directory locally** (tracker-first intake) → inspect `CADENCE_ORG.md` §9 *before* delegating:
  - **Live tracker bound** → invoke `/cadence-triage <TICKET-ID>` (one-time seed-read), then enter Step 2 with `<TICKET-ID>`. Surface any tracker fetch failure verbatim.
  - **`Bound tracker(s): None`** → **halt** with `no_bound_tracker` citing `CADENCE_ORG.md` §9 (inner-source repos require a free-text problem statement or `--file-only` draft path).
- **Raw problem statement** (optionally with `--propose`): if `--propose` is supplied (or `PROJECT_INTENT.md` scope/duplication is uncertain on a broad raw idea), run `/cadence-propose` Step 00 first (fit check against `PROJECT_INTENT.md` + `local_semantic_embed` duplicate scan -> `specs/drafts/<slug>.md`, stopping cleanly if out-of-scope); otherwise invoke `/cadence-triage` passing the problem statement **verbatim**, read back the minted `<TICKET-ID>`, and enter Step 2.

## Step 2 — Admission Gate

Run `read_state.py` and dispatch on `status`:

| `status` | Admitted? |
|---|---|
| `absent` (tracker-first) | yes — after verifying §9 binds a live tracker in Step 1 |
| `draft`, `triaged`, `spec-in-review` | yes |
| `spec-approved` | yes **only** when `spec_mr` is missing/unrecorded or the spec MR is still in draft |
| `in-progress`, `in-review`, `merged`, `archived` | no — clean exit (`nothing to do`), naming `/cadence-build`, `/cadence-maintain`, `/cadence-close`, or `/cadence-archive` |
| unreadable, empty, or unknown | **halt**, quoting the `status` field and raw value verbatim |

## Step 3 — State Loop

Per `.agents/skills/cadence-build/references/worktree-and-ledger.md`, execute each iteration in strict order: **(0) verify runtime-neutral worktree isolation + `guard_tuple=` staleness**, then **(1) run `read_state.py <TICKET-ID>`** and verify the **loop progress guard** (`guard_tuple=` changed vs prior iteration).

### State: `draft`
Invoke `/cadence-triage <TICKET-ID>`. Re-read state; if `triaged_at` or `stage: triage` landed while `status` stayed `draft`, report status drift and set `status: triaged` in `metadata.yaml`.

### State: `triaged`
- **`tier` Medium or High:**
  - If `specs/<TICKET-ID>/spec.md` does **not** exist AND `grep -c '_(not yet answered)_' specs/<TICKET-ID>/problem.md` `>= 1`, invoke `/cadence-elicit <TICKET-ID>` directly **first** (never pre-skip based on background session topology; if probes remain `_(not yet answered)_`, `certainty-gate.sh` will raise `ESCALATE_HUMAN` (`unanswered_probes`) before spec approval). Never log duplicate `triage` effort inside `/cadence-define`.
  - Invoke `/cadence-spec <TICKET-ID>`.
- **`tier` Low or Trivial** → jump to *Stopping at Low and Trivial*.
- **Missing/empty/unrecognized `tier`** → **halt** (never default to `Low`).

### Stopping at Low and Trivial
Check `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/`:
- **Already on `origin/<integration-branch>`** → nothing to capture (opening a capture MR would create an empty diff). Name the next step (`/cadence-implement <TICKET-ID>` or `/cadence-build <TICKET-ID>` at Low; `/cadence-build <TICKET-ID>` or direct ad-hoc edit at Trivial — never name `/cadence-implement` for Trivial) and stop cleanly.
- **Not yet on `origin/<integration-branch>`** → offer two choices (acting directly if the user prompt already stated a preference, or defaulting to Option 2 if non-interactive):
  1. **Hand off for immediate implementation** (`/cadence-implement` / `/cadence-build` at Low; `/cadence-build` / ad-hoc edit at Trivial; never implement inside `/cadence-define`).
  2. **Open a triage-capture MR** on branch phase `triage` (`triage/<type>/<TICKET-ID>`), keeping `status: triaged` and leaving `spec_mr` and `merge_request` **empty**, push, open draft MR, publish via *Finishing the Spec MR*, and stop.

### State: `spec-in-review`
- If `spec_mr` is already populated → inspect live forge state via `State: spec-approved` step 1.
- If `spec_mr` is empty:
  1. Unless `spec_approved_at` is already populated, present open questions (`## Open Questions` + `design-options.md` if present) as structured option menus; when `**Gate 1 rulings:** required` appears in `spec.md`, record Gate 1 rulings in `decisions.md` and verify via `verify-facts.sh --rulings <TICKET-ID>`. Also run `(.agents/skills/cadence-certainty/certainty-gate.sh --stage spec <TICKET-ID> || skills/cadence-certainty/certainty-gate.sh --stage spec <TICKET-ID>)` before approving or publishing (`exit 1` -> fix via `/cadence-spec`; `exit 2` -> present Escalation Packet and record human rulings in `decisions.md` until `exit 0`).
  2. Set `status: spec-approved` and `spec_approved_at` (`date -u +%Y-%m-%dT%H:%M:%SZ`) **into the spec branch commit before opening the MR** (never defer until after merge).
  3. Commit, push, and execute *Opening the Spec MR*.

### State: `spec-approved`
Never assume an empty `spec_mr` means no MR exists (opening a second blind MR yields an empty-diff PR).
1. **When `spec_mr` is non-empty:** query `gh pr view "$SPEC_MR" --json state,isDraft,url`:
   - `OPEN` + `isDraft: true` → jump to *Finishing the Spec MR*.
   - `OPEN` + `isDraft: false` → run the *Optional Watch Handoff Prompt* below and exit cleanly (`nothing to do`).
   - `MERGED` → clean exit (`nothing to do`).
   - `CLOSED` (unmerged) → **halt** (human rejected MR).
   - Forge explicitly denies PR exists → **halt** (metadata contradiction).
   - Forge unreachable → **do not halt on read**; fall back to `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/` and disclose unverified forge state.
2. **When `spec_mr` is empty:** query `gh pr list --head <spec-branch> --state all --json number,url,state,isDraft,mergedAt`, then check `git ls-tree origin/<integration-branch> specs/<TICKET-ID>/` & `git log --oneline -- specs/<TICKET-ID>/spec.md | head`:
   - Discovered `MERGED` (or landed with recoverable PR URL) → record URL in `spec_mr` (using a tiny reconciliation PR if `<integration-branch>` is protected), push → done.
   - Discovered `OPEN` + `isDraft: true` → record URL in `spec_mr`, commit/push, run *Finishing the Spec MR*.
   - Discovered `OPEN` + `isDraft: false` → record URL in `spec_mr`, commit/push → run the *Optional Watch Handoff Prompt* below → done.
   - Discovered `CLOSED` (unmerged) → **halt**.
   - Neither MR nor landed `spec.md` exists → run *Opening the Spec MR*.
   - Landed with no recoverable PR reference → **halt** (never fabricate a URL).

## Opening & Finishing the Spec MR

1. Push `<spec-branch>` and open a **draft** PR targeting `<integration-branch>`:
   ```bash
   gh pr create --draft --base <integration-branch> --head <spec-branch> --title "..." --body "..."
   ```
2. Record the returned PR URL in `spec_mr` inside `specs/<TICKET-ID>/metadata.yaml`, commit, and push.
3. Publish ready and re-read to prove `isDraft: false` via `ready_mr.sh`:
   ```bash
   bash .agents/skills/cadence-define/scripts/ready_mr.sh <pr-url-or-number> \
     || bash skills/cadence-define/scripts/ready_mr.sh <pr-url-or-number>
   ```
   - Exit `0`: quote the verbatim `ready_mr:` stdout line in the summary, verify `spec_mr` equals `url=` (unless Low/Trivial capture MR), present the Run-End Checklist, run the *Optional Watch Handoff Prompt* below, and **stop immediately** unless explicitly confirmed (never self-merge, never auto-monitor merge, never start implementation). Name `/cadence-build <TICKET-ID>` as the next step after human merge.
   - Exit `2`: **halt** citing MR URL and cause.

### Optional Watch Handoff Prompt
`/cadence-define` owns the single watch prompt for this run (inner `/cadence-spec` skips its standalone watch prompt when called from `/cadence-define`). After presenting the Run-End Checklist whenever a spec or triage-capture MR is open and ready on the forge and an interactive operator is present, ask:
> `Invoke /cadence-watch <TICKET-ID> now to monitor this MR and bound tracker comments? (watch = --watch live poll / once = --once single check / no = stop here; or use /schedule for recurring --once checks)`
Invoke `/cadence-watch <TICKET-ID> --watch` or `/cadence-watch <TICKET-ID> --once` **only** on explicit confirmation (`watch` / `once`); if declined or non-interactive/unattended, stop immediately with zero polling.

## Run-End Checklist (Every Exit Path)

1. **Terminal outcome classification:** `spec MR open and ready` | `capture MR open and ready` | `handed off for implementation` | `nothing to do` | `halt` (with exact state & cause).
2. **Verbatim `ready_mr:` line** (when published) + confirmation that `spec_mr` matches `url=`.
3. **Session topology & worktree status** (`session_topology=...`, `worktree_state=...`, left-standing worktree path & branch).
4. **Stopping reason & next actor** (human spec reviewer, opt-in `/cadence-watch <TICKET-ID>` handoff, or unblocking step on halt).
