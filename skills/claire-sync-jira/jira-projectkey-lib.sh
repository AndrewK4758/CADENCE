#!/usr/bin/env bash
#
# jira-projectkey-lib.sh -- the SINGLE project-key resolver for this adapter
# (BTG-179).
#
# Bounded context: Tracker projection / Jira Server-DC adapter.
# Invariants relied on from outside this boundary:
#   - `CLAIRE_ORG.md` §9 #tracker-binding is the single per-repo tracker
#     binding, and BTG-179 admits the PROJECT KEY into it. Base URLs and
#     credentials stay in the environment: an identifier is configuration, a
#     credential is not.
#   - `ci-templates/scripts/org-binding-resolve.sh` is the SOLE reader of the
#     per-prefix grammar. This file never re-implements it.
#
# WHY A SEPARATE FILE rather than jira-lib.sh, which the spec's file table named:
# jira-lib.sh sits at 397 lines against a 400-line DX ceiling that
# btg-157-hardenings.test.sh S-7.10 pins at 399 with an explicit
# "must not GROW" assertion (BTG-113 DEC-017). There is no room for a resolver
# there, and widening that wall is precisely the outcome that seam forbids.
# Relocating whole into a sibling library is this adapter's established pattern
# (jira-type-lib.sh, jira-umbrella-lib.sh, jira-meta.sh). Recorded as BTG-179
# DEC-016.
#
# RESOLUTION ORDER, and the reason it is an order rather than a set:
#   (1) the ticket prefix's §9 per-prefix row      -- the binding
#   (2) §9's scalar `**Project key(s):**` line     -- the binding, single-binding form
#   (3) the environment variable named by the config `env` block
#       -- DEPRECATED. Sunset: ONE release cycle, per
#          docs/policies/deprecation-policy.md's *Configuration keys (env vars,
#          feature flags)* row, which is more specific than the host surface's
#          Stable two-cycle level. Migration: docs/migrations/multi-tracker-binding.md.
#
# On the (1) path an EMPTY key HALTS and (2)/(3) are UNREACHABLE: a binding that
# is present and incomplete is never rescued from the environment, or an operator
# who mistyped one table cell silently writes to whatever their shell last
# exported.
#
# And on a per-prefix repo an ABSENT PREFIX HALTS the same way -- (2) and (3) are
# UNREACHABLE there too, so a caller that supplies no prefix never reaches the
# environment variable. Level (1) needs a prefix, and a repo-wide DEFAULT is not
# an answer to a per-prefix binding: the binding is not losing to the
# environment, it is UNREACHABLE, and answering anyway writes a perfectly valid
# issue to whatever project the shell last exported (BTG-206). The remedy is
# `--prefix PREFIX`, or a ticket id -- and, since BTG-242, ONLY that. §9's
# `**Bound tracker(s):**` line is REMOVED, so instructing an operator to declare
# the repo-wide form now yields a repo that halts `tracker.binding.form_removed`.
#
# CHANNELS. This function is called inside `$(...)`, where an `exit` would leave
# only the SUBSHELL, so it REPORTS on stderr and RETURNS non-zero; every call site
# is written `KEY="$(js_project_key ...)" || exit "$JS_EXIT_CONFIG"`. A halt that
# only killed the subshell would hand the caller an empty key -- the silent
# fallback this whole file exists to prevent.

JS_ORG_FILE_DEFAULT="docs/agentic-sdlc/CLAIRE_ORG.md"
JS_ORG_RESOLVER_DEFAULT="ci-templates/scripts/org-binding-resolve.sh"

# js_org_section9 <org> -- §9's region, from its own heading to the next TOP-LEVEL
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
js_org_section9() {
  awk -v pat="^## (9\\\\. )?Tracker Binding[[:space:]]*\$" '
    $0 ~ pat     { g=1; print; next }
    g && /^## /   { exit }
    g             { print }' "$1" 2>/dev/null
}

# js_org_perprefix_table <org> -- true iff §9 carries a per-prefix table with at
# least one DATA row. A header and a separator are not a table.
js_org_perprefix_table() {
  [[ -f "$1" ]] || return 1
  js_org_section9 "$1" | awk '
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

# js_org_scalar_key <org> -- §9's scalar `**Project key(s):**` value, trimmed of
# whitespace and backticks; empty when absent or still a template placeholder.
js_org_scalar_key() {
  local v
  v="$(js_org_section9 "$1" | sed -n 's/^\*\*Project key(s):\*\*[[:space:]]*//p' | head -1)"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v#\`}"; v="${v%\`}"
  case "$v" in "<"*">") v="" ;; "{{"*) v="" ;; esac
  printf '%s' "$v"
}

