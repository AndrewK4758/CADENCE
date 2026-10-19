#!/usr/bin/env bash
#
# jira-lib.sh -- shared library for the /cadence-sync-jira operation scripts.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: the repository is the source of
# truth and Jira is the projection layer; this library never writes an owned
# artifact (never `metadata.yaml`), it only READS repo state and speaks REST v2
# to Jira. It is SOURCED by every operation script -- it is not an entry point and
# runs nothing on load.
#
# It exists so that no operation script re-implements a transport detail, a config
# key's fail-loud/default polarity, or the return-channel discipline. Contracts:
# jira-server-scripts.md (the script-contract sidecar) sections 1-4.
#
# Return-channel discipline (DEC-001), which every caller inherits:
#   stdout -- machine-readable `key=value` result lines ONLY (js_emit)
#   stderr -- the human-readable `syncjs.*` reported-condition stream (js_report)
#   exit   -- 0 ok / 1 fail-loud / 2 usage / 3 transport unreachable / 4 config HALT
#
# Credential handling (Facet 7): $JIRA_PAT is read from the environment at call
# time and handed to curl through a `-K-` stdin config block -- never a positional
# argument, a temp file, an artifact, or any output channel.

# Exit-code vocabulary (jira-server-scripts.md section 1)
JS_EXIT_OK=0
JS_EXIT_FAIL=1
JS_EXIT_USAGE=2
JS_EXIT_TRANSPORT=3
JS_EXIT_CONFIG=4

# --- Channels -------------------------------------------------------------
# js_emit <key> <value> -- one machine-readable result line on STDOUT.
js_emit() {
  printf '%s=%s\n' "$1" "$2"
}

# js_report <syncjs.condition> [detail...] -- one audit line on STDERR.
js_report() {
  local condition="$1"; shift
  printf '%s: %s\n' "$condition" "$*" >&2
}

# js_halt <exit-code> <syncjs.condition> [detail...] -- report and exit loud
# (never returns; a caller that wants to continue must not use it).
js_halt() {
  local code="$1" condition="$2"; shift 2
  js_report "$condition" "$@"
  exit "$code"
}

# js_worklog_skip_zero <syncjs.condition> <effort> <stage> <at> -- BTG-112 AC-9.
# A stage recording NO TIME has nothing to project: returns 0 (caller skips and
# ADVANCES the watermark) after reporting the audited condition, 1 otherwise.
# Body lives here, branch is one line at the call site (jira-worklog.sh sits
# against the 400-line agentic-DX ceiling, R-6). The condition id is passed in,
# not hardcoded, so it stays visible there and the parity gate finds the token.
# The advance mirrors skipped_already_logged and is deliberately UNLIKE the
# malformed branch, which withholds it because a malformed entry may still owe
# a projection once repaired; a zero entry never can (append-only, immutable),
# and withholding would leave a TRAILING zero entry re-reported forever
# (DEC-007). Reports stage/at/duration only, never a multiplier (surface 3).
js_worklog_skip_zero() {
  [[ "$2" == "0m" ]] || return 1
  js_report "$1" "stage=$3 at=$4 records no time (0m) -- posting nothing and advancing the watermark past it; the entry is append-only and immutable, so it can never later owe a projection"
  return 0
}

