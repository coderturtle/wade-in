# Module 08: Opening Week Machine

## The question this module answers

Can I automate the repetitive stuff instead of doing it by hand, twenty-five times?

Opening week is a blur. Jack Crews, who handles logistics and deliveries, drops two things on
your desk: a folder of 25 delivery photos (stage gear, the bar install, the new marquee) named
whatever his phone called them, `IMG_0001.jpg` through `IMG_0025.jpg`, and a handwritten sheet
mapping each one to a real name - by date and what it's actually a photo of. He wants the real
names used before anyone else needs to find one of these.

Down the hall, Penny Johnson needs something different: six booking confirmations, one per
client on her spring calendar, each one personalized with that client's name, event date, and
amount due. She has a CSV and a short letter template. Both jobs are the same shape underneath -
one input row, one output file, repeated - and both are exactly the kind of task Claude Code
should be doing for you, not you doing it 25 times by hand.

## Before you start

You'll need Module 04 finished (directing a script without reading its code) and Module 07
finished (spreadsheet-shaped work with a stated rule and a before/after count). This module
leans on both: renaming from a mapping file is scripted automation over real files, and filling a
letter template from a CSV is the same row-by-row discipline Module 07 taught, aimed at a new
kind of output.

This module has two separate halves. Do them in either order - nothing in one depends on the
other.

## Part 1: batch-renaming Jack's photos

Jack's photos live in `fixtures/photos/` - 25 files, `IMG_0001.jpg` through `IMG_0025.jpg`.
His mapping sheet is `fixtures/photo-mapping.csv`, two columns: `original_filename` and
`new_filename`. Open it yourself first and look at a few rows, so you know what you're asking
for before you ask for it.

The job: for every row in that mapping, copy the matching photo from `fixtures/photos/` into a
new folder, `08-auto/photos/`, under its new name. Copy, not move - the originals in
`fixtures/photos/` need to stay exactly where they are; the checklist below compares each
renamed file against its original to prove nothing got corrupted along the way, and it can only
do that if the original is still there.

Ask Claude Code for this directly. Something like:

```
Read fixtures/photo-mapping.csv. For every row, copy the file named in original_filename from
fixtures/photos/ to 08-auto/photos/, saving it under the name in new_filename. Don't touch or
delete anything in fixtures/photos/ - copy, don't move. There are 25 rows; when you're done, tell
me how many files you copied.
```

Watch what Claude Code proposes before you approve it, same habit as every module before this
one. When it's done, open `08-auto/photos/` yourself and spot-check two or three files against
the mapping sheet - do the new names actually match what the sheet says for those original
filenames?

## Part 2: Penny's confirmation letters

Penny's six bookings live in `fixtures/bookings-for-letters.csv` - one row per client, with
`name`, `event_date`, and `amount` columns. Here's the letter template she wants used, exactly as
she wrote it:

```
Dear {{name}},

Thanks for booking with The Double Deuce for your event on {{event_date}}. We're looking
forward to it.

Total amount due: ${{amount}}

See you then,
Penny Johnson
Events & Programming Lead, The Double Deuce
```

The `{{name}}`, `{{event_date}}`, and `{{amount}}` pieces are placeholders - each one needs to be
replaced with that row's real value, for every one of the six rows, with nothing left over in
`{{double-brace}}` form anywhere in the final letters.

The job: for every row in `fixtures/bookings-for-letters.csv`, produce one filled-in letter and
save it into a new folder, `08-auto/letters/` - six files total, one per client. Filenames are
your call; the content is what matters.

Ask Claude Code for this directly, giving it both the CSV and the template:

```
Read fixtures/bookings-for-letters.csv. For each of the 6 rows, take this letter template and
replace {{name}}, {{event_date}}, and {{amount}} with that row's real values, then save the
result as its own file in 08-auto/letters/ - six files total. Make sure no {{ placeholder is
left unfilled anywhere in any of the six letters. Here's the template:

Dear {{name}},

Thanks for booking with The Double Deuce for your event on {{event_date}}. We're looking
forward to it.

Total amount due: ${{amount}}

See you then,
Penny Johnson
Events & Programming Lead, The Double Deuce
```

Once it's done, open two or three of the letters yourself and check them against the CSV row
they're supposed to match - right name, right date, right amount, nothing left as a raw
placeholder.

## Required to advance

**A checklist you run yourself:**

```
bash checks/check.sh 08
```

This checks, for real, across both halves: all 25 photos are renamed into `08-auto/photos/`
exactly as the mapping sheet says - the full set, nothing extra, nothing missing - and each
renamed file is checksum-verified byte-identical to its own original, proving it was actually
copied and renamed, not corrupted or regenerated from scratch; and all 6 letters exist in
`08-auto/letters/`, each one containing its own row's exact name, event date, and amount, with a
literal `{{` placeholder count of zero across every letter. It prints `RESULT: PASS (n/n)` when
everything's there.

One honest limit, same shape as every module before this one: this checklist confirms the output
has the right names, the right bytes, and the right values in the right places. It can't tell
whether Claude Code actually did the renaming and merging versus you doing it by hand, and it
can't judge whether the letters read well - only that the required facts are in them.

**A short write-up.** Create `08-auto/answers.txt`, containing two lines, each starting with the
label shown:

```
REUSABLE: <could this same template-and-mapping approach run again next month with new inputs? What would have to change, and what would stay the same?>
FIRST_CHANGE: <the first thing you'd change about how you asked for this job, if you ran it again>
```

Same rule as every module before this one: copying the bracketed prompts above word for word
won't pass. Write your own answer, even a short one - this is about whether you actually
understand why the pattern generalizes, not just whether it worked once.

## Takeaway

Two reusable mini-recipes added to `my-pack/`: **batch-rename-from-mapping** (point Claude Code at
a folder of files and a mapping sheet, ask it to copy-and-rename the whole set, verify a sample by
hand) and **mail-merge-from-CSV** (point it at a CSV and a template with placeholders, ask it to
produce one filled file per row, verify no placeholder survives). Both are the same underlying
move - one row or one mapping entry becomes one output file - and both are worth reaching for any
time a job says "do this same thing 25 times."

---

*Next: [Module 09, Off the Clock](../09-off-the-clock/README.md) - the first module that asks you
to step outside this sandboxed folder, on purpose, with a taught safety ritual for working with
your own real files.*
