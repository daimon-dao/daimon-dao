"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useConfig, useConnect, useDisconnect, useSwitchChain, type Connector } from "wagmi";
import { ACTIVE_CHAIN, explorerAddress } from "@/config/contracts";
import { shortAddress } from "@/lib/format";
import { isUserRejection } from "@/lib/errors";
import {
  IN_APP_CONNECTOR_ID,
  isInAppWallet,
  isMobileDevice,
  rememberInAppDisconnect,
  subscribeInjectedWallet,
  waitForInjectedWallet,
} from "@/lib/injectedWallet";
import { useI18n } from "@/components/LocaleProvider";
import { BottomSheet, useIsMobile } from "@/components/BottomSheet";
import { useTerms } from "@/components/TermsGate";

export function ConnectButton() {
  const { t } = useI18n();
  const { accepted: termsAccepted, requestTerms } = useTerms();
  const [mounted, setMounted] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const [connectError, setConnectError] = useState<string | null>(null);
  const errorTimer = useRef<number | undefined>(undefined);
  const menuRef = useRef<HTMLDivElement>(null);
  const isMobile = useIsMobile();
  const { address, isConnected, chainId, connector } = useAccount();
  const { connectors, connectAsync, isPending } = useConnect();
  const { disconnectAsync } = useDisconnect();
  const config = useConfig();
  const { switchChain } = useSwitchChain();

  // Wallet in-app browser (mobile + injected wallet): known only in the
  // browser, and it can change after load (late injection) -> state, updated
  // on every detection event.
  const [inApp, setInApp] = useState(false);
  const [mobileDevice, setMobileDevice] = useState(false);
  useEffect(() => {
    setMobileDevice(isMobileDevice());
    setInApp(isInAppWallet());
    return subscribeInjectedWallet(() => setInApp(isInAppWallet()));
  }, []);

  useEffect(() => setMounted(true), []);
  useEffect(() => () => window.clearTimeout(errorTimer.current), []);

  function showConnectError(msg: string) {
    setConnectError(msg);
    window.clearTimeout(errorTimer.current);
    errorTimer.current = window.setTimeout(() => setConnectError(null), 8000);
  }

  // Every connection attempt goes through here: a rejection in the wallet is
  // the user's choice (silent); anything else is SAID, never swallowed.
  async function connectWith(c: Connector) {
    setConnectError(null);
    try {
      await connectAsync({ connector: c });
    } catch (err) {
      if (isUserRejection(err)) return;
      const e = err as { name?: string; code?: number };
      if (e?.name === "ConnectorAlreadyConnectedError") return;
      console.error("[connect] wallet connection failed:", err);
      if (e?.name === "ProviderNotFoundError") showConnectError(t("connect.errorNoWallet"));
      else if (e?.code === -32002 || e?.name === "ResourceUnavailableRpcError")
        showConnectError(t("connect.errorPending"));
      else showConnectError(t("connect.errorGeneric"));
    }
  }

  /*
   * The Connect tap. Terms first, always. Then, inside a wallet's in-app
   * browser, straight to that wallet: one tap, no menu, no WalletConnect.
   * Everywhere else, the connector menu (desktop dropdown / mobile sheet).
   */
  async function onConnectTap() {
    setConnectError(null);
    if (!termsAccepted) {
      requestTerms();
      return;
    }
    if (menuOpen) {
      setMenuOpen(false);
      return;
    }
    const inAppConnector = connectors.find((c) => c.id === IN_APP_CONNECTOR_ID);
    // On a phone, a wallet that injects late is waited for briefly.
    if (inAppConnector && isMobileDevice() && (inApp || (await waitForInjectedWallet()))) {
      await connectWith(inAppConnector);
      return;
    }
    setMenuOpen(true);
  }
  // Close on outside click: ONLY for the desktop dropdown — the bottom sheet
  // lives in a portal outside menuRef (it closes with its own backdrop).
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
      // Fallback for contexts where the Clipboard API is denied.
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

  // Opens the wallet's account picker WITHOUT disconnecting: when another
  // account is chosen MetaMask emits accountsChanged and wagmi updates.
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
      /* user rejection or unsupported wallet: no error */
    }
  }

  // Compact label below sm: "Connect"/"Connetti" on ONE line — the full text
  // broke the header at 360-428px (post-i18n bug).
  const connectLabel = (
    <>
      <span className="sm:hidden">{t("connect.connectShort")}</span>
      <span className="hidden sm:inline">{t("connect.connect")}</span>
    </>
  );

  /*
   * Contents of the two menus, shared between the dropdown (>=sm) and the
   * bottom sheet (<sm). In the sheet the tap targets grow to >=44px (py-3,
   * base text).
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
          onClick={async () => {
            setMenuOpen(false);
            await disconnectAsync().catch(() => {});
            // In-app, the same wallet sits behind several connectors: the
            // disconnect must hold for all of them (src/lib/injectedWallet.ts).
            if (inApp) await rememberInAppDisconnect(config.storage);
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
    // The in-app connector never appears in the menu (it has its own one-tap
    // path). On a phone the menu only opens when no wallet is injected, so the
    // browser-wallet entries could not work there: WalletConnect only.
    const shown = connectors.filter(
      (c) => c.id !== IN_APP_CONNECTOR_ID && !(mobileDevice && c.type === "injected")
    );
    return (
      <>
        {shown.map((c) => (
          <button
            key={c.uid}
            className={item}
            onClick={() => {
              setMenuOpen(false);
              void connectWith(c);
            }}
          >
            {c.name === "Injected" ? t("connect.injectedName") : c.name}
          </button>
        ))}
        <p className={`px-3 pt-1 text-xs text-secondario ${sheet ? "px-4 pb-1" : ""}`}>
          {mobileDevice ? t("connect.mobileHint") : t("connect.injectedHint")}
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
    // Exploratory click -> options menu, NEVER a direct disconnect.
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
        // Terms first, then in-app one tap or the menu (onConnectTap).
        onClick={() => void onConnectTap()}
        // In-app, a second tap while pending re-asks the wallet (which answers
        // "request already open" -> a message) instead of a dead button.
        disabled={isPending && !inApp}
        aria-expanded={menuOpen}
      >
        {isPending ? t("connect.connecting") : connectLabel}
      </button>
      {connectError && (
        <div
          role="status"
          className="absolute right-0 z-20 mt-2 w-64 rounded-xl border border-rosso/40 bg-card p-3 text-xs leading-snug text-testo shadow-xl"
          onClick={() => setConnectError(null)}
        >
          {connectError}
        </div>
      )}
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
