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
// Only the symbol's 3 gold paths (hooks + bar), without disc/rings/masks.
const SYMBOL = (LOGO_INNER.match(/<path[^>]*fill="rgb\(76\.[^>]*\/>/g) || []).join("");
// watermark: large SYMBOL recolored in a light tone at low opacity (tone on
// tone), bleeding off the right edge. A light color → a watermark that "rises"
// from the dark background instead of darkening it.
function watermark(x, y, size, op, color = CREAM) {
  const sym = SYMBOL.replace(/fill="rgb\(76\.[^"]*\)"/g, `fill="${color}"`);
  return `<g opacity="${op}"><svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="0 0 500 500">${sym}</svg></g>`;
}
const head = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1500" height="500" viewBox="0 0 1500 500">`;

const L1 = { it: "Nessun owner. Nessun mint.", en: "No owner. No mint." };

// VARIANT A — no logo, text as the hero, centered (avatar is bottom-left)
function variantA(lang) {
  return head +
    `<rect width="1500" height="500" fill="${NAVY}"/>` +
    rings(820, 250, 0.05) +
    T(820, 172, L1[lang], { size: 56, weight: 600, fill: GOLD, anchor: "middle" }) +
    T(820, 292, "Floor 21B.", { size: 116, weight: 900, fill: GOLD, anchor: "middle" }) +
    T(820, 352, "Don't trust, verify.", { size: 36, weight: 500, fill: CREAM, op: 0.85, anchor: "middle" }) +
    `</svg>`;
}

// VARIANT B — logo watermark on the right (faded), text on the left-center
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
