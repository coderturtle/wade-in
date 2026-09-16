# Mock Learner Gremlin: full sweep synthesis (Modules 02-10)

**Date:** 2026-09-16. Companion to `2026-09-14-module-01.md` (Module 01's earlier run) - together these cover the full 10-module arc. Full per-module reports: `2026-09-16-module-0{2,3,4,5,6,7,8,9,10}.md`.

**Scale:** 9 modules, 2 personas each (diligent + scripted-flaw), every attempt using real nested `claude` CLI invocations against real fixtures - no fabricated artifacts anywhere in the sweep. Manual orchestration throughout, per this Gremlin's own documented preference over Workflow-tool parallelization.

## Cross-cutting findings

### 1. Real Claude Code resists small mistakes differently depending on how they're stated

The single most important pattern across this sweep, discovered by accident rather than by design. Three scripted flaws depending on the nested session "taking the bait" of an imperfect instruction did not land as intended:

- **Module 03:** an omitted "leave everything else untouched" constraint didn't produce a collateral edit - the model made only the four requested corrections anyway.
- **Module 08:** a mistyped placeholder name (`{{amount_due}}` vs. the CSV's real `amount` column) was semantically self-corrected, unprompted.
- **Module 10 (contrast case):** when the flaw was instead an *explicit, stated* scope ("there are six files," not an omission or typo), the model noticed the discrepancy but respected the stated instruction rather than overriding it - producing exactly the intended flawed output.

Read together, these establish a real, useful design principle for this workshop's own future content work: **a scripted flaw that depends on the model inferring around an ambiguous or imperfect instruction is unreliable; a scripted flaw baked into an explicit, unambiguous (if wrong) instruction is reliable.** This is good news about the underlying product - it does not blindly propagate small human errors into larger ones when the task is well-bounded - but it is a real methodological lesson for testing this workshop's own checkers going forward, not just a one-off curiosity.

### 2. The permission-prompt interactive-testing boundary is real and applies to every module

No module's Attempt Agent could hold up a live interactive permission dialog - a subagent inherently can't. Every run used `claude -p ... --permission-mode acceptEdits` (refined in Module 04 onward to scoped `--allowedTools` grants once plain `acceptEdits` was found not to cover Bash execution). This means **no run in this entire sweep tested any module's actual core teaching moment of watching and approving a live prompt** - only the artifact-producing and self-verification halves. This is named in every individual report; naming it once more here because it's the single most consistent gap across all nine runs, and the honest fix is a real human pilot, not a better version of this Gremlin's own mechanism.

### 3. Two real, previously-undocumented defects were found by running the real product, not by reading code

- **Module 04:** the module's own text claims `RESULT: PASS (7/7)`; the real checker has 8 checks, one (script-file presence) never mentioned in the prose. Confirmed by two independent live runs agreeing exactly.
- **Module 09:** the "new file exists from Part 5" check doesn't actually require Part 5's task to have run - an unrelated optional file (the module's own suggested `CLAUDE.md`) satisfies it. Confirmed twice, independently, by both personas' real runs.

Neither was hypothetical or found by static reading - both surfaced only because the exercises were actually run for real, which is the entire reason this Gremlin exists as a check distinct from a text review.

### 4. Gate discrimination was precise everywhere it was actually tested

Where a scripted flaw did land as intended (Modules 02, 04, 06, 07, 09's safety quiz, 10), the resulting checker failure isolated *exactly* to the flawed dimension, with every other check passing on real, correctly-produced content. This is strong, repeated evidence that this workshop's checker design - many small, independent checks rather than one blended pass/fail - is working as intended, not just in the DDD-authored bypass testing done earlier tonight, but against genuinely blind attempts with no knowledge of the checker's internals.

### 5. Real, unplanned findings about the underlying product surfaced organically

- **Module 06:** real Claude Code refused to accept a user-asserted wrong total on its first attempt, independently re-deriving the correct figure from the source file and asking for confirmation before writing anything - discovered as a side effect of testing a wrong-input scripted flaw, not something staged.
- **Module 05:** real live web research self-reported a blocked pricing page (403) rather than fabricating a number, and separately discovered and honestly reported that a real vendor's current pricing structure had changed since the module was authored.

Both are genuine evidence that the product behaves the way this workshop teaches learners to expect it to - caught only because these runs used the real product against the real internet, not a simulation of it.

### 6. Safety-critical isolation (Module 09) traded real end-to-end coverage for real safety

Testing Module 09 properly required isolating `$HOME` so no test could ever touch this machine's actual home directory - independently confirmed untouched, twice, including by a fresh blind agent's full-tree grep sweep. The unavoidable cost: the isolated environment had no reachable Claude Code login credentials, so neither persona's Part 5 (the actual live-session, real-file-writing part) could run at all. Both personas handled this honestly - one reported the block and moved on, one stopped mid-exercise to ask how to proceed rather than improvise around it. This is the right tradeoff (never risk the real thing to test the test), but it means Module 09's actual core mechanic remains the single least-covered piece of this entire sweep.

## What the sweep does not establish

Per Design Principle 6, said once for the whole sweep rather than module by module: every clean result here is evidence each module's gate is mechanically satisfiable and discriminating against a real, blind, honestly-executed attempt - not evidence a real first-time human learner will have the same experience, especially given the interactive-permission-prompt gap named above. A real human pilot remains the one thing this Gremlin's mechanism cannot substitute for.

## Recommendation for future scripted-flaw design in this workshop

Based on finding #1 above: when authoring a new module's scripted-flaw persona, prefer flaws that are explicit and literal in the persona's own stated input (a wrong number asserted outright, a backwards rule stated plainly, a wrong date range named directly) over flaws that depend on an omission or a typo the model might reasonably infer past. The former reliably produced the intended failure in every case this sweep tried (Modules 02, 04, 06, 07, 09, 10); the latter did not (Modules 03, 08) - not because the checkers were weak, but because the flaw itself never actually reached the checker in a form it was supposed to fail on.
