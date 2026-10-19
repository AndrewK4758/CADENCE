# `/claire-sync-jira` — reported conditions: links and transition hops

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, ADR_CLAIRE-0025).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-conditions.md` — every script writes its result to **stdout**
as `key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>` lines
(`.claude/skills/claire-sync-jira/jira-server-scripts.md`, *the three-channel return contract*).

**This file is one part of one catalogue, not a second catalogue.** It was split off by BTG-102,
which documented three more conditions on the projection write and pushed the single file past the
400-line DX ceiling. The record is **split, never truncated**: facet conflict C-3 resolves Operability
above DX on *content*, and DX is served by the placement instead. The seam is by emitting script —
`jira-link.sh`'s link family and the one `jira-transition.sh` hop condition that travels with it — so a
reader chasing a `syncjs.link.*` name lands in one file rather than two.

The **umbrella projection** was later split off the same way, by BTG-105, and now lives in
`.claude/skills/claire-sync-jira/jira-server-conditions-umbrella.md`. That ticket also **retired** the
re-type conditions on the umbrella path (`syncjs.umbrella.retype_rejected`,
`syncjs.retype.type_unverified` and their `*_body_unbuildable` / `summary_*` siblings) along with the
writes they guarded; the re-type conditions on the **projection write** (`syncjs.write.issuetype_*`,
BTG-102) are a different family and are unaffected.

Everything else — transport, self-identity, worklogs, acceptance criteria, the preservation comment, the
estimate and the re-type conditions on the projection write, the `*_body_unbuildable` family, the
`type: epic` fork, scratch staging and the import seed — stays in
`.claude/skills/claire-sync-jira/jira-server-conditions.md`.

**Every name in this file is verified against the emitting line in the script.** A condition that is
documented but never emitted, or emitted but described as something else, is the defect class BTG-075's
re-reviews kept finding.

---

## The link account (BTG-107 AC-1)

Every non-linked disposition of a declared reference lands in exactly one of three stdout counters,
which partition `jira-link.sh`'s rejection total exhaustively and disjointly. Each counter names one
operator action:

- **`references_unreadable`** — the declaration could not be READ; zero requests were made. Fix
  `metadata.yaml`. Seeded from `jira-link-targets.sh`'s own refusal count (including a failed jq pass,
  below), and never incremented anywhere else in `jira-link.sh`.
- **`references_unresolved`** — the reference was read, but its far end could not be established:
  transport, 401/403/500, or a definitive 404. Fix the instance, or wait for the referenced ticket to be
  synced. A definitive absence and an auth/server failure share this one counter (BTG-107 DEC-007) — both
  mean "the far end could not be established", and the stderr condition names which.
- **`references_skipped`** — the reference resolved, but its link was not created, completed or confirmed
  this run (including an ordered link skipped because its type was unreadable — see `ordered_skipped`
  below). Re-run, or inspect the named condition.

`REJECTED`, the value that selects `link_result`, is a DERIVED SUM of the three — assigned exactly once,
never incremented directly — so the partition is exhaustive and disjoint by construction rather than by
discipline. `js_link_emit_account` is the SOLE writer of the stdout payload, called from every one of the
script's seven early-exit paths and from the main loop's tail, so no path can emit a partial account.

## Related-ticket links (`jira-link.sh`, best-effort)

- **`syncjs.link.created`** / **`syncjs.link.up_to_date`** / **`syncjs.link.rejected`** — the outcome
  for one target pair. A pre-existing link suppresses a new one only when it is of the **same type**.
- **`syncjs.link.referenced_absent`** — a definitive `404` for the referenced ticket on the direct key
  lookup: a genuine absence, skipped and reported. **BTG-124 (DEC-007) widened what reaches this
  condition.** Until then a `404` fell through to a summary search that matched the repo id embedded in
  the projected Summary; BTG-124 removed the id from the Summary and the gate deleted the fallback
  rather than re-pointing it. So a repo-id target that is **not itself a Jira key** is now reported
  absent here instead of being resolved. The accepted cost: a cross-reference to a not-yet-synced
  ticket does not link. It degrades quietly by design — the step is best-effort and exits `0` — but
  never *silently*: the absence is named and counted.
- **`syncjs.link.reference_unresolved`** — the question could not be ASKED (transport failure, 401,
  403, 500). Counted against the result so `link_result` is never `up-to-date`; retried next run
  (DEC-033). Still strictly distinct from `referenced_absent`: a failure to ask is never an answer.
- **`syncjs.link.reference_resolved`** — **RETIRED by BTG-124 (DEC-007) and no longer emitted.** It
  reported a repo id resolved to a Jira key by the summary-search fallback, which no longer exists.
  Recorded here rather than deleted so an operator grepping their transcripts for it learns why it
  stopped appearing instead of finding nothing.
- **`syncjs.link.signal_ambiguous`** — a flat `related_tickets:` entry's trailing comment asserts
  **both** landing directions at once; the entry degrades to the symmetric default rather than picking
  one and recording the ordering backwards (DEC-032).
- **`syncjs.link.type_undiscoverable`** — the instance's `issueLinkType` list could not be read. An
  unreadable list is **not** an absent type, so nothing is guessed and no ordered link is written this
  run.
- **`syncjs.link.type_fallback`** — no link type on the instance carries the `precedes` /
  `is preceded by` phrasing, so the symmetric default relation is used: the ordering semantics are lost
  and only the relation is recorded. The ordered type is always **discovered from the instance** by
  phrasing, never taken from the config's declared name — the config's `name`/`id` are anchors only
  (DEC-031).
- **`syncjs.link.ordered_skipped`** — an ordered link is skipped this run because the type is unknown;
  the type is never guessed. **BTG-107 AC-1**: this path is now COUNTED into `references_skipped`. Before
  this it incremented neither counter, so a run whose every target hit it emitted `links_created=0` with
  `link_result=up-to-date` — a clean run that linked nothing. `link_result` is now `rejected` on that path,
  the identical classification BTG-124 (DEC-007) applied to `referenced_absent`.
- **The ordered-link self-heal** — the one deletion this script ever makes, and the single sanctioned
  exception to its additive-only invariant. The correctly-ordered link is **created first** and verified
  **before** the reversed one is deleted, so no step can leave the pair unlinked (DEC-029):
  - **`syncjs.link.direction_reversed`** — a stored link records the ordering backwards; the heal
    begins.
  - **`syncjs.link.direction_healed`** — the replacement landed and was verified, and the reversed link
    was removed.
  - **`syncjs.link.heal_abandoned`** — the correctly-ordered replacement was **rejected**, so the
    reversed link is deliberately LEFT IN PLACE and nothing was deleted. The ordering still renders
    backwards, but the relation is not lost and the next run retries.
  - **`syncjs.link.heal_incomplete`** — the replacement is in place and verified, but removing the
    reversed link was refused: **both** links are present and the stale one needs removing by hand.
- **`syncjs.link.related_tickets_value_shape_unrecognized`** — a `related_tickets:` declaration is not
  something this step can read as a ticket reference. **BOTH ARMS report under this one name** — a KEYED
  sub-key's value or one of its list elements, and a FLAT list item — with the message text carrying the
  distinction (BTG-106 DEC-006; BTG-108 DEC-007). Four triggers, all one condition: the value is a **map**
  where a list or a scalar was expected; a list **element** is neither a ticket-bearing map nor a readable
  string; the candidate reference **does not look like a ticket reference**; or an assembled
  `<declaring-key> <target>` row does not carry **exactly two fields** with a reference-shaped target.
  "Looks like a ticket reference" is an **ALLOWLIST**: letters, digits, `_` and `-`, and nothing else. It was
  formerly a denylist (whitespace or any of `[`, `]`, `{`, `}`, `"`), which admitted `../../etc` and
  `CTS-61/62` — both reached the issue-key path segment **unencoded** (BTG-106 review item N-3, closed by
  BTG-108 DEC-001). The declaration is reported and
  skipped, **never interpolated** into an issue key: a structure sent as a REST path segment is a corrupted
  request, not a lookup (a whole `cross_ticket_coupling` array once reached the wire, truncated at the first
  space, on every run, silently — PROD_CLAIRE-011). Emitted **before** any target string is formed, so no call is
  made for it, and **counted** into the run's rejections, so `link_result` reads `rejected` and never `none`
  even when the unreadable declaration is the only one. The message names the sub-key, the position (its
  value, or element N) and the offending value truncated to 120 characters.
  The third trigger is what makes the second one true for **flow (inline) style**, which is the spelling that
  actually reaches this step as text: the metadata reader has no flow-mapping parser, so
  `cross_ticket_coupling: {ticket: "CTS-70"}` arrives as that whole *string* and an inline list-of-maps
  arrives as its comma-split *fragments*. Both are refused here rather than interpolated, and so is
  `ticket: "CTS-61 and CTS-62"`, which the dedupe would otherwise truncate to `CTS-61` with no report at all
  (BTG-106 DEC-015/DEC-016).
  A **list** whose elements *are* readable is not this condition: it projects one link per element, each
  inheriting its sub-key's own declaring key (BTG-106 DEC-001/DEC-002/DEC-004).
  On the **FLAT** arm — the block sequence whose relation is stated in the trailing comment — the same
  condition fires for a list item that is a flow-style map, an inline sequence, a path-ish or slash-bearing
  value, or a phrase naming more than one ticket (`- CTS-72 and CTS-73`). Every arm's rows converge on ONE
  post-assembly validation chokepoint, so the question is asked once with one predicate, and a top-level
  ordering key's rows inherit it too **once they reach assembly** — an element under an ordering key that
  aborts the extraction pass *upstream* of assembly never becomes a row for the chokepoint to judge, and is
  spec R-3, owned by BTG-114 (BTG-108 maintainer gate). The unqualified earlier wording claimed coverage of
  that case and was false: a `precedes:` map element makes the run report `link_result=none` — a clean
  absence — while both it *and* an innocent sibling declaration vanish. The message names the **declaring key**
  and the offending value
  truncated to 120 characters with whitespace runs collapsed. Before BTG-108 the flat arm ran no predicate at
  all: `- CTS-72 and CTS-73` linked `CTS-72` and discarded `CTS-73` with **zero reports**, and a flow map was
  interpolated verbatim — PROD_CLAIRE-011 live on the arm carrying every one of this repository's own declarations
  (BTG-108 DEC-003/DEC-008).
