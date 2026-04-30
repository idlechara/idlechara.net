import { BlogList } from '../components/BlogEntry.jsx';
import { Marquee } from '../components/Marquee.jsx';
import { NowListening, WebRing, VisitCounter } from '../components/Widgets.jsx';
import posts from '../data/posts.json';

const RECENT_POSTS = posts.slice(0, 3);

const getHomeMarquee = () => {
  const tlPost = posts.find(p => p.section === 'tl');
  const blogPost = posts.find(p => p.section === 'blog');
  const newestPost = posts[0];

  const tlText = tlPost ? `currently translating: ${tlPost.title}` : 'currently translating: [none]';
  const blogText = blogPost ? `currently reading: ${blogPost.title}` : 'currently reading: [none]';
  const dateText = newestPost?.date ? `idlechara.moe — est. 2018 — last updated ${newestPost.date}` : 'idlechara.moe — est. 2018';

  return [
    dateText,
    tlText,
    blogText,
    // 'ssh into nekoi_openwrt',
  ];
};

const HOME_MARQUEE = getHomeMarquee();

export function HomePage({ go, showMarquee = true }) {
  return (
    <div className="content-card">
      <div className="hero">
        <div className="hero-greet">
          <span className="small">// welcome.txt</span>
          <h1>hi, i'm Eri ✦</h1>
          <p>
            there is some shit stored on this site which no one uses and no one cares about — but i love it anyway. it has pretty much some fragments of older blogs and I intend to rebuild it as a whole someday.
          </p>
          <p style={{ marginBottom: 18 }}>
            this is where i dump translations, dev experiments and the occasional
            life update. grab a snack, wander around.{' '}
            <span style={{ color: 'var(--pink-deep)' }}>(=^･ω･^=)</span>
          </p>
          <button className="btn" onClick={() => go('blog')}>read the blog →</button>{' '}
          <button className="btn mint" onClick={() => go('about')}>about me</button>
        </div>
        <div>
          <NowListening />
          <WebRing />
          <VisitCounter />
        </div>
      </div>

      {showMarquee && <Marquee items={HOME_MARQUEE} />}

      <h2>recent stuff</h2>
      <BlogList posts={RECENT_POSTS} go={go} />
    </div>
  );
}
