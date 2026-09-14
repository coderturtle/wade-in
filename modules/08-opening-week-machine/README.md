# Module 08: Opening Week Machine

## The question this module answers

Can I automate the repetitive stuff instead of doing it by hand, twenty-five times?

## Where it sits in the arc

Eighth module. Prerequisites: [Module 04, Let It Run](../04-let-it-run/README.md) and [Module 07,
Penny's Ledger](../07-pennys-ledger/README.md) - this module combines safe-script-direction with
spreadsheet-driven data to power batch operations. Next: [Module 09, Off the
Clock](../09-off-the-clock/README.md). See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Direct a batch-renaming task from a mapping file, rather than renaming files one at a time.
- Direct a templated mail-merge from a spreadsheet, producing one output per row.
- Recognize when this same pattern would be reusable next month with new inputs.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Jack Crews's delivery photos plus a mapping sheet, and Penny's booking-confirmation letter template
plus her spreadsheet - see `docs/workshop-design.md` §7, Module 08 row.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script confirms the renamed file set exactly matches
  the set it derives from the mapping fixture (no extras, none missing, each one still the original
  file, not a corrupted or regenerated one), and confirms each generated letter contains its row's
  exact values from the spreadsheet with no unfilled template placeholders remaining.
- **Short write-up (secondary):** could this same template-and-mapping approach run again next
  month with new inputs, and what would the learner change first.

## Takeaway

Two reusable mini-recipes added to the pack: batch-rename-from-mapping, mail-merge-from-spreadsheet.

## Stop condition (placeholder)

The checker script passes with the full count, and the write-up shows the learner understands why
the approach generalizes.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
