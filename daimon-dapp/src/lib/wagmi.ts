import { createConfig, http } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";
import { ACTIVE_CHAIN } from "@/config/contracts";

/*
 * Connettori: injected copre MetaMask e Trust Wallet (in-app browser e
 * estensione). WalletConnect richiede un projectId di WalletConnect Cloud:
 * viene aggiunto solo se NEXT_PUBLIC_WC_PROJECT_ID e' impostato.
 */
const wcProjectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

export const wagmiConfig = createConfig({
  chains: [ACTIVE_CHAIN],
  // Con SSR/prerender di Next la reidratazione dello store da localStorage
  // va rimandata a DOPO il mount: senza, il primo render client (wallet
  // gia' connesso in precedenza) differisce dall'HTML del server ->
  // "Hydration failed". E' il pattern raccomandato da wagmi per Next.
  ssr: true,
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
