# Module 04: Let It Run

## The question this module answers

Can I have Claude Code write and run a small script for me, directing and verifying without ever
reading the code?

Frank Tilghman stops by your office with a stack of paper. "Garrett kept a nightly door count.
Every single night, on its own little slip. Never once added them up." He drops the stack on your
desk. "I need last month's total. Carl Bruner's doing the books this quarter, and he will want
exact figures. Not 'about.' Exact."

Twelve nights, twelve numbers, no total anywhere. Today's job: get Claude Code to add them up for
you, the right way. Not by asking it to just tell you the answer in the chat window, and not by
adding twelve numbers yourself, either. You're going to have it write a small script that does the
counting, run that script for real, and then check the result against the raw slips yourself.

## Before you start

You'll need Module 03 finished, and a workshop folder you're comfortable working in by now. If
it's been a while, run the same quick check you have every module since 01: `pwd`, and confirm it
ends in your workshop folder's name.

One thing worth saying plainly before you start: you do not need to read or understand the script
Claude Code writes for this. That's the actual point of this module, not a shortcut around it. You
direct what it should do, you watch it run, and you check the *result* against the real files
yourself. The script's own contents are Claude Code's business, not yours.

## Part 1: twelve nights, no totals

Look in `fixtures/` for twelve files named `door-count-2026-08-01.txt` through
`door-count-2026-08-12.txt`, one per night. Open one in a text editor to see the shape - each file
is two lines:

```
Date: 2026-08-01
Count: 154
```

That's the whole format: a date line, a count line, one file per night. Twelve files, twelve
nights, nobody's added them up. That's what Tilghman handed you, and it's exactly what Claude Code
will work from.

## Part 2: ask for a plan before you ask for a script

Open a session the same way you have since Module 02, in whichever permission mode you've settled
into by now. If you'd like to see every step approved individually again, launch with
`claude --permission-mode default` like you did back then.

Before asking for anything to be written, ask what the plan is. Something like:

```
I need the total door count for August from the 12 files in fixtures/door-count-*.txt, plus which
night was the busiest and which was the slowest. Before you write anything, tell me in plain
English how you'd do this - what you'd read, what you'd calculate, and where you'd save the
result. Don't write or run anything yet.
```

Read what comes back. This is the habit this module is really teaching: a plan you can read and
sanity-check in plain English, before any file gets written or any script gets run. If the plan
looks like it does something other than what you asked - reads the wrong files, guesses at a
format, skips a night - say so and ask for it to change before you say go. There's no wrong way to
push back here; that's what this step is for.

## Part 3: have it write the script, then run it

Once the plan looks right, ask for the actual work. Be specific about where the result needs to
land and what it needs to contain, the same way Module 02 taught you to be specific about a
summary's shape. Something like this works as a starting point:

```
Write a short script that reads all 12 files in fixtures/door-count-*.txt, adds up every night's
Count to get the August total, and finds the single busiest night (highest count) and the single
slowest night (lowest count). Run the script, then save its result to 04-scripts/door-report.txt
in exactly this format, five lines, each starting with the label shown:

TOTAL: <the August total>
BEST_NIGHT_DATE: <date of the busiest night, e.g. 2026-08-08>
BEST_NIGHT_COUNT: <that night's count>
WORST_NIGHT_DATE: <date of the slowest night>
WORST_NIGHT_COUNT: <that night's count>
```

You'll see at least one permission prompt here - creating the script file, and again to run it.
Read before you accept, same as every module since 02. Once it reports back, `04-scripts/` should
contain both the script itself and `door-report.txt`.

## Part 4: verify one night by hand

Don't just trust the total. Pick one night - the busiest one is a good choice, since it's called
out by name in the report - and open its raw file yourself: `fixtures/door-count-2026-08-08.txt`,
or whichever date the report names as busiest. Confirm the `Count:` line in that raw file actually
matches what `door-report.txt` claims for that night.

This is the same discipline Module 02 taught for a summary and Module 03 taught for a correction:
Claude Code is usually right, and "usually" is exactly why you check. A script can have a bug the
same way a person can make an arithmetic mistake - the difference is a script's mistake is
consistent and easy to miss if nobody ever looks at a raw number next to its claimed total.

## Required to advance

**A checklist you run yourself.** From inside your workshop folder:

```
bash checks/check.sh 04
```

This checks, for real: `04-scripts/` is a real folder (not a shortcut standing in for one);
`04-scripts/door-report.txt` exists and was actually written there (not a shortcut, and not some
other trick that avoids the file really being written); all 12 raw `door-count-*.txt` files are
still exactly what they started as, checked against a copy of their real content sealed into the
checklist itself - if Claude Code (or anything else) ever "corrected" one of the raw files to match
a wrong total instead of the other way around, this catches it and tells you plainly to contact the
workshop, not to trust the result; the August total in your report is exactly right, recomputed
from the raw files independently rather than compared against a number the checklist has
memorized; the busiest night's date and count are both exactly right; the slowest night's date and
count are both exactly right; and you've filled in a short answers file, in your own words, below.
It prints `RESULT: PASS (7/7)` when everything's there.

**A short answers file.** Create `04-scripts/answers.txt`, containing three lines, each starting
with the label shown:

```
PLAN_FIRST: <did you ask Claude Code for a plan before it wrote the script - what did you ask for?>
CHECKED_BY_HAND: <which night's figure did you verify by hand against its raw fixture file, and what did you find?>
WHAT_NEXT_TIME: <what would you do differently next time you ask Claude Code to write and run a script?>
```

Same rule as every module so far: copying the bracketed prompts above word for word won't pass.
Write your own answer, even a short one.

## Takeaway

Add a new page to your pack: `my-pack/recipe-safe-script-direction.md`. Write down, in your own
words, the four-step rhythm this module just walked you through:

1. **Plan** - ask what it would do before asking it to do anything.
2. **Preview** - read the plan (and the permission prompt) before saying go.
3. **Run** - let it write and run the script.
4. **Verify** - check at least one real result by hand against a raw source file.

This is the recipe you'll reach for any time you want Claude Code to automate something small for
you, in this workshop and after it. You're not writing this recipe to describe *this* script - it's
generic on purpose, so it still applies the next time the files and the numbers are completely
different.

---

*Next: [Module 05, Homework for Utah](../05-homework-for-utah/README.md) - a different kind of
task, sending Claude Code out to the web instead of into local files. It only needs Module 02, so
you could technically do it before this one, but the arc goes in order for a reason. Modules 07,
08, and 09 all build directly on the plan-preview-run-verify rhythm you just practiced here, so
it's worth having it solid before you move on.*
