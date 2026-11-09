import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { coin, render } from "./lib.mjs";

// G1 "Myth of Er" cards (Friday 13 Nov 2026), version 2: the spindle of
// Necessity (Plato, Republic X) above the river, one scene, the proposal date
// in gold. Same toolchain as g1_reminder.mjs (resvg + Inter from fonts/use);
// the logo comes from ../brand/daimon-logo.svg through lib.mjs, untouched.
//
//   node g1_er.mjs   -> out/g1_er_X_en.png  (1600 x 900)
//                       out/g1_er_TG_en.png (1200 x 1200)
//                       out/g1_er_TG_it.png (1200 x 1200)
//
// Palette: navy #0a1128, card #111b3a, gold #c9a227, cream #f5e9c8,
// secondary #8a94ad. One font (Inter), two text colours (cream headline, gold
// date). Cream at reduced opacity only for the whorls; gold and secondary
// always at full opacity. No background rings: the only rings are the whorls.
// X safe zone: nothing on the edges, no text bottom-left (the avatar).

const NAVY = "#0a1128";
const CARD = "#111b3a";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";
const SECONDARY = "#8a94ad";

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const f2 = (n) => Number(n.toFixed(2));

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

/* ============ The scene: spindle above the river ============ */
// Eight nested whorls: concentric ellipses, same centre, same tilt, 2 px
// cream strokes graded from 70 % (innermost) to 30 % (outermost). One Siren
// (a 5 px cream dot, full opacity) sits on each whorl; the eight angles step
// by a constant so the dots read as a gentle spiral. The spindle shaft is a
// 3 px gold vertical line through the common centre, reaching 60 px beyond
// the outermost whorl top and bottom, with a small hook (a gold semicircle,
// radius 16, turning to the right) at the top. The river is three parallel
// wavy lines in the secondary colour (2 px, full opacity, 14 px apart),
// 1.3 times the width of the outermost whorl, centred under the shaft,
// starting 50 px under the shaft's bottom end.
const WHORLS = [240, 208, 178, 150, 124, 100, 78, 56]; // horizontal radii, outer -> inner
const SQUASH = 0.42; // vertical radius / horizontal radius (perspective)
const TILT = -12; // degrees, the same for every whorl
const BEYOND = 60; // the shaft's reach beyond the outermost whorl, px
const HOOK_R = 16;
const DOT_R = 5;
const SIREN0 = 200; // first Siren's angle on the outermost whorl, degrees
const SIREN_STEP = 32; // angle step whorl by whorl (the spiral), degrees
const RIVER_GAP = 50; // shaft bottom -> first river line, px
const RIVER_PITCH = 14;
const RIVER_AMP = 6;
const RIVER_WAVELENGTH = 92;
const RIVER_FACTOR = 1.3;

const TH = (TILT * Math.PI) / 180;
const opacityOf = (i) => f2(0.3 + (0.7 - 0.3) * ((WHORLS.length - 1 - i) / (WHORLS.length - 1)));
// extent of a tilted ellipse along x and y
const extentX = (rx) => Math.sqrt((rx * Math.cos(TH)) ** 2 + (rx * SQUASH * Math.sin(TH)) ** 2);
const extentY = (rx) => Math.sqrt((rx * Math.sin(TH)) ** 2 + (rx * SQUASH * Math.cos(TH)) ** 2);

// Geometry of the whole group relative to the whorls' centre (cx, cy).
export function sceneBox() {
  const halfShaft = extentY(WHORLS[0]) + BEYOND;
  const top = -halfShaft - HOOK_R; // top of the hook
  const riverTop = halfShaft + RIVER_GAP;
  const bottom = riverTop + 2 * RIVER_PITCH + RIVER_AMP;
  const halfRiver = extentX(WHORLS[0]) * RIVER_FACTOR;
  return { top, bottom, halfRiver, halfShaft, riverTop };
}

