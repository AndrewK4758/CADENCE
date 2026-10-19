#!/usr/bin/env bash
# adopt-provision.sh -- the "provision" half of adopt's copy/provision seam.
#
# Bounded context: CADENCE adoption / the /cadence-adopt installer surface.
#
# THE SEAM. adopt-cadence.sh COPIES the framework into the target; this module
# PROVISIONS the target's own repository. Every block here writes something the
# ADOPTER owns -- the repository skeleton, generated create-once artifacts,
# registrations into adopter-owned config, and the id-allocation ledger seed.
# Every block that copies framework-owned bytes verbatim stayed behind. That
# boundary is the file's own: each block below was already annotated
# "create-once", "generated here (NOT copied)" or "surgically register", while
# every retained block is a verbatim copy.
#
# Invariants relied on from outside this boundary:
#   - SOURCED, never executed. Every function reads SRC / DST / copied / skipped
#     / note_copied / note_skipped / GITIGNORE_* from the CALLER's scope at call
#     time, exactly as gitignore-block.sh does. Running this file as a
#     subprocess would lose the counters the summary line reports.
#   - The caller runs under `set -euo pipefail`, so a failed command inside a
#     function aborts adoption rather than degrading it. The explicit `exit 1`
#     paths below are therefore reachable failure handling, not belt-and-braces.
#   - CALL ORDER IS BEHAVIOR and is preserved exactly by the entry point:
#     skeleton -> generated artifacts -> registrations -> [gitignore flag] ->
#     id ledger. The blocks are unchanged relocations, not rewrites.
#
# Spec: archive/BTG-132/spec.md (Scope 2b); decisions.md DEC-005 (the named seam),
# following archive/BTG-078/decisions.md DEC-019.

# --- version resolution (serves the version stamp only) --------------------
# Resolve CORE's version-of-record from the SRC repo (PI-021 / DEC-002). The
# canonical source is README.md line "**Version X.Y.Z**" (always present), with
# the highest version git tag as a cross-check (BTG-303: the repository's bound
# version scheme, resolved from CADENCE_ORG.md#version-scheme-binding, not
# assumed to be semver here -- this regex/sort mechanism was verified correct
# for a four-digit-year CalVer value too). Echoes the resolved version, or
# nothing if it cannot be resolved (an unresolvable version is a fatal stamp
# write -- never a "version=unknown" stamp; AC-4 edge case). The version is read
# ONLY from SRC (core), never from the adopter's $DST.
resolve_core_version() {
  local src="$1" readme_ver tag_ver
  readme_ver="$(sed -nE 's/^\*\*Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' \
                  "$src/README.md" 2>/dev/null | head -n1)"
  tag_ver="$(git -C "$src" tag 2>/dev/null \
               | sed -nE 's/^v?([0-9]+\.[0-9]+\.[0-9]+)$/\1/p' \
               | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)"
  # README line is canonical; the tag is a cross-check only. If the README line
  # is absent, fall back to the tag; if neither resolves, echo nothing (fatal).
  if [[ -n "$readme_ver" ]]; then
    printf '%s' "$readme_ver"
  elif [[ -n "$tag_ver" ]]; then
    printf '%s' "$tag_ver"
  fi
}

# --- the adopter's repository skeleton --------------------------------------
provision_repo_skeleton() {
# CHANGELOG.md: fresh skeleton — the CADENCE repo's own file records the
# framework's release history and must not be copied.
if [[ -e "$DST/CHANGELOG.md" ]]; then
  note_skipped "CHANGELOG.md"
else
  cat > "$DST/CHANGELOG.md" <<'EOF'
# Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Entries are generated from spec archives. Each entry links to the archived spec for full context.

## [Unreleased]
EOF
  note_copied "CHANGELOG.md (fresh skeleton)"
fi

# archive/: empty directory — completed specs accumulate here.
if [[ -d "$DST/archive" ]]; then
  note_skipped "archive/"
else
  mkdir -p "$DST/archive"
  touch "$DST/archive/.gitkeep"
  note_copied "archive/ (empty)"
fi

# specs/drafts/: a gitignored local drafting area for problem statements before
# /cadence-triage (BTG-010). The folder is tracked; its contents are ignored by a
# .gitignore that keeps only itself (* then !.gitignore). Create-if-absent —
# an existing .gitignore may hold adopter-customized patterns; never overwrite.
if [[ -e "$DST/specs/drafts/.gitignore" ]]; then
  note_skipped "specs/drafts/.gitignore"
else
  mkdir -p "$DST/specs/drafts"
  printf '*\n!.gitignore\n' > "$DST/specs/drafts/.gitignore"
  note_copied "specs/drafts/.gitignore (gitignored drafting area)"
fi
}

