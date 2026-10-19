#!/usr/bin/env bash
#
# yt-connect.sh -- prerequisite connectivity check + self-identity resolution.
#
# Bounded context: Tracker projection / YouTrack Server adapter (BTG-176).
# Invariant relied on from outside this boundary: YouTrack answers
# `GET /api/users/me?fields=id,login,fullName,email` with a top-level `.login`
# (the login later steps write as an Assignee value) and a top-level `.id` (the
# internal user id, which the same field also accepts) -- OBSERVED live against
# v2026.1 build 13162. The effective self identity resolved HERE is resolved ONCE
# per invocation and consumed by later steps; they never re-resolve it.
#
# Upstream: invoked by the /cadence-sync-youtrack orchestrator as the first step of every
#   operation.
# Downstream: one REST GET against the adopter's YouTrack instance; a user-level
#   identity cache OUTSIDE the repository tree.
# Spec: archive/BTG-176/spec.md (AC-1, Facet 7) ; youtrack-scripts.md.
#
# Contract (three channels):
#   stdout : self=<login>  self_id=<internal-id>  self_source=env|cache|rest
#            (or self_result=unresolved)
#   stderr : syncyt.* reported conditions
#   exit   : 0 ok / 1 credential rejected / 2 usage / 3 transport unreachable
#
# The identity is a real human identity: it is written ONLY to the user-level
# cache outside the repo tree and NEVER to a repository file, metadata.yaml, an
# issue field, or git history.

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yt-lib.sh"

# The config sidecar is required before anything else: it binds the NAMES of the
# environment variables this script reads, so there is nothing to resolve
# without it.
yt_config_require

# A required variable that is UNSET is a USAGE failure, reported by name and
# BEFORE any network call. It is deliberately not folded into the 401 path: an
# unset token and a rejected token are different problems with different
# remedies, and a run that sent an empty Bearer header would collect a 401 and
# tell the operator to check a credential they never supplied.
declare -A ENV_NAME=()
for logical in base_url token self; do
  # Every name is resolved from the config ONCE and remembered, so that later
  # messages name the variable THIS adopter bound. Naming a variable through a
  # hardcoded `|| echo YOUTRACK_...` fallback would tell an adopter who rebound
  # the name to go and fix a variable they do not use.
  ENV_NAME[$logical]="$(yt_config_map env "$logical")" || exit "$YT_EXIT_CONFIG"
done
for logical in base_url token; do
  name="${ENV_NAME[$logical]}"
  if [[ -z "${!name:-}" ]]; then
    yt_halt "$YT_EXIT_USAGE" syncyt.connect.env_absent \
      "required environment variable is unset: $name -- no request was issued"
  fi
done

# --- ADOPTER-SUPPLIED ALWAYS WINS ------------------------------------------
# A non-empty adopter-supplied self identity (the variable the config's `env`
# block binds as `self`) short-circuits everything below: no cache read, no
# cache write, no REST call. The adopter value is NEVER cached -- unsetting it
# later must re-resolve, never resurrect it from disk.
ADOPTER_SELF="$(yt_env_value self)" || ADOPTER_SELF=""
if [[ -n "$ADOPTER_SELF" ]]; then
  yt_emit self "$ADOPTER_SELF"
  yt_emit self_source env
  exit "$YT_EXIT_OK"
fi

# --- fingerprints -----------------------------------------------------------
# The token is hashed via STDIN only -- never as a command argument (argv is
# visible to other users through `ps`).
BASE_FOR_FP="$(yt_env_value base_url)"
TOKEN_FOR_FP="$(yt_env_value token)"
INSTANCE_FP="$(printf '%s' "$BASE_FOR_FP" | sha256sum | cut -c1-16)"
CRED_FP="$(printf '%s\0%s' "$TOKEN_FOR_FP" "$BASE_FOR_FP" | sha256sum | cut -c1-32)"

CACHE_DIR=""
if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  CACHE_DIR="$XDG_CACHE_HOME/cadence/youtrack-self"
elif [[ -n "${HOME:-}" ]]; then
  CACHE_DIR="$HOME/.cache/cadence/youtrack-self"
fi
# No cache location resolvable => proceed WITHOUT a cache (resolve fresh, report
# once, never fatal, and NEVER a fallback into the repository tree).
CACHE_FILE=""
[[ -n "$CACHE_DIR" ]] && CACHE_FILE="$CACHE_DIR/$INSTANCE_FP"

