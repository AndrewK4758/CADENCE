# Test Scope -- Tests Validate Application Functionality Only

**Status:** Normative. Applies to every test in every test project in this repository.

## The rule

A test's subject is the software this repository produces -- never a governance document describing how that software is built -- so no test reads, parses, or asserts on the forbidden subjects below.

## Forbidden subjects

No test reads, parses, or asserts on any of the following. They are named as paths CLAIRE
itself installs or owns, so the set means the same thing in every language and every stack.

- **The compiled agent and skill tree your runtime binding installs.** Resolve the root from
  `CLAIRE_ORG.md#runtime-binding` rather than assuming a literal; the two reference bindings
  place it at `.claude/**` and at `.opencode/**` respectively.
- **`archive/**`** -- completed tickets' artifacts.
- **`docs/**`** -- every document under the documentation root, this policy included.
- **`specs/**`** -- in-flight tickets' problem statements, specs, test plans and decision logs.
- **Root-level governance prose** -- `CLAUDE.md`, `CLAIRE_DIRECTIVES.md`, `PROJECT_INTENT.md`,
  `README.md` and `CHANGELOG.md`.

A test that reads any of these is asserting on a sentence, not on behaviour. It reddens when the
sentence is reworded, which trains reviewers to read red as noise and turns ordinary editing into
a test-fixing exercise.

## What is still in scope

Everything the application itself loads or executes at runtime, plus the source that produces it
and the fixtures its tests consume. The test is not "which directory is this in" but "does the
product read this when it runs, or is this the source that becomes the product".

Concrete examples belong to the adopting repository, not to this framework, because the file
that carries runtime configuration in one stack does not exist in another. Name yours in your own
repository's contribution guidance; this policy states the principle and stops there.

## Scope of this rule

The forbidden subjects are the documents that describe how the software is built. They are not
the software. In a repository whose **product** IS the governed document corpus -- a framework,
a standards body, a documentation generator -- those documents are the application surface, and
this rule does not reach them.

That condition is **declared, not inferred**. A repository states which side of the line it is on
in `CLAIRE_ORG.md#test-scope-binding`, and the three enforcing roles resolve that binding before
enforcing anything. Declaring it rather than detecting it is deliberate: a rule that guesses
whether your documents are your product will guess wrong, and the wrong guess is silent.

## Enforcement

Three roles carry this rule, each with its own obligation:

- **implementer** -- never authors a test whose subject is a forbidden path. A documentary
  acceptance criterion is recorded in the ticket's `decisions.md` as verified at the human gate,
  never turned into a test.
- **code-reviewer** -- a test asserting on a forbidden path is a **blocking** finding, and the
  remedy is deletion rather than narrowing.
- **spec-author** -- never writes a scenario whose expected outcome is satisfied by reading a
  governance document.
