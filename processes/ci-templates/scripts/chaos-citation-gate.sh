#!/usr/bin/env bash
#
# chaos-citation-gate.sh -- BTG-186 structural gate (AC-1a / AC-1b / AC-3 / AC-4).
#
# Bounded context: Build tooling / compile-gate flow. Invariant relied on from
# outside this boundary: docs/policies/chaos-profiles.md is the canonical Chaos
# Profile Catalog, and its `### CP-NN: <name>` headings are the ONLY definition
# of which profiles exist.
#
# Exit codes: 0 clean ; 1 on a violation ; 2 on setup failure.
#
# READ-ONLY BY CONSTRUCTION -- it writes no file inside the scanned tree.
#
# References: archive/BTG-186/{problem,spec,test-plan,decisions}.md ;
#             ci-templates/scripts/dead-citation-gate.sh (the shape copied).

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    *) echo "chaos-citation-gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done

CATALOG_REL="docs/policies/chaos-profiles.md"
CATALOG="$ROOT/$CATALOG_REL"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# "1 file" / "0 files" -- the summary line is the gate's primary assertion
# surface, so it is written as English a reader can quote, not as a code.
plural() { # count, singular-noun
  [ "$1" -eq 1 ] && echo "$2" || echo "${2}s"
}

emit_seam() {
  local seam_type="$1" event_name="$2" subject="${3:-}"
  echo "seam_type=$seam_type event_name=$event_name subject=$subject" >&2
}

# --- catalog -----------------------------------------------------------------
# Emits "CP-NN<TAB>Canonical Name" per entry. The accepted code set is derived
# here, at run time, from the catalog itself -- NEVER hardcoded. A hardcoded code
# list is the very defect this gate exists to catch.
load_catalog() {
  if [[ ! -r "$CATALOG" ]]; then
    echo "chaos-citation: FATAL -- catalog not readable: $CATALOG_REL" >&2
    emit_seam UNSOUND_CONDITION chaos.catalog.unreadable "$CATALOG_REL"
    exit 2
  fi
  sed -n 's/^### \(CP-[0-9]\{1,\}\): \(.*\)$/\1	\2/p' "$CATALOG" > "$WORK/catalog.tsv"
  cut -f1 "$WORK/catalog.tsv" > "$WORK/codes.txt"
  if [[ ! -s "$WORK/codes.txt" ]]; then
    # A zero-code catalog is not "a catalog with nothing to check". It is a
    # catalog whose heading format this gate no longer understands, and it would
    # pass EVERY file vacuously -- the exact failure this gate exists to close.
    echo "chaos-citation: FATAL -- catalog parsed to zero profiles: $CATALOG_REL" >&2
    emit_seam UNSOUND_CONDITION chaos.catalog.empty "$CATALOG_REL"
    exit 2
  fi

  # The NAME set is validated too, not just the code set (AC-1b Preconditions:
  # "asserted rather than assumed"). The two halves fail in OPPOSITE directions,
  # which is why one guard cannot stand for both: a zero-CODE catalog reports
  # everything, while a zero-NAME catalog reports NOTHING -- every label becomes
  # a non-match and the whole cross-name rule passes vacuously over the entire
  # corpus, certified by a clean "N files scanned, 0 violations" line.
  #
  # Normalized here EXACTLY as pass 2's awk normalizes, so what is validated is
  # the key set the join actually builds and not a near-miss of it. Blank names
  # are dropped rather than kept as a "" key: an empty key would make a `CP-NN
  # ()` parenthetical collide with it and manufacture a finding out of nothing.
  # `[^a-z0-9][^a-z0-9]*` is written as POSIX BRE, not `\+`; busybox sed and
  # busybox uniq were both run against this pipeline in the CI base image.
  cut -f2 "$WORK/catalog.tsv" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9][^a-z0-9]*/ /g; s/^ *//; s/ *$//' \
    | grep -v '^$' > "$WORK/names.txt"
  if [[ ! -s "$WORK/names.txt" ]]; then
    echo "chaos-citation: FATAL -- catalog parsed to zero profile names: $CATALOG_REL" >&2
    emit_seam UNSOUND_CONDITION chaos.catalog.empty "$CATALOG_REL"
    exit 2
  fi

  # Two entries normalizing to one key make the code->name join LAST-WINS, and
  # the consequence is not a missed finding but a MISDIRECTED one: a citation of
  # the losing code under its OWN name is reported as a mis-citation, so the
  # build fails and the author is told they got it wrong while the real defect
  # -- an ambiguous catalog -- stays silent. A gate that blames the wrong party
  # is worse than one that says nothing, so the ambiguity is named instead.
  local dup
  dup="$(sort "$WORK/names.txt" | uniq -d | head -1)"
  if [[ -n "$dup" ]]; then
    echo "chaos-citation: FATAL -- two catalog entries share the normalized name \"$dup\": $CATALOG_REL" >&2
    emit_seam UNSOUND_CONDITION chaos.catalog.ambiguous_name "$dup"
    exit 2
  fi
}

