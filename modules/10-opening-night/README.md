# Module 10: Opening Night

## The question this module answers

Handed a genuinely new job end to end, can I do it all, and leave with something I'll actually use
again?

Tilghman calls you in on a Monday. Season opener's in two weeks, the full package, no one else
free to touch it: a vendor comparison for the AV setup, the crew hours tallied and checked, a
budget write-up for Carl Bruner, a guest list that's currently sitting in two different people's
inboxes, and a run of press photos that need renaming and confirmation letters going out before
anyone forgets. None of it is hard exactly. All of it is new - new numbers, new names, new files,
nothing you can just copy from an earlier module and change the dates on. That's the point of
today.

## Before you start

You'll need every module from 01 through 09 finished - not because this module tests each one in
isolation, but because it asks you to reach for whichever one fits, without being told which, the
same way a real week at work does. Budget 60-90 minutes. There's more ground here than any single
earlier module, on purpose.

One practical note before you start: everything below lives inside `10-capstone/` in your workshop
folder, and every fixture it uses is brand new - under `fixtures/capstone/`, not reused from any
earlier module. Nothing here is graded by comparing against what you turned in for Modules 03
through 08; the checklist recomputes the right answer itself from this module's own numbers, so
there's nothing to gain from pasting in old work and everything to lose from it not matching.

## Part 1: the AV vendor brief (Module 05's research skill)

Tilghman wants three AV vendors compared before he commits to one for opening night - pricing,
what's included, and a straight recommendation, sourced from real pages, not guessed.

Ask Claude Code to research three real AV/event-rental vendors (or search-engine-plausible
stand-ins, same as Module 05) and write a brief to `10-capstone/research/av-comparison-brief.md`
with these exact section headers:

```
## Vendors Compared
## Pricing
## Equipment Included
## Recommendation
```

`## Pricing` needs an actual comparison table - vendor names down one side, at least three rows of
real numbers, no empty cells. Cite where the numbers came from: at least three source URLs, from
at least three different sites, somewhere in the brief.

## Part 2: crew hours, by script (Module 04's direction skill)

Jack Crews logged hours for the eight days leading up to opening night, one file per day, at
`fixtures/capstone/crew-hours-2026-09-08.txt` through `-15.txt`, opening night itself. Each file
has the same two-line shape:

```
Date: 2026-09-08
Hours: 14
```

Same job as Module 04, new data: direct Claude Code to write a script - don't read the eight files
by hand and don't let it hand-tally them either - that reads all eight, sums the hours, and finds
the single busiest day and single lightest day. Ask for its plan before you let anything run,
same habit Module 04 taught.

The script and its output both need to end up in `10-capstone/crew/`. The report itself,
`10-capstone/crew/crew-report.txt`, needs these five labels, one value each:

```
TOTAL_HOURS: <sum across all eight files>
BUSIEST_DATE: <the date with the most hours>
BUSIEST_HOURS: <that day's hour count>
LIGHTEST_DATE: <the date with the fewest hours>
LIGHTEST_HOURS: <that day's hour count>
```

Then, in your own words, create `10-capstone/crew/answers.txt`:

```
PLAN_FIRST: <did you ask for a plan before running anything - yes or no, and what happened?>
```

## Part 3: the budget write-up for Bruner (Module 06's drafting skill)

Carl Bruner's raw notes are sitting at `fixtures/capstone/opening-night-raw-figures.txt` - his own
working figures, not formatted for anyone but him, four cost lines he hasn't totaled himself yet.
Same drill as Module 06: direct Claude Code to draft a clean write-up from these raw notes, not
retype them by hand.

Write it to `10-capstone/budget/opening-night-budget.md`, 150-400 words, with these exact headers:

```
## Summary
## Budget Breakdown
## Notable Items
## Comparison to Last Season
## Prepared By
```

It needs to actually total the four cost lines correctly, and state the total, the expected
attendance, the advance ticket price, and the entertainment fee somewhere in the document - Bruner
checks every figure by hand, same as always.

## Part 4: the guest list merge (Module 07's cleaning skill)

