#!/usr/bin/env bash
# check.sh: Wade In's required-checklist runner. One script, one module number
# per invocation: `./check.sh 01`, `./check.sh 02`, etc.
#
# Hardened per this workshop's own docs/workshop-design.md §8 and this
# factory's own closed-book checker-hardening lessons -- and per real,
# demonstrated findings from two rounds of adversarial review (a same-model
# doubt-driven-development pass, then a cross-model Codex pass) against this
# exact script. Each fix below names the specific bypass that was actually
# reproduced, not a hypothetical one:
#   - Resolves its own root from the SCRIPT's path, never from `pwd`. A
#     learner's agent could `cd` somewhere unexpected, deliberately or by
#     accident, and a checker that trusts the working directory can be
#     fooled into checking the wrong files or none at all.
#   - Verifies fixture integrity against an embedded checksum (see
#     EXPECTED_WELCOME_NOTE_SHA256 below), not by re-reading the live
#     fixtures/ file and trusting it. An earlier version computed its
#     "pristine" reference from fixtures/ at run time; a tampered fixture
#     silently became the new "pristine" copy and the check still passed.
#     (Correction: the header comment in an earlier version of this script,
#     and docs/workshop-design.md §8's own account of it, both claimed
#     fixtures were copied into a neutral scratch directory before
#     comparison -- they weren't, by the time the embedded-checksum fix
#     landed. That stale claim is fixed here and in workshop-design.md, not
#     just the behavior.)
#   - Rejects a symlink OR a hard link standing in for a real copy, at every
#     level: the leaf file, AND the parent directory (a symlinked
#     `01-terminal/my-notes -> ../fixtures` was demonstrated to pass the
#     original leaf-only check). A hard link shares the fixture's own inode
#     -- same bytes, but never touched `cp` -- and was also demonstrated to
#     pass a naive `-f`-plus-checksum check.
#   - Requires the login check to be a REAL mechanical check
#     (`claude auth status`), not a self-attested answer-file field. An
#     earlier version accepted `LOGIN_CONFIRMED: no` as a pass, because the
#     field was only checked for non-emptiness, not content.
#   - Requires answers to be genuinely written, not the literal placeholder
#     text copied verbatim from the module page (also demonstrated to pass
#     a naive non-empty-after-label check).
#   - Distinguishes "the checker's own tooling is missing" from "your
#     submission is wrong" in its output, rather than collapsing both into
#     the same failure message.
#   - Never prints a passing result unless every check in the requested
#     module's group actually ran and passed. A truncated, errored, or
#     partially-run check exits nonzero and never prints RESULT: PASS.
#
# Named limit, stated honestly rather than implied solved: this script ships
# inside the workshop folder, readable and editable by the learner's own
# Claude Code session. Nothing here can stop a determined self-cheater who
# edits this file directly (verified: changing the embedded checksum to
# match a fake submission does pass). The checks above close the bypasses a
# genuinely honest attempt, or an errant session, could stumble into by
# accident -- not every bypass a deliberately dishonest one could construct.
#
# Usage:
#   ./checks/check.sh 01
#
# Network: none, except the `claude auth status` call, which is a local
# CLI command reporting locally-cached login state -- not a check.sh network
# call of its own.
set -uo pipefail

MODULE="${1:-}"
if [[ -z "$MODULE" ]]; then
  echo "Usage: check.sh <module-number>  (e.g. check.sh 01)" >&2
  exit 2
fi

# Resolve the workshop root from THIS SCRIPT's own real path, not from
# wherever it happens to be invoked from. `pwd -P` (physical, symlinks
# resolved) throughout -- not just `pwd` -- because the symlink-detection
# check below compares resolved paths against ROOT-derived ones, and on
# macOS /tmp itself is a symlink to /private/tmp. Using plain `pwd` for ROOT
# but `pwd -P` for the symlink check compared paths in two different forms
# and produced a false FAIL on a perfectly legitimate real directory,
# caught by testing this fix against a real diligent attempt, not just
# reading the code.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

TOTAL=0
PASSED=0
FAILED_ITEMS=()

check() {
  local description="$1"
  local result="$2"  # "pass" or "fail"
  TOTAL=$((TOTAL + 1))
  if [[ "$result" == "pass" ]]; then
    PASSED=$((PASSED + 1))
    printf '  PASS: %s\n' "$description"
  else
    FAILED_ITEMS+=("$description")
    printf '  FAIL: %s\n' "$description"
  fi
}

