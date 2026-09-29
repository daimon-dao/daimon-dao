import { createConnector } from "wagmi";
import { injected } from "wagmi/connectors";
import type { EIP1193Provider } from "viem";

/*
 * Wallet in-app browsers (MetaMask, Trust Wallet, Binance Web3 wallet, ...).
 *
 * Inside one, the wallet IS the browser: it injects its provider into the
 * page, and "Connect" must go straight to it -- one tap, no connector menu,
 * never a WalletConnect QR. This module
 *  - detects the injected wallet: its EIP-6963 announcement first,
 *    window.ethereum as the fallback, including wallets that inject after our
 *    scripts have run (the ethereum#initialized event, plus a short poll);
 *  - provides the wagmi connector for it, which asks the wallet for accounts
 *    with eth_requestAccounts ONLY. wagmi's stock injected connector first
 *    sends wallet_requestPermissions, which mobile wallets handle
 *    inconsistently -- one that never answers it leaves "Connect" hanging
 *    with no prompt, the in-app bug this fixes.
 *
 * Imported by the wagmi config, which also runs on the server: nothing here
 * touches window before being called in the browser.
 */

export const IN_APP_CONNECTOR_ID = "inAppWallet";
const DISCONNECTED_FLAG = `${IN_APP_CONNECTOR_ID}.disconnected`;
// How long after load a late-injecting wallet is waited for.
const DETECTION_WINDOW_MS = 2500;

type ProviderDetail = {
  info: { uuid: string; name: string; icon: string; rdns: string };
  provider: EIP1193Provider;
};

const announced: ProviderDetail[] = [];
const listeners = new Set<() => void>();
let startedAt = 0;

function notify() {
  listeners.forEach((l) => l());
}

function windowEthereum(): EIP1193Provider | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as { ethereum?: EIP1193Provider }).ethereum;
}

function start() {
  if (typeof window === "undefined" || startedAt) return;
  startedAt = Date.now();
  window.addEventListener("eip6963:announceProvider", (e) => {
    const detail = (e as CustomEvent<ProviderDetail>).detail;
    if (!detail?.provider || !detail.info?.uuid) return;
    if (announced.some((d) => d.info.uuid === detail.info.uuid)) return;
    announced.push(detail);
    notify();
  });
  window.dispatchEvent(new Event("eip6963:requestProvider"));
  // window.ethereum may appear after our scripts ran: MetaMask signals it
  // with ethereum#initialized, other wallets say nothing, hence the poll.
  window.addEventListener("ethereum#initialized", notify, { once: true });
  let seen = Boolean(windowEthereum());
  const poll = window.setInterval(() => {
    if (!seen && windowEthereum()) {
      seen = true;
      notify();
    }
  }, 200);
  window.setTimeout(() => window.clearInterval(poll), DETECTION_WINDOW_MS);
}

/** The injected wallet: its EIP-6963 announcement first, window.ethereum as fallback. */
export function getInjectedWallet(): { provider: EIP1193Provider; name?: string; rdns?: string } | undefined {
  start();
  const d = announced[0];
  if (d) return { provider: d.provider, name: d.info.name, rdns: d.info.rdns };
  const eth = windowEthereum();
  return eth ? { provider: eth } : undefined;
}

/** A phone or tablet (UA, plus iPadOS, which reports a desktop Mac UA). */
export function isMobileDevice(): boolean {
  if (typeof navigator === "undefined") return false;
  if (/Android|iPhone|iPad|iPod|Mobile|Opera Mini|IEMobile/i.test(navigator.userAgent)) return true;
  return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1;
}

/** In a wallet's in-app browser: a mobile device with an injected wallet. */
export function isInAppWallet(): boolean {
  return isMobileDevice() && Boolean(getInjectedWallet());
}

export function subscribeInjectedWallet(cb: () => void): () => void {
  start();
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

/**
 * true as soon as an injected wallet is known; within the first moments after
 * load, waits for a late injection instead of concluding "none".
 */
export function waitForInjectedWallet(): Promise<boolean> {
  start();
  if (getInjectedWallet()) return Promise.resolve(true);
  const remaining = startedAt + DETECTION_WINDOW_MS - Date.now();
  if (remaining <= 0) return Promise.resolve(false);
  return new Promise((resolve) => {
    const finish = (found: boolean) => {
      unsubscribe();
      window.clearTimeout(timer);
      resolve(found);
    };
    const unsubscribe = subscribeInjectedWallet(() => {
      if (getInjectedWallet()) finish(true);
    });
    const timer = window.setTimeout(() => finish(Boolean(getInjectedWallet())), remaining);
  });
}

/*
 * Disconnect memory, shared. In an in-app browser the same wallet is reachable
 * through three connectors: this one, wagmi's generic `injected`, and the one
 * wagmi's EIP-6963 discovery creates (id = the wallet's rdns). wagmi's
 * reconnect tries them all on every page load, so a "Disconnect" made
 * through any of them must hold for all three -- otherwise the next load
 * reconnects silently through another (a wallet that cannot revoke its
 * permission keeps answering eth_accounts).
 */
type FlagStorage =
  | { getItem(k: string): unknown; setItem(k: string, v: unknown): unknown; removeItem(k: string): unknown }
  | null
  | undefined;

function disconnectFlags(): string[] {
  const rdns = getInjectedWallet()?.rdns;
  return [DISCONNECTED_FLAG, "injected.disconnected", ...(rdns ? [`${rdns}.disconnected`] : [])];
}

/** Marks the in-app wallet disconnected for every connector that reaches it. */
export async function rememberInAppDisconnect(storage: unknown): Promise<void> {
  for (const k of disconnectFlags()) await (storage as FlagStorage)?.setItem(k, true);
}

async function anyDisconnectFlag(storage: FlagStorage): Promise<boolean> {
  for (const k of disconnectFlags()) if (await storage?.getItem(k)) return true;
  return false;
}

/*
 * The in-app connector: wagmi's injected connector aimed at the detected
 * wallet, with shimDisconnect off (so connect() goes straight to
 * eth_requestAccounts), and the shared disconnect memory above in place of the
 * shim. Its provider exists only on a mobile device, so on desktop wagmi's
 * reconnect never picks it and the extension keeps its usual connectors.
 */
export function inAppWallet() {
  return createConnector((config) => {
    const base = injected({
      shimDisconnect: false,
      target: {
        id: IN_APP_CONNECTOR_ID,
        name: "In-app wallet",
        provider: () => (isMobileDevice() ? getInjectedWallet()?.provider : undefined),
      },
    })(config);
    const storage = config.storage as FlagStorage;
    // Same signature as the base connect (generic over withCapabilities).
    const connect = async function (this: typeof base, parameters?: Parameters<typeof base.connect>[0]) {
      const result = await base.connect.call(this, parameters);
      // An explicit connect lifts the memory (reconnects pass isReconnecting
      // and only happen when no flag is set anyway).
      for (const k of disconnectFlags()) await storage?.removeItem(k);
      return result;
    } as typeof base.connect;
    return {
      ...base,
      connect,
      async disconnect() {
        await base.disconnect.call(this);
        await rememberInAppDisconnect(storage);
      },
      async isAuthorized() {
        if (await anyDisconnectFlag(storage)) return false;
        return base.isAuthorized.call(this);
      },
    };
  });
}
