import localFont from "next/font/local";

// IPFS target (see font.ts): the same Inter, latin subset, variable weight,
// from the file vendored in src/fonts/ (its origin and hash: src/fonts/README.md).
const inter = localFont({
  src: "../fonts/Inter-latin.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
});

export const fontClassName = inter.className;
