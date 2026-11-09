import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { coin, render } from "./lib.mjs";

// G1 "Myth of Er" cards (Friday 13 Nov 2026): the spindle of Necessity
// (Plato, Republic X) as the illustration, the proposal date in gold. Same
// toolchain as g1_reminder.mjs (resvg + Inter from fonts/use); the logo comes
// from ../brand/daimon-logo.svg through lib.mjs, untouched.
//
//   node g1_er.mjs   -> out/g1_er_X_en.png  (1600 x 900)
//                       out/g1_er_TG_en.png (1200 x 1200)
//                       out/g1_er_TG_it.png (1200 x 1200)
//
// Palette: navy #0a1128, card #111b3a, gold #c9a227, cream #f5e9c8,
// secondary #8a94ad. One font (Inter), three text colours. Tone-on-tone
// elements only in cream at low opacity; gold only for the spindle and the
// date. No background rings: the only rings are the whorls of the spindle.
// X safe zone: nothing on the edges, no text bottom-left (the avatar).

const NAVY = "#0a1128";
const CARD = "#111b3a";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";
const SECONDARY = "#8a94ad";

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

// The spindle of Necessity: eight nested whorls (concentric ellipses, same
// centre, same tilt, seen in perspective) in cream tone-on-tone, and the
// spindle itself, one gold vertical line through the common centre that
// reaches a little beyond the outermost whorl top and bottom.
const WHORLS = [290, 252, 216, 182, 150, 120, 92, 66]; // horizontal radii, px
const SQUASH = 0.42; // vertical radius / horizontal radius (perspective)
const TILT = -12; // degrees, the same for every whorl
const BEYOND = 60; // the spindle's reach beyond the outermost whorl, px

function spindle(cx, cy) {
  let s = "";
  for (const rx of WHORLS) {
    const ry = (rx * SQUASH).toFixed(2);
    s += `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none" stroke="${CREAM}" stroke-opacity="0.3" stroke-width="1.5" transform="rotate(${TILT} ${cx} ${cy})"/>`;
  }
  const th = (TILT * Math.PI) / 180;
  const rx = WHORLS[0], ry = rx * SQUASH;
  const halfH = Math.sqrt((rx * Math.sin(th)) ** 2 + (ry * Math.cos(th)) ** 2) + BEYOND;
  s += `<line x1="${cx}" y1="${(cy - halfH).toFixed(2)}" x2="${cx}" y2="${(cy + halfH).toFixed(2)}" stroke="${GOLD}" stroke-width="2.5" stroke-linecap="round"/>`;
  return s;
}

// The river (Lethe): one thin wavy horizontal line in the secondary colour,
// below everything else, inside the margins.
function river(x0, x1, y, { amp = 7, wavelength = 96 } = {}) {
  const pts = [];
  for (let x = x0; x <= x1; x += 4) {
    pts.push(`${x},${(y + amp * Math.sin(((x - x0) / wavelength) * 2 * Math.PI)).toFixed(2)}`);
  }
  return `<polyline points="${pts.join(" ")}" fill="none" stroke="${SECONDARY}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>`;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

const TEXT = {
  en: {
    big: ["The choice comes", "before the river."],
    date: "16 Nov · 12:00 UTC",
    small: "Myth of Er · Plato, Republic X · G1 snapshot",
  },
  it: {
    big: ["La scelta viene", "prima del fiume."],
    date: "16 nov · 13:00 · ora italiana",
    small: "Mito di Er · Platone, Repubblica X · snapshot di G1",
  },
};

/* ============ X card 1600×900: spindle left, text right (left-aligned) ============ */
function xCard(lang) {
  const t = TEXT[lang];
  const tx = 860;
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    coin(70, 70, 96, { coinFill: CARD }) +
    T(1530, 128, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    spindle(440, 450) +
    T(tx, 372, t.big[0], { size: 68, weight: 700, fill: CREAM }) +
    T(tx, 456, t.big[1], { size: 68, weight: 700, fill: CREAM }) +
    T(tx, 544, t.date, { size: 44, weight: 700, fill: GOLD }) +
    T(tx, 614, t.small, { size: 26, weight: 500, fill: SECONDARY }) +
    river(120, 1480, 790) +
    `</svg>`;
}

/* ============ Telegram card 1200×1200: spindle above, text below (centred) ============ */
function tgCard(lang) {
  const t = TEXT[lang];
  const cx = 600;
  return head(1200, 1200) +
    `<rect width="1200" height="1200" fill="${NAVY}"/>` +
    coin(60, 60, 96, { coinFill: CARD }) +
    T(1140, 118, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    spindle(cx, 380) +
    T(cx, 730, t.big[0], { size: 72, weight: 700, fill: CREAM, anchor: "middle" }) +
    T(cx, 816, t.big[1], { size: 72, weight: 700, fill: CREAM, anchor: "middle" }) +
    T(cx, 902, t.date, { size: 44, weight: 700, fill: GOLD, anchor: "middle" }) +
    T(cx, 972, t.small, { size: 26, weight: 500, fill: SECONDARY, anchor: "middle" }) +
    river(120, 1080, 1085) +
    `</svg>`;
}

export const cards = () => [
  ["g1_er_X_en.png", xCard("en")],
  ["g1_er_TG_en.png", tgCard("en")],
  ["g1_er_TG_it.png", tgCard("it")],
];

/* ============ RENDER ============ */
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const OUT = process.env.G1_OUT || "out";
  fs.mkdirSync(OUT, { recursive: true });
  for (const [name, svg] of cards()) {
    render(svg, `${OUT}/${name}`);
    console.log("ok", name);
  }
  console.log("ALL DONE");
}
