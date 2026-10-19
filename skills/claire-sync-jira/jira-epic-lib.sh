#!/usr/bin/env bash
#
# jira-epic-lib.sh -- the `type: epic` FORK, as one shared implementation.
#
# Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075).
# Invariant relied on from outside this boundary (BTG-036): Jira Server/DC
# FORBIDS an Epic from carrying an Epic Link. A `type: epic` ticket that already
# carries one therefore CANNOT be typed `Epic`; it takes the umbrella branch and
# is typed as the instance's plain issue type instead.
#
# Why this is a library rather than a step. The fork decides the issue's TYPE, so
# it must be resolved BEFORE the type is written -- the deleted design put it at
# step 3 for exactly that reason. Two scripts need the answer: `jira-write-issue.sh`,
# which is the sole writer of `issuetype`/`summary`, and `jira-epic.sh`, which
# writes the umbrella's child links. Re-deriving it in each is how an umbrella
# came to be typed `Epic` at step 4 and re-typed back at step 9, oscillating on
# every run. One implementation, two callers -- the same structural answer
# `js_link_upsert_ordered` gives the ordered-link calibration.
#
# It is SOURCED, never invoked. Everything it OWNS is discovery -- reads only --
# with exactly ONE exception, `js_epic_child_associate`, which owns the child
# branch's single Epic Link write. That exception is disclosed here rather than
# left for a reader to discover: it landed by relocation under the 400-line DX
# ceiling (seventh review, BL-C4), on the DEC-057 precedent. It never writes
# `metadata.yaml`, and neither does anything else here (AC-6).
#
# Contract:
#   js_epic_link_field           -> JS_EPIC_LINK_FIELD (the per-instance id)
#   js_epic_branch <issue-key>   -> JS_EPIC_BRANCH  = single-level|umbrella
#                                   JS_EPIC_E       = the top-level Epic key
#                                                     (umbrella branch only)
#   js_epic_write_plan / js_epic_ac_skip_exit -- step 4's TWO epic early exits.
#                                   Both emit step 4's five-key payload on their
#                                   caller's stdout and exit 0; they live side by
#                                   side because splitting them across two files
#                                   is how the two payloads would drift apart.
#   js_epic_child_associate      -- the CHILD branch's Epic Link write, emitting
#                                   jira-epic.sh's `epic_result` payload and
#                                   exiting 0 on every outcome (DEC-033).
# Both return 0 on a resolved answer and non-zero when the instance could not be
# read. A non-zero return is NEVER a branch: the caller reports and refuses to
# mutate, because promoting on a failed read is a guess (Behavior 5).

# js_epic_link_field -- discover the Epic Link custom field's id BY EXACT NAME.
# The id is plugin-provided and varies per instance, so a hardcoded
# `customfield_10001` silently writes into whatever unrelated field holds that id
# elsewhere. Zero matches and more than one both resolve to "unreadable", never to
# a best guess at which field an adopter means.
js_epic_link_field() {
  local field_name
  JS_EPIC_LINK_FIELD=""
  field_name="$(js_config_map link_relations epic_link_field_name)" || return "$JS_EXIT_CONFIG"
  if ! js_rest GET "/rest/api/2/field" || ! js_http_ok; then
    js_report syncjs.umbrella.epic_link_unreadable \
      "the field discovery read failed (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the Epic Link field id is never guessed"
    return 1
  fi
  JS_EPIC_LINK_FIELD="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$field_name" \
    'if type=="array" then (map(select(.name == $n)) | if length == 1 then .[0].id else empty end) else empty end' 2>/dev/null)"
  if [[ -z "$JS_EPIC_LINK_FIELD" ]]; then
    # "This instance HAS no Epic Link field" is not the same answer as "I could
    # not look", and only the second is unknowable. If the field does not exist
    # here then no issue can carry one, so no umbrella can exist either and the
    # single-level branch is a FACT about the instance rather than a guess.
    # Collapsing the two made every `type: epic` ticket halt on an instance
    # without the Agile plugin -- a projection this adapter is perfectly able to
    # perform.
    js_report syncjs.epic.link_field_absent \
      "no unambiguous '$field_name' field on this instance -- no issue here can carry an Epic Link, so this is the single-level Epic projection (never a guess at an umbrella)"
    return 2
  fi
  return 0
}

