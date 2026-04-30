import { useState, useEffect } from 'react';
import { WEBRING_SITES } from '../data/webring.js';
import { LASTFM_USERNAME } from '../data/music.js';

export function NowListening() {
  const [tracks, setTracks] = useState([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [direction, setDirection] = useState('next');

  useEffect(() => {
    if (!LASTFM_USERNAME) return;
    const loadTracks = async () => {
      try {
        const res = await fetch(`${import.meta.env.BASE_URL}nowplaying.json`);
        if (res.ok) {
          const data = await res.json();
          if (Array.isArray(data) && data.length > 0) {
            setTracks(data);
          }
        }
      } catch (e) {
        console.warn('No now playing data found');
      }
    };

    loadTracks();
  }, []);

  // Auto-advance carousel every 5 seconds
  useEffect(() => {
    if (tracks.length === 0) return;

    const interval = setInterval(() => {
      setDirection('next');
      setCurrentIndex((prev) => (prev + 1) % tracks.length);
    }, 5000);

    return () => clearInterval(interval);
  }, [tracks.length]);

  if (!LASTFM_USERNAME) return null;
  if (tracks.length === 0) return null;

  // Safety check for current track
  const currentTrack = tracks[currentIndex];
  if (!currentTrack) return null;

  const handlePrev = (e) => {
    e.preventDefault();
    setDirection('prev');
    setCurrentIndex((prev) => (prev - 1 + tracks.length) % tracks.length);
  };

  const handleNext = (e) => {
    e.preventDefault();
    setDirection('next');
    setCurrentIndex((prev) => (prev + 1) % tracks.length);
  };

  const trackName = currentTrack?.name || 'Unknown Track';
  const artistName = currentTrack?.artist || 'Unknown Artist';
  const imageUrl = currentTrack?.image || '';
  const trackUrl = currentTrack?.url || '#';
  const timestamp = currentTrack?.timestamp ? new Date(currentTrack.timestamp).toLocaleDateString() : '';

  const openTrack = (e) => {
    e.preventDefault();
    window.open(trackUrl, '_blank');
  };

  return (
    <div className="now-listening">
      <div className="label">★ now spinning</div>
      <div className="now-listening-track">
        <button onClick={handlePrev} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 16, flexShrink: 0, padding: 0 }}>‹</button>

        <div
          key={currentIndex}
          className={`now-listening-slide ${direction === 'next' ? 'slide-next' : 'slide-prev'}`}
        >
          {imageUrl && (
            <img
              src={imageUrl}
              alt={trackName}
              style={{
                width: 48,
                height: 48,
                borderRadius: 4,
                objectFit: 'cover',
                flexShrink: 0,
                cursor: 'pointer',
              }}
              onClick={openTrack}
              onError={(e) => {
                e.target.style.display = 'none';
              }}
            />
          )}

          <div style={{ flex: 1, minWidth: 0, cursor: 'pointer' }} onClick={openTrack}>
            <span className="eq"><span /><span /><span /><span /></span>
            <b style={{ display: 'block', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{trackName}</b>
            <div style={{ fontSize: 12, color: 'var(--ink-soft)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {artistName}
            </div>
            <div style={{ fontSize: 10, color: 'var(--ink-soft)', marginTop: 4 }}>
              {currentIndex + 1} / {tracks.length}
            </div>
            {timestamp && (
              <div style={{ fontSize: 9, color: 'var(--ink-soft)', marginTop: 2 }}>
                {timestamp}
              </div>
            )}
          </div>
        </div>

        <button onClick={handleNext} style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 16, flexShrink: 0, padding: 0 }}>›</button>
      </div>
    </div>
  );
}

export function WebRing({ ringName = 'moe-ring', ringDesc = 'a tiny circle of personal sites' }) {
  const [currentIndex, setCurrentIndex] = useState(0);

  if (!WEBRING_SITES || WEBRING_SITES.length === 0) return null;

  const currentSite = WEBRING_SITES[currentIndex];

  const handlePrevious = () => {
    setCurrentIndex((prev) => (prev - 1 + WEBRING_SITES.length) % WEBRING_SITES.length);
  };

  const handleNext = () => {
    setCurrentIndex((prev) => (prev + 1) % WEBRING_SITES.length);
  };

  const handleSiteClick = () => {
    window.open(currentSite.url, '_blank');
  };

  return (
    <div className="webring" style={{ display: 'none' }}>
      <div className="arrow" onClick={handlePrevious} style={{ cursor: 'pointer' }} title="Previous site">‹</div>
      <div style={{ flex: 1, cursor: 'pointer' }} onClick={handleSiteClick}>
        <b>{currentSite.name}</b><br />
        <span style={{ color: 'var(--ink-soft)' }}>{ringDesc}</span>
      </div>
      <div className="arrow" onClick={handleNext} style={{ cursor: 'pointer' }} title="Next site">›</div>
    </div>
  );
}

export function VisitCounter({ count = '001337' }) {
  return (
    <div style={{ marginTop: 14, display: 'none', alignItems: 'center', gap: 10, fontSize: 12 }}>
      <span style={{ letterSpacing: 1 }}>visitors:</span>
      <div className="visit-counter">
        {count.split('').map((c, i) => <span key={i}>{c}</span>)}
      </div>
    </div>
  );
}
