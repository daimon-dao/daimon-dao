// Fresh loads of the production app in NEW browser contexts (no cache, no storage): counts
// hydration errors (#418), other page errors, the theme class and whether Vercel's bot
// challenge script was injected into <head> (the known cause of #418 on headless loads).
//   BASE=https://app.daimon.money node prod-loads.mjs [loads=6]
import puppeteer from "puppeteer-core";

const BASE = (process.env.BASE ?? "https://app.daimon.money").replace(/\/+$/, "");
const BROWSER = process.env.BROWSER ?? "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const N = Number(process.argv[2] ?? "6");
const ROUTES = (process.env.ROUTES ?? "/,/staking,/migrazione,/governance,/terms,/").split(",");

const browser = await puppeteer.launch({ executablePath: BROWSER, headless: true, args: ["--lang=en-US"] });
let hyd = 0, other = 0, challenged = 0;
for (let i = 0; i < N; i++) {
  const ctx = await browser.createBrowserContext();
  const page = await ctx.newPage();
  await page.setViewport({ width: 1280, height: 900 });
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e).slice(0, 120)));
  page.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text().slice(0, 120)); });
  const route = ROUTES[i % ROUTES.length];
  const res = await page.goto(BASE + route, { waitUntil: "networkidle0", timeout: 120000 });
  await new Promise((r) => setTimeout(r, 1500));
  const s = await page.evaluate(() => ({
    cls: document.documentElement.className,
    lang: document.documentElement.lang,
    challenge: !!document.querySelector('head > script[src^="/"][src*="_"]:not([src*="_next"])') || !!document.head.firstElementChild?.matches?.('script[type="text/javascript"][src]'),
    title: document.title,
    hasHeader: !!document.querySelector("header"),
  }));
  const h = errors.filter((e) => /error #418|#423|#425/.test(e)).length;
  const o = errors.filter((e) => !/error #418|#423|#425|Failed to load resource/.test(e));
  hyd += h ? 1 : 0; other += o.length; challenged += s.challenge ? 1 : 0;
  const codes = errors.filter((e) => /error #\d+/.test(e)).map((e) => e.match(/error #(\d+)/)[1]).join("+");
  console.log(`load ${i + 1} ${route}: HTTP ${res.status()}, html.class=${s.cls}, lang=${s.lang}, header=${s.hasHeader}, hydration errors=${h}${codes ? " (#" + codes + ")" : ""}, challenge script=${s.challenge}${o.length ? ", other errors: " + JSON.stringify(o) : ""}`);
  await ctx.close();
}
await browser.close();
console.log(`\n${N} fresh loads: ${hyd} with hydration errors, ${challenged} with a challenge script in head, ${other} other errors`);
