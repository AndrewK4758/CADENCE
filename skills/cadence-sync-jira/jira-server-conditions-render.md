# `/cadence-sync-jira` — reported conditions: deterministic markup rendering

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-205).
External invariant relied upon: identical to `.agents/skills/cadence-sync-jira/jira-server-conditions.md` — every script emits machine-readable results on **stdout** and audit conditions on **stderr** as `syncjs.<family>.<condition>` lines. Each condition cataloged below is emitted directly by the named script and verified by test harnesses.

**This file is a modular segment of the single condition catalog, split rather than truncated.** BTG-205 factored out the deterministic markup-rendering conditions so `jira-server-conditions.md` stays beneath the `<400`-line Developer Experience ceiling, matching the modular split pattern of BTG-102, BTG-105, BTG-168, and BTG-173. The script contracts for `jira-md2wiki.sh` and `jira-desc-lib.sh` reside in `.agents/skills/cadence-sync-jira/jira-server-scripts-render.md`.

---

## Markup conversion — `jira-md2wiki.sh`

### `syncjs.render.md2wiki_failed` (Critical)

Emitted when `jira-md2wiki.sh` cannot complete conversion over its Markdown input — most commonly due to an unclosed fenced code block (```` ``` ````). The filter exits `1`.

**Crucial safety guarantee: stdout remains completely EMPTY on failure.** Emitting a partially converted fragment to stdout would be dangerous because the caller would substitute the half-converted text into `ticket_TEMPLATE.md` and `PUT` it to Jira with HTTP 200, silently corrupting the live issue description. Therefore, `jira-md2wiki.sh` buffers its entire output in memory and prints to stdout only after conversion finishes cleanly with exit `0`.

**Operator remediation:** fix the malformed Markdown syntax in the source `problem.md` section (such as closing an unterminated code fence) and re-run `/cadence-sync-jira`. Never attempt to force-project a partial render.

---

## The wholesale-overwrite hazard — `jira-desc-lib.sh`

**Context on update-path description projection:** on the `update` path, `jira-write-issue.sh` replaces the Jira issue's `description` field **in full**. When a freshly rendered description is less complete or differently formatted than the live description in Jira, replacing it overwrites the live content with HTTP 200.

**Why omitting `--description-file` is NOT a valid workaround:** on the `update` path, omitting `--description-file` halts loud with `syncjs.description.update_reproject_absent` (BTG-062) because skipping description updates would silently strand repository edits to `problem.md`.

**How determinism eliminates false diffs:** because `jira-md2wiki.sh` is a pure, deterministic function of its input, re-rendering an unchanged `problem.md` produces a byte-identical wiki-markup description, so neither condition below fires on steady-state re-syncs. The two conditions below surface the remaining cases that determinism alone cannot prevent: when an issue's live description was previously written by a hand-rolled conversion or edited manually in the Jira UI.

**Operator workaround when a live Jira description must be preserved temporarily:** read the live description via REST, write those exact bytes into the description temp file, and let the sync re-project them unchanged (satisfying BTG-062 while you update `problem.md` to incorporate the desired content).

### `syncjs.description.reprojection_delta` (Warning)

Emitted when the freshly rendered wiki-markup description differs from the issue's current live `description` in Jira. Logs the ticket ID, the Jira issue key, and the added/removed line counts **in each direction** (so the operator can immediately tell whether the update is expanding or shrinking the description), while intentionally omitting the full description body from stderr logs.

**Non-blocking: the update `PUT` proceeds and overwrites the live description.** Making a description delta halt the sync was explicitly rejected (BTG-205 DEC-005) because halting would block every legitimate `problem.md` edit as well as the first sync after upgrading to `jira-md2wiki.sh`. Instead, this warning guarantees that a description overwrite is always visible in the audit stream.

**Expected one-time transition notice:** on the very first sync of a pre-existing issue after adopting `jira-md2wiki.sh`, any formatting differences between the legacy hand-converted description and `jira-md2wiki.sh`'s canonical output will trigger this warning once, and never again on subsequent unchanged runs.

**Operator remediation:** if `problem.md` and `metadata.yaml` were intentionally updated, no action is needed. If the repository artifacts were unchanged, inspect the issue description in Jira to confirm the canonical render looks as expected.

### `syncjs.description.live_read_unavailable` (Warning)

Emitted when the issue's current live `description` could not be fetched prior to the update `PUT` (due to a non-2xx response or unparseable body) — meaning **no before/after comparison could be performed**. Logged under its own distinct condition name and never conflated with "zero delta" (following the PROD_CADENCE-006 principle that "unable to check" and "verified clean" are distinct states).

**Non-blocking: the update `PUT` proceeds identically.** Only the pre-write delta comparison is skipped.

**Operator remediation:** none required for a one-off occurrence; if persistent, verify that the PAT has browse permission on the project's issues.
