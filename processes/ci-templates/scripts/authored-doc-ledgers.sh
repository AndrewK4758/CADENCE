#!/usr/bin/env bash
#
# authored-doc-ledgers.sh -- the ledgers ci-templates/scripts/authored-doc-gate.sh
# consults (BTG-191).
#
# Bounded context: Build tooling / compile-gate flow. Split out of
# authored-doc-gate.sh along the same real seam dead-citation-ledgers.sh was
# split from dead-citation-gate.sh: that file is the CLASSIFIER (what counts as a
# violation), this one is the LEDGERS (what the project has decided is a RECORD
# rather than an expectation, and on what terms). Keeping them in one file would
# put the classifier past the <400-line DX ceiling every named gate script here
# respects.
#
# SOURCED, never executed. It defines arrays only -- no function, no side effect,
# no `set` change -- so a harness may source it without perturbing its own shell.
#
# THE ROW GRAMMAR IS THE SAME IN ALL THREE LEDGERS, deliberately:
#
#     <repo-relative-path>|<anchor substring>|<reason>
#
# and an exemption matches only when the offending line CONTAINS its anchor. A
# path-wide or empty anchor would excuse every future line of a growing file --
# the shape PROD_CLAIRE-020 records going quietly blind, and the reason
# BTG176_MCP_KEY_LEDGER carries THREE rows for one release note rather than one.
# The gate refuses such a row by name (seam
# authoreddoc.disposition.unledgered_site), so the rule is enforced rather than
# merely stated.
#
# WHY THE LEDGERS LIVE HERE AND NOT BESIDE THEIR HARNESSES. Before BTG-191 each
# predicate lived inside the harness that consumed it, and its ledger beside it,
# so the only way to disposition a violation was to edit a harness. The gate is
# now the single predicate home with three callers (the authoring steps, the
# run-gates.sh row, and the harnesses), which means one ledger reachable from all
# three. `ci-templates/scripts/tests/` does not ship to adopters (it is a
# framework_dev path in artifacts/footprint.generated), so a ledger the SHIPPED
# gate must read cannot live under it.
#
# References: archive/BTG-191/{spec,test-plan,decisions}.md ;
#             ci-templates/scripts/dead-citation-ledgers.sh (the shape copied).

