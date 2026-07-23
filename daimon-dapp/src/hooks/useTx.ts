"use client";

import { useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useConfig, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { getAccount, switchChain, waitForTransactionReceipt } from "wagmi/actions";
import { ACTIVE_CHAIN } from "@/config/contracts";
import { mapTxError, isUserRejection, isChainMismatch } from "@/lib/errors";
import { useI18n } from "@/components/LocaleProvider";

export type TxPhase = "idle" | "signing" | "pending" | "success" | "error";

/*
 * Transaction lifecycle (DAPP_SPEC.md §8.2):
 * awaiting signature -> pending -> confirmed/failed, with the hash for the
 * BscScan link and the error already translated into the UI language.
 *
 * AUTOMATIC REFETCH: on the on-chain CONFIRMATION (receipt success) all the
 * active wagmi/react-query queries are invalidated, so voting bars, balances,
 * allowances, positions and rewards refresh on their own on every page,
 * without a manual refresh.
 *
 * STRUCTURAL ERROR HANDLING: send() NEVER rejects (no unhandled rejection from
 * the onClick handlers, hence no Next overlay). Three cases:
 *  (a) user rejection in the wallet (4001) -> normal action: silent state
 *      reset + neutral "Transaction canceled" notice;
 *  (b) contract revert -> phase "error" with the mapped, localized message
 *      (mapTxError);
 *  (c) unexpected error -> phase "error" with a generic message, full details
 *      in the console for debugging.
 *
 * NETWORK GUARD: before EVERY signature, if the wallet is on a chain different
 * from the expected one a switch is requested; the signature only starts once
 * the switch succeeds (and with an explicit chainId as a second belt).
 * Never again a signature request on the wrong chain.
 */
export function useTx() {
  const queryClient = useQueryClient();
  const config = useConfig();
  const { t, locale } = useI18n();
  const [notice, setNotice] = useState<string | null>(null);

  // Neutral notices auto-dismiss (or disappear on the next action).
  const noticeTimer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(noticeTimer.current), []);
  function showNotice(msg: string) {
    setNotice(msg);
    window.clearTimeout(noticeTimer.current);
    noticeTimer.current = window.setTimeout(() => setNotice(null), 6000);
  }

  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    error: writeError,
    reset,
  } = useWriteContract();

  // The receipt hook feeds the UI phases (pending/success) while the component
  // is mounted; the INVALIDATION, instead, is imperative (below), so it does
  // not depend on the component's lifetime.
  const receipt = useWaitForTransactionReceipt({
    hash,
    query: { enabled: Boolean(hash) },
  });

  async function send(
    args: Parameters<typeof writeContractAsync>[0]
  ): Promise<`0x${string}` | null> {
    window.clearTimeout(noticeTimer.current);
    setNotice(null);

    // Network guard: the wallet might be on another chain (e.g. BSC mainnet).
    // The switch is requested BEFORE the signature; if the user rejects it, no
    // transaction starts.
    const { chainId } = getAccount(config);
    if (chainId !== undefined && chainId !== ACTIVE_CHAIN.id) {
      try {
        await switchChain(config, { chainId: ACTIVE_CHAIN.id });
      } catch (err) {
        if (isUserRejection(err)) {
          showNotice(t("tx.switchCanceled"));
        } else {
          console.error("[useTx] network switch failed:", err);
          showNotice(t("tx.switchFailed", { chain: ACTIVE_CHAIN.name }));
        }
        return null;
      }
    }

    try {
      // explicit chainId: even if the connector state were misaligned, wagmi
      // refuses the signature on a different chain.
      const txHash = await writeContractAsync({ ...args, chainId: ACTIVE_CHAIN.id });
      // GUARANTEED invalidation on confirmation: an imperative promise that
      // survives even if the component that launched the transaction is
      // unmounted before the receipt (e.g. the user closes the advanced form
      // right after submit — the proposal #1 bug). A useEffect tied to the
      // hook, instead, dies with the unmount.
      waitForTransactionReceipt(config, { hash: txHash })
        .then((r) => {
          if (r.status === "success") queryClient.invalidateQueries();
        })
        .catch(() => {});
      return txHash;
    } catch (err) {
      if (isUserRejection(err)) {
        // (a) Rejecting a signature is not an error: state brought back to
        // idle and an auto-dismissing neutral notice, no red, no overlay.
        reset();
        showNotice(t("tx.canceledInWallet"));
      } else if (isChainMismatch(err)) {
        // Wrong network that slipped past the guard (e.g. misaligned connector
        // state): viem REFUSED to sign on the wrong chain anyway. reset()
        // clears the error phase, then a neutral notice.
        reset();
        showNotice(t("tx.switchAndRetry", { chain: ACTIVE_CHAIN.name }));
      } else {
        // (b)/(c) wagmi has already recorded writeError: the phase becomes
        // "error" and TxStatus shows the mapped, localized message.
        // The raw details remain in the console for debugging.
        console.error("[useTx] transaction not sent:", err);
      }
      return null;
    }
  }

  let phase: TxPhase = "idle";
  if (isSigning) phase = "signing";
  else if (writeError) phase = "error";
  else if (hash && receipt.isLoading) phase = "pending";
  else if (hash && receipt.isSuccess) phase = "success";
  else if (hash && receipt.isError) phase = "error";

  // Computed on every render with the active language: a language change
  // during an ongoing transaction also updates the error message.
  const errorMessage = writeError
    ? mapTxError(writeError, locale)
    : receipt.isError
      ? t("tx.failedOnChain")
      : null;

  return { send, phase, hash, errorMessage, notice, reset };
}
