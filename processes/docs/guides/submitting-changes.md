# Submitting Changes

CLAIRE is forge-neutral. You can submit a change proposal through any of three workflows depending on where the repo lives:

| Forge | Mechanism | Description container |
|---|---|---|
| **GitLab** | Merge Request (MR) | MR description (Markdown) |
| **GitHub** | Pull Request (PR) | PR description (Markdown) |
| **SourceHut** | Patchset via `git send-email` | Cover letter (Markdown-in-email) or, for a single-commit series, the commit message itself |

The rest of the framework uses "MR" as the generic noun for *the change proposal*. On GitLab that maps to a Merge Request; on GitHub to a Pull Request; on SourceHut to a patchset thread on `lists.sr.ht`. The content the reviewers need is the same across forges — only the transport differs.

This guide covers the **authoring** side: how you get your branch in front of reviewers. Reviewer behavior (gate checklists, agent reads, archival) is forge-neutral and lives in the relevant policy and agent docs.

---

## `submission.md` — the canonical source

The change-proposal description and the review discussion are versioned repository artifacts. Before you submit through any forge, write [`specs/{ticket-id}/submission.md`](../../specs/TEMPLATE/submission.md) using the template at `specs/TEMPLATE/submission.md`. Commit it on your branch alongside the implementation. Then submit through your forge:

- **GitLab:** paste the `## Description` section of `submission.md` into the MR body.
- **GitHub:** paste the `## Description` section into the PR body.
- **SourceHut:** use the `## Description` section as the cover letter (`git send-email --cover-letter --annotate …`), or, for a single-commit series, as the lead commit message.

After submission, the `## Discussion` section is appended as review feedback comes in. For SourceHut this is the canonical record (the `lists.sr.ht` thread may move or rot). For GitLab/GitHub it mirrors the forge thread so the archive carries the discussion when the spec freezes. The `## Resolution` section is filled by the maintainer (or by the archivist) when the change merges.

The code-reviewer and maintainer agents read `submission.md` directly as "the MR description". They do not need API access to your forge. The forge UI/thread is still useful for line-level commenting and the merge action itself — but the system of record is in the repo.

### What the Description section must contain

The `## Description` section of `submission.md` carries this payload (the template enforces the shape):

- A one-line **summary** that names the bounded context(s) and flow(s) the change belongs to.
- A link to the corresponding `spec.md` (Standard track) or the abbreviated specification inline (Lightweight track — see [`contributor_experience_guide.md`](contributor_experience_guide.md)).
- A **Functional Validation** subsection: either a checklist of end-user-observable behaviour changes a QA
  engineer can verify by hand at the UI/API boundary, or the single line `No behavioral changes expected --
  regression testing only.` Leaving it unfilled is **not** the no-change form — it projects to the tracker as
  an explicit NOT SPECIFIED marker, which is a visible gap rather than an assurance.
- A **Doc impact** line: either a link to a `docs/flows/` update, or an explicit "Doc impact: none — internal to {context}" acknowledgment.
- A **Compatibility impact** line for changes touching a registered surface. Resolve that across **every** registry present, per `docs/policies/change-tiers.md`'s rule: `docs/policies/surface-registry.md` (adopter-owned) and `docs/policies/claire-surfaces.md` (core-owned).
- For changes with database migrations: an `[reversible, idempotent]` confirmation or a link to the integration test that proves apply/rollback/reapply works.

---

## Workflow 1 — GitLab (Merge Request)

