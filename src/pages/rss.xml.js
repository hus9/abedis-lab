import rss from '@astrojs/rss';
import { getPublishedPosts } from '../lib/posts';

export async function GET(context) {
  const posts = await getPublishedPosts();
  return rss({
    title: 'Lit Bulb Lab',
    description: 'Hard things, drawn simple. Tech explained for brains that work differently.',
    site: context.site,
    items: posts.map((post) => ({
      title: post.data.title,
      description: post.data.gist,
      pubDate: post.data.pubDate,
      categories: [post.data.category],
      link: `/posts/${post.id}/`,
    })),
  });
}
