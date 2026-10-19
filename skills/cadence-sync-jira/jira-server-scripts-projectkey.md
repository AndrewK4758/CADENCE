# `/cadence-sync-jira` — script contracts: the project-key resolver

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-179).
Boundary invariant: matches its siblings
`.agents/skills/cadence-sync-jira/jira-server-scripts.md` and
`.agents/skills/cadence-sync-jira/jira-server-scripts-type.md` — the repository (`metadata.yaml` +
`problem.md`) is the source of truth; Jira is the projection layer, and every script communicates on
exactly three channels (stdout `key=value`, stderr `syncjs.*`, exit code).

**This file is a further part of one unified index, not another independent index.** It was split off by BTG-179
(`archive/BTG-179/decisions.md` DEC-019, a requester ruling at an implementation gate) when the primary file
stood at **396** lines against an assertion that fails at `>= 400`, and `jira-lib.sh` stood at **397** — so
the project-key resolver could go neither in the library the spec's manifest named nor in the index
that must register it. The record is **split, never truncated**: the same pillar-tension resolution
BTG-105 applied to the umbrella entries and BTG-173 to the issue-type concern (C-3 — Operability
outranks Agentic DX on *content*; DX is served by file placement instead). The seam is the question **"which
project does this ticket's key come from?"**.

`btg-075-script-contract.test.sh`'s `js_index_view` merges every `jira-server-scripts-*.md` into the
primary before each lookup, so a split cannot hide a missing contract entry.

---

### jira-projectkey-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, project-key half — **sourced** by `jira-lib.sh` (BTG-179) |
| **What it does** | `js_project_key <ticket-id>` or `js_project_key --prefix <PREFIX>` — the SINGLE project-key resolver for this adapter. Order: **(1)** the ticket prefix's `CADENCE_ORG.md` §9 per-prefix row, resolved through `ci-templates/scripts/org-binding-resolve.sh`, the sole reader of that grammar; **(2)** §9's scalar `**Project key(s):**` line; **(3)** the environment variable the config's `env` block names — **DEPRECATED**, removed after **one release cycle** per `docs/policies/deprecation-policy.md`'s *Configuration keys* row, with migration instructions in `docs/migrations/multi-tracker-binding.md`. On the (1) path an EMPTY key HALTS and (2)/(3) are UNREACHABLE. **On a per-prefix repository an ABSENT PREFIX likewise HALTS**, and (2)/(3) are UNREACHABLE there too: (1) needs a prefix, a repo-wide `**Project key(s):**` DEFAULT is not an answer to a per-prefix binding so (2) is preempted deliberately, and answering from the environment would write a valid issue to whatever project the operator's shell last exported. Remedy: pass `--prefix PREFIX`, or a ticket id — and since BTG-242 that is the ONLY remedy, because §9's `**Bound tracker(s):**` line is REMOVED and declaring it now yields a repository that halts `tracker.binding.form_removed` (BTG-206, corrected by BTG-242). Two calling forms exist because two call sites know two different things — a write knows the TICKET, whereas a reservation is creating it and knows only the PREFIX the operator selected |
| **Why not in `jira-lib.sh`** | `jira-lib.sh` sits against a 400-line Agentic DX ceiling that `btg-157-hardenings.test.sh` S-7.10 pins at 399 with an explicit must-not-grow assertion (BTG-113 DEC-017). Relocating whole into a sibling library is this adapter's established pattern |
| **Inputs** | `CADENCE_ORG.md` (`$CADENCE_ORG_FILE`) and the shared resolver (`$CADENCE_ORG_RESOLVER`), both repo-relative by default |
| **Outputs (stdout)** | The resolved project key, one line |
| **Exit codes** | `0` resolved; `4` (`$JS_EXIT_CONFIG`) otherwise. It REPORTS and RETURNS rather than halting: called inside `$(...)`, an exit would terminate only the subshell and hand the caller an empty key, so every call site is `KEY="$(js_project_key ...)" || exit "$JS_EXIT_CONFIG"` |
| **Conditions** | `syncjs.config.prefix_underivable`, `syncjs.config.project_key_unresolved`, `syncjs.config.project_key_precondition_unmet` (a per-prefix table is declared and **no prefix was supplied**, so the binding cannot be consulted — exit `4`, nothing created), `syncjs.config.resolver_unavailable`, `syncjs.config.project_key_env_ignored`, `syncjs.config.project_key_from_env` (the deprecation signal, level (3) ONLY) |
| **Re-run (idempotency)** | Stateless; the org file is re-read on every call — a cached binding is a stale binding |

**BTG-315 (additive):** the same file also carries `js_agent_user <ticket-id>`, the §9 per-prefix
row's OPTIONAL fifth cell (`agent_user=` from the resolver's `--tracker` mode). Unlike
`js_project_key`, it has NO scalar fallback and NO deprecated environment variable, and it NEVER
halts: an underivable prefix, an absent resolver, or an unresolved binding all resolve to EMPTY
(unsplit) rather than a config HALT, because split mode is strictly additive (AC-4) — nothing about
resolving the agent-time user may turn an otherwise-working sync into a halt. Re-run: stateless,
same as `js_project_key`.
