import { formatUnits, parseUnits } from "viem";
import type { Locale } from "@/lib/i18n";

/*
 * THE number formatter of the dApp. Every number the UI shows -- headline
 * figures, tooltips, percentages, prices, multipliers -- goes through the
 * functions below with the current language, so the two always agree and
 * nothing is formatted by hand in the pages (use them through
 * useFormat(), src/hooks/useFormat.ts).
 *
 *   EN  "," thousands, "." decimals, suffixes M / B      1,000B DMN, 250,000 DMN
 *   IT  "." thousands, "," decimals, suffixes mln / mld  1.000 mld di DMN, 250.000 DMN
 *
 * Suffixes start at a million: below it, amounts are written in full with
 * separators ("1.000 DMN", never "1 mila"). Grouping is applied here, not
 * left to Intl: Italian CLDR does not group four-digit numbers ("1000").
 *
 * The parts of an amount (number, suffix, "di", unit) are joined with
 * NON-BREAKING spaces: "1.000 mld di DMN" never breaks across two lines.
 *
 * Token amounts are TRUNCATED toward zero, never rounded (DAPP_SPEC.md §8.5):
 * the figure shown never exceeds the on-chain value -- with rounding a burned
 * 999.9559B would read "1,000B" and hide the burn. They are computed from the
 * bigint through decimal strings, so no float ever touches them.
 */

const SEP: Record<Locale, { group: string; decimal: string }> = {
  en: { group: ",", decimal: "." },
  it: { group: ".", decimal: "," },
};

// Compact tiers: [power of ten, suffix], from a million up only. IT suffixes
// are words, spaced from the number and followed by "di" before a unit
// ("5,016 mld di DMN").
const TIERS: Record<Locale, ReadonlyArray<readonly [number, string]>> = {
  en: [[9, "B"], [6, "M"]],
  it: [[9, "mld"], [6, "mln"]],
};

// Joins the parts of one amount: never a line break inside it.
const NBSP = String.fromCharCode(0xa0); // U+00A0 NO-BREAK SPACE

/** "1234567.5" (plain, "." decimal) -> "1,234,567.5" / "1.234.567,5". */
function localize(plain: string, locale: Locale): string {
  const neg = plain.startsWith("-");
  const [int, frac] = (neg ? plain.slice(1) : plain).split(".");
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, SEP[locale].group);
  return `${neg ? "-" : ""}${grouped}${frac ? SEP[locale].decimal + frac : ""}`;
}

/** Cuts a plain decimal string to `digits` decimals (toward zero), drops padding zeros. */
function truncPlain(plain: string, digits: number): string {
  const [int, frac = ""] = plain.split(".");
  const cut = frac.slice(0, digits).replace(/0+$/, "");
  const out = cut ? `${int}.${cut}` : int;
  return out === "-0" ? "0" : out;
}

/** A JS number as a plain decimal string: never exponent notation. */
function plainOf(n: number): string {
  return new Intl.NumberFormat("en-US", { useGrouping: false, maximumFractionDigits: 20 }).format(n);
}

/** Number, truncated to `maxFrac` decimals: "0.0017" / "0,0017", "1,000" / "1.000". */
export function formatNumber(n: number, locale: Locale, maxFrac = 2): string {
  if (!isFinite(n)) return "-";
  return localize(truncPlain(plainOf(n), maxFrac), locale);
}

/** Percentage, truncated: "0.0017%" / "0,0017%". */
export function formatPercent(pct: number, locale: Locale, maxFrac = 2): string {
  return `${formatNumber(pct, locale, maxFrac)}%`;
}

/** Lock multiplier: "1.5x" / "1,5x". */
export function formatMultiplier(x: number, locale: Locale): string {
  return `${formatNumber(x, locale, 3)}x`;
}

/*
 * Compact amount from a bigint: "17.2M" / "17,2 mln", "1,000B" / "1.000 mld".
 * `digits` = decimals kept on the tiered figure (truncated, padding dropped).
 * Below a million there is no tier, the amount is written in full ("250,000" /
 * "250.000"): 2 decimals from 1 up, 6 below 1.
 */
function compactParts(
  value: bigint,
  locale: Locale,
  decimals: number,
  digits: number
): { text: string; tiered: boolean } {
  const neg = value < 0n;
  const abs = neg ? -value : value;
  const sign = neg ? "-" : "";
  const unit = 10n ** BigInt(decimals);
  for (const [exp, suffix] of TIERS[locale]) {
    if (abs >= 10n ** BigInt(exp) * unit) {
      const num = localize(truncPlain(formatUnits(abs, decimals + exp), digits), locale);
      return { text: `${sign}${num}${locale === "it" ? NBSP : ""}${suffix}`, tiered: true };
    }
  }
  const plain = formatUnits(abs, decimals);
  const small = abs < unit;
  const cut = truncPlain(plain, small ? 6 : 2);
  if (cut === "0" && abs > 0n) return { text: `<${localize("0.000001", locale)}`, tiered: false };
  return { text: `${sign}${localize(cut, locale)}`, tiered: false };
}

