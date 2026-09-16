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
  # Module 10 reuses this helper for its own guest-list merge artifact.
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

array_index_of() {
  # Bash-3.2-safe lookup: given a target value and a haystack passed as
  # remaining args, print the matching index or "-1". This, plus a plain
  # indexed array, is this script's stand-in for an associative array's key
  # lookup -- `declare -A` is never used anywhere in this script (stock
  # macOS bash 3.2 has no associative arrays at all and crashes hard on
  # one, confirmed and fixed repeatedly across every module tonight).
  #
  # Caller responsibility: expanding "${arr[@]}" for a genuinely
  # zero-length array under this script's `set -u` trips a real bash bug
  # present in versions before 4.4 ("unbound variable" on an empty array
  # even though it was explicitly initialized with `arr=()`) -- stock bash
  # 3.2 has this bug. Every call site guards with `[[ "${#arr[@]}" -gt 0 ]]`
  # before expanding an array into this function's arguments.
  # Module 10 reuses this helper for its own guest-list merge artifact.
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
EXPECTED_STANDIN_NOTE_SHA256="3d322629bbf07b27385c321bbc9e7a5a01945555676d2f9a72d4393ff5676712"
EXPECTED_STANDIN_PACKING_SHA256="f1834bcffc2c2eb9c4ec5b37de0aba444f417560b2c0f0d45182cb74b78c5c81"
EXPECTED_STANDIN_RECIPE_SHA256="13c259fb430dbee8c8a58f53db27fb3e81f7712000e11ae77b0a067f360bd413"

# Module 10 (the capstone) fixture checksums. The 20 pristine press photos
# get one aggregate checksum (cat'd in sorted filename order, zero-padded so
# lexical order matches numeric order) rather than 20 individual constants,
# same technique Module 08 already uses for its own 25 photos.
declare -a EXPECTED_CREW_HOURS_DATES=(2026-09-08 2026-09-09 2026-09-10 2026-09-11 2026-09-12 2026-09-13 2026-09-14 2026-09-15)
crew_hours_expected_sha256() {
  case "$1" in
    2026-09-08) echo "58db41183ba5664edf995e3227e9d472a0f15ad3fcfaa422d4ced1ad3d52d9fe" ;;
    2026-09-09) echo "dda6df253d5bb4611e6b302e18c7e321b323c48d862b4abb38fed2cc4d2cf52c" ;;
    2026-09-10) echo "a3bcf0735bd87d0db9a0b8c3c0c5c891fda69c4e07b3f377ede277cea31a50ea" ;;
    2026-09-11) echo "8ebd3c84bad67a24d3170928ccd22de02b2f81ffd60d5d5c4e799abc468ca37f" ;;
    2026-09-12) echo "0180466fa822f567afd0d94d9cad9556ac177f02202e4260742196545332f0b6" ;;
    2026-09-13) echo "f58abeb8bc6a82dcbc265929fa7c563b98b7fea792026294cec8e36a98957076" ;;
    2026-09-14) echo "5df4d1d2cda4f0ae396f2a040c974ad5dfad60bd2a5e449486e5a710b61c6507" ;;
    2026-09-15) echo "fcbf13ac442c41e6494d4f225ab7304ab34de6c82aefa6f999b98dc386c74a6b" ;;
    *) echo "" ;;
  esac
}
EXPECTED_OPENING_NIGHT_FIGURES_SHA256="908c7f3f8eaa510bb7a47b22dd825e19718440d0013574c4e4f52a7b04fadfda"
EXPECTED_PENNY_GUEST_LIST_SHA256="cf36c74f98c4c4f07524bad48a14daf5893414511b954d44d537ab9808ada681"
EXPECTED_TILGHMAN_GUEST_DRAFT_SHA256="43ea496e872fdabe71b10233c00c1739496aa3a27332a8d108582c85a1a80470"
EXPECTED_PRESS_PHOTO_MAPPING_SHA256="445691e5c2f886eafd54460e4e763fc56ea1c9f6d18913e64ec03c2a7e2832d2"
EXPECTED_PRESS_PHOTOS_AGG_SHA256="98d8ffb97af18290d673c36ba1f2d85c98bc7596a928db978b7150c2e6157a60"
EXPECTED_VIP_CONFIRMATIONS_SHA256="86b330903692c522af546bbed0ccd09f841523dacc66e9f1ccad4b1cf0189b2d"

# --- Module 09 helper functions --------------------------------------------
# Module 09 (Off the Clock) is the one module whose graded artifacts live in
# TWO places: this workshop folder's own 09-real-work/ (the checker's
# bookkeeping -- manifests, the quiz answer, the safety plan) and a real
# folder OUTSIDE the workshop folder entirely, at $HOME/wade-in-real-folder
# (the learner's own real-or-stand-in files and their backup). Both halves
# get real, hardened checks below -- never a display of any file's content.

# real_folder_path: the one fixed, documented location for the learner's
# real-or-stand-in folder. A fixed convention (not a learner-supplied path)
# keeps this checkable without ever asking the learner to type a path into
# an answers file that this script would then have to trust unverified.
real_folder_path() {
  printf '%s/wade-in-real-folder' "${HOME:-$ROOT}"
}

# parse_manifest_names FILE [BASE_DIR]: prints one candidate filename per
# line, trimmed, skipping blank lines, the backup/ folder itself (routinely
# shows up in a plain `ls` of the real folder, since the taught ritual order
# is copy in -> back up -> manifest), and dotfiles (OS-noise like
# .DS_Store, not something the learner deliberately copied in).
# BASE_DIR, if given, makes the "backup" exclusion precise: only a real
# DIRECTORY named "backup" is skipped, not a plain file that happens to be
# named "backup" with no extension -- found by a fresh-context adversarial
# pass, a real file literally named "backup" was silently dropped from
# every manifest with no warning under the earlier, name-only version of
# this filter. When BASE_DIR isn't given, falls back to the old name-only
# behavior (used at the one call site that doesn't have a real folder to
# check against yet).
parse_manifest_names() {
  local manifest_file="$1"
  local base_dir="${2:-}"
  [[ -f "$manifest_file" ]] || return 0
  local line trimmed
  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$trimmed" ]] && continue
    if [[ "$trimmed" == "backup" ]]; then
      if [[ -n "$base_dir" ]]; then
        [[ -d "$base_dir/backup" ]] && continue
      else
        continue
      fi
    fi
    case "$trimmed" in
      .*) continue ;;
    esac
    printf '%s\n' "$trimmed"
  done < "$manifest_file"
}

