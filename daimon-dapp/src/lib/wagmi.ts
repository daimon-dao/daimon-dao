import { cookieStorage, createConfig, createStorage, fallback, http } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { ACTIVE_CHAIN, APP_URL, RPC_URLS } from "@/config/contracts";
import { inAppWallet } from "@/lib/injectedWallet";

/*
 * Connectors: inAppWallet for a wallet's own in-app browser on mobile
 * (MetaMask, Trust, Binance: one tap, no menu); injected (plus the EIP-6963
 * wallets wagmi discovers) for desktop extensions; WalletConnect for every
 * other mobile browser. WalletConnect requires a WalletConnect Cloud projectId: it is
 * added only if NEXT_PUBLIC_WC_PROJECT_ID is set. The projectId is a PUBLIC
 * identifier (it ships in the bundle by design), not a secret.
 */
const wcProjectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

// What the wallet shows in the WalletConnect pairing prompt. The url is the
// production domain even on a preview deployment: it is the name users must
// learn to trust.
const wcMetadata = {
  name: "Daimon DAO",
  description: "Daimon (DMN): 1:1 migration, vote-escrow staking and on-chain governance on BNB Chain.",
  url: APP_URL,
  icons: [`${APP_URL}/apple-icon.png`],
};

// Module-level SINGLETON config: created once per runtime, never inside a
// component (connectors must not be recreated on every render).
export const wagmiConfig = createConfig({
  chains: [ACTIVE_CHAIN],
  // Full SSR pattern recommended by wagmi for Next (App Router):
  //  - ssr: true defers store rehydration until after mount
  //    (without it: hydration mismatch with the already-connected wallet);
  //  - cookieStorage makes the connection state readable ALSO from the
  //    server: the root layout passes it as initialState to the WagmiProvider
  //    (cookieToInitialState), so the connection is present from the first
  //    render and survives client-side navigations without a flash.
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
  connectors: [
    // Inside a wallet's in-app browser (mobile): one-tap connect to the
    // injected wallet, see src/lib/injectedWallet.ts.
    inAppWallet(),
    injected(),
    ...(wcProjectId
      ? [walletConnect({ projectId: wcProjectId, showQrModal: true, metadata: wcMetadata })]
      : []),
  ],
  // Both chains to satisfy the type (ACTIVE_CHAIN is a union): only the active
  // one is actually used. Public endpoints only, in order (contracts.ts).
  transports: {
    [bsc.id]: fallback(RPC_URLS[56].map((u) => http(u))),
    [bscTestnet.id]: fallback(RPC_URLS[97].map((u) => http(u))),
  },
});
