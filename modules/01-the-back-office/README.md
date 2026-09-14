# Module 01: The Back Office

## The question this module answers

What is this black window, and how do I tell it to do things?

Frank Tilghman, the owner, hands you the keys to your new office. It used to belong to a man
named Garrett, who's just retired. Most of what's in the office is still exactly how he left it.

> "You'll find things are a little behind. That's the job for the first few weeks: get this
> office caught up, one thing at a time. Nothing urgent today. Just get settled, figure out
> where things are, and make yourself at home."
>
> - Frank, in a note waiting on the desk

Today's job is smaller than it sounds: get the folder of files that came with the office open on
your own computer, and learn just enough about this black window to move around inside it.

## Before you start

You'll need:

- A computer you control - one where you're allowed to install software. macOS 13 or newer,
  Windows 10 (version 1809 or newer), or a common current Linux distribution all work. (Alpine
  Linux needs two extra packages installed first - if that's you, see the note in Part 3.)
- A paid Claude account (a Claude Pro, Max, Team, Enterprise, or Console account - the free plan
  doesn't include what this workshop uses).
- About 45-60 minutes, somewhere you won't be interrupted. This module is deliberately slow. If
  you already know your way around a terminal, most of this will feel obvious - that's fine, work
  through it anyway, since later modules build on the exact vocabulary this one sets up.

## Part 1: what a terminal actually is

Every computer has a program that lets you type instructions instead of clicking things. On a
Mac or Linux it's usually called **Terminal**. On Windows it's called **PowerShell**. Both do the
same job: you type a line of text (called a **command**), press Enter, and the computer does
exactly what you asked and shows you the result as more text.

That's genuinely most of what there is to know before you start. The rest is vocabulary you'll
pick up by doing it.

**Open it now:**

- **macOS**: press `Cmd + Space`, type `Terminal`, press Enter.
- **Windows**: press `Win + X` and choose **Windows PowerShell** (or **Terminal**) from the menu.
- **Linux**: open your terminal app - usually `Ctrl + Alt + T`, or search "Terminal" in your
  application menu.

A window opens with a blinking line waiting for you. That blinking line is called the **prompt** -
it's the computer telling you it's ready for your next command. You can't click on anything inside
this window the way you would in a normal app; everything happens by typing a command and pressing
Enter.

If you're on Windows, one quick check: PowerShell shows `PS C:\Users\YourName>` at the start of the
line. If what you see instead is just `C:\Users\YourName>`, with no `PS`, you're in a different
program called Command Prompt - close it and reopen using the steps above, since the commands in
this workshop are written for PowerShell specifically.

## Part 2: get the workshop folder open

Wade In gives you a folder of files to work with - the same one Tilghman handed you, in
scenario terms. Download it and unzip it somewhere you'll remember, like your Desktop or
Documents folder.

*(A one-click download of just this folder is planned but not built yet. For now: go to [the
wade-in repository on GitHub](https://github.com/coderturtle/wade-in), click the green **Code**
button, then **Download ZIP**. This downloads the whole project as one file, usually named
something like `wade-in-main.zip` - no git knowledge needed, just a browser. Unzip it, then look
inside the folder it creates for a folder named `workshop-folder`. That inner folder is the one
you actually want; everything else in the download can be ignored.)*

Once you've found that `workshop-folder`, move or copy it somewhere you'll remember, like your
Desktop, and rename it to something shorter if you'd like - `wade-in-workshop` is what the rest of
this module calls it. Everything from here on happens inside that folder.

### Moving into the folder

The terminal always has a "current location" - a specific folder it's paying attention to, the
same way a file browser window is always looking at some specific folder. This is called your
**current directory** ("directory" is just an older word for "folder"). Every command you run acts
on whatever's in your current directory, unless you tell it otherwise.

Type this, but replace the path with wherever you actually put the folder:

```
cd ~/Desktop/wade-in-workshop
```

`cd` means "change directory" - it moves your current directory to the one you name. If you're not
sure of the exact path, most terminals let you type `cd ` (with a trailing space) and then drag the
actual folder from your file browser into the terminal window - it'll fill in the path for you.

Check it worked:

```
ls
```

(On Windows PowerShell, `ls` also works and does the same thing.) This lists everything in your
current directory. You should see a file called `START-HERE.md`, a folder called `fixtures`, a
folder called `checks`, and a folder called `my-pack`. If you see those, you're in the right place.

## Part 3: install Claude Code

**Windows only, do this first:** this workshop's checklist script (used below, and in every later
module) needs a program called `bash` to run, which Windows doesn't include by default. Install
[Git for Windows](https://git-scm.com/downloads/win): download it, run the installer, and click
Next on every screen to accept the defaults - none of the options need to change. This also gives
Claude Code itself a better experience on Windows, so it's worth doing either way, not just for the
checklist. macOS and most common Linux distributions already have everything they need; skip this
step there.

**Alpine Linux only:** Alpine doesn't include `bash` or `curl` by default either, both needed
below. Install them first with `apk add bash curl` before continuing.

Copy the line for your system below, paste it into your terminal, and press Enter.

**macOS, Linux:**

```
curl -fsSL https://claude.ai/install.sh | bash
```

**Windows (PowerShell):**

```
irm https://claude.ai/install.ps1 | iex
```

You'll see text scroll by while it downloads and installs. When it's done, you'll see
`Claude Code successfully installed!`. If you see an error instead, or the word `claude` isn't
recognized afterward, the most common fix is closing this terminal window and opening a brand
new one - the install adds Claude Code to a list your terminal only reads when it starts up.

Check the install worked:

```
claude --version
```

This should print something like `2.1.211 (Claude Code)`. This check doesn't need you to be
logged in yet - it's just confirming the program itself is there.

## Part 4: log in

Type:

```
claude
```

The first time you run this, Claude Code opens your web browser and asks you to sign in. Follow
the prompts there. When it's done, your terminal shows `Login successful` and asks you to press
Enter to continue.

**A step you don't need to take now, but is worth knowing about:** if this browser step doesn't
happen automatically - for instance, the browser window never opens - your terminal will offer to
let you copy a link instead. Paste that link into any browser yourself and sign in there.

Once you see `Login successful`, press Enter. You're now inside a **session** - the name for one
continuous conversation with Claude Code, from opening it to closing it. Close this one for now by
typing `exit`, or pressing `Ctrl+D` twice (verified against Claude Code's own current
documentation, 2026-09-14). You'll open a new session for real in the next module.

**One thing worth knowing before you move on:** Claude Code remembers this login afterward, so you
normally won't see this step again. But if Module 02 asks you to log in a second time, that's
completely normal - it just means your login needs refreshing. Follow the same browser step again
and carry on.

## Part 5: your first few commands

A handful of commands will come up constantly. Try each one now, inside your workshop folder:

- `pwd` - prints your current directory, in full. Useful any time you're not sure where you are.
- `mkdir -p 01-terminal/my-notes` - creates a new folder. `mkdir` means "make directory"; the `-p`
  means "and create any parent folders along the way too if they don't exist yet" - without it,
  this exact command would fail, since there's no `01-terminal` folder here yet for `my-notes` to
  go inside. This creates the exact folder this module's gate checks for.
- `cp fixtures/welcome-note.txt 01-terminal/my-notes/welcome-note.txt` - copies a file from one
  place to another. `cp` means "copy." This is the actual required step below, not just practice -
  run it for real.

If a command ever seems to hang - no prompt comes back, nothing happens - press `Ctrl+C`. That
interrupts whatever's running and gives you back your prompt. It's the terminal's equivalent of a
cancel button, and it's always safe to try.

## Required to advance

Two things, both checked from your own terminal - nobody else needs to see them.

**A checklist you run yourself.** From inside your workshop folder, run:

```
bash checks/check.sh 01
```

*(Windows: if typing this directly gives an error about `bash` not being recognized, open **Git
Bash** from your Start menu instead - it installed alongside Git for Windows in Part 3 - and run
the same command there.)*

This checks, for real: your workshop folder is really unpacked (`START-HERE.md` is there); you
created a real `01-terminal/my-notes/` folder (not a shortcut standing in for one); you copied
`welcome-note.txt` into it for real, exactly, byte for byte (not a shortcut, and not some other
trick that avoids actually running `cp`); the `claude` command is genuinely installed and working;
you're genuinely logged in (checked directly, the same way Claude Code itself checks); and you've
filled in a short answers file, in your own words, not copied from this page (below). It prints
`RESULT: PASS (6/6)` when everything's there - if it prints anything else, it tells you exactly
what's still missing.

**A short answers file.** Create `01-terminal/answers.txt` - a plain text file, made with any text
editor your computer already has (Notepad on Windows, TextEdit on macOS, or your file browser's
"new text file" option) - containing four lines, each starting with the label shown:

```
PROMPT: <in your own words, what is the prompt?>
CURRENT_DIRECTORY: <in your own words, what is a current directory?>
STUCK_TERMINAL: <what would you do if the terminal looked stuck?>
LOGIN_CONFIRMED: <what happened when you logged in - anything odd, or did it just work?>
```

The first three are checked for real content, not just presence - copying the bracketed prompts
above word for word won't pass, on purpose. Nobody's grading whether they're "correct," only
whether you actually wrote your own answer. `LOGIN_CONFIRMED` is pure reflection, not part of the
gate at all - whether you're actually logged in is checked directly, above, not by what you write
here. If you can't explain one of the first three yet, that's worth noticing before moving on, not
something to paper over with a guess.

## Takeaway

Start `my-pack/cheatsheet.md` - the first page of a personal terminal survival card you'll keep
adding to. Same as `answers.txt` above: any text editor your computer already has works fine for
creating it. Write down, in your own words, however you'd want to explain it to yourself next week:

- How to open a terminal.
- How to check what folder you're in, and how to move to a different one.
- How to create a folder and copy a file into it.
- What to do if it looks stuck.

This file is yours. Nothing checks its exact wording - it only matters that it's actually useful to
you later.
