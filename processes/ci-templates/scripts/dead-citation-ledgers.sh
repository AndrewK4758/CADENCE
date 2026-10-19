#!/usr/bin/env bash
#
# dead-citation-ledgers.sh -- the two ledgers dead-citation-gate.sh consults,
# and the shrink-only ratchet over them (BTG-083, AC-2 / AC-4).
#
# Bounded context: Build tooling / compile-gate flow. Split out of
# dead-citation-gate.sh along a real seam: that file is the CLASSIFIER (what
# counts as a dead citation), this one is the LEDGERS (what the project has
# decided to tolerate, and on what terms). Keeping them in one file put it at
# 624 lines, well past the <400-line DX ceiling every other gate script here
# respects and far past this ticket's own <250 target.
#
# SOURCED, never executed: it defines functions and mutates the caller's
# EXEMPT_PATTERNS / BASELINE_FILES / failures. It relies on emit_seam,
# fail_event and warn_event being defined by the caller BEFORE it is sourced.
#
# The two ledgers have OPPOSITE LIFECYCLES and are deliberately separate files
# (BTG-083 DEC-004): the exemption allowlist is permanent-by-design and may grow
# with a recorded reason; the baseline is debt with an expiry and may only
# SHRINK. Sharing one file would let debt quietly acquire the status of design.
#
# References: archive/BTG-083/{spec,decisions}.md ; ci-templates/scripts/dead-citation-gate.sh

# Every non-comment, non-blank line of a ledger.
ledger_entries() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true; }

# Trim leading/trailing whitespace. Pure bash on purpose: `| xargs` mangles or
# outright fails on a value containing an apostrophe or a backtick, and reason
# text is prose -- an apostrophe in a reason would empty the field and produce a
# FALSE `citation.exemption.unreasoned` report.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Split `<pattern> | <class> | <reason>` without a subshell per field.
parse_exemption() {
  local line="$1"
  EX_PAT="$(trim "${line%%|*}")"
  local rest="${line#*|}"
  if [[ "$rest" == "$line" ]]; then EX_CLASS=""; EX_REASON=""; return 0; fi
  EX_CLASS="$(trim "${rest%%|*}")"
  local why="${rest#*|}"
  if [[ "$why" == "$rest" ]]; then EX_REASON=""; else EX_REASON="$(trim "$why")"; fi
}

# --- Ledger validation -----------------------------------------------------
# An exemption entry carries `<pattern> | <class> | <reason>`. A missing reason
# is a WARN, not a failure: it is a hygiene defect, not a dead pointer -- but it
# must be surfaced, because an unreasoned exemption is indistinguishable from
# debt that was quietly waved through.

# A ledger that cannot be read is a HALT, never a pass. A gate that treats a
# missing ledger as "nothing is exempt, and also nothing is wrong" reports a
# green verdict it never computed -- fail loud, never fail open.
require_ledger() {
  local path="$1" what="$2"
  if [[ ! -f "$path" ]]; then
    emit_seam UNSOUND_CONDITION citation.ledger.unreadable "$path"
    echo "dead-citation-gate: FATAL -- the $what ledger is missing: $path" >&2
    echo "dead-citation-gate: refusing to report a verdict computed without it." >&2
    exit 2
  fi
  if [[ ! -r "$path" ]]; then
    emit_seam UNSOUND_CONDITION citation.ledger.unreadable "$path"
    echo "dead-citation-gate: FATAL -- the $what ledger is unreadable: $path" >&2
    exit 2
  fi
}
require_ledger "$EXEMPTIONS" exemption
# --emit-baseline is the one mode that legitimately runs without a baseline: it
# is what PRODUCES one. Human-invoked, never in CI.
[[ "$MODE" == "emit-baseline" ]] || require_ledger "$BASELINE" baseline

