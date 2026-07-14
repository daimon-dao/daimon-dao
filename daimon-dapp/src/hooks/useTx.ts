"use client";

import { useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { mapTxError, isUserRejection } from "@/lib/errors";

export type TxPhase = "idle" | "signing" | "pending" | "success" | "error";

/*
 * Ciclo di vita di una transazione (DAPP_SPEC.md §8.2):
 * in attesa di firma -> pending -> confermata/fallita, con hash per il
 * link a BscScan e errore gia' tradotto in italiano.
 *
 * REFETCH AUTOMATICO: alla CONFERMA on-chain (receipt success) vengono
 * invalidate tutte le query wagmi/react-query attive, cosi' barre di voto,
 * saldi, allowance, posizioni e reward si aggiornano da soli su ogni
 * pagina, senza refresh manuale.
 *
 * GESTIONE ERRORI STRUTTURALE: send() non rigetta MAI (niente unhandled
 * rejection dagli onClick, quindi niente overlay di Next). Tre casi:
 *  (a) rifiuto dell'utente nel wallet (4001) -> azione normale: reset
 *      silenzioso dello stato + avviso neutro "Transazione annullata";
 *  (b) revert del contratto -> phase "error" con messaggio italiano
 *      mappato (mapTxError);
 *  (c) errore imprevisto -> phase "error" con messaggio generico,
 *      dettagli completi in console per il debug.
 */
export function useTx() {
  const queryClient = useQueryClient();
  const [notice, setNotice] = useState<string | null>(null);

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

  async function send(
    args: Parameters<typeof writeContractAsync>[0]
  ): Promise<`0x${string}` | null> {
    setNotice(null);
    try {
      return await writeContractAsync(args);
    } catch (err) {
      if (isUserRejection(err)) {
        // (a) Rifiutare una firma non e' un errore: stato riportato a
        // idle e avviso neutro, nessun rosso, nessun overlay.
        reset();
        setNotice("Transazione annullata nel wallet.");
      } else {
        // (b)/(c) wagmi ha gia' registrato writeError: la fase diventa
        // "error" e TxStatus mostra il messaggio mappato in italiano.
        // I dettagli grezzi restano in console per il debug.
        console.error("[useTx] transazione non inviata:", err);
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

  const errorMessage = writeError
    ? mapTxError(writeError)
    : receipt.isError
      ? "La transazione è fallita on-chain."
      : null;

  return { send, phase, hash, errorMessage, notice, reset };
}
