import { useState, useEffect } from 'react';
import { WEBRING_SITES } from '../data/webring.js';
import { LASTFM_USERNAME, LASTFM_API_KEY } from '../data/music.js';

export function NowListening({ track = 'citypop mix vol.04', artist = 'drifting around at 2v30khz' }) {
  const [music, setMusic] = useState({ track, artist, loading: false });

  const isConfigured = LASTFM_USERNAME && LASTFM_API_KEY && LASTFM_API_KEY !== '5a2b77b7dc8b5c5b7b6d5d5c1f5b5f5d';
  if (!isConfigured) return null;

  useEffect(() => {
    const fetchNowPlaying = async () => {
      setMusic(prev => ({ ...prev, loading: true }));
      try {
        const url = `https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=${LASTFM_USERNAME}&api_key=${LASTFM_API_KEY}&limit=1&format=json`;
        console.log('Fetching from:', url);
        const res = await fetch(url);
        const data = await res.json();
        console.log('Last.fm response:', data);

        if (data.recenttracks?.track) {
          const t = data.recenttracks.track;
          const trackName = t.name || 'Unknown Track';
          const artistName = typeof t.artist === 'string' ? t.artist : (t.artist?.name || 'Unknown Artist');

          console.log('Track:', trackName, 'Artist:', artistName);
          setMusic({
            track: trackName,
            artist: artistName,
            loading: false
          });
        } else {
          console.warn('No recent tracks found in response');
          setMusic(prev => ({ ...prev, loading: false }));
        }
      } catch (e) {
        console.error('Failed to fetch last.fm:', e);
        setMusic(prev => ({ ...prev, loading: false }));
      }
    };

    fetchNowPlaying();
    const interval = setInterval(fetchNowPlaying, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="now-listening">
      <div className="label">★ now spinning</div>
      <div>
        <span className="eq"><span /><span /><span /><span /></span>
        <b>{music.track}</b> — {music.artist}
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
