import fs from "node:fs";
import { pathToFileURL } from "node:url";
import { coin, render } from "./lib.mjs";

// G1 "Myth of Er" cards (Friday 13 Nov 2026), version 4: the scene of v3,
// "the cosmos of Er" (Plato, Republic X) as a generative particle composition
// in the language of the particle engine of daimon.money (seeded mulberry32,
// small round dots, nothing but dots), unchanged (same seed, same parameters,
// same position), with a new text block: a small kicker, the headline, the
// date. Same toolchain as g1_reminder.mjs (resvg + Inter from fonts/use); the
// logo comes from ../brand/daimon-logo.svg through lib.mjs, untouched.
//
//   node g1_er.mjs   -> out/g1_er_X_en.png  (1600 x 900)
//                       out/g1_er_TG_en.png (1200 x 1200)
//                       out/g1_er_TG_it.png (1200 x 1200)
//
// Palette: navy #0a1128, card #111b3a (the coin only), gold #c9a227,
// cream #f5e9c8, secondary #8a94ad. Rules of the illustration:
//   - every particle has exactly one palette colour, nothing is blended;
//   - gold and secondary are always at full opacity: they fade only by size
//     and density; cream may fade by opacity as well;
//   - gold particles have a radius of at least GOLD_MIN_R (1.0 px);
//   - no solid line anywhere: the orbits, the axis and the river are dots;
//   - all randomness comes from mulberry32(SEED): two renders are identical.
// X safe zone: nothing on the edges, no text bottom-left (the avatar).

const NAVY = "#0a1128";
const CARD = "#111b3a";
const GOLD = "#c9a227";
const CREAM = "#f5e9c8";
const SECONDARY = "#8a94ad";

const SEED = 20261116; // the date of the proposal
const GOLD_MIN_R = 1.0;

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const f2 = (n) => Number(n.toFixed(2));

function T(x, y, s, { size = 40, weight = 700, fill = CREAM, anchor = "start", op = 1, spacing = 0 } = {}) {
  return `<text x="${x}" y="${y}" font-family="Inter" font-weight="${weight}" font-size="${size}" fill="${fill}" fill-opacity="${op}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${esc(s)}</text>`;
}

/* ============ Deterministic randomness ============ */
// The same generator as src/lib/shapes.ts on daimon.money.
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
// Standard normal from two uniforms (Box-Muller), still seeded.
function gauss(rand) {
  let u = 0;
  while (u === 0) u = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rand());
}
const lerp = (a, b, t) => a + (b - a) * t;

/* ============ The scene: the cosmos of Er ============ */
// 1. The spindle as a cosmos: eight concentric orbits (same centre, axis
//    ratio SQUASH, tilt TILT) made only of dots scattered along each ellipse
//    with a small radial jitter (a few with a wider one, so a thin scatter
//    lives between the orbits). Inner orbits mostly gold, outer mostly cream.
//    Depth: on the far (upper) half of each ellipse the dots are smaller and
//    the cream ones dimmer; on the near (lower) half larger and brighter.
// 2. The axis of Necessity: a vertical beam of gold dots through the centre,
//    densest at the centre, thinning by density toward both ends, reaching
//    AXIS_BEYOND px beyond the outermost orbit above and below.
// 3. The eight Sirens: one larger bright cream dot (SIREN_R) on each orbit,
//    with a soft cream halo (HALO_R at HALO_OP), at angles stepping by a
//    constant so the eight read as a gentle spiral.
// 4. The fall: under the orbits sparse dots drift down on slightly curved
//    paths, smaller as they fall; cream near the orbits, secondary lower
//    down (the proportion changes with depth, each dot keeps one colour).
// 5. The river of forgetting: a horizontal current of secondary dots along
//    RIVER_LINES sinuous streamlines close under the axis; size and density
//    decrease toward both ends and toward the bottom, so the current
//    dissolves into the navy.
// 6. Dust: a very sparse scattering of tiny cream dots inside the scene box.
const ORBITS = [240, 208, 178, 150, 124, 100, 78, 56]; // horizontal radii, outer -> inner
const SQUASH = 0.42; // vertical radius / horizontal radius (perspective)
const TILT = -12; // degrees, the same for every orbit
const ORBIT_DENSITY = 1.6; // dots per px of perimeter
const ORBIT_JITTER = 1.6; // radial jitter, px (sigma), for most dots
const ORBIT_SCATTER = 0.14; // share of the dots with the wide jitter
const ORBIT_SCATTER_JITTER = 9; // px (sigma)
const GOLD_SHARE = (i) => 0.12 + 0.78 * ((i / (ORBITS.length - 1)) ** 1.3); // i = 0 outer ... 7 inner

