"use client";

import { useEffect } from "react";
import { useI18n } from "@/components/LocaleProvider";

/*
 * Route error boundary (App Router convention): if a render error escapes
 * everything else, the user sees this sober panel instead of a broken page or
 * the overlay. The details go to the console. It renders inside the root
 * layout, so the LocaleProvider is available.
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
