import { useState, useEffect } from 'react';

export function useRouter() {
  const [route, setRoute] = useState({ page: 'home', slug: null });

  useEffect(() => {
    const apply = () => {
      const h = location.hash.replace(/^#\/?/, '');
      if (!h) { setRoute({ page: 'home', slug: null }); return; }
      const [page, slug] = h.split('/');
      setRoute({ page: page || 'home', slug: slug || null });
    };
    apply();
    window.addEventListener('hashchange', apply);
    return () => window.removeEventListener('hashchange', apply);
  }, []);

  const go = (page, slug = null) => {
    location.hash = slug ? `#/${page}/${slug}` : `#/${page}`;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return { route, go };
}
