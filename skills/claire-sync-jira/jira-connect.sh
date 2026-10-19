#!/usr/bin/env bash
#
# jira-connect.sh -- prerequisite connectivity check + self-identity resolution.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: Jira Server/DC answers
# `GET /rest/api/2/myself` with a top-level `.name` (the Server/DC username the
# assignment step later writes as `.user.name`) -- verified live under BTG-066.
# The effective self identity resolved HERE is resolved ONCE per invocation and
# consumed by later steps; they never re-resolve it.
#
# Upstream: invoked by the /claire-sync-jira orchestrator as the first step of
#   every operation (single ticket, bulk, or intake).
# Downstream: one REST v2 GET against the adopter's Jira instance; a user-level
#   identity cache OUTSIDE the repository tree.
# Spec: archive/BTG-075/spec.md (AC-1, Facet 7) ; jira-server-scripts.md.
#
# Contract (three channels, DEC-001):
#   stdout : self=<username>  self_source=env|cache|rest   (or self_result=unresolved)
#   stderr : syncjs.* reported conditions
#   exit   : 0 ok / 1 credential rejected / 3 transport unreachable
#
# The identity is a real human identity: it is written ONLY to the user-level
# cache outside the repo tree and NEVER to a repository file, metadata.yaml, an
# issue field, or git history (BTG-066 non-persistence invariant).

set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/jira-lib.sh"

# The config sidecar is required before anything else: it binds the NAMES of the
# environment variables this script reads (AC-7), so there is nothing to resolve
# without it.
js_config_require

for logical in base_url pat; do
  name="$(js_config_map env "$logical")"
  if [[ -z "${!name:-}" ]]; then
    js_halt "$JS_EXIT_USAGE" syncjs.connect.env_absent "required environment variable is unset: $name"
  fi
done

# --- ADOPTER-SUPPLIED ALWAYS WINS (BTG-066) --------------------------------
# A non-empty $JIRA_SELF short-circuits everything below: no cache read, no cache
# write, no REST call. The adopter value is NEVER cached -- unsetting it later
# must re-resolve, never resurrect it from disk.
ADOPTER_SELF="$(js_env_value self)" || ADOPTER_SELF=""
if [[ -n "$ADOPTER_SELF" ]]; then
  js_emit self "$ADOPTER_SELF"
  js_emit self_source env
  exit "$JS_EXIT_OK"
fi

# --- fingerprints (BTG-066) -------------------------------------------------
# The PAT is hashed via STDIN only -- never as a command argument (argv is
# visible to other users through `ps`).
# resolved THROUGH the env block, like every other credential read
BASE_FOR_FP="$(js_env_value base_url)"
PAT_FOR_FP="$(js_env_value pat)"
INSTANCE_FP="$(printf '%s' "$BASE_FOR_FP" | sha256sum | cut -c1-16)"
CRED_FP="$(printf '%s\0%s' "$PAT_FOR_FP" "$BASE_FOR_FP" | sha256sum | cut -c1-32)"

CACHE_DIR=""
if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  CACHE_DIR="$XDG_CACHE_HOME/claire/jira-self"
elif [[ -n "${HOME:-}" ]]; then
  CACHE_DIR="$HOME/.cache/claire/jira-self"
fi
# No cache location resolvable => proceed WITHOUT a cache (resolve fresh, report
# once, never fatal, and NEVER a fallback into the repository tree).
CACHE_FILE=""
[[ -n "$CACHE_DIR" ]] && CACHE_FILE="$CACHE_DIR/$INSTANCE_FP"

# --- read + validate the cache (structural invalidation, NO TTL) ------------
# Validity is a single equality check: the STORED credential fingerprint must
# equal the fingerprint recomputed from the CURRENT $JIRA_PAT + $JIRA_BASE_URL.
# A rotated PAT or a re-pointed instance can therefore never validate an old
# entry -- a wrong-actor write is structurally impossible, not merely unlikely.
if [[ -n "$CACHE_FILE" && -f "$CACHE_FILE" ]]; then
  if ! read -r cached_fp cached_self < "$CACHE_FILE" 2>/dev/null || [[ -z "${cached_fp:-}" ]]; then
    js_report syncjs.self.cache_unreadable "$CACHE_FILE -- treating as a miss, resolving fresh"
  elif [[ "$cached_fp" != "$CRED_FP" ]]; then
    js_report syncjs.self.cache_invalidated \
      "stored credential fingerprint differs from the current credential -- discarding the entry and re-resolving"
  elif [[ -n "${cached_self:-}" ]]; then
    js_report syncjs.self.resolved "source=cache"
    js_emit self "$cached_self"
    js_emit self_source cache
    exit "$JS_EXIT_OK"
  fi
fi

# --- resolve over the network ----------------------------------------------
if ! js_rest GET /rest/api/2/myself; then
  js_halt "$JS_EXIT_TRANSPORT" syncjs.transport.rest_unreachable \
    "GET /rest/api/2/myself could not reach ${BASE_FOR_FP%/}${JS_TRANSPORT_ERROR:+ -- curl: $JS_TRANSPORT_ERROR}"
fi
if ! js_http_ok; then
  js_halt "$JS_EXIT_FAIL" syncjs.connect.rest_rejected \
    "GET /rest/api/2/myself returned HTTP $JS_HTTP_STATUS -- the Personal Access Token is missing, expired, or unauthorized"
fi

# Read the identity from EXACTLY ONE field: `.name`. Never fall back to `.key` or
# `.emailAddress` -- a fallback chain is a silent-degradation path.
SELF_NAME="$(printf '%s' "$JS_HTTP_BODY" | jq -er '.name' 2>/dev/null)" || SELF_NAME=""
if [[ -z "$SELF_NAME" ]]; then
  # Connectivity is proven, the identity is not: NON-BLOCKING (the assignment
  # step degrades by skipping), reported, never guessed or substituted.
  js_report syncjs.self.shape_unrecognized \
    "HTTP $JS_HTTP_STATUS carried no usable .name -- the self identity stays UNRESOLVED"
  js_emit self_result unresolved
  exit "$JS_EXIT_OK"
fi

SELF_VAR="$(js_config_map env self 2>/dev/null || echo JIRA_SELF)"
js_report syncjs.self.resolved "source=rest (set \$$SELF_VAR to make this value permanent)"

# --- write back (ONLY after a SUCCESSFUL resolution) -----------------------
# A failed resolution writes NOTHING -- a failure must never poison the cache.
# Write atomically: 0700 directory, temp file in the SAME directory, 0600, then
# rename, so a reader never observes a partial file. Only the irreversible
# fingerprint and the identity are stored -- never the PAT.
if [[ -n "$CACHE_FILE" ]]; then
  if mkdir -p -m 0700 "$CACHE_DIR" 2>/dev/null \
     && tmp="$(mktemp "$CACHE_DIR/.tmp.XXXXXX" 2>/dev/null)" \
     && printf '%s %s\n' "$CRED_FP" "$SELF_NAME" > "$tmp" \
     && chmod 0600 "$tmp" \
     && mv -f "$tmp" "$CACHE_FILE"; then
    :
  else
    rm -f "${tmp:-}" 2>/dev/null
    js_report syncjs.self.cache_write_failed \
      "could not persist the identity cache at $CACHE_FILE -- this invocation is unaffected"
  fi
fi

js_emit self "$SELF_NAME"
js_emit self_source rest
exit "$JS_EXIT_OK"
