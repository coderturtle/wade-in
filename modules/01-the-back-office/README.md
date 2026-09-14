# Module 01: The Back Office

## The question this module answers

What is this black window, and how do I tell it to do things?

## Where it sits in the arc

First module, no prerequisite - the only module in the arc with none. Next:
[Module 02, Meet the New Hire](../02-meet-the-new-hire/README.md); the hinge is that nothing past
this module can ask Claude Code anything until you can open a terminal, navigate it, and run a
command yourself. See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Open a terminal application and recognize what a command prompt is.
- Understand what "current directory" means and navigate between two folders.
- Run a taught command (create a folder, copy a file) and read its result.
- Recover from a terminal that "looks stuck," without panicking or closing the window.
- Install the `claude` CLI following hand-held, copy-paste instructions.

## Exercise material to draw from (not a spec - authored during the content-building pass)

None decided yet - this module doesn't yet have an existing curriculum anchor to draw from within
this factory's own prior workshops. Candidate sources for content-authoring time: general terminal-basics teaching material
aimed at complete beginners, adapted rather than copied, kept tightly scoped to only what Module 02
onward actually needs.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** `check.sh 01`, run by the learner themselves, confirms - the
  workshop folder is unpacked with its marker file intact (exact path checked); a new
  `01-terminal/my-notes/` directory exists; the supplied `fixtures/welcome-note.txt` is copied into
  it byte-identical (checksum compare); the `claude` CLI resolves on PATH via the checker's own
  `command -v` probe; a `RESULT: PASS (n/n)` line prints with the full count. **Open design
  question, not yet resolved:** whether this module's checker should also
  confirm the learner has actually authenticated/logged in, not just installed the CLI - see
  `docs/workshop-design.md` §14 item 1, the single highest-priority open question in the whole
  design - the fix (if any) would likely land in this module's own checker, but the design doc
  names it as blocking specifically for Module 02's content, not this one.
- **Short write-up (secondary), presence-checked at the required-checklist tier:** three short
  own-words answers in a provided answers file - what a prompt is, what a current
  directory is, what to do if the terminal "looks stuck."

## Takeaway

`my-pack/cheatsheet.md` started: the learner's own terminal survival card (open, navigate, recover).

## Stop condition (placeholder)

The checker script passes with the full count, and all three own-words answers are present.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet - that's the next phase, run
> one module at a time. See [`modules/README.md`](../README.md) for workshop-wide status, and
> `docs/workshop-design.md` §14 item 1 for the specific open question that should be resolved
> before Module 02's real content is written (this module's own checker is likely where the fix
> lands, even though the design doc names Module 02 as what it blocks).