CHECKSUM_TOOL_AVAILABLE=true
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  CHECKSUM_TOOL_AVAILABLE=false
fi

file_checksum() {
  # macOS ships shasum, not sha256sum; Linux is the reverse. Try both.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "NO_CHECKSUM_TOOL"
  fi
}

file_inode() {
  # macOS/BSD stat and GNU stat take different flags for "just the inode
  # number." Try both; used to detect a hard link (same inode as the
  # fixture, meaning `cp` was never actually run).
  stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1" 2>/dev/null || echo "NO_STAT_TOOL"
}

# Embedded checksums: the real, known-good sha256 of each fixture as
# authored, computed once and pinned here. Update this value deliberately
# (and note why, in a commit message) any time a fixture's real content
# changes -- never let it silently drift from what's actually on disk.
EXPECTED_WELCOME_NOTE_SHA256="f9f6b278a9732f0dbcc0969414f34d7365942ce8e8aea705775a5e933b8e7475"
EXPECTED_VENUE_HISTORY_SHA256="3afe8aea8f84e6fff4da67c0f48d14b7956c6630ff06756c2ea2bb6180eec7a5"
EXPECTED_MONTHLY_RAW_NUMBERS_SHA256="9268dbb4a3b65e437b159a082ee51eeb7d70bd24365bdbca6004a24206aea255"

echo "-- Wade In required checklist: Module $MODULE ------------------------"
echo ""

