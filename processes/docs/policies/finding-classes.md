# Non-Blocking Finding Classes

**Status:** Normative. Read by `claire-reviewer`, `claire-maintainer`, `/claire-review` step 6,
`/claire-maintain` step 6b, `/claire-archive` steps 1b and 2e, and `claire-archivist` step 6.
This is the single statement of the five classes, the high-value bar, the entry token format,
who classifies, and the routing rules. Every consumer **points** at this document; none restates
it (Behavior 6).

## The organizing principle

A real defect inside the diff is **blocking**. A non-blocking finding inside the diff is
therefore not a defect. Only a defect this change will not fix warrants a ticket.

## The five classes

| Class | Definition | Offered as a candidate? | Disposed where |
|---|---|---|---|
| `out-of-scope-defect` | A real defect this change will not fix -- outside its footprint, or a residual a gate rules out of scope (ADR_CLAIRE-0043) -- that clears the high-value bar below | Yes | The gate's disposition step |
| `adr-owed` | An ADR is owed for a decision **this change** makes | Never at review or maintain | `/claire-archive` step 1b only |
| `nit` | Stylistic or cosmetic preference. No defect | Never | Logged |
| `hygiene` | Routine upkeep: boundary docs, doc freshness, naming, an evidence-confirmation request | Never | Logged |
| `observation` | Context, credit, or a question with no action owed | Never | Logged |

## The high-value bar (`out-of-scope-defect` only)

**"Would this be filed if it were found on its own?"** A defect that fails this bar is classed
by its nature (`nit` / `hygiene` / `observation`), never `out-of-scope-defect`.

## Entry format

```
N. [<class>] <location> -- <description>
N. [adr-owed] <decision ref> -- ADR must cover: <scope>; waits on: <precondition | none>
```

The token is one of the five exact lowercase strings. Anything else -- absent, misspelled,
capitalized, two tokens, or an `adr-owed` entry missing either clause -- is **UNCLASSED**.

## Who classifies

The authoring role classifies **its own entries only**. Neither role re-classes the other's
entries, and no skill re-classes any entry. A role that disagrees with another role's class
raises its own new finding (in its own class) that cites the other entry; it never rewrites it.

## Routing at a disposition step

1. **Unlabelled entry:** an entry with **no disposition yet** and no valid class token halts the
   step before enumerating; an entry that already carries a disposition is a legacy record and is
   exempt from this halt, classed or not. Emit `finding.class.unlabelled` naming each entry (gate,
   authoring role, entry text). Request a label from the human at the gate: an empty or
   unrecognized answer re-prompts exactly once, and a second miss records Deferred naming
   `finding.class.unlabelled`, never classed by default. A valid supplied label is appended beside
   the entry in `## Discussion` as `(class: <token>; supplied by <operator> at <gate>,
   <YYYY-MM-DD>)`, leaving the entry's own text unchanged, where `<operator>` resolves from `git
   config user.name`/`user.email`, else the OS login, else the literal string `identity could not
   be determined` -- never left blank. **This note is the entry's class** from that point on, at
   every later disposition step, at any gate: every later halt check, the candidate filter
   (step 2), the tally (step 3), `/claire-archive`'s exit criterion for `Follow-ups created` and
   for `adr-owed` items, and -- when the token is `adr-owed` -- presentation at `/claire-archive`
   step 1b, all read it exactly as if the entry's own text carried that bracket token. With no
   confirmation channel at all, record Deferred naming the cause. Never default either way.
2. **Filter:** candidates = `out-of-scope-defect` entries carrying no disposition yet (plus, at
   `/claire-archive`, `adr-owed` items deferred at step 1b).
3. **Tally clause:** `N non-blocking findings logged (nit a, hygiene b, observation c, adr-owed d)`,
   cumulative across gates. Zero-count classes are omitted; the counts sum to N. Carried on the
   `None owed` form, and on every other form whenever at least one finding has been logged.
4. **Prior-work check** (before presenting): search `specs/` (open) and `archive/` (completed)
   for the candidate; present exactly one verdict -- `new`, `duplicate of <id>`, or
   `fold into <id>` -- citing the matched id. **Fold eligibility:** an open match is fold-eligible
   only at `draft` or `triaged`. At any later open status, the verdict turns on the match's
   relationship to the candidate, never on status alone: a match that already **covers** the
   candidate (the candidate adds nothing the target does not already describe) is presented as
   `duplicate of <id>`, regardless of the match's status; a match that does **not** cover the
   candidate -- fold-shaped, but the target has moved past `draft`/`triaged` and so can no longer
   safely absorb it -- is presented as `new`, citing the target as related, **never**
   `duplicate of <id>` and **never** `fold into <id>`. An archived match is related context and
   never by itself suppresses a candidate -- it is presented as `new`. A `new` verdict records the
   search's return (terms, both roots, hit count), never only a conclusion. If the check cannot
   run, halt with `followup.dedupe.check_unavailable`; never present a candidate as `new` by
   default.
5. **Confirmed outcomes:** `new` -> the gate writes the candidate's description to its draft path,
   then invokes `/claire-triage --file-only <draft-path>` (BTG-345). `duplicate` -> files
   nothing; record `Duplicate of <id> -- ...`. `fold into` -> re-check the target's fold
   eligibility (open, at `draft` or `triaged`, per Routing step 4) at write time, append a dated
   line to its `problem.md` `## Notes`, then record `Folded into <id> -- ...`, then run the bound
   `CLAIRE_ORG.md` §9 tracker sync for `<id>` at the end of the operation -- a failed projection is
   reported, never silently skipped (no tracker bound => nothing to sync, say so). A target that
   has moved on by write time is re-presented as `new` with the target cited, never folded. Never
   record a fold whose target write did not land; a failed target write is recorded Deferred,
   never Folded.

## `adr-owed` at archive

Presented at `/claire-archive` step 1b with its recorded precondition and the current evidence on
it. The human either **promotes** it (archivist step 6 authors the ADR, citing the source ticket
and entry, never re-judging whether one is owed) or **defers** it with a named reason, in which
case it joins step 2e's candidates under the ordinary `out-of-scope-defect` filing path. An
`adr-owed` item is never skipped silently, and a recorded deferral or precondition is never by
itself a bar to promotion once its stated reason no longer holds.

A valid `adr-owed` label supplied at `/claire-archive` step 2e.a -- an entry classed only after
step 1b already ran, so 1b never saw it -- is recorded Deferred naming the reason "classed after
/claire-archive step 1b", and is admitted to step 2e's candidates exactly as a step 1b deferral
is; it is never left with no path to promotion or disposition.
