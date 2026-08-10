---
target: how do people know new posts are added (homepage/posts index)
total_score: 23
p0_count: 2
p1_count: 2
timestamp: 2026-07-03T07-51-42Z
slug: src-pages-index-astro
---
# Critique — How do people know new posts are added? (homepage + posts index + post pages)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 1 | Daily-publishing site looks static; homepage shows zero evidence of new content |
| 2 | Match System / Real World | 4 | Plain language throughout; genuinely excellent |
| 3 | User Control and Freedom | 2 | Post pages dead-end: no prev/next, no "more in category" |
| 4 | Consistency and Standards | 2 | 3 different image conventions across 5 posts (one broken in prod); 2 title formulas repeated |
| 5 | Error Prevention | 1 | No draft/future-date filter (unpublished Jul-4 draft listed); no build-time image check (broken images shipped) |
| 6 | Recognition Rather Than Recall | 3 | Nav labeled, categories visible |
| 7 | Flexibility and Efficiency | 1 | No RSS, no newsletter, no search — no way to subscribe or be notified |
| 8 | Aesthetic and Minimalist Design | 4 | Calm, distinctive, on-brand; detector found zero slop |
| 9 | Error Recovery | 2 | No custom 404 page in src/pages |
| 10 | Help and Documentation | 3 | "Why" section explains the site's promise well |
| **Total** | | **23/40** | **Acceptable — significant gaps for the stated goal** |

## Anti-Patterns Verdict
LLM assessment: does NOT read as AI-made. Fraunces + Atkinson Hyperlegible + warm paper + single orange accent + the "database in four lines" demo = real identity. (Fraunces is on the current reflex-reject list, but it's shipped brand identity — keep it.)
Deterministic scan: 0 findings across src/pages, src/layouts, src/components. Browser overlay skipped — nothing to visualize.

## Answer to the question: how do people know new posts are added?
**They don't.** Current channels, audited:
1. Homepage: never shows posts. A returning visitor sees an identical brochure every day. CTA "See how it works" scrolls to topic cards, not content.
2. Posts index: grouped category-first, so the newest post (Jul 3) renders BELOW an older AI post; dates are small/muted; no "new" affordance.
3. RSS/Atom: none. Sitemap: none. OG/Twitter meta: none (and no `site` in astro.config, so the share button builds wrong absolute URLs).
4. Newsletter/email: none.
5. Instagram carousel: the ONLY announcement channel — manual, broken upload tooling, prior Graph-API attempts died on token exchange/expiry. Single point of failure, and its CTA sends people to the domain root, not the new post.

## Priority Issues
- **[P0] Broken images live on production (Docker post)**: MDX uses `/assets/posts/...` absolute paths but files live in `src/assets/` → both images 404. Three conventions across five posts. Fix: standardize on imported src/assets, add a build-time check; pin the convention in the illustrator stage prompt.
- **[P0 for goal] Freshness is invisible**: add a "Latest" strip (newest 3, hero thumbnail, date, NEW badge <48h) to the homepage; make the primary CTA "Read today's post"; sort/present posts index recency-first with category as filter, not primary grouping. `/impeccable craft`
- **[P1] No subscription channel**: add RSS (@astrojs/rss) + sitemap + OG/Twitter meta + `site` config; per-post og.png can be rasterized from existing hero SVGs with the pipeline's sharp script. `/impeccable harden`
- **[P1] No draft guard**: getCollection returns future-dated/unfinished posts (Jul-4 draft with raw IMAGE comments is listed locally right now). Filter `pubDate <= now` + `draft` flag. `/impeccable harden`
- **[P2] Post-bottom dead end**: only a Share-on-X button. Add prev/next-in-category + IG follow. `/impeccable craft`

## Persona Red Flags
**Jordan (first-timer, from IG)**: carousel says "Full breakdown → abedis.net"; lands on homepage; the promised post is nowhere on screen; must guess "Posts" in nav. Two hops + a guess = abandonment.
**Casey (mobile, distracted)**: broken hero image on the Docker post is the first thing after the title — instant trust hit on the exact post being promoted that day.
**Maya (project persona: ADHD returning reader)**: checks back after enjoying a post; homepage is pixel-identical to yesterday; concludes the site is dormant; never returns. The audience with the least tolerance for "hunt for what changed" is this site's core audience.

## Minor Observations
- Nav "Topics/Why/Posts": content site buries content third.
- Two legacy /carousel/* pages from the pre-pipeline workflow still routable.
- Title formula "X vs Y: You're Not Actually Choosing" already used twice in five posts (writer-stage prompt issue).
- Dev server had been running stale since Jul 1, hiding 3 posts locally — restart it after content lands, or rely on prod.

## Questions to Consider
- What if the homepage led with today's post instead of the pitch?
- Should the IG CTA deep-link to the day's post URL (pipeline knows the slug) instead of the domain?
- Is category-first the right mental model for a 1-post-per-day site, or is it a timeline with category filters?