# --- corpus ------------------------------------------------------------------
# One repository-relative path per line.
#
# specs/TEMPLATE/ IS EXCLUDED HERE, BY CONSTRUCTION (AC-4 / DEC-005). The
# template's CP-NN citations are illustrative placeholders -- documentation, not
# citations. The exclusion is a property of THIS FUNCTION, not a ledger entry a
# later change could quietly widen: PROD_CADENCE-020 records a blanket exemption
# blinding a citation sweep to the very writes it should have caught, and this
# gate refuses to ship that shape. The exclusion is filtered on one side and
# VERIFIED on the other (see the guard below), so a breach is loud rather than
# silent.
#
# busybox find (the CI image carries no findutils): -name and -type are used,
# -printf is not. Verified by running the CI base image, not by reasoning about
# flag support.
enumerate_corpus() {
  ( cd "$ROOT" && find specs archive -name test-plan.md -type f 2>/dev/null ) \
    | sed 's#^\./##' \
    | grep -v '^specs/TEMPLATE/' \
    | sort > "$WORK/corpus.txt"

  # VERIFY the exclusion held, independently of the filter that applied it. The
  # filter is anchored at the tree root; this check is unanchored, so a TEMPLATE
  # path reachable by some other route is caught rather than quietly scanned. A
  # check written as the mirror image of its own filter can only ever agree with
  # it, which is how an exclusion goes blind (PROD_CADENCE-020).
  if grep -q 'specs/TEMPLATE/' "$WORK/corpus.txt"; then
    echo "chaos-citation: FATAL -- a specs/TEMPLATE/ path entered the scan corpus" >&2
    emit_seam BOUNDARY_FAULT chaos.scope.template_included \
      "$(grep -m1 'specs/TEMPLATE/' "$WORK/corpus.txt")"
    exit 2
  fi
}

# --- pass 1: existence (AC-1a) -----------------------------------------------
# Scanned ONE FILE AT A TIME, deliberately, so grep's exit status stays legible.
# Batched through xargs the statuses collapse: "no match anywhere" (grep 1) and
# "could not read a file" (grep 2) both surface as a single 123, and the gate
# would have to guess which happened. Guessing here means reporting a clean
# verdict over a file it never read -- the DELTA_AUDIT_GAP this seam exists to
# close. Per file: 0 = matches, 1 = no match (legitimate), >1 = the scan failed.
#
# The cost is one grep per corpus file (146 today) on a runner that already
# carries 22 rows; measured at well under a second for the full corpus.
#
# `-a` IS LOAD-BEARING, on both passes. A corpus file holding a NUL byte is
# classified binary, and the status guard above cannot see what follows: GNU grep
# prints "binary file matches" and EXITS 0, so `rc -gt 1` never fires, the file's
# citations are dropped, and it is still counted in the scanned total -- a
# vacuous pass wearing the audit trail of a real one (JI-2; the CP-06 "never a
# silent skip" expectation). `-a` reads every file as text, so the citations are
# scanned and the verdict no longer depends on which grep is installed.
#
# MEASURED, not reasoned about -- BTG-200 AC-4: `docker run alpine:latest` with
# the package list the then-current CI manifest installed (bash diffutils gawk
# grep sed coreutils; that manifest is now deleted, the measurement is not),
# against a corpus file carrying a dangling code followed by NUL bytes:
#   * that package set puts GNU grep 3.12 at /bin/grep, so CI hits the GNU
#     "binary file matches" + exit 0 case above -- this was a live CI-affecting
#     vacuous pass, not a theoretical one;
#   * busybox grep accepts `-a` and its output is byte-identical to GNU's.
# Do not restate an exit code for any other grep build here without re-running
# it: a flavour claim that cannot be reproduced is the defect this comment
# exists to prevent.
scan_codes() {
  : > "$WORK/hits.txt"
  [[ -s "$WORK/corpus.txt" ]] || return 0
  local f rc
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    ( cd "$ROOT" && grep -aHonE '\bCP-[0-9]+\b' "$f" ) >> "$WORK/hits.txt"
    rc=$?
    if [[ $rc -gt 1 ]]; then
      echo "chaos-citation: FATAL -- the corpus scan failed on $f (grep exit $rc)" >&2
      emit_seam DELTA_AUDIT_GAP chaos.scan.failed "$f"
      exit 2
    fi
  done < "$WORK/corpus.txt"
}

