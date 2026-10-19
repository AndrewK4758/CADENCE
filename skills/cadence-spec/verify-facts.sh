#!/usr/bin/env bash
# verify-facts.sh -- BTG-331. Mechanical fact-checker for a CADENCE spec, plus
# the Gate 1 ruling-label checker /cadence-implement's Prerequisites consult.
#
# Bounded context: CADENCE framework tooling / the registered /cadence-spec
# surface (docs/policies/cadence-surfaces.md), cross-referenced from
# /cadence-implement and the cadence-implementer role (Prerequisites step 5).
# Invariant relied on from outside this boundary: this check applies only to
# a spec carrying the sentinel line `**Gate 1 rulings:** required` in its
# Open Questions -- every archived or in-flight spec authored before BTG-331
# lacks it, and this script never treats that absence as a failure (WARN in
# facts mode, "not required" in rulings mode). See archive/BTG-331/spec.md
# (Proposed Design -> Sidecar interface) for the design rationale.
#
# Usage:
#   verify-facts.sh [--base <ref>] <ticket-id>    # facts mode (default HEAD)
#   verify-facts.sh --rulings <ticket-id>         # rulings mode
#
# Where it looks: resolves specs/<id>/ then archive/<id>/, same idiom as
# verify-spec.sh -- neither present is a loud exit 1 naming both roots.
#
# stdout facts:   PASS|FAIL|WARN|UNVERIFIABLE  files-affected <type> <path> [-- reason]
#                 PASS|FAIL|WARN|UNVERIFIABLE  citation <path>:<spec> [-- reason]
#                 <spec> is a line number, a range (N-M) or a comma-separated
#                 list of numbers/ranges (e.g. "81-91", "73,304-321") -- the
#                 MAX numeric endpoint is checked (cycle-2 code-review B1).
# stdout rulings: RULING gate=<n> item=<id> value=<v> label=<diverged|examined|accepted-as-presented>
#                 MISSING gate=1 item=<id>
#                 SUMMARY required=<n> missing=<n> diverged=<n> examined=<n> accepted-as-presented=<n>
#
# Exit codes: 0 = clean (or nothing required) ; 1 = a checked fact FAILed
# (sentinel present), a required Gate 1 ruling is missing/malformed, an
# impossible state was found, or a usage/precondition error occurred.
#
# Read-only. Writes nothing, mutates nothing -- a human appends ruling lines
# to decisions.md by hand; this script only reads them back.
#
# PORTABILITY: bash + git/awk/grep/sed only (II_CADENCE-013, busybox-safe CI).
# No symbol resolution, no sha256 -- Replaceability (spec.md Additional Facets).

set -u

usage() {
  echo "Usage: $0 [--base <ref>] <ticket-id>" >&2
  echo "       $0 --rulings <ticket-id>" >&2
  exit 1
}

MODE="facts"
BASE="HEAD"
TICKET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rulings) MODE="rulings"; shift ;;
    --base)
      [[ $# -ge 2 ]] || usage
      BASE="$2"; shift 2 ;;
    -*) usage ;;
    *)
      [[ -z "$TICKET" ]] || usage
      TICKET="$1"; shift ;;
  esac
done
[[ -n "$TICKET" ]] || usage

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../../.." && pwd)"

# verify-facts-lib.sh (BTG-331 cycle 2, DEC-011): check_citation and
# compute_label live there to hold this file under the 400-line Facet 3
# ceiling. Sourced from THIS FILE's own directory (not $ROOT), so it resolves
# in both the neutral source tree and the compiled .agents/skills/cadence-spec/
# tree -- sidecar-completeness-gate.sh mirrors the whole directory.
if [[ ! -f "$SELF_DIR/verify-facts-lib.sh" ]]; then
  echo "ERROR: required module not found: $SELF_DIR/verify-facts-lib.sh" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$SELF_DIR/verify-facts-lib.sh"

# Resolve the ticket's artifact root -- specs/<id> first, else archive/<id>/
# (same two-branch, loud-miss shape as verify-spec.sh).
if   [[ -d "$ROOT/specs/$TICKET"   ]]; then TICKET_REL="specs/$TICKET"
elif [[ -d "$ROOT/archive/$TICKET" ]]; then TICKET_REL="archive/$TICKET"
else
  echo "ERROR: no artifacts for $TICKET -- searched specs/$TICKET/ and archive/$TICKET/" >&2
  exit 1
fi
TICKET_DIR="$ROOT/$TICKET_REL"
SPEC="$TICKET_DIR/spec.md"
DECISIONS="$TICKET_DIR/decisions.md"
DESIGN_OPTIONS="$TICKET_DIR/design-options.md"

[[ -f "$SPEC" ]] || { echo "ERROR: spec.md missing at $TICKET_REL/spec.md" >&2; exit 1; }

echo "verify-facts: $TICKET_REL"

sentinel_present() {
  grep -qF '**Gate 1 rulings:** required' "$SPEC"
}

# ==========================================================================
# Facts mode
# ==========================================================================

FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0
UNVERIFIABLE_COUNT=0

