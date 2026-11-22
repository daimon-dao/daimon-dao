import fs from "node:fs";
import { coin, render } from "./lib.mjs";

// G1 "result" cards (Sunday 22 Nov 2026): the vote passed and the proposal is
// queued in the Timelock. Same toolchain as g1_live.mjs (resvg + Inter from
// fonts/use); the logo comes from ../brand/daimon-logo.svg through lib.mjs,
// untouched, in the same 96 px medallion as g1_live.mjs.
//
//   node g1_result.mjs     -> out/g1_result_X_en.png  (1600 x 900)
//                             out/g1_result_TG_en.png (1200 x 1200)
//                             out/g1_result_TG_it.png (1200 x 1200)
//
// The picture is a generative particle composition in the language of the
// website (src/components/Particles.tsx, src/lib/shapes.ts: same PRNG, same
// bulb profile): 45 gold particles, one per address that voted, flow down from
// the top into an hourglass made of cream particles (the 7 days of the
// Timelock). Every gold particle has the same radius and the same opacity:
// they count addresses, not votes. A few already rest in the upper bulb; none
// is in the lower bulb.
//
// The scene is built once, in unit coordinates, from a fixed seed, and is the
// same in the three images: a card only chooses where to put it and how large.
//
// Palette: navy #0a1128, gold #c9a227, cream #f5e9c8 (the medallion keeps its
// own disc, #111b3a, as in g1_live.mjs). One font (Inter).
// X safe zone: nothing on the edges, no text bottom-left (the avatar).

const NAVY = "#0a1128";
const CARD = "#111b3a";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";

const SEED = 20261122; // the day G1 was queued
const VOTERS = 45; // addresses that voted on G1
const RESTING = 6; // gold particles already at rest in the upper bulb

const OUT = process.env.G1_OUT || "out";
fs.mkdirSync(OUT, { recursive: true });

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const f2 = (v) => v.toFixed(2);

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

/* ============ the scene (unit coordinates, y down, height 1) ============ */

// Same seeded PRNG as the website (src/lib/shapes.ts).
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const WIDTH = 0.9; // the scene box is 0.9 wide and 1 high
const CX = WIDTH / 2;
const TOP = 0.345; // open mouth of the upper bulb
const NECK = 0.65;
const BOTTOM = 0.955;
const HALF_NECK = 0.02;
const HALF_BULB = 0.205;
const R_GOLD = 0.0105; // radius of every gold particle

/** Half-width of a bulb at `t` (0 = wide end, 1 = neck): the website's profile. */
const halfWidth = (t) => HALF_NECK + HALF_BULB * Math.pow(1 - t, 1.55);
/** Half-width of the upper bulb at height y. */
const upperHalfWidth = (y) => halfWidth((y - TOP) / (NECK - TOP));

function buildScene(seed) {
  /* --- the hourglass: cream particles on the outline of the two bulbs --- */
  const glass = [];
  {
    const rand = mulberry32(seed + 1);
    for (let k = 0; k < 1500; k++) {
      const t = rand();
      const side = rand() < 0.5 ? -1 : 1;
      const upper = rand() < 0.5;
      const y = upper ? TOP + t * (NECK - TOP) : BOTTOM - t * (BOTTOM - NECK);
      glass.push({
        x: CX + side * halfWidth(t) + (rand() - 0.5) * 0.007,
        y: y + (rand() - 0.5) * 0.004,
        r: 0.0013 + rand() * 0.0021,
        o: 0.35 + rand() * 0.65,
      });
    }
    // the base it stands on (particles, not a line)
    for (let k = 0; k < 150; k++) {
      glass.push({
        x: CX + (rand() * 2 - 1) * (HALF_NECK + HALF_BULB + 0.03),
        y: BOTTOM + 0.014 + (rand() - 0.5) * 0.005,
        r: 0.0013 + rand() * 0.0019,
        o: 0.35 + rand() * 0.55,
      });
    }
  }

  /* --- 45 gold particles --- */
  const gold = [];
  const trails = [];
  const minGap = R_GOLD * 2.9;
  const free = (x, y) => gold.every((g) => Math.hypot(g.x - x, g.y - y) >= minGap);

  // (a) the ones already at rest: a small pile held above the neck
  {
    const rand = mulberry32(seed + 2);
    let y = NECK - 0.03;
    while (gold.length < RESTING) {
      const room = upperHalfWidth(y) - R_GOLD * 1.5;
      const n = Math.min(RESTING - gold.length, Math.max(1, Math.floor((2 * room) / (R_GOLD * 2.5)) + 1));
      for (let j = 0; j < n; j++) {
        const x = CX + (n === 1 ? 0 : (j - (n - 1) / 2) * R_GOLD * 2.5);
        gold.push({ x: x + (rand() - 0.5) * 0.002, y: y + (rand() - 0.5) * 0.003 });
      }
      y -= R_GOLD * 2.15;
    }
  }

  // (b) the ones in flight: each follows its own curve from a different point
  //     at the top, through the mouth, towards the pile
  {
    const rand = mulberry32(seed + 3);
    const flying = VOTERS - RESTING;
    const order = Array.from({ length: flying }, (_, i) => i);
    for (let i = flying - 1; i > 0; i--) {
      const j = Math.floor(rand() * (i + 1));
      [order[i], order[j]] = [order[j], order[i]];
    }
    for (let i = 0; i < flying; i++) {
      const x0 = 0.03 + ((i + 0.15 + rand() * 0.7) / flying) * (WIDTH - 0.06);
      const y0 = 0.0 + rand() * 0.07;
      const e = (x0 - CX) / (WIDTH / 2); // -1 … 1: keeps the curves from crossing much
      const mouth = e * 0.13 + (rand() - 0.5) * 0.03;
      const P = [
        [x0, y0],
        [x0 + (rand() - 0.5) * 0.04, y0 + 0.13 + rand() * 0.07],
        [CX + mouth * 1.25, TOP - 0.07],
        [CX + mouth * 0.3, NECK - 0.105],
      ];
      const at = (u) => {
        const v = 1 - u;
        const b = [v * v * v, 3 * v * v * u, 3 * v * u * u, u * u * u];
        return [0, 1].map((c) => b[0] * P[0][c] + b[1] * P[1][c] + b[2] * P[2][c] + b[3] * P[3][c]);
      };
      let placed = null;
      for (let attempt = 0; attempt < 400 && !placed; attempt++) {
        const slot = attempt === 0 ? order[i] + rand() : rand() * flying;
        const u = 0.07 + (slot / flying) * 0.86;
        const [x, y] = at(u);
        const inside = y > TOP - R_GOLD;
        if (inside && Math.abs(x - CX) > upperHalfWidth(Math.max(y, TOP)) - R_GOLD * 1.8) continue;
        if (!free(x, y)) continue;
        placed = { x, y, u };
      }
      if (!placed) throw new Error(`no room for gold particle ${i} (seed ${seed})`);
      gold.push({ x: placed.x, y: placed.y });
      // the path it has travelled: a fading wake of small cream particles
      const steps = 22;
      for (let k = 1; k <= steps; k++) {
        const u = placed.u - k * 0.011;
        if (u < 0) break;
        const [x, y] = at(u);
        const fade = 1 - k / (steps + 1);
        trails.push({
          x: x + (rand() - 0.5) * 0.003,
          y: y + (rand() - 0.5) * 0.003,
          r: 0.0011 + 0.0016 * fade,
          o: 0.06 + 0.3 * fade * fade,
        });
      }
    }
  }
  if (gold.length !== VOTERS) throw new Error(`${gold.length} gold particles, expected ${VOTERS}`);
  if (gold.some((g) => g.y > NECK)) throw new Error("a gold particle is below the neck");

  /* --- the watermark: a sparse cream dust, tone on tone --- */
  const dust = [];
  {
    const rand = mulberry32(seed + 4);
    for (let k = 0; k < 520; k++) {
      dust.push({
        x: -1.4 + rand() * 3.4,
        y: -0.6 + rand() * 2.2,
        r: 0.0012 + rand() * 0.002,
        o: 0.04 + rand() * 0.07,
      });
    }
  }
  return { glass, gold, trails, dust };
}

