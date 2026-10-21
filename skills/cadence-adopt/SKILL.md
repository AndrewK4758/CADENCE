---
name: cadence-adopt
description: Install the portable CADENCE governance file set into a target repository. Wraps the canonical adoption script and never overwrites pre-existing files in the destination.
argument-hint: "<target-repo-root> [--gitignore-machinery]"
arguments: [target_repo_root, gitignore_machinery]
allowed-tools: Read Bash
---

## Task

Install the portable CADENCE framework footprint into the repository directory at `$target_repo_root` by delegating execution to the canonical adoption script at `.agents/skills/cadence-adopt/adopt-cadence.sh` (with `.gemini/` as the canonical Gemini/Antigravity runtime directory and `.claude/` or other CLI runtime directories projected off `.agents/` per `docs/policies/cli-runtime-adoption-policy.md`).

This skill never reimplements file-copy logic directly — the shell script serves as the single authoritative source for which artifacts are installed and which are skipped. The skill validates arguments, executes the script, and streams the script's output verbatim so that every `copied:` / `skip (exists):` line and the concluding `Done: N copied, M skipped` summary remain intact.

An optional `--gitignore-machinery` flag (disabled by default) instructs the script to also write a managed `.gitignore` block enumerating the installed CADENCE machinery, enabling co-located adopters to keep framework files local-only (untracked on their remote) without manually maintaining `.gitignore`. The flag acts as a clean pass-through: the skill validates and forwards it, while the script (PI-034) derives the ignore-path set from the adopter footprint descriptor and owns the block insertion/replacement logic. `AGENTS.md` is never gitignored (adopters customize and share it across the team).

## Prerequisites

Before invoking the script, confirm:

1. `$target_repo_root` is supplied and non-empty. If absent, halt with: "Usage: `/cadence-adopt <target-repo-root>`. The target-repo-root is the path to the repository receiving the framework file set."
2. `$target_repo_root` does not resemble a remote URL (contains no `://` substring and no `git@` prefix). If it does, halt with: "Adoption operates on a local directory. Clone the target repository first, then re-run `/cadence-adopt` against the local clone."

## Steps

### 1. Canonicalize and validate the target

Resolve `$target_repo_root` to its canonical absolute path:

```bash
realpath "$target_repo_root"
```

If `realpath` fails because the path does not exist, halt with: "Target directory does not exist: `$target_repo_root`. Create the directory (or clone the target repo) before running adoption."

Next, confirm the resolved path is a directory:

```bash
[[ -d "<canonical_target>" ]]
```

If the path points to a regular file or anything other than a directory, halt with the same missing-target error message.

### 2. Refuse self-target

Determine the CADENCE source repository root:

```bash
git rev-parse --show-toplevel
```

Canonicalize that path using `pwd -P` semantics. If the canonicalized target path matches the canonicalized CADENCE repository root, halt with: "Target is the CADENCE repo itself. Adoption copies the framework into a *different* repository; targeting the source repo is a no-op at best and a self-overwrite at worst."

Apply symlink-resolving canonicalization (`realpath` or `cd <path> && pwd -P`) on both paths so that a symlinked destination pointing back to the source repository is likewise rejected.

### 3. Locate the canonical script

The canonical adoption script resides at:

```
<cadence-root>/.agents/skills/cadence-adopt/adopt-cadence.sh
```

Confirm that the file exists and carries executable permissions. If not, halt with: "Canonical script not found at `<path>`. Run from a clone of the CADENCE repo (or an adopted repo whose `.agents/skills/cadence-adopt/` is intact)."

### 4. Invoke the script

Execute the script (appending `--gitignore-machinery` only when requested by the adopter):

```bash
<cadence-root>/.agents/skills/cadence-adopt/adopt-cadence.sh "<canonical_target>" [--gitignore-machinery]
```

When the adopter omits the flag, invoke the script without it (preserving byte-identical default behavior with zero `.gitignore` I/O). When the flag is supplied, the script writes or replaces a single managed block and reports `.gitignore (machinery block written|replaced)` in its per-file output stream.

Stream stdout and stderr directly to the adopter verbatim. Never alter, condense, or paraphrase the per-file status lines or final summary — they constitute the adoption audit trail. If the script exits non-zero or emits diagnostic/gate output exceeding 30 lines (for example during post-copy gate checks such as `authored-doc-gate.sh` or `dead-citation-gate.sh`), automatically route the noisy log output through `offload_log_triage` (`local-fast-cpu` on `:11434`) to extract verbatim error lines while preserving the complete raw output in `/tmp/agy-last-triage.log`.

### 5. Verify the file set landed in the target

Because the script reports completion against its own `$DST` working target at copy time — which could differ from the adopter's intended destination if executed inside an ephemeral isolation worktree that is subsequently cleaned up — **independently** verify the canonical absolute destination resolved in Step 1 after the script exits 0:

