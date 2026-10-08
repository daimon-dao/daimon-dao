# Vendored font (IPFS mirror build only)

`Inter-latin.woff2` is the file the Vercel build downloads from Google Fonts
at build time through `next/font/google` (`Inter`, variable weight 100–900,
latin subset). The IPFS mirror build (`npm run build:ipfs`) uses this copy
through `next/font/local` (`src/app/font-local.ts`) so that the build needs no
network and the same commit always produces the same bytes, hence the same
CID (`docs/IPFS_MIRROR.md`).

| | |
|---|---|
| Source | `https://fonts.gstatic.com/s/inter/v20/UcC73FwrK3iLTeHuS_nVMrMxCp50SjIa1ZL7.woff2` (the `/* latin */` face of `https://fonts.googleapis.com/css2?family=Inter:wght@100..900&display=swap`, fetched 2026-10-04) |
| SHA-256 | `3100e775e8616cd2611beecfa23a4263d7037586789b43f035236a2e6fbd4c62` |
| Size | 48,256 bytes |
| Licence | Inter, © The Inter Project Authors, SIL Open Font License 1.1 (`https://github.com/rsms/inter/blob/master/LICENSE.txt`) |

The Vercel build does not use this directory: `src/app/font.ts` picks one font
module per target and the bundler drops the other.
