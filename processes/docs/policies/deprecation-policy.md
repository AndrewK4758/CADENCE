# Deprecation Policy

This document defines how public surfaces are deprecated, communicated to consumers, and eventually removed. All deprecations must follow this policy. The lifecycle of each deprecation is tracked by **the registry that owns the surface**: [`docs/policies/claire-surfaces.md`](claire-surfaces.md)'s *Deprecated / relocated surfaces* table for a **core-owned** surface, [`docs/policies/surface-registry.md`](surface-registry.md)'s Deprecation Log for an **adopter-owned** one. Routing a core-owned deprecation to the adopter-owned table announces it where no consumer of that surface reads (BTG-200; this sentence corrected by BTG-275).

## Deprecation Periods

Minimum time between deprecation announcement and surface removal, by surface type:

| Surface Type | Minimum Deprecation Period | Rationale |
|---|---|---|
| Public API endpoints | 2 release cycles | External consumers need time to migrate; coordinated rollouts required |
| Inter-service contracts (events, shared DTOs) | 1 release cycle | Internal consumers can be coordinated more quickly |
| Configuration keys (env vars, feature flags) | 1 release cycle | Deployment infrastructure changes require pipeline updates |
| Database contracts (shared tables/views) | 2 release cycles | Schema migrations require coordinated deployment across services |
| CLI arguments / SDK methods | 2 release cycles | Downstream tooling and scripts need migration time |
| Agent / skill definition (an agent definition, or a slash command and its co-located sidecars) | 2 release cycles | Every adopting repo consumes these by copy and customizes them in place, so a rename or a removed step breaks their fork exactly as a renamed CLI argument breaks a script. Added by **BTG-275** (AC-4). The period is **derived, not chosen**: every per-agent and per-skill row in `claire-surfaces.md` already asserts *2 release cycles*, and before this row that promise was undetermined by the policy meant to define it. `archive/BTG-194/spec.md` reached the same finding and left it to a follow-on. The **TYPE row governs** a deprecation's window, not the host surface's own stability — see the `/claire-triage --file-only` inline-form entry in `claire-surfaces.md`'s *Deprecated / relocated surfaces* table, which takes its 2-cycle window from the *CLI arguments / SDK methods* row above rather than from `/claire-triage`'s Stable registration |

