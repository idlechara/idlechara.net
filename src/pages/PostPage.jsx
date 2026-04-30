import { SECTIONS } from '../data/sections.js';
import posts from '../data/posts.json';

export function PostPage({ section, slug, go }) {
  const post = posts.find((p) => p.slug === slug);
  if (!post) {
    return (
      <div className="content-card">
        <h1>404 — lost in the stars</h1>
        <p>this post drifted away. <a onClick={() => go(section)} style={{ cursor: 'pointer' }}>← go back</a></p>
      </div>
    );
  }
  return (
    <div className="content-card">
      <span className="post-back" onClick={() => go(SECTIONS[section] ? section : 'home')}>
        ← back to {SECTIONS[section]?.title || 'home'}
      </span>
      <h1>{post.title}</h1>
      <div className="post-meta">
        {post.date && <span>📅 {post.date}</span>}
        <span className={`tag ${post.tag}`}>{post.tag}</span>
      </div>
      <hr />
      <div className="post-body" dangerouslySetInnerHTML={{ __html: post.body }} />
    </div>
  );
}
