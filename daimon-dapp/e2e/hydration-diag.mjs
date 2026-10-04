// Diagnose React #418 (hydration mismatch) on the mirror. Loads one page repeatedly in ONE browser
// context (theme toggled after the first load, as a visitor would), until a load reports a hydration
// error; then prints where the final DOM of that load differs from the final DOM of the previous,
// clean load of the same page. In production React patches NO attribute during hydration, so a
// load that re-rendered from scratch (after #418) shows exactly the attributes/text that differed.
//   BASE=... node hydration-diag.mjs [/staking/] [mobile=0] [maxLoads=8]
import puppeteer from "puppeteer-core";

const BASE = (process.env.BASE ?? "").replace(/\/+$/, "");
const BROWSER = process.env.BROWSER ?? "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const [, , route = "/staking/", mobile = "0", maxLoads = "8"] = process.argv;
const MOBILE_UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36";

const browser = await puppeteer.launch({ executablePath: BROWSER, headless: true });
const page = await browser.newPage();
if (mobile === "1") {
  await page.setUserAgent(MOBILE_UA);
  await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
} else await page.setViewport({ width: 1280, height: 900 });
await page.evaluateOnNewDocument(() => {
  if (sessionStorage.getItem("init")) return;
  sessionStorage.setItem("init", "1");
  localStorage.setItem("daimon-terms", JSON.stringify({ version: "0.3", acceptedAt: "2026-10-03T00:00:00Z" }));
  localStorage.setItem("daimon-theme", "dark");
});
const errors = [];
page.on("pageerror", (e) => errors.push(String(e).slice(0, 300)));
page.on("console", (m) => { if (m.type() === "error" || m.type() === "warning") errors.push(m.type() + ": " + m.text().replace(/\s+/g, " ").slice(0, 2500)); });

const norm = (s) => s.replace(/\s+/g, " ").replace(/<!--[^>]*-->/g, "").replace(/<script[\s\S]*?<\/script>/g, "").replace(/> </g, "><").trim();
const tokens = (s) => s.split(/(?=<)/);

function firstDiffs(a, b, n = 6) {
  const ta = tokens(a), tb = tokens(b);
  const out = [];
  let i = 0, j = 0;
  while (i < ta.length && j < tb.length && out.length < n) {
    if (ta[i] === tb[j]) { i++; j++; continue; }
    out.push(`  @${i}\n    PREV: ${ta.slice(Math.max(0, i - 1), i + 2).join("").slice(0, 300)}\n    THIS: ${tb.slice(Math.max(0, j - 1), j + 2).join("").slice(0, 300)}`);
    // resync: skip the differing token on both sides
    i++; j++;
  }
  return out;
}

let prevClean = null;
for (let n = 1; n <= Number(maxLoads); n++) {
  errors.length = 0;
  if (n === 1) await page.goto(BASE + route, { waitUntil: "networkidle0", timeout: 120000 });
  else await page.reload({ waitUntil: "networkidle0", timeout: 120000 });
  await new Promise((r) => setTimeout(r, 2500));
  const body = norm(await page.evaluate(() => document.body.outerHTML));
  const hyd = errors.filter((e) => /418|421|422|423|425|hydrat/i.test(e));
  console.log(`load ${n}: ${hyd.length ? "HYDRATION ERROR " + hyd[0].slice(0, 120) : "clean"}; html.class=${await page.evaluate(() => document.documentElement.className)}`);
  if (hyd.length && prevClean) {
    console.log("differences vs the previous clean load:");
    console.log(firstDiffs(prevClean, body).join("\n") || "  (none at token level)");
    break;
  }
  if (!hyd.length) prevClean = body;
  if (n === 1) {
    await page.evaluate(() => [...document.querySelectorAll("header button")].find((b) => /☀️|🌙/.test(b.textContent))?.click());
    await new Promise((r) => setTimeout(r, 300));
    prevClean = null; // theme changed: the next clean load is the reference
  }
}
await browser.close();
