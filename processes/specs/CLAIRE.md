# CLAIRE — A Framework for Refracting Problem Statements into Governed Iteration Specs

*A Zachman-grounded, facet-driven, SCOUT-decomposed framework for generating architectural specs that AI agents and human teams can execute.*

**Version:** 2.0
**Purpose:** A reusable template for any LLM (Claude, GPT, etc.) to analyze a codebase, build a project-specific architectural facet library, decompose each acceptance criterion into testable behavioral contracts, and generate one or more iteration specs from a user prompt. CLAIRE (Cognitive Learning & AI Response Engine) takes a single prompt and decomposes it into a set of governed specs — each shaped by the architectural concerns that matter most for that work.

**How CLAIRE relates to SCOUT:** CLAIRE is the umbrella framework. SCOUT (State, Constraints, Outputs, Updates, Triggers) is one of the tools CLAIRE uses — it decomposes each acceptance criterion into five behavioral dimensions that map directly to Gherkin test scenarios and runtime observability seams. SCOUT is introduced in Phase 3.

**How to use this document:**
1. Give this template to your LLM alongside access to your codebase (or an empty repo for greenfield projects).
2. Optionally, provide an **org configuration** that pre-fills constants for your organization (see "Creating Your Org Configuration" below, or the examples in `EXAMPLES/`).
3. Provide a **problem statement** (see "Writing a Problem Statement" below).
4. The LLM follows Phases 1–5 to produce: a Zachman grounding, a facet library, a SCOUT decomposition per acceptance criterion (with derived observability seams), iteration specs, and (when more than one iteration is produced) a comparison document.

---

## What CLAIRE Is Not

- **Not a project management framework.** It produces specs, not sprints or roadmaps. Use your existing PM tools for scheduling.
- **Not a code generator.** Specs are precise enough for an agent to execute, but CLAIRE itself doesn't write code.
- **Not prescriptive about technology.** CLAIRE works with any language, framework, or architecture. The facets evaluate architectural concerns, not technology choices.
- **Not all-or-nothing.** You can use just the problem statement format, or just Phase 1 (Zachman grounding), or the full 5-phase workflow. Each phase produces a standalone artifact.

---

## Writing a Problem Statement

The quality of CLAIRE's output depends entirely on the quality of your input. A good problem statement has four parts:

### The four-part structure

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  [VERB]  what you want to do                                        │
│  [SCOPE] what part of the system it affects                         │
│  [WHY]   what pain or goal motivates this                           │
│  [CONSTRAINTS] what limits the solution space                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**VERB** tells the LLM which facets to emphasize. SCOPE tells it how much of the codebase to explore. WHY prevents the LLM from solving the wrong problem. CONSTRAINTS prevent it from proposing solutions you can't execute.

### Verbs and what they signal

| Verb | Signals | LLM interprets as |
|------|---------|-------------------|
| **Add** | New capability that doesn't exist | New code, possibly new tables/endpoints |
| **Migrate** | Replace one technology with another | Preserve behavior, change implementation |
| **Refactor** | Change structure without changing behavior | No new features, no new endpoints |
| **Fix** | Something is broken | Diagnosis first, then targeted repair |
| **Improve** | Something works but is inadequate | Measure current state, then optimize |
| **Harden** | Something is vulnerable or non-compliant | Audit first, then remediate |
| **Scale** | Something works but won't at higher load | Profile first, then redesign bottlenecks |
| **Split** | Something is too large or coupled | Identify boundaries, then extract |

### Examples: weak vs. strong problem statements

**Weak:** "Make the app better."

- No verb, no scope, no why, no constraints. The LLM will explore the entire codebase and guess.

**Weak:** "Add authentication."

- Has a verb and implicit scope, but no why or constraints. The LLM might propose OAuth, SAML, API keys, or magic links all valid, but only one fits your situation.

**Strong:**

```
VERB:        Migrate
SCOPE:       The entire frontend (13 views, R Shiny)
WHY:         The app is datatable-centric, not mobile-friendly, and
             unmaintainable by AI coding agents (10K-line server file,
             no type safety). Campaign managers struggle with
             4-direction scrolling on every view.
CONSTRAINTS: Keep the existing Flask API unchanged. Use React + Next.js.
             Must work on mobile and desktop. Claude Code agents will
             write the implementation. Team has no dedicated frontend
             engineer.
```

**Strong:**

```
VERB:        Add
SCOPE:       The checkout flow (3 pages: cart, payment, confirmation)
WHY:         We need Apple Pay support before the holiday season.
             Currently only Stripe card payments are supported.
CONSTRAINTS: Stripe is our payment processor (no new vendors).
             Must pass PCI-DSS SAQ-A. Ship by November 1.
             Two engineers available, one senior, one junior.
```

**Strong:**

```
VERB:        Refactor
SCOPE:       The API layer (src/api/) — currently 4 files averaging
             1,200 lines each
WHY:         AI agents produce incorrect code because the files are
             too long and mix concerns (routing, validation, DB queries,
             response formatting in one function). We're moving to
             agentic maintenance and need the codebase to be
             agent-friendly.
CONSTRAINTS: No behavior changes — every existing API response must
             remain identical. No new dependencies. Must keep all
             47 existing tests passing.
```

### Shorthand format

If you prefer brevity, use this one-liner template:

```
[VERB] [SCOPE] because [WHY], constrained by [CONSTRAINTS].
```

Example:

```
Migrate the frontend from R Shiny to React + Next.js because the
current UI is unmaintainable and not mobile-friendly, constrained
by keeping the Flask API unchanged and using Claude Code for
implementation.
```

### What if I don't know the constraints?

State what you *do* know and mark the rest as open:

```
VERB:        Add
SCOPE:       User notifications (email + in-app)
WHY:         Users miss critical updates to their campaigns
CONSTRAINTS: No preference on email provider (open to suggestion).
             Must integrate with our existing PostgreSQL database.
             Timeline: flexible. Team: 1 engineer + Claude Code.
```

The LLM will use the Zachman grounding phase to discover constraints you didn't know about (e.g., "the system already has a job queue that could deliver notifications" or "there's no email service configured — adding one requires a new infrastructure dependency").

---

## Sample Workflow: Brand-New Project

This walkthrough shows CLAIRE applied to a greenfield project — an internal expense reporting tool — from problem statement through spec delivery.

