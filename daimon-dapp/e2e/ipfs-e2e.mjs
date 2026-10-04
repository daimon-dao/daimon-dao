// Browser checks of the IPFS mirror build (docs/IPFS_MIRROR.md, "Testing locally"), served by
// scripts/serve-ipfs-local.mjs from a PATH origin (http://127.0.0.1:8080/ipfs/<cid>) or a SUBDOMAIN
// origin (http://<cid>.ipfs.localhost:8080), against a local anvil fork of BSC mainnet with a mock
// wallet: the dApp's public RPC calls are answered by the fork (request interception), the wallet is
// an EIP-1193 mock whose eth_sendTransaction goes to the fork (anvil --auto-impersonate: no key).
//
//   BASE=http://127.0.0.1:8080/ipfs/<cid> node ipfs-e2e.mjs setup     fund the test wallet (once per fork)
//   BASE=... node ipfs-e2e.mjs all                                   every check below, in order
//   BASE=... node ipfs-e2e.mjs smoke|nav|locale|theme|terms|notfound|dashboard|migrate|stake|vote|inapp|mobile-wc
//
// Pages carry no <base>: every URL is relative to the page itself (src/lib/route.ts); only the 404 page has one.
// Every check reports "requests: ok" only when no request of the page failed (status >= 400 or
// network error) and none escaped the site prefix (a request to the origin root outside /ipfs/<cid>/
// would be a broken relative path on a path gateway).
import puppeteer from "puppeteer-core";

const BASE = (process.env.BASE ?? "http://127.0.0.1:8080/ipfs/unset").replace(/\/+$/, "");
const ANVIL = process.env.ANVIL ?? "http://127.0.0.1:8546";
const BROWSER = process.env.BROWSER ?? "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";
const TEST = "0x7e57000000000000000000000000000000000001";
const DMX = "0x36EbA94407B53c631eE822C219e94580fadd67c7";
const DMN = "0x160864F9945C52063A7c9f5dcd57C0C89eacbE6a";
const STAKING = "0xBb596e7308D6C5AED55cEC597D372840Cbe575b1";
const GOVERNOR = "0x1397a7d25595B718BE6FEEDd42ed5E60F66E16De";
const MIGRATION = "0x76368b60514b145617385847aCFF7b7EA9764725";
const TIMELOCK = "0xCdaa1CFe783a4DE642ca3Ed98A38bFdC16f30891";
const RPC_HOSTS = ["bsc-dataseed.binance.org", "bsc-rpc.publicnode.com", "bsc-dataseed1.defibit.io", "bsc-dataseed1.ninicoin.io"];
const MOBILE_UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36";
const E18 = 10n ** 18n;
const ROUTES = ["/", "/migrazione/", "/staking/", "/governance/", "/terms/", "/terms/it/"];
const url = (route) => BASE + route;

let rpcId = 1;
async function rpc(method, params = []) {
  const r = await fetch(ANVIL, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: rpcId++, method, params }) });
  const j = await r.json();
  if (j.error) throw new Error(`${method}: ${j.error.message}`);
  return j.result;
}
const hex = (n) => "0x" + BigInt(n).toString(16);
const pad = (a) => a.toLowerCase().replace("0x", "").padStart(64, "0");
async function call(to, data) { return BigInt(await rpc("eth_call", [{ to, data }, "latest"])); }
const balanceOf = (token, who) => call(token, "0x70a08231" + pad(who));
const allowance = (token, owner, spender) => call(token, "0xdd62ed3e" + pad(owner) + pad(spender));
const fmt = (wei) => (Number(wei / 10n ** 12n) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 6 });
async function selector(sig) {
  const { keccak_256 } = await import("@noble/hashes/sha3.js").catch(() => import("@noble/hashes/sha3"));
  return "0x" + Buffer.from(keccak_256(new TextEncoder().encode(sig))).toString("hex").slice(0, 8);
}

