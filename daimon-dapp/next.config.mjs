/*
 * Security headers on every response. A wallet dApp must never be framed:
 * inside another site's frame, a visitor could be tricked into clicking
 * "Approve" or "Migrate" on a page they cannot see (clickjacking).
 * frame-ancestors 'none' is the modern control, X-Frame-Options DENY the same
 * for older browsers; nosniff stops a response from being run as a type it
 * was not served as.
 */
const securityHeaders = [
  { key: "Content-Security-Policy", value: "frame-ancestors 'none'" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Content-Type-Options", value: "nosniff" },
];

/*
 * Two build targets, one source tree (src/config/target.ts):
 *  - default, `next build`: the Vercel app. This branch of the config is the
 *    one that has always been here, unchanged.
 *  - DAPP_TARGET=ipfs, `npm run build:ipfs` (scripts/build-ipfs.mjs): a static
 *    export for the IPFS mirror, docs/IPFS_MIRROR.md. No server: headers()
 *    cannot exist (a static file has no response headers), the pages become
 *    directories with an index.html (what IPFS gateways serve), every
 *    asset path is made relative after the export so one build works from
 *    https://<cid>.ipfs.<gw>/ and from https://<gw>/ipfs/<cid>/ alike
 *    (together with the <base href> the build script writes into every page), and the build id is a constant so
 *    the output is a pure function of the source.
 */
const IPFS = process.env.DAPP_TARGET === "ipfs";

/** @type {import('next').NextConfig} */
const ipfsTarget = {
  output: "export",
  // With output: "export" this is the EXPORT directory (the build itself still
  // uses .next): the site, as the gateways will serve it.
  distDir: "out-ipfs",
  trailingSlash: true,
  // next/font refuses a relative prefix, so a placeholder origin that the
  // build script replaces with base-relative paths in every emitted file
  // (and fails if any trace of it survives): the same name as in
  // scripts/build-ipfs.mjs.
  assetPrefix: "https://ipfs-mirror.invalid",
  images: { unoptimized: true },
  generateBuildId: () => "ipfs-mirror",
};

/** @type {import('next').NextConfig} */
const vercelTarget = {
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  ...(IPFS ? ipfsTarget : vercelTarget),
  webpack: (config) => {
    // The wagmi/connectors barrel pulls in the MetaMask SDK, which references
    // React Native's AsyncStorage. This dApp never uses that connector (only
    // injected + WalletConnect) and never runs on React Native: resolve it to
    // an empty module instead of a build warning. Same for pino-pretty, an
    // optional dev-only pretty printer of WalletConnect's logger.
    config.resolve.fallback = {
      ...config.resolve.fallback,
      "@react-native-async-storage/async-storage": false,
      "pino-pretty": false,
    };
    // wagmi/chains re-exports every viem chain, including Tempo, whose ox
    // helper has a dynamic require webpack flags as a "critical dependency".
    // Only bsc / bscTestnet are used; silence exactly that module, nothing else.
    config.ignoreWarnings = [
      ...(config.ignoreWarnings ?? []),
      { module: /node_modules[\\/]ox[\\/]_esm[\\/]tempo[\\/]/, message: /Critical dependency/ },
    ];
    return config;
  },
};

export default nextConfig;
