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
 * initialLocale comes from the server (cookie / Accept-Language read in the
 * root layout): the first client render uses the SAME language as the server
 * HTML → no hydration mismatch. Changing language is client-side only: it
 * writes the cookie (persistence across later refreshes/navigations) and
 * updates the state → the whole UI re-renders without a reload, wallet included.
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

  // After a client-side language change: <html lang> and <title> stay
  // consistent (the server metadata only updates on the next request).
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
  if (!ctx) throw new Error("useI18n requires LocaleProvider in the tree");
  return ctx;
}
