# Workshop Review Panel: all ten modules, real content

**Date:** 2026-09-16
**Scope:** all ten modules' real, authored content (README.md + checker) across the stacked, unmerged branches (agent/claude/module-01-content through module-10-content, PRs #6-15). First panel run against real content since the 2026-07-03-style design-doc-only run; supersedes nothing, extends the 2026-09-14 design-doc review now that content exists.
**Personas:** all seven, fanned out in parallel, no persona saw another's output before writing its own, per `~/hekton/gremlins/workshop/workshop-review-panel.md`'s own process.

## How to read this report

Per the panel's own Human Gate: this report is a critique, not a set of applied fixes. Findings below are grouped by cross-persona agreement (higher confidence) and single-persona findings (still real, narrower). One candidate finding was independently re-verified against Anthropic's live documentation and found to be **incorrect** — noted explicitly rather than silently dropped, since a persona's disagreement is data, not a verdict.

## Cross-persona agreements (2+ personas, independently)

### 1. The root README contradicts itself about content status — Developer Evangelist + End-User/Learner

Both personas, working independently, hit the same self-contradiction on the very first document a visitor reads. **Root cause identified:** this defect exists on `agent/claude/module-02-content` (the branch both reviewers were pointed at, and the current tip of the "trunk" every module branch stacks on) but was already fixed on `agent/claude/module-10-content` during that module's own tracking-doc update pass earlier today — a live, concrete instance of the cross-branch documentation drift already flagged in `docs/decisions.md`'s 2026-09-16 entries. The fix exists; it just hasn't propagated to the branch most likely to be read right now.

**Action taken:** applied the same fix directly to `agent/claude/module-02-content` (the current main checkout) as part of writing this report, since it's the highest-visibility copy and the fix was already known-correct.

### 2. Terminology/structural drift across modules — Professional Technical Writer (primary), corroborated by Instructional Designer's pack-completeness finding

- The reflection artifact is introduced as "**A short answers file**" in Modules 01-07 and 09, but "**A short write-up**" in Modules 08 and 10 — same element, two names.
- Module 01 has no "*Next: [Module 02]...*" closing cross-reference; every other module (02-09) has one.
- Module 06 refers to the budget character as "Carl" ten times (including a section heading and an answer-field label), where every other module uses surname-only ("Bruner") after first introduction.
- Minor: Module 08's "A checklist you run yourself:" uses a colon where every other module uses a period; epigraph attribution style (first name vs. full name vs. surname) is inconsistent module to module.

None of these are brand-lint violations (checked clean against `docs/brand.md`'s hard rules) — they're consistency gaps the linter isn't designed to catch.

## Single-persona findings (real, narrower)

### 3. Module 10's pack-completeness gate is content-blind — Instructional Designer

The gate counts any ≥5 non-empty, non-symlinked files in `my-pack/` beyond the three exactly-named ones. A learner passes by dropping five unrelated stub files in — the check never verifies the files are the actual recipes Modules 05-08 ask for. This is a known, accepted trade-off from Module 10's own DDD process (documented in `docs/decisions.md`), not a newly discovered defect, but this review sharpens exactly how gameable the current count-based proxy is. Worth a cheap partial mitigation: require each counted file to be non-trivial in length (matching the bar already used for the capstone's own `answers.txt`), not just non-empty.

### 4. Module 10 doesn't gate re-engagement with Module 09's safety ritual — Instructional Designer

Confirmed by direct inspection of `check.sh`: zero Module-09/safety-related checks exist in the `10)` case block. "Before you finish: re-read Module 09" is a bare instruction with no artifact and no check, unlike every other prior module the capstone genuinely re-exercises (04, 06, 07, 08).

### 5. Module 09's real-folder ritual has three structural safety-design gaps — Security-Conscious Reviewer

- `backup/` lives inside the same folder the agent is given access to, protected only by instruction wording the module itself already calls unreliable ("an instruction, not a lock").
- The stated "verify" step (`ls`) is a filename listing — it can't detect an in-place content edit to an existing file, only additions/deletions by name.
- The "CLAUDE.md is an instruction, not a lock" caveat is introduced in Module 09 but Modules 03-08 already rely on CLAUDE.md governing behavior without ever stating that caveat.

No blind-approve habit found elsewhere in the arc; Module 04's plan-first habit is taught and consistently reinforced (Module 10 explicitly calls it back).