# --- Argument parsing -----------------------------------------------------
# js_argv_pair <syncjs.condition> "$@" -- guard a `--flag <value>` pair BEFORE the
# `shift 2` that consumes it.
#
# With exactly one argument left, `shift 2` fails and shifts NOTHING, so the
# surrounding `while [[ $# -gt 0 ]]` loop never advances: the script spins at
# 100% CPU with no output and no exit. That is the one failure mode Behavior 5
# cannot tolerate -- neither loud nor recoverable -- and it is reachable from the
# orchestrator itself, whose step table writes `--issue-key $KEY` unquoted with
# `$KEY` empty on the create path. So this is a live seam, not defensive padding.
js_argv_pair() {
  local condition="$1"; shift
  [[ $# -ge 2 ]] || js_halt "$JS_EXIT_USAGE" "$condition" \
    "$1 requires a value, but the argument list ends there"
}

# --------------------------------------------------------------------------
# Configuration (AC-7)
# --------------------------------------------------------------------------

# js_config_path -- $JIRA_SERVER_CONFIG when set, else the co-located
# `jira-server-config.json`.
js_config_path() {
  if [[ -n "${JIRA_SERVER_CONFIG:-}" ]]; then
    printf '%s\n' "$JIRA_SERVER_CONFIG"
  else
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-server-config.json"
  fi
}

# js_config_get <jq-filter> [jq-arg...] -- resolve one value from the config sidecar.
# Trailing arguments reach `jq` VERBATIM, so a caller BINDS an untrusted key with
# --arg instead of splicing it into the filter (B-11). Prints the value; returns
# non-zero printing nothing on absent/null, so callers decide the polarity (never a
# silent default). NB: `jq -e` is NOT used -- a *false* boolean would read as absent.
js_config_get() {
  local filter="$1" cfg value; shift
  cfg="$(js_config_path)"
  value="$(jq -r "$@" "$filter" "$cfg" 2>/dev/null)" || return 1
  [[ "$value" == "null" ]] && return 1
  printf '%s\n' "$value"
}

# js_config_map <block> <key> -- resolve `.<block>."<key>"` from the config.
# An unresolvable lookup is a config HALT, never a guess: a guessed issue type,
# priority, or transition target is an ungoverned decision (CLAUDE.md Behavior 5).
js_config_map() {
  local block="$1" key="$2" value
  if ! value="$(js_config_get '.[$b][$k]' --arg b "$block" --arg k "$key")"; then
    js_report syncjs.config.marker_unresolved \
      "no '$key' entry under '$block' in $(js_config_path)"
    return "$JS_EXIT_CONFIG"
  fi
  printf '%s\n' "$value"
}

# js_config_map2 <block> <key1> <key2> -- resolve `.<block>."<key1>"."<key2>"`,
# the two-level shape the workflow map uses (issue type -> repo status -> Jira
# status, and `global_transitions` -> Jira status -> transition id).
#
# Unlike js_config_map it does NOT halt on a miss: it returns non-zero, printing
# nothing, and the caller decides the polarity. That is deliberate -- an unmapped
# (issue type, status) pair is a legitimate "this workflow does not define that
# state", which the caller reports and skips, whereas a missing issue-type or
# priority mapping is an unresolvable projection. The lookup still lives HERE so
# no operation script reaches past this library into the raw config.
js_config_map2() {
  js_config_get '.[$b][$k1][$k2]' --arg b "$1" --arg k1 "$2" --arg k2 "$3" || return 1
}

# js_config_workflow_statuses <issue-type> -- every status THIS issue type's
# workflow map declares, one per line. It is the set an intermediate transition
# hop is allowed to step through, so the walk can never leave the governed
# workflow onto an arbitrary board state. It lives HERE, with every other config
# lookup, so no operation script reaches past this library into the raw config
# (AC-7) -- the same reason js_config_map2 does.
js_config_workflow_statuses() {
  js_config_get '.status_workflow_map[$t] | if type=="object" then (to_entries[].value) else empty end' --arg t "$1" || return 1
}

# js_config_require -- called at startup by every script. An absent or unparseable
# config sidecar HALTs rather than falling back to built-in assumptions: the
# instance mapping is adopter-owned, so proceeding would project guesses.
js_config_require() {
  local cfg; cfg="$(js_config_path)"
  if [[ ! -f "$cfg" ]]; then
    js_halt "$JS_EXIT_CONFIG" syncjs.config.absent \
      "the configuration sidecar was not found at $cfg (set \$JIRA_SERVER_CONFIG to override)"
  fi
  if ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
    js_halt "$JS_EXIT_CONFIG" syncjs.config.absent \
      "the configuration sidecar at $cfg is not a JSON object (malformed) -- refusing to proceed on guessed values"
  fi
}

# js_env_value <logical-name> -- read the environment variable whose NAME the
# config's `env` block binds (e.g. logical `base_url` -> `JIRA_BASE_URL`), so an
# adopter can rebind a name without editing a script.
js_env_value() {
  local logical="$1" name
  name="$(js_config_map env "$logical")" || return "$JS_EXIT_CONFIG"
  printf '%s\n' "${!name:-}"
}

# js_config_toggle <toggle-name> -- 0 when ENABLED, non-zero when DISABLED. The
# ABSENT-value polarity is per-key, preserved from the ticket that set it:
#   worklog_creation_enabled          absent => ENABLED  (BTG-064, opt-out)
#   acceptance_criteria_sync_enabled  absent => ENABLED  (BTG-046, opt-out)
#   assignment_reconciliation_enabled absent => DISABLED (BTG-014, opt-in)
# An explicit `true`/`false` always wins over the default.
js_config_toggle() {
  local toggle="$1" value default
  case "$toggle" in
    worklog_creation_enabled|acceptance_criteria_sync_enabled) default=enabled ;;
    assignment_reconciliation_enabled)                          default=disabled ;;
    *) js_report syncjs.config.marker_unresolved "unknown toggle: $toggle"; return "$JS_EXIT_CONFIG" ;;
  esac
  if ! value="$(js_config_get ".toggles.\"$toggle\"")"; then
    [[ "$default" == "enabled" ]] && return 0
    js_report syncjs.config.toggle_default_disabled "$toggle is absent -- resolving to its opt-in default (DISABLED)"
    return 1
  fi
  case "$value" in
    true)  return 0 ;;
    false) return 1 ;;
    *) js_report syncjs.config.marker_unresolved "$toggle must be true or false, found: '$value'"
       return "$JS_EXIT_CONFIG" ;;
  esac
}

