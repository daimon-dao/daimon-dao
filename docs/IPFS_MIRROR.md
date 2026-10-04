# The IPFS mirror of the dApp

Status: **phase 1 — built and tested locally, nothing published** (2026-10-04).
Phase 2 (pinning, pointing `daimon.blockchain` at it) needs the decisions
listed at the end.

## What it is

A second build of the same dApp (`daimon-dapp/`, same commit, same
contracts, same texts) that needs no server at all: a folder of static files
whose content hash (the IPFS CID) identifies it. Pinned on IPFS and named by
the Unstoppable Domains name `daimon.blockchain`, it is the backup of
`https://app.daimon.money` for the day Vercel, the DNS of `daimon.money` or a
registrar is unavailable, blocked or coerced: the contracts are
permissionless and the mirror gives holders an interface that nobody can
take down by taking down one host.

It is a **mirror**, not a second product: the official app stays
`app.daimon.money`, the mirror says so in its `mirror.json` and in the
notice it shows on shared gateways, and it is rebuilt from the same commit
as the production app whenever that matters (see "When to update").

What the mirror cannot be: a server-side anything. The sections below say
what that removes and what, if anything, replaces it.

## The build

Two targets, one source tree. The Vercel app is `npm run build`, exactly as
before: nothing in its behaviour changed (the branch that differs is
selected by `DAPP_TARGET=ipfs` and `NEXT_PUBLIC_DAPP_TARGET=ipfs`, both
unset on Vercel, and `src/config/target.ts` is the single switch the code
reads).

```bash
cd daimon-dapp && npm ci && npm run build:ipfs
```

`scripts/build-ipfs.mjs` does, in order:

1. refuses a dirty tree (pass `--allow-dirty` while developing), wipes
   `out-ipfs/`, `release-ipfs/` and the intermediate `.next/`;
2. runs `next build` with the `ipfs` target: `output: "export"`, every
   route prerendered to `<route>/index.html` (what gateways serve for a
   directory), a constant build id, and the environment taken from the
   committed `.env.ipfs` (`NEXT_PUBLIC_CHAIN_ID=56`, the WalletConnect id),
   so a builder's `.env.local` cannot change the bytes;
3. post-processes the export so the same files work from a subdomain
   gateway (`https://<cid>.ipfs.<gw>/staking/`) and from a path gateway
   (`https://<gw>/ipfs/<cid>/staking/`): every asset reference rewritten
   relative to its own page (`_next/…` on `/`, `../_next/…` on
   `/staking/`, `../../_next/…` on `/terms/it/`), the font URL inside the
   stylesheet relative to the stylesheet, webpack's public path (the chunks
   loaded after the first paint) resolved from the URL its own runtime was
   loaded from, a `404` page gateways understand (`ipfs-404.html`, the only
   file with a `<base>`, computed at load time) and `mirror.json` naming the
   commit, chain and parameters. It fails if any absolute root reference
   survives. No `<base>` element in the pages, on purpose: React drops
   whatever it did not render when it re-renders the document after a
   hydration mismatch, and a page whose links depend on a `<base>` then
   breaks (seen in the first test run);
4. computes the CID with `scripts/ipfs-cid.mjs` and writes the CAR to pin:
   `release-ipfs/daimon-dapp.car`, `release-ipfs/CID.txt`.

What the static target changes in the app, and why:

