#!/usr/bin/env bash
#
# authored-doc-orgtoken.sh -- the org-token portability predicate: no
# org-specific project token may appear in any path that ships to an adopter,
# outside an anchored, reasoned exemption ledger (BTG-191).
#
# Bounded context: Build tooling / compile-gate flow. Invariants relied on from
# outside this boundary: `artifacts/footprint.generated` is the source of record
# for which paths ship to an adopter, and `docs/agentic-sdlc/CLAIRE_ORG.md`
# section 16's target clauses are the source of record for the token set.
#
# SOURCED, never executed. Functions only -- no `set` change, no trap, no output.
# It relies on `adg_is_ledgered` and `BTG095_EXEMPTIONS` being defined by the
# caller BEFORE it is sourced.
#
# EXTRACTED VERBATIM from ci-templates/scripts/tests/btg-095-lib/guard.sh, whose
# whole subject this is. The four function bodies moved unchanged into this
# `adg_` namespace; guard.sh now defines the same four public names as one-line
# delegations, so every consumer of that library calls exactly what it always
# called and there is one body.
#
# WHY IT HAD TO MOVE. This is the largest of the three causes BTG-191 addresses:
# five of the seven Class-1 scenarios in the 2026-09-01 baseline sweep traced to
# one org token in `docs/agentic-sdlc/production-insights.md`, a `kind=seed` file
# installed into every adopting repository. Closing it needs a check at the
# triage-agent's PROD-entry append and at /claire-archive's insights writes, and
# `ci-templates/scripts/tests/` is a `framework_dev` path that does not ship, so
# the rule could not stay there.
#
# WHY IT IS ITS OWN FILE rather than a section of authored-doc-predicates.sh.
# Distinct subject, distinct source of record and distinct failure mode: the
# other two predicates read a release note against a manifest or an enumeration,
# while this one derives its needle set at run time and has a two-condition
# fail-closed refusal the others do not have. Held together the predicate file
# came to 468 lines, past the whole-file ceiling; split along this seam each
# half is a single coherent concern. The same split, for the same reason, that
# dead-citation-gate.sh made from dead-citation-ledgers.sh.
#
# HOLDS, AFTER BTG-247 (DEC-007's re-derived 324-line threshold, rows 13-21):
# the needle derivation (`ORG_TOKEN_CLAUSE_RE` et al., `adg_org_token_state`,
# `adg_org_tokens`) and the sweep (`adg_org_token_leaks`). The scan-scope
# helpers moved to `authored-doc-predicates.sh` (already a consumer of
# `adg_portable_paths`, DEC-003's subject argument) and `predicate_org_token`,
# the sweep's formatting wrapper, moved to the new `authored-doc-report.sh`
# (spec.md Proposed Design Step 5) -- this file no longer derives BOTH its scan
# scope and its needle set; it derives only the needle set now.
#
# WHY DERIVED, NEVER HARDCODED, AT BOTH LEVELS. The portable-path set is read from
# the footprint descriptor every run, so a newly-installed path is covered the day
# it lands. The TOKEN set is read from the org configuration's own target clauses
# every run, so a third adapter is swept the day its clause lands, with no edit
# here. Until BTG-175 the token was a hardcoded constant covering one of the two
# declared adapters, and the other adapter's eighteen literals were invisible to
# this enforcement from the day they landed to the day that was closed.
#
# PORTABILITY: bash + grep/awk/sed/sort/cut only. No `find` (the CI image installs
# no findutils, and busybox find is not GNU find), no `find -printf`, no python3.
#
# References: archive/BTG-095/decisions.md ; archive/BTG-175/decisions.md
#             DEC-003/DEC-020/DEC-021 ; archive/BTG-191/{spec,decisions}.md.

