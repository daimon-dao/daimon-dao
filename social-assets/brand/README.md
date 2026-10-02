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

Copies in use: the dApp's `public/logo.svg` and `src/app/icon.svg`
(= `daimon-logo.svg`), the site's `public/logo-32.svg` (= `daimon-logo-32.svg`),
and the medallion `../logo-512.png` (logo + gold edge ring, also the site's
`public/logo-512.png`). The dApp's `apple-icon.png` was rendered from the .ai
directly and is unaffected.

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

## Verification (2 October 2026)

At 512 × 512 px (262,144 px), on white, against the .ai rendered by pdf.js:

- `daimon-logo.svg`: 2,279 px (resvg) and 2,865 px (Edge) differ by more than
  8/255, all on anti-aliased edges; the earlier SVG had 21,265 and 22,217, the
  octagon's missing corners.
- Against the earlier SVG in the same renderer, only pixels inside the band
  (radius 74.5–205.6) changed; the rest of the disc, the gold marks and the
  edge are untouched.

## Regenerating

`../scripts/brand.mjs` renders the PNGs here and `../logo-512.png`; the social
cards and banners read the logo from here through `../scripts/lib.mjs`.
