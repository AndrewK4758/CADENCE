# `/claire-sync-jira` — script contracts: deterministic markup rendering

Bounded context: Tracker projection / Jira Server-DC adapter (BTG-075, BTG-205).
Invariant relied on from outside this boundary: identical to its sibling
`.claude/skills/claire-sync-jira/jira-server-scripts.md` — the repository (`metadata.yaml` +
`problem.md`) is the source of truth; Jira is the projection layer, and every script communicates on
exactly three channels (stdout, stderr `syncjs.*`, exit code).

**This file is a further part of one index, not another index.** BTG-205 split it off because
`jira-server-scripts.md` stood at **399** lines against a `-lt 400` ceiling — zero headroom — so the
new contract had nowhere to land in place. The record is **split, never truncated**: the same
facet-conflict resolution BTG-102 applied to the condition catalogue, BTG-105 to the umbrella entries,
BTG-168 to the screen-availability concern and BTG-173 to the issue-type entry (C-3: Operability
outranks DX on *content*; DX is served by placement instead).
`btg-075-script-contract.test.sh`'s `js_index_view` merges every `jira-server-scripts-*.md` into the
primary before each lookup, so a split cannot hide a missing contract entry.

Its reported conditions are catalogued in
`.claude/skills/claire-sync-jira/jira-server-conditions-render.md`.

---

## The division of labour inside `render_ticket_template` (BTG-205 DEC-001)

`render_ticket_template` is **agent-performed**, and stays so. BTG-150 established that deliberately
and by search, and its call-site shape is exactly right: the orchestration's
`render_description_tempfile` snippet
(`.claude/skills/claire-sync-jira/jira-server-orchestration.md`, section 4) calls it as a shell function
and that snippet is **unchanged**.

What BTG-205 changes is what happens *inside* it. The framework maintainer resolved the question
directly: *"the intent is for the model to generate the content, but formatting that content for Jira
wiki should be a deterministic process."* So the step splits along an axis BTG-150 conflated:

| Axis | Who performs it | Status |
|---|---|---|
| **Content authorship** — which `problem.md` section fills which `{{token}}`, what prose is carried, what counts as absent | the **model** | **UPHELD**, unchanged from BTG-150 |
| **Markup conversion** — turning an already-selected Markdown fragment into Jira wiki markup | **`jira-md2wiki.sh`**, deterministically | **SUPERSEDED for this step only** |

Concretely, `render_ticket_template` MUST:

1. Extract each `{{token}}`'s source fragment from `problem.md` / `metadata.yaml`, exactly as the
   *Token sources* table of `.claude/skills/claire-sync-jira/ticket_TEMPLATE.md` directs. **Unchanged —
   this is authorship.**
2. **Pipe every extracted Markdown fragment through `jira-md2wiki.sh`** before substituting it. The
   `{{functional_validation}}` fragment is piped with `--functional-validation`, which applies that
   token's both-polarity NOT-SPECIFIED guard mechanically instead of by reading the rule.
3. Substitute the converted results into the template body.

**The template body itself is NEVER passed through the filter.** It is already wiki markup and a
second pass would corrupt it. Only `{{token}}` values are converted.

A fragment that converts to nothing yields an **empty** token value, not a blank line; apply that
token's *If missing* rule to it exactly as if the section had been absent.

---

### jira-md2wiki.sh

| Field | Value |
|---|---|
| **Operation/step** | Projection, step 4 sub-step — convert **one already-selected** Markdown fragment to Jira Server/DC wiki markup. It is a **filter**, not an operation: it takes no ticket id and no issue key, and it decides nothing about *what* the description says |
| **What it does** | Applies the *Rendering rules* of `.claude/skills/claire-sync-jira/ticket_TEMPLATE.md` mechanically, in a fixed and non-commutative pass order: (1) strip `<!-- … -->` HTML comments, outside fenced code; (2) segment into blocks — fenced code, heading, table, list, blockquote, paragraph; (3) strip `> **Probe:**` openers **together with every contiguous `>` continuation line**, because a run stripped at the opener alone strands the answer body as loose prose; (4) unwrap each list item onto ONE line, since wiki ends an item at the newline; (5) unwrap hard-wrapped paragraphs, and **only** paragraphs — never a list, a table or a code block; (6) convert tables structurally, promoting the header row to doubled pipes **only when a separator row identifies it** and dropping that separator; (7) emit a kept blockquote as a `{quote}` macro and **recurse** on the inner text, which terminates because the prefix is removed before the call; (8) inline conversions last and over the assembled line, which is the only reason a code span that wrapped across a source newline converts at all — `**bold**` → `*bold*`, `~~struck~~` → `-struck-`, `` `code` `` → doubled-brace monospace **with every brace inside the span backslash-escaped** (wiki monospace ends at the first inner brace), `- item` → `* item`, `- [ ]`/`- [x]` → plain bullets, `#`…`######` → `h1.`…`h6.`. **Fenced-code CONTENT is never transformed** — only its delimiters become `{code}` |
| **Inputs** | A Markdown fragment on **stdin**. Optional `--functional-validation`, which applies `ticket_TEMPLATE.md`'s both-polarity NOT-SPECIFIED guard to this fragment: a real item is detected **structurally and placeholder-aware** (brace-delimited scaffolding is the template's own guidance, not QA guidance), and the canonical no-change line is matched **anchored** against a constant pinned to `specs/TEMPLATE/problem.md`, with the candidate **dash-normalized** first so both the double-hyphen and the em-dash spellings match (BTG-205 DEC-010). `U+2013 EN DASH` is deliberately **not** folded, so a line spelled with one renders the visible NOT SPECIFIED marker rather than being silently accepted. No other argument |
| **Outputs (stdout)** | The converted wiki markup. **This is the one script in the set whose stdout is a DOCUMENT rather than `key=value` lines**, because it is a filter — stated explicitly so a reader of the three-channel contract is not surprised. A fragment that converts to nothing emits nothing, not a blank line |
| **Exit codes** | `0` converted; `1` a pass could not complete (`syncjs.render.md2wiki_failed`) — **and stdout is left EMPTY in that case**, so a partial render can never be projected as though it were correct; `2` usage. `3` and `4` are unreachable by construction: there is no transport and no config |
| **Re-run (idempotency)** | A **total function of its input**: identical input yields byte-identical output, every run, on any machine. That property is what removes the "unchanged source, different render" defect class outright rather than reporting on it — and it is what makes the delta guard in `.claude/skills/claire-sync-jira/jira-server-conditions-render.md` quiet on a genuinely unchanged ticket |
| **Purity** | Reads **no** credential, **no** configuration, **no** repository file and **no** environment variable, and opens no socket. It does not source `jira-lib.sh`, because that pulls the transport and the owned-data reader in transitively; its two channel helpers are declared locally instead, on the same names and the same exit vocabulary |

