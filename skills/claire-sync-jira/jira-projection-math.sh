#!/usr/bin/env bash
#
# jira-projection-math.sh -- the estimate-projection and duration-arithmetic
# half of jira-lib.sh (BTG-247 row: jira-lib.sh split). MOVED VERBATIM from the
# parent (pre-split lines :309-:386): js_estimate_project, duration_minutes,
# and remaining_of. All three are PURE (string/number in, string/number out --
# no config lookup, no transport, no side effect), which is what already
# distinguished this content from every other function jira-lib.sh keeps.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075),
# same as jira-lib.sh. SOURCED by jira-lib.sh via a
# ${BASH_SOURCE[0]}-relative path, so every existing caller (which sources
# ONLY jira-lib.sh) gets this module transitively with no call-site change.
#
# References: archive/BTG-247/spec.md ; archive/BTG-247/decisions.md (this
# split's own DEC entry) ; the functions' own history is in jira-lib.sh's
# "Duration arithmetic" comment (moved there originally from jira-worklog.sh).

# --------------------------------------------------------------------------
# Estimate projection
# --------------------------------------------------------------------------

# js_estimate_project <raw> -- project a repo `estimated_effort` onto a Jira
# duration. Prints the duration and returns 0; prints NOTHING and returns 1 when
# the value is not a duration this adapter can project.
#
# `estimated_effort` is human-authored planning prose, not a typed field, and the
# repo's real values prove it: alongside `4h` and `0.5d` sit ranges (`2-4h`,
# `0.5-1d`, and one EN-DASH `1-2d`), bare words (`hours`), an inequality (`<1h`),
# a mixed phrase (`half-day to 1d`) and a whole sentence. Jira rejects every one
# of those as a duration with a 400, and the write is a BLOCKING step -- so
# sending them verbatim means those tickets can never sync at all.
#
# Two rules, both restored from the deleted projection sidecar:
#   - a RANGE projects its UPPER bound (`2-4h` -> `4h`), because the upper bound
#     is the commitment the estimate is read as;
#   - anything else that is not a duration is OMITTED and REPORTED by the caller,
#     never sent. Omitting the field leaves the live Original Estimate untouched
#     and costs the operator one reported ticket; sending it halts the ticket
#     before its status, worklogs and links are projected.
# An en/em dash is normalized to `-` first: it is the same range written by a
# different editor, and a projection that turned on which dash key an author hit
# would be a defect wearing a typography disguise.
js_estimate_project() {
  local raw="$1" value unit_re='[0-9]+(\.[0-9]+)?[wdhm]'
  value="$(printf '%s' "$raw" | sed 's/\xe2\x80\x93/-/g; s/\xe2\x80\x94/-/g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "$value" ]] || return 1
  # a plain duration, possibly composite (`1d 4h`) -- passes through unchanged
  if [[ "$value" =~ ^$unit_re([[:space:]]+$unit_re)*$ ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  # a range: `<lower>[unit]-<upper><unit>` -> the upper bound, with its unit
  if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?[wdhm]?-($unit_re)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------
# Duration arithmetic (worklog post-check)
# --------------------------------------------------------------------------
# Moved here from jira-worklog.sh so that file stays inside the DX <400-line
# ceiling. Both are PURE -- a duration string and a JSON body in, a value out --
# and no gate anchors on either. Neither touches the post-check ORDERING the
# parity gate DOES anchor on (REMAINING_BEFORE= / the post / REMAINING_AFTER=),
# which all remain in jira-worklog.sh in that order.
# $WORKDAY_HOURS / $WORKWEEK_DAYS are resolved by the caller from the config.
# duration_minutes <jira-duration> -- "1d 4h 30m" -> minutes. Returns non-zero
# (printing nothing) when the string is not a Jira duration, so an unparseable
# value is never silently treated as zero.
duration_minutes() {
  awk -v s="$1" -v wd="$WORKDAY_HOURS" -v ww="$WORKWEEK_DAYS" '
    BEGIN {
      n = split(s, part, " "); if (n == 0) exit 1
      total = 0
      for (i = 1; i <= n; i++) {
        if (part[i] !~ /^[0-9]+(\.[0-9]+)?[wdhm]$/) exit 1
        v = substr(part[i], 1, length(part[i]) - 1) + 0
        u = substr(part[i], length(part[i]), 1)
        if      (u == "w") total += v * ww * wd * 60
        else if (u == "d") total += v * wd * 60
        else if (u == "h") total += v * 60
        else               total += v
      }
      printf "%.0f\n", total
    }'
}

# remaining_of <json> -- the raw REST v2 `.fields.timetracking.remainingEstimate`.
# Returns non-zero when the body is not an object (an unparseable verification is
# never a pass), and prints the empty string when the issue carries no estimate.
remaining_of() {
  printf '%s' "$1" | jq -r 'if type == "object" then (.fields.timetracking.remainingEstimate // "") else error("not an object") end' 2>/dev/null
}
