#!/usr/bin/env bash
# adopt-provision.sh -- adopter-owned skeleton, generated descriptors, hooks/gemini registrations, and id-ledger seed.
# Sourced by adopt-cadence.sh (reads SRC, DST, copied, skipped, note_copied, note_skipped at call time).

resolve_core_version() {
  local src="$1" readme_ver stamp_ver tag_ver c
  readme_ver="$(sed -nE 's/^\*\*Version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)\*\*.*/\1/p' "$src/README.md" 2>/dev/null | head -n1)"
  for c in "$src/processes/.cadence-version" "$src/.cadence-version"; do
    [[ -f "$c" ]] || continue
    stamp_ver="$(sed -nE 's/^version=([0-9]+\.[0-9]+\.[0-9]+.*)$/\1/p' "$c" 2>/dev/null | head -n1)"
    [[ -n "$stamp_ver" ]] && break
  done
  tag_ver="$(git -C "$src" tag 2>/dev/null | sed -nE 's/^(cadence-)?v?([0-9]+\.[0-9]+\.[0-9]+)$/\2/p' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)"
  if [[ -n "$readme_ver" ]]; then
    printf '%s' "$readme_ver"
  elif [[ -n "${stamp_ver:-}" ]]; then
    printf '%s' "$stamp_ver"
  elif [[ -n "$tag_ver" ]]; then
    printf '%s' "$tag_ver"
  fi
}

provision_repo_skeleton() {
  if [[ -e "$DST/CHANGELOG.md" ]]; then
    note_skipped "CHANGELOG.md"
  else
    cat > "$DST/CHANGELOG.md" <<'EOF'
# Changelog

All notable changes to this repository will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]
EOF
    note_copied "CHANGELOG.md (fresh skeleton)"
  fi

  if [[ -d "$DST/archive" ]]; then
    note_skipped "archive/"
  else
    mkdir -p "$DST/archive"
    touch "$DST/archive/.gitkeep"
    note_copied "archive/ (empty)"
  fi

  if [[ -e "$DST/specs/drafts/.gitignore" ]]; then
    note_skipped "specs/drafts/.gitignore"
  else
    mkdir -p "$DST/specs/drafts"
    printf '*\n!.gitignore\n' > "$DST/specs/drafts/.gitignore"
    note_copied "specs/drafts/.gitignore (gitignored drafting area)"
  fi

  if [[ -e "$DST/docs/policies/surface-registry.md" ]]; then
    note_skipped "docs/policies/surface-registry.md"
  else
    mkdir -p "$DST/docs/policies"
    cat > "$DST/docs/policies/surface-registry.md" <<'EOF'
# Project Surface Registry

Adopter-owned compatibility contracts for project APIs, schemas, CLI commands, and CADENCE configuration anchors. Framework surfaces live in `docs/policies/cadence-surfaces.md`.

| Surface | Type | Location | Contract / Notes |
|---|---|---|---|
| Organization governance | Configuration contract | `docs/agentic-sdlc/CADENCE_ORG.md` | Model tier, tracker, and branch-strategy bindings |
EOF
    note_copied "docs/policies/surface-registry.md (starter seed)"
  fi
}

provision_generated_artifacts() {
  local rel="artifacts/footprint.generated" eject_script
  if [[ -e "$DST/$rel" ]]; then
    note_skipped "$rel"
  else
    mkdir -p "$(dirname "$DST/$rel")"
    eject_script="$(_src_for "ci-templates/scripts/cadence-eject.sh" || true)"
    if [[ -n "$eject_script" ]] && bash "$eject_script" --derive-adopter-footprint > "$DST/$rel" 2>/dev/null && [[ -s "$DST/$rel" ]]; then
      note_copied "$rel (adopter descriptor, generated)"
    else
      rm -f "$DST/$rel"
      echo "ERROR: could not generate the adopter eject descriptor ($rel); aborting." >&2
      exit 1
    fi
  fi

  rel="ci-templates/scripts/dead-citation-baseline.txt"
  if [[ -e "$DST/$rel" ]]; then
    note_skipped "$rel"
  else
    mkdir -p "$(dirname "$DST/$rel")"
    if bash "$DST/ci-templates/scripts/dead-citation-gate.sh" --root "$DST" --emit-baseline > "$DST/$rel" 2>/dev/null && [[ -s "$DST/$rel" ]]; then
      note_copied "$rel (adopter debt ledger, generated for this tree)"
    else
      rm -f "$DST/$rel"
      echo "WARNING: could not generate dead-citation baseline ($rel); generate with dead-citation-gate.sh --emit-baseline." >&2
    fi
  fi
}

