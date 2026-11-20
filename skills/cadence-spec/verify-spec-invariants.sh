#!/usr/bin/env bash
# verify-spec-invariants.sh -- Layer-1.5 semantic & cross-artifact invariant checks
# sourced by verify-spec.sh (split cleanly to keep every module <400 lines).

set -u

check_chord_tables_and_data_integrity() {
  local spec="$1" is_archive="$2"
  local di_dormant=0
  if awk '/^### (Pillar|Facet) [0-9]+:.*Data/{f=1; next} /^#{1,3} /{f=0} f' "$spec" \
       | grep -qiE 'not triggered|dormant' \
     || grep -qiE '^[-*][[:space:]]*Data.*(not triggered|dormant)' "$spec"; then
    di_dormant=1
  fi

  local res
  res="$(python3 - "$spec" "$di_dormant" <<'PY'
import re, sys

spec_path, di_dormant = sys.argv[1], int(sys.argv[2])
text = open(spec_path, encoding="utf-8", errors="replace").read().splitlines()

dims = ("Conditions", "Handling", "Outcomes", "Rules", "Deltas")
current_ac = None
ac_rows = {}
in_chord = False
in_fence = False

for raw in text:
    if re.match(r"^\s*```", raw):
        in_fence = not in_fence
        continue
    if in_fence:
        continue
    if re.match(r"^##\s+CHORD\s+(Analysis|Decomposition)", raw, re.I):
        in_chord = True
        continue
    if re.match(r"^##\s+", raw) and not re.match(r"^##\s+CHORD", raw, re.I):
        in_chord = False
        current_ac = None
        continue
    if not in_chord:
        continue
    m_ac = re.match(r"^####\s+(AC-\d+)\b", raw)
    if m_ac:
        current_ac = m_ac.group(1)
        ac_rows.setdefault(current_ac, {})
        continue
    if current_ac and raw.lstrip().startswith("|"):
        cols = [c.strip() for c in raw.strip().strip("|").split("|")]
        if cols:
            head = re.sub(r"[*_`]", "", cols[0]).strip()
            for d in dims:
                if head.lower() == d.lower() or head.lower().startswith(d.lower() + " "):
                    detail = cols[2] if len(cols) >= 3 else (cols[1] if len(cols) >= 2 else "")
                    ac_rows[current_ac][d] = detail

missing_rows = []
empty_details = []
dormant_contradictions = []

for ac, rows in ac_rows.items():
    for d in dims:
        if d not in rows:
            missing_rows.append(f"{ac}:{d}")
        else:
            val = rows[d].strip()
            if not val or val in {"-", "--", "N/A", "TBD", "TODO"} or re.fullmatch(r"\{Fill in\}", val, re.I):
                if d == "Deltas" and val.lower() in {"none", "n/a", "no internal state mutations"}:
                    continue
                empty_details.append(f"{ac}:{d}")
    if di_dormant and "Deltas" in rows:
        dval = rows["Deltas"].strip().lower()
        if dval and dval not in {"none", "none.", "n/a", "no internal state mutations", "no internal state mutations.", "-", "--"} and not dval.startswith("{"):
            dormant_contradictions.append(f"{ac} Deltas='{rows['Deltas'][:60]}'")

if missing_rows:
    print("MISSING_ROWS\t" + ", ".join(missing_rows))
if empty_details:
    print("EMPTY_DETAILS\t" + ", ".join(empty_details))
if dormant_contradictions:
    print("DORMANT_DI\t" + "; ".join(dormant_contradictions))
print("AC_IDS\t" + " ".join(ac_rows.keys()))
PY
)"
  local line kind payload
  local spec_ac_ids=""
  while IFS= read -r line; do
    kind="${line%%	*}"
    payload="${line#*	}"
    case "$kind" in
      MISSING_ROWS)
        if [[ "$is_archive" -eq 1 ]]; then warn "CHORD dimension row(s) missing in archived spec: $payload"
        else fail "CHORD table incomplete — missing dimension row(s): $payload"; fi ;;
      EMPTY_DETAILS)
        if [[ "$is_archive" -eq 1 ]]; then warn "Empty CHORD cell(s) in archived spec: $payload"
        else fail "CHORD table has empty/placeholder detail cell(s): $payload"; fi ;;
      DORMANT_DI)
        fail "spec.data_integrity.dormant_trigger_contradicted — Data Integrity marked dormant but CHORD Deltas mutates state: $payload" ;;
      AC_IDS) spec_ac_ids="$payload" ;;
    esac
  done <<< "$res"

  SPEC_AC_IDS="$spec_ac_ids"
}

