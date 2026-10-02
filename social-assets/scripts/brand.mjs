import fs from "node:fs";
import { Resvg } from "@resvg/resvg-js";
import { LOGO_INNER } from "./lib.mjs";

// Everything here derives from ../brand/daimon-logo.svg:
// - ../brand/daimon-logo-{32,256,512}.png: the bare logo, transparent corners;
// - ../brand/daimon-logo-ring.svg and daimon-logo-ring-{32,256,512,1024}.png: the
//   medallion (logo at 500/512 of the side, centred, plus a gold edge ring), the
//   logo as daimon.money shows it;
// - ../logo-512.png: the medallion at 512 px (byte-identical to
//   daimon-logo-ring-512.png): root README header, protocol paper, GitHub
//   organization avatar, the site's public/logo-512.png.
const at = (p) => new URL(p, import.meta.url);
const png = (svg, size) => new Resvg(svg, { fitTo: { mode: "width", value: size } }).render().asPng();

const svg = fs.readFileSync(at("../brand/daimon-logo.svg"), "utf8");
for (const size of [32, 256, 512]) {
  fs.writeFileSync(at(`../brand/daimon-logo-${size}.png`), png(svg, size));
  console.log("ok", `brand/daimon-logo-${size}.png`);
}

// The logo's paths untouched, in a 500-unit box offset by 6 inside a 512 square;
// the ring (r 250, width 6, #c9a227 at 70 %) straddles the disc's edge.
const ring =
  `<?xml version="1.0" encoding="UTF-8"?>\n` +
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n` +
  `<svg x="6" y="6" width="500" height="500" viewBox="0 0 500 500">\n${LOGO_INNER.trim()}\n</svg>\n` +
  `<circle cx="256" cy="256" r="250" fill="none" stroke="#c9a227" stroke-opacity="0.7" stroke-width="6"/>\n` +
  `</svg>\n`;
fs.writeFileSync(at("../brand/daimon-logo-ring.svg"), ring);
console.log("ok", "brand/daimon-logo-ring.svg");
for (const size of [32, 256, 512, 1024]) {
  fs.writeFileSync(at(`../brand/daimon-logo-ring-${size}.png`), png(ring, size));
  console.log("ok", `brand/daimon-logo-ring-${size}.png`);
}
fs.writeFileSync(at("../logo-512.png"), png(ring, 512));
console.log("ok", "logo-512.png");