# --- generated create-once artifacts ----------------------------------------
provision_generated_artifacts() {
# artifacts/footprint.generated: the ADOPTER eject descriptor (PI-017 DEC-011).
# Generated here (NOT copied from the framework repo): the framework's own
# descriptor is deny-by-default and would wrongly strip an adopter's project
# code. The adopter descriptor is the precise installed CADENCE surface
# (categories 1+2 only); eject in the adopter repo reads it to strip only
# framework material, never project files.
rel="artifacts/footprint.generated"
if [[ -e "$DST/$rel" ]]; then
  note_skipped "$rel"
else
  mkdir -p "$(dirname "$DST/$rel")"
  # Descriptor generation failure is FATAL — without it, eject in the adopted
  # repo has no boundary and would fail open. Adoption must NOT report success
  # with the eject descriptor absent (II-014: verify post-conditions, never
  # warn-and-continue past a missing deliverable). PI-017 DEC-012.
  if bash "$SRC/ci-templates/scripts/cadence-eject.sh" --derive-adopter-footprint \
       > "$DST/$rel" 2>/dev/null && [[ -s "$DST/$rel" ]]; then
    note_copied "$rel (adopter descriptor, generated)"
  else
    rm -f "$DST/$rel"
    echo >&2
    echo "ERROR: could not generate the adopter eject descriptor ($rel)." >&2
    echo "Adoption aborted — eject in the adopted repo requires this descriptor;" >&2
    echo "refusing to report success without it." >&2
    exit 1
  fi
fi

# BTG-083: the dead-citation BASELINE is GENERATED for the adopter's own tree,
# never copied — core's baseline is DEBT naming core's files, and installing it
# would both be meaningless in the adopter repo and SILENCE that repo's real
# findings. Create-once, exactly like the eject descriptor and the version stamp
# above: an existing baseline is the adopter's own ledger and is never clobbered.
#
# The gate fails CLOSED on a missing baseline (it refuses to report a verdict it
# did not compute), so adoption must leave a valid one behind or /cadence-archive's
# blocking step is dead on arrival. Generating rather than writing an empty file
# means the adopter starts from a truthful record of the debt they already have,
# green on the first run, with the ratchet holding from that point forward.
#
# A generation FAILURE is NOT fatal here, unlike the eject descriptor: eject
# without a boundary would fail OPEN and strip the wrong files, whereas a missing
# citation baseline makes the gate fail CLOSED and merely blocks until a human
# runs --emit-baseline. Warn loudly and name the command; never abort adoption
# over a ledger the adopter can regenerate in one line.
rel="ci-templates/scripts/dead-citation-baseline.txt"
if [[ -e "$DST/$rel" ]]; then
  note_skipped "$rel"
else
  mkdir -p "$(dirname "$DST/$rel")"
  if bash "$DST/ci-templates/scripts/dead-citation-gate.sh" --root "$DST" --emit-baseline \
       > "$DST/$rel" 2>/dev/null && [[ -s "$DST/$rel" ]]; then
    note_copied "$rel (adopter debt ledger, generated for this tree)"
  else
    rm -f "$DST/$rel"
    echo >&2
    echo "WARNING: could not generate the dead-citation baseline ($rel)." >&2
    echo "  /cadence-archive's citation-disposition step and the dead-citation gate row will" >&2
    echo "  FAIL CLOSED until it exists. Generate it with:" >&2
    echo "    bash ci-templates/scripts/dead-citation-gate.sh --emit-baseline \\" >&2
    echo "      > ci-templates/scripts/dead-citation-baseline.txt" >&2
  fi
fi

# .cadence-version: the core version stamp (PI-021) is now written by the
# RELEASE PHASE (BTG-314, adopt-release-tree.sh), before this function ever
# runs -- it must name the commit whose tree gets installed (DEC-011), and the
# COPY_PATHS work below runs only inside that commit's own materialized tree.
# note_copied is called there directly (the counters are the caller's scope,
# exactly as here). Create-once still holds: the release phase never overwrites
# an existing stamp (R11). resolve_core_version (above) stays defined in THIS
# file -- it is the version-of-record reader the release phase reuses.
}

