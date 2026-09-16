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
