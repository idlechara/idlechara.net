#!/usr/bin/env node
// build-posts.js — reads entries/*.md → src/data/posts.json + copies images + fetches last.fm tracks

import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';

// Load config
const configPath = path.resolve(import.meta.dirname, '..', 'src', 'data', 'music.js');
let LASTFM_USERNAME = '';
let LASTFM_API_KEY = '';

try {
  const configContent = fs.readFileSync(configPath, 'utf8');
  const usernameMatch = configContent.match(/LASTFM_USERNAME\s*=\s*['"]([^'"]+)['"]/);
  const apiKeyMatch = configContent.match(/LASTFM_API_KEY\s*=\s*['"]([^'"]+)['"]/);
  if (usernameMatch) LASTFM_USERNAME = usernameMatch[1];
  if (apiKeyMatch) LASTFM_API_KEY = apiKeyMatch[1];
} catch (e) {
  console.warn('Could not load last.fm config');
}

const ROOT = path.resolve(import.meta.dirname, '..');
const ENTRIES_DIR = path.join(ROOT, 'entries');
const OUT_JSON = path.join(ROOT, 'src', 'data', 'posts.json');
const OUT_ABOUT = path.join(ROOT, 'src', 'data', 'about.html');
const PUBLIC_ASSETS = path.join(ROOT, 'public', 'assets', 'posts');

const SECTION_MAP = {
  blog: 'blog',
  dev: 'dev',
  translation: 'tl',
  yorokobe: 'yorokobe',
};

// copy a file, creating parent dirs as needed
function copyFile(src, dest) {
  if (!fs.existsSync(src)) return false;
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return true;
}

