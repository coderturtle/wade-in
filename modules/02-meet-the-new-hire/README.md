# Module 02: Meet the New Hire

## The question this module answers

How do I ask Claude Code for something, watch what it proposes, and check what it did?

## Where it sits in the arc

Second module. Prerequisite: [Module 01, The Back Office](../01-the-back-office/README.md) - you
need a working terminal and an installed `claude` CLI before you can launch a session at all. Next:
[Module 03, Garrett's Filing System](../03-garretts-filing-system/README.md); the hinge is that
this module teaches the basic ask-watch-check rhythm, and Module 03 is the first time you direct
Claude Code to actually change a file. See [`modules/README.md`](../README.md) for the full arc.

## Learning objectives (placeholder - finalized when content is authored)

- Launch a Claude Code session and send it a first real request.
- Recognize a permission prompt and understand why Claude Code asks before acting.
- Read what Claude Code proposes before approving it, not just click through.
- Check a produced result against the source material yourself, rather than trusting it by default.

## Exercise material to draw from (not a spec - authored during the content-building pass)

Doc Clay's request to summarize the venue's history document from the predecessor's files - see
`docs/workshop-design.md` §7, Module 02 row, for the scenario framing this exercise is built from.

## Required gate (placeholder - shape decided now, real checker written later)

- **Required checklist (primary):** a checker script confirms a summary file exists, is a short,
  bounded length, and contains two specific facts the checker itself reads from the source fixture
  (not an embedded answer key). This check establishes the file has the right properties; it can't
  establish that Claude Code, rather than the learner typing by hand, actually produced it - a
  named limit of this kind of check, not something this module's gate claims to solve.
- **Short write-up (secondary):** own-words answers on what a permission prompt is, why Claude Code
  asks before acting, and one thing the learner checked themselves before trusting the summary.

## Takeaway

The terminal survival card from Module 01 grows: launch, ask, interrupt, exit, and "read before you
accept."

## Stop condition (placeholder)

The checker script passes with the full count, and the write-up answers are present.

---

> **Skeleton only.** This module has a decided question, arc position, gate shape, and takeaway
> shape. It has no authored exercise, fixture, or checker script yet. See
> [`modules/README.md`](../README.md) for workshop-wide status.