# js_project_key <ticket-id> | --prefix <PREFIX>
#
# TWO CALLING FORMS, because two call sites know two different things. A write
# knows the TICKET; a reservation is creating the ticket and knows only the
# PREFIX the operator selected. Deriving a prefix from a hyphenless string would
# make `--prefix DEF` and a malformed ticket id indistinguishable, so the caller
# says which it has.
js_project_key() {
  local subject="${1:-}" prefix="" org resolver envname envval out key
  org="${CLAIRE_ORG_FILE:-$JS_ORG_FILE_DEFAULT}"
  resolver="${CLAIRE_ORG_RESOLVER:-$JS_ORG_RESOLVER_DEFAULT}"

  if [[ "$subject" == "--prefix" ]]; then
    prefix="${2:-}"
    [[ -n "$prefix" ]] || { js_report syncjs.config.prefix_underivable \
      "--prefix was given with no value"; return "$JS_EXIT_CONFIG"; }
  elif [[ -n "$subject" ]]; then
    case "$subject" in
      *-*) prefix="${subject%%-*}" ;;
      *)   js_report syncjs.config.prefix_underivable \
             "no ticket-id prefix can be derived from '$subject' -- the whole id is never treated as a prefix"
           return "$JS_EXIT_CONFIG" ;;
    esac
  fi

  envname="$(js_config_map env project_key)" || return "$JS_EXIT_CONFIG"
  envval="${!envname:-}"

  # --- (1) the prefix's §9 row -------------------------------------------
  if [[ -n "$prefix" ]] && js_org_perprefix_table "$org"; then
    if [[ ! -f "$resolver" ]]; then
      js_report syncjs.config.resolver_unavailable \
        "$org declares a per-prefix tracker table but the shared binding resolver is not at '$resolver' -- refusing to answer from the environment"
      return "$JS_EXIT_CONFIG"
    fi
    if ! out="$(bash "$resolver" --tracker "$prefix" --org "$org" 2>&1)"; then
      js_report syncjs.config.project_key_unresolved \
        "the §9 binding for prefix '$prefix' did not resolve: $(printf '%s' "$out" | tr '\n' ' ')"
      return "$JS_EXIT_CONFIG"
    fi
    key="$(printf '%s\n' "$out" | sed -n 's/^project_key=//p' | head -1)"
    if [[ -z "$key" ]]; then
      js_report syncjs.config.project_key_unresolved \
        "prefix '$prefix' resolves through §9 to no project key -- an inner-source prefix is a declared SKIP, never a write"
      return "$JS_EXIT_CONFIG"
    fi
    # THE DIVERGENCE NOTICE. Silently preferring the binding is still a surprise
    # to an operator whose shell exports a different value; they are told which
    # one won rather than left to infer it from the issue that appeared.
    if [[ -n "$envval" && "$envval" != "$key" ]]; then
      js_report syncjs.config.project_key_env_ignored \
        "\$$envname is set to '$envval' but prefix '$prefix' binds project '$key' in CLAIRE_ORG.md §9 -- the BINDING wins; the environment value is ignored"
    fi
    # THE EXTENDED AUDIT LINE (§9 AUDIT, widened by BTG-179). The pre-existing
    # rule records the resolved TRACKER before contact so a wrong-tracker write
    # is visible up front. Multi-binding adds a second way to be wrong the old
    # line could not show -- the right tracker and the WRONG PROJECT -- and a
    # ticket that lands in another team's board is not recoverable by deleting
    # it, because it has already been seen. So the selection is made legible
    # BEFORE the request rather than reconstructable after it.
    js_report syncjs.config.binding_selected \
      "prefix=$prefix project_key=$key tracker=$(printf '%s' "$out" | sed -n 's/^tracker=//p' | head -1) skill=$(printf '%s' "$out" | sed -n 's/^skill=//p' | head -1) source=$(printf '%s' "$out" | sed -n 's/^source=//p' | head -1)"
    printf '%s\n' "$key"
    return 0
  fi

  # --- (1b) THE PRECONDITION GATE ----------------------------------------
  # Level (1) above is guarded on a NON-EMPTY prefix AND the table predicate, so
  # an EMPTY prefix short-circuits before the table is ever consulted -- and
  # resolution would land on the DEPRECATED environment variable while a complete
  # binding sits one argument away, unread. That is not the binding losing to the
  # environment; it is the binding being UNREACHABLE.
  #
  # THIS GATE RESTS ON THE PRINCIPLE, NOT ON THE ABSENCE OF A LINE (BTG-242). It
  # used to be justified by §9's two declaration forms being EXCLUSIVE, so that a
  # per-prefix repo had no scalar line at (2) to fall to. BTG-242 RETIRED that
  # exclusivity and RETAINED `**Project key(s):**`, so a per-prefix table and a
  # repo-wide key line may now legitimately coexist, and the old justification is
  # plainly false about such a file. The gate itself is unchanged and still right,
  # on the ground it always really stood on: `**Project key(s):**` is a repo-wide
  # DEFAULT, and defaulting past a DECLARED per-prefix binding for want of an
  # argument is exactly the bypass this gate refuses. (2) is therefore preempted
  # DELIBERATELY rather than vacuously.
  #
  # This is the same axis the (1) path already decided: "a binding that is
  # present and incomplete is never rescued from the environment"
  # (docs/migrations/multi-tracker-binding.md §1). A binding that is present and
  # UNCONSULTABLE is the same class of state, so it takes the same answer.
  #
  # SCOPED BY CONSTRUCTION, not by a caller list: the prefix is empty ONLY when
  # js_project_key is called with no arguments at all. A ticket-id caller either
  # derives a prefix or has already halted at `prefix_underivable`, and
  # `--prefix` with no value likewise. So jira-write-issue.sh and
  # jira-umbrella-lib.sh can never enter this block, and no enumeration of
  # callers has to be maintained as callers change.
  #
  # FAILS OPEN ON AN ABSENT ORG FILE, inherited from level (1)'s own predicate
  # (`js_org_perprefix_table` returns non-zero when the file is missing). That
  # polarity is pre-existing and deliberately unchanged here; a repo with no org
  # file has no binding to be unreachable.
  #
  # THE REMEDY IS NAMED INLINE, and since BTG-242 there is exactly ONE. An
  # operator told only that they are wrong has to go and find out what to do. What
  # resolves this state is supplying the prefix -- as `--prefix PREFIX` or as a
  # ticket id. Declaring a repo-wide form is NOT a second remedy any more:
  # `**Bound tracker(s):**` is removed and that instruction now yields a halting
  # repo, and a `**Project key(s):**` line does not help because this gate is
  # reached before (2). Naming a remedy that does not work is worse than naming
  # one, so only the one that works is named.
  if [[ -z "$prefix" ]] && js_org_perprefix_table "$org"; then
    js_report syncjs.config.project_key_precondition_unmet \
      "$org declares a PER-PREFIX tracker table but no prefix was supplied, so the binding cannot be consulted -- and a repo-wide **Project key(s):** default is not an answer to a per-prefix binding, so it is not consulted either. Refusing to answer from \$$envname: a declared binding is never bypassed for want of an argument. Pass --prefix PREFIX, or a ticket id"
    return "$JS_EXIT_CONFIG"
  fi

  # --- (2) §9's scalar project-key line ----------------------------------
  key="$(js_org_scalar_key "$org")"
  if [[ -n "$key" ]]; then
    if [[ -n "$envval" && "$envval" != "$key" ]]; then
      js_report syncjs.config.project_key_env_ignored \
        "\$$envname is set to '$envval' but CLAIRE_ORG.md §9 declares project key '$key' -- the BINDING wins"
    fi
    js_report syncjs.config.binding_selected \
      "prefix=${prefix:-n/a} project_key=$key source=scalar"
    printf '%s\n' "$key"
    return 0
  fi

  # --- (3) the deprecated environment variable ---------------------------
  if [[ -n "$envval" ]]; then
    js_report syncjs.config.project_key_from_env \
      "the project key came from \$$envname, which is DEPRECATED as the project-key source and is removed after ONE release cycle -- declare it in CLAIRE_ORG.md §9 instead (see docs/migrations/multi-tracker-binding.md)"
    printf '%s\n' "$envval"
    return 0
  fi

  js_report syncjs.config.project_key_unresolved \
    "no project key: §9 declares no per-prefix row for '${prefix:-<no prefix given>}', no scalar **Project key(s):** line, and \$$envname is unset"
  return "$JS_EXIT_CONFIG"
}

