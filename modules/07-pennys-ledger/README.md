# Module 07: Penny's Ledger

## The question this module answers

Can I direct real spreadsheet-shaped cleanup, and prove nothing was lost?

## Where it sits in the arc

Seventh module. Prerequisite: [Module 04, Let It Run](../04-let-it-run/README.md) - this module
extends the safe-script-direction skill from 04 into merging and deduplicating real data. Next:
[Module 08, Opening Week Machine](../08-opening-week-machine/README.md). See
[`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Direct Claude Code to merge two overlapping data files under a stated rule.
- Demand a before/after count as proof nothing was silently dropped or duplicated.
- Spot-check at least one merged row by hand against its real source.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Penny's spring bookings, split across two overlapping files (hers and the predecessor's) that need
reconciling under a stated merge rule - see `docs/workshop-design.md` §7, Module 07 row, including
the source-of-truth rule the checker enforces (the current owner's file wins on conflict).

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script recomputes the expected post-merge row count
  and the expected ID set from the two pristine source files under the module's stated merge rule,
  and confirms every surviving row's key fields match the correct source values, not just that the
  right IDs are present.
- **Short write-up (secondary):** in plain words, what the merge rule did, which duplicates it
  collapsed, and how the learner satisfied themselves nothing was lost.

## Takeaway

A spreadsheet-cleanup recipe: state the rule, demand a before/after count, verify a sample row.

## Stop condition (placeholder)

The checker script passes with the full count, and the write-up correctly explains the merge.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
