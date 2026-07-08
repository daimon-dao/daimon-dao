import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/Providers";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PausedBanner } from "@/components/PausedBanner";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Daimon DAO",
  description:
    "dApp ufficiale Daimon (DMN): migrazione 1:1, staking vote-escrow e governance on-chain su BNB Chain.",
};

// Tema applicato PRIMA dell'idratazione per evitare flash: dark di default.
const themeScript = `
try {
  var t = localStorage.getItem('daimon-theme');
  document.documentElement.classList.add(t === 'light' ? 'light' : 'dark');
} catch (e) { document.documentElement.classList.add('dark'); }
`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="it" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className={`${inter.className} min-h-screen bg-bg text-testo antialiased`}>
        <Providers>
          <PausedBanner />
          <Header />
          <main className="mx-auto max-w-6xl px-4 py-8">{children}</main>
          <Footer />
        </Providers>
      </body>
    </html>
  );
}