# --- surgical registrations into adopter-owned config -----------------------
provision_registrations() {
# .claude/settings.json: surgically register the CADENCE hooks (BTG-008 / AC-3).
# Create the file if absent (CADENCE entries only); if present, insert only the
# CADENCE hook entries, preserving all project-owned content (env, project
# hooks). Ownership is the .claude/cadence-hooks/ command-path sentinel (DEC-002).
# Fatal-on-failure with a post-condition verify (II-014): adoption must NOT report
# success with the registration absent. Pure POSIX shell (no jq), atomic, fail-loud.
rel=".claude/settings.json"
# >>> binding-resolution (clause-7 exempt) >>>
hooks_adapter="$SRC/ci-templates/scripts/adapters/claude-code-hooks.sh"
# <<< binding-resolution (clause-7 exempt) <<<
hooks_manifest="$SRC/artifacts/hooks/hooks.manifest"
if [[ -f "$hooks_adapter" && -f "$hooks_manifest" ]]; then
  # shellcheck source=/dev/null
  . "$hooks_adapter"
  if cc_hook_settings_add "$DST/$rel" "$hooks_manifest" \
       && [[ -s "$DST/$rel" ]] && grep -q '\.claude/cadence-hooks/' "$DST/$rel"; then
    note_copied "$rel (hooks registered)"
  else
    echo >&2
    echo "ERROR: could not register the CADENCE hooks in $rel." >&2
    echo "Adoption aborted — refusing to report success without hook registration." >&2
    exit 1
  fi
else
  echo >&2
  echo "ERROR: hooks adapter/manifest missing in source (adoption incomplete)." >&2
  exit 1
fi

# .mcp.json: surgically register the CADENCE MCP servers (BTG-057 / AC-3).
# Mirrors the hook-registration block above: create the file if absent (CADENCE
# entries only); if present, insert only the CADENCE MCP server entries,
# preserving every adopter-owned MCP server + non-mcpServers content. Ownership is
# the reserved `cadence-` server-key prefix sentinel (DEC-002). Additive,
# atomic, fail-loud, pure POSIX shell (no jq). Fatal-on-failure with a
# post-condition verify (II-014): adoption must NOT report success with the
# registration absent. The Claude MCP surface is `.mcp.json` at the repo root
# (mcpServers); the OpenCode adopt call-site is wired only where an OpenCode adopt
# seam exists in the fleet (OQ-4 / DEC-007) -- this adopt path is Claude-concrete.
# >>> binding-resolution (clause-7 exempt) >>>
rel_mcp=".mcp.json"
mcp_adapter="$SRC/ci-templates/scripts/adapters/claude-code-mcp.sh"
# <<< binding-resolution (clause-7 exempt) <<<
mcp_manifest="$SRC/artifacts/mcp/mcp.manifest"
if [[ -f "$mcp_adapter" && -f "$mcp_manifest" ]]; then
  # shellcheck source=/dev/null
  . "$mcp_adapter"
  # The post-condition is SCOPED TO WHAT THE MANIFEST DECLARES (BTG-176 AC-16).
  # It previously read `grep -q '"cadence-'` unconditionally, which silently
  # assumed the manifest carries at least one row -- so emptying the manifest
  # (DEC-013 removed the last one) made every adoption ABORT with a DELTA_AUDIT_GAP
  # over a registration nothing had asked for. The verify still fails loud when
  # rows ARE declared and none landed; it is the ONE case of "nothing declared,
  # nothing registered" that is now a success rather than a fault.
  mcp_declared="$(mcp_manifest_keys "$mcp_manifest")"
  if cc_mcp_registry_add "$DST/$rel_mcp" "$mcp_manifest" \
       && [[ -s "$DST/$rel_mcp" ]] \
       && { [[ -z "$mcp_declared" ]] || grep -q '"cadence-' "$DST/$rel_mcp"; }; then
    if [[ -n "$mcp_declared" ]]; then
      note_copied "$rel_mcp (MCP servers registered)"
    else
      # Never "registered" when nothing was: an audit line that overstates what
      # happened is the same defect class as a silent skip, read the other way.
      note_copied "$rel_mcp (no CADENCE MCP server to register -- the manifest carries zero rows)"
    fi
  else
    # emit_seam is provided by the sourced adapter (mcp-registry-verify.sh, guarded).
    emit_seam DELTA_AUDIT_GAP adopt.postcondition.mcp_absent "$DST/$rel_mcp"
    echo >&2
    echo "ERROR: could not register the CADENCE MCP servers in $rel_mcp." >&2
    echo "Adoption aborted — refusing to report success without MCP registration." >&2
    exit 1
  fi
else
  echo >&2
  echo "ERROR: MCP adapter/manifest missing in source (adoption incomplete)." >&2
  exit 1
fi
}

