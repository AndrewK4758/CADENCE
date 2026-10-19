# SDLC Framework Repository (`~/projects/sdlc`)

Single-source-of-truth repository for **CLAIRE** agents, skills, lifecycle hooks, and SDLC governance processes adapted for **Google Antigravity (Gemini 4 Argon & Gemini 3.8 Flash)** + **Local Hardware Coprocessor Offload** (Ryzen 9 9955HX3D 3D V-Cache + RTX 5070 Ti).

## Directory Structure

- `agents/` — The 9 governed CLAIRE subagents (`agent.md` format):
  - **Deep Reasoning & Code Authoring (`model: pro` -> Gemini 4 Argon High)**:
    - `claire-architect`
    - `claire-explorer`
    - `claire-spec-author`
    - `claire-implementer`
    - `claire-reviewer`
    - `claire-maintainer`
    - `claire-migration-author`
  - **High-Breadth / Mechanical (`model: flash` -> Gemini 3.8 Flash High)**:
    - `claire-triage-agent`
    - `claire-archivist`
- `skills/` — All 19 CLAIRE workflow skills (`claire-prep`, `claire-cycle`, `claire-triage`, `claire-elicit`, `claire-spec`, `claire-implement`, `claire-review`, `claire-maintain`, `claire-migrate`, `claire-archive`, `claire-parallel`, `claire-mint`, `claire-sync-jira`, `claire-sync-youtrack`, `claire-adopt`, `claire-upgrade`, `claire-interview`, `claire-bump-model`, `claire-release`).
- `hooks/` — Request/response lifecycle hooks (`tms-sync-reminder.sh`, `tms-doc-sync-stop.sh`, `hooks.json`) compatible with both Antigravity and Claude Code.
- `processes/` — Generic, project-agnostic CLAIRE templates, policies, guides, and CI gate scripts (`CLAIRE_DIRECTIVES.md`, `specs/TEMPLATE/`, `docs/agentic-sdlc/`, `docs/policies/`, `docs/guides/`, `ci-templates/scripts/`).
- `import/` — One-command linking (`link-sdlc.sh`, `agents.json`, `skills.json`) so updates in `~/projects/sdlc` take effect across every linked repository automatically.

## Importing into a Repository (or Globally)

```bash
# Link into a specific project repository (.agents/):
~/projects/sdlc/import/link-sdlc.sh /path/to/repo

# Or enable all 9 CLAIRE agents & 19 skills globally in ~/.gemini/config/:
~/projects/sdlc/import/link-sdlc.sh --global
```
