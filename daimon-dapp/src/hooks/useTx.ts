"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useConfig, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { waitForTransactionReceipt } from "wagmi/actions";
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
  const config = useConfig();
  const [notice, setNotice] = useState<string | null>(null);

  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    error: writeError,
    reset,
  } = useWriteContract();

  // Il receipt hook alimenta le fasi UI (pending/success) finche' il
  // componente e' montato; l'INVALIDAZIONE invece e' imperativa (sotto),
  // cosi' non dipende dalla vita del componente.
  const receipt = useWaitForTransactionReceipt({
    hash,
    query: { enabled: Boolean(hash) },
  });

  async function send(
    args: Parameters<typeof writeContractAsync>[0]
  ): Promise<`0x${string}` | null> {
    setNotice(null);
    try {
      const txHash = await writeContractAsync(args);
      // Invalidazione GARANTITA alla conferma: promise imperativa che
      // sopravvive anche se il componente che ha lanciato la transazione
      // viene smontato prima del receipt (es. l'utente chiude il form
      // avanzato subito dopo il submit — il bug della proposta #1).
      // Un useEffect legato all'hook, invece, muore con l'unmount.
      waitForTransactionReceipt(config, { hash: txHash })
        .then((r) => {
          if (r.status === "success") queryClient.invalidateQueries();
        })
        .catch(() => {});
      return txHash;
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
