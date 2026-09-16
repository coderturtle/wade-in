# Module 03: Garrett's Filing System

## The question this module answers

Can I direct Claude Code to read and fix real files, and teach it how this office works?

Emmett catches you by the supply cabinet with a folded piece of paper in his hand. "Found
Garrett's old phone list taped up in here. Called four different numbers before I figured out
they were wrong. Wrote down what's actually right - figured you'd want it before somebody else
gets an earful from the kitchen."

Doc Clay, passing by, adds the second half of the job: "While you're in there fixing that, do
something about having to explain this place to Claude Code every single session. Give it some
notes it'll actually remember next time."

Today's job has two parts: direct Claude Code to fix the phone list using Emmett's memo, and give
Claude Code a permanent set of house rules for this folder so you stop repeating yourself.

## Before you start

You'll need Module 02 finished - you should be comfortable opening a session, asking for something
specific, watching a permission prompt, and checking a result against its source. If it's been a
while, run the same quick check as before: `pwd`, confirm it ends in your workshop folder's name,
`cd` back in if it doesn't.

## Part 1: read what you're working with

Two files are waiting in `fixtures/`:

- `fixtures/staff-list.txt` - the staff phone list, exactly as Garrett left it.
- `fixtures/emmett-memo.txt` - Emmett's memo, listing what's wrong with it.

Open both yourself first, before you ask Claude Code to touch anything - same habit Module 02
ended on. You don't need to memorize what's wrong; just get a feel for the two documents you're
about to hand off.

## Part 2: direct the correction

Open a session inside your workshop folder (`claude`, same as before). This time you're asking
Claude Code to change an existing file, not create a new one from scratch - the first time this
workshop has asked that of you.

Ask for it in your own words. Something like this works as a starting point:

```
Read fixtures/staff-list.txt and fixtures/emmett-memo.txt. Emmett's memo lists corrections to
the staff list. Create 03-files/staff-list-corrected.txt: a copy of staff-list.txt with exactly
the entries Emmett's memo corrects changed to what the memo says they should be, and every other
line left completely untouched - same wording, same spacing, same everything.
```

The last part matters as much as the corrections themselves. "Every other line left completely
untouched" is a real constraint, not filler - Doc doesn't just want the four wrong numbers fixed,
she wants a file she can trust wasn't quietly rewritten somewhere else while it was open. Asking
for that explicitly is what makes it something you can actually verify afterward, not just take
on faith.

You'll see a permission prompt before Claude Code creates the file, same as Module 02. Read it
before you approve it.

## Part 3: verify it yourself

Don't just glance at the result and move on. Open `03-files/staff-list-corrected.txt`,
`fixtures/staff-list.txt`, and `fixtures/emmett-memo.txt` side by side. Check each of the four
corrections Emmett's memo describes actually landed, with the exact wording his memo gives. Then
check the opposite direction: pick two or three lines Emmett's memo *doesn't* mention, and confirm
they're still exactly what they were in the original - nothing rephrased, nothing "cleaned up"
along the way.

This second check is the one it's easy to skip. A correction that's right but came with a few
unrequested extra edits is a real, common way an otherwise-good result quietly stops being
trustworthy.

## Part 4: teach it how this office works

You've now told Claude Code the same kind of thing twice - what this folder is, what not to
touch, how you like things checked. Every session so far has started from zero. A `CLAUDE.md`
file sitting in a folder is different: Claude Code reads it automatically at the start of every
session that starts inside that folder, so anything genuinely useful you put there travels
forward without you retyping it.

Your workshop folder already has one, `CLAUDE.md`, sitting at its root - it's had a couple of
rules in it since Module 01, about not touching `checks/` and staying inside this folder unless a
module says otherwise. You're not replacing it. You're adding to it.

Ask Claude Code to add four new sections to that file, each starting with one of these exact
headings:

```
## About this folder
## House rules
## How I like output
## Never touch
```

The headings matter exactly as written - the checklist below looks for them verbatim. What goes
underneath each one is yours to write, though, and this is the part worth spending real time on.
Generic advice like "be careful" or "double-check your work" doesn't change anything about a
future session's behavior, because it doesn't say what to actually do differently. A rule earns
its place by being specific enough that it would visibly change what happens next time - something
drawn from what you've actually noticed about how this office's files work, not a rule that could
apply to any folder anywhere.

A starting point, not a script - write your own version once you see the shape of it:

```
Add four sections to CLAUDE.md at the root of this folder: "## About this folder" (a couple of
sentences on what this workshop folder is and who uses it), "## House rules" (specific rules
about how files in this office should be handled - for instance, phone lists and other records
here get corrected against a named source like a memo, never guessed at or rewritten from
scratch), "## How I like output" (how you want results formatted or checked before you consider
them done), and "## Never touch" (anything beyond checks/ that should stay untouched unless a
module says otherwise). Keep the existing content in the file - add these as new sections, don't
replace what's already there.
```

Read what Claude Code proposes before approving it, same as every file change so far. If a rule it
drafts reads generic, ask it to make that one more specific before you accept it - "note things
down carefully" isn't a house rule, "corrections to any list in this folder must cite which memo
or source justified the change" is.

## Required to advance

**A checklist you run yourself.** From inside your workshop folder:

```
bash checks/check.sh 03
```

This checks, for real: `03-files/staff-list-corrected.txt` exists and is a genuine file (not a
shortcut standing in for one); the workshop's own fixtures haven't been tampered with; all four of
Emmett's corrections were actually applied, re-derived from his memo's own wording each time this
runs rather than from a fixed answer this script has memorized - so it stays correct even if the
memo's exact phrasing is ever revised; every other line of the file matches the original, catching
any collateral edit anywhere else in the file, not just the four known spots (an incidental trailing
blank line at the very end of the file won't trip this, but a changed word anywhere will);
`CLAUDE.md` contains at least 3 of the 4 required headings, exactly as written above; and the
original safety headings from Module 01 are still there too - you're adding sections, not replacing
the file. It prints `RESULT: PASS (n/n)` when everything's there.

**A short answers file.** Create `03-files/answers.txt`, containing three lines, each starting
with the label shown:

```
HOUSE_RULE: <one house rule you wrote and what specific Double Deuce filing quirk it responds to>
WHAT_I_CHECKED: <how you checked the corrected file yourself, against the memo, rather than trusting it on sight>
WHAT_CHANGES: <in your own words, what will actually be different about a session's behavior now that CLAUDE.md has these rules>
```

Same rule as Modules 01-02: copying the bracketed prompts above word for word won't pass. Write
your own answer, even a short one.

One honest limit, worth knowing: the checklist confirms the four required headings are present.
It can't judge whether what you wrote under them is actually specific enough to change a session's
behavior - that's a real judgment call, and it's yours to make. Read back what you wrote in `##
House rules` once it's done and ask yourself honestly whether it would have told you, three
modules ago, what to actually do differently. If it wouldn't have, it's worth another pass before
you consider this one finished.

## Takeaway

`CLAUDE.md` v1 - the pack's spine. You won't rewrite this file every module from here on; later
modules mostly add their own separate recipe files to `my-pack/` instead. But this one keeps
traveling with you underneath everything else, so it's worth getting genuinely useful now rather
than later.

---

*Next: [Module 04, Let It Run](../04-let-it-run/README.md) - the first time you'll direct Claude
Code to write and run a small script on your behalf, without reading the code yourself.*