| Vercel app | IPFS mirror | Where |
|---|---|---|
| Language from the `daimon-locale` cookie, else `Accept-Language`, read by the server so the first HTML is already in the right language | Pages prerendered in English; the browser's stored choice (`localStorage` `daimon-locale`), else `navigator.language`, applied in a layout effect right after hydration. An inline script in `<head>` hides the body for an Italian-speaking visitor until then (no flash of English); the mark lifts itself after 4 s if the scripts never run | `src/lib/i18n.ts`, `src/components/LocaleProvider.tsx`, `src/app/layout.tsx` |
| Wallet state in a cookie (`cookieStorage`) so the server renders the connected state | wagmi's default store, `localStorage`; the connection is restored after mount on every page load | `src/lib/wagmi.ts` |
| `next/link` (client-side navigation, prefetch) | Plain anchors with hrefs relative to the page (`staking/` on `/`, `../staking/` on `/governance/`, `../../` on `/terms/it/`): a full page load per click. Next's router would fetch its payloads from the origin root, which on a path gateway is not the site | `src/components/AppLink.tsx` |
| `usePathname()` compared with the routes (nav highlight, "is this the terms page") | The route and the page's depth rebuilt from the router tree, read once at the root (`RouteProvider`, `useSelectedLayoutSegments`) and the same at prerender and after hydration whatever URL the gateway serves | `src/lib/route.ts` |
| Inter from Google Fonts, downloaded at build time | The same Inter (latin, variable) vendored in `src/fonts/` (`next/font/local`): no network at build time, so the bytes are a function of the commit | `src/app/font.ts`, `src/fonts/README.md` |
| Security headers, middleware | Absent (next section) | `next.config.mjs` |
| — | A notice on shared-origin gateways (next section) | `src/components/GatewayNotice.tsx` |

The dev server is not a target: `next dev` always runs the Vercel app.

## What a server used to do

| Item | On Vercel | On the mirror | Residual risk, in plain words |
|---|---|---|---|
| `Content-Security-Policy: frame-ancestors 'none'` and `X-Frame-Options: DENY` (no site may frame the dApp) | Response headers set by `next.config.mjs` | **Gone.** A static file carries no headers; gateways set their own, and none sets these for the content they serve. Nothing replaces it: a frame-busting script is bypassed by `sandbox` attributes and is not worth the false safety | A hostile page can frame the mirror and try clickjacking: overlay its own UI on a hidden frame so a click lands on "Approve" or "Migrate". The wallet still shows its own confirmation outside the page, with the amounts, so the attack needs the user to confirm in the wallet too. Mitigation: never follow links to the mirror from untrusted pages; use the subdomain form or Brave's resolution, type the CID. |
| `X-Content-Type-Options: nosniff` | Header | **Gone.** Gateways serve types by extension (`.js`, `.css`, `.html`) and most send `nosniff` themselves | Negligible: all files have proper extensions. |
| The region middleware (`src/middleware.ts`, HTTP 451 for listed countries) | Edge middleware, dormant (`RESTRICTED_COUNTRIES` is empty by decision, terms §5) | **Gone**, by construction: there is no edge and no request. The build still compiles the file (Next reports it) but a static export never runs it | None today (the list is empty). If the project ever restricts a jurisdiction on Vercel, the mirror cannot: that is what a censorship-resistant mirror means, and the terms' §5 would have to say so for the mirror. |
| One origin per site (`app.daimon.money`): `localStorage` (terms acceptance, language, theme, wagmi state, a WalletConnect session) is private to the dApp | — | Depends on the gateway. **Subdomain** gateways (`https://<cid>.ipfs.<gw>`) and Brave's resolution give each CID its own origin: private, but **reset on every new CID** (a new release = a fresh origin: terms asked again, wallet reconnected). **Path** gateways (`https://<gw>/ipfs/<cid>/`) share one origin among every site on that gateway | On a path gateway any other IPFS site opened through the same gateway can read and write what the mirror stores, including a WalletConnect session (a wallet still shows every request for approval, but it would appear to come from "Daimon DAO"). The mirror shows a notice on path gateways and links to the official app; the docs and every link the project publishes use subdomain gateways only. |
| `noindex` on testnet, metadata per language | Server metadata | Static English metadata; the title follows the language after hydration | Cosmetic. |
| Vercel's bot challenge in front of the app | Vercel | Gone | Bots can fetch the mirror freely. It is public content; nothing to protect. |
| Fresh deploys by push | Vercel | A new CID per release, to pin and to point the name at (phase 2 steps) | A stale mirror: holders may use an old interface. `mirror.json` names the commit; "When to update" below. |

