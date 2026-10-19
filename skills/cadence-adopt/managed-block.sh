#!/usr/bin/env bash
#
# managed-block.sh -- the GENERIC marker-fenced managed-block writer (BTG-198
# DEC-014). Extracted behaviour-preserving from gitignore-block.sh (PI-034,
# lines 102-177 of that module before this change), which now delegates to it,
# as does context-block.sh. One implementation of a REGISTERED marker contract
# (docs/policies/cadence-surfaces.md), not two that drift invisibly while each
# copy's own tests stay green.
#
# Bounded context: adopt-cadence install flow (co-located layout). Knows
# NOTHING about .gitignore, CLAUDE.md, footprint descriptors or markers -- the
# caller supplies the file, both markers and a pre-built block file.
#
# Invariant relied on from outside this boundary: the caller has already built
# the complete block (markers included) in <block_file>, and owns that temp
# file's lifecycle. This module never deletes the caller's block file.
#
# Upstream: sourced by gitignore-block.sh and context-block.sh from beside
#   themselves. Downstream: read-modify-writes the caller's target file.
# Spec: archive/BTG-198/spec.md (Proposed Design, Install layer); decisions.md
#       DEC-014 (extract, do not duplicate); archive/PI-034/spec.md DEC-012/DEC-014
#       for the semantics this preserves byte-for-byte.
#
# LF-line-ending caveat, INHERITED from PI-034 and DELIBERATELY NOT HARDENED
# here (BTG-198 OQ-2, resolved at the spec-approval gate 2026-09-02 -- accept
# the caveat, do not harden). Marker detection and replacement below match the
# markers as exact WHOLE lines (grep -qFx / awk $0==), so a managed block whose
# lines were CRLF-converted by an editor is NOT recognized and a re-run appends
# a SECOND block instead of replacing it. Our own writes are always LF
# (printf '\n'), so this only affects an externally CRLF-mangled file. This
# module is SHARED, so a CRLF-tolerant match would silently change the
# registered .gitignore marker contract too -- which deserves its own tier
# assessment, not a rider on BTG-198. Risk R-4 is an accepted residual,
# DETECTED (not prevented) by the adopt.context.block_action decision seam: a
# "written" action on a repo that has adopted before is the tell.

# Guard so a double-source (both sibling modules source this) is harmless.
MANAGED_BLOCK_SOURCED=1

# Set by write_managed_block to "written" | "replaced" so the caller can
# announce which path it took.
MANAGED_BLOCK_ACTION=""

# The caller's deliverable phrase, interpolated into the write-failure refusal
# so each caller's message reads as it did before the extraction (II-014: the
# refusal must name the deliverable that could not be produced). Callers set it
# immediately before calling; the default keeps a caller that forgets honest
# rather than silent.
MANAGED_BLOCK_DELIVERABLE="managed block"

# Set by write_managed_block on a failure to the REASON it refused:
#   unterminated -- an open marker with no matching close marker
#   write_failed -- the block could not be built or committed
# Empty on success. This module is marker-agnostic and must stay so, which is
# exactly why it does not emit a seam itself: the seam EVENT NAME belongs to the
# caller's bounded context (adopt.context.* vs adopt.gitignore.*). Exposing the
# reason instead lets each caller name its own seam without this module growing
# knowledge of either.
MANAGED_BLOCK_ERROR=""

