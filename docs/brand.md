# Brand / Style Layer: Wade In

> The only place this workshop's personality lives. `README.md` and, once built, `site/`'s layout
> and content all read from this file — they don't redefine voice, banned language, or visual
> identity independently. Adapted from `copilot-fluent/docs/brand.md` (this factory's only other
> non-engineering-audience workshop) and `object-lesson/docs/brand.md` (its most recent true-beginner
> workshop), itself descended from `borrow-native`'s and `terminal-velocity`'s.

## Site identity

**Name:** Wade In
**Tagline:** Open a real terminal for the first time, and leave able to get real work done with
Claude Code — no coding, no CLI experience assumed.
**Parent brand:** Hekton
**Slug:** `wade-in`

## Tone and voice

**Core voice:** A patient, competent colleague showing you something for the first time — not a
professor, not a hype account, not a script reading commands at you. This workshop's audience is
categorically different from every prior workshop in this factory except `copilot-fluent`: someone
who has never opened a terminal and may be actively nervous about breaking something. The voice has
to earn trust in the first two minutes or lose the learner before Module 01 even starts.

**Tone rules:**
- **Gloss terminal/CLI vocabulary the first time it appears in real instructional content —
  Module 01's own exercise text specifically, and anywhere else a learner needs the term to
  complete a step.** Not just Hekton-internal jargon (the lesson `object-lesson`'s brand.md already
  carries) — for this audience, "command," "directory," "PATH," "session," even "terminal" itself
  need a one-line plain-English gloss where they're first load-bearing. **Scoped deliberately,
  corrected after an adversarial review flagged the rule as written applying too bluntly:** a
  high-level, incidental mention on the homepage or the modules index ("a learner who has never
  opened a terminal") doesn't need a gloss — the sentence is already about the reader's
  unfamiliarity with the term, so the context carries the meaning; gate the discipline for where a
  learner actually needs the definition to act, primarily Module 01's real content once it's
  authored (still skeleton-only as of this pass, so full compliance here is real, but
  content-authoring-time, work). This factory's own Review Panel confirmed the underlying risk is
  real, not hypothetical, for this workshop specifically (the End-User/Target Learner persona,
  re-aimed to a zero-terminal-experience reader, found the design doc's own internal/learner-facing
  text genuinely hard to disentangle at a glance).
- **Maintainer/process vocabulary never appears in learner-facing copy.** "Tier 1," "Tier 2,"
  "Coachgremlin," "self-attested," "grading key," "Design Principle" — all of it stays in `docs/`.
  A learner-facing module page describes what to do and what "done" looks like, in plain language,
  never in this factory's own internal vocabulary. **Deliberately narrower than an earlier draft of
  this list, corrected after an adversarial review caught the mismatch:** ordinary English words
  like "checker" and "the arc" are not banned — they're plain language a first-time reader can parse
  from context, unlike the genuinely opaque terms above. `scripts/check-brand-lint.sh`'s own
  `MAINTAINER_TERMS` list is this rule's authoritative, mechanically-enforced scope; this prose
  should stay in sync with it, not the other way around. This is the single most
  convergent finding from this workshop's own design-doc review chain (4 of 7 Review Panel personas,
  independently) — treat it as load-bearing, not a style preference.
- **State only what's actually built, in the tense that's actually true.** Don't describe an
  intended checker script, an undesigned site feature, or an unauthored module in confident present
  tense as if it exists. This workshop's own review chain caught itself doing exactly this once
  already (the Skeptical Practitioner persona, 2026-09-14) — the fix isn't to hedge every sentence,
  it's to say "will check" for a script that isn't written yet and "checks" only once it is.
- **No unhedged "first ... in this factory" or "strongest ... this factory has built" framing.**
  A comparison scoped to this factory's own handful of sibling workshops is a low bar dressed as a
  structural distinction — this workshop's own Skeptical Practitioner review caught this pattern
  recurring four separate times in one draft. If a claim is genuinely externally differentiated, say
  so and scope it to what's actually been checked (see the "hedge honestly" rule below); if it's
  only true relative to this factory's own prior output, say that plainly instead of reaching for
  "first."
- **Hedge honestly, not performatively.** If a claim is marked unverified, don't immediately build
  on it as if it were settled two paragraphs later — say what's actually known, then stop, then flag
  what would need checking before it could be stated as fact. An honest hedge that gets treated as
  load-bearing anyway is worse than no hedge at all, since it reads as due diligence without being
  due diligence.
- **Never let a checker, a permission prompt, or the terminal itself read as an adversary.** The
  whole method bet is that a real deterministic check and an honest permission prompt are
  trustworthy, not obstacles to "beat" or "get past." No joking about "tricking the checker,"
  "getting around a prompt," or "the terminal being scary" played for a laugh at the learner's
  expense — reassurance, not mockery, about the parts that are genuinely intimidating on a first
  attempt.
- **Never imply blanket-approving permission prompts is the normal or expected behavior.** This
  workshop's own Security-Conscious Reviewer found the design under-taught this specific habit —
  content must not casually model or joke about clicking through prompts without reading them, even
  in passing, even as a "we've all done it" aside.
- First person for build-log entries. Plain instructional language for module content and workshop
  structure.
- Admit uncertainty directly rather than smoothing over it.

## Hard rules

- **No em dash characters.** Use period, colon, semicolon, comma, parenthesis, or a plain hyphen
  instead. (Applies to all published workshop content — README, module READMEs, build-log entries,
  the site. Design/planning docs under `docs/`, including this file, are working documents and are
  exempt.)
