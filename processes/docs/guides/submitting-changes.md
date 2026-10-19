# Submitting Changes

CADENCE is forge-agnostic. You can submit a change proposal through any of three standard forge workflows depending on where your repository is hosted:

| Forge | Mechanism | Description container |
|---|---|---|
| **GitLab** | Merge Request (MR) | MR description (Markdown) |
| **GitHub** | Pull Request (PR) | PR description (Markdown) |
| **SourceHut** | Patchset via `git send-email` | Cover letter (Markdown-in-email) or, for a single-commit series, the commit message itself |

Across CADENCE documentation, "MR" serves as the generic term for *a submitted change proposal*. On GitLab it corresponds to a Merge Request, on GitHub to a Pull Request, and on SourceHut to an email patchset thread on `lists.sr.ht`. The substantive engineering record required by reviewers is identical across all three — only the transport layer differs.

This guide covers the **authoring and submission** mechanics: how you prepare your branch and put it in front of reviewers. Gate checklists, AI review execution, and archival rules are forge-neutral and live in their respective policy and workflow documents.

---

## `submission.md` — the canonical source

In CADENCE, both the change-proposal description and the review discussion are version-controlled repository artifacts. Before opening an MR/PR or sending a patchset on any forge, instantiate [`specs/{ticket-id}/submission.md`](../../specs/TEMPLATE/submission.md) from `specs/TEMPLATE/submission.md` and commit it on your branch alongside the change. Then project its contents to your forge:

- **GitLab:** copy the `## Description` section of `submission.md` into the Merge Request body.
- **GitHub:** copy the `## Description` section into the Pull Request body.
- **SourceHut:** use the `## Description` section as the patchset cover letter (`git send-email --cover-letter --annotate …`), or as the commit message body for a single-commit patch.

As review feedback arrives, substantive threads and dispositions are appended to `submission.md`'s `## Discussion` section. On SourceHut, `submission.md` serves as the primary permanent record (since external mailing-list archives can move or go offline). On GitLab and GitHub, it mirrors the forge review thread into the repository so that when the ticket is archived to `archive/{ticket-id}/`, the entire engineering conversation travels with the code history. Once the change merges, the maintainer (or `cadence-archivist` during `/cadence-archive`) completes the `## Resolution` section.

Both `cadence-reviewer` and `cadence-maintainer` read `submission.md` directly from the working tree as "the MR description" — neither agent requires network API credentials to your forge. The forge web UI or email thread remains the ergonomic surface for inline diff comments and clicking Merge, while the Git repository remains the authoritative system of record.

### What the Description section must contain

The `## Description` section of `submission.md` carries six required elements (enforced by the template structure):

- A concise **summary** identifying the bounded context(s) and business flow(s) (`docs/flows/`) the change participates in.
- A link to `spec.md` (Standard track) or the inline abbreviated specification (Lightweight track — see [`contributor_experience_guide.md`](contributor_experience_guide.md)).
- A **Functional Validation** subsection: either an actionable checklist of user- or API-observable behaviors that a reviewer or QA engineer can verify at the boundary, or the exact sentence `No behavioral changes expected -- regression testing only.` Leaving this section blank or placeholdered is **never** treated as "no change" — tracker projection renders an unpopulated section as an explicit `NOT SPECIFIED` warning.
- A **Doc impact** statement: either a link to the updated `docs/flows/` / `docs/SYSTEM_OVERVIEW.md` files, or an explicit `"Doc impact: none — internal to {context}"` declaration (`docs/policies/doc-maintenance-policy.md`).
- A **Compatibility impact** statement whenever the change touches a registered surface, resolved across **every** surface registry present in the repository per `docs/policies/change-tiers.md`: `docs/policies/surface-registry.md` (adopter-owned) and `docs/policies/cadence-surfaces.md` (core-owned).
- Whenever database migrations are included: an explicit `[reversible, idempotent]` verification record or a reference to the automated integration test exercising the `apply → rollback → reapply` cycle (`docs/policies/migration-policy.md`).

---

## Workflow 1 — GitLab (Merge Request)

