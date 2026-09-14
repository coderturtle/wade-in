# Modules

Wade In's arc takes a learner who has never opened a terminal through ten modules inside one continuing scenario: **The Double Deuce**, a fictional live-music venue whose newly hired Operations Coordinator (you) inherits years of chaotic files from a recently retired predecessor. Work through the modules in order - Module 01 is a hard prerequisite for everything after it, since nothing past it assumes you already know how to open a terminal or run a command.

**Hands-on by design, not passive text.** No module here completes by reading it. Every module states a required gate before content exists: an artifact you produce, checked two ways. Every module also has a stated **takeaway**: something reusable you're meant to keep, not just proof you did the exercise. Named honestly: most modules' checked artifact and its takeaway are currently two separate things (the checked work is one file, the reusable pack piece is another) rather than the gate directly producing the takeaway - closing that gap for real is still an open design decision, not solved yet.

> **Content status: Module 01 has real, authored content, fixtures, and a working checker script.
> Modules 02-10 are still skeleton only** - a decided question, arc position, gate shape, and
> takeaway shape, no authored exercise yet. That's the next phase, run one module at a time. See
> `docs/next-actions.md` for what happens next.

## The gate, in plain terms

Two checks, every module:

| Tier | What it is (once each module's real exercise is written) |
|---|---|
| **Required checklist** | A short script, planned to ship inside the workshop folder, that will check your work against a set of facts: a file that exists, a number that's correct, a set of names that matches. You'll run it yourself, or ask Claude Code to run it, and it will tell you plainly whether you passed. |
| **A quick write-up, graded for you** | A short answer in your own words about what you did or why, checked by an AI pass against a supplied standard. This part is about judgment calls a script can't make on its own. |

None of this exists yet for any module - see the status note above.

Full design, including exactly what each check can and can't prove: [`docs/workshop-design.md`](../docs/workshop-design.md) §8.

## The arc

Rough time estimates below are exactly that: estimates, not commitments. They're judgment calls made before any real content exists, expected to take roughly this long. Budget roughly 10-13 hours total across all ten modules, spread across multiple sessions - this isn't designed to be done in one sitting, and Module 01 alone is deliberately slow.

| # | Module | Hard prerequisite | The question it answers | Estimated time* |
|---|---|---|---|---|
| 01 | [The Back Office](01-the-back-office/README.md) | none | What is this black window, and how do I tell it to do things? | ~45-60 min |
| 02 | [Meet the New Hire](02-meet-the-new-hire/README.md) | 01 | How do I ask Claude Code for something, watch what it proposes, and check what it did? | ~30-45 min |
| 03 | [Garrett's Filing System](03-garretts-filing-system/README.md) | 02 | Can I direct Claude Code to read and fix real files, and teach it how this office works? | ~45-60 min |
| 04 | [Let It Run](04-let-it-run/README.md) | 03 | Can I have Claude Code write and run a small script for me, directing and verifying without ever reading the code? | ~45-60 min |
| 05 | [Homework for Utah](05-homework-for-utah/README.md) | 02 (04 recommended) | Can I send Claude Code out to the web and come back with sourced, checkable answers instead of confident guesses? | ~45-60 min |
| 06 | [The Bruner Report](06-the-bruner-report/README.md) | 03 | Starting from raw numbers, can I direct a client-ready document into existence with every figure exact? | ~45-60 min |
| 07 | [Penny's Ledger](07-pennys-ledger/README.md) | 04 | Can I direct real spreadsheet-shaped cleanup, and prove nothing was lost? | ~45-60 min |
| 08 | [Opening Week Machine](08-opening-week-machine/README.md) | 04, 07 | Can I automate the repetitive stuff instead of doing it by hand, twenty-five times? | ~45-60 min |
| 09 | [Off the Clock](09-off-the-clock/README.md) | 03, 04 | How do I do any of this on my own real files without hurting myself? | ~45-60 min |
| 10 | [Opening Night](10-opening-night/README.md) | all of 01-09 | Handed a genuinely new job end to end, can I do it all, and leave with something I'll actually use again? | ~2-3 hrs (the capstone, plan a dedicated block) |

*Estimates only, not commitments - see the note above the table.

Full per-module gate design and coverage check: [`docs/workshop-design.md`](../docs/workshop-design.md) §7.

## What you keep

Each module is meant to leave you with a takeaway: a piece of your own personal `CLAUDE.md` and recipe pack, assembled module by module (see the note above on where this isn't fully gate-enforced yet).

| # | Module | Takeaway |
|---|---|---|
| 01 | The Back Office | A terminal survival card: open, navigate, recover |
| 02 | Meet the New Hire | The card grows: launch, ask, interrupt, exit, "read before you accept" |
| 03 | Garrett's Filing System | Your personal `CLAUDE.md` v1, the pack's spine |
| 04 | Let It Run | A "safe script direction" recipe: plan, preview, run, verify |
| 05 | Homework for Utah | A research prompt template: demand sources, separate fact from summary |
| 06 | The Bruner Report | A document-drafting prompt template |
| 07 | Penny's Ledger | A spreadsheet-cleanup recipe |
| 08 | Opening Week Machine | Two reusable mini-recipes: batch-rename, mail-merge |
| 09 | Off the Clock | A real-folder safety checklist |
| 10 | Opening Night | The full assembled pack, everything above combined, the literal artifact of "fluent" |

## A note on the scenario

The Double Deuce is a fictional venue. Every module's starting business data (client records, bookings, financial figures) is simulated - no real client data, no real vendor relationships, ever. Two modules are named, deliberate exceptions that reach outside that fictional data: Module 05 asks you to research real, public vendor websites, and Module 09 asks you to (optionally) work with a few of your own real files.
