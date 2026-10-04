import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import { cookieToInitialState, type State } from "wagmi";
import "./globals.css";
import { fontClassName } from "@/app/font";
import { getWagmiConfig } from "@/lib/wagmi";
import { Providers } from "@/components/Providers";
import { RouteProvider } from "@/lib/route";
import { LocaleProvider } from "@/components/LocaleProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { PausedBanner } from "@/components/PausedBanner";
import { RpcHealthBanner } from "@/components/RpcHealthBanner";
import { TestnetBanner } from "@/components/TestnetBanner";
import { GatewayNotice } from "@/components/GatewayNotice";
import { GlobalErrorGuard } from "@/components/GlobalErrorGuard";
import { TermsProvider, TERMS_ACCEPTED_SCRIPT } from "@/components/TermsGate";
import { IS_TESTNET } from "@/config/contracts";
import { IS_IPFS_BUILD } from "@/config/target";
import {
  DEFAULT_LOCALE,
  LOCALE_COOKIE,
  LOCALE_PENDING_SCRIPT,
  isLocale,
  localeFromAcceptLanguage,
  translate,
  type Locale,
} from "@/lib/i18n";

/*
 * Request language: explicit cookie (the user's choice) or, on first visit,
 * Accept-Language (Italian only if primary). Detected server-side so the
 * initial HTML and the first client render coincide. cookies() and headers()
 * are async since Next 15.
 *
 * IPFS mirror: there is no request. The HTML is prerendered in English and
 * the browser applies its own language after hydration (LocaleProvider);
 * cookies()/headers() are never called, which is what keeps every route
 * static.
 */
async function detectLocale(): Promise<Locale> {
  if (IS_IPFS_BUILD) return DEFAULT_LOCALE;
  const fromCookie = (await cookies()).get(LOCALE_COOKIE)?.value;
  if (isLocale(fromCookie)) return fromCookie;
  return localeFromAcceptLanguage((await headers()).get("accept-language"));
}

export async function generateMetadata(): Promise<Metadata> {
  const locale = await detectLocale();
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

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await detectLocale();
  // wagmi state reconstructed from the cookie server-side: the wallet
  // connection is in the first render (no "Connect wallet" flash and no state
  // loss across navigations). Note: headers() makes the routes dynamic — fine,
  // the data is read on-chain from the client anyway.
  // IPFS mirror: no cookie and no server; wagmi reconnects from localStorage
  // after mount, as any static dApp does.
  const initialState: State | undefined = IS_IPFS_BUILD
    ? undefined
    : cookieToInitialState(getWagmiConfig(), (await headers()).get("cookie"));

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
        {IS_IPFS_BUILD && <script dangerouslySetInnerHTML={{ __html: LOCALE_PENDING_SCRIPT }} />}
        <script dangerouslySetInnerHTML={{ __html: TERMS_ACCEPTED_SCRIPT }} />
      </head>
      <body className={`${fontClassName} min-h-screen bg-bg text-testo antialiased`}>
        <RouteProvider>
        <LocaleProvider initialLocale={locale}>
          <Providers initialState={initialState}>
            <GlobalErrorGuard />
            <TermsProvider>
              {IS_IPFS_BUILD && <GatewayNotice />}
              <TestnetBanner />
              <PausedBanner />
              <RpcHealthBanner />
              <Header />
              <main className="mx-auto max-w-6xl px-4 py-8">{children}</main>
              <Footer />
            </TermsProvider>
          </Providers>
        </LocaleProvider>
        </RouteProvider>
      </body>
    </html>
  );
}