### Step 0: Set up

Place this template where your LLM can access it. In Claude Code, for example:

```bash
# Option A: Add to project
cp CLAIRE.md your-project/specs/CLAIRE.md

# Option B (Claude Code, for example): add to your tool's global rules directory
cp CLAIRE.md ~/.claude/rules/claire.md
```

Then open a conversation with access to your codebase (or an empty repo for greenfield).

### Step 1: Write the problem statement

```
VERB:        Build
SCOPE:       A new internal expense reporting tool (greenfield)
WHY:         Finance team currently uses shared Google Sheets to track
             expenses. No approval workflow, no audit trail, frequent
             data entry errors, no receipt attachment support.
CONSTRAINTS: - Must integrate with Okta SSO (existing company identity
               provider)
             - PostgreSQL (company standard)
             - Deploy to AWS ECS (existing infra)
             - 2 engineers + Claude Code for implementation
             - Finance team (non-technical) are the primary users
             - Must support mobile (field employees submit expenses
               on phone)
             - SOC 2 compliance required (audit trail on all changes)
```

### Step 2: Give both to the LLM

```
You have access to the CLAIRE framework in specs/CLAIRE.md.

Here is my problem statement:

[paste problem statement]

Run CLAIRE on this project. Start with Phase 1 (Zachman Grounding).
```

### Step 3: LLM executes Phase 1 (Zachman Grounding)

For a greenfield project, the Zachman fact sheet captures what exists in the *surrounding infrastructure* rather than in the (empty) codebase:

```markdown
# ZACHMAN_FACTS.md

## What (Data)
- No existing database — will be new PostgreSQL instance
- Entities to model (from problem statement): Expense, Receipt,
  ApprovalRequest, User, Department, Category
- Compliance requirement: every mutation must have an audit log entry
  (SOC 2)

## How (Process)
- No existing API — will be new
- Required workflows: submit expense → manager approval → finance
  review → reimbursement
- Multi-step: expense submission involves creating an Expense row,
  attaching Receipt(s), and creating an ApprovalRequest

## Where (Network)
- AWS ECS (existing cluster, team has Terraform modules)
- PostgreSQL (AWS RDS, existing provisioning playbook)
- Okta SSO (existing, OIDC/SAML)
- S3 for receipt storage (existing bucket pattern)
- No existing job queue or email service

## Who (People)
- Employees (submit expenses, view own history)
- Managers (approve/reject for direct reports)
- Finance (review all, export reports, configure categories)
- Ops: same 2 engineers who build it
- Maintenance: Claude Code agents

## When (Timing)
- No scheduled jobs initially
- Approval SLA: managers should see pending approvals within minutes
  (near-real-time, not batch)
- No existing cron infrastructure

## Why (Motivation)
- Replaces Google Sheets (no audit trail, no approval workflow)
- SOC 2 audit in Q3 — expense tracking is a finding
- CI/CD: GitHub Actions (company standard)
- Release cadence: continuous deploy to ECS on merge to main
```

### Step 4: LLM executes Phase 2 (Facet Library)

Based on the problem statement and Zachman facts, the LLM selects facets:

```
Selected facets (5):

1. Simplicity        — greenfield, small team, keep it minimal
2. Operability       — 2-person team operates what they build
3. DX (Agentic)      — Claude Code writes most of the code
4. Data Integrity    — SOC 2 requires audit trail on all mutations;
                        approval workflow is a multi-step write
5. Security Posture  — Okta SSO integration, PII in expense data,
                        receipt attachments in S3

Triggered mandatory:
- Backwards Compatibility (not triggered — greenfield, no consumers yet)

Not selected:
- Performance (small user base, no scale concern yet)
- Testability (merged into Operability — CI tests are an ops concern)
- Replaceability (greenfield, no legacy to swap)
```

The LLM then customizes each facet with project-specific measures, anti-patterns, and decision rules, and produces `FACET_LIBRARY.md`.

### Step 5: LLM executes Phase 3 (SCOUT Decomposition)

For each acceptance criterion in the problem statement, the LLM decomposes the behavior into the five SCOUT dimensions and derives observability seams:

```
AC: "A manager can approve an expense submitted by their direct report."

SCOUT Decomposition:
  State          — Expense exists in state Submitted; actor is the
                   approver assigned to the requesting user
  Constraints    — Approval changes Expense state to Approved; only
                   one approval per Expense
  Outputs        — Email notification to requester; audit log entry
                   recording approver + timestamp + comment
  Updates        — Expense.state = Approved; ApprovalRequest.resolved_at
                   set; audit_log row inserted
  Triggers       — Approver action via UI; Expense ID; optional comment

Derived Observability Seams:
  IMPOSSIBLE_STATE  — approval handler executes on non-Submitted expense
  LINEAGE_GAP       — Expense.state changes without audit_log row
                      written in same transaction
  LINEAGE_GAP       — Approved state reached without email notification
                      span in trace
```

The output is a section per AC in the iteration spec, plus a seam specification table.

### Step 6: LLM executes Phase 4 (Iteration Spec Generation)

The LLM evaluates the complexity classes:

```
Mutation types in scope:
- Single-table CRUD: create expense, edit category (Class 2)
- Multi-table write: submit expense with receipts + approval
  request (Class 3)
- Cross-service: Okta SSO + S3 receipt upload (Class 4)

Class 2 → governed by Simplicity + Operability + DX
Class 3 → adds Data Integrity (audit trail, multi-step sequencing)
Class 4 → Security Posture is already selected; no new facet needed

Decision: 2 iterations
- Iteration 1: Project scaffold, auth, simple CRUD (Classes 2 + 4)
  → Facets: Simplicity, Operability, DX, Security Posture
- Iteration 2: Approval workflow, audit trail, receipt management
  (Class 3)
  → Adds: Data Integrity
```

Output: `ITERATION_1_SPEC.md` and `ITERATION_2_SPEC.md`. Each iteration spec embeds its relevant SCOUT decompositions and seam tables from Phase 3.

### Step 7: LLM executes Phase 5 (Comparison)

Because more than one iteration was produced, the LLM produces `SPEC_COMPARISON.md` explaining:

- Iteration 1 mitigates **deployment risk** (can we get an app running in ECS with Okta SSO?)
- Iteration 2 mitigates **compliance risk** (does the audit trail meet SOC 2 requirements?)
- The split axis is **mutation complexity** (single-table vs. multi-step approval chain)