# The §16 target-clause FORM the token set is derived from, and the document it is
# read out of. This one pattern is the entire coupling between the guard and the
# governance declaration.
ORG_TOKEN_CLAUSE_RE='^- [*][*]Target — always ([A-Z][A-Z0-9]*), by name[.][*][*]'
ORG_TOKEN_SOURCE_REL='docs/agentic-sdlc/CLAIRE_ORG.md'

# The ADAPTER-DECLARATION form: §16 opens one subsection per adapter it admits.
#
# WHY A SECOND, INDEPENDENT SIGNAL (BTG-175 review B-1, DEC-020). Counting the
# target clauses and comparing that with the tokens derived FROM those same
# clauses is an identity, not a measurement -- it cannot fail, and it hid a
# fail-open in which a PARTIAL reword left the guard sweeping half the declared
# set and reporting clean. This heading is derived from a DIFFERENT part of the
# document, so "how many adapters are declared" and "how many tokens parsed" can
# genuinely disagree -- which is the whole point.
ORG_ADAPTER_DECL_RE='^#{2,4}[[:space:]]+Live[ -][Vv]alidation of the .* adapter[[:space:]]*$'

# adg_org_token_state <tree-root> -- WHICH OF THREE STATES section 16's adapter
# census puts this tree in. Echoes EXACTLY ONE literal and nothing else:
#
#   SOURCE_UNREADABLE  the org configuration is absent or unreadable
#   DECLARED_NONE      readable, and it declares no Live-Validation adapter
#   DECLARED_SOME      readable, and it declares at least one
#
# WHY IT EXISTS (BTG-250). `adg_org_tokens` has ONE empty answer and FIVE causes,
# and they were indistinguishable: an adopter that legitimately declares no
# adapter got the same FATAL as a repository whose every clause had been
# reworded. That made the WHOLE gate unrunnable, on every path including
# `--path` over an unrelated document, for a normal and supported configuration
# -- Live-Validation is opt-in per §16 -- and cost two composed insight entries
# in the reporting adopter (PROD_CLAIRE-032).
#
# THE DISCRIMINATOR IS THE HEADING CENSUS, NEVER THE TOKEN COUNT. Deciding
# whether the token derivation failed by counting the tokens it derived is an
# identity, not a measurement: exactly the fault BTG-175 review B-1 found. The
# census reads a DIFFERENT part of the document, so "declares an adapter" and
# "yielded a token" can genuinely disagree -- the only way the question can be
# answered at all.
#
# NO MARKER, NO FLAG, NO `git`. The state is read from the document ITSELF, so
# nothing is added to CLAIRE_ORG.md and §16 stays NOT a binding (DEC-003,
# confirmed at the gate as DEC-009). A template-faithful adopter -- the template
# carries no §16 at all -- is classified correctly the day it installs, with
# nothing to adopt and no upgrade step.
#
# READABILITY IS A DISTINCT STATE, not a kind of emptiness. An absent document
# says nothing about what the repository declares, so it can never resolve
# inert; its arm is the fail-closed one.
adg_org_token_state() {   # -> stdout: exactly one literal; rc always 0
  local org="$1/$ORG_TOKEN_SOURCE_REL"
  [ -f "$org" ] && [ -r "$org" ] || { echo SOURCE_UNREADABLE; return 0; }
  if grep -qE "$ORG_ADAPTER_DECL_RE" "$org" 2>/dev/null
  then echo DECLARED_SOME
  else echo DECLARED_NONE
  fi
}