# js_epic_branch <issue-key> -- THE GATE. The two branches are mutually exclusive
# and gated SOLELY on the ticket's OWN LIVE Epic Link, read once:
#   empty/absent -> single-level  (issuetype = Epic, Epic Name = Summary)
#   populated    -> umbrella      (issuetype = the plain type; E = that value)
# Gating on `decomposed_into` instead sends a REAL Epic-on-Epic down the child
# path, which writes the forbidden field, takes a 400, and silently never lands
# the decomposition lineage.
js_epic_branch() {
  local issue_key="$1"
  JS_EPIC_BRANCH=""
  JS_EPIC_E=""
  js_epic_link_field
  case "$?" in
    0) ;;
    2) JS_EPIC_BRANCH=single-level; return 0 ;;   # the field does not exist here
    *) return 1 ;;                                # the read failed -- unknowable
  esac
  if ! js_rest GET "/rest/api/2/issue/$issue_key?fields=$JS_EPIC_LINK_FIELD" || ! js_http_ok; then
    js_report syncjs.umbrella.epic_link_unreadable \
      "$issue_key's own Epic Link could not be read (HTTP ${JS_HTTP_STATUS:-unreachable}) -- E is never guessed"
    return 1
  fi
  JS_EPIC_E="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg f "$JS_EPIC_LINK_FIELD" '.fields[$f] // ""' 2>/dev/null)"
  if [[ -z "$JS_EPIC_E" || "$JS_EPIC_E" == "null" ]]; then
    JS_EPIC_E=""
    JS_EPIC_BRANCH=single-level
  else
    JS_EPIC_BRANCH=umbrella
  fi
  return 0
}

# js_umbrella_summary <ticket-title> -- the umbrella summary, STRIP-THEN-PREPEND.
# The target is recomputed from the REPO title every sync and never appended to
# the live summary, so the prefix is single BY CONSTRUCTION: a re-sync writes an
# identical value, and a live summary a prior buggy run left doubly prefixed
# collapses back to exactly one. Prints nothing (rc 1) for an empty title, so a
# caller never writes a bare "[UMBRELLA] " and never guesses a title.
JS_UMBRELLA_PREFIX="[UMBRELLA] "
js_umbrella_summary() {
  local title="$1"
  title="$(printf '%s' "$title" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  while [[ "$title" == "$JS_UMBRELLA_PREFIX"* ]]; do
    title="${title#"$JS_UMBRELLA_PREFIX"}"
    title="$(printf '%s' "$title" | sed 's/^[[:space:]]*//')"
  done
  [[ -n "$title" ]] || return 1
  printf '%s%s\n' "$JS_UMBRELLA_PREFIX" "$title"
}

