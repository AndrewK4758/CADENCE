#!/usr/bin/env bash
#
# upgrade-idseed.sh -- PI-039 create-if-missing scan-and-seed for /cadence-upgrade.
#
# Bounded context: Upgrade seam / id-allocation bootstrap (PI-039, DEC-006).
# Invariant relied on from outside this boundary: mint-id.sh --seed is one-time
# (refuses an already-seeded prefix), so this whole module is idempotent by
# construction; CADENCE_ORG.md §10 governs whether the TICKET prefix is seeded.
#
# Sourced by upgrade-cadence.sh; reads TARGET / CORE / DRY_RUN from the engine
# scope (dynamic scoping, like upgrade-bootstrap.sh / upgrade-modes.sh -- globals
# resolve at call time). Dispatched by the engine's --seed-ledger mode, OUTSIDE
# main()'s atomic merge transaction, and NEVER touches the .cadence-version stamp.
#
# WHY: a pre-allocator adopter with months of specs/+archive/+docs/ADR/ history
# (and intent-insights.md / production-insights.md) has no reserve ledger yet.
# Scanning their real high-water marks and --seed-ing each prefix ensures the
# first --reserve never collides with or reuses an already-minted id (M-3).
#
# References: specs/PI-039/{spec,decisions}.md (DEC-006) ; PROD_CADENCE-001 (PI-031).

idseed_mint() { echo "${CORE}/artifacts/commands/cadence-mint/mint-id.sh"; }

# A build-time seam fires as a stderr line + the caller's non-zero exit.
idseed_seam() { echo "seam_type=$1 event_name=$2 subject=${3:-}" >&2; }

# PROD_CADENCE-001 lesson (mirrors assert_not_dry_run): a seed WRITE attempted under
# --dry-run is an UNSOUND_CONDITION. Normal flow returns before the write in
# dry-run mode; this guard is the defense-in-depth checkpoint at the write site.
idseed_assert_not_dry_run() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    idseed_seam UNSOUND_CONDITION upgrade.idseed.write_under_dry_run "${1:-seed}"
    echo "upgrade-idseed: BUG -- a seed write was attempted under --dry-run" >&2
    return 1
  fi
}