/** Compact amount, no unit (voting power, thresholds): "17.2M" / "17,2 mln". */
export function formatCompact(value: bigint, locale: Locale, digits = 1, decimals = 18): string {
  return compactParts(value, locale, decimals, digits).text;
}

/** Compact amount with its unit: "1,000B DMN" / "1.000 mld di DMN" / "250 DMN". */
export function formatToken(
  value: bigint,
  locale: Locale,
  unit: string,
  digits = 1,
  decimals = 18
): string {
  const { text, tiered } = compactParts(value, locale, decimals, digits);
  return `${text}${locale === "it" && tiered ? `${NBSP}di` : ""}${NBSP}${unit}`;
}

/** Exact amount, all integer digits grouped, up to 6 decimals (truncated), for the tooltips. */
export function formatExact(value: bigint, locale: Locale, decimals = 18): string {
  return localize(truncPlain(formatUnits(value, decimals), 6), locale);
}

/** Exact amount with its unit: "1,000,000,000,000 DMN" / "1.000.000.000.000 DMN". */
export function formatTokenExact(value: bigint, locale: Locale, unit: string, decimals = 18): string {
  return `${formatExact(value, locale, decimals)}${NBSP}${unit}`;
}

/*
 * Dollars, plain decimals, never exponent notation. From $1 up, cents
 * ("$1,234.56" / "$1.234,56"); below $1, `significant` significant digits
 * ("$0.296" / "$0,296", "$0.000000296" / "$0,000000296").
 */
export function formatUsd(n: number, locale: Locale, significant = 3): string {
  if (!isFinite(n)) return "-";
  const plain =
    Math.abs(n) >= 1
      ? new Intl.NumberFormat("en-US", { useGrouping: false, minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n)
      : new Intl.NumberFormat("en-US", { useGrouping: false, maximumSignificantDigits: significant }).format(n);
  return `$${localize(plain, locale)}`;
}

/*
 * Reads an amount typed by the user, in the current language, into base
 * units. Grouped thousands in the language's own style are accepted
 * ("1.000,5" IT / "1,000.5" EN); otherwise either "." or "," is taken as the
 * decimal point ("1.5" and "1,5" are one and a half in both). Returns null
 * for anything else -- never a guess.
 */
export function parseAmount(input: string, locale: Locale, decimals = 18): bigint | null {
  // \s also covers no-break spaces (U+00A0, U+202F) pasted from formatted text.
  const s = input.trim().replace(/[\s']/g, "");
  if (s === "") return null;
  const { group, decimal } = SEP[locale];
  const g = group === "." ? "\\." : ",";
  const d = decimal === "." ? "\\." : ",";
  let plain: string;
  if (new RegExp(`^\\d{1,3}(${g}\\d{3})+(${d}\\d*)?$`).test(s)) {
    plain = s.split(group).join("").replace(decimal, ".");
  } else if (/^\d*[.,]?\d*$/.test(s) && /\d/.test(s)) {
    plain = s.replace(",", ".");
  } else {
    return null;
  }
  try {
    return parseUnits(plain, decimals);
  } catch {
    return null;
  }
}

/** bigint -> number, for UI arithmetic only (sliders, USD estimates) -- never for display. */
export function formatUnitsNumber(value: bigint, decimals = 18): number {
  return Number(formatUnits(value, decimals));
}

/*
 * Truncates `x` to `digits` decimals TOWARD ZERO (never rounding), as a plain
 * "." string. Kept for callers that compute, not display.
 */
export function truncFixed(x: number, digits: number): string {
  return truncPlain(plainOf(x), digits);
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

/** Every formatter bound to one language: what useFormat() hands to the pages. */
export function formattersFor(locale: Locale) {
  return {
    locale,
    number: (n: number, maxFrac?: number) => formatNumber(n, locale, maxFrac),
    percent: (pct: number, maxFrac?: number) => formatPercent(pct, locale, maxFrac),
    multiplier: (x: number) => formatMultiplier(x, locale),
    compact: (v: bigint, digits?: number) => formatCompact(v, locale, digits),
    token: (v: bigint, unit: string, digits?: number) => formatToken(v, locale, unit, digits),
    exact: (v: bigint) => formatExact(v, locale),
    tokenExact: (v: bigint, unit: string) => formatTokenExact(v, locale, unit),
    usd: (n: number, significant?: number) => formatUsd(n, locale, significant),
    parse: (input: string) => parseAmount(input, locale),
    countdown: (seconds: number) => formatCountdown(seconds, locale),
    date: (unixSeconds: number | bigint) => formatDate(unixSeconds, locale),
  };
}

export type Formatters = ReturnType<typeof formattersFor>;
