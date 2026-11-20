#!/usr/bin/env bash
# Copies the portable CADENCE framework files into a target repository.
# Usage: skills/cadence-adopt/adopt-cadence.sh <target-repo-root> [--gitignore-machinery]
# Never overwrites a file that already exists in the destination.
set -euo pipefail

usage() {
  echo "Usage: $0 <target-repo-root> [--gitignore-machinery]" >&2
  exit 1
}

GITIGNORE_MACHINERY=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --gitignore-machinery) GITIGNORE_MACHINERY=1 ;;
    --*) echo "ERROR: unknown option: $arg" >&2; usage ;;
    *)   ARGS+=("$arg") ;;
  esac
done
[[ ${#ARGS[@]} -eq 1 ]] || usage

_resolve_src_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/processes/CADENCE_DIRECTIVES.md" || -f "$d/CADENCE_DIRECTIVES.md" ]]; then
      echo "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null \
    || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

SRC="$(_resolve_src_root)"
DST="${ARGS[0]}"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Co-located sidecar modules sourced in this shell's scope (globals resolve at call time).
# shellcheck source=/dev/null
. "$SELF_DIR/gitignore-block.sh"
# shellcheck source=/dev/null
. "$SELF_DIR/context-block.sh"
# shellcheck source=/dev/null
. "$SELF_DIR/adopt-provision.sh"
# shellcheck source=/dev/null
. "$SELF_DIR/adopt-release-tree.sh"

copied=0
skipped=0
note_copied()  { copied=$((copied + 1));  echo "  copied:        $1"; }
note_skipped() { skipped=$((skipped + 1)); echo "  skip (exists): $1"; }

if [[ ! -d "$DST" ]]; then
  echo "ERROR: target directory does not exist: $DST" >&2
  exit 1
fi
DST="$(cd "$DST" && pwd -P)"

if [[ "$DST" == "$(cd "$SRC" && pwd -P)" ]]; then
  echo "ERROR: target is the CADENCE repo itself" >&2
  exit 1
fi

# BTG-314 release handshake: run release-tree materialization when invoked directly.
[[ -z "${CADENCE_ADOPT_RELEASE_TREE:-}" ]] && adopt_from_release_tree   # never returns
[[ "${CADENCE_ADOPT_RELEASE_TREE:-}" != "checkout" && -n "${CADENCE_ADOPT_RELEASE_TREE:-}" && -e "$SRC/.git" ]] && {
  echo "seam_type=UNSOUND_CONDITION event_name=adopt.release_tree.handshake_outside_tree subject=$SRC" >&2
  exit 1
}

# Resolve target-relative path -> framework source path (supports sdlc processes/ + legacy flat layout).
_src_for() {
  local rel="$1" c
  case "$rel" in
    .agents/agents|.agents/agents/*) c="$SRC/agents${rel#.agents/agents}" ; [[ -e "$c" ]] && { echo "$c"; return 0; } ;;
    .agents/skills|.agents/skills/*) c="$SRC/skills${rel#.agents/skills}" ; [[ -e "$c" ]] && { echo "$c"; return 0; } ;;
    .agents/hooks|.agents/hooks/*)   c="$SRC/hooks${rel#.agents/hooks}"   ; [[ -e "$c" ]] && { echo "$c"; return 0; } ;;
  esac
  for c in "$SRC/$rel" "$SRC/processes/$rel"; do
    [[ -e "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# Portable framework files, copied verbatim; directories recursively.
COPY_PATHS=(
  CADENCE_DIRECTIVES.md
  specs/CADENCE.md
  specs/TEMPLATE
  docs/ADR/TEMPLATE.md
  docs/flows/TEMPLATE.md
  docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md
  docs/agentic-sdlc/PROJECT_INTENT_TEMPLATE.md
  docs/agentic-sdlc/chord-reference.md
  docs/agentic-sdlc/human-gates.md
  docs/agentic-sdlc/migration-workflow.md
  docs/agentic-sdlc/slash-commands.md
  docs/agentic-sdlc/team-rituals.md
  docs/policies/branch-strategy/long-lived-feature-release.md
  docs/policies/branch-strategy/trunk-based.md
  docs/policies/version-scheme/semver.md
  docs/policies/version-scheme/calver-yyyy-ww.md
  docs/policies/cli-runtime-adoption-policy.md
  docs/policies/conflict-resolution.md
  docs/policies/cadence-surfaces.md
  docs/policies/deprecation-policy.md
  docs/policies/doc-maintenance-policy.md
  docs/policies/chaos-profiles.md
  docs/policies/change-tiers.md
  docs/policies/emergency-fast-track.md
  docs/policies/migration-policy.md
  docs/policies/observability-patterns.md
  docs/policies/inner_source_sdlc_charter.md
  docs/policies/test-scope.md
  docs/policies/finding-classes.md
  docs/policies/completeness-invariants.md
  docs/policies/comment-discipline.md
  docs/guides/submitting-changes.md
  docs/guides/contributor_experience_guide.md
  docs/guides/ef-migration-examples.md
  docs/guides/process-metrics.md
  docs/guides/workflow
  .agents/agents
  .agents/skills
  .agents/hooks
  ci-templates/scripts/cadence-eject.sh
  ci-templates/scripts/eject-footprint.sh
  ci-templates/scripts/eject-footprint-headers.sh
  ci-templates/scripts/eject-transform.sh
  ci-templates/scripts/eject-exceptions.conf
  ci-templates/scripts/adapters
  ci-templates/scripts/dead-citation-gate.sh
  ci-templates/scripts/dead-citation-ledgers.sh
  ci-templates/scripts/dead-citation-exemptions.txt
  ci-templates/scripts/chaos-citation-gate.sh
  ci-templates/scripts/authored-doc-gate.sh
  ci-templates/scripts/authored-doc-predicates.sh
  ci-templates/scripts/authored-doc-orgtoken.sh
  ci-templates/scripts/authored-doc-ledgers.sh
  ci-templates/scripts/authored-doc-report.sh
  ci-templates/scripts/core-prefix-seed-gate.sh
  ci-templates/scripts/stage-effort.sh
  ci-templates/scripts/worklog-split.sh
  ci-templates/scripts/org-binding-resolve.sh
  ci-templates/scripts/org-binding-parse.sh
  ci-templates/scripts/org-binding-modes.sh
  ci-templates/scripts/org-binding-crossref.sh
)

copy_file() {
  local rel="$1" src_item="$2"
  if [[ -e "$DST/$rel" ]]; then
    note_skipped "$rel"
  else
    mkdir -p "$(dirname "$DST/$rel")"
    cp -L "$src_item" "$DST/$rel"
    note_copied "$rel"
  fi
}

echo "Copying CADENCE framework files from $SRC to $DST"

for path in "${COPY_PATHS[@]}"; do
  src_target="$(_src_for "$path" || true)"
  if [[ -z "$src_target" ]]; then
    echo "ERROR: missing in source: $path" >&2
    exit 1
  fi
  if [[ -d "$src_target" ]]; then
    while IFS= read -r -d '' f; do
      case "$f" in
        */__pycache__/*|*.pyc) continue ;;
      esac
      if [[ "$path" == ".agents/hooks" && "$f" == *.json ]]; then
        continue
      fi
      copy_file "$path/${f#"$src_target/"}" "$f"
    done < <(find -L "$src_target" -type f -print0 | sort -z)
  elif [[ -f "$src_target" ]]; then
    copy_file "$path" "$src_target"
  else
    echo "ERROR: unsupported source entry: $src_target" >&2
    exit 1
  fi
done

# intent-insights.md (adopter seed, created from template or stripped source entries).
rel="docs/agentic-sdlc/intent-insights.md"
if [[ -e "$DST/$rel" ]]; then
  note_skipped "$rel"
else
  src_ii="$(_src_for "docs/agentic-sdlc/intent-insights.template.md" || _src_for "$rel" || true)"
  [[ -n "$src_ii" ]] || { echo "ERROR: missing in source: intent-insights template/seed" >&2; exit 1; }
  mkdir -p "$(dirname "$DST/$rel")"
  awk '/^### II-/ { skip = 1 } skip && /^---$/ { skip = 0 } !skip' "$src_ii" > "$DST/$rel"
  note_copied "$rel (entries stripped)"
fi

# production-insights.md (adopter seed, created from template if absent).
rel="docs/agentic-sdlc/production-insights.md"
if [[ -e "$DST/$rel" ]]; then
  note_skipped "$rel"
else
  src_pi="$(_src_for "docs/agentic-sdlc/production-insights.template.md" || _src_for "$rel" || true)"
  if [[ -n "$src_pi" ]]; then
    mkdir -p "$(dirname "$DST/$rel")"
    cp -L "$src_pi" "$DST/$rel"
    note_copied "$rel (seeded from template)"
  fi
fi

# authored-doc-exemptions.txt: copy with framework repo's accrued rows stripped.
rel="ci-templates/scripts/authored-doc-exemptions.txt"
if [[ -e "$DST/$rel" ]]; then
  note_skipped "$rel"
else
  src_ade="$(_src_for "$rel" || true)"
  if [[ -n "$src_ade" && -f "$src_ade" ]]; then
    mkdir -p "$(dirname "$DST/$rel")"
    grep -E '^[[:space:]]*(#|$)' "$src_ade" > "$DST/$rel"
    note_copied "$rel (rows stripped)"
  fi
fi

provision_repo_skeleton
provision_generated_artifacts

if ! write_context_wiring "$SRC" "$DST"; then
  echo "Adoption aborted — could not wire the CADENCE directives into $DST/$CONTEXT_FILE." >&2
  exit 1
fi

provision_registrations

if [[ "$GITIGNORE_MACHINERY" -eq 1 ]]; then
  if write_gitignore_block "$SRC" "$DST"; then
    note_copied ".gitignore (machinery block ${GITIGNORE_ACTION})"
  else
    echo "Adoption aborted — could not write the requested .gitignore machinery block." >&2
    exit 1
  fi
fi

provision_id_ledger

if ! verify_context_wiring "$DST"; then
  exit 1
fi

missing=()
for path in "${COPY_PATHS[@]}" \
            "docs/agentic-sdlc/intent-insights.md" \
            "docs/agentic-sdlc/production-insights.md" \
            "CHANGELOG.md" "archive" "specs/drafts/.gitignore" \
            "artifacts/footprint.generated" "AGENTS.md" \
            ".agents/hooks.json" ".gemini/GEMINI.md" ".gemini/agents" ".gemini/skills" \
            ".cadence-version"; do
  [[ -e "$DST/$path" ]] || missing+=("$path")
done
if (( ${#missing[@]} )); then
  echo >&2
  echo "ERROR: adoption incomplete — expected paths missing in $DST:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if [[ "$GITIGNORE_MACHINERY" -eq 1 ]] \
   && ! grep -qF "$GITIGNORE_BEGIN" "$DST/.gitignore" 2>/dev/null; then
  echo >&2
  echo "ERROR: --gitignore-machinery set but the managed block is absent from $DST/.gitignore." >&2
  echo "Adoption aborted — refusing to report success without the requested .gitignore machinery block." >&2
  exit 1
fi

print_context_notice

echo
echo "Done: $copied copied, $skipped skipped (already present)."
echo "Next: author PROJECT_INTENT.md and docs/agentic-sdlc/CADENCE_ORG.md from their _TEMPLATE files,"
echo "and record your project's own architecture and conventions in AGENTS.md (CADENCE directives"
echo "live in CADENCE_DIRECTIVES.md and are imported from AGENTS.md and .gemini/GEMINI.md)."
