#!/usr/bin/env bash
#
# upgrade-baseline.sh -- the /claire-upgrade post-apply dead-citation baseline
# concern (BTG-100, DEC-004), a colocated sidecar module carved out of
# upgrade-claire.sh for the same reason upgrade-hooks.sh / upgrade-mcp.sh /
# upgrade-removals.sh / upgrade-modes.sh were: the entry point is already over the
# 400-line DX ceiling (CLAIRE_ORG.md §2, Facet 3), so this concern costs it TWO
# lines (a source and a call) instead of ~20.
#
# Bounded context: Upgrade seam / layered-source flow.
# Invariant relied on from outside this boundary: an adopter who has just received
# ci-templates/scripts/dead-citation-gate.sh (via the BTG-100 RECONCILE backfill,
# or already) can invoke it with `--root <tree> --emit-baseline` to compute that
# tree's own debt ledger. Downstream: /claire-archive step 2b and the run-gates.sh
# dead-citation row both FAIL CLOSED without that ledger, so a backfill that
# delivers the classifier without generating a baseline leaves the classifier
# exiting 2 (setup failure) and the delivery useless.
#
# Sourced by upgrade-claire.sh after upgrade-bootstrap.sh, so it runs in the
# entry point's shell scope: the globals it reads (TARGET) and the emit_seam
# helper resolve at CALL time from that scope (dynamic scoping), exactly as every
# peer sidecar does. Shipped into the compiled skill by the PI-023 directory-copy
# contract, so it needs no manifest row of its own.
#
# Spec: archive/BTG-100/spec.md (AC-3); decisions.md DEC-004.

# Create-once generation of the adopter's OWN dead-citation debt ledger,
# behaviourally mirroring adopt-claire.sh:273-307. No args. Reads TARGET from
# the shared scope. ALWAYS returns 0 -- non-fatal by design.
#
# GENERATE, NEVER COPY (R10, verified not assumed): core's baseline is DEBT naming
# CORE's files, so installing it "would both be meaningless in the adopter repo and
# SILENCE that repo's real findings" (adopt-claire.sh:273-289). That is why
# dead-citation-baseline.txt is deliberately absent from both COPY_PATHS and the
# BTG-100 RECONCILE rows, and is computed per tree here instead.
#
# NON-FATAL is the verified polarity (R12): a missing baseline makes the classifier
# fail CLOSED (it refuses to report a verdict it did not compute), unlike the eject
# descriptor which fails OPEN. Failing an entire upgrade over a ledger the adopter
# regenerates in one line would be disproportionate; failing closed downstream is
# safe and loud.
ensure_dead_citation_baseline() {
  local rel="ci-templates/scripts/dead-citation-baseline.txt"
  local gate="$TARGET/ci-templates/scripts/dead-citation-gate.sh"
  local ledgers="$TARGET/ci-templates/scripts/dead-citation-ledgers.sh"
  local dest="$TARGET/$rel" tmp

  # Create-once: an existing baseline is the ADOPTER's own ledger (JI-7) and is
  # never clobbered. Idempotent -- a no-op on every subsequent upgrade.
  [[ -e "$dest" ]] && return 0
  # Classifier-presence guard, mirroring adopt-claire.sh's own guard: an adopter
  # who never receives the classifier (or its ledgers module) is SILENTLY skipped.
  # This is a normal state, not an anomaly, so no seam fires -- a seam here would
  # false-positive on every legitimately pre-BTG-083 tree.
  [[ -s "$gate" && -s "$ledgers" ]] || return 0

  mkdir -p "$(dirname "$dest")" 2>/dev/null
  tmp="$(mktemp)"
  # Generate-to-temp-then-move: a bare `> "$dest"` would leave a partial or
  # zero-byte ledger behind on a mid-generation failure, and a zero-byte baseline
  # is worse than none (it reads as "no debt" rather than "not computed").
  if bash "$gate" --root "$TARGET" --emit-baseline > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv "$tmp" "$dest"
    echo "upgrade-claire: generated $rel (this tree's own dead-citation debt ledger)."
    return 0
  fi
  rm -f "$tmp"
  emit_seam LINEAGE_GAP upgrade.baseline.generation_failed "$rel"
  echo "upgrade-claire: WARNING -- could not generate $rel (non-fatal; the upgrade still applied)." >&2
  echo "upgrade-claire: /claire-archive's citation-disposition step and the dead-citation gate row will" >&2
  echo "upgrade-claire: FAIL CLOSED until it exists. Generate it with:" >&2
  echo "upgrade-claire:   bash ci-templates/scripts/dead-citation-gate.sh --emit-baseline \\" >&2
  echo "upgrade-claire:     > ci-templates/scripts/dead-citation-baseline.txt" >&2
  return 0
}
