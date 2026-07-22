"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { ACTIVE_CHAIN, explorerAddress } from "@/config/contracts";
import { shortAddress } from "@/lib/format";
import { useI18n } from "@/components/LocaleProvider";
import { BottomSheet, useIsMobile } from "@/components/BottomSheet";

export function ConnectButton() {
  const { t } = useI18n();
  const [mounted, setMounted] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  const isMobile = useIsMobile();
  const { address, isConnected, chainId, connector } = useAccount();
  const { connectors, connectAsync, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  useEffect(() => setMounted(true), []);
  // Chiusura al click fuori: SOLO per il dropdown desktop — il bottom sheet
  // vive in un portal fuori da menuRef (chiude col suo backdrop).
  useEffect(() => {
    if (isMobile) return;
    function onClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false);
    }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, [isMobile]);

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

  // Etichetta compatta sotto sm: "Connect"/"Connetti" su UNA riga — il
  // testo esteso spaccava l'header a 360-428px (bug post-i18n).
  const connectLabel = (
    <>
      <span className="sm:hidden">{t("connect.connectShort")}</span>
      <span className="hidden sm:inline">{t("connect.connect")}</span>
    </>
  );

  /*
   * Contenuti dei due menu, condivisi tra dropdown (>=sm) e bottom sheet
   * (<sm). Nel sheet i tap target salgono a >=44px (py-3, testo base).
   */
  function accountMenuItems(sheet: boolean) {
    if (!address) return null;
    const item = sheet
      ? "block w-full rounded-lg px-4 py-3 text-left text-base"
      : "block w-full rounded-lg px-3 py-2 text-left text-sm";
    return (
      <>
        <button
          onClick={copyAddress}
          className={`${item} break-all font-mono ${sheet ? "text-sm" : "text-xs"} text-testo hover:bg-oro/10`}
          title={t("connect.copyTitle")}
        >
          {copied ? t("connect.copied") : address}
        </button>
        <a
          href={explorerAddress(address)}
          target="_blank"
          rel="noopener noreferrer"
          className={`${item} text-testo hover:bg-oro/10`}
          onClick={() => setMenuOpen(false)}
        >
          {t("connect.viewOnBscscan")}
        </a>
        <button onClick={changeAccount} className={`${item} text-testo hover:bg-oro/10`}>
          {t("connect.switchAccount")}
        </button>
        <div className="my-1 border-t border-bordi" />
        <button
          onClick={() => {
            setMenuOpen(false);
            disconnect();
          }}
          className={`${item} text-rosso/80 hover:bg-rosso/10`}
        >
          {t("connect.disconnect")}
        </button>
      </>
    );
  }

  function connectorItems(sheet: boolean) {
    const item = sheet
      ? "block w-full rounded-lg px-4 py-3 text-left text-base text-testo hover:bg-oro/10"
      : "block w-full rounded-lg px-3 py-2 text-left text-sm text-testo hover:bg-oro/10";
    return (
      <>
        {connectors.map((c) => (
          <button
            key={c.uid}
            className={item}
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
        <p className={`px-3 pt-1 text-xs text-secondario ${sheet ? "px-4 pb-1" : ""}`}>
          {t("connect.injectedHint")}
        </p>
      </>
    );
  }

  if (!mounted) {
    return <button className="btn-oro whitespace-nowrap opacity-60">{connectLabel}</button>;
  }

  if (isConnected && chainId !== ACTIVE_CHAIN.id) {
    return (
      <button
        className="whitespace-nowrap rounded-lg bg-rosso/90 px-4 py-2 text-sm font-medium text-white hover:bg-rosso"
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
          className="whitespace-nowrap rounded-lg border border-oro/60 px-3 py-2 font-mono text-sm font-medium text-oro hover:bg-oro/10 sm:px-4"
          onClick={() => setMenuOpen((v) => !v)}
          title={t("connect.walletOptions")}
          aria-expanded={menuOpen}
        >
          {shortAddress(address)}
        </button>
        {menuOpen && !isMobile && (
          <div className="absolute right-0 z-20 mt-2 w-72 rounded-xl border border-bordi bg-card p-2 shadow-xl">
            {accountMenuItems(false)}
          </div>
        )}
        <BottomSheet
          open={menuOpen && isMobile}
          onClose={() => setMenuOpen(false)}
          label={t("connect.walletOptions")}
        >
          {accountMenuItems(true)}
        </BottomSheet>
      </div>
    );
  }

  return (
    <div className="relative" ref={menuRef}>
      <button
        className="btn-oro whitespace-nowrap"
        onClick={() => setMenuOpen((v) => !v)}
        disabled={isPending}
        aria-expanded={menuOpen}
      >
        {isPending ? t("connect.connecting") : connectLabel}
      </button>
      {menuOpen && !isMobile && (
        <div className="absolute right-0 z-20 mt-2 w-56 rounded-xl border border-bordi bg-card p-2 shadow-xl">
          {connectorItems(false)}
        </div>
      )}
      <BottomSheet
        open={menuOpen && isMobile}
        onClose={() => setMenuOpen(false)}
        label={t("connect.connect")}
      >
        {connectorItems(true)}
      </BottomSheet>
    </div>
  );
}