### 6. Tier-2 grading described as delivered but not built as described — Skeptical Critic

`modules/README.md`'s gate table states "checked by an AI pass against a supplied standard" and claims Modules 01-09 "have this for real now." No module actually runs a live AI-grading pass — each checks an answers file's presence/non-placeholder content only. This is consistent with the project's own real, considered decision (per `docs/next-actions.md`: "not every module needs a Tier 2... Module 01 ships with no AI-graded rubric at all") but the gate-table description itself overstates what's mechanically true across all nine modules uniformly.

### 7. Windows/Linux checker-testing status stated with more confidence than warranted — Skeptical Critic

Module 01 gives unhedged, specific Windows install/checker-invocation steps. `docs/next-actions.md` already states plainly the checker "has only been tested on macOS" and Windows/Linux execution "remain genuinely untested." The install *commands* were live-verified against Anthropic's docs; the *checker's* cross-platform behavior was not — the module text doesn't distinguish the two.

### 8. Leftover self-certifying citation — AI/ML→Claude Code Practitioner

Module 01: "(verified against Claude Code's own current documentation, 2026-09-14)" — reads as internal scaffolding note, not real sourcing, and shouldn't ship in learner-facing copy.

## A candidate finding checked and refuted

**AI/ML→Claude Code Practitioner persona claimed** that Module 02's framing of `--permission-mode default` as a meaningful, deliberate choice is technically wrong, on the theory that `default` mode is simply the real out-of-the-box behavior for a fresh account, making the explicit flag a no-op.

**Independently re-verified against Anthropic's live docs** (`code.claude.com/docs/en/permission-modes`) before accepting or acting on this: *"On Pro, Max, and Team plans, the built-in starting permission mode is auto mode"* — a distinct mode from `default`/Manual, where a classifier approves actions instead of asking the human. This directly confirms the module's existing claim (itself the product of an earlier, separately live-doc-verified Codex review, per `docs/decisions.md`'s 2026-09-15 entry) and refutes the persona's. **No action taken** — this is exactly the kind of disagreement DDD's RECONCILE step exists for: a reviewer's finding is data, not a verdict, and re-reading the artifact (here, the actual product docs) settled it rather than either blindly applying or blindly dismissing.

## What checked out clean

- Brand-lint hard rules (no em dashes, no banned phrases, no maintainer-vocabulary leaks, no "Wade Garrett" in full) — clean across all ten files by direct grep, confirmed by the Technical Writer persona independently of the repo's own `scripts/check-brand-lint.sh`.
- Prerequisite chain in every module's "Before you start" section matches `docs/workshop-design.md`'s dependency graph exactly (Instructional Designer).
- Every module has a real, stated gate; deterministic checks are consistently the primary and sole-required gate everywhere a subject has one (Instructional Designer) — no module quietly reduces to "read this, then move on."
- Install commands, OS/version gating, `pwd`/`cd`/`ls` semantics, permission-prompt UI behavior, and every bash-3.2-compatibility claim in the checker scripts (Claude Code Practitioner).
- No blind-approve/unsafe-habit modeling found outside the three Module-09-specific structural gaps above (Security-Conscious Reviewer).

## Prioritized action list

1. **Root README status contradiction** — fixed during this review (item 1); needs propagating to every other module branch before merge, same as the cross-branch drift already tracked in `docs/decisions.md`.
2. **Module 10's missing Module-09 re-engagement gate** (item 4) — a real, specific, code-confirmed design gap in the capstone's own stated purpose.
3. **Module 09's three structural safety gaps** (item 5) — the highest-stakes module in the arc; worth a deliberate second pass given what's at stake if a learner generalizes the gap badly.
4. **Terminology/structural drift cleanup** (item 2) — cheap, mechanical, no design judgment required.
5. **Tier-2 description overclaim + Windows/Linux hedge** (items 6-7) — text-only fixes, low cost.
6. **Pack-completeness content-blindness** (item 3) — already a known, accepted trade-off; the cheap partial mitigation (non-trivial-length requirement) is optional, not urgent.
7. **Leftover citation cleanup** (item 8) — trivial.

Per the panel's own Human Gate, none of the above has been applied except item 1 (a text-only propagation of an already-known-correct fix from another branch). The rest await a human decision on priority and whether to apply now or batch with other pre-merge cleanup.
