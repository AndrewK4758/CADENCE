# CADENCE Agentic SDLC (`~/projects/sdlc`)

**CADENCE** (*Contextual Architecture, Decomposition, Execution, Navigation, Consolidation & Enshrinement*) is a vendor-neutral, hardware-tiered agentic software development lifecycle framework. Every letter of **CADENCE** maps directly to a governed phase of the engineering workflow:

1. **C — Classify**: Issue intake, 4-part problem framing (`VERB`, `SCOPE`, `WHY`, `CONSTRAINTS`), objective change-tier sizing (`Trivial`, `Low`, `Medium`, `High`), automatic local semantic duplicate/codebase discovery, and intent elicitation (`cadence-triage-agent`, `/cadence-triage`, `/cadence-elicit`, `/cadence-mint`).
2. **A — Architect & Explore**: Cross-boundary implicit contract discovery and 2–3 structurally distinct, unranked steelmanned design options (`cadence-architect`, `cadence-explorer`, `/cadence-prep`).
3. **D — Decompose & Specify**: Grounding via the **Contextual Grounding Matrix (`6W×4L`)**, evaluation against **Engineering Pillars**, and **CHORD** 5-part behavioral decomposition (**C**onditions [`Given`], **H**andling/Triggers [`When`], **O**utcomes [`Then` external], **R**ules [`Then` invariants], **D**eltas [`Then` internal mutations]) into `spec.md` and Gherkin `test-plan.md`, gated by `[Human Gate: Spec Approval]` (`cadence-spec-author`, `/cadence-spec`, `/cadence-interview`).
4. **E — Execute via TDD**: Strict BDD Red $\rightarrow$ Green $\rightarrow$ Accumulate $\rightarrow$ Commit cycles and expand/contract schema migrations (`cadence-implementer`, `cadence-migration-author`, `/cadence-implement`, `/cadence-migrate`, `/cadence-cycle`, `/cadence-parallel`).
5. **N — Navigate Gates**: Automatic local coprocessor pre-scans followed by `[Human Gate: Code Review]` and `[Human Gate: Maintainer Acceptance]` (`cadence-reviewer`, `cadence-maintainer`, `/cadence-review`, `/cadence-maintain`).
6. **C — Consolidate**: Merge and same-session bi-directional tracker projection to YouTrack or Jira (`/cadence-sync-youtrack`, `/cadence-sync-jira`).
7. **E — Enshrine**: Relocation to `archive/{ticket-id}/`, two-pass dead-citation sweeps, ADR and intent-insight promotion, living business flow updates (`docs/flows/`), and release cutting (`cadence-archivist`, `/cadence-archive`, `/cadence-release`).

---

## Universal `.agents/` Primary Architecture & `.gemini/` Reference Implementation

Per [`processes/docs/policies/cli-runtime-adoption-policy.md`](file:///home/ak/projects/sdlc/processes/docs/policies/cli-runtime-adoption-policy.md):
- **`.agents/` is the Universal Primary Source of Truth** across all CLI tools (`.agents/agents/`, `.agents/skills/`, `.agents/hooks/`, `.agents/agents.json`, `.agents/skills.json`, and `AGENTS.md`).
- **`.gemini/` is the Canonical Reference Implementation** for Google Antigravity (`agy`) and Gemini CLI, projected directly off `.agents/`.
- Other CLI runtimes (`.claude/`, `.opencode/`) project their directories off `.agents/` following the `.gemini/` reference adapter (`import/link-sdlc.sh <repo> --claude`).

---

## Automatic 2-Tier Local Hardware Coprocessor Offload

Every CADENCE agent and skill has automatic local model offloading woven directly into its procedural steps (plus `hooks/local-offload-enforcer.sh`):
- **Tier 1 — Zero-VRAM Always-On CPU (`127.0.0.1:9379`, Ryzen 9 9955HX3D 128MB 3D V-Cache, 0 MB GPU VRAM)**:
  - `local-fast-cpu` (`gemma-4-e2b`): Automatic compaction of test, build, compiler, migration, and gate logs via `offload_log_triage` (saving full numbered raw output to `/tmp/agy-last-triage.log`).
  - `local-embed-cpu` (`nomic-embed-text`): Automatic zero-VRAM semantic ranking across `specs/`, `archive/`, `production-insights.md`, `intent-insights.md`, `docs/ADR/`, and `docs/flows/` via `local_semantic_embed`.
- **Tier 2 — On-Demand Hybrid/GPU (`127.0.0.1:9380`, RTX 5070 Ti 12GB VRAM, 300s idle auto-unload)**:
  - `local-moe-hybrid` (`gemma-4-26b-a4b` MoE): Cross-boundary scouting via `repo-scout` and mechanical pre-review sweeps (`<400`-line ceiling, comment discipline, CHORD seams: `UNSOUND_CONDITION`, `RULE_DIVERGENCE`, `BOUNDARY_FAULT`, `DELTA_AUDIT_GAP`) via `offload_deep_review`.
  - `local-12b-gpu` (`gemma-4-12b`): Dense GPU diff pre-review when requested.