# ======================================================================
# LEDGER 1 -- MCP server keys named but absent from artifacts/mcp/mcp.manifest
# ======================================================================
#
# MOVED HERE FROM ci-templates/scripts/tests/btg-176-lib/mcp-manifest.sh, byte
# for byte, by BTG-191. The array keeps its name so every existing consumer
# reads the same rows it always did; that file now sources this one.
# THE SWEEP IS WIDER THAN "FILES THAT READ THE MANIFEST", deliberately. A
# consumer that names the key without ever opening the manifest -- a rendered
# golden fixture, a registry row, a harness assertion -- is exactly as dangling,
# and is the shape that survives a narrower sweep. So every non-comment line
# under the shipping and governance roots is swept, and each surviving
# occurrence must carry a LEDGER ROW naming why it is a record rather than an
# expectation. `archive/` and `specs/` are outside the sweep by rule: they are
# the historical record of the change, and a record that could not name the
# thing it removed would be useless.
BTG176_MCP_KEY_LEDGER=(
  'docs/policies/claire-surfaces.md|the `claire-mcp-youtrack` remote-http row|the two registered surface rows RECORD the removal by name. A registry that could not name what it retired would leave an adopter unable to tell a removal from an omission'
  'ci-templates/scripts/tests/btg-176-lib/structural.sh|claire-mcp-youtrack|S-1.2 sweeps the shipped adapter for any surviving MCP identifier -- an ABSENCE assertion, so the key appears as the needle it searches for and never as an expectation'
  'ci-templates/scripts/tests/btg-176-lib/surface.sh|claire-mcp-youtrack|S-1.1 asserts the skill body no longer names the MCP server registration -- the same absence shape as the row above'
  'ci-templates/scripts/tests/btg-176-lib/mcp-manifest.sh|claire-mcp-youtrack|this scenario and its ledger; the sweep must be able to name its own subject'
  'ci-templates/scripts/tests/btg-176-lib/mcp-consumers.sh|claire-mcp-youtrack|S-16.5 and S-16.6 assert that no re-founded sibling still names the removed row OUTSIDE A COMMENT -- the key is the needle those absence checks search for'
  'ci-templates/scripts/tests/btg-176-lib/record.sh|claire-mcp-youtrack|S-7.1 and S-7.2 read the manifest to decide whether the row is ABSENT or PRESENT-with-a-reason; the key is the subject of that question, and both branches are asserted'
  'docs/ADR/0024-mcp-manifest-supports-an-additive-remote-http-transport-form.md|`claire-mcp-youtrack` row from `artifacts/mcp/mcp.manifest`|the superseded ADR names the consumer it LOST. A supersession that could not say which row went would leave a reader unable to check the claim'
  'docs/migrations/youtrack-mcp-registration-removal.md|claire-mcp-youtrack|the migration note RECORDS the removal for adopters and names the key they must retire. A migration note that could not name the registration being withdrawn would leave an adopter unable to find the entry in their own runtime config -- the same record-not-expectation shape as the registry and superseded-ADR rows above'
  'docs/agentic-sdlc/intent-insights.md|claire-mcp-youtrack|the promoted intent insight RECORDS what this ticket removed and why. An append-only discovery register that could not name its own subject would record nothing checkable -- the same record-not-expectation shape as the rows above'
  # --- the release note for the version that shipped the removal (BTG-190) ---
  #
  # THREE ROWS, NOT ONE PER FILE. The three occurrences are three different
  # statements, so each is anchored on its own sentence: a file-wide anchor here
  # would excuse every future line of a release note that is still being read by
  # adopters, which is the blind spot this ledger exists to remove.
  'docs/releases/v4.0.10.md|the `claire-mcp-youtrack` registration is removed|the release headline RECORDS what v4.0.10 shipped. A release note that could not name the registration it withdrew would leave an adopter unable to tell a removal from an omission -- the same record-not-expectation shape as the registry, superseded-ADR and migration-note rows above'
  'docs/releases/v4.0.10.md|MCP registration is removed (BTG-176)|the Breaking Changes entry RECORDS the removal against the ticket that made it; the key is the subject of the breaking change being declared, not an expectation that the row exists'
  'docs/releases/v4.0.10.md|retire it with `/upgrade-claire`|the upgrade instruction tells an adopter which entry to retire from their OWN runtime config. This one cannot be genericised at all: an adopter who is not told the key cannot find the registration to remove'
  'ci-templates/scripts/tests/youtrack-mcp.test.sh|key=claire-mcp-youtrack transport=http|SYNTHETIC fixtures built by mk_two_row_manifest and its siblings. That harness was RE-FOUNDED as the remote-http transport-FORM harness (DEC-053 R-3): its rows are written into mktemp manifests it owns, so they exercise the engine and assert nothing about the shipped manifest'
  'ci-templates/scripts/tests/youtrack-mcp.test.sh|"claire-mcp-youtrack"|the round-trip assertions over those same synthetic manifests -- same reason as the row above'
  # --- the one row BTG-191's relocation of this ledger makes necessary ---
  #
  # The array above now LIVES in ci-templates/scripts/authored-doc-ledgers.sh,
  # which is inside `ci-templates` -- one of the four roots this predicate
  # sweeps. A ledger must be able to name its own subject, exactly as the
  # btg-176-lib rows above are excused for naming theirs. Anchored on the key
  # itself, which is what those sibling rows anchor on too.
  'ci-templates/scripts/authored-doc-ledgers.sh|claire-mcp-youtrack|this file IS the ledger; every row above names the removed key as the needle it searches for, never as an expectation. Same record-not-expectation shape as the btg-176-lib rows it was moved from, at its new address (BTG-191)'
)

