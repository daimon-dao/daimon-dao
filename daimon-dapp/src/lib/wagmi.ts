import { cookieStorage, createConfig, createStorage, http } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { ACTIVE_CHAIN } from "@/config/contracts";

/*
 * Connettori: injected copre MetaMask e Trust Wallet (in-app browser e
 * estensione). WalletConnect richiede un projectId di WalletConnect Cloud:
 * viene aggiunto solo se NEXT_PUBLIC_WC_PROJECT_ID e' impostato.
 */
const wcProjectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

// Config SINGLETON a livello di modulo: creata una sola volta per runtime,
// mai dentro un componente (i connectors non vanno ricreati a ogni render).
export const wagmiConfig = createConfig({
  chains: [ACTIVE_CHAIN],
  // Pattern SSR completo raccomandato da wagmi per Next (App Router):
  //  - ssr: true rimanda la reidratazione dello store a dopo il mount
  //    (senza: hydration mismatch col wallet gia' connesso);
  //  - cookieStorage rende lo stato di connessione leggibile ANCHE dal
  //    server: il root layout lo passa come initialState al WagmiProvider
  //    (cookieToInitialState), cosi' la connessione e' presente dal primo
  //    render e sopravvive alle navigazioni client-side senza flash.
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
  connectors: [
    injected(),
    ...(wcProjectId
      ? [walletConnect({ projectId: wcProjectId, showQrModal: true })]
      : []),
  ],
  // Entrambe le chain per soddisfare il tipo (ACTIVE_CHAIN e' una union):
  // viene usata solo quella attiva.
  transports: {
    [bsc.id]: http("https://bsc-dataseed.binance.org"),
    [bscTestnet.id]: http("https://data-seed-prebsc-1-s1.binance.org:8545"),
  },
});
