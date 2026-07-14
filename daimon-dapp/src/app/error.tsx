"use client";

import { useEffect } from "react";

/*
 * Error boundary di route (convenzione App Router): se un errore di render
 * sfugge a tutto il resto, l'utente vede questo pannello sobrio invece di
 * una pagina rotta o dell'overlay. I dettagli finiscono in console.
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[error boundary]", error);
  }, [error]);

  return (
    <div className="mx-auto max-w-lg py-16 text-center">
      <p className="text-3xl">⚠️</p>
      <h1 className="mt-3 text-xl font-semibold text-orochiaro">
        Qualcosa è andato storto
      </h1>
      <p className="mt-2 text-sm text-secondario">
        Si è verificato un errore imprevisto nell&apos;interfaccia. I tuoi
        fondi on-chain non sono toccati da errori di visualizzazione.
      </p>
      <button className="btn-oro mt-5" onClick={reset}>
        Riprova
      </button>
    </div>
  );
}
