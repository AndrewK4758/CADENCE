# Version Scheme: Calendar Versioning, zero-padded ISO year.week (calver-yyyy-ww)

> **Scheme-name-agnostic binding, scheme-specific narrative.** This document names the bump
> vocabulary and the next-version rule for the `calver-yyyy-ww` scheme. It declares no value the
> [Version-Scheme Binding](../../agentic-sdlc/CLAIRE_ORG.md#version-scheme-binding) does not also
> carry (`version-pattern`, `cycle-qualifying-cut`); this document is not a second source for
> those fields.

This document models a **calendar version** of the shape `YYYY.WW.PATCH`, where `YYYY` is the
ISO week-numbering year and `WW` is the zero-padded two-digit ISO week, both as `date +%G.%V`
emits natively. It is one of the two scheme documents CLAIRE ships; a repo selects it via the
[Version-Scheme Binding](../../agentic-sdlc/CLAIRE_ORG.md#version-scheme-binding)
(`bound-version-scheme: calver-yyyy-ww`).

## Legal spelling

| Field | Value |
|---|---|
| `version-pattern` | `^[0-9]{4}\.(0[1-9]\|[1-4][0-9]\|5[0-3])\.(0\|[1-9][0-9]*)$` |
| `cycle-qualifying-cut` | non-patch (a cut where the `YYYY.WW` prefix advances; a same-week PATCH-only cut does not count as one release cycle) |

**This scheme has no fixed release rhythm.** At most one qualifying cut can occur per ISO
week (the `YYYY.WW` prefix only changes once the calendar week changes), and many weeks will
have no cut at all. A "2 release cycle" guarantee under this scheme therefore counts actual
qualifying cuts, however long they take to accumulate -- it is never computed as a fixed
calendar end date.

**Exactly one spelling is legal.** The ISO week is **zero-padded to two digits**
(`2026.09.0`, never `2026.9.0`), because `date +%G.%V` emits the padded form natively. The legal
spelling is the one the derivation command already produces, and the unpadded form requires a
deliberate extra stripping step nobody has a reason to take. A version string that does not match
`version-pattern` is never written.

## Classify the bump (retained as a compatibility signal)

The same classification rules as `semver.md` are retained here, not as a number source (the
version number under `calver-yyyy-ww` is derived from the calendar, never from the bump), but as a
**compatibility signal** carried into the release notes' *Breaking changes* section:

- **MAJOR-equivalent** (any **breaking** change: the same signals `semver.md` names, a removed or
  renamed registered/public surface, a broken contract, an enacted deprecation/sunset).
- **MINOR-equivalent** (additive capability, no breakage).
- **PATCH-equivalent** (fixes and housekeeping only, no new or changed public surface).

The classification is reported and carried into the release notes; it never alters the derived
version number.

## Compute the next version

```
next_version(current, today):
  ww  = date +%G.%V           # e.g. 2026.39, zero-padded by construction
  if current starts with "<ww>." then  patch = current.patch + 1
  else                                 patch = 0
  return "<ww>.<patch>"
```

- A first cut in a new ISO week proposes patch `0`.
- A second (or later) cut in the **same** ISO week increments the patch.
- A cut after the ISO year rolls over resets the patch to `0` under the new year/week.

## Worked Examples

```
/claire-release
```

Today is ISO year 2026 week 39 and the current version is `5.1.0` (the last cut predates this
scheme). `date +%G.%V` resolves `2026.39`; no version this week exists yet, so the patch is `0`.
Proposes **`2026.39.0`**, admitted by `version-pattern` and ranking strictly above `5.1.0`.

```
/claire-release
```

Run a second time in the same ISO week, current version `2026.39.0`. `date +%G.%V` still resolves
`2026.39`; the current version already starts with `2026.39.`, so the patch increments. Proposes
**`2026.39.1`**.

```
/claire-release
```

Run after the ISO year rolls over, current version `2026.52.3`. `date +%G.%V` now resolves
`2027.01`; the current version does not start with `2027.01.`, so the patch resets. Proposes
**`2027.01.0`**, ranking strictly above `2026.52.3`.