### Step 8: Review and execute

You now have these documents:

```
specs/
  ZACHMAN_FACTS.md         # What exists today (or what surrounds the new system)
  FACET_LIBRARY.md         # 5 customized facets with precedence matrix
  ITERATION_1_SPEC.md      # Scaffold + auth + simple CRUD (with SCOUT + seams)
  ITERATION_2_SPEC.md      # Approval workflow + audit trail (with SCOUT + seams)
  SPEC_COMPARISON.md       # Why 2 iterations, risk profile, compliance checklist
```

Hand any spec to an engineer or Claude Code agent:

```
Read specs/ITERATION_1_SPEC.md. Execute the agent task sequence
in section 6, starting with task 1. Ask me before proceeding
past any human review gate.
```

---

## Sample Workflow: Existing Project

For an existing codebase, the workflow is identical except Phase 1 is richer — the LLM explores actual code rather than inferring from the problem statement.

```
You have access to the CLAIRE framework in specs/CLAIRE.md.

Here is my problem statement:

Refactor the API layer (src/api/) because files average 1,200 lines
and mix routing, validation, DB queries, and response formatting.
Claude Code agents produce incorrect code due to file size and
concern mixing. Constrained by: no behavior changes, all 47 tests
must keep passing, no new dependencies.

Run CLAIRE. Start with Phase 1.
```

The LLM reads every file in `src/api/`, counts lines, maps function responsibilities, identifies the 47 tests, and produces a Zachman fact sheet grounded in the actual code. Phases 2–5 proceed identically.

### When to re-run CLAIRE

- **New major feature:** Write a new problem statement, re-run from Phase 1. The Zachman facts will include changes from prior iterations.
- **Mid-iteration course correction:** Update the problem statement's constraints, re-run from Phase 2. The Zachman facts haven't changed; only the facet selection or precedence might.
- **Post-iteration retrospective:** Compare actual outcomes against the spec's success criteria. Update the facet library's measures and anti-patterns based on what you learned. This improves future runs.

---

## Creating Your Org Configuration

An org configuration pre-fills constants that are the same across all your projects. This is **optional** — CLAIRE works without one — but it eliminates redundant discovery in Phase 1 and ensures consistency across projects.

To create one, make a file called `CLAIRE_{ORG}.md` (or any name you prefer; `CLAIRE_ORG.md` is the generic slot name) alongside `CLAIRE.md`. See the `EXAMPLES/` directory for real examples at different scales.

### What to pre-fill

**Zachman Constants** — facts that are true for every project in your org:

| Column | What to capture | Examples |
|--------|----------------|----------|
| **Where (Network)** | VCS, CI/CD, hosting, secrets management, observability, IaC | "GitHub Actions", "AWS ECS", "Datadog" |
| **Who (People)** | Identity provider, auth enforcement pattern, who maintains code | "Auth0 OIDC", "server-side enforcement", "engineers + AI agents" |
| **Why (Motivation)** | Branch strategy, release cadence, compliance requirements | "deploy on merge to main", "SOC 2 audit trail required" |

**What**, **How**, and **When** are almost always project-specific — don't pre-fill them.

**Mandatory Facets** — facets that apply to every project regardless of the problem statement:

- You can pre-select 0–4 of the 9 standard facets as mandatory
- For each, replace the "typical measures" and "typical anti-patterns" with your org's specifics
- You can also designate **Backwards Compatibility** as a *triggered mandatory* facet: it activates whenever a change touches a registered public surface or introduces one. See "Triggered Mandatory Facets" in Phase 2.
- Common patterns:
  - **Compliance-heavy orgs:** Data Integrity is mandatory (audit trail on all mutations)
  - **AI-first teams:** DX (Agentic) is mandatory (code optimized for agent maintenance)
  - **Small teams with no SRE:** Operability is mandatory (the team runs what it builds)
  - **Startups:** Simplicity is mandatory (complexity kills velocity at small scale)

**Precedence Matrix** — your org's default ordering with rationale:

- The default CLAIRE precedence (Data Integrity > Security > Backwards Compatibility *(when triggered)* > Simplicity > Operability > ...) works for most orgs
- Override it if your org has a different risk profile — e.g., a startup might put Simplicity first because over-engineering is a bigger risk than a missed audit log
- Always document *why* you deviate from the default

### What NOT to pre-fill

- Technology choices that vary by project (language, framework, database engine)
- What (Data), How (Process), When (Timing) — these are project-specific
- Anti-patterns specific to one codebase
- Team-specific conventions that aren't org-wide

---

## Scaling the Framework

CLAIRE scales from a solo developer's side project to a regulated enterprise system. Use what you need:

### Light mode — solo dev, small features, bug fixes

Use only:
- **problem.md** — the shorthand one-liner format is fine
- **spec.md** — skip the Zachman grid; keep the SCOUT decomposition and proposed design sections
- Inline your test strategy in the spec (skip the separate test-plan.md)
- Skip metadata.yaml and decisions.md

This is enough to get structured thinking without ceremony.

### Standard mode — team of 2–5, feature work

Use all templates except metadata.yaml (unless you have a project tracker to sync with):
- problem.md
- spec.md (full Zachman grid + SCOUT decomposition)
- test-plan.md
- decisions.md

### Full mode — regulated, enterprise, large teams

Use all templates plus an org configuration:
- problem.md with full business context
- spec.md with complete Zachman grid, SCOUT decomposition, and facet evaluation
- test-plan.md with BDD scenarios and implementation order
- decisions.md for the audit trail
- metadata.yaml synced with your project tracker
- Org configuration (`CLAIRE_ORG.md`) with mandatory facets and compliance requirements
- Observability seam specifications derived from SCOUT decompositions

---

## Phase 1: Zachman Grounding

Before defining facets or decomposing behaviors, the LLM must answer six questions about the system as it exists today. These correspond to the six Zachman Framework columns. Every answer must cite specific files, functions, or configurations — not general impressions.

### Instructions for the LLM

**If an org configuration exists** (e.g., `EXAMPLES/regulated-enterprise.md`), copy its pre-filled Zachman constants into the fact sheet first, then layer project-specific facts on top.

#### For existing codebases

