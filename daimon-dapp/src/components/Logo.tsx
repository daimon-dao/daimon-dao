/*
 * Official Daimon logo with its gold edge ring (public/logo-ring.svg, vector,
 * 512x512 viewBox): a byte-for-byte copy of
 * social-assets/brand/daimon-logo-ring.svg, the logo as daimon.money shows it.
 * The ring is part of the file, so it looks the same in both themes and needs
 * no CSS. public/logo.svg (the plain logo) stays served for external links.
 */
/* eslint-disable @next/next/no-img-element */
export function Logo({ size = 36 }: { size?: number }) {
  return (
    <img
      src="/logo-ring.svg"
      alt="Daimon"
      width={size}
      height={size}
      className="shrink-0 select-none"
      style={{ width: size, height: size }}
    />
  );
}
