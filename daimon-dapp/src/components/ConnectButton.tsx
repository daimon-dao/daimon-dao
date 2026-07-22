"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { ACTIVE_CHAIN, explorerAddress } from "@/config/contracts";
import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";

export function ConnectButton() {
  const { t } = useI18n();
  const [mounted, setMounted] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const { address, isConnected, chainId, connector } = useAccount();
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

  async function copyAddress() {
    if (!address) return;
    let ok = false;
    try {
      await navigator.clipboard.writeText(address);
      ok = true;
    } catch {
      // Fallback per contesti dove la Clipboard API e' negata.
      try {
        const ta = document.createElement("textarea");
        ta.value = address;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        ok = document.execCommand("copy");
        document.body.removeChild(ta);
      } catch {}
    }
    if (ok) {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }

  // Apre il selettore account del wallet SENZA disconnettere: alla scelta
  // di un altro account MetaMask emette accountsChanged e wagmi si aggiorna.
  async function changeAccount() {
    setMenuOpen(false);
    try {
      const provider = (await connector?.getProvider()) as
        | { request?: (args: { method: string; params?: unknown[] }) => Promise<unknown> }
        | undefined;
      await provider?.request?.({
        method: "wallet_requestPermissions",
        params: [{ eth_accounts: {} }],
      });
    } catch {
      /* rifiuto dell'utente o wallet senza supporto: nessun errore */
    }
  }

  if (!mounted) {
    return <button className="btn-oro opacity-60">{t("connect.connect")}</button>;
  }

  if (isConnected && chainId !== ACTIVE_CHAIN.id) {
    return (
      <button
        className="rounded-lg bg-rosso/90 px-4 py-2 text-sm font-medium text-white hover:bg-rosso"
        onClick={() => switchChain({ chainId: ACTIVE_CHAIN.id })}
      >
        {t("connect.switchTo", { chain: ACTIVE_CHAIN.name })}
      </button>
    );
  }

  if (isConnected && address) {
    // Click esplorativo -> menu con le opzioni, MAI disconnessione diretta.
    return (
      <div className="relative" ref={menuRef}>
        <button
          className="rounded-lg border border-oro/60 px-4 py-2 text-sm font-medium text-oro hover:bg-oro/10"
          onClick={() => setMenuOpen((v) => !v)}
          title={t("connect.walletOptions")}
        >
          {shortAddress(address)}
        </button>
        {menuOpen && (
          <div className="absolute right-0 z-20 mt-2 w-72 rounded-xl border border-bordi bg-card p-2 shadow-xl">
            <button
              onClick={copyAddress}
              className="block w-full break-all rounded-lg px-3 py-2 text-left font-mono text-xs text-testo hover:bg-oro/10"
              title={t("connect.copyTitle")}
            >
              {copied ? t("connect.copied") : address}
            </button>
            <a
              href={explorerAddress(address)}
              target="_blank"
              rel="noopener noreferrer"
              className="block rounded-lg px-3 py-2 text-sm text-testo hover:bg-oro/10"
              onClick={() => setMenuOpen(false)}
            >
              {t("connect.viewOnBscscan")}
            </a>
            <button
              onClick={changeAccount}
              className="block w-full rounded-lg px-3 py-2 text-left text-sm text-testo hover:bg-oro/10"
            >
              {t("connect.switchAccount")}
            </button>
            <div className="my-1 border-t border-bordi" />
            <button
              onClick={() => {
                setMenuOpen(false);
                disconnect();
              }}
              className="block w-full rounded-lg px-3 py-2 text-left text-sm text-rosso/80 hover:bg-rosso/10"
            >
              {t("connect.disconnect")}
            </button>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="relative" ref={menuRef}>
      <button className="btn-oro" onClick={() => setMenuOpen((v) => !v)} disabled={isPending}>
        {isPending ? t("connect.connecting") : t("connect.connect")}
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
              {c.name === "Injected" ? t("connect.injectedName") : c.name}
            </button>
          ))}
          <p className="px-3 pt-1 text-xs text-secondario">{t("connect.injectedHint")}</p>
        </div>
      )}
    </div>
  );
}
