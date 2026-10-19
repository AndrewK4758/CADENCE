#!/usr/bin/env bash
#
# jira-rest.sh -- the transport half of the /cadence-sync-jira shared library.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary: Jira Server/DC speaks REST v2
# with a Bearer PAT, and that PAT is an operator-environment credential -- it
# rides curl's `-K-` stdin config block and never reaches argv, a temp file, an
# artifact, or any output channel (Facet 7).
#
# SOURCED by jira-lib.sh, never on its own: it depends on the exit-code
# vocabulary, the reporters and the config resolvers defined there. It was split
# out when the combined library outgrew the 400-line DX ceiling -- the seam is
# clean (transport vs config/metadata) and no call site changed, because every
# script still sources jira-lib.sh alone.
#
# Contracts: jira-server-scripts.md sections 1-2.

# --------------------------------------------------------------------------
# Transport -- direct Jira REST v2 with a Bearer PAT (AC-1)
# --------------------------------------------------------------------------
# js_rest <method> <path> [json-body-file]
#
# Upstream: called by every operation script for its one Jira operation.
# Downstream: `$JIRA_BASE_URL/rest/api/2/...` on the adopter's Jira Server/DC.
# Spec: archive/BTG-075/spec.md (Proposed Design -- Credential handling, Facet 7).
#
# The Authorization header is written into curl's `-K-` stdin config block, so
# the PAT is never a positional argument (invisible to `ps`) and never touches a
# file. On return: JS_HTTP_STATUS holds the status code and JS_HTTP_BODY the
# response body. Returns 0 on a completed exchange (whatever the status), or
# JS_EXIT_TRANSPORT when the exchange itself could not happen -- the caller
# decides the polarity, so no transport failure is ever swallowed here.
# js_transport_env -- resolve the base URL and PAT THROUGH the config's `env`
# block, so a rebound variable name is honoured rather than met with a bare 401.
# Cached per process. Sets JS_BASE_URL / JS_PAT.
js_transport_env() {
  [[ -n "${JS_BASE_URL+set}" ]] && return 0
  JS_BASE_URL="$(js_env_value base_url)" || return "$JS_EXIT_CONFIG"
  JS_PAT="$(js_env_value pat)" || return "$JS_EXIT_CONFIG"
  return 0
}

