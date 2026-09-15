# Wade In

> Open a real terminal for the first time, and leave able to get real work done with Claude Code - no coding, no CLI experience assumed.

Wade In is a self-paced, public workshop being built to teach non-technical knowledge workers, who have never used a terminal, to use the real Claude Code CLI for research, document drafting, spreadsheet-adjacent tasks, and light file-based automation. The plan: every exercise will run inside a workshop-provided sandbox on your own machine, checked by a real deterministic script, with an AI-graded pass covering the judgment calls a mechanical check can't. That's the design this repo is building toward, not something you can try yet - see Status below.

**Status:** Modules 01-09 have real, authored content and working checker scripts. Module 10 (the capstone) is design and skeleton only, authored last since it draws on the others. Not fully ready to start yet - none of this content is merged to `main` yet, and it hasn't had a real human pilot. Watch this repo.

## The arc

Ten modules, starting from zero: a terminal-literacy module (what a command even is) before Claude Code ever enters the picture, then a steady ramp through prompting, file editing, running scripts safely, web research, document drafting, spreadsheet-shaped cleanup, and automation, then a module on doing all of this safely on your own real files, then a synthesis capstone. Full reasoning for the order, the scenario, and the gate design is in [Workshop Design](docs/workshop-design.md); the per-module breakdown and current skeleton status is in [Modules](modules/README.md).

## Quick Start

There's nothing to run yet - no module has real exercise content, and no downloadable workshop folder exists. Watch this repo's [build log](https://coderturtle.github.io/wade-in/build-log/) or the [modules index](modules/README.md) for progress.

## Build in public

This workshop's own build is published as a dated journal at [coderturtle.github.io/wade-in](https://coderturtle.github.io/wade-in/) once the site exists and the first deploy is triggered - the maintainer's record of building the workshop and its reusable Gremlin tooling at the same time, written deliberately rather than auto-generated from session logs.

## Key Docs

- [Workshop Design](docs/workshop-design.md): the audience, the two-tier deterministic-checker gate method, the scenario, and every named open design question
- [Modules](modules/README.md): all ten modules, gate tiers, and current skeleton status
- [Brand](docs/brand.md): voice, hard rules, and visual identity for published content
- [Next Actions](docs/next-actions.md): what's being worked on now
- [Maintainers](docs/maintainers.md): internal/agent-facing notes (classification, documentation contract, review-panel reports)
