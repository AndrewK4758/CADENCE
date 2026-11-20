# Completeness Invariants & Anti-Exclusion Policy

**Status:** Normative. Consumed by `cadence-triage-agent`, `cadence-explorer`, `cadence-spec-author`, `cadence-spec-challenger`, `cadence-implementer`, `cadence-reviewer`, `cadence-security-auditor`, `cadence-breaker`, `cadence-maintainer`, `/cadence-elicit`, `/cadence-spec`, `/cadence-review`, `/cadence-certainty`, and deterministic gates (`verify-spec-invariants.sh`, `certainty-gate.sh`). Every consumer **points** to this policy rather than duplicating its clauses (`CADENCE_DIRECTIVES.md` Behavior 6).

---

## 1. Organizing Principle: Balanced Breadth × Depth

Completeness is the product of **horizontal breadth** (every caller, writer, coupled state field, and lifecycle stage that shares an invariant) and **vertical depth** (end-to-end verification across process, network, lock, temporal, and restart boundaries without mocking out the risk seam).

- **In prompts and governance:** Normative core prompts stay **domain-neutral and principle-driven**. Never embed project-specific incident anecdotes, vendor names, or bespoke identifiers into normative rules; place illustrative cases strictly inside labeled `# Worked Example` annexes, repo-local `production-insights.md`, or test/eval fixtures. Every normative anti-exclusion rule must pair with either a deterministic gate check or an executable eval.
- **In specifications, code, and tests:** *Minimum code required* (`Behavior 2`) and `Structural Simplicity` apply **strictly among designs that preserve all active higher-ranked pillars**. A minimal diff that leaves a known invariant breach open is incomplete, not simple.

---

## 2. Six Universal Defect-Exclusion Classes (Banned From Recommended Fixes)

Valid issues must never silently drop out of **Gate 1 recommended designs** or **Gate 2 blocking recommended fixes** through any of these six mechanisms:

| Class | Mechanism | Binding Countermeasure |
|---|---|---|
| **E-1** | **Scope-Carve-Out Shield** — `Out of Scope` excludes a sibling caller, background worker, or secondary entry point that mutates the same invariant or invokes the same irreversible external sink. | Shared-invariant siblings default **in scope**. Excluding one requires an explicit Gate 1 `OQ-N` naming the residual failure path plus a tracked follow-up ticket; verify caller closure via `evidence.yaml` `kind: absence`. |
| **E-2** | **Pillar Precedence Inversion** — A lower-ranked pillar (`Structural Simplicity`, `Agentic Ergonomics`) or blanket novelty penalty overrides a higher-ranked active pillar (`Data & Audit Fidelity`, `Security Boundary Posture`, `Surface Compatibility`). | **Non-Inversion Dominance Rule:** A lower-ranked pillar never defeats a higher-ranked active pillar when an alternative eliminates a `KNOWN` failure mode on that higher pillar, absent an explicit Gate 1 risk-acceptance `OQ-N`. Separate `speculative-novelty` (budget `0`) from `invariant-required-state` (never penalized). |
| **E-3** | **Unforced `KNOWN` High-Impact Failure** — A selected design retains an unmitigated `Severity: HIGH` or Rank #1/#2 pillar `Failure modes (KNOWN)` entry with no forced human ruling. | Tag every `Failure modes (KNOWN)` bullet `[Pillar: <Name> \| Severity: HIGH\|MEDIUM\|LOW \| Scope: in-scope\|sibling\|cross-boundary]`. Unruled high-impact `KNOWN` modes on the selected option trigger deterministic escalation/halt (`unruled_known_risk`). |
| **E-4** | **Truncated Lifecycle Horizon** — Design or tests model only the single synchronous request/response hop and skip crash, reload, timeout, TTL, or lock boundaries. | Apply the **5-Boundary Lifecycle Walk** (§3) and standardized chaos profiles (`CP-01`–`CP-14` in `docs/policies/chaos-profiles.md`). |
| **E-5** | **Rework Tunnel Vision & Single-Field Proof** — Rework verifies the prior cycle's single failing scalar while ignoring (or asserting as expected) corruption in coupled fields or regressions in newly added error/lock paths. | Assert the **full coupled invariant tuple** (primary state + derived flags + external collaborator state) on every concurrency/recovery test; cold-break rework deltas with zero implementer narrative. |
| **E-6** | **Prose Rationalization / Downgrade** — A reviewer documents a live race, stale write, or boundary defect in prose and waves it off with an eventual-reconciliation or low-likelihood excuse. | Record every surfaced review anomaly in the structured Adversarial Lens Disposition table (`BLOCKING \| PROVEN_SAFE \| WAIVED`). Enforced mechanically alongside `docs/policies/finding-classes.md`. |

---

## 3. The 5-Boundary Lifecycle Walk (Vertical Depth Protocol)

Whenever a change touches persistent state, concurrent writers, external side effects, or interactive submission flows, specs, implementations, and cold-breaker probes must trace all five boundaries (marking each *Handled*, *Proven N/A*, or *Risk-Accepted via `OQ-N`*):

