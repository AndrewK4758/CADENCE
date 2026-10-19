#!/usr/bin/env bash
#
# yt-lib.sh -- shared library for the /cadence-sync-youtrack operation scripts.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: the repository is the source of
# truth and YouTrack is the projection layer; this library never writes an owned
# artifact (never `metadata.yaml`), it only READS repo state and speaks the
# YouTrack REST API. It is SOURCED by every operation script -- it is not an
# entry point and runs nothing on load.
#
# It exists so that no operation script re-implements a transport detail, a
# config key's fail-loud/default polarity, or the return-channel discipline.
# Contracts: youtrack-scripts.md (the script-contract sidecar).
#
# Return-channel discipline (BTG-075 DEC-001, mirrored), which every caller
# inherits:
#   stdout -- machine-readable `key=value` result lines ONLY (yt_emit)
#   stderr -- the human-readable `syncyt.*` reported-condition stream (yt_report)
#   exit   -- 0 ok / 1 rejected / 2 usage / 3 transport unreachable / 4 config HALT
#
# Credential handling (Facet 7): the permanent token is read from the environment
# at call time and handed to curl through a `-K-` stdin config block -- never a
# positional argument, a temp file, an artifact, or any output channel.
#
# THIS ADAPTER SHARES NO CODE WITH /cadence-sync-jira. BTG-059 DEC-002 ruled that
# the two curated reference adapters carry no shared tracker-core, and BTG-176
# DEC-005/DEC-014 confirmed parity is FEATURE/SEMANTIC, not a byte-for-byte
# inventory. The shapes here rhyme with the sibling's because the owned data and
# the channel discipline are the same; the transport, the endpoints and the field
# model are YouTrack's own and are not translated from Jira's.

# Exit-code vocabulary (spec.md, Proposed Design -- Signatures)
YT_EXIT_OK=0
YT_EXIT_FAIL=1
YT_EXIT_USAGE=2
YT_EXIT_TRANSPORT=3
YT_EXIT_CONFIG=4

# --- Channels -------------------------------------------------------------
# yt_emit <key> <value> -- one machine-readable result line on STDOUT.
yt_emit() {
  printf '%s=%s\n' "$1" "$2"
}

# yt_report <syncyt.condition> [detail...] -- one audit line on STDERR.
yt_report() {
  local condition="$1"; shift
  printf '%s: %s\n' "$condition" "$*" >&2
}

# yt_halt <exit-code> <syncyt.condition> [detail...] -- report and exit loud
# (never returns; a caller that wants to continue must not use it).
yt_halt() {
  local code="$1" condition="$2"; shift 2
  yt_report "$condition" "$@"
  exit "$code"
}

# --------------------------------------------------------------------------
# Configuration (AC-3)
# --------------------------------------------------------------------------

# yt_config_path -- $YOUTRACK_SERVER_CONFIG when set, else the co-located
# `youtrack-server-config.json`.
yt_config_path() {
  if [[ -n "${YOUTRACK_SERVER_CONFIG:-}" ]]; then
    printf '%s\n' "$YOUTRACK_SERVER_CONFIG"
  else
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/youtrack-server-config.json"
  fi
}

# yt_config_get <jq-filter> [jq-arg...] -- resolve one value from the config
# sidecar. Trailing arguments reach `jq` VERBATIM, so a caller BINDS an untrusted
# key with --arg instead of splicing it into the filter. Prints the value;
# returns non-zero printing nothing on absent/null, so callers decide the
# polarity (never a silent default). NB: `jq -e` is NOT used -- a *false* boolean
# would read as absent.
yt_config_get() {
  local filter="$1" cfg value; shift
  cfg="$(yt_config_path)"
  value="$(jq -r "$@" "$filter" "$cfg" 2>/dev/null)" || return 1
  [[ "$value" == "null" ]] && return 1
  printf '%s\n' "$value"
}

# yt_config_map <block> <key> -- resolve `.<block>."<key>"` from the config.
# An unresolvable lookup is a config HALT, never a guess: a guessed Type,
# Priority or State is an ungoverned decision (CLAUDE.md Behavior 5), and on this
# instance it is also a guaranteed HTTP 400 -- an unmapped enum value is rejected
# with "An <value>-type entity with the specified name ({1}) was not found"
# (OBSERVED, spec sidecar 2 §C).
yt_config_map() {
  local block="$1" key="$2" value
  if ! value="$(yt_config_get '.[$b][$k]' --arg b "$block" --arg k "$key")"; then
    yt_report syncyt.config.marker_unresolved \
      "no '$key' entry under '$block' in $(yt_config_path)"
    return "$YT_EXIT_CONFIG"
  fi
  printf '%s\n' "$value"
}

