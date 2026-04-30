import { useState, useEffect } from 'react';

export function ClickSparkles() {
  const [bursts, setBursts] = useState([]);

  useEffect(() => {
    const onClick = (e) => {
      const id = Math.random().toString(36).slice(2);
      const palette = ['#ffffff', '#f9c1da', '#fff8a8', '#bdeadf', '#b9dff5'];
      const pieces = Array.from({ length: 7 }, (_, k) => ({
        k,
        ang: (k / 7) * Math.PI * 2 + Math.random() * 0.6,
        dist: 28 + Math.random() * 36,
        color: palette[Math.floor(Math.random() * palette.length)],
        sz: 8 + Math.random() * 10,
      }));
      setBursts((b) => [...b, { id, x: e.clientX, y: e.clientY, pieces }]);
      setTimeout(() => setBursts((b) => b.filter((it) => it.id !== id)), 700);
    };
    window.addEventListener('click', onClick);
    return () => window.removeEventListener('click', onClick);
  }, []);

  return (
    <div className="sparkle-layer" aria-hidden="true">
      {bursts.map((b) => (
        <div key={b.id} className="sparkle-burst" style={{ left: b.x, top: b.y }}>
          {b.pieces.map((p) => (
            <span
              key={p.k}
              className="sparkle-piece"
              style={{
                background: p.color,
                width: `${p.sz}px`,
                height: `${p.sz}px`,
                '--dx': `${Math.cos(p.ang) * p.dist}px`,
                '--dy': `${Math.sin(p.ang) * p.dist}px`,
              }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}