1. **Caller / Client State Survival (`CP-14`):** If the initiating client, UI, or worker reloads, remounts, or restarts while a mutation's outcome is unknown, attempt identity or status recovery survives until a terminal outcome is observed.
2. **Post-Commit In-Flight Ambiguity (`CP-12`):** If an external dependency commits an irreversible side effect and then faults or times out before returning a receipt, immediate retries and subsequent background/scheduled ticks execute the side effect at most once.
3. **Post-Lock Predicate Re-Validation (`CP-05`):** Whenever state is read unlocked, external I/O executes, and a lock is acquired to write derived state or flags, the locked block re-evaluates the decision predicate against the live locked row and reconciles/compensates if the predicate flipped during the I/O window.
4. **Cross-Boundary Authority & Temporal Asymmetry (`CP-11`, `CP-13`):** Whenever an external cache, deduplication window, lease, or token TTL can expire earlier than the local replay or retention window, local durable persistence owns authority rather than delegating correctness solely to the external TTL.
5. **Coupled-State Tuple Atomicity (`CP-04`, `CP-05`):** Every domain invariant spanning multiple columns, tables, caches, or external collaborators is verified as a complete tuple `P(primary_state, derived_state, external_state)` across every interleaving and rework cycle.

---

## 4. Shared-Invariant Closure (`evidence.yaml` `kind: absence`)

For `Medium` and `High` tickets where Pillar 4 (`Data & Audit Fidelity`) or Pillar 6 (`Security Boundary Posture`) is `active`, `specs/{ticket-id}/evidence.yaml` must include at least one `load_bearing` `kind: absence` claim per shared external side-effect sink or shared-invariant mutator, listing every in-scope caller in `proof.expected_files` (plus any Gate-1-ruled `OQ-N` exception). If an unlisted sibling caller exists in the codebase, `certainty-gate.sh` fails closed (`falsified_absence`).

---

## 5. Repo-Level Completeness Strictness Resolution

Whether completeness-gate gaps (missing shared-invariant `absence` proofs, unruled `KNOWN` high-impact risks, pillar-precedence inversions, unwaived review anomalies, or shared-surface `Out of Scope` overlaps) emit **`HALT` (`exit 1`)** or **`ESCALATE_HUMAN` (`exit 2`)** is governed declaratively at the repository level rather than hardcoded globally:

1. **Explicit command override (highest precedence):** `--strictness halt|escalate` on `certainty-gate.sh` (or an explicit strict/advisory instruction in the invoking command) overrides the repository default for that run.
2. **Repo-level governance / system MD binding:** Resolved from `docs/agentic-sdlc/CADENCE_ORG.md#completeness-strictness-binding` (falling back to root `AGENTS.md`, `GEMINI.md`, or `CLAUDE.md` when the markers are placed there):
   - `completeness-strictness: halt` or `escalate` pins the mode directly.
   - `completeness-strictness: auto` derives strictness from team review posture:
     - **`team-size > 1` AND `enforce-review: yes`** -> **`halt`** (`exit 1`, strict enforcement for multi-person reviewed repositories).
     - **`team-size == 1` OR `enforce-review: no`** -> **`escalate`** (`exit 2`, advisory human-escalation mode for solo or unreviewed workflows).
3. **Unconfigured rule (fail-loud, never silent default):** When no override is passed and the repo-level markers are absent, empty, placeholder, or invalid, `certainty-gate.sh` emits `ESCALATE completeness_strictness_unconfigured` (`exit 2`). Orchestrating skills (`/cadence-certainty`, `/cadence-spec`, `/cadence-review`, `/cadence-build`) must **prompt the operator** to choose `halt` vs `escalate` for the current run and offer to persist the binding in the repository's governance/system markdown file.

---

## 6. Mechanical Reinforcement Across Rework, Traceability, Chaos, Upgrade, and Cross-Model Gates

1. **Rework-Delta SHA Bookmarking:** `<!-- cadence-run:cycle ... -->` markers carry optional `sha=<short-sha>` (or `<repo>:<short-sha>,...` in satellite workspaces) parsed by `read_state.py` (`ledger_last_sha=`) and resolved by `breaker-trigger.sh` (`rework_base=<sha>`), ensuring `/cadence-review` hands `cadence-breaker` both the full branch diff and the exact `<rework_base>..HEAD` rework delta.
2. **Cross-Repo Citation & Traceability Parity:** `verify-facts.sh` (facts, `--rulings`, and `--trace`) accepts repeatable `--code-root <dir>` flags and `<repo>:<path>` references (forwarded by `certainty-gate.sh`), preventing satellite workspaces from silently skipping citation/traceability verification.
3. **Chaos Matrix Applicability Gate:** `verify-spec-invariants.sh` (`check_chaos_applicability`) mechanically enforces that `test-plan.md` (or a Gate 1 `OQ-N`) covers `CP-05`, `CP-12`, `CP-13`, and `CP-14` whenever `spec.md` declares matching lock, external side-effect, TTL/authority, or interactive reset triggers.
4. **Upgrade Org-Fold Strictness Preservation:** `upgrade-orgfold.sh` appends `#completeness-strictness-binding` cleanly onto pre-binding repositories with an explicit review notice and preserves customized `team-size` / `enforce-review` / `completeness-strictness` markers across future template prose updates; `/cadence-onboard` Step 3b confirms them interactively during repository setup.
5. **Test-Diff Anti-Tautology Detection:** `offload_diff_checks.py` / `trace_diff_hygiene.py` scan unified diffs deterministically for `MOCK_ONLY_ASSERTION` (new tests asserting only mock call counts with zero state/return assertions) and `SELF_MOCKED_SUT` (new tests mocking/patching symbols modified in production files of the same diff), surfacing flags in both `offload_deep_review` and `verify-facts.sh --trace`.
6. **Physical Cross-Model Gate Attestation:** `<!-- cadence-run:cycle ... -->` markers carry optional `implementer_model=`, `reviewer_model=`, and `breaker_model=` attributes surfaced by `read_state.py` (`ledger_last_models=`), verified at Gate 3 (`cadence-maintainer`), and aggregated in `/cadence-retro` (`retro_scan.py` `model_attestation=independent:N,same_model:N,unattested_high:N`).
