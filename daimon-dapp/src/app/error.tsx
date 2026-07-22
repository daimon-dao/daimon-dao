"use client";

import { useEffect } from "react";
import { useI18n } from "@/components/LocaleProvider";

/*
 * Error boundary di route (convenzione App Router): se un errore di render
 * sfugge a tutto il resto, l'utente vede questo pannello sobrio invece di
 * una pagina rotta o dell'overlay. I dettagli finiscono in console.
 * Renderizza dentro il root layout, quindi il LocaleProvider e' disponibile.
 */
export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const { t } = useI18n();

  useEffect(() => {
    console.error("[error boundary]", error);
  }, [error]);

  return (
    <div className="mx-auto max-w-lg py-16 text-center">
      <p className="text-3xl">⚠️</p>
      <h1 className="mt-3 text-xl font-semibold text-orochiaro">
        {t("errorPage.title")}
      </h1>
      <p className="mt-2 text-sm text-secondario">{t("errorPage.message")}</p>
      <button className="btn-oro mt-5" onClick={reset}>
        {t("errorPage.retry")}
      </button>
    </div>
  );
}