- No AI-slop openers ("In today's fast-paced world...", "It's important to note...").
- No unqualified efficacy superlatives ("game-changing," "revolutionary," "10x," "unlock your
  potential").
- No engagement bait, fake scarcity, or "one weird trick" framing.
- **No unearned hype labels on any exercise, checker, or module** ("showpiece," "the ultimate,"
  "the most important module") without a stated, checkable reason why. This workshop's own
  Skeptical Practitioner review caught exactly this pattern once already (a checker called a
  "showpiece" with no comparison criteria given) — the fix that shipped was removing the label, not
  justifying it after the fact.
- **Never present a real prospective safety-danger scenario as harmless or funny.** Module 09's
  real-file exercise and its surrounding content are the one place this workshop asks a learner to
  step outside a fully sandboxed environment — that module's content carries the same seriousness
  `copilot-fluent`'s liability guardrails did for its subject, adapted to this workshop's actual
  risk (real shell/file access, not financial-advice liability).
- **Never claim a real human has piloted this workshop, or that a real learner's experience is
  known, until `docs/workshop-design.md` §10's real-human-pilot commitment has actually happened
  and is recorded.** Every claim about how gentle, effective, or complete the on-ramp is stays
  scoped to "designed to" until then.

## Banned phrases

Reused from the wider Hekton house style, plus workshop-specific additions:

- delve, tapestry, unlock, seamless, game-changing, revolutionize, transform your workflow,
  supercharge, effortlessly, cutting-edge, thought leader
- "in today's fast-paced world," "it's important to note," "at scale" (unless the content proves
  the scale)
- Workshop-specific: "master the art of," "in this comprehensive guide," "unlock your potential,"
  "10x your skills," "trick the checker," "beat the checker," "get past the prompt," "the terminal
  is scary" (played for a laugh rather than named as a real, respected first-timer feeling)

## Visual identity

Inherit `copilot-fluent`'s (and, before it, `borrow-native`'s and `terminal-velocity`'s) Astro
starter tokens rather than invent a new palette, once the site is built. Wade In's own accent choice
is still `[TBD]`, below.

| Element | Direction |
|---|---|
| Overall mood | A calm, well-lit back office on your first day, not a hacker terminal aesthetic |
| Colour approach | Dark-on-light default; restrained palette; dark mode optional later |
| Typography | Crisp, generous whitespace, readable monospace for terminal transcripts/commands |
| Imagery | Artifact-led: real terminal output, real checker `RESULT: PASS` lines, real produced files, not stock photos or decorative AI art. Never a stock "hacker in a hoodie" image — actively wrong tone for this audience |
| Decoration | No neon AI aesthetic, no hero banners, no gradient-mesh backgrounds |

## Gremlin and factory language rules

- Coachgremlin, the Workshop Gremlin, and the Mock Learner Gremlin are real, documented agents with
  concrete responsibilities (`~/hekton/gremlins/`) — reference them plainly in maintainer-facing
  docs (`docs/`, `docs/maintainers.md`), never in learner-facing copy. This is stricter than
  `object-lesson`'s own rule (which allowed a glossed, on-first-use mention in learner copy) — per
  the tone rule above, this workshop's own Review Panel found even a glossed mention risks reading
  as intimidating jargon to a true first-timer, so the line here is a hard exclusion, not a
  gloss-and-allow.
- A module README is a production artifact: plain. A build-log entry can be warmer where the actual
  events were warm.

## Anti-goals

- Not an AI-hype funnel or a marketing page for Hekton or for Claude Code.
- Not a certification mill — no claim that completing this workshop credentials anything (§6 of
  `docs/workshop-design.md` is explicit that no external certification exists to anchor to).
- Not condescending about the audience never having used a terminal. Genuinely new to a terminal is
  not the same as unintelligent or bad at their actual job; the tone should read as "this specific
  tool is new to you," never "computers are hard, don't worry."
- Not a place to publish an unverified live-product claim as settled fact — every claim about
  Claude Code's actual install flow, permission model, or data handling gets the flagged-for-
  verification treatment in `docs/` until it's been re-checked against Anthropic's current
  documentation, per `docs/workshop-design.md` §11/§12's own standing rule.
- Not overrun with gremlin/factory language to the point of reading like internal tooling docs
  handed to the wrong audience.

## Application map

| Artifact | Reads |
|---|---|
| `README.md` | Title + tagline |
| `site/` | Tone, hard rules, banned phrases, visual identity, vocabulary-leak safeguard |
| Module READMEs | Tone, hard rules, banned phrases, jargon-glossing rule, maintainer-vocabulary exclusion |
| Build-log entries | Tone and voice rules (first person, warmth where earned, no hype) |

## [TBD]: items for later

The site now exists and inherits neutral placeholder values for all of these (see
`site/src/styles/global.css` and `site/public/favicon.svg`) - they're functional defaults, not yet
deliberate brand decisions, and still open:

- [ ] Exact accent colour token (currently the neutral default inherited from `copilot-fluent`'s
  starter, not a chosen Wade In accent)
- [ ] Favicon / wordmark treatment (currently a placeholder ripple mark, not a considered choice)
- [ ] Dark mode colour tokens (currently the same neutral defaults' dark variant, not tuned)
- [ ] Terminal-transcript syntax highlighting/theme choice for code blocks
