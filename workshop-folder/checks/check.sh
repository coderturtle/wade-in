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

trim_field() {
  # Strip leading/trailing whitespace from one CSV field value. Found by a
  # fresh-context adversarial pass on Module 07: a semantically-correct
  # merge, written with a space after each comma (`BK-101, Name, ...`
  # instead of no-space CSV -- a plausible style if a script hand-writes
  # the CSV as text), failed 3 of 8 checks with generic messages giving no
  # hint the real cause was stray whitespace, not a merge error. Trimming
  # each field before comparison treats "400" and " 400" as the same
  # value, matching what a human would consider "the same," without
  # weakening the exact-match check against any REAL content difference.
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

array_index_of() {
  # Bash-3.2-safe lookup: given a target value and a haystack passed as
  # remaining args, print the matching index or "-1". This, plus a plain
  # indexed array, is this script's stand-in for an associative array's key
  # lookup -- `declare -A` is never used anywhere in this script (stock
  # macOS bash 3.2 has no associative arrays at all and crashes hard on one,
  # confirmed and fixed twice already; see the comment on Module 01's
  # answers check below for the exact failure mode).
  #
  # Caller responsibility: expanding "${arr[@]}" for a genuinely
  # zero-length array under this script's `set -u` trips a real bash
  # bug present in versions before 4.4 ("unbound variable" on an empty
  # array even though it was explicitly initialized with `arr=()`) -- stock
  # bash 3.2 has this bug. Every call site below guards with
  # `[[ "${#arr[@]}" -gt 0 ]]` before expanding an array into this
  # function's arguments, rather than expanding an possibly-empty array
  # directly.
  local target="$1"
  shift
  local i=0
  local v
  for v in "$@"; do
    if [[ "$v" == "$target" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  printf '%s\n' "-1"
  return 1
}

# Embedded checksums: the real, known-good sha256 of each fixture as
# authored, computed once and pinned here. Update this value deliberately
# (and note why, in a commit message) any time a fixture's real content
# changes -- never let it silently drift from what's actually on disk.
EXPECTED_WELCOME_NOTE_SHA256="f9f6b278a9732f0dbcc0969414f34d7365942ce8e8aea705775a5e933b8e7475"
EXPECTED_VENUE_HISTORY_SHA256="3afe8aea8f84e6fff4da67c0f48d14b7956c6630ff06756c2ea2bb6180eec7a5"
EXPECTED_PENNY_BOOKINGS_SHA256="a84d9f1d87635beee84c0cebb4543c5212c7b09bab9d52bf20d755f4bbd78c6d"
EXPECTED_GARRETT_BOOKINGS_SHA256="4d1159c92e231829fd0b985028e268bfcc31d9cb3aa806c310e28a420dcc388d"

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
  07)
    # Module 07: Penny's Ledger. Merge two overlapping bookings CSVs under a
    # stated rule -- Penny's copy is authoritative for any booking ID
    # present in both files (she's the current owner; Garrett's copy is the
    # stale one) -- add a total_due column, and prove nothing was lost or
    # invented. Ground truth is recomputed from the two pristine fixtures at
    # check time, never read from an embedded key, so this only passes if
    # the merge was genuinely done. Same no-`declare -A` discipline as every
    # case above: every lookup uses a plain indexed array plus
    # `array_index_of` (defined near the top of this script), guarded
    # against the empty-array `set -u` bug noted there.

    PENNY_FIXTURE="$ROOT/fixtures/penny-bookings.csv"
    GARRETT_FIXTURE="$ROOT/fixtures/garrett-bookings.csv"
    OUTPUT_DIR="$ROOT/07-csv"
    OUTPUT_FILE="$OUTPUT_DIR/bookings-clean.csv"
    REQUIRED_HEADER="booking_id,name,event_date,deposit,balance,total_due"

    # 1. Fixture integrity: both source CSVs match their pinned checksums.
    #    Checked first so every downstream check can say plainly whether a
    #    failure is the learner's or a corrupted/tampered fixture's -- the
    #    same discipline as Module 01/02's fixture checks, applied to two
    #    fixtures instead of one.
    FIXTURES_OK=true
    PENNY_SUM="$(file_checksum "$PENNY_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    GARRETT_SUM="$(file_checksum "$GARRETT_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$PENNY_SUM" != "$EXPECTED_PENNY_BOOKINGS_SHA256" || "$GARRETT_SUM" != "$EXPECTED_GARRETT_BOOKINGS_SHA256" ]]; then
      FIXTURES_OK=false
      check "workshop fixtures penny-bookings.csv and garrett-bookings.csv match their expected content (contact the workshop, not your own mistake)" fail
    else
      check "workshop fixtures penny-bookings.csv and garrett-bookings.csv match their expected content" pass
    fi

    # 2. 07-csv/ is a real directory (not a symlink standing in for one --
    #    same bypass class as Module 02's 02-meet/ check, reproduced there
    #    with a symlinked parent redirecting outside the sandbox) and
    #    bookings-clean.csv is a real file inside it: not a symlink, and not
    #    a hard link either (a freshly-merged file never shares an inode
    #    with anything else on a first write).
    OUTPUT_DIR_OK=true
    if [[ -e "$OUTPUT_DIR" ]]; then
      REAL_OUTPUT_DIR="$(cd "$OUTPUT_DIR" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_OUTPUT_DIR" != "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR_OK=false
      fi
    else
      OUTPUT_DIR_OK=false
    fi
    OUTPUT_LINK_COUNT="$(stat -f '%l' "$OUTPUT_FILE" 2>/dev/null || stat -c '%h' "$OUTPUT_FILE" 2>/dev/null || echo "1")"
    LEARNER_FILE_OK=false
    if [[ "$OUTPUT_DIR_OK" == false ]]; then
      check "07-csv/bookings-clean.csv exists (07-csv/ is a symlink, not a real directory)" fail
    elif [[ -L "$OUTPUT_FILE" ]]; then
      check "07-csv/bookings-clean.csv exists (found a symlink, not a real file)" fail
    elif [[ -f "$OUTPUT_FILE" && "$OUTPUT_LINK_COUNT" != "1" ]]; then
      check "07-csv/bookings-clean.csv exists (found a hard link, not an independently-written file)" fail
    elif [[ -s "$OUTPUT_FILE" ]]; then
      check "07-csv/bookings-clean.csv exists and is non-empty" pass
      LEARNER_FILE_OK=true
    else
      check "07-csv/bookings-clean.csv exists and is non-empty" fail
    fi

    # 3. The exact required header row, given to the learner verbatim up
    #    front in the module itself -- an exact string match, not a loose
    #    one (a reordered or renamed column is not the required header).
    if [[ "$LEARNER_FILE_OK" == true ]]; then
      ACTUAL_HEADER="$(sed -n '1p' "$OUTPUT_FILE" 2>/dev/null)"
      ACTUAL_HEADER="${ACTUAL_HEADER%$'\r'}"
      # Compare column-by-column, each trimmed, not the raw header string --
      # same reasoning as trim_field above: "booking_id, name, ..." (a space
      # after the comma) is the same header to a human as "booking_id,name",
      # and this module never taught CSV syntax closely enough to make that
      # distinction load-bearing.
      ACTUAL_HEADER_TRIMMED="$(printf '%s' "$ACTUAL_HEADER" | awk -F',' '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i)}; out=$1; for(i=2;i<=NF;i++){out=out","$i}; print out}')"
      if [[ "$ACTUAL_HEADER_TRIMMED" == "$REQUIRED_HEADER" ]]; then
        check "bookings-clean.csv has the exact required header row" pass
      else
        check "bookings-clean.csv has the exact required header row" fail
      fi
    else
      check "bookings-clean.csv has the exact required header row" fail
    fi

    # 4. Recompute the true merged set from the two pristine fixtures.
    #    Garrett's file is read first as the base layer; Penny's file is
    #    read second and overwrites any ID it shares with Garrett's (her
    #    copy is authoritative on conflict -- she's the current owner) and
    #    adds any ID that's hers alone. This IS the merge rule the checker
    #    enforces, recomputed from pristine fixtures every run, not a hidden
    #    embedded key.
    EXPECTED_IDS=()
    EXPECTED_NAME=()
    EXPECTED_DATE=()
    EXPECTED_DEPOSIT=()
    EXPECTED_BALANCE=()
    if [[ "$FIXTURES_OK" == true ]]; then
      for SRC in "$GARRETT_FIXTURE" "$PENNY_FIXTURE"; do
        FIRST_LINE=true
        while IFS=',' read -r f_id f_name f_date f_deposit f_balance; do
          if [[ "$FIRST_LINE" == true ]]; then
            FIRST_LINE=false
            continue
          fi
          f_id="${f_id%$'\r'}"
          f_balance="${f_balance%$'\r'}"
          [[ -z "$f_id" ]] && continue
          IDX="-1"
          if [[ "${#EXPECTED_IDS[@]}" -gt 0 ]]; then
            IDX="$(array_index_of "$f_id" "${EXPECTED_IDS[@]}")"
          fi
          if [[ "$IDX" -ge 0 ]]; then
            EXPECTED_NAME[$IDX]="$f_name"
            EXPECTED_DATE[$IDX]="$f_date"
            EXPECTED_DEPOSIT[$IDX]="$f_deposit"
            EXPECTED_BALANCE[$IDX]="$f_balance"
          else
            EXPECTED_IDS+=("$f_id")
            EXPECTED_NAME+=("$f_name")
            EXPECTED_DATE+=("$f_date")
            EXPECTED_DEPOSIT+=("$f_deposit")
            EXPECTED_BALANCE+=("$f_balance")
          fi
        done < "$SRC"
      done
    fi
    EXPECTED_COUNT="${#EXPECTED_IDS[@]}"

    # 5. Parse the learner's own output into matching arrays, preserving
    #    every row exactly as found (including a duplicate, if there is
    #    one) so the checks below can catch a duplicate or a dropped row
    #    instead of silently deduping the learner's own mistake away.
    ACTUAL_IDS=()
    ACTUAL_NAME=()
    ACTUAL_DATE=()
    ACTUAL_DEPOSIT=()
    ACTUAL_BALANCE=()
    ACTUAL_TOTAL=()
    if [[ "$LEARNER_FILE_OK" == true ]]; then
      FIRST_LINE=true
      while IFS=',' read -r a_id a_name a_date a_deposit a_balance a_total; do
        if [[ "$FIRST_LINE" == true ]]; then
          FIRST_LINE=false
          continue
        fi
        a_total="${a_total%$'\r'}"
        a_id="$(trim_field "$a_id")"
        a_name="$(trim_field "$a_name")"
        a_date="$(trim_field "$a_date")"
        a_deposit="$(trim_field "$a_deposit")"
        a_balance="$(trim_field "$a_balance")"
        a_total="$(trim_field "$a_total")"
        if [[ -z "$a_id" && -z "$a_name" && -z "$a_date" && -z "$a_deposit" && -z "$a_balance" && -z "$a_total" ]]; then
          continue
        fi
        ACTUAL_IDS+=("$a_id")
        ACTUAL_NAME+=("$a_name")
        ACTUAL_DATE+=("$a_date")
        ACTUAL_DEPOSIT+=("$a_deposit")
        ACTUAL_BALANCE+=("$a_balance")
        ACTUAL_TOTAL+=("$a_total")
      done < "$OUTPUT_FILE"
    fi
    ACTUAL_COUNT="${#ACTUAL_IDS[@]}"

    # 6. Row count equals the checker's own recomputed post-dedup count.
    if [[ "$FIXTURES_OK" == true && "$LEARNER_FILE_OK" == true && "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ]]; then
      check "row count matches the recomputed post-dedup count ($EXPECTED_COUNT)" pass
    else
      check "row count matches the recomputed post-dedup count ($EXPECTED_COUNT, found $ACTUAL_COUNT)" fail
    fi

    # 7. Closed-set comparison: the booking-ID set in bookings-clean.csv
    #    exactly equals the recomputed expected set -- no lost rows (an
    #    expected ID missing from the learner's file) and no invented rows
    #    (a learner ID that doesn't correspond to any real booking in either
    #    fixture). Checked both directions, index-based rather than array-
    #    expansion-based throughout, so a zero-length array on either side
    #    never gets expanded directly under this script's `set -u`.
    ID_SET_OK=true
    if [[ "$FIXTURES_OK" != true || "$LEARNER_FILE_OK" != true ]]; then
      ID_SET_OK=false
    else
      i=0
      while [[ $i -lt $EXPECTED_COUNT ]]; do
        eid="${EXPECTED_IDS[$i]}"
        IDX="-1"
        if [[ "${#ACTUAL_IDS[@]}" -gt 0 ]]; then
          IDX="$(array_index_of "$eid" "${ACTUAL_IDS[@]}")"
        fi
        [[ "$IDX" -lt 0 ]] && ID_SET_OK=false
        i=$((i + 1))
      done
      i=0
      while [[ $i -lt $ACTUAL_COUNT ]]; do
        aid="${ACTUAL_IDS[$i]}"
        IDX="-1"
        if [[ "${#EXPECTED_IDS[@]}" -gt 0 ]]; then
          IDX="$(array_index_of "$aid" "${EXPECTED_IDS[@]}")"
        fi
        [[ "$IDX" -lt 0 ]] && ID_SET_OK=false
        i=$((i + 1))
      done
    fi
    if [[ "$ID_SET_OK" == true ]]; then
      check "the booking-ID set exactly matches the recomputed expected set (no lost rows, no invented rows)" pass
    else
      check "the booking-ID set exactly matches the recomputed expected set (no lost rows, no invented rows)" fail
    fi

    # 8. For every surviving ID, name/event_date/deposit/balance exactly
    #    match that ID's source-of-truth value under the stated merge rule
    #    (Penny's copy wins on conflict) -- exact string comparison, not a
    #    substring or a loose numeric comparison.
    FIELDS_OK=true
    if [[ "$FIXTURES_OK" != true || "$LEARNER_FILE_OK" != true || "$ID_SET_OK" != true ]]; then
      FIELDS_OK=false
    else
      i=0
      while [[ $i -lt $EXPECTED_COUNT ]]; do
        eid="${EXPECTED_IDS[$i]}"
        IDX="-1"
        if [[ "${#ACTUAL_IDS[@]}" -gt 0 ]]; then
          IDX="$(array_index_of "$eid" "${ACTUAL_IDS[@]}")"
        fi
        if [[ "$IDX" -lt 0 ]]; then
          FIELDS_OK=false
        else
          [[ "${ACTUAL_NAME[$IDX]}" != "${EXPECTED_NAME[$i]}" ]] && FIELDS_OK=false
          [[ "${ACTUAL_DATE[$IDX]}" != "${EXPECTED_DATE[$i]}" ]] && FIELDS_OK=false
          [[ "${ACTUAL_DEPOSIT[$IDX]}" != "${EXPECTED_DEPOSIT[$i]}" ]] && FIELDS_OK=false
          [[ "${ACTUAL_BALANCE[$IDX]}" != "${EXPECTED_BALANCE[$i]}" ]] && FIELDS_OK=false
        fi
        i=$((i + 1))
      done
    fi
    if [[ "$FIELDS_OK" == true ]]; then
      check "every surviving booking's name/event_date/deposit/balance exactly match the source of truth (Penny's copy wins on conflict)" pass
    else
      check "every surviving booking's name/event_date/deposit/balance exactly match the source of truth (Penny's copy wins on conflict)" fail
    fi

    # 9. total_due is arithmetically correct per row: deposit + balance,
    #    recomputed by the checker from that row's own deposit/balance
    #    values. An internal-consistency check, independent of check 8
    #    above -- a row with the wrong deposit still needs the right sum of
    #    whatever it actually wrote. Deposit/balance/total_due are plain
    #    whole-dollar integers in this module's fixtures, so plain bash
    #    arithmetic (no bc/awk float dependency) is exact here; each value
    #    is validated as an integer string first so a non-numeric or
    #    empty field fails cleanly instead of crashing the arithmetic.
    TOTAL_OK=true
    if [[ "$LEARNER_FILE_OK" != true || "$ACTUAL_COUNT" -eq 0 ]]; then
      TOTAL_OK=false
    else
      i=0
      while [[ $i -lt $ACTUAL_COUNT ]]; do
        dep="${ACTUAL_DEPOSIT[$i]}"
        bal="${ACTUAL_BALANCE[$i]}"
        tot="${ACTUAL_TOTAL[$i]}"
        if [[ "$dep" =~ ^-?[0-9]+$ && "$bal" =~ ^-?[0-9]+$ && "$tot" =~ ^-?[0-9]+$ ]]; then
          ROW_EXPECTED_TOTAL=$((dep + bal))
          [[ "$tot" != "$ROW_EXPECTED_TOTAL" ]] && TOTAL_OK=false
        else
          TOTAL_OK=false
        fi
        i=$((i + 1))
      done
    fi
    if [[ "$TOTAL_OK" == true ]]; then
      check "every row's total_due equals deposit + balance" pass
    else
      check "every row's total_due equals deposit + balance" fail
    fi

    # 10. Own-words write-up: presence-checked for genuine content, same
    #     discipline as every other module's answers file (rejects the
    #     literal placeholder text copied verbatim from the module page,
    #     and rejects a symlink or hard link standing in for a real file).
    ANSWERS07="$ROOT/07-csv/answers.txt"
    ANSWERS07_LINK_COUNT="$(stat -f '%l' "$ANSWERS07" 2>/dev/null || stat -c '%h' "$ANSWERS07" 2>/dev/null || echo "1")"
    PLACEHOLDER_RULE07="<in your own words, what did the merge rule do whenever a booking ID showed up in both files?>"
    PLACEHOLDER_PAIRS07="<name at least one booking ID that appeared in both files, and say what happened to it>"
    PLACEHOLDER_LOST07="<how did you satisfy yourself that nobody's booking went missing?>"
    if [[ "$OUTPUT_DIR_OK" == false ]]; then
      check "07-csv/answers.txt has all three reflection answers, in your own words (07-csv/ is a symlink, not a real directory)" fail
    elif [[ -L "$ANSWERS07" ]]; then
      check "07-csv/answers.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS07" && "$ANSWERS07_LINK_COUNT" != "1" ]]; then
      check "07-csv/answers.txt has all three reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS07" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01's identical pattern, above.
      for label in "DEDUP_RULE:" "COLLAPSED_PAIRS:" "VERIFIED_NOTHING_LOST:"; do
        case "$label" in
          "DEDUP_RULE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_RULE07" ;;
          "COLLAPSED_PAIRS:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_PAIRS07" ;;
          "VERIFIED_NOTHING_LOST:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_LOST07" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS07" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "07-csv/answers.txt has all three reflection answers, in your own words" pass
      else
        check "07-csv/answers.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "07-csv/answers.txt has all three reflection answers, in your own words" fail
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