# report_fact <verdict> <category> <target> [reason]
# verdict is PASS|FAIL|UNVERIFIABLE. A FAIL is downgraded to WARN (and does
# NOT count toward the exit-1 tally) when the sentinel is absent -- a
# pre-BTG-331 spec is never retroactively rejected. Never silent either way.
report_fact() {
  local verdict="$1" category="$2" target="$3" reason="${4:-}"
  local final="$verdict"
  case "$verdict" in
    FAIL)
      if [[ "$SENTINEL" -eq 1 ]]; then
        final="FAIL"; FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        final="WARN"; WARN_COUNT=$((WARN_COUNT + 1))
      fi
      ;;
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    UNVERIFIABLE) UNVERIFIABLE_COUNT=$((UNVERIFIABLE_COUNT + 1)) ;;
  esac
  if [[ -n "$reason" ]]; then
    printf '%s %s %s -- %s\n' "$final" "$category" "$target" "$reason"
  else
    printf '%s %s %s\n' "$final" "$category" "$target"
  fi
}

check_files_affected_row() { # <path> <type>
  local path="$1" type="$2"
  # Own-ticket specs/<id>/ (or archive/<id>/) paths are never verifiable
  # facts about this spec's effect on the tree -- no line at all (R1 edge case).
  [[ "$path" == specs/"$TICKET"/* || "$path" == archive/"$TICKET"/* ]] && return 0
  # Placeholder or glob path -- unverifiable, never failed.
  if [[ "$path" == *'{'* || "$path" == *'*'* ]]; then
    report_fact UNVERIFIABLE files-affected "$type $path"
    return 0
  fi
  case "$type" in
    Add)
      if git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
        report_fact FAIL files-affected "$type $path" "path exists at base ($BASE)"
      else
        report_fact PASS files-affected "$type $path"
      fi
      ;;
    Modify|Delete)
      if git -C "$ROOT" cat-file -e "$BASE:$path" 2>/dev/null; then
        report_fact PASS files-affected "$type $path"
      else
        report_fact FAIL files-affected "$type $path" "path is absent at base ($BASE)"
      fi
      ;;
    *)
      report_fact FAIL files-affected "$type $path" "unrecognized change type: $type"
      ;;
  esac
}

facts_mode() {
  if ! git -C "$ROOT" rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null 2>&1; then
    echo "ERROR: base ref does not resolve: $BASE" >&2
    exit 1
  fi

  SENTINEL=0
  sentinel_present && SENTINEL=1

  local path type
  while IFS=$'\t' read -r path type; do
    [[ -n "$path" ]] || continue
    check_files_affected_row "$path" "$type"
  done < <(awk -F'|' '
    /^### Files Affected/ { insec=1; rownum=0; next }
    /^#/ { insec=0 }
    insec && /^\|/ {
      rownum++
      if (rownum <= 2) next
      p=$2; t=$4
      gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^`|`$/, "", p)
      gsub(/^[ \t]+|[ \t]+$/, "", t)
      print p "\t" t
    }
  ' "$SPEC")

  local token tpath tspec
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    tpath="${token%:*}"
    tspec="${token##*:}"
    check_citation "$tpath" "$tspec"
  done < <(
    awk '/^[[:space:]]*```/{f=!f; next} !f' "$SPEC" \
      | grep -oE '`[^`]+:[0-9]+([,-][0-9]+)*`' \
      | sed -e 's/^`//' -e 's/`$//' \
      | sort -u
  )

  echo "SUMMARY pass=$PASS_COUNT fail=$FAIL_COUNT warn=$WARN_COUNT unverifiable=$UNVERIFIABLE_COUNT"

  if [[ "$SENTINEL" -eq 1 && "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# ==========================================================================
# Rulings mode
# ==========================================================================

# compute_label -- R7 (BTG-331 code-review cycle 1, B3). Now defined in the
# sourced verify-facts-lib.sh, generalized to iterate EVERY backticked token
# in <why> (not just the first) -- see that file for the full contract.

rulings_mode() {
  SENTINEL=0
  sentinel_present && SENTINEL=1
  if [[ "$SENTINEL" -eq 0 ]]; then
    echo "rulings not required for $TICKET -- spec.md carries no Gate 1 rulings sentinel"
    exit 0
  fi

  if [[ ! -f "$DECISIONS" ]]; then
    echo "ERROR: decisions.md missing for $TICKET -- required because spec.md carries the Gate 1 rulings sentinel" >&2
    exit 1
  fi

  local -a REQUIRED_OQ=()
  while IFS= read -r oq; do
    [[ -n "$oq" ]] && REQUIRED_OQ+=("$oq")
  done < <(
    awk '/^### Open Questions/{f=1; next} /^#/{f=0} f' "$SPEC" \
      | grep -oE 'OQ-[0-9]+' | sort -u -t- -k2,2n
  )

  local design_required=0
  [[ -f "$DESIGN_OPTIONS" ]] && design_required=1

  declare -A RULING_VALUE=() RULING_WHY=()
  local -a MALFORMED=()
  local line

  while IFS= read -r line; do
    if [[ "$line" == "Gate 1 Design Exploration outcome:"* ]]; then
      # B2 (code review cycle 1): match the three literal outcome values
      # explicitly, never a greedy `.+`, which misparsed a reason containing
      # " -- " and silently dropped an unrecognized value. Any other outcome
      # line is reported malformed, quoted, same as a malformed ruling line.
      if [[ "$line" =~ ^Gate\ 1\ Design\ Exploration\ outcome:\ (accepted\ as\ recommended|accepted\ with\ amendment|overridden\ to\ a\ different\ option)\ --\ (.+)$ ]]; then
        local outcome="${BASH_REMATCH[1]}" val=""
        case "$outcome" in
          "accepted as recommended") val="agree" ;;
          "accepted with amendment") val="amend" ;;
          "overridden to a different option") val="override" ;;
        esac
        RULING_VALUE["1:design"]="$val"
        RULING_WHY["1:design"]="${BASH_REMATCH[2]}"
      else
        MALFORMED+=("$line")
      fi
    elif [[ "$line" =~ ^Gate\ [1-3]\ ruling: ]]; then
      if [[ "$line" =~ ^Gate\ ([1-3])\ ruling:\ ([A-Za-z0-9._-]+)\ --\ (agree|amend|override)\ --\ (.+)$ ]]; then
        local gate="${BASH_REMATCH[1]}" item="${BASH_REMATCH[2]}" val="${BASH_REMATCH[3]}" why="${BASH_REMATCH[4]}"
        RULING_VALUE["$gate:$item"]="$val"
        RULING_WHY["$gate:$item"]="$why"
      else
        MALFORMED+=("$line")
      fi
    fi
  done < <(awk '/^[[:space:]]*```/{f=!f; next} !f' "$DECISIONS")

  local -a PRINTED_KEYS=()
  local MISSING_COUNT=0 DIVERGED=0 EXAMINED=0 ACCEPTED=0
  local oq key label

  for oq in "${REQUIRED_OQ[@]}"; do
    key="1:$oq"
    PRINTED_KEYS+=("$key")
    if [[ -n "${RULING_VALUE[$key]+x}" ]]; then
      label="$(compute_label "${RULING_VALUE[$key]}" "${RULING_WHY[$key]}")"
      printf 'RULING gate=1 item=%s value=%s label=%s\n' "$oq" "${RULING_VALUE[$key]}" "$label"
      case "$label" in
        diverged) DIVERGED=$((DIVERGED + 1)) ;;
        examined) EXAMINED=$((EXAMINED + 1)) ;;
        accepted-as-presented) ACCEPTED=$((ACCEPTED + 1)) ;;
      esac
    else
      printf 'MISSING gate=1 item=%s\n' "$oq"
      MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
  done

  if [[ "$design_required" -eq 1 ]]; then
    key="1:design"
    PRINTED_KEYS+=("$key")
    if [[ -n "${RULING_VALUE[$key]+x}" ]]; then
      label="$(compute_label "${RULING_VALUE[$key]}" "${RULING_WHY[$key]}")"
      printf 'RULING gate=1 item=design value=%s label=%s\n' "${RULING_VALUE[$key]}" "$label"
      case "$label" in
        diverged) DIVERGED=$((DIVERGED + 1)) ;;
        examined) EXAMINED=$((EXAMINED + 1)) ;;
        accepted-as-presented) ACCEPTED=$((ACCEPTED + 1)) ;;
      esac
    else
      printf 'MISSING gate=1 item=design\n'
      MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
  fi

  # Gate 2/3 (and any non-required Gate 1) rulings: reported, never required,
  # and never counted in SUMMARY (spec.md AC-3 R6/S-3.2).
  local -a remaining=()
  local k printed
  for k in "${!RULING_VALUE[@]}"; do
    printed=0
    for key in "${PRINTED_KEYS[@]}"; do
      [[ "$k" == "$key" ]] && { printed=1; break; }
    done
    [[ "$printed" -eq 0 ]] && remaining+=("$k")
  done
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    label="$(compute_label "${RULING_VALUE[$k]}" "${RULING_WHY[$k]}")"
    printf 'RULING gate=%s item=%s value=%s label=%s\n' "${k%%:*}" "${k#*:}" "${RULING_VALUE[$k]}" "$label"
  done < <(printf '%s\n' "${remaining[@]+"${remaining[@]}"}" | sort)

  for line in "${MALFORMED[@]+"${MALFORMED[@]}"}"; do
    printf 'ERROR: malformed Gate ruling line: %s\n' "$line" >&2
  done

  local required_total=$(( ${#REQUIRED_OQ[@]} + design_required ))
  echo "SUMMARY required=$required_total missing=$MISSING_COUNT diverged=$DIVERGED examined=$EXAMINED accepted-as-presented=$ACCEPTED"

  if [[ "$MISSING_COUNT" -gt 0 || "${#MALFORMED[@]}" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

case "$MODE" in
  facts)   facts_mode ;;
  rulings) rulings_mode ;;
esac
