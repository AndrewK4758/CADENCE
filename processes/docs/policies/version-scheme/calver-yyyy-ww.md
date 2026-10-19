# Version Scheme: Calendar Versioning, zero-padded ISO year.week (calver-yyyy-ww)

> **Scheme-name-agnostic binding, scheme-specific narrative.** This policy defines the bump classification vocabulary and next-version derivation algorithm for the `calver-yyyy-ww` scheme. It introduces no configuration value that is not already declared in the [Version-Scheme Binding](../../agentic-sdlc/CADENCE_ORG.md#version-scheme-binding) (`version-pattern`, `cycle-qualifying-cut`); this file serves as the human-readable specification, never a competing second source for those bound fields.

This specification models a **calendar versioning** scheme of the form `YYYY.WW.PATCH`, where `YYYY` denotes the four-digit ISO week-numbering year and `WW` denotes the zero-padded two-digit ISO week number, matching the native output of `date +%G.%V`. It is one of the two portable versioning schemes shipped with CADENCE; an adopting repository selects it via the [Version-Scheme Binding](../../agentic-sdlc/CADENCE_ORG.md#version-scheme-binding) (`bound-version-scheme: calver-yyyy-ww`).

## Legal spelling

| Field | Value |
|---|---|
| `version-pattern` | `^[0-9]{4}\.(0[1-9]\|[1-4][0-9]\|5[0-3])\.(0\|[1-9][0-9]*)$` |
| `cycle-qualifying-cut` | non-patch (a cut where the `YYYY.WW` prefix advances; a same-week PATCH-only cut does not count as one release cycle) |

**This scheme carries no fixed release cadence.** At most one qualifying release cut can occur within any single ISO week (because the `YYYY.WW` prefix advances only when the calendar week advances), and quiet weeks may have no release cut at all. Consequently, a "2 release cycle" deprecation guarantee under `calver-yyyy-ww` always counts actual qualifying release cuts across however many weeks they take to occur -- it is never converted into a fixed calendar deadline.

**Strictly one canonical spelling is valid.** The ISO week component is **always zero-padded to two digits** (`2026.09.0`, never `2026.9.0`), matching what `date +%G.%V` produces natively. Because the standard shell command emits the zero-padded form directly, an unpadded week number would require deliberate stripping and is rejected. No version string that fails `version-pattern` is ever written.

## Classify the bump (retained as a compatibility signal)

The impact classification rules defined in `semver.md` are retained under `calver-yyyy-ww` — not to calculate the version digits (which are derived from the ISO calendar), but as an explicit **compatibility signal** surfaced in the release notes' *Breaking changes* section:

- **MAJOR-equivalent** (any **breaking** change: matching the exact signals named in `semver.md`, such as a removed or renamed registered/public surface, an incompatible contract change, or an enacted deprecation sunset).
- **MINOR-equivalent** (purely additive capability with zero breaking changes).
- **PATCH-equivalent** (bug fixes, internal refactors, and documentation/housekeeping with no new or modified public surfaces).

`/cadence-release` reports this compatibility classification and writes it into the release notes without altering the calendar-derived version string.

## Compute the next version

```
next_version(current, today):
  ww  = date +%G.%V           # e.g. 2026.39, zero-padded by construction
  if current starts with "<ww>." then  patch = current.patch + 1
  else                                 patch = 0
  return "<ww>.<patch>"
```

- The first release cut in a new ISO week sets `PATCH` to `0`.
- Any subsequent release cut within the **same** ISO week increments `PATCH` by `1`.
- The first release cut after an ISO year rollover resets `PATCH` to `0` under the new `YYYY.WW` prefix.

## Worked Examples

```
/cadence-release
```

Suppose today falls in ISO year 2026, week 39, and the repository's prior version is `5.1.0` (cut under an earlier SemVer binding). `date +%G.%V` evaluates to `2026.39`; because no release has been cut in `2026.39` yet, the patch component starts at `0`. The skill proposes **`2026.39.0`**, which satisfies `version-pattern` and sorts strictly above `5.1.0`.

```
/cadence-release
```

Invoked a second time during the same ISO week when the current version is `2026.39.0`. `date +%G.%V` again returns `2026.39`; because the current version already begins with `2026.39.`, the patch component increments by one, proposing **`2026.39.1`**.

```
/cadence-release
```

Invoked after the ISO year boundary rolls over when the current version is `2026.52.3`. `date +%G.%V` now evaluates to `2027.01`; because the current version does not begin with `2027.01.`, the patch component resets to `0`, proposing **`2027.01.0`** (which sorts strictly above `2026.52.3`).
