# Emergency Fast-Track

When a live production outage occurs or a critical security vulnerability is under active exploitation, running the full standard SDLC introduces unacceptable latency. This policy provides a compressed emergency path that trades up-front process gates for immediate remediation speed — coupled with mandatory retroactive payback within 48 hours.

## When to Use

The emergency fast-track is authorized **only** when all three of the following conditions hold simultaneously:

1. **Severity:** Production availability or core functionality is degraded for users, OR a critical security vulnerability is actively exploitable in the wild.
2. **Urgency:** Remediation cannot wait for the next standard release cycle (measured in hours, not days).
3. **Scope:** The root cause is isolated and understood — you know precisely what failed and what minimal change restores service.

If any of these three conditions is not satisfied, use the standard CADENCE workflow at the appropriate change tier.

**What never qualifies for fast-track:** "Product wants this shipped by end of day," commercial deadline pressure, behind-schedule feature work, or longstanding technical debt that has become inconvenient. Those remain Medium- or High-tier changes under schedule pressure — accelerate them by parallelizing work and tightening review turnaround, never by bypassing governance gates.

## The Fast-Track Process

```
Incident declared
    │
    ▼
Step 1: Fix        ─── Author writes the minimal fix (no up-front spec, no full TDD ceremony)
    │
    ▼
Step 2: Verify     ─── One human reviewer confirms the fix resolves the incident safely
    │
    ▼
Step 3: Ship       ─── Merge and deploy immediately
    │
    ▼
Step 4: Payback    ─── Within 48 hours: retroactive spec, full test coverage, and documentation
```

### Step 1: Fix

- Cut a branch directly from the production-mirror / trunk branch (`main`) using the naming pattern: `hotfix/{ticket-id}-{description}`.
- Implement the smallest possible code change that resolves the incident. Zero opportunistic refactoring, zero "while we're here" cleanups.
- Prefix the commit message with `[HOTFIX]`.
- Write unit tests covering the immediate fix (unit tests execute in seconds and prevent immediate regression; use `offload_log_triage` / `log-triage` to verify clean compilation and test execution). Full integration, journey, and chaos test suites are deferred to Step 4 payback.

### Step 2: Verify (One Human Gate)

A single human reviewer — distinct from the hotfix author — verifies:

- [ ] The patch directly addresses the active production incident
- [ ] The patch introduces no obvious secondary regressions or side effects
- [ ] The diff is strictly minimal (no unrelated edits)
- [ ] Unit tests pass cleanly

During emergency verification, the reviewer does **not** pause to:
- Audit against a formal specification (none exists yet)
- Enforce boundary documentation headers
- Check flow documentation freshness
- Execute the full adversarial chaos matrix

**Time budget:** 15 minutes maximum. If a reviewer cannot understand and verify the hotfix within 15 minutes, the change is too broad for fast-track — narrow it to the immediate mitigation first.

### Step 3: Ship

- Merge the hotfix branch into `main`.
- Deploy immediately through the standard CD pipeline (if a database migration is included, the migration verification job still executes first).
- Bypassed pre-deploy gates: Spec Review (Gate 1), Maintainer Acceptance (Gate 3), and full Deploy Validation (Gate 4).

### Step 4: Payback (Mandatory, within 48 hours)

An emergency fast-track is a short-term loan taken against engineering rigor, and the principal must be repaid in full within 48 hours:

1. **Author a retroactive specification** — create `problem.md` capturing what failed, the root cause, and the remediation applied. While a full Contextual Grounding Matrix (6W×4L) and CHORD decomposition are not required unless the fix permanently altered cross-boundary contracts, the artifact must preserve complete diagnostic context for future maintainers.
2. **Backfill integration and journey tests** — while Step 1's unit test guards the specific line of code, payback adds integration and journey tests that guard against the broader failure class.
3. **Reconcile documentation** — if the hotfix altered a business flow or introduced an operational workaround, update `docs/flows/` and/or `docs/SYSTEM_OVERVIEW.md`.
4. **Update the production insights register** — append a categorized entry to `docs/agentic-sdlc/production-insights.md` mapping the incident to its CHORD dimension (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, or `BOUNDARY_FAULT`).
5. **Evaluate chaos profile coverage** — check whether the incident exposed a distributed failure mode absent from `docs/policies/chaos-profiles.md`; if so, add a new chaos profile or strengthen simulator assertions.

