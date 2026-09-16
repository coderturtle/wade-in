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
EXPECTED_STAFF_LIST_SHA256="f7e6af0c87228e99d6d880b0b4b10bc1cda45e708f03235eaa2fcd973be9243f"
EXPECTED_EMMETT_MEMO_SHA256="7abfa8b6da208141a046ac44fc903e56d4692cd4d190b9660ed3d2526a9fb5d3"
EXPECTED_MONTHLY_RAW_NUMBERS_SHA256="9268dbb4a3b65e437b159a082ee51eeb7d70bd24365bdbca6004a24206aea255"

# Module 04's 12 door-count fixtures, one embedded sha256 per date. A `case`
# statement, not `declare -A` -- see the Module 01/02 comment below on why:
# stock macOS bash 3.2 has no associative arrays, and `declare -A` crashes
# the whole script there with no RESULT line at all.
door_count_expected_sha256() {
  case "$1" in
    2026-08-01) echo "9f3a8b0744369ca0b6f7a5769d390ac4a6b72a34ad51a3a045132b5ed8487d05" ;;
    2026-08-02) echo "a183c3cd769d0b13246e3e514b50cb109843589f2cd7941a28e25abeade1eb54" ;;
    2026-08-03) echo "9d0ca4e2d2baf943d302bcc99405155781a8693844354566f98458b1ccf6009d" ;;
    2026-08-04) echo "3e0793a8e27e75cdc0620846373717e3e0b475ef224f1a068e4bc941fa4a6382" ;;
    2026-08-05) echo "6ed3288ba4c4903931664d796e3525baf5366ec6b2c39c5dde6bdfb758ed0176" ;;
    2026-08-06) echo "fa474fc1e93a53e7c03ce55cfb4f8681f3f14f0a7aa580ab930997ff64334482" ;;
    2026-08-07) echo "4a5f01d395b6ebb6fb2913b7832a35f9c0c302cef096f2c13389e3c4e4161866" ;;
    2026-08-08) echo "1b89b5f6799ea7775b7c35cbe5a87f7e15481f33a78ebf67fd401bf257028730" ;;
    2026-08-09) echo "f8b9e67bfd801f5c1ad79191e1306704c3b9d33f77e2739aabd6ef761b0af800" ;;
    2026-08-10) echo "978a2a71906bb53d2079865e2ce3cb6bc3363245a2fbdfcf4a171c8cf410eff5" ;;
    2026-08-11) echo "6e74f02629bbd62f12222ca010716891e23bed2f9c8d921ee5cb2f88463f09f7" ;;
    2026-08-12) echo "c0f0ac145ff52a136daa425d148b70c757fd1989f976635cc07f2413f4dc100c" ;;
    *) echo "" ;;
  esac
}

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
  03)
    # 1. 03-files/ itself is a real directory, not a symlink standing in for
    #    one -- same convention as 01-terminal/my-notes/ and 02-meet/.
    EXPECTED_03_FILES="$ROOT/03-files"
    FILES_DIR_OK=true
    if [[ -e "$EXPECTED_03_FILES" ]]; then
      REAL_03_FILES="$(cd "$EXPECTED_03_FILES" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_03_FILES" != "$EXPECTED_03_FILES" ]]; then
        FILES_DIR_OK=false
      fi
    fi

    CORRECTED="$ROOT/03-files/staff-list-corrected.txt"
    STAFF_FIXTURE="$ROOT/fixtures/staff-list.txt"
    MEMO_FIXTURE="$ROOT/fixtures/emmett-memo.txt"

    # 2. staff-list-corrected.txt exists for real -- not a symlink, and not a
    #    hard link either (same discipline as 02-meet/summary.txt: a fresh
    #    link count above 1 means some other path shares these exact bytes,
    #    which a freshly-produced corrected file never does on its own).
    CORRECTED_LINK_COUNT="$(stat -f '%l' "$CORRECTED" 2>/dev/null || stat -c '%h' "$CORRECTED" 2>/dev/null || echo "1")"
    if [[ "$FILES_DIR_OK" == false ]]; then
      check "03-files/staff-list-corrected.txt exists (03-files/ is a symlink, not a real directory)" fail
    elif [[ -L "$CORRECTED" ]]; then
      check "03-files/staff-list-corrected.txt exists (found a symlink, not a real file)" fail
    elif [[ -f "$CORRECTED" && "$CORRECTED_LINK_COUNT" != "1" ]]; then
      check "03-files/staff-list-corrected.txt exists (found a hard link, not an independently-written file)" fail
    elif [[ -s "$CORRECTED" ]]; then
      check "03-files/staff-list-corrected.txt exists and is non-empty" pass
    else
      check "03-files/staff-list-corrected.txt exists and is non-empty" fail
    fi
    CORRECTED_REAL_FILE=false
    [[ "$FILES_DIR_OK" == true && -f "$CORRECTED" && ! -L "$CORRECTED" && "$CORRECTED_LINK_COUNT" == "1" ]] && CORRECTED_REAL_FILE=true

    # 3. Both fixtures match their pinned checksums -- must pass before any
    #    value recomputed from them can be trusted. Same embedded-checksum
    #    discipline as every fixture above; a tampered memo (e.g. edited to
    #    claim a different "correct" phone number) would otherwise make the
    #    check below faithfully verify against the tampered value instead of
    #    the real one.
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      check "workshop fixtures staff-list.txt and emmett-memo.txt match their expected content (couldn't verify: no checksum tool found on this system - contact the workshop)" fail
      FIXTURES_03_OK=false
    else
      STAFF_SUM="$(file_checksum "$STAFF_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
      MEMO_SUM="$(file_checksum "$MEMO_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
      if [[ "$STAFF_SUM" == "$EXPECTED_STAFF_LIST_SHA256" && "$MEMO_SUM" == "$EXPECTED_EMMETT_MEMO_SHA256" ]]; then
        check "workshop fixtures staff-list.txt and emmett-memo.txt match their expected content" pass
        FIXTURES_03_OK=true
      else
        check "workshop fixtures staff-list.txt and emmett-memo.txt match their expected content (contact the workshop, not your own mistake)" fail
        FIXTURES_03_OK=false
      fi
    fi

    # 4. Recompute the expected corrected file from the pristine fixtures,
    #    then compare the learner's submission to it byte-for-byte. This one
    #    whole-file comparison proves BOTH that all 4 corrections were
    #    actually applied AND that no other line was collaterally edited -- a
    #    wrong value, a missed correction, or a stray edit anywhere else in
    #    the file all produce a non-matching file and fail together.
    #
    #    The 4 wrong/correct value pairs are parsed from the memo's OWN text
    #    at check time, never hardcoded here -- each correction in the memo
    #    follows the fixed pattern "<subject> says <wrong>, but it should say
    #    <correct>.", and the line-selecting anchor phrases below (e.g.
    #    "Penny Johnson's line says") are fixed prose the fixture was
    #    authored with, not a hardcoded answer key. If the memo's wording is
    #    ever revised, this recomputation moves with it, same discipline as
    #    Module 02's fixture-derived facts.
    #
    #    Substitution uses perl's \Q...\E (quote-metacharacters) rather than
    #    a bash parameter-expansion substitution or a hand-escaped sed
    #    pattern: tested directly against stock macOS bash 3.2, and
    #    `${var/"$pattern"/"$replacement"}` does NOT strip the quotes there
    #    the way it does under bash 5 -- it inserts literal double-quote
    #    characters into the output. Reproduced directly, not assumed; perl
    #    (already relied on elsewhere in this repo) sidesteps both that bug
    #    and any need to hand-escape regex metacharacters in the extracted
    #    values.
    if [[ "$CORRECTED_REAL_FILE" == true && "$FIXTURES_03_OK" == true ]]; then
      LINE1="$(grep -m1 "Penny Johnson's line says" "$MEMO_FIXTURE" 2>/dev/null || true)"
      LINE2="$(grep -m1 "Carl Bruner's extension says" "$MEMO_FIXTURE" 2>/dev/null || true)"
      LINE3="$(grep -m1 "Jack Crews's job says" "$MEMO_FIXTURE" 2>/dev/null || true)"
      LINE4="$(grep -m1 "Angelo's name says" "$MEMO_FIXTURE" 2>/dev/null || true)"

      WRONG1="$(printf '%s' "$LINE1" | sed -n 's/.* says \(.*\), but it should say .*/\1/p')"
      RIGHT1="$(printf '%s' "$LINE1" | sed -n 's/.*but it should say \([^.]*\)\..*/\1/p')"
      WRONG2="$(printf '%s' "$LINE2" | sed -n 's/.* says \(.*\), but it should say .*/\1/p')"
      RIGHT2="$(printf '%s' "$LINE2" | sed -n 's/.*but it should say \([^.]*\)\..*/\1/p')"
      WRONG3="$(printf '%s' "$LINE3" | sed -n 's/.* says \(.*\), but it should say .*/\1/p')"
      RIGHT3="$(printf '%s' "$LINE3" | sed -n 's/.*but it should say \([^.]*\)\..*/\1/p')"
      WRONG4="$(printf '%s' "$LINE4" | sed -n 's/.* says \(.*\), but it should say .*/\1/p')"
      RIGHT4="$(printf '%s' "$LINE4" | sed -n 's/.*but it should say \([^.]*\)\..*/\1/p')"

      if [[ -z "$WRONG1" || -z "$RIGHT1" || -z "$WRONG2" || -z "$RIGHT2" || -z "$WRONG3" || -z "$RIGHT3" || -z "$WRONG4" || -z "$RIGHT4" ]]; then
        check "staff-list-corrected.txt has all 4 corrections applied, with no other line changed (couldn't parse the memo - contact the workshop)" fail
      else
        EXPECTED_TMP="$(mktemp "${TMPDIR:-/tmp}/wade-in-03-expected.XXXXXX" 2>/dev/null || echo "/tmp/wade-in-03-expected.$$")"
        WRONG1="$WRONG1" RIGHT1="$RIGHT1" WRONG2="$WRONG2" RIGHT2="$RIGHT2" \
        WRONG3="$WRONG3" RIGHT3="$RIGHT3" WRONG4="$WRONG4" RIGHT4="$RIGHT4" \
        perl -pe '
          s/\Q$ENV{WRONG1}\E/$ENV{RIGHT1}/;
          s/\Q$ENV{WRONG2}\E/$ENV{RIGHT2}/;
          s/\Q$ENV{WRONG3}\E/$ENV{RIGHT3}/;
          s/\Q$ENV{WRONG4}\E/$ENV{RIGHT4}/;
        ' "$STAFF_FIXTURE" > "$EXPECTED_TMP" 2>/dev/null

        # Compare with a trailing-newline-normalized checksum, not the raw
        # file bytes -- found by a fresh-context adversarial pass: a fully
        # correct submission (all 4 corrections applied, nothing else
        # touched) that differed from the expected file ONLY by a missing
        # or extra trailing newline -- an invisible, extremely common
        # artifact of how a tool writes a file -- failed with a message
        # ("no other line changed") that actively misled the learner about
        # the real cause. `$(cat file)` strips all trailing newlines in
        # bash command substitution; hashing that normalized form (not the
        # raw file) makes trailing-newline differences invisible to this
        # check while staying fully sensitive to every other byte,
        # including mid-file blank lines and trailing whitespace within a
        # line -- only the absolute end-of-file newline count is ignored.
        EXPECTED_NORMALIZED_SUM="$(printf '%s' "$(cat "$EXPECTED_TMP" 2>/dev/null)" | file_checksum /dev/stdin 2>/dev/null || echo "EXPECTED_BUILD_FAILED")"
        LEARNER_NORMALIZED_SUM="$(printf '%s' "$(cat "$CORRECTED" 2>/dev/null)" | file_checksum /dev/stdin 2>/dev/null || echo "LEARNER_READ_FAILED")"
        rm -f "$EXPECTED_TMP"

        if [[ "$EXPECTED_NORMALIZED_SUM" == "$LEARNER_NORMALIZED_SUM" ]]; then
          check "staff-list-corrected.txt has all 4 corrections applied, with no other line changed" pass
        else
          check "staff-list-corrected.txt has all 4 corrections applied, with no other line changed" fail
        fi
      fi
    else
      check "staff-list-corrected.txt has all 4 corrections applied, with no other line changed" fail
    fi

    # 5. wade-in-workshop/CLAUDE.md (the same file Module 01 already created
    #    at the workshop root -- see docs/workshop-design.md §14 item 5) now
    #    contains at least 3 of the 4 required section headers, each matched
    #    as an EXACT whole line (`grep -Fxq`), not a substring -- so the
    #    file's own pre-existing "## Never touch `checks/`" heading (a
    #    different, longer line) never accidentally counts as the required
    #    "## Never touch" header. A case statement, not `declare -A`, per
    #    this script's own bash-3.2 rule established above.
    CLAUDE_MD="$ROOT/CLAUDE.md"
    CLAUDE_LINK_COUNT="$(stat -f '%l' "$CLAUDE_MD" 2>/dev/null || stat -c '%h' "$CLAUDE_MD" 2>/dev/null || echo "1")"
    if [[ -L "$CLAUDE_MD" ]]; then
      check "CLAUDE.md has at least 3 of the 4 required house-rules section headers (found a symlink, not a real file)" fail
    elif [[ -f "$CLAUDE_MD" && "$CLAUDE_LINK_COUNT" != "1" ]]; then
      check "CLAUDE.md has at least 3 of the 4 required house-rules section headers (found a hard link, not an independently-written file)" fail
    elif [[ -f "$CLAUDE_MD" ]]; then
      HEADER_COUNT=0
      FOUND_HEADERS=()
      for header in "## About this folder" "## House rules" "## How I like output" "## Never touch"; do
        if grep -Fxq "$header" "$CLAUDE_MD" 2>/dev/null; then
          HEADER_COUNT=$((HEADER_COUNT + 1))
          FOUND_HEADERS+=("$header")
        fi
      done
      if [[ "$HEADER_COUNT" -ge 3 ]]; then
        check "CLAUDE.md has at least 3 of the 4 required house-rules section headers (found $HEADER_COUNT/4)" pass
      else
        check "CLAUDE.md has at least 3 of the 4 required house-rules section headers (found $HEADER_COUNT/4: ${FOUND_HEADERS[*]:-none})" fail
      fi
    else
      check "CLAUDE.md has at least 3 of the 4 required house-rules section headers" fail
    fi

    # 5b. The Module 01 safety preamble is still present -- found by a
    #    fresh-context adversarial pass: a session asked to "add sections"
    #    to CLAUDE.md could plausibly regenerate the whole file instead of
    #    appending, silently dropping the original "Never touch checks/"
    #    and "stay inside this folder" instructions while still adding all
    #    4 new headers cleanly -- reproduced directly, a full 5/5 pass with
    #    the original safety content entirely gone. This can't prove the
    #    CONTENT still means what it meant (a determined rewrite could keep
    #    the heading text and gut the instruction under it, the same
    #    provenance limit every module's checks already carry) but it does
    #    catch the specific, plausible accident this module's own task
    #    invites: the two original headings disappearing outright.
    if [[ -f "$CLAUDE_MD" && ! -L "$CLAUDE_MD" && "$CLAUDE_LINK_COUNT" == "1" ]]; then
      SAFETY_PREAMBLE_OK=true
      for original_header in "## Never touch \`checks/\`" "## Stay inside this folder unless a module says otherwise"; do
        grep -Fxq "$original_header" "$CLAUDE_MD" 2>/dev/null || SAFETY_PREAMBLE_OK=false
      done
      if [[ "$SAFETY_PREAMBLE_OK" == true ]]; then
        check "CLAUDE.md still has the original Module 01 safety headings (not overwritten)" pass
      else
        check "CLAUDE.md still has the original Module 01 safety headings (not overwritten - add your new sections, don't replace the file)" fail
      fi
    else
      check "CLAUDE.md still has the original Module 01 safety headings (not overwritten)" fail
    fi

    # 6. Own-words answers file: same discipline as Modules 01-02 -- presence-
    #    checked for genuine content, rejecting the literal placeholder text
    #    from the module page itself, and rejecting a symlink or hard link
    #    standing in for a real file.
    ANSWERS03="$ROOT/03-files/answers.txt"
    ANSWERS03_LINK_COUNT="$(stat -f '%l' "$ANSWERS03" 2>/dev/null || stat -c '%h' "$ANSWERS03" 2>/dev/null || echo "1")"
    PLACEHOLDER_RULE03="<one house rule you wrote and what specific Double Deuce filing quirk it responds to>"
    PLACEHOLDER_CHECK03="<how you checked the corrected file yourself, against the memo, rather than trusting it on sight>"
    PLACEHOLDER_CHANGE03="<in your own words, what will actually be different about a session's behavior now that CLAUDE.md has these rules>"
    if [[ "$FILES_DIR_OK" == false ]]; then
      check "03-files/answers.txt has all three reflection answers, in your own words (03-files/ is a symlink, not a real directory)" fail
    elif [[ -L "$ANSWERS03" ]]; then
      check "03-files/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS03" && "$ANSWERS03_LINK_COUNT" != "1" ]]; then
      check "03-files/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS03" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01's identical pattern, above, for why.
      for label in "HOUSE_RULE:" "WHAT_I_CHECKED:" "WHAT_CHANGES:"; do
        case "$label" in
          "HOUSE_RULE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_RULE03" ;;
          "WHAT_I_CHECKED:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_CHECK03" ;;
          "WHAT_CHANGES:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_CHANGE03" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS03" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "03-files/answers.txt has all three reflection answers, in your own words" pass
      else
        check "03-files/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "03-files/answers.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  04)
    # 1. 04-scripts/ itself is a real directory, not a symlink standing in
    #    for one -- same convention as Module 02's 02-meet/ check: a
    #    symlinked parent would let the required output actually live
    #    outside the sandbox while still passing every downstream check.
    EXPECTED_04_SCRIPTS="$ROOT/04-scripts"
    SCRIPTS_DIR_OK=true
    if [[ -e "$EXPECTED_04_SCRIPTS" ]]; then
      REAL_04_SCRIPTS="$(cd "$EXPECTED_04_SCRIPTS" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_04_SCRIPTS" != "$EXPECTED_04_SCRIPTS" ]]; then
        SCRIPTS_DIR_OK=false
      fi
    fi
    if [[ "$SCRIPTS_DIR_OK" == true && -d "$EXPECTED_04_SCRIPTS" ]]; then
      check "04-scripts/ directory exists (not a symlink)" pass
    else
      check "04-scripts/ directory exists (not a symlink)" fail
      SCRIPTS_DIR_OK=false
    fi

    # 2. 04-scripts/door-report.txt exists for real -- not a symlink, and not
    #    a hard link either (same discipline as Module 02's summary.txt: this
    #    file is learner/Claude-Code-authored, not copied from a fixture, so
    #    any link count above 1 means it's sharing bytes with some other path
    #    rather than having been written here).
    REPORT="$ROOT/04-scripts/door-report.txt"
    REPORT_LINK_COUNT="$(stat -f '%l' "$REPORT" 2>/dev/null || stat -c '%h' "$REPORT" 2>/dev/null || echo "1")"
    REPORT_OK=false
    if [[ "$SCRIPTS_DIR_OK" == false ]]; then
      check "04-scripts/door-report.txt exists and is non-empty (04-scripts/ isn't set up as a real directory yet)" fail
    elif [[ -L "$REPORT" ]]; then
      check "04-scripts/door-report.txt exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$REPORT" && "$REPORT_LINK_COUNT" != "1" ]]; then
      check "04-scripts/door-report.txt exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$REPORT" ]]; then
      check "04-scripts/door-report.txt exists and is non-empty" pass
      REPORT_OK=true
    else
      check "04-scripts/door-report.txt exists and is non-empty" fail
    fi

    # 2b. Some actual script file sits in 04-scripts/ too -- not just the
    #    report. Found by a fresh-context adversarial review: the module's
    #    own text promises "04-scripts/ should contain both the script
    #    itself and door-report.txt," but nothing enforced that half of the
    #    claim -- a learner (or their session) could hand-type door-report.txt
    #    directly, never have Claude Code write or run anything, and still
    #    pass every other check. Reproduced directly: a folder with only
    #    door-report.txt and answers.txt in it passed 7/7 before this fix.
    #    This can't prove Claude Code wrote a CORRECT script (the same
    #    provenance limit named workshop-wide in §8 -- no local check can),
    #    but it can and should catch the specific case of no script existing
    #    at all, which is strictly weaker than that limit and was silently
    #    unguarded. Any regular file other than door-report.txt/answers.txt
    #    counts -- this workshop doesn't mandate a specific language.
    SCRIPT_FOUND=false
    if [[ "$SCRIPTS_DIR_OK" == true ]]; then
      for f in "$EXPECTED_04_SCRIPTS"/*; do
        [[ -e "$f" ]] || continue
        BASE_NAME="$(basename "$f")"
        if [[ "$BASE_NAME" != "door-report.txt" && "$BASE_NAME" != "answers.txt" && -f "$f" && ! -L "$f" ]]; then
          SCRIPT_FOUND=true
          break
        fi
      done
    fi
    if [[ "$SCRIPT_FOUND" == true ]]; then
      check "04-scripts/ contains the script itself, not just the report" pass
    else
      check "04-scripts/ contains the script itself, not just the report" fail
    fi

    # 3. All 12 door-count fixtures are unmodified -- checksum-verified
    #    against the embedded, pinned hashes above (never a checksum
    #    computed from the live fixture at run time, which would let a
    #    tampered fixture silently become its own new "pristine" reference --
    #    the same class of bypass Module 01 and 02's fixture checks already
    #    guard against). Recomputing TOTAL/BEST/WORST below only happens if
    #    every fixture passes here; a single tampered or missing fixture
    #    fails this check AND every downstream figure check, with a "contact
    #    the workshop" message, rather than quietly computing a wrong answer
    #    from bad input.
    DOOR_COUNT_DATES=(2026-08-01 2026-08-02 2026-08-03 2026-08-04 2026-08-05 2026-08-06 2026-08-07 2026-08-08 2026-08-09 2026-08-10 2026-08-11 2026-08-12)
    FIXTURES_OK=true
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      check "all 12 door-count fixtures unmodified (couldn't verify: no checksum tool found on this system - contact the workshop)" fail
      FIXTURES_OK=false
    else
      BAD_FIXTURES=()
      for d in "${DOOR_COUNT_DATES[@]}"; do
        FPATH="$ROOT/fixtures/door-count-$d.txt"
        EXPECTED_SUM="$(door_count_expected_sha256 "$d")"
        ACTUAL_SUM="$(file_checksum "$FPATH" 2>/dev/null || echo "MISSING_FIXTURE")"
        if [[ "$ACTUAL_SUM" != "$EXPECTED_SUM" ]]; then
          BAD_FIXTURES+=("door-count-$d.txt")
        fi
      done
      if [[ "${#BAD_FIXTURES[@]}" -eq 0 ]]; then
        check "all 12 door-count fixtures unmodified (checksum verified)" pass
      else
        check "all 12 door-count fixtures unmodified (contact the workshop, not your own mistake - affected: ${BAD_FIXTURES[*]})" fail
        FIXTURES_OK=false
      fi
    fi

    # Recompute the monthly total, best night, and worst night independently
    # from the pristine fixtures -- never from door-report.txt itself, and
    # never a hardcoded answer key -- so a wrong script produces a wrong
    # report and fails here, and this stays correct even if a future fixture
    # revision changes the real figures.
    TOTAL_EXPECTED=0
    BEST_DATE=""; BEST_COUNT=-1
    WORST_DATE=""; WORST_COUNT=-1
    if [[ "$FIXTURES_OK" == true ]]; then
      for d in "${DOOR_COUNT_DATES[@]}"; do
        FPATH="$ROOT/fixtures/door-count-$d.txt"
        LINE="$(grep -m1 '^Count:' "$FPATH" 2>/dev/null || true)"
        N="$(echo "$LINE" | sed 's/^Count:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        TOTAL_EXPECTED=$((TOTAL_EXPECTED + N))
        if [[ "$N" -gt "$BEST_COUNT" ]]; then BEST_COUNT="$N"; BEST_DATE="$d"; fi
        if [[ "$WORST_COUNT" -eq -1 || "$N" -lt "$WORST_COUNT" ]]; then WORST_COUNT="$N"; WORST_DATE="$d"; fi
      done
    fi

    # Helper: read one labeled value out of door-report.txt, exact-trimmed,
    # no substring or token matching involved -- door-report.txt is a
    # structured labeled file the learner's script writes (format given
    # verbatim in the module page), not free prose, so an exact per-label
    # match is the right tool here and sidesteps the substring-match bug
    # class Module 02's own review found in its free-text summary check.
    read_report_label() {
      local label="$1"
      [[ "$REPORT_OK" == true ]] || { echo ""; return; }
      local line
      line="$(grep -m1 "^$label" "$REPORT" 2>/dev/null || true)"
      echo "$line" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    # 4. The exact monthly total.
    if [[ "$REPORT_OK" == true && "$FIXTURES_OK" == true ]]; then
      ACTUAL_TOTAL="$(read_report_label 'TOTAL:')"
      if [[ "$ACTUAL_TOTAL" == "$TOTAL_EXPECTED" ]]; then
        check "door-report.txt has the exact monthly total ($TOTAL_EXPECTED)" pass
      else
        check "door-report.txt has the exact monthly total (expected $TOTAL_EXPECTED, found '${ACTUAL_TOTAL:-nothing}')" fail
      fi
    else
      check "door-report.txt has the exact monthly total (contact the workshop, not your own mistake)" fail
    fi

    # 5. The exact best night -- date AND count together, since a report
    #    with the right count on the wrong date (or vice versa) isn't
    #    actually correct.
    if [[ "$REPORT_OK" == true && "$FIXTURES_OK" == true ]]; then
      ACTUAL_BEST_DATE="$(read_report_label 'BEST_NIGHT_DATE:')"
      ACTUAL_BEST_COUNT="$(read_report_label 'BEST_NIGHT_COUNT:')"
      if [[ "$ACTUAL_BEST_DATE" == "$BEST_DATE" && "$ACTUAL_BEST_COUNT" == "$BEST_COUNT" ]]; then
        check "door-report.txt has the exact best night ($BEST_DATE, $BEST_COUNT)" pass
      else
        check "door-report.txt has the exact best night (expected $BEST_DATE / $BEST_COUNT, found '${ACTUAL_BEST_DATE:-nothing}' / '${ACTUAL_BEST_COUNT:-nothing}')" fail
      fi
    else
      check "door-report.txt has the exact best night (contact the workshop, not your own mistake)" fail
    fi

    # 6. The exact worst night, same discipline as the best night above.
    if [[ "$REPORT_OK" == true && "$FIXTURES_OK" == true ]]; then
      ACTUAL_WORST_DATE="$(read_report_label 'WORST_NIGHT_DATE:')"
      ACTUAL_WORST_COUNT="$(read_report_label 'WORST_NIGHT_COUNT:')"
      if [[ "$ACTUAL_WORST_DATE" == "$WORST_DATE" && "$ACTUAL_WORST_COUNT" == "$WORST_COUNT" ]]; then
        check "door-report.txt has the exact worst night ($WORST_DATE, $WORST_COUNT)" pass
      else
        check "door-report.txt has the exact worst night (expected $WORST_DATE / $WORST_COUNT, found '${ACTUAL_WORST_DATE:-nothing}' / '${ACTUAL_WORST_COUNT:-nothing}')" fail
      fi
    else
      check "door-report.txt has the exact worst night (contact the workshop, not your own mistake)" fail
    fi

    # 7. Own-words answers file: same discipline as Modules 01 and 02 --
    #    presence-checked for genuine content, rejecting the literal
    #    placeholder text from the module page itself, and rejecting a
    #    symlink or hard link standing in for a real file.
    ANSWERS04="$ROOT/04-scripts/answers.txt"
    ANSWERS04_LINK_COUNT="$(stat -f '%l' "$ANSWERS04" 2>/dev/null || stat -c '%h' "$ANSWERS04" 2>/dev/null || echo "1")"
    PLACEHOLDER_PLAN04="<did you ask Claude Code for a plan before it wrote the script - what did you ask for?>"
    PLACEHOLDER_CHECKED04="<which night's figure did you verify by hand against its raw fixture file, and what did you find?>"
    PLACEHOLDER_NEXT04="<what would you do differently next time you ask Claude Code to write and run a script?>"
    if [[ "$SCRIPTS_DIR_OK" == false ]]; then
      check "04-scripts/answers.txt has all three reflection answers, in your own words (04-scripts/ isn't set up as a real directory yet)" fail
    elif [[ -L "$ANSWERS04" ]]; then
      check "04-scripts/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS04" && "$ANSWERS04_LINK_COUNT" != "1" ]]; then
      check "04-scripts/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS04" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01/02's identical pattern, above.
      for label in "PLAN_FIRST:" "CHECKED_BY_HAND:" "WHAT_NEXT_TIME:"; do
        case "$label" in
          "PLAN_FIRST:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_PLAN04" ;;
          "CHECKED_BY_HAND:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_CHECKED04" ;;
          "WHAT_NEXT_TIME:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_NEXT04" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS04" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "04-scripts/answers.txt has all three reflection answers, in your own words" pass
      else
        check "04-scripts/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "04-scripts/answers.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  05)
    # Module 05 is named, in docs/workshop-design.md itself, as this arc's
    # weakest deterministic tier: real live web research against the real
    # internet, not a workshop-supplied fixture. This checker is deliberately
    # [structural-only] -- it verifies the brief's shape and sourcing
    # discipline (does it exist, does it have the required sections, does it
    # cite real-looking sources from more than one site, does its comparison
    # table actually have content in every cell), never whether any specific
    # price or feature claim is true. That substance is this module's Tier-2
    # reflection, not something a local script can check against a live,
    # third-party website without becoming network-dependent itself.

    # 1. 05-research/ itself is a real directory, not a symlink standing in
    #    for one -- same convention as 02-meet/'s own directory check.
    EXPECTED_05_RESEARCH="$ROOT/05-research"
    RESEARCH_DIR_OK=true
    if [[ -e "$EXPECTED_05_RESEARCH" ]]; then
      REAL_05_RESEARCH="$(cd "$EXPECTED_05_RESEARCH" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_05_RESEARCH" != "$EXPECTED_05_RESEARCH" ]]; then
        RESEARCH_DIR_OK=false
      fi
    fi

    # 2. 05-research/comparison-brief.md exists for real -- not a symlink,
    #    and not a hard link either (checked via link count, the same
    #    convention as 02-meet/summary.txt, since this file is learner/
    #    Claude-Code-authored, not copied from a fixture, so there's no
    #    single reference inode to compare against).
    BRIEF="$ROOT/05-research/comparison-brief.md"
    BRIEF_LINK_COUNT="$(stat -f '%l' "$BRIEF" 2>/dev/null || stat -c '%h' "$BRIEF" 2>/dev/null || echo "1")"
    BRIEF_REAL_FILE=false
    if [[ "$RESEARCH_DIR_OK" == false ]]; then
      check "05-research/comparison-brief.md exists and is non-empty (05-research/ is a symlink, not a real directory)" fail
    elif [[ -L "$BRIEF" ]]; then
      check "05-research/comparison-brief.md exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$BRIEF" && "$BRIEF_LINK_COUNT" != "1" ]]; then
      check "05-research/comparison-brief.md exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$BRIEF" ]]; then
      check "05-research/comparison-brief.md exists and is non-empty" pass
      BRIEF_REAL_FILE=true
    else
      check "05-research/comparison-brief.md exists and is non-empty" fail
    fi

    # 3. All 4 required section headers present, verbatim -- a closed set,
    #    the module's own text names these exact four strings. An ordinary
    #    indexed array (not `declare -A`) is fine under bash 3.2; only
    #    associative arrays crash it.
    REQUIRED_HEADERS=("## Platforms Compared" "## Pricing" "## Features" "## Recommendation")
    if [[ "$BRIEF_REAL_FILE" == true ]]; then
      MISSING_HEADERS=()
      for h in "${REQUIRED_HEADERS[@]}"; do
        grep -qxF "$h" "$BRIEF" 2>/dev/null || MISSING_HEADERS+=("$h")
      done
      if [[ "${#MISSING_HEADERS[@]}" -eq 0 ]]; then
        check "comparison-brief.md has all 4 required section headers" pass
      else
        check "comparison-brief.md has all 4 required section headers (still missing: ${MISSING_HEADERS[*]})" fail
      fi
    else
      check "comparison-brief.md has all 4 required section headers" fail
    fi

    # 4. At least 3 source URLs from at least 3 distinct SITES -- a count,
    #    not a pattern match, and not a reachability check (this checker
    #    makes no network calls of its own; verifying a URL is live is out
    #    of scope, named honestly in the module text as Part 4's job, not
    #    this script's). "Site" is approximated as the last two dot-
    #    separated labels of the hostname (a naive registrable-domain
    #    guess, not a real public-suffix-list lookup), specifically so
    #    `www.eventbrite.com` and `checkout.eventbrite.com` count as the
    #    SAME site as `eventbrite.com` -- found by a fresh-context
    #    adversarial pass, which cited one real company three times via
    #    three subdomains and passed "3 distinct sites" while researching
    #    exactly one platform. A trailing sentence-final period (a bare
    #    URL with no path, at the end of a sentence, e.g. "...see
    #    https://eventbrite.com.") is stripped before comparison too --
    #    the same pass found this turned two real citations of one site
    #    into an apparent third, from completely ordinary prose, not
    #    deliberate gaming. Named limit: the last-two-labels heuristic is
    #    wrong for multi-part public suffixes like `co.uk` (it would treat
    #    `example.co.uk` as site "co.uk") -- accepted for now since no
    #    ticketing platform this module expects uses one, not claimed to
    #    be a general-purpose registrable-domain parser.
    if [[ "$BRIEF_REAL_FILE" == true ]]; then
      HOSTNAMES="$(grep -oE 'https?://[A-Za-z0-9.-]+' "$BRIEF" 2>/dev/null \
        | sed -E 's#^https?://##' \
        | sed -E 's/\.$//' \
        | tr '[:upper:]' '[:lower:]' \
        | awk -F'.' '{if (NF>=2) print $(NF-1)"."$NF; else print $0}' \
        | sort -u)"
      HOSTNAME_COUNT="$(printf '%s\n' "$HOSTNAMES" | grep -c '.' || true)"
      if [[ "$HOSTNAME_COUNT" -ge 3 ]]; then
        check "comparison-brief.md cites source URLs from at least 3 distinct sites (found $HOSTNAME_COUNT)" pass
      else
        check "comparison-brief.md cites source URLs from at least 3 distinct sites (found $HOSTNAME_COUNT)" fail
      fi
    else
      check "comparison-brief.md cites source URLs from at least 3 distinct sites" fail
    fi

    # 5. A comparison table exists, INSIDE THE PRICING SECTION SPECIFICALLY,
    #    with at least 3 data rows (plus a header row, so at least 4 pipe-
    #    delimited content rows total) and no empty cells in any of them --
    #    a reasonable structural proxy for "every claim row in the required
    #    comparison table non-empty," per docs/workshop-design.md §7,
    #    without trying to validate that any individual cell's content is
    #    factually correct.
    #    Scoping to the Pricing section (from its own header to the next
    #    "## " header, or end of file) is itself a fix: a fresh-context
    #    adversarial pass found the original version scanned the WHOLE
    #    document, so an unrelated decorative table anywhere else (e.g.
    #    stray notes under Features) could either falsely PASS a brief with
    #    no real Pricing table at all, or falsely FAIL a perfectly correct
    #    Pricing table over one unrelated blank cell somewhere else in the
    #    file -- both reproduced directly.
    #    A markdown table row matches (after trimming leading whitespace,
    #    since a table indented under a list item or reformatted with a
    #    couple of leading spaces is still valid Markdown and was
    #    demonstrated to be silently rejected by a stricter
    #    column-zero-only version of this regex) `^\|.*\|[[:space:]]*$`;
    #    its separator row (the `|---|---|---|` line under the header) is
    #    told apart from a real content row by stripping every `|`, `:`,
    #    `*`, `-`, and space character from the line and checking whether
    #    anything is left -- a separator row has nothing left, a real row
    #    (even one made mostly of dashes and colons in its actual text)
    #    still does. A single-regex version of this same idea was tried
    #    first and was wrong: it only matched between the FIRST and LAST
    #    pipe on the line, so a real 4-column separator (three internal
    #    pipes) never matched at all and the check failed a perfectly
    #    correct table -- caught by running this check against a real,
    #    honestly-written table, not by reading the regex.
    if [[ "$BRIEF_REAL_FILE" == true ]]; then
      PRICING_SECTION="$(awk '/^## Pricing[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag' "$BRIEF" 2>/dev/null)"
      TABLE_LINES="$(printf '%s\n' "$PRICING_SECTION" | grep -E '^[[:space:]]*\|.*\|[[:space:]]*$' 2>/dev/null || true)"
      CONTENT_ROWS=0
      EMPTY_CELL_ROWS=0
      HAS_SEPARATOR=false
      while IFS= read -r raw_line; do
        [[ -z "$raw_line" ]] && continue
        line="$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//')"
        STRIPPED="$(printf '%s' "$line" | sed 's/[|:*[:space:]-]//g')"
        if [[ -z "$STRIPPED" ]]; then
          HAS_SEPARATOR=true
          continue
        fi
        CONTENT_ROWS=$((CONTENT_ROWS + 1))
        INNER="${line#|}"
        INNER="${INNER%|}"
        ROW_EMPTY=false
        OLDIFS="$IFS"
        IFS='|'
        read -ra CELLS <<< "$INNER"
        IFS="$OLDIFS"
        for cell in "${CELLS[@]}"; do
          TRIMMED="$(printf '%s' "$cell" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          [[ -z "$TRIMMED" ]] && ROW_EMPTY=true
        done
        if [[ "$ROW_EMPTY" == true ]]; then
          EMPTY_CELL_ROWS=$((EMPTY_CELL_ROWS + 1))
        fi
      done <<< "$TABLE_LINES"
      if [[ "$HAS_SEPARATOR" == true && "$CONTENT_ROWS" -ge 4 && "$EMPTY_CELL_ROWS" -eq 0 ]]; then
        check "comparison-brief.md has a comparison table with at least 3 rows and no empty cells" pass
      else
        check "comparison-brief.md has a comparison table with at least 3 rows and no empty cells" fail
      fi
    else
      check "comparison-brief.md has a comparison table with at least 3 rows and no empty cells" fail
    fi

    # 6. Own-words answers file: same discipline as every earlier module --
    #    presence-checked for genuine content, rejecting the literal
    #    placeholder text from the module page itself, and rejecting a
    #    symlink or hard link standing in for a real file.
    ANSWERS05="$ROOT/05-research/answers.txt"
    ANSWERS05_LINK_COUNT="$(stat -f '%l' "$ANSWERS05" 2>/dev/null || stat -c '%h' "$ANSWERS05" 2>/dev/null || echo "1")"
    PLACEHOLDER_SOURCES05="<did you open at least one cited page yourself and compare it to what the brief says? what did you find?>"
    PLACEHOLDER_DISAGREE05="<did the sources disagree with each other about anything, or did Claude Code's first answer turn out to be wrong once you checked? what happened?>"
    PLACEHOLDER_CONFIDENCE05="<how much would you trust this brief if you were handing it to Tilghman today, and what would you still want to double-check?>"
    if [[ "$RESEARCH_DIR_OK" == false ]]; then
      check "05-research/answers.txt has all three reflection answers, in your own words (05-research/ is a symlink, not a real directory)" fail
    elif [[ -L "$ANSWERS05" ]]; then
      check "05-research/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS05" && "$ANSWERS05_LINK_COUNT" != "1" ]]; then
      check "05-research/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS05" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01's identical pattern, above, for why.
      for label in "SOURCES_CHECKED:" "DISAGREEMENT:" "CONFIDENCE:"; do
        case "$label" in
          "SOURCES_CHECKED:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_SOURCES05" ;;
          "DISAGREEMENT:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_DISAGREE05" ;;
          "CONFIDENCE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_CONFIDENCE05" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS05" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "05-research/answers.txt has all three reflection answers, in your own words" pass
      else
        check "05-research/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "05-research/answers.txt has all three reflection answers, in your own words" fail
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
