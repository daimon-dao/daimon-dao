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
 * Request language: explicit cookie (the user's choice) or, on first visit,
 * Accept-Language (Italian only if primary). Detected server-side so the
 * initial HTML and the first client render coincide.
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
    // The testnet staging must not be indexed by search engines before launch;
    // on mainnet (NEXT_PUBLIC_CHAIN_ID=56) the noindex disappears on its own.
    ...(IS_TESTNET && { robots: { index: false, follow: false } }),
  };
}

// Theme applied BEFORE hydration to avoid a flash: dark by default.
const themeScript = `
try {
  var t = localStorage.getItem('daimon-theme');
  document.documentElement.classList.add(t === 'light' ? 'light' : 'dark');
} catch (e) { document.documentElement.classList.add('dark'); }
`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = detectLocale();
  // wagmi state reconstructed from the cookie server-side: the wallet
  // connection is in the first render (no "Connect wallet" flash and no state
  // loss across navigations). Note: headers() makes the routes dynamic — fine,
  // the data is read on-chain from the client anyway.
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
