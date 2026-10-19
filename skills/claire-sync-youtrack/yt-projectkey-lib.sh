#!/usr/bin/env bash
#
# yt-projectkey-lib.sh -- the SINGLE project-key resolver for this adapter
# (BTG-179). The byte-parallel sibling of the Jira adapter's
# jira-projectkey-lib.sh: same three-level order, same channels, same
# never-rescue-a-declared-binding rule.
#
# Bounded context: Tracker projection / YouTrack Server adapter.
# Invariants relied on from outside this boundary:
#   - `CLAIRE_ORG.md` §9 #tracker-binding is the single per-repo tracker
#     binding, and BTG-179 admits the PROJECT KEY into it. Base URLs and tokens
#     stay in the environment: an identifier is configuration, a credential is not.
#   - `ci-templates/scripts/org-binding-resolve.sh` is the SOLE reader of the
#     per-prefix grammar. This file never re-implements it.
#
# WHY A SEPARATE FILE rather than yt-lib.sh: yt-lib.sh is 371 lines against the
# 400-line DX ceiling, and a resolver of this size does not fit under it.
# Relocating whole into a sibling library is this adapter family's established
# pattern. Recorded as BTG-179 DEC-016.
#
# RESOLUTION ORDER:
#   (1) the ticket prefix's §9 per-prefix row
#   (2) §9's scalar `**Project key(s):**` line
#   (3) the environment variable named by the config `env` block -- DEPRECATED,
#       removed after ONE release cycle, per docs/policies/deprecation-policy.md's
#       *Configuration keys (env vars, feature flags)* row. Migration guide:
#       docs/migrations/multi-tracker-binding.md.
#
# On the (1) path an EMPTY key HALTS and (2)/(3) are UNREACHABLE.
#
# CHANNELS. Called inside `$(...)`, where an `exit` would leave only the
# subshell, so it REPORTS on stderr and RETURNS non-zero; every call site is
# `KEY="$(yt_project_key ...)" || exit "$YT_EXIT_CONFIG"`.

YT_ORG_FILE_DEFAULT="docs/agentic-sdlc/CLAIRE_ORG.md"
YT_ORG_RESOLVER_DEFAULT="ci-templates/scripts/org-binding-resolve.sh"

# yt_org_section9 <org> -- §9's region, from its own heading to the next TOP-LEVEL
# heading.
#
# THE ORDINAL IS OPTIONAL AND THE NAME IS NOT, byte-for-byte the rule
# `org-binding-parse.sh:section_region()` applies. `CLAIRE_ORG_TEMPLATE.md`
# ships `## Tracker Binding` unnumbered and tells the adopter to rename the file
# and "adjust the content, not the structure", so a numbered-only match finds
# NOTHING in the default adopter state -- and the caller reads that as "no
# per-prefix table", bypasses a binding that is present and complete, and writes
# to whatever the deprecated environment variable holds. Exit 0, wrong project.
#
# THE TERMINATOR IS ANY `## `, not `## 10.`. A file that numbers §9 and not §10
# (or the reverse) would otherwise leave §9's region running to EOF, so §10's and
# §13's tables would be read as §9's rows.
#
# WHY THIS COPY EXISTS AT ALL, given DEC-004's one-grammar-one-reader rule: the
# predicate below is what decides whether the shared resolver is REQUIRED, so it
# must answer when the resolver is ABSENT -- querying the resolver to find out
# whether the resolver is needed would make an un-upgraded adopter's missing
# resolver look like "no table" and re-open the fail-open it exists to close.
# The copy cannot be deleted; it is stopped from drifting instead, by S-6.10,
# which asserts this predicate and the canonical parser agree over a matrix of
# org shapes.
yt_org_section9() {
  awk -v pat="^## (9\\\\. )?Tracker Binding[[:space:]]*\$" '
    $0 ~ pat     { g=1; print; next }
    g && /^## /   { exit }
    g             { print }' "$1" 2>/dev/null
}

# yt_org_perprefix_table <org> -- true iff §9 carries a per-prefix table with at
# least one DATA row. A header and a separator are not a table.
yt_org_perprefix_table() {
  [[ -f "$1" ]] || return 1
  yt_org_section9 "$1" | awk '
    # NAMED, not `.* bindings` (BTG-179 DEC-030). This predicate is §9-scoped,
    # so a wide match is safe TODAY -- but the canonical `table_rows` now names
    # its subsection, and a copy that stayed wide would drift the other way:
    # accepting a §9 table the canonical parser rejects. S-6.10 asserts the two
    # agree, and it can only stay true if both spell the grammar identically.
    /^### Per-prefix tracker bindings/ { t=1; next }
    t && /^#{2,3} /               { exit }
    t && /^\| *Ticket prefix/     { next }
    t && /^\|[ -]*-[- |]*\|/      { next }
    t && /^\|/                    { f=1; exit }
    END { exit(f ? 0 : 1) }'
}

# yt_org_scalar_key <org> -- §9's scalar `**Project key(s):**` value.
yt_org_scalar_key() {
  local v
  v="$(yt_org_section9 "$1" | sed -n 's/^\*\*Project key(s):\*\*[[:space:]]*//p' | head -1)"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v#\`}"; v="${v%\`}"
  case "$v" in "<"*">") v="" ;; "{{"*) v="" ;; esac
  printf '%s' "$v"
}

