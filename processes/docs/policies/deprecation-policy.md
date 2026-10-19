# Deprecation Policy

This policy governs how public surfaces are deprecated, signaled to downstream consumers, and ultimately removed. Every surface deprecation must adhere to this lifecycle. Each deprecation is tracked in **the registry that owns the surface**: [`docs/policies/cadence-surfaces.md`](cadence-surfaces.md)'s *Deprecated / relocated surfaces* table for a **core-owned** framework surface, and [`docs/policies/surface-registry.md`](surface-registry.md)'s Deprecation Log for an **adopter-owned** project surface. Recording a core-owned deprecation inside the adopter-owned registry would announce it where no consumer of that framework surface looks (BTG-200; clarified by BTG-275).

## Deprecation Periods

Minimum guaranteed window between a deprecation announcement and surface removal, categorized by surface type:

| Surface Type | Minimum Deprecation Period | Rationale |
|---|---|---|
| Public API endpoints | 2 release cycles | External consumers need time to migrate; coordinated rollouts required |
| Inter-service contracts (events, shared DTOs) | 1 release cycle | Internal consumers can be coordinated more quickly |
| Configuration keys (env vars, feature flags) | 1 release cycle | Deployment infrastructure changes require pipeline updates |
| Database contracts (shared tables/views) | 2 release cycles | Schema migrations require coordinated deployment across services |
| CLI arguments / SDK methods | 2 release cycles | Downstream tooling and scripts need migration time |
| Agent / skill definition (an agent definition, or a slash command and its co-located sidecars) | 2 release cycles | Every adopting repo consumes these by copy and customizes them in place, so a rename or a removed step breaks their fork exactly as a renamed CLI argument breaks a script. Added by **BTG-275** (AC-4). The period is **derived, not chosen**: every per-agent and per-skill row in `cadence-surfaces.md` already asserts *2 release cycles*, and before this row that promise was undetermined by the policy meant to define it. `archive/BTG-194/spec.md` reached the same finding and left it to a follow-on. The **TYPE row governs** a deprecation's window, not the host surface's own stability — see the `/cadence-triage --file-only` inline-form entry in `cadence-surfaces.md`'s *Deprecated / relocated surfaces* table, which takes its 2-cycle window from the *CLI arguments / SDK methods* row above rather than from `/cadence-triage`'s Stable registration |

A "release cycle" equals one **qualifying** release cut under the repository's bound version scheme (`CADENCE_ORG.md#version-scheme-binding`, §18): a release cut qualifies when it increments any version component other than the trailing patch number (the binding's `cycle-qualifying-cut` field). A patch-only release never counts toward a deprecation window. While derived from the version scheme, this is a cut count rather than a fixed calendar duration: under schemes that allow at most one qualifying cut per calendar unit and zero cuts during quiet weeks (such as `calver-yyyy-ww`, which permits at most one non-patch cut per ISO week), no fixed calendar duration can substitute for an actual qualifying-cut count without mismeasuring quiet intervals. Consequently, a deprecation window of "N release cycles" is always measured in actual qualifying cuts, never projected as a fixed calendar date from a nominal cycle length.

**Tightening under `semver`, and a withdrawal for continuous deployment -- both stated rather than left implicit.** Prior to this scheme-derived rule, a "release cycle" was defined informally as "one merge-to-main deployment" (which a patch release also satisfied), paired with a continuous-deployment clause: "treat 2 calendar weeks as 1 release cycle." Counting strictly qualifying (non-patch) cuts is **more protective of consumers than the first clause**: a window measured in non-patch cuts takes at least as long to elapse as one counting every merge-to-main deployment, and never closes earlier. Against the second clause the effect reverses, representing a deliberate policy change rather than a no-op: a continuous-deployment adopter cutting multiple qualifying releases per week previously owed a 2-calendar-week floor per cycle, whereas under qualifying-cut counting the window closes as soon as N qualifying releases are cut — which may take less than two calendar weeks per cycle. **The continuous-deployment calendar-weeks equivalence is deliberately withdrawn by this policy** (requester ruling, 2026-09-21; keeping it as a minimum floor — closing on the later of N qualifying cuts or N × 2 calendar weeks — was evaluated and declined, as was retaining it prospectively). No calendar-duration floor replaces it for newly announced windows; the old rule survives solely as the historical referent referenced by the Grandfather clause below for pre-existing windows.

**Grandfather clause.** Every deprecation or sunset window is governed for its entire lifespan by the `cycle-qualifying-cut` rule **in force on the date it was announced**: it closes upon the Nth qualifying cut counted from announcement, regardless of calendar duration. **For any window announced before this scheme-derived definition took effect, the rule in force at announcement remains the prior definition: one "release cycle" equals one merge-to-main deployment, or 2 calendar weeks under continuous deployment.** That was the commitment made to consumers when those windows opened, and it is honored in full because the withdrawal of the continuous-deployment equivalence above is strictly prospective. Rebinding a repository's version scheme after a deprecation window has been announced never alters the closing condition of a window already in flight; a rebind governs only future announcements.

## Signaling Requirements

