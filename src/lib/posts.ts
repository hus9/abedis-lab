import { getCollection, type CollectionEntry } from 'astro:content';

/** Published posts only (no future-dated pipeline drafts), newest first. */
export async function getPublishedPosts(): Promise<CollectionEntry<'posts'>[]> {
  const now = new Date();
  const posts = await getCollection('posts', (p) => p.data.pubDate <= now);
  return posts.sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf());
}

const heroes = import.meta.glob<{ default: ImageMetadata }>(
  '/src/assets/posts/*/hero.svg',
  { eager: true }
);

/** Hero image metadata for a post slug, if the post has one. */
export function getHero(slug: string): ImageMetadata | undefined {
  return heroes[`/src/assets/posts/${slug}/hero.svg`]?.default;
}

/** True if the post is less than 48 hours old at build time. */
export function isNew(pubDate: Date): boolean {
  return Date.now() - pubDate.valueOf() < 48 * 60 * 60 * 1000;
}
