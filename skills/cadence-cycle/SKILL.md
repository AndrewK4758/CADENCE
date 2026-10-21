---
name: cadence-cycle
description: Drive a CADENCE ticket through implementation and code-review cycles and stop — pick up where the approved spec landed on the integration branch (or where a Trivial/Low ticket was triaged), iterate /cadence-implement and /cadence-review until blocking issues reach zero, open the implementation MR, record it in metadata.yaml, and publish it ready for review. Activate this skill whenever the user wants an existing ticket built and reviewed up to a reviewable MR, such as "implement BTG-123", "build out this ticket", "the spec merged, take it from here", "run the review cycles on this", "get this coded and up for review", or "continue BTG-99" on a ticket mid-cycle. Prefer this over /cadence-run when the goal ends at a reviewable implementation MR, and over /cadence-implement or /cadence-review individually when multiple review cycles may be required. Picks up directly where /cadence-prep stops, declines cleanly when a Medium/High spec has not merged yet, and never invokes /cadence-maintain, monitors the merge, or runs /cadence-archive. Requires a CADENCE-governed repository and an existing local ticket.
---

# cadence-cycle

Drive a single established ticket from **its approved specification having merged onto the integration branch** (or from `triaged` at Low/Trivial tier) up to **having its implementation MR open, recorded in `metadata.yaml`, and published ready for review**, then stop.

This skill executes the middle segment of `/cadence-run`: identical preflight checks, worktree isolation, state-machine loop, progress guard, cycle ledger format, and fail-loud discipline. It starts where `/cadence-prep` finishes and stops where `/cadence-maintain` begins. If you are ever about to invoke `/cadence-maintain` or `/cadence-archive`, or poll an MR waiting for merge, you have stepped outside `/cadence-cycle`'s scope — stop immediately and state that boundary.

Like `/cadence-run` and `/cadence-prep`, **the ticket's on-disk artifacts serve as the program counter.** Nothing is held solely in session memory across iterations; resuming a run reconstructs all state from `metadata.yaml`, `submission.md`, and the forge.

**Three intentional differences from `/cadence-run` define this skill's contract:**

1. **Free-text problem statements are refused.** `/cadence-cycle` builds a ticket that has already been established in `specs/<TICKET-ID>/`; it never mints or triages a new ticket. Supplying anything other than an existing ticket ID halts immediately.
2. **The implementation MR is published ready for review as soon as blocking review issues reach zero, prior to `/cadence-maintain`.** Whereas `/cadence-run` keeps the implementation MR in draft mode until `/cadence-maintain` accepts it (since `/cadence-run` continues through merge and archival), `/cadence-cycle`'s deliverable is a *reviewable implementation MR* handed over to the human/maintainer gate.
3. **`/cadence-maintain` never executes, and the MR is never monitored after publication.** The run finishes the moment `ready_mr.sh` confirms the MR is no longer a draft. Never report the ticket as accepted or merged.

## Interoperating with `/cadence-run` and `/cadence-prep`

Because operators routinely start a ticket with `/cadence-prep`, build it with `/cadence-cycle`, and finish it with `/cadence-run` (or `/cadence-finish`), every marker written by `/cadence-cycle` must use the shared schema read by its sibling skills:

**The cycle ledger uses the shared HTML comment marker — `cadence-run:cycle`.**
All state readers (`read_state.py`) across `/cadence-run`, `/cadence-prep`, and `/cadence-cycle` grep for the exact token `cadence-run:cycle`. Writing a skill-specific `cadence-cycle:cycle` marker would make completed cycles invisible to `read_state.py`, causing a resumed run or `/cadence-run` handoff to read `ledger_cycles_completed=0` and restart the 4-cycle review cap from 1. Always write `<!-- cadence-run:cycle ... -->`.

The same rule governs `metadata.yaml` attributes: `merge_request` records the implementation MR URL, `spec_mr` records the specification MR URL, and neither field is ever repurposed.

**Held non-blocking follow-ups use the exact prefix `Deferred -- held for the maintainer gate:` inside `submission.md`'s `## Resolution` -> `Follow-ups created`** (see *Held follow-ups: one decision, at the gate*). For Medium and High tier tickets, `/cadence-cycle` leaves that held set intact so `/cadence-finish` or `/cadence-run` can reconcile and present it once `/cadence-maintain` completes.

## Reading state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

Never parse `metadata.yaml` or `submission.md` cycle counts manually by hand. `read_state.py` avoids `yaml.safe_load` pitfalls on wrapped multi-line scalars and halts on ticket-id case mismatches rather than misreporting a ticket as `absent`.

**`read_state.py` is a deliberate twin of the copies in `/cadence-run` and `/cadence-prep`** so each skill directory remains standalone. Any fix to one copy must be applied to all copies in the same change.

If `read_state.py` is missing, **halt** immediately with cause `read_state_unavailable`.

## Preflight — abort conditions

Each preflight failure is an immediate hard stop naming its cause:

