# `/cadence-sync-youtrack` — script contracts: the project-key resolver

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176, BTG-179).
External invariant relied upon: identical to `.agents/skills/cadence-sync-youtrack/youtrack-scripts.md` — the git repository (`metadata.yaml` + `problem.md`) is the sole source of truth; YouTrack is the downstream projection layer, and every script communicates strictly across three channels (stdout `key=value`, stderr `syncyt.*`, exit code).

**This document is a modular segment of the single script-contract index, split rather than truncated.** BTG-179 (`archive/BTG-179/decisions.md` DEC-019) factored `yt-projectkey-lib.sh` into its own file and companion index segment so both `youtrack-scripts.md` and `yt-lib.sh` remain comfortably below the `<400`-line Developer Experience ceiling, matching the modular index structure in `cadence-sync-jira`. Its single responsibility is answering: **"which YouTrack project key governs this ticket or prefix?"**

`btg-176-rest-foundation.test.sh`'s E-8 contract reader merges all `youtrack-scripts-*.md` files into `youtrack-scripts.md` prior to each check, guaranteeing that splitting the index never masks an undocumented script.

---

### yt-projectkey-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, project-key and agent-user resolver — **sourced** by `yt-lib.sh` (BTG-179) |
| **What it does** | Defines `yt_project_key <ticket-id>` and `yt_project_key --prefix <PREFIX>` — the single authoritative project-key resolver for the YouTrack adapter. Resolution order: **(1)** the ticket prefix's row in `CADENCE_ORG.md` §9, parsed via `ci-templates/scripts/org-binding-resolve.sh` (the sole parser for §9's table grammar); **(2)** §9's scalar `**Project key(s):**` declaration; **(3)** the fallback environment variable named in `youtrack-server-config.json`'s `env` block — **DEPRECATED** and scheduled for removal after **one release cycle** per `docs/policies/deprecation-policy.md` (*Configuration keys* row; see `docs/migrations/multi-tracker-binding.md`). When level (1) matches a prefix row whose project key cell is empty, the resolver HALTs immediately without falling through to (2) or (3) — an incomplete §9 row is never silently masked by an environment variable. Supports two invocation signatures because `yt-resolve.sh` has a full `<ticket-id>` whereas `yt-reserve.sh` is allocating a new ID and knows only `--prefix <PREFIX>` |
| **Inputs** | `CADENCE_ORG.md` (`$CADENCE_ORG_FILE`, repo-relative `docs/agentic-sdlc/CADENCE_ORG.md` by default) and the shared binding resolver script (`$CADENCE_ORG_RESOLVER`, `ci-templates/scripts/org-binding-resolve.sh` by default) |
| **Outputs (stdout)** | The resolved YouTrack project shortName on a single line |
| **Exit codes** | `0` when resolved; `4` (`$YT_EXIT_CONFIG`) on any unresolvable, missing, or contradictory binding state. Because `yt_project_key` is invoked inside command substitution (`KEY="$(yt_project_key ...)" || exit "$YT_EXIT_CONFIG"`), it emits the `syncyt.config.*` condition to stderr and returns `4` so the parent script exits cleanly |
| **Conditions** | `syncyt.config.prefix_underivable`, `syncyt.config.project_key_unresolved`, `syncyt.config.resolver_unavailable`, `syncyt.config.project_key_env_ignored` (emitted when §9 takes precedence over a set environment variable so the operator knows which source won), `syncyt.config.project_key_from_env` (the deprecation warning emitted at level (3) only) |
| **Re-run (idempotency)** | Stateless; `CADENCE_ORG.md` is parsed fresh on every invocation so binding updates take effect immediately without stale cache invalidation |

**BTG-315 (additive):** `yt-projectkey-lib.sh` also provides `yt_agent_user <ticket-id>`, the YouTrack counterpart to `cadence-sync-jira`'s `js_agent_user` — reading the optional fifth column (`Agent-time user`) of the ticket prefix's `CADENCE_ORG.md` §9 row. It has no scalar fallback, no environment variable fallback, and **never triggers a config HALT**: any absent or unresolvable state returns an empty string (keeping the run in standard unsplit worklog mode, AC-4). Re-run semantics: stateless, identical to `yt_project_key`.
