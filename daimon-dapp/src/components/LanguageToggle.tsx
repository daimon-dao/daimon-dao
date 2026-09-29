"use client";

import { useI18n } from "@/components/LocaleProvider";
import type { Locale } from "@/lib/i18n";

/*
 * Language selector EN | IT: the choice persists in a cookie (read by the
 * server on the next request) and the UI changes immediately, without a reload
 * — the wallet connection and the pages' state are not touched.
 */
export function LanguageToggle() {
  const { locale, setLocale, t } = useI18n();
  const options: Locale[] = ["en", "it"];
  return (
    <div
      className="flex overflow-hidden rounded-lg border border-bordi text-sm"
      role="group"
      aria-label={t("header.changeLanguage")}
    >
      {options.map((l) => (
        <button
          key={l}
          onClick={() => setLocale(l)}
          className={`px-2.5 py-2 uppercase ${
            locale === l
              ? "bg-oro/15 font-medium text-oro"
              : "text-secondario hover:text-testo"
          }`}
          aria-pressed={locale === l}
        >
          {l}
        </button>
      ))}
    </div>
  );
}
