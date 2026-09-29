"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { TERMS_VERSION } from "@/content/terms";
import { useI18n } from "@/components/LocaleProvider";
import { LanguageToggle } from "@/components/LanguageToggle";
import { Logo } from "@/components/Logo";

/*
 * Terms acknowledgment (DISCLAIMER_TERMS v0.2, DAPP_SPEC.md §8 point 9): no
 * wallet interaction before the visitor has read a plain summary and
 * explicitly accepted. The acceptance lives ONLY in this browser's
 * localStorage, with the terms version -- no cookie, nothing sent anywhere. A
 * new TERMS_VERSION (npm run terms) invalidates every stored acceptance.
 *
 * No flash either way: the gate is in the server HTML, and TERMS_ACCEPTED_SCRIPT
 * (run in <head> before paint, like the theme) marks <html> when the stored
 * version matches, which hides the gate by CSS until React takes over.
 */
export const TERMS_STORAGE_KEY = "daimon-terms";
export const TERMS_ACCEPTED_ATTR = "data-terms-accepted";

export const TERMS_ACCEPTED_SCRIPT = `
try {
  var a = JSON.parse(localStorage.getItem('${TERMS_STORAGE_KEY}') || 'null');
  if (a && a.version === '${TERMS_VERSION}') document.documentElement.setAttribute('${TERMS_ACCEPTED_ATTR}', '');
} catch (e) {}
`;

function readAccepted(): boolean {
  try {
    const a = JSON.parse(localStorage.getItem(TERMS_STORAGE_KEY) ?? "null");
    return a?.version === TERMS_VERSION;
  } catch {
    return false;
  }
}

type TermsContext = {
  /** true only once the CURRENT terms version has been accepted */
  accepted: boolean;
  /** shows the gate (e.g. a wallet action attempted from /terms) */
  requestTerms: () => void;
};

const Ctx = createContext<TermsContext | null>(null);

export function useTerms(): TermsContext {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useTerms requires TermsProvider in the tree");
  return ctx;
}

export function TermsProvider({ children }: { children: ReactNode }) {
  // null = localStorage not read yet (server render and first client render)
  const [accepted, setAccepted] = useState<boolean | null>(null);
  const [requested, setRequested] = useState(false);
  const pathname = usePathname();
  const appRef = useRef<HTMLDivElement>(null);

  useEffect(() => setAccepted(readAccepted()), []);

  const accept = useCallback(() => {
    try {
      localStorage.setItem(
        TERMS_STORAGE_KEY,
        JSON.stringify({ version: TERMS_VERSION, acceptedAt: new Date().toISOString() })
      );
    } catch {
      // Storage blocked (private mode, policy): valid for this page load only.
    }
    document.documentElement.setAttribute(TERMS_ACCEPTED_ATTR, "");
    setAccepted(true);
    setRequested(false);
  }, []);

  const requestTerms = useCallback(() => setRequested(true), []);

  // The full terms stay readable without accepting; everywhere else the gate
  // covers the app until acceptance.
  const onTermsPage = pathname === "/terms" || pathname.startsWith("/terms/");
  const show = accepted !== true && (!onTermsPage || requested);

  // Behind the gate the app is inert (no keyboard focus, no clicks) and does
  // not scroll.
  useEffect(() => {
    appRef.current?.toggleAttribute("inert", show);
    document.body.style.overflow = show ? "hidden" : "";
  }, [show]);

  return (
    <Ctx.Provider value={{ accepted: accepted === true, requestTerms }}>
      {show && <TermsScreen onAccept={accept} />}
      <div ref={appRef}>{children}</div>
    </Ctx.Provider>
  );
}

function TermsScreen({ onAccept }: { onAccept: () => void }) {
  const { t } = useI18n();
  const points = ["p1", "p2", "p3", "p4"] as const;
  return (
    <div
      className="terms-gate fixed inset-0 z-50 overflow-y-auto bg-bg"
      role="dialog"
      aria-modal="true"
      aria-labelledby="terms-gate-title"
    >
      <div className="mx-auto flex min-h-full max-w-xl flex-col justify-center px-4 py-8">
        <div className="mb-6 flex items-center justify-between">
          <Logo />
          <LanguageToggle />
        </div>
        <div className="card">
          <h1 id="terms-gate-title" className="text-xl font-semibold text-orochiaro">
            {t("terms.title")}
          </h1>
          <p className="mt-2 text-sm text-secondario">{t("terms.intro")}</p>
          <ul className="mt-5 space-y-4 text-sm leading-relaxed">
            {points.map((k) => (
              <li key={k} className="border-l-2 border-oro/50 pl-3">
                <b className="text-orochiaro">{t(`terms.${k}Title`)}</b> {t(`terms.${k}`)}
              </li>
            ))}
          </ul>
          <p className="mt-5 text-sm">
            {t("terms.fullTerms", { version: TERMS_VERSION })}{" "}
            <Link href="/terms" target="_blank" className="text-oro underline underline-offset-2">
              English
            </Link>
            {" · "}
            <Link href="/terms/it" target="_blank" className="text-oro underline underline-offset-2">
              Italiano
            </Link>
          </p>
          <p className="mt-1 text-xs text-secondario">{t("terms.authoritative")}</p>
          <button className="btn-oro mt-6 w-full py-3 text-base" onClick={onAccept}>
            {t("terms.accept")}
          </button>
          <p className="mt-3 text-xs text-secondario">{t("terms.storage")}</p>
        </div>
      </div>
    </div>
  );
}
