import { cookieStorage, createConfig, createStorage, http } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { ACTIVE_CHAIN } from "@/config/contracts";

/*
 * Connectors: injected covers MetaMask and Trust Wallet (in-app browser and
 * extension). WalletConnect requires a WalletConnect Cloud projectId: it is
 * added only if NEXT_PUBLIC_WC_PROJECT_ID is set.
 */
const wcProjectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

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
    injected(),
    ...(wcProjectId
      ? [walletConnect({ projectId: wcProjectId, showQrModal: true })]
      : []),
  ],
  // Both chains to satisfy the type (ACTIVE_CHAIN is a union): only the active
  // one is actually used.
  transports: {
    [bsc.id]: http("https://bsc-dataseed.binance.org"),
    [bscTestnet.id]: http("https://data-seed-prebsc-1-s1.binance.org:8545"),
  },
});
