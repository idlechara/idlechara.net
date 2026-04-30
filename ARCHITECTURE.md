# Architecture

Technical reference for `idlechara.moe`. Pairs with the high-level overview in `README.md`.

## Stack

- **Vite 5** + **React 18** (no TypeScript, no JSX framework — plain JS modules).
- Build-time only: `marked` (Markdown → HTML), `gray-matter` (frontmatter parsing).
- Hash-based SPA routing (no router library).
- Static deploy to GitHub Pages via `.github/workflows/deploy.yml`.

## Build pipeline

`scripts/build-posts.js` runs before every `vite` invocation (see `package.json`: `dev` and `build` both prepend `node scripts/build-posts.js`). It performs four jobs:

### 1. Markdown ingestion (`processSection`)

For every directory in `SECTION_MAP`:

| Source dir | Section key |
|------------|-------------|
| `entries/blog`        | `blog`     |
| `entries/dev`         | `dev`      |
| `entries/translation` | `tl`       |
| `entries/yorokobe`    | `yorokobe` |

Each `.md` file is read, frontmatter is parsed, and the body is converted to HTML by `buildHtml`. Posts with no `title` are skipped with a warning. Posts with `hidden: true` are skipped silently (used for unlisted entries reachable only by direct slug).

The slug is `fm.slug` if provided, otherwise the filename minus `.md` (the regex runs twice to defensively handle accidental `.md.md`).

Output: `src/data/posts.json`, sorted by `date` descending.

### 2. Image handling (`buildHtml`)

Two passes copy images to `public/assets/posts/{slug}/`:

1. Scans the markdown body with `/!\[.*?\]\((.+?)\)|src="(.+?)"/g` for relative refs (skips `http`/absolute) and copies each.
2. Recursively copies any subdirectory next to the `.md` file — covers galleries that aren't directly referenced in the body.

After `marked.parse`, a regex rewrites every relative `src=` / `href=` (excluding `http://`, `/`, `#`) ending in an image extension to `./assets/posts/{slug}/...`.

### 3. HTML transformations (`buildHtml`, post-`marked`)

Run in this order:

1. **Strip leading H1** — post titles render in `PostPage` separately, so the in-body H1 would duplicate.
2. **Multi-image paragraphs** → `<div class="post-gallery">` with one `<figure>` per image. Each gets a `gallery-img-wrap` container; alt text becomes a `<figcaption>`. Triggered when `<p>` contains 2+ `<img>`.
3. **Single-image paragraphs** → `<figure class="post-figure">` (centered, captioned).

The order matters: the gallery rule must run before the single-image rule, otherwise a single-image paragraph inside a gallery would get rewrapped.

### 4. About page (`processAbout`)

`entries/about.md` → `src/data/about.html`. Frontmatter is stripped, leading `# heading` is removed (the page provides its own), then `marked.parse` produces raw HTML imported by `AboutPage.jsx`.

### 5. Last.fm scraping (`buildNowPlaying`)

Server-side scrape of `https://www.last.fm/user/{LASTFM_USERNAME}` — **no API key**, just HTML parsing. Driven by `LASTFM_USERNAME` in `src/data/music.js`.

**Why scraping instead of API?** A deliberate decision: avoid storing keys in the public repo and avoid rate limits on a tiny build job.

The flow:

1. `fetchWithRetry` hits the user page with a desktop UA. On HTTP 600 (Nginx upstream errors, common from last.fm) or network failure, it retries up to 3× with exponential backoff + jitter (`2^attempt * 1000ms + random*1000ms`).
2. The HTML is split into `<tr class="...chartlist-row...">` blocks. Up to 50 rows are parsed.
3. Per row, four pieces are extracted:
   - **Album art** — first `lastfm/i/u/{34s|64s|174s|226s}/...` URL.
   - **Timestamp** — `data-date-time="..."` or fallback `abbr title="..."`. If neither, defaults to "now".
   - **Track + artist** — multi-line regex on `href="...music/{artist}/_/{track}"` followed by `title="..."`. Artist/track are URL-decoded; the `title` attribute provides the human-readable track name.
   - **Deduplication** — `artist|track` key in a `Set` skips repeats.
4. Output: `public/nowplaying.json` — array of `{ name, artist, url, image, timestamp }`.

If the username is empty or the fetch fails, the file is simply not written and the front-end widget hides itself.

## Front-end

### Entry point

`src/main.jsx` mounts `<App />` into `#root`. `App.jsx` composes the static layout (TitleBar + Sidebar + main + Footer), the global effects (StarField, ClickSparkles, Lightbox), the Tweaks panel, and dispatches the current page via `<Router>`.

### Routing (`src/hooks/useRouter.jsx`)

Hash-based, parsed as `#/{page}/{slug}`:

- `#/` or empty → `{ page: 'home', slug: null }`
- `#/blog` → `{ page: 'blog', slug: null }`
- `#/dev/timecapsule` → `{ page: 'dev', slug: 'timecapsule' }`

`go(page, slug?)` updates `location.hash` and smooth-scrolls to top. The hook listens for `hashchange` events so back/forward buttons work.

### Router dispatch (`src/pages/Router.jsx`)

Priority order:

1. If `route.slug` is set → `<PostPage>` (regardless of section).
2. Otherwise switch on `route.page`:
   - `home` → `<HomePage>`
   - `blog | tl | dev | yorokobe` → `<BlogListPage>` for that section
   - `links` → `<LinksPage>`
   - `about` → `<AboutPage>`
   - default → `<HomePage>`

