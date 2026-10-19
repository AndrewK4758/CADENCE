# `/claire-sync-jira` — reported conditions: the umbrella projection

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-105).
Invariant relied on from outside this boundary: identical to its siblings
`.claude/skills/claire-sync-jira/jira-server-conditions.md` and
`.claude/skills/claire-sync-jira/jira-server-conditions-links.md` — every script writes its result to
**stdout** as `key=value` lines and its audit conditions to **stderr** as `syncjs.<family>.<condition>`
lines (`.claude/skills/claire-sync-jira/jira-server-scripts.md`, *the three-channel return contract*).

**This file is the third part of one catalogue, not a third catalogue.** It was split off by BTG-105,
which replaced the umbrella re-type with a create-and-close flow: five names retired, eighteen added,
against a primary already at the 400-line DX ceiling. The record is **split, never truncated** — the
same facet-conflict resolution BTG-102 applied when it split the links half (C-3: Operability outranks
DX on *content*; DX is served by the placement instead). The seam is by emitting site: the umbrella
branch of `.claude/skills/claire-sync-jira/jira-epic.sh` and its module
`.claude/skills/claire-sync-jira/jira-umbrella-lib.sh`.

**Every name in this file is verified against the emitting line in the script.** A condition that is
documented but never emitted, or emitted but described as something else, is the defect class BTG-075's
re-reviews kept finding.

---

## What changed, and why (BTG-105)

The predecessor flow **re-typed the original issue in place**: `PUT /rest/api/2/issue/{T}
{fields:{issuetype:{name: <umbrella issue_type>}}}`, with no check of the live type. On Jira Server/DC a
bare update `PUT` does **not** enforce `editmeta.allowedValues` (BTG-102 DEC-026, live-verified): it
returns **204**, the type **takes**, the workflow pointer does **not** follow, the reachable transition
set collapses, and **no `Workflow` changelog item is written**. Both of that path's safeguards were
therefore structurally unable to fire — `retype_rejected` needed a non-2xx, `type_unverified` needed the
type not to take — so the corruption produced **no condition at all** (DEC-031). Three PLAYSCRUM issues
were realised this way (PROD_CLAIRE-014); their repair is BTG-103's, not this path's.

**An issue born at the right type needs no re-type.** So the branch now creates a fresh issue `U`
already at `umbrella.issue_type`, gives it the original's Epic Link to the top-level Epic `E`, moves the
children's ordered links onto it, and **closes** the original. The original keeps its type, its Epic Link
and its summary, and survives as the record that a supersession occurred.

**`U` is never an `Epic`.** It must carry an Epic Link to `E`, and Jira Server/DC forbids an Epic from
carrying one (BTG-036) — which is precisely why `umbrella.issue_type` is `"Issue"`. **The children are
not touched:** their Epic Link already points at `E` and continues to, so the board shape is unchanged.

**Retired names**, emitted by nothing and documented nowhere as of BTG-105:
`syncjs.umbrella.retype_rejected`, `syncjs.retype.type_unverified`,
`syncjs.umbrella.retype_body_unbuildable`, `syncjs.umbrella.summary_rejected`,
`syncjs.umbrella.summary_body_unbuildable`. They named branches that cease to exist. The whole
`syncjs.retype.*` namespace disappears with them.

## The branch's three modes

Resolved from **repo-owned state alone** — the `umbrella_epic_url` scalar in the ticket's
`metadata.yaml` — and **never** by searching the tracker. `CLAIRE_ORG.md` §9: "already synced" is
decided from repo-owned state, never by reading mutable tracker state. Deriving it from a summary search
would let a human rename mint a second replacement, or a similarly-named issue hijack this one.

| Mode | Condition | Behavior |
|---|---|---|
| **replace** | `umbrella_epic_url` empty | Create `U`, set its Epic Link to `E`, move the ordered links, close the original, emit the binding |
| **converge** | set, and not this run's issue key | `U` already exists: **no create.** Re-assert `U`'s Epic Link if it is not `E`, converge the ordered links, retry the close |
| **settled** | set, and IS this run's issue key | The ticket already projects onto `U`. No create, no retire, no close — converge the ordered links only, so a **later-added** child still gets one |

**Existence is not lineage.** `converge` proves the bound issue is really there, which says *nothing* about
whether it carries its Epic Link to `E` — and `epic_link_unset` (below) leaves precisely that state behind
for this mode to inherit. So the **same read** that proves existence also reads `U`'s Epic Link and
**re-asserts** it when it is not `E`; a refusal returns non-zero, so the original is **not** closed and
`jira_url` is **not** re-pointed. Without this, run 2 closed the original over an umbrella with no parent
and reported a clean `epic_result=umbrella`, after which every later run read `U`'s empty Epic Link and took
the **single-level** branch — silently, forever. An already-correct link is left untouched, so a converged
re-run re-asserts nothing.