1. **`docs/agentic-sdlc/CADENCE_ORG.md` must exist** (in the current directory or an ancestor). Its absence means this is not a CADENCE-governed repository. Abort and inform the operator.
2. **The `§15 Branch-Strategy Binding` markers must resolve.** Never hardcode a branch name — `ADR_CADENCE-0020` makes §15 the sole machine-readable source for the integration branch and branch-naming convention.

Running `read_state.py` executes both preflight checks and exits non-zero with the cause on `stderr` if either fails.

## Step 0 — Mandatory automatic local offload (`offload_log_triage` & `offload_deep_review`)

Across every implement/review iteration in `/cadence-cycle`, enforce two automatic local coprocessor offloads:

1. **Test, Build, and Migration Log Compaction (`offload_log_triage`).** On **every** test runner, compiler build, linter, or migration verification step inside `/cadence-implement` (and any gate script) whose output exceeds 30 lines, automatically pipe the output through `offload_log_triage` (`local-fast-cpu` / `gemma-4-e2b` on `:11434`, 0 MB VRAM), saving the full numbered raw output to `/tmp/agy-last-triage.log` and returning verbatim failing assertions, compiler errors, and `file:line` coordinates.
2. **Pre-Review & Pre-MR Mechanical Diff Scan (`offload_deep_review`).** Automatically run `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:11434`) on `git diff <integration-branch>...HEAD` before opening or updating the implementation MR and at Step 0 of each `/cadence-review` cycle to verify the `<400`-line Agentic Ergonomics ceiling, comment discipline, and CHORD seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).

## Step 1 — resolve the argument

**The argument must be a valid ticket identifier whose spec directory already exists locally:**

- **Ticket-id shaped** (`PREFIX-123`) **and `specs/<id>/` exists on disk** → target ticket resolved; proceed to Step 2 (the admission gate).
- **Ticket-id shaped and `archive/<id>/` exists on disk** → the ticket is already archived (`nothing to do`); report that and stop cleanly.
- **Ticket-id shaped but neither `specs/<id>/` nor `archive/<id>/` exists** → **halt** with cause `ticket_not_established`. Tracker-first intake belongs to `/cadence-triage <TICKET-ID>` or `/cadence-prep <TICKET-ID>`, never `/cadence-cycle`, because an untriaged tracker issue has no local `problem.md` or `tier:` to govern implementation. Instruct the operator to run `/cadence-triage <TICKET-ID>` or `/cadence-prep <TICKET-ID>` first, and never invoke `/cadence-triage` from inside `/cadence-cycle`.
- **Not ticket-id shaped** (e.g., inline prose or a draft file path) → **halt** with cause `not_a_ticket_id`, quoting the argument verbatim. Free-text problem statements belong to `/cadence-prep` or `/cadence-run`; `/cadence-cycle` never invents a ticket, tier, or acceptance criteria on the fly.

## Step 2 — the admission gate

`/cadence-cycle` owns the implementation-and-review window. Admitting a ticket outside that window either builds against an unmerged specification or re-runs review cycles on an MR that is already published for maintainer acceptance.

Run `read_state.py` and evaluate `status` **jointly with `tier`**:

