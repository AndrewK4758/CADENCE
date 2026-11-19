---
name: cadence-watch
description: Poll open GitHub PRs, GitLab MRs, and bound Jira/YouTrack ticket comments for a CADENCE ticket (or all active tickets), mirror new external feedback into submission.md with idempotent watermarks, and automatically continue the SDLC on merges or remediate in-scope change requests while preserving mandatory human gates.
argument-hint: "[<ticket-id> | --all] [--once | --watch] [--interval <sec>] [--timeout <sec>] [--no-tracker] [--dry-run]"
arguments: [target_and_flags]
allowed-tools: Read Write Edit Glob Grep Bash Skill
---

# cadence-watch

Monitor open `spec_mr` / `merge_request` / `triage_mr` threads on GitHub (`gh`) or GitLab (`glab`) plus inbound comments on the bound external tracker (`CADENCE_ORG.md#tracker-binding`: Jira Server/DC or YouTrack Server), mirror unseen feedback into `specs/<TICKET-ID>/submission.md`, and advance or remediate the ticket strictly within approved scope while preserving every mandatory CADENCE human gate.

> **Shared State & Isolation Contract:** Always inspect ticket state and poll external sources via `pr_watch.py` (using byte-identical `read_state.py` and `CADENCE_ORG.md#branch-strategy-binding` `integration-branch`, never hardcoded `main`/`develop`). Never parse `metadata.yaml` by hand, never self-merge an unmerged PR, never commit directly onto a protected `<integration-branch>`, and never mutate files under `--dry-run`.

## Step 0 — Optional Local Offload (:11434, Cloud-Only Fallback)

1. **Failure & CI Log Compaction (`offload_log_triage`):** When `:11434` is reachable, pipe `ci_failed` run logs (`gh run view --log-failed` / `glab ci trace`) and any failing verification/test output >30 lines through `offload_log_triage` (`inference` on `:11434`, raw log saved to `/tmp/agy-last-triage.log`; else inspect directly).
2. **Pre-Push Mechanical Diff Scan (`offload_deep_review`):** When `:11434` is reachable, before pushing remediation commits on `merge_request`, invoke `offload_deep_review(diff_range="<integration-branch>...HEAD", cwd="<worktree-root>")` to verify `<400`-line file ceilings, comment discipline, and CHORD seams.
3. **Semantic Grounding & Dedupe (`local_semantic_embed` / `repo-scout`):** When `:11434` is reachable, use `local_semantic_embed` (`embedding` on `:11434`) when grounding reviewer questions in `specs/`, `archive/`, or codebase symbols, or checking non-blocking follow-up candidates (falling back to `Grep`/`Glob` when offline).

## Step 1 — Poll Forge & Bound Tracker (`pr_watch.py`)

Stage a temporary snapshot file (`SNAP="$(mktemp)"`) and run a single poll by default (`--once`), or continuous polling (`--watch --interval 60 --timeout 1800`) when requested in headless/CLI runs (in interactive runtimes with a native cron/scheduler, prefer scheduling recurring `--once` checks instead of blocking):

```bash
python3 .agents/skills/cadence-watch/scripts/pr_watch.py <TICKET-ID-OR---all> \
  [--once | --watch --interval <sec> --timeout <sec>] [--no-tracker] \
  --write-snapshot "$SNAP" --format kv \
|| python3 skills/cadence-watch/scripts/pr_watch.py <TICKET-ID-OR---all> ...
```

- **Exit `2` (`cadence-watch.halt`):** Halt immediately and surface the stderr diagnostic verbatim (missing `gh`/`glab`, broken `#tracker-binding`, missing tracker auth env when `--no-tracker` is omitted, or ticket-ID case mismatch). Never expose `JIRA_PAT` / `YOUTRACK_TOKEN` values or `sign=` URLs.
- **No-op states (`event=idle`, `already_archived`, `no_active_prs`, `timeout`):** Clean up `"$SNAP"`, report the concise summary, and stop cleanly with zero file writes or git mutations.
- **Under `--dry-run`:** Classify and present every detected event and proposed action, clean up `"$SNAP"`, and stop without mirroring, editing, dispatching, replying, or writing watermarks.

## Step 2 — Mirror Unseen External Feedback Before Acting

