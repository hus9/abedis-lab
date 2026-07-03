import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const posts = defineCollection({
  loader: glob({ pattern: '**/*.{md,mdx}', base: './src/content/posts' }),
  schema: z.object({
    title: z.string(),
    gist: z.string(),
    category: z.enum(['AI', 'Tech', 'Trading', 'Tinkering']),
    // Plain-words subject ("Automatic watches") — hook titles deliberately
    // don't name the topic, so cards/pages show this label alongside them.
    topic: z.string().optional(),
    pubDate: z.coerce.date(),
    readingTime: z.number(), // minutes
  }),
});

export const collections = { posts };