EXEMPT_PATTERNS=()
EXEMPT_USED=()
load_exemptions() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    parse_exemption "$line"
    [[ -z "$EX_PAT" ]] && continue
    if [[ -z "$EX_REASON" ]]; then
      warn_event citation.exemption.unreasoned "$EX_PAT (class ${EX_CLASS:-?}) carries no reason"
    fi
    EXEMPT_PATTERNS+=("$EX_PAT")
  done < <(ledger_entries "$EXEMPTIONS")
}

load_exemptions

# --- Exemption matching ----------------------------------------------------
# ANCHORED against the WHOLE repo-relative path -- never by substring or prefix
# resemblance, or a non-exempt sibling silently inherits an exemption.
#
# FOURTH FORM, added at BTG-340 (DEC-076, DEC-065 item 9/9): `<path>:<line>` or
# `<path>:<line1>-<line2>` exempts ONLY the named line(s) of the named file,
# never the whole file -- so a single A-f (functional-predicate) citation can
# be dispositioned without blanket-exempting every OTHER citation the same
# file carries (btg-129-retirement-shape.test.sh R-4's own named defect: a
# file-wide exemption silently voided the dead-citation trail for every OTHER
# citation sharing the file, including ones with no connection to the
# line-specific reason). `lineno` is OPTIONAL: called with none (the
# tree-wide staleness sweep below, which has no citation line in hand), a
# line-anchored pattern still matches on PATH ALONE, so "this exemption still
# covers a real file" stays correctly tracked; called WITH a line number (the
# gate's own per-citation scan), it additionally requires the line to fall in
# range, so a citation elsewhere in the SAME file is never silently covered.
pattern_matches() {
  local path="$1" pat="$2" lineno="${3:-}"
  case "$pat" in
    */\*\*) [[ "$path" == ${pat%\*\*}* ]] ;;
    */)     [[ "$path" == ${pat}* ]] ;;
    *:[0-9]*)
      local ppath="${pat%%:*}" prange="${pat#*:}" plo phi
      [[ "$path" == "$ppath" ]] || return 1
      [[ -z "$lineno" ]] && return 0
      case "$prange" in
        *-*) plo="${prange%-*}"; phi="${prange#*-}" ;;
        *)   plo="$prange"; phi="$prange" ;;
      esac
      (( lineno >= plo && lineno <= phi ))
      ;;
    *)      [[ "$path" == $pat ]] ;;
  esac
}

is_exempt() {
  local path="$1" lineno="${2:-}" i
  for i in "${!EXEMPT_PATTERNS[@]}"; do
    if pattern_matches "$path" "${EXEMPT_PATTERNS[$i]}" "$lineno"; then
      EXEMPT_USED[$i]=1
      return 0
    fi
  done
  return 1
}

# An exemption pattern is "used" if it covers ANY file in the tree -- not merely
# any file carrying a dead citation. A pattern that matches nothing at all has
# rotted (its subject was renamed or deleted) and nobody can justify it any more.
mark_exemptions_matching_tree() {
  local f rel i
  while IFS= read -r f; do
    rel="${f#$ROOT/}"
    for i in "${!EXEMPT_PATTERNS[@]}"; do
      [[ -n "${EXEMPT_USED[$i]:-}" ]] && continue
      pattern_matches "$rel" "${EXEMPT_PATTERNS[$i]}" && EXEMPT_USED[$i]=1
    done
  done < <(find "$ROOT" -type f -not -path "$ROOT/.git/*" -not -path "$ROOT/archive/*" 2>/dev/null)
}

# --- The baseline (DEBT, shrink-only) --------------------------------------
# Deliberately a SEPARATE ledger from the exemption allowlist: an exemption is
# permanent-by-design and may grow with a reason; a baseline entry is debt with
# an expiry and may only SHRINK. Sharing one file would let debt quietly acquire
# the status of design (DEC-004).
BASELINE_FILES=()
load_baseline() {
  local line
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -n "$line" ]] && BASELINE_FILES+=("$line")
  done < <(ledger_entries "$BASELINE")
}
load_baseline

