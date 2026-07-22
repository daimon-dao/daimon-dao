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
 * Ciclo di vita di una transazione (DAPP_SPEC.md §8.2):
 * in attesa di firma -> pending -> confermata/fallita, con hash per il
 * link a BscScan e errore gia' tradotto nella lingua della UI.
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
 *
 * GUARDIA DI RETE: prima di OGNI firma, se il wallet e' su una chain
 * diversa da quella attesa viene richiesto lo switch; la firma parte solo
 * a switch riuscito (e con chainId esplicito come seconda cintura).
 * Mai piu' richieste di firma sulla chain sbagliata.
 */
export function useTx() {
  const queryClient = useQueryClient();
  const config = useConfig();
  const { t, locale } = useI18n();
  const [notice, setNotice] = useState<string | null>(null);

  // Gli avvisi neutri si auto-dissolvono (o spariscono alla prossima azione).
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
    window.clearTimeout(noticeTimer.current);
    setNotice(null);

    // Guardia di rete: il wallet potrebbe essere su un'altra chain (es.
    // BSC mainnet). Lo switch viene richiesto PRIMA della firma; se
    // l'utente lo rifiuta, nessuna transazione parte.
    const { chainId } = getAccount(config);
    if (chainId !== undefined && chainId !== ACTIVE_CHAIN.id) {
      try {
        await switchChain(config, { chainId: ACTIVE_CHAIN.id });
      } catch (err) {
        if (isUserRejection(err)) {
          showNotice(t("tx.switchCanceled"));
        } else {
          console.error("[useTx] cambio rete fallito:", err);
          showNotice(t("tx.switchFailed", { chain: ACTIVE_CHAIN.name }));
        }
        return null;
      }
    }

    try {
      // chainId esplicito: anche se lo stato del connettore fosse
      // disallineato, wagmi rifiuta la firma su una chain diversa.
      const txHash = await writeContractAsync({ ...args, chainId: ACTIVE_CHAIN.id });
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
        // idle e avviso neutro auto-dissolvente, nessun rosso, nessun overlay.
        reset();
        showNotice(t("tx.canceledInWallet"));
      } else if (isChainMismatch(err)) {
        // Rete sbagliata sfuggita alla guardia (es. stato del connettore
        // disallineato): viem ha comunque RIFIUTATO di firmare sulla chain
        // errata. reset() toglie la fase error, poi avviso neutro.
        reset();
        showNotice(t("tx.switchAndRetry", { chain: ACTIVE_CHAIN.name }));
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

  // Calcolato a ogni render con la lingua attiva: un cambio lingua a
  // transazione in corso aggiorna anche il messaggio d'errore.
  const errorMessage = writeError
    ? mapTxError(writeError, locale)
    : receipt.isError
      ? t("tx.failedOnChain")
      : null;

  return { send, phase, hash, errorMessage, notice, reset };
}
