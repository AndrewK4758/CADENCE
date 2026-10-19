#!/usr/bin/env bash
#
# authored-doc-report.sh -- the REPORTING/PRESENTATION half of the authored-doc
# guard (BTG-247 rows 13-21, spec.md Proposed Design Step 5): formatting a
# predicate's raw hits into the record channel, and printing the sanctioned
# disposition menu. Neither function derives anything -- both take an already-
# computed answer and shape it for a reader or a caller.
#
# Bounded context: Build tooling / compile-gate flow, same as the other four
# authored-doc-*.sh files. SOURCED by authored-doc-gate.sh, never executed.
#
# WHY THIS SEAM. `predicate_org_token` (moved verbatim from
# authored-doc-orgtoken.sh, pre-split lines :359-:394) is explicitly a
# "sweep-formatting wrapper" over `adg_org_token_leaks` (spec.md Step 5's own
# words) -- it derives nothing itself, it reshapes that sweep's raw hits into
# the `intent.portability.org_token_in_portable_path:` record line. Moving it
# to authored-doc-predicates.sh, as an early draft of this relocation
# literally read, would have pushed that file to 335+36=371 lines, well past
# DEC-007's 324-line threshold; predicates.sh's own remaining capacity after
# the scan-scope move is 324-335<0, so it has none left. `adg_print_dispositions`
# (moved verbatim from authored-doc-gate.sh, pre-split lines :209-:231) is the
# gate's disposition-menu printer -- also pure presentation, never a rule --
# moved here to give authored-doc-gate.sh (399, zero headroom under the real
# CI-enforced LCG_CEILING=400 gate) the two lines its new `. "$ADG_SELF_DIR/..."`
# source line and `# shellcheck source=` directive need, in the SAME commit as
# this file first ships (so R-5's `-le 399` never observes an intermediate
# state, spec.md Step 4's ordering rule applied to this family too).
#
# `adg_ledger_hygiene` stays in authored-doc-gate.sh -- SEAM-5 requires it
# textually present in the entry point, and this file's whole point is content
# that is NOT a rule the entry point must carry itself.
#
# A SECOND WAVE (coordinator correction, DEC-034): the first pass left
# `authored-doc-predicates.sh` at 335 (11 over DEC-007's 324) and
# `authored-doc-gate.sh` at 378 (54 over), the second one unflagged as a
# breach at all. AC-1 binds every touched file on both the shedding AND the
# receiving side, and neither number is an agent's to wave through -- only a
# human gate grants that (DEC-018's precedent for `upgrade-collect.sh`, after
# an exhaustive audit). This file absorbed the correction on BOTH fronts:
#
# `adg_uncovered_documents` and `adg_report_uncovered` (moved verbatim from
# authored-doc-predicates.sh) are the SEAM-4 diagnostic's derivation and its
# report line. Both are REPORTING in exactly this file's sense -- neither is a
# rule, both take an already-computed set (the swept paths, the covered set
# read from `--path` call sites) and format it for a reader -- and grep -rl
# across ci-templates/scripts/tests/ found ZERO test files naming either
# function, the lowest-risk relocation in this whole family. This brought
# predicates.sh from 335 to <= 324.
#
# `adg_emit_seam`, `ADG_EXTRA_LEDGER_ROW`, `adg_report_violation` and
# `adg_setup_failure` (all moved verbatim from authored-doc-gate.sh) are its
# generic output-formatting and setup-failure helpers -- REPORTING, not rules,
# and none is `adg_ledger_hygiene` (which SEAM-5 keeps in the entry point).
# `ADG_EXTRA_LEDGER_ROW` is consumed only by `adg_ledger_hygiene`, which stays
# behind in authored-doc-gate.sh -- the knob moved with this file's other
# reporting-testability content rather than staying beside the one rule it
# configures, since nothing requires them to be co-located and gate.sh had no
# headroom to keep it. This brought authored-doc-gate.sh from 378 to <= 324.
#
# No function is renamed: authored-doc-gate.sh's hardcoded post-load census
# (grep for `for adg_fn in`) names `predicate_org_token` by that exact
# identifier, unchanged.
#
# PORTABILITY: bash + grep/awk/sed/sort/cut only. No `find -printf`, no python3.
#
# References: archive/BTG-247/spec.md (Proposed Design Step 5) ;
#             archive/BTG-247/decisions.md DEC-003 (scan-scope seam), DEC-007
#             (the 324-line threshold this split satisfies) ;
#             archive/BTG-191/{problem,spec,test-plan,decisions}.md (the
#             predicates this reports on) ; archive/BTG-190/decisions.md (the
#             disposition-menu ordering rule).