const SCENE = buildScene(SEED);

/** The scene placed on a card: unit (0,0) at (ox,oy), 1 unit = s px. */
function scene({ s, ox, oy }) {
  const dots = (list) =>
    list
      .map((p) => `<circle cx="${f2(ox + p.x * s)}" cy="${f2(oy + p.y * s)}" r="${f2(p.r * s)}" fill-opacity="${p.o.toFixed(3)}"/>`)
      .join("");
  const gold = SCENE.gold
    .map((p) => `<circle cx="${f2(ox + p.x * s)}" cy="${f2(oy + p.y * s)}" r="${f2(R_GOLD * s)}"/>`)
    .join("");
  return (
    `<g fill="${CREAM}">${dots(SCENE.dust)}${dots(SCENE.trails)}${dots(SCENE.glass)}</g>` +
    `<g fill="${GOLD}">${gold}</g>`
  );
}

const TEXT = {
  en: {
    kicker: "G1 · approved",
    big: "97.5% For",
    line: "Queued · executable from 29 Nov, 15:16 UTC",
  },
  it: {
    kicker: "G1 · approvata",
    big: "97,5% a favore",
    line: "In coda · eseguibile dal 29 nov, 16:16 ora italiana",
  },
};

/* ============ X card 1600×900 ============ */
function xCard(lang) {
  const t = TEXT[lang];
  const x = 120;
  return head(1600, 900) +
    `<rect width="1600" height="900" fill="${NAVY}"/>` +
    scene({ s: 800, ox: 800, oy: 44 }) +
    coin(70, 70, 96, { coinFill: CARD }) +
    T(x, 330, t.kicker, { size: 48, weight: 700, fill: CREAM }) +
    T(x - 5, 470, t.big, { size: 132, weight: 900, fill: GOLD }) +
    T(x, 546, t.line, { size: 30, weight: 500, fill: CREAM, op: 0.72 }) +
    `</svg>`;
}

/* ============ Telegram card 1200×1200 ============ */
function tgCard(lang) {
  const t = TEXT[lang];
  const cx = 600;
  return head(1200, 1200) +
    `<rect width="1200" height="1200" fill="${NAVY}"/>` +
    scene({ s: 780, ox: cx - CX * 780, oy: 36 }) +
    coin(60, 60, 96, { coinFill: CARD }) +
    T(cx, 902, t.kicker, { size: 46, weight: 700, fill: CREAM, anchor: "middle" }) +
    T(cx, 1030, t.big, { size: 124, weight: 900, fill: GOLD, anchor: "middle" }) +
    T(cx, 1104, t.line, { size: 32, weight: 500, fill: CREAM, anchor: "middle", op: 0.72 }) +
    `</svg>`;
}

/* ============ RENDER ============ */
const jobs = [
  ["g1_result_X_en.png", xCard("en")],
  ["g1_result_TG_en.png", tgCard("en")],
  ["g1_result_TG_it.png", tgCard("it")],
];

for (const [name, svg] of jobs) {
  render(svg, `${OUT}/${name}`);
  console.log("ok", name);
}
console.log(`ALL DONE (seed ${SEED}, ${SCENE.gold.length} gold particles)`);
