"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { LOCALE_COOKIE, translate, type Locale } from "@/lib/i18n";

type I18nContext = {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: (key: string, vars?: Record<string, string | number>) => string;
};

const Ctx = createContext<I18nContext | null>(null);

/*
 * initialLocale arriva dal server (cookie / Accept-Language letti nel root
 * layout): il primo render client usa la STESSA lingua dell'HTML server →
 * niente hydration mismatch. Il cambio lingua e' solo client-side: scrive
 * il cookie (persistenza a refresh/navigazioni successive) e aggiorna lo
 * stato → tutta la UI si ri-renderizza senza reload, wallet incluso.
 */
export function LocaleProvider({
  initialLocale,
  children,
}: {
  initialLocale: Locale;
  children: ReactNode;
}) {
  const [locale, setLocaleState] = useState<Locale>(initialLocale);

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l);
    document.cookie = `${LOCALE_COOKIE}=${l}; path=/; max-age=31536000; samesite=lax`;
  }, []);

  // Dopo un cambio lingua client-side: <html lang> e <title> restano
  // coerenti (i metadata server si aggiornano solo al prossimo request).
  useEffect(() => {
    document.documentElement.lang = locale;
    document.title = translate(locale, "meta.title");
  }, [locale]);

  const t = useCallback(
    (key: string, vars?: Record<string, string | number>) =>
      translate(locale, key, vars),
    [locale]
  );

  return <Ctx.Provider value={{ locale, setLocale, t }}>{children}</Ctx.Provider>;
}

export function useI18n(): I18nContext {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useI18n richiede LocaleProvider nel tree");
  return ctx;
}
