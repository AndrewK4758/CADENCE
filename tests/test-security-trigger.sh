#!/usr/bin/env bash
# Offline regression checks for Option 2B security-trigger.sh & security-auditor parity.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TRIGGER="$ROOT/skills/cadence-review/security-trigger.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$TMP" >/dev/null
git -C "$TMP" checkout -q -b impl/fix/ACME-TRIG

# 1. Trivial tier skips cleanly
bash "$TRIGGER" --root "$TMP" ACME-103 | grep -q "^decision=SKIP tier=trivial "

# 2. High tier triggers unconditionally even with empty diff
bash "$TRIGGER" --root "$TMP" ACME-201 | grep -q "^decision=TRIGGER tier=high "

# 3. Low tier with benign helper skips
mkdir -p "$TMP/specs/ACME-301"
printf 'id: ACME-301\ntier: Low\nstatus: in-review\n' > "$TMP/specs/ACME-301/metadata.yaml"
cat > "$TMP/src/format_helper.py" <<'PY'
def format_cents(cents):
    return f"${cents / 100:.2f}"
PY
git -C "$TMP" add src/format_helper.py specs/ACME-301/metadata.yaml
git -C "$TMP" commit -q -m "benign formatting helper"
out_low_skip="$(bash "$TRIGGER" --root "$TMP" --base trunk ACME-301)"
[[ "$out_low_skip" == "decision=SKIP tier=low signals=none reason=no-risk-signals" ]]

# 4. Medium tier touching auth/concurrency triggers with exact signal names
mkdir -p "$TMP/specs/ACME-302"
printf 'id: ACME-302\ntier: Medium\nstatus: in-review\n' > "$TMP/specs/ACME-302/metadata.yaml"
cat > "$TMP/src/alpha.py" <<'PY'
import fcntl
def verify_jwt_session(token):
    fcntl.flock(0, fcntl.LOCK_EX)
    return bool(token)
PY
out_med_trig="$(bash "$TRIGGER" --root "$TMP" --base trunk ACME-302)"
[[ "$out_med_trig" == decision=TRIGGER\ tier=medium* ]]
[[ "$out_med_trig" == *"auth"* ]]
[[ "$out_med_trig" == *"concurrency"* ]]

# 5. Deleted auth/flock line in Low tier ALSO triggers (caught removal of security guard)
git -C "$TMP" commit -am "commit auth helper" -q
cat > "$TMP/src/alpha.py" <<'PY'
def compute_total(items):
    return len(items)
PY
git -C "$TMP" commit -am "remove auth helper" -q
out_del_trig="$(bash "$TRIGGER" --root "$TMP" --base HEAD~1 ACME-301)"
[[ "$out_del_trig" == decision=TRIGGER\ tier=low*auth* ]]
[[ "$out_del_trig" == *"concurrency"* ]]

# 6. docs/ prose-only change under Medium tier does NOT false-trigger
git -C "$TMP" checkout -q -b impl/docs/ACME-DOC trunk
mkdir -p "$TMP/specs/ACME-303" "$TMP/docs"
printf 'id: ACME-303\ntier: Medium\nstatus: in-review\n' > "$TMP/specs/ACME-303/metadata.yaml"
echo "Auth OAuth JWT flock SQL SELECT * FROM users" > "$TMP/docs/notes.md"
bash "$TRIGGER" --root "$TMP" --base trunk ACME-303 | grep -q "^decision=SKIP tier=medium signals=none"

# 7. Fail-closed on empty/unrecognized tier or invalid --base
mkdir -p "$TMP/specs/ACME-304"
printf 'id: ACME-304\ntier: ""\nstatus: in-review\n' > "$TMP/specs/ACME-304/metadata.yaml"
! bash "$TRIGGER" --root "$TMP" ACME-304 >/dev/null 2>&1
printf 'id: ACME-304\ntier: invalid\nstatus: in-review\n' > "$TMP/specs/ACME-304/metadata.yaml"
! bash "$TRIGGER" --root "$TMP" ACME-304 >/dev/null 2>&1
! bash "$TRIGGER" --root "$TMP" --base nonexistent-ref ACME-301 >/dev/null 2>&1
