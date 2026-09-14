// @ts-check
import { defineConfig } from "astro/config";
import mdx from "@astrojs/mdx";
import tailwind from "@astrojs/tailwind";
import remarkRelativeMdLinks from "./src/plugins/remark-relative-md-links.mjs";

// https://astro.build/config
export default defineConfig({
  // Custom domain (wade-in.coderturtle.io) via GitHub Pages + Route53 CNAME,
  // per agentic-infra-lab's patterns/github-pages-dns - the current
  // factory-wide convention (every prior workshop site uses base: "/" on a
  // <slug>.coderturtle.io domain, not GitHub Pages' project-path default).
  // DNS is not live - deployment/DNS is deliberately deferred until real
  // content exists, per docs/workshop-design.md's own status line.
  // Every internal link MUST still be base-aware (import.meta.env.BASE_URL),
  // not a bare "/path", so the site stays portable if that ever changes.
  site: "https://wade-in.coderturtle.io",
  base: "/",
  integrations: [mdx(), tailwind()],
  output: "static",
  // Module READMEs are authored as plain GitHub-readable markdown and link
  // to each other with relative ".md" paths (e.g.
  // "../02-meet-the-new-hire/README.md") that are correct on GitHub but have
  // no matching route on this static site. remarkRelativeMdLinks rewrites
  // those links, in the markdown AST, to the site's own directory-index URL
  // shape at render time - see src/plugins/remark-relative-md-links.mjs.
  // Adapted directly from copilot-fluent's own RISK-0003 fix. `markdown.
  // remarkPlugins` runs for every markdown file Astro renders, including
  // every content collection entry (buildlog, modules - see
  // src/content/config.ts), not just .md pages under src/pages/.
  markdown: {
    remarkPlugins: [remarkRelativeMdLinks],
  },
});
