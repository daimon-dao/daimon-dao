"use client";

import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { mapTxError } from "@/lib/errors";

export type TxPhase = "idle" | "signing" | "pending" | "success" | "error";

/*
 * Ciclo di vita di una transazione (DAPP_SPEC.md §8.2):
 * in attesa di firma -> pending -> confermata/fallita, con hash per il
 * link a BscScan e errore gia' tradotto in italiano.
 *
 * REFETCH AUTOMATICO: alla CONFERMA on-chain (receipt success) vengono
 * invalidate tutte le query wagmi/react-query attive, cosi' barre di voto,
 * saldi, allowance, posizioni e reward si aggiornano da soli su ogni
 * pagina, senza refresh manuale. (Un refetch chiamato subito dopo la
 * firma leggerebbe ancora lo stato pre-transazione.)
 */
export function useTx() {
  const queryClient = useQueryClient();

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

  // Invalida una sola volta per hash confermato.
  const invalidatedFor = useRef<`0x${string}` | null>(null);
  useEffect(() => {
    if (receipt.isSuccess && hash && invalidatedFor.current !== hash) {
      invalidatedFor.current = hash;
      queryClient.invalidateQueries();
    }
  }, [receipt.isSuccess, hash, queryClient]);

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
