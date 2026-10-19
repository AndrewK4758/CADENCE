# Version Scheme: Semantic Versioning (semver)

> **Scheme-name-agnostic binding, scheme-specific narrative.** This document names the bump
> vocabulary and the next-version rule for the `semver` scheme. It declares no value the
> [Version-Scheme Binding](../../agentic-sdlc/CLAIRE_ORG.md#version-scheme-binding) does not also
> carry (`version-pattern`, `cycle-qualifying-cut`); this document is not a second source for
> those fields.

This document models **Semantic Versioning** (`MAJOR.MINOR.PATCH`): a three-field dotted version
where a change's classification determines which field increments. It is one of the two scheme
documents CLAIRE ships; a repo selects it via the
[Version-Scheme Binding](../../agentic-sdlc/CLAIRE_ORG.md#version-scheme-binding)
(`bound-version-scheme: semver`).

**Relocated verbatim.** The classification rules, the arithmetic, and the three worked examples
below were relocated character-for-character from `artifacts/commands/claire-release.md` (its
prior step 2 and Worked Example section) when the version-scheme binding was introduced
(BTG-303). Nothing here was rewritten in the move.

## Legal spelling

| Field | Value |
|---|---|
| `version-pattern` | `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$` |
| `cycle-qualifying-cut` | non-patch (a cut that advances MAJOR or MINOR; a PATCH-only cut does not count as one release cycle) |

## Classify the bump

Classify the `[Unreleased]` content against these rules, in precedence order (first match wins):

- **MAJOR** — any **breaking** change. Signals: a `### Removed` or `### Deprecated`-then-enacted group; an entry describing a **removed or renamed** registered/public surface, a broken output/command/spec/wire contract, a changed default that alters existing behavior, or an enacted deprecation/sunset; prose containing "breaking", "no longer", "removed", "renamed", "incompatible", "must migrate"; a **non-additive** change to a surface registered Stable in `PROJECT_INTENT.md` §5 (e.g. an agent/skill instruction reorganized or deleted, not merely appended).
- **MINOR** — **additive capability**, no breakage. Signals: a `### Added` group; a new agent / skill / probe / facet / template / policy; a `### Changed` group that only *adds* behavior or text while preserving every existing contract and name.
- **PATCH** — **fixes and housekeeping only**. Signals: only `### Fixed`, documentation corrections, internal refactors, dependency bumps — with **no new or changed public surface**.

State the classification with the specific entries that drove it. If `$bump_override` was supplied and **disagrees** with the computed bump, show both and flag the disagreement prominently (especially a forced *down*grade past a breaking change — that is the dangerous case).

## Compute the next version

Compute the next version from the current version + bump: MAJOR → `(X+1).0.0`, MINOR → `X.(Y+1).0`, PATCH → `X.Y.(Z+1)`.

## Worked Examples

```
/claire-release
```

Reads `[Unreleased]`, finds it is all additive `### Added` / `### Changed` entries (no removals, no renamed surfaces), proposes **vX.(Y+1).0** as a **minor** release with the entries that drove the call, and asks for confirmation. On `yes`, it finalizes the changelog, bumps the README, drafts the release notes, shows the diff, commits `RELEASE-X.(Y+1).0` on confirmation, annotates the tag, and — after a final confirmation — pushes the branch and tag.

```
/claire-release major
```

Same, but forces a **major** bump. The skill still prints its own analysis; if the entries look purely additive it warns "override forces MAJOR over a minor-looking changelog — confirm this is intentional" before proceeding.

```
/claire-release patch
```

Forces a **patch** bump. If the changelog contains a `### Added` or a breaking entry, the skill flags the disagreement loudly (a forced downgrade can mislabel a feature or a breaking change as a fix) and waits for explicit confirmation.
