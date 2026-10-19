# `/cadence-sync-jira` — script contracts: deterministic markup rendering

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-205).
Boundary invariant: matches its sibling
`.agents/skills/cadence-sync-jira/jira-server-scripts.md` — the repository (`metadata.yaml` +
`problem.md`) is the source of truth; Jira is the projection layer, and every script communicates on
exactly three channels (stdout, stderr `syncjs.*`, exit code).

**This file is a further part of one unified index, not another independent index.** BTG-205 split it off because
`jira-server-scripts.md` stood at **399** lines against a `-lt 400` ceiling — zero headroom — so the
new contract had nowhere to land in place. The record is **split, never truncated**: the same
pillar-tension resolution BTG-102 applied to the condition catalogue, BTG-105 to the umbrella entries,
BTG-168 to the screen-availability concern, and BTG-173 to the issue-type entry (C-3: Operability
outranks Agentic DX on *content*; DX is served by file placement instead).
`btg-075-script-contract.test.sh`'s `js_index_view` merges every `jira-server-scripts-*.md` into the
primary before each lookup, so a split cannot hide a missing contract entry.

Its reported conditions are catalogued in
`.agents/skills/cadence-sync-jira/jira-server-conditions-render.md`.

---

## The division of labour inside `render_ticket_template` (BTG-205 DEC-001)

`render_ticket_template` is **agent-performed**, and remains so. BTG-150 established that deliberately,
and its call-site shape is preserved: the orchestration's
`render_description_tempfile` snippet
(`.agents/skills/cadence-sync-jira/jira-server-orchestration.md`, section 4) calls it as a shell function,
and that snippet is **unchanged**.

What BTG-205 refines is what happens *inside* it. The framework maintainer resolved the question
directly: *"the intent is for the model to generate the content, but formatting that content for Jira
wiki should be a deterministic process."* Thus the step splits along an axis BTG-150 previously conflated:

| Axis | Who performs it | Status |
|---|---|---|
| **Content authorship** — which `problem.md` section fills which `{{token}}`, what prose is carried, what counts as absent | the **model** | **UPHELD**, unchanged from BTG-150 |
| **Markup conversion** — turning an already-selected Markdown fragment into Jira wiki markup | **`jira-md2wiki.sh`**, deterministically | **SUPERSEDED for this step only** |

Concretely, `render_ticket_template` MUST:

1. Extract each `{{token}}`'s source fragment from `problem.md` / `metadata.yaml`, following the
   *Token sources* table of `.agents/skills/cadence-sync-jira/ticket_TEMPLATE.md`. **Unchanged —
   this is authorship.**
2. **Pipe every extracted Markdown fragment through `jira-md2wiki.sh`** before substituting it. The
   `{{functional_validation}}` fragment is piped with `--functional-validation`, which applies that
   token's both-polarity NOT-SPECIFIED guard mechanically instead of relying on prose interpretation.
3. Substitute the converted results into the template body.

**The template body itself is NEVER passed through the filter.** It is already Jira wiki markup and a
second pass would corrupt it. Only `{{token}}` values are converted.

A fragment that converts to nothing yields an **empty** token value, not a blank line; apply that
token's *If missing* rule to it exactly as if the section had been absent.

---

### jira-md2wiki.sh

| Field | Value |
|---|---|
| **Operation/step** | Projection, step 4 sub-step — convert **one already-selected** Markdown fragment to Jira Server/DC wiki markup. It is a **filter**, not an operation: it takes no ticket id and no issue key, and it decides nothing about *what* the description says |
| **What it does** | Applies the *Rendering rules* of `.agents/skills/cadence-sync-jira/ticket_TEMPLATE.md` mechanically, in a fixed and non-commutative pass order: (1) strip `<!-- … -->` HTML comments outside fenced code; (2) segment into blocks — fenced code, heading, table, list, blockquote, paragraph; (3) strip `> **Probe:**` openers **together with every contiguous `>` continuation line**, because stripping only the opener strands the answer body as loose prose; (4) unwrap each list item onto ONE line, since wiki markup ends an item at the newline; (5) unwrap hard-wrapped paragraphs, and **only** paragraphs — never a list, table, or code block; (6) convert tables structurally, promoting the header row to doubled pipes **only when a separator row identifies it** and dropping that separator; (7) emit a kept blockquote as a `{quote}` macro and **recurse** on the inner text, which terminates because the prefix is removed before the call; (8) run inline conversions last over the assembled line, which ensures a code span wrapped across a source newline converts properly — `**bold**` → `*bold*`, `~~struck~~` → `-struck-`, `` `code` `` → doubled-brace monospace **with every brace inside the span backslash-escaped** (wiki monospace ends at the first inner brace), `- item` → `* item`, `- [ ]`/`- [x]` → plain bullets, `#`…`######` → `h1.`…`h6.`. **Fenced-code CONTENT is never transformed** — only its delimiters become `{code}` |
| **Inputs** | A Markdown fragment on **stdin**. Optional `--functional-validation`, which applies `ticket_TEMPLATE.md`'s both-polarity NOT-SPECIFIED guard to this fragment: a real item is detected **structurally and placeholder-aware** (brace-delimited scaffolding is the template's own guidance, not QA guidance), and the canonical no-change line is matched **anchored** against a constant pinned to `specs/TEMPLATE/problem.md`, with the candidate **dash-normalized** first so both the double-hyphen and em-dash spellings match (BTG-205 DEC-010). `U+2013 EN DASH` is deliberately **not** folded, so a line spelled with one renders the visible NOT SPECIFIED marker rather than being silently accepted. No other argument |
| **Outputs (stdout)** | The converted wiki markup. **This is the one script in the set whose stdout is a DOCUMENT rather than `key=value` lines**, because it is a filter — stated explicitly so a reader of the three-channel contract is not surprised. A fragment that converts to nothing emits nothing, not a blank line |
| **Exit codes** | `0` converted; `1` a pass could not complete (`syncjs.render.md2wiki_failed`) — **and stdout is left EMPTY in that case**, so a partial render can never be projected as though it were complete; `2` usage. `3` and `4` are unreachable by construction: there is no transport and no config |
| **Re-run (idempotency)** | A **total function of its input**: identical input yields byte-identical output on every run and on any machine. That property eliminates the "unchanged source, different render" defect class outright — and keeps the delta guard in `.agents/skills/cadence-sync-jira/jira-server-conditions-render.md` quiet on a genuinely unchanged ticket |
| **Purity** | Reads **no** credential, **no** configuration, **no** repository file, and **no** environment variable, and opens no socket. It does not source `jira-lib.sh`, because that would pull in the transport and owned-data reader transitively; its two channel helpers are declared locally instead, using the same names and exit vocabulary |