# write_managed_block <file> <begin_marker> <end_marker> <block_file>
#   <file>         the target file to read-modify-write (created if absent).
#   <begin_marker> <end_marker>  exact whole-line markers fencing the block.
#   <block_file>   a file holding the COMPLETE fresh block (markers included).
# Replaces the FIRST open->first close region in place when a terminated block
# is present; otherwise appends a fresh block after ensuring a trailing newline.
# Returns 0 with MANAGED_BLOCK_ACTION set, or non-zero with a loud stderr
# refusal (II-014: never report success past a requested deliverable), leaving
# the target file with no partial block on any failure path.
write_managed_block() {
  local file="$1" begin="$2" end="$3" blockfile="$4"
  local label; label="$(basename "$file")"
  MANAGED_BLOCK_ACTION=""
  MANAGED_BLOCK_ERROR=""

  local out; out="$(mktemp)" || return 1
  if [[ -f "$file" ]] && grep -qFx "$begin" "$file"; then
    # Guard (PI-034 review S-1): an open marker with NO matching close marker
    # would make the replace awk below stay in-block to EOF and still report
    # success -- silently deleting every line after the dangling open marker.
    # PI-034 DEC-014 OQ-1 declined self-heal of a *double* block (two matched
    # pairs); this is the distinct *unterminated* case, which is data-loss, not
    # merely no-heal. Refuse loudly and leave the file byte-untouched.
    if ! awk -v b="$begin" -v e="$end" '
      $0==b { seen=1 }
      seen && $0==e { closed=1; exit }
      END { exit (closed ? 0 : 1) }
    ' "$file"; then
      rm -f "$out"
      MANAGED_BLOCK_ERROR="unterminated"
      echo >&2
      echo "ERROR: $file has an unterminated CADENCE managed block (open marker with no matching close marker)." >&2
      echo "Adoption aborted -- rewriting it would delete every line after the open marker; refusing (II-014). Repair $label by hand and re-run." >&2
      return 1
    fi
    # Replace: emit everything except the first marker..marker region, splicing
    # the freshly-built block in at the open marker's position.
    if ! awk -v b="$begin" -v e="$end" -v blk="$blockfile" '
      BEGIN { done_repl=0; inb=0 }
      !done_repl && !inb && $0==b {
        inb=1
        while ((getline ln < blk) > 0) print ln
        close(blk)
        next
      }
      inb && $0==e { inb=0; done_repl=1; next }
      inb { next }
      { print }
    ' "$file" > "$out"; then
      rm -f "$out"
      MANAGED_BLOCK_ERROR="write_failed"
      echo >&2
      echo "ERROR: could not rewrite the managed block in $file." >&2
      echo "Adoption aborted -- refusing to report success without the requested $MANAGED_BLOCK_DELIVERABLE (II-014)." >&2
      return 1
    fi
    MANAGED_BLOCK_ACTION="replaced"
  else
    # Fresh write: preserve any existing (non-managed) content, then append the
    # block. A trailing newline is ensured before the appended block.
    if [[ -f "$file" && -s "$file" ]]; then
      if ! { cat "$file"; [[ -z "$(tail -c1 "$file")" ]] || printf '\n'; cat "$blockfile"; } > "$out"; then
        rm -f "$out"
        MANAGED_BLOCK_ERROR="write_failed"
        echo >&2
        echo "ERROR: could not write the managed block to $file." >&2
        echo "Adoption aborted -- refusing to report success without the requested $MANAGED_BLOCK_DELIVERABLE (II-014)." >&2
        return 1
      fi
    else
      cp "$blockfile" "$out" 2>/dev/null || { rm -f "$out"; MANAGED_BLOCK_ERROR="write_failed"; \
        echo >&2; \
        echo "ERROR: could not write the managed block to $file." >&2; \
        echo "Adoption aborted -- refusing to report success without the requested $MANAGED_BLOCK_DELIVERABLE (II-014)." >&2; \
        return 1; }
    fi
    MANAGED_BLOCK_ACTION="written"
  fi

  # Commit the rewritten content atomically. mv preserves nothing partial: on
  # failure no half-written block is left under the markers.
  if ! mv "$out" "$file"; then
    rm -f "$out"
    MANAGED_BLOCK_ERROR="write_failed"
    echo >&2
    echo "ERROR: could not write $file (unwritable target)." >&2
    echo "Adoption aborted -- refusing to report success without the requested $MANAGED_BLOCK_DELIVERABLE (II-014)." >&2
    return 1
  fi
  return 0
}
