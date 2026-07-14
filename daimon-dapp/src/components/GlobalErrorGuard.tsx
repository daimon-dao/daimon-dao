"use client";

import { useEffect, useState } from "react";

/*
 * Rete di sicurezza finale contro gli unhandled rejection che sfuggono ai
 * flussi gestiti — in particolare gli eventi asincroni delle librerie
 * wallet che vivono FUORI dalle nostre promise (es. "Proposal expired" di
 * @walletconnect/utils quando il QR scade dopo minuti).
 *
 * Politica: MAI l'overlay rosso di Next.
 *  - eventi benigni noti (QR scaduto, firma rifiutata): console.info,
 *    con toast discreto solo dove utile all'utente;
 *  - tutto il resto: console.error con i dettagli completi + toast
 *    generico. L'overlay e' soppresso ma nulla viene nascosto al debug.
 */
export function GlobalErrorGuard() {
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    let timer: number | undefined;
    function show(msg: string) {
      setToast(msg);
      window.clearTimeout(timer);
      timer = window.setTimeout(() => setToast(null), 6000);
    }

    // Eventi benigni noti delle librerie wallet: vanno intercettati PRIMA
    // che il dev-overlay di Next (bubble phase) li mostri. Capture phase +
    // stopImmediatePropagation impedisce ad altri listener di reagire.
    function isBenign(reason: { code?: number; message?: string } | null, msg: string) {
      return (
        /proposal expired|session request expired/i.test(msg) ||
        reason?.code === 4001 ||
        /user rejected|user denied|connection request reset|request expired/i.test(msg)
      );
    }

    function onRejection(e: PromiseRejectionEvent) {
      const reason = e.reason as { code?: number; message?: string } | null;
      const msg = reason?.message ?? String(e.reason ?? "");

      if (isBenign(reason, msg)) {
        e.preventDefault();
        e.stopImmediatePropagation();
        if (/proposal expired|session request expired|request expired/i.test(msg)) {
          console.info("[wallet] richiesta WalletConnect scaduta (QR non usato in tempo)");
          show("Connessione scaduta, riprova.");
        } else {
          console.info("[wallet] richiesta rifiutata/annullata dall'utente");
          // nessun toast: l'ha deciso l'utente
        }
        return;
      }

      // Errore imprevisto: sopprimiamo comunque l'overlay ma logghiamo tutto
      // e avvisiamo con un toast generico (mai una pagina rossa).
      e.preventDefault();
      console.error("[global] unhandled rejection:", e.reason);
      show("Si è verificato un errore imprevisto. Dettagli nella console.");
    }

    // capture: true -> il nostro handler precede quelli in bubble (Next).
    window.addEventListener("unhandledrejection", onRejection, { capture: true });
    return () => {
      window.removeEventListener("unhandledrejection", onRejection, { capture: true });
      window.clearTimeout(timer);
    };
  }, []);

  if (!toast) return null;
  return (
    <div
      role="status"
      className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 rounded-lg border border-bordi bg-card px-4 py-2.5 text-sm text-testo shadow-xl"
    >
      {toast}
    </div>
  );
}
