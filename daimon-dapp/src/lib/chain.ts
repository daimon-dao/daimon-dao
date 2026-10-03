import type { Connector } from "wagmi";
import { numberToHex } from "viem";
import { ACTIVE_CHAIN } from "@/config/contracts";

/*
 * "Is the wallet on the active chain?" answered by the wallet itself.
 *
 * wagmi keeps the chain id it was told at connection time and updates it on
 * the wallet's chainChanged event. A wallet that reports one chain while
 * connecting and settles on another without saying so (seen with the MetaMask
 * in-app browser on BNB Smart Chain: the dApp asked to switch to the chain the
 * wallet was already on) leaves that value stale. So before the dApp asks for
 * a switch, or shows the "switch to" button, it asks the provider for
 * eth_chainId once more and trusts that answer; when it differs from wagmi's,
 * wagmi is re-aligned through the connector's own onChainChanged, the same
 * path a real chainChanged event takes.
 */
type Eip1193 = { request(args: { method: string; params?: unknown[] }): Promise<unknown> };

/** The chain the wallet is on right now, straight from the provider (undefined if it cannot say). */
export async function walletChainId(connector: Connector | undefined): Promise<number | undefined> {
  try {
    const provider = (await connector?.getProvider()) as Eip1193 | undefined;
    const hex = await provider?.request({ method: "eth_chainId" });
    const id = typeof hex === "string" || typeof hex === "number" ? Number(hex) : NaN;
    return Number.isInteger(id) && id > 0 ? id : undefined;
  } catch {
    return undefined;
  }
}

/**
 * true when the wallet is on ACTIVE_CHAIN. `reported` is wagmi's current value:
 * when it already says the active chain nothing is asked; otherwise the
 * provider is consulted and, if it disagrees with wagmi, wagmi is re-synced.
 */
export async function isOnActiveChain(
  connector: Connector | undefined,
  reported: number | undefined
): Promise<boolean> {
  if (reported === ACTIVE_CHAIN.id) return true;
  const actual = await walletChainId(connector);
  if (actual === undefined) return reported === undefined;
  if (actual !== reported) {
    console.warn(`[chain] wallet reports chain ${actual}, wagmi had ${reported}: re-syncing`);
    connector?.onChainChanged(numberToHex(actual));
  }
  return actual === ACTIVE_CHAIN.id;
}
