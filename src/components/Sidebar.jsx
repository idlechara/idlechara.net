import { NAV } from '../data/sections.js';

function NavMenu({ route, go }) {
  return (
    <div className="sb-card">
      <div className="sb-tab">menu</div>
      <ul className="sb-list">
        {NAV.map((item) => {
          const active = route.page === item.id && !route.slug;
          return (
            <li key={item.id}>
              <a className={`sb-item${active ? ' active' : ''}`} onClick={() => go(item.id)}>
                <span className="bullet" />
                {item.label}
              </a>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function ProfileCard() {
  return (
    <div className="info-card" style={{ display: 'none' }}>
      <div className="avatar">ฅ^•ﻌ•^ฅ</div>
      <div className="handle">@KuKy_NeKoi</div>
      <div className="status"><span className="dot"></span>online · purring</div>
      <hr style={{ border: 0, borderTop: '1.5px dashed var(--ink-soft)', margin: '10px 0' }} />
      <div style={{ fontSize: 11, lineHeight: 1.6 }}>
        <b>★ today's mood:</b><br />
        slightly sleepy but motivated. coffee level: dangerous.
      </div>
    </div>
  );
}

function GuestbookCard() {
  return (
    <div className="info-card" style={{ background: 'var(--pink)', display: 'none' }}>
      <div style={{ fontSize: 11, fontWeight: 800, letterSpacing: 2, textTransform: 'uppercase', marginBottom: 6 }}>
        ✉ guestbook
      </div>
      <div style={{ fontSize: 12 }}>
        drop a note in the guestbook (coming soon, probably).
      </div>
    </div>
  );
}

function YorokobeShōnenCard({ go }) {
  return (
    <div
      className="info-card"
      style={{ background: 'var(--cream)', cursor: 'pointer', display: 'none' }}
      onClick={() => go('yorokobe', 'yorokobe')}
      title="Click to read"
    >
      <div style={{ fontSize: 11, fontWeight: 800, letterSpacing: 2, textTransform: 'uppercase', marginBottom: 6 }}>
        🎊 yorokobe shounen
      </div>
      <div style={{ fontSize: 12 }}>
        rejoice, my boy — common coding mistakes we all know.
      </div>
    </div>
  );
}

export function Sidebar({ route, go }) {
  return (
    <aside className="sidebar">
      <NavMenu route={route} go={go} />
      <ProfileCard />
      <YorokobeShōnenCard go={go} />
      <GuestbookCard />
    </aside>
  );
}
