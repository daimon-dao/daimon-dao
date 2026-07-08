"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { mapTxError } from "@/lib/errors";

export type TxPhase = "idle" | "signing" | "pending" | "success" | "error";

/*
 * Ciclo di vita di una transazione (DAPP_SPEC.md §8.2):
 * in attesa di firma -> pending -> confermata/fallita, con hash per il
 * link a BscScan e errore gia' tradotto in italiano.
 */
export function useTx() {
  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    error: writeError,
    reset,
  } = useWriteContract();

  const receipt = useWaitForTransactionReceipt({
    hash,
    query: { enabled: Boolean(hash) },
  });

  let phase: TxPhase = "idle";
  if (isSigning) phase = "signing";
  else if (writeError) phase = "error";
  else if (hash && receipt.isLoading) phase = "pending";
  else if (hash && receipt.isSuccess) phase = "success";
  else if (hash && receipt.isError) phase = "error";

  const errorMessage = writeError
    ? mapTxError(writeError)
    : receipt.isError
      ? "La transazione è fallita on-chain."
      : null;

  return { send: writeContractAsync, phase, hash, errorMessage, reset };
}