Explore the codebase and produce a **Zachman Fact Sheet** with one section per column. Each section must contain:
- **Concrete evidence** (file paths, line numbers, function names, config values)
- **Counts** (how many entities, endpoints, services, roles, scheduled jobs)
- **Boundaries** (what is in scope vs. out of scope for this system)

Do not speculate. If a column has no evidence (e.g., no scheduled jobs exist), state that explicitly.

#### For greenfield projects

There is no codebase to explore. Instead:

1. **Start from the problem statement's SCOPE and CONSTRAINTS.** These define the boundaries of the new system.
2. **Inventory the surrounding ecosystem** — infrastructure, identity providers, CI/CD, existing services the new system must integrate with, team capabilities.
3. **For each Zachman column, capture what is *known* vs. what must be *decided*.** Mark open decisions explicitly — Phase 2 will validate them against the governing facets.
4. **What (Data) and How (Process) will be *design proposals***, not discovered facts. Label them as such: "Proposed entities: ..." rather than "Existing entities: ..."
5. **Where (Network), Who (People), and Why (Motivation) are often partially known** even for greenfield — the team, the hosting environment, and the compliance requirements usually predate the project.

Greenfield Zachman facts are inherently more speculative. The facet library in Phase 2 should flag any fact marked as a design proposal and validate it against the governing facets before relying on it in Phase 4.

### The Six Questions

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT (Data)                                                         │
│                                                                     │
│ What data does the system own?                                      │
│                                                                     │
│ - List every persistent entity (DB tables, files, caches)           │
│ - For each: name, primary key, approximate row count, read/write    │
│ - Identify which are source-of-truth vs. derived/cached             │
│ - Note any composite keys, soft deletes, or temporal versioning     │
│ - Map entity relationships (1:1, 1:many, many:many)                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ HOW (Process)                                                       │
│                                                                     │
│ What does the system do with that data?                             │
│                                                                     │
│ - List every API endpoint or entry point (REST, GraphQL, CLI, UI)   │
│ - Classify each as: read-only, single-table write, multi-table      │
│   write, or side-effect (email, S3, queue publish)                  │
│ - For writes: what is the mutation contract? (request shape,        │
│   required fields, audit logging, validation rules)                 │
│ - Identify business logic that lives outside the database           │
│   (computation, orchestration, transformation)                      │
│ - Count: how many generic CRUD endpoints vs. custom logic           │
│   endpoints?                                                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHERE (Network)                                                     │
│                                                                     │
│ What services does the system connect to and run on?                │
│                                                                     │
│ - List every runtime service (databases, caches, queues, APIs,      │
│   external SaaS)                                                    │
│ - For each: protocol, port, auth mechanism, network zone            │
│   (public/private/VPN)                                              │
│ - Map the deployment topology (containers, VMs, serverless,         │
│   CDN)                                                              │
│ - Identify secrets and how they are managed (env vars, vault,       │
│   config files)                                                     │
│ - Note any service that must be co-located (localhost-only          │
│   communication) vs. network-accessible                             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHO (People)                                                        │
│                                                                     │
│ Who uses the system and with what permissions?                      │
│                                                                     │
│ - List every user role or group                                     │
│ - For each: what can they see, what can they do, how are they       │
│   identified (SSO, API key, header, token)                          │
│ - Where is authorization enforced? (server-side, client-side,       │
│   proxy, database)                                                  │
│ - Who operates the system? (same team as users? dedicated ops?      │
│   no ops — self-service?)                                           │
│ - Who maintains the code? (human developers, AI agents, both,       │
│   contractor rotation)                                              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHEN (Timing)                                                       │
│                                                                     │
│ What are the system's timing dependencies and behaviors?            │
│                                                                     │
│ - Scheduled jobs (cron, queue workers, periodic tasks)              │
│ - Cache TTLs and invalidation strategies                            │
│ - Polling intervals (background fetches, health checks)             │
│ - Event-driven refresh patterns (pub/sub, webhooks, reactive)       │
│ - SLAs or latency expectations (page load, API response,            │
│   job completion)                                                   │
│ - Data freshness requirements (real-time, near-real-time,           │
│   eventual)                                                         │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ WHY (Motivation)                                                    │
│                                                                     │
│ What drives changes to this system?                                 │
│                                                                     │
│ - CI/CD pipeline structure (branch strategy, deploy triggers,       │
│   environments)                                                     │
│ - Release cadence (continuous, weekly, manual, tagged)              │
│ - Rollback mechanism (blue-green, feature flags, config switch,     │
│   revert commit)                                                    │
│ - Current pain points that motivate this work                       │
│ - Stakeholder constraints (compliance, performance, deadline,       │
│   team skill)                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Output format

Produce a single document titled `ZACHMAN_FACTS.md` with six sections matching the columns above. Each section should be 10–30 bullet points of concrete, cited facts.

---

## Phase 2: Facet Library Construction

A **facet** is a named architectural concern that governs decisions across the project. Facets are not features — they are lenses through which features are evaluated.

### Standard Facet Catalog

Below are 9 standard facets. Not every project needs all 9. The LLM should **select 4–6 facets** that are most relevant to the user's prompt and the Zachman facts, then customize each one for the specific project.

#### Facet definitions

