#!/usr/bin/env bash
#
# context-block.sh -- the always-sidecar context-wiring concern of
# adopt-cadence (BTG-198). Co-located sidecar module, sourced by
# adopt-cadence.sh in its shell scope so SRC/DST and the note_* helpers resolve
# as in the entry point.
#
# Bounded context: adopt-cadence install flow (co-located layout). Writes ONLY
# the adopter target repo's root context file (CLAUDE.md) and the framework-owned
# directive sidecar beside it.
#
# Invariant relied on from outside this boundary: CLAUDE.md is categorically
# ADOPTER-OWNED (footprint kind=seed; excluded from the /cadence-upgrade merge
# set), and CADENCE_DIRECTIVES.md is framework-owned (footprint kind=installed;
# the merged row). Nothing here may overwrite the adopter's own directives:
# every framework write into CLAUDE.md happens inside the marker-fenced managed
# block below, and nowhere else.
#
# Upstream: called unconditionally by adopt-cadence.sh after
#   provision_generated_artifacts and before the verify loop. Downstream: copies
#   <src>/CADENCE_DIRECTIVES.md into the target and read-modify-writes
#   <target>/CLAUDE.md.
# Spec: archive/BTG-198/spec.md (Proposed Design, Install layer); decisions.md
#       DEC-004 (the sidecar name), DEC-005 (this repo splits too), DEC-014
#       (delegate the write to managed-block.sh).

# The shared marker-fenced writer (BTG-198 DEC-014). Sourced from beside this
# module; the guard makes the double-source (gitignore-block.sh sources it too)
# harmless.
# shellcheck source=/dev/null
[[ -n "${MANAGED_BLOCK_SOURCED:-}" ]] || . "$(dirname "${BASH_SOURCE[0]}")/managed-block.sh"

# The REGISTERED context managed-block marker contract (spec.md New Public
# Surfaces; docs/policies/cadence-surfaces.md). HTML comments, not `#` comments:
# CLAUDE.md is Markdown and a line beginning `# >>>` renders as an H1 heading.
# Changing this text ORPHANS every existing block, exactly as the .gitignore pair
# does -- so it is a stability guarantee, not an implementation detail.
CONTEXT_BEGIN='<!-- >>> CADENCE directives (managed by /adopt-cadence) >>> -->'
CONTEXT_END='<!-- <<< CADENCE directives <<< -->'

# The framework-owned directive sidecar and the adopter-owned context file.
# The FILENAMES are deliberately literal, not neutralized (BTG-198 OQ-1, resolved
# at the spec-approval gate 2026-09-02: keep the CLAUDE.md literal, neutralize
# only the include DIRECTIVE). Only the include primitive itself is adapter-bound,
# through the sanctioned context-import placeholder used below (the token form is
# described in ci-templates/scripts/neutral-vocabulary.sh, not reproduced in this
# comment -- writing it here would make the compiler expand the prose too).
CONTEXT_SIDECAR='CADENCE_DIRECTIVES.md'
CONTEXT_FILE='CLAUDE.md'

# Set by write_context_wiring to "stub" | "written" | "replaced" -- the three
# branches of the adopt.context.block_action decision seam. "stub" means the
# target had no context file and one was generated; "written"/"replaced" come
# straight from MANAGED_BLOCK_ACTION.
CONTEXT_ACTION=""

# Structured seam emitter, one parseable line on stderr, in the repo-wide
# `SEAM seam_type=... event_name=... detail=...` grammar (compile-util.sh). It is
# defined LOCALLY rather than sourced because the shared emit_seam is not in
# scope at this point in adoption -- the same reason adopt-provision.sh states
# for its own MCP-seam guard.
context_emit_seam() {
  echo "SEAM seam_type=$1 event_name=$2 detail=$3" >&2
}

# The ONE explanatory sentence required by AC-1/AC-2, emitted verbatim into both
# the generated stub and the managed block so there is a single definition of it.
_context_sentence() {
  cat <<'SENTENCE'
The line above imports the framework-owned CADENCE directives from
CADENCE_DIRECTIVES.md; everything else in this file is yours, and CADENCE
never edits it.
SENTENCE
}

# The managed block body, markers included, written to stdout. The import line
# carries the compile-time context-import placeholder (BTG-198 DEC-012): neutral
# source names NO concrete include primitive, and the bound adapter expands it
# into that runtime's include directive at compile time.
_context_block_body() {
  printf '%s\n' "$CONTEXT_BEGIN"
  printf '%s\n' "@CADENCE_DIRECTIVES.md"
  printf '\n'
  _context_sentence
  printf '%s\n' "$CONTEXT_END"
}