**`settled` is not optional bookkeeping.** Once `jira_url` names `U`, and `U` carries an Epic Link to
`E`, the umbrella branch is entered on **every** subsequent sync (the fork gates solely on the live Epic
Link). Without it the branch would treat `U` as its own original and retire the live umbrella every run.
The shared Epic Link arm still runs in this mode, but there is no lineage left to prove: its
comparison is **identical by construction** — `E` is `U`'s own live Epic Link, read from the same
field of the same issue moments earlier — so it issues no write absent a
**concurrent external mutation** landing between the two reads (`archive/BTG-105/decisions.md`
DEC-025). Stated here
affirmatively rather than left to be inferred from silence, so a claim-phrasing sweep can find it.

## Entering the branch

- **`syncjs.umbrella.epic_link_unreadable`** — the branch was reached but the Epic Link field id or its
  live value could not be read. **HALT the branch before any mutation**; never promote to Epic anyway,
  never guess `E` (Behavior 5).
- **`syncjs.umbrella.children_unreadable`** — `decomposed_into` is present and non-empty but is **not a
  sequence** (DEC-044). **HALT the branch before any mutation**: a shape the reader cannot interpret is
  not an absent child set.
- **`syncjs.umbrella.child_unresolved`** — a `decomposed_into` child has no `metadata.yaml` in this
  repo. The whole child set is resolved **before the first write**, so this costs nothing but a report.
- **`syncjs.umbrella.child_unprojected`** — a child has no `jira_url` yet. Not an error: its Epic Link
  is set on the run after it is first synced.
- **`syncjs.umbrella.scratch_unavailable`** (Warning) — no scratch file could be staged, so the write it
  was staged for is **refused** rather than degraded into a bodyless request a permissive server accepts.

## Creating the replacement (`js_umbrella_issue_ensure`)

- **The accepted project-key shape (BTG-166).** A replacement is only ever created in a project whose
  keys this adapter can use: an uppercase-alphanumeric project part (starting with a letter), a hyphen,
  then digits — `<PROJECT>-<number>` — the same shape `js_issue_key_valid` enforces at every
  interpolation site on this path. This is the shape **THIS ADAPTER accepts**, not a general definition
  of what a Jira issue key looks like. A project key outside it is **refused before any
  request is issued**: the refusal names the project key and the accepted shape, and nothing is created.
- **`syncjs.umbrella.issue_created`** — `U` was created at the configured umbrella type, naming its key.
  The key is read from the response's `.key` and **never computed** (PROD_CLAIRE-011: a value that was not
  really a key reached the wire and the run still reported success).
- **`syncjs.umbrella.issue_at_target`** — mode **converge**: a replacement is already recorded and the
  instance confirms it. **No second issue is created.** At most one replacement per ticket, ever. Its
  **detail text states which of the two converge outcomes occurred** — the Epic Link was *already
  correct and CONFIRMED, with no live write issued*, or it *was RE-ASSERTED by a live write, CONFIRMED
  by a read-back*. **No new condition name was added for this distinction**: a nineteenth name was
  considered and rejected for information this message already carries, so the audit stream tells a
  real convergence from a no-op without the vocabulary growing.
- **`syncjs.umbrella.at_replacement`** — mode **settled**: the ticket already projects onto its
  replacement, so nothing is created, retired or closed this run.
- **`syncjs.umbrella.binding_contradicted`** (Critical) — the repo records a replacement the instance
  answers **404** for, or one it could not read at all. A **contradiction**, not a state to reconcile:
  **fail loud, create nothing**. A 404 from a transient fault is indistinguishable from a genuine
  deletion, so re-creating would mint duplicates this adapter has no lock with which to detect. Resolve
  it by hand — clear `umbrella_epic_url` to authorise a new replacement, or restore the issue.
- **`syncjs.umbrella.title_absent`** — the repo title is empty, so the create is **refused**: a bare
  `[UMBRELLA] ` is never written and a title is never guessed. (The consequence changed at BTG-105: the
  predecessor merely skipped a summary write, whereas a create cannot proceed without a summary.)
- **`syncjs.umbrella.issue_body_unbuildable`** — the creation body could not be built, so **no POST is
  issued**. A build failure is the **adapter's**, never the instance's, so `issue_create_rejected` is
  **not** also reported (BTG-084).