```
┌──────────────────────────────────────────────────────────────────┐
│ SIMPLICITY                                                       │
│                                                                  │
│ The system should have the fewest moving parts necessary to      │
│ deliver the required capability.                                 │
│                                                                  │
│ Zachman alignment: How (Process), What (Data)                    │
│                                                                  │
│ When to select: Always. Every project benefits from this facet.  │
│                                                                  │
│ Typical measures:                                                │
│ - Runtime service count                                          │
│ - State management layers                                        │
│ - Config/boilerplate lines to add a new capability               │
│ - Build step count                                               │
│ - Dependency count                                               │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Wrapper abstractions that add indirection without value        │
│ - "Smart" components mixing data fetching + logic + rendering    │
│ - Premature abstraction for hypothetical future requirements     │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ OPERABILITY                                                      │
│                                                                  │
│ The system must be deployable, observable, and recoverable by    │
│ the team that actually operates it.                              │
│                                                                  │
│ Zachman alignment: Where (Network), When (Timing),               │
│                    Why (Motivation)                              │
│                                                                  │
│ When to select: Always. Every system must be operated.           │
│                                                                  │
│ Typical measures:                                                │
│ - Time from commit to running in target environment              │
│ - Number of environment variables / secrets required             │
│ - Health check coverage (can you tell if it's working?)          │
│ - Rollback time and procedure complexity                         │
│ - Log discoverability (structured? aggregated? searchable?)      │
│ - Distributed tracing across inter-service calls                 │
│ - Metric emission for new endpoints (latency, error rate)        │
│ - Alert coverage for new dependencies                            │
│ - Observability seams derived from SCOUT dimensions              │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Client-only error handling with no server-side visibility      │
│ - Build processes requiring exotic toolchain versions            │
│ - Secrets that differ between build-time and runtime             │
│ - "Works on my machine" configurations                           │
│ - Observability added "later" as a follow-up ticket              │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ DEVELOPER EXPERIENCE (AGENTIC CODING)                            │
│                                                                  │
│ The codebase must maximize the probability that an AI coding     │
│ agent produces correct code on the first attempt.                │
│                                                                  │
│ Zachman alignment: How (Process), What (Data)                    │
│                                                                  │
│ When to select: When AI agents (Claude Code, Copilot, Cursor,    │
│ etc.) will write or maintain a significant portion of the code.  │
│                                                                  │
│ Typical measures:                                                │
│ - Max file size (target: <400 lines; a scenario-indexed BDD      │
│   test-harness glob may instead be governed per function)        │
│ - Type coverage (target: 100% strict)                            │
│ - Pattern consistency (every instance of X follows the same      │
│   structure)                                                     │
│ - Files an agent must read to add a new capability (target: <5)  │
│ - Naming convention consistency (one pattern, no exceptions)     │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Metaprogramming that hides the call graph                      │
│ - Implicit conventions documented only in READMEs                │
│ - Files serving multiple purposes                                │
│ - Shared mutable state outside managed stores                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ DATA INTEGRITY                                                   │
│                                                                  │
│ Every mutation must be auditable, consistent with system         │
│ contracts, and recoverable from partial failure.                 │
│                                                                  │
│ Zachman alignment: What (Data), When (Timing), Who (People)      │
│                                                                  │
│ When to select: When the system performs writes that touch       │
│ multiple entities, require audit trails, or have compliance      │
│ requirements. Also select when migrating write paths.            │
│                                                                  │
│ Typical measures:                                                │
│ - Mutation audit coverage (% of writes with audit log entry)     │
│ - Multi-table write sequencing (documented step order)           │
│ - Partial failure handling (retry? rollback? accept?)            │
│ - Cache-to-source consistency (stale reads after mutation?)      │
│ - Optimistic vs. pessimistic classification per mutation type    │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Fire-and-forget multi-step mutations                           │
│ - Client-side computed fields submitted to the API               │
│ - Missing cache invalidation after writes                        │
│ - Destructive operations without confirmation                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ SECURITY POSTURE                                                 │
│                                                                  │
│ Changes must not introduce new attack surface. Authentication    │
│ and authorization remain where they are enforced today.          │
│                                                                  │
│ Zachman alignment: Who (People), Where (Network)                 │
│                                                                  │
│ When to select: When the change touches auth flows, user input   │
│ handling, network boundaries, or introduces new client-side      │
│ code that interacts with sensitive data.                         │
│                                                                  │
│ Typical measures:                                                │
│ - Secrets exposure (none in client-side code)                    │
│ - Input sanitization (framework defaults, no raw HTML)           │
│ - Auth enforcement point (server, not client)                    │
│ - Third-party dependency surface (CDN, npm, external scripts)    │
│ - CSP / CORS configuration                                       │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Client-side role checks without server enforcement             │
│ - eval(), dangerouslySetInnerHTML, dynamic script injection      │
│ - Secrets in environment variables exposed to the browser        │
│ - Auth tokens in localStorage                                    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ REPLACEABILITY                                                   │
│                                                                  │
│ Any layer should be replaceable without rewriting adjacent       │
│ layers. Components communicate through contracts, not shared     │
│ internals.                                                       │
│                                                                  │
│ Zachman alignment: What (Data), How (Process), Where (Network)   │
│                                                                  │
│ When to select: When the project uses third-party libraries      │
│ that may be swapped (UI framework, ORM, cloud provider), or      │
│ when building a system intended to outlive its current tech      │
│ stack.                                                           │
│                                                                  │
│ Typical measures:                                                │
│ - Files changed to swap a library (target: <10)                  │
│ - API contract defined by types, not shared code                 │
│ - No cross-layer imports (frontend does not import backend)      │
│ - Vendored vs. linked dependencies                               │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Route structure tightly coupled to API paths                   │
│ - CSS-in-JS locking styles to a runtime                          │
│ - ORM-like client layers mirroring the server schema             │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ PERFORMANCE EFFICIENCY                                           │
│                                                                  │
│ The system must meet its latency and throughput targets without  │
│ over-provisioning resources.                                     │
│                                                                  │
│ Zachman alignment: When (Timing), Where (Network),               │
│                    What (Data)                                   │
│                                                                  │
│ When to select: When the change affects response time, data      │
│ volume, rendering speed, or resource consumption. Also select    │
│ when the prompt involves optimization, scaling, or load.         │
│                                                                  │
│ Typical measures:                                                │
│ - p95 response time for critical paths                           │
│ - Bundle size / time to interactive                              │
│ - Query count per page load (N+1 detection)                      │
│ - Memory footprint under load                                    │
│ - Virtualization for large datasets                              │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Fetching all rows when pagination exists                       │
│ - Re-rendering entire trees on single-field changes              │
│ - Synchronous blocking calls in hot paths                        │
│ - Missing indexes on frequently queried columns                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ TESTABILITY                                                      │
│                                                                  │
│ Every behavior the system claims to have must be verifiable      │
│ by an automated test that runs in CI.                            │
│                                                                  │
│ Zachman alignment: How (Process), Why (Motivation)               │
│                                                                  │
│ When to select: When the project has existing tests that must    │
│ be preserved, when the change introduces new behaviors that      │
│ need regression coverage, or when the prompt explicitly          │
│ mentions testing, QA, or reliability.                            │
│                                                                  │
│ Typical measures:                                                │
│ - Test pyramid balance (unit > integration > E2E)                │
│ - Test co-location (tests adjacent to source)                    │
│ - CI test execution time                                         │
│ - Mocking strategy (real dependencies vs. fakes vs. mocks)       │
│ - Flakiness rate                                                 │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Tests that depend on external service availability             │
│ - Test data shared across test files (coupling)                  │
│ - Snapshot tests as a substitute for behavioral assertions       │
│ - Tests that pass locally but fail in CI                         │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ BACKWARDS COMPATIBILITY                                          │
│                                                                  │
│ Public surfaces (APIs, events, schemas, configuration contracts) │
│ must remain backwards-compatible for their documented guarantee  │
│ period. Breaking changes require deprecation, migration path,    │
│ and compatibility tests.                                         │
│                                                                  │
│ Zachman alignment: How (Process), What (Data), When (Timing)     │
│                                                                  │
│ When to select: When the project has consumers (other services,  │
│ external clients, public APIs), when changes touch shared        │
│ contracts or integration points, or when the prompt involves     │
│ API versioning, deprecation, or migration.                       │
│                                                                  │
│ Often elevated to *triggered mandatory* (see below).             │
│                                                                  │
│ Typical measures:                                                │
│ - Public surface registry exists and is current                  │
│ - All public surfaces have defined stability and guarantee       │
│   period                                                         │
│ - Breaking changes have deprecation plan with sunset date        │
│ - Golden-file tests for stable API response shapes               │
│ - Consumer-driven contract tests for inter-service dependencies  │
│ - Versioned integration tests (old clients vs. new service)      │
│ - Deprecation signals at runtime (headers, logs, metrics)        │
│                                                                  │
│ Typical anti-patterns:                                           │
│ - Removing response fields without checking consumers            │
│ - Renaming endpoints without API versioning                      │
│ - Changing payload semantics without version bump                │
│ - Adding required fields to existing request contracts           │
│ - "We'll fix consumers later" without tracked deprecation        │
│ - Updating golden files without reviewing the diff               │
└──────────────────────────────────────────────────────────────────┘
```

