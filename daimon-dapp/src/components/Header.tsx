"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Logo } from "./Logo";
import { ConnectButton } from "./ConnectButton";
import { useI18n } from "@/components/LocaleProvider";
import type { Locale } from "@/lib/i18n";

const NAV: Array<{ href: string; labelKey: string }> = [
  { href: "/", labelKey: "nav.dashboard" },
  { href: "/migrazione", labelKey: "nav.migration" },
  { href: "/staking", labelKey: "nav.staking" },
  { href: "/governance", labelKey: "nav.governance" },
];

function ThemeToggle() {
  const { t } = useI18n();
  const [mounted, setMounted] = useState(false);
  const [light, setLight] = useState(false);
  useEffect(() => {
    setMounted(true);
    setLight(document.documentElement.classList.contains("light"));
  }, []);
  function toggle() {
    const el = document.documentElement;
    const nowLight = !el.classList.contains("light");
    el.classList.toggle("light", nowLight);
    el.classList.toggle("dark", !nowLight);
    try {
      localStorage.setItem("daimon-theme", nowLight ? "light" : "dark");
    } catch {}
    setLight(nowLight);
  }
  if (!mounted) return <button className="w-9" aria-hidden />;
  return (
    <button
      onClick={toggle}
      className="rounded-lg border border-bordi px-2.5 py-2 text-sm text-secondario hover:text-testo"
      title={light ? t("header.toDark") : t("header.toLight")}
      aria-label={t("header.changeTheme")}
    >
      {light ? "🌙" : "☀️"}
    </button>
  );
}

/*
 * Selettore lingua EN | IT: la scelta persiste in cookie (letta dal server
 * al prossimo request) e la UI cambia subito, senza reload — la connessione
 * wallet e lo stato delle pagine non vengono toccati.
 */
function LanguageToggle() {
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

/*
 * MOBILE-FIRST (spec §8.6): sotto `sm` la barra contiene SOLO logo,
 * bottone wallet compatto e hamburger — lingua e tema vivono nel menu
 * hamburger come voci etichettate. Da `sm` in su tornano nella barra.
 */
export function Header() {
  const { t } = useI18n();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-30 border-b border-bordi bg-bg/95 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-2 px-3 py-3 sm:gap-4 sm:px-4">
        <Link href="/" className="flex shrink-0 items-center gap-2 sm:gap-3">
          <Logo />
          <span className="text-lg font-semibold tracking-wide text-orochiaro">DAIMON</span>
        </Link>

        <nav className="ml-6 hidden gap-1 md:flex">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className={`rounded-lg px-3 py-2 text-sm ${
                pathname === n.href
                  ? "bg-oro/15 font-medium text-oro"
                  : "text-secondario hover:text-testo"
              }`}
            >
              {t(n.labelKey)}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          {/* Lingua e tema: solo da sm in su (su mobile stanno nel menu ☰) */}
          <div className="hidden items-center gap-2 sm:flex">
            <LanguageToggle />
            <ThemeToggle />
          </div>
          <ConnectButton />
          <button
            className="rounded-lg border border-bordi px-3 py-2 text-sm text-secondario md:hidden"
            onClick={() => setOpen((v) => !v)}
            aria-label={t("header.openMenu")}
          >
            ☰
          </button>
        </div>
      </div>

      {open && (
        <nav className="border-t border-bordi px-4 py-2 md:hidden">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              onClick={() => setOpen(false)}
              className={`block rounded-lg px-3 py-2 text-sm ${
                pathname === n.href ? "font-medium text-oro" : "text-secondario"
              }`}
            >
              {t(n.labelKey)}
            </Link>
          ))}
          {/* Su mobile lingua e tema vivono qui (sopra sm sono nella barra) */}
          <div className="mt-1 flex items-center justify-between gap-3 border-t border-bordi px-3 py-3 sm:hidden">
            <span className="text-sm text-secondario">{t("header.language")}</span>
            <LanguageToggle />
          </div>
          <div className="flex items-center justify-between gap-3 px-3 pb-3 sm:hidden">
            <span className="text-sm text-secondario">{t("header.theme")}</span>
            <ThemeToggle />
          </div>
        </nav>
      )}
    </header>
  );
}