- **`syncjs.umbrella.issue_create_rejected`** — reported from **four** distinct code paths in
  `js_umbrella_issue_ensure`, all under this one name:
  - **no project key resolves at all** for the ticket (pre-existing, config-class): nothing is created
    and no request is issued.
  - **the resolved project key cannot yield a usable issue key** (BTG-166's pre-flight probe,
    config-class): nothing is created and no request is issued; the refusal names the project key and
    the accepted shape.
  - the instance **refused** the create, or was unreachable — a genuine **non-2xx**. Nothing else was
    mutated: the create is the **first** write on the path, so a failure here costs nothing and a
    re-run retries it.
  - the instance answered **2xx** and **an issue was created**, but its key is not one this adapter can
    use — either the response carried **no key at all**, or it carried one this adapter's shape does
    not accept. Unlike the two arms above, an issue now **EXISTS**: no binding is recorded for it, and a
    re-run does **NOT** retry the create — it creates **another** issue. Resolve the created issue by
    hand.
- **`syncjs.umbrella.epic_link_unset`** (Critical) — `U` exists but its Epic Link to `E` could not be
  confirmed — the body could not be staged or built, the write was refused, or a 2xx did not land. `U`'s
  binding **is** still recorded (the issue EXISTS and must never be created twice), the original is
  **not** closed, and `jira_url` is **not** re-pointed, so the next run converges it in mode
  **converge**. The write carries the discovered custom field **only** — no `issuetype`. **The
  convergence is real, not asserted:** mode `converge` calls the same writer, so this condition fires
  again on the next run if the re-assertion is refused again, and the close stays blocked until the
  lineage is confirmed. It is emitted from **both** paths, the create and the re-assertion.
- **`syncjs.umbrella.epic_link_conflict`** — the recorded replacement `U` carries a **different**
  populated Epic Link than the top-level `E`. This is a human's **deliberate re-parent**, not drift, and
  it is never silently reversed. It is the umbrella-path analog of
  **`syncjs.umbrella.child_epic_link_conflict`** below, and the two agree **by construction**: the same
  non-empty test (including the literal string `null`, which Jira can return where a genuine absence is
  meant), the same run-mode polarity, and the old value named in both.
  - **interactive** (the default) ⇒ the link is **left untouched**, the conflict is reported naming the
    value found and the value not written, and the function returns non-zero — so the superseded
    original is **not** closed and `jira_url` is **not** re-pointed. The recorded binding is still
    emitted, so a re-run converges rather than minting a second replacement.

    The non-zero return also exits **before the ordered child-link loop**, so the children's
    `precedes ` links **stop converging too** while the conflict stands — not only the close and the
    url re-point. This is a **deliberate difference from the sibling child path**, which `continue`s
    its loop and reports `umbrella-partial`: the umbrella is a **singular** object, and continuing
    past an unresolved conflict would close the original over it. Resolve the conflict (or re-run
    headless) and the same run converges the children.
  - **headless** ⇒ the link is overwritten with `E` **deliberately**, confirmed by the same read-back
    every Epic Link write already carries.

  The predicate is **`js_run_mode`** and the variable NAME comes from the config's
  `run_mode.headless_env` binding — an absent binding is a **config HALT**, never a call-site default.
  An **empty** Epic Link is **not** a conflict: it is re-asserted exactly as before, which is the
  behaviour `epic_link_unset` above leaves behind for this arm to converge.

  **An operator who wants the old behaviour** on a re-parented umbrella sets the headless signal for
  that run. There is nothing to migrate ahead of time.

## Moving the children's ordered links

The ordering link type is **discovered from the instance** by outward/inward phrasing and used
**verbatim** — this org's is named `precedes ` **with a genuine trailing space**. Only the **far
endpoint** moves: the child stays the predecessor and the config's inversion calibration is unchanged.

- **`syncjs.umbrella.ordered_skipped`** — the child ordered link is skipped because the instance's link
  types were unreadable; the type is never guessed.
- **`syncjs.umbrella.child_linked`** / **`syncjs.umbrella.child_link_present`** /
  **`syncjs.umbrella.child_link_rejected`** — the outcome for one child against the **replacement**: the
  ordered link was created, was already present in the correct direction, or was refused.
- **`syncjs.umbrella.link_unverified`** — a child ordered link was created but the **post-create
  direction read-back** could not confirm it. A `201` is not proof: `POST /rest/api/2/issueLink` answers
  with an empty body, so the stored direction is recovered by re-reading the issue.
  *(Its siblings `syncjs.umbrella.direction_reversed` / `.direction_healed` / `.heal_incomplete` /
  `.type_undiscoverable` / `.type_fallback` come from the same shared ordered-link machinery as
  `jira-link.sh`, under the umbrella prefix.)*
