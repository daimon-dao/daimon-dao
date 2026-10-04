/*
 * The UI font (Inter), one module per build target:
 *
 *  - Vercel app: next/font/google, as always. The build downloads the font
 *    from Google Fonts and self-hosts it.
 *  - IPFS mirror: next/font/local with the woff2 vendored in src/fonts/, so
 *    the build touches no network and the same commit always yields the same
 *    bytes, hence the same CID (docs/IPFS_MIRROR.md, "Reproducibility").
 *
 * The test is the raw env literal on purpose: the bundler inlines it, drops
 * the dead branch, and only ONE of the two font modules exists in a build.
 * Through an imported constant both would be bundled (and both fonts
 * fetched/emitted), which is exactly what must not happen.
 */
/* eslint-disable @typescript-eslint/no-require-imports */
export const fontClassName: string =
  process.env.NEXT_PUBLIC_DAPP_TARGET === "ipfs"
    ? (require("./font-local") as { fontClassName: string }).fontClassName
    : (require("./font-google") as { fontClassName: string }).fontClassName;
