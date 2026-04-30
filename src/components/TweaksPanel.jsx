import { useState, useRef, useCallback, useEffect } from 'react';

const TWEAKS_STORAGE_KEY = 'idlechara.tweaks';

export function useTweaks(defaults) {
  const [values, setValues] = useState(() => {
    try {
      const stored = localStorage.getItem(TWEAKS_STORAGE_KEY);
      if (stored) return { ...defaults, ...JSON.parse(stored) };
    } catch (_) { /* ignore quota / privacy mode */ }
    return defaults;
  });

  useEffect(() => {
    try {
      localStorage.setItem(TWEAKS_STORAGE_KEY, JSON.stringify(values));
    } catch (_) { /* ignore */ }
  }, [values]);

  const setTweak = useCallback((keyOrEdits, val) => {
    const edits = typeof keyOrEdits === 'object' && keyOrEdits !== null
      ? keyOrEdits : { [keyOrEdits]: val };
    setValues((prev) => ({ ...prev, ...edits }));
  }, []);
  return [values, setTweak];
}

const PANEL_STYLE = `
  .twk-panel{position:fixed;right:16px;bottom:60px;z-index:2147483646;width:280px;
    max-height:calc(100vh - 80px);display:flex;flex-direction:column;
    background:rgba(255,250,240,.92);color:#2b2247;
    backdrop-filter:blur(24px) saturate(160%);
    border:2px solid #2b2247;border-radius:14px;
    box-shadow:5px 5px 0 #5a4a92;
    font:11.5px/1.4 'Anonymous Pro','Courier New',monospace;overflow:hidden}
  .twk-hd{display:flex;align-items:center;justify-content:space-between;
    padding:10px 8px 10px 14px;cursor:move;user-select:none;
    border-bottom:1px dashed #c9bfe6}
  .twk-hd b{font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase}
  .twk-x{appearance:none;border:0;background:transparent;color:rgba(43,34,71,.55);
    width:22px;height:22px;border-radius:6px;cursor:pointer;font-size:13px;line-height:1;
    font-family:inherit}
  .twk-x:hover{background:rgba(0,0,0,.06);color:#2b2247}
  .twk-body{padding:2px 14px 14px;display:flex;flex-direction:column;gap:10px;
    overflow-y:auto;overflow-x:hidden;min-height:0;
    scrollbar-width:thin;scrollbar-color:rgba(0,0,0,.15) transparent}
  .twk-row{display:flex;flex-direction:column;gap:5px}
  .twk-row-h{flex-direction:row;align-items:center;justify-content:space-between;gap:10px}
  .twk-lbl{display:flex;justify-content:space-between;align-items:baseline;color:rgba(43,34,71,.72)}
  .twk-lbl>span:first-child{font-weight:500}
  .twk-val{color:rgba(43,34,71,.5);font-variant-numeric:tabular-nums}
  .twk-sect{font-size:10px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;
    color:rgba(43,34,71,.45);padding:10px 0 0}
  .twk-sect:first-child{padding-top:0}
  .twk-field{appearance:none;width:100%;height:26px;padding:0 8px;
    border:1.5px solid rgba(0,0,0,.15);border-radius:7px;
    background:rgba(255,255,255,.7);color:inherit;font:inherit;outline:none}
  .twk-field:focus{border-color:rgba(0,0,0,.3)}
  select.twk-field{padding-right:22px;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'><path fill='rgba(0,0,0,.5)' d='M0 0h10L5 6z'/></svg>");
    background-repeat:no-repeat;background-position:right 8px center}
  .twk-slider{appearance:none;-webkit-appearance:none;width:100%;height:4px;margin:6px 0;
    border-radius:999px;background:rgba(0,0,0,.12);outline:none}
  .twk-slider::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;
    width:14px;height:14px;border-radius:50%;background:#fff;
    border:1.5px solid rgba(0,0,0,.2);box-shadow:0 1px 3px rgba(0,0,0,.2);cursor:pointer}
  .twk-toggle{position:relative;width:32px;height:18px;border:0;border-radius:999px;
    background:rgba(0,0,0,.15);transition:background .15s;cursor:pointer;padding:0}
  .twk-toggle[data-on="1"]{background:#ec84b3}
  .twk-toggle i{position:absolute;top:2px;left:2px;width:14px;height:14px;border-radius:50%;
    background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.25);transition:transform .15s}
  .twk-toggle[data-on="1"] i{transform:translateX(14px)}
`;