# predicate_org_token <tree-root> <path>...
#
# One `intent.portability.org_token_in_portable_path: <path>:<line>:<text>` per
# unexempted occurrence that falls inside <path>....
#
# IT FILTERS THE FULL SWEEP RATHER THAN NARROWING IT, and that is deliberate. The
# scan scope is the guard's own footprint-derived one; restricting the grep to
# the caller's paths would let a write-time caller decide what the portability
# rule applies to, which is the boundary re-derived by hand that the Data
# Integrity facet forbids. A path outside the shipping set simply produces no
# hits, which is the correct answer for it.
#
# THE DERIVATION-FAILURE LINE IS NEVER FILTERED OUT. `adg_org_token_leaks` reports
# a failed or partial token derivation as one synthetic
# `<token-derivation>:0:FATAL ...` record so that every existing caller's
# `[[ -n "$leaks" ]]` turns red with no caller change. Dropping it here because
# its path is not one the caller named would convert a loud fail-closed into a
# silent clean sweep -- the exact fail-open the two-condition refusal exists to
# close.
predicate_org_token() {
  local root="$1"; shift
  local hit path p
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    case "$hit" in
      '<token-derivation>:0:'*)
        echo "intent.portability.org_token_in_portable_path: $hit"; continue ;;
    esac
    path="${hit%%:*}"
    for p in "$@"; do
      case "$path" in
        "$p"|"$p"/*) echo "intent.portability.org_token_in_portable_path: $hit"; break ;;
      esac
    done
  done <<< "$(adg_org_token_leaks "$root")"
}

# adg_print_dispositions -- the sanctioned ways forward, printed once whenever
# the run reports a violation.
#
# A GATE THAT ONLY BLOCKS IS UNUSABLE AT THE STEP THAT AUTHORED THE DOCUMENT.
# Both /cadence-release-authored causes this gate catches were LEGITIMATE RECORDS
# that BTG-190 dispositioned with ledger rows, not edits: an operator blocked
# mid-cut with no stated remedy is pushed toward editing an immutable record,
# which is facet conflict C-1. The menu is contract, not courtesy, and its order
# is the ruling order -- LEDGER ROW is the default, and revising is admissible
# only while the document is still a draft and the statement is genuinely wrong.
adg_print_dispositions() {
  cat <<'EOF'
authored-doc: disposition -- choose exactly ONE per hit, and never an edit to a committed record:
  1. LEDGER ROW (the default) -- add an anchored row to that guard's ledger in
     ci-templates/scripts/authored-doc-ledgers.sh, anchored on the offending
     SENTENCE and never on the file. A path-wide anchor excuses every future line
     of a growing document; that is why the MCP ledger carries three rows for one
     release note rather than one, and the gate reports such a row as a violation
     in its own right (seam authoreddoc.disposition.unledgered_site).
  2. REVISE THE DRAFT -- only where the document has NOT yet been committed and
     the statement is genuinely wrong rather than a record of what shipped.
EOF
}

# adg_uncovered_documents <tree-root> <swept-path>...
#
# Every swept path that NO write-time call site names, one per line.
#
# THE SEAM-4 OBSERVABILITY, and it reports a gap rather than closing one. A check
# at an authoring step is structurally blind to a write that no step describes,
# and this repository has a measured instance: two of the five occurrences of the
# org-token leak were authored into `production-insights.md` by an archival
# sub-step that appeared in no document at all. The sweep mode is the compensating
# control -- its scope comes from the footprint, not from a list of steps -- but a
# compensating control nobody can see is indistinguishable from an assumption
# that the gap is closed, so the sweep says what it is compensating for.
#
# BOTH SETS ARE DERIVED. The swept set is the caller's; the COVERED set is read
# out of the call sites themselves, by finding every `--path <doc>` invocation in
# the runtime-neutral source. A hand-written list of covered documents would
# agree with itself forever while a step quietly lost its call.
#
# It is INFORMATIONAL, never a violation: an uncovered document is not a defect
# in that document, and failing on it would block every release note for the
# crime of not being named individually by a skill body.
adg_uncovered_documents() {
  local root="$1"; shift
  local covered p
  covered="$( cd "$root" 2>/dev/null && \
              grep -rhoE 'authored-doc-gate\.sh --path [^ `]+' artifacts 2>/dev/null \
                | sed 's/.*--path //' | sort -u )"
  for p in "$@"; do
    printf '%s\n' "$covered" | grep -qxF "$p" || echo "$p"
  done
}

# adg_report_uncovered <tree-root> <swept-path>... -- the SEAM-4 report line.
adg_report_uncovered() {
  local root="$1"; shift
  local uncovered n
  uncovered="$(adg_uncovered_documents "$root" "$@" | tr '\n' ' ')"
  n="$(printf '%s' "$uncovered" | wc -w | tr -d ' ')"
  echo "authored-doc: note authoreddoc.caller.undocumented_write_path -- $n swept document(s) have no write-time call site; this repo-wide sweep is the compensating control for each: $uncovered"
  adg_emit_seam DELTA_AUDIT_GAP authoreddoc.caller.undocumented_write_path "$n uncovered"
}

# adg_emit_seam <TYPE> <event_name> <subject> -- the repository's seam-emission
# convention (chaos-citation-gate.sh). PREFIXED, so sourcing this file into a
# harness can never clobber that harness's own `emit_seam`.
#
# MOVED VERBATIM from authored-doc-gate.sh (BTG-247 rows 13-21, DEC-007's
# 324-line threshold).
adg_emit_seam() {
  echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2
}

# ADG_EXTRA_LEDGER_ROW -- one additional row, appended to every ledger for the
# duration of one run.
#
# ITS ONLY PURPOSE IS TO MAKE THE LEDGER-HYGIENE CHECK TESTABLE from outside the
# process, and it is deliberately singular and read-only-at-startup: a mechanism
# that could load a whole ledger from the environment would be a way to disable
# the gate from a caller's shell, which is the opposite of what a gate is for. It
# can only ADD a row, never remove one, so the worst it can do is make a run
# report MORE.
#
# MOVED VERBATIM from authored-doc-gate.sh (BTG-247 rows 13-21). Its own
# consumer, `adg_ledger_hygiene`, stays in authored-doc-gate.sh per SEAM-5 --
# this knob is a report-testability concern, not a rule, so it moved with the
# rest of this file's REPORTING content rather than staying beside the one
# rule it configures.
ADG_EXTRA_LEDGER_ROW="${ADG_EXTRA_LEDGER_ROW:-}"

# adg_report_violation <guard> <seam> <path> <line> <text>
#
# Every failure names the GUARD, the SEAM, the PATH and the LINE -- never a bare
# non-zero exit. A caller reads the exit status directly, never through a pipe
# that would swallow it.
#
# MOVED VERBATIM from authored-doc-gate.sh (BTG-247 rows 13-21).
adg_report_violation() {
  local guard="$1" seam="$2" path="$3" line="$4" text="$5"
  echo "FAIL [$guard] $seam: $path:$line: $(printf '%s' "$text" | cut -c1-140)"
  adg_emit_seam LOGIC_FAULT "$seam" "$path:$line"
}

# adg_setup_failure <seam> <message> -- MOVED VERBATIM from authored-doc-gate.sh
# (BTG-247 rows 13-21).
adg_setup_failure() { # seam, message
  echo "authored-doc: FATAL -- $2" >&2
  adg_emit_seam UNSOUND_CONDITION "$1" "$2"
  exit 2
}
