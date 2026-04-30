import { LINK_GROUPS } from '../data/links.js';

function LinkCard({ icon, label, sub, href, color }) {
  return (
    <a className="link-card" href={href} target="_blank" rel="noopener noreferrer">
      <div className="lc-icon" style={color ? { background: color } : undefined}>{icon}</div>
      <div>
        <div className="lc-title">{label}</div>
        <div className="lc-sub">{sub}</div>
      </div>
    </a>
  );
}

export function LinksPage() {
  return (
    <div className="content-card">
      <span style={{ fontSize: 12, letterSpacing: 2, textTransform: 'uppercase', color: 'var(--periwinkle-deep)' }}>
        // bookmarks.txt
      </span>
      <h1>some links for you ✦</h1>
      <p>places i hang out &amp; resources i return to.</p>
      {LINK_GROUPS.map((g) => (
        <div key={g.title}>
          <h2>{g.title}</h2>
          <div className="links-grid">
            {g.items.map((item) => <LinkCard key={item.label} {...item} />)}
          </div>
        </div>
      ))}
    </div>
  );
}
