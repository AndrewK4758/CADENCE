# Test Scope -- Tests Validate Application Functionality Only

**Status:** Normative. Governs every automated test across every test project in this repository.

## The rule

An automated test's subject is exclusively the runtime software this repository builds and ships -- never a governance or specification document describing how that software is developed. Consequently, no test may read, parse, or assert against any of the forbidden subjects listed below.

## Forbidden subjects

No test reads, parses, or asserts on any of the following paths. They are defined as the artifact trees CADENCE itself installs or governs, ensuring the boundary holds uniformly across every programming language and technology stack:

- **The compiled agent, skill, and hook tree installed by your runtime binding.** Resolve the concrete directory root from `CADENCE_ORG.md#runtime-binding` rather than hardcoding a path; the reference bindings install into `.agents/**` (primary), `.gemini/**` (Antigravity), or `.opencode/**`.
- **`archive/**`** -- completed tickets' historical specification and closeout artifacts.
- **`docs/**`** -- all documentation and policy files under the documentation root, including this policy.
- **`specs/**`** -- active tickets' problem statements, specifications, test plans, submission records, and decision logs.
- **Root-level governance prose** -- `AGENTS.md`, `CADENCE_DIRECTIVES.md`, `PROJECT_INTENT.md`, `README.md`, and `CHANGELOG.md`.

A test that reads any of these files asserts on prose phrasing rather than application behavior. Such tests break whenever documentation is clarified or reworded, training engineers to ignore failing test suites as noise and turning routine documentation maintenance into a test-repair chore.

## What is still in scope

Everything the application itself loads, parses, or executes at runtime, along with the production source code that builds it and the dedicated test fixtures consumed by the test suite. The deciding question is never "which folder does this file sit in?", but rather "does the shipped application read or execute this file at runtime, or is this dedicated test fixture data?".

Concrete stack examples belong in the adopting repository's own contributor guidance rather than in this portable policy, because runtime configuration files vary across languages and frameworks. State your stack-specific examples in your repository's `AGENTS.md`; this policy establishes the invariant boundary.

## Scope of this rule

The forbidden paths above represent documents that govern *how the software is built*, not the software itself. In a repository whose **shipped product** IS the governed document and tooling corpus -- such as the CADENCE framework repository itself, a standards corpus, or a documentation compiler -- those files constitute the application surface under test, and this prohibition does not apply to them.

Whether a repository falls on the application side or the document-product side of that line is **explicitly declared, never heuristically inferred**. Every repository records its stance in `CADENCE_ORG.md#test-scope-binding`, and the three enforcing roles resolve that binding before applying this policy. Requiring an explicit declaration rather than guessing from file extensions is intentional: a heuristic that guesses whether markdown files are your product will eventually guess wrong silently.

## Enforcement

Three CADENCE roles enforce this boundary, each carrying a specific duty:

- **implementer (`cadence-implementer`)** -- never writes a test that reads or asserts on a forbidden governance path. Whenever an acceptance criterion is purely documentary, the implementer records it in `specs/{ticket-id}/decisions.md` for human verification at the review gate rather than fabricating a file-reading test.
- **code-reviewer (`cadence-reviewer`)** -- flags any test that reads or asserts on a forbidden path as a **blocking** finding whose required resolution is deleting the test rather than weakening its assertion.
- **spec-author (`cadence-spec-author`)** -- never authors a Gherkin scenario whose `Then` assertion is satisfied by inspecting a governance or specification document.