js_rest() {
  local method="$1" path="$2" body_file="${3:-}"
  js_transport_env || return "$JS_EXIT_CONFIG"
  local url="${JS_BASE_URL%/}$path"
  local raw=() args
  args=(-sS -K- -X "$method" -H 'Accept: application/json' -w '\n%{http_code}')
  if [[ -n "$body_file" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body_file")
  fi
  # curl's own -sS diagnostic is CAPTURED, not discarded: it is the only thing that
  # distinguishes a DNS failure from a TLS or proxy error, and "could not reach the
  # instance" is useless to an operator without it.
  #
  # That capture file is a DIAGNOSTIC AID, never the exchange, and BTG-079 AC-5 makes
  # the difference load-bearing. It was staged unguarded, so with $TMPDIR globally
  # unusable this was the FIRST mktemp in a run to fail: the empty path failed the
  # `2>` redirect, the command substitution returned non-zero, and the run halted on
  # `syncjs.transport.rest_unreachable` -- loud and safe, but a MISDIAGNOSIS, because
  # nothing had been sent and the instance was never unreachable. So an unstageable
  # capture file now degrades the DETAIL (`/dev/null`, the detail named as missing)
  # and the exchange proceeds; the run then halts at the first site where a scratch
  # file is genuinely load-bearing -- the request body -- naming a scratch condition.
  # `mktemp`'s own stderr is suppressed either way: DEC-001 reserves stderr for
  # `syncjs.*` conditions.
  local out err_file
  err_file="$(mktemp 2>/dev/null)" || err_file=""
  if ! out="$(printf 'header = "Authorization: Bearer %s"\n' "$JS_PAT" \
              | curl "${args[@]}" "$url" 2>"${err_file:-/dev/null}")"; then
    JS_HTTP_STATUS=""
    JS_HTTP_BODY=""
    JS_TRANSPORT_ERROR="curl's diagnostic could not be captured (no scratch file)"
    [[ -n "$err_file" ]] && JS_TRANSPORT_ERROR="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]*$//')"
    [[ -n "$err_file" ]] && rm -f "$err_file"
    return "$JS_EXIT_TRANSPORT"
  fi
  JS_TRANSPORT_ERROR=""
  rm -f "$err_file"
  mapfile -t raw <<<"$out"
  JS_HTTP_STATUS="${raw[-1]}"
  unset 'raw[-1]'
  JS_HTTP_BODY="$(printf '%s\n' "${raw[@]}")"
  return 0
}

# js_rest_download <absolute-url> <dest-path> -- fetch a BINARY body to a file.
#
# js_rest must NEVER be used for this: it captures the response through a command
# substitution, and command substitution DROPS NUL BYTES ("ignored null byte in
# input"). Every real PNG/PDF/zip/docx contains NULs, so the body would land
# silently short and the caller would persist a corrupted artifact as a success.
# curl writes straight to the file, so no shell variable holds the bytes.
# The URL is ABSOLUTE and used verbatim: Jira returns content URLs as
# `<base>/secure/attachment/{id}/{filename}` with no `/rest/api/2` segment, so
# prepending the base again yields `https://hosthttps://host/...`.
# The PAT still rides curl's `-K-` stdin config block: never argv, never a file.
js_rest_download() {
  local url="$1" dest="$2" status err_file
  js_transport_env || return "$JS_EXIT_CONFIG"
  # Same diagnostic-aid-not-the-exchange rule as js_rest above (BTG-079 AC-5).
  err_file="$(mktemp 2>/dev/null)" || err_file=""
  if ! status="$(printf 'header = "Authorization: Bearer %s"\n' "$JS_PAT" \
                 | curl -sS -K- -L -o "$dest" -w '%{http_code}' "$url" 2>"${err_file:-/dev/null}")"; then
    JS_HTTP_STATUS=""
    JS_TRANSPORT_ERROR="curl's diagnostic could not be captured (no scratch file)"
    [[ -n "$err_file" ]] && JS_TRANSPORT_ERROR="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]*$//')"
    [[ -n "$err_file" ]] && rm -f "$err_file"
    return "$JS_EXIT_TRANSPORT"
  fi
  [[ -n "$err_file" ]] && rm -f "$err_file"
  JS_HTTP_STATUS="$status"
  js_http_ok || return "$JS_EXIT_FAIL"
  return 0
}

# js_http_ok -- true when the last js_rest exchange returned a 2xx.
js_http_ok() {
  [[ "${JS_HTTP_STATUS:-}" =~ ^2[0-9][0-9]$ ]]
}

# --------------------------------------------------------------------------
# Body staging -- the ONE builder every request body goes through (BTG-084)
# --------------------------------------------------------------------------
# js_build_body <dest-file> <syncjs.condition> <subject> <jq-arg>...
#
# Upstream: every script that stages a body for a subsequent js_rest PUT/POST.
# Downstream: writes ONLY <dest-file> and, on failure, one syncjs.* line on
# stderr. Spec: archive/BTG-084/spec.md (Proposed Design -- Shared library).
#
# Answers BOTH questions the wire needs answered before a body is sent:
#   (a) did jq EXIT 0, and (b) did it PRODUCE content.
# They are DIFFERENT questions. A jq that dies mid-write leaves a TRUNCATED,
# NON-EMPTY file that an emptiness probe reads as "built", and a jq that exits 0
# having written nothing defeats a status probe. Only the pair is a check.
#
# Returns 0 built / 1 not built. On 1 it emits exactly ONE syncjs.* line naming
# <condition> and composed from <subject>; the CALLER decides whether that is a
# skip or a halt and MUST NOT report again -- a caller that must halt uses a bare
# `exit "$JS_EXIT_FAIL"`, never js_halt, which would double-report.
#
# jq's own stderr is suppressed: DEC-001 reserves stderr for syncjs.* conditions,
# and a raw jq diagnostic is not a condition an operator or the orchestrator can
# route. The loudness is RESTORED -- and improved -- by the named condition.
# Reads STDIN when the caller pipes into it (the AC body build does).
js_build_body() {
  local dest="$1" condition="$2" subject="$3"; shift 3
  if ! jq "$@" > "$dest" 2>/dev/null || ! grep -q '[^[:space:]]' "$dest"; then
    js_report "$condition" \
      "$subject could not be built (jq exited non-zero, or produced nothing) -- issuing NO write rather than the bodyless or MALFORMED request a partial build degrades into"
    return 1
  fi
  return 0
}