check_cross_artifact_traceability() {
  local root="$1" spec="$2" test_plan="$3" is_archive="$4" ac_ids="$5"
  local ac
  local missing_cov=""
  local cov_block
  cov_block="$(awk '/^## Acceptance Criteria Coverage/{f=1; next} /^## /{f=0} f' "$test_plan")"
  for ac in $ac_ids; do
    if ! grep -qE "\b${ac}\b" <<<"$cov_block"; then
      missing_cov="$missing_cov $ac"
    fi
  done
  if [[ -n "$missing_cov" ]]; then
    if [[ "$is_archive" -eq 1 ]]; then warn "test-plan.md Acceptance Criteria Coverage omits:$missing_cov"
    else fail "test-plan.md Acceptance Criteria Coverage omits CHORD block(s):$missing_cov"; fi
  else
    [[ -n "$ac_ids" ]] && pass "All CHORD AC blocks traced in test-plan.md Coverage"
  fi

  # Observability Seams parity (RULE_DIVERGENCE baselines + test-plan OS-N links)
  local seams_sec
  seams_sec="$(awk '/^## Observability Seams/{f=1; next} /^## /{f=0} f' "$spec")"
  if grep -qE 'RULE_DIVERGENCE' <<<"$seams_sec"; then
    local base_rows
    base_rows="$(awk '/^### Baseline Definitions/{f=1; next} /^#/{f=0} f && /^\|/' "$spec" | tail -n +3 | wc -l)"
    if [[ "$base_rows" -ge 1 ]]; then
      pass "RULE_DIVERGENCE baseline table populated ($base_rows row(s))"
    else
      warn "RULE_DIVERGENCE declared in Observability Seams without Baseline Definitions rows"
    fi
  fi
  if grep -qE '\b(UNSOUND_CONDITION|RULE_DIVERGENCE|DELTA_AUDIT_GAP|BOUNDARY_FAULT)\b' <<<"$seams_sec"; then
    if grep -qE '\bOS-[0-9]+\b|UNSOUND_CONDITION|RULE_DIVERGENCE|DELTA_AUDIT_GAP|BOUNDARY_FAULT' "$test_plan"; then
      pass "Observability seam scenario(s) traced in test-plan.md"
    else
      warn "spec.md declares Observability Seams but test-plan.md has no OS-N / seam scenario"
    fi
  fi

  # Files Affected <400-line risk check on existing Modify targets
  local path ctype lines
  while IFS=$'\t' read -r path ctype; do
    [[ -n "$path" && "$ctype" == "Modify" && "$path" != *'{'* && -f "$root/$path" ]] || continue
    lines="$(wc -l < "$root/$path" | tr -d ' ')"
    if [[ "$lines" -ge 360 ]]; then
      warn "Modify target '$path' is already $lines lines (close to/exceeds <400-line Agentic Ergonomics ceiling)"
    fi
  done < <(awk -F'|' '
    /^### Files Affected/ { insec=1; rownum=0; next }
    /^#/ { insec=0 }
    insec && /^\|/ {
      rownum++; if (rownum <= 2) next
      p=$2; t=$4
      gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/^`|`$/, "", p)
      gsub(/^[ \t]+|[ \t]+$/, "", t)
      print p "\t" t
    }
  ' "$spec")
}

check_design_options_hygiene() {
  local opts="$1" is_archive="$2"
  [[ -f "$opts" ]] || return 0
  if grep -qE '^## Axis of variation' "$opts"; then
    pass "design-options.md has Axis of variation"
  else
    fail "design-options.md missing '## Axis of variation'"
  fi

  local opt_count
  opt_count="$(grep -cE '^## Option [A-Z]:' "$opts" || true)"
  if [[ "$opt_count" -eq 0 ]]; then
    fail "design-options.md has no '## Option A/B/C:' sections"
  elif [[ "$opt_count" -eq 1 ]] && ! grep -qiE 'collapse|single viable' "$opts"; then
    fail "design-options.md has 1 option without an explicit space-collapse proof"
  else
    pass "design-options.md declares $opt_count structural option(s)"
  fi

  local req
  for req in 'Structure:' 'Steelman:' 'Failure modes \(KNOWN\):' 'Failure modes \(UNKNOWN\):' 'Pillar-relevant properties:' 'Novelty class:'; do
    if ! grep -qE "$req" "$opts"; then
      if [[ "$is_archive" -eq 1 ]]; then warn "design-options.md missing '$req' bullet"
      else fail "design-options.md missing required bullet matching '$req'"; fi
    fi
  done

  # Flag ranking/recommendation bias outside code spans
  local rank_hits
  rank_hits="$(sed -E 's/`[^`]*`//g' "$opts" | grep -niE '\b(recommended option|preferred option|winning option|best option|we recommend|strongest choice)\b' || true)"
  if [[ -n "$rank_hits" ]]; then
    if [[ "$is_archive" -eq 1 ]]; then warn "design-options.md may contain ranking language"
    else fail "design-options.md leaks ranking/preference language (violates unranked explorer separation)"; fi
  else
    pass "design-options.md free of ranking/recommendation leakage"
  fi
}

