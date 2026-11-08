import fs from "node:fs";
import { coin, render } from "./lib.mjs";

// G1 reminder cards ("stat" type, Friday 13 Nov 2026): the proposal date and
// time as the giant figure, stake before it to vote. Same toolchain as g1.mjs
// (resvg + Inter from fonts/use); the logo comes from ../brand/daimon-logo.svg
// through lib.mjs, untouched.
//
//   node g1_reminder.mjs   -> out/g1_reminder_X_en.png  (1600 x 900)
//                             out/g1_reminder_TG_en.png (1200 x 1200)
//                             out/g1_reminder_TG_it.png (1200 x 1200)
//
// Palette: navy #0a1128, card #111b3a, borders #2a3655, gold #c9a227,
// cream #f5e9c8, secondary #8a94ad. One font (Inter), three text colours.
// X safe zone: nothing on the edges, no text bottom-left (the avatar).

const NAVY = "#0a1128";
const CARD = "#111b3a";
const BORDER = "#2a3655";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";
const SECONDARY = "#8a94ad";

const OUT = process.env.G1_OUT || "out";
fs.mkdirSync(OUT, { recursive: true });

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

// faint concentric rings, cream tone-on-tone (the only watermark allowed)
function faintRings(cx, cy, op = 0.035) {
  let r = "";
  for (const rad of [120, 200, 290, 400, 520]) {
    r += `<circle cx="${cx}" cy="${cy}" r="${rad}" fill="none" stroke="${CREAM}" stroke-opacity="${op}" stroke-width="1.5"/>`;
  }
  return r;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

const TEXT = {
  en: {
    big: "16 Nov · 12:00 UTC",
    under: null,
    caption: ["Stake before the proposal to vote on G1"],
    line: "G1 · the first Daimon DAO proposal",
  },
  it: {
    big: "16 nov · 13:00",
    under: "ora italiana",
    caption: ["Lo stake deve esserci prima della proposta", "per votare G1"],
    line: "G1 · la prima proposta della DAO Daimon",
  },
};

/* ============ X card 1600×900 ============ */
function xCard(lang) {
  const t = TEXT[lang];
  const cx = 800;
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    faintRings(cx, 450) +
    coin(70, 70, 96, { coinFill: CARD }) +
    T(1530, 128, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    T(cx, 455, t.big, { size: 144, weight: 900, fill: GOLD, anchor: "middle" }) +
    T(cx, 560, t.caption[0], { size: 46, weight: 600, fill: CREAM, anchor: "middle" }) +
    `<rect x="${cx - 80}" y="600" width="160" height="2" fill="${BORDER}"/>` +
    T(cx, 668, t.line, { size: 34, weight: 500, fill: SECONDARY, anchor: "middle" }) +
    `</svg>`;
}

/* ============ Telegram card 1200×1200 ============ */
function tgCard(lang) {
  const t = TEXT[lang];
  const cx = 600;
  let body;
  if (t.caption.length === 1) {
    body =
      T(cx, 570, t.big, { size: 108, weight: 900, fill: GOLD, anchor: "middle" }) +
      T(cx, 675, t.caption[0], { size: 48, weight: 600, fill: CREAM, anchor: "middle" }) +
      `<rect x="${cx - 80}" y="717" width="160" height="2" fill="${BORDER}"/>` +
      T(cx, 795, t.line, { size: 36, weight: 500, fill: SECONDARY, anchor: "middle" });
  } else {
    body =
      T(cx, 525, t.big, { size: 108, weight: 900, fill: GOLD, anchor: "middle" }) +
      T(cx, 583, t.under, { size: 30, weight: 500, fill: SECONDARY, anchor: "middle" }) +
      T(cx, 685, t.caption[0], { size: 46, weight: 600, fill: CREAM, anchor: "middle" }) +
      T(cx, 745, t.caption[1], { size: 46, weight: 600, fill: CREAM, anchor: "middle" }) +
      `<rect x="${cx - 80}" y="787" width="160" height="2" fill="${BORDER}"/>` +
      T(cx, 865, t.line, { size: 36, weight: 500, fill: SECONDARY, anchor: "middle" });
  }
  return head(1200, 1200) +
    `<rect width="1200" height="1200" fill="${NAVY}"/>` +
    faintRings(cx, 600) +
    coin(60, 60, 96, { coinFill: CARD }) +
    T(1140, 118, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    body +
    `</svg>`;
}

/* ============ RENDER ============ */
const jobs = [
  ["g1_reminder_X_en.png", xCard("en")],
  ["g1_reminder_TG_en.png", tgCard("en")],
  ["g1_reminder_TG_it.png", tgCard("it")],
];

for (const [name, svg] of jobs) {
  render(svg, `${OUT}/${name}`);
  console.log("ok", name);
}
console.log("ALL DONE");
