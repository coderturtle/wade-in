# Next Actions: Wade In

## Immediate

- [x] Define project brief — see `.hekton/project.yaml` idea field
- [x] Record first design decisions in `docs/decisions.md` — naming pass + full interview-confirmed scope now logged
- [x] Draft, adversarially critique, and reconcile `docs/workshop-design.md` (three-agent chain) — done 2026-09-14
- [x] Run the Workshop Review Panel (7-persona pass) against the reconciled `docs/workshop-design.md` — done 2026-09-14, findings folded into the design doc's §14 (Open design questions) and §15 (Revision Log) rather than a separate report file

## This Week

Design doc §14 items, in its own priority order:

- [ ] **Blocking for content authoring:** close the Module 01→02 authenticated-session gap — highest-confidence finding across both review passes (3 Review Panel personas + Codex). See `docs/workshop-design.md` §14 item 1, §11.
- [ ] Resolve the platform decision (macOS/Linux-first vs. dual-track vs. Windows-first) — the single largest unresolved design risk. §14 item 2, §11.
- [ ] Pin Tier 2's completion contract: required-to-advance status, submission convention, model policy, disagreement/retry path — cheap now, expensive to retrofit across ten checkers. §14 item 3.
- [ ] Decide whether each module's checker should also gate that module's own `my-pack/` contribution (the Design Principle 4 gap). §14 item 4.
- [ ] Decide whether the safety-instructing `CLAUDE.md` and Module 03's learner-editable `CLAUDE.md` are the same file or two. §14 item 5.
- [ ] Decide install-step placement: end of Module 01 vs. a separate setup interlude. §14 item 6.
- [ ] Decide whether the sandbox should also be enforced via Claude Code's own permission-mode/allowed-directory settings, not instruction alone. §14 item 7.
- [ ] Decide whether a permission-habituation counter-exercise should land earlier than Module 09. §14 item 8.
- [ ] Build Deliverables & branding: module skeleton, brand layer, `docs/brand.md`, `docs/maintainers.md`, `docs/risks.md`
- [ ] Build the site skeleton (Astro, vocabulary-leak-safe placeholder for skeleton-only modules per the non-engineering variant's standing safeguard) — no deploy yet

## Later

- [ ] Live-verify every Claude Code product claim in `docs/workshop-design.md` before it reaches learner-facing copy: install/auth flow, permission-prompt behavior, web search/fetch availability, data-handling/retention policy, current OS/Windows support (§2, §4, §11, §12 all carry claims flagged not-yet-verified)
- [ ] Set up test machines for each target platform and a burner learner-grade Anthropic account for realistic cost/limit measurement
- [ ] Design the downloadable-workshop-folder packaging pipeline (no-git audience — never a `git clone`)
- [ ] Content-authoring pass (Coachgremlin, one module at a time): author, fresh-context DDD pass, cross-model adversarial review, Mock Learner Gremlin per module (manual orchestration preferred over Workflow-tool parallelization, per that gremlin's own documented reliability findings)
- [ ] Recruit and run at least one real human terminal-first-timer pilot before public launch — the only mechanism that can validate Module 01's on-ramp at all (`docs/workshop-design.md` §10)
- [ ] Deployment/DNS (agentic-infra-lab's `github-pages-dns` pattern) — explicitly deferred until real content exists
