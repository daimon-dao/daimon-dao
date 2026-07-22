import fs from "node:fs";
import { coin, render } from "./lib.mjs";

const NAVY = "#0a1128";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";

const OUT = "out";
fs.mkdirSync(OUT, { recursive: true });

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// text helper
function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

// texture minima: anelli concentrici molto tenui (echo del logo)
function faintRings(cx, cy, color = GOLD, op = 0.05) {
  let r = "";
  for (const rad of [120, 200, 290, 400]) {
    r += `<circle cx="${cx}" cy="${cy}" r="${rad}" fill="none" stroke="${color}" stroke-opacity="${op}" stroke-width="1.5"/>`;
  }
  return r;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

/* ============ 1. PROFILE BANNER 1500×500 ============ */
function banner(lang) {
  const l1 = lang === "it" ? "Nessun owner. Nessun mint." : "No owner. No mint.";
  const hero = lang === "it" ? "Floor 21B." : "Floor 21B.";
  const sub = "Don't trust, verify.";
  return head(1500, 500) +
    `<rect width="1500" height="500" fill="${NAVY}"/>` +
    faintRings(230, 250, GOLD, 0.045) +
    // medaglione a sinistra, alzato per lasciare libero l'angolo in basso a sx (avatar)
    coin(120, 78, 210, { coinFill: "#111b3a", glow: true }) +
    // filo verticale di separazione, discreto
    `<rect x="405" y="150" width="2" height="200" fill="${GOLD}" fill-opacity="0.35"/>` +
    T(455, 185, l1, { size: 54, weight: 600, fill: GOLD }) +
    T(455, 300, hero, { size: 96, weight: 900, fill: GOLD }) +
    T(455, 358, sub, { size: 34, weight: 500, fill: CREAM, op: 0.85 }) +
    `</svg>`;
}

/* ============ 2. STAT CARDS 1600×900 ============ */
function statCard({ eyebrow, big, bigSize, caption, extra = "" }) {
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    faintRings(800, 450, GOLD, 0.035) +
    coin(70, 70, 96, { coinFill: "#111b3a" }) +
    T(1530, 128, "daimon-dao", { size: 26, weight: 500, fill: CREAM, op: 0.5, anchor: "end" }) +
    (eyebrow ? T(800, 320, eyebrow, { size: 40, weight: 600, fill: CREAM, op: 0.55, anchor: "middle", spacing: 8 }) : "") +
    T(800, 495, big, { size: bigSize, weight: 900, fill: GOLD, anchor: "middle" }) +
    T(800, 615, caption, { size: 40, weight: 500, fill: CREAM, op: 0.9, anchor: "middle" }) +
    extra +
    `</svg>`;
}

// barra di deflazione stilizzata per la card d
const deflBar = (() => {
  const x = 400, y = 680, w = 800, h = 16;
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" fill="#111b3a" stroke="${GOLD}" stroke-opacity="0.25"/>` +
    `<rect x="${x}" y="${y}" width="26" height="${h}" rx="8" fill="${GOLD}"/>` +
    `<circle cx="${x + 26}" cy="${y + h / 2}" r="9" fill="${GOLD}"/>` +
    T(x, y + 55, "1000B", { size: 26, weight: 600, fill: CREAM, op: 0.7 }) +
    T(x + w, y + 55, "21B", { size: 26, weight: 600, fill: GOLD, anchor: "end" });
})();

/* ============ 3. QUOTE CARDS 1600×900 ============ */
function quoteCard(line1, line2, { l2gold = true } = {}) {
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    faintRings(800, 450, GOLD, 0.03) +
    coin(730, 150, 140, { coinFill: "#111b3a", glow: true }) +
    T(800, 500, line1, { size: 74, weight: 600, fill: CREAM, anchor: "middle" }) +
    T(800, 600, line2, { size: 82, weight: 800, fill: l2gold ? GOLD : CREAM, anchor: "middle" }) +
    `<rect x="740" y="680" width="120" height="3" fill="${GOLD}" fill-opacity="0.5"/>` +
    `</svg>`;
}

/* ============ 4. GITHUB PREVIEW 1280×640 ============ */
function githubPreview() {
  return head(1280, 640) +
    `<rect width="1280" height="640" fill="${NAVY}"/>` +
    faintRings(640, 300, GOLD, 0.04) +
    coin(560, 120, 160, { coinFill: "#111b3a", glow: true }) +
    T(640, 400, "Daimon DAO", { size: 72, weight: 800, fill: GOLD, anchor: "middle" }) +
    T(640, 465, "No owner · No mint · Floor 21B", { size: 30, weight: 500, fill: CREAM, op: 0.8, anchor: "middle" }) +
    T(640, 545, "github.com/daimon-dao", { size: 26, weight: 500, fill: CREAM, op: 0.5, anchor: "middle" }) +
    `</svg>`;
}

/* ============ RENDER ============ */
// Banner gestiti da banner.mjs (varianti A/B). Qui: card social + preview, EN.
const jobs = [
  ["stat-fee.png", statCard({ eyebrow: "FEE", big: "11% → 4%", bigSize: 175, caption: "decided by the DAO, not by a boss" })],
  ["stat-timelock.png", statCard({ eyebrow: "TIMELOCK", big: "604,800", bigSize: 185, caption: "seconds of timelock. Exact. Even for us." })],
  ["stat-owner-mint.png", statCard({ eyebrow: "GUARANTEES", big: "0 owner · 0 mint", bigSize: 130, caption: "forever, guaranteed by the code" })],
  ["stat-supply.png", statCard({ eyebrow: "SUPPLY", big: "1000B → 21B", bigSize: 150, caption: "deflationary supply toward the floor", extra: deflBar })],
  ["quote-codice.png", quoteCard("Humans make mistakes.", "Code doesn't.")],
  ["quote-verificate.png", quoteCard("Don't trust us.", "Verify.")],
  ["github-preview.png", githubPreview()],
];

for (const [name, svg] of jobs) {
  render(svg, `${OUT}/${name}`);
  console.log("ok", name);
}
console.log("TUTTO FATTO");