# pin_get TAG PINFILE: reads a single tagged value (tab-separated) out of the
# checker's own state file. A case statement elsewhere in this script already
# explains why this file never uses `declare -A` -- this is the same
# discipline: a flat, tab-separated, grep/awk-readable file instead.
pin_get() {
  local tag="$1" pinfile="$2"
  [[ -f "$pinfile" ]] || return 0
  awk -F'\t' -v t="$tag" '$1==t{v=$2} END{if (v!="") print v}' "$pinfile" 2>/dev/null
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
  09)
    # Module 09 (Off the Clock) is the first and only module that leaves the
    # workshop sandbox. Its artifacts live in two places: this workshop
    # folder's own 09-real-work/ (the checker's bookkeeping - manifests, the
    # safety quiz answer, the safety plan) and a real folder OUTSIDE the
    # workshop folder entirely, at $HOME/wade-in-real-folder (the learner's
    # own real-or-stand-in files and their backup). Hard privacy rule,
    # audited directly, not just intended: this case block computes
    # checksums (which necessarily read file bytes) but never prints,
    # extracts, or otherwise displays any file's actual content anywhere -
    # every message below names files, checksums, and counts only.
    STATE_DIR="$ROOT/09-real-work"
    # An unset/empty $HOME falls back to $ROOT inside real_folder_path(),
    # which used to fail silently downstream with a misleading "still
    # inside the workshop folder" message -- found by a fresh-context
    # adversarial pass, that message misdiagnoses the actual problem (a
    # missing $HOME in the learner's shell) as a folder-placement mistake.
    # Name the real cause directly instead, at the one check that would
    # otherwise report it wrong.
    HOME_UNSET=false
    [[ -z "${HOME:-}" ]] && HOME_UNSET=true
    REAL_FOLDER="$(real_folder_path)"
    REAL_BACKUP="$REAL_FOLDER/backup"
    BEFORE_MANIFEST="$STATE_DIR/before-manifest.txt"
    AFTER_MANIFEST="$STATE_DIR/after-manifest.txt"
    QUIZ_FILE="$STATE_DIR/safety-quiz-answers.txt"
    PLAN_FILE="$STATE_DIR/safety-plan.txt"
    PIN_FILE="$STATE_DIR/.checker-state"

    # 1. Workshop-provided stand-in fixtures are present and intact - same
    #    fixture-integrity discipline as Modules 01/02's own fixtures, so a
    #    corrupted download is diagnosed as a workshop problem, not a
    #    learner mistake. Runs regardless of whether the learner actually
    #    used the stand-ins or their own real files - this verifies the
    #    DOWNLOAD, not the learner's choice.
    STANDIN_DIR="$ROOT/fixtures/stand-in-files"
    STANDIN_OK=true
    STANDIN_PROBLEM=""
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      STANDIN_OK=false
      STANDIN_PROBLEM="no checksum tool found on this system - contact the workshop"
    else
      for pair in "note-to-self.txt:$EXPECTED_STANDIN_NOTE_SHA256" \
                  "weekend-packing-list.txt:$EXPECTED_STANDIN_PACKING_SHA256" \
                  "recipe-notes.txt:$EXPECTED_STANDIN_RECIPE_SHA256"; do
        sname="${pair%%:*}"
        sexpected="${pair##*:}"
        spath="$STANDIN_DIR/$sname"
        if [[ -L "$spath" || ! -f "$spath" ]]; then
          STANDIN_OK=false
          STANDIN_PROBLEM="$sname is missing (contact the workshop)"
          continue
        fi
        ssum="$(file_checksum "$spath" 2>/dev/null || echo "")"
        if [[ "$ssum" != "$sexpected" ]]; then
          STANDIN_OK=false
          STANDIN_PROBLEM="$sname doesn't match its expected content (contact the workshop, not your own mistake)"
        fi
      done
    fi
    if [[ "$STANDIN_OK" == true ]]; then
      check "workshop stand-in files are present and intact" pass
    else
      check "workshop stand-in files are present and intact ($STANDIN_PROBLEM)" fail
    fi

    # 2. The real-or-stand-in folder exists, is a REAL directory (not a
    #    symlink), and is genuinely outside this workshop folder - not just
    #    a differently-named folder still living inside it, and not a
    #    symlink pointing back in. This is the one module where "outside the
    #    sandbox" is the whole point; a folder that only looks outside would
    #    quietly defeat the entire exercise.
    REAL_FOLDER_OK=true
    REAL_FOLDER_PROBLEM=""
    if [[ "$HOME_UNSET" == true ]]; then
      REAL_FOLDER_OK=false
      REAL_FOLDER_PROBLEM="your \$HOME environment variable isn't set, so this can't be checked - contact the workshop"
    elif [[ -L "$REAL_FOLDER" ]]; then
      REAL_FOLDER_OK=false
      REAL_FOLDER_PROBLEM="found a symlink at $REAL_FOLDER, not a real folder - use mkdir, not ln -s"
    elif [[ ! -d "$REAL_FOLDER" ]]; then
      REAL_FOLDER_OK=false
      REAL_FOLDER_PROBLEM="no folder found at $REAL_FOLDER yet"
    else
      REAL_FOLDER_RESOLVED="$(cd "$REAL_FOLDER" 2>/dev/null && pwd -P || echo "")"
      if [[ -z "$REAL_FOLDER_RESOLVED" ]]; then
        REAL_FOLDER_OK=false
        REAL_FOLDER_PROBLEM="couldn't resolve $REAL_FOLDER"
      elif [[ "$REAL_FOLDER_RESOLVED" == "$ROOT" || "$REAL_FOLDER_RESOLVED" == "$ROOT"/* ]]; then
        REAL_FOLDER_OK=false
        REAL_FOLDER_PROBLEM="this folder is still inside the workshop folder - it needs to be outside it"
      fi
    fi
    if [[ "$REAL_FOLDER_OK" == true ]]; then
      check "a real folder exists outside the workshop folder, at $REAL_FOLDER" pass
    else
      check "a real folder exists outside the workshop folder, at $REAL_FOLDER ($REAL_FOLDER_PROBLEM)" fail
    fi

    # Everything below depends on being able to compute checksums at all.
    # Guard it as one block: with no checksum tool, computing "NO_CHECKSUM_TOOL"
    # on both sides of a comparison would otherwise silently "match" and
    # produce a false PASS - the exact bypass Module 01's own checksum-tool
    # guard was built to avoid, reproduced here for the same reason.
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      check "before-manifest.txt exists, lists real files, and is timestamped by the checker (no checksum tool found on this system - contact the workshop)" fail
      check "after-manifest.txt exists, is non-empty, and is timestamped by the checker (no checksum tool found on this system - contact the workshop)" fail
      check "before-manifest.txt was recorded before after-manifest.txt (no checksum tool found on this system - contact the workshop)" fail
      check "backup/ exists and contains exactly the files listed in your before-manifest (no checksum tool found on this system - contact the workshop)" fail
      check "every file in backup/ is byte-identical to the original (checked by checksum, recorded when before-manifest.txt was first pinned) (no checksum tool found on this system - contact the workshop)" fail
      BEFORE_OK=false
    else

    # 3. before-manifest.txt: read, and pin the checker's own record of it
    #    the first time this exact content is seen. Pinning captures BOTH a
    #    timestamp (this script's own wall clock, never trusted from file
    #    mtimes or anything the learner could set by hand) AND a sha256 of
    #    every real file the manifest names, at that moment - the "originals'
    #    checksums recorded at backup time" the backup/ check below verifies
    #    against. If the manifest's content ever changes (a legitimate redo),
    #    the OLD pin - including any after-manifest stamp - is discarded and
    #    replaced, since a changed "before" invalidates whatever "after" was
    #    compared against it.
    BEFORE_OK=false
    BEFORE_PROBLEM="before-manifest.txt not found yet"
    if [[ -L "$BEFORE_MANIFEST" ]]; then
      BEFORE_PROBLEM="found a symlink, not a real file - use a real redirect (ls ... > before-manifest.txt)"
    elif [[ -f "$BEFORE_MANIFEST" && -s "$BEFORE_MANIFEST" ]]; then
      BEFORE_HASH_NOW="$(file_checksum "$BEFORE_MANIFEST" 2>/dev/null || echo "")"
      STORED_BEFORE_HASH="$(pin_get "BEFORE_STAMP_HASH" "$PIN_FILE")"
      if [[ -n "$BEFORE_HASH_NOW" && "$BEFORE_HASH_NOW" == "$STORED_BEFORE_HASH" ]]; then
        # Already pinned for this exact content - nothing to redo.
        BEFORE_OK=true
      else
        NAMES="$(parse_manifest_names "$BEFORE_MANIFEST" "$REAL_FOLDER")"
        if [[ -z "$NAMES" ]]; then
          BEFORE_PROBLEM="before-manifest.txt doesn't list any real files - run it (ls $REAL_FOLDER > ...) after copying files in"
        elif [[ "$REAL_FOLDER_OK" != true ]]; then
          BEFORE_PROBLEM="can't verify the files it lists until the real folder itself exists"
        else
          PIN_ALL_OK=true
          PIN_BAD_NAME=""
          ORIGINAL_LINES=""
          while IFS= read -r nm; do
            [[ -z "$nm" ]] && continue
            fpath="$REAL_FOLDER/$nm"
            if [[ -L "$fpath" ]]; then
              PIN_ALL_OK=false; PIN_BAD_NAME="$nm (a symlink, not a real file)"; continue
            fi
            if [[ ! -f "$fpath" ]]; then
              PIN_ALL_OK=false; PIN_BAD_NAME="$nm (not found in your real folder)"; continue
            fi
            nm_sum="$(file_checksum "$fpath" 2>/dev/null || echo "")"
            ORIGINAL_LINES="${ORIGINAL_LINES}ORIGINAL"$'\t'"${nm}"$'\t'"${nm_sum}"$'\n'
          done <<< "$NAMES"
          if [[ "$PIN_ALL_OK" == true ]]; then
            NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
            {
              printf 'BEFORE_STAMP_HASH\t%s\n' "$BEFORE_HASH_NOW"
              printf 'BEFORE_STAMP_EPOCH\t%s\n' "$NOW_EPOCH"
              printf '%s' "$ORIGINAL_LINES"
            } > "$PIN_FILE" 2>/dev/null
            BEFORE_OK=true
          else
            BEFORE_PROBLEM="before-manifest.txt lists $PIN_BAD_NAME"
          fi
        fi
      fi
    elif [[ -f "$BEFORE_MANIFEST" ]]; then
      BEFORE_PROBLEM="before-manifest.txt exists but is empty"
    fi
    if [[ "$BEFORE_OK" == true ]]; then
      check "before-manifest.txt exists, lists real files, and is timestamped by the checker" pass
    else
      check "before-manifest.txt exists, lists real files, and is timestamped by the checker ($BEFORE_PROBLEM)" fail
    fi

    # 4. after-manifest.txt: same non-empty/symlink checks, then its own
    #    independent checker-written stamp - but only once a valid
    #    before-manifest is already pinned. That ordering requirement is
    #    structural, not just a timestamp comparison: this script never
    #    stamps an after-manifest until a before-manifest has already been
    #    stamped, so "before" being chronologically before "after" is
    #    guaranteed by construction, not merely asserted by comparing two
    #    numbers a learner could otherwise have influenced.
    AFTER_OK=false
    AFTER_PROBLEM="after-manifest.txt not found yet"
    BEFORE_PINNED_HASH="$(pin_get "BEFORE_STAMP_HASH" "$PIN_FILE")"
    if [[ -L "$AFTER_MANIFEST" ]]; then
      AFTER_PROBLEM="found a symlink, not a real file - use a real redirect (ls ... > after-manifest.txt)"
    elif [[ -f "$AFTER_MANIFEST" && -s "$AFTER_MANIFEST" ]]; then
      if [[ -z "$BEFORE_PINNED_HASH" ]]; then
        AFTER_PROBLEM="waiting on a valid before-manifest.txt first (see above)"
      else
        AFTER_HASH_NOW="$(file_checksum "$AFTER_MANIFEST" 2>/dev/null || echo "")"
        STORED_AFTER_HASH="$(pin_get "AFTER_STAMP_HASH" "$PIN_FILE")"
        if [[ -n "$AFTER_HASH_NOW" && "$AFTER_HASH_NOW" == "$STORED_AFTER_HASH" ]]; then
          AFTER_OK=true
        else
          NOW_EPOCH2="$(date +%s 2>/dev/null || echo 0)"
          TMP_PIN="${PIN_FILE}.tmp$$"
          grep -v -e $'^AFTER_STAMP_HASH\t' -e $'^AFTER_STAMP_EPOCH\t' "$PIN_FILE" > "$TMP_PIN" 2>/dev/null
          {
            cat "$TMP_PIN" 2>/dev/null
            printf 'AFTER_STAMP_HASH\t%s\n' "$AFTER_HASH_NOW"
            printf 'AFTER_STAMP_EPOCH\t%s\n' "$NOW_EPOCH2"
          } > "$PIN_FILE" 2>/dev/null
          rm -f "$TMP_PIN" 2>/dev/null
          AFTER_OK=true
        fi
      fi
    elif [[ -f "$AFTER_MANIFEST" ]]; then
      AFTER_PROBLEM="after-manifest.txt exists but is empty"
    fi
    if [[ "$AFTER_OK" == true ]]; then
      check "after-manifest.txt exists, is non-empty, and is timestamped by the checker" pass
    else
      check "after-manifest.txt exists, is non-empty, and is timestamped by the checker ($AFTER_PROBLEM)" fail
    fi

    # 4b. At least one genuinely new file exists in the real folder, present
    #    in after-manifest.txt but not in before-manifest.txt -- real,
    #    non-empty evidence that Part 5's directed task actually produced
    #    something, not just that two manifests exist and are in order.
    #    Found by a fresh-context adversarial pass: without this check,
    #    `ls` run twice back to back with no Claude Code session ever
    #    launched -- no new file, no permission prompt, nothing -- produced
    #    a full RESULT: PASS (9/9). This module's entire reason to exist is
    #    the directed real-file task; this check is what actually requires
    #    it happened, even though it still can't prove Claude Code (rather
    #    than the learner by hand) produced the new file's content -- the
    #    same provenance limit every module's checks already carry.
    NEW_FILE_OK=false
    NEW_FILE_PROBLEM="can't check for new work until both manifests are properly recorded (see above)"
    if [[ "$BEFORE_OK" == true && "$AFTER_OK" == true && "$REAL_FOLDER_OK" == true ]]; then
      BEFORE_NAMES="$(parse_manifest_names "$BEFORE_MANIFEST" "$REAL_FOLDER")"
      AFTER_NAMES="$(parse_manifest_names "$AFTER_MANIFEST" "$REAL_FOLDER")"
      NEW_FILE_PROBLEM="after-manifest.txt lists no file that wasn't already in before-manifest.txt - do Part 5's task for real, then re-run ls"
      while IFS= read -r nm; do
        [[ -z "$nm" ]] && continue
        if ! printf '%s\n' "$BEFORE_NAMES" | grep -Fxq "$nm"; then
          npath="$REAL_FOLDER/$nm"
          if [[ -L "$npath" ]]; then
            NEW_FILE_PROBLEM="$nm is new but is a symlink, not a real file"
            continue
          fi
          if [[ -f "$npath" && -s "$npath" ]]; then
            NEW_FILE_OK=true
            NEW_FILE_PROBLEM=""
            break
          fi
        fi
      done <<< "$AFTER_NAMES"
    fi
    if [[ "$NEW_FILE_OK" == true ]]; then
      check "at least one new, non-empty file exists from Part 5's directed task" pass
    else
      check "at least one new, non-empty file exists from Part 5's directed task ($NEW_FILE_PROBLEM)" fail
    fi

    # 5. Chronological order: before-manifest's stamp must be no later than
    #    after-manifest's stamp. `date +%s` is second-resolution (the most
    #    this script can portably rely on across macOS and Linux without a
    #    nanosecond-capable `date` everywhere), so this compares with <=, not
    #    strict <, to avoid a false FAIL on two stamps written within the
    #    same second. The real ordering guarantee is the structural one
    #    above (after can never be stamped before before is) - this
    #    comparison is defense in depth on top of it, not the only thing
    #    standing between a learner and a fabricated order.
    BEFORE_EPOCH="$(pin_get "BEFORE_STAMP_EPOCH" "$PIN_FILE")"
    AFTER_EPOCH="$(pin_get "AFTER_STAMP_EPOCH" "$PIN_FILE")"
    if [[ "$BEFORE_OK" == true && "$AFTER_OK" == true && -n "$BEFORE_EPOCH" && -n "$AFTER_EPOCH" && "$BEFORE_EPOCH" -le "$AFTER_EPOCH" ]]; then
      check "before-manifest.txt was recorded before after-manifest.txt" pass
    else
      check "before-manifest.txt was recorded before after-manifest.txt" fail
    fi

    # 6 & 7. backup/: filenames must match the pre-run (before-)manifest, AND
    #    each backed-up file's checksum must match the original's checksum as
    #    recorded when before-manifest was first pinned. Filename match alone
    #    would pass an empty or corrupted backup as long as it had the right
    #    names sitting in it with wrong (or no) bytes - the checksum pass is
    #    what actually catches that.
    BACKUP_NAMES_OK=false
    BACKUP_NAMES_PROBLEM="can't check backup/ until before-manifest.txt is properly pinned (see above)"
    PINNED_NAMES=""
    if [[ "$BEFORE_OK" == true ]]; then
      PINNED_NAMES="$(awk -F'\t' '$1=="ORIGINAL"{print $2}' "$PIN_FILE" 2>/dev/null)"
      if [[ -L "$REAL_BACKUP" ]]; then
        BACKUP_NAMES_PROBLEM="found a symlink at backup/, not a real folder - use mkdir, not ln -s"
      elif [[ ! -d "$REAL_BACKUP" ]]; then
        BACKUP_NAMES_PROBLEM="no backup/ folder found yet at $REAL_BACKUP"
      else
        BACKUP_ACTUAL_NAMES="$(find "$REAL_BACKUP" -maxdepth 1 -type f ! -name '.*' -exec basename {} \; 2>/dev/null | sort)"
        PINNED_NAMES_SORTED="$(printf '%s\n' "$PINNED_NAMES" | sort)"
        if [[ "$BACKUP_ACTUAL_NAMES" == "$PINNED_NAMES_SORTED" ]]; then
          BACKUP_NAMES_OK=true
        else
          BACKUP_NAMES_PROBLEM="backup/ doesn't contain exactly the files your before-manifest lists (missing, extra, renamed, or symlinked files)"
        fi
      fi
    fi
    if [[ "$BACKUP_NAMES_OK" == true ]]; then
      check "backup/ exists and contains exactly the files listed in your before-manifest" pass
    else
      check "backup/ exists and contains exactly the files listed in your before-manifest ($BACKUP_NAMES_PROBLEM)" fail
    fi

    BACKUP_SUMS_OK=false
    BACKUP_SUMS_PROBLEM="can't verify backup checksums until the check above passes"
    if [[ "$BACKUP_NAMES_OK" == true ]]; then
      BACKUP_SUMS_OK=true
      BACKUP_SUMS_PROBLEM=""
      while IFS=$'\t' read -r tag bname bsum; do
        [[ "$tag" == "ORIGINAL" ]] || continue
        bfile="$REAL_BACKUP/$bname"
        ofile="$REAL_FOLDER/$bname"
        if [[ -L "$bfile" ]]; then
          BACKUP_SUMS_OK=false; BACKUP_SUMS_PROBLEM="$bname in backup/ is a symlink, not a real copy"; continue
        fi
        b_inode="$(file_inode "$bfile")"
        o_inode="$(file_inode "$ofile")"
        if [[ "$b_inode" != "NO_STAT_TOOL" && "$b_inode" == "$o_inode" ]]; then
          BACKUP_SUMS_OK=false; BACKUP_SUMS_PROBLEM="$bname in backup/ is a hard link to the original, not an independent copy"; continue
        fi
        actual_sum="$(file_checksum "$bfile" 2>/dev/null || echo "")"
        if [[ -z "$actual_sum" || "$actual_sum" != "$bsum" ]]; then
          BACKUP_SUMS_OK=false; BACKUP_SUMS_PROBLEM="$bname in backup/ doesn't match the original's checksum (empty or corrupted backup)"
        fi
      done < "$PIN_FILE"
    fi
    if [[ "$BACKUP_SUMS_OK" == true ]]; then
      check "every file in backup/ is byte-identical to the original (checked by checksum, recorded when before-manifest.txt was first pinned)" pass
    else
      check "every file in backup/ is byte-identical to the original (checked by checksum, recorded when before-manifest.txt was first pinned) ($BACKUP_SUMS_PROBLEM)" fail
    fi
    fi

    # 8. Closed-set safety exercise: six numbered situations are described on
    #    this module's own page; exactly three are safe. The answer file
    #    names those three, matched exactly against the published key below -
    #    this key follows directly from the rule this module actually
    #    teaches (stay inside the one real folder you deliberately set up for
    #    this, and never let Claude Code touch your only backup), not an
    #    arbitrary judgment call.
    QUIZ_OK=false
    QUIZ_PROBLEM="safety-quiz-answers.txt not found yet"
    if [[ -L "$QUIZ_FILE" ]]; then
      QUIZ_PROBLEM="found a symlink, not a real file"
    elif [[ -f "$QUIZ_FILE" && -s "$QUIZ_FILE" ]]; then
      QUIZ_LINE="$(grep -m1 '^SAFE_SITUATIONS:' "$QUIZ_FILE" 2>/dev/null || true)"
      QUIZ_VALUE="$(printf '%s' "$QUIZ_LINE" | sed 's/^SAFE_SITUATIONS:[[:space:]]*//')"
      QUIZ_NUMS="$(printf '%s' "$QUIZ_VALUE" | grep -oE '[0-9]+' | sort -n)"
      QUIZ_COUNT="$(printf '%s\n' "$QUIZ_NUMS" | grep -c . || true)"
      QUIZ_UNIQUE_COUNT="$(printf '%s\n' "$QUIZ_NUMS" | sort -nu | grep -c . || true)"
      EXPECTED_NUMS="$(printf '2\n4\n6\n')"
      if [[ -z "$QUIZ_VALUE" ]]; then
        QUIZ_PROBLEM="the SAFE_SITUATIONS: line is empty"
      elif [[ "$QUIZ_COUNT" -ne 3 || "$QUIZ_UNIQUE_COUNT" -ne 3 ]]; then
        QUIZ_PROBLEM="pick exactly 3 distinct situation numbers"
      elif [[ "$QUIZ_NUMS" == "$EXPECTED_NUMS" ]]; then
        QUIZ_OK=true
      else
        QUIZ_PROBLEM="that's not the right set of 3 - re-read the six situations against the rule this module teaches"
      fi
    elif [[ -f "$QUIZ_FILE" ]]; then
      QUIZ_PROBLEM="safety-quiz-answers.txt exists but is empty"
    fi
    if [[ "$QUIZ_OK" == true ]]; then
      check "safety-quiz-answers.txt selects exactly the 3 safe situations" pass
    else
      check "safety-quiz-answers.txt selects exactly the 3 safe situations ($QUIZ_PROBLEM)" fail
    fi

    # 9. Own-words safety plan: same presence-and-genuine-content discipline
    #    as Modules 01/02's answers files, not AI-graded (see this module's
    #    own text for why - the safety plan's substance is a self-audit, not
    #    something with a single correct wording).
    PLACEHOLDER_NEVER="<what you would never point Claude Code at, and why>"
    PLACEHOLDER_UNDO="<what your undo story is - how you'd actually recover if something went wrong>"
    PLACEHOLDER_LINE="<where your own line between sandbox and real sits, in your own words>"
    if [[ -L "$PLAN_FILE" ]]; then
      check "safety-plan.txt has all three reflection answers, in your own words (found a symlink, not a real file)" fail
    elif [[ -f "$PLAN_FILE" ]]; then
      MISSING_LABELS=()
      for label in "NEVER_TOUCH:" "UNDO_STORY:" "MY_LINE:"; do
        case "$label" in
          "NEVER_TOUCH:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_NEVER" ;;
          "UNDO_STORY:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_UNDO" ;;
          "MY_LINE:") EXPECTED_PLACEHOLDER="$PLACEHOLDER_LINE" ;;
        esac
        LINE="$(grep -m1 "^$label" "$PLAN_FILE" 2>/dev/null || true)"
        VALUE="$(echo "$LINE" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$VALUE" || "$VALUE" == "$EXPECTED_PLACEHOLDER" ]]; then
          MISSING_LABELS+=("$label")
        fi
      done
      if [[ "${#MISSING_LABELS[@]}" -eq 0 ]]; then
        check "safety-plan.txt has all three reflection answers, in your own words" pass
      else
        check "safety-plan.txt has all three reflection answers, in your own words (still needed: ${MISSING_LABELS[*]})" fail
      fi
    else
      check "safety-plan.txt has all three reflection answers, in your own words" fail
    fi
    ;;
  10)
    # Module 10, the capstone: five artifacts, each drawing one mechanism
    # from an earlier module, all bound to genuinely new capstone-only
    # fixture data (fixtures/capstone/), plus a pack-completeness check.
    # Every hardening convention from every earlier module applies here too
    # -- no declare -A, checksum-protected fixtures, symlink/hard-link
    # rejection, exact-token/context-bound matching, never a bare
    # anywhere-in-document substring match.

    # === Artifact 1: research brief (Module 05's mechanism) ===================
    # [structural-only], same contract as Module 05: exists, 4 required
    # headers verbatim, >=3 distinct-site sources, a comparison table (scoped
    # to its own section) with no empty cells. Reuses Module 05's own
    # DDD-fixed logic (registrable-domain approximation + trailing-period
    # strip for hostname counting; table scoped to its own section, not the
    # whole document; leading-whitespace-tolerant table rows).
    EXPECTED_10_RESEARCH="$ROOT/10-capstone/research"
    RESEARCH10_DIR_OK=true
    if [[ -e "$EXPECTED_10_RESEARCH" ]]; then
      REAL_10_RESEARCH="$(cd "$EXPECTED_10_RESEARCH" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_10_RESEARCH" != "$EXPECTED_10_RESEARCH" ]] && RESEARCH10_DIR_OK=false
    fi
    BRIEF10="$ROOT/10-capstone/research/av-comparison-brief.md"
    BRIEF10_LINK_COUNT="$(stat -f '%l' "$BRIEF10" 2>/dev/null || stat -c '%h' "$BRIEF10" 2>/dev/null || echo "1")"
    BRIEF10_REAL_FILE=false
    if [[ "$RESEARCH10_DIR_OK" == false ]]; then
      check "10-capstone/research/av-comparison-brief.md exists and is non-empty (10-capstone/research/ is a symlink, not a real directory)" fail
    elif [[ -L "$BRIEF10" ]]; then
      check "10-capstone/research/av-comparison-brief.md exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$BRIEF10" && "$BRIEF10_LINK_COUNT" != "1" ]]; then
      check "10-capstone/research/av-comparison-brief.md exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$BRIEF10" ]]; then
      check "10-capstone/research/av-comparison-brief.md exists and is non-empty" pass
      BRIEF10_REAL_FILE=true
    else
      check "10-capstone/research/av-comparison-brief.md exists and is non-empty" fail
    fi

    REQUIRED_HEADERS10=("## Vendors Compared" "## Pricing" "## Equipment Included" "## Recommendation")
    if [[ "$BRIEF10_REAL_FILE" == true ]]; then
      MISSING_HEADERS10=()
      for h in "${REQUIRED_HEADERS10[@]}"; do
        grep -qxF "$h" "$BRIEF10" 2>/dev/null || MISSING_HEADERS10+=("$h")
      done
      if [[ "${#MISSING_HEADERS10[@]}" -eq 0 ]]; then
        check "av-comparison-brief.md has all 4 required section headers" pass
      else
        check "av-comparison-brief.md has all 4 required section headers (still missing: ${MISSING_HEADERS10[*]})" fail
      fi
    else
      check "av-comparison-brief.md has all 4 required section headers" fail
    fi

    if [[ "$BRIEF10_REAL_FILE" == true ]]; then
      HOSTNAMES10="$(grep -oE 'https?://[A-Za-z0-9.-]+' "$BRIEF10" 2>/dev/null \
        | sed -E 's#^https?://##' \
        | sed -E 's/\.$//' \
        | tr '[:upper:]' '[:lower:]' \
        | awk -F'.' '{
            n=NF
            if (n>=3) {
              last2=$(n-1)"."$n
              if (last2=="co.uk" || last2=="org.uk" || last2=="ac.uk" || last2=="gov.uk" || last2=="com.au" || last2=="net.au" || last2=="org.au" || last2=="co.nz" || last2=="co.jp" || last2=="co.in" || last2=="co.za" || last2=="com.br" || last2=="com.mx") {
                print $(n-2)"."$(n-1)"."$n
                next
              }
            }
            if (n>=2) print $(n-1)"."$n; else print $0
          }' \
        | sort -u)"
      HOSTNAME10_COUNT="$(printf '%s\n' "$HOSTNAMES10" | grep -c '.' || true)"
      if [[ "$HOSTNAME10_COUNT" -ge 3 ]]; then
        check "av-comparison-brief.md cites source URLs from at least 3 distinct sites (found $HOSTNAME10_COUNT)" pass
      else
        check "av-comparison-brief.md cites source URLs from at least 3 distinct sites (found $HOSTNAME10_COUNT)" fail
      fi
    else
      check "av-comparison-brief.md cites source URLs from at least 3 distinct sites" fail
    fi

    if [[ "$BRIEF10_REAL_FILE" == true ]]; then
      PRICING10_SECTION="$(awk '/^## Pricing[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag' "$BRIEF10" 2>/dev/null)"
      TABLE10_LINES="$(printf '%s\n' "$PRICING10_SECTION" | grep -E '^[[:space:]]*\|.*\|[[:space:]]*$' 2>/dev/null || true)"
      CONTENT10_ROWS=0; EMPTY10_CELL_ROWS=0; HAS10_SEPARATOR=false
      while IFS= read -r raw_line; do
        [[ -z "$raw_line" ]] && continue
        line="$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//')"
        STRIPPED10="$(printf '%s' "$line" | sed 's/[|:*[:space:]-]//g')"
        if [[ -z "$STRIPPED10" ]]; then HAS10_SEPARATOR=true; continue; fi
        CONTENT10_ROWS=$((CONTENT10_ROWS + 1))
        INNER10="${line#|}"; INNER10="${INNER10%|}"
        ROW10_EMPTY=false
        OLDIFS="$IFS"; IFS='|'; read -ra CELLS10 <<< "$INNER10"; IFS="$OLDIFS"
        for cell in "${CELLS10[@]}"; do
          TRIMMED10="$(printf '%s' "$cell" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          [[ -z "$TRIMMED10" ]] && ROW10_EMPTY=true
        done
        [[ "$ROW10_EMPTY" == true ]] && EMPTY10_CELL_ROWS=$((EMPTY10_CELL_ROWS + 1))
      done <<< "$TABLE10_LINES"
      if [[ "$HAS10_SEPARATOR" == true && "$CONTENT10_ROWS" -ge 4 && "$EMPTY10_CELL_ROWS" -eq 0 ]]; then
        check "av-comparison-brief.md has a comparison table with at least 3 rows and no empty cells" pass
      else
        check "av-comparison-brief.md has a comparison table with at least 3 rows and no empty cells" fail
      fi
    else
      check "av-comparison-brief.md has a comparison table with at least 3 rows and no empty cells" fail
    fi

    # === Artifact 2: script tally (Module 04's mechanism) ======================
    EXPECTED_10_CREW="$ROOT/10-capstone/crew"
    CREW_DIR_OK=true
    if [[ -e "$EXPECTED_10_CREW" ]]; then
      REAL_10_CREW="$(cd "$EXPECTED_10_CREW" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_10_CREW" != "$EXPECTED_10_CREW" ]] && CREW_DIR_OK=false
    fi
    if [[ "$CREW_DIR_OK" == true && -d "$EXPECTED_10_CREW" ]]; then
      check "10-capstone/crew/ directory exists (not a symlink)" pass
    else
      check "10-capstone/crew/ directory exists (not a symlink)" fail
      CREW_DIR_OK=false
    fi

    CREW_REPORT="$ROOT/10-capstone/crew/crew-report.txt"
    CREW_REPORT_LINK_COUNT="$(stat -f '%l' "$CREW_REPORT" 2>/dev/null || stat -c '%h' "$CREW_REPORT" 2>/dev/null || echo "1")"
    CREW_REPORT_OK=false
    if [[ "$CREW_DIR_OK" == false ]]; then
      check "10-capstone/crew/crew-report.txt exists and is non-empty (10-capstone/crew/ isn't set up as a real directory yet)" fail
    elif [[ -L "$CREW_REPORT" ]]; then
      check "10-capstone/crew/crew-report.txt exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$CREW_REPORT" && "$CREW_REPORT_LINK_COUNT" != "1" ]]; then
      check "10-capstone/crew/crew-report.txt exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$CREW_REPORT" ]]; then
      check "10-capstone/crew/crew-report.txt exists and is non-empty" pass
      CREW_REPORT_OK=true
    else
      check "10-capstone/crew/crew-report.txt exists and is non-empty" fail
    fi

    CREW_SCRIPT_FOUND=false
    if [[ "$CREW_DIR_OK" == true ]]; then
      for f in "$EXPECTED_10_CREW"/*; do
        [[ -e "$f" ]] || continue
        BASE_NAME="$(basename "$f")"
        if [[ "$BASE_NAME" != "crew-report.txt" && "$BASE_NAME" != "answers.txt" && -f "$f" && ! -L "$f" && -s "$f" ]]; then
          F_LINK_COUNT="$(stat -f '%l' "$f" 2>/dev/null || stat -c '%h' "$f" 2>/dev/null || echo "1")"
          [[ "$F_LINK_COUNT" != "1" ]] && continue
          CREW_SCRIPT_FOUND=true
          break
        fi
      done
    fi
    if [[ "$CREW_SCRIPT_FOUND" == true ]]; then
      check "10-capstone/crew/ contains the script itself, not just the report" pass
    else
      check "10-capstone/crew/ contains the script itself, not just the report" fail
    fi

    CREW_FIXTURES_OK=true
    if [[ "$CHECKSUM_TOOL_AVAILABLE" == false ]]; then
      check "all 8 crew-hours fixtures unmodified (couldn't verify: no checksum tool found on this system - contact the workshop)" fail
      CREW_FIXTURES_OK=false
    else
      BAD_CREW_FIXTURES=()
      for d in "${EXPECTED_CREW_HOURS_DATES[@]}"; do
        FPATH="$ROOT/fixtures/capstone/crew-hours-$d.txt"
        EXPECTED_SUM="$(crew_hours_expected_sha256 "$d")"
        ACTUAL_SUM="$(file_checksum "$FPATH" 2>/dev/null || echo "MISSING_FIXTURE")"
        [[ "$ACTUAL_SUM" != "$EXPECTED_SUM" ]] && BAD_CREW_FIXTURES+=("crew-hours-$d.txt")
      done
      if [[ "${#BAD_CREW_FIXTURES[@]}" -eq 0 ]]; then
        check "all 8 crew-hours fixtures unmodified (checksum verified)" pass
      else
        check "all 8 crew-hours fixtures unmodified (contact the workshop, not your own mistake - affected: ${BAD_CREW_FIXTURES[*]})" fail
        CREW_FIXTURES_OK=false
      fi
    fi

    CREW_TOTAL_EXPECTED=0
    CREW_BEST_DATE=""; CREW_BEST_HOURS=-1
    CREW_WORST_DATE=""; CREW_WORST_HOURS=-1
    if [[ "$CREW_FIXTURES_OK" == true ]]; then
      for d in "${EXPECTED_CREW_HOURS_DATES[@]}"; do
        FPATH="$ROOT/fixtures/capstone/crew-hours-$d.txt"
        LINE="$(grep -m1 '^Hours:' "$FPATH" 2>/dev/null || true)"
        N="$(echo "$LINE" | sed 's/^Hours:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        CREW_TOTAL_EXPECTED=$((CREW_TOTAL_EXPECTED + N))
        if [[ "$N" -gt "$CREW_BEST_HOURS" ]]; then CREW_BEST_HOURS="$N"; CREW_BEST_DATE="$d"; fi
        if [[ "$CREW_WORST_HOURS" -eq -1 || "$N" -lt "$CREW_WORST_HOURS" ]]; then CREW_WORST_HOURS="$N"; CREW_WORST_DATE="$d"; fi
      done
    fi

    read_crew_label() {
      local label="$1"
      [[ "$CREW_REPORT_OK" == true ]] || { echo ""; return; }
      local line
      line="$(grep -m1 "^$label" "$CREW_REPORT" 2>/dev/null || true)"
      echo "$line" | sed "s/^$label//" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    if [[ "$CREW_REPORT_OK" == true && "$CREW_FIXTURES_OK" == true ]]; then
      ACTUAL_CREW_TOTAL="$(read_crew_label 'TOTAL_HOURS:')"
      if [[ "$ACTUAL_CREW_TOTAL" == "$CREW_TOTAL_EXPECTED" ]]; then
        check "crew-report.txt has the exact total hours, recomputed from the 8 fixtures" pass
      else
        check "crew-report.txt has the exact total hours, recomputed from the 8 fixtures" fail
      fi
    else
      check "crew-report.txt has the exact total hours, recomputed from the 8 fixtures (contact the workshop, not your own mistake)" fail
    fi

    if [[ "$CREW_REPORT_OK" == true && "$CREW_FIXTURES_OK" == true ]]; then
      ACTUAL_CREW_BEST_DATE="$(read_crew_label 'BUSIEST_DATE:')"
      ACTUAL_CREW_BEST_HOURS="$(read_crew_label 'BUSIEST_HOURS:')"
      if [[ "$ACTUAL_CREW_BEST_DATE" == "$CREW_BEST_DATE" && "$ACTUAL_CREW_BEST_HOURS" == "$CREW_BEST_HOURS" ]]; then
        check "crew-report.txt has the exact busiest day, recomputed from the 8 fixtures" pass
      else
        check "crew-report.txt has the exact busiest day, recomputed from the 8 fixtures" fail
      fi
    else
      check "crew-report.txt has the exact busiest day, recomputed from the 8 fixtures (contact the workshop, not your own mistake)" fail
    fi

    if [[ "$CREW_REPORT_OK" == true && "$CREW_FIXTURES_OK" == true ]]; then
      ACTUAL_CREW_WORST_DATE="$(read_crew_label 'LIGHTEST_DATE:')"
      ACTUAL_CREW_WORST_HOURS="$(read_crew_label 'LIGHTEST_HOURS:')"
      if [[ "$ACTUAL_CREW_WORST_DATE" == "$CREW_WORST_DATE" && "$ACTUAL_CREW_WORST_HOURS" == "$CREW_WORST_HOURS" ]]; then
        check "crew-report.txt has the exact lightest day, recomputed from the 8 fixtures" pass
      else
        check "crew-report.txt has the exact lightest day, recomputed from the 8 fixtures" fail
      fi
    else
      check "crew-report.txt has the exact lightest day, recomputed from the 8 fixtures (contact the workshop, not your own mistake)" fail
    fi

    ANSWERS10_CREW="$ROOT/10-capstone/crew/answers.txt"
    ANSWERS10_CREW_LINK_COUNT="$(stat -f '%l' "$ANSWERS10_CREW" 2>/dev/null || stat -c '%h' "$ANSWERS10_CREW" 2>/dev/null || echo "1")"
    if [[ -L "$ANSWERS10_CREW" ]]; then
      check "10-capstone/crew/answers.txt has a genuine reflection answer" fail
    elif [[ -f "$ANSWERS10_CREW" && "$ANSWERS10_CREW_LINK_COUNT" != "1" ]]; then
      check "10-capstone/crew/answers.txt has a genuine reflection answer" fail
    elif [[ -f "$ANSWERS10_CREW" ]]; then
      LINE="$(grep -m1 "^PLAN_FIRST:" "$ANSWERS10_CREW" 2>/dev/null || true)"
      VALUE="$(echo "$LINE" | sed "s/^PLAN_FIRST://" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      PLACEHOLDER_PLAN10="<did you ask for a plan before running anything - yes or no, and what happened?>"
      if [[ -n "$VALUE" && "$VALUE" != "$PLACEHOLDER_PLAN10" ]]; then
        check "10-capstone/crew/answers.txt has a genuine reflection answer" pass
      else
        check "10-capstone/crew/answers.txt has a genuine reflection answer" fail
      fi
    else
      check "10-capstone/crew/answers.txt has a genuine reflection answer" fail
    fi

    # === Artifact 3: budget doc for Bruner (Module 06's mechanism) =============
    EXPECTED_10_BUDGET="$ROOT/10-capstone/budget"
    BUDGET_DIR_OK=true
    if [[ -e "$EXPECTED_10_BUDGET" ]]; then
      REAL_10_BUDGET="$(cd "$EXPECTED_10_BUDGET" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_10_BUDGET" != "$EXPECTED_10_BUDGET" ]] && BUDGET_DIR_OK=false
    fi
    BUDGET_DOC="$ROOT/10-capstone/budget/opening-night-budget.md"
    BUDGET_LINK_COUNT="$(stat -f '%l' "$BUDGET_DOC" 2>/dev/null || stat -c '%h' "$BUDGET_DOC" 2>/dev/null || echo "1")"
    BUDGET_REAL_FILE=false
    if [[ "$BUDGET_DIR_OK" == false ]]; then
      check "10-capstone/budget/opening-night-budget.md exists and is non-empty (10-capstone/budget/ is a symlink, not a real directory)" fail
    elif [[ -L "$BUDGET_DOC" ]]; then
      check "10-capstone/budget/opening-night-budget.md exists and is non-empty (found a symlink, not a real file)" fail
    elif [[ -f "$BUDGET_DOC" && "$BUDGET_LINK_COUNT" != "1" ]]; then
      check "10-capstone/budget/opening-night-budget.md exists and is non-empty (found a hard link, not an independently-written file)" fail
    elif [[ -s "$BUDGET_DOC" ]]; then
      check "10-capstone/budget/opening-night-budget.md exists and is non-empty" pass
      BUDGET_REAL_FILE=true
    else
      check "10-capstone/budget/opening-night-budget.md exists and is non-empty" fail
    fi

    WORD10_COUNT=0
    if [[ "$BUDGET_REAL_FILE" == true ]]; then
      WORD10_COUNT="$(wc -w < "$BUDGET_DOC" 2>/dev/null | tr -d ' ')"
      if [[ "$WORD10_COUNT" -ge 150 && "$WORD10_COUNT" -le 400 ]]; then
        check "opening-night-budget.md is 150-400 words long (found $WORD10_COUNT)" pass
      else
        check "opening-night-budget.md is 150-400 words long (found $WORD10_COUNT)" fail
      fi
    else
      check "opening-night-budget.md is 150-400 words long" fail
    fi

    REQUIRED_BUDGET_HEADERS=("## Summary" "## Budget Breakdown" "## Notable Items" "## Comparison to Last Season" "## Prepared By")
    if [[ "$BUDGET_REAL_FILE" == true ]]; then
      MISSING_BUDGET_HEADERS=()
      for h in "${REQUIRED_BUDGET_HEADERS[@]}"; do
        grep -qxF "$h" "$BUDGET_DOC" 2>/dev/null || MISSING_BUDGET_HEADERS+=("$h")
      done
      if [[ "${#MISSING_BUDGET_HEADERS[@]}" -eq 0 ]]; then
        check "opening-night-budget.md has all 5 required section headers, written exactly as specified" pass
      else
        check "opening-night-budget.md has all 5 required section headers, written exactly as specified (still missing: ${MISSING_BUDGET_HEADERS[*]})" fail
      fi
    else
      check "opening-night-budget.md has all 5 required section headers, written exactly as specified" fail
    fi

    BUDGET_FIXTURE="$ROOT/fixtures/capstone/opening-night-raw-figures.txt"
    BUDGET_FIXTURE_SUM="$(file_checksum "$BUDGET_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$BUDGET_FIXTURE_SUM" != "$EXPECTED_OPENING_NIGHT_FIGURES_SHA256" ]]; then
      check "opening-night-budget.md includes the exact total budget (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "opening-night-budget.md includes the expected attendance (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "opening-night-budget.md includes the advance ticket price (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
      check "opening-night-budget.md includes the entertainment fee (workshop fixture doesn't match its expected content - contact the workshop, not your own mistake)" fail
    else
      ENT_FEE="$(grep -oE 'Entertainment fee: \$[0-9,]+' "$BUDGET_FIXTURE" | grep -oE '[0-9,]+$' | tr -d ',')"
      AV_FEE="$(grep -oE 'AV and sound rental: \$[0-9,]+' "$BUDGET_FIXTURE" | grep -oE '[0-9,]+$' | tr -d ',')"
      CATERING_FEE="$(grep -oE 'Catering: \$[0-9,]+' "$BUDGET_FIXTURE" | grep -oE '[0-9,]+$' | tr -d ',')"
      SECURITY_FEE="$(grep -oE 'Security staffing: \$[0-9,]+' "$BUDGET_FIXTURE" | grep -oE '[0-9,]+$' | tr -d ',')"
      ATTENDANCE="$(grep -oE 'Expected attendance: [0-9]+' "$BUDGET_FIXTURE" | grep -oE '[0-9]+$')"
      TICKET_PRICE="$(grep -oE 'Advance ticket price: \$[0-9]+' "$BUDGET_FIXTURE" | grep -oE '[0-9]+$')"
      TOTAL_BUDGET_EXPECTED=$((ENT_FEE + AV_FEE + CATERING_FEE + SECURITY_FEE))

      TOTAL_LINE_TOKENS="$(grep -iE 'total' "$BUDGET_DOC" 2>/dev/null | grep -oE '\$?[0-9][0-9,]*' | tr -d '$,')"
      if [[ "$BUDGET_REAL_FILE" == true ]] && echo "$TOTAL_LINE_TOKENS" | grep -qxF "$TOTAL_BUDGET_EXPECTED"; then
        check "opening-night-budget.md includes the exact total budget, correctly summed" pass
      else
        check "opening-night-budget.md includes the exact total budget, correctly summed" fail
      fi

      ATTEND_LINE_TOKENS="$(grep -iE 'attend' "$BUDGET_DOC" 2>/dev/null | grep -oE '[0-9][0-9,]*' | tr -d ',')"
      if [[ "$BUDGET_REAL_FILE" == true ]] && echo "$ATTEND_LINE_TOKENS" | grep -qxF "$ATTENDANCE"; then
        check "opening-night-budget.md includes the expected attendance" pass
      else
        check "opening-night-budget.md includes the expected attendance" fail
      fi

      TICKET_LINE_TOKENS="$(grep -iE 'ticket|price' "$BUDGET_DOC" 2>/dev/null | grep -oE '\$?[0-9][0-9,]*' | tr -d '$,')"
      if [[ "$BUDGET_REAL_FILE" == true ]] && echo "$TICKET_LINE_TOKENS" | grep -qxF "$TICKET_PRICE"; then
        check "opening-night-budget.md includes the advance ticket price" pass
      else
        check "opening-night-budget.md includes the advance ticket price" fail
      fi

      ENT_LINE_TOKENS="$(grep -iE 'entertainment' "$BUDGET_DOC" 2>/dev/null | grep -oE '\$?[0-9][0-9,]*' | tr -d '$,')"
      if [[ "$BUDGET_REAL_FILE" == true ]] && echo "$ENT_LINE_TOKENS" | grep -qxF "$ENT_FEE"; then
        check "opening-night-budget.md includes the entertainment fee" pass
      else
        check "opening-night-budget.md includes the entertainment fee" fail
      fi
    fi

    # === Artifact 4: guest list merge (Module 07's mechanism) ==================
    PENNY_GUEST_FIXTURE="$ROOT/fixtures/capstone/penny-guest-list.csv"
    TILGHMAN_GUEST_FIXTURE="$ROOT/fixtures/capstone/tilghman-guest-draft.csv"
    GUEST_OUTPUT_DIR="$ROOT/10-capstone/guests"
    GUEST_OUTPUT_FILE="$GUEST_OUTPUT_DIR/guest-list-clean.csv"
    REQUIRED_GUEST_HEADER="guest_id,name,comp_tickets,plus_ones,total_admits"

    GUEST_FIXTURES_OK=true
    PENNY_GUEST_SUM="$(file_checksum "$PENNY_GUEST_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    TILGHMAN_GUEST_SUM="$(file_checksum "$TILGHMAN_GUEST_FIXTURE" 2>/dev/null || echo "MISSING_FIXTURE")"
    if [[ "$PENNY_GUEST_SUM" != "$EXPECTED_PENNY_GUEST_LIST_SHA256" || "$TILGHMAN_GUEST_SUM" != "$EXPECTED_TILGHMAN_GUEST_DRAFT_SHA256" ]]; then
      GUEST_FIXTURES_OK=false
      check "workshop fixtures penny-guest-list.csv and tilghman-guest-draft.csv match their expected content (contact the workshop, not your own mistake)" fail
    else
      check "workshop fixtures penny-guest-list.csv and tilghman-guest-draft.csv match their expected content" pass
    fi

    GUEST_OUTPUT_DIR_OK=true
    if [[ -e "$GUEST_OUTPUT_DIR" ]]; then
      REAL_GUEST_OUTPUT_DIR="$(cd "$GUEST_OUTPUT_DIR" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_GUEST_OUTPUT_DIR" != "$GUEST_OUTPUT_DIR" ]] && GUEST_OUTPUT_DIR_OK=false
    else
      GUEST_OUTPUT_DIR_OK=false
    fi
    GUEST_OUTPUT_LINK_COUNT="$(stat -f '%l' "$GUEST_OUTPUT_FILE" 2>/dev/null || stat -c '%h' "$GUEST_OUTPUT_FILE" 2>/dev/null || echo "1")"
    GUEST_LEARNER_FILE_OK=false
    if [[ "$GUEST_OUTPUT_DIR_OK" == false ]]; then
      check "10-capstone/guests/guest-list-clean.csv exists (10-capstone/guests/ is a symlink, not a real directory)" fail
    elif [[ -L "$GUEST_OUTPUT_FILE" ]]; then
      check "10-capstone/guests/guest-list-clean.csv exists (found a symlink, not a real file)" fail
    elif [[ -f "$GUEST_OUTPUT_FILE" && "$GUEST_OUTPUT_LINK_COUNT" != "1" ]]; then
      check "10-capstone/guests/guest-list-clean.csv exists (found a hard link, not an independently-written file)" fail
    elif [[ -s "$GUEST_OUTPUT_FILE" ]]; then
      check "10-capstone/guests/guest-list-clean.csv exists and is non-empty" pass
      GUEST_LEARNER_FILE_OK=true
    else
      check "10-capstone/guests/guest-list-clean.csv exists and is non-empty" fail
    fi

    if [[ "$GUEST_LEARNER_FILE_OK" == true ]]; then
      ACTUAL_GUEST_HEADER="$(sed -n '1p' "$GUEST_OUTPUT_FILE" 2>/dev/null)"
      ACTUAL_GUEST_HEADER="${ACTUAL_GUEST_HEADER%$'\r'}"
      ACTUAL_GUEST_HEADER_TRIMMED="$(printf '%s' "$ACTUAL_GUEST_HEADER" | awk -F',' '{for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i)}; out=$1; for(i=2;i<=NF;i++){out=out","$i}; print out}')"
      if [[ "$ACTUAL_GUEST_HEADER_TRIMMED" == "$REQUIRED_GUEST_HEADER" ]]; then
        check "guest-list-clean.csv has the exact required header row" pass
      else
        check "guest-list-clean.csv has the exact required header row" fail
      fi
    else
      check "guest-list-clean.csv has the exact required header row" fail
    fi

    GUEST_EXPECTED_IDS=(); GUEST_EXPECTED_NAME=(); GUEST_EXPECTED_COMP=(); GUEST_EXPECTED_PLUS=()
    if [[ "$GUEST_FIXTURES_OK" == true ]]; then
      for SRC in "$TILGHMAN_GUEST_FIXTURE" "$PENNY_GUEST_FIXTURE"; do
        FIRST_LINE=true
        while IFS=',' read -r g_id g_name g_comp g_plus; do
          if [[ "$FIRST_LINE" == true ]]; then FIRST_LINE=false; continue; fi
          g_id="$(trim_field "${g_id%$'\r'}")"
          g_name="$(trim_field "$g_name")"
          g_comp="$(trim_field "$g_comp")"
          g_plus="$(trim_field "${g_plus%$'\r'}")"
          [[ -z "$g_id" ]] && continue
          IDX="-1"
          [[ "${#GUEST_EXPECTED_IDS[@]}" -gt 0 ]] && IDX="$(array_index_of "$g_id" "${GUEST_EXPECTED_IDS[@]}")"
          if [[ "$IDX" -ge 0 ]]; then
            GUEST_EXPECTED_NAME[$IDX]="$g_name"; GUEST_EXPECTED_COMP[$IDX]="$g_comp"; GUEST_EXPECTED_PLUS[$IDX]="$g_plus"
          else
            GUEST_EXPECTED_IDS+=("$g_id"); GUEST_EXPECTED_NAME+=("$g_name"); GUEST_EXPECTED_COMP+=("$g_comp"); GUEST_EXPECTED_PLUS+=("$g_plus")
          fi
        done < "$SRC"
      done
    fi
    GUEST_EXPECTED_COUNT="${#GUEST_EXPECTED_IDS[@]}"

    GUEST_ACTUAL_IDS=(); GUEST_ACTUAL_NAME=(); GUEST_ACTUAL_COMP=(); GUEST_ACTUAL_PLUS=(); GUEST_ACTUAL_TOTAL=()
    if [[ "$GUEST_LEARNER_FILE_OK" == true ]]; then
      FIRST_LINE=true
      while IFS=',' read -r a_id a_name a_comp a_plus a_total; do
        if [[ "$FIRST_LINE" == true ]]; then FIRST_LINE=false; continue; fi
        a_id="$(trim_field "$a_id")"; a_name="$(trim_field "$a_name")"; a_comp="$(trim_field "$a_comp")"
        a_plus="$(trim_field "$a_plus")"; a_total="$(trim_field "${a_total%$'\r'}")"
        if [[ -z "$a_id" && -z "$a_name" && -z "$a_comp" && -z "$a_plus" && -z "$a_total" ]]; then continue; fi
        GUEST_ACTUAL_IDS+=("$a_id"); GUEST_ACTUAL_NAME+=("$a_name"); GUEST_ACTUAL_COMP+=("$a_comp")
        GUEST_ACTUAL_PLUS+=("$a_plus"); GUEST_ACTUAL_TOTAL+=("$a_total")
      done < "$GUEST_OUTPUT_FILE"
    fi
    GUEST_ACTUAL_COUNT="${#GUEST_ACTUAL_IDS[@]}"

    if [[ "$GUEST_FIXTURES_OK" == true && "$GUEST_LEARNER_FILE_OK" == true && "$GUEST_ACTUAL_COUNT" -eq "$GUEST_EXPECTED_COUNT" ]]; then
      check "guest-list-clean.csv row count matches the recomputed post-dedup count" pass
    else
      check "guest-list-clean.csv row count matches the recomputed post-dedup count" fail
    fi

    GUEST_ID_SET_OK=true
    if [[ "$GUEST_FIXTURES_OK" != true || "$GUEST_LEARNER_FILE_OK" != true ]]; then
      GUEST_ID_SET_OK=false
    else
      i=0
      while [[ $i -lt $GUEST_EXPECTED_COUNT ]]; do
        eid="${GUEST_EXPECTED_IDS[$i]}"; IDX="-1"
        [[ "${#GUEST_ACTUAL_IDS[@]}" -gt 0 ]] && IDX="$(array_index_of "$eid" "${GUEST_ACTUAL_IDS[@]}")"
        [[ "$IDX" -lt 0 ]] && GUEST_ID_SET_OK=false
        i=$((i + 1))
      done
      i=0
      while [[ $i -lt $GUEST_ACTUAL_COUNT ]]; do
        aid="${GUEST_ACTUAL_IDS[$i]}"; IDX="-1"
        [[ "${#GUEST_EXPECTED_IDS[@]}" -gt 0 ]] && IDX="$(array_index_of "$aid" "${GUEST_EXPECTED_IDS[@]}")"
        [[ "$IDX" -lt 0 ]] && GUEST_ID_SET_OK=false
        i=$((i + 1))
      done
    fi
    if [[ "$GUEST_ID_SET_OK" == true ]]; then
      check "the guest-ID set exactly matches the recomputed expected set (no lost rows, no invented rows)" pass
    else
      check "the guest-ID set exactly matches the recomputed expected set (no lost rows, no invented rows)" fail
    fi

    GUEST_FIELDS_OK=true
    if [[ "$GUEST_FIXTURES_OK" != true || "$GUEST_LEARNER_FILE_OK" != true || "$GUEST_ID_SET_OK" != true ]]; then
      GUEST_FIELDS_OK=false
    else
      i=0
      while [[ $i -lt $GUEST_EXPECTED_COUNT ]]; do
        eid="${GUEST_EXPECTED_IDS[$i]}"; IDX="-1"
        [[ "${#GUEST_ACTUAL_IDS[@]}" -gt 0 ]] && IDX="$(array_index_of "$eid" "${GUEST_ACTUAL_IDS[@]}")"
        if [[ "$IDX" -lt 0 ]]; then
          GUEST_FIELDS_OK=false
        else
          [[ "${GUEST_ACTUAL_NAME[$IDX]}" != "${GUEST_EXPECTED_NAME[$i]}" ]] && GUEST_FIELDS_OK=false
          [[ "${GUEST_ACTUAL_COMP[$IDX]}" != "${GUEST_EXPECTED_COMP[$i]}" ]] && GUEST_FIELDS_OK=false
          [[ "${GUEST_ACTUAL_PLUS[$IDX]}" != "${GUEST_EXPECTED_PLUS[$i]}" ]] && GUEST_FIELDS_OK=false
        fi
        i=$((i + 1))
      done
    fi
    if [[ "$GUEST_FIELDS_OK" == true ]]; then
      check "every surviving guest's name/comp_tickets/plus_ones exactly match the source of truth (Penny's copy wins on conflict)" pass
    else
      check "every surviving guest's name/comp_tickets/plus_ones exactly match the source of truth (Penny's copy wins on conflict)" fail
    fi

    GUEST_TOTAL_OK=true
    if [[ "$GUEST_LEARNER_FILE_OK" != true || "$GUEST_ACTUAL_COUNT" -eq 0 ]]; then
      GUEST_TOTAL_OK=false
    else
      i=0
      while [[ $i -lt $GUEST_ACTUAL_COUNT ]]; do
        comp="${GUEST_ACTUAL_COMP[$i]}"; plus="${GUEST_ACTUAL_PLUS[$i]}"; tot="${GUEST_ACTUAL_TOTAL[$i]}"
        if [[ "$comp" =~ ^-?[0-9]+$ && "$plus" =~ ^-?[0-9]+$ && "$tot" =~ ^-?[0-9]+$ ]]; then
          ROW_EXPECTED_TOTAL=$((comp + plus))
          [[ "$tot" != "$ROW_EXPECTED_TOTAL" ]] && GUEST_TOTAL_OK=false
        else
          GUEST_TOTAL_OK=false
        fi
        i=$((i + 1))
      done
    fi
    if [[ "$GUEST_TOTAL_OK" == true ]]; then
      check "every row's total_admits equals comp_tickets + plus_ones" pass
    else
      check "every row's total_admits equals comp_tickets + plus_ones" fail
    fi

    # === Artifact 5: press-photo rename + VIP mail merge (Module 08's mechanism) ===
    PRESS_MAPPING_CSV="$ROOT/fixtures/capstone/press-photo-mapping.csv"
    PRESS_MAPPING_SUM="$(file_checksum "$PRESS_MAPPING_CSV" 2>/dev/null || echo "MISSING_FIXTURE")"
    PRESS_MAPPING_OK=true
    if [[ "$PRESS_MAPPING_SUM" != "$EXPECTED_PRESS_PHOTO_MAPPING_SHA256" ]]; then
      PRESS_MAPPING_OK=false
      check "fixtures/capstone/press-photo-mapping.csv matches its expected content (contact the workshop, not your own mistake)" fail
    else
      check "fixtures/capstone/press-photo-mapping.csv matches its expected content" pass
    fi

    PRESS_PHOTOS_AGG_SUM="$(for i in $(seq -w 1 20); do f="$ROOT/fixtures/capstone/press-photos/PRESS_$i.jpg"; sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"; sum="$(file_checksum "$f" 2>/dev/null)"; printf 'PRESS_%s.jpg %s %s\n' "$i" "$sz" "$sum"; done | file_checksum /dev/stdin 2>/dev/null || echo "MISSING_FIXTURE")"
    PRESS_PHOTOS_FIXTURE_OK=true
    if [[ "$PRESS_PHOTOS_AGG_SUM" != "$EXPECTED_PRESS_PHOTOS_AGG_SHA256" ]]; then
      PRESS_PHOTOS_FIXTURE_OK=false
      check "fixtures/capstone/press-photos/ (20 originals) match their expected content (contact the workshop, not your own mistake)" fail
    else
      check "fixtures/capstone/press-photos/ (20 originals) match their expected content" pass
    fi

    EXPECTED_PRESS_OUT="$ROOT/10-capstone/press-photos"
    PRESS_OUT_OK=true
    if [[ -e "$EXPECTED_PRESS_OUT" ]]; then
      REAL_PRESS_OUT="$(cd "$EXPECTED_PRESS_OUT" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_PRESS_OUT" != "$EXPECTED_PRESS_OUT" ]] && PRESS_OUT_OK=false
    else
      PRESS_OUT_OK=false
    fi
    if [[ "$PRESS_OUT_OK" == true ]]; then
      check "10-capstone/press-photos/ directory exists (not a symlink)" pass
    else
      check "10-capstone/press-photos/ directory exists (not a symlink)" fail
    fi

    PRESS_RENAME_OK=true
    PRESS_RENAME_CORRECT=0
    if [[ "$PRESS_MAPPING_OK" == true && "$PRESS_PHOTOS_FIXTURE_OK" == true && "$PRESS_OUT_OK" == true ]]; then
      while IFS=',' read -r orig new; do
        [[ "$orig" == "original_filename" ]] && continue
        orig="$(trim_field "${orig%$'\r'}")"; new="$(trim_field "${new%$'\r'}")"
        [[ -z "$orig" ]] && continue
        OUT_PATH="$EXPECTED_PRESS_OUT/$new"
        ORIG_PATH="$ROOT/fixtures/capstone/press-photos/$orig"
        if [[ -L "$OUT_PATH" ]]; then
          PRESS_RENAME_OK=false; continue
        fi
        if [[ ! -f "$OUT_PATH" ]]; then
          PRESS_RENAME_OK=false; continue
        fi
        OUT_LINK_COUNT="$(stat -f '%l' "$OUT_PATH" 2>/dev/null || stat -c '%h' "$OUT_PATH" 2>/dev/null || echo "1")"
        if [[ "$OUT_LINK_COUNT" != "1" ]]; then
          PRESS_RENAME_OK=false; continue
        fi
        OUT_SUM="$(file_checksum "$OUT_PATH" 2>/dev/null || echo "")"
        ORIG_SUM="$(file_checksum "$ORIG_PATH" 2>/dev/null || echo "")"
        if [[ -n "$OUT_SUM" && "$OUT_SUM" == "$ORIG_SUM" ]]; then
          PRESS_RENAME_CORRECT=$((PRESS_RENAME_CORRECT + 1))
        else
          PRESS_RENAME_OK=false
        fi
      done < "$PRESS_MAPPING_CSV"
    else
      PRESS_RENAME_OK=false
    fi
    if [[ "$PRESS_RENAME_OK" == true && "$PRESS_RENAME_CORRECT" -eq 20 ]]; then
      check "all 20 photos renamed into 10-capstone/press-photos/, correctly named and byte-identical to their originals" pass
    else
      check "all 20 photos renamed into 10-capstone/press-photos/, correctly named and byte-identical to their originals (found $PRESS_RENAME_CORRECT/20 correct)" fail
    fi

    if [[ "$PRESS_OUT_OK" == true ]]; then
      PRESS_ACTUAL_COUNT="$(find "$EXPECTED_PRESS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
      if [[ "$PRESS_ACTUAL_COUNT" -eq 20 ]]; then
        check "10-capstone/press-photos/ contains exactly the 20 expected files, no extras" pass
      else
        check "10-capstone/press-photos/ contains exactly the 20 expected files, no extras (found $PRESS_ACTUAL_COUNT)" fail
      fi
    else
      check "10-capstone/press-photos/ contains exactly the 20 expected files, no extras" fail
    fi

    VIP_CSV="$ROOT/fixtures/capstone/vip-confirmations.csv"
    VIP_CSV_SUM="$(file_checksum "$VIP_CSV" 2>/dev/null || echo "MISSING_FIXTURE")"
    VIP_CSV_OK=true
    if [[ "$VIP_CSV_SUM" != "$EXPECTED_VIP_CONFIRMATIONS_SHA256" ]]; then
      VIP_CSV_OK=false
      check "fixtures/capstone/vip-confirmations.csv matches its expected content (contact the workshop, not your own mistake)" fail
    else
      check "fixtures/capstone/vip-confirmations.csv matches its expected content" pass
    fi

    EXPECTED_VIP_LETTERS_OUT="$ROOT/10-capstone/vip-letters"
    VIP_LETTERS_OUT_OK=true
    if [[ -e "$EXPECTED_VIP_LETTERS_OUT" ]]; then
      REAL_VIP_LETTERS_OUT="$(cd "$EXPECTED_VIP_LETTERS_OUT" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_VIP_LETTERS_OUT" != "$EXPECTED_VIP_LETTERS_OUT" ]] && VIP_LETTERS_OUT_OK=false
    fi

    VIP_LETTER_FILES=()
    VIP_LETTERS_TOTAL_ENTRIES=0
    if [[ "$VIP_LETTERS_OUT_OK" == true ]]; then
      VIP_LETTERS_TOTAL_ENTRIES="$(find "$EXPECTED_VIP_LETTERS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
      while IFS= read -r -d '' entry; do
        [[ -L "$entry" ]] && continue
        if [[ -f "$entry" ]]; then
          LINK_COUNT="$(stat -f '%l' "$entry" 2>/dev/null || stat -c '%h' "$entry" 2>/dev/null || echo "1")"
          [[ "$LINK_COUNT" == "1" ]] && VIP_LETTER_FILES+=("$entry")
        fi
      done < <(find "$EXPECTED_VIP_LETTERS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' -print0 2>/dev/null)
    fi

    if [[ "$VIP_LETTERS_OUT_OK" == false ]]; then
      check "10-capstone/vip-letters/ contains exactly 5 real letter files, no extras, no symlinks or hard links (10-capstone/vip-letters/ is a symlink, not a real directory)" fail
    elif [[ "$VIP_LETTERS_TOTAL_ENTRIES" -eq 5 && "${#VIP_LETTER_FILES[@]}" -eq 5 ]]; then
      check "10-capstone/vip-letters/ contains exactly 5 real letter files, no extras, no symlinks or hard links" pass
    else
      check "10-capstone/vip-letters/ contains exactly 5 real letter files, no extras, no symlinks or hard links (found $VIP_LETTERS_TOTAL_ENTRIES entries, ${#VIP_LETTER_FILES[@]} usable)" fail
    fi

    VIP_ROW_MATCHED=0
    VIP_CLAIMED=()
    if [[ "$VIP_CSV_OK" == true && "${#VIP_LETTER_FILES[@]}" -gt 0 ]]; then
      FIRST_LINE=true
      while IFS=',' read -r v_name v_date v_party; do
        if [[ "$FIRST_LINE" == true ]]; then FIRST_LINE=false; continue; fi
        v_name="$(trim_field "$v_name")"; v_date="$(trim_field "$v_date")"; v_party="$(trim_field "${v_party%$'\r'}")"
        [[ -z "$v_name" ]] && continue
        ROW_MATCHED=false
        for idx in "${!VIP_LETTER_FILES[@]}"; do
          ALREADY_CLAIMED=false
          if [[ "${#VIP_CLAIMED[@]}" -gt 0 ]]; then
            for c in "${VIP_CLAIMED[@]}"; do [[ "$c" == "$idx" ]] && ALREADY_CLAIMED=true; done
          fi
          [[ "$ALREADY_CLAIMED" == true ]] && continue
          CANDIDATE="${VIP_LETTER_FILES[$idx]}"
          if grep -qF "$v_name" "$CANDIDATE" 2>/dev/null && grep -qF "$v_date" "$CANDIDATE" 2>/dev/null && grep -qE "(^|[^0-9])${v_party}([^0-9]|\$)" "$CANDIDATE" 2>/dev/null; then
            ROW_MATCHED=true
            VIP_CLAIMED+=("$idx")
            break
          fi
        done
        [[ "$ROW_MATCHED" == true ]] && VIP_ROW_MATCHED=$((VIP_ROW_MATCHED + 1))
      done < "$VIP_CSV"
    fi
    if [[ "$VIP_ROW_MATCHED" -eq 5 ]]; then
      check "all 5 VIP letters contain their row's exact name, event date, and party size from the CSV" pass
    else
      check "all 5 VIP letters contain their row's exact name, event date, and party size from the CSV (matched $VIP_ROW_MATCHED/5)" fail
    fi

    VIP_ALL_NAMES=()
    if [[ "$VIP_CSV_OK" == true ]]; then
      FIRST_LINE=true
      while IFS=',' read -r v_name v_date v_party; do
        if [[ "$FIRST_LINE" == true ]]; then FIRST_LINE=false; continue; fi
        v_name="$(trim_field "$v_name")"
        [[ -z "$v_name" ]] && continue
        VIP_ALL_NAMES+=("$v_name")
      done < "$VIP_CSV"
    fi
    VIP_EXCLUSIVE_OK=true
    if [[ "${#VIP_LETTER_FILES[@]}" -eq 0 || "${#VIP_ALL_NAMES[@]}" -eq 0 ]]; then
      VIP_EXCLUSIVE_OK=false
    else
      for CANDIDATE in "${VIP_LETTER_FILES[@]}"; do
        NAME_HITS=0
        for nm in "${VIP_ALL_NAMES[@]}"; do
          grep -qF "$nm" "$CANDIDATE" 2>/dev/null && NAME_HITS=$((NAME_HITS + 1))
        done
        [[ "$NAME_HITS" -ne 1 ]] && VIP_EXCLUSIVE_OK=false
      done
    fi
    if [[ "$VIP_EXCLUSIVE_OK" == true ]]; then
      check "each VIP letter is personalized to exactly one guest, not a shared roster of all five" pass
    else
      check "each VIP letter is personalized to exactly one guest, not a shared roster of all five" fail
    fi

    VIP_PLACEHOLDER_COUNT=0
    if [[ "${#VIP_LETTER_FILES[@]}" -gt 0 ]]; then
      for CANDIDATE in "${VIP_LETTER_FILES[@]}"; do
        C="$(grep -o '{' "$CANDIDATE" 2>/dev/null | wc -l | tr -d ' ')"
        VIP_PLACEHOLDER_COUNT=$((VIP_PLACEHOLDER_COUNT + C))
        C2="$(grep -oE '\[[A-Za-z_]+\]|<[A-Za-z_]+>|[A-Za-z_]+_HERE' "$CANDIDATE" 2>/dev/null | wc -l | tr -d ' ')"
        VIP_PLACEHOLDER_COUNT=$((VIP_PLACEHOLDER_COUNT + C2))
      done
      if [[ "$VIP_PLACEHOLDER_COUNT" -eq 0 ]]; then
        check "zero unfilled template placeholders across the VIP letters (no leftover {, [BRACKETED], <TAGGED>, or _HERE markers)" pass
      else
        check "zero unfilled template placeholders across the VIP letters (found $VIP_PLACEHOLDER_COUNT leftover placeholder marker(s))" fail
      fi
    else
      check "zero unfilled template placeholders across the VIP letters (no letter files found to check)" fail
    fi

    # === Pack completeness gate ===
    # Checks what modules 01-09 actually produce, not an idealized naming scheme:
    # three exactly-named files (Modules 01/02, 04, 09), the root CLAUDE.md's
    # Module 03 headers, and a count-based proxy for the loosely-specified
    # Modules 05/06/07/08 contributions (each says "add something to my-pack/"
    # without dictating a filename).
    MY_PACK_DIR="$ROOT/my-pack"
    MY_PACK_DIR_OK=true
    if [[ -e "$MY_PACK_DIR" ]]; then
      REAL_MY_PACK_DIR="$(cd "$MY_PACK_DIR" 2>/dev/null && pwd -P || echo "")"
      [[ "$REAL_MY_PACK_DIR" != "$MY_PACK_DIR" ]] && MY_PACK_DIR_OK=false
    else
      MY_PACK_DIR_OK=false
    fi
    if [[ "$MY_PACK_DIR_OK" == true ]]; then
      check "my-pack/ directory exists (not a symlink)" pass
    else
      check "my-pack/ directory exists (not a symlink)" fail
    fi

    for pack_check in \
      "cheatsheet.md:your terminal survival card from Modules 01 and 02" \
      "recipe-safe-script-direction.md:your safe-script-direction recipe from Module 04" \
      "real-folder-ritual.md:your real-folder ritual notes from Module 09"; do
      pack_file="${pack_check%%:*}"
      pack_label="${pack_check#*:}"
      PACK_FILE_PATH="$MY_PACK_DIR/$pack_file"
      PACK_FILE_OK=false
      if [[ "$MY_PACK_DIR_OK" == true && -f "$PACK_FILE_PATH" && ! -L "$PACK_FILE_PATH" && -s "$PACK_FILE_PATH" ]]; then
        LINK_COUNT="$(stat -f '%l' "$PACK_FILE_PATH" 2>/dev/null || stat -c '%h' "$PACK_FILE_PATH" 2>/dev/null || echo "1")"
        [[ "$LINK_COUNT" == "1" ]] && PACK_FILE_OK=true
      fi
      if [[ "$PACK_FILE_OK" == true ]]; then
        check "my-pack/$pack_file exists with real content ($pack_label)" pass
      else
        check "my-pack/$pack_file exists with real content ($pack_label)" fail
      fi
    done

    ROOT_CLAUDE_MD="$ROOT/CLAUDE.md"
    ROOT_CLAUDE_MD_LINK_COUNT="$(stat -f '%l' "$ROOT_CLAUDE_MD" 2>/dev/null || stat -c '%h' "$ROOT_CLAUDE_MD" 2>/dev/null || echo "1")"
    ROOT_CLAUDE_MD_OK=false
    if [[ -f "$ROOT_CLAUDE_MD" && ! -L "$ROOT_CLAUDE_MD" && "$ROOT_CLAUDE_MD_LINK_COUNT" == "1" ]]; then
      if grep -Fxq '## Never touch `checks/`' "$ROOT_CLAUDE_MD" 2>/dev/null \
        && grep -Fxq '## Stay inside this folder unless a module says otherwise' "$ROOT_CLAUDE_MD" 2>/dev/null; then
        ROOT_CLAUDE_MD_OK=true
      fi
    fi
    if [[ "$ROOT_CLAUDE_MD_OK" == true ]]; then
      check "the workshop folder's CLAUDE.md still has its original headers after Module 03's edit" pass
    else
      check "the workshop folder's CLAUDE.md still has its original headers after Module 03's edit" fail
    fi

    MY_PACK_EXTRA_COUNT=0
    if [[ "$MY_PACK_DIR_OK" == true ]]; then
      while IFS= read -r -d '' entry; do
        [[ -L "$entry" ]] && continue
        BASE_NAME="$(basename "$entry")"
        case "$BASE_NAME" in
          .gitkeep|cheatsheet.md|recipe-safe-script-direction.md|real-folder-ritual.md) continue ;;
        esac
        if [[ -f "$entry" && -s "$entry" ]]; then
          LINK_COUNT="$(stat -f '%l' "$entry" 2>/dev/null || stat -c '%h' "$entry" 2>/dev/null || echo "1")"
          [[ "$LINK_COUNT" == "1" ]] && MY_PACK_EXTRA_COUNT=$((MY_PACK_EXTRA_COUNT + 1))
        fi
      done < <(find "$MY_PACK_DIR" -mindepth 1 -not -name '.*' -print0 2>/dev/null)
    fi
    if [[ "$MY_PACK_EXTRA_COUNT" -ge 5 ]]; then
      check "my-pack/ has real entries from Modules 05-08 too (found $MY_PACK_EXTRA_COUNT beyond the three named files, need at least 5)" pass
    else
      check "my-pack/ has real entries from Modules 05-08 too (found $MY_PACK_EXTRA_COUNT beyond the three named files, need at least 5)" fail
    fi

    # === Tier 2: own-words capstone reflection ===
    CAPSTONE_ANSWERS="$ROOT/10-capstone/answers.txt"
    CAPSTONE_ANSWERS_OK=false
    if [[ -f "$CAPSTONE_ANSWERS" && ! -L "$CAPSTONE_ANSWERS" ]]; then
      LINK_COUNT="$(stat -f '%l' "$CAPSTONE_ANSWERS" 2>/dev/null || stat -c '%h' "$CAPSTONE_ANSWERS" 2>/dev/null || echo "1")"
      [[ "$LINK_COUNT" == "1" ]] && CAPSTONE_ANSWERS_OK=true
    fi
    ANSWERS_WORDS=0
    if [[ "$CAPSTONE_ANSWERS_OK" == true ]]; then
      ANSWERS_WORDS="$(wc -w < "$CAPSTONE_ANSWERS" 2>/dev/null | tr -d ' ')"
    fi
    if [[ "$CAPSTONE_ANSWERS_OK" == true && "$ANSWERS_WORDS" -ge 40 ]]; then
      check "10-capstone/answers.txt exists with a real, substantial reflection (own words, not copy-pasted instructions)" pass
    else
      check "10-capstone/answers.txt exists with a real, substantial reflection (own words, not copy-pasted instructions)" fail
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
