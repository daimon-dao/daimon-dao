import { formatUnits } from "viem";
import type { Locale } from "@/lib/i18n";

/*
 * Truncates `x` to `digits` decimals TOWARD ZERO (never rounding): the value
 * shown never exceeds the real one. Essential for the deflationary metrics —
 * with rounding, 999.955 would become "1000.0", hiding the burn. It builds the
 * string from the integer parts to avoid toFixed re-rounding due to
 * floating-point imprecision.
 */
export function truncFixed(x: number, digits: number): string {
  const sign = x < 0 ? "-" : "";
  const abs = Math.abs(x);
  const factor = 10 ** digits;
  const scaled = Math.floor(abs * factor); // truncate downward
  const intPart = Math.floor(scaled / factor);
  if (digits === 0) return `${sign}${intPart}`;
  const fracPart = (scaled % factor).toString().padStart(digits, "0");
  return `${sign}${intPart}.${fracPart}`;
}

/*
 * Amount formatting (DAPP_SPEC.md §8.5): compact and readable ("987.4B",
 * "1.5M"), with the exact value available for the tooltips. Always truncated
 * downward: the displayed figure never exceeds the real on-chain value.
 */
export function formatCompact(value: bigint, decimals = 18, digits = 1): string {
  const n = Number(formatUnits(value, decimals));
  if (!isFinite(n)) return "-";
  const abs = Math.abs(n);
  // No "T" tier: the project's reference scale is the billion
  // ("1000B -> 21B"), so 1e12 is shown as 1000B.
  if (abs >= 1e9) return `${truncFixed(n / 1e9, digits)}B`;
  if (abs >= 1e6) return `${truncFixed(n / 1e6, digits)}M`;
  if (abs >= 1e3) return `${truncFixed(n / 1e3, digits)}K`;
  if (abs >= 1) return truncFixed(n, 2);
  if (abs === 0) return "0";
  return n.toLocaleString("it-IT", { maximumFractionDigits: 6 });
}

/** bigint (18 decimals) -> number, for non-critical UI calculations. */
export function formatUnitsNumber(value: bigint, decimals = 18): number {
  return Number(formatUnits(value, decimals));
}

/** Exact value with separators, for the tooltips. */
export function formatExact(value: bigint, decimals = 18): string {
  const s = formatUnits(value, decimals);
  const [int, frac] = s.split(".");
  const intFmt = BigInt(int).toLocaleString("it-IT");
  return frac ? `${intFmt},${frac.slice(0, 6)}` : intFmt;
}

/*
 * Compact amount without padding zeros and with thousands separators:
 * "1,000B", "4.999B", "12.5M". Same downward truncation as formatCompact (a
 * burned 999.9559B shows "999.955B", never "1,000B"); only the zeros that
 * carry nothing are dropped. en-US grouping in both languages, like every
 * number in the UI (the decimal point is "." everywhere).
 */
export function formatCompactTrim(value: bigint, decimals = 18, digits = 3): string {
  const n = Number(formatUnits(value, decimals));
  if (!isFinite(n)) return "-";
  const abs = Math.abs(n);
  const [scaled, unit] =
    abs >= 1e9 ? [n / 1e9, "B"] : abs >= 1e6 ? [n / 1e6, "M"] : abs >= 1e3 ? [n / 1e3, "K"] : [n, ""];
  const [int, frac = ""] = truncFixed(scaled, digits).split(".");
  const intGrouped = BigInt(int).toLocaleString("en-US");
  const fracTrim = frac.replace(/0+$/, "");
  return `${intGrouped}${fracTrim ? `.${fracTrim}` : ""}${unit}`;
}

/*
 * A dollar amount in plain decimals: NEVER exponent notation (toPrecision
 * and String() switch to "2.97e-7" below 1e-6). Below $1, three significant
 * digits ("$0.297", "$0.000000297"); from $1 up, cents ("$12.34", "$1,234.56").
 */
export function formatUsdPlain(n: number, significant = 3): string {
  if (!isFinite(n)) return "-";
  if (Math.abs(n) >= 1)
    return `$${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  return `$${n.toLocaleString("en-US", { maximumSignificantDigits: significant })}`;
}

export function formatUsd(n: number): string {
  if (n >= 1e9) return `$${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `$${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `$${(n / 1e3).toFixed(1)}K`;
  if (n >= 0.01) return `$${n.toFixed(2)}`;
  return formatUsdPlain(n);
}

export function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/** Human-readable countdown: "3g 4h" / "3d 4h", "2h 15m", "12m". */
export function formatCountdown(secondsLeft: number, locale: Locale = "en"): string {
  if (secondsLeft <= 0) return locale === "it" ? "adesso" : "now";
  const d = Math.floor(secondsLeft / 86400);
  const h = Math.floor((secondsLeft % 86400) / 3600);
  const m = Math.floor((secondsLeft % 3600) / 60);
  const dayUnit = locale === "it" ? "g" : "d";
  if (d > 0) return `${d}${dayUnit} ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return locale === "it" ? "meno di 1 minuto" : "less than a minute";
}

export function formatDate(unixSeconds: number | bigint, locale: Locale = "en"): string {
  return new Date(Number(unixSeconds) * 1000).toLocaleString(
    locale === "it" ? "it-IT" : "en-US",
    {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      // Deadlines are absolute instants: say which clock the time is on.
      timeZoneName: "short",
    }
  );
}
