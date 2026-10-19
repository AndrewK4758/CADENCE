#!/usr/bin/env bash
#
# worklog-split.sh -- BTG-315: the SINGLE site that resolves a per-stage
#                      operator-share factor and computes the two-leg split
#                      of one projected `stage_effort` entry between the
#                      operator and the configured agent-time user.
#
# Bounded context: CLAIRE framework governance / tracker-projection worklog
# posting. Invariant relied on from outside this boundary: `CLAIRE_ORG.md`
# section 19 (Worklog Attribution Split) is the SINGLE source of the per-stage
# operator-share factor table; this script READS that table live (section-
# scoped on its own heading, never a file-wide grep -- BTG-315 R-6) and embeds
# no value of its own. The `stage_effort` ledger this script's callers read is
# UNAFFECTED by this script (BTG-315 AC-6): it computes a tracker-projection
# split only, never a ledger mutation.
#
# Upstream: the two tracker adapters' worklog steps (`/claire-sync-jira`,
# `/claire-sync-youtrack`), invoked once per selected ledger entry when a
# non-empty agent-time user is configured on the ticket's §9 row (unconfigured
# adopters never invoke this script at all -- AC-4).
# Downstream: the two returned minute counts are handed, unmodified, to each
# adapter's own post-and-verify logic; this script issues no network request.
# Spec: archive/BTG-315/spec.md (Proposed Design, Core tooling); decisions.md
# DEC-003 (split formula), DEC-009 (OQ-7/OQ-8/OQ-9 rulings).
#
# WHY A SCRIPT AND NOT TWO ADAPTER-LOCAL COPIES (DEC-002). Two independent
# implementations of the same billing-split arithmetic is the drift shape
# BTG-112 DEC-002 and Behavior 6 exist to prevent: a fix landing in one
# adapter and not the other would silently diverge the split between
# trackers. One script called by both adapters makes agreement STRUCTURAL.
#
#   INVARIANT -- the resolved factor never appears on stdout or stderr (AC-1
#   R6). The caller supplies a stage and a whole-minute duration and receives
#   two finished minute counts ONLY.
#
# Contract:
#   Usage:  worklog-split.sh --stage <id> --minutes <whole-minutes> [--root <dir> | --org <file>]
#   --org <file> (BTG-317), when given, names the org file DIRECTLY -- the
#   §19 table is read from exactly that file, mirroring
#   org-binding-resolve.sh's own --org. --root is ignored when --org is
#   given. Without --org, --root behaves exactly as before (AC-4): the org
#   file is <root>/docs/agentic-sdlc/CLAIRE_ORG.md.
#   stdout: exactly two lines on success -- "operator_minutes=<n>" then
#           "agent_minutes=<n>", non-negative integers summing to --minutes.
#   stderr: NOTHING on the success path when no diagnostic applies. The single
#           non-halting diagnostic is `worklogsplit.factor.org_value_unusable
#           stage=<id> cause=<missing|invalid>` (never the value) when the
#           §19 value for the stage is missing or invalid and no valid
#           per-operator override applies (AC-1 R4, OQ-7). --org naming a
#           file's LOCATION alone never triggers this diagnostic (AC-3) --
#           only that file's own §19 content can.
#   exit 0: success (the diagnostic above may still have fired)
#   exit 1: IMPOSSIBLE_STATE worklogsplit.compute.out_of_domain -- a computed
#           leg fell outside 0..--minutes; refuses to print an answer
#   exit 2: usage error -- missing --stage, non-integer --minutes, an
#           unknown argument, or (AC-5) --org GIVEN naming a value that is
#           missing, unreadable, a directory, or an EMPTY/whitespace-only
#           string (W-1 / cycle-1 B2: an explicit empty --org is a usage
#           error, never treated as "--org not given"); this NEVER falls
#           back to the root's org file -- `worklogsplit.org.unreadable`
#           names the failure. --org as the FINAL argument with no value
#           also exits 2 naming `--org` (W-7 / OQ-3 (b)), guarded before the
#           argument shift so it never hangs, as org-binding-resolve.sh's
#           own last-argument guard does. --stage, --minutes and --root keep
#           their pre-existing trailing-flag behavior (out of scope).
#
# THE ACCEPT GRAMMAR (AC-1 R5 / OQ-8; PROD_CLAIRE-042's overflow closed): whole
# numbers, decimals, and the leading-dot form (`.5`), value in the closed
# interval 0..1, at most 9 significant fractional digits once trailing zeros
# are stripped. A trailing dot (`1.`), a sign, a suffix or padding whitespace
# never match. This pattern is registered verbatim in
# docs/policies/claire-surfaces.md's `CLAIRE_WORKLOG_FACTOR_<STAGE>` rows;
# WLS_ACCEPT_PATTERN below is the one definition both read (S-1.10 diffs them).
#
# THE TWO POLARITIES, deliberately different (mirroring stage-effort.sh
# DEC-003, extended by BTG-315 OQ-7):
#   * A PER-OPERATOR OVERRIDE (`CLAIRE_WORKLOG_FACTOR_<STAGE>`) that fails the
#     accept grammar is QUIETLY IGNORED in favour of the §19 value -- no halt,
#     no warning (BTG-112 DEC-003 parity).
#   * A §19 value that is MISSING (no section, no row for the stage, or an
#     unknown stage id) or INVALID (fails the accept grammar) resolves to `1`
#     (all operator) and emits the non-halting warning above. A missing
#     binding is louder than a missing preference (Behavior 5).
#
# SOURCEABLE, as well as directly executable: sourcing this file (as the
# BTG-315 test harness does) defines the functions below and performs no I/O
# and no argument dispatch -- only a direct invocation runs the dispatch block
# at the end (the live-verification-projectkey.sh BTG-245 pattern).

