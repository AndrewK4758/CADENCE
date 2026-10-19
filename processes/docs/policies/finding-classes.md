# Non-Blocking Finding Classes

**Status:** Normative. Consumed by `cadence-reviewer`, `cadence-maintainer`, `/cadence-review` step 6,
`/cadence-maintain` step 6b, `/cadence-archive` steps 1b and 2e, and `cadence-archivist` step 6.
This policy is the single authoritative definition of the five non-blocking finding classes, the
high-value bar, the bracketed entry grammar, classification ownership, and disposition routing.
Every consuming skill and role **points** to this document; none restates it (`CADENCE_DIRECTIVES.md` Behavior 6).

## The organizing principle

Any real defect inside the diff under review is **blocking**. Consequently, a non-blocking finding
inside the diff is never a defect. Only a genuine defect that this change will not fix warrants
filing a follow-up ticket.

## The five classes

| Class | Definition | Offered as a candidate? | Disposed where |
|---|---|---|---|
| `out-of-scope-defect` | A real defect this change will not fix -- outside its footprint, or a residual a gate rules out of scope (ADR_CADENCE-0043) -- that clears the high-value bar below | Yes | The gate's disposition step |
| `adr-owed` | An ADR is owed for a decision **this change** makes | Never at review or maintain | `/cadence-archive` step 1b only |
| `nit` | Stylistic or cosmetic preference. No defect | Never | Logged |
| `hygiene` | Routine upkeep: boundary docs, doc freshness, naming, an evidence-confirmation request | Never | Logged |
| `observation` | Context, credit, or a question with no action owed | Never | Logged |

## The high-value bar (`out-of-scope-defect` only)

**"Would this be filed if it were found on its own?"** Any issue that does not clear this bar is
classified according to its actual nature (`nit` / `hygiene` / `observation`), never as
`out-of-scope-defect`.

## Entry format

```
N. [<class>] <location> -- <description>
N. [adr-owed] <decision ref> -- ADR must cover: <scope>; waits on: <precondition | none>
```

The bracketed `<class>` token must be one of the five exact lowercase strings above. Any deviation
-- missing token, misspelling, uppercase characters, multiple tokens, or an `adr-owed` entry omitting
either required clause -- renders the entry **UNCLASSED**.

## Who classifies

Each authoring role classifies **only its own entries**. Neither review role re-classifies the
other's entries, and no orchestrating skill re-classifies any entry. If a role disagrees with
another role's classification, it records a separate finding under its own class citing the earlier
entry; it never edits the original entry in place.

## Routing at a disposition step

1. **Unlabelled entry:** any entry carrying **no disposition yet** and lacking a valid class token
   halts the disposition step before candidate enumeration begins; entries that already carry a
   recorded disposition are legacy records and are exempt from this halt regardless of whether they
   carry a class token. Emit `finding.class.unlabelled` naming each unclassed entry (gate,
   authoring role, verbatim entry text). Prompt the human at the gate to supply a class label: an
   empty or unrecognized response re-prompts exactly once, and a second invalid response records
   `Deferred` citing `finding.class.unlabelled` rather than guessing a default class. When the
   operator supplies a valid class token, append `(class: <token>; supplied by <operator> at <gate>,
   <YYYY-MM-DD>)` beside the entry in `## Discussion` while leaving the entry's original text
   untouched, where `<operator>` resolves from `git config user.name` / `user.email`, falling back
   to the OS login name, or finally the literal string `identity could not be determined` -- never
   left blank. **That appended annotation serves as the entry's authoritative class** at all
   subsequent disposition steps across every gate: later halt checks, candidate filtering (step 2),
   the cumulative tally (step 3), `/cadence-archive`'s exit checks for `Follow-ups created` and
   `adr-owed` items, and -- when the supplied token is `adr-owed` -- presentation at
   `/cadence-archive` step 1b, all treat the annotation identically to an inline bracketed token. If
   no interactive confirmation channel is available, record `Deferred` naming the cause. Never
   default in either direction.
