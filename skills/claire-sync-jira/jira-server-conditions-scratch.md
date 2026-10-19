# `/claire-sync-jira` — reported conditions: scratch staging and import seed

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-247).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-conditions.md` — every script writes its result to
**stdout** and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines. Nothing here
is a second implementation; each condition below is emitted by the named script, and this file is the
operator-facing catalogue of what each one means.

**Every name in this file is verified against the emitting line in the script.** A condition that is
documented but never emitted, or emitted but described as something else, is the defect class BTG-075's
re-reviews kept finding.

**This file is a further part of one catalogue, not another catalogue.** BTG-247 split it off because
`jira-server-conditions.md` stood at **398** lines against a `-lt 400` ceiling, so the new conditions
had nowhere to land in place. **Split, never truncated**, exactly as BTG-102, BTG-105, BTG-168, BTG-173
and BTG-205 did before it.

---

## Scratch staging (`syncjs.<scope>.scratch_unavailable`, every script — BTG-079 AC-4/AC-5)

Every script that builds a request body stages it in a scratch file first. `mktemp` can fail — a full
or read-only `$TMPDIR`, a quota, `ENOSPC` — and BEFORE BTG-079 most call sites did not look. Two things
then went wrong at once, and neither was a condition an operator could route:

1. **The channel broke.** `mktemp` printed its own diagnostic to stderr, and the empty path it left
   behind made bash's next `> "$path"` redirect fail with a bare `line NNN: : No such file or
   directory`. DEC-001 gives stdout to `key=value` and stderr to `syncjs.*` conditions; a raw shell
   diagnostic is neither.
2. **The write silently degraded.** `js_rest` omits both `--data-binary` and the `Content-Type` header
   when the body path is empty, so an unstaged body goes out as a **bodyless** request — which a
   permissive server accepts — while the run reports success. DEC-057 named that hazard and closed it at
   the acceptance-criteria site; DEC-060 closed the child Epic Link site; both times the disclosure
   bounding the residual was itself wrong about how many sites remained (corrected by DEC-061).

BTG-079 closes the CLASS rather than counting instances again. Every `mktemp` in the adapter now
silences its own diagnostic and is guarded on its own line, and
`btg-075-structural-seams.test.sh` **OS-1.7** (`syncjs.script.unguarded_mktemp`, SEAM_VIOLATION) asserts
that over the whole compiled tree — so a NEW call site cannot be missed by an inventory. Each guard
keeps its own script's polarity, and every reported result value was already declared:

- **`syncjs.write.scratch_unavailable`** (Critical) — the MAIN request body could not be staged.
  **HALT**; nothing is sent. Sibling of `syncjs.write.body_unbuildable`.
- **`syncjs.ac.body_unbuildable`** (Warning) — the acceptance-criteria body BUILT EMPTY (as distinct
  from `syncjs.ac.scratch_unavailable`, where the file could not be created at all). The write is
  refused with `ac_result=body-unbuildable` and the sync continues. It is a separate probe because
  neither of the other guards can see it: the scratch file WAS created, and the state-4
  "no items recognized" guard reads `jq '.fields[$f] | length'` on a zero-length file, which errors to
  `""` and never to the `"0"` it compares against — so `--data-binary "@<empty file>"` went out and
  CLEARED the field under an `ac_result=projected` report.
- **`syncjs.worklog.scratch_unavailable`** (Critical) — **HALT**, posting nothing. A worklog cannot be
  un-posted, so a body this run could not stage is never sent on a guess.
- **`syncjs.comment.scratch_unavailable`** (Critical) — **HALT**. The as-filed original is still
  un-preserved, so the sync must not overwrite it — the same polarity as this step's read failures.
- **`syncjs.transition.scratch_unavailable`** (Critical) — **HALT**. A bodyless `POST /transitions` is
  rejected 400 and this step is BLOCKING.
- **`syncjs.reserve.scratch_unavailable`** (Critical) — **HALT**. No key is reserved; a key is never
  guessed.
- **`syncjs.import.scratch_unavailable`** (Critical) — **HALT**, nothing seeded. A partial seed is
  indistinguishable from a complete one to the caller.
- **`syncjs.link.scratch_unavailable`** (Warning) — no links are created; `links_created=0` and
  `link_result=rejected`. Best-effort, so it halts its BRANCH, not the ticket. `jira-link-lib.sh`
  reports the same condition under its caller's `$JS_LINK_REPORT_PREFIX` and returns non-zero for that
  one link, exactly as its `link_body_unbuildable` sibling does.
- **`syncjs.umbrella.scratch_unavailable`** (Warning) — no child Epic Links are set;
  `epic_result=rejected` at exit 0 (DEC-033).
- **`syncjs.assign.rejected`** (Warning, pre-existing value reused) — the assignee body could not be
  staged, so no assignment call is made. Assignment is best-effort and its enumeration already carries
  `rejected`; a scratch failure is one more way the assignment did not happen.
- **`syncjs.assign.body_unbuildable`** (Warning, BTG-084) — the assignee body could not be BUILT, as
  distinct from `rejected` above, which is the instance's verdict. **Observed** unguarded (against a test
  stub, not a live instance): a 0-byte body reached the wire under `assign_result=applied`. Whether a real
  Jira reads that as a field CLEAR or rejects it is **not verified here** — either way the run reported a
  write that did not happen. Emits the declared `assign_result=rejected`; exit 0.

**The transport's capture file is the ONE deliberate exception, and it degrades rather than refuses**
(AC-5). `js_rest` / `js_rest_download` stage a temp file solely to capture curl's `-sS` diagnostic. That
file is a diagnostic AID, not the exchange — and because it was the FIRST `mktemp` in a run, a globally
unusable `$TMPDIR` used to halt the whole run with `syncjs.transport.rest_unreachable`: loud and safe,
but a **misdiagnosis**, since nothing had been sent and the instance was never unreachable. An
unstageable capture file now degrades only the DETAIL (`JS_TRANSPORT_ERROR` says the diagnostic could
not be captured) and the exchange proceeds, so the run halts at the first site where a scratch file is
genuinely load-bearing — the request body — under a `scratch_unavailable` condition that names what
actually failed.

## Import seed (`jira-import.sh`)

- **`syncjs.import.no_reverse_map`** (Info) — the Jira issue type has no **unique** inverse in
  `issue_type_map`, so **no `type:` hint is emitted** and the imported ticket is left untyped for
  triage to classify. `Bug`'s preimage is `{bug, security}`, and seeding `bug` there would risk
  mislabeling security work. The inverse is computed from the config rather than restated as a second
  table, so it cannot drift from the forward mapping.
- The **attachment manifest** (`manifest_file=`) carries one line per attachment — source key, id,
  sanitized filename, size, `mimeType`, and its disposition (`path:` stored, `url:` referenced,
  `failed:` fetch failed). `/claire-triage` renders exactly one `## Supporting Evidence` bullet per line.
  Counts alone cannot tell a caller **which** attachment is missing, and a referenced attachment's URL
  never left the script at all (BTG-043).

