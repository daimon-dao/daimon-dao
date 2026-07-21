import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { headers } from "next/headers";
import { cookieToInitialState } from "wagmi";
import "./globals.css";
import { wagmiConfig } from "@/lib/wagmi";
import { Providers } from "@/components/Providers";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PausedBanner } from "@/components/PausedBanner";
import { TestnetBanner } from "@/components/TestnetBanner";
import { GlobalErrorGuard } from "@/components/GlobalErrorGuard";
import { IS_TESTNET } from "@/config/contracts";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Daimon DAO",
  description:
    "dApp ufficiale Daimon (DMN): migrazione 1:1, staking vote-escrow e governance on-chain su BNB Chain.",
  // Lo staging testnet non va indicizzato dai motori di ricerca prima del
  // lancio; su mainnet (NEXT_PUBLIC_CHAIN_ID=56) il noindex sparisce da solo.
  ...(IS_TESTNET && { robots: { index: false, follow: false } }),
};

// Tema applicato PRIMA dell'idratazione per evitare flash: dark di default.
const themeScript = `
try {
  var t = localStorage.getItem('daimon-theme');
  document.documentElement.classList.add(t === 'light' ? 'light' : 'dark');
} catch (e) { document.documentElement.classList.add('dark'); }
`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // Stato wagmi ricostruito dal cookie lato server: la connessione del
  // wallet e' nel primo render (niente flash "Connetti wallet" e niente
  // perdita di stato nelle navigazioni). Nota: headers() rende le route
  // dinamiche — va bene, i dati sono comunque letti on-chain dal client.
  const initialState = cookieToInitialState(wagmiConfig, headers().get("cookie"));

  return (
    <html lang="it" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className={`${inter.className} min-h-screen bg-bg text-testo antialiased`}>
        <Providers initialState={initialState}>
          <GlobalErrorGuard />
          <TestnetBanner />
          <PausedBanner />
          <Header />
          <main className="mx-auto max-w-6xl px-4 py-8">{children}</main>
          <Footer />
        </Providers>
      </body>
    </html>
  );
}