# provision_seed_completeness <prefix>... -- the PROD_CADENCE-022 completeness seam on
# the adopt path (BTG-180 AC-7). Fires when provisioning ends with fewer ledger
# rows than it set out to write, whether it ended by completing or by failing.
#
# IT ASKS THE LEDGER, never a counter the loop kept: a counter re-states the
# loop's own belief, and the defect class here is a step believing it did more
# than it did. `emit_seam` is not defined at this point in adoption -- the MCP
# block defines it, and it runs in a different function -- so the line is emitted
# directly in the shape every other seam in this file uses.
provision_seed_completeness() {
  local missing="" rows p
  [[ $# -ge 1 ]] || return 0
  rows="$( (cd "$DST" && bash "$MINT_ID" --list) 2>/dev/null || true )"
  for p in "$@"; do
    printf '%s\n' "$rows" | grep -q "^$p-[0-9]" || missing="$missing,$p"
  done
  [[ -n "$missing" ]] || return 0
  echo "seam_type=DELTA_AUDIT_GAP event_name=idalloc.seed.prefix_unenumerated subject=${missing#,}" >&2
  echo "ERROR: the id ledger carries no high-water row for: ${missing#,}" >&2
}

# --- the PI-039 id-allocation ledger seed -----------------------------------
provision_id_ledger() {
# PI-039: seed the id-allocation ledger (generate-if-absent, fatal-on-failure).
# Runs AFTER the deliverable-copy blocks and BEFORE the verify loop (so --peek
# can assert the ledger resolves). The allocator is the SOURCE mint-id.sh (always
# present when adopt runs); it resolves the ledger against $DST's git-common-dir
# (or $DST/.cadence fallback), so the seed lands in the adopter's shared ledger.
# ADR is seeded ALWAYS (§10-independent); the ticket prefix is seeded ONLY when
# §10 is unbound AND a concrete prefix is resolvable (DEC-008). On a fresh-from-
# template repo the ticket prefix self-seeds at -001 on the first --reserve.
# Seeding is create-if-absent: --seed refuses an already-seeded prefix, so a
# re-adopt leaves the ledger byte-untouched. The ledger carries NO footprint row
# (adopter data, like CHANGELOG.md/archive/ — AC-14).
MINT_ID="$SRC/artifacts/commands/cadence-mint/mint-id.sh"
if [[ -f "$MINT_ID" ]]; then
  adopter_org="$DST/docs/agentic-sdlc/CADENCE_ORG.md"
  seed_prefixes=(ADR)
  # EVERY prefix §10 DECLARES, not just the one §10's repo-wide `id_scheme:`
  # names (BTG-180). A multi-prefix adopter with history under a second prefix
  # otherwise gets no high-water row for it, and that prefix's first `--reserve`
  # collides with an id that already exists (PROD_CADENCE-022).
  #
  # A FAILED ENUMERATION IS FATAL, never an empty list: `--allocator-prefixes`
  # fails closed when §10 declares a table and the shared resolver is absent, and
  # absorbing that into "no prefixes declared" would seed nothing while reporting
  # a successful adoption.
  declared=""
  if [[ -f "$adopter_org" ]]; then
    declared="$( (cd "$DST" && bash "$MINT_ID" --allocator-prefixes "$adopter_org") 2>/dev/null )" || {
      echo "ERROR: could not enumerate the ticket prefixes §10 declares in '$adopter_org'." >&2
      echo "       Refusing to seed a partial set -- an unseeded prefix collides on its first --reserve." >&2
      exit 1
    }
  fi
  if [[ -n "$declared" ]]; then
    # PER-PREFIX §10. Each declared prefix is asked about ITSELF; a prefix whose
    # own row binds an external allocator is excluded here rather than refused at
    # the write site, because the write-site guard exits non-zero and the loop
    # below turns that into a failed adoption -- so a correct configuration must
    # never reach it.
    while IFS= read -r dprefix; do
      [[ -n "$dprefix" ]] || continue
      binding="$( (cd "$DST" && bash "$MINT_ID" --binding-for "$dprefix" "$adopter_org") 2>/dev/null || echo unbound)"
      [[ "$binding" == "unbound" ]] && seed_prefixes+=("$dprefix")
    done <<< "$declared"
  fi
  # THE UNION, NOT AN `elif` (BTG-180 DEC-013, superseding DEC-002 / AC-4 R1).
  # §10's *Per-prefix resolution* rule MINTS BY CONVENTION for a prefix with no
  # row, so the one the repo-wide `id_scheme:` names is governed and needs a row
  # too -- it got NONE while the two reads excluded each other, on an adoption
  # that exited 0 and emitted no seam. The pre-change guarding condition is
  # restored VERBATIM here, so the block below stays byte-identical.
  if [[ -f "$adopter_org" ]]; then
    # Resolve a CONCRETE ticket prefix from §10's id_scheme (`<PREFIX>-NNN`);
    # a placeholder (`<...>`) or absent scheme is not resolvable -> ticket self-seeds later.
    tprefix="$(awk -F'`' '/id_scheme:/ {for(i=2;i<=NF;i++) if($i ~ /-N+$/){print $i; exit}}' "$adopter_org" 2>/dev/null | sed -E 's/-N+$//' || true)"
    case "$tprefix" in ""|*"<"*|*"{{"*) tprefix="" ;; esac
    # PER PREFIX, not repo-wide (BTG-179 AC-8). The prefix is resolved FIRST
    # because the binding question is asked about IT: on a multi-binding org the
    # repo-wide `--binding` reads the literal `Per-prefix` on §10's bound line,
    # calls it bound, and skips every prefix -- including one whose own row
    # declares `None -- closed default`. Run from $DST so --binding-for locates
    # the shared resolver repo-relative under $PWD; an unresolvable answer falls
    # back to `unbound`, preserving §10's MINT polarity, and the
    # --guard-ticket-seed call below is the fail-closed check at the write site.
    if [[ -n "$tprefix" ]]; then
      binding="$( (cd "$DST" && bash "$MINT_ID" --binding-for "$tprefix" "$adopter_org") 2>/dev/null || echo unbound)"
      [[ "$binding" == "unbound" ]] && seed_prefixes+=("$tprefix")
    fi
  fi
  # DEDUPE HERE, at NEITHER contributor's append (DEC-013): both may name the
  # same prefix, and deduping at a `seed_prefixes+=` would edit a line the SCALAR
  # path executes. `--seed` is create-if-missing so a duplicate row is
  # impossible, but a second audit line claiming one is not.
  mapfile -t seed_prefixes < <(printf '%s\n' "${seed_prefixes[@]}" | awk '!seen[$0]++')
  for p in "${seed_prefixes[@]}"; do
    # Defense-in-depth: never seed a ticket prefix while §10 is bound (guard fires
    # idalloc.seed.ticket_prefix_seeded_while_bound if violated).
    if ! bash "$MINT_ID" --guard-ticket-seed "$p" "$adopter_org" >/dev/null 2>&1; then
      echo "ERROR: refusing to seed ticket prefix '$p' -- §10 binds an external allocator." >&2
      exit 1
    fi
    seed_out="$( (cd "$DST" && bash "$MINT_ID" --seed "$p" 0) 2>&1 )" && \
      note_copied "ticket-index.tsv (seeded $p to high-water 0)" || {
        if echo "$seed_out" | grep -qi 'already seeded'; then
          note_skipped "ticket-index.tsv ($p already seeded)"
        else
          echo "ERROR: could not seed the id-allocation ledger for prefix '$p'." >&2
          echo "$seed_out" >&2
          provision_seed_completeness "${seed_prefixes[@]}"
          exit 1
        fi
      }
  done
  provision_seed_completeness "${seed_prefixes[@]}"
  # Verify-loop precondition (M-4): the ledger must resolve before reporting success.
  if ! ( cd "$DST" && bash "$MINT_ID" --peek ADR ) >/dev/null 2>&1; then
    echo "ERROR: id-allocation ledger did not resolve after seeding (--peek ADR failed)." >&2
    exit 1
  fi
else
  echo "ERROR: allocator mint-id.sh not found at $MINT_ID; cannot seed the id ledger." >&2
  exit 1
fi
}