Payback is tracked via a dedicated follow-up ticket carrying a strict **48-hour SLA**. Any payback ticket that remains incomplete after 48 hours automatically escalates to the project maintainer (see `docs/policies/conflict-resolution.md` Scenario 5).

## CI Pipeline Behavior for Hotfixes

Branches matching `hotfix/*` run a streamlined CI pipeline:

| Stage | Runs? | Why |
|---|---|---|
| Validate (lint, build) | Yes | Must compile |
| Unit Tests | Yes | Must not regress |
| Doc Check | **No** | Deferred to payback |
| Ephemeral Env | **No** | Too slow for hotfix |
| Integration Tests | **No** | Deferred to payback |
| Contract Tests | **No** | Deferred to payback |
| Journey / Chaos | **No** | Deferred to payback |
| Migration Verify | Yes (if migrations present) | Migrations are irreversible — always verify |
| Teardown | N/A | No ephemeral env created |

## Who Can Declare a Fast-Track

Emergency fast-track is never self-declared by an individual contributor in isolation. It must be authorized by one of:

- An on-call engineer actively responding to a paged production incident
- A team lead or engineering manager
- A security engineer responding to an active security disclosure

The authorizing individual, incident ID, and payback ticket ID are recorded directly in the hotfix commit footer:

```
[HOTFIX] Fix payment timeout causing 500s on checkout

Declared by: @jane-oncall
Incident: INC-2345
Payback ticket: TT-6789
```

## Guardrails

- **No fast-track merge to `main` without at least one unit test.** An untested emergency fix is a repeat outage waiting to happen.
- **No fast-track for database schema changes without migration verification.** Production schema mutations cannot be undone if they fail midway.
- **No stacked fast-tracks.** If a second emergency hotfix is needed in the same subsystem before the first hotfix's payback ticket is closed, the subsystem has a structural stability problem — escalate immediately to engineering leadership.
- **Payback is mandatory.** An un-repaid hotfix leaves undocumented behavioral debt in the critical path. The 48-hour window is enforced because incident context decays rapidly once the alert clears.

## Relationship to Change Tiers

Emergency fast-track is not a fifth change tier — it is a time-bounded inversion of the normal delivery sequence:

| Aspect | Normal (any tier) | Fast-Track |
|---|---|---|
| Spec | Required (Low: problem.md, Medium+: full) | Retroactive within 48h |
| Human gates | Per tier (1-4 gates) | 1 gate (single reviewer) |
| CI pipeline | Full per tier | Compressed (validate + unit + migration only) |
| Documentation | Per tier | Deferred to payback |
| Chaos testing | Medium+ if applicable | Deferred to payback |

Once Step 4 payback finishes, the change achieves the exact same test, documentation, and audit coverage as a standard change — executed in reverse order (mitigate first, codify second).

## Post-Incident Review

Every fast-track deployment feeds into the team's post-incident review ritual (see `docs/agentic-sdlc/team-rituals.md`), examining four diagnostic questions:

- Could an existing or newly defined chaos profile in `chaos-profiles.md` have surfaced this failure pre-merge?
- Were `docs/SYSTEM_OVERVIEW.md` and `docs/flows/` accurate enough to orient responders immediately, or was recovery delayed by stale documentation?
- Should this failure mode be instrumented as a permanent CHORD observability seam (`UNSOUND_CONDITION`, `DELTA_AUDIT_GAP`, `RULE_DIVERGENCE`, or `BOUNDARY_FAULT`)?
- Which specific test scenario now prevents this entire failure class from recurring?
