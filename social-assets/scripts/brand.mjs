import fs from "node:fs";
import { Resvg } from "@resvg/resvg-js";
import { LOGO_INNER, render } from "./lib.mjs";

// Rasters of ../brand/daimon-logo.svg:
// - ../brand/daimon-logo-{32,256,512}.png: the bare logo, transparent corners;
// - ../logo-512.png: the square medallion (logo at 500 px, centred, plus a gold
//   edge ring): root README header, protocol paper, GitHub organization avatar.
const at = (p) => new URL(p, import.meta.url);

const svg = fs.readFileSync(at("../brand/daimon-logo.svg"), "utf8");
for (const size of [32, 256, 512]) {
  const png = new Resvg(svg, { fitTo: { mode: "width", value: size } }).render().asPng();
  fs.writeFileSync(at(`../brand/daimon-logo-${size}.png`), png);
  console.log("ok", `brand/daimon-logo-${size}.png`);
}

const medallion =
  `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">` +
  `<svg x="6" y="6" width="500" height="500" viewBox="0 0 500 500">${LOGO_INNER}</svg>` +
  `<circle cx="256" cy="256" r="250" fill="none" stroke="#c9a227" stroke-opacity="0.7" stroke-width="6"/>` +
  `</svg>`;
render(medallion, at("../logo-512.png"));
console.log("ok", "logo-512.png");