## Reproducibility: same commit, same CID

The CID is a hash of the bytes, so "the same commit gives the same CID" needs
every byte to be a function of the source. What the build fixes:

- the build id is the constant `ipfs-mirror` (Next's default is random);
- the environment comes from `.env.ipfs` only (`NEXT_PUBLIC_*` values are
  inlined into the bundle: a different WalletConnect id is a different CID);
- the font is in the repository (no download at build time; Google could
  serve different bytes tomorrow);
- `mirror.json` records the commit of the tree it was built from, so a CID
  can be matched to a commit from the outside (and a `-dirty` commit never
  matches a tagged one);
- the CID is computed with explicit UnixFS parameters, the ones every IPFS
  implementation uses for `--cid-version 1`: CIDv1, sha2-256, raw leaves,
  256 KiB chunks, balanced layout, at most 174 links per node, plain
  directories (no HAMT below 256 KiB of links), no file modes or times.
  `release-ipfs/daimon-dapp.car` carries every block with that root: a
  pinning service that imports the CAR as-is reports this CID; one that
  re-adds the files with other parameters (1 MiB chunks are becoming a
  default elsewhere) reports a different CID for the same bytes.

What is NOT fixed, hence part of "the same commit":

- `package-lock.json` and Node's major version (`npm ci`, Node 24 here); a
  different Next or wagmi version is different output;
- the same post-processing, i.e. the same `scripts/`.

### Proof (two clean builds)

Done on 2026-10-04 from commit `e746190`, Node 24.20.0, Windows 11: after
`rm -rf node_modules out-ipfs release-ipfs .next && npm ci`, two consecutive
`npm run build:ipfs` produced

| Build | CID | Files | Bytes |
|---|---|---|---|
| 1 | `bafybeifnf3oepnldwebfnhukltu6bpw2rcslnny2zybuomn573pzjnkxoq` | 114 | 3,542,827 |
| 2 | `bafybeifnf3oepnldwebfnhukltu6bpw2rcslnny2zybuomn573pzjnkxoq` | 114 | 3,542,827 |

and `diff -r` of the two `out-ipfs/` directories was empty. The two CAR
files differed in byte order only (the importer reads files concurrently):
`scripts/ipfs-cid.mjs` now writes the blocks sorted by CID, and three runs
on the same export then gave one CAR, SHA-256
`5419ca61ae3a2c19cd11e9a2cb4a9feaf8e90915a533793c728579e57a40c42e`, 138
blocks, root as above. (That fix is the commit after `e746190`, which
changes nothing in `out-ipfs/`, so the CID of this commit is the same.)

### How anyone can rebuild and compare

```bash
git clone https://github.com/daimon-dao/daimon-dao.git && cd daimon-dao
git checkout <commit>            # the one in mirror.json of the published mirror
cd daimon-dapp && npm ci && npm run build:ipfs
cat release-ipfs/CID.txt         # must equal the published CID
```

Independent check of the CID itself, with any IPFS node (kubo), on the
exported folder: `ipfs add -r -Q --cid-version 1 out-ipfs` (kubo ≥ 0.40:
the `unixfs-v1-2025` profile uses 1 MiB chunks and would print a different
CID; do not apply it). The parameters are also written in `mirror.json`.

To compare a published mirror with a local build without trusting any
gateway: fetch `https://<cid>.ipfs.<gw>/mirror.json`, rebuild that commit,
compare the CID; or download the CAR from the pinning service and
`ipfs dag import` it locally.

## Testing locally

Tools, all under `daimon-dapp/`:

- `npm run serve:ipfs` (`scripts/serve-ipfs-local.mjs`): a stand-in for a
  gateway, serving `out-ipfs/` both as a path gateway
  (`http://127.0.0.1:8080/ipfs/<cid>/`) and as a subdomain gateway
  (`http://<cid>.ipfs.localhost:8080/`; browsers resolve `*.localhost` to
  the loopback without any setup). It reproduces what matters: the redirect
  that adds the trailing slash to a directory, `index.html` for a
  directory, `ipfs-404.html` with status 404 for a missing path, content
  types by extension, no security headers.
- `e2e/ipfs-e2e.mjs` (puppeteer-core driving the local Edge/Chromium): the
  mirror against a local **anvil fork of BSC mainnet** with a **mock
  wallet** (an EIP-1193 provider whose transactions go to the fork, which
  runs with `--auto-impersonate`: no key anywhere). The dApp's public RPC
  calls are intercepted and answered by the fork. `e2e/fork-proxy.mjs`
  lets anvil fork from a non-archive public RPC for hours (it reads state
  at `latest`).

```bash
# 1. fork (one terminal)
node e2e/fork-proxy.mjs --port 8547
anvil --fork-url http://127.0.0.1:8547 --port 8546 --auto-impersonate --host 127.0.0.1 --no-rate-limit
# 2. site (another terminal)
npm run build:ipfs && npm run serve:ipfs
# 3. checks, on both origins
cd e2e && npm install
node ipfs-e2e.mjs setup                                             # funds the test wallet
BASE=http://127.0.0.1:8080/ipfs/$(cat ../release-ipfs/CID.txt) node ipfs-e2e.mjs all
node ipfs-e2e.mjs setup
BASE=http://$(cat ../release-ipfs/CID.txt).ipfs.localhost:8080 node ipfs-e2e.mjs all
```

What `all` checks, on each origin: every route loads with no `<base>`, no
failed request and no request escaping the site prefix, the font, the nav
highlight, the shared-origin notice shown on the path origin
and not on the subdomain one; navigation by the header links keeps the
wallet connected across the full page loads; language (Italian browser with
nothing stored → Italian page, no cookie, no flash mark left; switch to
English → `localStorage`, survives a reload; stored Italian on every page);
theme (both starting themes, toggle, reload); terms (readable in both
languages without accepting, the gate elsewhere, acceptance persisted);
the 404 page; the dashboard figures against direct fork reads; the
migration flow (approve, claim, 1:1 on chain); staking (approve, stake,
voting power on chain); governance (propose, warp, vote, `hasVoted` on
chain); the in-app wallet path (mobile UA + injected provider: one tap, no
menu, no `wallet_requestPermissions`, still connected after a page load).
`mobile-wc` (mobile browser, no provider → the WalletConnect modal) needs a
build with a project id:
`IPFS_OVERRIDE_NEXT_PUBLIC_WC_PROJECT_ID=<id> npm run build:ipfs -- --allow-dirty`.

Results of 2026-10-04 (build of commit `542fc8b`, CID
`bafybeihecuoelmxnibwkvcqfuwfi274lnhptbdq6xz7zgdvot7mmm6glxe`, anvil fork of
BSC mainnet at the day's head through the proxy, Edge headless on Windows):
**every functional check passed on both origins** — 44 "ok" lines each on
`http://127.0.0.1:8080/ipfs/<cid>` and on `http://<cid>.ipfs.localhost:8080`:
all six routes, no failed or escaped request, nav with the wallet kept
across page loads, Italian browser → Italian page with no cookie, EN/IT
switch persisted in `localStorage`, both themes persisted, terms readable
in both languages and gate persisted, 404 page, dashboard figures equal to
the fork's (5/5), migration 5,000 DMX → 5,000 DMN (1:1 on chain), stake
2,000 DMN → voting power on chain, propose + vote (`hasVoted` on chain),
in-app one-tap connect without `wallet_requestPermissions` and still
connected after a full page load. The shared-origin notice showed on the
path origin and not on the subdomain one. `mobile-wc` was not run: the
committed `.env.ipfs` ships no WalletConnect id (decision 3).

One finding, not a failure of the mirror: on roughly one page load in four,
React reports a hydration mismatch (`Minified React error #418`) and
re-renders the document on the client; the page then works (every check
above passed on such loads too), the theme, language and terms acceptance
are re-applied by the app, and the only visible effect is a brief re-render
of the first paint. The harness counts these as "hydration re-renders" and
does not fail on them. It is **not caused by the mirror's changes**: the
untouched master dApp (`e4fa328`), built as for Vercel and with its own
assets, shows the same intermittent #418 (7 in 22 loads,
`e2e/hydration-diag.mjs` + `e2e/static-vercel-serve.mjs`) as soon as its
HTML is served as a static file in one piece — it never does when
`next start` streams the same HTML, and it stops when the file is sent in
two chunks 150 ms apart. So it is a property of Next 15 / React 19 pages
delivered whole, which is what every gateway does; it may also be the
"residual #418" seen on Vercel's cached responses. Left as is: the mirror is
built so that a client re-render loses nothing (page-relative paths, no
`<base>`, state re-applied after mount). Worth a separate investigation on
the Vercel app, outside this scope.

## Where it will live (research of 2026-10-04)

The IPFS public-goods layer changed in 2026 and the docs must not assume
what was true a year ago:

- **`ipfs.io` and `dweb.link` no longer serve content** (retired on
  2026-09-21 when Protocol Labs stopped funding Shipyard; both answer 403/429
  today). Their replacement for browsers is `inbrowser.link`, a
  service-worker gateway that fetches blocks itself from providers and gives
  each CID its own origin (`https://<cid>.ipfs.inbrowser.link/`). It is
  maintained by the IPFS Foundation on a best-effort basis; so is
  `delegated-ipfs.dev`, the routing endpoint it relies on. Kubo and the
  other reference implementations have no dedicated maintainers since
  2026-09-30. Sources: blog.ipfs.tech, "IPFS is moving beyond the sponsored
  gateways" (2026-08-25); ipshipyard.com, "The end of IPFS at Shipyard"
  (2026-08-24); filebase.com blog (2026-09-08).
- **Storacha (ex web3.storage) stopped accepting writes** (May 2026; its
  sites redirect to an unrelated product) and **Fleek hosting closed**
  (2026-01-31). nft.storage stopped uploads in 2024. Cloudflare's and
  Infura's public IPFS gateways are gone too.

### Pinning: two services, one CID

Both free, no card, different companies, both able to pin the **same**
CID (so one CID is served by both, and either can re-pin it from the other
through the standard Pinning Service API):

| | Filebase (primary) | Pinata (secondary) |
|---|---|---|
| Free tier today | 5 GB, 500 pins, 10 GB/month of gateway bandwidth, one dedicated gateway `<name>.myfilebase.com` | 1 GB, 500 files, 10 GB/month, one dedicated gateway `<name>.mypinata.cloud` |
| CAR import (CID preserved byte for byte) | **Yes, free** (`import=car` through its S3 API) | Paid plans only; on the free plan Pinata **pins by CID** (fetches the blocks from Filebase) |
| Pinning Service API | yes | yes |
| Main risk | its free tier has been trimmed several times (1,000 → 500 pins) and the company now markets S3 storage | hard 1 GB cap and a cut-off at 25 % over it; its own gateway serves HTML only with a custom domain (irrelevant: other gateways serve it) |

A 3.5 MB site is under 1 % of either quota. Alternatives looked at and not
chosen: 4EVERLAND (free tier needs an on-chain registration and its CAR
handling is undocumented), Lighthouse (free-tier retention undocumented,
proprietary pin API), a self-hosted kubo (fine as the CID oracle and a
third copy, but a home node is rarely reachable by `inbrowser.link`, which
needs HTTPS-reachable providers). Sources: pinata.cloud/pricing,
docs.pinata.cloud (uploading files, pin by CID, limits); filebase.com/pricing,
filebase docs (pinning files, Pinning Service API, dedicated gateways); all
read on 2026-10-04.

### Unstoppable Domains: `daimon.blockchain`

Read-only facts (UD public profile API and the Polygon registry, 2026-10-04):

- The name is a UNS domain on **Polygon** (chain 137), registry
  `0xa9a6A3626993D487d2Dbda3173cf58cA1a9D9e9f`, token id = namehash
  `0x42cf9218e407b8577218ee198c7651f2db66bc476c716f73e314586cc7b004d9`.
  It does not exist on Ethereum L1 or on Base, and UD does not bridge
  Polygon names to Base.
- **Owner: `0x41B533AF0Db427dc97988B47f86383f42372f395`**, which is none of
  the DMX owner (`0xF8EC…B0Ae`), the DMN deployer (`0x4D38…a26e`), the
  guardian Safe (`0x37F4…c7a8`) or its three signers (`0xD9dB…fc16`,
  `0xdFfe…687f`, `0xacA4…0F9b`). It is DMX's `marketingAddress2`
  (CHECKLIST_MAINNET.md, protocol paper §"The DMX contract"), which holds
  about 303.5 billion DMX and has 121 transactions on BSC.
- Records already set: `ipfs.html.value = QmZV91e6bp2Pn7eVdg7GHa1c8gKipu1dwJhR24ECqjA5BW`
  (the deprecated key: an IPFS site was pointed at some time in the past; no
  gateway serves that CID today), a BNB address (the owner), and the web2
  URL `https://www.daimon.one/`.

How a .blockchain name points to IPFS today:

- The record to set is `dweb.ipfs.hash = <cid>` (current key; browsers fall
  back to the deprecated `ipfs.html.value`, so setting both is the safe
  choice). Note that UD documents the value as a 46-character hash, i.e. a
  CIDv0 (`Qm…`); a CIDv1 (`bafy…`) is longer. Whether the UI accepts a
  CIDv1 is to be verified on a throwaway record first; if not, the mirror
  can be published as CIDv0 (same bytes, different encoding; both pinning
  services accept it), at the price of losing the subdomain form on some
  gateways. Decision 4 below.
- **Who signs, what it costs.** The owner wallet (`0x41B5…f395`) signs. On
  the UD website ("Manage → Website → Custom website linking → Launch
  Website") the owner signs a message in the wallet and UD's relayer pays the
  Polygon gas: free for the owner. Without UD's relayer, the owner can call
  `setMany(keys, values, tokenId)` on the registry's "Write as Proxy" tab on
  Polygonscan for a few cents of POL. A Ledger through MetaMask should
  manage either; UD's current signing format is not documented in a 2025/26
  source, so test with a throwaway record first.
- **Who resolves it.** Shrinking: UD withdrew its ICANN applications on
  2026-08-27, so `.blockchain` will never resolve in normal DNS. Brave
  resolves UD names natively (setting "Resolve Unstoppable Domains domain
  names", via Infura to the Polygon contract) and opens the content through
  a public gateway; Brave removed its local IPFS node in 2024 and moved its
  gateway from `ipfs.io` to `inbrowser.link` in 2026 (brave-browser issue
  53690; the exact release could not be confirmed). The UD browser
  extension (Chrome, Edge, Opera, Brave) resolves and redirects to a
  gateway the user picks. Opera's native support dates from 2021 and could
  not be confirmed current. MetaMask resolves UD names for sends only.
  There is no `.link`-style HTTPS gateway for UD names (`ud.me/<name>` is a
  profile page, not the site).

So `daimon.blockchain` is a pointer of last resort for Brave and extension
users; what the project must also publish is the **CID** and a gateway URL
(`https://<cid>.ipfs.inbrowser.link/`, `https://<name>.myfilebase.com/ipfs/<cid>/`).

### WalletConnect

Injected wallets (browser extensions, wallets' in-app browsers) are
unaffected by where the page is served from. WalletConnect pairing works
from any origin, but the wallet's "Verify" check compares the page's origin
with the one domain allow-listed for the project id: with
`metadata.url = https://app.daimon.money` and a gateway origin, every wallet
with Verify shows **"Domain mismatch"** (red); with no allow-listed domain,
"Cannot verify" (yellow). There is no wildcard, no second verified domain
per project, and nothing can attest an origin that changes with every CID.
MetaMask Mobile currently shows WalletConnect apps as unverified even on
their real domain (Reown note, August 2026). Options, decision 3 below:

1. ship the mirror **without** WalletConnect (`.env.ipfs` as committed):
   extensions and in-app browsers only, no warning anywhere;
2. ship the production project id and accept the red "Domain mismatch";
3. a second project id for the mirror with `metadata.url` set to one
   **stable** mirror origin the project controls (a dedicated gateway with a
   custom domain, e.g. `ipfs.daimon.money` — which brings back a DNS
   dependency for that path only) and that domain allow-listed: "Domain
   match" there, "Cannot verify" elsewhere.

## When to update the mirror

Rebuild, re-pin and re-point the name:

- **always**, for a security fix in the dApp or any change touching funds
  (what a transaction sends, the contract addresses, the RPC list, the
  terms shown before a wallet action);
- **always**, for a new terms version (`TERMS_VERSION`);
- for a major release of the dApp (a new page or flow holders rely on);
- **never** for cosmetic changes alone, and never between those events: a
  mirror that changes often is a mirror nobody can verify.

Each update is a new CID; the old CID stays valid forever where it is
pinned (unpin it after the name points at the new one and the new one is
confirmed served). Keep `release-ipfs/CID.txt` and the commit of every
published mirror in the launch record.

## Phase 2: publishing (not done)

1. Decide the four points below; set `.env.ipfs` accordingly; commit; tag
   (`ipfs-mirror-v1`).
2. From the tag: `npm ci && npm run build:ipfs`; record the CID.
3. Filebase: upload `release-ipfs/daimon-dapp.car` as a CAR import; check
   the CID it reports equals `CID.txt`; create the free dedicated gateway;
   open `https://<name>.myfilebase.com/ipfs/<cid>/` and run the smoke
   checks against it (`BASE=https://<name>.myfilebase.com/ipfs/<cid> node
   e2e/ipfs-e2e.mjs smoke`).
4. Pinata: pin by CID; wait until `https://delegated-ipfs.dev/routing/v1/providers/<cid>`
   lists both providers; open `https://<cid>.ipfs.inbrowser.link/` (the
   Brave path).
5. Unstoppable Domains, with the owner wallet of `daimon.blockchain`: set
   `dweb.ipfs.hash` (and `ipfs.html.value`) to the CID; verify in Brave
   with UD resolution enabled, and with the UD extension.
6. Announce the CID, the gateway URLs and how to verify them (this file's
   "How anyone can rebuild and compare"), through the official channels
   only (`docs/REGISTRO_POST.md`); add the mirror to the site's and the
   README's "Official channels"; add the mirror to `SECURITY.md`'s scope.
7. Put the publish date, commit, CID and the gateway URLs in the launch
   record.

## Decisions needed before phase 2

1. **The pinning pair**: Filebase + Pinata as above, or another pair.
2. **The CID form on the name**: CIDv1 if UD's UI accepts it, else CIDv0
   (see above).
3. **WalletConnect on the mirror**: none (as committed), the production id
   with the red warning, or a second project id bound to one stable mirror
   domain the project controls.
4. **Who holds the name**: the owner is DMX's `marketingAddress2`
   (`0x41B5…f395`), outside the guardian Safe and outside the documented
   launch keys. The mirror's name is a security-relevant pointer: whether to
   leave it there, move it to the guardian Safe (a Polygon transfer, signed
   by the current owner) or to a key documented in TEAM_HOLDINGS.md is a
   policy decision, and TEAM_HOLDINGS.md should name the address either way.
5. **A stable mirror domain** (`ipfs.daimon.money` on a dedicated gateway):
   convenient and needed for option 3 above, but a DNS dependency; the
   CID-based URLs remain the censorship-resistant ones.