# The GATE's ledger is a SUPERSET of the array above, not a replacement for it.
#
# Two reasons, both measured rather than assumed:
#
#   1. The array above is consumed by btg-176's own S-16.8, whose dead-row check
#      asserts that every one of its rows still resolves. Adding rows there that
#      that scenario never contemplated would silently widen its subject; adding
#      them here leaves it asserting exactly what it was written to assert.
#   2. The gate's needle is WIDER than that harness's. btg-176 sweeps for ONE key
#      by name -- the row its own ticket removed. The gate reads the manifest's
#      documented ownership grammar instead (`key=<server-key>` MUST start
#      `claire-`; artifacts/mcp/mcp.manifest states it as the classifier's
#      sentinel) and reports any `claire-mcp-*` key the manifest does not
#      carry, so a FUTURE removal is covered on the day it lands with no edit
#      here. A per-key needle would have to be edited every time, which is the
#      hand-maintained denylist the Simplicity facet names as an anti-pattern.
#
# Widening the needle surfaced FIVE further occurrences inside the gate's scan
# scope, every one of them a RECORD of BTG-075's removal of
# `claire-mcp-atlassian`. They were found by RUNNING the widened predicate over
# the committed corpus, not predicted: three registry/registry-note lines and two
# lines of the release note for the version that shipped the removal.
#
# Each is anchored on its OWN sentence, never on its file. Two of the three files
# are registries that gain a row per ticket and the third is a release note
# adopters still read; a path anchor on any of them would excuse every line those
# files ever gain -- the PROD_CLAIRE-020 shape this ledger's own grammar forbids.
ADG_MCP_KEY_LEDGER=(
  "${BTG176_MCP_KEY_LEDGER[@]}"
  'docs/policies/claire-surfaces.md|the `claire-mcp-atlassian` row is deleted from|the /claire-sync-jira registry row RECORDS the BTG-075 removal as an adopter-visible consequence. A registry that could not name what it retired leaves an adopter unable to tell a removal from an omission -- the same reason its `claire-mcp-youtrack` sibling row above is excused'
  'docs/policies/claire-surfaces.md|the `claire-mcp-atlassian` docker row was REMOVED from|the MCP-manifest registry row RECORDS the same removal against the ticket that made it. A SECOND row rather than a wider anchor on the first: these are two different statements on two different lines, and one anchor spanning both would be a file-wide excuse in all but name'
  'docs/policies/surface-registry.md|the existing `claire-mcp-atlassian` **docker row is byte-unchanged**|the adopter-owned registry RECORDS the state of the docker row at the point BTG-059 added the remote-http form. The claim is only checkable because it names the row it is about'
  'docs/releases/v4.0.5.md|BTG-075 removes the `claire-mcp-atlassian` row from|v4.0.5 is the release that SHIPPED the removal, and its notes are an immutable record of what shipped (BTG-190 DEC-006). The sanctioned disposition for a release note that trips a guard is a ledger row, never an edit to the note'
  'docs/releases/v4.0.5.md|**`claire-mcp-atlassian` is removed from|the Breaking Changes entry of that same release note. Its own row, on its own sentence: a release note is read top to bottom by adopters and each statement is separately load-bearing, which is why the youtrack ledger above carries THREE rows for one file rather than one'
)

# ======================================================================
# LEDGER 2 -- restatements of the DX file-length measure
# ======================================================================
#
# MOVED HERE FROM ci-templates/scripts/tests/btg-090-dx-measure-scope.test.sh,
# byte for byte, by BTG-191. All three arrays keep their names, so every scenario
# in that harness reads exactly the rows it always did; that file now sources
# this one.
#
# WHY THE MEASURE NEEDS A LEDGER AT ALL. Every hit the sweep reaches must resolve
# to exactly one of:
#   (a) an ENUMERATED operative representation -- a path in REPS, a site that
#       states the measure as a rule its reader is governed by NOW; or
#   (b) a DATED PROVENANCE site -- a comment recording WHY a past split happened,
#       exempted by an anchor on its own text; or
#   (c) a NON-MEASURE false positive -- a line the sweep's pattern reaches that
#       is not a statement of the file-size measure at all.
# Anything else fails, naming the path. A fixed list of sites is what failed at
# PI-037: its changelog claimed the 300 -> 400 raise was "updated consistently
# across every living policy statement" and four operative sites still carried
# 300, two of them registered Stable surfaces.

# The 12 operative representations of the file-size measure, enumerated in
# spec.md's Compatibility Impact. BTG-198 swapped CLAUDE.md -> CLAIRE_DIRECTIVES.md
# (count unchanged): the measure MOVED with the shipped directive content when
# CLAUDE.md became adopter-owned, and an enumeration that stayed pointed at the old
# home would match nothing over a scan set holding an enumerated representation --
# leaving every later verdict from this predicate vacuous (Risk R-7). "Operative" means the site states the measure
# as a rule its reader is governed by NOW -- as distinct from a dated provenance
# comment recording why a past split happened, which DEC-006 exempts by an
# attributed criterion (see the exemption ledger under S-3.3).
REPS=(
  "docs/agentic-sdlc/CLAIRE_ORG.md"
  "CLAIRE_DIRECTIVES.md"
  "docs/agentic-sdlc/scout-reference.md"
  "docs/agentic-sdlc/CLAIRE_ORG_TEMPLATE.md"
  "specs/TEMPLATE/spec.md"
  "specs/CLAIRE.md"
  "artifacts/roles/claire-spec-author.md"
  "artifacts/roles/claire-reviewer.md"
  ".claude/agents/claire-spec-author/AGENT.md"
  ".claude/agents/claire-reviewer/AGENT.md"
  "ci-templates/scripts/tests/fixtures/opencode-golden/.opencode/agents/claire-spec-author.md"
  "ci-templates/scripts/tests/fixtures/opencode-golden/.opencode/agents/claire-reviewer.md"
)