### Triggered Mandatory Facets

Some facets are not always-on, but become **mandatory whenever a specific condition is met**. The org config or project facet library declares these explicitly. They sit alongside the always-on mandatory facets when active, and are skipped (with an explicit "N/A" note) when their trigger does not fire.

**The canonical triggered mandatory facet is Backwards Compatibility:**

- **Trigger:** the change touches a public surface registered in the project's surface registry, or introduces a new public surface (API endpoint, event schema, DTO contract, configuration key, library export).
- **When triggered:** include Backwards Compatibility with all measures from the standard facet definition, customized to the project. Add a "Compatibility Impact" section to the iteration spec classifying the change (additive / modification / removal) and naming the affected surfaces.
- **When not triggered:** mark "Backwards Compatibility — N/A (no registered surfaces affected, no new public surfaces introduced)."

When in doubt, include it — the cost of an "N/A" evaluation is low; the cost of a missed breaking change is high.

Orgs may define additional triggered mandatory facets (e.g., a Privacy facet triggered whenever PII fields are added; a Performance facet triggered whenever a new endpoint is added to a latency-sensitive path).

### Facet selection rules

The LLM should select facets based on these criteria:

1. **Always include** Simplicity and Operability. They apply to every project.
2. **Include Data Integrity** if the prompt involves writes, migrations, refactors that touch mutation paths, or compliance.
3. **Include DX (Agentic)** if AI agents will implement or maintain the code.
4. **Include Security Posture** if the change touches auth, user input, network boundaries, or introduces client-side code.
5. **Include Performance** if the prompt mentions speed, scale, optimization, or the Zachman facts reveal large datasets or latency-sensitive paths.
6. **Include Testability** if the project has an existing test suite that must be preserved, or the prompt mentions reliability.
7. **Include Replaceability** if the prompt involves a migration, a library swap, or building a system expected to outlive its current stack.
8. **Evaluate each declared triggered mandatory facet's trigger** on every project — include Backwards Compatibility when the change touches registered or new public surfaces, and any additional triggered mandatory facet the org declares (per the "Triggered Mandatory Facets" section above) when its own trigger fires.
9. **Never include more than 6 facets** (not counting triggered mandatory facets that activate). If more seem relevant, merge the least critical into an adjacent facet (e.g., merge Testability into Operability if testing is primarily a CI concern).

### Customization instructions

For each selected facet, the LLM must:

1. **Keep the definition** as-is or tighten it to the project's context.
2. **Replace "typical measures" with project-specific measures.** Use concrete numbers from the Zachman facts. Example: replace "Runtime service count" with "Runtime service count (currently 3: Flask on 5000, ct-tools on 5500, Shiny on 3838; target: 2)".
3. **Replace "typical anti-patterns" with project-specific anti-patterns.** Reference actual code or architecture. Example: replace "Wrapper abstractions" with "A service layer between React Query hooks and the Flask API fetch calls — the API client is already thin enough".
4. **Write a decision rule** specific to this project. This is the tiebreaker when two valid approaches exist. It should be one sentence.

### Precedence matrix

After selecting and customizing facets, the LLM must produce a **precedence list** — an ordered ranking of facets from highest to lowest priority. This resolves conflicts when two facets disagree.

**Default precedence** (override per project if justified):

```
1. Data Integrity              — never compromise correctness for convenience
2. Security Posture            — never introduce new attack surface
3. Backwards Compatibility     — public contracts are promises to consumers
                                 (when triggered; collapses out otherwise)
4. Simplicity                  — fewer parts over cleverer parts
5. Operability                 — the team must be able to deploy and debug
6. DX (Agentic)                — optimize for agents, not at the cost of correctness
7. Performance                 — fast enough, not fastest possible
8. Testability                 — tested enough, not 100% coverage for its own sake
9. Replaceability              — nice to have, don't over-abstract
```

When Backwards Compatibility is not triggered, the effective precedence collapses to positions 1–2 and 4–9.

### Output format

Produce a single document titled `FACET_LIBRARY.md` with:
- One section per selected facet (definition, Zachman alignment, measures, anti-patterns, decision rule)
- A section identifying any *triggered mandatory facets* and their activation rules
- A "Facet Interaction Matrix" section at the end with the precedence list

---

## Phase 3: SCOUT Decomposition

While Phases 1 and 2 ground the system and pick the governing concerns, **SCOUT** is where each acceptance criterion becomes a testable behavioral contract. SCOUT decomposes every AC into five dimensions; each dimension maps directly to Gherkin scenarios and runtime observability seams.