| `status` | admitted? |
|---|---|
| `triaged` | **admitted ONLY when `tier` is `Trivial` or `Low`** — at `Medium`/`High` the specification is still owed |
| `spec-approved` | **admitted ONLY after verifying the spec has merged onto the integration branch** — see gate below |
| `in-progress` | yes |
| `in-review` | **admitted ONLY while the implementation MR is not yet both recorded and published ready** |
| `draft`, `spec-in-review` | no — still in the intake/specification window; direct the operator to `/cadence-prep <TICKET-ID>` |
| `merged`, `archived` | no — nothing to do (already past this skill's window) |
| unreadable, empty, or not in this table | **halt**, citing the `status` field and raw value read |

**"Nothing to do" is a clean, successful exit and must never be framed as an error.** State the ticket's current `status`, clarify whether the ticket is *not yet at* or *already past* `/cadence-cycle`'s window, and name the skill that governs that state (`/cadence-prep` when earlier; `/cadence-maintain` or `/cadence-run` when later).

**An unrecognized or empty `status` is a hard halt, never "nothing to do."** Always quote the exact value read from `metadata.yaml`.

### The gate at `triaged`

- **Tier `Trivial` or `Low`** → **admitted.** Under `docs/policies/change-tiers.md`, no `spec.md` is authored at these tiers: Low tier implements against `problem.md`'s Acceptance Criteria checklist, and Trivial tier executes *The Trivial path* below.
- **Tier `Medium` or `High`** → **not admitted.** A Medium/High ticket at `triaged` still needs `/cadence-spec` and human spec approval. Direct the operator to `/cadence-prep <TICKET-ID>` (or `/cadence-spec <TICKET-ID>`) and stop.
- **Absent, empty, or unrecognized `tier`** → **halt** immediately. Never default an unknown tier to Low.

### The gate at `spec-approved` — verifying the spec *landed on the integration branch*

**Verify integration-branch ancestry on every entry at `spec-approved`.** Because `/cadence-prep` writes `status: spec-approved` into the spec branch commit *prior* to opening and merging the spec MR, `metadata.yaml` on a spec branch already reads `status: spec-approved` while the spec MR is still open awaiting human review.

- **Tier `Low` or `Trivial`** → no `spec.md` or spec MR exists at these tiers; **admitted** without checking for `spec.md` upstream.
- **Tier `Medium` or `High`** → verify that `specs/<TICKET-ID>/spec.md` is present on the integration branch tip:

  ```bash
  git ls-tree origin/<integration-branch> specs/<TICKET-ID>/
  ```

  Checking `origin/<integration-branch>` directly tests the exact invariant that matters — whether the approved specification is present in the base tree from which the implementation branch will be cut — even if `spec_mr` was never backfilled. Corroborate with `gh pr view "$SPEC_MR" --json state` when the forge is reachable.

  - **`spec.md` is present on `origin/<integration-branch>`** → **admitted.**
  - **`spec.md` is absent from `origin/<integration-branch>`** → **not admitted (*not yet* in window).** The specification exists only locally or in an unmerged spec MR. Inform the operator that the spec MR must merge into `<integration-branch>` first, name `/cadence-prep <TICKET-ID>` (if not yet proposed) or `/cadence-run <TICKET-ID>` (to monitor the merge), and stop.

Never cut an implementation branch before a Medium/High spec merges into `<integration-branch>`: phase branches cut cleanly from `<integration-branch>` rather than stacking on unmerged spec branches, so starting early would omit `spec.md` from the implementation branch or drag unmerged spec commits into the implementation diff.

### The gate at `in-review` — checking whether the implementation MR is already reviewable

Because `status: in-review` spans active review cycles, cap checkpoints, and finished MRs awaiting `/cadence-maintain`, check `merge_request` and the forge in this order:

0. **Tier `Trivial`** → bypass cycle counting completely (Trivial runs zero `/cadence-review` cycles) and jump to *The Trivial path*.
1. **`merge_request` is empty** → **admitted**; no implementation MR has been recorded yet.
2. **`merge_request` is populated** → query the forge:
   ```bash
   gh pr view "$MERGE_REQUEST" --json state,isDraft,url
   ```
   - `OPEN` and `isDraft: true` → **admitted**; the MR is still a draft, so review cycles or publication remain unfinished.
   - `OPEN` and `isDraft: false` → **nothing to do**; the implementation MR is already published ready for review, closing `/cadence-cycle`'s window. Direct the operator to `/cadence-maintain <TICKET-ID>` (or `/cadence-run <TICKET-ID>`).
   - `MERGED` → **nothing to do**; report the status drift explicitly (`status: in-review` on a merged MR is stale and ready for `/cadence-archive`).
   - `CLOSED` (unmerged) → **halt.** A human closed/rejected this implementation MR; never restart cycles on a rejected MR without explicit operator instruction.
   - **Forge unreachable** → do not treat network unavailability as a ticket defect. Fall back to local evidence (`ledger_cycles_completed`, last review verdict in `submission.md`), disclose what could not be verified against the forge, and err on the side of caution: if local evidence shows 0 blocking issues on the latest cycle, do not start redundant cycles.

## Step 3 — the state loop

Every iteration executes two actions **in strict order**: verify worktree isolation first, then read ticket state via `read_state.py`.

### Iteration step 0 — ensure worktree isolation (agent mode only)

**Agent mode** applies when this session was dispatched as an autonomous background agent (`claude --bg` or from `claude agents`) rather than an interactive foreground terminal. Query the CLI directly:

```bash
claude agents --json 2>/dev/null | python3 -c '
import json, os, sys
sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
try:
    rows = json.load(sys.stdin)
except Exception:
    rows = []
m = [r for r in rows if r.get("sessionId") == sid]
print("session kind=%s" % (m[0]["kind"] if m else "unknown"))'
```

`kind=background` indicates a background session; **`interactive`, `unknown`, or command failure is NOT agent mode**.

**Combine `kind=background` with the delegate check:** because a subagent spawned by the Agent tool inherits its parent's `CLAUDE_CODE_SESSION_ID`, `claude agents --json` returns the parent session's `kind=background` row. Isolate **if and only if** `kind=background` **and** this execution is the top-level session run rather than a delegated subagent. If uncertain, do not isolate and state why, so a subagent never strands commits in a nested worktree invisible to its caller.

**Never inspect `AI_AGENT` or `CLAUDE_CODE_CHILD_SESSION` to infer background mode** — both variables are set identically across foreground `claude -p` calls and background agents.

**Always print the observed `session kind=...` and the isolation branch taken.**

Worktree isolation is especially critical during `/cadence-cycle`: `/cadence-implement` repeatedly edits source files, runs tests, and creates per-scenario commits, so two agents sharing one working tree will interleave commits across each other's branches.

Check whether the current working directory is already a linked worktree:

```bash
[ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ] \
  && echo launch-checkout || echo in-worktree
```

When already `in-worktree`, log the worktree path and continue. When in `launch-checkout` under agent mode:

1. Run `read_state.py` **in the launch checkout first** and save its output (`location=`, `status=`, and the full `guard_tuple=`).
2. Invoke `EnterWorktree` with name `cadence-cycle/<TICKET-ID>`.
3. If `EnterWorktree` is unavailable, **halt** immediately with cause `worktree_unavailable` — never run `/cadence-implement` commits inside a shared launch checkout in background agent mode.

**Mandatory worktree staleness guard.** Immediately re-run `read_state.py` inside the worktree and compare the **entire `guard_tuple=` line** against the launch-checkout reading:

- **Full `guard_tuple=` line matches byte-for-byte** → proceed.
- **Any discrepancy in `guard_tuple=`** → **halt** immediately, quoting both `guard_tuple=` lines verbatim.

Comparing the complete `guard_tuple=` (rather than only `location` and `status`) is critical in `/cadence-cycle` because `guard_tuple=` includes `merge_request` and `ledger_cycles_completed`: since `submission.md`'s cycle ledger lives on the implementation branch, a newly created worktree cut from the integration branch before checking out the implementation branch would otherwise read `ledger_cycles_completed=0` while `location` and `status` matched, resetting the 4-cycle review cap. Additionally, if a spec existed only locally in the launch checkout, the fresh worktree reveals that it never merged onto `<integration-branch>`.

**Verify the integration branch base.** If `CADENCE_ORG.md` §15's `integration-branch` differs from the remote default branch, note it explicitly and ensure `/cadence-implement` cuts the implementation branch from `origin/<integration-branch>`.

**Leave the worktree standing at run end.** Deleting the worktree would remove the local checkout of the open implementation branch; report the worktree path and branch name in the run-end checklist.

### Iteration step 1 — read the state

```bash
python3 <skill-dir>/scripts/read_state.py <TICKET-ID>
```

**Remember that `status` in `metadata.yaml` always runs ahead of the merge by design** — which is why Step 2 verified `spec.md` on `origin/<integration-branch>` directly.

**Loop progress guard.** Capture the `guard_tuple=` line from `read_state.py` before each iteration and compare it after the iteration completes. **If `guard_tuple=` is unchanged → halt and report what action was attempted and what blocked progression.** Because `guard_tuple=` includes `ledger_cycles_completed`, each completed implement/review cycle advances the tuple even though `status` remains `in-review` across cycles.

Valid loop termination conditions:
1. The implementation MR is open, recorded in `merge_request`, and confirmed ready for review (`ready_mr:` exit 0).
2. Step 2's admission gate returned "nothing to do".
3. The 4-cycle review cap was reached with blocking issues still open and the operator chose not to authorize additional cycles (or no operator was reachable).
4. An explicit fail-loud halt rule fired, or the loop progress guard tripped.

---

## The Trivial path

For tickets classified as `tier: Trivial`, the governed TDD cycle does not apply and `/cadence-implement` refuses the tier (`docs/policies/change-tiers.md`). Therefore, **execute the Trivial change directly inside `/cadence-cycle` during this run** — perform the straightforward edit, commit it on the branch, and open the MR, with no Gherkin TDD loop or `spec.md`.

*Ad hoc* at Trivial tier means **skipping `/cadence-implement`'s ceremony while still performing the edit and opening the MR yourself — never handing a to-do list back to the operator.**

Execute these steps in order:

1. Cut the branch per `CADENCE_ORG.md` §15, make the Trivial edit, and append a concise entry to `specs/<TICKET-ID>/decisions.md` recording what changed and that it followed the Trivial ad-hoc path.
2. Push the branch, open the MR **as a draft** targeting `<integration-branch>`, write the MR URL into `merge_request` in `specs/<TICKET-ID>/metadata.yaml`, set `status: in-review`, commit, and push.
3. Publish the MR ready for review via *Finishing the implementation MR* below and stop.

**Do not invoke `/cadence-review` on a Trivial ticket** — human review of the MR itself serves as the sole review at Trivial tier, so zero review cycles and zero `cadence-run:cycle` ledger entries are written. Note that while `docs/policies/change-tiers.md` remarks that Trivial doc changes can auto-merge if CI passes, `integration-branch-protected: yes` in `CADENCE_ORG.md` §15 still requires an MR to land the commit onto the protected integration branch; both rules operate together without contradiction.

## Sprint confirmation: once per run, covering every cycle

Because `/cadence-implement` executes the `CADENCE_ORG.md` §13 sprint-enforcement guard on **every** invocation — prompting the user and appending a `decisions.md` entry each time the guard lands on `Confirm` — running four implement/review cycles naively would ask the human the identical sprint-scope question four times. Instead, **`/cadence-cycle` resolves the sprint guard once prior to the first `/cadence-implement` call, collects at most one human confirmation for the entire run, and relays that recorded confirmation across every cycle in this run** (including any extra cycles authorized at the cycle cap).

**First, run the per-prefix sprint binding resolver** from the repository root:

```bash
bash ci-templates/scripts/org-binding-resolve.sh --sprint <PREFIX>
```

Verify that the command exits `0` and emits `enabled=`, `skill=`, `fallback=`, and `source=`. Any non-zero exit (such as `sprint.binding.form_removed` or `sprint.binding.enabled_without_tracker`) or missing output line is an immediate **halt** quoting the output verbatim — never default to `enabled=no` when the resolver errors.

- **`enabled=no`** → routes to the `Confirm` path; prompt the operator once (below).
- **`enabled=yes`** → invoke `<skill> sprint-check <TICKET-ID>` once:
  - `in-sprint` → sprint check passed (`Proceed`); no confirmation prompt or `decisions.md` entry is needed.
  - `not-in-sprint` → **halt** immediately prior to any implementation (`Block` is never overridable by confirmation).
  - `inconclusive` → apply `fallback=`: when `Block`, **halt** immediately; when `Confirm`, prompt the operator once (below).

**Prompt once on `Confirm`.** State the ticket ID, the resolver's verdict and why it requires confirmation, and explain clearly that **confirming `yes` authorizes every `/cadence-implement` cycle during this `/cadence-cycle` run**. Only an explicit affirmative `yes` proceeds; any `no`, empty, or ambiguous response **halts immediately with zero writes**. **When no interactive operator is reachable**, halt immediately — never self-confirm an out-of-sprint or unverified ticket.

**Write the run-level confirmation before starting Cycle 1** (strict write-before-proceed): append a dated entry to `specs/<TICKET-ID>/decisions.md` recording `"operator confirmed the ticket is in scope for implementation; this confirmation covers every implement/review cycle of this run"` alongside the operator identity resolved from `git config user.name` + `git config user.email`, else OS login (`id -un` / `logname` / `$USER`), else the fallback literal `identity could not be determined` (never read identity from user-typed input). If writing `decisions.md` fails, halt immediately.

**Relay across cycles:** when each `/cadence-implement` invocation inside the loop prompts its own sprint guard on `Confirm`, supply `yes` on the operator's behalf citing the run-level `decisions.md` entry, allowing `/cadence-implement` to write its own per-cycle audit line as usual.

Enforce three strict boundaries on this relay (halting if any boundary is crossed):
- **Confirm verdicts only.** If a subsequent cycle's sprint check returns `not-in-sprint` (`Block`) or shifts from `in-sprint` to `inconclusive`, stop and report rather than relaying.
- **Scoped strictly to this run and this ticket.** A subsequent `/cadence-cycle` or `/cadence-run` invocation must ask fresh rather than treating a prior run's `decisions.md` entry as standing authorization (though it may cite the prior entry as context).
- **Separate from the 4-cycle review cap.** Confirming sprint scope never authorizes continuing past 4 review cycles.

## The implement/review cycle

This loop drives Low, Medium, and High tier tickets (Trivial tickets take *The Trivial path* above).

**Step A — Determine the starting cycle count.** Read `ledger_cycles_completed` from `read_state.py`. The `cadence-run:cycle` ledger in `submission.md` is authoritative. Only when `ledger_cycles_completed` is `0` on a legacy ticket whose reviews predate the ledger, count the existing `/cadence-review` verdict blocks in `submission.md`. Never use `stage_effort` entries to count cycles (effort logging can be omitted, which would undercount completed cycles).

**Step B — Satisfy the once-per-run sprint confirmation** (per *Sprint confirmation: once per run* above) if not yet completed in this run.

**Step C — Execute the cycle loop:**

1. Invoke `/cadence-implement <TICKET-ID>`, relaying the recorded sprint confirmation when its guard prompts on `Confirm`. Inside `/cadence-implement`, every test/build/migration command exceeding 30 lines is automatically compacted via `offload_log_triage` (`/tmp/agy-last-triage.log`) and the pre-review diff is scanned via `offload_deep_review`.
2. **Immediately after the first `/cadence-implement` completes, ensure a draft implementation MR exists** — because `/cadence-implement` itself does not open a forge MR. If `merge_request` is empty, open the MR **as a draft** (`gh pr create --draft --base <integration-branch> --head <impl-branch> ...`) and immediately write its URL to `merge_request` in `specs/<TICKET-ID>/metadata.yaml`, commit, and push. Keep the MR in draft mode throughout all review cycles so no human reviewer is notified while blocking issues remain.
3. Invoke `/cadence-review <TICKET-ID>` (which automatically runs its Step 0 `offload_deep_review` mechanical pre-scan before `cadence-reviewer`), **holding** any non-blocking follow-up candidates rather than prompting the operator mid-loop (see *Held follow-ups: one decision, at the gate*).
4. Append the cycle's `<!-- cadence-run:cycle ... -->` ledger line to `submission.md` (see *The cycle ledger* below), commit, and push.
5. **When blocking issues == 0** → exit the loop and advance to *Finishing the implementation MR* (for **Low** tier, reconcile and decide the held follow-up candidates first per *At the gate: reconcile, then decide once*).
6. **When blocking issues > 0** → check the 4-cycle cap below; if within budget, begin the next iteration **fixing ONLY the blocking issues**. Deliberately leave non-blocking suggestions untouched during the loop: modifying code for non-blocking suggestions expands the diff surface, triggering fresh review findings and preventing loop convergence.

### The cycle cap

**Hard checkpoint at 4 total `/cadence-review` cycles (including cycles recorded prior to this run).**
Whenever cycle 4 (or the end of an authorized extension) finishes with `blocking > 0`, **pause and prompt the human operator** — never continue into cycle 5 unasked, and never fail silently.

Four unconverged cycles indicate a structural issue (an ambiguous spec, an oversized ticket, or oscillating review feedback) that requires human judgment:

- Present the checkpoint clearly: total cycles run, the specific blocking findings from the latest review, and a choice between (a) authorizing `K` additional cycles or (b) stopping here so the operator can inspect the branch directly.
- **If the operator authorizes additional cycles, log the authorization in `specs/<TICKET-ID>/decisions.md`** — recording the prompt, the operator's verbatim response, and the exact number of additional cycles authorized — before resuming the loop (still appending a `cadence-run:cycle` ledger marker on every cycle).
  - **Cycle-cap authorizations apply strictly to the current run.** A future invocation of `/cadence-cycle` or `/cadence-run` that sees `ledger_cycles_completed >= 4` with open blockers will prompt the operator again, citing the prior `decisions.md` entry as context rather than treating it as a permanent blank check.
- **If no interactive operator is reachable**, stop cleanly at the cap and report the open blockers. Never self-authorize extra cycles.

### Progress summary

Maintain and display this live progress block across iterations so the operator can track convergence at a glance:

```
BTG-123  cycle 3/4  —  Reviewing
  cycle 1: blocking 4 · non-blocking 7   ✔ addressed
  cycle 2: blocking 1 · non-blocking 3   ✔ addressed
  cycle 3: blocking ? · non-blocking ?   ← in progress
```

Where each active cycle stage is shown as `Implementing` or `Reviewing`.

## Held follow-ups: one decision, at the gate

Normally, `/cadence-review` Step 6 prompts the human after every review to decide which non-blocking `out-of-scope-defect` candidates to file via `/cadence-triage --file-only`. Inside a multi-cycle loop, asking on Cycle 1 is premature: Cycle 2's blocking fixes frequently refactor or delete the code a Cycle 1 non-blocking finding pointed at. Therefore, `/cadence-cycle` **holds** all non-blocking candidates across the loop and presents the consolidated set **once at the human gate**, after code changes have stabilized.

**Scope of held items:** every non-blocking candidate not addressed as part of a blocking fix (which under Step C.6 above is all of them).

### During each cycle

When `/cadence-review` reaches Step 6c (*present and confirm*), intercept the prompt and record a **deferral** on the operator's behalf — never a `Declined` and never a `none owed` or immediate filing (recording `Declined` or `none owed` would permanently hide the finding from `/cadence-maintain` Step 6b and `/cadence-archive` Step 2e). Immediately after `/cadence-review` finishes:

1. Beneath that cycle's review section in `submission.md`'s `## Discussion`, list each held candidate from that cycle on its own line: its one-line summary plus its exact deferred filing command `/cadence-triage --file-only specs/drafts/<TICKET-ID>-held-c<n>-<k>.md` (where `n` is the cycle number and `k` is the candidate ordinal). Do not write the scratch file in `specs/drafts/` until the candidate is actually confirmed for filing at the gate.
2. Update `submission.md`'s `## Resolution` -> `Follow-ups created` so it contains **a single consolidated held line** spanning all cycles completed so far (replacing the prior cycle's held line or any `None owed` written by an earlier zero-candidate cycle):

   `Deferred -- held for the maintainer gate: <N> candidates from code-review cycles <list>, held because later cycles can change them; candidates and their exact filing commands are in ## Discussion.`

   Preserve the exact prefix `Deferred -- held for the maintainer gate:` byte-for-byte so `/cadence-finish`, `/cadence-run`, and `/cadence-archive` recognize the held set.