```bash
test -f "<canonical_target>/specs/CADENCE.md" \
  && test -d "<canonical_target>/specs/TEMPLATE" \
  && test -d "<canonical_target>/.agents/skills"
```

If any assertion fails, do NOT report success. Halt with: "Adoption reported success but the framework file set is not present at `<canonical_target>` (missing `specs/CADENCE.md` / `specs/TEMPLATE/` / `.agents/skills/`). The copy likely ran against a different directory (for example, an isolation worktree). Re-run from the CADENCE repo with an absolute target path."

Note that `.agents/` is the primary neutral runtime surface (with `.gemini/` serving as the canonical Gemini/Antigravity runtime projection and `.claude/` or other CLI directories projected off `.agents/` per `docs/policies/cli-runtime-adoption-policy.md`).

The script also **seeds the id-allocation ledger** (PI-039): it initializes the reserve ledger (under `git-common-dir`, or a working-tree `.cadence/` fallback), seeds `ADR` to high-water mark 0 unconditionally, and seeds the ticket prefix to 0 whenever §10 is unbound and a concrete prefix can be resolved (a brand-new template repository self-seeds its ticket prefix at `-001` upon the first `--reserve`). Ledger seeding is create-if-absent (re-running adoption never overwrites existing seeds) and fatal on failure; the script verifies ledger resolution (`--peek ADR`) prior to reporting success. The ledger belongs to adopter state and has **no** footprint descriptor row.

### 6. Report outcome

- When the script exits 0 **and** Step 5 verification passes: output a single line — "Adoption complete. Next steps: see `docs/agentic-sdlc/getting-started.md` §2 (author PROJECT_INTENT.md) and §3 (customize AGENTS.md)."
- When the script exits non-zero: output "Adoption script failed with exit code `<N>`. See stderr above." Terminate immediately without printing a success message.

## Constraints

- **Wrap, never reimplement.** The bash script is the sole source of truth for the file manifest, the no-overwrite safety guarantee, and the per-file output grammar. This skill never copies framework files using native file-writing tools — its `allowed-tools` intentionally omits Edit and Write.
- **Never overwrites existing files.** The script's `[[ -e "$DST/$rel" ]]` guard enforces the non-destructive invariant. To refresh a specific file from upstream, the adopter must remove it explicitly before re-running adoption or use `/cadence-upgrade`.
- **Local filesystem only.** Remote repository URLs (HTTPS, SSH, `git@`) are rejected. Cloning the target repository beforehand is the adopter's responsibility.
- **Deterministic execution.** Identical resolved release commit + identical destination state produces the exact same copy set (BTG-314: resolved from the core checkout's release tag commit using the same resolution rule as `/cadence-upgrade`, never from uncommitted working-tree state). The skill introduces no adaptive branching.
- **Audit-trail fidelity.** Every `copied:` / `skip (exists):` line and the concluding `Done: N copied, M skipped` summary emitted by the script are preserved verbatim.

## Examples

```
/cadence-adopt /home/me/my-new-project
```

Checks that `/home/me/my-new-project` exists, is a directory, and is distinct from the CADENCE source repository. Executes the canonical script to install the framework file set into the target, streaming each per-file status line and the `N copied, M skipped` summary.

```
/cadence-adopt git@github.com:me/repo.git
```

**Refused.** Adoption only runs against a local directory. Clone the repository locally first, then invoke `/cadence-adopt` with the local path.

```
/cadence-adopt .
```

If the current working directory is the CADENCE source repository, **refused** — self-targeting is disallowed. If invoked from an already-adopted repository targeting itself, the same check refuses the self-target.

```
/cadence-adopt /tmp/already-adopted
```

When `/tmp/already-adopted` already houses the CADENCE file set, the script executes cleanly and skips every existing path (`skip (exists):` per file), finishing with `Done: 0 copied, N skipped (already present).` The skill confirms completion without mutating existing files.

```
/cadence-adopt /home/me/my-new-project --gitignore-machinery
```

Installs the framework as normal, then writes a single managed `.gitignore` section (bounded by `# >>> CADENCE machinery ... >>>` / `# <<< CADENCE machinery <<<`) enumerating the installed CADENCE machinery — including the compiled `.agents/agents` and `.agents/skills` trees (plus any projected `.gemini/` or `.claude/` runtime surfaces per `docs/policies/cli-runtime-adoption-policy.md`) and installed documentation/templates — keeping framework machinery untracked in the adopter's remote repository. `AGENTS.md` (along with the bare runtime config root, `CHANGELOG.md`, and `archive/`) remains tracked. Re-running with `--gitignore-machinery` updates the managed block in place without duplicating entries.
