# `/claire-sync-youtrack` — script contracts: the project-key resolver

Bounded context: Tracker projection / YouTrack Server adapter (BTG-176, BTG-179).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-youtrack/youtrack-scripts.md` — the repository (`metadata.yaml` + `problem.md`) is
the source of truth; YouTrack is the projection layer, and every script communicates on exactly three
channels (stdout `key=value`, stderr `syncyt.*`, exit code).

**This file is the second part of one index, not a second index.** It was split off by BTG-179
(`archive/BTG-179/decisions.md` DEC-019, a requester ruling at an implementation gate) when the primary
stood at **398** lines against an assertion that fails at `>= 400`, and `yt-lib.sh` at **371** — so the
project-key resolver could go neither in the library the spec's manifest named nor in the index that
must register it. The split mirrors the sibling adapter, which has carried a split index since BTG-105.
The record is **split, never truncated**. The seam is the question **"which project does this ticket's
key come from?"**.

`btg-176-rest-foundation.test.sh`'s E-8 reader merges every `youtrack-scripts-*.md` into the primary
before each lookup, so a split cannot hide a missing contract entry — the same guarantee the sibling
adapter's `js_index_view` gives, extended to this index by BTG-179.

---

### yt-projectkey-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, project-key half — **sourced** by `yt-lib.sh` (BTG-179) |
| **What it does** | `yt_project_key <ticket-id>` or `yt_project_key --prefix <PREFIX>` — the SINGLE project-key resolver for this adapter. Order: **(1)** the ticket prefix's `CLAIRE_ORG.md` §9 per-prefix row, resolved through `ci-templates/scripts/org-binding-resolve.sh`, which is the sole reader of that grammar; **(2)** §9's scalar `**Project key(s):**` line; **(3)** the environment variable the config's `env` block names — **DEPRECATED**, removed after **one release cycle** per `docs/policies/deprecation-policy.md`'s *Configuration keys* row, migration in `docs/migrations/multi-tracker-binding.md`. On the (1) path an EMPTY key HALTS and (2)/(3) are UNREACHABLE: a binding that is present and incomplete is never rescued from the environment. Two calling forms because two call sites know two different things — a resolve knows the TICKET, a reservation is creating it and knows only the PREFIX the operator selected |
| **Inputs** | `CLAIRE_ORG.md` (`$CLAIRE_ORG_FILE`, default repo-relative) and the shared resolver (`$CLAIRE_ORG_RESOLVER`, default repo-relative) |
| **Outputs (stdout)** | The resolved project key, one line |
| **Exit codes** | `0` resolved; `4` (`$YT_EXIT_CONFIG`) on any unresolved or contradictory state. It REPORTS and RETURNS rather than halting, because it is called inside `$(...)` where an exit would leave only the subshell and hand the caller an empty key — every call site is written `KEY="$(yt_project_key ...)" || exit "$YT_EXIT_CONFIG"` |
| **Conditions** | `syncyt.config.prefix_underivable`, `syncyt.config.project_key_unresolved`, `syncyt.config.resolver_unavailable`, `syncyt.config.project_key_env_ignored` (the binding won over a set environment variable — reported so an operator is told which one won), `syncyt.config.project_key_from_env` (the deprecation signal, level (3) ONLY) |
| **Re-run (idempotency)** | Stateless; the org file is re-read on every call, deliberately — a cached binding is a stale binding and this framework has no runtime to invalidate one in |

**BTG-315 (additive):** the same file also carries `yt_agent_user <ticket-id>`, the byte-parallel
sibling of the Jira adapter's `js_agent_user` — the §9 per-prefix row's OPTIONAL fifth cell. No
scalar fallback, no deprecated environment variable, and NEVER a config HALT: every failure mode
resolves to EMPTY (unsplit) rather than a config HALT, because split mode is strictly additive
(AC-4). Re-run: stateless, same as `yt_project_key`.