const AXIS_BEYOND = 70; // the axis reaches this far beyond the outermost orbit, px
const AXIS_COUNT = 640;
const AXIS_JITTER = 1.5; // px (sigma)

const SIREN_R = 5;
const HALO_R = 12;
const HALO_OP = 0.2;
const SIREN0 = 200; // first Siren's angle on the outermost orbit, degrees
const SIREN_STEP = 32; // angle step orbit by orbit (the spiral), degrees

const FALL_PATHS = 26;
const FALL_HALF = 200; // the fall starts within this half-width, px

const RIVER_GAP = 28; // axis bottom -> first streamline, px
const RIVER_LINES = 4;
const RIVER_PITCH = 13;
const RIVER_FACTOR = 1.3; // river half-width / outermost orbit half-width
const RIVER_COUNT = 520; // dots on the first streamline (the others fewer)

const DUST_COUNT = 80;

const TH = (TILT * Math.PI) / 180, COS = Math.cos(TH), SIN = Math.sin(TH);
// extent of a tilted ellipse along x and y
const extentX = (rx) => Math.sqrt((rx * COS) ** 2 + (rx * SQUASH * SIN) ** 2);
const extentY = (rx) => Math.sqrt((rx * SIN) ** 2 + (rx * SQUASH * COS) ** 2);
// a point of the ellipse rx (scaled by `scale`) at parameter t, relative to the centre
function onOrbit(rx, t, scale = 1) {
  const px = rx * scale * Math.cos(t), py = rx * SQUASH * scale * Math.sin(t);
  return [px * COS - py * SIN, px * SIN + py * COS];
}
// Ramanujan's perimeter
const perimeter = (rx) => { const a = rx, b = rx * SQUASH; return Math.PI * (3 * (a + b) - Math.sqrt((3 * a + b) * (a + 3 * b))); };

// Geometry of the whole group relative to the orbits' centre (cx, cy).
export function sceneBox() {
  const halfShaft = extentY(ORBITS[0]) + AXIS_BEYOND;
  const riverTop = halfShaft + RIVER_GAP;
  const bottom = riverTop + (RIVER_LINES - 1) * RIVER_PITCH + 10;
  const halfRiver = extentX(ORBITS[0]) * RIVER_FACTOR;
  return { top: -halfShaft, bottom, halfRiver, halfShaft, riverTop };
}

let lastStats = null;
export const stats = () => lastStats;