2. **Filter:** candidate set = all `out-of-scope-defect` entries that carry no disposition yet
   (plus, at `/cadence-archive`, any `adr-owed` items deferred during step 1b).
3. **Tally clause:** `N non-blocking findings logged (nit a, hygiene b, observation c, adr-owed d)`,
   accumulated across all gates. Classes with a count of zero are omitted, and the listed counts
   sum to `N`. This tally clause is included on the `None owed` disposition form, and on every other
   disposition form whenever one or more non-blocking findings have been logged.
4. **Prior-work check** (executed before presenting candidates): search both `specs/` (active work)
   and `archive/` (completed work) for each candidate, and present exactly one deduplication verdict
   -- `new`, `duplicate of <id>`, or `fold into <id>` -- citing the matched ticket ID. **Fold
   eligibility:** an open ticket is eligible to absorb a fold only when its status is `draft` or
   `triaged`. At any later open status, the verdict depends on whether the existing ticket already
   encompasses the candidate, never on status alone: a match that already **covers** the candidate
   (meaning the candidate adds nothing beyond what the target ticket already specifies) is presented
   as `duplicate of <id>` regardless of the target's lifecycle stage; a match that does **not**
   yet cover the candidate -- fold-shaped in topic, but the target ticket has progressed past
   `draft`/`triaged` and can no longer safely expand its scope -- is presented as `new` with the
   target cited as related context, **never** `duplicate of <id>` and **never** `fold into <id>`. An
   archived match provides historical context only and never suppresses a live defect -- it is
   always presented as `new`. Every `new` verdict records the search's actual return (search terms,
   both searched roots, and hit count), never merely a bare conclusion. If the prior-work search
   cannot execute, halt with `followup.dedupe.check_unavailable`; never default a candidate to `new`
   without searching.
5. **Confirmed outcomes:** `new` -> the gate writes the candidate's description to its draft file
   path and invokes `/cadence-triage --file-only <draft-path>` (BTG-345). `duplicate` -> files no
   ticket and records `Duplicate of <id> -- ...`. `fold into` -> re-verify the target ticket's fold
   eligibility (`draft` or `triaged` status per step 4) at write time, append a dated bullet to the
   target's `problem.md` under `## Notes`, record `Folded into <id> -- ...`, and execute the bound
   `CADENCE_ORG.md` §9 tracker sync for `<id>` at the end of the operation -- reporting any failed
   tracker projection loudly rather than skipping it silently (if no tracker is bound, state so
   explicitly). If the target ticket has advanced past `draft`/`triaged` by write time, re-present
   the candidate as `new` citing the target rather than folding into an in-flight spec. Never record
   `Folded into <id>` unless the write to the target's `problem.md` succeeded; a failed write
   records `Deferred`, never `Folded`.

## `adr-owed` at archive

Every `adr-owed` finding is presented at `/cadence-archive` step 1b alongside its recorded
precondition and the current evidence satisfying or blocking that precondition. The human operator
either **promotes** it (`cadence-archivist` step 6 then authors the new ADR citing the source ticket
and finding entry, without re-evaluating whether an ADR is warranted) or **defers** it with an
explicitly stated reason, in which case the item enters step 2e's candidate queue to be filed as a
tracked follow-up ticket via the standard `out-of-scope-defect` path. An `adr-owed` finding is never
dropped silently, and a previously recorded deferral or precondition never blocks promotion once its
stated condition is met.

If a valid `adr-owed` label is supplied during `/cadence-archive` step 2e.a -- meaning the finding
was unclassed until after step 1b had already completed -- it is recorded as `Deferred` with the
reason `"classed after /cadence-archive step 1b"` and routed directly into step 2e's candidate queue
just like a step 1b deferral, ensuring no `adr-owed` item is ever stranded without a promotion or
filing path.