# js_epic_write_plan <ticket> <mode> <issue-key> -- the step-4 half of the fork.
# Returns 0 for a SINGLE-LEVEL epic, having set EPIC_NAME_FIELD in the caller. For
# an UMBRELLA it emits step 4's payload and EXITS -- step 4 must not write at all. HALTS the ticket
# when the branch cannot be READ -- every field step 4 writes for an epic depends
# on the answer, so there is no partial write to fall back on, and promoting on a
# failed read writes the state Jira forbids.
js_epic_write_plan() {
  local ticket="$1" mode="$2" issue_key="$3" base="${4:-}"
  EPIC_NAME_FIELD=""
  # On CREATE there is no live issue and therefore no Epic Link: the branch is
  # single-level by construction and costs no call.
  if [[ "$mode" == "create" ]]; then
    JS_EPIC_BRANCH=single-level
  elif ! js_epic_branch "$issue_key"; then
    js_halt "$JS_EXIT_FAIL" syncjs.umbrella.epic_link_unreadable \
      "$ticket is type 'epic' but its live Epic Link could not be read -- refusing to write an issue type on a guess (an Epic carrying an Epic Link is a state Jira forbids); NO write was issued, re-run once the instance is readable"
  fi
  if [[ "$JS_EPIC_BRANCH" == "umbrella" ]]; then
    # The umbrella's type (`Issue`, never `Epic`), its `[UMBRELLA] ` summary and
    # its child decomposition are ONE live-verified sequence owned by
    # jira-epic.sh (BTG-036). What step 4 must not do is type it `Epic` on the
    # way past: Jira either rejects that (400 at a BLOCKING step, so the whole
    # restored lineage never fires) or accepts it, and the issue then oscillates
    # `Issue -> Epic -> Issue` with its summary flipping on every run.
    js_report syncjs.umbrella.write_deferred \
      "$ticket carries Epic Link $JS_EPIC_E, so it is an UMBRELLA and is NOT typed 'Epic' here -- its type, its '[UMBRELLA] ' summary and its child decomposition are jira-epic.sh's (BTG-036); this step issues no write"
    js_emit issue_key "$issue_key"
    js_emit jira_url "$base/browse/$issue_key"
    js_emit estimate_result none
    js_emit epic_branch umbrella
    js_emit ac_result skipped-epic
    exit "$JS_EXIT_OK"
  fi
  # The single-level Epic. On an instance with the Agile plugin the Epic Name
  # field is REQUIRED on the Epic create screen, so a create without it is
  # rejected 400. Discovered BY NAME (per-instance id), never hardcoded.
  local epic_name_name
  epic_name_name="$(js_config_map link_relations epic_name_field_name)" || epic_name_name=""
  if [[ -n "$epic_name_name" ]] && js_rest GET "/rest/api/2/field" && js_http_ok; then
    EPIC_NAME_FIELD="$(printf '%s' "$JS_HTTP_BODY" | jq -r --arg n "$epic_name_name" \
      'if type=="array" then (map(select(.name == $n)) | if length == 1 then .[0].id else empty end) else empty end' 2>/dev/null)"
  fi
  if [[ -z "$EPIC_NAME_FIELD" && "$mode" == "create" ]]; then
    js_halt "$JS_EXIT_FAIL" syncjs.epic.name_field_unresolved \
      "no unambiguous '$epic_name_name' field on this instance -- an Epic create without it is rejected 400 by the Agile plugin; refusing to fire a doomed create"
  fi
  return 0
}

# js_epic_ac_skip_exit <ticket> <issue-key> <base> <estimate-result>
#
# Step 4's OTHER epic early exit, kept beside the umbrella one above because the
# two emit the SAME five-key payload and are the only two places step 4 leaves
# early. BTG-046/BTG-040: an Epic has no acceptance criteria of its own -- the
# children carry them -- so the field is skipped ENTIRELY rather than written
# empty, which would clear whatever a human put there.
js_epic_ac_skip_exit() {
  local ticket="$1" issue_key="$2" base="$3" estimate_result="$4"
  js_report syncjs.ac.skipped_epic "$ticket is an Epic -- the acceptance-criteria field is not projected (its children carry them)"
  js_emit issue_key "$issue_key"
  js_emit jira_url "${base%/}/browse/$issue_key"
  js_emit estimate_result "$estimate_result"
  # the resolved fork, so the run report names which branch this epic took and
  # the orchestrator never has to infer it from the issue type it sees
  js_emit epic_branch single-level
  js_emit ac_result skipped-epic
  exit "$JS_EXIT_OK"
}

