# Next Actions: Wade In

## Immediate

- [x] Define project brief — see `.hekton/project.yaml` idea field
- [x] Record first design decisions in `docs/decisions.md` — naming pass + full interview-confirmed scope now logged
- [x] Draft, adversarially critique, and reconcile `docs/workshop-design.md` (three-agent chain) — done 2026-09-14

## This Week

- [ ] Run the Workshop Review Panel (7-persona pass) against the reconciled `docs/workshop-design.md`
- [ ] Resolve the platform decision (macOS/Linux-first vs. dual-track vs. Windows-first) — currently the single largest unresolved design risk, per `docs/workshop-design.md` §11
- [ ] Design Module 01's authenticated-session check (`docs/workshop-design.md` §11's named gap — the checker currently only confirms `claude` resolves on PATH, not that login/auth succeeded)
- [ ] Decide install-step placement: end of Module 01 vs. a separate setup interlude (`docs/workshop-design.md` §7 row 01/§11)
- [ ] Decide whether the sandbox-safety `CLAUDE.md` and the learner's editable pack `CLAUDE.md` (Module 03) are the same file or two separate files (`docs/workshop-design.md` §8/§18)
- [ ] Decide Tier 2's completion contract: required-to-advance status, submission convention, model policy, disagreement/retry path (`docs/workshop-design.md` §7's named Design Principle 4/Tier-2 gaps)
- [ ] Build Deliverables & branding: module skeleton, brand layer, `docs/brand.md`, `docs/maintainers.md`, `docs/risks.md`
- [ ] Build the site skeleton (Astro, vocabulary-leak-safe placeholder for skeleton-only modules per the non-engineering variant's standing safeguard) — no deploy yet

## Later

- [ ] Live-verify every Claude Code product claim in `docs/workshop-design.md` before it reaches learner-facing copy: install/auth flow, permission-prompt behavior, web search/fetch availability, data-handling/retention policy, current OS/Windows support (§2, §4, §11, §12 all carry claims flagged not-yet-verified)
- [ ] Set up test machines for each target platform and a burner learner-grade Anthropic account for realistic cost/limit measurement
- [ ] Design the downloadable-workshop-folder packaging pipeline (no-git audience — never a `git clone`)
- [ ] Content-authoring pass (Coachgremlin, one module at a time): author, fresh-context DDD pass, cross-model adversarial review, Mock Learner Gremlin per module (manual orchestration preferred over Workflow-tool parallelization, per that gremlin's own documented reliability findings)
- [ ] Recruit and run at least one real human terminal-first-timer pilot before public launch — the only mechanism that can validate Module 01's on-ramp at all (`docs/workshop-design.md` §10)
- [ ] Deployment/DNS (agentic-infra-lab's `github-pages-dns` pattern) — explicitly deferred until real content exists