### The Five Dimensions

| Dimension | What It Captures | Becomes in the Test |
|---|---|---|
| **State** | System state that must be true before the behavior executes | `Given` — test setup |
| **Constraints** | Business invariants that govern the behavior | `Then` — the contract being verified |
| **Outputs** | Observable outputs: external calls, notifications, events | `Then` — verify external interactions |
| **Updates** | State changes to entities or persistent storage | `Then` — verify state changes |
| **Triggers** | Data, parameters, or events that trigger the behavior | `When` — the action under test |

For each AC in the problem statement, fill all five cells. Be specific — each cell should reference concrete entities, services, or API endpoints from the Zachman facts.

### The Edge Case Engine

For each dimension, ask "what if this is violated?":

| Dimension | Violation | Produces |
|---|---|---|
| State | Entity missing? Wrong state? Expired? | Not-found errors, state validation failures |
| Constraints | Invariant broken? Constraint exceeded? | Business rule violation scenarios |
| Outputs | External service fails? Timeout? | Resilience and error handling scenarios |
| Updates | Concurrent modification? | Optimistic concurrency conflict scenarios |
| Triggers | Null? Empty? Wrong type? Unauthorized? | Validation errors, auth failures |

This is mechanical, not creative. Five dimensions, each with a finite set of violation types. The result is edge case coverage that does not depend on individual experience or time pressure.

### SCOUT-to-Gherkin

Each SCOUT decomposition produces Gherkin scenarios directly:

```gherkin
# Happy path: State → Given, Triggers → When, Updates + Outputs → Then
Scenario: S-1.1 -- Primary success path
  Given {state from SCOUT}
  When {trigger from SCOUT}
  Then {update from SCOUT}
  And {output from SCOUT}

# Edge case: what if precondition is violated?
Scenario: S-1.2 -- Entity not found
  Given {precondition violation}
  When {same input}
  Then {error response with specific message}
```

The scenarios are **framework-agnostic**. The implementer agent discovers the project's test framework, assertion library, and conventions at implementation time (see Phase 4 — Test Infrastructure Discovery).

### Observability Seams

SCOUT dimensions extend into production monitoring through **observability seams**: structured log events emitted at dimension boundaries that make divergence detectable at runtime. AI-generated code may pass all tests yet contain subtle logic errors that only manifest under production data distributions. Tests verify behavior against known scenarios; seams detect unknown scenarios by asserting SCOUT invariants continuously in production.

Each SCOUT dimension derives a specific seam type. This derivation is mechanical — if you have a SCOUT decomposition, you can derive the seams without creative judgment.

| SCOUT Dimension | Seam Type | What It Detects |
|---|---|---|
| **State** | `IMPOSSIBLE_STATE` | A behavior executed when its preconditions were false |
| **Constraints** | `DECISION_DRIFT` | Business rule branch distribution deviates from baseline |
| **Outputs** | `LINEAGE_GAP` | Expected external call or checkpoint was skipped |
| **Updates** | `LINEAGE_GAP` | State change did not produce expected audit record |
| **Triggers** | `SEAM_VIOLATION` | Post-validation invariant violated after transformation |

**Derivation prompts:**

- *State → IMPOSSIBLE_STATE:* "If this precondition were false at runtime despite validation, what state would I observe?"
- *Constraints → DECISION_DRIFT:* "What is the expected distribution of this decision under normal traffic? What deviation would indicate a problem?"
- *Outputs → LINEAGE_GAP:* "If this external call silently failed (no error, no execution), would anything detect it?"
- *Updates → LINEAGE_GAP:* "If this state change happened but the audit record was not written, would anything detect it?"
- *Triggers → SEAM_VIOLATION:* "After this input is transformed/mapped/converted, could the result violate the original validation constraint?"

Not every AC requires all seam types. Derive only what the SCOUT decomposition supports:
- No branching rule → no DECISION_DRIFT seam
- No external output → no LINEAGE_GAP for outputs
- No audit-required update → no LINEAGE_GAP for updates

### Output format

Produce, for each acceptance criterion in the problem statement:

1. A **SCOUT decomposition table** (five rows, one per dimension).
2. An **edge case list** derived mechanically from the decomposition.
3. A **seam specification table** listing each derived seam (dimension, type, event name, trigger condition, severity).

These outputs are embedded directly into the iteration spec(s) in Phase 4. They are also the source from which the test plan's Gherkin scenarios are generated.

---

## Phase 4: Iteration Spec Generation

The LLM combines the user's prompt, the Zachman facts, the facet library, and the SCOUT decompositions to produce one or more iteration specs.

### How many iterations?

The LLM must determine the correct number of iterations (1–3) using this decision tree:

```
Is every mutation in scope the same complexity class?
  YES → 1 iteration
  NO  → Does the higher-complexity class require a NEW governing
        facet not needed by the lower class?
    YES → 2 iterations (split at the complexity boundary)
    NO  → 1 iteration (same facets govern both; split would duplicate
          patterns without adding architectural value)

Does any remaining work require a THIRD new facet?
  YES → 3 iterations
  NO  → Stop at the current count
```

**Complexity classes** (from lowest to highest):
1. Read-only views
2. Single-table CRUD
3. Multi-table writes with sequencing
4. Cross-service orchestration (API + external service + queue/event)

**The test for splitting:** A new iteration is justified only if it introduces a governing facet that **materially changes the architecture** — meaning it adds patterns, constraints, or verification steps that would not exist otherwise. If the new work simply uses more of the same patterns, it belongs in the current iteration.

### Iteration spec structure

Each iteration spec must follow this structure. Sections marked [required] must always be present. Sections marked [if applicable] are included only when the Zachman facts or governing facets support them.

