#!/usr/bin/env node
// build-posts.js — reads entries/*.md → src/data/posts.json + copies images

import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';

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

console.log('\nDone.');
