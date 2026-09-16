# Mock Learner Gremlin: Module 09/10 remediation acceptance re-run

**Date:** 2026-09-16
**Scope:** acceptance gate for the Module 09/10 safety remediation (backup relocation, in-place-edit fingerprint check, `index.txt`-specific provenance check, Module 03's CLAUDE.md caveat, Module 10's ritual-rehearsal gate), following a Codex-plan / Fable-critique / orchestrator-reconcile review chain. Three blind, isolated agents, each given only the relevant module's public `README.md` (never `checks/check.sh`, never this project's `docs/`), each working in its own disposable scratch copy of `workshop-folder/` with `$HOME` overridden away from this machine's real home directory throughout.

## Agent 1 — Module 09 blind diligent attempt + two scripted probes

**Diligent attempt:** followed the README literally, reached `RESULT: PASS (12/12)` on the first honest pass. Real folder location, sibling backup location, manifest mechanics, fingerprint pinning, and the `index.txt`-specific check all matched the README's description exactly - no guessing required. The only friction was environmental (a sandboxed `$HOME` has no reachable login credentials, so the actual interactive `claude` session in Part 5 couldn't run - the same acknowledged limitation Run 2026-09-16-module-09.md already named, not a new defect) and one documentation gap: the optional Part 5 `CLAUDE.md`, written before `index.txt`, shows up as a second "new" file in the after-manifest, and the README didn't say whether that was fine. **Fixed:** added a one-line reassurance to Part 5 confirming it doesn't affect anything, since the check now looks for `index.txt` specifically by name.

**Checker-state tampering probe (the exact bypass a prior run's Finding 4 was about, applied to the new fingerprint check):** tampered with an original file in place, confirmed the fingerprint check caught it, then hand-edited `.checker-state` to overwrite the stored `ORIGINAL` checksum with the tampered file's new hash - the direct way to try to hide the edit from the fingerprint check. **Did not produce a false PASS.** The fingerprint check did clear, but the backup-integrity check failed instead: the checker reuses the same stored `ORIGINAL` checksum as the reference for both checks, so overwriting it to hide the live-folder edit simultaneously breaks the comparison against the untouched backup file, which still hashes to the true original value. `RESULT: FAIL (11/12)` either way. This is an emergent property of reusing one pin record for two independent checks, not a deliberate design decision documented anywhere - worth knowing, not worth adding complexity to preserve, since a from-scratch attempt to fully forge both the fingerprint entry and the backup file was out of this probe's scope and would require actually reconstructing a plausible original, not just editing a checksum.

**Single-file baseline edge case:** a real folder with exactly one file (not three) pinned, backed up, and verified with no special-case failures - `RESULT: PASS (12/12)`.

## Agent 2 — Module 10 rehearsal-gate brute-force quantification

Given only the module's README (not `check.sh`), attempted to find the correct `SAFE_ACTIONS:` set for the new ritual-rehearsal scenario by lexicographic enumeration against checker pass/fail feedback alone, with zero reasoning about the scenario's content. **Found it in 6 attempts**, in a few seconds of wall-clock time - the checker is fast, deterministic, and unthrottled, so exhaustive search over all C(6,3)=20 combinations is trivial. Assessment, direct quote: "the mechanical gate provides essentially zero resistance to a learner who wants to skip the reasoning" - the `WHY_RISKY` free-text field is the only real barrier, and it's an honor-system one, exactly as the module's own honest-limits text already discloses. No new finding: this confirms the risk named in the module's own text at the expected severity, rather than surfacing anything undisclosed.

## Agent 3 (fork) — Fix 6 verbatim-copy re-verification

Re-tested, rather than assumed from an earlier session's memory, that pasting Module 08's own Takeaway paragraph verbatim into `my-pack/recipe-batch-rename.md` still gets caught by the `RECIPE_VERBATIM` banned-excerpt check, and that a genuine own-words rewrite of comparable length still clears it. Confirmed both: `FAIL: ...has real, substantial content in your own words` for the verbatim copy, `PASS` for the rewrite. No drift since Fix 6 landed.

## What this run establishes

No new defect requiring a code fix was found. The two probes most directly aimed at defeating the new Module 09 checks (checker-state tampering to hide an in-place edit; a minimal single-file baseline) both held up correctly. Module 10's rehearsal gate is exactly as brute-forceable as its own text already admits - a confirmation of a disclosed limit, not a new one. Fix 6's verbatim-copy rejection still works. One real documentation gap was found and fixed (the optional Part 5 `CLAUDE.md` interaction with the after-manifest).

## Honest limit

Per Design Principle 6: this is evidence the remediated checks are mechanically sound against the specific probes this run tried, not proof no other bypass exists. In particular, this run did not attempt to forge a complete matching fingerprint-plus-backup pair from scratch (as opposed to editing an existing pin record after the fact), and did not re-test Module 09's actual live interactive Part 5 session end to end, for the same credential-isolation reason the original 2026-09-16-module-09.md run named.
