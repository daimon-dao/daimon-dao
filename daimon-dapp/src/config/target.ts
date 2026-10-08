/*
 * Build target of this bundle, fixed at build time (NEXT_PUBLIC_* values are
 * inlined by the bundler):
 *
 *  - default: the Vercel app (app.daimon.money). A Node server renders every
 *    page per request: the language comes from a cookie / Accept-Language,
 *    the wallet state from a cookie, the edge middleware and the security
 *    headers exist. Nothing in this file changes that target.
 *
 *  - "ipfs" (`npm run build:ipfs`, docs/IPFS_MIRROR.md): a static export for
 *    the censorship-resistant mirror (daimon.blockchain). No server at all:
 *    the language is chosen in the browser (localStorage), the wallet state
 *    lives in localStorage, links are relative, and whatever needs a server
 *    (headers, the region middleware) is simply absent.
 *
 * Code that must differ between the two targets branches on this constant,
 * and nowhere else. The default branch is always the one Vercel runs.
 */
export const IS_IPFS_BUILD = process.env.NEXT_PUBLIC_DAPP_TARGET === "ipfs";
