# Module 03: Garrett's Filing System

## The question this module answers

Can I direct Claude Code to read and fix real files, and teach it how this office works?

## Where it sits in the arc

Third module. Prerequisite: [Module 02, Meet the New Hire](../02-meet-the-new-hire/README.md) - the
ask-watch-check rhythm from that module is what makes directing a real fix here possible. Next:
[Module 04, Let It Run](../04-let-it-run/README.md), which requires this module directly; most of
the rest of the arc (06, 09) also requires this module, though Module 05 only requires Module 02 -
this module's personal `CLAUDE.md` is the pack's spine most, but not all, later modules build on.
See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Direct Claude Code to find and correct specific errors in a real file, without editing it by
  hand.
- Verify a correction against the actual source of truth, not just accept a plausible-looking fix.
- Write a personal `CLAUDE.md` with house rules specific and actionable enough to actually change a
  session's future behavior, not generic platitudes.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Emmett's correction memo against the predecessor's staff phone list - see
`docs/workshop-design.md` §7, Module 03 row, for the scenario framing.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script confirms `03-files/staff-list-corrected.txt`
  has each of the 4 planted wrong values (a closed set, drawn from the correction memo) replaced
  with that memo's exact corrected value, with no collateral edits elsewhere
  in the file, and that `wade-in-workshop/CLAUDE.md` exists containing at least 3 of the 4 exact
  required section headers (`## About this folder`, `## House rules`, `## How I like output`,
  `## Never touch`).
- **Short write-up:** none - this module's conceptual check is whether the CLAUDE.md house rules
  are specific and actionable, graded directly against the artifact itself rather than a separate
  write-up.

## Takeaway

Personal `CLAUDE.md` v1: the pack's spine, revisited (not continuously rewritten) in later modules.

## Stop condition (placeholder)

The checker script passes with the full count, and the CLAUDE.md content is judged specific and
actionable by the conceptual check.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
