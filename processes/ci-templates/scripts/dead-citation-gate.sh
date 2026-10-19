#!/usr/bin/env bash
#
# dead-citation-gate.sh -- BTG-083 structural gate (AC-3 / AC-4 / AC-5).
#
# Bounded context: Build tooling / compile-gate flow, and the /claire-archive lifecycle
# contract. Invariant relied on from outside this boundary: /claire-archive relocates
# `specs/<id>/` to `archive/<id>/` (artifacts/commands/claire-archive.md step 2), so a
# `specs/<id>/` string literal outside archive/, for an id that now has an
# archive/<id>/ directory, is a DEAD path -- a pointer to somewhere that no
# longer exists. This is the recurrence production-insights.md PROD_CLAIRE-009 records.
#
# ONE classifier, THREE callers (BTG-083 DEC-003, extended by BTG-133) -- not
# three mechanisms, so a reader learns the classification rules once:
#
#   dead-citation-gate.sh [--root <dir>]        # repo-wide ratchet (the CI row)
#   dead-citation-gate.sh --id <ticket>         # /claire-archive step 2b, that one id
#   dead-citation-gate.sh --except-id <ticket>  # /claire-archive step 2c, every OTHER id
#   dead-citation-gate.sh --emit-baseline       # human-invoked ledger emitter
#
# Step 2c exists because /claire-archive's own ADR and intent-insight promotion write
# new files into the tree step 2b already scanned, and those files routinely cite
# a DIFFERENT already-archived ticket -- structurally invisible to a single-id
# scan. Live instance: BTG-127's archival shipped ADR_CLAIRE-0052 citing two dead paths
# and turned the integration branch red (PROD_CLAIRE-015).
#
# TWO EXCLUSIONS, TWO DIFFERENT AXES -- never conflate them (BTG-133 DEC-004):
#   * `specs/$TICKET/` skipped as a CITING LOCATION -- WHERE A HIT LIVES. Inside
#     the --id branch only; that tree relocates with the move, so its internal
#     citations are not inbound references at all.
#   * $TICKET skipped as a SCANNED TARGET -- WHICH ID WE LOOK FOR. In the SCAN_IDS
#     derivation loop, ratchet path only, driven by --except-id.
# Conflating them either silences the ticket's own sweep (scanned-target exclusion
# leaking into --id mode) or makes step 2c double-report the archiving ticket
# under the wrong remediation vocabulary. In the /claire-archive SKILL home the single-id
# step owns the archiving ticket's own id and the complement step owns every other
# one. In the ARCHIVIST ROLE home that split does NOT hold: the complement step is
# a TWO-CALL step that also re-runs the own-id sweep over the post-promotion tree,
# because the role's own single-id step runs BEFORE the promotions write the files
# it would need to see (BTG-133 DEC-029). Union total, intersection empty -- with
# one residual: a file carrying a BLANKET exemption in the exemptions ledger is
# outside BOTH calls, and the intent-insights ledger is one of them, so a dead
# citation the intent-insight promotion writes is caught by neither (DEC-033,
# follow-up BTG-162). Read that totality claim with its one hole visible.
#
# Exit codes: 0 clean ; 1 on a violation ; 2 on setup failure.
#
# It is READ-ONLY BY CONSTRUCTION -- it writes no file inside the tree at all.
#
# References: archive/BTG-083/{problem,spec,test-plan,decisions}.md ;
#             ci-templates/scripts/effort-boundary-gate.sh (the shape copied) ;
#             docs/agentic-sdlc/production-insights.md PROD_CLAIRE-009 / PROD_CLAIRE-005.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="ratchet"
TICKET=""
# --except-id is a SCOPE MODIFIER ON THE RATCHET, not a fourth MODE: leaving MODE
# alone keeps the emit-baseline guards and the whole ratchet downstream path at
# their exact prior meanings (BTG-133 DEC-005).
EXCEPT_ID=""
EXCEPT_ID_GIVEN="no"      # distinguishes "flag absent" from "flag given, value empty"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)          ROOT="$2"; shift 2 ;;
    --emit-baseline) MODE="emit-baseline"; shift ;;
    --id)            MODE="id"; TICKET="${2:-}"; shift 2 ;;
    # `shift 2` is NOT safe here: with no value after the flag it shifts nothing
    # and the parse loop spins forever. Shift what actually exists.
    --except-id)     EXCEPT_ID="${2:-}"; EXCEPT_ID_GIVEN="yes"; shift; [[ $# -gt 0 ]] && shift ;;
    *) echo "dead-citation-gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ "$MODE" == "id" && -z "$TICKET" ]]; then
  echo "dead-citation-gate: --id requires a ticket id" >&2; exit 2
fi

EXEMPTIONS="$ROOT/ci-templates/scripts/dead-citation-exemptions.txt"
BASELINE="$ROOT/ci-templates/scripts/dead-citation-baseline.txt"

emit_seam() {
  local seam_type="$1" event_name="$2" subject="${3:-}"
  echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
}

# --- --except-id: the ARGUMENT half of its contract ------------------------
# Properties of the invocation alone, so checked here; the TREE half (the
# excluded id must actually be archived) is checked further down, where the
# archived-id set is known. Both refuse with exit 2 -- a scope modifier that
# cannot be honoured as asked is a setup failure, never a run at some other scope.
if [[ -n "$EXCEPT_ID" && "$MODE" != "ratchet" ]]; then
  emit_seam IMPOSSIBLE_STATE citation.except_id.mode_conflict "--except-id with --$MODE"
  echo "dead-citation-gate: FATAL -- --except-id is a scope modifier on the ratchet and" >&2
  echo "cannot be combined with --$MODE. Refusing rather than silently picking one." >&2
  exit 2
fi
# An empty or absent value means "exclude nothing" -- a plain ratchet run wearing
# the flag, which is the fail-open E-5 measured. Refused.
if [[ "$EXCEPT_ID_GIVEN" == "yes" && -z "$EXCEPT_ID" ]]; then
  echo "dead-citation-gate: --except-id requires a ticket id" >&2; exit 2
fi

failures=0
fail_event() {
  local event="$1" detail="${2:-}"
  emit_seam IMPOSSIBLE_STATE "$event" "$detail"
  echo "dead-citation-gate: FAILED ($event) -- $detail" >&2
  failures=$((failures + 1))
}

warn_event() {
  local event="$1" detail="${2:-}"
  emit_seam LINEAGE_GAP "$event" "$detail"
  echo "dead-citation-gate: WARN ($event) -- $detail" >&2
}

# --- The ONE way this gate scans ------------------------------------------
# `grep` exits 0 on a match, 1 on no match and >1 on an ERROR. Discarding its
# stderr and ignoring its status makes "the scan broke" indistinguishable from
# "there is nothing wrong" -- the single worst confusion for a gate whose premise
# is failing closed, and a false all-clear rather than a missing one. It is
# checked HERE, once, for every scan this gate performs: the repo-wide ratchet
# scan, the --id inbound scan on /claire-archive's blocking path, and the
# repoint-target scan (S-3.8 / S-3.9 / S-3.10). A fourth scan added later
# inherits the check by construction instead of re-acquiring the defect.
#
# Each scan also runs exactly ONCE into a file. Several loops consume the result;
# reading the file keeps that from silently becoming several scans.
scan_into() {   # scan_into <outfile> <what> <grep-args...>  -> 0 ok, 1 failed loudly
  local out="$1" what="$2"; shift 2
  local errf rc; errf="$(mktemp)"
  grep -rIn "$@" "$ROOT" \
    --exclude-dir=.git --exclude-dir=archive --exclude-dir=node_modules \
    >"$out" 2>"$errf"
  rc=$?
  if [[ "$rc" -gt 1 ]]; then
    fail_event citation.scan.failed \
      "the $what exited $rc -- refusing to report a verdict it did not compute: $(head -2 "$errf" | tr '\n' ' ')"
    rm -f "$errf"; return 1
  fi
  rm -f "$errf"
  sed -i "s|^$ROOT/||" "$out" 2>/dev/null || true
  return 0
}

# --- The ONE terminator (BTG-126): an id ends where a character that cannot CONTINUE it begins, or at
# EOL -- a negated class, never an enumerated set; defined ONCE and consumed at EVERY matching site,
# because widening only the outer scan was reproduced printing "clean" over 22 live citations
# (citation.detector.predicate_desynchronised). POSIX ERE only, GNU + busybox. archive/BTG-126/decisions.md DEC-002.
CITE_TERMCLASS='[^A-Za-z0-9-]'
CITE_TERM="($CITE_TERMCLASS|\$)"

# --- Ledger module -------------------------------------------------------
# The two ledgers, their parsing, their matching rules and the shrink-only
# ratchet live in a sibling module. The split is along a real seam -- this file
# is the CLASSIFIER (what counts as a dead citation), the module is the LEDGERS
# (what the project has decided to tolerate) -- and it keeps both halves inside
# the <400-line DX ceiling that every other gate script in this repo respects.
# A missing module is a loud setup failure, never a silent skip: without it the
# gate would have no notion of exempt or baselined and would fail every file.
LEDGER_LIB="$(dirname "${BASH_SOURCE[0]}")/dead-citation-ledgers.sh"
if [[ ! -f "$LEDGER_LIB" ]]; then
  echo "seam_type=IMPOSSIBLE_STATE event_name=citation.ledger.unreadable subject=$LEDGER_LIB" >&2
  echo "dead-citation-gate: FATAL -- required module not found: $LEDGER_LIB" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$LEDGER_LIB"

# --- --id: the /claire-archive caller (AC-5) --------------------------------------
# The SAME classifier, scoped to one id at the moment of the move (DEC-003 R19) --
# not a second implementation, so a reader learns the classification rules once.
#
# It DETECTS, CLASSIFIES and BLOCKS. It never rewrites: the measured
# counterexamples prove a blanket repoint corrupts working code (a
# `git show <ref>:specs/<id>/...` path is CORRECT as written because it addresses
# a historical tree), and PROD_CLAIRE-009 itself says the historical-versus-live
# distinction "should force to a human/spec decision rather than resolve
# silently".
#
# The BASELINE IS DELIBERATELY NOT CONSULTED here. A newly archived id must never
# be able to join the debt ledger, or the closed-and-only-shrinking property that
# makes the residual debt acceptable at all is lost (DEC-010 control 5).
if [[ "$MODE" == "id" ]]; then
  if [[ ! -d "$ROOT/archive/$TICKET" && ! -d "$ROOT/specs/$TICKET" ]]; then
    emit_seam IMPOSSIBLE_STATE citation.repoint.target_absent "$TICKET"
    echo "dead-citation-gate: FATAL -- neither archive/$TICKET/ nor specs/$TICKET/ exists." >&2
    exit 2
  fi
  if [[ ! -d "$ROOT/archive/$TICKET" ]]; then
    emit_seam IMPOSSIBLE_STATE citation.repoint.target_absent "archive/$TICKET"
    echo "dead-citation-gate: FATAL -- archive/$TICKET/ does not exist; run this AFTER the move." >&2
    exit 2
  fi
  # /claire-archive's BLOCKING path: a suppressed scan failure here completes an archival
  # with an undispositioned inbound citation AND a green check, which spec Risk
  # R-1 names as strictly worse than the no-gate status quo (S-3.9).
  ID_OUT="$(mktemp)"
  trap 'rm -f "$ID_OUT"' EXIT INT TERM
  if ! scan_into "$ID_OUT" "inbound-citation scan for $TICKET" -E "specs/$TICKET$CITE_TERM"; then
    echo "" >&2
    echo "ARCHIVE BLOCKED: the inbound-citation scan for $TICKET could not run." >&2
    echo "The disposition list is INCOMPLETE, not empty. Archive does NOT complete." >&2
    exit 1
  fi
  id_hits=0
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    text="${rest#*:}"
    # The ticket's OWN spec tree is excluded: it relocates WITH the move, so its
    # internal citations are not inbound references at all. Excluding it is what
    # keeps the check from blocking every archive on the ticket's own artifacts.
    [[ "$path" == "specs/$TICKET/"* ]] && continue
    is_exempt "$path" "$lineno" && continue
    # A citation that is CODE rather than a comment is surfaced for individual
    # judgement and never blanket-repointed.
    shape="comment"
    printf '%s' "$text" | grep -qE '^[[:space:]]*(#|//|--|\*)' || shape="NOT-A-COMMENT"
    emit_seam LINEAGE_GAP archive.citation_sweep.undispositioned "$TICKET:$path:$lineno"
    echo "dead-citation-gate: BLOCKED -- $path:$lineno cites specs/$TICKET [$shape]" >&2
    if [[ "$shape" == "NOT-A-COMMENT" ]]; then
      echo "    This occurrence is CODE, not a comment (a filter argument, a variable" >&2
      echo "    binding, or a path addressed against a historical git ref). Read it and" >&2
      echo "    disposition it INDIVIDUALLY -- never blanket-repoint it." >&2
    fi
    id_hits=$((id_hits + 1))
  done < "$ID_OUT"

  if [[ "$id_hits" -eq 0 ]]; then
    echo "OK: no inbound specs/$TICKET/ citations to disposition."
    exit 0
  fi
  echo "" >&2
  echo "============================================" >&2
  echo "ARCHIVE BLOCKED: $id_hits undispositioned inbound citation(s) for $TICKET." >&2
  echo "============================================" >&2
  echo "Choose exactly ONE disposition for EACH hit above:" >&2
  echo "  REPOINT (the default) -- rewrite specs/$TICKET/ -> archive/$TICKET/ in place." >&2
  echo "  EXEMPT                -- add an entry to dead-citation-exemptions.txt naming" >&2
  echo "                           the class and the reason." >&2
  echo "Record every hit and its disposition in archive/$TICKET/summary.md." >&2
  echo "Archive does NOT complete while any hit is undispositioned." >&2
  exit 1
fi

# --- The archived-id set ---------------------------------------------------
# DERIVED AT RUN TIME from archive/*/ -- never hardcoded. A hardcoded id is the
# very defect this gate exists to catch: it rots the moment the tree moves around
# it (the live instance is btg-075-mcp-absence.test.sh:167).
ARCHIVED_IDS=()
derive_archived_ids() {
  local p id
  for p in "$ROOT"/archive/*/; do
    [[ -d "$p" ]] || continue
    id="$(basename "$p")"
    [[ -n "$id" ]] && ARCHIVED_IDS+=("$id")
  done
}
derive_archived_ids

# An EMPTY archive is a clean pass -- a fresh adopter has nothing to scan. But an
# empty derivation while archive/ IS populated means the derivation itself broke,
# and reporting an all-clear on a broken derivation is worse than reporting
# nothing: it is a FALSE all-clear.
if [[ ${#ARCHIVED_IDS[@]} -eq 0 ]]; then
  # The broken-derivation check keys on SUBDIRECTORIES, not on "any entry".
  # An archived id IS a directory, so `archive/` holding only files means zero
  # ids is the CORRECT answer, not evidence of a broken derivation. Keying on
  # any-entry fired a false CRITICAL on every fresh adopter, because
  # /claire-adopt installs `archive/.gitkeep` -- caught by running a real
  # adoption end to end (S-3.4b), not by reading the copy list.
  archive_subdirs=0
  if [[ -d "$ROOT/archive" ]]; then
    for p in "$ROOT"/archive/*/; do [[ -d "$p" ]] && archive_subdirs=$((archive_subdirs + 1)); done
  fi
  if [[ "$archive_subdirs" -gt 0 ]]; then
    fail_event citation.scan.id_set_empty \
      "archive/ is non-empty but the archived-id derivation yielded no ids -- refusing to report an all-clear"
    echo "" >&2
    echo "FAILED: $failures dead-citation violation(s)." >&2
    exit 1
  fi
  [[ "$MODE" == "emit-baseline" ]] && emit_empty_baseline_and_exit "no archived ids; nothing to scan"
  echo "OK: dead-citation gate clean (no archived ids; nothing to scan)."
  exit 0
fi

# --- --except-id: the TREE half of its contract ----------------------------
# FAIL LOUD, NEVER FALL BACK. Spec experiment E-5 prototyped this flag unguarded
# and MEASURED the degradation: a typo'd id silently became a plain ratchet run,
# a verdict over a scope nobody asked for, reported as the requested one.
#
# Sited after the archived-id derivation, not at parse time: this is a TREE fact.
# Sitting after the empty-archive early exit also keeps a fresh adopter (archive/
# holding a placeholder and no ticket directories) a clean pass -- nothing to
# sweep is not the same as a requested scope that could not be honoured.
if [[ -n "$EXCEPT_ID" && ! -d "$ROOT/archive/$EXCEPT_ID" ]]; then
  emit_seam IMPOSSIBLE_STATE citation.except_id.target_absent "$EXCEPT_ID"
  echo "dead-citation-gate: FATAL -- archive/$EXCEPT_ID/ does not exist, so --except-id" >&2
  echo "$EXCEPT_ID excludes nothing and this run would silently widen to a plain" >&2
  echo "ratchet sweep. Refusing." >&2
  exit 2
fi

# An id that ALSO has a live specs/<id>/ directory is NOT dead: the ticket is
# mid-archive, or was re-opened. Its citations point at something that exists.
SCAN_IDS=()
for id in "${ARCHIVED_IDS[@]}"; do
  [[ -d "$ROOT/specs/$id" ]] && continue
  # /claire-archive step 2c: the archiving ticket's own id is step 2b's business, under
  # its own disposition contract. Skipped as a SCANNED TARGET here -- a different
  # axis from the citing-location exclusion in the --id branch (DEC-004).
  [[ -n "$EXCEPT_ID" && "$id" == "$EXCEPT_ID" ]] && continue
  SCAN_IDS+=("$id")
done

if [[ ${#SCAN_IDS[@]} -eq 0 ]]; then
  [[ "$MODE" == "emit-baseline" ]] && emit_empty_baseline_and_exit "every archived id also has a live specs/ tree"
  echo "OK: dead-citation gate clean (every archived id also has a live specs/ tree)."
  exit 0
fi

# ONE alternation, ONE scan -- not one scan per id. Ids are matched with their
# delimiters (`specs/<id>/`) so ALPHA-016 can never absorb a hit that belongs to
# ALPHA-016a, and the alternation is ordered longest-first so the regex engine
# prefers the more specific id.
build_alternation() {
  local sorted; sorted="$(printf '%s\n' "${SCAN_IDS[@]}" | awk '{print length, $0}' | sort -rn -k1,1 | cut -d' ' -f2-)"
  printf '%s' "$sorted" | paste -sd'|' -
}
PAT="$(build_alternation)"

# --- Scan ------------------------------------------------------------------
# The scan is REPO-WIDE and EXTENSION-AGNOSTIC. An extension-scoped glob
# under-reports: the same tree yields 68 or 69 BTG-075 files depending on whether
# `.yaml` is in the glob (spec M-1 vs M-2), and nobody wrote the glob down.
# Exit-status checking and the run-once-into-a-file discipline live in scan_into.
SCAN_OUT="$(mktemp)"
REPOINT_OUT=""
cleanup_scan() { rm -f "$SCAN_OUT" ${REPOINT_OUT:+"$REPOINT_OUT"}; }
trap cleanup_scan EXIT INT TERM

if ! scan_into "$SCAN_OUT" "repository scan" -E "specs/($PAT)$CITE_TERM"; then
  echo "" >&2
  echo "FAILED: the dead-citation scan could not run." >&2
  exit 1
fi

scan_hits() { cat "$SCAN_OUT"; }

# --- --emit-baseline -------------------------------------------------------
# Writes the ledger to STDOUT, never into the tree: the gate stays read-only by
# construction, and the human redirects it deliberately. The output is the set of
# non-exempt files carrying a dead citation, i.e. exactly the residual debt on
# the tree AS IT STANDS -- so it must be run AFTER the correction, never before.
# Every distinct id on the line, for the same reason as the classify loop below:
# emitting only the leftmost writes a ledger the classifier then reads as covering
# ids it does not cover (S-3.11).
line_ids() {   # line_ids <text> -> one archived id per line, deduped
  printf '%s' "$1" | grep -oE "specs/($PAT)$CITE_TERM" | sed "s|^specs/||; s|$CITE_TERMCLASS\$||" | sort -u
}

if [[ "$MODE" == "emit-baseline" ]]; then
  emit_tmp="$(mktemp)"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    path="${hit%%:*}"
    is_exempt "$path" "$(cut -d: -f2 <<<"$hit")" && continue
    while IFS= read -r hid; do
      [[ -z "$hid" ]] && continue
      printf '%s|%s\n' "$path" "$hid"
    done < <(line_ids "${hit#*:}")
  done < <(scan_hits) | sort -u > "$emit_tmp"
  n="$(grep -c . "$emit_tmp" || true)"
  print_baseline_header "$n"
  cat "$emit_tmp"
  rm -f "$emit_tmp"
  exit 0
fi

dead_files=0
BASELINE_SEEN=()
# EVERY distinct archived id on the line, never merely the leftmost. Resolving one
# id per line made the detector fail OPEN: with the pair-form ledger, a baselined
# leading id blinded the whole line to every other id on it -- a hole the bare-path
# form did not have, so it is closed where the pair form was introduced (S-3.11).
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  path="${hit%%:*}"
  rest="${hit#*:}"
  lineno="${rest%%:*}"
  is_exempt "$path" "$lineno" && continue
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if is_baselined "$path" "$id"; then
      BASELINE_SEEN+=("$path|$id")
      BASELINE_SEEN+=("$path")
      continue
    fi
    fail_event citation.dead_reference "$path:$lineno cites specs/$id -- $id is archived at archive/$id/"
    dead_files=$((dead_files + 1))
  done < <(line_ids "$rest")
done < <(scan_hits)

# --- A repoint must land somewhere that EXISTS -----------------------------
# Suppressing this scan's exit status silently SKIPS citation.repoint.target_absent
# (Critical): a pointer rewritten to a directory that was never created looks
# corrected and still resolves nowhere (S-3.10).
REPOINT_OUT="$(mktemp)"
if ! scan_into "$REPOINT_OUT" "archive/<id>/ repoint-target scan" \
       -E 'archive/[A-Za-z]+-[0-9]+[a-z]?/'; then
  echo "" >&2
  echo "FAILED: the repoint-target scan could not run." >&2
  exit 1
fi
# The failure mode a naive sweep creates: a pointer is rewritten to
# `archive/<id>/`, looks corrected, and still resolves nowhere because that
# directory was never there. Verifying only that the SOURCE path is gone would
# certify exactly this. The check is scoped to `archive/<id>/`-shaped citations
# (an id-looking segment), so an ordinary path under archive/ is not implicated.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  path="${hit%%:*}"
  rest="${hit#*:}"
  lineno="${rest%%:*}"
  is_exempt "$path" "$lineno" && continue
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    tid="${ref#archive/}"; tid="${tid%/}"
    [[ -d "$ROOT/archive/$tid" ]] && continue
    fail_event citation.repoint.target_absent \
      "$path:$lineno cites archive/$tid/ but that directory does not exist -- a repoint that resolves nowhere"
  done < <(printf '%s' "$rest" | grep -oE 'archive/[A-Za-z]+-[0-9]+[a-z]?/' | sort -u)
done < "$REPOINT_OUT"

check_baseline_ratchet

# --- Warning-level ledger hygiene ------------------------------------------
# A baseline entry naming a file that no longer carries a dead citation is
# RETIRED debt. It passes, but it is surfaced every run so the ledger cannot
# silently rot upward in apparent value.
for b in "${BASELINE_FILES[@]}"; do
  seen=""
  for s in ${BASELINE_SEEN[@]+"${BASELINE_SEEN[@]}"}; do
    [[ "$s" == "$b" ]] && { seen=1; break; }
  done
  [[ -n "$seen" ]] && continue
  warn_event citation.baseline.stale_entry \
    "$b no longer carries a dead citation -- retire the entry (the baseline may shrink)"
done

mark_exemptions_matching_tree
for i in "${!EXEMPT_PATTERNS[@]}"; do
  [[ -n "${EXEMPT_USED[$i]:-}" ]] && continue
  warn_event citation.exemption.unmatched \
    "${EXEMPT_PATTERNS[$i]} matches no file in the tree -- a rotted exemption nobody can justify"
done

# === Report ================================================================
if [[ $failures -eq 0 ]]; then
  echo "OK: dead-citation gate clean."
  exit 0
fi
echo "" >&2
echo "============================================" >&2
echo "FAILED: $failures dead-citation violation(s)." >&2
echo "============================================" >&2
exit 1
