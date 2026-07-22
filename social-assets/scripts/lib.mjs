import fs from "node:fs";
import { Resvg } from "@resvg/resvg-js";

// Contenuto interno del logo (defs + paths), senza il wrapper <svg>.
// Va inserito in un <svg ... viewBox="0 0 500 500"> per scalare bene.
const raw = fs.readFileSync("logo.svg", "utf8");
export const LOGO_INNER = raw
  .replace(/<\?xml[^>]*\?>/, "")
  .replace(/<svg[^>]*>/, "")
  .replace(/<\/svg>\s*$/, "");

// Medaglione: coin navy (leggermente più chiaro del fondo) + anello oro.
// x,y = angolo in alto a sinistra; size = diametro.
export function coin(x, y, size, { coinFill = "#131d40", ring = "#c9a227", ringOp = 0.65, glow = false } = {}) {
  const r = size / 2;
  return `<g transform="translate(${x},${y})">
    ${glow ? `<circle cx="${r}" cy="${r}" r="${r + 5}" fill="${ring}" opacity="0.08"/>` : ""}
    <circle cx="${r}" cy="${r}" r="${r}" fill="${coinFill}"/>
    <svg x="0" y="0" width="${size}" height="${size}" viewBox="0 0 500 500">${LOGO_INNER}</svg>
    <circle cx="${r}" cy="${r}" r="${r - 1}" fill="none" stroke="${ring}" stroke-opacity="${ringOp}" stroke-width="${Math.max(2, size / 70)}"/>
  </g>`;
}

export function render(svg, outPath) {
  const r = new Resvg(svg, { font: { fontDirs: ["fonts/use"], loadSystemFonts: false } });
  fs.writeFileSync(outPath, r.render().asPng());
}
