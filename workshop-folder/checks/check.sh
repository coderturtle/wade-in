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
EXPECTED_STAFF_LIST_SHA256="f7e6af0c87228e99d6d880b0b4b10bc1cda45e708f03235eaa2fcd973be9243f"
EXPECTED_EMMETT_MEMO_SHA256="7abfa8b6da208141a046ac44fc903e56d4692cd4d190b9660ed3d2526a9fb5d3"
EXPECTED_MONTHLY_RAW_NUMBERS_SHA256="9268dbb4a3b65e437b159a082ee51eeb7d70bd24365bdbca6004a24206aea255"
EXPECTED_PENNY_BOOKINGS_SHA256="a84d9f1d87635beee84c0cebb4543c5212c7b09bab9d52bf20d755f4bbd78c6d"
EXPECTED_GARRETT_BOOKINGS_SHA256="4d1159c92e231829fd0b985028e268bfcc31d9cb3aa806c310e28a420dcc388d"
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
      # Excludes dotfiles (-not -name '.*') -- found by a fresh-context
      # adversarial pass: the module's own text tells the learner to open
      # this folder in Finder to spot-check a few files, and Finder
      # routinely writes a .DS_Store into any local folder it displays,
      # which would otherwise inflate this count to 26 with no diagnostic
      # telling a first-time terminal user what happened or how to fix it.
      ACTUAL_PHOTO_COUNT="$(find "$EXPECTED_PHOTOS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
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
      # Same dotfile exclusion as the photos count above (.DS_Store from
      # Finder spot-checking).
      LETTERS_TOTAL_ENTRIES="$(find "$EXPECTED_LETTERS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
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
      done < <(find "$EXPECTED_LETTERS_OUT" -mindepth 1 -maxdepth 1 -not -name '.*' -print0 2>/dev/null)
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
      # Counts any lone `{` character, not just literal `{{` -- found by a
      # fresh-context adversarial pass: a broken/near-miss remnant like
      # "{ {amount} }" (a space between the braces) doesn't contain "{{" at
      # all and was demonstrated to slip through undetected when a
      # different, correctly-filled line elsewhere in the same letter
      # already satisfied the content-match check. The template's own fixed
      # prose (see the module text) never contains a literal `{` anywhere
      # once the three placeholders are genuinely filled in, so counting
      # every `{` is not an overclaim -- a correctly-filled letter has zero.
      PLACEHOLDER_COUNT=0
      for CANDIDATE in "${LETTER_FILES[@]}"; do
        C="$(grep -o '{' "$CANDIDATE" 2>/dev/null | wc -l | tr -d ' ')"
        PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + C))
      done
      if [[ "$PLACEHOLDER_COUNT" -eq 0 ]]; then
        check "zero unfilled template placeholders across the letters (no leftover { anywhere)" pass
      else
        check "zero unfilled template placeholders across the letters (found $PLACEHOLDER_COUNT leftover { character(s))" fail
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
    # Checks what modules 01-09 actually ask the learner to produce: three
    # exactly-named files (Modules 01/02, 04, 09), the root CLAUDE.md's Module
    # 03 headers, and five more exactly-named recipe files (Modules 05-08,
    # Module 08 contributing two). Named, not counted -- a count-based proxy
    # was gameable by five unrelated stub files, a real finding from this
    # workshop's own Workshop Review Panel (2026-09-16, Instructional
    # Designer persona). Each named file also needs a real word count and
    # must not just be its own source module's Takeaway paragraph pasted
    # verbatim -- the same panel's own DDD-style adversarial pass on this
    # exact fix named that as a real, cheap bypass a length-only bar misses.
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

    # Five more named recipes, one per Modules 05-07 and two from Module 08.
    # Each needs: real file (not symlink/hard-link), at least 40 words (the
    # same bar the capstone's own answers.txt already uses), and not just its
    # source module's own Takeaway paragraph copied verbatim -- checked via a
    # distinctive, sufficiently long excerpt from that exact paragraph,
    # normalized for whitespace so line-wrapping alone doesn't dodge it.
    for recipe_check in \
      "recipe-research-prompt.md:your research-prompt recipe from Module 05:demand named sources for any factual claim" \
      "recipe-document-drafting.md:your document-drafting recipe from Module 06:name the source file, name the exact output path" \
      "recipe-csv-task.md:your CSV-task recipe from Module 07:state the rule before you ask, demand a before/after count" \
      "recipe-batch-rename.md:your batch-rename recipe from Module 08:point Claude Code at a folder of files and a mapping sheet" \
      "recipe-mail-merge.md:your mail-merge recipe from Module 08:point it at a CSV and a template with placeholders"; do
      recipe_file="$(printf '%s' "$recipe_check" | awk -F':' '{print $1}')"
      recipe_label="$(printf '%s' "$recipe_check" | awk -F':' '{print $2}')"
      recipe_banned_excerpt="$(printf '%s' "$recipe_check" | awk -F':' '{print $3}')"
      RECIPE_PATH="$MY_PACK_DIR/$recipe_file"
      RECIPE_EXISTS_OK=false
      if [[ "$MY_PACK_DIR_OK" == true && -f "$RECIPE_PATH" && ! -L "$RECIPE_PATH" ]]; then
        RECIPE_LINK_COUNT="$(stat -f '%l' "$RECIPE_PATH" 2>/dev/null || stat -c '%h' "$RECIPE_PATH" 2>/dev/null || echo "1")"
        [[ "$RECIPE_LINK_COUNT" == "1" ]] && RECIPE_EXISTS_OK=true
      fi
      if [[ "$RECIPE_EXISTS_OK" == true ]]; then
        check "my-pack/$recipe_file exists ($recipe_label)" pass
      else
        check "my-pack/$recipe_file exists ($recipe_label)" fail
      fi

      RECIPE_WORDS=0
      RECIPE_VERBATIM=false
      if [[ "$RECIPE_EXISTS_OK" == true ]]; then
        RECIPE_WORDS="$(wc -w < "$RECIPE_PATH" 2>/dev/null | tr -d ' ')"
        RECIPE_NORMALIZED="$(tr '\n' ' ' < "$RECIPE_PATH" 2>/dev/null | tr -s ' ')"
        if printf '%s' "$RECIPE_NORMALIZED" | grep -qF "$recipe_banned_excerpt"; then
          RECIPE_VERBATIM=true
        fi
      fi
      if [[ "$RECIPE_EXISTS_OK" == true && "$RECIPE_WORDS" -ge 40 && "$RECIPE_VERBATIM" == false ]]; then
        check "my-pack/$recipe_file has real, substantial content in your own words" pass
      else
        check "my-pack/$recipe_file has real, substantial content in your own words" fail
      fi
    done

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
