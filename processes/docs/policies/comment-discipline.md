# Comment Discipline -- Keep a Comment Only If Deleting It Loses Information

**Status:** Normative. Applies to inline code comments a change adds or modifies. It does not
require or authorize retroactive rewriting of comments that predate the change carrying this
policy (see Scope).

## The rule

Keep a comment only if deleting it would lose information a reader cannot recover from the code
itself, the governed record (`archive/`, `docs/`), or git history.

## What survives

A comment that passes the rule above is one of: an unrecorded "why" (a rationale not already
captured elsewhere); a non-obvious ordering or concurrency constraint; a workaround for an
external defect; a boundary comment's required minimum fields (see `C7` below); or an API
documentation comment on a registered public surface (see `C8` below). Everything else fails the
rule and is not written. A pre-existing comment that fails the rule is deleted only when a later,
unrelated change already needs to rewrite that specific comment for its own reasons (see Scope) --
never swept proactively.

## Conventions

- **C1 -- Fix the code before commenting it.** A comment that explains *what* code does is
  resolved by renaming or restructuring the code, never by writing or keeping the comment.
- **C2 -- Big "why"s go in the record; the comment is a pointer.** A rationale longer than one
  line is recorded as a `decisions.md` DEC entry. The comment is reduced to the pointer
  `ABC-123 DEC-4` (form `{TICKET-ID} DEC-{N}`). DEC entries are immutable once recorded; a
  superseding decision is a new entry that references the old one, so the pointer keeps resolving.
- **C3 -- No change narrative.** A comment never describes the change instead of the code:
  "added for X", "previously did Y", "fixed per review", "moved from Z", "no longer needed
  because...". That narrative belongs in the commit message and `submission.md`. Narrative is
  defined by what the comment *describes* (the diff) rather than by phrase-matching a banned word
  list -- a comment that uses a temporal word to describe the code itself ("previously-allocated
  buffer") is not narrative.
- **C4 -- Pointers cite ids, never ticket-artifact paths.** A pointer cites `ABC-123`,
  `ABC-123 S-2.3` or `ABC-123 DEC-4`, never a `specs/<id>/...` or `archive/<id>/...` path. Ids
  stay valid after a ticket is archived; paths do not. A stable `docs/` path is not a
  ticket-artifact path and is not covered by this convention.
- **C5 -- Test tags cite the ticket id and scenario id(s).** A test carries a one-line tag, in a
  comment or in its own name, naming the ticket id and the scenario id(s) it covers (for example
  `// ABC-123 S-2.3`, or both ids for a test covering two scenarios: `// ABC-123 S-2.3, S-2.4`).
  The Gherkin `Given`/`When`/`Then` text itself lives only in `test-plan.md` and is never restated
  as a comment. At Low tier, where there is no `test-plan.md`, the tag cites the acceptance
  criterion instead: `// ABC-123 AC-2`.
- **C6 -- Ticketed TODOs; no commented-out code.** A `TODO` comment always carries a ticket id; a
  `TODO` with no ticket id is not written. Commented-out code is deleted rather than kept, because
  git history already retains it.
- **C7 -- Boundary comments carry only their minimum fields.** A header comment on a
  boundary-crossing file carries its bounded context/flow and a citation to the external
  invariant it relies on -- by id or `docs/flows/` anchor, never restated (BTG-341 DEC-008); a
  docstring on a boundary-crossing function carries its upstream inputs, downstream effects
  and a ticket-id reference. Both carry only these fields -- any elaboration, including the
  invariant's own text, belongs in the referenced `docs/flows/` document, not inline. A comment
  carrying its required fields is complete regardless of length; it is never flagged as missing
  or deficient for being short, and citing rather than restating the invariant is never itself a
  missing-field finding.
- **C8 -- Registered public-surface doc comments are contract, not commentary.** API
  documentation comments that are part of a registered public surface's published contract (XML
  doc comments, Javadoc, JSDoc, docstrings on an exported API, or the stack's equivalent) are
  exempt from the content-removing conventions above -- the delete test, C1, C2's length rule, and
  C7's boundary terseness -- because shortening or deleting them would remove contract content.
  They stay bound by C3, C4 and C6. "Registered" is a declared fact (the adopter's own
  `docs/policies/surface-registry.md` or this repository's `docs/policies/claire-surfaces.md`),
  never inferred from a surface merely being public. A boundary docstring that is also a
  registered contract gets the C8 exemption for its contract text, but C7's required fields are
  still required.

## Behavior 6 applies to comments

A comment that a change makes inaccurate is updated or deleted in the same change that falsifies
it (`CLAIRE_DIRECTIVES.md` Behavior 6). This holds even when the falsified comment sits in a file
outside the change's own Files Affected list -- Behavior 6 outranks "touch only what you must" for
a fact the change itself falsified.

## Scope

This policy governs inline code comments only -- not `spec.md`, `problem.md`, or other prose/spec
documents. It applies **prospectively only**: it does not require or authorize a sweep of
comments that predate the change that adopts it. An existing comment is brought into conformance
only when an unrelated, later change already needs to rewrite that specific comment for its own
reasons.

## What the pointers rely on

A `{TICKET-ID} S-{N}` pointer relies on scenario ids staying stable once a spec is approved. A
`{TICKET-ID} DEC-{N}` pointer relies on `decisions.md` entries being immutable. Both rely on
archival (`specs/<id>/` to `archive/<id>/`) leaving ticket ids unchanged.

## Enforcement

The implementer writes to this rule when it writes or rewrites a comment. The reviewer enforces
it in both directions: it still flags missing boundary documentation (C7), and it flags -- as a
**non-blocking** finding, scoped to comments the change under review itself added or modified -- a
comment that fails the delete test, carries a change narrative (C3), cites a path instead of an id
(C4), or restates governed Gherkin or acceptance-criteria text. A comment whose exact text appears
among the diff's removed lines has moved, not been added, and is out of scope. The reviewer also
flags, as a **non-blocking** finding, a pre-existing comment that the diff's own code change makes
inaccurate (the Behavior 6 fold above) -- this check is in scope on a line the diff did not itself
touch, because Behavior 6 outranks the touched-only scope for a fact the change itself falsified.
A comment-only finding set never yields a blocking verdict.
