// Generate 1200x630 OG card PNGs into public/og/ from each post's hero image.
// Runs as npm prebuild. Never fails the build: missing sharp or a bad SVG
// just means that post falls back to /og/default.png.
import { readdir, mkdir, access } from 'node:fs/promises';
import path from 'node:path';

const ROOT = path.dirname(new URL(import.meta.url, ).pathname) + '/..';
const OUT = path.join(ROOT, 'public/og');
const OG_W = 1200, OG_H = 630;

let sharp;
try {
  sharp = (await import('sharp')).default;
} catch {
  console.warn('og-gen: sharp unavailable, skipping OG image generation');
  process.exit(0);
}

const exists = (p) => access(p).then(() => true, () => false);
await mkdir(OUT, { recursive: true });

// Default site card: brand wordmark on warm paper.
const defaultSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${OG_W}" height="${OG_H}">
  <rect width="100%" height="100%" fill="#f7f3ec"/>
  <text x="80" y="300" font-family="Georgia, serif" font-weight="900" font-size="84" fill="#1f1b16">Lit Bulb Lab</text>
  <text x="80" y="380" font-family="Georgia, serif" font-size="44" fill="#d6552b">Hard things, drawn simple.</text>
  <rect x="80" y="430" width="120" height="8" fill="#d6552b"/>
</svg>`;
await sharp(Buffer.from(defaultSvg)).png().toFile(path.join(OUT, 'default.png'));

const postsDir = path.join(ROOT, 'src/content/posts');
const slugs = (await readdir(postsDir)).filter((f) => f.endsWith('.mdx')).map((f) => f.replace(/\.mdx$/, ''));

for (const slug of slugs) {
  const heroSvg = path.join(ROOT, `src/assets/posts/${slug}/hero.svg`);
  const legacyPng = path.join(ROOT, `public/images/${slug}.png`);
  const out = path.join(OUT, `${slug}.png`);
  try {
    if (await exists(heroSvg)) {
      await sharp(heroSvg, { density: 150 }).resize(OG_W, OG_H, { fit: 'cover' }).png({ palette: true, quality: 90 }).toFile(out);
    } else if (await exists(legacyPng)) {
      await sharp(legacyPng).resize(OG_W, OG_H, { fit: 'cover' }).png({ palette: true, quality: 90 }).toFile(out);
    } else {
      continue; // falls back to default.png via SeoHead
    }
    console.log(`og-gen: ${slug}.png`);
  } catch (err) {
    console.warn(`og-gen: failed for ${slug}: ${err.message}`);
  }
}