# js_agent_user <ticket-id> -- BTG-315: the §9 per-prefix row's OPTIONAL fifth
# cell (`agent_user=` from the resolver's `--tracker` mode), or empty when
# unconfigured.
#
# Unlike js_project_key this has NO scalar fallback and NO deprecated
# environment variable: the agent-time user is a per-prefix-only setting.
# Every failure mode -- an undervivable prefix, an absent resolver, an
# unresolved binding -- resolves to EMPTY (unsplit) rather than a config
# HALT, because split mode is strictly additive (AC-4): nothing about
# resolving it may turn an otherwise-working sync into a halt for an
# adopter who never asked for the split.
js_agent_user() {
  local subject="${1:-}" prefix="" org resolver out
  org="${CLAIRE_ORG_FILE:-$JS_ORG_FILE_DEFAULT}"
  resolver="${CLAIRE_ORG_RESOLVER:-$JS_ORG_RESOLVER_DEFAULT}"
  case "$subject" in
    *-*) prefix="${subject%%-*}" ;;
    *) return 0 ;;
  esac
  [[ -f "$resolver" ]] || return 0
  out="$(bash "$resolver" --tracker "$prefix" --org "$org" 2>/dev/null)" || return 0
  printf '%s\n' "$out" | sed -n 's/^agent_user=//p' | head -1
}