# yt_config_map2 <block> <key1> <key2> -- resolve `.<block>."<key1>"."<key2>"`,
# the TWO-LEVEL shape `status_state_map` uses (YouTrack Type -> repo status ->
# State value), mirroring the sibling adapter's `js_config_map2`.
#
# THE POLARITY IS THIS ADAPTER'S, NOT THE SIBLING'S, and the difference is
# deliberate (BTG-176 DEC-077). `js_config_map2` returns non-zero silently and
# lets the caller decide, because Jira has a transition GRAPH -- an unmapped
# (type, status) pair there is a legitimate "this workflow does not define that
# state", which the sibling reports and skips. There is no graph here: State is
# an ordinary field, so an unmapped pair is not a state the workflow declines to
# offer, it is a projection this adapter cannot make. It HALTs, reporting BOTH
# keys -- a message naming only the status would send an operator to add a key
# that is already there, under a Type that is not.
#
# It never falls back to a flat lookup. A flat default is exactly the shape this
# correction removes: it would resolve every Type to one policy while the config
# said otherwise, and report success doing it.
yt_config_map2() {
  local block="$1" k1="$2" k2="$3" value
  if ! value="$(yt_config_get '.[$b][$k1][$k2]' --arg b "$block" --arg k1 "$k1" --arg k2 "$k2")"; then
    yt_report syncyt.config.marker_unresolved \
      "no '$k2' entry under '$block' -> '$k1' in $(yt_config_path) -- this map is resolved by (Type, status) and BOTH must be present; no state is guessed"
    return "$YT_EXIT_CONFIG"
  fi
  printf '%s\n' "$value"
}

# yt_config_require -- called at startup by every script. An absent or
# unparseable config sidecar HALTs rather than falling back to built-in
# assumptions: the instance mapping is adopter-owned, so proceeding would project
# guesses.
#
# The two arms report the SAME condition and the SAME exit code on purpose. An
# absent file and a file that cannot be read as configuration are one state for
# this adapter -- there is nothing to resolve -- and giving them separate
# vocabularies would make an operator learn two names for one problem.
#
# Halting HERE, before anything reads the environment, is load-bearing rather
# than tidy: this file binds the NAMES of the environment variables the transport
# reads, so a run that proceeded past an absent config would reach the instance
# with an empty Bearer token and collect a 401 -- reporting a CREDENTIAL problem
# for a CONFIGURATION problem.
yt_config_require() {
  local cfg; cfg="$(yt_config_path)"
  if [[ ! -f "$cfg" ]]; then
    yt_halt "$YT_EXIT_CONFIG" syncyt.config.absent \
      "the configuration sidecar was not found at $cfg (set \$YOUTRACK_SERVER_CONFIG to override)"
  fi
  if ! jq -e 'type == "object"' "$cfg" >/dev/null 2>&1; then
    yt_halt "$YT_EXIT_CONFIG" syncyt.config.absent \
      "the configuration sidecar at $cfg is not a JSON object (malformed) -- refusing to proceed on guessed values (set \$YOUTRACK_SERVER_CONFIG to point at a usable one)"
  fi
}

# yt_env_value <logical-name> -- read the environment variable whose NAME the
# config's `env` block binds (e.g. logical `base_url` -> `YOUTRACK_BASE_URL`), so
# an adopter can rebind a name without editing a script. The NAME is
# configuration; the VALUE is a credential and is never stored anywhere.
yt_env_value() {
  local logical="$1" name
  name="$(yt_config_map env "$logical")" || return "$YT_EXIT_CONFIG"
  printf '%s\n' "${!name:-}"
}

# yt_config_capability -- the worklog post-add verification capability.
#
# FAIL-LOUD, and deliberately the INVERSE of an opt-out toggle: this is a
# framework-declared constant, so an absent, malformed, or non-allowlisted value
# HALTs and reports the offending value verbatim. It is NEVER silently resolved
# to `none` -- that would convert an unconfigured adapter into a sanctioned
# non-enforcing one, which is the worst outcome available here: the adapter would
# keep posting work items and reporting success while verifying nothing. Only an
# EXPLICIT `none` sanctions non-enforcement.
#
# `spent-time-increment` is THIS adapter's check: the instance's `Spent time`
# field only grows, so absorption is verified by the increment matching the
# posted duration (live-confirmed). `remaining-estimate-decrement` is the JIRA
# adapter's check and is NOT accepted here -- no branch implements it, so
# allowlisting it would turn every post into a failed post-check. Refusing a
# value no branch implements is CLAUDE.md Behavior 2, not an oversight.
yt_config_capability() {
  local value
  value="$(yt_config_get '.worklog_postcheck_capability')" || value=""
  case "$value" in
    spent-time-increment|none)
      printf '%s\n' "$value" ;;
    *)
      yt_halt "$YT_EXIT_CONFIG" syncyt.worklog.capability_marker_absent \
        "worklog_postcheck_capability in $(yt_config_path) is absent or unrecognized: '$value' (allowed on this adapter: spent-time-increment | none; remaining-estimate-decrement is the Jira adapter's) -- never silently resolved to 'none', which would disarm the post-add absorption check without saying so" ;;
  esac
}