# Highest numeric suffix for a ticket-style prefix across specs/+archive/ dir names.
idseed_scan_ticket() {
  local prefix="$1" max=0 n d base
  for base in "$TARGET/specs" "$TARGET/archive"; do
    [[ -d "$base" ]] || continue
    for d in "$base/$prefix"-*; do
      [[ -e "$d" ]] || continue
      n="${d##*/}"; n="${n#"$prefix"-}"
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      n=$((10#$n)); (( n > max )) && max=$n
    done
  done
  echo "$max"
}

# Highest ADR number from docs/ADR/NNNN-*.md filenames.
idseed_scan_adr() {
  local max=0 n f
  [[ -d "$TARGET/docs/ADR" ]] || { echo 0; return; }
  for f in "$TARGET/docs/ADR"/[0-9]*.md; do
    [[ -e "$f" ]] || continue
    n="${f##*/}"; n="${n%%-*}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    n=$((10#$n)); (( n > max )) && max=$n
  done
  echo "$max"
}

# Highest NNN for a grep-able series (II / PROD) in a markdown file.
idseed_scan_series() {
  local prefix="$1" file="$2" max=0 n
  [[ -f "$file" ]] || { echo 0; return; }
  while read -r n; do
    [[ -n "$n" ]] || continue
    n=$((10#$n)); (( n > max )) && max=$n
  done < <(grep -oE "${prefix}-[0-9]+" "$file" 2>/dev/null | sed -E "s/${prefix}-//")
  echo "$max"
}

# Resolve the ticket prefix from §10 id_scheme (`<PREFIX>-NNN`); empty when the
# scheme is an un-substituted placeholder or absent (ticket self-seeds later).
idseed_ticket_prefix() {
  local org="$TARGET/docs/agentic-sdlc/CADENCE_ORG.md" p
  [[ -f "$org" ]] || return 0
  p="$(awk -F'`' '/id_scheme:/ {for(i=2;i<=NF;i++) if($i ~ /-N+$/){print $i; exit}}' "$org" 2>/dev/null | sed -E 's/-N+$//' || true)"
  case "$p" in ""|*"<"*|*"{{"*) return 0 ;; esac
  echo "$p"
}

# Seed one prefix to N, honoring create-if-missing (--seed refuses a seeded
# prefix) and --dry-run (report only, write nothing). Reports the action.
idseed_one() {
  local prefix="$1" n="$2" mint out; mint="$(idseed_mint)"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "  would seed: $prefix to high-water $n (dry-run: nothing written)"
    return 0
  fi
  idseed_assert_not_dry_run "$prefix" || return 1   # defense-in-depth at the write site
  if out="$( (cd "$TARGET" && bash "$mint" --seed "$prefix" "$n") 2>&1 )"; then
    echo "  seeded: $prefix to high-water $n"
  elif echo "$out" | grep -qi 'already seeded'; then
    echo "  skip: $prefix already seeded (create-if-missing)"
  else
    echo "upgrade-idseed: ERROR seeding $prefix: $out" >&2
    return 1
  fi
}

# The adopter's org file as an ABSOLUTE path (BTG-180 cycle 2, DEC-014).
#
# $TARGET MAY BE RELATIVE: `upgrade-cadence.sh` sets
# `TARGET="${UPGRADE_TARGET:-$PWD}"` and never absolutises it, and the documented
# invocation places no constraint on the value. Every enumeration child below
# runs inside `(cd "$TARGET" && ...)` and is handed `"$TARGET/docs/..."`, which
# no longer resolves AFTER that cd -- the child reports "no table", the
# enumeration comes back EMPTY, the run falls through to the scalar path and
# exits 0 having written zero ticket rows. That is B1's failure class with a
# different trigger, so the path is resolved ONCE here rather than per call site.
#
# SCOPED TO THE PER-PREFIX FUNCTIONS ON PURPOSE. $TARGET itself is NOT rewritten:
# doing so would put new behaviour on the scalar path, and the scalar path is
# already correct under a relative target (its own `--binding-for` /
# `--guard-ticket-seed` reads fall back to §10's MINT polarity and it seeds from
# `$TARGET/specs`, read before any cd). DEC-002 stays intact.
#
# Returns 1 -- never a half-resolved path -- when $TARGET is not a readable
# directory; the callers turn that into a loud halt.
idseed_org_abs() {
  local root
  root="$(cd "$TARGET" 2>/dev/null && pwd)" || return 1
  [[ -n "$root" ]] || return 1
  printf '%s/docs/agentic-sdlc/CADENCE_ORG.md' "$root"
}

# The ticket prefixes §10 DECLARES, one per line -- empty on the scalar form
# (BTG-180). Echoes nothing and returns 1 when the enumeration cannot be
# obtained, with the reason on stderr: a declared table the resolver cannot
# answer for is NOT "no prefixes declared", and absorbing it into an empty list
# would seed nothing while reporting complete success (PROD_CADENCE-022's signature).
#
# Run from $TARGET so `--allocator-prefixes` locates the shared resolver
# repo-relative under $PWD, exactly as `--binding-for` already does.
idseed_declared_prefixes() {
  local mint org etmp out rc
  mint="$(idseed_mint)"
  org="$(idseed_org_abs)" \
    || { echo "upgrade-idseed: ERROR target '$TARGET' is not a readable directory" >&2; return 1; }
  [[ -f "$org" ]] || return 0
  etmp="$(mktemp)"
  out="$( (cd "$TARGET" && bash "$mint" --allocator-prefixes "$org") 2>"$etmp" )"; rc=$?
  # THE CHANNELS STAY SEPARATE. The wildcard-row diagnostic travels on stderr,
  # and merging it into stdout would make a diagnostic indistinguishable from a
  # declared prefix -- and then seed a prefix named after a sentence.
  if [[ $rc -ne 0 ]]; then
    echo "upgrade-idseed: ERROR enumerating §10's declared ticket prefixes: $(tr '\n' ' ' < "$etmp")" >&2
    rm -f "$etmp"; return 1
  fi
  cat "$etmp" >&2
  rm -f "$etmp"
  printf '%s' "$out"
}

# The PER-PREFIX seed path (BTG-180). Reached only when §10 declares a
# per-prefix table; the scalar form falls to run_idseed_mode()'s untouched
# body below, which is what makes a single-prefix adopter byte-identical BY
# CONSTRUCTION rather than by a branch that happens to agree (DEC-002).
#
# Each prefix carries the WHOLE existing per-prefix contract -- `--binding-for`,
# then `--guard-ticket-seed` AT THE WRITE SITE, then its OWN scanned high-water.
# The guard is per PREFIX, not per RUN: hoisting it out of the loop would check
# the first prefix and wave the rest through.
#
# TWO PASSES, and the split is load-bearing rather than tidy. Pass 1 resolves
# EVERY declared prefix's binding BEFORE the first write, so the expected set is
# known up front. That is what lets a halt at prefix k name the prefixes it did
# NOT attempt, and what lets the completeness seam name every declared prefix on
# a run that halted before writing anything -- a set built as the loop went would
# omit exactly the prefixes an operator most needs to hear about.
idseed_seed_declared() {
  local list="$1" mint org p binding todo=() targets=() i
  mint="$(idseed_mint)"
  org="$(idseed_org_abs)" \
    || { echo "upgrade-idseed: ERROR target '$TARGET' is not a readable directory" >&2; return 1; }
  mapfile -t todo <<< "$list"
  echo "upgrade-idseed: scan-and-seed (prefixes=$(IFS=,; echo "${todo[*]}")$([[ "${DRY_RUN:-0}" -eq 1 ]] && echo ', dry-run'))"
  # ADR/II/PROD are §10-independent and always local -- their own scanners, their
  # own unconditional seeding, never folded into the ticket scan (DEC-005 cl.2).
  idseed_one ADR  "$(idseed_scan_adr)" || return 1
  idseed_one II   "$(idseed_scan_series II   "$TARGET/docs/agentic-sdlc/intent-insights.md")" || return 1
  idseed_one PROD "$(idseed_scan_series PROD "$TARGET/docs/agentic-sdlc/production-insights.md")" || return 1
  # PASS 1 -- who is eligible. A bound prefix's ids originate externally, so a
  # local high-water row would be a dead, false source of truth; it is reported,
  # never merely omitted, because an unreported skip is indistinguishable from a
  # prefix the enumeration never saw.
  for p in "${todo[@]}"; do
    binding="$( (cd "$TARGET" && bash "$mint" --binding-for "$p" "$org") 2>/dev/null || echo unbound)"
    if [[ "$binding" == "unbound" ]]; then
      targets+=("$p")
    else
      echo "  skip: ticket prefix '$p' (bound allocator -- its ids originate externally)"
    fi
  done
  # PASS 2 -- the writes. HALT AT THE FIRST FAILURE (DEC-004): a failing seed
  # usually means the ledger or the resolver is broken, and continuing writes
  # further rows under a condition already known untrustworthy. NOTHING IS ROLLED
  # BACK -- the ledger is append-only and each --seed is independently valid, so
  # the partial state is the RESUMABLE state, not a corrupt one.
  for (( i = 0; i < ${#targets[@]}; i++ )); do
    p="${targets[i]}"
    if ! (cd "$TARGET" && bash "$mint" --guard-ticket-seed "$p" "$org") >/dev/null 2>&1; then
      idseed_halt_at "$p" "the write-site guard refused it (§10 binds an external allocator)" "${targets[@]:i+1}"
      idseed_report_completeness "${targets[@]}"
      return 1
    fi
    if ! idseed_one "$p" "$(idseed_scan_ticket "$p")"; then
      # idseed_one has already printed the underlying failure text on stderr;
      # this adds WHERE it stopped and WHAT is still missing.
      idseed_halt_at "$p" "see the error above" "${targets[@]:i+1}"
      idseed_report_completeness "${targets[@]}"
      return 1
    fi
  done
  idseed_report_completeness "${targets[@]}"
}

# idseed_halt_at <prefix> <reason> <unattempted>... -- the AC-6 failure message.
# It names the failing prefix, the reason, and the prefixes NOT ATTEMPTED, so an
# operator never has to diff the ledger against §10 to learn what is missing --
# which is the reading exercise PROD_CADENCE-022 records nobody performing.
idseed_halt_at() {
  local p="$1" why="$2"; shift 2
  echo "upgrade-idseed: ERROR seeding ticket prefix '$p': $why" >&2
  if [[ $# -gt 0 ]]; then
    echo "upgrade-idseed: halted at '$p'; prefixes not attempted: $(IFS=,; echo "$*")" >&2
  else
    echo "upgrade-idseed: halted at '$p'; every other declared prefix was already attempted" >&2
  fi
}

# idseed_report_completeness <prefix>... -- the PROD_CADENCE-022 seam. Fires when the
# run finishes with fewer ledger rows than §10 declared.
#
# IT ASKS THE LEDGER, not a counter the loop kept. A counter re-states the loop's
# own belief, and the defect class here is precisely a step believing it did more
# than it did -- so only a re-read can tell "seeded" from "has a row".
#
# THE ZERO-DECLARED CASE IS GUARDED, not "passing" (II-167). On a scalar repo --
# every current adopter -- both sides are 0 and an unguarded equality holds
# vacuously, so a completely broken check would look healthy forever.
#
# DRY-RUN IS EXCLUDED: a run that deliberately wrote nothing is not an
# incomplete run, and emitting a defect signal for it would teach an operator to
# ignore the seam.
idseed_report_completeness() {
  local mint rows p missing=""
  [[ $# -ge 1 ]] || return 0
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  mint="$(idseed_mint)"
  rows="$( (cd "$TARGET" && bash "$mint" --list) 2>/dev/null || true )"
  for p in "$@"; do
    printf '%s\n' "$rows" | grep -q "^$p-[0-9]" || missing="$missing,$p"
  done
  [[ -n "$missing" ]] || return 0
  idseed_seam DELTA_AUDIT_GAP idalloc.seed.prefix_unenumerated "${missing#,}"
  echo "upgrade-idseed: the ledger carries no high-water row for: ${missing#,} -- the first --reserve under each would collide with an id that already exists" >&2
}

# The --seed-ledger entry point. §10-gates the ticket prefix; ADR/II/PROD always.
run_idseed_mode() {
  local mint; mint="$(idseed_mint)"
  [[ -f "$mint" ]] || { echo "upgrade-idseed: allocator not found at $mint" >&2; return 1; }
  local org="$TARGET/docs/agentic-sdlc/CADENCE_ORG.md"
  # PER-PREFIX §10 => the enumeration. SCALAR §10 => the body below, unedited.
  # The two paths never merge (BTG-180 DEC-002).
  local declared; declared="$(idseed_declared_prefixes)" || return 1
  if [[ -n "$declared" ]]; then
    # THE UNION (DEC-013, superseding DEC-002 / AC-3 R1). §10's *Per-prefix
    # resolution* rule says a prefix with NO ROW in the table MINTS BY
    # CONVENTION, and that this is not a degraded answer but THE answer -- so the
    # prefix §10's repo-wide `id_scheme:` names is governed, legal and
    # locally-minting, and needs a high-water row exactly as much as a listed
    # one. While the two reads were MUTUALLY EXCLUSIVE it got none, on a run that
    # exited 0 and emitted no seam: PROD_CADENCE-022's own signature, and a REGRESSION --
    # the pre-change tree seeded it.
    #
    # APPENDED ON THIS BRANCH ONLY. The scalar path below is reached solely when
    # $declared is EMPTY, so DEC-002's identity-by-construction is untouched.
    # It also enters $targets, hence the completeness seam's expected set, so an
    # underrun on it is VISIBLE rather than merely fixed.
    local utp; utp="$(idseed_ticket_prefix)"
    # MIRRORS THE ENUMERATOR'S OWN EXCLUSION. resolve_allocator_prefixes() drops
    # ADR/II/PROD from the TABLE read because they are §10-independent and read by
    # scanners of their own (DEC-005 cl.2) -- `docs/ADR/NNNN-*.md` is a path shape
    # idseed_scan_ticket cannot see. Without this the SAME input re-enters by the
    # other door: an `id_scheme: ADR-NNN` arrives as a declared ticket prefix,
    # and only the unconditional block ABOVE running first (plus --seed's
    # refusal) keeps the high-water right. Ordering is not a contract.
    case "$utp" in ADR|II|PROD) utp="" ;; esac
    if [[ -n "$utp" ]] && ! printf '%s\n' "$declared" | grep -qxF -- "$utp"; then
      declared="$declared"$'\n'"$utp"
    fi
    idseed_seed_declared "$declared"; return $?
  fi
  # THE TICKET PREFIX IS RESOLVED FIRST, because the binding question is asked
  # ABOUT IT (BTG-179 AC-8). The repo-wide `--binding` cannot answer it on a
  # multi-binding org: the scalar lexer reads the literal `Per-prefix` on §10's
  # bound line and calls it bound, so EVERY prefix is skipped -- including the
  # ones whose own §10 row declares `None -- closed default` and whose whole
  # point is that they mint locally. `--binding-for` asks about this prefix.
  local tp; tp="$(idseed_ticket_prefix)"
  local binding="n/a"
  if [[ -n "$tp" ]]; then
    # Run from $TARGET: --binding-for locates the shared resolver repo-relative
    # under $PWD, exactly as --binding locates its org file.
    #
    # A REFUSAL IS NOT `unbound` (BTG-242). This read used to swallow a non-zero
    # exit and substitute `unbound`, "preserving §10's MINT polarity" -- which was
    # true while the only way to fail was a missing resolver. It is not true now:
    # an org file still declaring a REMOVED declaration form HALTs, and reading
    # that halt as `unbound` is `idalloc.binding.answered_from_ignorance` -- a
    # repo-wide verdict manufactured from a refusal, on the path that WRITES the
    # ledger. The `--guard-ticket-seed` check below did stop the write, but the
    # run then reported "while bound" for a file that is neither bound nor
    # readable, sending the operator to fix the wrong thing.
    #
    # So the refusal is CARRIED rather than replaced: `binding` becomes the
    # sentinel `unresolvable`, which matches NEITHER the `unbound` seed arm nor the
    # bound-skip arm, and the ticket-prefix branch below refuses loudly.
    #
    # THE REFUSAL IS SCOPED TO THE TICKET PREFIX. ADR/II/PROD are §10-INDEPENDENT
    # -- always minted locally, even by a tracker-bound adopter -- so an
    # unresolvable §10 must not stop them being seeded. Aborting here instead would
    # make an org-file grammar problem withhold three prefixes that do not consult
    # §10 at all.
    local bfor_out bfor_rc
    bfor_out="$( (cd "$TARGET" && bash "$mint" --binding-for "$tp" "$org") 2>&1 )"; bfor_rc=$?
    if [[ "$bfor_rc" -ne 0 ]]; then
      binding="unresolvable"
      IDSEED_BINDING_WHY="$(printf '%s' "$bfor_out" | tr '\n' ' ')"
    else
      binding="$bfor_out"
    fi
  fi
  echo "upgrade-idseed: scan-and-seed (prefix=${tp:-<unresolved>} binding=$binding$([[ "${DRY_RUN:-0}" -eq 1 ]] && echo ', dry-run'))"
  # ADR/II/PROD are §10-independent and always local.
  idseed_one ADR  "$(idseed_scan_adr)" || return 1
  idseed_one II   "$(idseed_scan_series II   "$TARGET/docs/agentic-sdlc/intent-insights.md")" || return 1
  idseed_one PROD "$(idseed_scan_series PROD "$TARGET/docs/agentic-sdlc/production-insights.md")" || return 1
  # Ticket prefix: ONLY when a concrete prefix resolves AND ITS OWN binding is unbound.
  if [[ -z "$tp" ]]; then
    echo "  skip: ticket prefix not resolvable from §10 id_scheme (self-seeds on first --reserve)"
  elif [[ "$binding" == "unresolvable" ]]; then
    # A REFUSAL IS NOT `unbound` (BTG-242). Reported as its own outcome, distinct
    # from both the bound skip and the unresolvable-PREFIX skip above, because the
    # three send an operator to fix three different things.
    idseed_seam UNSOUND_CONDITION idalloc.binding.answered_from_ignorance "$tp"
    echo "upgrade-idseed: refusing to seed ticket prefix '$tp' -- its §10 binding could not be resolved from $org." >&2
    echo "       ${IDSEED_BINDING_WHY:-<no diagnostic>}" >&2
    echo "       A refusal is not 'unbound': seeding on one would write a local ledger row for ids that may originate externally." >&2
    return 1
  elif [[ "$binding" == "unbound" ]]; then
    if ! (cd "$TARGET" && bash "$mint" --guard-ticket-seed "$tp" "$org") >/dev/null 2>&1; then
      echo "upgrade-idseed: refusing to seed ticket prefix '$tp' while bound" >&2; return 1
    fi
    idseed_one "$tp" "$(idseed_scan_ticket "$tp")" || return 1
  else
    echo "  skip: ticket prefix '$tp' (bound allocator -- its ids originate externally)"
  fi
}