- **`syncjs.link.epic_exempt`** — the ticket is an Epic; its children carry the Epic Link field, so no
  issue link is created.
- **`syncjs.link.none`** — the ticket declares no related tickets; no link call is made. Reserved for a
  genuine absence: a declaration the step could not READ reports `rejected` instead (above).

## Additional link and transition conditions

- **`syncjs.link.link_read_failed`** (Warning) — the existing-link state of a pair could not be read,
  so the link is **not** created. "No such link" is an instruction to create one; "I could not look" is
  not. Conflated, a transient 5xx appended a duplicate on every affected run (Jira Server does not
  dedupe REST-created links), and a stored **reversed** link was left in place permanently and
  unreported because its id was never captured.
- **`syncjs.link.type_fallback`** (Warning) — the instance carries no link type by the configured name
  (`Duplicate` / `Cloners` / the ordered type), so the symmetric default is used: the relation is
  recorded but its specific meaning is lost. Stock names are renameable and localized, so they are
  discovered by name case-insensitively rather than hardcoded (AC-7).
- **`syncjs.transition.hop`** (Info) — the mapped target is not offered from the current status, so one
  **governed** intermediate hop is taken and the transitions are re-listed from there (the Bug
  workflow's `Code Review → In Progress → Done` path). A candidate must be a status this issue type's
  workflow map declares, must not already have been visited, and must be **unique** — two governed
  onward hops is a real choice between paths, and choosing one is refused.
