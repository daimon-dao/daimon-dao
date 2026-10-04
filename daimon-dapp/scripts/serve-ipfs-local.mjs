/*
 * A local stand-in for an IPFS HTTP gateway, to test the mirror build the way
 * a gateway serves it (docs/IPFS_MIRROR.md, "Testing locally"):
 *
 *   node scripts/serve-ipfs-local.mjs [--port 8080] [--root out-ipfs] [--cid <cid>]
 *
 * then, with <cid> = release-ipfs/CID.txt unless --cid says otherwise:
 *   path gateway:       http://127.0.0.1:8080/ipfs/<cid>/
 *   subdomain gateway:  http://<cid>.ipfs.localhost:8080/   (Chromium and Firefox
 *                       resolve *.localhost to the loopback without any DNS setup)
 *
 * Gateway behaviour reproduced: a directory asked without its trailing slash
 * is redirected to it (301), a directory serves its index.html, a missing
 * path gets ipfs-404.html with status 404, content types by extension, no
 * security headers of any kind (a gateway sets none for the site). Binds to
 * 127.0.0.1 only.
 */
import { createServer } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : dflt;
};
const PORT = Number(opt("--port", "8080"));
const ROOT = resolve(opt("--root", "out-ipfs"));
const CID = opt("--cid") ?? readFileSync(resolve("release-ipfs", "CID.txt"), "utf8").trim();

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".woff2": "font/woff2",
  ".ico": "image/x-icon",
};

function send(res, status, file, extra = {}) {
  const body = readFileSync(file);
  res.writeHead(status, {
    "content-type": TYPES[extname(file)] ?? "application/octet-stream",
    "content-length": body.length,
    "x-ipfs-path": `/ipfs/${CID}`,
    ...extra,
  });
  res.end(body);
}

const server = createServer((req, res) => {
  const host = (req.headers.host ?? "").split(":")[0];
  const url = new URL(req.url, `http://${req.headers.host}`);
  let path = decodeURIComponent(url.pathname);
  let prefix = "";

  if (host === `${CID}.ipfs.localhost`) {
    // subdomain gateway: the site is the origin's root
  } else if (path === `/ipfs/${CID}`) {
    res.writeHead(301, { location: `/ipfs/${CID}/${url.search}` });
    return res.end();
  } else if (path.startsWith(`/ipfs/${CID}/`)) {
    prefix = `/ipfs/${CID}`;
    path = path.slice(prefix.length);
  } else {
    res.writeHead(404, { "content-type": "text/plain" });
    return res.end(`not this gateway's content (expected /ipfs/${CID}/ or host ${CID}.ipfs.localhost)\n`);
  }

  const file = normalize(join(ROOT, path));
  if (!file.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end();
  }
  if (existsSync(file) && statSync(file).isDirectory()) {
    if (!path.endsWith("/")) {
      res.writeHead(301, { location: `${prefix}${path}/${url.search}` });
      return res.end();
    }
    const index = join(file, "index.html");
    if (existsSync(index)) return send(res, 200, index);
  } else if (existsSync(file)) {
    return send(res, 200, file);
  }
  const nf = join(ROOT, "ipfs-404.html");
  if (existsSync(nf)) return send(res, 404, nf);
  res.writeHead(404, { "content-type": "text/plain" });
  res.end("404\n");
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`serving ${ROOT} as ${CID}`);
  console.log(`  path gateway:      http://127.0.0.1:${PORT}/ipfs/${CID}/`);
  console.log(`  subdomain gateway: http://${CID}.ipfs.localhost:${PORT}/`);
});