3. Re-read `Follow-ups created` to verify that `/cadence-review` did not write an unexpected disposition (such as a filed ID, `Declined`, or `none owed` over non-zero candidates). If it did, halt and report the drift rather than overwriting a potentially human-authored disposition.

When a cycle produces zero non-blocking candidates, leave any existing held line from earlier cycles intact.

### At the gate: reconcile, then decide once

**When the held set is decided:**

- **Tier `Medium` or `High`:** **not decided inside `/cadence-cycle`.** Because Medium and High tickets have a human maintainer gate (`/cadence-maintain`) that `/cadence-cycle` never runs, keep the `Deferred -- held for the maintainer gate:` line intact in `submission.md` so `/cadence-finish` or `/cadence-run` reconciles and presents it alongside `/cadence-maintain`'s own findings. Report the count of held candidates in the run summary.
- **Tier `Low`:** **decided right here in `/cadence-cycle`** as soon as `blocking == 0`, prior to running *Finishing the implementation MR*. Because Low tier has no `/cadence-maintain` gate (`docs/policies/change-tiers.md`), the end of the final code-review cycle is the ticket's sole pre-merge gate.
- **Resuming a `Low`-tier ticket at `blocking == 0`** whose `Follow-ups created` still carries the `Deferred -- held for the maintainer gate:` prefix (from an interrupted gate): execute the reconciliation and decision steps below before publishing the MR.
- **Stopping early (at the 4-cycle cap or on a halt):** leave the held line intact and report the held count and which gate will dispose of it.

