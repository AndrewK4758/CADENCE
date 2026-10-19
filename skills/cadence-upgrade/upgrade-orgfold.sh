#!/usr/bin/env bash
#
# upgrade-orgfold.sh -- the /cadence-upgrade template-to-live org-fold sidecar
# (BTG-048). A colocated module shipped by the PI-023 directory-copy contract and
# sourced by upgrade-cadence.sh, so it runs in the entry point's shell scope:
# the globals it reads (TARGET, CORE, BASE_EMPTY, NEW_VERSION) and the helpers it
# reuses (emit_seam, core_file) resolve at CALL time from that scope (dynamic
# scoping), exactly like upgrade-repair.sh / upgrade-collect.sh.
#
# Bounded context: Upgrade seam / template-to-live reconciliation (BTG-048).
# Upstream: run_orgfold is dispatched by upgrade-cadence.sh's main() on the
#   clean-apply path, AFTER the stamp advance and the stale-staging cleanup and
#   BEFORE the final success echo -- a dependent, best-effort, stamp-INDEPENDENT
#   post-apply stage (the --repair precedent, upgrade-repair.sh:20-27). A
#   template-merge conflict aborts the run before the fold ever dispatches.
# Downstream: reconciles the just-applied docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md
#   inter-version changes into the adopter's live docs/agentic-sdlc/CADENCE_ORG.md
#   (the file every skill/agent reads at runtime). On a clean fold the live file is
#   rewritten atomically; on a conflict the marker-bearing form is STAGED under
#   .cadence-upgrade-staging/ and the live file is byte-untouched (DEC-001).
# Spec: specs/BTG-048/spec.md (AC-1..AC-10); decisions.md DEC-001..DEC-014.
#
# Contract (decisions.md): 3-way shape base = core@base_commit template (DEC-003),
#   source = the just-applied template, target = the live file. Section-aware
#   routing (DEC-008, extended by BTG-315 DEC-014): Contextual Grounding Who/Where/Why ->
#   row-add keyed on first-column content (DEC-014 trim + case-sensitive);
#   "Runtime Binding" -> hard-revert (DEC-004, number-agnostic heading match);
#   "Tracker Binding" -> the `### Per-prefix tracker bindings` table is spliced
#   out and merged deterministically (header from source when the adopter never
#   touched it AND the change is a strict column append -- BTG-316: a reorder,
#   removal or rename over an unchanged live header surfaces a conflict
#   instead -- live's rows always carried verbatim, a customized header still
#   surfaces a conflict), with everything else in the section taking the plain
#   3-way line-merge unchanged (BTG-315 DEC-014, closing the BTG-315 DEC-013
#   finding: a header widened over populated rows has no unchanged context line
#   for `git merge-file` to separate the two changes, so it always conflicted
#   without this); every other section -> section-scoped 3-way line-merge.
#   Never in place on conflict (DEC-001). Best-effort / stamp-independent
#   (DEC-002): a fold conflict never rolls back the stamp. Fail-loud skips
#   (DEC-010): BASE_EMPTY / no-base and no-live-file hard-skip loud and NEVER
#   create the live file (adopter owns creation).

# Colocated template->live pairing table (DEC-006; mirrors the RECONCILE shape,
# upgrade-collect.sh:43-55). Adding a future pairing is one data row here -- no new
# code block. Row schema: <template-path>|<live-path>.
ORGFOLD_PAIRS=(
  "docs/agentic-sdlc/CADENCE_ORG_TEMPLATE.md|docs/agentic-sdlc/CADENCE_ORG.md"
)

