import { useState, useEffect, useRef } from 'react';

const POOF_COUNT = 20;
const CLOSE_DURATION = 650; // ms

function makePoofStars(rect) {
  const hw = rect.width / 2;
  const hh = rect.height / 2;
  return Array.from({ length: POOF_COUNT }, () => {
    // start at random point across the frame (relative to screen center)
    const sx = (Math.random() * 2 - 1) * hw;
    const sy = (Math.random() * 2 - 1) * hh;
    // fly outward from that point — angle biased away from frame center
    const angle = Math.atan2(sy, sx) + (Math.random() - 0.5) * 1.4;
    const speed = 100 + Math.random() * 180;
    return {
      sx, sy,
      ex: sx + Math.cos(angle) * speed,
      ey: sy + Math.sin(angle) * speed,
      rot: Math.random() * 600 - 300,
      sz: 14 + Math.random() * 12,
    };
  });
}

export function Lightbox() {
  const [src, setSrc] = useState(null);
  const [offset, setOffset] = useState({ dx: 0, dy: 0 });
  const [closing, setClosing] = useState(false);
  const [poofStars, setPoofStars] = useState([]);
  const frameRef = useRef(null);

  useEffect(() => {
    const onClick = (e) => {
      const img = e.target.closest(
        '.content-card .post-figure img, .content-card .post-gallery img, .content-card .post-body img'
      );
      if (!img) return;
      e.preventDefault();

      const rect = img.getBoundingClientRect();
      const cx = rect.left + rect.width / 2;
      const cy = rect.top + rect.height / 2;
      setOffset({
        dx: cx - window.innerWidth / 2,
        dy: cy - window.innerHeight / 2,
      });

      setSrc(img.currentSrc || img.src);
      setClosing(false);
    };
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
  }, []);

  useEffect(() => {
    if (!src) return;
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    document.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [src]);

  const close = () => {
    if (closing) return;
    const rect = frameRef.current?.getBoundingClientRect() ?? { width: 300, height: 200 };
    setPoofStars(makePoofStars(rect));
    setClosing(true);
    setTimeout(() => { setSrc(null); setClosing(false); setPoofStars([]); }, CLOSE_DURATION);
  };

  if (!src) return null;

  return (
    <div
      className={`lightbox${closing ? ' closing' : ''}`}
      onClick={!closing ? close : undefined}
      role="dialog"
      aria-label="image preview"
    >
      {closing ? (
        <>
          <div className="lightbox-frame closing">
            <img src={src} alt="" />
          </div>
          <div className="lightbox-poof-stars">
            {poofStars.map((s, i) => (
              <span
                key={i}
                style={{
                  '--sx': `${s.sx}px`,
                  '--sy': `${s.sy}px`,
                  '--ex': `${s.ex}px`,
                  '--ey': `${s.ey}px`,
                  '--rot': `${s.rot}deg`,
                  width: `${s.sz}px`,
                  height: `${s.sz}px`,
                }}
              />
            ))}
          </div>
        </>
      ) : (
        <div
          className="lightbox-frame"
          ref={frameRef}
          style={{ '--dx': `${offset.dx}px`, '--dy': `${offset.dy}px` }}
          onClick={(e) => e.stopPropagation()}
        >
          <img src={src} alt="" />
          <button className="lightbox-close" onClick={close} aria-label="close">×</button>
        </div>
      )}
    </div>
  );
}