- **`syncjs.umbrella.ordered_stale_unreadable`** — the original's `issuelinks` could not be read, so
  **no stale link is deleted on a guess**. Every child counts as unapplied and the original is not
  closed. An unreadable answer is not an empty one, and the delete is the one **irreversible** write on
  this path.
- **`syncjs.umbrella.ordered_retired`** — the stale ordered link between a child and the superseded
  original was deleted, **after** its replacement was verified. The child now carries exactly one
  ordering link. The link's id is **discovered** from a single snapshot read taken before the loop, and
  matched in **either** direction — a link a prior run created reversed must still be retired.
- **`syncjs.umbrella.ordered_dual_linked`** (Warning) — **create-before-delete's visible cost.** The new
  ordered link IS in place but removing the stale one was refused, so the child is linked to **both**.
  Never *unlinked*, only ever dual-linked: the replacement link is created and verified **first**, so no
  step can leave a pair with zero ordering links. It counts into the partial guard, which **blocks the
  close**, and the next run converges — the create reports up-to-date, the delete is retried against a
  freshly-read snapshot.
- **`syncjs.umbrella.at_target`** — the child already points at the top-level Epic `E`; left untouched.
  **Meaning unchanged by BTG-105:** the children's Epic Link target is `E` both before and after.
- **`syncjs.umbrella.child_epic_link_conflict`** — a child carries a **different** populated Epic Link
  (an anomaly). The signal accompanies the **deliberate** resolution, which the run-mode predicate
  decides, and is never a silent guess:
  - **interactive** (the default) ⇒ the child is **left untouched** and the conflict is reported for a
    human to resolve. The script issues **no prompt**: its stdout is the orchestrator's data channel, so
    "ask the human" here means *report and write nothing*, which is the fail-safe DEC-011 requires.
  - **headless** ⇒ the child's Epic Link is overwritten with `E`.

  The predicate itself is **`js_run_mode` in `.claude/skills/claire-sync-jira/jira-lib.sh`** (DEC-011): the
  run is headless **iff** the env variable named by the config's `run_mode.headless_env` binding is
  **truthy** (`1` / `true` / `yes`); absent, empty or falsey ⇒ interactive. The variable NAME is
  configuration, so an adopter may rebind it; an absent binding is a config HALT (exit 4), never a
  call-site default.
- **`syncjs.umbrella.child_epic_link_unreadable`** / **`syncjs.umbrella.child_epic_link_rejected`** /
  **`syncjs.umbrella.child_epic_link_unverified`** — the child Epic Link write's read, write, and
  mandatory read-back failures. The Epic Link is never written blind and a `2xx` is never taken as proof
  the field took the value.

The child Epic Link write points each child at **`E`, the top-level Epic — past the umbrella**, never at
the umbrella itself: the umbrella is a plain Issue, and a Jira Epic Link must target an Epic (BTG-036).
**BTG-105 leaves this write byte-unchanged**, which is why the board shape does not change.

## Retiring the original (`js_umbrella_original_close`)

The original is retired **by transition**, never by re-type and never by delete. Deleting it would
destroy the Epic Link, the projected worklogs and the changelog that are the evidence trail PROD_CLAIRE-014 and
BTG-103 both rest on. The close target is
`status_workflow_map[<the original's LIVE issue type>]["archived"]` — the terminal status this
configuration **already declares per issue type**, so **no new configuration key exists**. The live type
is read from the instance, never taken from the repo.

**No `issuetype` write is issued against the original at any point**, so the standing rule — *a status
is NEVER transitioned merely to force a type change* — holds **by construction**. Retiring a superseded
umbrella issue is a gate-ratified exception to BTG-040's *"an Epic's status is never touched"*: that
invariant is scoped to `.claude/skills/claire-sync-jira/jira-transition.sh`, which is untouched here, and
the original is not typed `Epic` in Jira.

- **`syncjs.umbrella.closed`** — the original was transitioned to its archived status, naming the
  transition id that was actually fired. Its type, its Epic Link and its summary are **unchanged**.
- **`syncjs.umbrella.close_at_target`** — already at the target; **no POST at all**. A human who closed
  it by hand reached the same state, and re-firing would re-run Jira's post-functions for nothing.
- **`syncjs.umbrella.close_unmapped`** — no `status_workflow_map` entry declares an `archived` status
  for the original's live issue type, so it has no close target on this instance. Left **open** and
  reported, rather than transitioned somewhere ungoverned.
