// Experiment: serve the VERCEL build's HTML of one page as a frozen static file (captured once from
// `next start`), with its assets from .next/static, to tell "static serving timing" apart from the
// mirror's code changes when chasing a hydration mismatch.
//   node static-vercel-serve.mjs --from http://127.0.0.1:3006 --port 3007
import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { extname, join, resolve } from "node:path";

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const FROM = opt("--from", "http://127.0.0.1:3006");
const PORT = Number(opt("--port", "3007"));
const MODE = opt("--mode", "plain"); // plain | split (head first, body 150 ms later) | nocache (assets uncacheable)
// APP_DIR: another checkout to take .next/static and public/ from (e.g. the untouched master).
const APP = resolve(process.env.APP_DIR ?? "..");
const TYPES = { ".js": "application/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2" };
const pages = new Map();
for (const route of ["/", "/staking", "/governance", "/migrazione"]) {
  try {
    const r = await fetch(FROM + route, { headers: { "accept-language": "en-US" }, signal: AbortSignal.timeout(180000) });
    pages.set(route, await r.text());
    console.log("captured", route, pages.get(route).length, "bytes");
  } catch (e) { console.log("skipped", route, String(e).slice(0, 80)); }
}
createServer((req, res) => {
  const url = new URL(req.url, "http://x");
  const path = url.pathname.replace(/\/$/, "") || "/";
  if (pages.has(path)) {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    if (MODE === "split") {
      const html = pages.get(path); const cut = html.indexOf("<body");
      res.write(html.slice(0, cut));
      setTimeout(() => res.end(html.slice(cut)), 150);
      return;
    }
    return res.end(pages.get(path));
  }
  if (MODE === "proxy") {
    // dev server assets (readable React errors): fetched through, headers minimal
    return fetch(FROM + req.url).then(async (r) => { res.writeHead(r.status, { "content-type": r.headers.get("content-type") ?? "application/octet-stream" }); res.end(Buffer.from(await r.arrayBuffer())); }).catch(() => { res.writeHead(502); res.end(); });
  }
  let file = null;
  if (path.startsWith("/_next/static/")) file = join(APP, ".next", "static", path.slice("/_next/static/".length));
  else if (existsSync(join(APP, "public", path))) file = join(APP, "public", path);
  if (file && existsSync(file)) {
    res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream", ...(MODE === "nocache" ? { "cache-control": "no-store" } : {}) });
    return res.end(readFileSync(file));
  }
  res.writeHead(404);
  res.end();
}).listen(PORT, "127.0.0.1", () => console.log(`frozen Vercel pages on http://127.0.0.1:${PORT}`));