# The generated adopter-owned stub, written to stdout. The import line is the
# FIRST line of the file (AC-1 Rules), followed by the one explanatory sentence
# and a short adopter-owned heading. The stub carries NO markers: it is the
# adopter's file from the moment it is written, and a later re-adopt appends the
# managed block (the "written" branch) so the wiring becomes framework-managed
# without ever rewriting a line the adopter authored.
_context_stub_body() {
  printf '%s\n' "@CADENCE_DIRECTIVES.md"
  printf '\n'
  _context_sentence
  printf '\n'
  printf '%s\n' "# Project Context"
  printf '\n'
  printf '%s\n' "Record this project's architecture, domain model, conventions and standing"
  printf '%s\n' "agent instructions below."
}

# write_context_wiring <src> <dst>
#   <src>  framework-source root (holds the sidecar the COPY_PATHS loop installs).
#   <dst>  adopter target repo root.
# VERIFIES the sidecar landed, then wires the context file: absent -> generate
# the stub; present -> write/replace the managed block. Sets CONTEXT_ACTION.
# Returns 0 on success, non-zero with a loud stderr refusal on any failure
# (II-014: never report success past a requested deliverable), leaving no
# partial context file.
#
# It does NOT install the sidecar. CADENCE_DIRECTIVES.md is an ordinary
# framework-owned COPY_PATHS entry -- that single delivery mechanism is what
# eject-footprint.sh walks to derive its `kind=installed` row, so the entry
# cannot move here without a bespoke footprint echo. Installing it in BOTH
# places is what code review cycle 1 caught (blocking #2): the COPY_PATHS loop
# always runs first, so a second installer here could only ever report
# `skip (exists): CADENCE_DIRECTIVES.md` -- on a virgin adopt into an empty
# directory, an "already present" line naming a file that same run created.
# That is the exact routine-looking transcript line problem.md holds
# responsible for hiding the original total failure, and Data Integrity's audit
# measure here is ONE truthful line per file. Asserted by scenario S-1.5.
write_context_wiring() {
  local src="$1" dst="$2"
  local ctx="$dst/$CONTEXT_FILE"
  CONTEXT_ACTION=""

  # The sidecar must exist in the framework source AND have landed in the
  # target. The COPY_PATHS loop already fails loud on the first and copies for
  # the second, but this module is called unconditionally and DISTRUSTS that
  # loop rather than assuming it ran -- checking, never re-installing.
  if [[ ! -f "$src/$CONTEXT_SIDECAR" ]]; then
    echo >&2
    echo "ERROR: missing in source: $CONTEXT_SIDECAR" >&2
    echo "Adoption aborted -- refusing to report success without the CADENCE directives sidecar (II-014)." >&2
    return 1
  fi
  if [[ ! -f "$dst/$CONTEXT_SIDECAR" ]]; then
    echo >&2
    context_emit_seam DELTA_AUDIT_GAP adopt.context.sidecar_missing "$dst/$CONTEXT_SIDECAR"
    echo "ERROR: $CONTEXT_SIDECAR is not in the target after the framework copy: $dst/$CONTEXT_SIDECAR" >&2
    echo "Adoption aborted -- refusing to report success without the CADENCE directives sidecar (II-014)." >&2
    return 1
  fi

  # >>> BTG-198 context-pathtype-anchor-start: PATH-TYPE REFUSAL >>>
  # A directory (or any non-regular entry) at the context path cannot be wired.
  # Refuse LOUDLY rather than appending into it -- UNSOUND_CONDITION
  # adopt.context.target_not_writable. The S-1.4 standing guard strips exactly
  # this region from a throwaway engine COPY (a marker-anchored sed delete, never
  # line numbers, never against the tree) and proves the path-type refusal stops
  # coming -- i.e. that this branch is the discriminating cause of S-1.4 passing.
  # The delete leaves valid bash that falls through to the block path.
  if [[ -e "$ctx" && ! -f "$ctx" ]]; then
    echo >&2
    context_emit_seam UNSOUND_CONDITION adopt.context.target_not_writable "$ctx"
    echo "ERROR: $CONTEXT_FILE exists in the target but is not a regular file: $ctx" >&2
    echo "Adoption aborted -- refusing to write the CADENCE directives block into an unusable path (II-014)." >&2
    return 1
  fi
  # <<< BTG-198 context-pathtype-anchor-end: PATH-TYPE REFUSAL <<<

  if [[ ! -e "$ctx" ]]; then
    local tmp; tmp="$(mktemp)" || return 1
    if ! _context_stub_body > "$tmp" || ! mv "$tmp" "$ctx"; then
      rm -f "$tmp"
      echo >&2
      context_emit_seam UNSOUND_CONDITION adopt.context.target_not_writable "$ctx"
      echo "ERROR: could not write the generated $CONTEXT_FILE context stub ($ctx)." >&2
      echo "Adoption aborted -- refusing to report success without the CADENCE directives wiring (II-014)." >&2
      return 1
    fi
    CONTEXT_ACTION="stub"
    note_copied "$CONTEXT_FILE (context stub, generated)"
  else
    local block; block="$(mktemp)" || return 1
    _context_block_body > "$block"
    MANAGED_BLOCK_DELIVERABLE="CADENCE directives block"
    if ! write_managed_block "$ctx" "$CONTEXT_BEGIN" "$CONTEXT_END" "$block"; then
      rm -f "$block"
      # Name the seam for THIS bounded context. The shared writer stays
      # marker-agnostic and reports only a reason, so the two callers can emit
      # adopt.context.* and adopt.gitignore.* without it knowing either.
      case "$MANAGED_BLOCK_ERROR" in
        unterminated) context_emit_seam UNSOUND_CONDITION adopt.context.unterminated_block "$ctx" ;;
        *)            context_emit_seam UNSOUND_CONDITION adopt.context.target_not_writable "$ctx" ;;
      esac
      return 1
    fi
    rm -f "$block"
    CONTEXT_ACTION="$MANAGED_BLOCK_ACTION"
    note_copied "$CONTEXT_FILE (CADENCE directives block $CONTEXT_ACTION)"
  fi

  # RULE_DIVERGENCE adopt.context.block_action -- emitted on EVERY run with the
  # branch taken, so the branch distribution is observable. Baseline (spec.md):
  # "stub" on a fresh adopt, "replaced" on every re-adopt; a "written" on a repo
  # that has adopted before means the markers were not recognized, which is the
  # CRLF hazard R-4.
  context_emit_seam RULE_DIVERGENCE adopt.context.block_action "$CONTEXT_ACTION"
  return 0
}

