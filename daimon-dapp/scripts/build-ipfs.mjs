/*
 * The IPFS mirror build (docs/IPFS_MIRROR.md):
 *
 *   npm run build:ipfs                 -> out-ipfs/ (the site), release-ipfs/
 *                                         daimon-dapp.car + CID.txt
 *   npm run build:ipfs -- --allow-dirty   same from an uncommitted tree (dev only)
 *
 * 1. Refuses to run from a dirty tree (the CID is meant to be reproducible
 *    from a commit) and wipes the previous output.
 * 2. Runs `next build` with the "ipfs" target (next.config.mjs,
 *    src/config/target.ts): a static export. The environment is fixed HERE,
 *    from the committed .env.ipfs, so a builder's .env.local cannot change
 *    the bytes.
 * 3. Post-processes the export so the SAME files work from a subdomain
 *    gateway (https://<cid>.ipfs.<gw>/) and from a path gateway
 *    (https://<gw>/ipfs/<cid>/): the placeholder asset origin Next was given
 *    (next.config.mjs) is rewritten to paths relative to each page
 *    ("../_next/..." on /staking/), the metadata icons likewise, the font
 *    URL in the stylesheet relative to the stylesheet, and webpack's public
 *    path to the directory its runtime was loaded from. No <base> element
 *    (see src/lib/route.ts). Fails if any absolute root reference survives.
 *    A 404 page the gateways understand (ipfs-404.html) and a mirror.json
 *    naming the commit are added.
 * 4. Computes the CID (scripts/ipfs-cid.mjs) and writes the CAR to pin.
 */