- **`syncjs.umbrella.close_unreachable`** — no offered transition lands on the target and no
  `status_workflow_map.global_transitions` id is declared for it. **The offered set is named verbatim.**
  **No walk and no guess:** a collapsed transition set is exactly where a multi-hop walk wanders onto an
  ungoverned state, which is why `jira-transition.sh`'s walk is deliberately not reused. This is a live
  possibility precisely because these issues' transition sets are already collapsed — and it is benign,
  since the children already point at the replacement.
- **`syncjs.umbrella.close_rejected`** — the live read, the transitions read or the transition POST was
  refused by the **instance**. **No retry and no second POST**; the original stays open and a re-run
  resolves the id afresh. **Narrowed, never renamed** (BTG-157): it no longer covers this adapter's own
  scratch-staging or body-build failures, which are reported below under their own, adapter-origin names.
  Its meaning for every genuine instance outcome is unchanged, and it keeps firing for every one of them.
- **`syncjs.umbrella.close_body_unbuildable`** (Warning) — the close transition body could not be built
  by this adapter, so **no transition is issued** rather than the bodyless or malformed request a partial
  build degrades into. The adapter's own failure, named as its own: blaming the instance for a body this
  adapter built wrong is the misdiagnosis this distinction exists to prevent. Follows the shipped
  `<subject>_body_unbuildable` pattern (`issue_body_unbuildable`, `child_epic_link_body_unbuildable`).
- **`syncjs.umbrella.scratch_unavailable`** also fires on this path: the close body's scratch file could
  not be staged. Same name, same meaning as on the create path — see its entry above.
- **`syncjs.umbrella.close_unverified`** (Critical) — the transition returned 2xx but the **mandatory
  read-back** shows another status. PROD_CLAIRE-006's shape applied to status: verify *the thing that must be
  true afterwards*, never merely the field you sent.
- **`syncjs.umbrella.close_deferred`** — the child set was only partly applied, so the original is
  **not** closed and `jira_url` is **not** re-pointed. An issue is never retired while a child is
  stranded or dual-linked. A re-run converges the remainder and then retires the original.
- **`syncjs.umbrella.binding_deferred`** — the child set was whole but the close did not land, so
  `jira_url` still names the original and the branch will be re-entered to converge. The replacement
  **is** already recorded, so no second one is ever created. **It is carried on the machine channel
  too, as `epic_result=umbrella-unclosed`** — the close step's analogue of `umbrella-partial`, and for
  the same reason: the orchestrator parses the payload, never stderr, so a flat `umbrella` beside this
  condition would read as a **complete** projection. While the close does not land, `jira_url` never
  moves, so steps 1-8 keep writing the description, estimate, worklogs and assignee to the **superseded,
  link-stripped** original while the ordering links sit on `U` — a **split** projection. On an instance
  whose `global_transitions` target is not reachable from the original's current status this is not a
  transient state but the **steady** one, so it must be visible to the caller, not only to a reader of
  stderr.

## Completing

- **`syncjs.umbrella.partial`** — the child set was only PARTLY applied, with the applied and unapplied
  counts. A re-run converges the remainder, but only if the operator is told there IS a remainder. A
  failed link retire and an unreadable snapshot both count into it.
- **`syncjs.umbrella.projected`** — the umbrella branch completed, naming the replacement, `E`, the
  superseded original and the child counts.

## The repo-owned binding

`umbrella_epic_url` is emitted on **stdout** as soon as the replacement exists — even on a refusal that
leaves it unlinked — because the issue EXISTS and a run that dropped the binding would mint a second
replacement next time. `jira_url` is re-pointed **only** on full completion. That asymmetry is what
keeps a partial run **convergent** rather than stranded: it re-enters in mode **converge** and finishes
the job. The orchestrator is the sole **caller**; the dedicated writer script, `jira-metadata-write.sh`,
is the sole **writer** of `metadata.yaml` (BTG-125). This script only emits.

**Since BTG-125, an emitted binding is USUALLY a recorded one.** The orchestrator invokes
`jira-metadata-write.sh` a second time, early, the moment this script RETURNS with a non-empty
`umbrella_epic_url`, recording it ALONE — never a re-pointed `jira_url`, so the asymmetry above is
untouched. What remains discarded is narrower: a `key=value` line never reaches that early write if this
script itself halts before returning (a span that includes the child-link REST loop above). That is why
**every** config HALT (`exit 4`) on this path — including the ordered-link type discovery, which is a
*read* that halts on an absent binding — is resolved **before** the create: a halt standing after the
object-creating `POST` and before this script returns still risks a fresh orphan umbrella issue on the
next run, because the early write records what this script emits, not what happens inside it. The create
is the **first mutation**, and nothing that can halt stands behind it.