When `has_new_comments=true` (unseen PR reviews, inline diff comments, PR conversation comments, or bound Jira/YouTrack ticket comments):

1. Check out or enter the ticket's active branch/worktree (creating `../worktrees/watch-<TICKET-ID>` if operating from a primary checkout per `.agents/skills/cadence-build/references/worktree-and-ledger.md`).
2. Append each unseen entry chronologically to `specs/<TICKET-ID>/submission.md` under `## Discussion`, embedding the exact deduplication tag right beneath the heading:
   ```markdown
   ### {author} — {timestamp} — {source}
   <!-- cadence-watch:item source={source} id={id} -->
   > {path:line or tracker key}
   {comment body}
   ```
   (`pr_watch.py` ignores replies carrying `<!-- cadence-watch:reply` and tracker preservation comments automatically so mirror/reply cycles never self-trigger.)

## Step 3 — Dispatch by Event & PR Kind

Evaluate the classified `event` and `pr_kind` (for `--all`, process each actionable ticket independently):

### 1. `event=merged` on `spec_mr` or `triage_mr`
1. Fetch and fast-forward pull `<integration-branch>` (`git fetch origin <integration-branch>`; pull local `<integration-branch>` if safe).
2. Confirm the approved contract landed (`git ls-tree origin/<integration-branch> specs/<TICKET-ID>/spec.md` for Medium/High; `problem.md` for Low/Trivial). If absent, **halt** citing missing landed artifact.
3. Run Step 4 watermark `--ack` first, then invoke `/cadence-build <TICKET-ID>` (honoring `CADENCE_ORG.md#sprint-enforcement-binding` and worktree isolation).

### 2. `event=merged` on `merge_request`
1. Fetch `<integration-branch>` (`git fetch origin <integration-branch>`), confirm the merge commit is reachable on `origin/<integration-branch>`, and cleanly fast-forward local `<integration-branch>` (`git pull --ff-only origin <integration-branch>`).
2. **Do not push direct `metadata.yaml` commits onto a protected `<integration-branch>`.** Invoke the bound `CADENCE_ORG.md#tracker-binding` sync skill once to project `merged`, and safely remove the merged ticket worktree/branch (`git worktree remove` + `git branch -d`, never `git branch -D` unverified).
3. Run Step 4 watermark `--ack`, invoke `/cadence-archive <TICKET-ID>` (which persists `merged_at` from the merge commit/forge PR if unset alongside `status: archived` inside its `archive/{type}/{id}` PR, pausing cleanly at any human-gated `adr-owed`, follow-up, or dead-citation disposition), and run `bash .agents/skills/cadence-doctor/doctor.sh --ticket <TICKET-ID> || bash skills/cadence-doctor/doctor.sh --ticket <TICKET-ID>`.

### 3. `event=changes_requested` or `event=comments_new`
Classify **every** unseen item against the ticket's approved `tier`, `problem.md`, `spec.md`, and ratified `decisions.md` Gate 1 rulings before editing any code or spec:

- **Scope change, tier escalation, new requirements, or contradiction with approved `spec.md` / Gate 1 rulings:** **HALT immediately and escalate to the human operator.** Commit or preserve the Step 2 `submission.md` mirror note, do **not** alter `tier:`, approved `spec.md`, or production code, and report exact conflicting items.
- **In-scope specification revision (`pr_kind=spec_mr`):** Resume the spec worktree, apply localized revisions or invoke `/cadence-spec <TICKET-ID>`, re-run `verify-spec.sh <TICKET-ID>` and `verify-facts.sh <TICKET-ID>` until exit `0`, commit and push to the spec branch, and post a reply on the PR (`gh pr comment` / `glab mr note`) tagged `<!-- cadence-watch:reply for=<id> -->`.
- **In-scope implementation revision (`pr_kind=merge_request`):**
  1. Check `ledger_cycles_completed` from Step 1. If `>= 4` (or `cycle_cap_reached=true`), **HALT and prompt the operator** — never self-authorize a 5th cycle.
  2. Resume the ticket's isolated worktree (never spawn a new worktree from a stale ref when the existing branch already carries commits).
  3. **Root-Cause Generalization & Sibling Sweep + Cold Rework Gate:** Before implementing the targeted fix, walk **every subsequent `await`, cleanup, and error boundary** in touched functions and grep all sibling classes/callers/repos sharing the flaw so all related instances are fixed in one pass. Execute the BDD fix via `/cadence-implement <TICKET-ID>` (or `cadence-implementer`), verify `verify-facts.sh --trace <TICKET-ID>`, run Step 0 `offload_deep_review`, and re-run `/cadence-review <TICKET-ID>` (which forces `breaker-trigger.sh` into `mode=rework` dispatching zero-spec `cadence-breaker`, and increments `<!-- cadence-run:cycle ... -->`) **before** pushing or re-requesting review.
  4. Push updated commits to the PR branch, reply on the PR (`gh pr comment` / `glab mr note`) tagged `<!-- cadence-watch:reply for=<id> -->`, and note resolution on the tracker only if the comment originated from Jira/YouTrack (respecting `CADENCE_ORG.md#tracker-binding` one-directional sync rules).
