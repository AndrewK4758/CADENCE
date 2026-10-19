---
name: claire-adopt
description: Copy the CLAIRE framework file set into a target repository. Wraps the canonical adoption script; never overwrites files that already exist in the target.
argument-hint: "<target-repo-root> [--gitignore-machinery]"
arguments: [target_repo_root, gitignore_machinery]
allowed-tools: Read Bash
---

## Task

Copy the portable CLAIRE framework files into the directory at `$target_repo_root` by delegating to the canonical adoption script at `.claude/skills/claire-adopt/adopt-claire.sh`.

The skill does not implement the copy logic itself — the bash script is the single source of truth for what gets copied and what gets skipped. The skill validates inputs, invokes the script, and streams the script's output verbatim so the per-file `copied:` / `skip (exists):` lines and the final `Done: N copied, M skipped` summary are preserved as-is.

An optional `--gitignore-machinery` flag (default off) asks the script to also write a managed `.gitignore` block listing the installed CLAIRE machinery, so co-located adopters can keep the framework local-only (untracked in their remote) without hand-maintaining `.gitignore`. The flag is a thin pass-through: the skill validates and forwards it; the script (PI-034) derives the ignore-path set from the adopter footprint descriptor and owns the write/replace logic. `CLAUDE.md` is never gitignored (adopters customize and share it).

## Prerequisites

Before invoking the script, verify:

1. `$target_repo_root` is provided and non-empty. If missing, stop with: "Usage: `/claire-adopt <target-repo-root>`. The target-repo-root is the path to the repository receiving the framework file set."
2. `$target_repo_root` does not look like a URL (no `://` substring, no `git@` prefix). If it does, stop with: "Adoption operates on a local directory. Clone the target repository first, then re-run `/claire-adopt` against the local clone."

## Steps

### 1. Canonicalize and validate the target

Resolve `$target_repo_root` to an absolute path:

```bash
realpath "$target_repo_root"
```

If `realpath` fails (path does not exist), stop with: "Target directory does not exist: `$target_repo_root`. Create the directory (or clone the target repo) before running adoption."

Then verify it is a directory:

```bash
[[ -d "<canonical_target>" ]]
```

If it is a file or otherwise not a directory, stop with the same target-missing message.

### 2. Refuse self-target

Locate the CLAIRE repo root:

```bash
git rev-parse --show-toplevel
```

Canonicalize the result with `pwd -P` semantics. If the canonicalized target equals the canonicalized CLAIRE repo root, stop with: "Target is the CLAIRE repo itself. Adoption copies the framework into a *different* repository; targeting the source repo is a no-op at best and a self-overwrite at worst."

Use symlink-following resolution (`realpath` or `cd <path> && pwd -P`) on both sides so a symlinked target that points at the source is also refused.

### 3. Locate the canonical script

The canonical script lives at:

```
<claire-root>/.claude/skills/claire-adopt/adopt-claire.sh
```

Verify it exists and is executable. If not, stop with: "Canonical script not found at `<path>`. Run from a clone of the CLAIRE repo (or an adopted repo whose `.claude/skills/claire-adopt/` is intact)."

### 4. Invoke the script

Run (appending `--gitignore-machinery` only when the adopter passed it):

```bash
<claire-root>/.claude/skills/claire-adopt/adopt-claire.sh "<canonical_target>" [--gitignore-machinery]
```

If the adopter did not pass the flag, invoke without it (byte-identical legacy behavior — the script performs zero `.gitignore` I/O). When the flag is passed, the script writes/replaces a single managed block and announces `.gitignore (machinery block written|replaced)` in its per-file output.

Stream stdout and stderr to the adopter verbatim. Do not transform, summarize, or paraphrase the per-file lines or the final summary — they are the audit trail.

### 5. Verify the file set landed in the target

The script reports success based on its own `$DST`, which is its working directory at copy time — not necessarily the directory the adopter meant. If adoption is driven from an isolation worktree that is later discarded, the script can exit 0 having written into a directory that no longer exists. So after the script exits 0, **independently** re-verify the canonical absolute target computed in step 1:

