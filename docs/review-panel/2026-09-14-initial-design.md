# Workshop Review Panel — Initial Design Pass

**Date:** 2026-09-14
**Scope:** `docs/workshop-design.md` (post-Codex-reconciliation version), plus `README.md`
**Input state:** the design doc had already been through one three-agent review chain (Fable draft → Codex adversarial critique, 21 confirmed findings → reconciliation) before this panel ran.

Per `~/hekton/gremlins/workshop/workshop-review-panel.md`'s process: seven personas reviewed the same input set independently and in parallel, each with an explicit lens and an explicit instruction on what to ignore, no persona seeing another's output before writing its own. **End-User/Target Learner was re-aimed** from its usual agent-literate default to this workshop's actual audience: a non-technical knowledge worker with zero prior terminal experience — the same re-aiming `copilot-fluent`'s own first panel run required.

All seven personas returned genuinely distinct, non-generic findings.

## Cross-persona agreements (highest-confidence signal)

**The Module 01→02 authenticated-session gap** — independently flagged by three personas: Developer Evangelist (names it as the friction point between "found this" and "started Module 01"), End-User/Target Learner (names it "the nightmare scenario: passing, then silently failing one module later"), and Instructional Designer (its own top finding, explicitly recommending it block Module 02 content authoring). This corroborates a finding Codex's earlier adversarial pass also caught independently. Four independent sources, one root cause — promoted to `docs/workshop-design.md` §14 item 1.

**Maintainer-facing review apparatus bleeding into document readability, and risking leakage toward learner-facing copy** — independently flagged by four personas: Developer Evangelist ("the pitch is buried under its own process artifacts... a process risk, not just a tone note"), End-User/Target Learner (the document's honesty is "written at me from outside, in language I'd never see verbatim"), Professional Technical Writer ("a reader who doesn't already know this is a three-agent review artifact will read this as a document arguing with itself"), Skeptical Practitioner (present-tense "built" claims for unbuilt things outrun their own disclaimers). Fixed directly: the design doc was restructured so body prose states only reconciled claims, with the full Codex/panel audit trail moved to a dedicated Revision Log section (§15).

## Per-persona findings

### AI/ML Practitioner (technical accuracy)
- **Module 09 self-contradiction:** the checker claims to verify per-file checksums *and* claims it "never reads the learner's real files' contents" — computing a checksum requires reading every byte. Fixed: reworded to "never displays, extracts, or transmits content, only derives a checksum."
- **Module 07's row-level correctness check was underspecified for the realistic conflict case** — two overlapping fixtures with the same booking ID could carry different field values, and no tie-break rule was stated. Fixed: added an explicit merge rule (Penny's CSV authoritative on conflict).
- Minor: "`cp` evidence"/"`mkdir` evidence" phrasing conflated command-usage with outcome-verification — not fixed as a wording nit, low priority.
- The §8 checker-hardening pattern (resolve root from script path, neutral temp dir, checksum-verified fixtures, nonzero exit) was independently assessed as "genuinely correct and standard defensive-checker design."

