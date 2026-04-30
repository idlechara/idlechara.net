import aboutHtml from '../data/about.html?raw';

export function AboutPage() {
  return (
    <div className="content-card">
      <span style={{ fontSize: 12, letterSpacing: 2, textTransform: 'uppercase', color: 'var(--periwinkle-deep)' }}>
        // about.me
      </span>
      <h1>about me</h1>
      <div dangerouslySetInnerHTML={{ __html: aboutHtml }} />
    </div>
  );
}