# js_config_ordered_relation -- the ordered ("precedes") relation, as
# "<name>|<predecessor-slot>|<id>". Per-instance calibration, so an absent or
# CONTRADICTORY declaration HALTs here rather than defaulting at a call site: a
# guessed slot records ordering BACKWARDS on every link it writes.
#
# `name` is the adopter's declared type name and `id` its declared type id; both
# are only ANCHORS -- the live type is discovered from the instance by phrasing
# (jira-link-lib.sh), because on this org's instance the type is actually named
# `precedes ` (trailing space) and a name-matched projection links nothing.
#
# `inverted` and `predecessor_slot` describe the SAME calibration from two sides,
# so they can disagree only through a mis-edit: `inverted: true` means this
# instance renders the relation opposite to stock Jira (predecessor in the
# `inwardIssue` slot), `false` means stock convention (predecessor outward). A
# contradictory pair is not resolvable by picking one -- either choice writes
# half the instance's orderings backwards -- so it HALTs naming both values.
js_config_ordered_relation() {
  local name slot id inverted expect_slot
  name="$(js_config_get '.link_relations.precedes.name')" || name=""
  slot="$(js_config_get '.link_relations.precedes.predecessor_slot')" || slot=""
  id="$(js_config_get '.link_relations.precedes.id')" || id=""
  inverted="$(js_config_get '.link_relations.precedes.inverted')" || inverted=""
  case "$slot" in
    inwardIssue|outwardIssue) ;;
    *) js_report syncjs.config.marker_unresolved \
         "link_relations.precedes.predecessor_slot must be inwardIssue or outwardIssue, found: '$slot'"
       return "$JS_EXIT_CONFIG" ;;
  esac
  case "$inverted" in
    true)  expect_slot=inwardIssue ;;
    false) expect_slot=outwardIssue ;;
    *) js_report syncjs.config.marker_unresolved \
         "link_relations.precedes.inverted must be true or false, found: '$inverted' -- the instance calibration is never assumed"
       return "$JS_EXIT_CONFIG" ;;
  esac
  if [[ "$slot" != "$expect_slot" ]]; then
    js_report syncjs.config.marker_unresolved \
      "link_relations.precedes.inverted=$inverted implies predecessor_slot=$expect_slot, but the config declares '$slot' -- the two describe one calibration and cannot disagree; refusing to pick one and record half the orderings backwards"
    return "$JS_EXIT_CONFIG"
  fi
  if [[ -z "$name" ]]; then
    js_report syncjs.config.marker_unresolved "link_relations.precedes.name is absent -- the ordered relation type is never guessed"
    return "$JS_EXIT_CONFIG"
  fi
  printf '%s|%s|%s\n' "$name" "$slot" "$id"
}

