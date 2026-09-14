import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

// The build-log lives in docs/build-log/ at the repo root, not under src/. This is
// the maintainer's deliberate, dated journal - entries are written, not machine-
// generated from session logs. The glob loader reads it in place; nothing is
// duplicated into src/.
const buildlog = defineCollection({
  loader: glob({ pattern: "*.md", base: new URL("../../../docs/build-log", import.meta.url) }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    tags: z.array(z.string()).default([]),
    draft: z.boolean().default(false),
  }),
});

// The ten module READMEs, read in place from modules/ - the repo's own
// GitHub-facing directory structure, not duplicated into src/content/.
//
// This is the non-engineering-variant pattern established by copilot-fluent:
// a workshop site where learners read modules on the published site itself
// (a no-git audience), not just a maintainer build journal.
//
// Route-ID fix, load-bearing: Astro 5's glob loader's default ID generator
// only strips a trailing "/index" segment, not "/README" - left alone, every
// module's route would render at a URL like ".../01-.../readme" instead of a
// clean ".../01-.../". generateId strips the "/README.md" suffix explicitly
// so the id is just the module's own directory name.
//
// No frontmatter schema is imposed on these files - they're authored first as
// plain GitHub-readable markdown (see modules/*/README.md), and adding a YAML
// frontmatter block would make them uglier to read directly on GitHub, the
// primary place a maintainer edits them. The page route extracts the title
// from the file's own first heading via render()'s returned headings, not
// from frontmatter.
const modules = defineCollection({
  loader: glob({
    pattern: "*/README.md",
    base: new URL("../../../modules", import.meta.url),
    generateId: ({ entry }) => entry.replace(/\/README\.md$/i, ""),
  }),
  schema: z.object({}),
});

// No fixtures collection yet - no module has real fixtures authored yet (all
// ten are skeleton-only, see modules/README.md). Add a fixtures collection
// (mirroring copilot-fluent's own src/content/config.ts and its
// src/pages/modules/[...slug]/fixtures/[fixture].astro route) once the
// content-authoring pass gives at least one module a real fixtures/
// directory - don't build the route speculatively against nothing.

export const collections = { buildlog, modules };
