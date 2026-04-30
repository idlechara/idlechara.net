export function Marquee({ items }) {
  const loop = [...items, ...items];
  return (
    <div className="marquee-wrap">
      <div className="marquee-track">
        {loop.map((text, i) => (
          <span key={i}><span className="star">✦</span> {text}</span>
        ))}
      </div>
    </div>
  );
}
