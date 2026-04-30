import { BlogList } from '../components/BlogEntry.jsx';
import { SECTIONS } from '../data/sections.js';
import posts from '../data/posts.json';

export function BlogListPage({ section, go }) {
  const config = SECTIONS[section];
  const sectionPosts = posts.filter((p) => p.section === section);
  return (
    <div className="content-card">
      <span style={{ fontSize: 12, letterSpacing: 2, textTransform: 'uppercase', color: 'var(--periwinkle-deep)' }}>
        // {section}.log
      </span>
      <h1>{config.title}</h1>
      <p style={{ color: 'var(--ink-soft)' }}>{config.subtitle}</p>
      <hr />
      {sectionPosts.length === 0 ? (
        <p style={{ textAlign: 'center', padding: '40px 0', color: 'var(--ink-soft)' }}>
          ✦ nothing here yet — come back later ✦
        </p>
      ) : (
        <BlogList posts={sectionPosts} go={go} sectionOverride={section} />
      )}
    </div>
  );
}