async function setup() {
  await rpc("anvil_setBalance", [TEST, hex(10n * E18)]);
  await rpc("anvil_setBalance", [TIMELOCK, hex(1n * E18)]);
  await rpc("anvil_impersonateAccount", [TIMELOCK]);
  const amount = 5_000n * E18;
  const data = "0xa9059cbb" + pad(TEST) + amount.toString(16).padStart(64, "0"); // transfer(TEST, 5000 DMX)
  const h = await rpc("eth_sendTransaction", [{ from: TIMELOCK, to: DMX, data, gas: hex(300000) }]);
  let rec = null;
  for (let i = 0; i < 60 && !rec; i++) { rec = await rpc("eth_getTransactionReceipt", [h]); if (!rec) await sleep(500); }
  if (!rec) throw new Error("no receipt for " + h);
  console.log("DMX transfer from the fee-exempt Timelock:", rec.status === "0x1" ? "ok" : "FAILED");
  console.log("TEST balances: DMX", fmt(await balanceOf(DMX, TEST)), "DMN", fmt(await balanceOf(DMN, TEST)), "BNB", fmt(BigInt(await rpc("eth_getBalance", [TEST, "latest"]))));
}

// The mock wallet. Its permission survives a full page load (sessionStorage), as a real wallet's
// does: the mirror navigates with full page loads, and the connection must come back by itself.
function providerScript(address) {
  return `(() => {
    const ADDR = ${JSON.stringify(address)};
    const listeners = {};
    const fwd = async (method, params) => {
      const r = await fetch(${JSON.stringify(ANVIL)}, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params: params ?? [] }) });
      const j = await r.json();
      if (j.error) { const e = new Error(j.error.message); e.code = j.error.code; e.data = j.error.data; throw e; }
      return j.result;
    };
    const provider = {
      isMetaMask: true, isMockWallet: true, _log: [],
      get _authorized() { try { return sessionStorage.getItem("mock-wallet-authorized") === "1"; } catch { return false; } },
      set _authorized(v) { try { sessionStorage.setItem("mock-wallet-authorized", v ? "1" : "0"); } catch {} },
      async request({ method, params }) {
        provider._log.push(method);
        switch (method) {
          case "eth_requestAccounts": provider._authorized = true; return [ADDR];
          case "eth_accounts": return provider._authorized ? [ADDR] : [];
          case "eth_chainId": return "0x38";
          case "net_version": return "56";
          case "wallet_switchEthereumChain": provider._switches = (provider._switches ?? 0) + 1; return null;
          case "wallet_requestPermissions": case "wallet_getPermissions": return [{ parentCapability: "eth_accounts" }];
          case "wallet_revokePermissions": provider._authorized = false; return null;
          case "eth_sendTransaction": { const tx = { ...params[0], from: ADDR }; return fwd(method, [tx]); }
          case "personal_sign": case "eth_sign": case "eth_signTypedData_v4": { const e = new Error("unsupported"); e.code = 4200; throw e; }
          default: return fwd(method, params);
        }
      },
      on(ev, cb) { (listeners[ev] ??= new Set()).add(cb); return provider; },
      removeListener(ev, cb) { listeners[ev]?.delete(cb); return provider; },
      emit(ev, ...a) { listeners[ev]?.forEach((cb) => cb(...a)); },
    };
    window.ethereum = provider;
    const info = { uuid: "2b1b3c3a-0000-4000-8000-00000000mock", name: "Mock Wallet", icon: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E", rdns: "io.mock.wallet" };
    const announce = () => window.dispatchEvent(new CustomEvent("eip6963:announceProvider", { detail: Object.freeze({ info, provider }) }));
    window.addEventListener("eip6963:requestProvider", announce);
    announce();
  })();`;
}

