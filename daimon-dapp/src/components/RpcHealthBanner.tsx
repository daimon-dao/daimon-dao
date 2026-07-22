"use client";

import { useEffect, useState } from "react";
import { onlineManager } from "@tanstack/react-query";
import { getBlockNumber } from "viem/actions";
import { useClient } from "wagmi";
import { useI18n } from "@/components/LocaleProvider";

/*
 * Sonda di salute dell'RPC: ogni 15s chiede il numero di blocco tramite lo
 * STESSO transport viem della dApp. Due fallimenti consecutivi (~30s) →
 * banner discreto: i dati potrebbero non essere aggiornati. Sparisce da
 * solo alla prima lettura riuscita (il recupero dei dati e' automatico via
 * react-query, nessun refresh manuale richiesto).
 *
 * Volutamente NON usa react-query: le sue query wagmi girano in networkMode
 * offlineFirst e vanno in "paused" (mai in errore) quando l'onlineManager
 * crede il device offline — che e' esattamente uno dei casi da segnalare.
 * setInterval + try/catch non ha stati intermedi.
 */
export function RpcHealthBanner() {
  const { t } = useI18n();
  const client = useClient();
  const [failures, setFailures] = useState(0);

  useEffect(() => {
    if (!client) return;
    let alive = true;
    async function probe() {
      try {
        // Azione esplicita: il client di useClient() non ha i metodi estesi.
        await getBlockNumber(client!);
        if (!alive) return;
        setFailures(0);
        // L'RPC risponde: se react-query si crede "offline" (evento online
        // mai arrivato — capita su WebView e reti instabili), le query dati
        // resterebbero in pausa per sempre. La sonda che riesce E' la prova
        // di connettivita': sblocchiamo l'onlineManager e le query riprendono.
        if (!onlineManager.isOnline()) onlineManager.setOnline(true);
      } catch {
        if (alive) setFailures((f) => f + 1);
      }
    }
    probe();
    const iv = window.setInterval(probe, 15_000);
    return () => {
      alive = false;
      window.clearInterval(iv);
    };
  }, [client]);

  if (failures < 2) return null;
  return (
    <div className="border-b border-oro/40 bg-oro/10 px-4 py-1.5 text-center text-xs text-oro">
      {t("rpc.degraded")}
    </div>
  );
}