**How to reconcile and dispose of the held set (at Low tier):**

1. **Gather** all held candidates recorded across `## Discussion`.
2. **Reconcile** each candidate against the current branch `HEAD` and against prior work in `specs/` and `archive/` (using `local_semantic_embed` / `local-moe-hybrid`), proposing **exactly one** disposition per candidate:
   - **file as written** (still valid against final `HEAD`);
   - **file as rewritten** (still valid, but subsequent cycles shifted lines or context — provide the updated description and source cycle);
   - **decline, resolved** (a subsequent cycle's commit fixed or removed the code — cite the cycle/commit);
   - **decline, duplicate** (folds into another held candidate or existing ticket — cite the target).
3. **Present once:** display the numbered list of candidates with their proposed dispositions and ask the human operator which items to file. Re-prompt at most once on an empty or unrecognized response; if the second response is also invalid, leave the undecided candidates under the held `Deferred` line citing that reason.
4. **File** each confirmed candidate by writing its final description verbatim to `specs/drafts/<TICKET-ID>-held-c<n>-<k>.md` and invoking `/cadence-triage --file-only specs/drafts/<TICKET-ID>-held-c<n>-<k>.md` (deleting the scratch draft on exit `0`, or halting with the verbatim error on non-zero exit while preserving any already-filed tickets). Never invoke the id allocator directly or hand-create `specs/<id>/` files.
5. **Record:** replace the `Deferred -- held for the maintainer gate:` line in `## Resolution` -> `Follow-ups created` with the canonical template dispositions: one filed line per new ticket ID (labelled `after final code review` at Low tier), a `Declined` entry recording the operator's reason for each declined item, and a `Deferred` entry for any item left undecided. Account for every held candidate exactly once.
6. Commit and push the updated `submission.md` to the implementation branch.

**If no interactive operator is reachable**, keep the `Deferred -- held for the maintainer gate:` line untouched in `submission.md` and report it — never auto-file or auto-decline held candidates without human confirmation.

## The cycle ledger

Because review prose in `submission.md` varies across runs, `/cadence-cycle` maintains a deterministic machine-readable ledger line at the end of each review block under `## Discussion`:

```
<!-- cadence-run:cycle n=2 phase=code-review blocking=1 nonblocking=3 at=2026-08-21T14:02:11Z -->
```

**Always use the exact marker prefix `cadence-run:cycle`** (see *Interoperating with `/cadence-run` and `/cadence-prep`* above) and populate `at=` from `date -u +%Y-%m-%dT%H:%M:%SZ`.

**Append only the single HTML comment line for the completed cycle — never paste instructional examples or prose containing the literal marker string into `submission.md`**, as `read_state.py` greps `submission.md` for `cadence-run:cycle` and would miscount example lines as completed cycles. After every `/cadence-review` call, re-run `read_state.py` to verify `ledger_cycles_completed` incremented by exactly 1.

## Finishing the implementation MR

Once blocking review issues reach `0` (and Low-tier held follow-ups are dispositioned), publish the draft implementation MR ready for review using `ready_mr.sh`:

```bash
bash <skill-dir>/scripts/ready_mr.sh <pr-url-or-number>
```

`ready_mr.sh` checks `isDraft`, publishes the MR if still in draft, and **re-queries the forge afterward** to confirm `isDraft` is `false`.

| exit | meaning | what to do |
|---|---|---|
| 0 | confirmed ready for review (`was_draft=yes` published it; `was_draft=no` was already ready) | cycle run is complete |
| 2 | failed to publish or failed post-publish verification | **halt** citing the MR URL/number and failure cause |

Quote the script's stdout line verbatim in the final report:
`ready_mr: pr=… result=… was_draft=… url=…`

Verify before stopping that `merge_request` in `specs/<TICKET-ID>/metadata.yaml` matches the `url=` in `ready_mr:`. If they differ, commit and push the reconciled `merge_request` value before exiting.

**Then stop immediately.** Do not invoke `/cadence-maintain`, do not poll CI or merge state, and never report the ticket as accepted or merged. State clearly that the implementation MR is *open, recorded, and ready for review*, provide the MR URL, state how many non-blocking follow-ups remain held for the maintainer gate (at Medium/High), and name the next command — `/cadence-maintain <TICKET-ID>`, or `/cadence-run <TICKET-ID>` to drive maintainer evaluation, merge monitoring, and archival.

**Never self-merge the implementation MR.**

## Run-end checklist

Prior to ending `/cadence-cycle` — on **every** exit path, including halts, cycle-cap pauses, progress-guard trips, and nothing-to-do exits — verify and report all seven items:

1. **Terminal outcome classification** — name **exactly one** of:
   - `implementation MR open, recorded and ready`
   - `nothing to do` (naming the current `status` and whether it is *not yet at* or *already past* `/cadence-cycle`'s window)
   - `cycle cap reached awaiting authorisation`
   - `halt` (naming the exact state and cause)
2. **Verbatim `ready_mr:` evidence line** whenever the MR was published, confirming `merge_request` in `metadata.yaml` matches its `url=`.
3. **Cycle count summary backed by ledger entries** — state how many cycles existed prior to this run, how many cycles ran during this invocation, and the `blocking`/`nonblocking` counts from the final `cadence-run:cycle` entry.
4. **Session mode and worktree status** — state the observed `session kind=...` from Iteration step 0, whether agent-mode isolation ran, and (when isolated) the worktree path and branch *left standing*.
5. **Stopping reason and next actor** — state why the run ended and who acts next (`/cadence-maintain <TICKET-ID>`, `/cadence-run <TICKET-ID>`, or what unblocks a halt).
6. **Sprint-enforcement guard record** — state the output of `org-binding-resolve.sh --sprint <PREFIX>`, whether the operator was prompted once on `Confirm` (citing the `decisions.md` entry), whether `in-sprint` required no prompt, or whether the guard halted the run.
7. **Held follow-up disposition summary** — state how many non-blocking candidates remain held under `Deferred -- held for the maintainer gate:` for `/cadence-maintain` (at Medium/High), or list the filed ticket IDs, declined items, and deferred items decided at the Low-tier gate.

If any checklist item fails verification, report the gap explicitly rather than claiming clean completion.

## Fail-loud rules

Never guess or silently fall back on any of the following conditions:

- Missing, empty, or unrecognized `tier`, `status`, or `CADENCE_ORG.md` §15 branch binding → **halt** naming the field and quoting the raw value read. Never default an unknown tier to Low.
- Target ticket directory absent from `specs/` (and `archive/`), or an argument that is not a ticket ID (`ticket_not_established` / `not_a_ticket_id`) → **halt** immediately without invoking `/cadence-triage`.
- Medium or High tier ticket whose `spec.md` has not yet merged onto `origin/<integration-branch>` → **not admitted**; never cut an implementation branch against an unmerged local spec.
- A delegated skill (`/cadence-implement` or `/cadence-review`) returns success while leaving `status` or expected artifacts unchanged → surface the drift explicitly before reconciling.
- `merge_request` empty while an implementation MR already exists on the forge, or `merge_request` set to a URL **that the reachable forge explicitly denies** → reconcile the first by recording the real URL, and **halt** on the second. While *reading* state, an unreachable forge degrades to local evidence with disclosure; when *publishing* the MR via `ready_mr.sh`, forge reachability is mandatory and exits `2` on failure.
- Discrepancy between `ledger_cycles_completed` (`cadence-run:cycle` markers) and the number of `/cadence-review` verdict sections in `submission.md` → **halt** quoting both counts rather than guessing which count is right.
- Unresolvable sprint binding, `not-in-sprint` (`Block`), or an unanswered/declined `Confirm` prompt → **halt** prior to invoking `/cadence-implement`. Never relay a sprint confirmation the operator did not give in the current run.
- Every halt message must name the state where it halted and what action unblocks it.

## Local Model Offload Integration (Antigravity + LiteRT/GGUF)
- Step 0 automatically pipes every test, build, linter, or migration verification output exceeding 30 lines during `/cadence-implement` cycles through `offload_log_triage` (`local-fast-cpu` / `gemma-4-e2b` on `:11434`, 0 MB VRAM), preserving raw numbered output at `/tmp/agy-last-triage.log`.
- Step 0 automatically invokes `offload_deep_review` (`local-moe-hybrid` / `gemma-4-26b-a4b` on `:11434`) for pre-MR and pre-review mechanical diff checks (`<400`-line ceiling, comment discipline, CHORD seams).
- At the Low-tier follow-up gate, `local_semantic_embed` (`local-embed-cpu` on `:11434`, 0 MB VRAM) / `local-moe-hybrid` assists prior-work deduplication across `specs/` and `archive/`.
