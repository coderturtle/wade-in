# Module 09: Off the Clock

## The question this module answers

How do I do any of this on my own real files without hurting myself?

## Where it sits in the arc

Ninth module. Prerequisites: [Module 03, Garrett's Filing
System](../03-garretts-filing-system/README.md) and [Module 04, Let It Run](../04-let-it-run/README.md)
- this module is the first and only place the workshop deliberately leaves the sandbox, and it
needs both the file-direction and script-direction skills already in place before doing so safely.
Next: [Module 10, Opening Night](../10-opening-night/README.md); the hinge is that this module's
safety ritual is the thing the capstone asks the learner to re-engage with, even though the
capstone's own artifacts stay sandboxed. See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Copy a small set of real files (or provided stand-ins) into a working folder deliberately, rather
  than pointing Claude Code at an undefined real location.
- Back up before directing any change, and verify the backup is real, not just present.
- Recognize which of a set of realistic requests are safe to direct and which aren't, and say why.
- Write a personal safety plan: what to never point Claude Code at, and what the undo story is.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Tilghman hands over "the office laptop" - see `docs/workshop-design.md` §7, Module 09 row, and §12
for the full safety-design reasoning this module's gate is built from. A named, honestly partial
privacy adaptation: a learner may use provided stand-in files instead of their own real ones.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** the learner creates one real folder outside the workshop
  directory and copies a few real files (or stand-ins) into it, then runs the taught ritual. A
  checker script confirms a `backup/` exists whose filenames and
  per-file checksums match the originals recorded at backup time; confirms `before-manifest.txt`
  and `after-manifest.txt` both exist, are non-empty, and each carry a checker-written timestamp
  proving order; and confirms a closed-set safety
  quiz (6 described situations, select the 3 safe ones) matches a published key that follows
  from a rule the module explicitly teaches. The checker derives checksums from real files to verify
  backup integrity but never displays, extracts, or transmits their contents.
- **Short write-up (secondary):** the learner's own safety plan - what they'd never point Claude
  Code at, what their undo story is, where their own line between sandbox and real sits.

## Takeaway

A real-folder safety ritual checklist added to the pack: copy in, back up, manifest, preview,
verify.

## Stop condition (placeholder)

The checker script passes with the full count, and the safety plan is present and specific.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