Every deprecated surface must communicate its deprecation status to consumers across both runtime and documentation channels:

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
| Surface Registry entry | The Deprecation Log **of the registry that owns the surface**: `docs/policies/cadence-surfaces.md`'s *Deprecated / relocated surfaces* table for a **core-owned** surface, `docs/policies/surface-registry.md`'s Deprecation Log for an **adopter-owned** one. Routing a core-owned removal to the adopter-owned table announces it where no consumer of that surface reads (BTG-200). | At deprecation announcement |
| Migration guide | `docs/migrations/` or inline in spec | At deprecation announcement |
| CHANGELOG entry | `CHANGELOG.md` under `[Unreleased]` → `Deprecated` | At deprecation announcement |
| Consumer notification | Direct communication to known consumer teams | Within 1 business day of deprecation |

## Migration Documentation Requirements

Every breaking change or deprecation requires a dedicated migration guide containing:

1. **What is changing:** Identify the exact surface, field, endpoint, CLI flag, or behavior being deprecated.
2. **Why it is changing:** State the underlying business or architectural reason so consumers understand the rationale, not just the deadline.
3. **Before/After examples:** Provide concrete side-by-side request/response payloads, CLI invocations, or configuration snippets illustrating the legacy form and the replacement form.
4. **Timeline:** Specify the deprecation announcement version/date, the qualifying-cut sunset requirement, and any intermediate milestones.
5. **Migration steps:** List numbered, actionable steps a consumer can execute to complete the transition, including code samples in the primary consumer languages.
6. **Verification:** Explain how consumers can verify their migration succeeded (for example, confirming their service no longer receives `Deprecation: true` response headers or emits deprecation warnings).
7. **Support:** Name the owning team or communication channel for migration assistance.

Migration guides live in `docs/migrations/{surface-name}.md`, or inline within the specification's Compatibility Impact section for narrower changes.

## Sunset Process

Once the required deprecation window has fully elapsed and the surface is ready for removal:

### Pre-Sunset Checklist

- [ ] Minimum deprecation period (in qualifying release cuts) has fully elapsed
- [ ] All registered consumers have been notified and confirmed migration (or formally acknowledged the sunset timeline)
- [ ] Deprecated surface telemetry (`deprecated_surface_calls_total`) shows zero or near-zero invocation volume for at least 1 week
- [ ] Migration guide is published and reachable
- [ ] Rollback plan is documented in case removal triggers unexpected downstream failures

### Sunset Execution

1. **Feature flag removal:** If the deprecated surface was gated by a feature flag, remove both the flag definition and the legacy code path.
2. **Code removal:** Delete the deprecated endpoint, field, event handler, or schema element completely. Never leave unreachable dead code behind "deprecated" comments.
3. **Test cleanup:** Remove or archive compatibility tests targeting the retired surface. Archived contract tests move to `archive/` with an explanatory note rather than vanishing without a trace.
4. **Registry update:** Update **the registry that owns the surface** — `docs/policies/cadence-surfaces.md`'s *Deprecated / relocated surfaces* table for a core-owned surface, or `docs/policies/surface-registry.md`'s Deprecation Log for an adopter-owned surface — transitioning the entry status from "Active" to "Complete." (BTG-200)
5. **CHANGELOG entry:** Record the removal under the `Removed` heading in `CHANGELOG.md`.

### Post-Sunset Monitoring

Monitor service error rates and downstream consumer telemetry for 48 hours following sunset deployment. If unanticipated breakage surfaces, executing the documented rollback plan takes priority over keeping the sunset in place.

## Version Support Matrix

| Policy | Value |
|---|---|
| Concurrent API versions supported | Current + 1 previous |
| Version identifier location | URL path segment (`/api/v1/`, `/api/v2/`) |
| Version discovery | `API-Version` response header on all endpoints |
| New version trigger | Any breaking change to a stable endpoint that cannot be made additive |
| Previous version retirement | Follows standard deprecation period after new version is stable |

When a new major API version is introduced:
1. The prior version is immediately marked as `Deprecated` in the owning surface registry.
2. Runtime deprecation signals (HTTP headers, structured warning logs, Mimir counters) are enabled on the prior version.
3. The deprecation window counter begins.
4. Both API versions are supported concurrently until the deprecation window closes.

## Emergency Breaking Changes

When an active security vulnerability, regulatory compliance mandate, or critical data-integrity defect necessitates an immediate breaking change:

| Step | Action | Timeline |
|---|---|---|
| 1 | Document the security/compliance justification | Before deployment |
| 2 | Notify all known consumers with emergency notice | Same day as deployment |
| 3 | Deploy the breaking change | As needed by severity |
| 4 | Publish migration guide | Within 24 hours |
| 5 | Provide migration support window | 1 week minimum |
| 6 | Update surface registry and changelog | Within 24 hours |

Emergency breaking changes bypass the standard multi-cycle waiting period but still owe complete documentation, immediate consumer notification, and an actionable migration guide. The emergency justification is recorded in the Deprecation Log of **the registry that owns the surface** (`docs/policies/cadence-surfaces.md`'s *Deprecated / relocated surfaces* table when core-owned, or `docs/policies/surface-registry.md`'s Deprecation Log when adopter-owned — BTG-200) alongside an explicit note that the emergency fast-track was invoked.

## References

- [CADENCE Framework Surface Registry (core-owned)](cadence-surfaces.md) — framework surfaces and their *Deprecated / relocated surfaces* table
- [Public Surface Registry (adopter-owned)](surface-registry.md) — your project's own surfaces and their Deprecation Log
- [CADENCE Org Configuration](../agentic-sdlc/CADENCE_ORG.md) — Backwards Compatibility pillar measures
- RFC 8594 — The Sunset HTTP Header Field
