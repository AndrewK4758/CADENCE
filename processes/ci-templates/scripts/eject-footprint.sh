#!/usr/bin/env bash
#
# eject-footprint.sh -- the footprint-descriptor + strip-set concern of
# cadence-eject (PI-017; modularized to keep each file under the 300-line DX
# target, mirroring the compile-*.sh module split).
#
# Sourced by cadence-eject.sh in this shell's scope, so SELF_DIR, REPO_ROOT and
# FOOTPRINT resolve as before the split. Provides:
#   emit_seam           shared seam emitter (stderr line + caller's non-zero exit)
#   resolve_tree_root   binding-resolved native tree root (clause-7 fenced region)
#   derive_footprint    canonical-identity descriptor derivation (fw-dev | adopter)
#   load_exceptions     reviewed non-CADENCE exceptions (deny-by-default boundary)
#   load_descriptor     parse the descriptor into STRIP_PATHS / STRIP_SOURCE
#   strip_reason_for    is a repo-relative path in the strip set? + responsible entry
#
# References: specs/PI-017/{spec,decisions}.md (DEC-011) ; docs/ADR/0008-*.md cl.5.

# ---------------------------------------------------------------------------
# Observability seam emitter -- for this no-runtime tool, a seam "fires" as a
# stderr line + non-zero exit (mirrors compile-util.sh emit_seam).
# ---------------------------------------------------------------------------
emit_seam() {
  local seam_type="$1" event_name="$2" subject="${3:-}"
  echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
}

# BTG-008: the two descriptor header prologues live in a sourced sibling so this
# file stays under the 300-line DX target after the hooks tree_root + mode-gate
# additions. SELF_DIR is set by the entry point (cadence-eject.sh) before this
# module is sourced; when this module is sourced directly by a test, fall back.
_EFH_DIR="${SELF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=/dev/null
. "$_EFH_DIR/eject-footprint-headers.sh"

# ---------------------------------------------------------------------------
# Binding resolution (ADR_CADENCE-0008 cl.5 / RC-6): resolve a descriptor tree_root
# binding_hook (e.g. artifact_root:roles) into the native tree root WITHOUT
# this script naming the native root literally. We hand the equivalent body
# placeholder to the bound adapter's expansion (the single runtime-coupling
# home) and read back the resolved root.
# ---------------------------------------------------------------------------
# >>> binding-resolution (clause-7 exempt) >>>
# The ONLY region of this script that may name the bound runtime's adapter --
# this is the binding-resolution path (ADR_CADENCE-0008 cl.5 / DEC-006). The clause-7
# sweep over this source excludes exactly this fenced region; the strip logic
# below the fence holds no runtime-primitive literal.
resolve_tree_root() {
  local hook="$1"   # e.g. "artifact_root:roles"
  local adapter="$SELF_DIR/adapters/claude-code.sh"
  if [[ ! -f "$adapter" ]]; then
    emit_seam UNSOUND_CONDITION eject.binding.adapter_missing "$adapter"
    echo "cadence-eject: cannot resolve tree roots -- runtime adapter not found: $adapter" >&2
    return 1
  fi
  # Source the adapter for its binding-resolution function, then expand the
  # placeholder form of the hook. No native-root literal appears in THIS file.
  # shellcheck source=/dev/null
  . "$adapter"
  printf '{{%s}}' "$hook" | cc_expand_body
}
# <<< binding-resolution (clause-7 exempt) <<<

