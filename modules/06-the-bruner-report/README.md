# Module 06: The Bruner Report

## The question this module answers

Starting from raw numbers, can I direct a client-ready document into existence with every figure
exact?

## Where it sits in the arc

Sixth module. Prerequisite: [Module 03, Garrett's Filing
System](../03-garretts-filing-system/README.md) - this module reuses the file-direction skill from
03 against a new artifact shape (a drafted document, not a correction). Next: [Module 07, Penny's
Ledger](../07-pennys-ledger/README.md). See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Direct Claude Code to draft a formatted document from a raw source file.
- Specify a required structure and figure accuracy up front, rather than fixing it after the fact.
- Verify the document's key figures against the source rather than trusting the draft.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Carl Bruner's month-end request, drafted from Doc Clay's raw weekly numbers file - see
`docs/workshop-design.md` §7, Module 06 row.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script confirms `06-docs/monthly-summary.md` contains
  the exact top-line revenue figure, recomputed by the checker as the sum of the fixture's four
  weekly figures, plus 3 further exact figures read from the fixture, plus all 5 required section
  headers present verbatim (a closed set), plus a word count within a stated bound.
- **Short write-up (secondary):** does the document read as a summary for its intended reader,
  rather than a data dump, and did the learner verify the figures themselves.

## Takeaway

A document-drafting prompt template: source file, format spec, exact-figures constraint.

## Stop condition (placeholder)

The checker script passes with the full count, and the conceptual check confirms appropriate tone
and verified figures.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
