#!/usr/bin/env bash
# check-mirror-drift.sh: Detect when a repo-local mind-palace mirror has fallen
# behind the repo's own docs. Read-only. Schema-agnostic across project types.
#
# Usage:
#   scripts/check-mirror-drift.sh           # human report
#   scripts/check-mirror-drift.sh --check   # hook mode: exit 1 if drift is found
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
  echo "check-mirror-drift: no .hekton/project.yaml found above this script." >&2
  exit 0
fi

MP_REL="$(grep '^mind_palace_path:' "$ROOT/.hekton/project.yaml" 2>/dev/null \
  | sed 's/mind_palace_path: *//' | tr -d '"')"
# ── Public-capable split ──────────────────────────────────────────────────────
# A public-capable repo is born without factory-internal artefacts: it deliberately
# omits mind_palace_path AND the mind-palace/ mirror, both of which live in the
# private sibling that its own project.yaml names (`private_sibling:`).
#
# Without this, running from the public repo resolved MIRROR to "$ROOT/mind-palace/"
# — a directory that by design never exists — so the check exited 1 and the pre-push
# hook cried "mirror missing" on every single push. A warn-only hook that always warns
# trains you to ignore it, which is worse than not installing it.
#
# When not split, SIBLING is empty and MIRROR_ROOT stays $ROOT, so behaviour is
# unchanged for every ordinary repo.
MIRROR_ROOT="$ROOT"
SIBLING="$(grep '^private_sibling:' "$ROOT/.hekton/project.yaml" 2>/dev/null \
  | sed 's/private_sibling: *//' | tr -d '"')"
if [[ -n "$SIBLING" && -d "$(dirname "$ROOT")/$SIBLING" ]]; then
  MIRROR_ROOT="$(dirname "$ROOT")/$SIBLING"
  if [[ -z "$MP_REL" ]]; then
    MP_REL="$(grep '^mind_palace_path:' "$MIRROR_ROOT/.hekton/project.yaml" 2>/dev/null \
      | sed 's/mind_palace_path: *//' | tr -d '"')"
  fi
fi

# Last resort: DISCOVER the mirror rather than trust a recorded path.
#
# For a public-capable pair, mind_palace_path is recorded nowhere. The public repo omits
# it deliberately, and its generated project.yaml comment says it "lives in the private
# sibling's copy of this file" — but scaffold-project.sh never writes a project.yaml to
# the sibling at all (verified on object-lesson-private, 2026-08-18: .hekton/ holds only
# agent-run-log.yaml, change-log.yaml and build-tasks/). So the comment describes a file
# that does not exist.
#
# Rather than hardcode the vault taxonomy here, find the one directory under mind-palace/
# that holds an index.md. If there is more than one, do NOT guess — leaving MP_REL empty
# surfaces the existing "mirror directory missing" error, which is the honest outcome.
if [[ -z "$MP_REL" && -d "$MIRROR_ROOT/mind-palace" ]]; then
  _found="$(find "$MIRROR_ROOT/mind-palace" -maxdepth 5 -name index.md 2>/dev/null)"
  if [[ "$(printf '%s' "$_found" | grep -c .)" -eq 1 ]]; then
    _dir="$(dirname "$_found")"
    MP_REL="${_dir#"$MIRROR_ROOT/mind-palace/"}"
  fi
fi

# The docs themselves are split too, and not by a rule worth hardcoding: decisions.md
# is public, session-log.md is internal. Resolve each file wherever it actually is,
# preferring the public repo. Falling back to a non-existent path is fine — the
# helpers below already treat "missing" as zero/empty.
doc_path() {
  if [[ -f "$ROOT/docs/$1" ]]; then echo "$ROOT/docs/$1"
  elif [[ -f "$MIRROR_ROOT/docs/$1" ]]; then echo "$MIRROR_ROOT/docs/$1"
  else echo "$ROOT/docs/$1"; fi
}

DOCS="$ROOT/docs"
MIRROR="$MIRROR_ROOT/mind-palace/${MP_REL}"

DRIFT=0
warn() { printf '  WARN: %s\n' "$*"; }
ok() { printf '  OK: %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*"; }

echo "-- Mirror drift check --------------------------------------------------"
echo "  repo docs: $DOCS"
[[ "$MIRROR_ROOT" != "$ROOT" ]] && echo "  sibling:   $MIRROR_ROOT (public-capable split)"
echo "  mirror:    $MIRROR"
echo ""

if [[ ! -d "$MIRROR" ]]; then
  bad "mirror directory missing"
  exit 1
fi
for f in index.md decisions.md session-log.md; do
  if [[ ! -f "$MIRROR/$f" ]]; then
    bad "mirror/$f missing"
    DRIFT=1
  fi
done

count_dated_rows() { [[ -f "$1" ]] && grep -cE '^\|.*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" || echo 0; }
latest_log_date() { [[ -f "$1" ]] && grep -oE '##[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1 || echo ""; }
latest_adr() { [[ -f "$1" ]] && grep -oE '^#+[[:space:]]*ADR-[0-9]+' "$1" | grep -oE '[0-9]+' | sort -n | tail -1 || echo ""; }

REPO_DEC=$(count_dated_rows "$(doc_path decisions.md)")
MIR_DEC=$(count_dated_rows "$MIRROR/decisions.md")
if [[ "$REPO_DEC" -gt "$MIR_DEC" ]]; then
  warn "decisions: repo has $REPO_DEC dated rows, mirror has $MIR_DEC"
  DRIFT=1
else
  ok "decisions: mirror current ($MIR_DEC rows)"
fi

REPO_LOG=$(latest_log_date "$(doc_path session-log.md)")
MIR_LOG=$(latest_log_date "$MIRROR/session-log.md")
if [[ -n "$REPO_LOG" && "$REPO_LOG" > "$MIR_LOG" ]]; then
  warn "session-log: repo latest $REPO_LOG, mirror latest ${MIR_LOG:-none}"
  DRIFT=1
else
  ok "session-log: mirror current (${MIR_LOG:-none})"
fi

REPO_ADR=$(latest_adr "$(doc_path decisions.md)")
if [[ -n "$REPO_ADR" ]]; then
  if grep -q "ADR-${REPO_ADR}\b" "$MIRROR/index.md" 2>/dev/null || grep -qE "ADR-0*${REPO_ADR}" "$MIRROR/decisions.md" 2>/dev/null; then
    ok "index/decisions reference latest ADR-${REPO_ADR}"
  else
    warn "index does not reference latest decision ADR-${REPO_ADR}"
    DRIFT=1
  fi
fi

echo ""
if [[ "$DRIFT" -eq 0 ]]; then
  echo "Mirror is current."
else
  echo "Mirror has drifted. Update summary files in:"
  echo "  $MIRROR"
fi

if [[ "$CHECK_MODE" == true ]]; then
  exit "$DRIFT"
fi
exit 0
