# Module 04: Let It Run

## The question this module answers

Can I have Claude Code write and run a small script for me, directing and verifying without ever
reading the code?

## Where it sits in the arc

Fourth module. Prerequisite: [Module 03, Garrett's Filing System](../03-garretts-filing-system/README.md)
- you need a working personal `CLAUDE.md` and file-direction experience before handing off a
scripted task. Next: two modules branch from here, [Module 05, Homework for
Utah](../05-homework-for-utah/README.md) (recommended, not required) and [Module 06, The Bruner
Report](../06-the-bruner-report/README.md) (which needs Module 03 directly); the hinge is that this
module is where "directing, not typing" first extends from files to scripts. See
[`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Ask Claude Code to write and run a small script to solve a real task, without reading or writing
  the code by hand.
- Ask for a plan before letting a script run, and preview what it will do.
- Verify a script's output against the source data by hand, at least in part.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Tilghman's request for last month's door totals from a folder of nightly count files the
predecessor left with no totals computed - see `docs/workshop-design.md` §7, Module 04 row.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script recomputes the correct monthly total,
  best-night, and worst-night figures independently from the pristine source files and confirms the
  learner's report matches, while also confirming the source files themselves are unmodified.
- **Short write-up (secondary):** whether the learner asked for a plan first, ran it, and verified
  the result against at least one source file by hand.

## Takeaway

A "safe script direction" recipe added to the pack: plan, preview, run, verify.

## Stop condition (placeholder)

The checker script passes with the full count, and the write-up describes a real verification step.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
