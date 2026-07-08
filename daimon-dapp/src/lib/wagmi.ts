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