# js_epic_child_associate <issue-key> <field-id> <field-name> <parent-key>
#
# The CHILD branch's ONE write: this issue's own Epic Link <- its Epic parent.
# It lives here for the reason DEC-057 relocated step 4's early exits -- the
# 400-line DX ceiling -- and it is the only place this library mutates anything.
# Emits jira-epic.sh's `epic_result` payload and exits 0 on EVERY outcome: a
# best-effort step halts its BRANCH, never the ticket (DEC-033).
#
# The body is STAGED, and a failed `mktemp` REFUSES the write rather than
# degrading into one. `js_rest`'s `[[ -n "$body_file" ]]` omits both
# `--data-binary` AND the `Content-Type` header when the path is empty, so an
# unstaged body goes out as a BODYLESS PUT -- which a permissive server accepts,
# leaving the Epic Link unset while the run reports `associated`. That is
# DEC-057's hazard verbatim, on the same `PUT /rest/api/2/issue/{key}`.
#
# The build is then checked TWICE, because the two probes answer DIFFERENT
# questions and only the pair is a check (BTG-079 AC-1): `jq`'s own EXIT STATUS,
# and the file's content. `|| :` discarded the status and left the emptiness probe
# standing in for it -- but a jq that dies mid-write leaves a TRUNCATED, NON-EMPTY
# file, so the proxy answers "built" and a MALFORMED body is PUT under
# `epic_result=associated` (`{"fields": {` was observed reaching the wire). An
# EMPTY file is the same lost write through the other door -- the shape
# `jira-write-issue.sh` guards with `syncjs.write.body_unbuildable`. jq's own
# stderr stays out of the channel DEC-001 reserves for `syncjs.*` conditions.
#
# It installs NO `trap ... EXIT`, deliberately (BTG-079 AC-3). Bash keeps exactly
# ONE EXIT trap per shell, so a trap armed from inside a SOURCED library function
# REPLACES its caller's rather than adding to it -- `jira-write-issue.sh` arms
# `trap js_cleanup EXIT`, the AC-4 tempfile-lifecycle guarantee S-4.3 exists to
# prove, and a caller that armed one and then called this would silently lose its
# description-tempfile unlink. That was latent, not live (that script never calls
# this function, and `jira-epic.sh`'s own trap sits on the mutually-exclusive
# UMBRELLA branch), but this header advertises the function as a general entry
# point, so the hazard is REMOVED rather than merely written down: every exit is
# inside this function, so unlinking at each one does exactly what the trap did and
# touches nobody else's.
js_epic_child_associate() {
  local issue_key="$1" field_id="$2" field_name="$3" parent_key="$4"
  JS_EPIC_BODY_FILE=""
  if ! JS_EPIC_BODY_FILE="$(mktemp 2>/dev/null)"; then
    js_report syncjs.epic.scratch_unavailable \
      "no scratch file could be created for $issue_key's Epic Link body -- issuing NO write; an unstaged body degrades the PUT into a BODYLESS one that a permissive server accepts, leaving the field unset while the run reports success"
    js_emit epic_result rejected
    exit "$JS_EXIT_OK"
  fi
  # The reference implementation of this pattern, now expressed through the ONE
  # builder it seeded (BTG-084 DEC-004): message-preserving, token unchanged.
  if ! js_build_body "$JS_EPIC_BODY_FILE" syncjs.epic.body_unbuildable "the Epic Link body for $issue_key" \
       -n --arg f "$field_id" --arg v "$parent_key" '{fields: {($f): $v}}'; then
    rm -f "$JS_EPIC_BODY_FILE" 2>/dev/null
    js_emit epic_result rejected
    exit "$JS_EXIT_OK"
  fi
  if ! js_rest PUT "/rest/api/2/issue/$issue_key" "$JS_EPIC_BODY_FILE" || ! js_http_ok; then
    js_report syncjs.epic.rejected \
      "setting $issue_key's Epic Link to $parent_key was rejected (HTTP ${JS_HTTP_STATUS:-unreachable}) -- the sync continues"
    rm -f "$JS_EPIC_BODY_FILE" 2>/dev/null
    js_emit epic_result rejected
    exit "$JS_EXIT_OK"
  fi
  rm -f "$JS_EPIC_BODY_FILE" 2>/dev/null
  js_report syncjs.epic.associated "$issue_key associated with Epic $parent_key via '$field_name' ($field_id)"
  js_emit epic_result associated
  exit "$JS_EXIT_OK"
}
