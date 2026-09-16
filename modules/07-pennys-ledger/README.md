# Module 07: Penny's Ledger

## The question this module answers

Can I direct real spreadsheet-shaped cleanup, and prove nothing was lost?

Penny Johnson runs events and programming at the Double Deuce - bookings, talent schedules, guest
lists, the whole calendar. She corners you with two CSV files open side by side on her laptop.

> "This is what happens when nobody hands off properly. My spring bookings are in this file. But
> Garrett was still logging some of these before he left, so his file's got stuff mine doesn't -
> and where we overlap, his numbers are stale. Tilghman wants one clean sheet, amounts due and
> all, before he'll sign off on anything. And I mean it when I say nobody's booking goes missing -
> if you drop the Founders Day Reunion because you fat-fingered a merge, I will find out."
>
> - Penny, sliding both laptops across the table

Today's job is a real merge: two overlapping CSVs, a stated rule for who wins when they disagree,
a new column to compute, and a way to prove to yourself - and to Penny - that every booking
survived and every number is right.

## Before you start

You'll need Module 04, Let It Run, finished - this module leans directly on the same habit that
one taught: ask for a plan before anything runs, and verify the result against the source data by
hand rather than taking a script's word for it. If it's been a while, or you've closed and
reopened your terminal since, run `pwd` and confirm it ends in your workshop folder's name before
continuing.

## Part 1: two files, one overlap

Open `fixtures/penny-bookings.csv` and `fixtures/garrett-bookings.csv` yourself first, in any text
editor or spreadsheet program you'd like - don't ask Claude Code to summarize them for you yet.
Both files share the same five columns: `booking_id,name,event_date,deposit,balance`. Look at the
booking IDs each file has, and which ones show up in both.

You'll find some IDs only in Penny's file, some only in Garrett's, and some in both - and for at
least one of the shared IDs, the two files don't agree. Find it yourself before moving on. This is
the actual shape of the problem: it isn't just "combine two files," it's "combine two files that
disagree with each other about some of the same bookings."

## Part 2: state the rule, then ask for the merge

Penny was clear about who's right when the two files disagree: **her file is authoritative for
any booking ID that appears in both** - she's the current owner of these bookings, and Garrett's
copy is the stale one. An ID that appears in only one file just carries through unchanged,
whichever file it came from.

The output has to land at `07-csv/bookings-clean.csv`, with exactly this header row, in this exact
order:

```
booking_id,name,event_date,deposit,balance,total_due
```

That's five columns from the source files plus one new one: `total_due`, which every row needs
computed as `deposit + balance`.

Ask Claude Code to do this for real, in your own words, but make sure your request actually states
the rule - "merge these two files" alone leaves the conflict resolution to guesswork, and this
module's gate checks that specific rule, not just that some merge happened. Something like this
covers the required pieces:

```
Read fixtures/penny-bookings.csv and fixtures/garrett-bookings.csv. Merge them into one CSV at
07-csv/bookings-clean.csv with the header booking_id,name,event_date,deposit,balance,total_due.
Every booking_id should appear exactly once. If a booking_id exists in both files, use Penny's
row - her file is authoritative on conflict. If it only exists in one file, keep that row as-is.
Add a total_due column equal to deposit + balance for every row. Before you finish, tell me how
many unique booking IDs you found across both files, and how many rows the merged file has.
```

Asking for the before/after counts up front matters for Part 3 below - and it's the same habit
Module 04 taught: ask for a plan and a number you can check, not just a file.

## Part 3: verify it yourself

Don't take the row count Claude Code reports on faith - Penny won't, and the checker below
definitely won't. Do this by hand, the same way the example in `07-csv/answers.txt` below
describes:

- List the booking IDs in each source file yourself, and count how many *unique* IDs exist across
  both - that's the number of rows `bookings-clean.csv` should have.
- Pick the one ID you spotted disagreeing between the two files back in Part 1, and check its row
  in `bookings-clean.csv` matches Penny's file, not Garrett's.
- Pick one row that only existed in one source file, and confirm it carried through with its
  `total_due` correctly computed.

If your hand count and the file's row count don't match, something got merged wrong before you
even run the checklist - find it now, not after.

## Required to advance

**A checklist you run yourself.**

```
bash checks/check.sh 07
```

This checks, for real: both source fixtures are unmodified from how the workshop shipped them
(checksummed, so this can only be a workshop-side problem, never yours); `07-csv/bookings-clean.csv`
exists and has the exact required header row above, in that exact order; its row count equals the
checker's own recomputed count of unique booking IDs across both fixtures; its booking-ID set
exactly matches that recomputed set - no booking missing, none invented; for every surviving ID,
`name`, `event_date`, `deposit`, and `balance` exactly match the source-of-truth value under the
stated rule (Penny's file wins on any ID present in both); every row's `total_due` genuinely equals
that row's own `deposit + balance`; and you've filled in a short answers file, in your own words
(below). It prints `RESULT: PASS (n/n)` when everything's there.

**A short answers file.** Create `07-csv/answers.txt`, containing three lines, each starting with
the label shown:

```
DEDUP_RULE: <in your own words, what did the merge rule do whenever a booking ID showed up in both files?>
COLLAPSED_PAIRS: <name at least one booking ID that appeared in both files, and say what happened to it>
VERIFIED_NOTHING_LOST: <how did you satisfy yourself that nobody's booking went missing?>
```

Same rule as every earlier module's answers file: copying the bracketed prompts above word for
word won't pass. Write your own answer, grounded in what you actually did in Part 3.

## Takeaway

Add `my-pack/recipe-csv-task.md`: state the rule before you ask, demand a before/after count,
verify at least one sample row by hand against the real source file. This recipe generalizes past
today's bookings - it's the shape of any "combine two spreadsheets under a rule" task. The capstone
checks for this file by its exact name, so use it as shown, not a name of your own choosing.

---

*Next: [Module 08, Opening Week Machine](../08-opening-week-machine/README.md) - batch-renaming a
folder of delivery photos and mail-merging Penny's now-clean CSV into real confirmation letters.*
