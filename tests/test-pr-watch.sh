#!/usr/bin/env bash
# Offline regression suite for /cadence-watch (pr_watch.py & watch_sources.py).
set -euo pipefail
unset BASH_ENV

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WATCH_PY="$ROOT/skills/cadence-watch/scripts/pr_watch.py"
TMP="$(mktemp -d)"
SRV_PID=""
cleanup() {
  [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

bash "$ROOT/tests/fixtures/build_cadence_fixture.sh" "$TMP" >/dev/null
mkdir -p "$TMP/bin" "$TMP/mock_data" "$TMP/ws"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
DATA="${MOCK_GH_DIR:?}"
if [[ "$1 $2" == "pr view" ]]; then
  pr="${3##*/}"
  cat "$DATA/pr_${pr}.json"
elif [[ "$1" == "api" ]]; then
  pr="$(echo "$2" | sed -n 's|.*/pulls/\([0-9]*\)/comments|\1|p')"
  if [[ -f "$DATA/inline_${pr}.json" ]]; then
    cat "$DATA/inline_${pr}.json"
  else
    echo "[]"
  fi
fi
SH
cat > "$TMP/bin/glab" <<'SH'
#!/usr/bin/env bash
DATA="${MOCK_GL_DIR:?}"
if [[ "$1 $2" == "mr view" ]]; then
  mr="${3##*/}"
  cat "$DATA/mr_${mr}.json"
elif [[ "$1" == "api" ]]; then
  mr="$(echo "$2" | sed -n 's|.*/merge_requests/\([0-9]*\)/discussions|\1|p')"
  cat "${DATA}/disc_${mr}.json"
fi
SH
chmod +x "$TMP/bin/gh" "$TMP/bin/glab"
export MOCK_GH_DIR="$TMP/mock_data" MOCK_GL_DIR="$TMP/mock_data"

pw() { python3 -B "$WATCH_PY" "$@" --repo-root "$TMP" --state-dir "$TMP/ws"; }

# 1. GitHub spec_mr MERGED -> cadence-build (resolves integration_branch=trunk)
cat > "$TMP/mock_data/pr_77.json" <<'JSON'
{"number":77,"url":"https://github.com/acme/repo/pull/77","state":"MERGED","isDraft":false,"reviewDecision":"APPROVED","headRefName":"spec/high/ACME-106","headRefOid":"sha77","baseRefName":"trunk","mergedAt":"2026-11-19T10:00:00Z","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
out1="$(pw ACME-106)"
grep -q '^integration_branch=trunk$' <<<"$out1"
grep -q '^pr_kind=spec_mr$' <<<"$out1"
grep -q '^event=merged$' <<<"$out1"
grep -q '^next_action=cadence-build$' <<<"$out1"

# 2. GitHub merge_request MERGED -> cadence-archive
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"MERGED","isDraft":false,"reviewDecision":"APPROVED","headRefName":"impl/feat/ACME-112","headRefOid":"sha88","baseRefName":"trunk","mergedAt":"2026-11-19T10:00:00Z","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
out2="$(pw ACME-112)"
grep -q '^pr_kind=merge_request$' <<<"$out2"
grep -q '^event=merged$' <<<"$out2"
grep -q '^next_action=cadence-archive$' <<<"$out2"

# 3. CHANGES_REQUESTED + inline comments + --ack + TOCTOU mid-flight comment + reply suppression
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"OPEN","isDraft":false,"reviewDecision":"CHANGES_REQUESTED","headRefName":"impl/feat/ACME-112","headRefOid":"sha88a","baseRefName":"trunk","reviews":[{"id":"rev1","author":{"login":"bob"},"state":"CHANGES_REQUESTED","body":"Fix boundary","submittedAt":"2026-11-19T10:00:00Z"}],"comments":[{"id":"c_self","author":{"login":"bot"},"body":"Fixed\n<!-- cadence-watch:reply for=rev1 -->","createdAt":"2026-11-19T10:02:00Z"}],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
cat > "$TMP/mock_data/inline_88.json" <<'JSON'
[{"id":601,"user":{"login":"bob"},"body":"Guard nil","path":"src/x.py","line":9,"created_at":"2026-11-19T10:01:00Z"}]
JSON
out3="$(pw ACME-112 --write-snapshot "$TMP/s3.json")"
grep -q '^event=changes_requested$' <<<"$out3"
grep -q '^next_action=remediate_impl$' <<<"$out3"
grep -q '^new_pr_comment_count=0$' <<<"$out3"
grep -q '^new_inline_comment_count=1$' <<<"$out3"
pw --ack ACME-112 --from-snapshot "$TMP/s3.json" >/dev/null
pw ACME-112 | grep -q '^event=idle$'
cat > "$TMP/mock_data/inline_88.json" <<'JSON'
[{"id":601,"user":{"login":"bob"},"body":"Guard nil","path":"src/x.py","line":9},{"id":602,"user":{"login":"alice"},"body":"Log warning too","path":"src/x.py","line":14}]
JSON
out3b="$(pw ACME-112)"
grep -q '^event=comments_new$' <<<"$out3b"
grep -q '^item=github_inline:602:alice:src/x.py:14:Log warning too$' <<<"$out3b"

# 4. APPROVED -> cadence-close (merge_request) & await_human_merge (spec_mr)
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","headRefName":"impl/feat/ACME-112","headRefOid":"sha88b","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
cat > "$TMP/mock_data/inline_88.json" <<'JSON'
[]
JSON
pw ACME-112 | grep -q '^event=approved$'
pw ACME-112 | grep -q '^next_action=cadence-close$'
cat > "$TMP/mock_data/pr_77.json" <<'JSON'
{"number":77,"url":"https://github.com/acme/repo/pull/77","state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","headRefName":"spec/high/ACME-106","headRefOid":"sha77b","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
pw ACME-106 | grep -q '^next_action=await_human_merge$'

# 5. CLOSED unmerged -> halt_human_rejected
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"CLOSED","isDraft":false,"reviewDecision":"","headRefName":"impl/feat/ACME-112","headRefOid":"sha88b","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[]}
JSON
pw ACME-112 | grep -q '^event=closed_unmerged$'
pw ACME-112 | grep -q '^next_action=halt_human_rejected$'

# 6. ci_failed -> remediate_ci, ack -> idle
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"OPEN","isDraft":false,"reviewDecision":"","headRefName":"impl/feat/ACME-112","headRefOid":"sha88c","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"FAILURE"}]}
JSON
pw ACME-112 --write-snapshot "$TMP/s6.json" | grep -q '^event=ci_failed$'
pw --ack ACME-112 --from-snapshot "$TMP/s6.json" >/dev/null
pw ACME-112 | grep -q '^event=idle$'

# 7. GitLab glab (discussions_not_resolved + inline note -> changes_requested; merged -> cadence-archive; closed -> halt_human_rejected)
mkdir -p "$TMP/specs/ACME-301" "$TMP/specs/ACME-302"
printf 'id: ACME-301\ntier: Medium\nstatus: in-review\nmerge_request: "https://gitlab.example.com/acme/repo/-/merge_requests/301"\n' > "$TMP/specs/ACME-301/metadata.yaml"
printf 'id: ACME-302\ntier: Medium\nstatus: in-review\nmerge_request: "https://gitlab.example.com/acme/repo/-/merge_requests/302"\n' > "$TMP/specs/ACME-302/metadata.yaml"
cat > "$TMP/mock_data/mr_301.json" <<'JSON'
{"iid":301,"project_id":5,"web_url":"https://gitlab.example.com/acme/repo/-/merge_requests/301","state":"opened","draft":false,"detailed_merge_status":"discussions_not_resolved","source_branch":"impl/feat/ACME-301","target_branch":"trunk","sha":"gl301","head_pipeline":{"status":"success"}}
JSON
cat > "$TMP/mock_data/disc_301.json" <<'JSON'
[{"notes":[{"id":901,"system":false,"author":{"username":"gl_rev"},"body":"Rename param","position":{"new_path":"app.py","new_line":4},"created_at":"2026-11-19T11:00:00Z"}]}]
JSON
out7="$(pw ACME-301)"
grep -q '^forge=gitlab$' <<<"$out7"
grep -q '^event=changes_requested$' <<<"$out7"
grep -q '^new_inline_comment_count=1$' <<<"$out7"
cat > "$TMP/mock_data/mr_302.json" <<'JSON'
{"iid":302,"project_id":5,"web_url":"https://gitlab.example.com/acme/repo/-/merge_requests/302","state":"merged","draft":false,"source_branch":"impl/feat/ACME-302","target_branch":"trunk","sha":"gl302","head_pipeline":{"status":"success"},"notes":[]}
JSON
pw ACME-302 | grep -q '^next_action=cadence-archive$'

# 8. SourceHut explicit unsupported_forge
mkdir -p "$TMP/specs/ACME-303"
printf 'id: ACME-303\ntier: Low\nstatus: in-review\nmerge_request: "https://lists.sr.ht/~acme/repo-devel/patches/12"\n' > "$TMP/specs/ACME-303/metadata.yaml"
pw ACME-303 | grep -q '^event=unsupported_forge$'

# 9. Jira Server/DC + YouTrack Server HTTP mock, fail-closed unset env, --no-tracker, preservation filter
python3 - "$TMP/docs/agentic-sdlc/CADENCE_ORG.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text(encoding="utf-8").replace(
    "| `*` | None -- inner-source | | | |",
    "| ACME | Jira Server | ACME | /cadence-sync-jira | |\n| YT | YouTrack Server | YT | /cadence-sync-youtrack | |"
), encoding="utf-8")
PY
printf 'jira_url: "https://jira.example.test/browse/ACME-112"\n' >> "$TMP/specs/ACME-112/metadata.yaml"
mkdir -p "$TMP/specs/YT-9"
printf 'id: YT-9\ntier: Low\nstatus: in-review\nmerge_request: "https://github.com/acme/repo/pull/99"\nyoutrack_url: "https://yt.example.test/issue/YT-9"\n' > "$TMP/specs/YT-9/metadata.yaml"
cat > "$TMP/mock_data/pr_99.json" <<'JSON'
{"number":99,"url":"https://github.com/acme/repo/pull/99","state":"OPEN","isDraft":false,"reviewDecision":"","headRefName":"impl/feat/YT-9","headRefOid":"sha99","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[]}
JSON
PORT_FILE="$TMP/port.txt"
python3 -B - "$PORT_FILE" <<'PY' &
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith("/rest/api/2/issue/ACME-112/comment"):
            data = {"comments": [
                {"id": "jp1", "author": {"displayName": "bot"}, "body": "Original intake (as filed)\npreserved on import; the repo now owns the description below", "created": "2026-11-19T08:00:00Z"},
                {"id": "j4", "author": {"displayName": "stakeholder"}, "body": "Add audit field", "created": "2026-11-19T12:00:00Z"}
            ]}
        elif self.path.startswith("/api/issues/YT-9/comments"):
            data = [{"id": "y9", "author": {"login": "lead"}, "text": "Verify timeout path", "created": 5000, "deleted": False}]
        else:
            self.send_response(404); self.end_headers(); return
        b = json.dumps(data).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
SRV_PID=$!
for _ in $(seq 1 40); do [[ -s "$PORT_FILE" ]] && break; sleep 0.05; done
PORT="$(cat "$PORT_FILE")"
! env -u JIRA_BASE_URL -u JIRA_PAT python3 -B "$WATCH_PY" ACME-112 --repo-root "$TMP" --state-dir "$TMP/ws" 2>"$TMP/e9.err"
grep -q 'tracker_env_unset' "$TMP/e9.err"
env -u JIRA_BASE_URL -u JIRA_PAT python3 -B "$WATCH_PY" ACME-112 --no-tracker --repo-root "$TMP" --state-dir "$TMP/ws" | grep -q '^tracker_status=disabled_flag$'
jout="$(JIRA_BASE_URL="http://127.0.0.1:$PORT" JIRA_PAT="tok-jira-99" pw ACME-112)"
grep -q '^event=comments_new$' <<<"$jout"
grep -q '^new_tracker_comment_count=1$' <<<"$jout"
! grep -q 'tok-jira-99' <<<"$jout"
yout="$(YOUTRACK_BASE_URL="http://127.0.0.1:$PORT" YOUTRACK_TOKEN="tok-yt-99" pw YT-9)"
grep -q '^item=youtrack:y9:lead:-:Verify timeout path$' <<<"$yout"

# 10. submission.md dual-watermark dedupe, case mismatch halt, --watch timeout, and --all isolation
cat > "$TMP/mock_data/pr_88.json" <<'JSON'
{"number":88,"url":"https://github.com/acme/repo/pull/88","state":"OPEN","isDraft":false,"reviewDecision":"","headRefName":"impl/feat/ACME-112","headRefOid":"sha88c","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[{"conclusion":"SUCCESS"}]}
JSON
printf '\n### stakeholder\n<!-- cadence-watch:item source=jira id=j4 -->\nAdd audit field\n' >> "$TMP/specs/ACME-112/submission.md"
JIRA_BASE_URL="http://127.0.0.1:$PORT" JIRA_PAT="tok-jira-99" python3 -B "$WATCH_PY" ACME-112 --repo-root "$TMP" --state-dir "$TMP/ws_fresh" | grep -q '^event=idle$'
! pw acme-112 >/dev/null 2>&1
pw ACME-112 --no-tracker --watch --interval 0.03 --timeout 0.08 | grep -q '^event=timeout$'
cat > "$TMP/mock_data/pr_77.json" <<'JSON'
{"number":77,"url":"https://github.com/acme/repo/pull/77","state":"OPEN","isDraft":false,"reviewDecision":"","headRefName":"spec/high/ACME-106","headRefOid":"sha77b","baseRefName":"trunk","reviews":[],"comments":[],"statusCheckRollup":[]}
JSON
all_out="$(JIRA_BASE_URL="http://127.0.0.1:$PORT" JIRA_PAT="tok-jira-99" YOUTRACK_BASE_URL="http://127.0.0.1:$PORT" YOUTRACK_TOKEN="tok-yt-99" pw --all)"
grep -q '^active_tickets=6$' <<<"$all_out"
grep -q 'ticket=YT-9 .*event=comments_new' <<<"$all_out"
! env -u JIRA_BASE_URL -u JIRA_PAT YOUTRACK_BASE_URL="http://127.0.0.1:$PORT" YOUTRACK_TOKEN="tok-yt-99" python3 -B "$WATCH_PY" --all --repo-root "$TMP" --state-dir "$TMP/ws" >"$TMP/all_err.out" 2>"$TMP/all_err.err"
grep -q 'ticket=ACME-112 event=error cause=tracker_env_unset' "$TMP/all_err.out"
grep -q 'ticket=YT-9 .*event=comments_new' "$TMP/all_err.out"

echo "PASS: test-pr-watch (all 10 scenarios)"