# A baseline entry is `<path>|<id>`: the debt that was actually accepted, not the
# file it happens to live in. A bare `<path>` is still honoured -- an adopter's
# existing ledger must not break -- but it tolerates that file for ANY id, which
# is the wider blind spot the pair form closes.
is_baselined() {
  local path="$1" id="$2" b bp bi
  for b in "${BASELINE_FILES[@]}"; do
    bp="${b%%|*}"
    [[ "$path" == "$bp" ]] || continue
    if [[ "$b" == *"|"* ]]; then
      bi="$(trim "${b#*|}")"
      [[ "$id" == "$bi" ]] && return 0
    else
      return 0    # legacy path-only entry: tolerated for any id
    fi
  done
  return 1
}

# In --emit-baseline mode STDOUT IS THE LEDGER. Every status sentence therefore
# goes to stderr, and every exit path emits a syntactically valid ledger --
# including the "nothing to scan" ones. A documented `> baseline.txt` redirect
# would otherwise capture an "OK: ..." sentence AS A BASELINE ENTRY, which is
# both nonsense and, worse, an entry that silently excuses a real file later.
print_baseline_header() {
  local n="$1" sha
  sha="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo 'not-a-git-work-tree')"
  echo "# dead-citation-baseline.txt -- BTG-083 (AC-4), the residual DEBT ledger."
  echo "#"
  echo "# Generated by: dead-citation-gate.sh --emit-baseline"
  echo "# At SHA:  $sha"
  echo "# Scope:   every file under the repo root, ALL extensions, excluding"
  echo "#          archive/, .git/ and node_modules/; every id having an"
  echo "#          archive/<id>/ directory and no live specs/<id>/ tree."
  echo "# Command: bash ci-templates/scripts/dead-citation-gate.sh --emit-baseline > ci-templates/scripts/dead-citation-baseline.txt"
  echo "# Entries: $n"
  echo "#"
  echo "# Each entry is '<path>|<archived-id>' -- the debt that was actually"
  echo "# accepted, not merely the file it lives in. So ONE file citing three"
  echo "# archived ids is THREE entries: the entry count is larger than the file"
  echo "# count, and that is the point. A bare '<path>' entry is still honoured"
  echo "# for an adopter's existing ledger, but it tolerates that file for ANY id,"
  echo "# which leaves the file blind to genuinely new rot."
  echo "#"
  echo "# This file is DEBT, not design. Entries may be REMOVED as the debt is"
  echo "# retired; adding an entry that makes this ledger GROW fails the gate"
  echo "# (citation.baseline.grew, R13) -- a ratchet that can be loosened is"
  echo "# decorative. A PERMANENT exemption belongs in"
  echo "# dead-citation-exemptions.txt instead; the two files are separate"
  echo "# precisely so debt can never acquire the status of design."
  echo "#"
  echo "# THE PRECISE GUARANTEE, because the flatter claim 'ADDING an entry FAILS"
  echo "# the gate' overstated it (BTG-083 maintainer condition C-3, decisions.md"
  echo "# DEC-024). Both ratchet axes compare the entry COUNT, not set MEMBERSHIP."
  echo "# So a change that RETIRES two entries and ADDS one -- a NET SHRINK, 213 ->"
  echo "# 212 -- passes, and the ledger has silently gained a member that can blind"
  echo "# a file to real rot. A PURE addition is caught (the declared count, or the"
  echo "# merge-base comparison once this file exists there). Substitution under a"
  echo "# net shrink is NOT. Retiring debt is exactly when that shape occurs, so"
  echo "# every retirement pass must diff the ledger ENTRY BY ENTRY against the"
  echo "# previous revision and show additions separately from removals."
  echo "#"
  echo "# Retirement follow-on: BTG-092 -- the residual sweep filed out of BTG-083"
  echo "# OQ-1 (accepted risk AR-1; this pointer is AR-1 control 3, which had no"
  echo "# ticket id until the Maintainer gate required one). Until it ships, a"
  echo "# reader following one of these citations still lands nowhere."
}

emit_empty_baseline_and_exit() {
  print_baseline_header 0
  echo "dead-citation-gate: emitted an EMPTY baseline ($1)." >&2
  exit 0
}


# --- R13: the baseline may SHRINK, never GROW ------------------------------
check_baseline_ratchet() {
  local declared actual prev prev_ref prev_label cand base_ref merge_base integration
  # An added baseline entry is itself a failure, or the ratchet is decorative --
  # debt could otherwise be added faster than it is retired and the gate would stay
  # green forever. Checked on two independent axes, because each closes the other's
  # gap:
  #
  #   (a) the DECLARED entry count in the header vs. the actual number of entries.
  #       Works everywhere, including a fixture and an adopter's non-git checkout.
  #       Catches an entry appended without touching the header.
  #   (b) the previous COMMITTED revision's entry count vs. this one's, when the
  #       root is a git work tree and the baseline is tracked. Catches the case (a)
  #       cannot: an entry added AND the declared count bumped in the same edit.
  #
  # Neither is a fallback for the other and neither is silent: (a) always runs, and
  # (b) runs whenever git can answer, announcing itself when it cannot.
  declared="$(grep -m1 '^# Entries:' "$BASELINE" 2>/dev/null | sed 's/^# Entries:[[:space:]]*//' | tr -d '[:space:]')"
  actual="${#BASELINE_FILES[@]}"
  if [[ -z "$declared" ]]; then
    warn_event citation.baseline.header_incomplete \
      "$BASELINE carries no '# Entries:' header line -- the shrink-only ratchet cannot be checked against a declared count"
  elif [[ ! "$declared" =~ ^[0-9]+$ ]]; then
    fail_event citation.baseline.grew "$BASELINE declares a non-numeric entry count: [$declared]"
  elif [[ "$actual" -gt "$declared" ]]; then
    fail_event citation.baseline.grew \
      "$BASELINE holds $actual entries but declares $declared -- the baseline may only SHRINK (R13)"
  fi

  # Axis (b) compares against the MERGE BASE with the integration branch, never
  # against HEAD.
  #
  # Comparing against `HEAD:` was a defect, not a simplification: an automated
  # consumer clones and runs
  # on a CHECKED-OUT COMMIT, so the working-tree baseline IS HEAD's baseline and the
  # comparison is `prev == actual` unconditionally. The realistic offence -- add a
  # dead citation, regenerate the baseline, commit -- sailed through, and the header
  # axis cannot catch it either because `--emit-baseline` regenerates a correct
  # `# Entries:` count by construction. The merge base is the last state the change
  # is accountable to, which is what "may only shrink" actually means for a branch.
  #
  # EVERY reason this axis cannot run is ANNOUNCED. An axis that silently does not
  # run is indistinguishable from one that ran and found nothing -- the precise
  # failure mode being fixed here, so it is not reintroduced as a silent skip.
  rel_baseline="ci-templates/scripts/dead-citation-baseline.txt"
  axis_unavailable() {
    warn_event citation.baseline.axis_unavailable \
      "the revision-comparison half of the shrink-only ratchet did not run: $1 (the declared-count half still did)"
  }

  # The integration branch is RESOLVED from the branch-strategy binding, never
  # hardcoded -- a hardcoded branch name is the same defect class as a hardcoded
  # ticket id, which is what this whole gate exists to catch.
  resolve_integration_branch() {
    local org="$ROOT/docs/agentic-sdlc/CADENCE_ORG.md" line
    [[ -f "$org" ]] || return 1
    line="$(grep -m1 -oE '<!--[[:space:]]*integration-branch:[[:space:]]*[A-Za-z0-9._/-]+[[:space:]]*-->' "$org" 2>/dev/null)" || return 1
    [[ -n "$line" ]] || return 1
    line="${line#*integration-branch:}"; line="${line%%-->*}"
    line="$(trim "$line")"
    [[ -n "$line" ]] || return 1
    printf '%s' "$line"
  }

  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    axis_unavailable "the root is not a git work tree"
  elif ! integration="$(resolve_integration_branch)"; then
    axis_unavailable "no integration-branch marker in docs/agentic-sdlc/CADENCE_ORG.md (CADENCE_ORG.md#branch-strategy-binding)"
  else
    # Prefer the remote-tracking ref: a local branch can be stale, and a verdict
    # computed against a stale base is a false verdict.
    base_ref=""
    for cand in "origin/$integration" "$integration"; do
      if git -C "$ROOT" rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then base_ref="$cand"; break; fi
    done
    if [[ -z "$base_ref" ]]; then
      axis_unavailable "neither origin/$integration nor $integration resolves in this clone"
    elif ! merge_base="$(git -C "$ROOT" merge-base "$base_ref" HEAD 2>/dev/null)" || [[ -z "$merge_base" ]]; then
      axis_unavailable "no merge base between HEAD and $base_ref (unrelated histories, or a shallow clone)"
    else
      # Which revision is this change accountable to?
      #
      #   on a BRANCH  -> the merge base. Catches growth that was COMMITTED on the
      #                   branch, which is what a consumer sees when it checks the commit out.
      #   at/behind the integration tip -> HEAD. There is no branch delta, so the
      #                   only growth that can exist is UNCOMMITTED, and HEAD is
      #                   exactly the right comparison for it.
      #
      # Picking one or the other leaves a hole: comparing only against HEAD misses
      # committed branch growth (the original defect), and comparing only against
      # the merge base would miss working-tree growth on the integration branch.
      # Choosing per situation covers both.
      #
      # KNOWN RESIDUAL, stated rather than implied: growth COMMITTED DIRECTLY to
      # the integration branch is caught by neither, because once it is in, HEAD
      # and the merge base are the same commit. That path is out of the threat
      # model by configuration, not by luck -- CADENCE_ORG.md #branch-strategy-binding
      # declares `integration-branch-protected: yes`, so every change reaches the
      # integration branch through a branch, where the merge-base comparison fires
      # (proven by scenario S-4.2b). An adopter who sets that marker to `no` loses
      # this half of the ratchet and keeps only the declared-count half.
      #
      # FORWARD HAZARD, stated because the sentence above proves less than it
      # sounds like it proves: the merge-base comparison FIRING is a property of
      # the code path, and nothing here enforces that the gate is RUN on the
      # branch. BTG-200 AC-4: this hazard formerly cited an async CI backstop and
      # its allowed-refs list; that list had already been falsified by BTG-191 and
      # the manifest is now deleted, so the hazard is STRICTLY STRONGER than when
      # it was written -- on the integration tip `merge_base == HEAD`, and in
      # practice this axis fires via the OPT-IN pre-commit hook or a manual
      # `run-gates.sh` on a branch, neither of which is guaranteed, and there is
      # no backstop behind them. Whether any CI substrate runs is
      # `docs/agentic-sdlc/CADENCE_ORG.md` section 1 Where (Network)'s CI/CD row.
      # The declared-count axis is unconditional and is what holds when nobody
      # runs this one.
      if [[ "$merge_base" == "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" ]]; then
        prev_ref="HEAD"; prev_label="HEAD (no branch delta; uncommitted growth only)"
      else
        prev_ref="$merge_base"; prev_label="the $base_ref merge base"
      fi
      if ! git -C "$ROOT" cat-file -e "$prev_ref:$rel_baseline" 2>/dev/null; then
        axis_unavailable "the baseline did not exist at $prev_label (the commit that introduces it)"
      else
        prev="$(git -C "$ROOT" show "$prev_ref:$rel_baseline" 2>/dev/null | grep -vcE '^[[:space:]]*(#|$)')"
        if [[ "$actual" -gt "$prev" ]]; then
          fail_event citation.baseline.grew \
            "$rel_baseline grew from $prev entries at $prev_label to $actual -- the baseline may only SHRINK (R13)"
        fi
      fi
    fi
  fi

}
