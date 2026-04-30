export function BlogEntry({ post, onClick }) {
  return (
    <a className="blog-entry" onClick={onClick}>
      <div className="timestamp">{post.date}</div>
      <h2>{post.title}</h2>
      <p>{post.excerpt}</p>
      <div className="tag-row">
        <span className={`tag ${post.tag}`}>{post.tag}</span>
      </div>
    </a>
  );
}

export function BlogList({ posts, go, sectionOverride }) {
  return (
    <div className="blog-list">
      {posts.map((p) => (
        <BlogEntry
          key={p.slug}
          post={p}
          onClick={() => go(sectionOverride || p.section, p.slug)}
        />
      ))}
    </div>
  );
}