# ---------------------------------------------------------------------------
# Section splitter (DEC-008). Splits <infile> into <outdir>/preamble (lines before
# the first `^## ` H2), <outdir>/sec.NNN (each H2 section: heading line + body up
# to but excluding the next H2), and <outdir>/index ("NNN<TAB>key" per section).
# The section KEY is the H2 heading text with a leading `## ` and a leading `N.`
# numbering stripped, then trimmed -- CASE-SENSITIVE (DEC-014), so `## 8. Runtime
# Binding` and `## Runtime Binding` both normalize to `Runtime Binding`. Splitting
# keys on `^## ` at column 0 only (a `## ` inside a fenced block could mis-split --
# a documented Known Limitation, mirrors expand_dir_row's C-quote caveat).
# ---------------------------------------------------------------------------
_orgfold_split() {
  local infile="$1" outdir="$2"
  mkdir -p "$outdir"
  awk -v outdir="$outdir" '
    function norm(h,   k){
      k=h; sub(/^##[ \t]+/,"",k); sub(/^[0-9]+\.[ \t]*/,"",k)
      gsub(/^[ \t]+/,"",k); gsub(/[ \t]+$/,"",k); return k
    }
    BEGIN{ n=0; pre=1; idx=outdir "/index"; printf "" > idx }
    /^## / {
      pre=0; n++; cur=sprintf("%s/sec.%03d", outdir, n)
      printf "%03d\t%s\n", n, norm($0) >> idx
      print $0 > cur; next
    }
    { if(pre){ print >> (outdir "/preamble") } else { print >> cur } }
  ' "$infile"
}