# --- pass 2: label consistency (AC-1b) ---------------------------------------
# Reports a citation whose parenthetical, normalized, is EXACTLY some catalog
# entry's canonical name while the code it is attached to is a DIFFERENT entry.
#
# This is pure set membership against the catalog's OWN names. There is no
# threshold, no Title-Case heuristic and no word-overlap scoring, so the many
# legitimate contextual glosses in the corpus are untouched BY CONSTRUCTION
# rather than by tuning. The broad "any name-shaped label" rule was measured,
# rejected as spec.md Alternative 3, and ships as limitation L-5.
#
# normalize(): lowercase; every run of non-alphanumerics to a single space;
# trimmed. That is what makes a lower-case, punctuation-stripped rendering of a
# canonical name match the name it renders -- the shape the live corpus carries.
scan_labels() {
  : > "$WORK/labels.txt"
  [[ -s "$WORK/corpus.txt" ]] || return 0
  local f rc
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    ( cd "$ROOT" && grep -aHonE '\bCP-[0-9]+ \([^)]*\)' "$f" ) >> "$WORK/labels.txt"
    rc=$?
    if [[ $rc -gt 1 ]]; then
      echo "chaos-citation: FATAL -- the label scan failed on $f (grep exit $rc)" >&2
      emit_seam DELTA_AUDIT_GAP chaos.scan.failed "$f"
      exit 2
    fi
  done < "$WORK/corpus.txt"

  awk -F: -v catalog="$WORK/catalog.tsv" '
    function normalize(s) {
      s = tolower(s); gsub(/[^a-z0-9]+/, " ", s); gsub(/^ +| +$/, "", s); return s
    }
    BEGIN {
      FS = ":"
      while ((getline line < catalog) > 0) {
        split(line, p, "\t")
        # A blank name is skipped, not stored under the "" key -- otherwise a
        # `CP-NN ()` parenthetical would normalize to "" and collide with it.
        # load_catalog validates the SAME filtered set, so the guard there and
        # the map built here describe one thing rather than two.
        k = normalize(p[2])
        if (k == "") continue
        owner[k] = p[1]
        canonical[k] = p[2]
      }
    }
    {
      path = $0; sub(/:[^:]*:.*$/, "", path)
      lineno = $0; sub(/^[^:]*:/, "", lineno); sub(/:.*$/, "", lineno)
      rest = $0; sub(/^[^:]*:[^:]*:/, "", rest)
      code = rest; sub(/ .*/, "", code)
      label = rest; sub(/^[^(]*\(/, "", label); sub(/\)$/, "", label)
      n = normalize(label)
      if (n in owner && owner[n] != code)
        print path ":" lineno ":" code ":" n ":" owner[n] ":" canonical[n]
    }
  ' "$WORK/labels.txt" > "$WORK/collisions.txt"
}

# --- main --------------------------------------------------------------------
load_catalog
enumerate_corpus
scan_codes
scan_labels

# The code set is loaded with getline, NOT with the two-file NR==FNR idiom. With
# an EMPTY first file awk never reads a record from it, so NR==FNR then holds for
# the SECOND file and every hit is silently absorbed as a key -- the gate would
# report a clean verdict over a catalog it failed to parse. That is the exact
# vacuous pass this gate exists to prevent, so the join must not depend on the
# first file being non-empty.
#
# Fields are taken from the END of the record ($NF, $(NF-1)): grep -Hon prints
# `path:line:match`, and only the path can itself contain a colon.
awk -F: -v codes="$WORK/codes.txt" '
  BEGIN { while ((getline c < codes) > 0) known[c] = 1 }
  !($NF in known) { path = $0; sub(/:[^:]*:[^:]*$/, "", path); print path ":" $(NF-1) ":" $NF }
' "$WORK/hits.txt" > "$WORK/dangling.txt"

files=$(wc -l < "$WORK/corpus.txt" | tr -d ' ')

violations=0
warnings=0

# scope_of <path> -> specs | archive
# DEC-012: `specs/` is live work and hard-fails; `archive/` is a FROZEN RECORD
# and is report-only. Backfilling archived artifacts is out of scope
# (problem.md, "Out of Scope"), so failing on them would demand a remediation
# this ticket is not allowed to perform. The seam fires in BOTH scopes -- the
# scope changes the VERDICT, never the observability.
scope_of() {
  case "$1" in
    archive/*) echo archive ;;
    *)         echo specs ;;
  esac
}

# report_hit <path> <line> <event> <detail>
report_hit() {
  local path="$1" line="$2" event="$3" detail="$4" scope
  scope="$(scope_of "$path")"
  if [[ "$scope" == archive ]]; then
    echo "WARN $path:$line: $detail (archived record -- reported, not blocking)"
    warnings=$((warnings + 1))
  else
    echo "FAIL $path:$line: $detail"
    violations=$((violations + 1))
  fi
  emit_seam LOGIC_FAULT "$event" "$path:$line"
}

echo "=== chaos-citation gate: CP-NN citations vs $CATALOG_REL ==="
while IFS=: read -r path line code; do
  report_hit "$path" "$line" chaos.citation.unknown_profile \
    "$code is not a profile in the catalog"
done < "$WORK/dangling.txt"
while IFS=: read -r path line code norm owner canon; do
  report_hit "$path" "$line" chaos.citation.name_mismatch \
    "label \"$norm\" is $owner's canonical name ($canon), but the citation is $code"
done < "$WORK/collisions.txt"
echo "chaos-citation: $files $(plural "$files" file) scanned, $violations $(plural "$violations" violation), $warnings $(plural "$warnings" warning)"

[ "$violations" -eq 0 ] || exit 1
exit 0