import { execFileSync, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { packDirectory, UNIXFS_PARAMETERS } from "./ipfs-cid.mjs";

const APP_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = join(APP_DIR, "out-ipfs");
const RELEASE_DIR = join(APP_DIR, "release-ipfs");
const ENV_FILE = join(APP_DIR, ".env.ipfs");
// Must match next.config.mjs (assetPrefix of the ipfs target).
const PLACEHOLDER = "https://ipfs-mirror.invalid";
const BUILD_ID = "ipfs-mirror";

const args = new Set(process.argv.slice(2));
const allowDirty = args.has("--allow-dirty");

function sh(cmd, cmdArgs, opts = {}) {
  return execFileSync(cmd, cmdArgs, { cwd: APP_DIR, encoding: "utf8", ...opts }).trim();
}

function readEnvFile(file) {
  const env = {};
  for (const raw of readFileSync(file, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i < 0) throw new Error(`${file}: bad line "${line}"`);
    env[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return env;
}

function listFiles(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...listFiles(p));
    else out.push(p);
  }
  return out;
}

// ---------------------------------------------------------------- 1. source
let commit;
try {
  commit = sh("git", ["rev-parse", "HEAD"]);
  const dirty = sh("git", ["status", "--porcelain", "--", "."]);
  if (dirty) {
    if (!allowDirty) {
      console.error("build:ipfs: the dApp tree has uncommitted changes; commit them or pass --allow-dirty (dev only):\n" + dirty);
      process.exit(1);
    }
    commit += "-dirty";
  }
} catch {
  commit = process.env.DAPP_SOURCE_COMMIT;
  if (!commit) {
    console.error("build:ipfs: not a git checkout and DAPP_SOURCE_COMMIT is not set");
    process.exit(1);
  }
}

rmSync(OUT_DIR, { recursive: true, force: true });
rmSync(RELEASE_DIR, { recursive: true, force: true });
// The export reuses .next for its intermediate build.
rmSync(join(APP_DIR, ".next"), { recursive: true, force: true });

// ------------------------------------------------------------- 2. next build
const fixedEnv = readEnvFile(ENV_FILE);
const env = {
  ...process.env,
  ...fixedEnv,
  DAPP_TARGET: "ipfs",
  NEXT_PUBLIC_DAPP_TARGET: "ipfs",
  NEXT_TELEMETRY_DISABLED: "1",
};
// Overrides allowed from the command line for local testing only (e.g. a
// WalletConnect id to exercise the modal on a local gateway); the committed
// .env.ipfs is what a release uses.
for (const k of ["NEXT_PUBLIC_WC_PROJECT_ID", "NEXT_PUBLIC_CHAIN_ID"]) {
  if (process.env[`IPFS_OVERRIDE_${k}`] !== undefined) env[k] = process.env[`IPFS_OVERRIDE_${k}`];
}
console.log(`build:ipfs: commit ${commit}, chain ${env.NEXT_PUBLIC_CHAIN_ID}, WalletConnect ${env.NEXT_PUBLIC_WC_PROJECT_ID ? "on" : "off"}`);

const next = join(APP_DIR, "node_modules", "next", "dist", "bin", "next");
const build = spawnSync(process.execPath, [next, "build"], { cwd: APP_DIR, env, stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);
if (!existsSync(join(OUT_DIR, "index.html"))) {
  console.error(`build:ipfs: ${OUT_DIR}/index.html missing after the export`);
  process.exit(1);
}

// ----------------------------------------------------------- 3. post-process
const problems = [];

function depthOf(file) {
  const rel = relative(OUT_DIR, dirname(file));
  return rel ? rel.split(sep).length : 0;
}

// "" on /, "../" on /staking/, "../../" on /terms/it/: every URL in a page is
// made relative TO THAT PAGE, never to a <base> (React drops a <base> it did
// not render when it re-renders the document after a hydration mismatch; the
// app's own links are computed the same way, src/lib/route.ts).
function prefixOf(file) {
  return "../".repeat(depthOf(file));
}

const ABS_ATTR = /(\b(?:href|src)=")\/(?!\/)/g;
const ABS_FLIGHT = /(\\"(?:href|src)\\":\\")\/(?!\/)/g;

function rewriteHtml(file) {
  const prefix = prefixOf(file);
  let html = readFileSync(file, "utf8");
  if (!html.includes("<head>")) problems.push(`${file}: no <head>`);
  // Asset origin -> page-relative ("../_next/static/..."), in attributes and
  // in the RSC payload alike.
  html = html.split(`${PLACEHOLDER}/`).join(prefix);
  // The router's own asset prefix in the payload ("p"): same form, no slash.
  html = html.split(`\\"p\\":\\"${PLACEHOLDER}\\"`).join(`\\"p\\":\\"${prefix ? prefix.slice(0, -1) : "."}\\"`);
  // The metadata icons (/icon.svg?hash, /apple-icon.png?hash), same two places.
  html = html.replace(ABS_ATTR, `$1${prefix}`);
  html = html.replace(ABS_FLIGHT, `$1${prefix}`);
  for (const m of html.match(/\b(?:href|src)="\/[^/"][^"]*"/g) ?? []) problems.push(`${file}: absolute ${m}`);
  for (const m of html.match(/\\"(?:href|src)\\":\\"\/[^/\\][^\\]*/g) ?? []) problems.push(`${file}: absolute ${m}`);
  if (html.includes("<base ")) problems.push(`${file}: unexpected <base>`);
  writeFileSync(file, html);
}

function rewriteText(file) {
  // The RSC payloads Next's router would fetch on a client-side navigation;
  // the mirror navigates with full page loads (src/components/AppLink.tsx),
  // but they are kept consistent with the pages.
  const prefix = prefixOf(file);
  let txt = readFileSync(file, "utf8");
  txt = txt.split(`${PLACEHOLDER}/`).join(prefix);
  txt = txt.split(`"p":"${PLACEHOLDER}"`).join(`"p":"${prefix ? prefix.slice(0, -1) : "."}"`);
  txt = txt.replace(/("(?:href|src)":")\/(?!\/)/g, `$1${prefix}`);
  writeFileSync(file, txt);
}

function rewriteCss(file) {
  // _next/static/css/<x>.css refers to _next/static/media/<font>: a URL in a
  // stylesheet resolves against the stylesheet, so ../media/ is right at any
  // depth and on any gateway.
  let css = readFileSync(file, "utf8");
  css = css.split(`${PLACEHOLDER}/_next/static/media/`).join("../media/");
  writeFileSync(file, css);
}

function rewriteWebpackRuntime(file) {
  // Webpack's public path, used for every chunk loaded after the first paint
  // (the WalletConnect modal, the page chunks): the _next/ directory this
  // very script was loaded from, right at any depth and independent of the
  // page (the runtime is a classic script: currentScript is set while it
  // runs).
  let js = readFileSync(file, "utf8");
  const needle = `"${PLACEHOLDER}/_next/"`;
  const n = js.split(needle).length - 1;
  if (n !== 1) problems.push(`${file}: expected the public path once, found ${n}`);
  const publicPath =
    '(function(){try{var s=document.currentScript&&document.currentScript.src;if(s)return new URL("../../",s).href}catch(e){}return"_next/"})()';
  js = js.split(needle).join(publicPath);
  writeFileSync(file, js);
}

const files = listFiles(OUT_DIR);
for (const f of files) {
  if (f.endsWith(".html")) rewriteHtml(f);
  else if (f.endsWith(".txt")) rewriteText(f);
  else if (f.endsWith(".css")) rewriteCss(f);
  else if (/[\\/]webpack-[0-9a-f]+\.js$/.test(f)) rewriteWebpackRuntime(f);
}
for (const f of files) {
  if (/\.(html|txt|css|js|json)$/.test(f) && readFileSync(f, "utf8").includes(PLACEHOLDER)) {
    problems.push(`${f}: placeholder origin still present`);
  }
}

// The gateways' 404 page (served for any missing path under the root, at any
// depth): the root 404.html (depth 0, every URL relative to the root) plus a
// <base> computed at load time -- the site root is /ipfs/<cid>/ on a path
// gateway, / elsewhere. The only page that relies on a <base>.
const notFound = join(OUT_DIR, "404.html");
if (existsSync(notFound)) {
  const dyn = `<script>(function(){var m=location.pathname.match(/^\\/ip[fn]s\\/[^/]+\\//);document.write('<base href="'+(m?m[0]:'/')+'">');})();</script>`;
  const html = readFileSync(notFound, "utf8").replace("<head>", `<head>${dyn}`);
  if (!html.includes(dyn)) problems.push("404.html: base script not inserted");
  writeFileSync(join(OUT_DIR, "ipfs-404.html"), html);
} else problems.push("404.html missing");

// What this directory is, for anyone who finds it on a gateway.
const nextVersion = JSON.parse(readFileSync(join(APP_DIR, "node_modules", "next", "package.json"), "utf8")).version;
writeFileSync(
  join(OUT_DIR, "mirror.json"),
  JSON.stringify(
    {
      app: "daimon-dapp",
      target: "ipfs",
      commit,
      chainId: Number(env.NEXT_PUBLIC_CHAIN_ID),
      walletConnect: Boolean(env.NEXT_PUBLIC_WC_PROJECT_ID),
      buildId: BUILD_ID,
      next: nextVersion,
      official: "https://app.daimon.money",
      source: "https://github.com/daimon-dao/daimon-dao/blob/master/docs/IPFS_MIRROR.md",
      unixfs: UNIXFS_PARAMETERS,
    },
    null,
    2
  ) + "\n"
);

if (problems.length) {
  console.error("build:ipfs: post-processing failed:\n  " + problems.join("\n  "));
  process.exit(1);
}

// ------------------------------------------------------------------- 4. CID
mkdirSync(RELEASE_DIR, { recursive: true });
const car = join(RELEASE_DIR, "daimon-dapp.car");
const { cid, files: packed, bytes } = await packDirectory(OUT_DIR, car);
writeFileSync(join(RELEASE_DIR, "CID.txt"), cid + "\n");
cpSync(join(OUT_DIR, "mirror.json"), join(RELEASE_DIR, "mirror.json"));
console.log(`build:ipfs: ${packed.length} files, ${bytes} bytes -> ${relative(APP_DIR, OUT_DIR)}`);
console.log(`build:ipfs: CAR ${relative(APP_DIR, car)}`);
console.log(`build:ipfs: CID ${cid}`);
