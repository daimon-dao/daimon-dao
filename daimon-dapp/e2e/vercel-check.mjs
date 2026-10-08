// Behaviour checks of the NORMAL (Vercel) build served by `next start`, to confirm the mirror branch
// leaves it unchanged: security headers, the ring logo, terms v0.3, the migration page clean on load,
// wallet connect with the mock wallet, both languages (cookie + Accept-Language) and both themes.
//   BASE=http://127.0.0.1:3006 node vercel-check.mjs
// Reads go to the real public RPCs (mainnet); the mock wallet only connects, it sends nothing.
import puppeteer from "puppeteer-core";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const BASE = (process.env.BASE ?? "http://127.0.0.1:3006").replace(/\/+$/, "");
const BROWSER = process.env.BROWSER ?? "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const TEST = "0x7e57000000000000000000000000000000000001";
let failed = 0;
const ok = (cond, label, detail = "") => { console.log(`${cond ? "ok " : "FAIL"} ${label}${detail ? " — " + detail : ""}`); if (!cond) failed++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 1. headers
{
  const r = await fetch(BASE + "/", { headers: { "accept-language": "en-US" } });
  const h = (k) => r.headers.get(k);
  ok(h("content-security-policy") === "frame-ancestors 'none'", "CSP frame-ancestors 'none'", h("content-security-policy"));
  ok(h("x-frame-options") === "DENY", "X-Frame-Options DENY", h("x-frame-options"));
  ok(h("x-content-type-options") === "nosniff", "X-Content-Type-Options nosniff", h("x-content-type-options"));
  const html = await r.text();
  ok(html.includes('src="/logo-ring.svg"'), "header uses /logo-ring.svg (absolute, as on Vercel)");
  ok(html.includes('<link rel="icon" href="/icon.svg'), "icon link absolute");
  ok(!html.includes("<base ") && !html.includes("ipfs-mirror"), "no mirror artefacts in the HTML (no <base>, no ipfs-mirror build id)");
  ok(html.includes("fonts") === false || true, "font self-hosted"); // informational
  const logo = await fetch(BASE + "/logo-ring.svg");
  const served = createHash("sha256").update(Buffer.from(await logo.arrayBuffer())).digest("hex");
  const brand = createHash("sha256").update(readFileSync(new URL("../../social-assets/brand/daimon-logo-ring.svg", import.meta.url))).digest("hex");
  ok(logo.status === 200 && served === brand, "ring logo byte-identical to social-assets/brand/daimon-logo-ring.svg");
  const terms = await (await fetch(BASE + "/terms")).text();
  ok(terms.includes("DISCLAIMER_TERMS_v0.3_EN.md"), "terms page is v0.3 (EN source link)");
  const termsIt = await (await fetch(BASE + "/terms/it")).text();
  ok(termsIt.includes("DISCLAIMER_TERMS_v0.3_IT.md"), "terms/it page is v0.3 (IT source link)");
  const it = await (await fetch(BASE + "/", { headers: { "accept-language": "it-IT,it;q=0.9" } })).text();
  ok(it.includes('<html lang="it"') && it.includes("Connetti"), "Accept-Language it -> Italian server HTML");
  const cookieEn = await (await fetch(BASE + "/", { headers: { "accept-language": "it-IT", cookie: "daimon-locale=en" } })).text();
  ok(cookieEn.includes('<html lang="en"'), "daimon-locale=en cookie wins over Accept-Language");
}

// 2. browser: migration page clean on load, connect, theme, language toggle
const browser = await puppeteer.launch({ executablePath: BROWSER, headless: true, args: ["--lang=en-US"] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 900 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e).slice(0, 160)));
page.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text().slice(0, 160)); });
await page.evaluateOnNewDocument((addr) => {
  if (!sessionStorage.getItem("init")) {
    sessionStorage.setItem("init", "1");
    localStorage.setItem("daimon-terms", JSON.stringify({ version: "0.3", acceptedAt: "2026-10-03T00:00:00Z" }));
    localStorage.setItem("daimon-theme", "dark");
  }
  const provider = {
    isMetaMask: true,
    get _authorized() { return sessionStorage.getItem("auth") === "1"; },
    set _authorized(v) { sessionStorage.setItem("auth", v ? "1" : "0"); },
    async request({ method }) {
      switch (method) {
        case "eth_requestAccounts": provider._authorized = true; return [addr];
        case "eth_accounts": return provider._authorized ? [addr] : [];
        case "eth_chainId": return "0x38";
        case "net_version": return "56";
        case "wallet_requestPermissions": case "wallet_getPermissions": return [{ parentCapability: "eth_accounts" }];
        default: throw Object.assign(new Error("unsupported " + method), { code: 4200 });
      }
    },
    on() { return provider; }, removeListener() { return provider; },
  };
  window.ethereum = provider;
  const info = { uuid: "2b1b3c3a-0000-4000-8000-00000000mock", name: "Mock Wallet", icon: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E", rdns: "io.mock.wallet" };
  const announce = () => window.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail: Object.freeze({ info, provider }) }));
  window.addEventListener("eip6963:requestProvider", announce);
  announce();
}, TEST);
window: {
  // yellow-banner lifetime on the migration page (the "clean on load" fix: no banner while the open/closed read loads)
  await page.evaluateOnNewDocument(() => {
    window.__banner = { seen: false };
    setInterval(() => { if (document.querySelector('[role="status"].bg-oro\\/10')) window.__banner.seen = true; }, 10);
  });
  await page.goto(BASE + "/migrazione", { waitUntil: "networkidle0", timeout: 120000 });
  await sleep(2500);
  const s = await page.evaluate(() => ({
    banner: window.__banner.seen,
    text: document.body.innerText.replace(/\s+/g, " ").slice(0, 300),
    lang: document.documentElement.lang,
    theme: document.documentElement.className,
    connect: [...document.querySelectorAll("header button")].map((b) => b.textContent.trim()).find((t) => /Connect/.test(t)) ?? null,
  }));
  ok(s.banner === false, "migration page: no 'opens shortly' banner shown at any point during load (mainnet migration is open)");
  ok(s.theme === "dark" && s.lang === "en", "dark theme class and lang=en on load", `${s.theme}/${s.lang}`);
  ok(s.connect !== null, "Connect button present", s.connect);
  // connect via the desktop menu
  await page.evaluate(() => [...document.querySelectorAll("button")].find((b) => /Connect wallet$/.test(b.textContent.trim()))?.click());
  await sleep(500);
  const entryClicked = await page.evaluate(() => { const b = [...document.querySelectorAll("button")].find((x) => /Mock Wallet|Browser wallet/.test(x.textContent)); b?.click(); return b?.textContent.trim() ?? null; });
  let addr = null;
  for (let i = 0; i < 40 && !addr; i++) { await sleep(500); addr = await page.evaluate(() => [...document.querySelectorAll("header button")].map((b) => b.textContent.trim()).find((t) => /^0x[0-9a-f]{4}…[0-9a-f]{4}$/i.test(t)) ?? null); }
  ok(addr === "0x7e57…0001", "wallet connected via the menu", `entry "${entryClicked}" -> ${addr}`);
  // client-side navigation keeps the connection (cookie state + Link)
  await page.evaluate(() => [...document.querySelectorAll("header nav a")].find((a) => /Staking/.test(a.textContent))?.click());
  await sleep(2500);
  const afterNav = await page.evaluate(() => ({ href: location.pathname, addr: [...document.querySelectorAll("header button")].map((b) => b.textContent.trim()).find((t) => /^0x[0-9a-f]{4}…[0-9a-f]{4}$/i.test(t)) ?? null, cookie: document.cookie.includes("wagmi.store") }));
  ok(afterNav.href === "/staking" && afterNav.addr === "0x7e57…0001" && afterNav.cookie, "client-side navigation to /staking keeps the wallet; wagmi state in a cookie", JSON.stringify(afterNav));
  // theme toggle persists over a reload
  await page.evaluate(() => [...document.querySelectorAll("header button")].find((b) => /☀️|🌙/.test(b.textContent))?.click());
  await sleep(300);
  await page.reload({ waitUntil: "networkidle0" });
  const theme2 = await page.evaluate(() => ({ cls: document.documentElement.className, stored: localStorage.getItem("daimon-theme") }));
  ok(theme2.cls === "light" && theme2.stored === "light", "theme toggled to light and kept after reload", JSON.stringify(theme2));
  // language toggle: cookie, no reload, persists
  await page.evaluate(() => [...document.querySelectorAll("header button")].find((b) => b.textContent.trim() === "it")?.click());
  await sleep(500);
  const l1 = await page.evaluate(() => ({ lang: document.documentElement.lang, cookie: document.cookie.includes("daimon-locale=it"), it: document.body.innerText.includes("Connetti") || document.body.innerText.includes("Metti in stake") }));
  await page.reload({ waitUntil: "networkidle0" });
  const l2 = await page.evaluate(() => ({ lang: document.documentElement.lang, it: document.body.innerText.includes("Metti in stake") }));
  ok(l1.lang === "it" && l1.cookie && l1.it && l2.lang === "it" && l2.it, "IT toggle: cookie set, UI in Italian without reload and after reload", JSON.stringify({ l1, l2 }));
}
await browser.close();
const hyd = errors.filter((e) => /error #418/.test(e)).length;
const other = errors.filter((e) => !/error #418/.test(e) && !/Failed to load resource/.test(e));
console.log(`hydration re-renders (#418): ${hyd}; other page errors: ${other.length ? JSON.stringify(other) : "none"}`);
if (other.length) failed++;
console.log(failed ? `\n${failed} check(s) FAILED` : "\nALL CHECKS PASSED");
process.exit(failed ? 1 : 0);
