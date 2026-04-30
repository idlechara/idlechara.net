import { useState } from 'react';
import { useRouter } from './hooks/useRouter.jsx';
import { StarField } from './effects/StarField.jsx';
import { ClickSparkles } from './effects/ClickSparkles.jsx';
import { Lightbox } from './effects/Lightbox.jsx';
import { TitleBar } from './components/TitleBar.jsx';
import { Sidebar } from './components/Sidebar.jsx';
import { Footer } from './components/Footer.jsx';
import { Router } from './pages/Router.jsx';
import {
  useTweaks, TweaksPanel, TweakSection,
  TweakSlider, TweakToggle, TweakSelect,
} from './components/TweaksPanel.jsx';
import { PALETTES } from './data/palettes.js';

const TWEAK_DEFAULTS = {
  starCount: 90,
  starSpeed: 1,
  starSize: 28,
  palette: 'pastel-rainbow',
  showSparkles: true,
  showMarquee: true,
  contentWidth: 1600,
};

export function App() {
  const { route, go } = useRouter();
  const [tweaks, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [tweaksOpen, setTweaksOpen] = useState(false);
  const palette = PALETTES[tweaks.palette] || PALETTES['pastel-rainbow'];

  return (
    <>
      <StarField count={tweaks.starCount} palette={palette} speed={tweaks.starSpeed} size={tweaks.starSize} />
      {tweaks.showSparkles && <ClickSparkles />}
      <Lightbox />

      <div className="app" style={{ '--content-max-width': `${tweaks.contentWidth}px` }}>
        <TitleBar />
        <div className="layout">
          <Sidebar route={route} go={go} />
          <main>
            <Router route={route} go={go} showMarquee={tweaks.showMarquee} />
          </main>
        </div>
        <Footer />
      </div>

      <button
        className="tweaks-toggle"
        onClick={() => setTweaksOpen((v) => !v)}
        title="Tweaks"
        aria-label="Open tweaks panel"
      >
        ⚙
      </button>

      <TweaksPanel open={tweaksOpen} onClose={() => setTweaksOpen(false)}>
        <TweakSection label="Layout" />
        <TweakSlider label="Content width" value={tweaks.contentWidth} min={900} max={2200} step={50} unit="px" onChange={(v) => setTweak('contentWidth', v)} />
        <TweakSection label="Background stars" />
        <TweakSlider label="Star count"  value={tweaks.starCount} min={20} max={220} step={10} onChange={(v) => setTweak('starCount', v)} />
        <TweakSlider label="Drift speed" value={tweaks.starSpeed} min={0.3} max={3} step={0.1} onChange={(v) => setTweak('starSpeed', v)} />
        <TweakSlider label="Star size"   value={tweaks.starSize}  min={12} max={48} step={2}  onChange={(v) => setTweak('starSize', v)} />
        <TweakSelect label="Palette" value={tweaks.palette} options={[
          { value: 'pastel-rainbow', label: 'pastel rainbow (default)' },
          { value: 'pink-mint',      label: 'pink + mint' },
          { value: 'lemon-sky',      label: 'lemon + sky' },
          { value: 'kawaii-sunset',  label: 'kawaii sunset' },
        ]} onChange={(v) => setTweak('palette', v)} />
        <TweakSection label="Interaction fx" />
        <TweakToggle label="Click sparkles"  value={tweaks.showSparkles} onChange={(v) => setTweak('showSparkles', v)} />
        <TweakToggle label="Marquee on home" value={tweaks.showMarquee}  onChange={(v) => setTweak('showMarquee', v)} />
      </TweaksPanel>
    </>
  );
}