# --- read + validate the cache (structural invalidation, NO TTL) ------------
# Validity is a single equality check: the STORED credential fingerprint must
# equal the fingerprint recomputed from the CURRENT token + base URL. A rotated
# token or a re-pointed instance can therefore never validate an old entry -- a
# wrong-actor write is structurally impossible, not merely unlikely.
if [[ -n "$CACHE_FILE" && -f "$CACHE_FILE" ]]; then
  if ! read -r cached_fp cached_self cached_id < "$CACHE_FILE" 2>/dev/null || [[ -z "${cached_fp:-}" ]]; then
    yt_report syncyt.self.cache_unreadable "$CACHE_FILE -- treating as a miss, resolving fresh"
  elif [[ "$cached_fp" != "$CRED_FP" ]]; then
    yt_report syncyt.self.cache_invalidated \
      "stored credential fingerprint differs from the current credential -- discarding the entry and re-resolving"
  elif [[ -n "${cached_self:-}" ]]; then
    yt_report syncyt.self.resolved "source=cache"
    yt_emit self "$cached_self"
    yt_emit self_id "${cached_id:-}"
    yt_emit self_source cache
    exit "$YT_EXIT_OK"
  fi
fi

# --- resolve over the network ----------------------------------------------
if ! yt_rest GET '/api/users/me?fields=id,login,fullName,email'; then
  yt_halt "$YT_EXIT_TRANSPORT" syncyt.transport.rest_unreachable \
    "GET /api/users/me could not reach ${BASE_FOR_FP%/}${YT_TRANSPORT_ERROR:+ -- curl: $YT_TRANSPORT_ERROR}"
fi
if ! yt_http_ok; then
  # A completed exchange that was REFUSED is an AUTH failure, never a transport
  # one. The instance answered; the credential is what it rejected. Both live
  # 401 bodies are distinguishable and are relayed so the operator can tell an
  # invalid token ("Invalid token") from an absent header ("You are not logged
  # in."), while the remedy names the variable THIS adopter bound.
  TOKEN_VAR="${ENV_NAME[token]}"
  yt_halt "$YT_EXIT_FAIL" syncyt.connect.auth_rejected \
    "GET /api/users/me returned HTTP $YT_HTTP_STATUS -- the instance was reached and REFUSED the credential (this is not a transport failure). Set a valid permanent token in \$$TOKEN_VAR. Instance said: $(printf '%s' "$YT_HTTP_BODY" | tr '\n' ' ' | cut -c1-200)"
fi

# Read the identity from EXACTLY ONE field: `.login`. Never fall back to
# `.fullName` or `.email` -- a fallback chain is a silent-degradation path, and
# on this instance `Assignee` accepts a login or an internal id but not a display
# name, so a fallback would produce a value that 400s later, far from here.
SELF_LOGIN="$(printf '%s' "$YT_HTTP_BODY" | jq -er '.login' 2>/dev/null)" || SELF_LOGIN=""
SELF_ID="$(printf '%s' "$YT_HTTP_BODY" | jq -r '.id // empty' 2>/dev/null)" || SELF_ID=""
if [[ -z "$SELF_LOGIN" ]]; then
  # Connectivity is proven, the identity is not: NON-BLOCKING (the assignment
  # step degrades by skipping), reported, never guessed or substituted.
  yt_report syncyt.self.shape_unrecognized \
    "HTTP $YT_HTTP_STATUS carried no usable .login -- the self identity stays UNRESOLVED"
  yt_emit self_result unresolved
  exit "$YT_EXIT_OK"
fi

SELF_VAR="${ENV_NAME[self]}"
yt_report syncyt.self.resolved "source=rest (set \$$SELF_VAR to make this value permanent)"

# --- write back (ONLY after a SUCCESSFUL resolution) -----------------------
# A failed resolution writes NOTHING -- a failure must never poison the cache.
# Write atomically: 0700 directory, temp file in the SAME directory, 0600, then
# rename, so a reader never observes a partial file. Only the irreversible
# fingerprint and the identity are stored -- never the token.
if [[ -n "$CACHE_FILE" ]]; then
  if mkdir -p -m 0700 "$CACHE_DIR" 2>/dev/null \
     && tmp="$(mktemp "$CACHE_DIR/.tmp.XXXXXX" 2>/dev/null)" \
     && printf '%s %s %s\n' "$CRED_FP" "$SELF_LOGIN" "$SELF_ID" > "$tmp" \
     && chmod 0600 "$tmp" \
     && mv -f "$tmp" "$CACHE_FILE"; then
    :
  else
    rm -f "${tmp:-}" 2>/dev/null
    yt_report syncyt.self.cache_write_failed \
      "could not persist the identity cache at $CACHE_FILE -- this invocation is unaffected"
  fi
fi

yt_emit self "$SELF_LOGIN"
yt_emit self_id "$SELF_ID"
yt_emit self_source rest
exit "$YT_EXIT_OK"