# yt_project_key <ticket-id> | --prefix <PREFIX>
#
# Two calling forms, because two call sites know two different things: a resolve
# knows the TICKET, a reservation is creating the ticket and knows only the
# PREFIX the operator selected.
yt_project_key() {
  local subject="${1:-}" prefix="" org resolver envname envval out key
  org="${CLAIRE_ORG_FILE:-$YT_ORG_FILE_DEFAULT}"
  resolver="${CLAIRE_ORG_RESOLVER:-$YT_ORG_RESOLVER_DEFAULT}"

  if [[ "$subject" == "--prefix" ]]; then
    prefix="${2:-}"
    [[ -n "$prefix" ]] || { yt_report syncyt.config.prefix_underivable \
      "--prefix was given with no value"; return "$YT_EXIT_CONFIG"; }
  elif [[ -n "$subject" ]]; then
    case "$subject" in
      *-*) prefix="${subject%%-*}" ;;
      *)   yt_report syncyt.config.prefix_underivable \
             "no ticket-id prefix can be derived from '$subject' -- the whole id is never treated as a prefix"
           return "$YT_EXIT_CONFIG" ;;
    esac
  fi

  envname="$(yt_config_map env project_key)" || return "$YT_EXIT_CONFIG"
  envval="${!envname:-}"

  # --- (1) the prefix's §9 row -------------------------------------------
  if [[ -n "$prefix" ]] && yt_org_perprefix_table "$org"; then
    if [[ ! -f "$resolver" ]]; then
      yt_report syncyt.config.resolver_unavailable \
        "$org declares a per-prefix tracker table but the shared binding resolver is not at '$resolver' -- refusing to answer from the environment"
      return "$YT_EXIT_CONFIG"
    fi
    if ! out="$(bash "$resolver" --tracker "$prefix" --org "$org" 2>&1)"; then
      yt_report syncyt.config.project_key_unresolved \
        "the §9 binding for prefix '$prefix' did not resolve: $(printf '%s' "$out" | tr '\n' ' ')"
      return "$YT_EXIT_CONFIG"
    fi
    key="$(printf '%s\n' "$out" | sed -n 's/^project_key=//p' | head -1)"
    if [[ -z "$key" ]]; then
      yt_report syncyt.config.project_key_unresolved \
        "prefix '$prefix' resolves through §9 to no project key -- an inner-source prefix is a declared SKIP, never a write"
      return "$YT_EXIT_CONFIG"
    fi
    if [[ -n "$envval" && "$envval" != "$key" ]]; then
      yt_report syncyt.config.project_key_env_ignored \
        "\$$envname is set to '$envval' but prefix '$prefix' binds project '$key' in CLAIRE_ORG.md §9 -- the BINDING wins; the environment value is ignored"
    fi
    # THE EXTENDED AUDIT LINE (§9 AUDIT, widened by BTG-179). The pre-existing
    # rule records the resolved TRACKER before contact so a wrong-tracker write
    # is visible up front. Multi-binding adds a second way to be wrong the old
    # line could not show -- the right tracker and the WRONG PROJECT -- and a
    # ticket that lands in another team's board is not recoverable by deleting
    # it, because it has already been seen. So the selection is made legible
    # BEFORE the request rather than reconstructable after it.
    yt_report syncyt.config.binding_selected \
      "prefix=$prefix project_key=$key tracker=$(printf '%s' "$out" | sed -n 's/^tracker=//p' | head -1) skill=$(printf '%s' "$out" | sed -n 's/^skill=//p' | head -1) source=$(printf '%s' "$out" | sed -n 's/^source=//p' | head -1)"
    printf '%s\n' "$key"
    return 0
  fi

  # --- (2) §9's scalar project-key line ----------------------------------
  key="$(yt_org_scalar_key "$org")"
  if [[ -n "$key" ]]; then
    if [[ -n "$envval" && "$envval" != "$key" ]]; then
      yt_report syncyt.config.project_key_env_ignored \
        "\$$envname is set to '$envval' but CLAIRE_ORG.md §9 declares project key '$key' -- the BINDING wins"
    fi
    yt_report syncyt.config.binding_selected \
      "prefix=${prefix:-n/a} project_key=$key source=scalar"
    printf '%s\n' "$key"
    return 0
  fi

  # --- (3) the deprecated environment variable ---------------------------
  if [[ -n "$envval" ]]; then
    yt_report syncyt.config.project_key_from_env \
      "the project key came from \$$envname, which is DEPRECATED as the project-key source and is removed after ONE release cycle -- declare it in CLAIRE_ORG.md §9 instead (see docs/migrations/multi-tracker-binding.md)"
    printf '%s\n' "$envval"
    return 0
  fi

  yt_report syncyt.config.project_key_unresolved \
    "no project key: §9 declares no per-prefix row for '${prefix:-<no prefix given>}', no scalar **Project key(s):** line, and \$$envname is unset"
  return "$YT_EXIT_CONFIG"
}

# yt_agent_user <ticket-id> -- BTG-315: the byte-parallel sibling of the Jira
# adapter's js_agent_user. The §9 per-prefix row's OPTIONAL fifth cell
# (`agent_user=` from the resolver's `--tracker` mode), or empty when
# unconfigured. No scalar fallback, no deprecated environment variable, and
# NEVER a config HALT: every failure mode resolves to EMPTY (unsplit) because
# split mode is strictly additive (AC-4).
yt_agent_user() {
  local subject="${1:-}" prefix="" org resolver out
  org="${CLAIRE_ORG_FILE:-$YT_ORG_FILE_DEFAULT}"
  resolver="${CLAIRE_ORG_RESOLVER:-$YT_ORG_RESOLVER_DEFAULT}"
  case "$subject" in
    *-*) prefix="${subject%%-*}" ;;
    *) return 0 ;;
  esac
  [[ -f "$resolver" ]] || return 0
  out="$(bash "$resolver" --tracker "$prefix" --org "$org" 2>/dev/null)" || return 0
  printf '%s\n' "$out" | sed -n 's/^agent_user=//p' | head -1
}