check_pillar_precedence_convergence() {
  local spec="$1" opts="$2" is_archive="$3"
  [[ -f "$spec" && -f "$opts" ]] || return 0
  local has_sentinel=0
  grep -qF '**Gate 1 rulings:** required' "$spec" && has_sentinel=1
  local res
  res="$(python3 - "$spec" "$opts" <<'PY'
import re, sys

spec_txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
opts_txt = open(sys.argv[2], encoding="utf-8", errors="replace").read()

def is_dormant(pattern):
    m = re.search(rf"(?ms)^###\s+(?:Pillar|Facet)\s+\d+:\s*{pattern}.*?(?=^###\s+|\Z)", spec_txt, re.I)
    return (not m) or bool(re.search(r"\b(?:dormant|not triggered)\b", m.group(0), re.I))

di_active = not is_dormant(r"Data\s*(?:&|and)\s*Audit|Data Integrity")
sec_active = not is_dormant(r"Security(?: Boundary)? Posture")
if not (di_active or sec_active):
    sys.exit(0)

expl_m = re.search(r"(?ms)^##\s+Design Exploration\b.*?(?=^##\s+|\Z)", spec_txt)
if not expl_m:
    sys.exit(0)
expl = expl_m.group(0)
if not re.search(r"(?im)Pillar\s+precedence\s+check\s*:", expl):
    print("MISSING_CHECK\tDesign Exploration omits explicit 'Pillar precedence check:' line while Pillar 4/6 is active")

win_m = re.search(r"(?im)^[-*\s]*(?:\*\*)?(?:Winner|Selected\s+(?:winner|option))(?::\*\*|\*\*:|:)\s*(Option\s+[A-Z])\b", expl)
axis_m = re.search(r"(?im)^[-*\s]*(?:\*\*)?(?:Winning\s+axis|Decisive\s+pillar)[^:\n]*:(?:\*\*)?\s*(.+)$", expl)
oq_m = re.search(r"(?ms)^#{2,3}\s+(?:Risks\s+and\s+)?Open Questions\b.*?(?=^#{1,2}\s+|\Z)", spec_txt)
has_risk_oq = bool(oq_m and re.search(r"\bOQ-\d+\b", oq_m.group(0)) and re.search(r"(?i)\b(?:known|risk|trade-?off|pillar|precedence|option\s+[a-z]|sibling|durab|idempoten|ttl|stale|race)\b", oq_m.group(0)))

if win_m and axis_m:
    axis_low = axis_m.group(1).lower()
    picked_lower = any(k in axis_low for k in ("structural simplicity", "simplicity", "agentic ergonomics", "developer experience")) and not re.search(r"data\s*(?:&|and)\s*audit|data\s+integrity|security", axis_low)
    opt_m = re.search(rf"(?ms)^##\s+{re.escape(win_m.group(1))}\b.*?(?=^##\s+|\Z)", opts_txt)
    high_known = bool(opt_m and re.search(r"\[[^\]]*(?:Severity:\s*HIGH|Pillar:\s*(?:Data\s*(?:&|and)\s*Audit|Data\s+Integrity|Security))[^\]]*\]", opt_m.group(0), re.I))
    p_flag = any(re.search(r"\|\s*Flag\s*\|", m.group(0), re.I) for m in re.finditer(r"(?ms)^###\s+(?:Pillar|Facet)\s+[46]:.*?(?=^###\s+|\Z)", spec_txt))
    if picked_lower and (high_known or p_flag) and not has_risk_oq:
        print(f"INVERSION\t{win_m.group(1)} picked on lower-ranked pillar ({axis_m.group(1).strip()[:60]}) over active Pillar 4/6 risk without Gate 1 OQ-N")
PY
)"
  local line kind payload
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kind="${line%%	*}"
    payload="${line#*	}"
    case "$kind" in
      MISSING_CHECK)
        if [[ "$is_archive" -eq 1 || "$has_sentinel" -eq 0 ]]; then warn "$payload"
        else fail "$payload"; fi ;;
      INVERSION)
        if [[ "$is_archive" -eq 1 ]]; then warn "pillar_precedence_inversion: $payload"
        else fail "pillar_precedence_inversion: $payload"; fi ;;
    esac
  done <<< "$res"
}