case "$MODULE" in
  01)
    # 1. The marker file exists and is non-empty -- proof the folder actually unpacked.
    if [[ -s "$ROOT/START-HERE.md" ]]; then
      check "START-HERE.md exists and is non-empty" pass
    else
      check "START-HERE.md exists and is non-empty" fail
    fi

    # 2. The learner created 01-terminal/my-notes/ as a REAL directory, not
    #    a symlink standing in for one. `cd -P` resolves symlinks physically;
    #    comparing the resolved path against the expected literal path
    #    catches a symlinked parent redirecting into somewhere else entirely
    #    (demonstrated: `01-terminal/my-notes -> ../fixtures` passed a naive
    #    existence check and made every file inside it "match" for free).
    EXPECTED_MY_NOTES="$ROOT/01-terminal/my-notes"
    if [[ -d "$EXPECTED_MY_NOTES" ]]; then
      REAL_MY_NOTES="$(cd "$EXPECTED_MY_NOTES" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_MY_NOTES" == "$EXPECTED_MY_NOTES" ]]; then
        check "01-terminal/my-notes/ directory exists (not a symlink)" pass
      else
        check "01-terminal/my-notes/ directory exists (not a symlink)" fail
      fi
    else
      check "01-terminal/my-notes/ directory exists (not a symlink)" fail
    fi

    # 3. fixtures/welcome-note.txt was copied into it for real: byte-
    #    identical (checked against the embedded checksum, not a live copy
    #    of the fixture -- see header), not a symlink, and not a hard link
    #    either (same content, same inode as the fixture, but `cp` was never
    #    actually run -- demonstrated to pass a checksum-only check).
    FIXTURE_PATH="$ROOT/fixtures/welcome-note.txt"
    LEARNER_FILE="$ROOT/01-terminal/my-notes/welcome-note.txt"
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      # Neither sha256sum nor shasum is on PATH -- this system can't run the
      # check at all. Say that plainly, distinct from "fixture is wrong" or
      # "your copy is wrong": neither of those is what actually happened.
      # (Confirmed as a real, distinct failure mode: an earlier version of
      # this script collapsed a missing-tool system into the same "contact
      # the workshop, fixture is corrupt" message a genuinely tampered
      # fixture produces -- reproduced directly by stripping both tools from
      # PATH, not just reasoned about.)
      check "welcome-note.txt copied into my-notes/, byte-identical to the original (couldn't verify: no checksum tool found on this system - contact the workshop)" fail
    else
      FIXTURE_SUM="$(file_checksum "$FIXTURE_PATH" 2>/dev/null || echo "MISSING_FIXTURE")"
      if [[ "$FIXTURE_SUM" != "$EXPECTED_WELCOME_NOTE_SHA256" ]]; then
        # The shipped fixture itself doesn't match its own pinned checksum --
        # a workshop-folder integrity problem, not something the learner did.
        check "workshop fixture welcome-note.txt matches its expected content (contact the workshop, not your own mistake)" fail
      elif [[ -L "$LEARNER_FILE" ]]; then
        check "welcome-note.txt copied into my-notes/ (found a symlink, not an actual copy - use cp, not ln -s)" fail
      elif [[ -f "$LEARNER_FILE" ]]; then
        LEARNER_INODE="$(file_inode "$LEARNER_FILE")"
        FIXTURE_INODE="$(file_inode "$FIXTURE_PATH")"
        if [[ "$LEARNER_INODE" != "NO_STAT_TOOL" && "$LEARNER_INODE" == "$FIXTURE_INODE" ]]; then
          check "welcome-note.txt copied into my-notes/ (found a hard link, not an actual copy - use cp, not ln)" fail
        else
          LEARNER_SUM="$(file_checksum "$LEARNER_FILE")"
          if [[ "$LEARNER_SUM" == "$EXPECTED_WELCOME_NOTE_SHA256" ]]; then
            check "welcome-note.txt copied into my-notes/, byte-identical to the original" pass
          else
            check "welcome-note.txt copied into my-notes/, byte-identical to the original" fail
          fi
        fi
      else
        check "welcome-note.txt copied into my-notes/, byte-identical to the original" fail
      fi
    fi

    # 4. The claude command actually runs and reports a real version string,
    #    not just something named "claude" sitting on PATH (`command -v`
    #    alone was demonstrated to pass a fake no-op executable). Not a
    #    proof against a determined fake claiming a version-shaped string --
    #    named limit, not a security boundary.
    CLAUDE_VERSION_OUTPUT="$(claude --version 2>/dev/null || echo "")"
    if [[ "$CLAUDE_VERSION_OUTPUT" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
      check "the claude command is available and reports a real version (install worked)" pass
    else
      check "the claude command is available and reports a real version (install worked)" fail
    fi

    # 5. The learner is actually logged in - a REAL mechanical check via
    #    `claude auth status`, not a self-attested answer-file field. An
    #    earlier version of this checklist only confirmed the learner wrote
    #    *something* in a LOGIN_CONFIRMED field, including "no" - demonstrated
    #    to pass. `claude auth status` reports real, current login state as
    #    JSON; checked here for `"loggedIn": true` without parsing or
    #    printing the rest of that output (which can include an email
    #    address - not this checker's business to display).
    AUTH_STATUS_OUTPUT="$(claude auth status 2>/dev/null || echo "")"
    if echo "$AUTH_STATUS_OUTPUT" | grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true'; then
      check "logged in to Claude Code (verified via claude auth status)" pass
    else
      check "logged in to Claude Code (verified via claude auth status)" fail
    fi

    # 6. Own-words answers file: presence-checked for real content, not
    #    graded for correctness (there isn't a "correct" answer to these
    #    three reflection questions). Requires three non-empty labeled
    #    lines, AND rejects the literal placeholder text from the module
    #    page itself - demonstrated to pass a naive non-empty check
    #    (copying "<in your own words, what is the prompt?>" verbatim is not
    #    an answer). LOGIN_CONFIRMED is a reflection field now, not a gate -
    #    the real login gate is item 5, above.
    ANSWERS="$ROOT/01-terminal/answers.txt"
    PLACEHOLDER_PROMPT="<in your own words, what is the prompt?>"
    PLACEHOLDER_DIR="<in your own words, what is a current directory?>"
    PLACEHOLDER_STUCK="<what would you do if the terminal looked stuck?>"
    if [[ -f "$ANSWERS" ]]; then
      MISSING_LABELS=()
      # A case statement, not an associative array (`declare -A`) -- stock
      # macOS ships bash 3.2 (Apple stopped shipping newer bash over its
      # GPLv3 license), which has no associative arrays at all. `declare -A`
      # silently misbehaves there rather than erroring cleanly, and every
      # downstream reference to the array crashes the whole script with
      # "unbound variable" mid-run, printing no RESULT line at all. This was
      # missed by every round of testing on this machine, since this
      # machine's own PATH resolves `bash` to a Homebrew-installed 5.x, not
      # the stock 3.2 a real first-time learner on a fresh Mac would have --
      # confirmed by directly reproducing the crash with `/bin/bash`
      # specifically, not the `bash` this session had been testing with.
      for label in "PROMPT:" "CURRENT_DIRECTORY:" "STUCK_TERMINAL:"; do
        case "$label" in
          "PROMPT:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_PROMPT" ;;
          "CURRENT_DIRECTORY:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_DIR" ;;
          "STUCK_TERMINAL:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_STUCK" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "01-terminal/answers.txt has all three reflection answers, in your own words" pass
      else
        check "01-terminal/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "01-terminal/answers.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  02)
    # 1. 02-meet/ itself is a real directory, not a symlink standing in for
    #    one -- mirrors Module 01's `01-terminal/my-notes/` check. Reproduced
    #    by a cross-model review: a symlinked `02-meet -> /some/outside/dir`
    #    passed every downstream check, meaning the apparent workshop output
    #    could actually live outside the sandbox entirely.
    EXPECTED_02_MEET="$ROOT/02-meet"
    MEET_DIR_OK=true
    if [[ -e "$EXPECTED_02_MEET" ]]; then
      REAL_02_MEET="$(cd "$EXPECTED_02_MEET" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_02_MEET" != "$EXPECTED_02_MEET" ]]; then
        MEET_DIR_OK=false
      fi
    fi

    # 2. 02-meet/summary.txt exists for real -- not a symlink, and not a hard
    #    link either (checked via link count, not by comparing against one
    #    specific reference file the way Module 01 does for its fixture copy
    #    -- this file is learner/Claude-Code-authored, not copied from
    #    anywhere, so there's no single fixture inode to compare against;
    #    any link count above 1 means some other path shares these exact
    #    bytes, which a freshly-written file never does). Reproduced: hard-
    #    linking summary.txt and answers.txt to the same outside file, both
    #    passed identically to two real, independently-written files.
    SUMMARY="$ROOT/02-meet/summary.txt"
    SUMMARY_LINK_COUNT="$(stat -f '%l' "$SUMMARY" 2>/dev/null || stat -c '%h' "$SUMMARY" 2>/dev/null || echo "1")"
    if [[ "$MEET_DIR_OK" == false ]]; then
      check "02-meet/summary.txt exists and is non-empty (02-meet/ is a symlink, not a real directory)" fail
    elif [[ -L "$SUMMARY" ]]; then
      check "02-meet/summary.txt exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$SUMMARY" && "$SUMMARY_LINK_COUNT" != "1" ]]; then
      check "02-meet/summary.txt exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$SUMMARY" ]]; then
      check "02-meet/summary.txt exists and is non-empty" pass
    else
      check "02-meet/summary.txt exists and is non-empty" fail
    fi
    SUMMARY_REAL_FILE=false
    [[ "$MEET_DIR_OK" == true && -f "$SUMMARY" && ! -L "$SUMMARY" && "$SUMMARY_LINK_COUNT" == "1" ]] && SUMMARY_REAL_FILE=true

    # 3. It's 3-5 lines -- counting real content lines, not blank ones, so a
    #    trailing blank line from an editor doesn't wrongly fail a genuine
    #    3-5-line summary. "Line" means an actual line break, which is why
    #    the module's own suggested prompt explicitly asks for separate
    #    lines rather than a paragraph -- confirmed live against the real
    #    `claude` CLI that a vaguer prompt reliably produces flowing prose
    #    that fails this check on a perfectly correct, honest summary.
    if [[ "$SUMMARY_REAL_FILE" == true ]]; then
      NONBLANK_LINES="$(grep -cv '^[[:space:]]*$' "$SUMMARY" 2>/dev/null || echo 0)"
      if [[ "$NONBLANK_LINES" -ge 3 && "$NONBLANK_LINES" -le 5 ]]; then
        check "summary.txt is 3-5 lines long (found $NONBLANK_LINES)" pass
      else
        check "summary.txt is 3-5 lines long (found $NONBLANK_LINES)" fail
      fi
    else
      check "summary.txt is 3-5 lines long" fail
    fi

    # 4 & 5. The summary contains the venue's founding year and current
    #    capacity -- both re-derived from the fixture itself at check time
    #    (never an embedded key), so the check stays correct if the fixture's
    #    *values* ever change, and so it's actually testing whether the
    #    summary reflects the real source, not whether the learner guessed a
    #    number this script happens to have memorized. The fixture itself is
    #    checksum-verified first (see EXPECTED_VENUE_HISTORY_SHA256) -- a
    #    tampered fixture (e.g. edited to claim a founding year of 9999) was
    #    demonstrated to make the checker faithfully "verify" a summary
    #    against the tampered value instead of the real one, the same class
    #    of bypass Module 01's embedded checksum already guards against for
    #    its own fixture.
    #    Matching extracts every numeric token in the summary (an optional
    #    leading `-`, digits, an optional `.digits` extension) and requires
    #    an EXACT match against one of those tokens -- not a word-boundary
    #    substring match (`\b`), which still treats a hyphen or decimal
    #    point as a boundary and was demonstrated to accept "founded in
    #    -1962" or "capacity is 295.9" as containing the real values. Token
    #    extraction correctly tells a genuine sentence-ending period (the
    #    token "295" from "...is 295.") apart from a real decimal extension
    #    (the token "295.9" from "...is 295.9") -- confirmed directly after
    #    an earlier boundary-character version of this fix wrongly rejected
    #    the first, ordinary case.
    HISTORY_FIXTURE="$ROOT/fixtures/venue-history.txt"
    HISTORY_SUM="$(file_checksum "$HISTORY_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$HISTORY_SUM" != "$EXPECTED_VENUE_HISTORY_SHA256" ]]; then
      check "summary.txt includes the founding year (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "summary.txt includes the current capacity (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
    else
      FOUNDING_YEAR="$(grep -oE 'Double Deuce in [0-9]{4}' "$HISTORY_FIXTURE" 2>/dev/null | grep -oE '[0-9]{4}')"
      CAPACITY="$(grep -oE 'fire marshal inspection, is [0-9]+' "$HISTORY_FIXTURE" 2>/dev/null | grep -oE '[0-9]+$')"
      if [[ -z "$FOUNDING_YEAR" || -z "$CAPACITY" ]]; then
        check "summary.txt includes the founding year (couldn't read it from the workshop fixture - contact the workshop)" fail
        check "summary.txt includes the current capacity (couldn't read it from the workshop fixture - contact the workshop)" fail
      else
        if [[ "$SUMMARY_REAL_FILE" == true ]] && grep -oE -- '-?[0-9]+(\.[0-9]+)?' "$SUMMARY" 2>/dev/null | grep -qxF "$FOUNDING_YEAR"; then
          check "summary.txt includes the founding year ($FOUNDING_YEAR)" pass
        else
          check "summary.txt includes the founding year ($FOUNDING_YEAR)" fail
        fi
        if [[ "$SUMMARY_REAL_FILE" == true ]] && grep -oE -- '-?[0-9]+(\.[0-9]+)?' "$SUMMARY" 2>/dev/null | grep -qxF "$CAPACITY"; then
          check "summary.txt includes the current capacity ($CAPACITY)" pass
        else
          check "summary.txt includes the current capacity ($CAPACITY)" fail
        fi
      fi
    fi

    # 6. Own-words answers file: same discipline as Module 01 -- presence-
    #    checked for genuine content, rejecting the literal placeholder text
    #    from the module page itself, and rejecting a symlink or hard link
    #    standing in for a real file (same convention as checks 1-2, above).
    ANSWERS02="$ROOT/02-meet/answers.txt"
    ANSWERS02_LINK_COUNT="$(stat -f '%l' "$ANSWERS02" 2>/dev/null || stat -c '%h' "$ANSWERS02" 2>/dev/null || echo "1")"
    PLACEHOLDER_PROMPT02="<what happened when Claude Code asked to create or write the file - what did you see, what did you choose?>"
    PLACEHOLDER_WHY02="<in your own words, why does Claude Code ask before acting?>"
    PLACEHOLDER_CHECKED02="<one specific thing you checked yourself before trusting the summary>"
    if [[ "$MEET_DIR_OK" == false ]]; then
      check "02-meet/answers.txt has all three reflection answers, in your own words (02-meet/ is a symlink, not a real directory)" fail
    elif [[ -L "$ANSWERS02" ]]; then
      check "02-meet/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS02" && "$ANSWERS02_LINK_COUNT" != "1" ]]; then
      check "02-meet/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS02" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01's identical pattern, above, for why.
      for label in "PERMISSION_PROMPT:" "WHY_ASKS:" "WHAT_I_CHECKED:"; do
        case "$label" in
          "PERMISSION_PROMPT:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_PROMPT02" ;;
          "WHY_ASKS:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_WHY02" ;;
          "WHAT_I_CHECKED:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_CHECKED02" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS02" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "02-meet/answers.txt has all three reflection answers, in your own words" pass
      else
        check "02-meet/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "02-meet/answers.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  06)
    # 1. 06-docs/ itself is a real directory, not a symlink standing in for
    #    one -- same convention as Module 02's 02-meet/ check.
    EXPECTED_06_DOCS="$ROOT/06-docs"
    DOCS_DIR_OK=true
    if [[ -e "$EXPECTED_06_DOCS" ]]; then
      REAL_06_DOCS="$(cd "$EXPECTED_06_DOCS" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_06_DOCS" != "$EXPECTED_06_DOCS" ]]; then
        DOCS_DIR_OK=false
      fi
    fi

    # 2. 06-docs/monthly-summary.md exists for real -- not a symlink, and not
    #    a hard link either (checked via link count, same reasoning as
    #    Module 02's summary.txt check: this file is learner/Claude-Code-
    #    authored, not copied from a fixture, so a freshly written file never
    #    shares an inode with anything else).
    DOC="$ROOT/06-docs/monthly-summary.md"
    DOC_LINK_COUNT="$(stat -f '%l' "$DOC" 2>/dev/null || stat -c '%h' "$DOC" 2>/dev/null || echo "1")"
    if [[ "$DOCS_DIR_OK" == false ]]; then
      check "06-docs/monthly-summary.md exists and is non-empty (06-docs/ is a symlink, not a real directory)" fail
    elif [[ -L "$DOC" ]]; then
      check "06-docs/monthly-summary.md exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$DOC" && "$DOC_LINK_COUNT" != "1" ]]; then
      check "06-docs/monthly-summary.md exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$DOC" ]]; then
      check "06-docs/monthly-summary.md exists and is non-empty" pass
    else
      check "06-docs/monthly-summary.md exists and is non-empty" fail
    fi
    DOC_REAL_FILE=false
    [[ "$DOCS_DIR_OK" == true && -f "$DOC" && ! -L "$DOC" && "$DOC_LINK_COUNT" == "1" && -s "$DOC" ]] && DOC_REAL_FILE=true

    # 3. Word count within the stated bounds (150-400 words), counted the
    #    same plain way `wc -w` counts -- whitespace-separated tokens across
    #    the whole file, headers included, matching what the module page
    #    tells the learner to aim for.
    if [[ "$DOC_REAL_FILE" == true ]]; then
      WORD_COUNT="$(wc -w < "$DOC" 2>/dev/null | tr -d '[:space:]')"
      if [[ "$WORD_COUNT" =~ ^[0-9]+$ ]] && [[ "$WORD_COUNT" -ge 150 && "$WORD_COUNT" -le 400 ]]; then
        check "monthly-summary.md is 150-400 words long (found $WORD_COUNT)" pass
      else
        check "monthly-summary.md is 150-400 words long (found ${WORD_COUNT:-0})" fail
      fi
    else
      check "monthly-summary.md is 150-400 words long" fail
    fi

    # 4-7. The monthly total (recomputed by THIS SCRIPT as the sum of the
    #    fixture's four weekly figures -- never an embedded key, so the
    #    check stays correct if the fixture's own figures ever change) and
    #    three further figures (bar tab total, door revenue total, events
    #    held), all read directly from the fixture. The fixture is checksum-
    #    verified first -- same defense as Modules 01 and 02's own fixtures:
    #    a tampered fixture (e.g. edited to inflate a weekly figure) must not
    #    let the checker faithfully "verify" a summary against the tampered
    #    value instead of the real one.
    #    Figure matching extracts every run of digits (with an optional
    #    leading `$` and optional interior commas, both stripped before
    #    comparing) from the document and requires an EXACT match against
    #    the canonical digit string -- not a substring match, which (per
    #    Module 02's own documented bug) would let a longer nearby figure
    #    like "$127,845" wrongly appear to contain "$27,845".
    RAW_NUMBERS_FIXTURE="$ROOT/fixtures/monthly-raw-numbers.txt"
    RAW_NUMBERS_SUM="$(file_checksum "$RAW_NUMBERS_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$RAW_NUMBERS_SUM" != "$EXPECTED_MONTHLY_RAW_NUMBERS_SHA256" ]]; then
      check "monthly-summary.md includes the exact monthly total (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "monthly-summary.md includes the bar tab total (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "monthly-summary.md includes the door revenue total (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "monthly-summary.md includes the number of events held (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
    else
      WEEK_1="$(grep -oE 'Week 1 revenue: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      WEEK_2="$(grep -oE 'Week 2 revenue: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      WEEK_3="$(grep -oE 'Week 3 revenue: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      WEEK_4="$(grep -oE 'Week 4 revenue: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      BAR_TOTAL="$(grep -oE 'Bar tab total for the month: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      DOOR_TOTAL="$(grep -oE 'Door revenue total for the month: \$[0-9,]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9,]+$' | tr -d ',')"
      EVENTS_HELD="$(grep -oE 'Events held this month: [0-9]+' "$RAW_NUMBERS_FIXTURE" 2>/dev/null | grep -oE '[0-9]+$')"
      if [[ -z "$WEEK_1" || -z "$WEEK_2" || -z "$WEEK_3" || -z "$WEEK_4" || -z "$BAR_TOTAL" || -z "$DOOR_TOTAL" || -z "$EVENTS_HELD" ]]; then
        check "monthly-summary.md includes the exact monthly total (couldn't read the raw figures from the workshop fixture - contact the workshop)" fail
        check "monthly-summary.md includes the bar tab total (couldn't read it from the workshop fixture - contact the workshop)" fail
        check "monthly-summary.md includes the door revenue total (couldn't read it from the workshop fixture - contact the workshop)" fail
        check "monthly-summary.md includes the number of events held (couldn't read it from the workshop fixture - contact the workshop)" fail
      else
        MONTHLY_TOTAL=$((WEEK_1 + WEEK_2 + WEEK_3 + WEEK_4))
        if [[ "$DOC_REAL_FILE" == true ]]; then
          DOC_NUMBER_TOKENS="$(grep -oE '\$?[0-9][0-9,]*' "$DOC" 2>/dev/null | tr -d '$,')"
        else
          DOC_NUMBER_TOKENS=""
        fi
        if [[ "$DOC_REAL_FILE" == true ]] && echo "$DOC_NUMBER_TOKENS" | grep -qxF "$MONTHLY_TOTAL"; then
          check "monthly-summary.md includes the exact monthly total (\$$MONTHLY_TOTAL)" pass
        else
          check "monthly-summary.md includes the exact monthly total (\$$MONTHLY_TOTAL)" fail
        fi
        if [[ "$DOC_REAL_FILE" == true ]] && echo "$DOC_NUMBER_TOKENS" | grep -qxF "$BAR_TOTAL"; then
          check "monthly-summary.md includes the bar tab total (\$$BAR_TOTAL)" pass
        else
          check "monthly-summary.md includes the bar tab total (\$$BAR_TOTAL)" fail
        fi
        if [[ "$DOC_REAL_FILE" == true ]] && echo "$DOC_NUMBER_TOKENS" | grep -qxF "$DOOR_TOTAL"; then
          check "monthly-summary.md includes the door revenue total (\$$DOOR_TOTAL)" pass
        else
          check "monthly-summary.md includes the door revenue total (\$$DOOR_TOTAL)" fail
        fi
        # Events-held gets a stricter check than the three dollar totals: a
        # small, common integer like this one collides constantly with
        # unrelated numbers in ordinary prose (a date, "the 19th," a list
        # count) -- found by a fresh-context adversarial pass, which built
        # a real document that never states the events-held figure at all
        # but happened to mention "the 19th" elsewhere, and passed anyway.
        # Requiring the number to appear on the same LINE as the word
        # "event" (case-insensitive) is a real, meaningful tightening, not
        # a complete fix -- a line that mentions "event" AND some other
        # unrelated number would still false-accept -- but it closes the
        # specific, demonstrated false pass and is a named, accepted limit
        # rather than a claim of full semantic verification.
        if [[ "$DOC_REAL_FILE" == true ]]; then
          EVENT_LINE_TOKENS="$(grep -iE 'event' "$DOC" 2>/dev/null | grep -oE '\$?[0-9][0-9,]*' | tr -d '$,')"
        else
          EVENT_LINE_TOKENS=""
        fi
        if [[ "$DOC_REAL_FILE" == true ]] && echo "$EVENT_LINE_TOKENS" | grep -qxF "$EVENTS_HELD"; then
          check "monthly-summary.md includes the number of events held ($EVENTS_HELD)" pass
        else
          check "monthly-summary.md includes the number of events held ($EVENTS_HELD)" fail
        fi
      fi
    fi

    # 8. All 5 required section headers present verbatim -- a closed set,
    #    each checked as an exact whole-line match (not a substring, so a
    #    header buried mid-sentence or missing its own line doesn't count).
    #    A plain indexed array, not `declare -A` -- see the standing note on
    #    Modules 01/02's identical discipline, above: stock macOS bash 3.2
    #    has no associative arrays, but ordinary indexed arrays work fine.
    REQUIRED_HEADERS=("## Summary" "## Revenue Breakdown" "## Notable Items" "## Comparison to Prior Month" "## Prepared By")
    MISSING_HEADERS=()
    if [[ "$DOC_REAL_FILE" == true ]]; then
      for header in "${REQUIRED_HEADERS[@]}"; do
        if ! grep -qxF "$header" "$DOC" 2>/dev/null; then
          MISSING_HEADERS+=("$header")
        fi
      done
    else
      MISSING_HEADERS=("${REQUIRED_HEADERS[@]}")
    fi
    if [[ "${#MISSING_HEADERS[@]}" -eq 0 ]]; then
      check "monthly-summary.md has all 5 required section headers, written exactly as specified" pass
    else
      check "monthly-summary.md has all 5 required section headers, written exactly as specified (still missing: ${MISSING_HEADERS[*]})" fail
    fi

    # 9. Own-words answers file: same discipline as every module before this
    #    one -- presence-checked for genuine content, rejecting the literal
    #    placeholder text from the module page itself, and rejecting a
    #    symlink or hard link standing in for a real file.
    ANSWERS06="$ROOT/06-docs/answers.txt"
    ANSWERS06_LINK_COUNT="$(stat -f '%l' "$ANSWERS06" 2>/dev/null || stat -c '%h' "$ANSWERS06" 2>/dev/null || echo "1")"
    PLACEHOLDER_READS06="<does the document read like something you'd hand an accountant, or like your own working notes with headers added - and what would you change?>"
    PLACEHOLDER_VERIFIED06="<specifically, how did you check the figures yourself before trusting the draft?>"
    PLACEHOLDER_NOTICES06="<in your own words, what's the actual risk if one figure in a document like this is wrong?>"
    if [[ "$DOCS_DIR_OK" == false ]]; then
      check "06-docs/answers.txt has all three reflection answers, in your own words (06-docs/ is a symlink, not a real directory)" fail
    elif [[ -L "$ANSWERS06" ]]; then
      check "06-docs/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS06" && "$ANSWERS06_LINK_COUNT" != "1" ]]; then
      check "06-docs/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS06" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Modules 01/02's identical pattern, above.
      for label in "READS_LIKE_A_SUMMARY:" "VERIFIED_HOW:" "WHAT_CARL_NOTICES:"; do
        case "$label" in
          "READS_LIKE_A_SUMMARY:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_READS06" ;;
          "VERIFIED_HOW:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_VERIFIED06" ;;
          "WHAT_CARL_NOTICES:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_NOTICES06" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS06" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "06-docs/answers.txt has all three reflection answers, in your own words" pass
      else
        check "06-docs/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "06-docs/answers.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  *)
    echo "No checks defined yet for module '$MODULE'." >&2
    exit 2
    ;;
esac

echo ""
if [[ "$PASSED" -eq "$TOTAL" ]]; then
  echo "RESULT: PASS ($PASSED/$TOTAL)"
  exit 0
else
  echo "RESULT: FAIL ($PASSED/$TOTAL)"
  echo "Not yet passing: ${FAILED_ITEMS[*]}"
  exit 1
fi