Two people have been keeping opening-night guest lists, separately, and they don't agree:
`fixtures/capstone/penny-guest-list.csv` (Penny's) and `fixtures/capstone/tilghman-guest-draft.csv`
(Tilghman's own draft). Same shape of problem as Module 07's two overlapping files: some guests
appear in both with different numbers, some appear in only one.

Direct Claude Code to merge them into one clean file, and be explicit about the rule before you
ask: where the two disagree on the same guest, Penny's copy is the one that's right - she's the one
actually confirming RSVPs. Where a guest appears in only one file, keep them.

Write the result to `10-capstone/guests/guest-list-clean.csv` with this exact header row:

```
guest_id,name,comp_tickets,plus_ones,total_admits
```

`total_admits` is a new column - not in either source file - computed as `comp_tickets +
plus_ones` for every row.

## Part 5: photos and letters (Module 08's batch skill)

Jack Crews shot twenty press photos the week before opening night, sitting at
`fixtures/capstone/press-photos/PRESS_01.jpg` through `PRESS_20.jpg`, plus a mapping sheet at
`fixtures/capstone/press-photo-mapping.csv` saying what each one should be renamed to. Same
mechanism as Module 08: direct Claude Code to batch-rename from that mapping into a new folder,
`10-capstone/press-photos/`, rather than overwriting the originals in place.

Separately, `fixtures/capstone/vip-confirmations.csv` lists five VIP guests, their event date, and
their party size. Direct Claude Code to mail-merge a short confirmation letter for each one - one
file per row, in `10-capstone/vip-letters/`, each one naming that guest, the date, and their party
size somewhere in the text. Same rule as Module 08: check for leftover template placeholders
before you call it done. None should remain.

## Before you finish: re-read Module 09

Nothing in this capstone leaves your workshop folder - everything above stays sandboxed, same as
every module before Module 09. But the job itself, the kind Tilghman just handed you, is exactly
the kind of job that *could* show up on your own real files someday: vendor research, a budget
write-up, a guest list, a folder of photos. Before you move on, go back and reread Module 09's
five-step ritual - copy in, back up, manifest, preview, verify - and its two hard lines. You don't
need to run it again here. Just make sure it's the thing you'd actually reach for, not something
you skimmed once and filed away.

## Building your pack

This is also where everything you've been adding to `my-pack/` since Module 01 gets used for real,
not just kept. Before you call this module done, make sure `my-pack/` actually holds:

- `cheatsheet.md`, your terminal survival card from Modules 01 and 02.
- `recipe-safe-script-direction.md`, your safe-script-direction recipe from Module 04.
- `real-folder-ritual.md`, your real-folder ritual notes from Module 09.
- At least five more real entries from Modules 05 through 08 - your research-prompt template, your
  document-drafting recipe, your CSV-task recipe, and the batch-rename and mail-merge recipes from
  Module 08, at minimum.

If any of those went missing along the way, this is the moment to go back and actually write them,
not skip past it - the whole point of the pack is that it's still here when you need it.

Then write `10-capstone/answers.txt`, a short reflection in your own words: what from the pack you
actually reached for today, what (if anything) you had to figure out fresh, and what's still
missing from the pack that you'd want next time.

## Required to advance

**A checklist you run yourself.** From inside your workshop folder:

```
bash checks/check.sh 10
```

This checks, for real: all five artifacts against this module's own capstone fixtures (not any
earlier module's), each one using the same mechanism its source module taught - exact headers and
distinct-source citation counting for the research brief, a script-computed total and extremes for
the crew report, exact-figure matching for the budget write-up, a recomputed merge with the correct
conflict winner for the guest list, and byte-for-byte renamed photos plus placeholder-free letters
for the last part - and then the pack itself: the three named files, at least five more real
entries, and your workshop folder's `CLAUDE.md` still carrying the headers Module 03 asked you to
preserve. It prints `RESULT: PASS` with every item checked when everything's there. As always, the
message next to anything still failing says exactly what's missing.

**A short write-up.** `10-capstone/answers.txt`, from the pack-building step above - a genuine
reflection on what you actually used today, in your own words. Same rule as every prior module's
answers file: this isn't graded on a particular answer, and it isn't something Claude Code can
fill in for you convincingly. It's the one part of this module that's about you, not the files.

One honest limit, same shape as every earlier module's: this checklist can confirm the right files
exist with the right shape and the right numbers. It can't confirm Claude Code did the research,
the drafting, or the renaming rather than you doing it by hand and pasting the result in - the same
provenance limit every module before this one already carries. What it can confirm, completely,
is whether the work is actually correct against this module's own new facts.

## Takeaway

The full assembled pack, used for a real job today: `CLAUDE.md`, `cheatsheet.md`, a research
template, a drafting recipe, a safe-script-direction recipe, a CSV-task recipe, batch-rename and
mail-merge recipes, and the real-folder ritual - the literal artifact of "fluent," and the thing
you keep after this workshop ends.

---

*This is the last module. If you're looking for what to do next, `my-pack/` is it - the next real
job that looks anything like today's is the one it's for.*