# ---------------------------------------------------------------------------
# Descriptor derivation (canonical identity) -- compose the three category
# sources so the boundary cannot drift open as a hand-maintained list would.
# ---------------------------------------------------------------------------
# derive_footprint [mode]
#   mode = framework-dev (default) -> categories 1+2+3 (deny-by-default sweep);
#          adopter                 -> categories 1+2 only (precise installed
#                                     surface; NO deny-by-default sweep, so an
#                                     adopter's arbitrary project code is NEVER
#                                     stripped -- the framework_dev category is
#                                     "present only when ejecting a framework-dev
#                                     repo", spec category 3).
# BTG-015/018: the four adopter-owned seed docs are emitted as kind=seed (a strip
# path at eject; EXCLUDED from the upgrade merge). Data-driven seed identity in
# ONE labeled place -- the derive producer of the kind=seed grammar (DEC-005).
_EF_SEEDS="docs/agentic-sdlc/intent-insights.md docs/agentic-sdlc/production-insights.md docs/policies/surface-registry.md docs/SYSTEM_OVERVIEW.md"
_ef_is_seed() { case " $_EF_SEEDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

derive_footprint() {
  local mode="${1:-framework-dev}"
  local adopt="$REPO_ROOT/artifacts/commands/cadence-adopt/adopt-cadence.sh"
  if [[ ! -f "$adopt" ]]; then
    derive_adopter_from_committed   # adopter repo: no COPY_PATHS source (BTG-007 / DEC-004)
    return $?
  fi

  # Header (stable; the committed descriptor carries the same prologue).
  if [[ "$mode" == "adopter" ]]; then
    eject_footprint_header_adopter
  else
    eject_footprint_header_framework_dev
  fi

  # (1) tree_root rows -- the RC-6 native trees, named by binding hook only.
  # BTG-008: hooks is a third compiled tree_root (peer of roles/commands),
  # resolving to .claude/cadence-hooks via artifact_root:hooks (no literal).
  echo "kind=tree_root identity=roles binding_hook=artifact_root:roles"
  echo "kind=tree_root identity=commands binding_hook=artifact_root:commands"
  echo "kind=tree_root identity=hooks binding_hook=artifact_root:hooks"

  # (2) installed rows -- adopt-cadence COPY_PATHS, minus the two tree dirs
  # (those are tree_root rows), in COPY_PATHS order. The adopt-cadence tree
  # dirs are named via the same binding hooks, so we filter by resolved root.
  local roles_root commands_root hooks_root
  roles_root="$(resolve_tree_root artifact_root:roles)" || return 1
  commands_root="$(resolve_tree_root artifact_root:commands)" || return 1
  hooks_root="$(resolve_tree_root artifact_root:hooks)" || return 1
  # Extract the COPY_PATHS array entries from the sidecar (one per line). Skip
  # comment/blank lines + the compiled tree dirs (tree_root rows). The
  # ci-templates/*+artifacts/* skip is FRAMEWORK-DEV ONLY -- category 3 covers them
  # there; adopter mode skips category 3, so they MUST flow through here (else the
  # --gitignore-machinery block and an adopter eject both miss them). PI-042.
  # BTG-008: hooks is a third compiled tree dir (resolved hooks_root). BTG-015: an
  # adopter-owned seed doc is emitted as kind=seed here (a strip path at eject;
  # merge-excluded) rather than kind=installed.
  local path
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    [[ "$path" == "$roles_root" || "$path" == "$commands_root" || "$path" == "$hooks_root" || "$path" == "{{artifact_root:"* ]] && continue  # tree dirs (resolved roots or neutral placeholder, BTG-008/PI-024/DEC-010) are tree_root rows
    [[ "$mode" != "adopter" && ( "$path" == ci-templates/* || "$path" == artifacts/* ) ]] && continue
    _ef_is_seed "$path" && { echo "kind=seed path=$path"; continue; }   # BTG-015
    echo "kind=installed path=$path"
  done < <(awk '/^COPY_PATHS=\(/{f=1;next} f&&/^\)/{f=0} f{gsub(/^[ \t]+/,"");print}' "$adopt")
  # intent-insights.md is copied specially by adopt-cadence (entries stripped),
  # so it is not in COPY_PATHS but IS installed framework material. BTG-015: it is
  # an adopter-owned seed -> emitted as kind=seed (stripped; merge-excluded).
  echo "kind=seed path=docs/agentic-sdlc/intent-insights.md"
  # BTG-198: CLAUDE.md is GENERATED by adopt-cadence's context wiring (a stub, or
  # a managed block appended to the adopter's own file), so it left COPY_PATHS and
  # the loop above can no longer see it. Emitted explicitly here in BOTH modes,
  # exactly as intent-insights.md is directly above and for the same
  # generate-don't-copy reason. kind=seed, not kind=installed: it is categorically
  # ADOPTER-OWNED -- still stripped at eject (seed is a strip class) but EXCLUDED
  # from the upgrade merge set. Dropping this row would lose CLAUDE.md from an
  # adopter's descriptor entirely and eject would stop stripping it, which is a
  # Source Confidentiality leak (DELTA_AUDIT_GAP eject.footprint.context_row_missing).
  echo "kind=seed path=CLAUDE.md"
  # Two GENERATED installed rows (not in COPY_PATHS), emitted in BOTH modes via
  # the EXISTING `installed` kind (no new branch/grammar): .cadence-version = the
  # core stamp (PI-021 / F1 / ADR_CADENCE-0009); overlay = the adopter's layered-source
  # root, ruled STRIP as CADENCE IP at eject (PI-022 / DEC-004 / DEC-012).
  echo "kind=installed path=.cadence-version"
  echo "kind=installed path=overlay"
  # A THIRD generated installed row, ADOPTER MODE ONLY (PI-042): the eject descriptor
  # itself -- not a COPY_PATHS entry; framework-dev covers artifacts/ via category 3.
  [[ "$mode" == "adopter" ]] && echo "kind=installed path=artifacts/footprint.generated"

  # (3) framework_dev -- DENY-BY-DEFAULT (DEC-011), FRAMEWORK-DEV MODE ONLY. A
  # framework-dev repo is CADENCE by default: emit a framework_dev row for every
  # GIT-TRACKED top-level entry, EXCEPT (a) .git, (b) the reviewed non-CADENCE
  # exceptions (eject-exceptions.conf). Complete by construction -- a NEW *tracked*
  # top-level CADENCE file/dir is covered automatically, closing the fail-open
  # hole a hand-maintained list left (the code-reviewer's verified leak); the
  # completeness gate is the independent backstop. SKIPPED in adopter mode so an
  # adopter's arbitrary project code is never deny-by-default stripped.
  #
  # PI-019 / DEC-001: the sweep is scoped to GIT-TRACKED top-level entries (was
  # the raw working tree), so an untracked scratch file/dir cannot create a
  # spurious footprint.derive.drift. The eject-time strip walk (cadence-eject.sh)
  # deliberately stays content-driven (DEC-002) -- the two paths answer different
  # questions, so an unknown-provenance untracked file is still stripped at eject.
  [[ "$mode" == "adopter" ]] && return 0

  # Precondition (DEC-003): a git work tree is required to enumerate the tracked
  # set. Fail LOUD -- never fall back to the raw working tree (would re-introduce
  # the bug / risk a fail-open). All real callers run inside a git checkout.
  if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit_seam UNSOUND_CONDITION footprint.derive.no_git_worktree "$REPO_ROOT"
    echo "eject-footprint: cannot scope the footprint sweep -- $REPO_ROOT is not a git work tree." >&2
    echo "eject-footprint: refusing -- there is NO raw-working-tree fallback (would re-introduce untracked-drift / risk a leak)." >&2
    return 1
  fi

  local exceptions; exceptions="$(load_exceptions)"
  local base
  while IFS= read -r base; do          # base is a top-level tracked name
    [[ "$base" == ".git" ]] && continue
    # Skip reviewed non-CADENCE exceptions (exact top-level match).
    if printf '%s\n' "$exceptions" | grep -qxF "$base"; then
      continue
    fi
    echo "kind=framework_dev path=$base"
  done < <(git -C "$REPO_ROOT" ls-files -z \
             | tr '\0' '\n' \
             | sed 's#/.*##' \
             | LC_ALL=C sort -u)
}

# Read the reviewed non-CADENCE exceptions (deny-by-default boundary, DEC-011),
# one top-level path per line; comments/blanks stripped. A missing file means
# NO exceptions (strip everything) -- the conservative, leak-safe default.
EXCEPTIONS_FILE="${EJECT_EXCEPTIONS:-$SELF_DIR/eject-exceptions.conf}"
load_exceptions() {
  [[ -f "$EXCEPTIONS_FILE" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$EXCEPTIONS_FILE"
}

# ---------------------------------------------------------------------------
# Load the descriptor into two parallel arrays: STRIP_PATHS (literal repo-rel
# paths) and the resolved tree roots. Fails loudly on a missing/unparseable
# descriptor (never a fail-open fallback).
# ---------------------------------------------------------------------------
STRIP_PATHS=()
STRIP_SOURCE=()   # the descriptor entry responsible for each strip path

load_descriptor() {
  if [[ ! -f "$FOOTPRINT" ]]; then
    emit_seam UNSOUND_CONDITION eject.precondition.no_descriptor "$FOOTPRINT"
    echo "cadence-eject: footprint descriptor not found: $FOOTPRINT" >&2
    echo "cadence-eject: refusing to eject -- there is NO hardcoded strip-list fallback (fail-open is forbidden)." >&2
    return 1
  fi
  STRIP_PATHS=()
  STRIP_SOURCE=()
  # BTG-008 (DEC-005): the tree_root parent-dir strip (which wholesale-strips the
  # .claude parent, taking .claude/settings.json + the adopter's .agents/hooks/)
  # is gated to FRAMEWORK-DEV mode only. In adopter mode ONLY the specific
  # CADENCE tree roots (.agents/agents, .agents/skills, .claude/cadence-hooks)
  # strip, so an adopter's co-owned .claude/settings.json and their own
  # .agents/hooks/ survive (settings.json is transformed-on-ship instead). A
  # descriptor is framework-dev iff it carries any kind=framework_dev row.
  local fwdev_mode=0
  grep -qE '^kind=framework_dev ' "$FOOTPRINT" && fwdev_mode=1
  local line kind rest
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines.
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      "kind=tree_root "*)
        local hook root
        hook="$(printf '%s\n' "$line" | sed -nE 's/.*binding_hook=([^ ]+).*/\1/p')"
        if [[ -z "$hook" ]]; then
          emit_seam BOUNDARY_FAULT eject.descriptor.malformed_entry "$line"
          echo "cadence-eject: malformed tree_root entry (no binding_hook): $line" >&2
          return 1
        fi
        root="$(resolve_tree_root "$hook")" || return 1
        # Fail LOUD on an unresolved hook: an empty root OR a root that still
        # carries a {{...}} placeholder residue (the binding did not recognize
        # the hook) would otherwise yield a junk strip path that strips NOTHING
        # -- a silent leak. Never accept it (review fix; leak-critical).
        if [[ -z "$root" || "$root" == *'{{'* || "$root" == *'}}'* ]]; then
          emit_seam BOUNDARY_FAULT eject.descriptor.unresolved_hook "$hook"
          echo "cadence-eject: binding hook did not resolve to a tree root (got: '${root:-<empty>}'): $hook" >&2
          echo "cadence-eject: refusing -- an unresolved root would strip nothing (silent leak)." >&2
          return 1
        fi
        STRIP_PATHS+=("$root")
        STRIP_SOURCE+=("tree_root:$hook")
        # The whole generated tree ROOT is residue (Stance §5): strip its parent
        # directory so files directly under the root (not just the per-artifact
        # subdirs) are removed too. The parent is COMPUTED from the binding-
        # resolved root via dirname -- no native-root literal here. BTG-008
        # (DEC-005): FRAMEWORK-DEV mode only -- in adopter mode the co-owned
        # .claude/settings.json and adopter .agents/hooks/ must survive.
        local tree_root_dir; tree_root_dir="$(dirname "$root")"
        if [[ $fwdev_mode -eq 1 && -n "$tree_root_dir" && "$tree_root_dir" != "." && "$tree_root_dir" != "/" ]]; then
          local already="" sp
          for sp in "${STRIP_PATHS[@]}"; do
            [[ "$sp" == "$tree_root_dir" ]] && already=1 && break
          done
          if [[ -z "$already" ]]; then
            STRIP_PATHS+=("$tree_root_dir")
            STRIP_SOURCE+=("tree_root:$hook(root)")
          fi
        fi
        ;;
      "kind=installed "*|"kind=framework_dev "*|"kind=seed "*)
        # BTG-015 (DEC-002 F1 lockstep): kind=seed joins the strip class -- a seed
        # is still stripped from a client deliverable exactly as kind=installed
        # was, so this additive category does NOT trip the deny-by-default arm.
        local p
        p="$(printf '%s\n' "$line" | sed -nE 's/.*[[:space:]]path=([^ ]+).*/\1/p')"
        if [[ -z "$p" ]]; then
          emit_seam BOUNDARY_FAULT eject.descriptor.malformed_entry "$line"
          echo "cadence-eject: malformed descriptor entry (no path): $line" >&2
          return 1
        fi
        kind="${line%% *}"; kind="${kind#kind=}"
        STRIP_PATHS+=("$p")
        STRIP_SOURCE+=("$kind:$p")
        ;;
      *)
        emit_seam BOUNDARY_FAULT eject.descriptor.malformed_entry "$line"
        echo "cadence-eject: unparseable descriptor entry: $line" >&2
        echo "cadence-eject: refusing to skip-and-continue (a skipped entry is a silent leak)." >&2
        return 1
        ;;
    esac
  done < "$FOOTPRINT"
  # BTG-016a (DEC-001/DEC-006): tolerate a STALE committed footprint by backfilling
  # the hooks tree_root IN MEMORY (extracted to the sibling to keep this file
  # under the 300-line DX ceiling -- ADR_CADENCE-0009 clean; never mutates the descriptor).
  eject_footprint_backfill_hooks_root "$fwdev_mode" || return 1
  return 0
}

# Is repo-relative <rel> inside (or equal to) any strip path? Echoes the
# responsible descriptor source on a hit; returns 0 on hit, 1 on miss.
strip_reason_for() {
  local rel="$1" i sp
  for i in "${!STRIP_PATHS[@]}"; do
    sp="${STRIP_PATHS[$i]}"
    if [[ "$rel" == "$sp" || "$rel" == "$sp/"* ]]; then
      echo "${STRIP_SOURCE[$i]}"
      return 0
    fi
  done
  return 1
}