### jira-md2wiki-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, conversion half — **sourced by `jira-md2wiki.sh`**, never on its own and never invoked |
| **What it does** | Owns the individual transforms and the Functional Validation predicate, and nothing else: `js_md2wiki_strip_comments` (HTML-comment removal, multi-line, exempting fenced code), `js_md2wiki_inline` (the whole-line inline pass — code spans carved out first and converted last, so no other rule runs inside one; each span is lifted behind a line-derived delimiter and restored in place, with emphasis converted over the whole line in between, so a pair wrapping a span is never torn across a fragment boundary), `js_md2wiki_is_list` / `js_md2wiki_block_start` (the block classification where paragraph unwrapping stops), `js_md2wiki_list_item` (one already-unwrapped item converted to its wiki bullet, checklist marker dropped), plus the three AC-5 members: `JS_MD2WIKI_NO_CHANGE_LINE` (the canonical wording, byte-pinned to `specs/TEMPLATE/problem.md`), `JS_MD2WIKI_NOT_SPECIFIED` (the marker, matching `.agents/skills/cadence-sync-jira/ticket_TEMPLATE.md`), `js_fv_dash_normalize` (the three-operation candidate fold — em dash with its surrounding whitespace, whitespace-run collapse, trim, and **nothing else**), `js_fv_is_no_change_line` (that fold's **single** call site), and `js_fv_classify` |
| **Inputs** | Its arguments alone. It reads no file, no environment variable, no credential, and no socket |
| **Outputs (stdout)** | Each function echoes its own result to its caller; the library itself writes nothing and reports nothing |
| **Exit codes** | Returns, never exits. `js_md2wiki_inline` and the predicates are total; the pipeline in the entry point owns the fail-loud path |
| **Re-run (idempotency)** | Every function is a **total function of its arguments**, so re-sourcing and re-calling is inherently convergent — the property on which the unit-fixture set rests |

### jira-desc-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, overwrite-hazard half — **sourced by `jira-write-issue.sh`**, never on its own and never invoked. ONE function, ONE call site |
| **What it does** | `js_description_delta_check <ticket> <issue-key> <description-file> [<live-issue-json>]` compares the fresh render against the issue's **live** `description` and **names the overwrite before it happens**. The update path replaces `description` wholesale, making re-projection a destructive update; if a fresh render were worse than what is already live, it would replace better content with worse, returning 2xx with no error. The comparison **reuses** the live issue body already read by the estimate prerequisite when passed, and issues at most **ONE** extra `GET .../issue/{key}?fields=description` when not. An **absent or null** live description folds to the empty string and is reported as a **delta** — a create-then-update race leaves that exact state, representing a real difference rather than an unreadable one. A failed **exchange** is never conflated with "no delta" |
| **Inputs** | The rendered description temp file, and optionally the live issue JSON already in hand |
| **Outputs (stdout)** | None. Its entire output is the reported condition on stderr, or silence |
| **Exit codes** | Returns `0` on **every** path — it never halts and never alters what is written. This is deliberate (BTG-205 DEC-005): blocking would halt every legitimate description update and turn the first post-upgrade sync of every pre-existing issue into a halt, which would break a Stable surface. The integrity guarantee comes structurally from the filter being a total function: a re-render of an unchanged source is byte-identical, so this guard remains **silent** on a genuinely unchanged ticket |
| **Re-run (idempotency)** | Read-only over tracker state; it writes nothing, so re-running is inherently convergent |

Ordering at the call site is load-bearing and matches the discipline
`jira-write-issue.sh` documents for the screen probe: **after** the BTG-062 absent-render and
blank-render halts (an upstream defect must stay a loud failure and never be masked by a delta
report), **after** the screen guard (a withheld description has no delta to report), and **before** the
body is staged. The body produced is byte-identical whether the guard reported, stayed silent, or
could not read the live value at all.

`jira-md2wiki-lib.sh` holds the individual transforms and the Functional Validation predicate;
`jira-md2wiki.sh` holds the CLI contract, block segmentation, and pass pipeline. The split follows
the same entry-point/library shape as `jira-link.sh`/`jira-link-lib.sh`, keeping each file within
the Agentic DX file-size ceiling defined in `CADENCE_ORG.md` §2 Pillar 3.
