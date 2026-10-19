#!/usr/bin/env bash
#
# mint-id-binding.sh -- mint-id.sh's CLAIRE_ORG.md section 10 per-prefix
# allocator-binding delegation modes: --binding, --binding-for,
# --allocator-prefixes, --guard-ticket-seed, plus their shared
# resolver_required() predicate.
#
# Bounded context: CLAIRE framework tooling / id-allocation seam (same as
# mint-id.sh, which this file is SOURCED by, unconditionally, right after
# `action`/positional-argument parsing and before the core ledger modes
# --peek/--reserve/--seed/--list). Invariant relied on from outside this
# boundary: same as mint-id.sh's own -- CLAIRE_ORG.md section 10 governs
# whether the TICKET prefix mints locally or resolves through a bound
# external allocator; this file is the resolution half of that question.
#
# WHY THIS IS ITS OWN FILE (BTG-247, DEC-002's original mint-id carve-out,
# taken up again under DEC-008's hybrid convergence): mint-id.sh measured 399
# lines with zero headroom (AC-1). mint-id.sh SHIPS via the sidecar-directory
# mechanism (PI-023/DEC-001: the Claude Code adapter copies the whole
# colocated artifacts/commands/claire-mint/ directory into .claude/skills/claire-mint/,
# and sidecar-completeness-gate.sh asserts that image is complete and has no
# orphan), so a peer file here needs NO adopt-claire.sh COPY_PATHS row and
# NO upgrade-collect.sh RECONCILE row -- verified: neither array names
# mint-id.sh or any file beside it (DEC-004/DEC-009). Genuinely delivery-free.
#
# WHY THIS SEAM: the four blocks moved here (plus resolver_required, their
# shared predicate) are ALL section-10-binding-resolution concerns, entirely
# distinct in subject from the core ledger-allocation logic that stays in
# mint-id.sh (resolve_index/highest_for/rows_for/width_for/fmt_id/
# --peek/--reserve/--seed/--list). None of the four blocks is referenced by
# name from any other file or test by its FILE location -- each is reached
# only through mint-id.sh's own `action` dispatch, which is unaffected by
# which file defines the code it runs (this file is sourced, unconditionally,
# into the same shell). `width_for()` stays in mint-id.sh -- it is
# sed-anchored by name in btg-197-citation-sweep.test.sh and is core ledger
# logic, not a binding-resolution concern.
#
# Moved VERBATIM, byte-for-byte, from mint-id.sh (lines 127-350 as measured
# 2026-09-16) -- no re-wrap, no compression, no logic change (AC-9/AC-10's
# discipline, applied here even though this is a .sh split, not the .md
# class -- moving content unchanged is this ticket's rule everywhere).
#
# Spec: archive/BTG-247/spec.md AC-1 (headroom), DEC-002 (original carve-out),
# DEC-008 (hybrid convergence, Option A applies to mint-id).

