import { formatUnits } from "viem";

/*
 * Tronca `x` a `digits` decimali VERSO LO ZERO (mai arrotondamento): il
 * valore mostrato non supera mai quello reale. Fondamentale per le metriche
 * deflazionarie — con round, 999.955 diventerebbe "1000.0" nascondendo il
 * burn. Costruisce la stringa dai pezzi interi per evitare che toFixed
 * ri-arrotondi per imprecisione floating point.
 */
export function truncFixed(x: number, digits: number): string {
  const sign = x < 0 ? "-" : "";
  const abs = Math.abs(x);
  const factor = 10 ** digits;
  const scaled = Math.floor(abs * factor); // troncamento verso il basso
  const intPart = Math.floor(scaled / factor);
  if (digits === 0) return `${sign}${intPart}`;
  const fracPart = (scaled % factor).toString().padStart(digits, "0");
  return `${sign}${intPart}.${fracPart}`;
}

/*
 * Formattazione importi (DAPP_SPEC.md §8.5): compatta e leggibile
 * ("987.4B", "1.5M"), con il valore esatto disponibile per i tooltip.
 * Sempre troncata verso il basso: la cifra visualizzata non eccede mai il
 * valore on-chain reale.
 */
export function formatCompact(value: bigint, decimals = 18, digits = 1): string {
  const n = Number(formatUnits(value, decimals));
  if (!isFinite(n)) return "-";
  const abs = Math.abs(n);
  // Niente tier "T": la scala di riferimento del progetto e' il miliardo
  // ("1000B -> 21B"), quindi 1e12 si mostra come 1000B.
  if (abs >= 1e9) return `${truncFixed(n / 1e9, digits)}B`;
  if (abs >= 1e6) return `${truncFixed(n / 1e6, digits)}M`;
  if (abs >= 1e3) return `${truncFixed(n / 1e3, digits)}K`;
  if (abs >= 1) return truncFixed(n, 2);
  if (abs === 0) return "0";
  return n.toLocaleString("it-IT", { maximumFractionDigits: 6 });
}

/** bigint (18 decimali) -> number, per calcoli di UI non critici. */
export function formatUnitsNumber(value: bigint, decimals = 18): number {
  return Number(formatUnits(value, decimals));
}

/** Valore esatto con separatori, per i tooltip. */
export function formatExact(value: bigint, decimals = 18): string {
  const s = formatUnits(value, decimals);
  const [int, frac] = s.split(".");
  const intFmt = BigInt(int).toLocaleString("it-IT");
  return frac ? `${intFmt},${frac.slice(0, 6)}` : intFmt;
}

export function formatUsd(n: number): string {
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(1)}K`;
  if (n >= 0.01) return `$${n.toFixed(2)}`;
  return `$${n.toPrecision(3)}`;
}

export function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/** Countdown leggibile: "3g 4h", "2h 15m", "12m". */
export function formatCountdown(secondsLeft: number): string {
  if (secondsLeft <= 0) return "adesso";
  const d = Math.floor(secondsLeft / 86400);
  const h = Math.floor((secondsLeft % 86400) / 3600);
  const m = Math.floor((secondsLeft % 3600) / 60);
  if (d > 0) return `${d}g ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return "meno di 1 minuto";
}

export function formatDate(unixSeconds: number | bigint): string {
  return new Date(Number(unixSeconds) * 1000).toLocaleString("it-IT", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
