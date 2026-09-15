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