export function scene(cx, cy) {
  const rand = mulberry32(SEED);
  const { halfShaft, riverTop, halfRiver } = sceneBox();
  const n = { orbits: 0, orbitGold: 0, orbitCream: 0, axis: 0, sirens: 0, halos: 0, fallCream: 0, fallSecondary: 0, river: 0, dust: 0 };
  let s = `<g class="art">`;
  const dot = (x, y, r, color, op = 1) => {
    if (color === GOLD) { r = Math.max(GOLD_MIN_R, r); op = 1; }
    if (color === SECONDARY) op = 1;
    s += `<circle cx="${f2(cx + x)}" cy="${f2(cy + y)}" r="${f2(r)}" fill="${color}"${op < 1 ? ` fill-opacity="${f2(op)}"` : ""}/>`;
  };

  // 1. the orbits
  ORBITS.forEach((rx, i) => {
    const count = Math.round(perimeter(rx) * ORBIT_DENSITY);
    const goldShare = GOLD_SHARE(i);
    for (let k = 0; k < count; k++) {
      const t = rand() * 2 * Math.PI;
      const wide = rand() < ORBIT_SCATTER;
      const dr = gauss(rand) * (wide ? ORBIT_SCATTER_JITTER : ORBIT_JITTER);
      const [x, y] = onOrbit(rx, t, 1 + dr / rx);
      const depth = (Math.sin(t) + 1) / 2; // 0 = far (upper) half, 1 = near (lower) half
      const v = 0.85 + 0.3 * rand();
      if (rand() < goldShare) {
        dot(x, y, lerp(1.0, 1.9, depth) * v, GOLD);
        n.orbitGold++;
      } else {
        dot(x, y, lerp(0.7, 1.8, depth) * v, CREAM, lerp(0.35, 0.95, depth) * (0.9 + 0.1 * rand()));
        n.orbitCream++;
      }
      n.orbits++;
    }
  });

  // 2. the axis of Necessity
  for (let k = 0; k < AXIS_COUNT; k++) {
    const u = rand();
    const y = (rand() < 0.5 ? -1 : 1) * halfShaft * (1 - Math.sqrt(1 - u)); // linear density, densest at the centre
    const x = gauss(rand) * AXIS_JITTER;
    const core = 1 - Math.abs(y) / halfShaft;
    dot(x, y, (1.0 + 0.9 * core) * (0.8 + 0.4 * rand()), GOLD);
    n.axis++;
  }

  // 3. the eight Sirens
  ORBITS.forEach((rx, i) => {
    const a = ((SIREN0 + i * SIREN_STEP) * Math.PI) / 180;
    const [x, y] = onOrbit(rx, a);
    dot(x, y, HALO_R, CREAM, HALO_OP);
    n.halos++;
    dot(x, y, SIREN_R, CREAM);
    n.sirens++;
  });

  // 4. the fall: from the lower edge of the outermost orbit down to the river
  const lower = new Map(); // integer x -> lowest y of the outermost orbit
  for (let k = 0; k < 2880; k++) {
    const [x, y] = onOrbit(ORBITS[0], (k / 2880) * 2 * Math.PI);
    const xi = Math.round(x);
    if (!lower.has(xi) || y > lower.get(xi)) lower.set(xi, y);
  }
  for (let p = 0; p < FALL_PATHS; p++) {
    const x0 = (rand() * 2 - 1) * FALL_HALF;
    const yStart = (lower.get(Math.round(x0)) ?? 0) + 8 + rand() * 14;
    const yEnd = riverTop - 16 - rand() * 10;
    const curve = (rand() * 2 - 1) * 34, wob = (rand() * 2 - 1) * 6;
    const m = 4 + Math.floor(rand() * 4);
    for (let k = 0; k < m; k++) {
      const t = (k + 0.3 + rand() * 0.5) / m;
      const y = lerp(yStart, yEnd, t), x = x0 + curve * t * t + wob * Math.sin(t * Math.PI * 2);
      const v = 0.8 + 0.4 * rand();
      if (rand() < 1 - t) {
        dot(x, y, lerp(1.7, 0.7, t) * v, CREAM, lerp(0.9, 0.45, t));
        n.fallCream++;
      } else {
        dot(x, y, lerp(1.3, 0.5, t) * v, SECONDARY);
        n.fallSecondary++;
      }
    }
  }

  // 5. the river of forgetting
  for (let k = 0; k < RIVER_LINES; k++) {
    const count = Math.round(RIVER_COUNT * (1 - 0.18 * k));
    const amp = 7 - 0.8 * k, wavelength = 170 + 40 * k, phase = rand() * 2 * Math.PI;
    const yk = riverTop + k * RIVER_PITCH;
    let placed = 0;
    while (placed < count) {
      const x = (rand() * 2 - 1) * halfRiver;
      const e = 1 - (x / halfRiver) ** 2; // envelope: 1 at the centre, 0 at the ends
      if (rand() > e ** 1.1) continue; // density follows the envelope
      const y = yk + amp * Math.sin((2 * Math.PI * x) / wavelength + phase) + gauss(rand) * (1.0 + 0.3 * k);
      dot(x, y, Math.max(0.35, (0.45 + 1.25 * e) * (1 - 0.17 * k) * (0.8 + 0.4 * rand())), SECONDARY);
      placed++;
      n.river++;
    }
  }

  // 6. dust, inside the scene box only
  const { top, bottom } = sceneBox();
  for (let k = 0; k < DUST_COUNT; k++) {
    dot((rand() * 2 - 1) * halfRiver, lerp(top, bottom, rand()), 0.4 + 0.4 * rand(), CREAM, 0.2 + 0.25 * rand());
    n.dust++;
  }

  n.total = n.orbits + n.axis + n.sirens + n.halos + n.fallCream + n.fallSecondary + n.river + n.dust;
  lastStats = n;
  return s + `</g>`;
}