function wave(cx, y, half) {
  const pts = [];
  const x0 = cx - half, x1 = cx + half;
  for (let x = x0; x <= x1; x += 4) {
    pts.push(`${f2(x)},${f2(y + RIVER_AMP * Math.sin(((x - x0) / RIVER_WAVELENGTH) * 2 * Math.PI))}`);
  }
  return `<polyline points="${pts.join(" ")}" fill="none" stroke="${SECONDARY}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
}

export function scene(cx, cy) {
  const { halfShaft, riverTop, halfRiver } = sceneBox();
  let s = `<g class="art">`;
  WHORLS.forEach((rx, i) => {
    s += `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${f2(rx * SQUASH)}" fill="none" stroke="${CREAM}" stroke-opacity="${opacityOf(i)}" stroke-width="2" transform="rotate(${TILT} ${cx} ${cy})"/>`;
  });
  // the shaft and its hook
  const yTop = cy - halfShaft, yBot = cy + halfShaft;
  s += `<line x1="${cx}" y1="${f2(yTop)}" x2="${cx}" y2="${f2(yBot)}" stroke="${GOLD}" stroke-width="3" stroke-linecap="round"/>`;
  s += `<path d="M ${cx} ${f2(yTop)} A ${HOOK_R} ${HOOK_R} 0 0 1 ${cx + 2 * HOOK_R} ${f2(yTop)}" fill="none" stroke="${GOLD}" stroke-width="3" stroke-linecap="round"/>`;
  // the Sirens, one per whorl, drawn after the whorls
  WHORLS.forEach((rx, i) => {
    const a = ((SIREN0 + i * SIREN_STEP) * Math.PI) / 180;
    const px = rx * Math.cos(a), py = rx * SQUASH * Math.sin(a);
    const x = cx + px * Math.cos(TH) - py * Math.sin(TH);
    const y = cy + px * Math.sin(TH) + py * Math.cos(TH);
    s += `<circle cx="${f2(x)}" cy="${f2(y)}" r="${DOT_R}" fill="${CREAM}"/>`;
  });
  // the river
  for (let k = 0; k < 3; k++) s += wave(cx, cy + riverTop + k * RIVER_PITCH, halfRiver);
  return s + `</g>`;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

const TEXT = {
  en: { big: ["The choice comes", "before the river."], date: "16 Nov · 12:00 UTC" },
  it: { big: ["La scelta viene", "prima del fiume."], date: "16 nov · 13:00 · ora italiana" },
};

/* ============ X card 1600×900: scene left, text right (left-aligned) ============ */
function xCard(lang) {
  const t = TEXT[lang];
  const box = sceneBox();
  const cy = f2(450 - (box.top + box.bottom) / 2); // the group vertically centred
  const tx = 860;
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    coin(70, 70, 96, { coinFill: CARD }) +
    T(1530, 128, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    scene(420, cy) +
    T(tx, 389, t.big[0], { size: 68, weight: 700, fill: CREAM }) +
    T(tx, 473, t.big[1], { size: 68, weight: 700, fill: CREAM }) +
    T(tx, 561, t.date, { size: 50, weight: 700, fill: GOLD }) +
    `</svg>`;
}

/* ============ Telegram card 1200×1200: scene above, text below (centred) ============ */
function tgCard(lang) {
  const t = TEXT[lang];
  const box = sceneBox();
  const groupTop = 226;
  const cy = f2(groupTop - box.top);
  const cx = 600;
  return head(1200, 1200) +
    `<rect width="1200" height="1200" fill="${NAVY}"/>` +
    coin(60, 60, 96, { coinFill: CARD }) +
    T(1140, 118, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    scene(cx, cy) +
    T(cx, 800, t.big[0], { size: 72, weight: 700, fill: CREAM, anchor: "middle" }) +
    T(cx, 886, t.big[1], { size: 72, weight: 700, fill: CREAM, anchor: "middle" }) +
    T(cx, 976, t.date, { size: 50, weight: 700, fill: GOLD, anchor: "middle" }) +
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