### Prerequisites
- Push permissions to a feature branch or repository fork.
- Optional: [`glab`](https://gitlab.com/gitlab-org/cli) installed for CLI-driven MR creation.

### Authoring steps

```sh
# 1. Cut a feature branch (or dedicated git worktree) from the integration branch
git checkout -b impl/feature/TT-1234

# 2. Implement via strict red-green-refactor TDD (see 04-implementation.md)
#    Commit once per scenario cycle.

# 3. Populate specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Push the branch to origin
git push -u origin impl/feature/TT-1234

# 5a. Open the MR via the GitLab web UI, OR
# 5b. Create it from the CLI using the Description section of submission.md:
glab mr create \
  --target-branch develop \
  --title "TT-1234: short summary" \
  --description "$(sed -n '/^## Description/,/^---$/p' specs/TT-1234/submission.md)"
```

### Description format
The GitLab MR description mirrors `submission.md`'s `## Description` section, rendered natively as GitLab Flavored Markdown. Repositories using `.gitlab/merge_request_templates/` can point reviewers directly to `specs/{ticket-id}/submission.md`.

### Discussion
Reviewers post inline diff comments and general feedback on the GitLab MR thread. As substantive questions and findings are resolved, the author (or the `/cadence-review` and `/cadence-maintain` skills) mirrors the discussion and finding classifications into `submission.md`'s `## Discussion` section.

### Acceptance
Once all required human gates for the ticket's tier pass, the maintainer merges the MR in GitLab. The maintainer (or `cadence-archivist` during `/cadence-archive`) records the merge details and follow-up dispositions in `submission.md`'s `## Resolution` section.

---

## Workflow 2 — GitHub (Pull Request)

### Prerequisites
- Push permissions to a feature branch or fork (following the worktree + remote PR workflow).
- Optional: [`gh`](https://cli.github.com/) installed for CLI-driven PR creation.

### Authoring steps

```sh
# 1. Cut a branch (in a dedicated git worktree outside the primary checkout)
git checkout -b impl/feature/TT-1234

# 2. Implement via strict TDD, committing once per scenario cycle.

# 3. Populate specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Push the branch to origin
git push -u origin impl/feature/TT-1234

# 5a. Open the PR via the GitHub web UI, OR
# 5b. Create it from the CLI using the Description section of submission.md:
gh pr create \
  --base develop \
  --title "TT-1234: short summary" \
  --body "$(sed -n '/^## Description/,/^---$/p' specs/TT-1234/submission.md)"
```

### Description format
The GitHub PR body mirrors `submission.md`'s `## Description` section and renders as GitHub Flavored Markdown. If the repository defines `.github/PULL_REQUEST_TEMPLATE.md`, it can reference `specs/{ticket-id}/submission.md`.

### Discussion
Reviewers leave line-level and summary comments on the PR's "Files changed" and "Conversation" tabs. Substantive points and gate assessments are mirrored into `submission.md`'s `## Discussion` section so the in-repo archive remains self-contained.

### Acceptance
After the required human gates pass, the maintainer merges the PR on GitHub (`gh pr merge`), and the resolution record in `submission.md` is finalized.

---

## Workflow 3 — SourceHut (patchset via `git send-email`)

SourceHut uses an email-driven patch workflow rather than a browser-based PR form. Contributors format commits as patch emails sent to the project's mailing list and iterate via email replies. The web archive at `lists.sr.ht/~user/repo/patches` indexes every patchset thread.

### Prerequisites

- A working `git send-email` configuration (one-time setup taking ~5 minutes).
- The repository's target `[PATCHES]` mailing list address — typically `~user/repo-devel@lists.sr.ht`, documented in the project's `README.md` or `PROJECT_INTENT.md`.

#### One-time setup

```sh
# Configure the target mailing list for this repository
git config sendemail.to '~user/repo-devel@lists.sr.ht'

# Prefix patch subjects with [PATCH project_name]
git config format.subjectPrefix 'PATCH project_name'

# Configure your outbound SMTP server (Gmail example)
git config --global sendemail.smtpserver smtp.gmail.com
git config --global sendemail.smtpserverport 587
git config --global sendemail.smtpencryption tls
git config --global sendemail.smtpuser you@gmail.com
git config --global sendemail.smtppass <app-password>
```

If you are setting up `git send-email` for the first time, [`git-send-email.io`](https://git-send-email.io) provides step-by-step instructions for common email providers.

### Authoring steps

```sh
# 1. Cut a feature branch
git checkout -b impl/feature/TT-1234

# 2. Implement via TDD, committing once per scenario cycle.

# 3. Populate specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Format and transmit the patch series to the mailing list.
#    For a multi-commit branch, include --cover-letter:
git send-email --cover-letter --annotate origin/develop..HEAD

#    For a single-commit change, the commit message body carries the description
#    (populated from submission.md):
git send-email -1
```

When `--cover-letter` is passed, `git send-email` opens your editor on a `[PATCH 0/N]` cover-letter template. Replace the `*** SUBJECT HERE ***` and `*** BLURB HERE ***` markers with the `## Description` section from `submission.md`. That cover letter acts as the mailing-list equivalent of a PR description, while `specs/{ticket-id}/submission.md` inside the repository remains the permanent source of truth.

### Description format

Plain text or Markdown inside the cover-letter body copied from `submission.md`'s `## Description` section. Lists, links, and fenced code blocks render cleanly in the `lists.sr.ht` web interface.

### Subject prefix

By default `git send-email` numbers patches `[PATCH 1/N]`, `[PATCH 2/N]`, and so on. Setting `format.subjectPrefix` produces `[PATCH project_name 1/N]`, making patch threads easy to filter across shared mailing lists.

### Discussion

Reviewers reply directly to the patch emails (using standard `>` inline quoting to comment on specific diff lines).

Because mailing-list archives live outside the Git repository, **`submission.md`'s `## Discussion` section serves as the canonical archive of the review.** The author and review skills mirror substantive thread replies and dispositions into `submission.md` as the review progresses, ensuring no context is lost if an external list URL ever changes.

### Sending a new version

When review feedback calls for code revisions, update your branch commits, re-run the test suite, append the resolution notes to `submission.md` `## Discussion`, increment the patchset version in `## Forge metadata`, and transmit a `v2` series:

```sh
git send-email --cover-letter -v2 --annotate origin/develop..HEAD
```

Passing `-v2` prefixes subjects with `[PATCH v2 …]`. Include a concise v1→v2 changelog in the cover letter drawn from your latest `## Discussion` entries.

### Acceptance

Once the required human gates pass on the thread, the maintainer applies the patchset with `git am` (or `b4 am`):

```sh
# Fetch and apply the patchset by message-id using b4 (recommended)
b4 am <message-id>
# OR apply from a local mbox file
git am < ~/Maildir/patchset.mbox

# Verify the full test suite passes, then push to the integration branch
git push origin trunk
```

`git am` preserves original commit authorship while appending the maintainer's `Signed-off-by:` trailer when configured. Finally, `submission.md`'s `## Resolution` section is completed.

### Recording the thread URL

Record the `lists.sr.ht` thread URL in `submission.md` under `## Forge metadata`:

```
- Forge: sourcehut
- Thread URL: https://lists.sr.ht/~antonioyon/CADENCE-devel/patches/12345
- Branch: impl/feature/TT-1234
- Target branch: trunk
- Submitted: 2026-05-18 14:32 UTC
```

You may also populate `merge_request:` in `specs/{ticket-id}/metadata.yaml` with the same URL for quick CLI lookup; `submission.md` remains the authoritative record.

---

## Choosing a workflow for a new adopter repo

When adopting CADENCE in a repository, select the submission workflow that matches your hosting platform:

- **GitLab (self-managed or gitlab.com):** Workflow 1.
- **GitHub:** Workflow 2.
- **SourceHut (or any email-patch workflow):** Workflow 3.

A single repository only needs to use the workflow matching its forge; CADENCE supports all three so teams never have to switch hosting platforms to adopt the SDLC.

---

## What stays the same across workflows

- **`submission.md`** — authored before submission, supplies the MR/PR/cover-letter description, accumulates review discussion and finding dispositions, and freezes the final merge resolution inside `archive/{ticket-id}/`.
- **The human gates** — Spec Approval (Gate 1), Code Review (Gate 2), Maintainer Acceptance (Gate 3), and Deploy Validation (Gate 4). The gate criteria in `docs/agentic-sdlc/human-gates.md` are identical across all forges.
- **The `cadence-reviewer` and `cadence-maintainer` agents** — both consume local `git diff` and `submission.md` (assisted by `offload_deep_review` and `offload_log_triage`), operating with zero hard dependency on proprietary forge APIs.
- **Archival** — `/cadence-archive` relocates `specs/{ticket-id}/` to `archive/{ticket-id}/` with the completed `submission.md` preserving the full audit trail inside Git.
- **CI/CD pipelines** — the scripts under `ci-templates/` validate the commits on the integration branch regardless of how the change proposal was transported.

---

## Related docs

- [`contributor_experience_guide.md`](contributor_experience_guide.md) — end-to-end contributor onboarding, intent issues, and the lightweight vs. standard tracks.
- [`../agentic-sdlc/human-gates.md`](../agentic-sdlc/human-gates.md) — human gate checklists and review responsibilities.
- [`../policies/change-tiers.md`](../policies/change-tiers.md) — objective triggers determining which gates apply per change tier.
- [`../policies/inner_source_sdlc_charter.md`](../policies/inner_source_sdlc_charter.md) — enterprise Inner-Source SDLC governance charter.