# Dated-provenance exemptions. Authority: BTG-090 DEC-006 -- a comment recording
# WHY a past split happened is not a statement of the current rule, and
# rewriting it to 400 would make it FALSE about a split performed under the
# 300-era rule. Residue owned by BTG-149.
#
# Each entry anchors on a distinctive fragment of the ONE comment it excuses, so
# an exemption cannot silently widen: no entry is a path, a file name or a
# directory, and S-3.3 asserts that mechanically. One anchor covers a site and
# its two generated mirrors, because all three carry byte-identical text -- that
# is one site expressed in three trees, not three sites.
PROVENANCE_ANCHORS=(
  "<300-line cap (DEC-005). Returns the helper's status"
  "<300-line target -- the PI-014/PI-023 split precedent"
  "AC-3 dry-run finisher (DEC-005): keeps the entry point under the DX <300-line"
  "Moved here from jira-worklog.sh so that file stays inside the DX <400-line"
  "against the PI-037 400-line ceiling, under the 40-line target DEC-005 sets"
  "and both under the DX <300-line target; it is sourced below"
  "correct scan (spec.md R4) does not fit under the 400-line ceiling"
  "entry point stays under the DX <300-line target. This is a BEHAVIOR-PRESERVING"
  "out to keep both halves inside the <400-line DX ceiling"
  "Extracted here (the entry point stays under the <300-line DX"
  "single coherent concern and both stay under the DX <300-line target"
  "the DX <300-line target. BEHAVIOR-PRESERVING extraction: the functions move"
  "under the DX <300-line target). They run in this shell's scope"
  "upgrade-claire.sh under the DX <300-line cap (DEC-005). Args:"
  "loop, PI-031 R-1, to keep upgrade-claire.sh under the 300-line DX target"
  "The guard shares this line to stay net-zero against the 400-line ceiling"
  "past the DX <400-line ceiling, triggering the"
  "signal to split it — the DX facet's <400-line ceiling"
  "relocated under the 400-line ceiling and are documented under their new homes"
  "It moved from \`jira-meta.sh\` under the 400-line ceiling"
  "They moved from \`jira-meta.sh\` under the 400-line ceiling"
  "Every authored file < 400 lines, agent reads"
  "The per-file size ceiling FAILS CLOSED (BTG-043)"
  "DX line ceiling (BTG-075 blocking 11; the same split"
  # This change's own registry Notes. They RECORD the modification of two Stable
  # surfaces; they do not state the rule. Anchored on each row's own Note text,
  # not on the registry file, so a later un-attributed edit to the same file is
  # still caught.
  "step 10c's file-size question became CLASS-AWARE"
  "the file-size question MOVED from the Simplicity bullet"
  # ADR_CLAIRE-0061's Context section restates the pre-change ceiling to explain the
  # problem it records a decision about. Archival-time site (this ADR did not
  # exist when the ticket was authored): it is not one of the 12 operative
  # representations of the CURRENT rule and does not restate it as live policy
  # -- an ADR is a historical decision record, same status as the dated-
  # provenance comments above, not a carrier this change must keep reconciled.
  "states a single \`<400 lines\` whole-file ceiling for \"agent/skill"
  # v4.0.8's release note RESTATES the pre-change measure in order to describe the
  # change BTG-090 made to it. Archival-time site, the same status as ADR_CLAIRE-0061's
  # Context above: a release note is a dated record of what one version shipped,
  # not a carrier of the current rule, and it is not one of the operative
  # representations this sweep keeps reconciled. The statement was CHECKED against
  # the current rule and is accurate -- the sentence goes on to state the
  # per-function governance that replaced it -- so it is recorded, never rewritten
  # (BTG-190, DEC-006). Anchored on its own sentence, never on the file: the
  # release-notes directory keeps growing and a path anchor would excuse all of it.
  "Facet 3's \`<400 lines\` measure applied to"
  # BTG-168's extraction comment in jira-write-issue.sh, recording WHY the
  # screen-availability concern was relocated. A dated-provenance comment of
  # exactly the class DEC-006 authorises -- it explains a past split, it does not
  # state the current rule. ONE anchor covers all three trees (neutral source and
  # both generated mirrors carry the text byte-identically), per this ledger's own
  # one-site-three-trees rule above.
  #
  # It was MASKED, not absent: S-3.2 breaks on its first offender, so it could not
  # surface until the v4.0.8 site above was dispositioned (BTG-190, DEC-006).
  "Relocated for the same 400-line ceiling, and independently"
  # BTG-311's core_commit_for_version extraction: two dated-provenance comments
  # (upgrade-bootstrap.sh's own new source-guard comment for upgrade-resolve.sh,
  # and the new sidecar upgrade-resolve.sh's own header) recording WHY the
  # version-to-commit resolution concern moved to a colocated sidecar
  # (upgrade-bootstrap.sh was at 387/400, the same DX-ceiling trigger BTG-020
  # DEC-002 already documents for upgrade-collect.sh). upgrade-bootstrap.sh's
  # PRE-EXISTING BTG-020-era "Holds:" paragraph and its own source-guard comment
  # for upgrade-collect.sh are deliberately left BYTE-UNCHANGED (not merged into
  # BTG-311's edit) precisely so this ledger's site count is not perturbed by a
  # wording change to an already-anchored site; the now-stale "core_commit_for_
  # version" mention inside that frozen paragraph is reconciled by a SEPARATE,
  # newly-added "UPDATE (BTG-311, DEC-006)" paragraph immediately below it,
  # which states no digit-bearing measure and so trips no predicate here.
  "(BTG-311, DEC-006), extracted for the same DX <400-line reason and sourced"
  "module holds a single coherent concern and both stay under the DX <400-line"
  # BTG-332 code-review cycle 3 B3: upgrade-vocab.sh (423 lines) was over the
  # ceiling. Three dated-provenance comments record WHY the DEC-033/DEC-036
  # reference-swap concern moved to a new colocated sidecar, upgrade-vocab-ref.sh
  # -- upgrade-vocab.sh's own split-marker comment, upgrade-claire.sh's new
  # source-guard comment for the sidecar, and the new sidecar's own header. Each
  # anchor covers its one site in all three trees (neutral source, the compiled
  # Claude mirror, and the OpenCode golden mirror carry the text byte-identically).
  "the PI-037 400-line ceiling). vocab_ref_validate_core / vocab_ref_classify"
  "swap, split out of upgrade-vocab.sh to stay under the PI-037 400-line"
  "the PI-037 400-line DX ceiling). A colocated sidecar module shipped by the"
)

