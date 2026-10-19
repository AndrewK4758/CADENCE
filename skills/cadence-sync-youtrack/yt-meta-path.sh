#!/usr/bin/env bash
#
# yt-meta-path.sh -- yt_metadata_path, the metadata.yaml LOCATOR. Split out of
# the colocated yt-meta.sh (BTG-114 headroom relocation, the AC-12 analog of
# jira-meta.sh's DEC-004 -- adding the G2/G3/G4/G5 quote-escape grammar to
# yt-meta.sh costs +11 lines, measured, same as the Jira loader, and this file
# was at 391/400 with only 9 lines of headroom).
#
# Bounded context: same as yt-meta.sh, which this file is SOURCED by,
# unconditionally, so yt-lib.sh's existing `. yt-meta.sh` chain resolves
# `yt_metadata_path` exactly as before the move -- no call site changed
# (yt-epic.sh and yt-sprint-check.sh call it through yt-lib.sh, never sourcing
# this file directly).
#
# Moved VERBATIM from yt-meta.sh (its own `yt_metadata_path`, 43-56 as measured
# 2026-09-17) -- no re-wrap, no compression, no logic change.
#
# Spec: archive/BTG-114/spec.md AC-12 (the third reader), DEC-004 (the Jira
# loader's identical relocation, the precedent this one follows).

# --------------------------------------------------------------------------
# yt_metadata_path <id> -- specs/<id>/metadata.yaml, else the archived copy.
# --------------------------------------------------------------------------
# Both arms exist because a sync may legitimately be run against a ticket that
# has already been archived; neither location is guessed at, and an id in
# neither returns non-zero rather than resolving to a path that does not exist.
yt_metadata_path() {
  local id="$1" root="${CADENCE_REPO_ROOT:-.}"
  if [[ -f "$root/specs/$id/metadata.yaml" ]]; then
    printf '%s\n' "$root/specs/$id/metadata.yaml"
  elif [[ -f "$root/archive/$id/metadata.yaml" ]]; then
    printf '%s\n' "$root/archive/$id/metadata.yaml"
  else
    return 1
  fi
}

# yt_metadata_get <jq-filter> -- read one value from the loaded metadata.
# `// empty` so an absent key yields the empty string rather than the literal
# `null`, which a caller would otherwise write to the instance verbatim.
# Moved here alongside yt_metadata_path (same BTG-114 headroom relocation).
yt_metadata_get() {
  jq -r "$1 // empty" <<<"${YT_METADATA_JSON:-}" 2>/dev/null
}
