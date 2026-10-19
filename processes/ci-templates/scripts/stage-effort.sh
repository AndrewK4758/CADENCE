#!/usr/bin/env bash
#
# stage-effort.sh -- BTG-112: the SINGLE site that resolves a per-stage review
#                    multiplier and renders one stage's recorded effort.
#
# Bounded context: CLAIRE framework governance / the realized-effort audit
# ledger (`stage_effort[].effort` + `actual_effort` in `specs/{id}/metadata.yaml`).
# Invariant relied on from outside this boundary: `CLAIRE_ORG.md` section 12
# (Actual Effort Accumulation) is the SINGLE source of the per-stage review
# multiplier values and of the multiply-then-round-UP-to-15m rule; this script
# READS that table live and embeds no value of its own.
#
# Upstream: the seven effort-recording sites -- artifacts/commands/{triage,
# write-spec,implement,review-code,maintain,elicit}.md and
# artifacts/roles/claire-archivist.md -- each call this script at their stage's
# completion instead of performing the arithmetic themselves.
# Downstream: the returned duration string is written verbatim as the
# `stage_effort[].effort` value and added to `actual_effort`.
# Spec: archive/BTG-112/spec.md (Proposed Design); decisions.md DEC-002.
#
# WHY A SCRIPT AND NOT SEVEN PROSE INSTRUCTIONS (DEC-002). Seven independent
# copies of a resolution instruction is the drift shape BTG-002 and ADR_CLAIRE-0015
# exist to prevent, and PROD_CLAIRE-005 is the recorded case where section 12's rule
# was correct for 90+ entries and then silently stopped being executed. One
# script called seven times makes agreement STRUCTURAL rather than
# instructional. It also closes AC-11's new leak vector by construction:
#
#   INVARIANT -- the multiplier value never appears on stdout or stderr and is
#   never returned to the caller. The caller supplies a stage and an observed
#   time and receives a finished duration ONLY. An agent cannot write down a
#   number it was never given.
#
# Contract:
#   Usage:  stage-effort.sh --stage <triage|spec|implementation|code-review|
#                                    maintainer|archive>
#                           --observed <whole-minutes>
#                           [--root <dir>]
#   stdout: exactly one line -- the canonical section 12 rendering of the
#           computed duration (e.g. "45m", "1h 15m", "0m"). Nothing else is
#           ever printed.
#   stderr: NOTHING on the success path -- including when an override is
#           ignored (AC-4's quiet-ignore; see below).
#   exit 0: success
#   exit 2: usage error -- unknown stage, non-integer --observed, or an
#           UNPARSEABLE section 12 table.
#
# THE TWO POLARITIES, deliberately different (DEC-003):
#   * An OPERATOR-SUPPLIED OVERRIDE that fails the accept grammar is QUIETLY
#     IGNORED in favour of the section 12 value -- no halt, no warning, output
#     byte-identical to an unset run. This is a requester-chosen deviation from
#     CLAIRE_DIRECTIVES.md Behavior 5 (fail loud), recorded as BTG-112 DEC-003, and it is
#     scoped to exactly this one input class.
#   * An UNRESOLVABLE DEFAULT (the section 12 table cannot be parsed) or a
#     CALLER BUG (unknown stage, non-integer observed) is FAIL-LOUD: exit 2
#     naming the cause. A missing personal calibration is not a missing binding.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE=""
OBSERVED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)    STAGE="${2:-}"; shift 2 ;;
    --observed) OBSERVED="${2:-}"; shift 2 ;;
    --root)     ROOT="${2:-}"; shift 2 ;;
    *) echo "stage-effort: unknown argument: $1" >&2; exit 2 ;;
  esac
done

ORG_FILE="$ROOT/docs/agentic-sdlc/CLAIRE_ORG.md"

# --- Fail-loud caller validation --------------------------------------------
# An unknown stage and an unparseable table both leave the multiplier
# unresolved, but they are reported DISTINCTLY: collapsing them would tell an
# operator to go and repair a section 12 table that is perfectly fine. The
# stage set is the workflow lifecycle vocabulary, not a multiplier value, so
# naming it here leaks nothing.
case "$STAGE" in
  triage|spec|implementation|code-review|maintainer|archive) ;;
  "") echo "stage-effort: --stage <id> is required" >&2; exit 2 ;;
  *)  echo "stage-effort: unknown stage id: '$STAGE' (expected one of triage, spec, implementation, code-review, maintainer, archive)" >&2; exit 2 ;;
esac

if [[ ! "$OBSERVED" =~ ^[0-9]+$ ]]; then
  echo "stage-effort: --observed must be a whole number of minutes, got: '$OBSERVED'" >&2
  exit 2
fi