# ---------------------------------------------------------------------------
# _orgfold_grounding <live_sec> <src_sec>: emit the folded Contextual Grounding section (AC-3 /
# DEC-003). Within the "Pre-Filled Contextual Grounding Constants" H2, for each H3 table whose
# heading starts with Where / Who / Why, a source data row whose first-column key
# (pipe cell 1, trimmed, CASE-SENSITIVE -- DEC-014) is ABSENT from the live table is
# appended verbatim (the template placeholder); every existing live row is left
# byte-unchanged (live is authoritative -- re-adding a previously-deleted row is
# accepted). A source row with no extractable first-column key is skipped + reported
# (never mangles the table). Row-add applies only where a live table already exists.
# The folded section goes to stdout; each add/skip is reported to stderr.
# ---------------------------------------------------------------------------
_orgfold_grounding() {
  local livesec="$1" srcsec="$2"
  awk '
    function firstkey(line,   a,c,k){
      c=split(line,a,"|"); if(c<3) return "\x01BAD"       # need at least |cell1|
      k=a[2]; gsub(/^[ \t]+/,"",k); gsub(/[ \t]+$/,"",k)
      if(k=="") return "\x01BAD"; return k
    }
    function iscat(h){
      if(h ~ /^### Where([ \t]|$|\()/) return "Where"
      if(h ~ /^### Who([ \t]|$|\()/)   return "Who"
      if(h ~ /^### Why([ \t]|$|\()/)   return "Why"
      return ""
    }
    function flush(cat,   i,key){
      for(i=1;i<=scount[cat];i++){
        key=srckey[cat,i]
        if(key=="\x01BAD"){
          print "upgrade-cadence: org-fold skipped a malformed template Contextual Grounding row (no first-column key) in " cat "." > "/dev/stderr"
          continue
        }
        if(!liveseen[cat,key]){
          print srcline[cat,i]
          liveseen[cat,key]=1
          print "upgrade-cadence: org-fold added Contextual Grounding " cat " row [" key "] to the live table (template placeholder)." > "/dev/stderr"
        }
      }
    }
    # Pass 1: the SOURCE section (FNR==NR -- first file arg).
    FNR==NR {
      if($0 ~ /^### /){ scat=iscat($0); spc=0; next }
      if($0 ~ /^## /){ scat=""; next }
      if(scat!="" && $0 ~ /^[ \t]*\|/){
        spc++; if(spc<=2) next                            # header + separator
        i=++scount[scat]; srcline[scat,i]=$0; srckey[scat,i]=firstkey($0)
      }
      next
    }
    # Pass 2: the LIVE section -- emit, tracking category + table boundaries.
    {
      if($0 ~ /^### /){ if(pending) flush(lcat); lcat=iscat($0); lpc=0; pending=0; print; next }
      if($0 ~ /^## /){ if(pending) flush(lcat); lcat=""; lpc=0; pending=0; print; next }
      if(lcat!="" && $0 ~ /^[ \t]*\|/){
        lpc++; if(lpc>2){ k=firstkey($0); if(k!="\x01BAD") liveseen[lcat,k]=1 }
        pending=1; print; next
      }
      if(lcat!="" && pending){ flush(lcat); pending=0 }
      print
    }
    END{ if(pending) flush(lcat) }
  ' "$srcsec" "$livesec"
}

# BTG-315 (additive): the Tracker Binding table-splice extension (DEC-014),
# sourced here so _orgfold_trackerbinding / TB_TABLE_CONFLICT are in scope for
# fold_one below. Split into its own file to keep this one under the 400-line
# DX ceiling (Facet 3) -- see that file's own header for why.
ORGFOLD_TRACKERBINDING="$(dirname "${BASH_SOURCE[0]}")/upgrade-orgfold-trackerbinding.sh"
if [[ ! -f "$ORGFOLD_TRACKERBINDING" ]]; then
  echo "upgrade-orgfold: the Tracker Binding table-splice half is not at $ORGFOLD_TRACKERBINDING" >&2
  echo "       Both halves ship together; refusing to fold without it." >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$ORGFOLD_TRACKERBINDING"

# ---------------------------------------------------------------------------
# fold_one <base> <src> <live> <out>: reconstruct the folded live file into <out>
# and set FOLD_RC (0 clean / 1 at least one conflicted section). The live file's
# preamble and section order are authoritative; each live section is routed
# (DEC-008): a section matched in the source is 3-way line-merged (theirs = live,
# base = <base> section, ours = <src> section); a live-only section is carried
# verbatim (never deleted). Contextual Grounding row-add (DEC-003/AC-3), the Runtime Binding
# revert (DEC-004), the Tracker Binding table splice (BTG-315 DEC-014), and the
# brand-new source-section append (DEC-013) are layered in by the red-green
# cycles that follow.
# ---------------------------------------------------------------------------
FOLD_RC=0
fold_one() {
  local base="$1" src="$2" live="$3" out="$4"
  local wd; wd="$(mktemp -d)"
  _orgfold_split "$base" "$wd/base"
  _orgfold_split "$src"  "$wd/src"
  _orgfold_split "$live" "$wd/live"
  : > "$wd/empty"
  FOLD_RC=0
  : > "$out"
  [[ -f "$wd/live/preamble" ]] && cat "$wd/live/preamble" >> "$out"

  local -A SRCKEY BASEKEY
  local n key
  while IFS=$'\t' read -r n key; do SRCKEY["$key"]="$wd/src/sec.$n"; done < "$wd/src/index"
  while IFS=$'\t' read -r n key; do BASEKEY["$key"]="$wd/base/sec.$n"; done < "$wd/base/index"

  # The source "Pre-Filled Contextual Grounding Constants" section (matched by heading-text
  # prefix, number-agnostic) is the row-add source for the Contextual Grounding pass.
  local srcground=""
  while IFS=$'\t' read -r n key; do
    case "$key" in "Pre-Filled Contextual Grounding Constants"*) srcground="$wd/src/sec.$n"; break ;; esac
  done < "$wd/src/index"

  local -A LIVEKEY
  local livesec bfile merged
  while IFS=$'\t' read -r n key; do
    livesec="$wd/live/sec.$n"
    LIVEKEY["$key"]=1
    # Runtime Binding hard-revert (AC-4 / DEC-004): the section whose heading text
    # (number-stripped) is EXACTLY "Runtime Binding" is EXCLUDED from the merge and
    # carried byte-for-byte -- any template change/conflict there is thereby reverted,
    # unconditionally. Revert scope is Runtime Binding ONLY (draft-literal): the other
    # *-binding sections flow through the general line-merge below.
    if [[ "$key" == "Runtime Binding" ]]; then
      cat "$livesec" >> "$out"; continue
    fi
    # Contextual Grounding row-add (AC-3): the live "Pre-Filled Contextual Grounding Constants" section is
    # reconciled row-by-row, NEVER line-merged (its tables never conflict).
    case "$key" in
      "Pre-Filled Contextual Grounding Constants"*)
        if [[ -n "$srcground" ]]; then _orgfold_grounding "$livesec" "$srcground" >> "$out"
        else cat "$livesec" >> "$out"; fi
        continue ;;
    esac
    # Tracker Binding table-scoped splice (BTG-315 / AC-7 / DEC-014, extending
    # DEC-008's routing): the `### Per-prefix tracker bindings` table is
    # spliced out and merged deterministically (row-preserving header
    # widening, restricted to a strict column append -- BTG-316; a customized
    # header still surfaces a conflict); everything
    # ELSE in the section -- including a prose-only conflict with no table at
    # all -- still takes the SAME generic 3-way line merge as every other
    # section (S-3.3's pin), because `_orgfold_trackerbinding` falls back to
    # exactly that path when it finds no table to splice.
    if [[ "$key" == "Tracker Binding" && -n "${SRCKEY[$key]:-}" ]]; then
      bfile="${BASEKEY[$key]:-$wd/empty}"
      merged="$wd/tb-merged"
      _orgfold_trackerbinding "$bfile" "${SRCKEY[$key]}" "$livesec" > "$merged"
      cat "$merged" >> "$out"
      [[ "$TB_TABLE_CONFLICT" -eq 1 ]] && FOLD_RC=1
      continue
    fi
    if [[ -n "${SRCKEY[$key]:-}" ]]; then
      bfile="${BASEKEY[$key]:-$wd/empty}"
      merged="$wd/merged"
      if git merge-file -p -L theirs -L base -L "core@${NEW_VERSION:-new}" \
           "$livesec" "$bfile" "${SRCKEY[$key]}" > "$merged" 2>/dev/null; then
        cat "$merged" >> "$out"
      else
        cat "$merged" >> "$out"; FOLD_RC=1
      fi
    else
      cat "$livesec" >> "$out"   # live-only section carried verbatim (never deleted)
    fi
  done < "$wd/live/index"

  # Brand-new source sections (DEC-013): a source H2 absent from BOTH live and base
  # is an unambiguous clean add -- appended at end-of-file and reported (template-
  # positional ordering is a documented Known Limitation). A source section present
  # in base but deleted from live is NOT re-added (the deletion is respected).
  while IFS=$'\t' read -r n key; do
    if [[ -z "${LIVEKEY[$key]:-}" && -z "${BASEKEY[$key]:-}" ]]; then
      cat "$wd/src/sec.$n" >> "$out"
      echo "upgrade-cadence: org-fold appended new template section [$key] at end-of-file (relocate as needed)." >&2
    fi
  done < "$wd/src/index"

  rm -rf "$wd"
}

# ---------------------------------------------------------------------------
# orgfold_write <foldout> <live> <staged> <conflict:0|1>: the atomic apply (DEC-005
# Data Integrity -- compute-then-atomic-move, never a partial write). A clean fold
# atomically replaces the live file (which MUST still exist -- never create); a
# conflicted fold atomically moves the marker-bearing form into staging and leaves
# the live file byte-untouched. A vanished live file fires UNSOUND_CONDITION
# live_absent; a failed move fires UNSOUND_CONDITION partial_write.
# ---------------------------------------------------------------------------
orgfold_write() {
  local foldout="$1" live="$2" staged="$3" conflict="$4"
  if [[ "$conflict" -eq 1 ]]; then
    mkdir -p "$(dirname "$staged")" 2>/dev/null
    if ! mv "$foldout" "$staged" 2>/dev/null; then
      emit_seam UNSOUND_CONDITION upgrade.orgfold.partial_write "$staged"
      echo "upgrade-cadence: org-fold could not stage $staged -- the live file is untouched." >&2
      rm -f "$foldout"; return 1
    fi
    return 0
  fi
  if [[ ! -f "$live" ]]; then
    emit_seam UNSOUND_CONDITION upgrade.orgfold.live_absent "$live"
    echo "upgrade-cadence: org-fold aborted -- the live file vanished before apply: $live (nothing written)." >&2
    rm -f "$foldout"; return 1
  fi
  if ! mv "$foldout" "$live" 2>/dev/null; then
    emit_seam UNSOUND_CONDITION upgrade.orgfold.partial_write "$live"
    echo "upgrade-cadence: org-fold could not write $live (nothing partially applied)." >&2
    rm -f "$foldout"; return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# run_orgfold <base_commit> -- the post-apply fold stage (dispatched from main() on
# the clean-apply path). For each ORGFOLD_PAIRS row: hard-skip loud on BASE_EMPTY /
# an empty reconstructed base or an absent live file (DEC-010, never create); a
# clean no-op when the template did not change; otherwise fold and either apply
# (clean) or stage (conflict) atomically. Best-effort / stamp-independent (DEC-002):
# never rolls back the already-advanced stamp.
# ---------------------------------------------------------------------------
run_orgfold() {
  local base_commit="$1"
  local pair tpl live_rel base_tmp src live foldout staged
  for pair in "${ORGFOLD_PAIRS[@]}"; do
    IFS='|' read -r tpl live_rel <<<"$pair"
    # Guard 1a (DEC-010): the 2-way fallback has no reconstructable base -> a
    # whole-file add against an empty base would dump markers into a runtime-parsed
    # config. Hard-skip loud instead.
    if [[ "${BASE_EMPTY:-0}" -eq 1 ]]; then
      echo "upgrade-cadence: no base template -- org-fold skipped for $live_rel (re-run after a stamped upgrade)." >&2
      continue
    fi
    base_tmp="$(mktemp)"
    core_file "$base_commit" "$tpl" "$base_tmp"
    # Guard 1b: an empty base template at core@base_commit is BASE_EMPTY-equivalent.
    if [[ ! -s "$base_tmp" ]]; then
      echo "upgrade-cadence: no base template -- org-fold skipped for $live_rel." >&2
      rm -f "$base_tmp"; continue
    fi
    # Guard 2 (DEC-006/DEC-010): no live file -> skip loud, NEVER create it.
    live="$TARGET/$live_rel"
    if [[ ! -f "$live" ]]; then
      echo "upgrade-cadence: no live $live_rel -- org-fold skipped; adopter owns creation (never fabricated)." >&2
      rm -f "$base_tmp"; continue
    fi
    src="$TARGET/$tpl"
    if [[ ! -f "$src" ]]; then
      echo "upgrade-cadence: applied template $tpl absent -- org-fold skipped for $live_rel." >&2
      rm -f "$base_tmp"; continue
    fi
    # Template unchanged this upgrade -> a clean no-op (a legitimate log line, not a
    # seam -- BTG-015 DEC-007 precedent).
    if cmp -s "$base_tmp" "$src"; then
      echo "upgrade-cadence: template $tpl unchanged -- nothing to fold into $live_rel." >&2
      rm -f "$base_tmp"; continue
    fi
    foldout="$(mktemp "$TARGET/.orgfold.XXXXXX")"
    fold_one "$base_tmp" "$src" "$live" "$foldout"
    if [[ "$FOLD_RC" -eq 0 ]]; then
      if orgfold_write "$foldout" "$live" "" 0; then
        echo "upgrade-cadence: org-fold applied to $live_rel."
      fi
    else
      staged="$TARGET/.cadence-upgrade-staging/$live_rel"
      if orgfold_write "$foldout" "$live" "$staged" 1; then
        emit_seam RULE_DIVERGENCE upgrade.orgfold.conflicts_staged "$live_rel"
        echo "upgrade-cadence: org-fold produced CONFLICT(S) in $live_rel -- staged with conflict markers under .cadence-upgrade-staging/$live_rel (the live file is byte-untouched)." >&2
        echo "upgrade-cadence: !!! RESOLVE THESE ORG-FOLD CONFLICTS IMMEDIATELY before relying on $live_rel -- reconcile the staged copy, then replace the live file." >&2
      fi
    fi
    rm -f "$base_tmp"
  done
}
