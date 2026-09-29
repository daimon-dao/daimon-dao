/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
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