`yorokobe` is intentionally not in the `NAV` array (`src/data/sections.js`) — it's reachable only via the `<YorokobeShōnenCard>` in the sidebar (currently `display:none`) or by direct URL.

### Pages

| File | Renders |
|------|---------|
| `HomePage.jsx`    | Hero greeting, NowListening + WebRing + VisitCounter widgets, auto-computed marquee, three most recent posts |
| `BlogListPage.jsx`| Section header + filtered post cards |
| `PostPage.jsx`    | Single post body (raw HTML from `posts.json`) |
| `LinksPage.jsx`   | Renders `LINK_GROUPS` from `src/data/links.js` |
| `AboutPage.jsx`   | Imports `src/data/about.html` (build-generated) |

`HomePage.getHomeMarquee()` derives marquee text from `posts.json` at module load: most recent post's date, plus titles of latest `tl` and `blog` entries.

### Components

| File | Purpose |
|------|---------|
| `TitleBar.jsx`      | Top header strip |
| `Sidebar.jsx`       | `NavMenu` (active-page-aware) + `ProfileCard`/`GuestbookCard`/`YorokobeShōnenCard` (currently hidden via `display:none` rather than removed, so they remain in the source for future use) |
| `BlogEntry.jsx`     | Post card list |
| `Marquee.jsx`       | Scrolling text strip |
| `Widgets.jsx`       | `NowListening` (last.fm carousel), `WebRing`, `VisitCounter` |
| `Footer.jsx`        | Bottom strip |
| `TweaksPanel.jsx`   | Floating settings panel + reusable `TweakSlider`/`TweakToggle`/`TweakSelect`/`TweakSection` controls + `useTweaks` hook |

#### NowListening carousel

State: `tracks[]` loaded from `/nowplaying.json` on mount, `currentIndex` advances every 5s via `setInterval`. Auto-hides if `LASTFM_USERNAME` is empty or no tracks were fetched.

UI: prev/next chevron buttons, album art (48×48), track name + artist + counter + formatted timestamp. Clicking the artwork or the text block opens the track's last.fm URL in a new tab.

### Effects (`src/effects/`)

| File | Behavior |
|------|----------|
| `StarField.jsx`     | Background animated stars. Count, drift speed, size, palette controlled by Tweaks panel. |
| `ClickSparkles.jsx` | Spawns small particle burst on every document click. Toggleable. |
| `Lightbox.jsx`      | Global click handler — any `<img>` inside `.post-gallery` opens in a fullscreen overlay with a "poof" close animation. |

### Tweaks system

`useTweaks(defaults)` returns `[values, setTweak]`. `setTweak` accepts either `(key, value)` or a partial object for batched updates. State is in-memory only (not persisted) — refreshes reset to defaults defined in `App.jsx`.

The panel is draggable (header `mousedown`), bounded to viewport with a 16px margin, and styled via injected `<style>` tag rather than CSS classes in `style.css`.

## Data files (`src/data/`)

| File | Type | Source |
|------|------|--------|
| `posts.json`   | Generated | `scripts/build-posts.js` (gitignored) |
| `about.html`   | Generated | `scripts/build-posts.js` (gitignored) |
| `sections.js`  | Hand-written | `NAV` array + `SECTIONS` lookup (titles, subtitles) |
| `links.js`     | Hand-written | `LINK_GROUPS` for `LinksPage` |
| `palettes.js`  | Hand-written | Color themes for `StarField` and Tweaks select |
| `webring.js`   | Hand-written | `WEBRING_SITES` array for `WebRing` widget |
| `music.js`     | Hand-written | `LASTFM_USERNAME` (build-time only) |

## Conventions

- **No comments unless WHY is non-obvious.** Names carry intent.
- **Hide, don't delete.** Components like `ProfileCard`, `WebRing`, `VisitCounter` use `style={{ display: 'none' }}` instead of `return null`, preserving them as ready-to-revive features.
- **Generated files are gitignored** — `posts.json`, `about.html`, `nowplaying.json` are rebuilt on every `npm run dev` / `npm run build`.
- **Frontmatter is the source of truth** for post metadata. Date, slug, section, hidden state all live there, not in code.

## Caveats and design notes

- **Last.fm scraping is structurally fragile.** `buildNowPlaying` extracts `data-timestamp` (Unix epoch on `<tr>`) with a `chartlist-timestamp <span title="...">` fallback, plus image and track regexes. If last.fm changes markup, the build emits a loud `[WARN] last.fm scrape returned 0 tracks` and preserves the previous `public/nowplaying.json` rather than overwriting it with an empty file. The build is intentionally non-fatal — deploys never fail because of last.fm.
- **Offline dev:** use `npm run dev:offline` (sets `SKIP_LASTFM=1`) to skip the scrape. The previous `nowplaying.json` is preserved.
- **Tweaks state** persists to `localStorage` under `idlechara.tweaks`. Clear the key (or use a private window) to reset.
- **Post bodies render via `dangerouslySetInnerHTML`.** Acceptable because content comes from your own markdown — do not pipe untrusted input through this path.

## Dev container

A reproducible Node 20 environment lives in `.devcontainer/`. See `.devcontainer/README.md` for VS Code, Codespaces, and plain-Docker usage.

## Deployment

`.github/workflows/deploy.yml` on push to `main`:

1. `npm ci`
2. `npm run build` (runs `build-posts.js`, then `vite build`)
3. Publishes `dist/` to GitHub Pages

The last.fm scrape runs as part of `build-posts.js` during deploy — `nowplaying.json` is baked into the static site at build time, not fetched by the browser at runtime.