# org_tokens <tree-root> -- the org tokens this guard sweeps, DERIVED from
# CLAIRE_ORG.md §16's own target clauses. Echoes one token per line, in the
# order §16 declares them. Returns 1, with a reason on stderr, when it derives
# NOTHING.
#
# READ FROM THE TREE ROOT UNDER TEST, symmetric with adg_portable_paths "$1" -- never
# a silent fallback to the real repository root. Deriving from $REPO_ROOT
# unconditionally would make a synthetic-tree probe unable to test the derivation
# at all, which is CLAIRE_DIRECTIVES.md Behavior 5's ungoverned decision, and would make
# every fail-closed scenario unwritable.
#
# AN INCOMPLETE DERIVATION IS A LOUD FAILURE, not only an EMPTY one. Two
# conditions, and both fail closed through the same channel:
#
#   (1) ZERO tokens -- file absent, unreadable, §16 absent, or EVERY clause
#       reworded. An empty census proves absence of DETECTION, not absence of the
#       thing (II-131).
#   (2) A DECLARED ADAPTER WHOSE TOKEN DID NOT PARSE -- §16 opens a subsection for
#       it, but no target clause matches the form ANYWHERE BETWEEN THAT HEADING
#       AND THE NEXT HEADING AT THE SAME OR SHALLOWER LEVEL, which is what
#       "inside that subsection" means here. The token set is then a strict
#       subset of what the document declares.
#
#       THE SCOPING IS LOAD-BEARING AND WAS WRONG ONCE (review B-2). The walk
#       originally closed a subsection only at the NEXT ADAPTER heading, so the
#       LAST one ran to end-of-file and any conforming clause later in the
#       document -- even in a different section entirely -- retro-marked it
#       resolved. Reproduced on the REAL governance document: YouTrack's clause
#       reworded plus one well-formed clause appended after §16 gave rc=0,
#       tokens for the FIRST adapter and for the appended clause, the SECOND
#       adapter's token silently absent, and a CLEAN sweep over a tree with an
#       unexempted occurrence of it planted in a shipping path. The concrete
#       tokens are named in archive/BTG-175/decisions.md DEC-020/DEC-021; they
#       are not repeated in this file, which ships to every adopting repository.
#
# (2) WAS MISSING UNTIL BTG-175's CODE REVIEW, and its absence was a fail-open
# rather than a gap in coverage (review B-1, DEC-020). Reworded PARTIALLY -- one
# adapter's clause altered, the others intact -- org_tokens returned the surviving
# tokens with rc=0 and no diagnostic, and the sweep ran over half the declared set
# and reported CLEAN. Reproduced before it was fixed: a third adapter subsection
# whose clause used a plain hyphen instead of an em dash yielded two tokens, and an
# unexempted third-adapter literal planted in a swept path produced ZERO leaks.
# That is BTG-059's defect -- an org literal shipping unseen -- recurring one
# adapter later, inside the very guard written to prevent it.
#
# It is still ONE RULE in the sense that matters: one verdict, one channel, one
# diagnostic shape. The polarity is never inverted per-branch, which is the trap
# PROD_CLAIRE-005 and BTG-174's B-4 both took.
#
# NOT ANCHORED TO THE SECTION NUMBER. The clause form is the discriminator and it
# is unique to §16; also matching `## 16.` would add a SECOND way to derive
# nothing (a renumber) for no detection gain -- the same "one rule, not three"
# argument applied to this function's own implementation.
# Read with awk, not `sed -n s///p`: the clause pattern is an EXTENDED regular
# expression, and sed's default BRE would need every group re-escaped -- two
# spellings of one pattern is one more chance for them to disagree. awk is ERE by
# definition and is already the guard's declared toolchain.
adg_org_tokens() {
  local org="$1/$ORG_TOKEN_SOURCE_REL" out toks unresolved
  # AN UNREADABLE SOURCE IS ITS OWN CAUSE, guarded EXPLICITLY rather than
  # swallowed by the awk's `2>/dev/null` below. A document that cannot be read
  # supports no claim about what the repository declares, so it must never be
  # described as one that declares nothing -- which is exactly what the shared
  # empty-set message did, sending an operator to look for a missing clause in a
  # file that is not there (BTG-250 DEC-005, rows 1 and 2).
  #
  # ABSENT and PRESENT-BUT-UNREADABLE stay ONE rule: same class, same message,
  # same rc, same seam. DEC-005 separates this class from "declares nothing" and
  # deliberately does not split it further.
  if [ ! -f "$org" ] || [ ! -r "$org" ]; then
    echo "org_tokens: the org configuration at $org is ABSENT or UNREADABLE, so no token set could be derived from it at all. That is not a repository declaring no adapter; it is a derivation failure, and never a clean sweep." >&2
    return 1
  fi
  # ONE awk pass emits both streams: the tokens, and the name of any adapter
  # subsection that declared itself and produced none. Walking the subsections
  # rather than counting two numbers is what makes the diagnostic name the
  # OFFENDING ADAPTER instead of reporting an arithmetic mismatch -- and it is
  # robust to a subsection that carries two clauses, which a count is not.
  #
  # Tokens are collected file-wide, exactly as before, so nothing this guard
  # already derived can be lost by the completeness check being added around it.
  out="$(awk -v re="$ORG_TOKEN_CLAUSE_RE" -v decl="$ORG_ADAPTER_DECL_RE" '
    $0 ~ decl {
      if (cur != "" && !seen[cur]) print "UNRESOLVED " cur
      cur = $0
      sub(/^#+[[:space:]]+/, "", cur)
      match($0, /^#+/); curlvl = RLENGTH
      next
    }
    # A heading that is NOT an adapter declaration CLOSES the open subsection --
    # but only when it is at the SAME OR SHALLOWER level, i.e. a sibling or a
    # parent. Without this rule the LAST adapter subsection ran to EOF, so a
    # conforming clause anywhere later in the document retro-marked it resolved
    # and the refusal was silently rescued (review B-2).
    #
    # LEVEL-AWARE ON PURPOSE, and this is a correction to the fix as proposed.
    # "Any heading closes it" was measured against a well-formed document
    # carrying a deeper `#### ...` heading nested inside an adapter subsection
    # BEFORE its target clause: it REFUSED -- a false positive on a document with
    # nothing wrong with it, which would redden the repo for everyone. Comparing
    # levels keeps a nested heading inside its subsection while still closing on a
    # sibling or a parent, which is what "inside that subsection" has to mean if
    # the diagnostic is to stay true. Verified both ways (DEC-021).
    /^#+[[:space:]]/ {
      match($0, /^#+/)
      if (cur != "" && RLENGTH <= curlvl) {
        if (!seen[cur]) print "UNRESOLVED " cur
        cur = ""
      }
      next
    }
    $0 ~ re {
      if (match($0, /always [A-Z][A-Z0-9]*, by name/)) {
        print "TOKEN " substr($0, RSTART + 7, RLENGTH - 16)
        if (cur != "") seen[cur] = 1
      }
    }
    END { if (cur != "" && !seen[cur]) print "UNRESOLVED " cur }
  ' "$org" 2>/dev/null)"

  toks="$(printf '%s\n' "$out" | sed -n 's/^TOKEN //p')"
  unresolved="$(printf '%s\n' "$out" | sed -n 's/^UNRESOLVED //p')"

  if [[ -z "$toks" ]]; then
    echo "org_tokens: derived NO org token from $org -- expected at least one clause of the form '- **Target - always <TOKEN>, by name.**'. An empty token set is a derivation failure, never a clean sweep." >&2
    return 1
  fi
  if [[ -n "$unresolved" ]]; then
    echo "org_tokens: INCOMPLETE derivation from $org -- $(printf '%s' "$unresolved" | grep -c .) declared adapter subsection(s) yielded no target clause of the form '- **Target - always <TOKEN>, by name.**': $(printf '%s' "$unresolved" | tr '\n' ';'). Sweeping a STRICT SUBSET of the declared adapters and reporting clean is the fail-open this check exists to close; refusing to report a partial sweep as a whole one." >&2
    return 1
  fi
  printf '%s\n' "$toks"
  return 0
}

# org_token_leaks <tree-root> -- echoes "<path>:<lineno>:<line>" for every
# occurrence of ANY derived org token in a shipping path that no exemption
# anchors. Always exits 0; the CALLER decides what an empty result means.
#
# A LINE CARRYING SEVERAL TOKENS IS PRINTED ONCE AND MATCHED ONCE: the tokens go
# to ONE grep as several -e patterns rather than to one grep per token, so the
# real analogue at docs/policies/surface-registry.md -- which names a live object
# id for BOTH declared adapters on a single line -- cannot inflate every count
# downstream.
#
# A DERIVATION FAILURE IS SURFACED THROUGH THIS SAME CHANNEL -- one synthetic line
#   <token-derivation>:0:FATAL org_tokens ...
# so every existing caller's `[[ -n "$leaks" ]]` turns red with NO caller change.
# A new out-of-band signal would have to be ADOPTED by each call site, and each
# would keep silently passing until it was.
adg_org_token_leaks() {
  local root="$1" p hit path lineno text tok why
  local -a pats=()
  # The REASON is captured, not re-derived: org_tokens fails for two distinct
  # conditions (nothing derived, and a declared adapter that did not parse), and a
  # synthetic line that named only the first would send a reader to fix the wrong
  # thing in exactly the case that motivated the second.
  why="$(adg_org_tokens "$root" 2>&1 >/dev/null || true)"
  while read -r tok; do
    [[ -n "$tok" ]] && pats+=(-e "$tok")
  done <<< "$(adg_org_tokens "$root" 2>/dev/null || true)"
  if [[ "${#pats[@]}" -eq 0 ]]; then
    # WHICH OF THE FIVE CAUSES IS THIS? The question the code had no way to ask
    # before BTG-250, and the adapter-heading census is what answers it -- never
    # the token count, which is the identity BTG-175 review B-1 found here.
    case "$(adg_org_token_state "$root")" in
      DECLARED_NONE)
        # INERT, AND ANNOUNCED. A rule that simply goes quiet is
        # indistinguishable from one that failed to run, so the state and the
        # document it was read from go to STDERR on every run -- never to
        # stdout, which is the record channel `adg_main` reads and where a
        # single line voids the whole sweep.
        echo "org_tokens: DECLARED_NONE -- ZERO adapter subsections found in $root/$ORG_TOKEN_SOURCE_REL, so this repository declares no Live-Validation adapter and has no org token to sweep. The org-token rule is INERT for this tree; every other predicate still reports." >&2
        return 0 ;;
      *)
        # SOURCE_UNREADABLE, DECLARED_SOME, and ANY unrecognized value -- the
        # empty string a missing or half-loaded classifier yields included.
        # THE FAIL-CLOSED ARM IS THE DEFAULT, never a named one. Written the
        # other way round, an absent classifier would resolve INERT and the gate
        # would certify a tree whose org-token rule had silently stopped
        # running: a fail-open, and the same defect shape in the opposite
        # direction from the one this branch closes.
        echo "<token-derivation>:0:FATAL ${why:-org_tokens derived no usable token set from $root/$ORG_TOKEN_SOURCE_REL} -- the sweep examined nothing and certifies nothing"
        return 0 ;;
    esac
  fi
  while read -r p; do
    [[ -z "$p" ]] && continue
    [[ -e "$root/$p" ]] || continue
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      # grep -rn on a FILE prints "lineno:text"; on a DIRECTORY "path:lineno:text".
      if [[ -d "$root/$p" ]]; then
        path="${hit%%:*}"; path="${path#"$root/"}"
        text="${hit#*:}"; lineno="${text%%:*}"; text="${text#*:}"
      else
        path="$p"; lineno="${hit%%:*}"; text="${hit#*:}"
      fi
      adg_is_exempt "$path" "$text" || echo "$path:$lineno:$text"
    done <<< "$(grep -rn -F "${pats[@]}" "$root/$p" 2>/dev/null || true)"
  done <<< "$(adg_portable_paths "$root")"
  return 0
}

