# idlechara.moe

Personal blog with a 90s pastel vibe. Vite + React (plain JS) + markdown. Hosted on GitHub Pages.

## Architecture

```
entries/blog/*.md          ─┐
entries/dev/*.md            ├──> scripts/build-posts.js ──> src/data/posts.json ──> Vite ──> dist/
entries/translation/*.md   ─┘
entries/about.md                                      ──> src/data/about.html
entries/dev/images/                                   ──> public/assets/posts/{slug}/
```

Build script reads markdown → generates JSON + copies images. Vite bundles React and deploys to GitHub Pages.

## Local development

```sh
npm install
npm run dev      # prebuild (build-posts.js) + start Vite at localhost:5173
```

`npm run dev` regenerates `src/data/posts.json` and `src/data/about.html` on every start (both gitignored).

## Writing a post

Create a file in `entries/blog/`, `entries/dev/`, or `entries/translation/`. Add frontmatter:

```yaml
---
title: Post Title
date: Tue Apr 29 2025
tag: dev          # dev | life | tl
excerpt: One-sentence summary for the card.
---

Markdown body starts here.
```

**Optional frontmatter:**
- `slug` — override filename-derived slug
- `section` — override directory-derived section (`translation/` → `tl` by default)

**Images:**
- Put them next to the `.md` or in a subdirectory
- Reference as `./image.jpg` in markdown
- Build script copies to `public/assets/posts/{slug}/` and rewrites paths

**Image rendering:**
- Single image in a paragraph → `<figure class="post-figure">` (centered, captioned by alt text)
- Multiple images in one paragraph → `<div class="post-gallery">` masonry (each image clickable, opens in lightbox)

## Editing about page

Edit `entries/about.md`. Leading `# heading` is stripped (design has its own heading). No frontmatter needed.

## Editing links

Edit `src/data/links.js`. Exports `LINK_GROUPS`:
```js
export const LINK_GROUPS = [
  { title: 'Section Name', links: [
    { label: 'Link text', url: 'https://example.com', desc: 'Optional description' },
  ] },
];
```

## Deployment

Push to `main`. GitHub Actions (`.github/workflows/deploy.yml`) runs `npm ci && npm run build` and deploys `dist/` automatically.

Local build: `npm run build` → check `dist/`.

## Changing the look

- **Colors / fonts:** `src/style.css` (CSS custom properties at `:root`)
- **Color themes:** `src/data/palettes.js` (visitor-togglable via ⚙ panel)
- **Background stars:** `src/effects/StarField.jsx`
- **Click sparkles:** `src/effects/ClickSparkles.jsx`
- **Image lightbox + poof animation:** `src/effects/Lightbox.jsx`
- **Layout / structure:** `src/components/` and `src/pages/`

## Project structure

```
entries/           Source posts (markdown + images)
scripts/
  build-posts.js   Markdown → JSON pipeline
src/
  App.jsx          Root component
  main.jsx         React mount
  style.css        All styles
  data/            Static data (sections, links, palettes) + generated JSON/HTML
  hooks/useRouter.jsx
  effects/         StarField, ClickSparkles, Lightbox
  components/      TitleBar, Sidebar, BlogEntry, Marquee, Widgets, Footer, TweaksPanel
  pages/           Router, HomePage, BlogListPage, PostPage, LinksPage, AboutPage
public/            Static assets + generated post images
.github/workflows/ CI/CD to GitHub Pages
```

## Stack

Vite · React 18 · `marked` + `gray-matter` (build-time only) · hash-based SPA routing · GitHub Pages