# `binding_status()` IS GONE (BTG-242). It was §10's SCALAR lexer, reading the
# `**Bound allocator(s):**` line that ticket removes. Deleting it was the safer option,
# not the tidier one: with nothing left to lex it would have answered `unbound` for
# EVERY org file forever, including one whose table binds a real external allocator --
# a wrong answer with a zero exit, and both seed steps act on it
# (`idalloc.seed.ticket_prefix_seeded_while_bound`). `--binding` DELEGATES.
#
# §10's REGISTERED RESOLUTION RULE IS UNCHANGED (ADR_CLAIRE-0011 polarity: a missing
# binding is MINT, the inverse of §9's fail-loud). BTG-242 removed a DECLARATION FORM,
# not that rule -- and this comment carries the citation the deleted lexer used to,
# because the rule outlived the code that read it.
#
# resolver_required <org> -- true when ORG carries a §10 per-prefix allocator table
# with at least one DATA row (a header and a separator are not a table). When true, the
# shared resolver is the ONLY thing allowed to answer a per-prefix question; when false
# nothing is declared at all -- every prefix is unmatched, every prefix mints -- and the
# resolver, which an un-upgraded adopter or a pre-adopt invocation does not have, is not
# consulted. UNCHANGED BY BTG-242: it is this script's ONLY grammar-adjacent predicate
# now rather than one of two, which is the point of deleting the second.
resolver_required() {
  local org="${1:-docs/agentic-sdlc/CLAIRE_ORG.md}"
  [[ -f "$org" ]] || return 1
  awk '
    /^### Per-prefix allocator bindings/ { intable=1; next }
    intable && /^#{2,3} /                { exit }
    intable && /^\| *Ticket prefix/      { next }
    intable && /^\|[ -]*-[- |]*\|/       { next }
    intable && /^\|/                     { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$org"
}

# usage() and the `action`/positional-argument parse stay in mint-id.sh --
# `action` is already set by the time this file is sourced (see this file's
# own header). Duplicating either here would re-consume $1 via a second
# `shift` and silently corrupt `action` for every mode below.

# --binding [ORG] -- the REPO-WIDE bound/unbound predicate, now DELEGATED (BTG-242). Reads
# an org file, not the ledger, so it precedes ledger resolution and works pre-adopt. A
# repo-wide answer is ill-defined once prefixes bind differently, so this mode answers only
# where one EXISTS and fails loud where it does not. IT NEVER LEXES THE GRAMMAR.
#
#  (1) REMOVED LINE PRESENT -> halt idalloc.binding.form_removed. A PRESENCE test, never a
#      value lexer: it must fire whether or not the resolver is installed.
#  (2) ROWS DECLARED, RESOLVER ABSENT -> IMPOSSIBLE_STATE resolver_unavailable, exit 1.
#  (3) ROWS DECLARED, RESOLVER PRESENT -> enumerate, CAPTURING stdout so the enumerator's
#      EXIT STATUS is testable. A refusal MUST halt idalloc.binding.enumeration_refused and
#      never fall through to (5)'s `unbound`, which is SEAM-6 answered_from_ignorance in
#      its UNSAFE direction: it seeds a prefix whose ids originate outside. Then ask
#      --allocator per prefix: agree -> print it; DIFFER -> halt prefix_required, naming
#      --binding-for PREFIX -- two answers is PRESENT-and-ambiguous, not ABSENT.
#  (4) SUCCEEDED, YIELDED NOTHING (§10-independent / `*` / placeholder rows only) -> no
#      TICKET prefix is declared, so (5)'s `unbound` is REACHED, never fallen into.
#  (5) NOTHING DECLARED -> `unbound`, exit 0, AND DO NOT INVOKE THE RESOLVER. §10's MINT
#      polarity, preserving the pre-adopt / un-upgraded path.
if [[ "$action" == "--binding" ]]; then
  borg="${1:-docs/agentic-sdlc/CLAIRE_ORG.md}"
  if [[ -f "$borg" ]] && grep -q '^\*\*Bound allocator(s):\*\*' "$borg" 2>/dev/null; then   # (1)
    echo "condition=idalloc.binding.form_removed" >&2
    echo "mint-id: '$borg' still declares '**Bound allocator(s):**', a declaration form REMOVED by BTG-242 and no longer read. Delete the line and declare one row per ticket-id prefix in '### Per-prefix allocator bindings'." >&2
    echo "       §10's repo-wide 'id_scheme:' field is NOT removed and must stay. See docs/migrations/scalar-binding-removal.md; upgrade the framework FIRST, convert the file SECOND." >&2
    exit 1
  fi
  if resolver_required "$borg"; then
    bresolver="${CLAIRE_ORG_RESOLVER:-ci-templates/scripts/org-binding-resolve.sh}"
    if [[ ! -f "$bresolver" ]]; then                                                        # (2)
      emit_seam IMPOSSIBLE_STATE idalloc.binding.resolver_unavailable "$bresolver"
      echo "Error: '$borg' declares a per-prefix allocator table but the shared binding resolver is not at '$bresolver'." >&2
      echo "       Refusing to answer: a guessed 'unbound' would seed a local ledger row for ids that originate externally." >&2
      exit 1
    fi
    bplist="$(bash "$bresolver" --allocator-prefixes --org "$borg" 2>/dev/null)" || {       # (3)
      printf '%s\n' "condition=idalloc.binding.enumeration_refused" "mint-id: the shared resolver REFUSED to enumerate '$borg'; re-run it as 'org-binding-resolve.sh --allocator-prefixes --org $borg' for the condition= it names. Refusing to answer: an 'unbound' here would be answered from ignorance, and both seed steps act on it." >&2
      exit 1; }
    bseen=""
    while IFS= read -r bp; do
      [[ -n "$bp" ]] || continue
      bans="$(bash "$bresolver" --allocator "$bp" --org "$borg" 2>/dev/null | sed -n 's/^allocator=//p')" || exit 1
      [[ -n "$bans" ]] || { echo "Error: the resolver gave no allocator answer for prefix '$bp' in '$borg'." >&2; exit 1; }
      if [[ -z "$bseen" ]]; then bseen="$bans"
      elif [[ "$bseen" != "$bans" ]]; then
        echo "condition=idalloc.binding.prefix_required" >&2
        echo "mint-id: '$borg' declares prefixes that do not all bind the same way ('$bseen' and '$bans'), so a repo-wide bound/unbound answer does not exist for this file." >&2
        echo "       Ask the question that does have an answer: --binding-for PREFIX [CLAIRE_ORG.md]." >&2
        exit 1
      fi
    done <<<"$bplist"
    if [[ -n "$bseen" ]]; then echo "$bseen"; exit 0; fi
  fi
  # (4) a SUCCESSFUL empty enumeration reaches here; (5) nothing declared reaches here.
  echo unbound
  exit 0
fi

# --binding-for PREFIX [ORG]: the PER-PREFIX form of the same question (BTG-179).
# ADDITIVE -- `--binding` above is byte-unchanged, because its five existing
# callers do not know this mode exists and must be unable to tell it was added.
#
# The answer comes from the SHARED resolver, never from a second copy of the
# grammar lexer living here: the per-prefix grammar has exactly one reader
# (ci-templates/scripts/org-binding-resolve.sh), and a sidecar that re-implemented it
# would drift from it silently. Since BTG-242 there is no second lexer at all, so
# "never from a copy" is structural rather than a rule this handler has to keep.
if [[ "$action" == "--binding-for" ]]; then
  bp="${1:-}"; borg="${2:-docs/agentic-sdlc/CLAIRE_ORG.md}"
  if [[ -z "$bp" ]]; then usage; fi
  # Located the same way --binding locates its org file: repo-relative under
  # $PWD, so it works pre-adopt and outside a git tree. CLAIRE_ORG_RESOLVER is
  # the test seam, matching this script's existing CLAIRE_LEDGER /
  # CLAIRE_FLOCK_CMD convention.
  resolver="${CLAIRE_ORG_RESOLVER:-ci-templates/scripts/org-binding-resolve.sh}"
  # A PRESENT per-prefix table with an UNREACHABLE resolver is fail-loud, never a
  # degraded answer. Before BTG-242 a degraded answer WAS available -- the deleted
  # scalar lexer would have called EVERY prefix bound, including ones whose rows
  # declare the closed default -- and that availability was this guard's whole
  # reason. The lexer is gone; the guard stays, because the caller needs a refusal
  # rather than silence.
  if resolver_required "$borg" && [[ ! -f "$resolver" ]]; then
    emit_seam IMPOSSIBLE_STATE idalloc.binding.resolver_unavailable "$resolver"
    echo "Error: '$borg' declares a per-prefix allocator table but the shared binding resolver is not at '$resolver'." >&2
    echo "       Refusing to answer at all -- an invented 'unbound' would seed a prefix whose ids may originate externally." >&2
    exit 1
  fi
  out="$(bash "$resolver" --allocator "$bp" --org "$borg" 2>/dev/null)" || exit 1
  printf '%s\n' "$out" | sed -n 's/^allocator=//p'
  exit 0
fi

# --allocator-prefixes [ORG]: every TICKET prefix §10 declares, one per line, in
# table order (BTG-180). The two seed steps read this as their work queue.
# ADDITIVE -- every existing mode is byte-unchanged.
#
# HANDLED HERE, BEFORE resolve_index(), for the same reason --binding and
# --binding-for are: resolve_index() CREATES the ledger's parent directory as a
# side-effect of resolving it, and adopt asks this question before any ledger
# exists. A read-only question about a config file must not manufacture one.
#
# DELEGATES, NEVER LEXES. The per-prefix grammar has exactly one reader
# (ci-templates/scripts/org-binding-resolve.sh); a second copy here is the drift
# DEC-004 exists to prevent and DEC-030 already paid for -- the copies and the
# canonical parser disagreed about where a per-prefix table ends.
#
# TABLE ABSENT => print nothing, exit 0, AND DO NOT INVOKE THE RESOLVER. This is
# a TABLE test, not a file-presence test: an un-upgraded adopter or a pre-adopt
# invocation simply does not have the resolver, and must be unaffected.
#
# TABLE PRESENT + RESOLVER ABSENT => FAIL CLOSED, in the shape --binding-for and
# --guard-ticket-seed already carry. The degraded answer is available here, which
# is exactly why the guard exists: an empty enumeration on a file declaring three
# prefixes means "seed one prefix", which is the defect this mode removes,
# arriving with a zero exit.
if [[ "$action" == "--allocator-prefixes" ]]; then
  aorg="${1:-docs/agentic-sdlc/CLAIRE_ORG.md}"
  if resolver_required "$aorg"; then
    aresolver="${CLAIRE_ORG_RESOLVER:-ci-templates/scripts/org-binding-resolve.sh}"
    if [[ ! -f "$aresolver" ]]; then
      emit_seam IMPOSSIBLE_STATE idalloc.binding.resolver_unavailable "$aresolver"
      echo "Error: '$aorg' declares a per-prefix allocator table but the shared binding resolver is not at '$aresolver'." >&2
      echo "       Refusing to answer from an empty list -- that would seed one prefix and silently skip the rest." >&2
      exit 1
    fi
    bash "$aresolver" --allocator-prefixes --org "$aorg" || exit 1
  fi
  exit 0
fi

# --guard-ticket-seed PREFIX [ORG]: the single defense-in-depth check both seed
# steps (adopt/upgrade) share before seeding a TICKET prefix. ADR/II/PROD are
# §10-independent and always allowed; any OTHER prefix seeded while §10 is bound
# is a LOGIC_FAULT (idalloc.seed.ticket_prefix_seeded_while_bound) -- a bound
# tracker's ids originate externally, so a local ticket-ledger row would be a
# dead, false source of truth. Exits 0 (allowed) or non-zero (fault, seam fired).
#
# BTG-197: the three `_CLAIRE`-suffixed prefixes are CLAIRE core's own record
# identifiers, §10-independent for the reason the bare three are -- always minted
# locally. A core ADR number never originates in an adopting repo's tracker, so a
# bound §10 has nothing to say about it. ADDITIVE: the bare three are untouched.
#
# EXACT LITERALS, never `ADR*`: this arm decides whether a prefix may be seeded at
# all, so a loose pattern would silently exempt an adopter's own ADRIAN tickets
# from the very fault the guard exists to raise.
if [[ "$action" == "--guard-ticket-seed" ]]; then
  gp="${1:-}"; gorg="${2:-docs/agentic-sdlc/CLAIRE_ORG.md}"
  case "$gp" in
    ADR|II|PROD) exit 0 ;;   # always local, §10-independent
    ADR_CLAIRE|II_CLAIRE|PROD_CLAIRE) exit 0 ;;   # core's own, likewise
  esac
  # PER-PREFIX WHEN A TABLE IS PRESENT -- the shape BTG-179 corrected. THE REPO-WIDE
  # FALLBACK IS GONE (BTG-242) because the lexer it called is, and the two states
  # replacing it are NOT the same: a file declaring a REMOVED FORM is REFUSED (neither
  # bound nor readable -- `unbound` there would let a prefix whose ids may originate
  # externally take a local ledger row, the exact fault this guard raises), while a
  # file declaring NOTHING is ALLOWED (§10's mint polarity, and the pre-adopt path).
  if [[ -f "$gorg" ]] && grep -q '^\*\*Bound allocator(s):\*\*' "$gorg" 2>/dev/null; then
    emit_seam LOGIC_FAULT idalloc.seed.ticket_prefix_seeded_while_bound "$gp"
    echo "condition=idalloc.binding.form_removed" >&2
    echo "Error: refusing to seed '$gp' -- '$gorg' still declares '**Bound allocator(s):**', REMOVED by BTG-242, so its §10 binding cannot be resolved and a refusal is not 'unbound'. See docs/migrations/scalar-binding-removal.md." >&2
    exit 1
  fi
  if resolver_required "$gorg"; then
    gresolver="${CLAIRE_ORG_RESOLVER:-ci-templates/scripts/org-binding-resolve.sh}"
    if [[ ! -f "$gresolver" ]]; then
      emit_seam IMPOSSIBLE_STATE idalloc.binding.resolver_unavailable "$gresolver"
      echo "Error: '$gorg' declares a per-prefix allocator table but the shared binding resolver is not at '$gresolver'." >&2
      exit 1
    fi
    gstatus="$(bash "$gresolver" --allocator "$gp" --org "$gorg" 2>/dev/null | sed -n 's/^allocator=//p')" || exit 1
  else
    gstatus="unbound"
  fi
  if [[ "$gstatus" == "bound" ]]; then
    emit_seam LOGIC_FAULT idalloc.seed.ticket_prefix_seeded_while_bound "$gp"
    echo "Error: refusing to seed ticket prefix '$gp' -- §10 binds an external allocator (ids originate externally)." >&2
    exit 1
  fi
  exit 0
fi
