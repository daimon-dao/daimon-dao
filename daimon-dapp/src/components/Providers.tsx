"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, type State } from "wagmi";
import { useState, type ReactNode } from "react";
import { getWagmiConfig } from "@/lib/wagmi";

/*
 * Mounted ONCE in the root layout (never in the page layouts): the
 * wagmi/react-query state lives here and must survive client-side navigations.
 * initialState comes from the cookie read by the server (cookieToInitialState
 * in the root layout), so the wallet connection is already present at the
 * first render. The wagmi config comes from getWagmiConfig: this request's
 * own on the server, the page's single one in the browser.
 */
export function Providers({
  children,
  initialState,
}: {
  children: ReactNode;
  initialState?: State;
}) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: { queries: { staleTime: 15_000, refetchOnWindowFocus: false } },
      })
  );
  const [wagmiConfig] = useState(getWagmiConfig);

  return (
    <WagmiProvider config={wagmiConfig} initialState={initialState}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
