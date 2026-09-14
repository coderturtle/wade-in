---
title: "Scaffold, design, and a ten-module skeleton"
description: "Wade In goes from an idea to a named, reviewed, skeleton-complete workshop in one session."
pubDate: 2026-09-14
tags: ["design", "review-panel", "scaffold"]
draft: false
---

Wade In started today as a genuinely different problem from this factory's last non-engineering workshop, `copilot-fluent`. That one could lean on Word, Excel, and Outlook: apps the learner already trusted, with the teaching subject layered on top. This one doesn't get that. The thing being taught, Claude Code, is also the interface the learner has to sit down at cold. There's no "the app you already know" to anchor to.

So before anything else, I interviewed the scope instead of guessing at it. The real terminal, no wrapper, was the first fork, and it turned out to be the one everything else hangs off: if the learner has genuinely never opened a terminal before, Module 01 can't start with Claude Code at all. It has to start with what a terminal even is.

That gave the workshop its name almost by accident. Wade Garrett, the veteran mentor from *Road House*, was already sitting in this factory's shared Swayze-verse (the same universe `copilot-fluent`'s Kellerman & Castle draws its cast from). "Wade In" does double duty: it's the literal promise to a nervous first-timer, and, to anyone who recognizes it, a quiet nod to the mentor character the scenario is actually built around. Same discipline as Kellerman & Castle: play it straight until the reveal, after the capstone, never during.

The design doc went through the full chain this factory uses for decisions worth getting right: a Fable draft, an adversarial Codex critique with live repo access, and a reconciliation pass where I independently re-verified the two claims Codex made that would have mattered most if they were wrong (they weren't). Then a seven-persona Review Panel, with the End-User lens re-aimed to someone who's never touched a terminal. Four of the seven personas converged, independently, on the same thing: the document's own record of being reviewed was making it harder to read, not easier, and risked bleeding maintainer vocabulary toward the eventual site. That's now a hard rule in the brand layer, not just a one-time fix.

The other convergent finding is the one that actually matters for content authoring: a learner can pass Module 01's checker and walk straight into an unmodeled login failure in Module 02, with zero diagnostic vocabulary to recover from it. Three Review Panel personas and the Codex pass all found it independently. It's now the first thing listed in the design doc's open questions, and nothing in Module 02 gets written for real until it's closed.

Ten modules got their skeletons today: a question, a place in the arc, a gate shape with the deterministic checker tier stated first, and a takeaway, all traceable straight back to the design doc's own table. No real exercises yet. That's genuinely next, and it's gated on resolving the auth question above before Module 02 specifically, not a formality.

One thing worth naming since it's the actual point of doing all this twice: this is the Mock Learner Gremlin's first real run against a workshop other than `copilot-fluent`, once content exists to test. Every prior run was on one project. Whether the mechanism holds up somewhere else is the open question it's been waiting to answer.
