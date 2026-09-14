# Maintainers

This is the internal/agent-facing doc. Learners should read the top-level `README.md` instead; this file is for anyone working on the workshop itself.

**Classification:** factory-output
**Lifecycle:** active
**Owner:** coderturtle
**Promotion target:** `none`

This repo has two goals:

1. **Ship a workshop** teaching non-technical knowledge workers, who have never used a terminal, to use the real Claude Code CLI for research, document drafting, spreadsheet-adjacent tasks, and light file-based automation — taught inside one continuing fictional scenario (The Double Deuce), gated by a real, locally-executable deterministic checker script per module plus an AI-graded conceptual rubric on top.
2. **Feed evidence back into the reusable machinery**: this is the Workshop Gremlin's eighth real run and its second non-engineering-audience run (`copilot-fluent` was the first). It's also the Mock Learner Gremlin's first real run on a workshop other than `copilot-fluent` — the "does the mechanism generalize" milestone that gremlin's own Follow-Up Actions have been waiting on. Findings worth writing back to either gremlin's own definition should be captured as this run progresses.

## Implementation Status

- 2026-09-14 — Scaffolded as factory-output (working title `claude-code-for-non-engineers`). Naming pass complete: **Wade In**, local dir/GitHub repo/private sibling/vault card all renamed to match. See `docs/decisions.md`.
- Design doc complete via a three-agent review chain (Fable plan draft → Codex adversarial critique with live repo access, 21 confirmed findings → reconciliation): see [Workshop Design](workshop-design.md). Audience, format, scenario, module arc, and two-tier gate design are all settled; several genuinely open design questions (the Module 01→02 auth gap, the platform decision, Tier 2's completion contract) are named explicitly in that doc's §14, not silently resolved.
- 2026-09-14 — Workshop Review Panel (7-persona pass) run against the reconciled design doc: [Review Panel Report](review-panel/2026-09-14-initial-design.md). Strongest finding (corroborated by 4 independent sources across both review passes): the Module 01→02 auth gap, now the top item in `docs/workshop-design.md` §14 — treat as blocking for Module 02 content authoring specifically. A second 4-persona convergence drove a full restructure of the design doc (correction-callout prose moved out of the body into a dedicated Revision Log, §15).
- 2026-09-14 — Deliverables & branding step complete: module skeleton (all 10 modules, `modules/`), brand layer ([Brand](brand.md), with the Review Panel's Skeptical Practitioner findings encoded as permanent hard rules per the Workshop Gremlin's own voice-finding-handoff discipline), and README rewritten into learner-facing pitch shape with this doc split out.
- 2026-09-14 — Build-log/Pages publisher step complete: Astro site skeleton under `site/`, `docs/build-log/` started, deploy workflow defined (`workflow_dispatch` only, not triggered). `npm run build` and `astro check` both clean. This closes the Workshop Gremlin's own Completion Condition for the Build phase — see [Next Actions](next-actions.md) for what's left before content authoring can start in earnest.

## Documentation Contract

Agents working here must inspect `.hekton/project.yaml` before structural changes, record meaningful design decisions in `docs/decisions.md`, and update `docs/next-actions.md` when the work queue changes. Session/agent-run/change logs, the Human Understanding Check, and the Depth Decision live in the private sibling repo (`wade-in-private/`), not here — this repo is public-capable and was born without them.

Vault mutation is not allowed by default (`vault_mutation_allowed: false` in `.hekton/project.yaml`). The repo-local `mind-palace/` folder (in the private sibling) is only a mirror draft; do not write to the live vault unless explicitly authorised in-session — this project's naming-rename vault mutation was authorised in-session on 2026-09-14, see `docs/decisions.md`.

## Key Docs

- [Workshop Design](workshop-design.md) — audience, format, scenario, two-tier gate method, module arc, and every named open design question (§14)
- [Modules](../modules/README.md) — the 10-module arc index and current skeleton status
- [Brand](brand.md) — voice, hard rules, visual identity for published content
- [Codex Critique](../../wade-in-private/docs/codex-critique-workshop-design-2026-09-14.md) — the full adversarial critique behind the design doc's reconciliation (private sibling)
- [Workshop Review Panel Report](review-panel/2026-09-14-initial-design.md) — 7-persona critique, first run
- [Decisions](decisions.md)
- [Next Actions](next-actions.md)
- [Risks](risks.md)
- [Project Walkthrough](project-walkthrough.md)
- [Operating Model](operating-model.md)