### Developer Evangelist (the hook)
- Pitch buried under process artifacts — see cross-persona agreement above, fixed.
- The Wade Garrett/*Road House* easter egg is hidden until after the capstone by design — flagged that this shouldn't be oversold as part of what hooks a first-time visitor, since the clever part is invisible at first contact. Not a text change; a framing note for site/marketing copy at content time.
- **The Double Deuce scenario "genuinely clears the generic-tutorial-with-a-costume bar"** — explicitly checked against this factory's own `heartbeat` near-miss (a generic vehicle no panel caught until a separate critique) and found differentiated: the fixture-generation device (Garrett's messy files), the cast's distinct task-requester voices, and the capstone's literalized metaphor all do real work, not decoration.
- Platform/install/auth gap as first-contact friction — same root cause as the cross-persona finding above.

### End-User / Target Learner (re-aimed to zero-terminal-experience audience)
- Document's honesty about the learner's fear is real but written in a maintainer voice, not yet translated into learner-facing copy — noted for content time, not fixable in the design doc itself.
- Module 01's row stacks five pieces of terminal vocabulary (a command, `mkdir`, `cp`, "byte-identical," PATH) with no visible indication of how much hand-holding surrounds them — a content-authoring concern, not a design-doc defect per se, but sharpens the urgency of the auth-gap fix.
- The document's own vocabulary-leak worry (§3) is validated: this reviewer found the draft's internal/learner-facing text genuinely hard to disentangle at a glance, confirming the safeguard named in §3 is necessary, not precautionary.
- "10-13 hours" feels optimistic given the open platform/auth questions, not dishonest.

### Professional Technical Writer (clarity, structure, consistency)
- Correction-callout density — see cross-persona agreement, fixed via restructure.
- **Broken cross-reference:** `docs/next-actions.md` cited "`docs/workshop-design.md` §8/§18" — the doc only has 13 (now 15) sections; "18" was a Codex finding number, not a section. Fixed.
- Finding numbers reused across unrelated corrections (e.g. "finding 4" and "finding 17" each labeled two different fixes) with no accessible index, since the critique document lives only in the private sibling repo — resolved as a side effect of the restructure (findings are now described in prose in §15, not cited by bare number in the body).
- Opening status paragraph was overloaded — trimmed in the restructure.
- No `docs/brand.md` exists yet, so no house style to check voice against — flagged, not fixed (content-time work).
- Minor: "Tier 1"/"Tier-1" hyphenation inconsistency — not fixed, low priority.

### Skeptical Practitioner (unsupported claims, hype)
- Present-tense "built" claims for an unbuilt checker throughout §7's table, with the "nothing exists yet" disclaimer buried in §8 and never echoed at the table itself — addressed by the restructure's clearer separation of design-intent language from status claims, though the table itself still necessarily describes intended checker behavior in active voice (a design spec has to be readable as a spec); the live-repo status is now stated once, plainly, in §15 rather than only in one buried paragraph.
- **"First ... in this factory" language overused** and, in §9, smuggled into a section whose whole premise is "we didn't verify the external landscape" — fixed: trimmed throughout, removed from §9's differentiator claims specifically.
- §1's hedge was performative (flags "genuinely capable"/"most tutorials assume" as unverified, then treats it as a load-bearing premise two sections later) — tightened in the restructure.
- §6's fix for the "engineer-track" mislabel just substituted one unsupported claim (appeal to the human's own characterization) for another — left as-is; the human's stated framing is the actual, verifiable fact available here, and the doc already scopes it as the human's characterization rather than an external claim.
- **"Showpiece checker" (Module 07)** was unearned hype with no comparison criteria — fixed: label removed.

### Instructional Designer (does the arc build; hands-on-by-design)
- Module 01→02 gap as top finding, recommending it block Module 02 content authoring — see cross-persona agreement, promoted to §14 item 1 with that priority.
- Tier 2's undefined completion contract undermines hands-on-by-design more than the doc credited, since several modules' actual instructional payload (safety judgment in 09, verification discipline in 04) lives almost entirely in Tier 2 — promoted to §14 item 3, framed as blocking-before-content-authoring per this persona's own recommendation.
- Capstone doesn't re-exercise Module 09's real-file safety ritual despite listing it as a prerequisite — fixed: Module 10's row now includes an explicit prompt to re-engage the ritual.
- Design Principle 4 gap: independently assessed as accurately self-described by the document, real but not necessarily blocking — left open at §14 item 4, with the two resolution options the doc already names, per this persona's own recommendation to decide before (not during) content-authoring.
- Terminal-literacy-first sequencing sound in principle; thinner in practice than "the floor the rest of the arc stands on" claims, given the named auth gap — same fix as the top finding.

### Security-Conscious Reviewer (does content teach or imply unsafe habits)
- Sandbox currently enforced entirely by instruction; the document never asks whether Claude Code's real permission-mode/allowed-directory settings could enforce it technically — added as new §14 item 7, open for content time.
- Permission-prompt habituation diagnosed correctly but the counter-exercise arrives too late (Module 09 only), leaving Modules 02-08 to build an unopposed yes-clicking habit — added as new §14 item 8.
- Module 09's safety check is a recognition test (select the safe ones from a list), not demonstrated in-the-moment behavior — a PASS risks overstating "safety verified." Named explicitly in §12's revised text rather than left implicit.
- Data-leaving-the-machine privacy risk was stated generically in §12 but never tied specifically to Module 09, the one module where real personal file content is actually read — fixed: §12 now calls this out at the point it matters.

## Prioritized action list

1. **[Fixed]** Module 01→02 authenticated-session gap promoted to the design doc's highest-priority open question (§14 item 1) — 4 independent sources (3 personas + Codex).
2. **[Fixed]** Maintainer review-apparatus readability problem — design doc restructured, correction-callout prose moved to a Revision Log (§15) — 4 independent sources.
3. **[Fixed]** Module 09 checksum self-contradiction reworded.
4. **[Fixed]** Module 07 merge-rule underspecification closed with an explicit tie-break rule.
5. **[Fixed]** Broken `§8/§18` cross-reference in `docs/next-actions.md`.
6. **[Fixed]** "First ... in this factory" framing trimmed, especially out of §9.
7. **[Fixed]** §1's performative hedge tightened.
8. **[Fixed]** "Hundreds of actions" unsupported figure softened (also independently caught by Codex).
9. **[Fixed]** "Showpiece checker" hype label removed.
10. **[Fixed]** Capstone now references Module 09's safety ritual.
11. **[Fixed]** §12 privacy note tied specifically to Module 09.
12. **[Open, §14 item 3]** Tier 2's completion contract — flagged as blocking for content authoring by the Instructional Designer.
13. **[Open, §14 item 4]** Design Principle 4 gap — real, not necessarily blocking, decide before content authoring.
14. **[Open, §14 item 5]** CLAUDE.md file-identity question.
15. **[Open, §14 item 6]** Install-step placement.
16. **[Open, §14 item 7]** Sandbox enforcement mechanism (instruction-only vs. technical).
17. **[Open, §14 item 8]** Permission-habituation exercise pacing.
18. **[Not fixed, low priority]** Tier-1/Tier 1 hyphenation consistency.

## Human Gate

This report is critique-only. Items 1-11 above were applied directly to `docs/workshop-design.md` as low-risk, reversible doc-text fixes, matching this Gremlin's own first-run precedent (`terminal-velocity`, 2026-07-03) for design-doc-fixable findings under a standing instruction to act rather than pause on reversible edits. Items 12-18 are structural/content-time decisions left for human direction, named explicitly in the design doc's own §14 rather than decided here.