### Prerequisites
- Push access to a fork or feature branch in the same project.
- Optional: [`glab`](https://gitlab.com/gitlab-org/cli) for command-line MR creation.

### Authoring steps

```sh
# 1. Branch from the project's default branch
git checkout -b TT-1234-add-feature

# 2. Implement via TDD (see implementer agent / TDD discipline)
#    Commit per red-green cycle. Final commit count is unconstrained.

# 3. Write specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Push the branch
git push -u origin TT-1234-add-feature

# 5a. Open the MR through the GitLab web UI, OR
# 5b. Open it from the CLI, pasting the Description section as the body:
glab mr create \
  --target-branch develop \
  --title "TT-1234: short summary" \
  --description "$(sed -n '/^## Description/,/^---$/p' specs/TT-1234/submission.md)"
```

### Description format
The MR body is a copy of `submission.md`'s `## Description` section. GitLab Markdown renders it. If the project has `.gitlab/merge_request_templates/`, the template can simply point reviewers at `submission.md` in the repo.

### Discussion
GitLab MR comments, including threaded review on individual lines of the diff. As substantive comments accumulate, the author (or reviewers themselves on append) mirrors the substance back into `submission.md`'s `## Discussion` section so the archive carries the record.

### Acceptance
Maintainer clicks **Merge** in the GitLab UI after the human gates pass. The merge commit's message is shaped by the project's merge-method setting. The maintainer (or archivist on follow-up) fills in `submission.md`'s `## Resolution` section.

---

## Workflow 2 — GitHub (Pull Request)

### Prerequisites
- Push access to a fork or feature branch.
- Optional: [`gh`](https://cli.github.com/) for command-line PR creation.

### Authoring steps

```sh
# 1. Branch
git checkout -b TT-1234-add-feature

# 2. Implement via TDD, commit per cycle.

# 3. Write specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Push
git push -u origin TT-1234-add-feature

# 5a. Open the PR through the GitHub web UI, OR
# 5b. Open it from the CLI, using the Description section as the body:
gh pr create \
  --base develop \
  --title "TT-1234: short summary" \
  --body "$(sed -n '/^## Description/,/^---$/p' specs/TT-1234/submission.md)"
```

### Description format
The PR body is a copy of `submission.md`'s `## Description` section. GitHub-flavored Markdown renders it. If the project has `.github/PULL_REQUEST_TEMPLATE.md`, the template can simply point reviewers at `submission.md` in the repo.

### Discussion
PR comments, including threaded review on individual lines of the diff and "Files changed" view. As substantive comments accumulate, the author (or reviewers themselves on append) mirrors the substance back into `submission.md`'s `## Discussion` section so the archive carries the record.

### Acceptance
Maintainer clicks **Merge pull request** in the GitHub UI after the human gates pass. The maintainer (or archivist on follow-up) fills in `submission.md`'s `## Resolution` section.

---

## Workflow 3 — SourceHut (patchset via `git send-email`)

SourceHut does not have a UI-based MR/PR. Changes are submitted as patchsets to the project's mailing list and reviewed by email reply. The web view at `lists.sr.ht/~user/repo/patches` archives every thread; the threads are the system of record.

### Prerequisites

- A configured `git send-email` (one-time setup, ~5 minutes).
- The project's `[PATCHES]` mailing list address — typically `~user/repo-devel@lists.sr.ht` for a sr.ht-hosted project. Look in the project's README or `CONTRIBUTING` for the canonical address.

#### One-time setup

```sh
# Tell git the mailing list to send to
git config sendemail.to '~user/repo-devel@lists.sr.ht'

# Tell git to prefix patch subjects with [PATCH project_name]
git config format.subjectPrefix 'PATCH project_name'

# Configure your SMTP server (Gmail example shown)
git config --global sendemail.smtpserver smtp.gmail.com
git config --global sendemail.smtpserverport 587
git config --global sendemail.smtpencryption tls
git config --global sendemail.smtpuser you@gmail.com
git config --global sendemail.smtppass <app-password>
```

If you're new to `git send-email`, the SourceHut tutorial at [`git-send-email.io`](https://git-send-email.io) walks through SMTP setup for common providers.

### Authoring steps

```sh
# 1. Branch
git checkout -b TT-1234-add-feature

# 2. Implement via TDD, commit per cycle.

# 3. Write specs/TT-1234/submission.md from the template
cp specs/TEMPLATE/submission.md specs/TT-1234/submission.md
# fill in Status=Submitted, Description, Forge metadata, etc.

git add specs/TT-1234/submission.md
git commit -m "TT-1234: add submission artifact"

# 4. Format the patches and send them to the list.
#    For a multi-commit series, include --cover-letter:
git send-email --cover-letter --annotate origin/develop..HEAD

#    For a single-commit fix, the commit message itself is the description
#    (still copy the same content from submission.md):
git send-email -1
```

When `--cover-letter` is set, `git send-email` opens your editor on a placeholder cover-letter email. Replace the `*** SUBJECT HERE ***` and `*** BLURB HERE ***` placeholders with the contents of `submission.md`'s `## Description` section. The cover letter is the SourceHut equivalent of the MR/PR body — it is what subscribers to the list see — but `submission.md` in the repo is the canonical record. For a single-commit series the commit message plays the cover letter's role; populate it from `submission.md` the same way.

### Description format

Plain text or Markdown in the cover-letter body, mirroring `submission.md`'s `## Description` section. Lists, links, and code blocks render in the `lists.sr.ht` web archive even though the transport is email.

### Subject prefix

By default `git send-email` will subject patches `[PATCH 1/N]`, `[PATCH 2/N]`, etc. If `format.subjectPrefix` is set (recommended), the prefix becomes `[PATCH project_name 1/N]` so threads are easily filterable in archives.

### Discussion

Reviewers reply to the patchset thread (in their mail client or via the `lists.sr.ht` web UI). Inline comments use the standard email convention of quoting the diff line with `>` and replying underneath.

Because SourceHut has no built-in archive guarantee comparable to GitLab/GitHub's, **`submission.md`'s `## Discussion` section is the canonical record of the review.** The author (or reviewers themselves on append) mirrors substantive comments and resolutions back into the file as the conversation happens. If the `lists.sr.ht` thread ever moves or rots, the discussion is still in the repo.

### Sending a new version

If review feedback requires changes, rework your commits locally (`git rebase -i`, then re-run tests), update `submission.md` (append the resolution entries to `## Discussion`, bump the patchset-version entry in `## Forge metadata`), and send a v2:

```sh
git send-email --cover-letter -v2 --annotate origin/develop..HEAD
```

The `-v2` adds `[PATCH v2 …]` to the subject. The cover letter for v2 should include a brief changelog of what changed since v1 — copy it from the new `## Discussion` entries you just appended.

### Acceptance

The maintainer applies the patchset with `git am` after consensus on the thread:

```sh
# Fetch the patchset (from your inbox, or via b4 fetching the message-id from lists.sr.ht)
b4 am <message-id>            # if you use b4 (recommended)
# OR
git am < ~/Maildir/patchset.mbox

# Run the full test suite, then push to trunk
git push origin trunk
```

Patches preserve authorship — your commits land in `trunk` with your name in `Author:`. The maintainer's `Signed-off-by:` chain (if the project uses one) is appended. The maintainer (or archivist on follow-up) fills in `submission.md`'s `## Resolution` section.

### Recording the thread URL

Set the `Thread URL` field in `submission.md`'s `## Forge metadata` section to the `lists.sr.ht` patchset URL:

```
- Forge: sourcehut
- Thread URL: https://lists.sr.ht/~antonioyon/CLAIRE-devel/patches/12345
- Branch: TT-1234-add-feature
- Target branch: trunk
- Submitted: 2026-05-18 14:32 UTC
```

The same URL may also be set in `specs/{ticket-id}/metadata.yaml`'s `merge_request:` field as a quick pointer for automation; the authoritative record is `submission.md`.

---

## Choosing a workflow for a new adopter repo

If you're setting up CLAIRE in a new repo, pick the workflow that matches your forge:

- **Hosted on GitLab (self-hosted or gitlab.com):** Workflow 1.
- **Hosted on GitHub:** Workflow 2.
- **Hosted on SourceHut, or any setup where the project prefers email patches:** Workflow 3.

You do **not** need to support multiple workflows in one repo. The framework supports all three so adopters are not forced to migrate.

---

## What stays the same across workflows

- **`submission.md`** — written before submission, mirrors the description into the forge body / cover letter, accumulates discussion, and freezes the resolution. Archived alongside the other spec artifacts.
- **The human gates** — Spec Review, Code Review, Maintainer Acceptance, Deploy Validation. The gate checklists in `docs/agentic-sdlc/human-gates.md` apply regardless of forge.
- **The code-reviewer and maintainer agents** — they read `git diff` (forge-neutral) and `submission.md` (also forge-neutral) as their primary inputs.
- **Archival** — the archivist moves `specs/{ticket-id}/` to `archive/{ticket-id}/` with the frozen `submission.md` carrying the full record. The forge thread URL stays in the file for reference but is no longer load-bearing.
- **CI/CD** — the `ci-templates/` pipelines run on the merged commit on `trunk`/`main`/`develop`; they don't care how the change arrived.

---

## Related docs

- [`contributor_experience_guide.md`](contributor_experience_guide.md) — the full contributor workflow, including intent issues and the lightweight track.
- [`../agentic-sdlc/human-gates.md`](../agentic-sdlc/human-gates.md) — gate checklists and reviewer responsibilities.
- [`../policies/change-tiers.md`](../policies/change-tiers.md) — which process steps apply by change risk.
- [`../policies/inner_source_sdlc_charter.md`](../policies/inner_source_sdlc_charter.md) — governance charter (when adopting inner-source).