const head = (w, h) =>
  `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">`;

/* ============ The text block: kicker, headline, date ============ */
// The headline is broken where it reads naturally; the X card (narrower
// column, 640 px between x = 860 and the 100 px margin) takes three lines,
// the Telegram cards two. Rendered ink widths (Inter Bold, resvg):
//   X  68 px: "The choice comes" 602, "before the river" 507, "of forgetting." 430
//   TG 72 px: "The choice comes before" 884, "the river of forgetting." 769
//             "La scelta viene prima" 736, "del fiume dell'oblio." 683
// Both fit at the v3 sizes (68 / 72), so no step down was needed.
const TEXT = {
  en: {
    kicker: "THE MYTH OF ER · PLATO",
    x: ["The choice comes", "before the river", "of forgetting."],
    tg: ["The choice comes before", "the river of forgetting."],
    date: "16 Nov · 12:00 UTC",
  },
  it: {
    kicker: "IL MITO DI ER · PLATONE",
    tg: ["La scelta viene prima", "del fiume dell'oblio."],
    date: "16 nov · 13:00 · ora italiana",
  },
};

// Ink metrics of Inter as resvg renders it (measured): the block is centred on
// its ink, from the top of the kicker's capitals to the date's baseline (the
// dates have no descenders).
const KICKER = { size: 24, weight: 600, spacing: 3, cap: 18 }; // uppercase, letter-spaced, cap height 18 px
const DATE = { size: 50, weight: 700 }; // unchanged from v3
const GAP_KICKER = 26; // kicker baseline -> top of the headline's ascenders, px
const GAP_DATE = 88; // last headline baseline -> date baseline, px (as in v3)
const ascent = (size) => Math.round(size * 0.78); // top of the ascenders above the baseline
const pitch = (size) => size + 14; // headline line pitch: 68 -> 82, 72 -> 86

function textBlock(x, centreY, t, lines, size, anchor) {
  const n = lines.length;
  const height = KICKER.cap + GAP_KICKER + ascent(size) + pitch(size) * (n - 1) + GAP_DATE;
  const kickerY = Math.round(centreY - height / 2 + KICKER.cap);
  const first = kickerY + GAP_KICKER + ascent(size);
  let s = T(x, kickerY, t.kicker, { size: KICKER.size, weight: KICKER.weight, fill: SECONDARY, anchor, spacing: KICKER.spacing });
  lines.forEach((line, i) => { s += T(x, first + i * pitch(size), line, { size, weight: 700, fill: CREAM, anchor }); });
  return s + T(x, first + (n - 1) * pitch(size) + GAP_DATE, t.date, { size: DATE.size, weight: DATE.weight, fill: GOLD, anchor });
}

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
    textBlock(tx, 450, t, t.x, 68, "start") + // vertically centred on the card
    `</svg>`;
}

/* ============ Telegram card 1200×1200: scene above, text below (centred) ============ */
function tgCard(lang) {
  const t = TEXT[lang];
  const box = sceneBox();
  const groupTop = 226;
  const cy = f2(groupTop - box.top);
  const cx = 600;
  const sceneBottom = groupTop + (box.bottom - box.top); // 664
  const margin = 1100; // the 100 px bottom margin
  return head(1200, 1200) +
    `<rect width="1200" height="1200" fill="${NAVY}"/>` +
    coin(60, 60, 96, { coinFill: CARD }) +
    T(1140, 118, "daimon-dao", { size: 26, weight: 500, fill: SECONDARY, anchor: "end" }) +
    scene(cx, cy) +
    textBlock(cx, (sceneBottom + margin) / 2, t, t.tg, 72, "middle") + // centred in the free space under the scene
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
    console.log("ok", name, "particles", stats().total);
  }
  console.log("ALL DONE");
}
