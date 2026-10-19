# Emergency Fast-Track

When production is down or a critical security vulnerability is actively exploited, the full process creates unacceptable delay. This policy defines a compressed path that trades process rigor for speed — with mandatory payback afterward.

## When to Use

The fast-track applies **only** when all three conditions are met:

1. **Severity:** Production is degraded or unavailable for users, OR a critical security vulnerability is actively exploitable
2. **Urgency:** The fix cannot wait for the next normal release cycle (hours, not days)
3. **Scope:** The fix is narrow and well-understood — you know what's broken and how to fix it

If any condition is not met, use the normal process with the appropriate change tier.

**This is not for:** "The PM wants it by EOD," deadline pressure, features that are late, or tech debt that's suddenly annoying. Those are Medium/High tier changes with time pressure — compress by parallelizing work, not by skipping gates.

## The Fast-Track Process

```
Incident declared
    │
    ▼
Step 1: Fix        ─── Author writes the fix (no spec, no TDD ceremony)
    │
    ▼
Step 2: Verify     ─── One reviewer confirms it fixes the issue and doesn't make it worse
    │
    ▼
Step 3: Ship       ─── Merge and deploy immediately
    │
    ▼
Step 4: Payback    ─── Within 48 hours: retroactive spec, tests, and documentation
```

### Step 1: Fix

- Branch directly from `main` using naming convention: `hotfix/{ticket-id}-{description}`
- Write the minimum fix. No refactoring, no "while I'm here" improvements.
- Add the tag `[HOTFIX]` to the commit message
- Unit tests for the fix are required (they're fast to write and prevent regression). Integration/journey/chaos tests are deferred to payback.

### Step 2: Verify (One Human Gate)

One reviewer — not the author — must confirm:

- [ ] The fix addresses the reported issue
- [ ] The fix doesn't introduce obvious new problems
- [ ] The fix is scoped narrowly (no unrelated changes)
- [ ] Basic tests pass

The reviewer does NOT need to:
- Verify against a spec (there isn't one yet)
- Check boundary documentation
- Evaluate documentation freshness
- Run the full chaos matrix

**Time budget:** 15 minutes. If the reviewer can't approve in 15 minutes, the fix is too complex for fast-track — split it.

### Step 3: Ship

- Merge to `main`
- Deploy immediately via normal CD pipeline (migration job still runs first if migrations are included)
- Skip: spec review gate, maintainer gate, deploy validation gate

### Step 4: Payback (Mandatory, within 48 hours)

The fast-track is a loan against process rigor. It must be repaid:

1. **Create a retroactive spec** — `problem.md` documenting what broke, why, and what was done. Doesn't need full Zachman/SCOUT but must capture the fix's context for future readers.
2. **Add integration/journey tests** — The unit tests from Step 1 cover the immediate fix. Add broader coverage to prevent the class of failure, not just this instance.
3. **Update documentation** — If the fix touches a flow or introduces a workaround, update `docs/flows/` and/or `docs/SYSTEM_OVERVIEW.md`.
4. **Feed the production insights loop** — Add an entry to `docs/agentic-sdlc/production-insights.md` categorizing the incident.
5. **Evaluate for chaos profile** — Does this incident reveal a failure mode not covered by the existing chaos profiles? If so, propose a new profile or adjust simulator behavior.

Payback is tracked as a follow-up ticket with a 48-hour SLA. If the payback ticket is not completed within 48 hours, it escalates to the maintainer.

## CI Pipeline Behavior for Hotfixes

Hotfix branches (`hotfix/*`) get a compressed pipeline:

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

Fast-track is not self-service. It must be declared by:

- An on-call engineer responding to a production alert
- A team lead or engineering manager
- A security team member (for security incidents)

The declarer is recorded in the hotfix commit message:

```
[HOTFIX] Fix payment timeout causing 500s on checkout

Declared by: @jane-oncall
Incident: INC-2345
Payback ticket: TT-6789
```

## Guardrails

- **No fast-track to `main` without at least one test.** A fix without a test will break again.
- **No fast-track for schema changes without migration verify.** Migrations are irreversible in production.
- **No stacking fast-tracks.** If you need a second hotfix before the first payback is complete, the system has a deeper problem — escalate to engineering leadership.
- **Payback is not optional.** A hotfix without payback is tech debt created under emergency that will compound. The 48-hour SLA exists because context is freshest immediately after the incident.

## Relationship to Change Tiers

Fast-track is not a tier — it's a temporary override of the tier system:

| Aspect | Normal (any tier) | Fast-Track |
|---|---|---|
| Spec | Required (Low: problem.md, Medium+: full) | Retroactive within 48h |
| Human gates | Per tier (1-4 gates) | 1 gate (single reviewer) |
| CI pipeline | Full per tier | Compressed (validate + unit + migration only) |
| Documentation | Per tier | Deferred to payback |
| Chaos testing | Medium+ if applicable | Deferred to payback |

After payback is complete, the hotfix has equivalent coverage to a normal change — just delivered in reverse order (ship first, document after).

## Post-Incident Review

Every fast-track should feed the team's incident review ritual (see `docs/agentic-sdlc/team-rituals.md`). Key questions:

- Could this failure have been caught by an existing chaos profile?
- Was the SYSTEM_OVERVIEW.md accurate enough to diagnose quickly, or did responders waste time orienting?
- Should this failure pattern become a new observability seam?
- What test would have caught this before production?