async function openPage({ inject = true, mobile = false, fork = true, theme = "dark", terms = true, lang = "en-US", storage = {} } = {}) {
  const browser = await puppeteer.launch({ executablePath: BROWSER, headless: true, args: [`--lang=${lang}`] });
  const page = await browser.newPage();
  if (mobile) {
    await page.setUserAgent(MOBILE_UA);
    await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  } else await page.setViewport({ width: 1280, height: 900 });
  // The starting storage, written ONCE per browser context (every later document keeps what the
  // app wrote: the checks below rely on it surviving reloads).
  await page.evaluateOnNewDocument((theme, terms, storage) => {
    if (sessionStorage.getItem("e2e-init")) return;
    sessionStorage.setItem("e2e-init", "1");
    if (terms) localStorage.setItem("daimon-terms", JSON.stringify({ version: "0.3", acceptedAt: "2026-10-03T00:00:00Z" }));
    localStorage.setItem("daimon-theme", theme);
    for (const [k, v] of Object.entries(storage)) localStorage.setItem(k, v);
  }, theme, terms, storage);
  if (inject) await page.evaluateOnNewDocument(providerScript(TEST));
  const errors = [];
  const requests = { failed: [], escaped: [], external: new Set(), count: 0 };
  const site = new URL(BASE + "/");
  page.on("pageerror", (e) => errors.push(String(e).slice(0, 200)));
  page.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text().slice(0, 200)); });
  page.on("requestfailed", (r) => { const u = new URL(r.url()); if (u.host === site.host && u.pathname !== "/favicon.ico") requests.failed.push(`${r.failure()?.errorText} ${r.url()}`); });
  page.on("response", (r) => {
    const u = new URL(r.url());
    if (u.host !== site.host) { requests.external.add(u.host); return; }
    // The browser probes /favicon.ico by itself whenever a document has no icon link yet: not a request of the page.
    if (u.pathname === "/favicon.ico") return;
    requests.count++;
    if (r.status() >= 400) requests.failed.push(`${r.status()} ${r.url()}`);
    if (!r.url().startsWith(site.href) && r.url() !== site.href.slice(0, -1)) requests.escaped.push(`${r.status()} ${r.url()}`);
  });
  await page.setRequestInterception(true);
  page.on("request", async (req) => {
    const u = new URL(req.url());
    if (!fork || !RPC_HOSTS.includes(u.hostname)) return req.continue();
    const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "POST, OPTIONS" };
    if (req.method() === "OPTIONS") return req.respond({ status: 204, headers: cors });
    try {
      const r = await fetch(ANVIL, { method: "POST", headers: { "content-type": "application/json" }, body: req.postData() });
      req.respond({ status: 200, contentType: "application/json", headers: cors, body: await r.text() });
    } catch { req.abort(); }
  });
  return { browser, page, errors, requests };
}

function report(label, errors, requests) {
  const req = requests.failed.length || requests.escaped.length
    ? `FAILED ${JSON.stringify({ failed: requests.failed, escaped: requests.escaped })}`
    : `ok (${requests.count} same-site, external hosts: ${[...requests.external].join(", ") || "none"})`;
  // React #418 (hydration mismatch -> the document is re-rendered on the client) is counted, not
  // failed: it happens intermittently to the UNMODIFIED app too whenever its HTML is served as a
  // static file all at once (docs/IPFS_MIRROR.md, "Testing locally"), the page recovers, and every
  // check above still has to pass on such a load.
  const rerenders = errors.filter((e) => /error #418/.test(e)).length;
  const other = errors.filter((e) => !/error #418/.test(e));
  console.log(`${label}: requests: ${req}; hydration re-renders (#418): ${rerenders}; page errors: ${other.length ? JSON.stringify(other) : "none"}`);
  if (requests.failed.length || requests.escaped.length || other.length) process.exitCode = 1;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function buttonByText(page, re, { enabled = true } = {}) {
  for (const h of await page.$$("button")) {
    const { text, disabled } = await h.evaluate((b) => ({ text: b.textContent.trim(), disabled: b.disabled }));
    if (re.test(text) && (!enabled || !disabled)) return h;
  }
  return null;
}
async function waitButton(page, re, opts = {}, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const b = await buttonByText(page, re, opts);
    if (b) return b;
    await sleep(300);
  }
  const all = await page.$$eval("button", (bs) => bs.map((b) => [b.textContent.trim().slice(0, 40), b.disabled]));
  throw new Error(`button ${re} not found/enabled within ${timeout}ms; buttons: ${JSON.stringify(all)}`);
}
async function waitText(page, re, timeout = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (re.test(await page.evaluate(() => document.body.innerText))) return true;
    await sleep(300);
  }
  throw new Error(`text ${re} not found within ${timeout}ms`);
}
async function waitFor(fn, timeout = 60000, label = "condition") {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) { if (await fn()) return true; await sleep(500); }
  throw new Error(`${label} not met within ${timeout}ms`);
}
async function headerAddress(page) {
  return page.evaluate(() => [...document.querySelectorAll("header button")].map((b) => b.textContent.trim()).find((t) => /^0x[0-9a-f]{4}…[0-9a-f]{4}$/i.test(t)) ?? null);
}
async function connectDesktop(page) {
  if (await headerAddress(page)) { console.log("  already connected on load (reconnect from localStorage) -> header", await headerAddress(page)); return; }
  (await waitButton(page, /Connect wallet$/, {}, 15000)).click();
  const entry = (await buttonByText(page, /Mock Wallet/)) ?? (await waitButton(page, /Browser wallet/));
  const label = await entry.evaluate((b) => b.textContent.trim());
  await entry.click();
  await waitFor(async () => (await headerAddress(page)) !== null, 20000, "header shows the address");
  console.log(`  connected via "${label}" -> header ${await headerAddress(page)}`);
}
async function setInput(page, selector, value, index = 0) {
  const el = (await page.$$(selector))[index];
  await el.click();
  await page.keyboard.down("Control"); await page.keyboard.press("a"); await page.keyboard.up("Control");
  await page.keyboard.press("Backspace");
  await el.type(value);
}
const pageState = (page) => page.evaluate(() => ({
  href: location.href,
  base: document.querySelector("base")?.href ?? null,
  lang: document.documentElement.lang,
  theme: document.documentElement.className,
  pending: document.documentElement.hasAttribute("data-locale-pending"),
  bodyVisible: getComputedStyle(document.body).visibility,
  gate: !!document.querySelector(".terms-gate"),
  cookie: document.cookie,
  locale: localStorage.getItem("daimon-locale"),
  themeStored: localStorage.getItem("daimon-theme"),
  wagmiStore: localStorage.getItem("wagmi.store") ? "localStorage" : "none",
  activeNav: [...document.querySelectorAll("header nav a")].filter((a) => a.className.includes("bg-oro/15")).map((a) => a.getAttribute("href")),
  font: getComputedStyle(document.body).fontFamily.slice(0, 40),
  notice: document.querySelector('[role="status"]')?.textContent.slice(0, 60) ?? null,
}));

