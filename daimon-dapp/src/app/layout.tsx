import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { cookies, headers } from "next/headers";
import { cookieToInitialState } from "wagmi";
import "./globals.css";
import { wagmiConfig } from "@/lib/wagmi";
import { Providers } from "@/components/Providers";
import { LocaleProvider } from "@/components/LocaleProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PausedBanner } from "@/components/PausedBanner";
import { RpcHealthBanner } from "@/components/RpcHealthBanner";
import { TestnetBanner } from "@/components/TestnetBanner";
import { GlobalErrorGuard } from "@/components/GlobalErrorGuard";
import { IS_TESTNET } from "@/config/contracts";
import {
  LOCALE_COOKIE,
  isLocale,
  localeFromAcceptLanguage,
  translate,
  type Locale,
} from "@/lib/i18n";

const inter = Inter({ subsets: ["latin"] });

/*
 * Lingua della richiesta: cookie esplicito (scelta dell'utente) o, al
 * primo accesso, Accept-Language (italiano solo se primario). Rilevata
 * lato server cosi' l'HTML iniziale e il primo render client coincidono.
 */
function detectLocale(): Locale {
  const fromCookie = cookies().get(LOCALE_COOKIE)?.value;
  if (isLocale(fromCookie)) return fromCookie;
  return localeFromAcceptLanguage(headers().get("accept-language"));
}

export function generateMetadata(): Metadata {
  const locale = detectLocale();
  return {
    title: translate(locale, "meta.title"),
    description: translate(locale, "meta.description"),
    // Lo staging testnet non va indicizzato dai motori di ricerca prima del
    // lancio; su mainnet (NEXT_PUBLIC_CHAIN_ID=56) il noindex sparisce da solo.
    ...(IS_TESTNET && { robots: { index: false, follow: false } }),
  };
}

// Tema applicato PRIMA dell'idratazione per evitare flash: dark di default.
const themeScript = `
try {
  var t = localStorage.getItem('daimon-theme');
  document.documentElement.classList.add(t === 'light' ? 'light' : 'dark');
} catch (e) { document.documentElement.classList.add('dark'); }
`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = detectLocale();
  // Stato wagmi ricostruito dal cookie lato server: la connessione del
  // wallet e' nel primo render (niente flash "Connetti wallet" e niente
  // perdita di stato nelle navigazioni). Nota: headers() rende le route
  // dinamiche — va bene, i dati sono comunque letti on-chain dal client.
  const initialState = cookieToInitialState(wagmiConfig, headers().get("cookie"));

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body className={`${inter.className} min-h-screen bg-bg text-testo antialiased`}>
        <LocaleProvider initialLocale={locale}>
          <Providers initialState={initialState}>
            <GlobalErrorGuard />
            <TestnetBanner />
            <PausedBanner />
            <RpcHealthBanner />
            <Header />
            <main className="mx-auto max-w-6xl px-4 py-8">{children}</main>
            <Footer />
          </Providers>
        </LocaleProvider>
      </body>
    </html>
  );
}