```bash
test -f "<canonical_target>/specs/CLAIRE.md" \
  && test -d "<canonical_target>/specs/TEMPLATE" \
  && test -d "<canonical_target>/.claude/skills"
```

If any check fails, do NOT report success. Stop with: "Adoption reported success but the framework file set is not present at `<canonical_target>` (missing `specs/CLAIRE.md` / `specs/TEMPLATE/` / `.claude/skills/`). The copy likely ran against a different directory (for example, an isolation worktree). Re-run from the CLAIRE repo with an absolute target path."

The script additionally **seeds the id-allocation ledger** (PI-039): it generates the reserve ledger (git-common-dir, or a working-tree `.claire/` fallback), seeds `ADR` to high-water 0 always, and the ticket prefix to 0 when §10 is unbound and a concrete prefix is resolvable (a fresh-from-template repo self-seeds the ticket prefix at `-001` on the first `--reserve`). Seeding is fatal-on-failure and create-if-absent (a re-adopt never reseeds), and the script asserts the ledger resolves (`--peek ADR`) before reporting success. The ledger is adopter data and carries **no** footprint row.

### 6. Report outcome

- On script exit 0 **and** the step-5 verification passing: print one line — "Adoption complete. Next steps: see `docs/agentic-sdlc/getting-started.md` §2 (author PROJECT_INTENT.md) and §3 (customize CLAUDE.md)."
- On script exit non-zero: print "Adoption script failed with exit code `<N>`. See stderr above." Exit without adding a success summary.

## Constraints

- **Wrap, do not reimplement.** The bash script is the single source of truth for the file set, the never-overwrite invariant, and the per-file output format. The skill does NOT inline file-copy of framework files via other tools — its `allowed-tools` deliberately excludes Edit and Write.
- **Never overwrites.** The script's `[[ -e "$DST/$rel" ]]` check is the skill's safety invariant. If an adopter wants to re-sync a file, they delete it deliberately before re-running.
- **Local only.** No remote targets (git URLs, SSH paths). Cloning is the adopter's job.
- **Deterministic.** Same resolved release commit + same target state ⇒ same copy set (BTG-314: the release commit the core checkout's release tag names, resolved the same way `/claire-upgrade` resolves its base -- never the checkout's working tree, which is never installed). The skill does not add adaptive behavior.
- **Audit-trail preservation.** The per-file `copied:` / `skip (exists):` lines and the final `Done: N copied, M skipped` summary are emitted by the script unchanged.

## Examples

```
/claire-adopt /home/me/my-new-project
```

Validates that `/home/me/my-new-project` exists, is a directory, and is not the CLAIRE repo. Invokes the canonical script, which copies the framework file set into the target. Prints the script's per-file output and the `N copied, M skipped` summary.

```
/claire-adopt git@github.com:me/repo.git
```

**Refused.** Adoption operates on a local directory. The adopter must clone the repo first, then re-run with the local clone path.

```
/claire-adopt .
```

If the current working directory is the CLAIRE repo, **refused** — target is the CLAIRE repo itself. Otherwise (skill is being run from an adopted repo onto itself), also refused via the same check.

```
/claire-adopt /tmp/already-adopted
```

If `/tmp/already-adopted` already contains the framework files, the script runs to completion but skips every file (`skip (exists):` for each). The final summary reads `Done: 0 copied, N skipped (already present).` The skill reports adoption complete; no harm done.

```
/claire-adopt /home/me/my-new-project --gitignore-machinery
```

Adopts as usual, then writes a single managed `.gitignore` block (delimited by `# >>> CLAIRE machinery ... >>>` / `# <<< CLAIRE machinery <<<`) listing the installed CLAIRE machinery — including the compiled `.claude/agents` and `.claude/skills` trees and the installed docs/templates — so the framework stays untracked in the adopter's remote. `CLAUDE.md` (and the bare runtime config dir, `CHANGELOG.md`, `archive/`) stay tracked. Re-running with the flag replaces the block in place rather than appending a duplicate.
