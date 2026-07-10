/*
 * Logo ufficiale Daimon (public/logo.svg, vettoriale, tavola 500x500,
 * convertito dal file .ai ufficiale).
 *
 * In dark mode il disco navy del logo si fonderebbe con lo sfondo blu
 * notte: un anello oro sottile (solo dark) ne definisce il bordo senza
 * alterare il file originale.
 */
/* eslint-disable @next/next/no-img-element */
export function Logo({ size = 36 }: { size?: number }) {
  return (
    <img
      src="/logo.svg"
      alt="Daimon"
      width={size}
      height={size}
      className="shrink-0 select-none rounded-full dark:ring-1 dark:ring-oro/60"
      style={{ width: size, height: size }}
    />
  );
}
