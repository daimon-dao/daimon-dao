import fs from "node:fs";
import { render, LOGO_INNER } from "./lib.mjs";

const NAVY = "#0a1128";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
fs.mkdirSync("out", { recursive: true });

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}">${esc(s)}</text>`;
}
function rings(cx, cy, op) {
  return [110, 190, 280, 390].map((r) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${GOLD}" stroke-opacity="${op}" stroke-width="1.5"/>`).join("");
}
// Solo i 3 path oro del simbolo (uncini + barra), senza disco/anelli/maschere.
const SYMBOL = (LOGO_INNER.match(/<path[^>]*fill="rgb\(76\.[^>]*\/>/g) || []).join("");
// filigrana: SIMBOLO grande ricolorato in tono chiaro a bassa opacità (tono su
// tono), che sborda dal bordo destro. Colore chiaro → filigrana che si "alza"
// dal fondo scuro invece di incupirlo.
function watermark(x, y, size, op, color = CREAM) {
  const sym = SYMBOL.replace(/fill="rgb\(76\.[^"]*\)"/g, `fill="${color}"`);
  return `<g opacity="${op}"><svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 500 500">${sym}</svg></g>`;
}
const head = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1500" height="500" viewBox="0 0 1500 500">`;

const L1 = { it: "Nessun owner. Nessun mint.", en: "No owner. No mint." };

// VARIANTE A — nessun logo, testo protagonista, centrato (avatar è in basso-sx)
function variantA(lang) {
  return head +
    `<rect width="1500" height="500" fill="${NAVY}"/>` +
    rings(820, 250, 0.05) +
    T(820, 172, L1[lang], { size: 56, weight: 600, fill: GOLD, anchor: "middle" }) +
    T(820, 292, "Floor 21B.", { size: 116, weight: 900, fill: GOLD, anchor: "middle" }) +
    T(820, 352, "Don't trust, verify.", { size: 36, weight: 500, fill: CREAM, op: 0.85, anchor: "middle" }) +
    `</svg>`;
}

// VARIANTE B — filigrana logo a destra (sfumata), testo a sinistra-centro
function variantB(lang) {
  return head +
    `<rect width="1500" height="500" fill="${NAVY}"/>` +
    rings(1230, 240, 0.04) +
    watermark(1010, -50, 600, 0.16) +
    T(120, 150, L1[lang], { size: 50, weight: 600, fill: GOLD }) +
    T(120, 263, "Floor 21B.", { size: 104, weight: 900, fill: GOLD }) +
    T(120, 320, "Don't trust, verify.", { size: 34, weight: 500, fill: CREAM, op: 0.85 }) +
    `</svg>`;
}

const jobs = [
  ["banner-A-it.png", variantA("it")],
  ["banner-A-en.png", variantA("en")],
  ["banner-B-it.png", variantB("it")],
  ["banner-B-en.png", variantB("en")],
];
for (const [n, s] of jobs) { render(s, `out/${n}`); console.log("ok", n); }
