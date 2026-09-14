#!/usr/bin/env bash
# check-brand-lint.sh: Detect brand/style violations (em dashes, banned phrases,
# maintainer-vocabulary leaks) in published workshop content. Read-only.
# Adapted from copilot-fluent's scripts/check-brand-lint.sh (its multiline-
# join scan and allowlist marker, both real hardening this script's first
# draft lacked -- found by an adversarial cross-model review pass and fixed
# here rather than left as an inherited regression).
#
# Scope: published content only, per docs/brand.md's own boundary. Design/
# planning docs under docs/ (including docs/brand.md itself) are working
# documents and are explicitly exempt.
#
# Allowlist: a line containing the literal marker `brand-lint-ignore` is
# skipped by the banned-phrase AND em-dash scans, for that whole line. This
# exists because docs/brand.md's own hard rules state a rule by naming the
# phrase it prohibits -- without an escape hatch, published content that ever
# needs to explain a rule by naming the exact phrase would trip this same
# lint. Use sparingly, only for that exact situation.
#
# Named limit, not a security boundary: this is a whole-line bypass with no
# scoping beyond "the line contains this marker" -- a line using the marker
# to excuse an unrelated violation elsewhere on the same line would also
# pass. This tool trusts whoever adds the marker to use it honestly; it does
# not and cannot verify that.
#
# Usage:
#   scripts/check-brand-lint.sh           # human report
#   scripts/check-brand-lint.sh --check   # hook mode: exit 1 if violations found
#
# Network: none. Pure local file inspection.
set -uo pipefail

CHECK_MODE=false
[[ "${1:-}" == "--check" ]] && CHECK_MODE=true

ROOT=""
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/.hekton/project.yaml" ]]; then ROOT="$dir"; break; fi
  dir="$(dirname "$dir")"
done
if [[ -z "$ROOT" ]]; then
  echo "check-brand-lint: no .hekton/project.yaml found above this script." >&2
  exit 0
fi
cd "$ROOT"

VIOLATIONS=0
warn() { printf '  FAIL: %s\n' "$*"; VIOLATIONS=$((VIOLATIONS + 1)); }
ok() { printf '  OK: %s\n' "$*"; }

# Published-content scope: README, module content, build-log entries, and the
# site's own source once built. docs/brand.md and every other docs/ planning
# file are deliberately out of scope. Add new content dirs here as the
# workshop grows past its current skeleton.
SCOPE_FILES=()
[[ -f README.md ]] && SCOPE_FILES+=("README.md")
while IFS= read -r -d '' f; do SCOPE_FILES+=("$f"); done < <(find modules -name '*.md' -print0 2>/dev/null)
while IFS= read -r -d '' f; do SCOPE_FILES+=("$f"); done < <(find docs/build-log -name '*.md' -print0 2>/dev/null)
while IFS= read -r -d '' f; do SCOPE_FILES+=("$f"); done < <(find site/src -type f \( -name '*.astro' -o -name '*.mdx' \) -print0 2>/dev/null)

echo "-- Brand lint (published content only) ----------------------------------"
echo "  files checked: ${#SCOPE_FILES[@]}"
echo ""

# Strip any line containing the allowlist marker, then join lines WITHIN a
# paragraph (a lone newline, not part of a blank-line break) into spaces
# before matching -- preserving actual paragraph breaks as hard boundaries.
# The join exists because source wrapping (a multi-word phrase split across
# two lines) would otherwise evade a strictly per-line grep even though a
# browser renders the wrapped text as one continuous phrase. Only joining
# lone newlines, not every newline, avoids a second failure mode: two
# unrelated sentences either side of a paragraph break concatenating into an
# accidental match.
scan_files_excluding_allowlisted_lines() {
  local pattern="$1"; shift
  for f in "$@"; do
    grep -v 'brand-lint-ignore' "$f" 2>/dev/null | perl -0777 -pe 's/(?<!\n)\n(?!\n)/ /g' | tr -s ' ' | grep -qiF "$pattern" && echo "$f"
  done
}

if [[ "${#SCOPE_FILES[@]}" -eq 0 ]]; then
  ok "no published-content files found yet"
