# CADENCE — A Framework for Refracting Problem Statements into Governed Iteration Specs

*A Contextually-grounded (6W×4L), pillar-driven, CHORD-decomposed framework for generating architectural specifications that AI agents and human engineering teams can execute with precision.*

**Version:** 2.0
**Purpose:** A portable, reusable manual enabling any LLM (Gemini, Claude, GPT, etc.) to ground a system across six interrogatives and four abstraction layers, assemble a repository-specific library of Engineering Pillars, decompose every acceptance criterion into verifiable behavioral contracts, and generate one or more governed iteration specifications from a problem statement. **CADENCE** (*Contextual Architecture, Decomposition, Execution, Navigation, Consolidation & Enshrinement* — spanning the seven lifecycle stages: **C**lassify → **A**rchitect & Explore → **D**ecompose & Specify → **E**xecute via TDD → **N**avigate Gates → **C**onsolidate → **E**nshrine) takes an engineering problem statement and refracts it into executable specifications shaped by the architectural invariants that matter most for that work.

**How CADENCE relates to CHORD:** CADENCE is the overarching specification and lifecycle governance framework. **CHORD** (**C**onditions, **H**andling / Triggers, **O**utcomes, **R**ules, **D**eltas) is the behavioral decomposition engine CADENCE runs in Phase 3 — decomposing each acceptance criterion into five behavioral primitives that translate directly into Gherkin BDD scenarios and runtime observability seams (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`).

**How to use this document:**
1. Provide this manual to your LLM alongside read access to your repository (or an empty workspace for greenfield projects).
2. Optionally supply an **organization configuration** (`CADENCE_ORG.md`) that pre-populates platform constants and mandatory pillars for your organization (see "Creating Your Org Configuration" below, or the reference configs in `EXAMPLES/`).
3. Supply a structured **problem statement** (see "Writing a Problem Statement" below).
4. The LLM executes Phases 1–5 to produce: a Contextual Grounding fact sheet (`CONTEXT_FACTS.md`), a customized Pillar Library (`PILLAR_LIBRARY.md`), a CHORD behavioral decomposition per acceptance criterion (complete with derived observability seams), one or more iteration specifications (`ITERATION_N_SPEC.md`), and (whenever multiple iterations are warranted) an iteration comparison document (`SPEC_COMPARISON.md`).

---

## What CADENCE Is Not

- **Not a sprint-scheduling tool.** CADENCE produces rigorous engineering specifications and behavioral contracts, not Gantt charts or product roadmaps. Pair it with your bound issue tracker (`CADENCE_ORG.md#tracker-binding`).
- **Not an ungoverned code generator.** Specifications are detailed enough for an AI implementer agent to execute via red-green-refactor TDD, but CADENCE Phase 1–5 itself produces architectural specifications prior to Gate 1 approval rather than jumping straight to code.
- **Not tied to a single language or stack.** CADENCE operates across any programming language, runtime, or topology. Engineering Pillars evaluate architectural trade-offs and operational guarantees rather than prescribing a specific vendor.
- **Not monolithic.** Teams can adopt the four-part problem statement structure alone, run Phase 1 (Contextual Grounding) standalone, or execute the complete 5-phase specification and 7-stage lifecycle workflow. Every phase emits a self-contained artifact.

---

## Writing a Problem Statement

The fidelity of CADENCE's specifications depends directly on the clarity of the input problem statement. Every strong problem statement contains four distinct components:

### The four-part structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  [VERB]  the core action to perform                                 │
│  [SCOPE] the bounded context, subsystem, or modules affected        │
│  [WHY]   the user pain, business driver, or risk motivating it      │
│  [CONSTRAINTS] the non-negotiable boundaries on the solution space  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**VERB** signals which Engineering Pillars deserve primary weight. **SCOPE** bounds how much of the repository the LLM must inspect. **WHY** keeps the design anchored to the real business outcome. **CONSTRAINTS** rule out proposals your team or platform cannot support.

### Verbs and what they signal

| Verb | Signals | LLM interprets as |
|------|---------|-------------------|
| **Add** | Introduce a capability that does not exist yet | New domain logic, potentially new tables or endpoints |
| **Migrate** | Replace an underlying technology or runtime | Preserve external behavior while swapping implementation |
| **Refactor** | Restructure internals without altering external behavior | Zero new features, zero contract changes |
| **Fix** | Repair a defect or broken invariant | Root-cause diagnosis first, followed by targeted repair |
| **Improve** | Optimize a working but underperforming capability | Establish baseline measurement first, then optimize |
| **Harden** | Remediate security exposure or compliance gaps | Audit trust/data boundaries first, then enforce controls |
| **Scale** | Prepare a working path for higher throughput or volume | Profile bottlenecks first, then redesign hot paths |
| **Split** | Decouple an oversized or entangled module/service | Identify clean seam boundaries first, then extract |

### Examples: weak vs. strong problem statements

**Weak:** "Make the portal better."

- Missing verb, scope, business driver, and constraints. The LLM has to scan the entire repository and guess what "better" means.

**Weak:** "Add authentication."

- Supplies a verb and implied domain, but omits the motivation and environment constraints. OAuth2, SAML, mutual TLS, or API tokens are all plausible guesses, yet only one fits your architecture.

**Strong:**

```
VERB:        Migrate
SCOPE:       The entire frontend (13 views, legacy R Shiny)
WHY:         The UI is datatable-bound, unusable on mobile devices, and
             opaque to AI coding agents (a 10K-line monolithic server file
             with zero static typing). Campaign managers face 4-way
             scrolling on every screen.
CONSTRAINTS: Preserve the existing Flask REST API unchanged. Target
             React + Next.js. Must render cleanly on mobile and desktop.
             AI coding agents (.agents/ workflow) will author the
             implementation; the team has no dedicated frontend specialist.
```

**Strong:**

```
VERB:        Add
SCOPE:       The checkout flow (3 views: cart, payment, confirmation)
WHY:         We need Apple Pay support ahead of Q4 peak volume.
             Today only Stripe card entry is supported.
CONSTRAINTS: Keep Stripe as the sole payment processor (no new vendors).
             Must remain within PCI-DSS SAQ-A scope. Ship by November 1.
             Staffing: one senior engineer and one junior engineer.
```

**Strong:**

```
VERB:        Refactor
SCOPE:       The API layer (src/api/) — currently 4 files averaging
             1,200 lines each
WHY:         AI coding agents introduce regressions because each file
             exceeds 1,000 lines and entangles routing, input validation,
             SQL queries, and response serialization inside single handlers.
             We are adopting CADENCE agentic maintenance and need files
             under the 400-line Agentic Ergonomics ceiling.
CONSTRAINTS: Zero behavioral changes — every existing API response shape
             and status code must remain byte-identical. Zero new external
             dependencies. All 47 existing tests must continue passing.
```

### Shorthand format

For compact issues, use this single-sentence structure:

```
[VERB] [SCOPE] because [WHY], constrained by [CONSTRAINTS].
```

Example:

```
Migrate the frontend from R Shiny to React + Next.js because the
current UI is unmaintainable and not mobile-friendly, constrained
by keeping the Flask API unchanged and using CADENCE agents for
implementation.
```

### What if I don't know the constraints?

Declare the constraints you *do* know and mark the remainder as open for discovery:

```
VERB:        Add
SCOPE:       User notifications (email + in-app)
WHY:         Users miss time-sensitive state changes on their campaigns
CONSTRAINTS: No mandated email vendor (open to recommendation).
             Must integrate with the existing PostgreSQL database.
             Timeline: flexible. Team: 1 engineer + CADENCE agents.
```

During Phase 1 (Contextual Grounding), the LLM inspects the repository and surrounding platform to surface implicit constraints you may not have listed (for example, *"the service already runs a background worker queue suitable for async dispatch"* or *"no outbound SMTP/email provider is configured in Terraform — adding email requires a new secret and egress rule"*).

---

## Sample Workflow: Brand-New Project

This end-to-end walkthrough demonstrates CADENCE applied to a greenfield internal expense-reporting system, from initial problem statement to executable iteration specifications.

### Step 0: Set up

Make this manual accessible to your agentic coding tool (such as Google Antigravity / Gemini CLI via `.agents/` and `.gemini/`, or projected to `.claude/` per `docs/policies/cli-runtime-adoption-policy.md`):

```bash
# Option A: Place inside the repository's specs/ directory
cp CADENCE.md your-project/specs/CADENCE.md

# Option B: Install the full CADENCE framework into the target repository
scripts/adopt-cadence.sh /path/to/your-project
```

Open an agent session rooted in your repository workspace.

### Step 1: Write the problem statement

```
VERB:        Build
SCOPE:       A new internal expense reporting service (greenfield)
WHY:         The Finance team currently tracks employee expenses in shared
             spreadsheets with no approval workflow, no immutable audit trail,
             frequent manual entry errors, and no receipt attachment storage.
CONSTRAINTS: - Authenticate via Okta SSO (company-standard OIDC provider)
             - Persist data in PostgreSQL (company RDS standard)
             - Deploy containers to AWS ECS (existing Terraform modules)
             - Implemented by 2 engineers + CADENCE agents
             - Primary users are non-technical Finance staff and field employees
             - Mobile-responsive web UI required for field receipt uploads
             - SOC 2 compliance mandatory (100% mutation audit trail)
```

### Step 2: Give both to the LLM

```
You have access to the CADENCE framework manual in specs/CADENCE.md.

Here is my problem statement:

[paste problem statement]

Run CADENCE on this project. Begin with Phase 1 (Contextual Grounding).
```

### Step 3: LLM executes Phase 1 (Contextual Grounding)

On a greenfield repository, the Contextual Grounding fact sheet (`CONTEXT_FACTS.md`) inventories the surrounding platform constants and proposed domain boundaries rather than existing source files:

```markdown
# CONTEXT_FACTS.md

## What (Data)
- Greenfield datastore — new PostgreSQL RDS instance
- Proposed domain entities (from problem statement): Expense, Receipt,
  ApprovalRequest, User, Department, Category
- Compliance invariant: every state mutation must write an immutable audit
  record in the same transaction (SOC 2)

## How (Process)
- Greenfield API and web UI
- Core business flow: draft expense → submit with receipt(s) → manager
  approval/rejection → finance review → reimbursement export
- Multi-entity write: submitting an expense inserts/updates Expense,
  attaches Receipt records, and creates an ApprovalRequest atomically

## Where (Network)
- AWS ECS Fargate (existing cluster and shared Terraform modules)
- PostgreSQL on AWS RDS (provisioned via standard org module)
- Okta SSO (existing OIDC tenant)
- AWS S3 for receipt binary storage (existing encrypted bucket pattern)
- No pre-existing message queue or transactional email service bound yet

## Who (People)
- Employees (author expenses, upload receipts, view own submission history)
- Managers (approve or reject expenses for direct reports)
- Finance Administrators (audit all expenses, export batches, manage categories)
- Operations: operated by the same 2-engineer product team
- Code maintenance: human engineers + CADENCE agents (.agents/ workflow)

## When (Timing)
- No batch cron jobs required in initial release
- Approval visibility SLA: managers must see submitted expenses within minutes
  (near-real-time request path, not overnight batch)
- S3 presigned upload URLs expire after 15 minutes

## Why (Motivation)
- Eliminate error-prone spreadsheet tracking lacking approval controls
- Remediate Q3 SOC 2 audit finding on expense-change traceability
- CI/CD: GitHub Actions deploying continuously to ECS on merge to integration branch
```

### Step 4: LLM executes Phase 2 (Pillar Library)

Using the problem statement and `CONTEXT_FACTS.md`, the LLM assembles the governing Engineering Pillars:

```
Selected pillars (5):

1. Structural Simplicity      — greenfield service, 2-person team, minimize moving parts
2. Operational Resilience     — the 2-engineer build team operates the service in production
3. Agentic Ergonomics         — CADENCE agents author and maintain the codebase (<400 lines/file)
4. Data & Audit Fidelity      — triggered mandatory: SOC 2 requires 100% mutation audit coverage
                                and atomic multi-table expense submission writes
5. Security Boundary Posture  — triggered mandatory: Okta OIDC auth, employee PII, and S3 receipt
                                presigned URL access controls

Triggered mandatory (dormant):
- Surface Compatibility (not triggered — greenfield internal application with no external consumers yet)

Not selected:
- Execution Performance (modest internal concurrency, no high-throughput bottleneck)
- Automated Verifiability (folded into Operational Resilience CI gate checks)
- Modular Replaceability (committed to standard org stack: Postgres + ECS + Okta)
```

The LLM customizes each active pillar with concrete repository targets, anti-patterns, and a one-sentence decision rule, emitting `PILLAR_LIBRARY.md`.

### Step 5: LLM executes Phase 3 (CHORD Decomposition)

For every acceptance criterion in `problem.md`, the LLM decomposes the behavior across the five CHORD dimensions and derives runtime observability seams:

```
AC: "A manager can approve an expense submitted by their direct report."

CHORD Decomposition:
  Conditions     — Expense exists in Submitted state; authenticated caller is
                   the manager assigned to the Expense author's Department
  Handling       — POST /api/v1/expenses/{id}/approve with authenticated OIDC
                   principal, Expense ID, and optional approval note
  Outcomes       — Dispatches approval notification to the employee; emits
                   structured audit log event with trace_id and approver_id
  Rules          — Only a Submitted expense may transition to Approved; a
                   manager cannot approve their own expense; exactly one
                   terminal approval record per submission cycle
  Deltas         — Expense.state transitions Submitted → Approved;
                   ApprovalRequest.resolved_at set to current UTC;
                   audit_log row inserted in the same DB transaction

Derived Observability Seams:
  UNSOUND_CONDITION — approval handler invoked when Expense.state != Submitted
                      or caller is not the assigned department manager
  DELTA_AUDIT_GAP   — Expense.state mutates to Approved without a paired
                      audit_log insert in the same transaction
  DELTA_AUDIT_GAP   — approval transaction commits without the notification
                      dispatch span completing in the distributed trace
```

Each acceptance criterion receives a CHORD table, a mechanically derived edge-case list, and a seam specification table.

### Step 6: LLM executes Phase 4 (Iteration Spec Generation)

The LLM evaluates the mutation complexity classes in scope to determine the iteration count:

```
Mutation classes in scope:
- Single-table CRUD: manage expense categories, save draft expense (Class 2)
- Multi-table transactional write: submit expense + receipt links + approval
  request, manager approval/rejection with transactional audit ledger (Class 3)
- Cross-service integration: Okta OIDC login + S3 receipt upload (Class 4)

Class 2 + 4 → governed by Structural Simplicity, Operational Resilience,
              Agentic Ergonomics, and Security Boundary Posture
Class 3     → introduces multi-table sequencing and SOC 2 transactional audit
              ledger rules under Data & Audit Fidelity

Decision: 2 iterations
- Iteration 1: Service scaffold, Okta OIDC auth, S3 presigned receipt upload,
  and draft/category CRUD (Classes 2 + 4)
  → Pillars: Structural Simplicity, Operational Resilience, Agentic Ergonomics,
             Security Boundary Posture
- Iteration 2: Multi-step submission, manager/finance approval state machine,
  and transactional SOC 2 audit ledger (Class 3)
  → Adds: Data & Audit Fidelity multi-table sequencing & audit verification
```

The LLM outputs `ITERATION_1_SPEC.md` and `ITERATION_2_SPEC.md`, embedding the corresponding CHORD decompositions and observability seam tables from Phase 3.

### Step 7: LLM executes Phase 5 (Comparison)

Because two iterations were produced, the LLM generates `SPEC_COMPARISON.md` detailing:

- Iteration 1 retires **platform & integration risk** (verifying ECS deployment, Okta OIDC authentication, and S3 receipt uploads end-to-end).
- Iteration 2 retires **domain state-machine & compliance risk** (verifying multi-table transactional sequencing and SOC 2 audit completeness).
- The split boundary is **mutation complexity class** (single-entity CRUD + auth vs. multi-entity state transitions with audit invariants).

### Step 8: Review and execute

The specification directory now contains:

```
specs/
  CONTEXT_FACTS.md         # Grounded 6W×4L facts for the system and platform
  PILLAR_LIBRARY.md        # 5 customized Engineering Pillars + precedence order
  ITERATION_1_SPEC.md      # Scaffold + Okta auth + CRUD (with CHORD + seams)
  ITERATION_2_SPEC.md      # Approval workflow + audit ledger (with CHORD + seams)
  SPEC_COMPARISON.md       # Split rationale, risk profile, and pillar checklists
```

Hand the approved iteration specification to `cadence-implementer` (via `/cadence-implement` or direct execution):

```
Read specs/ITERATION_1_SPEC.md. Execute the ordered TDD scenario sequence
in section 8 / section 9, starting with scenario 1. Pause for human approval
at every designated human gate.
```

---

## Sample Workflow: Existing Project

On an existing repository, the workflow follows the exact same five phases, except Phase 1 is grounded in concrete source-code evidence (assisted by `repo-scout` / `local_semantic_embed` on `:9379` when local hardware offload is active) rather than greenfield proposals:

```
You have access to the CADENCE framework manual in specs/CADENCE.md.

Here is my problem statement:

Refactor the API layer (src/api/) because files average 1,200 lines
and entangle routing, validation, DB queries, and response formatting.
AI coding agents introduce regressions due to file length and mixed
concerns. Constrained by: zero behavior changes, all 47 existing tests
must keep passing, zero new dependencies.

Run CADENCE. Start with Phase 1 (Contextual Grounding).
```

The LLM inspects `src/api/`, records exact file paths and line counts, maps every endpoint's mutation class, inventories the 47 existing tests, and produces `CONTEXT_FACTS.md` anchored in real `file:line` citations. Phases 2–5 then proceed identically.

### When to re-run CADENCE

- **New feature or architectural initiative:** Author a new problem statement and run from Phase 1 (`CONTEXT_FACTS.md` will reflect changes landed in prior tickets).
- **Mid-flight constraint shift:** Update the problem statement's constraints and re-run from Phase 2 (`CONTEXT_FACTS.md` remains valid; pillar selection or precedence may shift).
- **Post-incident or post-iteration calibration:** Compare production outcomes (`production-insights.md`) against the specification's seams and success criteria, tightening pillar measures and anti-patterns for subsequent tickets.

---

## Creating Your Org Configuration

An organization configuration (`CADENCE_ORG.md`) pre-populates platform constants and mandatory Engineering Pillars shared across every repository in your organization. While **optional** — CADENCE works standalone without one — it eliminates repetitive infrastructure discovery in Phase 1 and enforces uniform quality standards across repositories.

To create one, copy `docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md` to `docs/agentic-sdlc/CADENCE_ORG.md` (or consult the reference configurations under `specs/EXAMPLES/`).

### What to pre-fill

**Contextual Grounding Constants** — platform facts that hold across all repositories in your organization:

| Column | What to capture | Examples |
|--------|----------------|----------|
| **Where (Network)** | VCS, CI/CD, container runtime, secrets manager, observability stack, IaC | "GitHub Actions", "AWS ECS", "Datadog / OpenTelemetry" |
| **Who (People)** | Identity provider, auth enforcement boundary, code maintainers | "Okta OIDC", "server-side principal enforcement", "engineers + CADENCE agents" |
| **Why (Motivation)** | Branch strategy binding, release cadence & version scheme binding, compliance regime | "long-lived `develop` integration branch", "CalVer `YYYY.WW.PATCH`", "SOC 2 audit trail required" |

Leave **What (Data)**, **How (Process)**, and **When (Timing)** un-filled at the organization level — they are discovered per repository during Phase 1.

**Mandatory Engineering Pillars** — pillars enforced on every specification across the organization:

- Pre-select 0–4 of the 9 standard pillars as always-on mandatory (the standard CADENCE org template pre-selects 3: **Structural Simplicity**, **Operational Resilience**, and **Agentic Ergonomics**).
- Replace generic measures and anti-patterns on each mandatory pillar with your organization's concrete thresholds.
- Configure **triggered mandatory** pillars: **Data & Audit Fidelity** (triggered whenever the system captures, mutates, or persists owned data), **Surface Compatibility** (triggered whenever a change touches registered public surfaces or introduces new ones), and **Security Boundary Posture** (triggered whenever a change touches auth, PII, input handling, or client code). See "Triggered Mandatory Pillars" in Phase 2.
- Common organizational profiles:
  - **Regulated / compliance-driven orgs:** Pin Data & Audit Fidelity and Security Boundary Posture as mandatory across all data-owning services.
  - **Agent-first engineering teams:** Enforce Agentic Ergonomics (`<400` lines per authored file, `<=5` files read per capability, strict types).
  - **Streamlined "you build it, you run it" teams:** Enforce Operational Resilience (shared CI templates, W3C tracing, structured JSON logs, CHORD runtime seams).
  - **Early-stage startups:** Emphasize Structural Simplicity (minimal service count, single datastore source of truth).

**Precedence Matrix** — your organization's tie-breaking order when pillars conflict:

- The default CADENCE precedence (`Data & Audit Fidelity [when triggered] > Security Boundary Posture > Surface Compatibility [when triggered] > Structural Simplicity > Operational Resilience > Agentic Ergonomics > ...`) fits most engineering organizations.
- If your organization overrides the default order, record the explicit rationale in `CADENCE_ORG.md`.

### What NOT to pre-fill

- Language, framework, or datastore choices that vary across repositories
- **What (Data)**, **How (Process)**, and **When (Timing)** cells — these belong to per-repository discovery
- Codebase-specific anti-patterns that apply to only one service
- Local team habits that are not organization-wide policy

---

## Scaling the Framework

CADENCE scales cleanly from a solo developer's utility repo to a multi-team regulated enterprise platform:

### Light mode — solo developer, small enhancements, localized bug fixes

Use only:
- **`problem.md`** — the single-sentence shorthand format is sufficient
- **`spec.md`** — omit the full 6W×4L matrix; retain the **CHORD decomposition** and **Proposed Design** sections
- Embed test scenarios directly inside `spec.md` (skipping a separate `test-plan.md`)
- Omit `metadata.yaml` and `decisions.md`

### Standard mode — product team of 2–5 engineers, standard feature delivery

Use the core specification templates (omitting external tracker bindings if running inner-source only):
- `problem.md`
- `spec.md` (Contextual Grounding Matrix + CHORD decomposition + Pillar evaluation)
- `test-plan.md` (ordered Gherkin scenarios)
- `decisions.md`

### Full mode — regulated systems, multi-repo platforms, full CADENCE governance

Use the complete artifact suite plus `CADENCE_ORG.md`:
- `problem.md` with stakeholder elicitation probes (`/cadence-elicit`)
- `design-options.md` authored independently by `cadence-explorer` (Medium/High tier)
- `spec.md` with full Contextual Grounding Matrix (6W×4L), CHORD decomposition, Engineering Pillar evaluation, Design Exploration convergence, and Compatibility Impact
- `test-plan.md` with Gherkin scenarios, CHORD observability seam scenarios (`UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `DELTA_AUDIT_GAP`, `BOUNDARY_FAULT`), journey invariants, and TDD implementation order
- `decisions.md` with immutable Gate 1/2/3 rulings
- `submission.md` capturing the change proposal, review discussion, and follow-up dispositions
- `metadata.yaml` with per-stage effort accumulation and automatic tracker projection (`CADENCE_ORG.md#tracker-binding`)

---

## Phase 1: Contextual Grounding

Before selecting Engineering Pillars or decomposing acceptance criteria, the LLM must establish a factual baseline of the system across the six fundamental interrogatives (**What**, **How**, **Where**, **Who**, **When**, **Why**). Every statement in Phase 1 must cite concrete repository evidence (file paths, line numbers, function signatures, or infrastructure manifests) rather than assumptions.

### Instructions for the LLM

**When an organization configuration (`CADENCE_ORG.md`) is present:** copy its pre-populated Contextual Grounding constants (**Where**, **Who**, **Why**) into `CONTEXT_FACTS.md` first, then layer repository-specific facts discovered from the codebase on top.

#### For existing codebases

Inspect the codebase (using `repo-scout` / `local_semantic_embed` on `:9379` when available) and produce a **Contextual Grounding Fact Sheet** (`CONTEXT_FACTS.md`) with one section per interrogative column. Every section must include:
- **Concrete citations** (exact file paths, line ranges, class/function names, configuration keys)
- **Explicit counts** (number of persistent entities, endpoints, runtime services, actor roles, scheduled jobs)
- **System boundaries** (what sits inside this repository's bounded context vs. external upstream/downstream systems)

Never guess. If an interrogative column has zero occurrences in the codebase (for example, zero scheduled cron jobs under **When**), state that fact explicitly.

#### For greenfield projects

When no application source code exists yet:

1. **Anchor on the problem statement's `SCOPE` and `CONSTRAINTS`.** These establish the initial boundary of the system.
2. **Inventory the surrounding platform ecosystem** — container runtime, identity provider, CI/CD pipelines, secrets manager, and adjacent services the new system will integrate with.
3. **Separate *known platform facts* from *open design proposals* in each column.** Explicitly tag open choices so Phase 2 can evaluate them against the active Engineering Pillars.
4. **Label `What (Data)` and `How (Process)` entries as proposals** (e.g., *"Proposed domain entities: ..."*) rather than discovered code facts.
5. **Populate `Where (Network)`, `Who (People)`, and `Why (Motivation)` from existing organization infrastructure and compliance requirements**, which almost always predate a new repository.

### The Six Questions

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT (Data)                                                         │
│                                                                     │
│ What persistent data and state does the system own?                 │
│                                                                     │
│ - List every persistent entity (DB tables, document collections,    │
│   file stores, caches)                                              │
│ - For each: name, primary key, approximate volume, read/write paths │
│ - Distinguish authoritative source-of-truth stores from caches      │
│ - Note composite keys, soft-delete flags, or temporal history tables│
│ - Map entity relationships (1:1, 1:many, many:many)                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ HOW (Process)                                                       │
│                                                                     │
│ What operations and workflows act on that data?                     │
│                                                                     │
│ - List every entry point (REST/GraphQL endpoints, CLI commands,     │
│   event consumers, UI actions)                                      │
│ - Classify each as: read-only, single-table write, multi-table      │
│   write, or external side-effect (email, S3, queue publish)         │
│ - For writes: document the mutation contract (request payload,      │
│   validation rules, transactional boundaries, audit logging)        │
│ - Identify domain orchestration and computation living outside      │
│   the datastore                                                     │
│ - Count: generic CRUD handlers vs. custom domain workflows          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHERE (Network)                                                     │
│                                                                     │
│ What infrastructure and external services does the system touch?    │
│                                                                     │
│ - List every runtime service (datastores, caches, message brokers,  │
│   internal microservices, third-party SaaS APIs)                    │
│ - For each: protocol, port, authentication method, network zone     │
│   (public ingress / private VPC / localhost sidecar)                │
│ - Map the deployment topology (containers, VMs, serverless, CDN)    │
│ - Identify how secrets are injected (secrets manager, mounts, env)  │
│ - Note any co-located dependencies vs. network-isolated calls       │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHO (People)                                                        │
│                                                                     │
│ Which actors interact with or operate the system?                   │
│                                                                     │
│ - List every actor role or principal group                          │
│ - For each: permitted reads, permitted mutations, and identity      │
│   mechanism (OIDC/SSO, API key, mTLS, service token)                │
│ - Where is authorization enforced? (API gateway, server handler,    │
│   data-access layer, row-level security)                            │
│ - Who operates the service in production? (product team, SRE,       │
│   self-service platform)                                            │
│ - Who authors and maintains the code? (human engineers, CADENCE     │
│   agents, or both)                                                  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHEN (Timing)                                                       │
│                                                                     │
│ What temporal constraints, schedules, and SLAs govern the system?   │
│                                                                     │
│ - Scheduled jobs (cron tasks, background workers, queue consumers)  │
│ - Cache TTLs and invalidation triggers                              │
│ - Polling intervals and readiness/liveness probe timers             │
│ - Event-driven triggers (webhooks, pub/sub consumers, streams)      │
│ - Latency SLAs (API p95/p99 targets, job completion windows)        │
│ - Data freshness guarantees (synchronous, near-real-time, eventual) │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHY (Motivation)                                                    │
│                                                                     │
│ What business goals, policies, and delivery pipelines drive change? │
│                                                                     │
│ - CI/CD pipeline stages, branch strategy, and deployment triggers   │
│ - Release cadence and version scheme                                │
│ - Rollback mechanism (container revert, expand/contract, flags)     │
│ - Core user pain points or operational risks motivating this work   │
│ - Non-negotiable compliance, regulatory, or deadline constraints    │
└─────────────────────────────────────────────────────────────────────┘
```

### Output format

Emit a single document named `CONTEXT_FACTS.md` containing six sections corresponding to the interrogative columns above, with 10–30 concrete, cited bullet points per section.

---

## Phase 2: Pillar Library Construction

An **Engineering Pillar** is a named architectural quality concern that governs design trade-offs across a repository. Pillars are not product features — they are the structural lenses through which every proposed design is evaluated.

### Standard Pillar Catalog

Below are the 9 standard CADENCE Engineering Pillars. Not every repository activates all 9. During Phase 2, the LLM **selects 4–6 pillars** (including the 3 always-on mandatory pillars plus any triggered mandatory pillars that activate and 0–2 open-slot pillars) and customizes each with concrete measures grounded in `CONTEXT_FACTS.md`.

#### Pillar definitions

```
┌──────────────────────────────────────────────────────────────────┐
│ STRUCTURAL SIMPLICITY                                            │
│                                                                  │
│ The system must have the fewest moving parts necessary to        │
│ deliver the required capability.                                 │
│                                                                  │
│ Contextual Grounding alignment: How (Process), What (Data)       │
│                                                                  │
│ When to select: Always (Always-On Mandatory Pillar 1).           │
│                                                                  │
│ Typical measures:                                                │
│ - Runtime deployable service count                               │
│ - State management layers (1 primary source of truth)            │
│ - Files/lines of config touched to wire a new capability (<=3)   │
│ - CI pipeline build step count                                   │
│ - External runtime dependency count                              │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Pass-through wrapper layers adding indirection without value   │
│ - Adding caching layers without profiling evidence               │
│ - Speculative abstractions for unrequested future use cases      │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ OPERATIONAL RESILIENCE                                           │
│                                                                  │
│ The system must be deployable, observable, and recoverable by    │
│ the team that operates it on standard infrastructure.            │
│                                                                  │
│ Contextual Grounding alignment: Where (Network), When (Timing),  │
│                                 Why (Motivation)                 │
│                                                                  │
│ When to select: Always (Always-On Mandatory Pillar 2).           │
│                                                                  │
│ Typical measures:                                                │
│ - Lead time from commit to running in target environment         │
│ - Secrets managed 100% via secrets manager (zero in env/source)  │
│ - Readiness/health check coverage across all dependencies        │
│ - Single-action rollback procedure documented and verified       │
│ - Structured JSON logging with trace_id, span_id, request_id     │
│ - W3C Trace Context propagation across inter-service calls       │
│ - Endpoint metrics (request count, p50/p95/p99 latency, errors)  │
│ - Alert coverage for dependencies and critical paths             │
│ - Runtime observability seams derived from CHORD dimensions      │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Client-only error handling invisible to server telemetry       │
│ - Unstructured log strings lacking correlation IDs               │
│ - Environment/asset references absent from target deployment     │
│ - Deferring logging, metrics, or CHORD seams to follow-up work   │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ AGENTIC ERGONOMICS                                               │
│                                                                  │
│ The codebase must maximize the probability that an AI coding     │
│ agent produces correct, compliant code on the first pass.        │
│                                                                  │
│ Contextual Grounding alignment: How (Process), What (Data)       │
│                                                                  │
│ When to select: Always (Always-On Mandatory Pillar 3) when AI    │
│ agents (.agents/ workflow) author or maintain repository code.   │
│                                                                  │
│ Typical measures:                                                │
│ - Max authored file length (strictly <400 lines; scenario-       │
│   indexed BDD test harnesses governed per function instead)      │
│ - Strict static type coverage (target: 100%)                     │
│ - Template uniformity (1 existing example suffices to author     │
│   a valid new instance)                                          │
│ - Context budget: agent reads <=5 files to add a capability      │
│ - Root AGENTS.md present and current                             │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Multi-concern "god files" mixing routing, logic, and storage   │
│ - Dynamic imports or metaprogramming obscuring the call graph    │
│ - Undocumented conventions living outside AGENTS.md / repo docs  │
│ - Shared mutable state outside explicit domain stores            │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ DATA & AUDIT FIDELITY                                            │
│                                                                  │
│ Every state mutation must be auditable, consistent with domain   │
│ contracts, and recoverable from partial failure.                 │
│                                                                  │
│ Contextual Grounding alignment: What (Data), When (Timing),      │
│                                 Who (People)                     │
│                                                                  │
│ When to select: Triggered mandatory whenever the system          │
│ captures, mutates, or persists data it owns, or when migrating   │
│ write paths or satisfying compliance audit requirements.         │
│                                                                  │
│ Typical measures:                                                │
│ - Mutation audit coverage (100% of writes emit an audit record)  │
│ - Actor identity captured from server auth principal, never input│
│ - Multi-table write sequencing and failure compensation specified│
│ - Server-side computation of all derived fields                  │
│ - Explicit cache invalidation on every write                     │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Fire-and-forget multi-step writes that leave partial state     │
│ - Trusting client-computed totals or status fields               │
│ - Optimistic UI mutations on multi-table transactions            │
│ - Cascading deletes without explicit blast-radius confirmation   │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ SECURITY BOUNDARY POSTURE                                        │
│                                                                  │
│ Changes must never weaken the authentication/authorization trust │
│ chain or expand the unvalidated attack surface.                  │
│                                                                  │
│ Contextual Grounding alignment: Who (People), Where (Network)    │
│                                                                  │
│ When to select: Triggered mandatory whenever a change touches    │
│ authentication, authorization, PII, untrusted input handling,    │
│ network boundaries, or new client-side code.                     │
│                                                                  │
│ Typical measures:                                                │
│ - Zero secrets or sensitive tokens exposed to client bundles     │
│ - Caller authority derived server-side from authenticated token  │
│ - Default-deny authorization policy on all new endpoints/views   │
│ - Per-record data-access authorization checks                    │
│ - Zero PII/financial/secret fields in logs or URL query strings  │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Client-side role checks without server-side enforcement        │
│ - Scoping queries by caller-supplied tenant/user ID parameters   │
│ - eval(), raw HTML injection, or unparameterized queries         │
│ - Storing sensitive session tokens in browser localStorage       │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ MODULAR REPLACEABILITY                                           │
│                                                                  │
│ Architectural layers communicate strictly through explicit       │
│ contracts so any adapter or library can be swapped cleanly.      │
│                                                                  │
│ Contextual Grounding alignment: What (Data), How (Process),      │
│                                 Where (Network)                  │
│                                                                  │
│ When to select: When integrating third-party libraries or        │
│ runtimes that may be replaced (UI framework, ORM, cloud SDK,     │
│ CLI runtime projection), or designing long-lived core modules.   │
│                                                                  │
│ Typical measures:                                                │
│ - Blast radius to swap an adapter/library (target: <10 files)    │
│ - Boundary contracts defined by repository-owned types/schemas   │
│ - Zero cross-layer leaky imports                                 │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Domain services importing vendor SDK types directly            │
│ - Coupling UI route hierarchy to backend persistence schemas     │
│ - Scattering runtime-specific primitives outside binding tables  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ EXECUTION PERFORMANCE                                            │
│                                                                  │
│ The system must satisfy its latency, throughput, and resource    │
│ budgets under production load without over-provisioning.         │
│                                                                  │
│ Contextual Grounding alignment: When (Timing), Where (Network),  │
│                                 What (Data)                      │
│                                                                  │
│ When to select: When the change affects latency-critical paths,  │
│ high-volume queries, client bundle size, or memory footprint,    │
│ or when the problem statement targets scaling or optimization.   │
│                                                                  │
│ Typical measures:                                                │
│ - p95 / p99 response latency on critical endpoints               │
│ - Client bundle size and time-to-interactive                     │
│ - Database query count per request (zero N+1 query patterns)     │
│ - Bounded memory footprint and streaming/pagination on large sets│
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Loading unbounded result sets into memory without pagination   │
│ - Full-tree UI re-renders on localized state updates             │
│ - Synchronous blocking I/O on hot request paths                  │
│ - Querying unindexed columns on large tables                     │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ AUTOMATED VERIFIABILITY                                          │
│                                                                  │
│ Every behavioral claim in the specification must be provable     │
│ by deterministic automated tests running in CI.                  │
│                                                                  │
│ Contextual Grounding alignment: How (Process), Why (Motivation)  │
│                                                                  │
│ When to select: When preserving a regression-sensitive test      │
│ suite, introducing complex state machines, or hardening          │
│ distributed journeys under chaos profiles.                       │
│                                                                  │
│ Typical measures:                                                │
│ - Test pyramid balance (unit BDD > integration BDD > journey)    │
│ - Deterministic execution (zero live external network calls)     │
│ - CI test suite runtime budget                                   │
│ - Zero flaky tests tolerated on the integration branch           │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Tests coupled to shared mutable state across test cases        │
│ - Unverified mocks masking real contract mismatches              │
│ - Asserting on governance markdown instead of runtime behavior   │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ SURFACE COMPATIBILITY                                            │
│                                                                  │
│ Public surfaces (APIs, events, schemas, CLI flags, config keys)  │
│ must remain backwards-compatible across their guarantee window.  │
│ Breaking changes require deprecation, migration guides, and      │
│ automated compatibility tests.                                   │
│                                                                  │
│ Contextual Grounding alignment: How (Process), What (Data),      │
│                                 When (Timing)                    │
│                                                                  │
│ When to select: Triggered mandatory whenever a change touches a  │
│ registered public surface or introduces a new public contract.   │
│                                                                  │
│ Typical measures:                                                │
│ - Public surface registries (`surface-registry.md` and           │
│   `cadence-surfaces.md`) are current                             │
│ - All stable surfaces declare a guarantee window                 │
│ - Breaking changes carry a deprecation plan and sunset date      │
│ - Golden-file snapshot tests guard stable response/event shapes  │
│ - Consumer-driven contract tests verify inter-service expectations│
│ - Versioned integration tests replay prior-version requests      │
│ - Runtime deprecation signals (headers, logs, metrics) emitted   │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Removing or renaming response fields without registry audit    │
│ - Renaming endpoints without API versioning                      │
│ - Altering payload semantics without a version increment         │
│ - Adding required fields to existing request contracts           │
│ - Updating golden snapshots without reviewing the contract diff  │
└──────────────────────────────────────────────────────────────────┘
```

### Triggered Mandatory Pillars

Certain Engineering Pillars do not need to be evaluated on every internal change, but become **strictly mandatory whenever their trigger condition holds**. The organization configuration (`CADENCE_ORG.md`) or repository pillar library declares these triggers explicitly. When triggered, they sit alongside the always-on mandatory pillars; when dormant, they are marked `"N/A (not triggered)"` with a one-line explanation.

**The three canonical triggered mandatory pillars are:**

1. **Data & Audit Fidelity:**
   - **Trigger:** The system captures, mutates, or persists data it owns (databases, file stores, ledgers, audit logs, or owned records of user input).
   - **When triggered:** Include all Data & Audit Fidelity measures customized to the repository's datastores.
   - **When dormant:** Mark `"Data & Audit Fidelity — N/A (change touches zero owned persistent data)."`
2. **Surface Compatibility:**
   - **Trigger:** The change touches a public surface registered in `docs/policies/surface-registry.md` or `docs/policies/cadence-surfaces.md`, or introduces a new public surface (API endpoint, event schema, shared DTO, CLI contract, configuration key).
   - **When triggered:** Include all Surface Compatibility measures and populate the `## Compatibility Impact` section in `spec.md`.
   - **When dormant:** Mark `"Surface Compatibility — N/A (no registered surfaces affected and no new public surfaces introduced)."`
3. **Security Boundary Posture:**
   - **Trigger:** The change touches authentication, authorization, PII/sensitive data, untrusted user input parsing, network ingress/egress, or client-side code.
   - **When triggered:** Include all Security Boundary Posture measures.
   - **When dormant:** Mark `"Security Boundary Posture — N/A (no auth, PII, input boundary, or client code touched)."`

All triggered mandatory pillars are **fail-closed**: whenever in doubt as to whether a trigger fires, activate the pillar.

### Pillar selection rules

The LLM selects governing pillars using these nine rules:

1. **Always include** Structural Simplicity and Operational Resilience on every project.
2. **Include Agentic Ergonomics** whenever AI coding agents author or maintain repository code (always-on in CADENCE repositories).
3. **Evaluate Data & Audit Fidelity's trigger** — activate whenever the system captures, mutates, or persists owned data, or when migrating write paths.
4. **Evaluate Security Boundary Posture's trigger** — activate whenever the change touches authentication, authorization, PII, input handling, network boundaries, or client-side code.
5. **Evaluate Surface Compatibility's trigger** — activate whenever the change touches registered public surfaces or introduces new public contracts.
6. **Include Execution Performance** when the problem statement targets latency, throughput, scale, or when `CONTEXT_FACTS.md` reveals large datasets or hot paths.
7. **Include Automated Verifiability** when preserving an existing regression suite or specifying distributed journey invariants under chaos profiles.
8. **Include Modular Replaceability** when the problem statement involves a technology migration, adapter swap, or multi-runtime projection.
9. **Keep open-slot pillars to at most 2** (for a total of 3 always-on + triggered mandatory pillars + 0–2 open-slot pillars). If additional open-slot concerns arise, fold the secondary concern into an adjacent active pillar (for example, folding Automated Verifiability into Operational Resilience).

### Customization instructions

For every active pillar in `PILLAR_LIBRARY.md`, the LLM must:

1. **Retain or sharpen the core definition** for the repository's domain.
2. **Replace generic measures with concrete repository targets** citing numbers and components from `CONTEXT_FACTS.md` (for example, replacing *"Runtime service count"* with *"Runtime service count (currently 3: Flask API on :5000, worker on :5500, legacy Shiny on :3838; target: 2 after retiring Shiny)"*).
3. **Replace generic anti-patterns with repository-specific anti-patterns** referencing actual modules and boundaries in the codebase.
4. **State a single-sentence decision rule** that resolves design tie-breaks for this repository.

### Precedence matrix

After customizing the active pillars, the LLM produces an ordered **Precedence Matrix** ranking the pillars from highest priority (#1) to lowest. Whenever two pillars recommend conflicting designs, the higher-ranked pillar prevails.

**Default CADENCE precedence** (override per repository only with documented justification):

```
1. Data & Audit Fidelity       — never trade away data correctness or auditability
                                 (when triggered; collapses out otherwise)
2. Security Boundary Posture   — never weaken the auth trust chain or expose PII
                                 (when triggered; collapses out otherwise)
3. Surface Compatibility       — public contracts are promises to consumers
                                 (when triggered; collapses out otherwise)
4. Structural Simplicity       — fewer moving parts beat clever abstractions
5. Operational Resilience      — the team must be able to deploy, observe, and roll back
6. Agentic Ergonomics          — optimize for first-pass agent accuracy (<400 lines/file)
7. Execution Performance       — meet SLA targets without premature micro-optimization
8. Automated Verifiability     — deterministic behavioral coverage in CI
9. Modular Replaceability      — clean seam contracts without speculative over-abstraction
```

Whenever any triggered mandatory pillar (1–3) is dormant for a given ticket, the active precedence order collapses cleanly past its slot.

### Output format

Emit `PILLAR_LIBRARY.md` containing:
- One section per active pillar (definition, Contextual Grounding alignment, concrete measures, anti-patterns, one-sentence decision rule)
- Explicit status and activation rules for all *triggered mandatory pillars*
- A closing **Pillar Interaction & Precedence Matrix** section

---

## Phase 3: CHORD Decomposition

Once Phase 1 grounds the system context and Phase 2 establishes the governing Engineering Pillars, **Phase 3 (CHORD Decomposition)** turns every acceptance criterion from `problem.md` into a rigorous behavioral contract. CHORD decomposes each criterion into five behavioral dimensions that map 1-to-1 onto Gherkin BDD scenarios and runtime observability seams.

### The Five Dimensions

| Dimension | What It Captures | Becomes in the Test |
|---|---|---|
| **Conditions** | System state and preconditions that must hold before execution | `Given` — test setup / arrangement |
| **Handling** | Input parameters, commands, or events that initiate the behavior | `When` — the action under test |
| **Outcomes** | Observable external emissions: responses, events, downstream calls | `Then` — verify external interactions |
| **Rules** | Business invariants and domain constraints governing the behavior | `Then` — verify domain invariants |
| **Deltas** | Internal state mutations to domain entities or persistent storage | `Then` — verify persistent state changes |

Populate all five rows for every acceptance criterion in `problem.md`, referencing concrete entities, services, and endpoints from `CONTEXT_FACTS.md`.

### The Edge Case Engine

For each of the five CHORD dimensions, ask *"what happens if this dimension is violated?"*:

| Dimension | Violation | Produces |
|---|---|---|
| Conditions | Entity missing? Wrong lifecycle state? Expired? | Not-found errors, precondition rejection scenarios |
| Handling | Null? Empty? Malformed type? Unauthenticated/unauthorized caller? | Input validation errors, auth rejection scenarios |
| Outcomes | Downstream dependency unreachable? Timeout? | Circuit-breaker, retry, and graceful error scenarios |
| Rules | Domain invariant broken? Quota or limit exceeded? | Business rule violation scenarios |
| Deltas | Concurrent modification? Partial multi-table write failure? | Optimistic concurrency conflict and rollback scenarios |

Because edge cases are derived mechanically across all five dimensions rather than brainstormed ad-hoc, scenario coverage remains thorough and repeatable across every ticket.

### CHORD-to-Gherkin

Each CHORD table translates directly into framework-agnostic Gherkin scenarios:

```gherkin
# Happy path: Conditions → Given, Handling → When, Deltas + Outcomes + Rules → Then
Scenario: S-1.1 -- Primary success path
  Given {conditions from CHORD}
  When {handling trigger from CHORD}
  Then {deltas from CHORD}
  And {outcomes from CHORD}

# Edge case: what if a required entry condition is violated?
Scenario: S-1.2 -- Entity not found
  Given {condition violation}
  When {same handling trigger}
  Then {error response with specific message}
```

The `cadence-implementer` agent discovers the repository's concrete test framework, assertion style, and fixture conventions during Phase 4 (Test Infrastructure Discovery) before translating each Gherkin scenario into executable test code.

### Observability Seams

CHORD dimensions extend directly into production monitoring through **observability seams**: structured runtime log events and metrics emitted at dimension boundaries so any production divergence from the specification is surfaced automatically. Automated tests prove the code handles known scenarios; observability seams verify that CHORD invariants hold continuously under real production traffic.

Each CHORD dimension derives a specific runtime seam family:

| CHORD Dimension | Seam Type | What It Detects |
|---|---|---|
| **Conditions** | `UNSOUND_CONDITION` | A handler executed when its required entry conditions were false |
| **Rules** | `RULE_DIVERGENCE` | Business rule branch distribution deviates from its expected baseline |
| **Outcomes** | `DELTA_AUDIT_GAP` | Expected external call, notification, or trace span was skipped |
| **Deltas** | `DELTA_AUDIT_GAP` | Persistent state mutation committed without its required audit record |
| **Handling** | `BOUNDARY_FAULT` | Post-validation invariant broken after input transformation or mapping |

**Mechanical derivation prompts:**

- *Conditions → `UNSOUND_CONDITION`:* "If this entry condition were false at runtime despite upstream checks, what invalid state would the handler observe?"
- *Rules → `RULE_DIVERGENCE`:* "What is the expected branch ratio for this decision under normal production traffic, and what shift indicates drift?"
- *Outcomes → `DELTA_AUDIT_GAP`:* "If this external call or event emission silently failed to run without throwing an error, what trace checkpoint would catch the omission?"
- *Deltas → `DELTA_AUDIT_GAP`:* "If this entity mutation committed without writing its companion audit log entry, what check would detect the missing record?"
- *Handling → `BOUNDARY_FAULT`:* "After this input payload is parsed, mapped, or normalized, could the transformed value violate the original validation rule?"

Derive only the seams supported by the acceptance criterion's CHORD table:
- No branching domain rule → no `RULE_DIVERGENCE` seam
- No external outcome → no outcome `DELTA_AUDIT_GAP` seam
- No audit-mandated state mutation → no delta `DELTA_AUDIT_GAP` seam

### Output format

For each acceptance criterion in `problem.md`, produce:

1. A **CHORD decomposition table** (five rows: Conditions, Handling, Outcomes, Rules, Deltas).
2. A **mechanically derived edge-case table** covering violations of each dimension.
3. A **seam specification table** listing each derived runtime seam (`AC`, `Dimension`, `Seam Type`, `Event Name`, `Trigger Condition`, `Severity`).

These three artifacts are embedded directly into `spec.md` (and `ITERATION_N_SPEC.md`) and drive the Gherkin scenario suite in `test-plan.md`.

---

## Phase 4: Iteration Spec Generation

In Phase 4, the LLM synthesizes the problem statement, `CONTEXT_FACTS.md`, `PILLAR_LIBRARY.md`, and the Phase 3 CHORD decompositions into one or more executable iteration specifications.

### How many iterations?

Determine the appropriate number of iterations (`1–3`) using this decision tree:

```
Do all mutations in scope belong to the same complexity class?
  YES → 1 iteration
  NO  → Does the higher-complexity class activate a NEW governing
        Engineering Pillar not required by the lower class?
    YES → 2 iterations (split along the complexity / pillar boundary)
    NO  → 1 iteration (the same pillars govern both; splitting would
          duplicate ceremony without retiring distinct architectural risk)

Does any remaining scope activate a THIRD distinct governing pillar?
  YES → 3 iterations
  NO  → Stop at the current iteration count
```

**Mutation complexity classes** (from lowest to highest):
1. Read-only queries and views
2. Single-table / single-entity CRUD mutations
3. Multi-table transactional writes with ordering and rollback/compensation rules
4. Cross-service distributed orchestration (local datastore + external API + async event/queue)

**Splitting criterion:** Splitting work into an additional iteration is warranted **only** when the higher complexity class introduces a governing Engineering Pillar that **materially changes the architectural patterns or verification gates**. If the remaining scope merely repeats the same patterns on additional endpoints, keep it in a single iteration.

### Iteration spec structure

Every iteration specification follows the structure below. Sections marked `[required]` are mandatory on all specs; sections marked `[if applicable]` are included whenever `CONTEXT_FACTS.md` or the active Engineering Pillars trigger them.

```markdown
# Iteration N: {Title}

**Governing pillars:** {List the Engineering Pillars shaping this iteration}

**Why these pillars:** {1-2 sentences explaining why this pillar set governs
this iteration, and for Iteration N>1, which new pillar activated and why}

---

## 1. Scope [required]

### 1.1 What is being built
{Bullet list of concrete deliverables}

### 1.2 What is NOT being built
{Explicit non-goals for this iteration — prevents scope drift}

### 1.3 Success criteria
{Table: Criterion | Verification Measure — each objectively testable}

---

## 2. Contextual Grounding Alignment (6W×4L) [required]

For each Contextual Grounding column relevant to this iteration, state:
- What changes relative to the baseline in CONTEXT_FACTS.md
- What remains unchanged
- What constraints the governing pillars impose

### 2.1 What (Data) changes
### 2.2 How (Process) changes
### 2.3 Where (Network) changes
### 2.4 Who (People) changes
### 2.5 When (Timing) changes
### 2.6 Why (Motivation) for this iteration

---

## 3. CHORD Decomposition [required]

For every acceptance criterion in scope, include the five-dimension CHORD
table (Conditions, Handling, Outcomes, Rules, Deltas) and edge-case table
from Phase 3, cross-referenced to concrete entities, services, and endpoints.

---

## 4. Observability Seams [if applicable — required whenever
                           CHORD decomposition derives any seam]

The seam specification table from Phase 3 filtered to this iteration's ACs
(UNSOUND_CONDITION, RULE_DIVERGENCE, DELTA_AUDIT_GAP, BOUNDARY_FAULT).
Every row becomes both a runtime assertion and a BDD test scenario.

---

## 5. Mutation & Data Patterns [if applicable — required when
                                Data & Audit Fidelity is active]

Define the reusable data-integrity patterns governing every write in this
iteration:
- Mutation classification (single-entity, multi-entity transactional,
  compensating saga, destructive/confirm-required)
- Cache invalidation rules per mutation
- Partial-failure recovery (transactional rollback, idempotent retry, compensation)
- Server-authoritative vs. optimistic UI rules

---

## 6. Component / Module Specifications [required]

For each deliverable in §1.1, specify:
- Inputs (API request contracts, event payloads, caller principals)
- Outputs (responses, domain events, audit records)
- Governing pillar constraints (<400 lines per authored file, <=3 files wired)
- Complete type/method signatures so cadence-implementer can execute via TDD
  without ambiguity

---

## 7. Compatibility Impact [if applicable — required when
                             Surface Compatibility is triggered]

For every affected surface in `surface-registry.md` or `cadence-surfaces.md`,
classify the change as additive / modification / removal and link to the
deprecation plan and compatibility test suite.

---

## 8. Verification Plan [required]

### 8.1 Test Infrastructure Discovery
{Fields populated by cadence-implementer after scanning existing test suites:
test runner, assertion library, mocking approach, fixture patterns,
integration harness, naming conventions. New BDD tests use discovered
conventions; pre-existing tests are never rewritten.}

### 8.2 Automated BDD & Seam Tests
{Gherkin scenarios and implementation order derived from CHORD decomposition}

### 8.3 Manual / Deploy Validation
{End-to-end checks performed at Gate 4 in a non-prod environment}

### 8.4 Rollback Procedure
{Single-action application and expand/contract schema rollback steps}

---

## 9. Agent Execution Instructions [if applicable — required when
                                     Agentic Ergonomics is active]

### Ordered TDD task sequence
{Numbered red-green-accumulate-commit sequence ordered from happy path to E2E}

### Parallelization boundaries
{Which independent modules or tickets can execute concurrently in isolated git worktrees}

### Human review gates
{Mandatory Gate 1, Gate 2, Gate 3, and Gate 4 checkpoints}
```

---

## Phase 5: Comparison Document (Multi-Iteration Only)

Whenever Phase 4 produces two or more iterations, the LLM generates `SPEC_COMPARISON.md` for Gate 1 architectural review, explaining **why the scope was partitioned across iterations** and **what architectural risk each iteration retires**.

### Required sections

```markdown
# Iteration Comparison

## 1. Fundamental Split Axis
{The primary architectural axis dividing the iterations — typically mutation
complexity class or the activation of an additional Engineering Pillar}

## 2. Contextual Grounding Column-by-Column Comparison
{Table across What, How, Where, Who, When, Why: Aspect | Iteration 1 | Iteration 2 | ...}

## 3. Component Reuse & Evolution Matrix
{Which modules/entities are created in Iteration 1 vs. reused or extended in Iteration 2+}

## 4. Risk Retirement Profile
{Which specific technical, operational, or compliance risk each iteration retires}

## 5. Iteration Count Decision Log
{Why this exact number of iterations was chosen rather than fewer or more}

## 6. Per-Iteration Pillar Compliance Checklists
{Verification checklist per iteration against its active Engineering Pillars}
```

---

## Prompt Integration Guide

Use the mapping table below to translate common user request archetypes into initial Engineering Pillar selections during Phase 2.

### Prompt type → Pillar selection hints

| Prompt type | Example | Likely active pillars |
|-------------|---------|-----------------------|
| **Add a feature** | "Add user notifications" | Structural Simplicity, Operational Resilience, Agentic Ergonomics, Data & Audit Fidelity (if writes), Security Boundary Posture (if user-facing) |
| **Pay down tech debt** | "Decouple the API handler layer" | Structural Simplicity, Modular Replaceability, Agentic Ergonomics |
| **Extract / modularize** | "Split the billing module into a service" | Structural Simplicity, Operational Resilience, Modular Replaceability, Surface Compatibility |
| **Migrate technology** | "Migrate frontend from Angular to React" | Structural Simplicity, Operational Resilience, Agentic Ergonomics, Data & Audit Fidelity (if mutation paths change) |
| **Optimize performance** | "Dashboard query latency exceeds 2s" | Execution Performance, Structural Simplicity, Operational Resilience |
| **Security / compliance hardening** | "Prepare expense service for SOC 2 audit" | Security Boundary Posture, Data & Audit Fidelity, Operational Resilience, Automated Verifiability |
| **Onboard AI coding agents** | "Adopt CADENCE and `.agents/` in this repo" | Agentic Ergonomics, Structural Simplicity, Automated Verifiability |
| **Scale throughput** | "Support 10x peak event ingestion load" | Execution Performance, Operational Resilience, Modular Replaceability |

### Prompt parsing rules

1. **Identify the primary verb.** Add, fix, refactor, migrate, improve, harden, onboard, or scale — each points to the primary Engineering Pillars at stake.
2. **Bound the scope.** Single module, cross-cutting subsystem, or entire repository? Scope determines how broadly Phase 1 explores and whether multiple iterations are warranted.
3. **Extract hard constraints.** Delivery deadlines, team size, platform standards, and regulatory regimes may elevate specific pillars in the Precedence Matrix.
4. **Halt and clarify when ambiguous.** If a problem statement omits scope or success criteria, ask targeted clarifying questions before starting Phase 1 — never guess silently (CADENCE Behavior 1).

### LLM workflow summary

```
User Problem Statement
  │
  ▼
Phase 1: Explore codebase & org constants → produce CONTEXT_FACTS.md (6W×4L)
  │
  ▼
Phase 2: Select 3 always-on + triggered mandatory + 0–2 open pillars → produce PILLAR_LIBRARY.md
  │
  ▼
Phase 3: Decompose each AC into CHORD dimensions (C-H-O-R-D) → derive observability seams
  │
  ▼
Phase 4: Evaluate mutation complexity classes → author ITERATION_N_SPEC.md / spec.md + test-plan.md
  │
  ▼
Phase 5 (when multi-iteration): Produce SPEC_COMPARISON.md
  │
  ▼
Present for Gate 1 (Spec Review) human approval
```

---

## Appendix: Pillar Library Quality Checklist

Before presenting `PILLAR_LIBRARY.md` or `spec.md` for Gate 1 review, verify every item below:

- [ ] Every pillar measure states a concrete, verifiable target or threshold rather than a vague aspiration
- [ ] Every anti-pattern cites a specific code structure, layer boundary, or operational failure mode relevant to this repository
- [ ] Every pillar includes a single-sentence decision rule that resolves design trade-offs deterministically
- [ ] Any deviation from the default CADENCE Precedence Matrix carries an explicit written justification
- [ ] Zero overlapping pillars (for example, do not invent a separate "Maintainability" pillar — it is already covered by Structural Simplicity + Agentic Ergonomics)
- [ ] Active pillars cover every Contextual Grounding column (`What`, `How`, `Where`, `Who`, `When`, `Why`) touched by the problem statement
- [ ] All triggered mandatory pillars (**Data & Audit Fidelity**, **Surface Compatibility**, **Security Boundary Posture**) have their trigger evaluation explicitly recorded
- [ ] Open-slot pillar selection stays within the `0–2` slot budget (alongside the 3 always-on mandatory pillars and any triggered mandatory pillars that activated)