### jira-md2wiki-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, conversion half — **sourced by `jira-md2wiki.sh`**, never on its own and never invoked |
| **What it does** | Owns the individual transforms and the Functional Validation predicate, and nothing else: `js_md2wiki_strip_comments` (HTML-comment removal, multi-line, exempting fenced code), `js_md2wiki_inline` (the whole-line inline pass — code spans carved out first and converted last, so no other rule runs inside one; each span is lifted behind a line-derived delimiter and restored in place, with emphasis converted over the whole line in between, so a pair that wraps a span is never torn across a fragment boundary), `js_md2wiki_is_list` / `js_md2wiki_block_start` (the block classification paragraph unwrapping stops at), `js_md2wiki_list_item` (one already-unwrapped item to its wiki bullet, checklist marker dropped), plus the three AC-5 members: `JS_MD2WIKI_NO_CHANGE_LINE` (the canonical wording, byte-pinned to `specs/TEMPLATE/problem.md`), `JS_MD2WIKI_NOT_SPECIFIED` (the marker, exactly as `.claude/skills/claire-sync-jira/ticket_TEMPLATE.md` mandates it), `js_fv_dash_normalize` (the three-operation candidate fold — em dash with its surrounding whitespace, whitespace-run collapse, trim, and **nothing else**), `js_fv_is_no_change_line` (that fold's **one** call site) and `js_fv_classify` |
| **Inputs** | Its arguments alone. It reads no file, no environment variable, no credential and no socket |
| **Outputs (stdout)** | Each function echoes its own result to its caller; the library itself writes nothing and reports nothing |
| **Exit codes** | Returns, never exits. `js_md2wiki_inline` and the predicates are total; the pipeline in the entry point owns the fail-loud path |
| **Re-run (idempotency)** | Every function is a **total function of its arguments**, so re-sourcing and re-calling is inherently convergent — the property the whole unit-fixture set rests on |

### jira-desc-lib.sh

| Field | Value |
|---|---|
| **Operation/step** | Shared library, overwrite-hazard half — **sourced by `jira-write-issue.sh`**, never on its own and never invoked. ONE function, ONE call site |
| **What it does** | `js_description_delta_check <ticket> <issue-key> <description-file> [<live-issue-json>]` compares the fresh render against the issue's **live** `description` and **names the overwrite before it happens**. The update path replaces `description` wholesale, so a re-projection is a destructive update; when the fresh render is worse than what is already live it replaces better content with worse, successfully, with a 2xx and no error. The comparison **reuses** the live issue body the estimate prerequisite already read when one is passed, and issues at most **ONE** extra `GET .../issue/{key}?fields=description` when it is not. An **absent or null** live description folds to the empty string and is reported as a **delta** — a create-then-update race leaves exactly that state, and it is a real difference, not an unreadable one. A failed **exchange** is never conflated with "no delta" |
| **Inputs** | The rendered description temp file, and optionally the live issue JSON already in hand |
| **Outputs (stdout)** | None. Its whole result is the reported condition, or silence |
| **Exit codes** | Returns `0` on **every** path — it never halts and never changes what is written. That is deliberate (BTG-205 DEC-005): blocking would halt every legitimate description update and would turn the first post-upgrade sync of every pre-existing issue into a halt, which is a breaking change to a Stable surface. The integrity guarantee comes structurally instead, from the filter being a total function: a re-render of an unchanged source is byte-identical, so this guard is **silent** on a genuinely unchanged ticket |
| **Re-run (idempotency)** | Read-only over tracker state; it writes nothing, so re-running is inherently convergent |

Ordering at the call site is load-bearing and matches the discipline
`jira-write-issue.sh` already documents for the screen probe: **after** the BTG-062 absent-render and
blank-render halts (an upstream defect must stay a loud failure and must never be masked by a delta
report), **after** the screen guard (a withheld description has no delta to report), and **before** the
body is staged. The body it produces is byte-identical whether the guard reported, stayed silent, or
could not read the live value at all.

`jira-md2wiki-lib.sh` holds the individual transforms and the Functional Validation predicate;
`jira-md2wiki.sh` holds the CLI contract, the block segmentation and the pass pipeline. The split is
the same entry-point/library shape as `jira-link.sh`/`jira-link-lib.sh`, and it exists because one file
would not fit under the agentic-DX file measure `CLAIRE_ORG.md` §2 Facet 3 states.