// copy a whole directory recursively
function copyDir(src, dest) {
  if (!fs.existsSync(src)) return;
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

function buildHtml(markdownBody, slug, entryDir) {
  // copy every referenced image from the entry directory into public/
  const destDir = path.join(PUBLIC_ASSETS, slug);
  const imagePaths = new Set();

  // collect image refs (markdown and raw HTML src=)
  for (const m of markdownBody.matchAll(/!\[.*?\]\((.+?)\)|src="(.+?)"/g)) {
    const ref = m[1] || m[2];
    if (ref && !ref.startsWith('http') && !ref.startsWith('/')) {
      imagePaths.add(ref);
    }
  }

  // copy images + subdirs
  for (const ref of imagePaths) {
    const srcPath = path.join(entryDir, ref);
    const destPath = path.join(destDir, ref);
    if (fs.existsSync(srcPath) && fs.statSync(srcPath).isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }

  // also copy any image-containing subdirectories sitting next to the .md file
  for (const entry of fs.readdirSync(entryDir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const subSrc = path.join(entryDir, entry.name);
      const subDest = path.join(destDir, entry.name);
      copyDir(subSrc, subDest);
    }
  }

  let html = marked.parse(markdownBody);

  // rewrite relative image src attributes (./foo or foo, not http:// or /)
  html = html.replace(
    /(src|href)="(?!https?:\/\/)(?!\/)(?!#)([^"]+\.(png|jpg|jpeg|gif|webp|svg))"/gi,
    (_, attr, ref) => {
      const normalized = ref.replace(/^\.\//, '');
      return `${attr}="./assets/posts/${slug}/${normalized}"`;
    }
  );

  // Strip the leading <h1> (post title is shown by PostPage separately)
  html = html.replace(/^<h1[^>]*>.*?<\/h1>\s*/i, '');

  // Convert <p> containing multiple <img> → post-gallery strip
  html = html.replace(/<p>((?:\s*<img[^>]+>\s*){2,})<\/p>/g, (_, imgs) => {
    const figures = [];
    for (const m of imgs.matchAll(/<img([^>]+)>/g)) {
      const alt = (m[1].match(/alt="([^"]*)"/) || [])[1] || '';
      figures.push(`<figure><div class="gallery-img-wrap">${'<img' + m[1] + '>'}</div>${alt ? `<figcaption>${alt}</figcaption>` : ''}</figure>`);
    }
    return `<div class="post-gallery">${figures.join('')}</div>`;
  });

  // Convert <p> with a single <img> → post-figure (centered, with caption)
  html = html.replace(/<p>\s*(<img[^>]+>)\s*<\/p>/g, (_, img) => {
    const alt = (img.match(/alt="([^"]*)"/) || [])[1] || '';
    return `<figure class="post-figure">${img}${alt ? `<figcaption>${alt}</figcaption>` : ''}</figure>`;
  });

  return html;
}

function processSection(sectionDir, sectionKey) {
  const posts = [];
  if (!fs.existsSync(sectionDir)) return posts;

  for (const file of fs.readdirSync(sectionDir)) {
    if (!file.endsWith('.md')) continue;

    const filePath = path.join(sectionDir, file);
    const raw = fs.readFileSync(filePath, 'utf8');

    // strip the old kuni comment-style date if present before parsing
    const cleaned = raw.replace(/^\[\/\/\]: # \(.+?\)\n/, '');
    const { data: fm, content } = matter(cleaned);

    if (!fm.title) {
      console.warn(`  [skip] ${file} — no frontmatter title`);
      continue;
    }

    if (fm.hidden) {
      console.log(`  [skip] ${file} — marked as hidden`);
      continue;
    }

    // slug: prefer explicit fm.slug, else strip .md (handles double .md.md)
    const slug = fm.slug || path.basename(file).replace(/\.md$/, '').replace(/\.md$/, '');

    const section = fm.section || sectionKey;
    const tag = fm.tag || section;

    const entryDir = path.dirname(filePath);
    const body = buildHtml(content, slug, entryDir);

    posts.push({
      slug,
      section,
      tag,
      date: fm.date || '',
      title: fm.title,
      excerpt: fm.excerpt || '',
      body,
    });

    console.log(`  [ok] ${slug} (${section})`);
  }

  return posts;
}

function processAbout() {
  const aboutPath = path.join(ENTRIES_DIR, 'about.md');
  if (!fs.existsSync(aboutPath)) return;
  const raw = fs.readFileSync(aboutPath, 'utf8');
  const cleaned = raw.replace(/^\[\/\/\]: # \(.+?\)\n/, '');
  const { content } = matter(cleaned);
  // strip the leading h1 (the design has its own heading)
  const body = content.replace(/^#[^#].*\n/, '');
  fs.writeFileSync(OUT_ABOUT, marked.parse(body), 'utf8');
  console.log('  [ok] about.html');
}

async function fetchWithRetry(url, maxRetries = 3) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      });

      // Retry on 600 errors (Nginx errors)
      if (res.status === 600 && attempt < maxRetries - 1) {
        // Exponential backoff with jitter: 2^attempt * 1000ms + random jitter
        const baseDelay = Math.pow(2, attempt) * 1000;
        const jitter = Math.random() * 1000;
        const delay = baseDelay + jitter;
        console.log(`  [retry] last.fm returned 600, waiting ${Math.round(delay)}ms before retry ${attempt + 1}/${maxRetries - 1}`);
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }

      return res;
    } catch (e) {
      if (attempt < maxRetries - 1) {
        const baseDelay = Math.pow(2, attempt) * 1000;
        const jitter = Math.random() * 1000;
        const delay = baseDelay + jitter;
        console.log(`  [retry] fetch failed, waiting ${Math.round(delay)}ms before retry ${attempt + 1}/${maxRetries - 1}`);
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      throw e;
    }
  }
}

