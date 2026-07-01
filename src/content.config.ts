import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const posts = defineCollection({
  loader: glob({ pattern: '**/*.{md,mdx}', base: './src/content/posts' }),
  schema: z.object({
    title: z.string(),
    gist: z.string(),
    category: z.enum(['AI', 'Tech', 'Trading', 'Tinkering']),
    pubDate: z.coerce.date(),
    readingTime: z.number(), // minutes
  }),
});

export const collections = { posts };
