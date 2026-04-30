import { HomePage } from './HomePage.jsx';
import { BlogListPage } from './BlogListPage.jsx';
import { PostPage } from './PostPage.jsx';
import { LinksPage } from './LinksPage.jsx';
import { AboutPage } from './AboutPage.jsx';

export function Router({ route, go, showMarquee }) {
  if (route.slug) return <PostPage section={route.page} slug={route.slug} go={go} />;
  switch (route.page) {
    case 'home':  return <HomePage go={go} showMarquee={showMarquee} />;
    case 'blog':
    case 'tl':
    case 'dev':
    case 'yorokobe': return <BlogListPage section={route.page} go={go} />;
    case 'links': return <LinksPage />;
    case 'about': return <AboutPage />;
    default:      return <HomePage go={go} showMarquee={showMarquee} />;
  }
}