provision_registrations() {
  local src_hooks_json
  src_hooks_json="$(_src_for ".agents/hooks/hooks.json" || _src_for "hooks/hooks.json" || _src_for ".agents/hooks.json" || true)"
  if [[ -e "$DST/.agents/hooks.json" ]]; then
    note_skipped ".agents/hooks.json"
  elif [[ -n "$src_hooks_json" && -f "$src_hooks_json" ]]; then
    python3 - "$src_hooks_json" "$DST/.agents/hooks.json" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").replace("/hooks/", "/.agents/hooks/")
pathlib.Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
    note_copied ".agents/hooks.json (portable hook config)"
  else
    echo "ERROR: hooks.json not found in source ($SRC)." >&2
    exit 1
  fi
  chmod +x "$DST/.agents/hooks"/*.sh "$DST/.agents/hooks/antigravity-local-offload-hook" 2>/dev/null || true

  local gemini_adapter=""
  for gemini_adapter in \
    "$DST/ci-templates/scripts/adapters/gemini-agy.sh" \
    "$(_src_for "ci-templates/scripts/adapters/gemini-agy.sh" || true)"; do
    [[ -n "$gemini_adapter" && -f "$gemini_adapter" ]] && break
    gemini_adapter=""
  done
  if [[ -n "$gemini_adapter" ]]; then
    bash "$gemini_adapter" "$DST" >/dev/null
    if [[ -L "$DST/.gemini/agents" && -L "$DST/.gemini/skills" && -f "$DST/.gemini/GEMINI.md" ]]; then
      note_copied ".gemini/ (Antigravity / Gemini projection)"
    else
      echo "ERROR: gemini-agy adapter failed to project .gemini/ in $DST." >&2
      exit 1
    fi
  else
    echo "ERROR: gemini-agy.sh adapter not found in source or target." >&2
    exit 1
  fi

  # Optional legacy Claude manifests when present in source.
  local rel=".claude/settings.json" hooks_adapter hooks_manifest
  hooks_adapter="$(_src_for "ci-templates/scripts/adapters/claude-code-hooks.sh" || true)"
  hooks_manifest="$SRC/artifacts/hooks/hooks.manifest"
  if [[ -f "$hooks_adapter" && -f "$hooks_manifest" ]]; then
    # shellcheck source=/dev/null
    . "$hooks_adapter"
    if cc_hook_settings_add "$DST/$rel" "$hooks_manifest" && [[ -s "$DST/$rel" ]] && grep -q '\.claude/cadence-hooks/' "$DST/$rel"; then
      note_copied "$rel (hooks registered)"
    else
      echo "ERROR: could not register CADENCE hooks in $rel." >&2
      exit 1
    fi
  fi

  local rel_mcp=".mcp.json" mcp_adapter mcp_manifest mcp_declared
  mcp_adapter="$(_src_for "ci-templates/scripts/adapters/claude-code-mcp.sh" || true)"
  mcp_manifest="$SRC/artifacts/mcp/mcp.manifest"
  if [[ -f "$mcp_adapter" && -f "$mcp_manifest" ]]; then
    # shellcheck source=/dev/null
    . "$mcp_adapter"
    mcp_declared="$(mcp_manifest_keys "$mcp_manifest")"
    if cc_mcp_registry_add "$DST/$rel_mcp" "$mcp_manifest" && [[ -s "$DST/$rel_mcp" ]] && { [[ -z "$mcp_declared" ]] || grep -q '"cadence-' "$DST/$rel_mcp"; }; then
      note_copied "$rel_mcp (MCP registry synced)"
    else
      emit_seam DELTA_AUDIT_GAP adopt.postcondition.mcp_absent "$DST/$rel_mcp"
      echo "ERROR: could not register CADENCE MCP servers in $rel_mcp." >&2
      exit 1
    fi
  fi
}

provision_seed_completeness() {
  local missing="" rows p
  [[ $# -ge 1 ]] || return 0
  rows="$( (cd "$DST" && bash "$MINT_ID" --list) 2>/dev/null || true )"
  for p in "$@"; do
    printf '%s\n' "$rows" | grep -q "^$p-[0-9]" || missing="$missing,$p"
  done
  [[ -n "$missing" ]] || return 0
  echo "seam_type=DELTA_AUDIT_GAP event_name=idalloc.seed.prefix_unenumerated subject=${missing#,}" >&2
  echo "ERROR: id ledger carries no high-water row for: ${missing#,}" >&2
}

provision_id_ledger() {
  MINT_ID=""
  local c
  for c in "$SRC/skills/cadence-mint/mint-id.sh" "$SRC/.agents/skills/cadence-mint/mint-id.sh" "$SRC/artifacts/commands/cadence-mint/mint-id.sh"; do
    [[ -f "$c" ]] && { MINT_ID="$c"; break; }
  done
  [[ -n "$MINT_ID" ]] || MINT_ID="$SRC/skills/cadence-mint/mint-id.sh"
  if [[ ! -f "$MINT_ID" ]]; then
    echo "ERROR: allocator mint-id.sh not found at $MINT_ID; cannot seed id ledger." >&2
    exit 1
  fi

  local adopter_org="$DST/docs/agentic-sdlc/CADENCE_ORG.md" seed_prefixes=(ADR) declared="" dprefix binding tprefix p seed_out
  if [[ -f "$adopter_org" ]]; then
    declared="$( (cd "$DST" && bash "$MINT_ID" --allocator-prefixes "$adopter_org") 2>/dev/null )" || {
      echo "ERROR: could not enumerate ticket prefixes §10 declares in '$adopter_org'." >&2
      exit 1
    }
  fi
  if [[ -n "$declared" ]]; then
    while IFS= read -r dprefix; do
      [[ -n "$dprefix" ]] || continue
      binding="$( (cd "$DST" && bash "$MINT_ID" --binding-for "$dprefix" "$adopter_org") 2>/dev/null || echo unbound)"
      [[ "$binding" == "unbound" ]] && seed_prefixes+=("$dprefix")
    done <<< "$declared"
  fi
  if [[ -f "$adopter_org" ]]; then
    tprefix="$(awk -F'`' '/id_scheme:/ {for(i=2;i<=NF;i++) if($i ~ /-N+$/){print $i; exit}}' "$adopter_org" 2>/dev/null | sed -E 's/-N+$//' || true)"
    case "$tprefix" in ""|*"<"*|*"{{"*) tprefix="" ;; esac
    if [[ -n "$tprefix" ]]; then
      binding="$( (cd "$DST" && bash "$MINT_ID" --binding-for "$tprefix" "$adopter_org") 2>/dev/null || echo unbound)"
      [[ "$binding" == "unbound" ]] && seed_prefixes+=("$tprefix")
    fi
  fi
  mapfile -t seed_prefixes < <(printf '%s\n' "${seed_prefixes[@]}" | awk '!seen[$0]++')
  for p in "${seed_prefixes[@]}"; do
    if ! bash "$MINT_ID" --guard-ticket-seed "$p" "$adopter_org" >/dev/null 2>&1; then
      echo "ERROR: refusing to seed ticket prefix '$p' -- §10 binds an external allocator." >&2
      exit 1
    fi
    seed_out="$( (cd "$DST" && bash "$MINT_ID" --seed "$p" 0) 2>&1 )" && \
      note_copied "ticket-index.tsv (seeded $p to high-water 0)" || {
        if echo "$seed_out" | grep -qi 'already seeded'; then
          note_skipped "ticket-index.tsv ($p already seeded)"
        else
          echo "ERROR: could not seed id-allocation ledger for '$p': $seed_out" >&2
          provision_seed_completeness "${seed_prefixes[@]}"
          exit 1
        fi
      }
  done
  provision_seed_completeness "${seed_prefixes[@]}"
  if ! ( cd "$DST" && bash "$MINT_ID" --peek ADR ) >/dev/null 2>&1; then
    echo "ERROR: id-allocation ledger did not resolve after seeding (--peek ADR failed)." >&2
    exit 1
  fi
}
