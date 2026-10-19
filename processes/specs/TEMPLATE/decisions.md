# Decision Log: {TICKET-ID} -- {Title}

This log captures architectural and design decisions made across the lifecycle of this specification. Every entry is immutable once committed -- if a later finding reverses an earlier choice, append a new entry that cites and supersedes the prior one. Once a ticket is **archived**, its decision entries are permanently frozen: a subsequent superseding ticket records the new decision in **its own** `decisions.md` and may append an **additive forward-pointer annotation** here, but the original entry's prose is never edited, rephrased, or removed.

For decisions carrying repository-wide or cross-context architectural impact, promote the decision to a formal ADR in the project's `docs/ADR/` directory during `/cadence-archive`.

---

## DEC-001: {Decision Title}

- **Date:** {YYYY-MM-DD}
- **Status:** Accepted | Superseded by DEC-{N}
- **Decider:** {Person or agent role making the call}
- **Phase:** Triage | Spec Authoring | Spec Review | Implementation | Code Review

### Context

{What design question, ambiguity, or engineering trade-off prompted this decision? Which constraints or invariants were in play?}

### Decision

{State the chosen approach clearly and unambiguously.}

### Rationale

{Explain why this option won over the alternatives. Cite the Contextual Grounding Matrix (6W×4L) cells and CADENCE Engineering Pillars affected by this choice.}

### Alternatives Considered

1. **{Alternative A}:** {Concise summary and the specific reason it was rejected}
2. **{Alternative B}:** {Concise summary and the specific reason it was rejected}

### Consequences

- **Positive:** {Direct benefits and guarantees gained from this decision}
- **Negative:** {Accepted costs, complexity, or operational trade-offs}
- **Follow-up:** {Required downstream actions -- e.g., "re-evaluate after runtime adapter migration completes"}

---

## DEC-002: {Next Decision}

{Follow the same structure above. Append subsequent decisions in chronological order.}
