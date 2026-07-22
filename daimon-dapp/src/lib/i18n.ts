import en from "@/messages/en.json";
import it from "@/messages/it.json";

/*
 * i18n minimale a dizionari (DAPP_SPEC.md §9): DUE lingue, poche centinaia
 * di stringhe — un provider React + lookup con interpolazione bastano.
 * Niente next-intl: nessun routing per-locale, nessun middleware, e
 * l'hydration resta sotto controllo diretto (il server legge il cookie e
 * passa la stessa lingua al provider client → HTML identico).
 *
 * Questo modulo e' universale (nessuna direttiva): usato dal root layout
 * lato server (metadata, lang) e dal provider lato client.
 */
export type Locale = "en" | "it";

export const LOCALE_COOKIE = "daimon-locale";
export const DEFAULT_LOCALE: Locale = "en";

const DICTS = { en, it } as const;

export function isLocale(v: unknown): v is Locale {
  return v === "en" || v === "it";
}

/** Primo accesso senza cookie: italiano solo se e' la lingua primaria del browser. */
export function localeFromAcceptLanguage(header: string | null): Locale {
  return (header ?? "").trim().toLowerCase().startsWith("it") ? "it" : DEFAULT_LOCALE;
}

function lookup(dict: unknown, key: string): string | undefined {
  let cur: unknown = dict;
  for (const part of key.split(".")) {
    if (cur === null || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[part];
  }
  return typeof cur === "string" ? cur : undefined;
}

/**
 * Traduzione con interpolazione "{var}". Fallback: inglese, poi la chiave
 * stessa (visibile in dev → una stringa mancante non passa inosservata).
 */
export function translate(
  locale: Locale,
  key: string,
  vars?: Record<string, string | number>
): string {
  const raw = lookup(DICTS[locale], key) ?? lookup(DICTS.en, key) ?? key;
  if (!vars) return raw;
  return raw.replace(/\{(\w+)\}/g, (m, name) =>
    name in vars ? String(vars[name]) : m
  );
}