else
  # Hard rule: no em dash characters (docs/brand.md).
  EM_HITS=$(scan_files_excluding_allowlisted_lines '—' "${SCOPE_FILES[@]}")
  if [[ -n "$EM_HITS" ]]; then
    warn "em dash found in: $(echo "$EM_HITS" | tr '\n' ' ')"
  else
    ok "no em dashes in published content"
  fi

  # Banned phrases (docs/brand.md's list, kept in sync by hand -- update both
  # when one changes).
  BANNED=(
    "delve" "tapestry" "unlock" "seamless" "game-changing" "revolutioniz"
    "transform your workflow" "supercharge" "effortlessly" "cutting-edge"
    "thought leader" "in today's fast-paced world" "it's important to note"
    "at scale" "master the art of" "in this comprehensive guide"
    "10x your skills" "trick the checker" "beat the checker"
    "get past the prompt" "the terminal is scary"
  )
  for phrase in "${BANNED[@]}"; do
    HITS=$(scan_files_excluding_allowlisted_lines "$phrase" "${SCOPE_FILES[@]}")
    if [[ -n "$HITS" ]]; then
      warn "banned phrase \"$phrase\" found in: $(echo "$HITS" | tr '\n' ' ')"
    fi
  done

  # Workshop-specific: maintainer/process vocabulary must never leak into
  # LEARNER-FACING content (docs/brand.md's hard rule, the single most
  # convergent finding from this workshop's own Review Panel -- 4 of 7
  # personas). Scoped narrower than the full SCOPE_FILES above, on purpose:
  # docs/build-log/ is the maintainer's own build-in-public journal (first
  # person, can and does reference this factory's real tooling by name --
  # matches copilot-fluent's own build-log precedent) and is deliberately
  # exempt here, same as it's exempt from every prior workshop's equivalent
  # rule. README.md and modules/*.md are the actual learner-facing front
  # door and module content, so those stay in scope.
  LEARNER_FACING_FILES=()
  [[ -f README.md ]] && LEARNER_FACING_FILES+=("README.md")
  while IFS= read -r -d '' f; do LEARNER_FACING_FILES+=("$f"); done < <(find modules -name '*.md' -print0 2>/dev/null)
  while IFS= read -r -d '' f; do LEARNER_FACING_FILES+=("$f"); done < <(find site/src -type f \( -name '*.astro' -o -name '*.mdx' \) -print0 2>/dev/null)

  # Kept deliberately narrower than a first draft of docs/brand.md's own
  # prose list: "checker" and "the arc" were originally named there too, but
  # an adversarial review pass caught the mismatch (they weren't in this
  # script's list) and, on reflection, they're plain English a first-time
  # reader can parse from context -- unlike the terms below, which are real,
  # opaque internal-factory jargon. docs/brand.md was corrected to match this
  # script's actual, narrower scope rather than the other way around.
  MAINTAINER_TERMS=(
    "Tier 1" "Tier 2" "Coachgremlin" "self-attested" "grading key"
    "Design Principle" "Mock Learner Gremlin" "Workshop Gremlin"
  )
  if [[ "${#LEARNER_FACING_FILES[@]}" -gt 0 ]]; then
    for term in "${MAINTAINER_TERMS[@]}"; do
      HITS=$(scan_files_excluding_allowlisted_lines "$term" "${LEARNER_FACING_FILES[@]}")
      if [[ -n "$HITS" ]]; then
        warn "maintainer-facing term \"$term\" leaked into learner-facing content: $(echo "$HITS" | tr '\n' ' ')"
      fi
    done
  fi

  [[ "$VIOLATIONS" -eq 0 ]] && ok "no banned phrases or maintainer-vocabulary leaks in published content"
fi

echo ""
if [[ "$VIOLATIONS" -eq 0 ]]; then
  echo "Brand lint clean."
else
  echo "Brand lint found $VIOLATIONS issue(s). Fix per docs/brand.md's hard rules."
fi

if [[ "$CHECK_MODE" == true ]]; then
  [[ "$VIOLATIONS" -gt 0 ]] && exit 1
fi
exit 0
