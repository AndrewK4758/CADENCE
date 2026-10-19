# Version Scheme: Semantic Versioning (semver)

> **Scheme-name-agnostic binding, scheme-specific narrative.** This policy specifies the bump classification rules and next-version arithmetic for the `semver` scheme. It declares no configuration value that is not already carried by the [Version-Scheme Binding](../../agentic-sdlc/CADENCE_ORG.md#version-scheme-binding) (`version-pattern`, `cycle-qualifying-cut`); this document provides the scheme narrative rather than a competing source for those fields.

This specification models **Semantic Versioning** (`MAJOR.MINOR.PATCH`): a three-component dotted version number in which the compatibility classification of the changeset determines which numeric field increments. It is one of the two portable versioning schemes shipped with CADENCE; a repository selects it through the [Version-Scheme Binding](../../agentic-sdlc/CADENCE_ORG.md#version-scheme-binding) (`bound-version-scheme: semver`).

**Relocated from the release skill.** The bump classification criteria, version arithmetic, and three worked examples below were extracted from `artifacts/commands/cadence-release.md` (its former inline step 2 and Worked Example section) when the declarative version-scheme binding was introduced (BTG-303), keeping the release skill scheme-neutral.

## Legal spelling

| Field | Value |
|---|---|
| `version-pattern` | `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$` |
| `cycle-qualifying-cut` | non-patch (a cut that advances MAJOR or MINOR; a PATCH-only cut does not count as one release cycle) |

## Classify the bump

Evaluate the entries under `[Unreleased]` in `CHANGELOG.md` against these rules in strict precedence order (the first matching level governs):

- **MAJOR** — any **breaking** change. Triggers include: a `### Removed` section or an enacted `### Deprecated` sunset; an entry documenting a **removed or renamed** registered/public surface, an incompatible output/CLI/spec/wire contract change, a modified default that alters existing runtime behavior, or a completed deprecation removal; changelog prose containing markers such as "breaking", "no longer", "removed", "renamed", "incompatible", or "must migrate"; or a **non-additive** modification to a surface listed as Stable in `PROJECT_INTENT.md` §5 (such as reorganizing or deleting steps in a stable agent or skill definition rather than appending).
- **MINOR** — **additive capability** with zero breaking changes. Triggers include: a `### Added` section; a net-new agent, skill, elicitation probe, Engineering Pillar, template, or policy; or a `### Changed` entry that strictly *expands* capability or documentation while keeping every existing contract and identifier intact.
- **PATCH** — **bug fixes and internal housekeeping only**. Triggers include: exclusively `### Fixed` entries, documentation clarifications, internal single-context refactors, or dependency updates — with **no new or altered public surface**.

Report the derived bump level alongside the specific changelog entries that triggered it. Whenever an explicit `$bump_override` argument is passed and **disagrees** with the derived classification, display both side-by-side and highlight the mismatch prominently (especially when an override forces a *downgrade* below a detected breaking change, which risks shipping an unannounced breaking release).

## Compute the next version

Calculate the target version from the current version and the selected bump level: MAJOR → `(X+1).0.0`, MINOR → `X.(Y+1).0`, PATCH → `X.Y.(Z+1)`.

## Worked Examples

```
/cadence-release
```

Inspects `[Unreleased]`, observes only additive `### Added` and `### Changed` entries (zero removals, zero renamed surfaces), proposes **vX.(Y+1).0** as a **minor** release citing the triggering changelog entries, and prompts for operator confirmation. Upon `yes`, it updates `CHANGELOG.md`, bumps the version badge in `README.md`, drafts the release notes and `specs/RELEASE-X.(Y+1).0/submission.md`, displays the diff, commits `RELEASE-X.(Y+1).0` on confirmation, creates the annotated Git tag, and — following a final confirmation — pushes the release branch and tag.

```
/cadence-release major
```

Follows the same sequence while forcing a **major** bump (`v(X+1).0.0`). The skill still executes its own changelog classification first; if the `[Unreleased]` entries appear purely additive, it emits a prominent warning ("override forces MAJOR over a minor-looking changelog — confirm this is intentional") before proceeding.

```
/cadence-release patch
```

Forces a **patch** bump (`vX.Y.(Z+1)`). If `[Unreleased]` contains any `### Added` or breaking-change signals, the skill flags the discrepancy loudly (since a forced downgrade can disguise a new feature or breaking change as a routine patch) and halts for explicit human confirmation.
