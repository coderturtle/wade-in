# Module 02: Meet the New Hire

## The question this module answers

How do I ask Claude Code for something, watch what it proposes, and check what it did?

Doc Clay catches you in the hallway on your second morning. "Heard you got the office open.
Good. Do me a favor - pull up whatever Garrett had on this place's history and send me the short
version. Nothing fancy. I just want to know you can find things in there."

That's today's job: open a real Claude Code session for the first time, ask it to read a file
and write you a short summary, watch what it does before you let it do anything, and check the
result yourself before you hand it over.

## Before you start

You'll need Module 01 finished - a working terminal, `claude` installed, and you logged in at
least once. If it's been a while since Module 01, or you've closed and reopened your terminal
since then, do the same quick check Module 01 ended on: run `pwd`, and confirm it ends in your
workshop folder's name. If it doesn't, `cd` back in the same way you did there before continuing.

## Part 1: opening a real session

Everything in Module 01 happened without Claude Code actually doing anything on your behalf - you
were just getting the terminal itself and the install sorted. This is different. Type:

```
claude --permission-mode default
```

If you're already logged in (you should be, from Module 01), you'll land somewhere new: an
interactive **session** - a running conversation where you can type requests in plain English and
Claude Code will act on them, inside your workshop folder, one exchange at a time. This is what
the rest of this workshop actually looks like.

That `--permission-mode default` piece is deliberate, not decoration - explained in Part 3, but
worth knowing now: on most current accounts, a plain `claude` starts in a mode that quietly
approves everyday actions for you, without asking. That's a genuinely reasonable normal setting
once you have a feel for what Claude Code does, but today you're meeting it for the first time, so
this module puts you in the mode that asks first, every time, on purpose.

**Two more things worth knowing before you type your first request:**

- If Claude Code is in the middle of doing something and you want to stop it, press `Esc`. It
  keeps whatever work it already finished and waits for you to redirect it - the same idea as
  `Ctrl+C` for an ordinary command, just for a session instead.
- When you're done with a session, press `Ctrl+D` twice in a row (the first press shows a
  confirmation, the second within a second or so actually exits) - same as Module 01's login
  session. Don't exit yet, though - you'll need this session for the rest of this module.

## Part 2: asking for something real

Doc wants a short summary of the venue's history, pulled from `fixtures/venue-history.txt` -
Garrett's own notes, still sitting in the file cabinet. Ask for it in your own words - nothing
checks the exact wording of your request, only the result, so feel free to phrase this however
feels natural to you. Something like this works as a starting point:

```
Read fixtures/venue-history.txt and write a summary to 02-meet/summary.txt as exactly 3 to 5
separate lines - one short point per line, each on its own line with a real line break between
them, not one paragraph. Make sure the summary includes the venue's founding year and its
current capacity.
```

Being specific like this matters for two different reasons. Which file to read, where to save the
result, and what it has to include is most of what a good request looks like in general - a vague
request ("summarize the venue's history somewhere") makes Claude Code guess at details you
actually care about. The "each on its own line, not one paragraph" part is specific to this
exercise: asked more loosely, Claude Code will often write a perfectly good summary as flowing
prose instead of separate lines, and the checker below counts lines - so being explicit about the
shape you want isn't just good practice here, it's required to pass.

## Part 3: the permission prompt

Because you launched with `--permission-mode default`, Claude Code will stop and ask you before it
creates `02-meet/summary.txt`. This is called a **permission prompt** - Claude Code pausing before
it changes anything on your computer, showing you exactly what it's about to do, and waiting for
you to say yes.

In this mode, Claude Code asks this way the first time it wants to use a given kind of action in a
session - reading files never needs your approval, but creating or writing one does, every time,
until you tell it otherwise. You'll typically see a choice like: approve just this one time, allow
file changes for the rest of this session so it stops asking, or say no. There's no wrong answer
here - saying yes once is completely reasonable, especially while you're still getting a feel for
what Claude Code proposes before you approve things by habit.

Actually read what it's proposing before you approve it. That's the whole point of this step
existing - not a formality to click through.

**Worth knowing for every session after this one:** the mode you launched in today, where Claude
Code asks first, is one of several. Most accounts actually default to a different mode that
quietly approves everyday actions on your behalf without asking, using a separate check running in
the background instead of stopping for you. Today's module deliberately put you in the
ask-first mode so you'd see this step happen at least once, on purpose, before you meet the
quieter default. Neither is wrong - the quieter one is genuinely fine for routine work once you
trust what Claude Code tends to do - but it's worth knowing the option exists, and that you can
always switch back to ask-first mode by pressing `Shift+Tab` during a session, or by launching
with `--permission-mode default` again like you did today.

## Part 4: check the result yourself

Once Claude Code reports back, don't just trust it. Open `02-meet/summary.txt` yourself, then open
`fixtures/venue-history.txt` next to it, and confirm the summary actually reflects what the source
document says - the founding year and the capacity figure in particular, since those are the two
concrete facts Doc actually asked for ("so I know you can find things"). Any text editor your
computer already has works fine for this - Notepad on Windows, TextEdit on macOS, or your file
browser's own "open with" option, same as Module 01.

This is the habit this whole module is really teaching: ask, watch what gets proposed before
approving it, then check the result against the source yourself rather than taking it on faith.
Claude Code is usually right. "Usually" is exactly why the check matters.

## Required to advance

**A checklist you run yourself.** You can run this from inside your Claude Code session (just ask
it to run the command below) or exit first with `Ctrl+D` twice and run it directly, whichever you
prefer - both work exactly the same way:

```
bash checks/check.sh 02
```

This checks, for real: `02-meet/summary.txt` exists and is 3-5 lines long; it contains the venue's
founding year and current capacity, both read by the checker directly from
`fixtures/venue-history.txt` itself (not a number this script has memorized - if that source
file's *facts* ever change, the check changes with them); and you've filled in a short answers
file, in your own words (below). It prints `RESULT: PASS (n/n)` when everything's there.

One honest limit, worth knowing: this check confirms the summary file has the right shape and the
two required facts in it. It can't tell whether Claude Code actually produced those words versus
you typing them in by hand, and it can't tell a genuine summary from three bare, thrown-together
lines that technically contain the right numbers - no local check can catch either of those, and
this workshop won't pretend otherwise. The point of doing this exercise for real isn't to satisfy
a script; it's the habit Part 4 describes.

**A short answers file.** Create `02-meet/answers.txt`, containing three lines, each starting with
the label shown:

```
PERMISSION_PROMPT: <what happened when Claude Code asked to create or write the file - what did you see, what did you choose?>
WHY_ASKS: <in your own words, why does Claude Code ask before acting?>
WHAT_I_CHECKED: <one specific thing you checked yourself before trusting the summary>
```

Same rule as Module 01: copying the bracketed prompts above word for word won't pass. Write your
own answer, even a short one.

## Takeaway

Your terminal survival card grows. Add a new section to `my-pack/cheatsheet.md` covering what's
new today: launching a session in ask-first mode (`claude --permission-mode default`), asking for
something specific, interrupting with `Esc` if you need to redirect mid-task, exiting with
`Ctrl+D` twice, what a permission prompt is and why it exists, and "read before you accept" as a
habit worth keeping for the rest of this workshop.

---

*Next: [Module 03, Garrett's Filing System](../03-garretts-filing-system/README.md) - the first
time you'll direct Claude Code to actually change a real file, not just create a new one.*
