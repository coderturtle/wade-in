# Module 06: The Bruner Report

## The question this module answers

Starting from raw numbers, can I direct a client-ready document into existence with every figure
exact?

Carl Bruner does the Double Deuce's books. He shows up once a month, on the same day, and he
wants one thing before he'll look at anything else: a summary in his format, with figures he
doesn't have to double-check against your working notes, because he's going to double-check them
anyway.

> "I don't need your notes. I need the number. If the number's wrong, I will find it - I always
> do - and then we're both spending the afternoon figuring out why."
>
> - Carl Bruner, on his way out the door last month

Doc Clay hands you her raw numbers file for the month - unformatted, not proofread, exactly what
she jotted down as the weeks went by - and asks you to turn it into the document Carl actually
wants. That's today's job: direct Claude Code to draft it, tell it exactly what shape and figures
it has to contain, and check every number yourself before it goes out.

## Before you start

You'll need Module 03 finished - the file-direction skill you built there (pointing Claude Code at
a specific source file and getting a specific, correct result back) is exactly what this module
asks you to do again, against a different kind of document. If it's been a while, run the same
quick check as always: `pwd`, confirm it ends in your workshop folder's name, `cd` back in if not.

## Part 1: read the raw numbers yourself first

Before you ask Claude Code for anything, open `fixtures/monthly-raw-numbers.txt` and read it. It's
Doc's own working notes - four weekly revenue figures, three more figures Carl will want, and a
line from Doc making the stakes plain. Notice that the monthly total isn't written down anywhere
in that file. Doc said as much: adding the four weeks correctly is part of the job, not something
already done for you.

You're reading this first for the same reason Module 02 had you read the source file before
trusting a summary of it: you can't tell whether a draft's numbers are right later if you don't
know what "right" looks like now.

## Part 2: tell Claude Code exactly what Carl needs

Carl doesn't want prose that wanders toward a number eventually. He wants a specific document:
five sections, in a specific order, with specific headers, holding specific figures - and nothing
padded out past a reasonable length. A vague request here produces a vague document, so this is a
case where being exact in your request matters more than being polite about it.

The document you produce, `06-docs/monthly-summary.md`, needs:

- All five of these section headers, written exactly as shown, each on its own line:
  - `## Summary`
  - `## Revenue Breakdown`
  - `## Notable Items`
  - `## Comparison to Prior Month`
  - `## Prepared By`
- The month's total revenue - the sum of all four weekly figures in the fixture - stated exactly,
  somewhere in the document.
- The three other exact figures from the fixture (the bar tab total, the door revenue total, and
  the number of events held) stated exactly, somewhere in the document.
- A prior-month comparison: there's no prior-month data in this workshop, so that section should
  say so plainly (`N/A - no prior-month data available` works fine) rather than invent a number.
- A total length between 150 and 400 words.

Something like this works as a starting request:

```
Read fixtures/monthly-raw-numbers.txt and draft 06-docs/monthly-summary.md for Carl Bruner, our
accountant. Use exactly these five section headers, in this order: "## Summary",
"## Revenue Breakdown", "## Notable Items", "## Comparison to Prior Month", "## Prepared By".
Add up the four weekly revenue figures yourself and state the exact monthly total. Also include
the bar tab total, the door revenue total, and the number of events held this month, all exactly
as given in the source file. There's no prior-month data, so say that plainly in that section
instead of guessing. Keep the whole document between 150 and 400 words - Carl wants a summary, not
a data dump.
```

Naming the reader (Carl, an accountant who checks every figure) is doing real work in this
request, not just flavor - it's the difference between a document that reads like a summary
somebody will actually use and one that reads like an internal notes dump with headers stapled on.

## Part 3: verify every figure yourself

Once Claude Code reports back, open `06-docs/monthly-summary.md` next to
`fixtures/monthly-raw-numbers.txt` and check the arithmetic and the figures by hand, the same way
Module 02 had you check a summary against its source. Specifically:

- Add the four weekly figures yourself. Does the document's total match what you got?
- Are the bar tab total, door revenue total, and event count each exactly what the source file
  says - not rounded, not approximated?

This is the actual point of the module, not a formality after the fact. Carl's line at the top of
this page is the honest version of what the checker below does mechanically: it recomputes the
total itself from the raw figures and expects an exact match, the same way a real accountant
would. A draft that's close isn't a draft that's right.

## Required to advance

**A checklist you run yourself.**

```
bash checks/check.sh 06
```

This checks, for real: `06-docs/monthly-summary.md` exists as a real file (not a symlink or hard
link standing in for one), inside a real `06-docs/` directory (not a symlink); it contains the
exact monthly total, **recomputed by the checker from the four weekly figures in
`fixtures/monthly-raw-numbers.txt`** - not a number this script has memorized, so the check stays
correct even if the fixture's own figures ever change; it contains the bar tab total, the door
revenue total, and the event count, all three read directly from that same fixture; all five
required section headers appear, written exactly as specified; and the whole document is between
150 and 400 words. It prints `RESULT: PASS (n/n)` when everything's there.

One honest limit, same as every module before this one: this check confirms the document has the
right shape and the right numbers in it. It can't tell whether you actually did the arithmetic
yourself versus trusting Claude Code's first draft, and it can't tell a genuinely accountant-ready
summary from five headers wrapped around the right numbers with no real sentences in between - no
local check can catch either of those. That's what Part 3, and the write-up below, are actually
for.

**A short answers file.** Create `06-docs/answers.txt`, containing three lines, each starting with
the label shown:

```
READS_LIKE_A_SUMMARY: <does the document read like something you'd hand an accountant, or like your own working notes with headers added - and what would you change?>
VERIFIED_HOW: <specifically, how did you check the figures yourself before trusting the draft?>
WHAT_CARL_NOTICES: <in your own words, what's the actual risk if one figure in a document like this is wrong?>
```

Same rule as every module before this one: copying the bracketed prompts above word for word won't
pass. Write your own answer, even a short one.

## Takeaway

Add `my-pack/recipe-document-drafting.md`: a document-drafting prompt template built from what
worked today - name the source file, name the exact output path, spell out the required structure
(section headers, in order), and state the exact-figures constraint plainly, the same way Part 2's
request did. This is the shape of request that turns "draft me a summary" from a guess into
something with a checkable right answer. The capstone checks for this file by its exact name, so
use it as shown, not a name of your own choosing.

---

*Next: [Module 07, Penny's Ledger](../07-pennys-ledger/README.md) - the first time you'll direct
real spreadsheet-shaped cleanup, merging and deduplicating two overlapping CSVs without losing a
single row.*