# yt_config_toggle <name> -- the resolved polarity of one optional capability:
# `enabled`, `disabled`, or `fail-closed`.
#
# THE DEFAULT POLARITY TABLE LIVES HERE AND NOWHERE ELSE (AC-3). Each toggle's
# default is the answer to "what should happen when an adopter never mentioned
# it", and each one is chosen, not inherited:
#
#   worklog_creation_enabled          enabled      effort projection is the
#                                                  adapter's point; an adopter who
#                                                  never configured it still gets it
#   assignment_reconciliation_enabled disabled     it REASSIGNS other people's
#                                                  issues; opt-in, never by default
#   link_creation_enabled             enabled      additive and reversible by hand
#   attachment_size_ceiling_mib       fail-closed  an ABSENT ceiling is not an
#                                                  unlimited one -- a download with
#                                                  no bound is how an adapter fills
#                                                  a disk on someone else's data
#
# An absent toggle is ANNOUNCED (`syncyt.config.default_polarity_applied`), never
# applied in silence: an operator reading the audit stream must be able to tell a
# configured polarity from an assumed one, and the two are otherwise identical in
# their effect on the run.
#
# A name this table does not carry HALTs. There is no "sensible default for an
# unknown toggle" -- inventing one would make the table above untrue, and it is
# the only place a polarity is defined.
yt_config_toggle() {
  local name="$1" value default
  case "$name" in
    worklog_creation_enabled|link_creation_enabled) default=enabled ;;
    assignment_reconciliation_enabled)              default=disabled ;;
    attachment_size_ceiling_mib)                    default=fail-closed ;;
    *)
      yt_halt "$YT_EXIT_CONFIG" syncyt.config.marker_unresolved \
        "'$name' is not a toggle this adapter declares a polarity for (declared: worklog_creation_enabled, assignment_reconciliation_enabled, link_creation_enabled, attachment_size_ceiling_mib) -- refusing to invent one, because the polarity table is the only place a default is defined" ;;
  esac

  if [[ "$name" == "attachment_size_ceiling_mib" ]]; then
    # A ceiling is a NUMBER, and only a usable number is a configured ceiling: an
    # absent one, a malformed one and a non-positive one are the same state --
    # there is no bound -- and they all resolve fail-closed.
    value="$(yt_config_get '.attachment_size_ceiling_mib')" || value=""
    if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
      printf 'enabled\n'; return 0
    fi
  else
    value="$(yt_config_get '.toggles[$t]' --arg t "$name")" || value=""
    case "$value" in
      true)  printf 'enabled\n';  return 0 ;;
      false) printf 'disabled\n'; return 0 ;;
    esac
  fi

  yt_report syncyt.config.default_polarity_applied \
    "the toggle '$name' is absent or unusable in $(yt_config_path)${value:+ (value: '$value')} -- resolving to its documented default '$default'; set it explicitly to make the choice yours rather than this adapter's"
  printf '%s\n' "$default"
  return 0
}

# --------------------------------------------------------------------------
# The projected custom fields (AC-12 / AC-13 / AC-15)
# --------------------------------------------------------------------------
# yt_config_field_map -- one TAB-separated `<repo-key> <field-name> <$type>` row
# per `custom_field_map` entry, or nothing when the map is empty (its shipped
# state). Emits nothing and succeeds for an absent map: a repository that
# projects no extra field is a normal repository, not a misconfigured one.
#
# The `$type` is ALLOWLISTED against the write forms this adapter actually
# implements, and an unrecognized one HALTs naming the offending value. The
# alternative -- writing an unknown form in whatever shape happened to be the
# default -- is how a field lands as the wrong JSON and is rejected, or worse
# accepted and stored as something else. An entry missing either half HALTs for
# the same reason: half a mapping is not a mapping.
yt_config_field_map() {
  local rows row key field ftype
  rows="$(yt_config_get '.custom_field_map // {} | to_entries[] | [.key, (.value.field // ""), (.value.type // "")] | @tsv')" \
    || return 0
  while IFS=$'\t' read -r key field ftype; do
    [[ -n "$key" ]] || continue
    if [[ -z "$field" || -z "$ftype" ]]; then
      yt_report syncyt.config.marker_unresolved \
        "custom_field_map entry '$key' in $(yt_config_path) declares no field name and/or no type -- refusing to project half a mapping"
      return "$YT_EXIT_CONFIG"
    fi
    case "$ftype" in
      SingleEnumIssueCustomField|StateIssueCustomField|SimpleIssueCustomField) ;;
      *)
        yt_report syncyt.config.marker_unresolved \
          "custom_field_map entry '$key' in $(yt_config_path) declares the type '$ftype', which this adapter has no write form for (implemented: SingleEnumIssueCustomField, StateIssueCustomField, SimpleIssueCustomField) -- refusing to write a field in a shape no branch produces"
        return "$YT_EXIT_CONFIG" ;;
    esac
    printf '%s\t%s\t%s\n' "$key" "$field" "$ftype"
  done <<<"$rows"
  return 0
}