async function buildNowPlaying() {
  if (process.env.SKIP_LASTFM) {
    console.log('Skipping last.fm fetch — SKIP_LASTFM set');
    return;
  }
  if (!LASTFM_USERNAME) {
    console.log('Skipping last.fm fetch — no username configured');
    return;
  }

  try {
    const url = `https://www.last.fm/user/${LASTFM_USERNAME}`;
    console.log(`Fetching last.fm tracks for ${LASTFM_USERNAME}...`);
    const res = await fetchWithRetry(url);

    if (!res.ok) {
      console.warn(`  [warn] last.fm returned ${res.status}`);
      return;
    }

    const html = await res.text();

    const tracks = [];
    const seen = new Set();

    // Split HTML by chartlist rows and process each one
    const rowPattern = /<tr[^>]*class="[^"]*chartlist-row[^"]*"[^>]*>[\s\S]*?<\/tr>/g;
    let rowMatch;

    while ((rowMatch = rowPattern.exec(html)) !== null && tracks.length < 50) {
      const rowHtml = rowMatch[0];

      // Extract image from this row
      const imgMatch = rowHtml.match(/src="([^"]*lastfm[^"]*\/i\/u\/(?:34s|64s|174s|226s)\/[^"]+?)"/);
      const image = imgMatch ? imgMatch[1] : '';

      // Timestamp: prefer the unix epoch on the <tr data-timestamp="..."> itself,
      // fall back to the chartlist-timestamp <span title="..."> human-readable form.
      const epochMatch = rowHtml.match(/data-timestamp="(\d+)"/);
      const titleMatch = rowHtml.match(/chartlist-timestamp[\s\S]*?<span\s+title="([^"]+)"/);
      let timestamp;
      if (epochMatch) {
        timestamp = new Date(Number(epochMatch[1]) * 1000).toISOString();
      } else if (titleMatch) {
        timestamp = titleMatch[1];
      } else {
        timestamp = '';
      }

      // Extract track info - handle multi-line href attributes
      // Match: href="/music/{artist}/_/{track}" with possible newlines/spaces between attributes
      const trackMatch = rowHtml.match(/href="([^"]*?\/music\/([^"]+?)\/_\/([^"]+?))"[\s\S]*?title="([^"]*)"[\s\S]*?<\/a>/);

      if (trackMatch) {
        const fullUrl = trackMatch[1];
        const artist = decodeURIComponent(trackMatch[2]);
        const trackFromUrl = decodeURIComponent(trackMatch[3]);
        const trackName = trackMatch[4] || trackFromUrl;

        const key = `${artist}|${trackName}`;
        if (!seen.has(key)) {
          seen.add(key);
          tracks.push({
            name: trackName,
            artist: artist,
            url: fullUrl.startsWith('http') ? fullUrl : `https://www.last.fm${fullUrl}`,
            image: image,
            timestamp: timestamp,
          });
        }
      }
    }

    if (tracks.length > 0) {
      const publicPath = path.join(ROOT, 'public', 'nowplaying.json');
      fs.writeFileSync(publicPath, JSON.stringify(tracks, null, 2), 'utf8');
      console.log(`  [ok] fetched ${tracks.length} tracks from last.fm`);
    } else {
      // Loud warning: scraping is structurally fragile. If this fires repeatedly,
      // last.fm changed their markup and rowPattern / track regex needs updating.
      console.warn('  [WARN] last.fm scrape returned 0 tracks — HTML structure may have changed');
      console.warn('         existing public/nowplaying.json (if any) is preserved');
    }
  } catch (e) {
    console.warn('  [WARN] last.fm scrape failed:', e.message);
    console.warn('         existing public/nowplaying.json (if any) is preserved');
  }
}

async function main() {
  console.log('Building posts...');
  fs.mkdirSync(path.dirname(OUT_JSON), { recursive: true });
  fs.mkdirSync(PUBLIC_ASSETS, { recursive: true });

  const allPosts = [];
  for (const [dir, key] of Object.entries(SECTION_MAP)) {
    console.log(`\nSection: ${dir}`);
    allPosts.push(...processSection(path.join(ENTRIES_DIR, dir), key));
  }

  // sort descending by date
  allPosts.sort((a, b) => new Date(b.date) - new Date(a.date));

  fs.writeFileSync(OUT_JSON, JSON.stringify(allPosts, null, 2), 'utf8');
  console.log(`\nWrote ${allPosts.length} posts → src/data/posts.json`);

  console.log('\nBuilding about page...');
  processAbout();

  console.log('\nFetching now playing...');
  await buildNowPlaying();

  console.log('\nDone.');
}

main().catch(err => {
  console.error('Build failed:', err);
  process.exit(1);
});
