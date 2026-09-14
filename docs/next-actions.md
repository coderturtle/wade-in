# Next Actions: Wade In

## Immediate

- [x] Define project brief — see `.hekton/project.yaml` idea field
- [x] Record first design decisions in `docs/decisions.md` — naming pass + full interview-confirmed scope now logged
- [x] Draft, adversarially critique, and reconcile `docs/workshop-design.md` (three-agent chain) — done 2026-09-14
- [x] Run the Workshop Review Panel (7-persona pass) against the reconciled `docs/workshop-design.md` — done 2026-09-14, full report at `docs/review-panel/2026-09-14-initial-design.md`, findings applied to `docs/workshop-design.md` §14/§15
- [x] Deliverables & branding: 10-module skeleton (`modules/`), brand layer (`docs/brand.md`, `docs/maintainers.md`, `docs/risks.md` populated), `scripts/check-brand-lint.sh` written and passing clean, wired into the pre-push hook — done 2026-09-14

## This Week

Design doc §14 items, in its own priority order — all block real module content, not the site skeleton:

- [ ] **Blocking for content authoring:** close the Module 01→02 authenticated-session gap — highest-confidence finding across both review passes (3 Review Panel personas + Codex). See `docs/workshop-design.md` §14 item 1, §11, `docs/risks.md` RISK-0002.
- [ ] Resolve the platform decision (macOS/Linux-first vs. dual-track vs. Windows-first) — the single largest unresolved design risk. §14 item 2, §11, RISK-0003.
- [ ] Pin Tier 2's completion contract: required-to-advance status, submission convention, model policy, disagreement/retry path — cheap now, expensive to retrofit across ten checkers. §14 item 3, RISK-0005.
- [ ] Decide whether each module's checker should also gate that module's own `my-pack/` contribution (the Design Principle 4 gap). §14 item 4.
- [ ] Decide whether the safety-instructing `CLAUDE.md` and Module 03's learner-editable `CLAUDE.md` are the same file or two. §14 item 5.
- [ ] Decide install-step placement: end of Module 01 vs. a separate setup interlude. §14 item 6.
- [ ] Decide whether the sandbox should also be enforced via Claude Code's own permission-mode/allowed-directory settings, not instruction alone. §14 item 7.
- [ ] Decide whether a permission-habituation counter-exercise should land earlier than Module 09. §14 item 8.
- [ ] Build the site skeleton (Astro, vocabulary-leak-safe placeholder for skeleton-only modules per the non-engineering variant's standing safeguard) — no deploy yet
- [ ] Cross-workshop: fix `scaffold-project.sh`'s default `.gitignore` so `scripts/setup-hooks.sh`/`scripts/check-mirror-drift.sh` aren't ignored by default in public-capable repos — same bug `object-lesson` found and worked around 2026-08-17, worked around again here 2026-09-14 (`docs/decisions.md`, `docs/risks.md` RISK-0008), still not fixed upstream

## Later

- [ ] Live-verify every Claude Code product claim in `docs/workshop-design.md` before it reaches learner-facing copy: install/auth flow, permission-prompt behavior, web search/fetch availability, data-handling/retention policy, current OS/Windows support (§2, §4, §11, §12 all carry claims flagged not-yet-verified)
- [ ] Set up test machines for each target platform and a burner learner-grade Anthropic account for realistic cost/limit measurement
- [ ] Design the downloadable-workshop-folder packaging pipeline (no-git audience — never a `git clone`)
- [ ] Content-authoring pass (Coachgremlin, one module at a time): author, fresh-context DDD pass, cross-model adversarial review, Mock Learner Gremlin per module (manual orchestration preferred over Workflow-tool parallelization, per that gremlin's own documented reliability findings)
- [ ] Recruit and run at least one real human terminal-first-timer pilot before public launch — the only mechanism that can validate Module 01's on-ramp at all (`docs/workshop-design.md` §10)
- [ ] Deployment/DNS (agentic-infra-lab's `github-pages-dns` pattern) — explicitly deferred until real content exists