# yt_field_attachment <resolved-type> <field-name> -- what the config's
# `type_conditional_fields` map says about whether <field-name> can attach to an
# issue of <resolved-type>. Prints exactly one verdict:
#
#   unguarded        the map never mentions this field, so it says nothing about
#                    it -- the read-back stays the only authority
#   attaches         the map lists it under this Type
#   refused          the map declares this Type and does NOT list the field, so
#                    the config itself says it cannot attach
#   type-undeclared  the map does not declare this Type at all -- the safe
#                    reading is "no conditional fields are declared for it", so
#                    nothing is refused
#   map-absent       there is no usable map; only the read-back guard is armed
#
# The two guards this feeds fail in different directions (DEC-015), so every
# verdict here is deliberately conservative about REFUSING: the map is adopter
# data and can go stale against the instance, whereas the read-back cannot. An
# unusable map therefore degrades to `map-absent` -- one guard instead of two --
# rather than halting a projection the read-back could still verify.
yt_field_attachment() {
  local out
  out="$(yt_config_get '
      (.type_conditional_fields // null) as $m
      | if ($m | type) != "object" then "map-absent"
        elif ([$m[]?[]?] | index($f)) == null then "unguarded"
        elif ($m | has($t)) == false then "type-undeclared"
        elif ($m[$t] | index($f)) != null then "attaches"
        else "refused" end' --arg t "$1" --arg f "$2")" || out="map-absent"
  printf '%s\n' "$out"
}

# yt_config_page_bound -- the explicit `$top` every paged read carries.
#
# FAIL-LOUD, like the capability marker and unlike a toggle: an absent or
# unusable bound HALTs rather than resolving to a default. The two defaults
# available are both wrong in ways that hide. Falling back to `-1` makes the read
# UNBOUNDED, which cannot truncate and therefore silently disarms the truncation
# signal -- an adapter that can never report `page_truncated` is indistinguishable
# from one whose pages never truncate. Falling back to some invented number
# silently decides how much of an adopter's data this adapter is willing to see.
yt_config_page_bound() {
  local value
  value="$(yt_config_get '.page_top_bound')" || value=""
  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  yt_report syncyt.config.marker_unresolved \
    "page_top_bound in $(yt_config_path) is absent or is not a positive integer${value:+ (value: '$value')} -- refusing to invent one. An unbounded read never truncates, so a default here would disarm the page-truncation signal without saying so"
  return "$YT_EXIT_CONFIG"
}

# yt_conditional_map_usable -- true when the config carries a
# `type_conditional_fields` map the pre-flight guard can actually evaluate.
#
# Separate from yt_field_attachment on purpose: that function answers a question
# about ONE field and is called once per mapped field, so a warning emitted from
# inside it would be repeated per field -- multiplying a fact about the RUN's
# guard posture by the size of the adopter's map. The map's absence is announced
# once, by the caller, before the loop.
#
# The verdict is taken from jq's own `type`, not from an emptiness test: an
# absent key and a key holding a string, a number or a list are all states this
# guard cannot evaluate, and only an object is one it can.
yt_conditional_map_usable() {
  local t
  t="$(yt_config_get '.type_conditional_fields | type')" || return 1
  [[ "$t" == "object" ]]
}

# --------------------------------------------------------------------------
# Owned data + transport (sourced) -- see yt-meta.sh / yt-rest.sh
# --------------------------------------------------------------------------
# The `metadata.yaml` reader and the REST helpers live in sibling modules so no
# file passes the 400-line DX ceiling. Callers source ONLY this file and get all
# three halves.
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-meta.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-rest.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-projectkey-lib.sh"
