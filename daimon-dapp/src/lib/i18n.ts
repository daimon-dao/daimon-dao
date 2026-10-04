import en from "@/messages/en.json";
import it from "@/messages/it.json";

/*
 * Minimal dictionary-based i18n (DAPP_SPEC.md §9): TWO languages, a few hundred
 * strings — a React provider + lookup with interpolation are enough. No
 * next-intl: no per-locale routing, no middleware, and hydration stays under
 * direct control (the server reads the cookie and passes the same language to
 * the client provider → identical HTML).
 *
 * This module is universal (no directive): used by the root layout server-side
 * (metadata, lang) and by the client-side provider.
 */
export type Locale = "en" | "it";

export const LOCALE_COOKIE = "daimon-locale";
export const DEFAULT_LOCALE: Locale = "en";

const DICTS = { en, it } as const;

export function isLocale(v: unknown): v is Locale {
  return v === "en" || v === "it";
}

/** First visit without a cookie: Italian only if it is the browser's primary language. */
export function localeFromAcceptLanguage(header: string | null): Locale {
  return (header ?? "").trim().toLowerCase().startsWith("it") ? "it" : DEFAULT_LOCALE;
}

/*
 * IPFS mirror (static build, docs/IPFS_MIRROR.md): no server reads a cookie,
 * so the choice lives in localStorage under the same name, and the first
 * visit follows navigator.language with the same rule as Accept-Language. The
 * prerendered HTML is English; LOCALE_PENDING_SCRIPT runs in <head> before
 * paint and, when the browser will switch to Italian, marks <html> so the CSS
 * keeps the body invisible until the provider has applied the language (no
 * flash of English). The mark lifts itself after a few seconds in case the
 * scripts never run, so a broken bundle still shows the English page.
 */
export const LOCALE_STORAGE_KEY = "daimon-locale";
export const LOCALE_PENDING_ATTR = "data-locale-pending";

/** The language the static build must show in this browser. */
export function readBrowserLocale(): Locale {
  let stored: string | null = null;
  try {
    stored = localStorage.getItem(LOCALE_STORAGE_KEY);
  } catch {}
  if (isLocale(stored)) return stored;
  return localeFromAcceptLanguage(typeof navigator === "undefined" ? null : navigator.language);
}

export const LOCALE_PENDING_SCRIPT = `
try {
  var l = localStorage.getItem('${LOCALE_STORAGE_KEY}');
  if (l === 'it' || (l !== 'en' && (navigator.language || '').toLowerCase().indexOf('it') === 0)) {
    document.documentElement.setAttribute('${LOCALE_PENDING_ATTR}', 'it');
    setTimeout(function () { document.documentElement.removeAttribute('${LOCALE_PENDING_ATTR}'); }, 4000);
  }
} catch (e) {}
`;

function lookup(dict: unknown, key: string): string | undefined {
  let cur: unknown = dict;
  for (const part of key.split(".")) {
    if (cur === null || typeof cur !== "object") return undefined;
    cur = (cur as Record<string, unknown>)[part];
  }
  return typeof cur === "string" ? cur : undefined;
}

/**
 * Translation with "{var}" interpolation. Fallback: English, then the key
 * itself (visible in dev → a missing string does not go unnoticed).
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