set -u

_self="${BASH_SOURCE[0]}"
[[ "$_self" == */* ]] || _self="./$_self"
ROOT="$(cd "${_self%/*}/../.." && pwd)"

WLS_ACCEPT_PATTERN='^([0-9]+(\.[0-9]+)?|\.[0-9]+)$'

# wls_var_name <stage> -- the override variable name, derived MECHANICALLY:
# uppercase the stage id and map `-` to `_` (identical rule to
# stage-effort.sh:99, restated once here rather than shared, since the two
# scripts serve different ledgers and this is a one-line rule).
wls_var_name() {
  printf 'CLAIRE_WORKLOG_FACTOR_%s' "$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
}

# wls_factor_parse <raw> -- the accept grammar (OQ-8) plus normalization. On
# acceptance, sets WLS_MANTISSA / WLS_SCALE (factor == MANTISSA / SCALE) and
# returns 0. On any rejection, returns 1 and leaves them untouched.
wls_factor_parse() {
  local raw="$1" intpart fracpart intval
  if [[ "$raw" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
    intpart="${BASH_REMATCH[1]}"; fracpart="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^([0-9]+)$ ]]; then
    intpart="${raw}"; fracpart=""
  elif [[ "$raw" =~ ^\.([0-9]+)$ ]]; then
    intpart="0"; fracpart="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  fracpart="$(printf '%s' "$fracpart" | sed 's/0*$//')"
  [[ ${#fracpart} -le 9 ]] || return 1
  # STRING comparison only, never arithmetic (review cycle-1 B1): an integer
  # part of unbounded length (e.g. 2^64) is out of range regardless of what
  # it evaluates to, and `$((10#$intpart))` on a value that long overflows a
  # 64-bit bash arithmetic context and silently wraps into something that
  # LOOKS in-range. Strip leading zeros as a string first; the result is
  # in-range iff it is exactly "0" or "1" -- both single characters, so no
  # arithmetic on an attacker-controlled-length string is ever performed.
  local stripped; stripped="$(printf '%s' "$intpart" | sed 's/^0*//')"
  [[ -z "$stripped" ]] && stripped="0"
  [[ "$stripped" == "0" || "$stripped" == "1" ]] || return 1
  intval="$stripped"
  # intval == 1 is only in range when the (now trailing-zero-stripped)
  # fractional part is empty, i.e. the value is exactly 1.
  [[ "$intval" == "0" || -z "$fracpart" ]] || return 1
  if [[ -n "$fracpart" ]]; then
    WLS_MANTISSA=$((10#${intpart}${fracpart}))
    WLS_SCALE=$((10 ** ${#fracpart}))
  else
    WLS_MANTISSA="$intval"
    WLS_SCALE=1
  fi
  return 0
}

# wls_org_value <stage> <org-file> -- the §19 table's raw cell text for
# <stage> in the given org file, section-scoped on the "Worklog Attribution
# Split" heading (numbered or not, mirroring org-binding-parse.sh's
# section_region ordinal rule) and NEVER a file-wide grep (R-6: keeps
# stage-effort.sh's section 12 `head -1` grep from ever reaching this table,
# and vice versa). Returns 1 -- "missing" -- when the org file, the section,
# or the stage's row is absent. The caller (wls_resolve_factor) is the one
# that decides WHICH file this is -- an explicit --org file (BTG-317 AC-1)
# or <root>/docs/agentic-sdlc/CLAIRE_ORG.md (AC-4) -- this function only
# ever reads the file it is given.
wls_org_value() {
  local stage="$1" org="$2" region row val
  [[ -f "$org" ]] || return 1
  region="$(awk '
    /^## ([0-9]+\. )?Worklog Attribution Split[[:space:]]*$/ { grab=1; next }
    grab && /^## /                                           { exit }
    grab                                                      { print }
  ' "$org")"
  [[ -n "$region" ]] || return 1
  row="$(printf '%s\n' "$region" | grep -E "^\|[[:space:]]*\`$stage\`" | head -1)"
  [[ -n "$row" ]] || return 1
  val="$(printf '%s\n' "$row" | sed -n 's/.*\*\*\([^*]*\)\*\*.*/\1/p')"
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

# wls_resolve_factor <stage> <root> [org] -- the full resolution chain (AC-1
# R2-R4). <org>, when non-empty, names the org file DIRECTLY (BTG-317 AC-1)
# and <root> is ignored; when empty, <root>/docs/agentic-sdlc/CLAIRE_ORG.md
# is used exactly as before this ticket (AC-4 backward compatibility).
# Always sets WLS_MANTISSA / WLS_SCALE. Sets WLS_WARN_CAUSE to "missing" or
# "invalid" when the §19 value had to be defaulted; leaves it empty
# otherwise.
WLS_WARN_CAUSE=""
wls_resolve_factor() {
  local stage="$1" root="$2" org_override="${3:-}" var override orgfile orgval rc
  WLS_WARN_CAUSE=""
  var="$(wls_var_name "$stage")"
  override="$(printenv "$var" 2>/dev/null)" || override=""
  if [[ -n "$override" ]] && wls_factor_parse "$override"; then
    return 0
  fi
  if [[ -n "$org_override" ]]; then
    orgfile="$org_override"
  else
    orgfile="$root/docs/agentic-sdlc/CLAIRE_ORG.md"
  fi
  orgval="$(wls_org_value "$stage" "$orgfile")"; rc=$?
  if [[ "$rc" -eq 0 ]] && wls_factor_parse "$orgval"; then
    return 0
  fi
  WLS_MANTISSA=1
  WLS_SCALE=1
  if [[ "$rc" -ne 0 ]]; then
    WLS_WARN_CAUSE="missing"
  else
    WLS_WARN_CAUSE="invalid"
  fi
  return 0
}

# wls_split <minutes> <mantissa> <scale> -- DEC-003's formula, fixed-point
# integer arithmetic only (PROD_CLAIRE-042): the agent leg is the entry times
# (1 - factor), floored to the next-lower 15-minute increment; the operator
# leg takes the remainder, so the two always sum to <minutes> and any
# off-boundary remainder lands on the operator (OQ-9). A defensive
# post-condition refuses any leg outside 0..<minutes> -- unreachable through
# wls_resolve_factor's own output (mantissa is always in 0..scale there), but
# checked here because this function is also the OS-1.1 seam's direct target.
wls_split() {
  local minutes="$1" mantissa="$2" scale="$3" diff agent operator
  diff=$(( scale - mantissa ))
  agent=$(( (minutes * diff) / (15 * scale) * 15 ))
  operator=$(( minutes - agent ))
  if (( agent < 0 || agent > minutes || operator < 0 )); then
    echo "worklogsplit: seam_type=IMPOSSIBLE_STATE event_name=worklogsplit.compute.out_of_domain minutes=$minutes computed_agent=$agent" >&2
    return 1
  fi
  WLS_OPERATOR="$operator"
  WLS_AGENT="$agent"
  return 0
}

# --- dispatch (direct execution only; sourcing stops here) -----------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  STAGE=""
  MINUTES=""
  ORG_ARG=""
  ORG_GIVEN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stage)   STAGE="${2:-}"; shift 2 ;;
      --minutes) MINUTES="${2:-}"; shift 2 ;;
      --root)    ROOT="${2:-}"; shift 2 ;;
      --org)
        # OQ-3 (b), W-7: guarded BEFORE the shift -- a value-less trailing
        # --org must never reach `shift 2` with only one argument left,
        # which is what hangs the parser (mirrors
        # org-binding-resolve.sh:107's own last-argument guard).
        if [[ $# -lt 2 ]]; then
          echo "worklog-split: --org requires a value (worklogsplit.org.unreadable)" >&2
          exit 2
        fi
        ORG_GIVEN=1; ORG_ARG="$2"; shift 2 ;;
      *) echo "worklog-split: unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$STAGE" ]]; then
    echo "worklog-split: --stage <id> is required" >&2
    exit 2
  fi
  if [[ ! "$MINUTES" =~ ^[0-9]+$ ]]; then
    echo "worklog-split: --minutes must be a whole number of minutes, got: '$MINUTES'" >&2
    exit 2
  fi
  # AC-5 / W-1 (cycle-1 B2): a GIVEN --org that does not name a readable
  # regular file fails loud HERE, before wls_resolve_factor ever runs -- it
  # NEVER falls back to the root's org file (there is no code path left
  # that could). Tracked via ORG_GIVEN, separately from ORG_ARG's value, so
  # an EXPLICIT empty or whitespace-only value is rejected exactly like a
  # missing/unreadable one, rather than being indistinguishable from
  # "--org was never passed" (R5-1).
  if (( ORG_GIVEN )) && { [[ -z "$ORG_ARG" ]] || [[ ! -f "$ORG_ARG" ]] || [[ ! -r "$ORG_ARG" ]]; }; then
    echo "worklog-split: --org file not found or unreadable: $ORG_ARG (worklogsplit.org.unreadable)" >&2
    exit 2
  fi

  WLS_MANTISSA=0
  WLS_SCALE=1
  wls_resolve_factor "$STAGE" "$ROOT" "$ORG_ARG"
  if [[ -n "$WLS_WARN_CAUSE" ]]; then
    echo "worklogsplit: seam_type=SEAM_VIOLATION event_name=worklogsplit.factor.org_value_unusable stage=$STAGE cause=$WLS_WARN_CAUSE" >&2
  fi

  if ! wls_split "$MINUTES" "$WLS_MANTISSA" "$WLS_SCALE"; then
    exit 1
  fi

  printf 'operator_minutes=%s\n' "$WLS_OPERATOR"
  printf 'agent_minutes=%s\n' "$WLS_AGENT"
  exit 0
fi
