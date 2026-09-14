// Module READMEs are authored as plain, GitHub-readable markdown and link to
// each other with relative paths that end in ".md" - e.g.
// "../02-meet-the-new-hire/README.md". Those links are correct on GitHub,
// but this site (the primary surface for a no-git learner audience) never
// serves a literal ".md" file: Astro's static build (see astro.config.mjs -
// default output: "static", no build.format override, which defaults to
// "directory") turns "modules/02-meet-the-new-hire/README.md" into the
// route "/modules/02-meet-the-new-hire/" (an index.html inside that
// directory). Left alone, every one of these links 404s on the live site.
//
// This remark plugin rewrites them at render time, in the markdown AST,
// rather than requiring every author to hand-write the site's URL shape (or
// GitHub's) into the same authored copy that starts every module's own
// content. Adapted directly from copilot-fluent's own RISK-0003 fix. It runs
// on whatever markdown Astro renders through the configured `markdown.
// remarkPlugins` (astro.config.mjs) - in this repo, that's every entry in
// the buildlog and modules content collections.
//
// Deliberately narrow, but the scope is by URL SHAPE, not by whether a route
// actually exists at the rewritten target - corrected here after an
// adversarial review caught the earlier comment overclaiming the opposite:
//   - Only touches links whose path ends in ".md" (optionally with a
//     "#fragment"). Non-".md" links (mailto:, anchors, GitHub URLs) pass
//     through untouched.
//   - Every OTHER relative ".md" link gets rewritten unconditionally,
//     including a link to a docs/ file this site never serves as its own
//     route (e.g. "../docs/workshop-design.md" would become
//     "../docs/workshop-design/", which 404s, same as the original
//     unrewritten link would have). The plugin does not check whether the
//     rewritten target actually exists - it can't, without duplicating this
//     site's own routing table. Known limitation, not currently live: as of
//     this comment, no module README or build-log entry links to a docs/
//     file, and modules/README.md itself (which does) is intentionally
//     excluded from the rendered `modules` collection (see
//     src/content/config.ts) - so nothing today exercises this gap. If a
//     future module links into docs/, that link needs its own real site
//     route or it will 404 regardless of what this plugin does to it.
//   - Only touches relative links. A URL with a scheme (http:, https:,
//     mailto:, etc.), including a scheme-relative URL ("//host/path"), is
//     left alone via the HAS_SCHEME check below - a bare "//" prefix isn't
//     actually matched by that check, a second, narrower known gap, harmless
//     today since no content uses scheme-relative links.
//   - "/README.md" (case-insensitive) becomes a trailing "/" - matching a
//     module's own directory-index route exactly (see
//     src/pages/modules/[...slug].astro's generateId, which strips the same
//     suffix). This also happens to make "../README.md" (a module linking
//     up to modules/README.md, the arc index) resolve to "/modules/" - the
//     modules index page - which is the closest real route to "the full
//     arc," even though that page is a hand-built listing rather than a
//     render of modules/README.md's own body.
//   - Any other ".md" path becomes the same path with the extension
//     stripped and a trailing "/" added.
export default function remarkRelativeMdLinks() {
  return (tree) => {
    walkLinks(tree, (node) => {
      node.url = rewriteUrl(node.url);
    });
  };
}

function walkLinks(node, visit) {
  if (node && node.type === "link" && typeof node.url === "string") {
    visit(node);
  }
  if (node && Array.isArray(node.children)) {
    for (const child of node.children) {
      walkLinks(child, visit);
    }
  }
}

const HAS_SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/; // http:, https:, mailto:, tel:, etc.
const ENDS_README_MD = /\/README\.md$/i;
const IS_BARE_README_MD = /^README\.md$/i;
const ENDS_MD = /\.md$/i;

function rewriteUrl(url) {
  if (!url || HAS_SCHEME.test(url)) return url;

  const hashIndex = url.indexOf("#");
  const path = hashIndex === -1 ? url : url.slice(0, hashIndex);
  const hash = hashIndex === -1 ? "" : url.slice(hashIndex);

  if (!ENDS_MD.test(path)) return url;

  let newPath;
  if (IS_BARE_README_MD.test(path)) {
    newPath = "./";
  } else if (ENDS_README_MD.test(path)) {
    newPath = path.replace(ENDS_README_MD, "/");
  } else {
    newPath = path.replace(ENDS_MD, "/");
  }

  return `${newPath}${hash}`;
}