# js_run_mode -- `headless` or `interactive`, from the config-bound env signal.
# DEC-011: the run is headless IFF that variable is TRUTHY (`1`/`true`/`yes`),
# case-insensitively. Absent, empty, an explicit negative, or anything
# unrecognised resolves to INTERACTIVE -- the fail-safe direction, because the
# only thing the headless mode authorizes is a human-gated overwrite. Under a
# "non-empty means headless" reading, `CADENCE_HEADLESS=0` (an operator saying
# NO) performs that overwrite on a present human's behalf. A misconfigured
# headless run merely stalls the one anomalous item, reported; it never writes.
#
# The binding itself is a config lookup, so an absent one HALTS here rather than
# being re-derived at a call site (AC-7: an adopter may rebind the name).
js_run_mode() {
  local name value
  name="$(js_config_map run_mode headless_env)" || return "$JS_EXIT_CONFIG"
  value="$(printf '%s' "${!name:-}" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes)   printf 'headless\n' ;;
    ''|0|false|no) printf 'interactive\n' ;;
    *) js_report syncjs.config.run_mode_unrecognized \
         "\$$name is '$value', which is neither truthy (1/true/yes) nor an explicit negative -- resolving to INTERACTIVE, the fail-safe direction"
       printf 'interactive\n' ;;
  esac
}

# js_config_capability -- the worklog post-add verification capability (BTG-064).
# FAIL-LOUD, the INVERSE of the opt-out toggles above: this is a
# framework-declared constant, so an absent, malformed, or non-allowlisted value
# HALTs and reports the offending value verbatim. It is NEVER silently resolved
# to `none` -- that would convert an unconfigured adapter into a sanctioned
# non-enforcing one. Only an EXPLICIT `none` sanctions non-enforcement.
js_config_capability() {
  local value
  value="$(js_config_get '.worklog_postcheck_capability')" || value=""
  # `spent-time-increment` is the YOUTRACK adapter's verification (its Spent time
  # only grows); the Jira adapter verifies absorption by the Remaining decrement
  # and has no implementation for the other. Allowlisting a value no branch
  # implements would turn every post into postcheck_failed, so it is NOT accepted
  # here (Behavior 2 -- nothing speculative). The YouTrack adapter keeps its own.
  case "$value" in
    remaining-estimate-decrement|none)
      printf '%s\n' "$value" ;;
    *)
      js_halt "$JS_EXIT_CONFIG" syncjs.config.marker_unresolved \
        "worklog_postcheck_capability in $(js_config_path) is absent or unrecognized: '$value' (allowed on this adapter: remaining-estimate-decrement | none; spent-time-increment is the YouTrack adapter's) -- never silently resolved to 'none'" ;;
  esac
}

# js_config_ceiling_mib -- the per-file attachment size ceiling (BTG-043).
# FAILS CLOSED: an absent, malformed, or non-positive value returns non-zero and
# emits NO value, so the caller references every attachment by URL and downloads
# none. An unbounded download is the unsafe direction.
js_config_ceiling_mib() {
  local value
  value="$(js_config_get '.attachment_size_ceiling_mib')" || value=""
  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  js_report syncjs.config.ceiling_unresolved \
    "attachment_size_ceiling_mib in $(js_config_path) is absent or unusable: '$value' -- failing CLOSED (reference every attachment, download none)"
  return "$JS_EXIT_CONFIG"
}

# --------------------------------------------------------------------------
# Owned data + transport (sourced) -- see jira-meta.sh / jira-rest.sh /
# jira-projection-math.sh
# --------------------------------------------------------------------------
# The `metadata.yaml` reader, the REST helpers, and the estimate-projection /
# duration-arithmetic pure functions (BTG-247) live in sibling modules so no
# file passes the 400-line DX ceiling. Callers source ONLY this file and get
# all four halves.
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-meta.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-rest.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-projectkey-lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-projection-math.sh"
