#!/usr/bin/env node
// Converts every .svg in a directory to .png (Instagram doesn't accept SVG)
// and removes the source .svg. Run from the repo root so it resolves sharp.
import { readdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import sharp from "sharp";

const dir = process.argv[2];
if (!dir) {
  console.error("Usage: svg-to-png.mjs <dir>");
  process.exit(1);
}

const svgs = readdirSync(dir).filter((f) => f.endsWith(".svg"));
if (svgs.length === 0) {
  console.log("No .svg files found.");
  process.exit(0);
}

for (const file of svgs) {
  const src = join(dir, file);
  const dest = join(dir, file.replace(/\.svg$/, ".png"));
  await sharp(src).png().toFile(dest);
  unlinkSync(src);
  console.log(`${file} -> ${file.replace(/\.svg$/, ".png")}`);
}