# verify_context_wiring <dst>
# Post-adopt assertion, run after every wiring path and BEFORE the generic
# missing-paths verify loop so an undeliverable context file is NAMED rather than
# folded into a generic "something is missing" list (JI-6). Mirrors the PI-034
# adopt.gitignore.block_missing post-condition but is UNCONDITIONAL: the context
# wiring is never an opt-in deliverable, so there is no flag to gate it on.
#
# Predicate (the requester's settled one): the sidecar is present AND the import
# line is present in the context file. On the block branches the open marker must
# be present too -- the generated stub deliberately carries none, so requiring a
# marker unconditionally would refuse the fresh-adopt path it is meant to protect.
# Returns 0 when the wiring is intact, non-zero with a named seam otherwise.
verify_context_wiring() {
  local dst="$1"
  if [[ ! -f "$dst/$CONTEXT_SIDECAR" ]]; then
    context_emit_seam DELTA_AUDIT_GAP adopt.context.sidecar_missing "$dst/$CONTEXT_SIDECAR"
    echo >&2
    echo "ERROR: $CONTEXT_SIDECAR is absent from $dst after adoption." >&2
    echo "Adoption aborted -- refusing to report success without the CADENCE directives sidecar (II-014)." >&2
    return 1
  fi
  if [[ ! -f "$dst/$CONTEXT_FILE" ]] || ! grep -qFx "@CADENCE_DIRECTIVES.md" "$dst/$CONTEXT_FILE"; then
    context_emit_seam DELTA_AUDIT_GAP adopt.context.block_missing "$dst/$CONTEXT_FILE"
    echo >&2
    echo "ERROR: $dst/$CONTEXT_FILE does not import $CONTEXT_SIDECAR after adoption." >&2
    echo "Adoption aborted -- refusing to report success with the CADENCE directives unwired (II-014)." >&2
    return 1
  fi
  if [[ "$CONTEXT_ACTION" == "written" || "$CONTEXT_ACTION" == "replaced" ]] \
     && ! grep -qFx "$CONTEXT_BEGIN" "$dst/$CONTEXT_FILE"; then
    context_emit_seam DELTA_AUDIT_GAP adopt.context.block_missing "$dst/$CONTEXT_FILE"
    echo >&2
    echo "ERROR: the CADENCE directives managed block is absent from $dst/$CONTEXT_FILE." >&2
    echo "Adoption aborted -- refusing to report success without the managed block (II-014)." >&2
    return 1
  fi
  return 0
}

# print_context_notice -- AC-4. Called ONLY after write_context_wiring succeeded,
# immediately before the final adoption summary, on STDOUT (it is not an error).
# Once per adopt run: "one-time" is per run, not per adopter lifetime -- no
# persistent state file is written to remember it.
print_context_notice() {
  echo
  echo "NOTICE -- your own directives may conflict with CADENCE behaviors."
  echo "  CADENCE's directives were installed as $CONTEXT_SIDECAR and imported from $CONTEXT_FILE."
  echo "  $CONTEXT_FILE is YOURS: CADENCE writes only inside its marker-fenced managed block"
  echo "  and never edits anything outside it."
  echo "  Where your instructions and CADENCE's disagree, a human is expected to review and"
  echo "  reconcile them. Nothing here is auto-resolved."
}