// ------------------------------------------------------------------ checks
async function smoke() {
  for (const route of ROUTES) {
    const { browser, page, errors, requests } = await openPage({ inject: false });
    await page.goto(url(route), { waitUntil: "networkidle0", timeout: 120000 });
    await sleep(800);
    const s = await pageState(page);
    const problems = [];
    if (s.base !== null) problems.push(`unexpected <base> ${s.base}`);
    if (s.bodyVisible !== "visible" || s.pending) problems.push(`body ${s.bodyVisible}, pending=${s.pending}`);
    if (!s.font.includes("inter") && !s.font.includes("Inter")) problems.push(`font ${s.font}`);
    // Links are relative to the page: on /staking/ the active link is "../staking/", on / it is "./".
    const depth = route.split("/").filter(Boolean).length;
    const expectNav = route === "/" ? "./" : "../".repeat(depth) + route.replace(/^\//, "");
    if (!route.startsWith("/terms") && !s.activeNav.includes(expectNav)) problems.push(`active nav ${JSON.stringify(s.activeNav)} != ${expectNav}`);
    if (route.startsWith("/terms") && s.gate) problems.push("terms gate shown on the terms page");
    const sharedPath = /\/ip[fn]s\//.test(new URL(BASE).pathname);
    if (sharedPath && !/IPFS mirror|Mirror IPFS/.test(s.notice ?? "")) problems.push(`shared-origin notice missing (${s.notice})`);
    if (!sharedPath && /IPFS mirror|Mirror IPFS/.test(s.notice ?? "")) problems.push("shared-origin notice shown on a subdomain origin");
    console.log(`smoke ${route}: ${problems.length ? "FAILED " + problems.join("; ") : "ok"} (lang=${s.lang}, theme=${s.theme}, notice=${s.notice ? "shown" : "none"})`);
    if (problems.length) process.exitCode = 1;
    report(`smoke ${route}`, errors, requests);
    await browser.close();
  }
}

async function nav() {
  const { browser, page, errors, requests } = await openPage();
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  await connectDesktop(page);
  for (const [label, expect] of [[/Staking/, "/staking/"], [/Governance/, "/governance/"], [/Migration/, "/migrazione/"], [/Dashboard/, "/"]]) {
    const link = (await page.$$("header nav a")).find(Boolean);
    const links = await page.$$("header nav a");
    let target = null;
    for (const l of links) if (label.test(await l.evaluate((a) => a.textContent))) target = l;
    if (!target) throw new Error(`nav link ${label} not found`);
    await Promise.all([page.waitForNavigation({ waitUntil: "networkidle0" }), target.click()]);
    await waitFor(async () => (await headerAddress(page)) !== null, 20000, "wallet reconnected after the full page load");
    const s = await pageState(page);
    const ok = s.href === url(expect);
    console.log(`nav ${label}: ${ok ? "ok" : "FAILED"} -> ${s.href}; wallet after reload: ${await headerAddress(page)}; store: ${s.wagmiStore}`);
    if (!ok) process.exitCode = 1;
    void link;
  }
  report("nav", errors, requests);
  await browser.close();
}

async function locale() {
  // Italian browser, nothing stored: Italian page, no cookie, no flash mark left behind.
  let { browser, page, errors, requests } = await openPage({ inject: false, lang: "it-IT" });
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  await sleep(500);
  let s = await pageState(page);
  const it1 = await page.evaluate(() => document.body.innerText.includes("Connetti"));
  console.log(`locale it-IT first visit: lang=${s.lang} italianText=${it1} cookie="${s.cookie}" stored=${s.locale} pending=${s.pending} body=${s.bodyVisible} -> ${s.lang === "it" && it1 && s.cookie === "" && !s.pending ? "ok" : "FAILED"}`);
  if (!(s.lang === "it" && it1 && s.cookie === "" && !s.pending)) process.exitCode = 1;
  // Switch to EN: localStorage, still no cookie; survives a full reload and a navigation.
  const en = (await page.$$("header button")).filter(Boolean);
  let enBtn = null;
  for (const b of en) if ((await b.evaluate((x) => x.textContent.trim())) === "en") enBtn = b;
  await enBtn.click();
  await sleep(300);
  s = await pageState(page);
  await page.reload({ waitUntil: "networkidle0" });
  await sleep(500);
  const s2 = await pageState(page);
  const en2 = await page.evaluate(() => document.body.innerText.includes("Connect wallet"));
  console.log(`locale switch to EN: stored=${s.locale} cookie="${s.cookie}"; after reload lang=${s2.lang} englishText=${en2} -> ${s.locale === "en" && s.cookie === "" && s2.lang === "en" && en2 ? "ok" : "FAILED"}`);
  if (!(s.locale === "en" && s.cookie === "" && s2.lang === "en" && en2)) process.exitCode = 1;
  report("locale", errors, requests);
  await browser.close();
  // English browser with a stored Italian choice: Italian, on every page.
  ({ browser, page, errors, requests } = await openPage({ inject: false, lang: "en-US", storage: { "daimon-locale": "it" } }));
  for (const route of ["/", "/staking/", "/governance/", "/migrazione/"]) {
    await page.goto(url(route), { waitUntil: "networkidle0" });
    await sleep(400);
    s = await pageState(page);
    const it = await page.evaluate(() => document.body.innerText.includes("Connetti"));
    console.log(`locale stored it on ${route}: lang=${s.lang} italianText=${it} title="${await page.title()}" -> ${s.lang === "it" && it ? "ok" : "FAILED"}`);
    if (!(s.lang === "it" && it)) process.exitCode = 1;
  }
  report("locale stored", errors, requests);
  await browser.close();
}

async function theme() {
  for (const start of ["dark", "light"]) {
    const { browser, page, errors, requests } = await openPage({ inject: false, theme: start });
    await page.goto(url("/staking/"), { waitUntil: "networkidle0" });
    let s = await pageState(page);
    const bg0 = await page.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
    const toggle = (await page.$$("header button")).filter(Boolean);
    let btn = null;
    for (const b of toggle) if (/☀️|🌙/.test(await b.evaluate((x) => x.textContent))) btn = b;
    await btn.click();
    await sleep(200);
    const s1 = await pageState(page);
    await page.reload({ waitUntil: "networkidle0" });
    const s2 = await pageState(page);
    const bg2 = await page.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
    const other = start === "dark" ? "light" : "dark";
    const ok = s.theme === start && s1.theme === other && s2.theme === other && s2.themeStored === other && bg0 !== bg2;
    console.log(`theme from ${start}: load=${s.theme} (${bg0}) toggled=${s1.theme} after reload=${s2.theme} (${bg2}) stored=${s2.themeStored} -> ${ok ? "ok" : "FAILED"}`);
    if (!ok) process.exitCode = 1;
    report(`theme ${start}`, errors, requests);
    await browser.close();
  }
}

async function terms() {
  // Not accepted: the full terms are readable in both languages, the app is gated, acceptance persists.
  const { browser, page, errors, requests } = await openPage({ inject: false, terms: false });
  for (const [route, re] of [["/terms/", /Terms of use/i], ["/terms/it/", /Condizioni d.uso/i]]) {
    await page.goto(url(route), { waitUntil: "networkidle0" });
    const s = await pageState(page);
    const text = await page.evaluate(() => document.body.innerText);
    const back = await page.$eval("article a", (a) => a.getAttribute("href"));
    const expectBack = "../".repeat(route.split("/").filter(Boolean).length); // "../" on /terms/, "../../" on /terms/it/
    const ok = !s.gate && re.test(text) && back === expectBack;
    console.log(`terms ${route}: gate=${s.gate} textFound=${re.test(text)} backLink="${back}" -> ${ok ? "ok" : "FAILED"}`);
    if (!ok) process.exitCode = 1;
  }
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  let s = await pageState(page);
  const gated = s.gate;
  (await waitButton(page, /I understand and accept/)).click();
  await sleep(300);
  const s1 = await pageState(page);
  await page.goto(url("/staking/"), { waitUntil: "networkidle0" });
  const s2 = await pageState(page);
  const stored = await page.evaluate(() => localStorage.getItem("daimon-terms"));
  const ok = gated && !s1.gate && !s2.gate && /"version":"0.3"/.test(stored ?? "");
  console.log(`terms gate: shown=${gated} afterAccept=${s1.gate} onNextPage=${s2.gate} stored=${stored} -> ${ok ? "ok" : "FAILED"}`);
  if (!ok) process.exitCode = 1;
  report("terms", errors, requests);
  await browser.close();
}

async function notfound() {
  const { browser, page } = await openPage({ inject: false });
  const res = await page.goto(url("/no-such-page/"), { waitUntil: "networkidle0" });
  const s = await pageState(page);
  const text = await page.evaluate(() => document.body.innerText);
  const ok = res.status() === 404 && s.base === BASE + "/" && /404|not found|non trovata/i.test(text);
  console.log(`notfound: status=${res.status()} base=${s.base} text="${text.replace(/\s+/g, " ").slice(0, 60)}" -> ${ok ? "ok" : "FAILED"}`);
  if (!ok) process.exitCode = 1;
  await browser.close();
}

async function dashboard() {
  const { browser, page, errors, requests } = await openPage({ inject: false });
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  await sleep(2500);
  const titles = await page.$$eval("[title]", (els) => els.map((e) => [e.textContent.trim().slice(0, 40), e.getAttribute("title")]).filter(([, t]) => /DMN|DMX/.test(t)));
  const toWei = (s) => { const m = s.replace(/[^0-9.]/g, ""); const [i, f = ""] = m.split("."); return BigInt(i + f.padEnd(18, "0").slice(0, 18)); };
  const ts = await call(DMN, "0x18160ddd"), init = await call(DMN, await selector("INITIAL_SUPPLY()")), staked = await call(STAKING, await selector("totalStakedAmount()")), migrated = await call(MIGRATION, await selector("totalMigrated()"));
  const chain = { totalSupply: ts, burned: init - ts, totalStaked: staked, totalMigrated: migrated };
  console.log("dashboard fork reads (wei):", Object.fromEntries(Object.entries(chain).map(([k, v]) => [k, v.toString()])));
  let matched = 0;
  for (const [label, title] of titles) {
    const w = toWei(title);
    const match = Object.entries(chain).find(([, v]) => v / 10n ** 18n === w / 10n ** 18n)?.[0];
    if (match) matched++;
    console.log(`  "${label}" title="${title}" -> ${match ?? "NO MATCH (price or not a chain read)"}`);
  }
  console.log(`dashboard: ${matched} figures match the fork -> ${matched >= 3 ? "ok" : "FAILED"}`);
  if (matched < 3) process.exitCode = 1;
  report("dashboard", errors, requests);
  await browser.close();
}

async function migrate() {
  const { browser, page, errors, requests } = await openPage();
  await page.goto(url("/migrazione/"), { waitUntil: "networkidle0" });
  await connectDesktop(page);
  const dmxBefore = await balanceOf(DMX, TEST), dmnBefore = await balanceOf(DMN, TEST);
  await waitText(page, /5,000|4,999|10,000/, 30000);
  (await waitButton(page, /^Approve the migration$/)).click();
  await waitFor(async () => (await allowance(DMX, TEST, MIGRATION)) >= dmxBefore, 60000, "allowance on chain");
  await waitButton(page, /Approval already granted/, { enabled: false });
  console.log("  approve: allowance on the fork =", fmt(await allowance(DMX, TEST, MIGRATION)), "DMX");
  const bs = await page.$$("button");
  let claimBtn = null;
  for (const b of bs) { const t = await b.evaluate((x) => ({ t: x.textContent.trim(), d: x.disabled })); if (!t.d && /migrat|receive|claim|DMN/i.test(t.t) && !/approve/i.test(t.t)) claimBtn = b; }
  if (!claimBtn) throw new Error("claim button not found; buttons: " + JSON.stringify(await page.$$eval("button", (bs) => bs.map((b) => [b.textContent.trim(), b.disabled]))));
  console.log("  clicking", await claimBtn.evaluate((b) => b.textContent.trim()));
  await claimBtn.click();
  await waitFor(async () => (await balanceOf(DMN, TEST)) > dmnBefore, 60000, "DMN received on chain");
  await sleep(2500);
  const dmxAfter = await balanceOf(DMX, TEST), dmnAfter = await balanceOf(DMN, TEST);
  const oneToOne = dmxBefore - dmxAfter === dmnAfter - dmnBefore;
  console.log(`migrate: DMX ${fmt(dmxBefore)} -> ${fmt(dmxAfter)}, DMN ${fmt(dmnBefore)} -> ${fmt(dmnAfter)} (1:1: ${oneToOne ? "YES" : "NO"}) -> ${oneToOne ? "ok" : "FAILED"}`);
  if (!oneToOne) process.exitCode = 1;
  report("migrate", errors, requests);
  await browser.close();
}

async function stake() {
  await rpc("eth_sendTransaction", [{ from: TEST, to: DMN, data: "0x095ea7b3" + pad(STAKING) + "0".repeat(64), gas: hex(100000) }]);
  await sleep(1500);
  const { browser, page, errors, requests } = await openPage();
  await page.goto(url("/staking/"), { waitUntil: "networkidle0" });
  await connectDesktop(page);
  await waitText(page, /days/, 30000);
  await setInput(page, 'input:not([type="range"])', "2000");
  await (await waitButton(page, /30 days/)).click();
  (await waitButton(page, /^1\. Approve$/)).click();
  await waitFor(async () => (await allowance(DMN, TEST, STAKING)) >= 2000n * E18, 60000, "DMN allowance for staking");
  const stakeBtn = await waitButton(page, /^Stake$/);
  const dmnBefore = await balanceOf(DMN, TEST);
  await stakeBtn.click();
  await waitFor(async () => (await balanceOf(DMN, TEST)) < dmnBefore, 60000, "DMN moved into staking");
  await sleep(3000);
  const vp = await call(STAKING, (await selector("votingPower(address)")) + pad(TEST));
  const body = await page.evaluate(() => document.body.innerText);
  console.log(`stake: DMN ${fmt(dmnBefore)} -> ${fmt(await balanceOf(DMN, TEST))}; votingPower on the fork = ${fmt(vp)} -> ${vp > 0n ? "ok" : "FAILED"}`);
  console.log("  page:", body.split("\n").filter((l) => /voting power/i.test(l)).slice(0, 2));
  if (vp === 0n) process.exitCode = 1;
  report("stake", errors, requests);
  await browser.close();
}

async function vote() {
  const { browser, page, errors, requests } = await openPage();
  await page.goto(url("/governance/"), { waitUntil: "networkidle0" });
  await connectDesktop(page);
  const countSel = await selector("proposalCount()");
  const before = await call(GOVERNOR, countSel);
  (await waitButton(page, /advanced|New proposal/i)).click();
  await waitText(page, /Target contract/);
  const inputs = await page.$$("input.input");
  await inputs[0].type(TIMELOCK.toLowerCase());
  await inputs[1].click(); await page.keyboard.down("Control"); await page.keyboard.press("a"); await page.keyboard.up("Control"); await inputs[1].type("0");
  await (await page.$("textarea.input")).type("IPFS mirror rehearsal: no-op proposal on a local fork");
  await sleep(1500);
  (await waitButton(page, /^Create proposal$/)).click();
  await waitFor(async () => (await call(GOVERNOR, countSel)) > before, 60000, "proposal count increased");
  const id = before;
  await waitText(page, /Proposal created and confirmed/, 30000);
  console.log(`  propose: proposalCount ${before} -> ${await call(GOVERNOR, countSel)}`);
  await rpc("evm_increaseTime", [86401]);
  await rpc("evm_mine", []);
  await page.goto(url("/governance/"), { waitUntil: "networkidle0" });
  await waitFor(async () => (await headerAddress(page)) !== null, 20000, "wallet reconnected after the reload");
  const yes = await waitButton(page, /^Vote Yes$/, {}, 30000);
  await yes.click();
  const hasVotedSel = await selector("hasVoted(uint256,address)");
  await waitFor(async () => (await call(GOVERNOR, hasVotedSel + id.toString(16).padStart(64, "0") + pad(TEST))) === 1n, 60000, "hasVoted on chain");
  await waitText(page, /You voted/, 30000);
  console.log(`vote: hasVoted(${id}, TEST) = true on the fork; page says "You voted" -> ok`);
  report("vote", errors, requests);
  await browser.close();
}

async function inapp() {
  const { browser, page, errors, requests } = await openPage({ mobile: true });
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  (await waitButton(page, /^Connect/)).click();
  await waitFor(async () => (await headerAddress(page)) !== null, 15000, "connected");
  const r = await page.evaluate(() => ({ log: window.ethereum._log, sheet: !!document.querySelector('[role="dialog"]') }));
  console.log(`inapp: one tap -> header ${await headerAddress(page)}; provider calls: ${r.log.join(", ")}; sheet shown: ${r.sheet}; wallet_requestPermissions sent: ${r.log.includes("wallet_requestPermissions")} -> ${!r.sheet && !r.log.includes("wallet_requestPermissions") ? "ok" : "FAILED"}`);
  if (r.sheet || r.log.includes("wallet_requestPermissions")) process.exitCode = 1;
  // The connection comes back by itself on the next page (full load).
  await page.goto(url("/staking/"), { waitUntil: "networkidle0" });
  await waitFor(async () => (await headerAddress(page)) !== null, 20000, "reconnected on /staking/");
  console.log(`inapp: still connected after a full page load -> ${await headerAddress(page)}`);
  report("inapp", errors, requests);
  await browser.close();
}

async function mobileWc() {
  // Needs a build with a WalletConnect project id (IPFS_OVERRIDE_NEXT_PUBLIC_WC_PROJECT_ID at build time).
  const { browser, page, errors, requests } = await openPage({ mobile: true, inject: false, fork: false });
  await page.goto(url("/"), { waitUntil: "networkidle0" });
  (await waitButton(page, /^Connect/)).click();
  await sleep(3500);
  const entries = await page.$$eval('[role="dialog"] button', (bs) => bs.map((b) => b.textContent.trim()));
  console.log("  mobile browser sheet entries:", JSON.stringify(entries));
  const wc = await waitButton(page, /^WalletConnect$/);
  await wc.click();
  await waitFor(async () => page.evaluate(() => !!document.querySelector("w3m-modal, wcm-modal, appkit-modal")), 30000, "WalletConnect modal element");
  await sleep(4000);
  const modal = await page.evaluate(() => {
    const el = document.querySelector("w3m-modal, wcm-modal, appkit-modal");
    const open = el?.hasAttribute("open") || el?.shadowRoot?.querySelector("[open], wui-overlay, .w3m-overlay") != null;
    return { tag: el?.tagName, open, hasQrOrLinks: !!el?.shadowRoot?.querySelector("wui-qr-code, w3m-connect-view, w3m-router, w3m-all-wallets-view") };
  });
  console.log(`mobile-wc: modal ${JSON.stringify(modal)} -> ${modal.open ? "ok" : "FAILED"}`);
  if (!modal.open) process.exitCode = 1;
  await page.screenshot({ path: "mobile-wc.png" });
  report("mobile-wc", errors.filter((e) => !/favicon|net::ERR|403|Failed to load resource|verify\.walletconnect/.test(e)), requests);
  await browser.close();
}

const cmds = { setup, smoke, nav, locale, theme, terms, notfound, dashboard, migrate, stake, vote, inapp, "mobile-wc": mobileWc };
cmds.all = async () => {
  for (const name of ["smoke", "nav", "locale", "theme", "terms", "notfound", "dashboard", "migrate", "stake", "vote", "inapp"]) {
    console.log(`\n== ${name} @ ${BASE}`);
    await cmds[name]();
  }
};
const cmd = process.argv[2];
if (!cmds[cmd]) { console.error("usage: BASE=<origin[/ipfs/<cid>]> node ipfs-e2e.mjs " + Object.keys(cmds).join("|")); process.exit(2); }
await cmds[cmd]();
console.log(`\n${cmd}: ${process.exitCode ? "FAILED" : "PASSED"}`);
