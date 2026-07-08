"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { ACTIVE_CHAIN } from "@/config/contracts";
import { shortAddress } from "@/lib/format";

export function ConnectButton() {
  const [mounted, setMounted] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connectAsync, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  useEffect(() => setMounted(true), []);
  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  if (!mounted) {
    return <button className="btn-oro opacity-60">Connetti wallet</button>;
  }

  if (isConnected && chainId !== ACTIVE_CHAIN.id) {
    return (
      <button
        className="rounded-lg bg-rosso/90 px-4 py-2 text-sm font-medium text-white hover:bg-rosso"
        onClick={() => switchChain({ chainId: ACTIVE_CHAIN.id })}
      >
        Passa a {ACTIVE_CHAIN.name}
      </button>
    );
  }

  if (isConnected && address) {
    return (
      <button
        className="rounded-lg border border-oro/60 px-4 py-2 text-sm font-medium text-oro hover:bg-oro/10"
        onClick={() => disconnect()}
        title="Clicca per disconnettere"
      >
        {shortAddress(address)}
      </button>
    );
  }

  return (
    <div className="relative" ref={menuRef}>
      <button className="btn-oro" onClick={() => setMenuOpen((v) => !v)} disabled={isPending}>
        {isPending ? "Connessione…" : "Connetti wallet"}
      </button>
      {menuOpen && (
        <div className="absolute right-0 z-20 mt-2 w-56 rounded-xl border border-bordi bg-card p-2 shadow-xl">
          {connectors.map((c) => (
            <button
              key={c.uid}
              className="block w-full rounded-lg px-3 py-2 text-left text-sm text-testo hover:bg-oro/10"
              onClick={async () => {
                setMenuOpen(false);
                try {
                  await connectAsync({ connector: c });
                } catch {
                  /* rifiuto dell'utente: nessun errore da mostrare */
                }
              }}
            >
              {c.name === "Injected" ? "Browser wallet (MetaMask / Trust)" : c.name}
            </button>
          ))}
          <p className="px-3 pt-1 text-xs text-secondario">
            MetaMask e Trust Wallet usano il wallet del browser.
          </p>
        </div>
      )}
    </div>
  );
}