# Hits the sweep's pattern reaches that are NOT statements of the file-size
# measure at all. Kept in their OWN list rather than folded into the provenance
# ledger above: calling a false positive "dated provenance" would misrepresent
# what was excused, and the two categories are audited differently.
NON_MEASURE_ANCHORS=(
  "Config lines to add capability (<100)"
  "**Arguments** are long-form"
)

# ======================================================================
# LEDGER 3 -- org-specific project tokens in paths that ship
# ======================================================================
#
# THE ROWS ARE NOT HERE. They are DATA, and they live in
# ci-templates/scripts/authored-doc-exemptions.txt, which `/claire-adopt`
# copies with its rows stripped and `/claire-upgrade` excludes from merges.
#
# WHY, stated where the rows used to be so the next reader does not put them
# back. Every row of this ledger names a path in THIS repository and quotes a
# phrase from THIS repository's history, including live project keys whose
# citation is their evidentiary value. This file SHIPS -- it is one of four gate
# files in COPY_PATHS -- so rows carried here would have shipped those keys into
# every adopting repository. Nothing would have caught it: the gate derives its
# scan scope from the footprint descriptor, which classes `ci-templates` as
# framework-development and enumerates nothing beneath it, so the guard was blind
# to its own leak. Code review cycle 1, blocking B-1.
#
# The other two ledgers above stay here because they are FRAMEWORK data: they
# describe the framework's own documents and carry no organisation-specific
# literal. The split is by ownership, not by size.
#
# AN ABSENT OR EMPTY LEDGER IS SAFE, and safe in the right direction: the array
# is then empty, nothing is excused, and the gate reports MORE rather than less.
# A fail-open here would be an exemption ledger that silently grew to cover
# everything, which is the opposite of what it is for.
ADG_EXEMPTIONS_FILE="${ADG_EXEMPTIONS_FILE:-$(dirname "${BASH_SOURCE[0]}")/authored-doc-exemptions.txt}"
# ...and it is part of the delivered set the sweep excludes: it is the gate's own
# data, not a document automation writes. Recorded beside its resolution so the
# two cannot disagree.
ADG_OWN_FILES="${ADG_OWN_FILES:-} $(basename "$ADG_EXEMPTIONS_FILE")"

BTG095_EXEMPTIONS=()
if [ -r "$ADG_EXEMPTIONS_FILE" ]; then
  while IFS= read -r adg_row; do
    case "$adg_row" in ''|'#'*) continue ;; esac
    BTG095_EXEMPTIONS+=("$adg_row")
  done < "$ADG_EXEMPTIONS_FILE"
  unset adg_row
fi
