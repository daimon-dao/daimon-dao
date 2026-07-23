/*
 * Official Daimon logo (public/logo.svg, vector, 500x500 artboard, converted
 * from the official .ai file).
 *
 * In dark mode the logo's navy disc would blend into the midnight-blue
 * background: a thin gold ring (dark only) defines its border without altering
 * the original file.
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
