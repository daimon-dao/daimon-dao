"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, type State } from "wagmi";
import { useState, type ReactNode } from "react";
import { wagmiConfig } from "@/lib/wagmi";

/*
 * Montato UNA sola volta nel root layout (mai nei layout di pagina):
 * lo stato wagmi/react-query vive qui e deve sopravvivere alle
 * navigazioni client-side. initialState arriva dal cookie letto dal
 * server (cookieToInitialState nel root layout), cosi' la connessione
 * del wallet e' presente gia' al primo render.
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

  return (
    <WagmiProvider config={wagmiConfig} initialState={initialState}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
