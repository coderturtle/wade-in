# Module 05: Homework for Utah

## The question this module answers

Can I send Claude Code out to the web and come back with sourced, checkable answers instead of
confident guesses?

Johnny Utah, the Double Deuce's brand-new marketing hire, catches you by the office door with a
legal pad full of crossed-out numbers. "Tilghman wants to start selling tickets online instead of
just counting cash at the door. He asked me to compare a few real ticketing companies, pricing and
features, before he'll even talk about it. I don't know where to start."

Angelo Pappas, passing by with a crate of glassware, doesn't slow down. "The phone and a chalkboard
worked fine for thirty years." He's not entirely wrong that the old way worked. He's also not the
one who has to answer Tilghman's next question, which will be "show me the numbers, not your
opinion of them."

Today's job: point Claude Code at the open internet, ask it to research real, currently operating
ticketing platforms, and come back with a brief that names its sources plainly enough that anyone,
including a skeptic like Pappas, could check it themselves.

## Before you start

You'll need:

- Module 02 finished (a working session, and the ask-watch-check habit from that module). Module 04
  is recommended, not required - this module doesn't ask Claude Code to write or run a script.
- A working internet connection on whatever machine is running your Claude Code session. This
  module is genuinely different from every module before it: instead of reading files already sitting
  in your workshop folder, Claude Code goes out to real, live websites and reads what's actually
  published there today.
- About 30-45 minutes.

**One honest note before you start:** every other module in this workshop uses files that come with
the workshop folder, so the same exercise behaves the same way for everyone. This one doesn't - it
depends on real companies' real web pages, which can change their wording, their prices, or their
layout at any time, and on your own session actually having live web access. If your session tells
you it can't reach the web, say so plainly in your answers file (below) rather than inventing numbers
or presenting general knowledge as something you just verified - Wade In doesn't ship a separate
practice-page fallback for this module, on purpose, so the honest move if you're blocked is to name
the gap, not paper over it.

## Part 1: the assignment, in Johnny's words

Johnny needs a brief comparing three real, currently operating ticketing platforms - companies that
actually sell event tickets online today, not made-up ones - on what they'd cost the Double Deuce
and what they'd actually let the venue do. He needs it in a shape Tilghman can skim: what the
platforms are, what they cost, what they do, and which one Johnny should recommend.

Before you ask Claude Code for anything, decide (or let Claude Code suggest, and you approve) which
three platforms to research. Any three real, currently operating ticketing platforms with public
pricing pages work - the point of this exercise is the research discipline, not a specific list of
companies.

## Part 2: asking for real research, with sources demanded

Open a session the same way you did in Module 02 and ask for the research directly. Being specific
about sourcing matters more here than in any earlier module - a vague request just gets you
confident-sounding prose with nothing behind it. Something like this works as a starting point:

```
Research three real, currently operating event-ticketing platforms that a small live-music venue
could use to sell tickets online. For each one, find its publicly published pricing (per-ticket
fees, percentage fees, or subscription costs) and note two or three features relevant to a small
venue (reserved seating, door/box-office sales, marketing tools). Cite the actual URL you got each
platform's pricing from - not a general company URL, the specific page. Write the result to
05-research/comparison-brief.md using exactly these four section headers, in this order:

## Platforms Compared
## Pricing
## Features
## Recommendation

Under Pricing, include a markdown table with one row per platform and no blank cells. Under
Recommendation, pick one platform for the Double Deuce and say why, based on what you found above.
```

Watch what Claude Code proposes before approving any file writes, the same habit Module 02 taught.

## Part 3: the shape this brief has to have

Whatever prompt you actually used, the finished file needs to land at
`05-research/comparison-brief.md` with these exact properties - this is what the checklist below
verifies, so it's worth checking yourself before you run it:

- All four section headers above, spelled and capitalized exactly as shown, each on its own line.
- At least three source URLs, from at least three different websites (not three different pages on
  the same company's site) - one per platform is the natural way to get there.
- A comparison table (under Pricing, or wherever you put it) with at least three data rows and no
  empty cells - every claim in that table has to actually say something, not leave a cell blank
  because Claude Code couldn't find a number.

This is the point worth being honest about, the same way Module 01 was honest about its own limits:
this checklist can confirm the brief has the right shape and cites real-looking sources. It cannot
confirm any of the actual numbers are correct, or that the cited pages really say what the brief
claims they say. That's Part 4's job, not a script's.

## Part 4: check the sources yourself

Open at least one of the cited URLs yourself, in a real browser, and compare what's actually on that
page against what the brief says it found. This is the same "read before you trust it" habit Module
02 taught, applied to the open web instead of a workshop fixture - and it matters more here, since
nothing in this workshop wrote these pages and nothing guarantees Claude Code read them perfectly.

While you're checking, notice whether any of the three platforms' pages disagreed with each other on
anything worth flagging (a fee structured completely differently, a feature one has and the others
plainly don't) - and if you asked Claude Code something and its first answer turned out to be wrong
or outdated compared to what the real page says, that's worth noticing too, not smoothing over.

## Required to advance

**A checklist you run yourself.**

```
bash checks/check.sh 05
```

This checks, structurally: `05-research/comparison-brief.md` exists as a real file; it contains all
four required section headers, verbatim; it cites source URLs from at least three different
websites; and it has a comparison table with at least three rows and no blank cells. It cannot
check, and doesn't claim to check, whether any specific price or feature claim in the brief is
actually true - that's this module's honest limit, named plainly rather than dressed up as
mechanically verified. It prints `RESULT: PASS (n/n)` when everything checkable is there.

**A short answers file.** Create `05-research/answers.txt`, containing three lines, each starting
with the label shown:

```
SOURCES_CHECKED: <did you open at least one cited page yourself and compare it to what the brief says? what did you find?>
DISAGREEMENT: <did the sources disagree with each other about anything, or did Claude Code's first answer turn out to be wrong once you checked? what happened?>
CONFIDENCE: <how much would you trust this brief if you were handing it to Tilghman today, and what would you still want to double-check?>
```

Same rule as every earlier module: copying the bracketed prompts word for word won't pass. Write
your own answer, even a short one.

## Takeaway

Add `my-pack/recipe-research-prompt.md`: demand named sources for any factual claim, keep what
a source actually says separate from Claude Code's summary of it, and check at least one source
yourself before treating a research brief as finished. This is the same ask-watch-check rhythm every
earlier module taught, pointed outward at the open web instead of inward at workshop files. The
capstone checks for this file by its exact name, so use it as shown, not a name of your own choosing.

---

*Next: [Module 06, The Bruner Report](../06-the-bruner-report/README.md) - a different kind of
document, drafted from numbers Doc already has rather than research you had to go find, but the same
discipline of checking figures before you hand them over.*