# --- Resolve the multiplier -------------------------------------------------
# 1. Derive the variable name MECHANICALLY from the stage id: uppercase it and
#    map `-` to `_`. One derivation rule covers all six names and survives any
#    future stage id -- section 12 states the rule, not six literal names.
#    The `-` -> `_` mapping is why the code-review variable is spelled
#    _CODE_REVIEW: a hyphen is not a valid POSIX shell identifier character, so
#    the hyphenated form would be settable only out-of-band and the feature
#    would become runtime-dependent (BTG-112 DEC-001).
VAR="CLAIRE_STAGE_EFFORT_MULTIPLIER_$(printf '%s' "$STAGE" | tr '[:lower:]-' '[:upper:]_')"

# 2. Read it with `printenv`, never `$VAR` expansion (DEC-001). An unset
#    variable is simply an empty read here -- not an error.
OVERRIDE="$(printenv "$VAR" 2>/dev/null)" || OVERRIDE=""

# 3. The accept grammar is an ALLOWLIST, never a denylist of bad forms: whole
#    numbers and decimals, the closed interval zero-to-one included, and NO
#    `x`/multiplication-sign suffix. A denylist would fail OPEN on an
#    unforeseen input, and the quiet-ignore polarity would make that failure
#    silent.
MULTIPLIER=""
if [[ "$OVERRIDE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  MULTIPLIER="$OVERRIDE"
else
  # Quiet fallback to the section 12 table. Nothing is reported: "quietly" is
  # defined as output byte-identical to an unset run.
  ROW="$(grep -E "^\|[[:space:]]*\`$STAGE\`" "$ORG_FILE" 2>/dev/null | head -1)"
  if [[ "$ROW" =~ \*\*([0-9]+(\.[0-9]+)?)× ]]; then
    MULTIPLIER="${BASH_REMATCH[1]}"
  else
    # FAIL LOUD (Behavior 5). The quiet-ignore polarity is scoped to the
    # OVERRIDE value only; an unresolvable DEFAULT is never guessed, never
    # substituted, and never silently treated as one.
    echo "stage-effort: cannot resolve the '$STAGE' multiplier from the section 12 stage table in $ORG_FILE -- the table is absent, unparseable, or carries no row for this stage; refusing to guess a default" >&2
    exit 2
  fi
fi

# --- Compute -----------------------------------------------------------------
# Fixed-point integer arithmetic, never floating point: the product of an
# observed time and a decimal multiplier must round UP EXACTLY, and a float
# representation of a value like the section 12 defaults can land a hair above
# an exact boundary and round a correct 45 up to 60.
#
# Split the multiplier into its digits: concatenating the integer and
# fractional parts IS the mantissa, and the fractional digit count is the
# power of ten. `10#` forces base 10 so a leading zero is never read as octal.
if [[ "$MULTIPLIER" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
  MANTISSA=$(( 10#${BASH_REMATCH[1]}${BASH_REMATCH[2]} ))
  SCALE=$(( 10 ** ${#BASH_REMATCH[2]} ))
else
  MANTISSA=$(( 10#$MULTIPLIER ))
  SCALE=1
fi

TOTAL=$(( OBSERVED * MANTISSA ))   # = product * SCALE

if [[ "$TOTAL" -eq 0 ]]; then
  # THE ZERO EXIT (BTG-112 AC-5). A zero product records a REAL zero-minute
  # stage rather than being lifted to the 15-minute floor. The rule keys on the
  # PRODUCT, not on the multiplier -- so zero observed minutes with any
  # multiplier lands here too, and every spelling of a zero multiplier ("0",
  # "0.0", "0.000") resolves identically because the test is on the computed
  # product, never on the raw string.
  #
  # Reachable ONLY through a per-operator override: the shipped section 12
  # defaults are non-zero, so the default path never yields a zero stage
  # (DEC-010 -- a committed zero default is out of contract for BTG-112).
  MINUTES=0
else
  # Round UP to the next 15-minute increment, never down. Integer ceiling
  # division, so the 15-minute floor is AUTOMATIC rather than a second clamp:
  # any positive product, however small, yields at least one increment. That is
  # what keeps the zero exit above from swallowing the floor.
  STEP=$(( SCALE * 15 ))
  MINUTES=$(( ( (TOTAL + STEP - 1) / STEP ) * 15 ))
fi

# --- Render ------------------------------------------------------------------
# The section 12 Format algorithm, verbatim: h = t div 60, m = t mod 60;
# "{h}h {m}m" when both are positive, "{h}h" when m is zero, "{m}m" when h is
# zero. A zero component is dropped and there is exactly one ASCII space
# between two present components. t = 0 therefore renders "0m" -- section 12's
# own defensive base case, which BTG-112 makes reachable.
H=$(( MINUTES / 60 ))
M=$(( MINUTES % 60 ))
if   (( H > 0 && M > 0 )); then echo "${H}h ${M}m"
elif (( H > 0 ));          then echo "${H}h"
else                            echo "${M}m"
fi
