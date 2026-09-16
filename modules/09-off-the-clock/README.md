# Module 09: Off the Clock

## The question this module answers

How do I do any of this on my own real files without hurting myself?

Tilghman catches you on your way out one evening and tosses you a set of keys. "Take the office
laptop home if you need to. You've got the run of the place now." He means it as a compliment.
It's also, without either of you quite framing it this way, the first moment nothing at the Double
Deuce is fenced off from you anymore.

Everything up to now has happened inside the workshop folder Tilghman handed you on day one:
Garrett's old files, fictional from the start, safe to point Claude Code at without a second
thought. Today's job is different. It's the one time this workshop deliberately asks you to step
outside that folder and work with something real, on purpose, using a ritual built to make that
safe: copy in, back up, manifest, preview, verify.

## Before you start

You'll need Modules 03 and 04 finished. Module 03 is where you learned to direct Claude Code to
change a real file and to write its house rules for how the office works; Module 04 is where you learned to direct it
through a plan-preview-run-verify cycle without reading the code yourself. Both habits matter
today, aimed somewhere new. Budget about 45-60 minutes, maybe a little more the first time through.

**One thing worth saying plainly before you start:** everything in this module happens on your own
machine, using either a couple of your own real files or the stand-ins this workshop provides. At
no point does this module, or its checklist script, ask you to send a file anywhere, paste content
into this page, or show your files to anyone. The checklist only ever looks at filenames, checksums
(short fingerprints computed from a file's contents, used to prove two files match without
comparing them by eye), and counts. It never prints, or needs to print, what's actually written
inside any file.

## Part 1: choose real files or stand-ins

You have two honest options here, and neither one is the "right" answer:

