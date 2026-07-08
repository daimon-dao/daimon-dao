"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { Logo } from "./Logo";
import { ConnectButton } from "./ConnectButton";

const NAV = [
  { href: "/", label: "Dashboard" },
  { href: "/migrazione", label: "Migrazione" },
  { href: "/staking", label: "Staking" },
  { href: "/governance", label: "Governance" },
];

function ThemeToggle() {
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
      title={light ? "Passa al tema scuro" : "Passa al tema chiaro"}
      aria-label="Cambia tema"
    >
      {light ? "🌙" : "☀️"}
    </button>
  );
}

export function Header() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-30 border-b border-bordi bg-bg/95 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-4 px-4 py-3">
        <Link href="/" className="flex items-center gap-3">
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
              {n.label}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          <ThemeToggle />
          <ConnectButton />
          <button
            className="rounded-lg border border-bordi px-3 py-2 text-sm text-secondario md:hidden"
            onClick={() => setOpen((v) => !v)}
            aria-label="Apri menu"
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
              {n.label}
            </Link>
          ))}
        </nav>
      )}
    </header>
  );
}
