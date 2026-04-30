# Dev Container

Reproducible development environment for `idlechara.moe`.

## What's inside

- **Base image:** `mcr.microsoft.com/devcontainers/javascript-node:20-bookworm` (Node 20 LTS on Debian Bookworm)
- **Extras:** GitHub CLI (`gh`)
- **Forwarded ports:** `5173` (Vite dev), `4173` (Vite preview)
- **Volume mount:** `node_modules` is stored in a named Docker volume so installs are fast on rebuild
- **VS Code extensions:** ESLint, Prettier, Markdown All in One, GitHub Actions, GitLens

## Usage

### VS Code / Cursor

1. Install the **Dev Containers** extension (`ms-vscode-remote.remote-containers`).
2. Open the repo, run **Dev Containers: Reopen in Container** from the command palette.
3. First build runs `npm install`. Subsequent opens reuse the cached volume.
4. Run `npm run dev` — Vite is auto-forwarded; the preview opens in a new tab.

### GitHub Codespaces

The container config is detected automatically. Click **Code → Codespaces → Create codespace on `main`** on GitHub. Same `npm run dev` flow.

### Plain Docker (no VS Code)

```sh
docker run --rm -it \
  -v "$PWD:/workspaces/idlechara.moe" \
  -w /workspaces/idlechara.moe \
  -p 5173:5173 \
  mcr.microsoft.com/devcontainers/javascript-node:20-bookworm \
  bash -lc "npm install && npm run dev -- --host 0.0.0.0"
```

## Notes

- `npm run dev` runs `scripts/build-posts.js` first, which scrapes `last.fm`. If you're offline, the scrape will fail silently and `nowplaying.json` won't be regenerated — the rest of the build still works.
- Generated files (`src/data/posts.json`, `src/data/about.html`, `public/nowplaying.json`, `public/assets/posts/`) are gitignored and rebuilt on every dev start.
- The `node_modules` volume is named `idlechara-node-modules` — delete it via `docker volume rm idlechara-node-modules` if you need a clean reinstall.
