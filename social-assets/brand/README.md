# Brand — the Daimon logo

**`Logo_DMN_Official.ai` is the source of truth**: the official logo, Adobe
Illustrator 24.1, December 2021, 500 × 500 pt artboard. Every other logo file
in the project derives from it.

| File | What it is |
|---|---|
| `Logo_DMN_Official.ai` | The Illustrator original. Source of truth. |
| `daimon-logo.svg` | Plain-shape rebuild of the .ai, `viewBox="0 0 500 500"`. Use it for anything vector. |
| `daimon-logo-32.svg` | The same SVG with `width`/`height` 32 (token-logo forms that ask for a 32 × 32 SVG; the site serves it at `daimon.money/logo-32.svg`). |
| `daimon-logo-32.png`, `-256.png`, `-512.png` | Rasters of `daimon-logo.svg`, transparent corners. |
| `daimon-logo-ring.svg` | The logo with its gold edge ring, as daimon.money shows it, `viewBox="0 0 512 512"`. The paths of `daimon-logo.svg`, untouched, plus one circle. |
| `daimon-logo-ring-32.png`, `-256.png`, `-512.png`, `-1024.png` | Rasters of `daimon-logo-ring.svg`, transparent corners. The 512 one is byte-identical to `../logo-512.png`. |

## Which file to use where

| Where | File |
|---|---|
| Anything vector: print, editing, a new format to derive | `daimon-logo.svg` |
| The logo as daimon.money shows it: avatars and profile pictures (GitHub organization, X), favicons and app icons, link previews, the logo alone on a dark background (where the navy disc would melt into it) | `daimon-logo-ring.svg`, or the `daimon-logo-ring-*.png` at the size needed (1024 for anything that asks for a large upload) |
| A token-logo form that asks for a 32 × 32 SVG | `daimon-logo-32.svg` |
| A raster of the logo as drawn in the .ai, with no ring: a light background, or a platform that frames the logo itself | `daimon-logo-256.png` / `-512.png` (`-32.png` for tiny slots) |
| The Illustrator original, for a designer | `Logo_DMN_Official.ai` |

Copies in use:

- daimon.money: `public/logo-512.png` (= `daimon-logo-ring-512.png`) in the
  header, the footer, the favicon and the Open Graph image;
  `public/logo-32.svg` (= `daimon-logo-32.svg`).
- app.daimon.money: `public/logo.svg` and `src/app/icon.svg`
  (= `daimon-logo.svg`). The header and the terms screen draw their own gold
  ring in CSS (`rounded-full dark:ring-1 dark:ring-oro/60` in
  `src/components/Logo.tsx`): 1 px of `#c9a227` at 60 % *outside* the 36 px
  disc, in the dark theme only. It is not the ring of these files: relative to
  the disc it is about 2.3 times thicker and sits outside the edge instead of
  across it. The dApp's `apple-icon.png` was rendered from the .ai directly.
- This repository: `../logo-512.png` (= `daimon-logo-ring-512.png`), the root
  README header and the protocol paper.

## Why a rebuild

The earlier SVG, a `pdftocairo -svg` conversion of the .ai used until October
2026, drew the dark band inside the disc as a 130-unit stroke inside a mask. A
mask's default region is the masked element's bounding box plus 10 %, and a
bounding box ignores the stroke width: the region (82–418) is narrower than the
band (outer radius 205). Renderers that follow the spec, Chromium/Edge and
resvg among them, cropped the band to a square whose corners are cut by the
circle: an octagon.

## How it is built

Straight from the .ai content stream, with no masks, clips, filters or defs:

| In the .ai | In `daimon-logo.svg` |
|---|---|
| Navy disc, r 250, sRGB (0.055, 0.031, 0.271) | Same path, copied from the earlier SVG |
| Circle r 140, stroke 130, (0, 0, 0.169), group opacity 0.4 | Even-odd ring, radii 75–205, `fill-opacity` 0.399994 |
| Circle r 145, stroke 10, (0, 0, 0.6), group opacity 0.6 | Even-odd ring, radii 140–150 |
| Circle r 150, stroke 3, (0, 0, 0.898), group opacity 0.6 | Even-odd ring, radii 148.5–151.5 |
| Gold marks and their 4-pt black outlines | Same paths, byte for byte |

### The ring version

`daimon-logo-ring.svg` is the medallion recipe behind `../logo-512.png` (in
use since July 2026), now kept as a file: `daimon-logo.svg`'s ten paths in a
500-unit box offset by 6 inside a 512 square, then
`<circle cx="256" cy="256" r="250" fill="none" stroke="#c9a227" stroke-opacity="0.7" stroke-width="6"/>`.
The ring straddles the disc's edge: it spans radii 247–253 of the square, so
it covers the outer 3 units of the disc at 70 % and leaves 3 transparent units
beyond it. Everything inside radius 247 is the plain logo.

## Verification (2 October 2026)

At 512 × 512 px (262,144 px), on white, against the .ai rendered by pdf.js:

- `daimon-logo.svg`: 2,279 px (resvg) and 2,865 px (Edge) differ by more than
  8/255, all on anti-aliased edges; the earlier SVG had 21,265 and 22,217, the
  octagon's missing corners.
- Against the earlier SVG in the same renderer, only pixels inside the band
  (radius 74.5–205.6) changed; the rest of the disc, the gold marks and the
  edge are untouched.

The ring version, against the plain logo (resvg 2.6.2):

- `daimon-logo-ring-512.png`, `../logo-512.png` and the file daimon.money
  serves at `/logo-512.png` are the same bytes (sha256 `29d26098…b7b31d`).
- At 256, 512 and 1024 px, `daimon-logo.svg` rendered alone at the inner size
  (250, 500, 1000 px) and placed at the offset (3, 6, 12 px) matches the ring
  PNG on every pixel inside the ring (47,140, 190,120 and 763,556 px) and
  outside it; only the ring's annulus differs. At 32 px the inner logo is
  31.25 px at offset 0.375, off the pixel grid: there the PNG matches the same
  SVG without the circle, inside and outside the annulus.
- Edge draws `daimon-logo-ring.svg` like resvg: at 512 px, 3,515 px differ by
  more than 8/255, all on anti-aliased edges (3,428 for `daimon-logo.svg`).

## Regenerating

`../scripts/brand.mjs` writes `daimon-logo-ring.svg` and renders the PNGs here
and `../logo-512.png`; the social cards and banners read the logo from here
through `../scripts/lib.mjs`.