- **Question / clarification:** Ground the answer directly in the codebase, `spec.md`, and `decisions.md` (via `local_semantic_embed` when `:11434` is reachable, or `read_file`), and post a concise reply tagged `<!-- cadence-watch:reply for=<id> -->`. If policy/product judgment is uncertain, halt and ask the human.
- **Non-blocking out-of-scope observation:** Mirror in `submission.md` `## Discussion` tagged with explicit finding class (`[out-of-scope-defect]`, `[nit]`, `[hygiene]`, `[observation]`, `[adr-owed]`) for disposition at the next human gate (`followup-disposition.md`).

### 4. `event=ci_failed`
Inspect failing checks (`gh pr checks` / `gh run view --log-failed` or `glab ci trace`), piping logs >30 lines through `offload_log_triage` when `:11434` is reachable. If caused by an in-scope code, test, or lint defect (and `ledger_cycles_completed < 4`), fix in the ticket worktree, re-run verification + optional `offload_deep_review`, and push; halt loudly on external infra outages or cycle cap `>= 4`.

### 5. `event=approved` (unmerged)
**Never self-merge silently.**
- **`merge_request`:** Invoke `/cadence-close <TICKET-ID>` (enforcing Gate 3 `/cadence-maintain` at Medium/High and explicit operator merge confirmation).
- **`spec_mr` / `triage_mr`:** Report spec PR approved on the forge and prompt the human reviewer/operator to merge it so `/cadence-build <TICKET-ID>` can begin.

### 6. `event=closed_unmerged`
**HALT (`halt_human_rejected`).** Record a rejection note in `submission.md` / `decisions.md`; never automatically set `status: cancelled` or run `/cadence-archive` without explicit human confirmation and a populated `resolution:` field.

### 7. `event=unsupported_forge` (SourceHut)
Emit an explicit warning that `lists.sr.ht` patchset threads cannot be auto-polled by `pr_watch.py`; instruct the operator to mirror mailing-list replies manually into `specs/<TICKET-ID>/submission.md`.

## Step 4 — Write-After-Completion Watermark Ack

Only **after** Step 2 mirroring and Step 3 dispatch/remediation/replies succeed (skip on `--dry-run`, `idle`, `timeout`, or error halts so failed runs retry safely):

```bash
python3 .agents/skills/cadence-watch/scripts/pr_watch.py --ack <TICKET-ID> --from-snapshot "$SNAP" \
|| python3 skills/cadence-watch/scripts/pr_watch.py --ack <TICKET-ID> --from-snapshot "$SNAP"
rm -f "$SNAP"
```

## Run-End Checklist

1. **Ticket(s) & PR:** `<TICKET-ID>`, `pr_kind`, `pr_url`, `forge`, `integration_branch`.
2. **Observed state:** `event`, `pr_state`, `review_decision`, `ci_status`, `tracker_status`, `ledger_cycles_completed`.
3. **Mirrored items:** count and IDs added to `submission.md` `## Discussion` (or `none`).
4. **Action taken / halt reason:** downstream skill invoked, PR fixes/replies pushed, or explicit human escalation/gate halt.
5. **Watermark status:** `acked (<watermark_file>)` or `unacked (<reason>)`, plus worktree path if left standing.