**Option A: use a few of your own real files.** Two or three low-stakes ones: an old note, a
draft, a list, something you wouldn't mind Claude Code reading. Not anything financial, medical,
password-related, or tied to confidential work. This option exercises the real stakes this module
is actually about (your own files, your own judgment about what's safe to point an agent at), and
it's why this module exists at all.

**Option B: use the stand-in files this workshop provides**, at
`fixtures/stand-in-files/` inside your workshop folder: `note-to-self.txt`,
`weekend-packing-list.txt`, and `recipe-notes.txt`. They're short, plainly fictional, and safe by
construction. Named plainly: this is an honestly **partial** substitute. Since nothing in them is
actually yours, this option doesn't put anything real at stake, which means it can't fully teach
the part of this exercise that's about *your own* judgment call over *your own* files. It's still a
completely reasonable choice, especially the first time, and the checklist script passes exactly
the same way either way.

Whichever you pick, remember: whatever Claude Code reads as part of this exercise is handled the
same way every request to it is (prompts and the file content needed to answer them leave your
machine to be processed, same as every other module). That's true of any file you ever point it
at, not something special about this module, but it's worth naming clearly right at the point
you're choosing real content for the first time.

## Part 2: copy in

Create one real folder outside your workshop folder, at a fixed spot this whole exercise uses:
`~/wade-in-real-folder` (`~` is short for your home folder, the personal folder your user account
starts in, the same one Desktop and Documents already live inside).

From inside your workshop folder:

```
mkdir ~/wade-in-real-folder
```

**If this prints `mkdir: ...: File exists`,** something is already sitting at that exact spot -
stop and look at what's there first (`ls ~/wade-in-real-folder`) rather than continuing past it.
This module's checklist looks specifically at this one fixed location, so the fix isn't to use a
different folder name - it's to make sure this exact folder is empty and actually yours before you
go on. If it's left over from an earlier attempt at this module, clear it out
(`rm -r ~/wade-in-real-folder` removes it entirely, then `mkdir` again) and start clean. If it's
something unrelated you don't recognize, stop and figure out what it is before touching it - don't
copy your exercise files into a folder you didn't set up yourself, and don't delete something you
don't understand.

Now copy your chosen files in, one at a time, by exact name. (Typing each `cp` out individually,
rather than using a wildcard like `*.*`, is worth the extra typing here. A wildcard copies
whatever happens to match the pattern, which is a worse habit to build for a folder that might
someday hold something more real than this exercise.)

If you're using the stand-ins:

```
cp fixtures/stand-in-files/note-to-self.txt ~/wade-in-real-folder/
cp fixtures/stand-in-files/weekend-packing-list.txt ~/wade-in-real-folder/
cp fixtures/stand-in-files/recipe-notes.txt ~/wade-in-real-folder/
```

If you're using your own files, the idea is the same, just with your own source paths, for example:

```
cp ~/Desktop/some-file.txt ~/wade-in-real-folder/
```

Repeat for each file you're bringing in. When you're done:

```
ls ~/wade-in-real-folder
```

Confirm you see exactly the files you meant to copy in, nothing more.

## Part 3: back up

Before Claude Code goes anywhere near this folder, make a real backup, by hand, while you know
exactly what's in it:

```
mkdir ~/wade-in-real-folder/backup
```

Then copy each file in by exact name again, same discipline as Part 2:

```
cp ~/wade-in-real-folder/note-to-self.txt ~/wade-in-real-folder/backup/
```

(Repeat for each file.) This is your undo story for today: if anything goes wrong later, the
answer is "copy it back out of `backup/`," not "hope Claude Code can undo it" or "hope you
remember what it used to say."

## Part 4: manifest

A **manifest**, for this exercise, is just a plain list of filenames, written down before you
change anything, so there's a real record of exactly what was there at the start. Write yours now,
still from inside your workshop folder:

```
mkdir -p 09-real-work
ls ~/wade-in-real-folder > 09-real-work/before-manifest.txt
```

This checklist script cares a lot about this file, and about proving *when* it was written, not
just trusting what it says. Run the checklist now, once, even though most of it will still show
`FAIL`:

```
bash checks/check.sh 09
```

That's expected and normal at this point, same as every other module's checklist mid-exercise.
What matters here: this run is what records, for real, that your before-manifest existed at this
point in time, before anything below happens. You can't back-date that later by editing the file's
timestamp; the checklist never trusts a file's timestamp, only its own clock, the first time it
sees this exact manifest.

## Part 5: preview

**Optional, worth doing anyway:** before you launch a session here, create a short `CLAUDE.md` file
directly inside `~/wade-in-real-folder/` (any text editor works, same as every answers file so
far) telling it to stay inside this folder. Something like:

```
Stay inside this folder. Don't read, write, or touch anything outside
~/wade-in-real-folder, including backup/ unless I specifically ask about it.
```

This is the same technique Module 03 taught for the workshop folder, pointed at your new real one.
It's an instruction, not a lock (nothing stops a session from being asked to ignore it), and it
only takes effect from the start of a session, not partway through, which is why it's worth
creating before you launch Claude Code here rather than after. Still a real, cheap habit worth
keeping every time you open Claude Code somewhere new.

Now, and only now, point Claude Code at the real folder itself:

```
cd ~/wade-in-real-folder
claude --permission-mode default
```

Ask for something small and strictly additive, nothing that renames, moves, or deletes anything.
Something like this works as a starting point:

```
Read the files directly in this folder (not backup/) and write a short, one-line description of
each one into a new file called index.txt in this same folder. Don't rename, move, or change any
of the files you read, and don't touch anything in backup/.
```

Because you launched with `--permission-mode default`, Claude Code will stop and show you exactly
what it's about to write before it writes it, the same permission prompt from Module 02. Read it.
That's the "preview" this whole ritual is named for: seeing the actual proposed change before you
say yes, every time, especially the first time you're doing this on something real. Approve it once
you've actually read it.

When it's done, exit with `Ctrl+D` twice, and `cd` back to your workshop folder.

## Part 6: verify

Check your real folder now has the new file, and nothing else changed:

```
ls ~/wade-in-real-folder
```

Write your after-manifest, the same way as before:

```
ls ~/wade-in-real-folder > 09-real-work/after-manifest.txt
```

Run the checklist again:

```
bash checks/check.sh 09
```

This is where the whole ritual gets checked for real: your backup matches what was actually there
before you started (not just in name, but byte for byte); your before-manifest really was recorded
before your after-manifest, not just placed in that order; and (below) the safety exercise and your
own safety plan. If anything still shows `FAIL`, the message next to it says exactly what's still
missing.

## The safety exercise

This module teaches two hard lines. Both matter, and the exercise below tests whether you can
actually apply them to a new situation, not just recognize the words:

1. **Only ever point Claude Code at paths inside the one real folder you deliberately set up for
   this.** Never at a path outside it, even to grab one more file, even "just to take a quick
   look." You decide what goes into that folder, by hand, before a session starts. A session
   reaching out to grab more on its own is exactly what this rule exists to catch.
2. **Never let Claude Code touch, move, or empty `backup/`.** Backup is your undo story. The
   moment it becomes part of the task instead of your safety net, you've lost the one thing that
   was supposed to protect you if something went wrong.

Six situations. Exactly three are safe under the two rules above. Read all six before you answer;
a couple of them only make sense once you actually apply the rule, not just skim for a scary word.

1. You're working in your real folder and, since Claude Code is already open, you ask it to "also
   take a look at my Downloads folder while it's there and tidy up anything obviously old."
2. You ask Claude Code to read the files sitting directly in your real folder and write a
   one-paragraph summary of each into a new file in that same folder.
3. You ask Claude Code to grab a copy of an old file from your Documents folder and add it to your
   real folder, since it might be useful for the task.
4. Claude Code proposes a plan to sort the files in your real folder into two subfolders by type,
   shows you exactly which files would move where, and you approve it after checking the plan
   doesn't touch anything in `backup/`.
5. Claude Code finishes the task and mentions that `backup/` is just taking up space now that
   everything looks done, and offers to empty it out. You say yes, since the task looks finished.
6. Before asking Claude Code to rename anything in your real folder, you check that `backup/`
   already contains a copy of every file, then ask it to show you its plan before it renames
   anything, and you read the plan carefully before approving.

Create `09-real-work/safety-quiz-answers.txt` containing one line, naming the three situation
numbers you think are safe, in this exact form:

```
SAFE_SITUATIONS: 2, 4, 6
```

(Those are example numbers, not the answer. Work it out from the two rules above.)

## Required to advance

**A checklist you run yourself.** From inside your workshop folder:

```
bash checks/check.sh 09
```

This checks, for real: the workshop's own stand-in files are intact; your real folder exists
outside the workshop folder; `backup/` contains exactly the files your before-manifest named, each
one byte-for-byte identical to the original (checked by checksum, not just by name, since a name
match alone wouldn't catch an empty or corrupted backup); both manifests exist and were timestamped
by the checklist itself, in the right order; at least one genuinely new file exists from Part 5's
directed task (not just two manifests that happen to be in order - something real actually has to
show up); and your safety exercise answer names exactly the right three situations. It prints
`RESULT: PASS (9/9)` when everything's there. As always, the message next to anything still failing
says exactly what's missing.

Two honest limits, worth knowing plainly rather than glossed over, since this is the one module
where getting this wrong has real consequences. First: this checklist can't prove you actually read
the permission prompt in Part 5 before approving it, or that Claude Code itself (rather than you,
by hand) produced the new file - the same provenance limit every earlier module's checks already
carry. Second, and more specific to this module: "before is recorded before after" proves the
checklist's own two stamps are in the right order, not that your backup genuinely reflects how
things stood before Part 5 started. If something already went wrong with a file before you ran the
backup step - a bad edit, a mistake, anything - and you only made the backup afterward, this
checklist has no way to catch that; it would still report a clean pass, because from its own
vantage point everything it can see happened in the right order. The real protection here isn't the
checklist. It's doing the ritual honestly, in the order it's taught, before anything happens that
you'd need it for - not after.

**A short answers file.** Create `09-real-work/safety-plan.txt` containing three lines, each
starting with the label shown:

```
NEVER_TOUCH: <what you would never point Claude Code at, and why>
UNDO_STORY: <what your undo story is - how you'd actually recover if something went wrong>
MY_LINE: <where your own line between sandbox and real sits, in your own words>
```

Same rule as every earlier module's answers file: copying the bracketed prompts above word for
word won't pass. This isn't a script Claude Code can help you get right, and it isn't graded on
being "correct." It's a real plan, in your own words, that's actually worth having before the next
time you point any AI tool at something that matters.

## Takeaway

Add a new file to your pack, `my-pack/real-folder-ritual.md`, in your own words, covering:

- The five-step ritual: copy in, back up, manifest, preview, verify.
- The two hard lines from the safety exercise above.
- Your own safety plan from `09-real-work/safety-plan.txt`, or a pointer to it.

This is the one page in your pack you're most likely to actually reread before doing this for real
again, on something that matters more than a stand-in packing list.

---

*Next: [Module 10, Opening Night](../10-opening-night/README.md), the capstone, which asks you to
re-read this module's ritual against a question of its own before you finish.*