A "release cycle" is one **qualifying** release cut under the repository's bound version
scheme (`CLAIRE_ORG.md#version-scheme-binding`, §18): a cut qualifies when it advances any
component other than the trailing patch field (the binding's `cycle-qualifying-cut` field).
A patch-only cut does not count. This is scheme-derived but not a calendar length: under a
scheme that permits at most one qualifying cut per calendar interval and some intervals with
none (e.g. `calver-yyyy-ww`, at most one non-patch cut per ISO week), no fixed calendar
figure can stand in for an actual count without silently mis-measuring a quiet stretch. A
window's length ("N release cycles") is therefore always counted in actual qualifying cuts,
never computed as a fixed end date from a calendar length.

**Tightening under `semver`, and a withdrawal for continuous deployment -- both stated rather
than left implicit.** Before this scheme-derived definition, a "release cycle" was informally
"one merge-to-main deployment," which a patch-only release also satisfied, with a second limb
for continuous deployment: "treat 2 calendar weeks as 1 release cycle." Counting only
qualifying (non-patch) cuts is strictly **more generous to consumers against the first limb**: a
window measured against merge-to-main deployments can only take as long or longer to close,
never shorter. Against the second limb the direction reverses, and this is a real change, not a
no-op: a continuous-deployment adopter cutting a qualifying (non-patch) release several times a
week previously had a guaranteed floor of 2 calendar weeks per cycle, and under qualifying-cut
counting a window now closes in however long it actually takes that adopter to cut N qualifying
releases, which can be far shorter than 2 calendar weeks per cycle. **The continuous-deployment
calendar-weeks equivalence is withdrawn by this change, deliberately** (requester ruling,
2026-09-21; retaining it as a floor -- closing on the later of N qualifying cuts or N x 2
calendar weeks -- was offered and declined, as was keeping it only for windows announced from
here forward). It is not replaced by anything for newly announced windows; it survives only as
the historical referent the Grandfather clause below points a pre-existing window back to.

**Grandfather clause.** A deprecation or sunset window is measured under the
`cycle-qualifying-cut` rule **in force when it was announced**, for the whole life of that
window: it closes on the Nth qualifying cut counted from announcement, however long that
takes. **For a window announced before this scheme-derived definition took effect, the rule in
force at announcement is the superseded one stated above: a "release cycle" was one
merge-to-main deployment, and for continuous deployment, treat 2 calendar weeks as 1 release
cycle.** That is the guarantee those windows were actually promised, and it is preserved here as
their referent even though the continuous-deployment equivalence is withdrawn (above) for
windows announced from this change forward -- the withdrawal is prospective only and never
reaches a window already running. Rebinding the version scheme after a window is announced never
re-dates it; a later rebind changes only how *future* announcements are counted, never a window
already running.

## Signaling Requirements

Every deprecated surface must signal its status to consumers through multiple channels:

### Runtime Signals

| Signal | Where | Format | Example |
|---|---|---|---|
| HTTP `Deprecation` header | API responses from deprecated endpoints | RFC 8594 | `Deprecation: true` |
| HTTP `Sunset` header | API responses from deprecated endpoints | RFC 8594 | `Sunset: Sat, 01 Nov 2026 00:00:00 GMT` |
| Response body marker | API responses including deprecated fields | JSON field | `"_deprecated": ["field_name"]` or top-level `"_deprecation_notice": "..."` |
| Structured log warning | Server-side, on each invocation of deprecated surface | JSON to stdout | `{"level": "warn", "msg": "deprecated_surface_invoked", "surface": "/api/v1/old-endpoint", "sunset": "2026-11-01", "migration": "https://docs/migration-guide"}` |
| Metric emission | Server-side counter | Mimir metric | `deprecated_surface_calls_total{surface="/api/v1/old-endpoint"}` counter |

### Documentation Signals

| Signal | Where | When |
|---|---|---|
| Surface Registry entry | The Deprecation Log **of the registry that owns the surface**: `docs/policies/claire-surfaces.md`'s *Deprecated / relocated surfaces* table for a **core-owned** surface, `docs/policies/surface-registry.md`'s Deprecation Log for an **adopter-owned** one. Routing a core-owned removal to the adopter-owned table announces it where no consumer of that surface reads (BTG-200). | At deprecation announcement |
| Migration guide | `docs/migrations/` or inline in spec | At deprecation announcement |
| CHANGELOG entry | `CHANGELOG.md` under `[Unreleased]` → `Deprecated` | At deprecation announcement |
| Consumer notification | Direct communication to known consumer teams | Within 1 business day of deprecation |

## Migration Documentation Requirements

Every breaking change requires a migration guide. The guide must contain:

1. **What is changing:** Name the specific surface, field, endpoint, or behavior being deprecated.
2. **Why it is changing:** Business or technical reason. Consumers deserve context, not just notice.
3. **Before/After examples:** Concrete request/response or configuration examples showing the old way and the new way.
4. **Timeline:** When the deprecation was announced, when the sunset will occur, and any intermediate milestones.
5. **Migration steps:** Numbered, actionable steps a consumer can follow to migrate. Include code samples in languages consumers use.
6. **Verification:** How the consumer can verify their migration is complete (e.g., "your service should no longer receive `Deprecation: true` headers").
7. **Support:** Who to contact if migration is blocked or unclear.

Migration guides are stored in `docs/migrations/{surface-name}.md` or inline in the spec's Compatibility Impact section for smaller changes.

## Sunset Process

When the deprecation period has elapsed and the surface is ready for removal:

### Pre-Sunset Checklist

- [ ] Deprecation period has fully elapsed
- [ ] All known consumers have been notified and confirmed migration (or acknowledged the timeline)
- [ ] Deprecated surface metric (`deprecated_surface_calls_total`) shows zero or near-zero traffic for at least 1 week
- [ ] Migration guide is published and accessible
- [ ] Rollback plan documented in case removal causes unexpected breakage

### Sunset Execution

1. **Feature flag removal:** If the deprecated surface was behind a feature flag, remove the flag and the deprecated code path.
2. **Code removal:** Remove the deprecated endpoint, field, event handler, or schema element. Do not leave dead code with "deprecated" comments.
3. **Test cleanup:** Remove or archive compatibility tests for the sunset version. Archived tests go to `archive/` with a note, not deleted entirely (audit trail).
4. **Registry update:** Update **the registry that owns the surface** — `docs/policies/claire-surfaces.md`'s *Deprecated / relocated surfaces* table for a core-owned surface, `docs/policies/surface-registry.md`'s Deprecation Log for an adopter-owned one — moving the entry status from "Active" to "Complete." (BTG-200)
5. **CHANGELOG entry:** Add entry under `Removed` in the changelog.

### Post-Sunset Monitoring

Monitor error rates and consumer health for 48 hours after sunset deployment. If unexpected breakage occurs, the rollback plan takes precedence over the sunset.

## Version Support Matrix

| Policy | Value |
|---|---|
| Concurrent API versions supported | Current + 1 previous |
| Version identifier location | URL path segment (`/api/v1/`, `/api/v2/`) |
| Version discovery | `API-Version` response header on all endpoints |
| New version trigger | Any breaking change to a stable endpoint that cannot be made additive |
| Previous version retirement | Follows standard deprecation period after new version is stable |

When a new API version is introduced:
1. The previous version is immediately marked as deprecated in the surface registry.
2. Deprecation signals (headers, logs, metrics) are added to the previous version.
3. The deprecation period clock starts.
4. Both versions are maintained until sunset.

## Emergency Breaking Changes

For security vulnerabilities, compliance violations, or data integrity issues that require immediate breaking changes:

| Step | Action | Timeline |
|---|---|---|
| 1 | Document the security/compliance justification | Before deployment |
| 2 | Notify all known consumers with emergency notice | Same day as deployment |
| 3 | Deploy the breaking change | As needed by severity |
| 4 | Publish migration guide | Within 24 hours |
| 5 | Provide migration support window | 1 week minimum |
| 6 | Update surface registry and changelog | Within 24 hours |

Emergency breaking changes bypass the normal deprecation period but still require documentation, consumer notification, and a migration path. The justification is recorded in the Deprecation Log of **the registry that owns the surface** (`docs/policies/claire-surfaces.md`'s *Deprecated / relocated surfaces* table when core-owned, `docs/policies/surface-registry.md`'s Deprecation Log when adopter-owned — BTG-200) with a note that the emergency process was used.

## References

- [CLAIRE Framework Surface Registry (core-owned)](claire-surfaces.md) — framework surfaces and their *Deprecated / relocated surfaces* table
- [Public Surface Registry (adopter-owned)](surface-registry.md) — your project's own surfaces and their Deprecation Log
- [CLAIRE Org Configuration](../agentic-sdlc/CLAIRE_ORG.md) — Backwards Compatibility facet measures
- RFC 8594 — The Sunset HTTP Header Field