```markdown
# Iteration N: {Title}

**Governing facets:** {List the facets that shape this iteration}

**Why these facets:** {1-2 sentences explaining why this combination,
and if Iteration N>1, what new facet was added and why}

---

## 1. Scope [required]

### 1.1 What is being built
{Bullet list of deliverables}

### 1.2 What is NOT being built
{Explicit exclusions — prevents scope creep}

### 1.3 Success criteria
{Table: Criterion | Measure — each must be objectively verifiable}

---

## 2. Zachman Alignment [required]

For each Zachman column relevant to this iteration, state:
- What changes from the current state (from ZACHMAN_FACTS.md)
- What stays the same
- What new constraints the governing facets impose

### 2.1 What (Data) changes
### 2.2 How (Process) changes
### 2.3 Where (Network) changes
### 2.4 Who (People) changes
### 2.5 When (Timing) changes
### 2.6 Why (Motivation) for this iteration

---

## 3. SCOUT Decomposition [required]

For each AC in scope, include the five-dimension table from Phase 3.
Cross-reference each row to a concrete entity, service, or endpoint.

---

## 4. Observability Seams [if applicable — required when
                          SCOUT decomposition produces any seam]

The seam specification table from Phase 3, filtered to this iteration's ACs.
Each row will become a runtime assertion and a verification test.

---

## 5. Patterns [if applicable — required when Data Integrity is
                a governing facet]

Define reusable patterns that all work in this iteration must follow.
Examples:
- Mutation classification (single-table, multi-table, guarded,
  destructive)
- Cache invalidation rules (which keys to invalidate per mutation)
- Failure handling (retry, rollback, accept partial state)
- Optimistic vs. pessimistic update rules

---

## 6. Component / Module Specifications [required]

For each deliverable in §1.1, provide:
- Inputs (data sources, API endpoints, user actions)
- Outputs (what the user sees, what gets written)
- Constraints from governing facets
- Enough detail for an agent to implement without ambiguity

---

## 7. Compatibility Impact [if applicable — required when
                            Backwards Compatibility is triggered]

For each affected surface, classify as additive / modification / removal
and link to deprecation plan if applicable.

---

## 8. Verification Plan [required]

### 8.1 Test Infrastructure Discovery
{Blank fields the implementer fills after scanning existing test
projects: test framework, assertion library, mocking library,
setup patterns, integration test infrastructure, naming conventions.
New BDD-style tests use discovered conventions; existing tests are
never refactored.}

### 8.2 Automated tests
{What to test, what tool, what scope — derived from SCOUT decomposition}

### 8.3 Manual verification
{Steps a human performs post-deploy}

### 8.4 Rollback procedure
{How to undo this iteration if it fails in production}

---

## 9. Agent Execution Instructions [if applicable — required when
                                    DX (Agentic) is a governing facet]

### Task sequence
{Numbered list of tasks with dependencies, ordered for TDD progression}

### Parallelization opportunities
{Which tasks can run concurrently}

### Human review gates
{Which tasks require human sign-off before proceeding}
```

---

## Phase 5: Comparison Document (Multi-Iteration Only)

If more than one iteration was generated, the LLM must produce a comparison document for architectural review. This document explains **why the work is split the way it is** and **what changes between iterations**.

### Required sections

```markdown
# Iteration Comparison

## 1. Fundamental Differences
{The single axis that divides the iterations — usually mutation
complexity class or governing facet addition}

## 2. Zachman Column-by-Column Comparison
{Table per column: Aspect | Iteration 1 | Iteration 2 | ... }

## 3. Component Reuse Matrix
{Which components are created vs. reused vs. extended per iteration}

## 4. Risk Profile Comparison
{What risk each iteration primarily mitigates}

## 5. Decision Log
{Why this number of iterations, not more or fewer}

## 6. Facet Compliance Checklists
{Per-iteration checklist derived from governing facets}
```

---

## Prompt Integration Guide

This section explains how the LLM should interpret different types of user prompts and map them to the workflow above.

### Prompt type → Facet selection hints

| Prompt type | Example | Likely facets |
|-------------|---------|---------------|
| **Add a feature** | "Add user notifications" | Simplicity, Operability, Data Integrity (if writes), Security (if user-facing) |
| **Fix tech debt** | "Reduce coupling in the API layer" | Simplicity, Replaceability, DX (Agentic) |
| **Refactor for modularity** | "Break the monolith into services" | Simplicity, Operability, Replaceability, Testability |
| **Migrate technology** | "Move from Angular to React" | Simplicity, Operability, DX (Agentic), Data Integrity (if write paths change) |
| **Improve performance** | "Page load is too slow" | Performance, Simplicity, Operability |
| **Security hardening** | "Prepare for SOC 2 audit" | Security Posture, Data Integrity, Operability, Testability |
| **Onboard AI agents** | "Set up the repo for Claude Code" | DX (Agentic), Simplicity, Testability |
| **Scale the system** | "Support 10x current load" | Performance, Operability, Replaceability |

### Prompt parsing rules

1. **Extract the verb.** Add, fix, refactor, migrate, improve, harden, onboard, scale — each maps to a different facet emphasis.
2. **Extract the scope.** One module? Entire system? A specific file? This determines whether exploration is needed and how many iterations to generate.
3. **Extract constraints.** Timeline, team size, technology mandates, compliance requirements — these may override default facet precedence.
4. **If the prompt is vague**, ask the user to clarify scope and constraints before proceeding to Phase 1. Do not guess.

### LLM workflow summary

```
User prompt
  │
  ▼
Phase 1: Explore codebase → produce ZACHMAN_FACTS.md
  │
  ▼
Phase 2: Select 4–6 facets + evaluate triggered mandatory → customize → produce FACET_LIBRARY.md
  │
  ▼
Phase 3: Decompose each AC into SCOUT dimensions → derive observability seams
  │
  ▼
Phase 4: Determine iteration count → write specs → produce ITERATION_N_SPEC.md
  │
  ▼
Phase 5 (if multi-iteration): Produce SPEC_COMPARISON.md
  │
  ▼
Present to user for review
```

---

## Appendix: Facet Library Quality Checklist

Before presenting the facet library to the user, the LLM should verify:

- [ ] Every measure references a concrete number or target, not a vague aspiration
- [ ] Every anti-pattern references a specific code pattern or architecture decision, not a generic warning
- [ ] Every decision rule is one sentence and resolves a specific type of tiebreak
- [ ] The precedence matrix has a clear justification for any deviation from the default order
- [ ] No facet duplicates another (e.g., "Maintainability" is not a separate facet — it is the combination of Simplicity + DX)
- [ ] Selected facets cover all Zachman columns relevant to the user's prompt (if the prompt affects Who, at least one facet aligns to Who)
- [ ] Triggered mandatory facets have their activation rules explicitly stated
- [ ] The library contains 4–6 facets (not counting triggered mandatory facets that activate)
