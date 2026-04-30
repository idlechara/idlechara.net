import { useMemo } from 'react';

function Star({ i, palette, speed, size }) {
  const seed = (n) => {
    const x = Math.sin(i * 9301 + n * 49297) * 233280;
    return x - Math.floor(x);
  };
  const top = seed(1) * 100;
  const left = seed(2) * 100;
  const sz = size * (0.55 + seed(3) * 0.9);
  const color = palette[Math.floor(seed(4) * palette.length)];
  const tDur = 2 + seed(5) * 4;
  const tDelay = -seed(6) * 6;
  const dDur = (10 + seed(7) * 18) / speed;
  const dDelay = -seed(8) * dDur;
  const rot = seed(9) * 360;
  const drift = 6 + seed(10) * 14;

  return (
    <span
      className="bg-star"
      style={{
        top: `${top}%`,
        left: `${left}%`,
        width: `${sz}px`,
        height: `${sz}px`,
        background: color,
        transform: `rotate(${rot}deg)`,
        animation: `starTwinkle ${tDur}s ease-in-out ${tDelay}s infinite, starDrift ${dDur}s ease-in-out ${dDelay}s infinite`,
        '--drift': `${drift}px`,
      }}
    />
  );
}

export function StarField({ count = 90, palette, speed = 1, size = 28 }) {
  const stars = useMemo(() => Array.from({ length: count }, (_, i) => i), [count]);
  return (
    <div className="bg-stars-layer" aria-hidden="true">
      {stars.map((i) => (
        <Star key={i} i={i} palette={palette} speed={speed} size={size} />
      ))}
    </div>
  );
}