export function TweaksPanel({ open, onClose, title = 'Tweaks ✦', children }) {
  const dragRef = useRef(null);
  const offsetRef = useRef({ x: 16, y: 60 });
  const PAD = 16;

  const clamp = useCallback(() => {
    const panel = dragRef.current;
    if (!panel) return;
    const w = panel.offsetWidth, h = panel.offsetHeight;
    offsetRef.current = {
      x: Math.min(Math.max(PAD, window.innerWidth - w - PAD), Math.max(PAD, offsetRef.current.x)),
      y: Math.min(Math.max(PAD, window.innerHeight - h - PAD), Math.max(PAD, offsetRef.current.y)),
    };
    panel.style.right = offsetRef.current.x + 'px';
    panel.style.bottom = offsetRef.current.y + 'px';
  }, []);

  useEffect(() => {
    if (!open) return;
    clamp();
    window.addEventListener('resize', clamp);
    return () => window.removeEventListener('resize', clamp);
  }, [open, clamp]);

  const onDragStart = (e) => {
    const panel = dragRef.current;
    if (!panel) return;
    const r = panel.getBoundingClientRect();
    const sx = e.clientX, sy = e.clientY;
    const startRight = window.innerWidth - r.right;
    const startBottom = window.innerHeight - r.bottom;
    const move = (ev) => {
      offsetRef.current = {
        x: startRight - (ev.clientX - sx),
        y: startBottom - (ev.clientY - sy),
      };
      clamp();
    };
    const up = () => {
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
    };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
  };

  if (!open) return null;

  return (
    <>
      <style>{PANEL_STYLE}</style>
      <div ref={dragRef} className="twk-panel" style={{ right: offsetRef.current.x, bottom: offsetRef.current.y }}>
        <div className="twk-hd" onMouseDown={onDragStart}>
          <b>{title}</b>
          <button className="twk-x" onClick={onClose}>✕</button>
        </div>
        <div className="twk-body">{children}</div>
      </div>
    </>
  );
}

export function TweakSection({ label }) {
  return <div className="twk-sect">{label}</div>;
}

export function TweakSlider({ label, value, min = 0, max = 100, step = 1, unit = '', onChange }) {
  return (
    <div className="twk-row">
      <div className="twk-lbl">
        <span>{label}</span>
        <span className="twk-val">{value}{unit}</span>
      </div>
      <input type="range" className="twk-slider" min={min} max={max} step={step}
        value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </div>
  );
}

export function TweakToggle({ label, value, onChange }) {
  return (
    <div className="twk-row twk-row-h">
      <div className="twk-lbl"><span>{label}</span></div>
      <button type="button" className="twk-toggle" data-on={value ? '1' : '0'}
        role="switch" aria-checked={!!value} onClick={() => onChange(!value)}><i /></button>
    </div>
  );
}

export function TweakSelect({ label, value, options, onChange }) {
  return (
    <div className="twk-row">
      <div className="twk-lbl"><span>{label}</span></div>
      <select className="twk-field" value={value} onChange={(e) => onChange(e.target.value)}>
        {options.map((o) => {
          const v = typeof o === 'object' ? o.value : o;
          const l = typeof o === 'object' ? o.label : o;
          return <option key={v} value={v}>{l}</option>;
        })}
      </select>
    </div>
  );
}
