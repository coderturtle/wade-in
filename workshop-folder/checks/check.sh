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
# Module 08's mapping CSV and bookings CSV get the same embedded-checksum
# treatment. Its 25 original photo fixtures get ONE aggregate checksum
# instead of 25 individual ones -- a single sha256 over `cat`'ing all 25
# files in sorted filename order (IMG_0001.jpg .. IMG_0025.jpg, which is
# also lexical order since the number is zero-padded to a fixed width).
# This still catches a tampered "original" fixture (the same class of bypass
# a per-file embedded checksum would catch) without hand-maintaining 25
# separate constants.
EXPECTED_PHOTO_MAPPING_SHA256="19c417a42d6c603c4f1ce9bc7ddd21065c23bbdf0121463228fa97113b480d54"
EXPECTED_PHOTOS_FIXTURE_SHA256="85335940951fb7685d44016bd4648a82652f680ef14c6fbcb44eafc2bb58ba53"
EXPECTED_BOOKINGS_SHA256="28e7e7f4a7c51441ad184bc590afe2b1b330b0781ce1ead3c988c46ce208799f"

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
  08)
    # Module 08 has two independent halves -- batch rename (Jack Crews's 25
    # delivery photos) and mail merge (Penny's 6 booking-confirmation
    # letters) -- both required. Every fixture involved is checksum-
    # protected, per docs/workshop-design.md §7's Module 08 row and this
    # script's own established hardening conventions above: never trust a
    # live fixture at check time, reject symlinks/hard links standing in for
    # required files or directories (at the leaf AND the parent), no
    # `declare -A` anywhere (bash 3.2 compatibility, see Module 01's comment
    # on this above).

    # --- Half 1: batch rename from a mapping fixture ----------------------

    # 1. The mapping fixture itself is checksum-protected. Without this, an
    #    edited mapping (e.g. quietly changing one row's expected new name)
    #    would make the checker "faithfully" verify a renamed set against a
    #    tampered expectation instead of the real one -- the same class of
    #    bypass Module 02's venue-history fixture check already guards
    #    against.
    MAPPING_CSV="$ROOT/fixtures/photo-mapping.csv"
    MAPPING_SUM="$(file_checksum "$MAPPING_CSV" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$MAPPING_SUM" == "$EXPECTED_PHOTO_MAPPING_SHA256" ]]; then
      check "fixtures/photo-mapping.csv matches its expected content" pass
      MAPPING_OK=true
    else
      check "fixtures/photo-mapping.csv matches its expected content (contact the workshop, not your own mistake)" fail
      MAPPING_OK=false
    fi

    # 2. The 25 original photo fixtures are checksum-protected too, as one
    #    aggregate hash over all 25 files concatenated in sorted filename
    #    order (see EXPECTED_PHOTOS_FIXTURE_SHA256's own comment, above).
    #    This closes a specific bypass: an agent that "fixes" the original
    #    fixture to match a wrong or corrupted renamed output would
    #    otherwise make the per-file comparison below "pass" against a
    #    tampered original instead of the real one.
    PHOTOS_FIXTURE_DIR="$ROOT/fixtures/photos"
    PHOTOS_FIXTURE_OK=false
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      check "fixtures/photos/ original 25 photos match their expected content (couldn't verify: no checksum tool found on this system - contact the workshop)" fail
    elif [[ -d "$PHOTOS_FIXTURE_DIR" ]]; then
      if command -v sha256sum >/dev/null 2>&1; then
        PHOTOS_AGG_SUM="$(cat "$PHOTOS_FIXTURE_DIR"/IMG_*.jpg 2>/dev/null | sha256sum | awk '{print $1}')"
      else
        PHOTOS_AGG_SUM="$(cat "$PHOTOS_FIXTURE_DIR"/IMG_*.jpg 2>/dev/null | shasum -a 256 | awk '{print $1}')"
      fi
      if [[ "$PHOTOS_AGG_SUM" == "$EXPECTED_PHOTOS_FIXTURE_SHA256" ]]; then
        check "fixtures/photos/ original 25 photos match their expected content" pass
        PHOTOS_FIXTURE_OK=true
      else
        check "fixtures/photos/ original 25 photos match their expected content (contact the workshop, not your own mistake)" fail
      fi
    else
      check "fixtures/photos/ original 25 photos match their expected content (contact the workshop, not your own mistake)" fail
    fi

    # 3. 08-auto/photos/ must be a real directory, not a symlink standing in
    #    for one -- same convention as Module 02's 02-meet/ check. Rejecting
    #    this at the directory level also covers a symlinked `08-auto`
    #    parent, since `cd`-ing through either level resolves physically.
    EXPECTED_PHOTOS_OUT="$ROOT/08-auto/photos"
    PHOTOS_OUT_OK=true
    if [[ -e "$EXPECTED_PHOTOS_OUT" ]]; then
      REAL_PHOTOS_OUT="$(cd "$EXPECTED_PHOTOS_OUT" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_PHOTOS_OUT" != "$EXPECTED_PHOTOS_OUT" ]]; then
        PHOTOS_OUT_OK=false
      fi
    fi

    # 4. Every one of the 25 mapped files: present under its new name in
    #    08-auto/photos/, not a symlink, not a hard link back to its
    #    original (same inode -- content matches, but `cp` never ran), and
    #    byte-identical to ITS OWN original fixture (derived fresh at check
    #    time from the pristine fixtures/photos/ -- not an embedded key for
    #    each file, per this module's own design: the mapping and the
    #    originals are what's checksum-pinned, above, so this per-file
    #    comparison is trustworthy without needing 25 more constants).
    RENAMED_TOTAL=0
    RENAMED_OK_COUNT=0
    if [[ "$MAPPING_OK" == true && "$PHOTOS_FIXTURE_OK" == true && "$PHOTOS_OUT_OK" == true ]]; then
      while IFS=',' read -r ORIG NEWNAME; do
        [[ "$ORIG" == "original_filename" ]] && continue
        [[ -z "$ORIG" ]] && continue
        RENAMED_TOTAL=$((RENAMED_TOTAL + 1))
        ORIG_PATH="$PHOTOS_FIXTURE_DIR/$ORIG"
        OUT_PATH="$EXPECTED_PHOTOS_OUT/$NEWNAME"
        if [[ -L "$OUT_PATH" ]]; then
          continue
        fi
        if [[ ! -f "$OUT_PATH" ]]; then
          continue
        fi
        OUT_INODE="$(file_inode "$OUT_PATH")"
        ORIG_INODE="$(file_inode "$ORIG_PATH")"
        if [[ "$OUT_INODE" != "NO_STAT_TOOL" && "$OUT_INODE" == "$ORIG_INODE" ]]; then
          continue
        fi
        OUT_SUM="$(file_checksum "$OUT_PATH")"
        ORIG_SUM="$(file_checksum "$ORIG_PATH")"
        if [[ "$OUT_SUM" == "$ORIG_SUM" ]]; then
          RENAMED_OK_COUNT=$((RENAMED_OK_COUNT + 1))
        fi
      done < "$MAPPING_CSV"
    fi

    if [[ "$PHOTOS_OUT_OK" == false ]]; then
      check "all 25 photos renamed into 08-auto/photos/, correctly named and byte-identical to their originals (08-auto/photos/ is a symlink, not a real directory)" fail
    elif [[ "$MAPPING_OK" != true ]]; then
      check "all 25 photos renamed into 08-auto/photos/, correctly named and byte-identical to their originals (couldn't verify: fixtures/photo-mapping.csv doesn't match its expected content)" fail
    elif [[ "$PHOTOS_FIXTURE_OK" != true ]]; then
      check "all 25 photos renamed into 08-auto/photos/, correctly named and byte-identical to their originals (couldn't verify: original fixtures/photos/ doesn't match its expected content)" fail
    elif [[ "$RENAMED_TOTAL" -eq 25 && "$RENAMED_OK_COUNT" -eq 25 ]]; then
      check "all 25 photos renamed into 08-auto/photos/, correctly named and byte-identical to their originals" pass
    else
      check "all 25 photos renamed into 08-auto/photos/, correctly named and byte-identical to their originals (found $RENAMED_OK_COUNT/25 correct)" fail
    fi

    # 5. No extras: every expected renamed file was already individually
    #    verified above, so if the TOTAL number of entries actually sitting
    #    in 08-auto/photos/ also equals 25, that rules out any additional
    #    file (or directory, or stray symlink) the mapping doesn't account
    #    for -- a bash-3.2-safe equivalent of a full closed-set comparison,
    #    with no associative arrays anywhere.
    if [[ "$PHOTOS_OUT_OK" == false ]]; then
      check "08-auto/photos/ contains exactly the 25 expected files, no extras (08-auto/photos/ is a symlink, not a real directory)" fail
    else
      ACTUAL_PHOTO_COUNT="$(find "$EXPECTED_PHOTOS_OUT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$ACTUAL_PHOTO_COUNT" -eq 25 ]]; then
        check "08-auto/photos/ contains exactly the 25 expected files, no extras" pass
      else
        check "08-auto/photos/ contains exactly the 25 expected files, no extras (found $ACTUAL_PHOTO_COUNT)" fail
      fi
    fi

    # --- Half 2: mail merge from a CSV fixture -----------------------------

    # 6. The bookings fixture is checksum-protected, same reasoning as the
    #    mapping fixture above.
    BOOKINGS_CSV="$ROOT/fixtures/bookings-for-letters.csv"
    BOOKINGS_SUM="$(file_checksum "$BOOKINGS_CSV" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$BOOKINGS_SUM" == "$EXPECTED_BOOKINGS_SHA256" ]]; then
      check "fixtures/bookings-for-letters.csv matches its expected content" pass
      BOOKINGS_OK=true
    else
      check "fixtures/bookings-for-letters.csv matches its expected content (contact the workshop, not your own mistake)" fail
      BOOKINGS_OK=false
    fi

    # 08-auto/letters/ must be a real directory, not a symlink (same
    # convention as 08-auto/photos/, above).
    EXPECTED_LETTERS_OUT="$ROOT/08-auto/letters"
    LETTERS_OUT_OK=true
    if [[ -e "$EXPECTED_LETTERS_OUT" ]]; then
      REAL_LETTERS_OUT="$(cd "$EXPECTED_LETTERS_OUT" 2>/dev/null && pwd -P || echo "")"
      if [[ "$REAL_LETTERS_OUT" != "$EXPECTED_LETTERS_OUT" ]]; then
        LETTERS_OUT_OK=false
      fi
    fi

    # Enumerate the letters actually sitting in 08-auto/letters/: real files
    # only, rejecting a symlink or a hard link standing in for one (link
    # count above 1), same convention as every earlier check in this script.
    LETTER_FILES=()
    LETTERS_TOTAL_ENTRIES=0
    if [[ "$LETTERS_OUT_OK" == true ]]; then
      LETTERS_TOTAL_ENTRIES="$(find "$EXPECTED_LETTERS_OUT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
      while IFS= read -r -d '' entry; do
        if [[ -L "$entry" ]]; then
          continue
        fi
        if [[ -f "$entry" ]]; then
          LINK_COUNT="$(stat -f '%l' "$entry" 2>/dev/null || stat -c '%h' "$entry" 2>/dev/null || echo "1")"
          if [[ "$LINK_COUNT" == "1" ]]; then
            LETTER_FILES+=("$entry")
          fi
        fi
      done < <(find "$EXPECTED_LETTERS_OUT" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    fi

    # 7. Exactly 6 real, usable letter files -- no extras, no symlinks or
    #    hard links standing in for one.
    if [[ "$LETTERS_OUT_OK" == false ]]; then
      check "08-auto/letters/ contains exactly 6 real letter files, no extras, no symlinks or hard links (08-auto/letters/ is a symlink, not a real directory)" fail
    elif [[ "$LETTERS_TOTAL_ENTRIES" -eq 6 && "${#LETTER_FILES[@]}" -eq 6 ]]; then
      check "08-auto/letters/ contains exactly 6 real letter files, no extras, no symlinks or hard links" pass
    else
      check "08-auto/letters/ contains exactly 6 real letter files, no extras, no symlinks or hard links (found $LETTERS_TOTAL_ENTRIES entries, ${#LETTER_FILES[@]} usable)" fail
    fi

    # 8. Every one of the 6 booking rows is matched to its own, distinct
    #    letter file -- containing that row's exact name and event date
    #    (fixed-string match) and its exact amount (extracted as a numeric
    #    token and matched exactly, same technique as Module 02's founding-
    #    year/capacity check, so "515.00" can't be falsely satisfied by a
    #    letter that actually says "1515.00" or "515.005"). Matching is
    #    greedy but exclusive (CLAIMED tracks which file has already been
    #    used) -- a single file crammed with all 6 rows' data can satisfy at
    #    most one row, not all six, since a claimed file is removed from
    #    consideration for the rest.
    ROW_TOTAL=0
    ROW_MATCH_OK=0
    if [[ "$BOOKINGS_OK" == true && "$LETTERS_OUT_OK" == true && "${#LETTER_FILES[@]}" -gt 0 ]]; then
      CLAIMED=()
      for ((i = 0; i < ${#LETTER_FILES[@]}; i++)); do
        CLAIMED[i]=0
      done
      while IFS=',' read -r NAME EVENT_DATE AMOUNT; do
        [[ "$NAME" == "name" ]] && continue
        [[ -z "$NAME" ]] && continue
        ROW_TOTAL=$((ROW_TOTAL + 1))
        FOUND=false
        for ((i = 0; i < ${#LETTER_FILES[@]}; i++)); do
          [[ "${CLAIMED[i]}" == "1" ]] && continue
          CANDIDATE="${LETTER_FILES[i]}"
          if grep -qF -- "$NAME" "$CANDIDATE" 2>/dev/null \
            && grep -qF -- "$EVENT_DATE" "$CANDIDATE" 2>/dev/null \
            && grep -oE -- '-?[0-9]+(\.[0-9]+)?' "$CANDIDATE" 2>/dev/null | grep -qxF -- "$AMOUNT"; then
            CLAIMED[i]=1
            FOUND=true
            break
          fi
        done
        [[ "$FOUND" == true ]] && ROW_MATCH_OK=$((ROW_MATCH_OK + 1))
      done < "$BOOKINGS_CSV"
    fi

    if [[ "$BOOKINGS_OK" != true ]]; then
      check "all 6 letters contain their row's exact name, event date, and amount from the CSV (couldn't verify: fixtures/bookings-for-letters.csv doesn't match its expected content)" fail
    elif [[ "$LETTERS_OUT_OK" == false ]]; then
      check "all 6 letters contain their row's exact name, event date, and amount from the CSV (08-auto/letters/ is a symlink, not a real directory)" fail
    elif [[ "$ROW_TOTAL" -eq 6 && "$ROW_MATCH_OK" -eq 6 ]]; then
      check "all 6 letters contain their row's exact name, event date, and amount from the CSV" pass
    else
      check "all 6 letters contain their row's exact name, event date, and amount from the CSV (matched $ROW_MATCH_OK/6)" fail
    fi

    # 9. Zero unexpanded template placeholders across every letter -- a
    #    literal count of the substring "{{" across all the real letter
    #    files found above. Any leftover "{{name}}"-shaped placeholder means
    #    the merge didn't actually run for that row.
    if [[ "$LETTERS_OUT_OK" == false ]]; then
      check "zero unfilled template placeholders across the letters (08-auto/letters/ is a symlink, not a real directory)" fail
    elif [[ "${#LETTER_FILES[@]}" -eq 0 ]]; then
      check "zero unfilled template placeholders across the letters (no letter files found to check)" fail
    else
      PLACEHOLDER_COUNT=0
      for CANDIDATE in "${LETTER_FILES[@]}"; do
        C="$(grep -o '{{' "$CANDIDATE" 2>/dev/null | wc -l | tr -d ' ')"
        PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + C))
      done
      if [[ "$PLACEHOLDER_COUNT" -eq 0 ]]; then
        check "zero unfilled template placeholders across the letters (no literal {{ left)" pass
      else
        check "zero unfilled template placeholders across the letters (found $PLACEHOLDER_COUNT occurrences of {{)" fail
      fi
    fi

    # 10. Own-words write-up: same discipline as Modules 01 and 02 -- presence-
    #    checked for genuine content, rejecting the literal placeholder text
    #    from the module page itself, and rejecting a symlink or hard link
    #    standing in for a real file.
    ANSWERS08="$ROOT/08-auto/answers.txt"
    ANSWERS08_LINK_COUNT="$(stat -f '%l' "$ANSWERS08" 2>/dev/null || stat -c '%h' "$ANSWERS08" 2>/dev/null || echo "1")"
    PLACEHOLDER_REUSABLE08="<could this same template-and-mapping approach run again next month with new inputs? What would have to change, and what would stay the same?>"
    PLACEHOLDER_FIRST_CHANGE08="<the first thing you'd change about how you asked for this job, if you ran it again>"
    if [[ -L "$ANSWERS08" ]]; then
      check "08-auto/answers.txt has both reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$ANSWERS08" && "$ANSWERS08_LINK_COUNT" != "1" ]]; then
      check "08-auto/answers.txt has both reflection answers, in your own words (found a hard link, not an independently-written file)" fail
    elif [[ -f "$ANSWERS08" ]]; then
      MISSING_LABELS=()
      # Bash-3.2-safe case statement, not an associative array -- see the
      # matching comment on Module 01's identical pattern, above, for why.
      for label in "REUSABLE:" "FIRST_CHANGE:"; do
        case "$label" in
          "REUSABLE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_REUSABLE08" ;;
          "FIRST_CHANGE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_FIRST_CHANGE08" ;;
        esac
        LINE="$(grep -m1 "^$label" "$ANSWERS08" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "08-auto/answers.txt has both reflection answers, in your own words" pass
      else
        check "08-auto/answers.txt has both reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "08-auto/answers.txt has both reflection answers, in your own words" fail
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