check_chaos_applicability() {
  local spec="$1" test_plan="$2" is_archive="$3"
  [[ -f "$spec" && -f "$test_plan" ]] || return 0
  local has_sentinel=0
  grep -qF '**Gate 1 rulings:** required' "$spec" && has_sentinel=1
  local res
  res="$(python3 - "$spec" "$test_plan" <<'PY'
import re, sys

spec_txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
tp_txt = open(sys.argv[2], encoding="utf-8", errors="replace").read()

def is_dormant(pattern):
    m = re.search(rf"(?ms)^###\s+(?:Pillar|Facet)\s+\d+:\s*{pattern}.*?(?=^###\s+|\Z)", spec_txt, re.I)
    return (not m) or bool(re.search(r"\b(?:dormant|not triggered)\b", m.group(0), re.I))

di_active = not is_dormant(r"Data\s*(?:&|and)\s*Audit|Data Integrity")
sec_active = not is_dormant(r"Security(?: Boundary)? Posture")

# Strip fenced blocks, Alternatives Considered, Prior Production Findings, and Out of Scope
lines, active_lines, in_fence, skip_sec = spec_txt.splitlines(), [], False, False
for raw in lines:
    if re.match(r"^\s*```", raw):
        in_fence = not in_fence; continue
    if in_fence:
        continue
    if re.match(r"^##\s+(?:Alternatives Considered|Out of Scope)\b", raw, re.I) or re.match(r"^###\s+Prior Production Findings\b", raw, re.I):
        skip_sec = True; continue
    if re.match(r"^##\s+", raw):
        skip_sec = False
    if not skip_sec:
        active_lines.append(raw)
body = "\n".join(active_lines)

oq_txt = "\n".join(m.group(0) for m in re.finditer(r"(?ms)^#{2,3}\s+(?:Risks\s+and\s+)?Open Questions\b.*?(?=^#{1,2}\s+|\Z)", spec_txt))

triggers = []
if di_active and (
    re.search(r"\bCP-12\b", body)
    or (
        re.search(r"(?i)\b(?:irreversible\s+external|external\s+(?:side[- ]?effect|mutation|charge|dispatch|write)|outbound\s+(?:mutation|payment|billing|webhook|charge))", body)
        and re.search(r"(?i)\b(?:retry|retries|timeout|idempoten|at-most-once|post-commit|ambiguous)\b", body)
    )
):
    triggers.append(("CP-12", "irreversible external side effect under retry/timeout"))

if (di_active or sec_active) and (
    re.search(r"\bCP-13\b", body)
    or re.search(r"(?i)\b(?:external|vendor|provider|remote|dedup(?:lication)?|idempotency|lease|token).{0,40}\b(?:ttl|expir(?:es?|ation|y)|evict(?:ion|ed)?)\b", body)
):
    triggers.append(("CP-13", "external authority/dedup/cache TTL expiration window"))

if di_active and (
    re.search(r"\bCP-05\b", body)
    or re.search(r"(?i)\b(?:for\s+update|row[- ]level\s+lock|row\s+lock|advisory\s+lock|pessimistic\s+lock|post-lock\s+(?:re-?validat|predicate)|lock\s+contention)\b", body)
):
    triggers.append(("CP-05", "concurrent contention / post-lock predicate re-validation"))

if (
    re.search(r"\bCP-14\b", body)
    or re.search(r"(?i)\b(?:reload|remount|page\s+refresh|route\s+change|browser\s+back|worker\s+restart|caller\s+reset).{0,50}\b(?:in-flight|mutation|attempt|idempoten|pending|submit)\b", body)
    or re.search(r"(?i)\b(?:in-flight|attempt\s+identity|pending\s+mutation).{0,50}\b(?:reload|remount|refresh|restart|reset)\b", body)
):
    triggers.append(("CP-14", "caller state reset/remount during in-flight mutation"))

satisfied, missing = [], []
for code, desc in triggers:
    if re.search(rf"\b{re.escape(code)}\b", tp_txt) or (re.search(r"\bOQ-\d+\b", oq_txt) and re.search(rf"\b{re.escape(code)}\b", oq_txt)):
        satisfied.append(code)
    else:
        missing.append((code, desc))

for code, desc in missing:
    print(f"MISSING\t{code} ({desc}) triggered by spec.md but omitted from test-plan.md")
if satisfied and not missing:
    print("SATISFIED\t" + ", ".join(satisfied))
PY
)"
  local line kind payload
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kind="${line%%	*}"
    payload="${line#*	}"
    case "$kind" in
      SATISFIED) pass "Chaos matrix applicability satisfied ($payload)" ;;
      MISSING)
        if [[ "$is_archive" -eq 1 || "$has_sentinel" -eq 0 ]]; then warn "chaos_matrix_omission: $payload"
        else fail "chaos_matrix_omission: $payload"; fi ;;
    esac
  done <<< "$res"
}
